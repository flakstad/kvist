;;; kvist-mode.el --- Major mode for Kvist -*- lexical-binding: t; -*-

;; Kvist is a Clojure-shaped syntax that lowers to Odin.  Editing should behave
;; like Clojure editing first, with small Kvist-specific font-lock and
;; indentation adjustments.

(require 'clojure-mode)
(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'xref)

(defgroup kvist nil
  "Editing support for Kvist."
  :group 'languages)

(defcustom kvist-indent-offset 2
  "Indentation offset for Kvist source."
  :type 'integer
  :group 'kvist)

(defcustom kvist-command "kvist"
  "Fallback Kvist executable used when no local checkout binary is found."
  :type 'string
  :group 'kvist)

(defcustom kvist-doc-buffer-name "*Kvist Doc*"
  "Buffer name used for Kvist documentation lookup."
  :type 'string
  :group 'kvist)

(defcustom kvist-doc-keybinding (kbd "C-c d")
  "Preferred key binding for Kvist docs at point."
  :type 'sexp
  :group 'kvist)

(defconst kvist-special-forms
  '("package" "import" "const" "struct" "enum" "union" "proc" "odin"
    "let" "do" "if" "when" "cond" "switch" "set!" "return" "defer"
    "for" "each" "comment" "new" "make" "get" "nil?" "in" "not-in"
    "type" "update" "update!"
    "break" "continue" "with-allocator" "with-temp-allocator"
    "with-delete" "when-let" "if-let" "when-ok" "if-ok"
    "slurp" "spit" "tap>"
    "->" "->>")
  "Kvist special forms and syntactic heads.")

(defconst kvist-core-helpers
  '("map" "filter" "remove" "reduce" "map-indexed" "keep" "mapcat"
    "concat" "merge" "merge!" "into" "into!" "interpose" "interleave"
    "reverse" "reverse!" "shuffle" "shuffle!" "sort" "sort!" "sort-by"
    "sort-by!" "map!" "map-indexed!" "filter!" "remove!" "keep!"
    "split-at" "partition" "partition-all" "partition-by" "zipmap"
    "index-by" "group-by" "frequencies" "keys" "vals" "distinct"
    "distinct-by" "range" "repeat" "repeatedly" "iterate" "cycle"
    "take" "drop" "butlast" "drop-last" "take-nth" "take-while"
    "drop-while" "find" "some?" "every?" "first" "second" "last"
    "nth" "rest" "empty?" "count" "contains?")
  "Kvist helper forms available for basic completion.")

(defconst kvist-completion-builtins
  (append kvist-special-forms kvist-core-helpers)
  "Static Kvist completions.")

(defconst kvist--kvist-canonical-imports
  '(("arr" . "kvist:arr")
    ("str" . "kvist:str")
    ("map" . "kvist:map")
    ("set" . "kvist:set")
    ("struct" . "kvist:struct"))
  "Canonical explicit imports for compiler-provided Kvist packages.")

(defvar-local kvist--editor-symbol-cache nil
  "Cached full file-context symbol metadata for the current buffer.")

(defun kvist--inside-string-on-line-p (pos)
  "Return non-nil if POS is inside a simple string on its current line."
  (save-excursion
    (goto-char pos)
    (let ((line-start (line-beginning-position))
          (in-string nil)
          (escaped nil))
      (goto-char line-start)
      (while (< (point) pos)
        (let ((ch (char-after)))
          (cond
           (escaped
            (setq escaped nil))
           ((= ch ?\\)
            (setq escaped t))
           ((= ch ?\")
            (setq in-string (not in-string)))))
        (forward-char 1))
      in-string)))

(defun kvist--match-line-comment (limit)
  "Search for an Odin `//' comment before LIMIT."
  (let (match)
    (while (and (not match) (search-forward "//" limit t))
      (let ((beg (match-beginning 0)))
        (unless (kvist--inside-string-on-line-p beg)
          (let ((end (min (line-beginning-position 2) limit)))
            (set-match-data (list beg end))
            (put-text-property beg end 'face 'font-lock-comment-face)
            (put-text-property beg end 'font-lock-face 'font-lock-comment-face)
            (goto-char end)
            (setq match t)))))
    (unless match
      (goto-char limit))
    match))

(defun kvist--match-block-comment (limit)
  "Search for an Odin `/* */' comment before LIMIT."
  (let (match)
    (while (and (not match) (search-forward "/*" limit t))
      (let ((beg (match-beginning 0)))
        (unless (kvist--inside-string-on-line-p beg)
          (let ((end (if (search-forward "*/" limit t)
                         (point)
                       limit)))
            (set-match-data (list beg end))
            (add-text-properties beg end '(font-lock-multiline t))
            (put-text-property beg end 'face 'font-lock-comment-face)
            (put-text-property beg end 'font-lock-face 'font-lock-comment-face)
            (goto-char end)
            (setq match t)))))
    (unless match
      (goto-char limit))
    match))

(defconst kvist-font-lock-keywords
  `((kvist--match-line-comment (0 font-lock-comment-face override))
    (kvist--match-block-comment (0 font-lock-comment-face override))
    (,(regexp-opt kvist-special-forms 'symbols) . font-lock-keyword-face)
    ("\\_<#[[:alnum:]_][[:alnum:]_-]*\\_>" . font-lock-preprocessor-face)
    ("\\_<\\.[[:alnum:]_][[:alnum:]_?!-]*\\_>" . font-lock-constant-face)
    (":[[:alnum:]_][[:alnum:]_?!-]*" . font-lock-builtin-face))
  "Extra font-lock rules for `kvist-mode'.")

(defun kvist--make-syntax-table ()
  "Return a fresh syntax table for `kvist-mode'."
  (let ((table (copy-syntax-table clojure-mode-syntax-table)))
    ;; Keep Clojure/Lisp comments, and also recognize Odin comments.
    (modify-syntax-entry ?\; "< b" table)
    (modify-syntax-entry ?/ ". 124b" table)
    (modify-syntax-entry ?* ". 23" table)
    (modify-syntax-entry ?\n "> b" table)
    table))

(defvar kvist-mode-syntax-table (kvist--make-syntax-table)
  "Syntax table for `kvist-mode'.")

(setq kvist-mode-syntax-table (kvist--make-syntax-table))

(defun kvist--put-indent (symbol spec)
  "Install Kvist indentation SPEC for SYMBOL."
  (put symbol 'clojure-indent-function spec))

(defun kvist--setup-indentation ()
  "Install Kvist indentation rules on top of `clojure-mode'."
  (dolist (entry '((package . 1)
                   (import . 1)
                   (const . 2)
                   (struct . 1)
                   (enum . 1)
                   (union . 1)
                   (proc . 2)
                   (odin . 1)
                   (let . 1)
                   (do . 0)
                   (if . 1)
                   (when . 1)
                   (cond . 0)
                   (switch . 1)
                   (set! . 1)
                   (return . 0)
                   (defer . 0)
                   (for . 1)
                   (each . 2)
                   (comment . 0)
                   (with-allocator . 1)
                   (with-temp-allocator . 1)
                   (with-delete . 1)
                   (new . 1)
                   (make . 1)))
    (kvist--put-indent (car entry) (cdr entry))))

(defun kvist--project-root (&optional start)
  "Return a likely Kvist project root for START or the current buffer."
  (let* ((path (cond
                ((bufferp start) (or (buffer-file-name start) default-directory))
                ((stringp start) start)
                ((buffer-file-name) (buffer-file-name))
                (t default-directory)))
         (dir (if (and path (file-directory-p path))
                  path
                (file-name-directory (expand-file-name path)))))
    (or (locate-dominating-file dir "cmd/kvist/main.odin")
        (locate-dominating-file dir "LANGUAGE.md")
        (locate-dominating-file dir ".git")
        dir)))

(defun kvist--executable (&optional start)
  "Return the Kvist executable to use for START."
  (let* ((root (file-name-as-directory (kvist--project-root start)))
         (default-root (file-name-as-directory (kvist--project-root default-directory)))
         (local (expand-file-name "kvist" root))
         (default-local (expand-file-name "kvist" default-root))
         (fallback (executable-find kvist-command)))
    (cond
     ((file-executable-p local) local)
     ((file-executable-p default-local) default-local)
     (fallback fallback)
     (t (error "Could not find kvist executable; run `odin build cmd/kvist'")))))

(defun kvist--source-temp-file ()
  "Write the current Kvist buffer to a temporary .kvist file."
  (unless buffer-file-name
    (user-error "Kvist tooling requires a file-backed buffer"))
  (let* ((dir (file-name-directory (expand-file-name buffer-file-name)))
         (temp (make-temp-file (expand-file-name ".kvist-symbols-" dir) nil ".kvist")))
    (write-region (point-min) (point-max) temp nil 'silent)
    temp))

(defun kvist--call-string (program args)
  "Call PROGRAM with ARGS and return (EXIT-CODE . OUTPUT)."
  (with-temp-buffer
    (let ((exit-code (apply #'call-process program nil t nil args)))
      (cons exit-code (buffer-substring-no-properties (point-min) (point-max))))))

(defun kvist--parse-symbol-line (line file)
  "Parse one `kvist symbols' LINE for FILE."
  (let ((fields (split-string line "\t")))
    (when (>= (length fields) 4)
      (let ((kind (nth 0 fields))
            (name (nth 1 fields))
            (line-text (nth 2 fields))
            (column-text (nth 3 fields))
            (detail (or (nth 4 fields) ""))
            (signature (or (nth 5 fields) ""))
            (doc (or (nth 6 fields) ""))
            (file-text (or (nth 7 fields) "")))
      (list :kind kind
            :name name
            :line (string-to-number line-text)
            :column (string-to-number column-text)
            :detail (or detail "")
            :signature (and signature (not (string-empty-p signature)) signature)
            :doc (kvist--unescape-doc doc)
            :file (if (string-empty-p file-text) file file-text))))))

(defun kvist--unescape-doc (text)
  "Decode escaped documentation TEXT from `kvist symbols'."
  (let ((i 0)
        (out ""))
    (while (< i (length text))
      (let ((ch (aref text i)))
        (if (and (= ch ?\\) (< (1+ i) (length text)))
            (let ((next (aref text (1+ i))))
              (setq out
                    (concat out
                            (pcase next
                              (?n "\n")
                              (?t "\t")
                              (?r "\r")
                              (?\\ "\\")
                              (_ (char-to-string next)))))
              (setq i (+ i 2)))
          (setq out (concat out (char-to-string ch)))
          (setq i (1+ i)))))
    out))

(defun kvist--symbols (&optional file)
  "Return current buffer symbols from `kvist symbols'."
  (let* ((source-file (or file buffer-file-name))
         (temp (if file nil (kvist--source-temp-file)))
         (input (or temp source-file))
         (program (kvist--executable source-file)))
    (unwind-protect
        (pcase-let ((`(,exit-code . ,output) (kvist--call-string program (list "symbols" input))))
          (unless (zerop exit-code)
            (user-error "%s" (string-trim output)))
          (let ((lines (cdr (split-string output "\n" t))))
            (delq nil
                  (mapcar (lambda (line)
                            (kvist--parse-symbol-line line source-file))
                          lines))))
      (when temp
        (ignore-errors (delete-file temp))))))

(defun kvist--editor-symbols (&optional file)
  "Return full file-context symbols from `kvist editor-symbols'."
  (let* ((source-file (or file buffer-file-name))
         (tick (and (null file) (buffer-chars-modified-tick))))
    (if (and (null file)
             kvist--editor-symbol-cache
             (equal (plist-get kvist--editor-symbol-cache :file) source-file)
             (equal (plist-get kvist--editor-symbol-cache :tick) tick))
        (plist-get kvist--editor-symbol-cache :symbols)
      (let* ((temp (if file nil (kvist--source-temp-file)))
             (input (or temp source-file))
             (program (kvist--executable source-file))
             (symbols
              (unwind-protect
                  (pcase-let ((`(,exit-code . ,output)
                                (kvist--call-string program (list "editor-symbols" input))))
                    (unless (zerop exit-code)
                      (user-error "%s" (string-trim output)))
                    (let ((lines (cdr (split-string output "\n" t))))
                      (delq nil
                            (mapcar (lambda (line)
                                      (kvist--parse-symbol-line line source-file))
                                    lines))))
                (when temp
                  (ignore-errors (delete-file temp))))))
        (when (null file)
          (setq kvist--editor-symbol-cache
                (list :file source-file :tick tick :symbols symbols)))
        symbols))))

(defun kvist--lookup-symbols (identifier &optional file)
  "Return matching file-context symbols for IDENTIFIER via the CLI."
  (let* ((source-file (or file buffer-file-name))
         (temp (if file nil (kvist--source-temp-file)))
         (input (or temp source-file))
         (program (kvist--executable source-file)))
    (unwind-protect
        (pcase-let ((`(,exit-code . ,output)
                      (kvist--call-string program (list "editor-symbols" input identifier))))
          (unless (zerop exit-code)
            (user-error "%s" (string-trim output)))
          (let ((lines (cdr (split-string output "\n" t))))
            (delq nil
                  (mapcar (lambda (line)
                            (kvist--parse-symbol-line line source-file))
                          lines))))
      (when temp
        (ignore-errors (delete-file temp))))))

(defun kvist--doc-text (identifier &optional file)
  "Return rendered documentation text for IDENTIFIER via the CLI."
  (let* ((source-file (or file buffer-file-name))
         (temp (if file nil (kvist--source-temp-file)))
         (input (or temp source-file))
         (program (kvist--executable source-file)))
    (unwind-protect
        (pcase-let ((`(,exit-code . ,output)
                      (kvist--call-string program (list "doc" input identifier))))
          (unless (zerop exit-code)
            (user-error "%s" (string-trim output)))
          output)
      (when temp
        (ignore-errors (delete-file temp))))))

(defun kvist--xref-symbols (identifier &optional file)
  "Return xref symbols for IDENTIFIER via the CLI."
  (let* ((source-file (or file buffer-file-name))
         (temp (if file nil (kvist--source-temp-file)))
         (input (or temp source-file))
         (program (kvist--executable source-file)))
    (unwind-protect
        (pcase-let ((`(,exit-code . ,output)
                      (kvist--call-string program (list "xref" input identifier))))
          (unless (zerop exit-code)
            (user-error "%s" (string-trim output)))
          (let (symbols)
            (dolist (line (split-string output "\n" t))
              (when (string-match
                     "\\`\\(.*\\):\\([0-9]+\\):\\([0-9]+\\)\t\\([^\t]+\\)\t\\(.+\\)\\'" line)
                (push (list :file (match-string 1 line)
                            :line (string-to-number (match-string 2 line))
                            :column (string-to-number (match-string 3 line))
                            :kind (match-string 4 line)
                            :name (match-string 5 line))
                      symbols)))
            (nreverse symbols)))
      (when temp
        (ignore-errors (delete-file temp))))))

(defun kvist--complete-symbols (&optional prefix file)
  "Return completion symbols for PREFIX via the CLI."
  (let* ((source-file (or file buffer-file-name))
         (temp (if file nil (kvist--source-temp-file)))
         (input (or temp source-file))
         (program (kvist--executable source-file)))
    (unwind-protect
        (pcase-let ((`(,exit-code . ,output)
                      (kvist--call-string
                       program
                       (append (list "complete" input)
                               (when prefix (list prefix))))))
          (unless (zerop exit-code)
            (user-error "%s" (string-trim output)))
          (let ((lines (cdr (split-string output "\n" t))))
            (delq nil
                  (mapcar (lambda (line)
                            (kvist--parse-symbol-line line source-file))
                          lines))))
      (when temp
        (ignore-errors (delete-file temp))))))

(defun kvist--symbol-bounds ()
  "Return bounds of the Kvist symbol-like token at point."
  (let ((chars "-[:alnum:]_?!+*/<>=.:"))
    (save-excursion
      (skip-chars-backward chars)
      (let ((beg (point)))
        (skip-chars-forward chars)
        (when (< beg (point))
          (cons beg (point)))))))

(defun kvist--normalize-qualified-identifier (identifier)
  "Normalize IDENTIFIER so `pkg/sym' and `pkg.sym' compare consistently."
  (if (string-match "\\`\\([^./]+\\)\\([./]\\)\\(.+\\)\\'" identifier)
      (concat (match-string 1 identifier) "/" (match-string 3 identifier))
    identifier))

(defun kvist--identifier-at-point ()
  "Return a Kvist identifier at point."
  (when-let ((bounds (kvist--symbol-bounds)))
    (kvist--normalize-qualified-identifier
     (string-trim
      (buffer-substring-no-properties (car bounds) (cdr bounds))
      "^:" ":$"))))

(defun kvist--symbol-matches-identifier-p (symbol identifier)
  "Return non-nil if SYMBOL matches IDENTIFIER."
  (let* ((name (kvist--normalize-qualified-identifier (plist-get symbol :name)))
         (identifier (kvist--normalize-qualified-identifier identifier)))
    (or (string= name identifier)
        (string-suffix-p (concat "." identifier) name)
        (string-suffix-p (concat "/" identifier) name))))

(defun kvist--dedupe-symbols-by-name (symbols)
  "Deduplicate SYMBOLS by their :name field, preserving first occurrence."
  (let ((seen (make-hash-table :test #'equal))
        out)
    (dolist (symbol symbols)
      (let ((name (plist-get symbol :name)))
        (unless (gethash name seen)
          (puthash name t seen)
          (push symbol out))))
    (nreverse out)))

(defun kvist--import-present-p (alias path)
  "Return non-nil when current buffer already imports ALIAS from PATH."
  (save-excursion
    (goto-char (point-min))
    (let ((quoted-path (regexp-quote path))
          (quoted-alias (regexp-quote alias)))
      (or (re-search-forward
           (format "^[[:space:]]*(import[[:space:]]+%s[[:space:]]+\"%s\")[[:space:]]*$"
                   quoted-alias quoted-path)
           nil t)
          (re-search-forward
           (format "^[[:space:]]*(import[[:space:]]+\"%s\")[[:space:]]*$"
                   quoted-path)
           nil t)))))

(defun kvist--import-insertion-point ()
  "Return buffer position where a new top-level import should be inserted."
  (save-excursion
    (goto-char (point-min))
    (let ((last-import-end nil)
          (package-end nil))
      (while (re-search-forward "^[[:space:]]*(\\(package\\|import\\)\\_>" nil t)
        (beginning-of-line)
        (let ((head (match-string 1)))
          (condition-case nil
              (let ((end (save-excursion
                           (forward-sexp 1)
                           (point))))
                (if (string= head "package")
                    (setq package-end end)
                  (setq last-import-end end))
                (goto-char end))
            (error
             (goto-char (line-end-position))))))
      (or last-import-end package-end (point-min)))))

(defun kvist--ensure-kvist-package-import (alias)
  "Ensure current buffer imports the canonical Kvist package ALIAS."
  (when-let ((path (cdr (assoc alias kvist--kvist-canonical-imports))))
    (unless (kvist--import-present-p alias path)
      (save-excursion
        (goto-char (kvist--import-insertion-point))
        (unless (bolp)
          (insert "\n"))
        (insert (format "(import %s \"%s\")\n" alias path))
        (unless (looking-at-p "\n")
          (insert "\n"))))))

(defun kvist--maybe-auto-import-qualified-symbol (&optional identifier)
  "Insert a canonical Kvist package import for IDENTIFIER when appropriate."
  (let* ((identifier (or identifier (kvist--identifier-at-point)))
         (normalized (and identifier (kvist--normalize-qualified-identifier identifier))))
    (when (and normalized
               (string-match "\\`\\([^/]+\\)/" normalized))
      (kvist--ensure-kvist-package-import (match-string 1 normalized)))))

(defun kvist--xref-backend () 'kvist)

(cl-defmethod xref-backend-identifier-at-point ((_backend (eql kvist)))
  (kvist--identifier-at-point))

(cl-defmethod xref-backend-definitions ((_backend (eql kvist)) identifier)
  (let* ((matches (or (ignore-errors (kvist--xref-symbols identifier))
                      (ignore-errors (kvist--lookup-symbols identifier))
                      (let* ((editor-symbols (ignore-errors (kvist--editor-symbols)))
                             (editor-matches (seq-filter (lambda (symbol)
                                                           (kvist--symbol-matches-identifier-p symbol identifier))
                                                         editor-symbols)))
                        editor-matches))))
    (mapcar
     (lambda (symbol)
       (let ((file (or (plist-get symbol :file) (buffer-file-name)))
             (line (plist-get symbol :line))
             (column (max 0 (1- (plist-get symbol :column)))))
         (xref-make
          (format "%s %s" (plist-get symbol :kind) (plist-get symbol :name))
          (xref-make-file-location file line column))))
     matches)))

(defun kvist--completion-bounds ()
  "Return completion bounds for Kvist symbols."
  (kvist--symbol-bounds))

(defun kvist--package-prefix (identifier)
  "Return (ALIAS . SEP) when IDENTIFIER starts a qualified package symbol."
  (when (and identifier
             (string-match "\\`\\([^./]+\\)\\([./]\\)\\([^./]*\\)\\'" identifier))
    (cons (match-string 1 identifier) (match-string 2 identifier))))

(defun kvist--completion-symbols (&optional identifier)
  "Return completion symbols for IDENTIFIER context."
  (or (ignore-errors (kvist--complete-symbols identifier))
      (ignore-errors (kvist--editor-symbols))))

(defun kvist--completion-candidates ()
  "Return completion candidates appropriate for the symbol at point."
  (let* ((identifier (kvist--identifier-at-point))
         (package-prefix (kvist--package-prefix identifier))
         (symbols (kvist--completion-symbols identifier)))
    (delete-dups
     (mapcar
      (lambda (symbol)
        (let ((name (plist-get symbol :name)))
          (if (and package-prefix
                   (string= (cdr package-prefix) "."))
              (replace-regexp-in-string "/" "." name t t)
            (replace-regexp-in-string "\\." "/" name t t))))
      symbols))))

(defun kvist--completion-exit (completed status)
  "Handle completion of COMPLETED with STATUS."
  (when (eq status 'finished)
    (kvist--maybe-auto-import-qualified-symbol completed)))

(defun kvist--completion-metadata (identifier)
  "Return symbol metadata alist keyed by display name for IDENTIFIER context."
  (let* ((identifier (or identifier (kvist--identifier-at-point)))
         (package-prefix (kvist--package-prefix identifier))
         (symbols (or (kvist--completion-symbols identifier)
                      (ignore-errors (kvist--symbols))
                      (ignore-errors (kvist--editor-symbols)))))
    (let (table)
      (dolist (symbol symbols)
        (let* ((name (plist-get symbol :name))
               (normalized (kvist--normalize-qualified-identifier name))
               (display (if (and package-prefix
                                 (string= (cdr package-prefix) "."))
                            (replace-regexp-in-string "/" "." name t t)
                          (replace-regexp-in-string "\\." "/" name t t))))
          (unless (assoc display table)
            (push (cons display (or (plist-get symbol :signature) normalized)) table))))
      table)))

(defun kvist--completion-annotation (metadata)
  "Return annotation function using completion METADATA."
  (lambda (candidate)
    (when-let ((entry (assoc candidate metadata)))
      (format "  %s" (cdr entry)))))

(defun kvist--completion-table (candidates metadata)
  "Return a completion table for CANDIDATES with completion METADATA."
  (lambda (string pred action)
    (if (eq action 'metadata)
        `(metadata (annotation-function . ,(kvist--completion-annotation metadata)))
      (complete-with-action action candidates string pred))))

(defun kvist--symbol-doc-candidates (identifier)
  "Return documentation candidates for IDENTIFIER."
  (let* ((matches (or (ignore-errors (kvist--lookup-symbols identifier))
                      (let* ((symbols (ignore-errors (kvist--editor-symbols))))
                        (seq-filter (lambda (symbol)
                                      (kvist--symbol-matches-identifier-p symbol identifier))
                                    symbols)))))
    (seq-filter (lambda (symbol)
                  (or (not (string-empty-p (or (plist-get symbol :doc) "")))
                      (not (string-empty-p (or (plist-get symbol :signature) "")))))
                matches)))

(defun kvist--show-doc-text (text)
  "Show documentation buffer TEXT."
  (let ((buffer (get-buffer-create kvist-doc-buffer-name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text)
        (unless (bolp)
          (insert "\n"))
        (goto-char (point-min))
        (special-mode)))
    (display-buffer buffer)))

(defun kvist--show-doc (symbol)
  "Show documentation for SYMBOL."
  (let ((buffer (get-buffer-create kvist-doc-buffer-name))
        (name (plist-get symbol :name))
        (kind (plist-get symbol :kind))
        (signature (plist-get symbol :signature))
        (detail (plist-get symbol :detail))
        (doc (plist-get symbol :doc))
        (file (plist-get symbol :file))
        (line (plist-get symbol :line)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "%s %s\n" kind name))
        (when (and signature (not (string-empty-p signature)))
          (insert (format "%s\n" signature)))
        (when (and detail (not (string-empty-p detail)))
          (insert (format "%s\n" detail)))
        (when file
          (insert (format "%s:%s\n" file line)))
        (insert "\n")
        (insert doc)
        (insert "\n")
        (goto-char (point-min))
        (special-mode)))
    (display-buffer buffer)))

(defun kvist--eldoc-string (symbol)
  "Return a one-line Eldoc string for SYMBOL."
  (let* ((name (plist-get symbol :name))
         (signature (or (plist-get symbol :signature) name))
         (doc (string-trim (or (plist-get symbol :doc) "")))
         (doc-line (car (split-string doc "\n" t))))
    (if (and doc-line (not (string-empty-p doc-line)))
        (format "%s -- %s" signature doc-line)
      signature)))

(defun kvist--eldoc-from-completion-prefix (identifier)
  "Return Eldoc text from a unique completion match for IDENTIFIER."
  (let* ((symbols (kvist--completion-symbols identifier))
         (metadata (kvist--completion-metadata identifier))
         (package-prefix (kvist--package-prefix identifier))
         (candidates
          (delete-dups
           (mapcar
            (lambda (symbol)
              (let ((name (plist-get symbol :name)))
                (if (and package-prefix
                         (string= (cdr package-prefix) "."))
                    (replace-regexp-in-string "/" "." name t t)
                  (replace-regexp-in-string "\\." "/" name t t))))
            symbols))))
    (when (= (length candidates) 1)
      (when-let ((entry (assoc (car candidates) metadata)))
        (cdr entry)))))

(defun kvist-eldoc-function (&rest _ignored)
  "Return Eldoc text for the Kvist symbol at point."
  (when-let ((identifier (kvist--identifier-at-point)))
    (if-let ((matches (kvist--symbol-doc-candidates identifier)))
        (let* ((normalized (kvist--normalize-qualified-identifier identifier))
               (exact (seq-find (lambda (symbol)
                                  (string=
                                   (kvist--normalize-qualified-identifier
                                    (plist-get symbol :name))
                                   normalized))
                                matches))
               (symbol (or exact (car matches))))
          (kvist--eldoc-string symbol))
      (kvist--eldoc-from-completion-prefix identifier))))

;;;###autoload
(defun kvist-doc-at-point ()
  "Show documentation for the Kvist or imported Odin symbol at point."
  (interactive)
  (let ((identifier (or (kvist--identifier-at-point)
                        (user-error "No symbol at point"))))
    (if-let ((text (ignore-errors (kvist--doc-text identifier))))
        (kvist--show-doc-text text)
      (let ((matches (kvist--symbol-doc-candidates identifier)))
        (cond
         ((null matches)
          (user-error "No docs found for %s" identifier))
         ((= (length matches) 1)
          (kvist--show-doc (car matches)))
         (t
          (let* ((names (mapcar (lambda (symbol)
                                  (format "%s %s" (plist-get symbol :kind) (plist-get symbol :name)))
                                matches))
                 (choice (completing-read "Doc: " names nil t)))
            (kvist--show-doc (nth (cl-position choice names :test #'equal) matches)))))))))

(defun kvist-completion-at-point ()
  "Complete Kvist special forms and symbols in the current file."
  (when-let ((bounds (kvist--completion-bounds)))
    (let ((metadata (kvist--completion-metadata (kvist--identifier-at-point))))
      (list (car bounds)
            (cdr bounds)
            (kvist--completion-table
             (kvist--completion-candidates)
             metadata)
            :exit-function #'kvist--completion-exit
            :exclusive 'no))))

(defun kvist--post-self-insert-auto-import ()
  "Auto-import canonical Kvist packages after typing a qualified prefix."
  (when (and (memq last-command-event '(?/ ?.))
             (not (nth 3 (syntax-ppss)))
             (not (nth 4 (syntax-ppss))))
    (kvist--maybe-auto-import-qualified-symbol)))

;;;###autoload
(define-derived-mode kvist-mode clojure-mode "Kvist"
  "Major mode for editing Kvist source files."
  :syntax-table kvist-mode-syntax-table
  (set-syntax-table kvist-mode-syntax-table)
  (setq-local clojure-indent-style 'align-arguments)
  (setq-local clojure-align-forms-automatically nil)
  (setq-local lisp-body-indent kvist-indent-offset)
  (setq-local indent-tabs-mode nil)
  (setq-local comment-start ";;")
  (setq-local comment-start-skip
              "\\(\\(^\\|[^\\\\\n]\\)\\(\\\\\\\\\\)*\\)\\(;+\\|//+\\|/\\*+\\|#|\\) *")
  (add-hook 'xref-backend-functions #'kvist--xref-backend nil t)
  (add-hook 'completion-at-point-functions #'kvist-completion-at-point nil t)
  (add-hook 'eldoc-documentation-functions #'kvist-eldoc-function nil t)
  (add-hook 'post-self-insert-hook #'kvist--post-self-insert-auto-import nil t)
  (font-lock-add-keywords nil kvist-font-lock-keywords)
  (kvist--setup-indentation))

(define-key kvist-mode-map (kbd "M-.") #'xref-find-definitions)
(define-key kvist-mode-map (kbd "C-c C-.") #'kvist-doc-at-point)
(define-key kvist-mode-map (kbd "C-c C-d") #'kvist-doc-at-point)
(define-key kvist-mode-map kvist-doc-keybinding #'kvist-doc-at-point)

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.kvist\\'" . kvist-mode))

(provide 'kvist-mode)

;;; kvist-mode.el ends here
