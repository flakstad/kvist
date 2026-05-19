;;; odinl-mode.el --- Major mode for OdinL -*- lexical-binding: t; -*-

;; OdinL is a Clojure-shaped syntax that lowers to Odin.  Editing should behave
;; like Clojure editing first, with small OdinL-specific font-lock and
;; indentation adjustments.

(require 'clojure-mode)
(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'xref)

(defgroup odinl nil
  "Editing support for OdinL."
  :group 'languages)

(defcustom odinl-indent-offset 2
  "Indentation offset for OdinL source."
  :type 'integer
  :group 'odinl)

(defcustom odinl-command "odinl"
  "Fallback OdinL executable used when no local checkout binary is found."
  :type 'string
  :group 'odinl)

(defcustom odinl-doc-buffer-name "*OdinL Doc*"
  "Buffer name used for OdinL documentation lookup."
  :type 'string
  :group 'odinl)

(defconst odinl-special-forms
  '("package" "import" "const" "struct" "enum" "union" "proc" "odin"
    "let" "do" "if" "when" "cond" "switch" "set!" "return" "defer"
    "for" "each" "comment" "new" "make" "get" "nil?" "in" "not-in"
    "break" "continue" "with-allocator" "with-temp-allocator"
    "with-delete" "slurp" "spit" "save-json" "load-json" "tap>"
    "->" "->>")
  "OdinL special forms and syntactic heads.")

(defconst odinl-core-helpers
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
  "OdinL helper forms available for basic completion.")

(defconst odinl-completion-builtins
  (append odinl-special-forms odinl-core-helpers)
  "Static OdinL completions.")

(defconst odinl-font-lock-keywords
  `((,(regexp-opt odinl-special-forms 'symbols) . font-lock-keyword-face)
    ("\\_<#[[:alnum:]_][[:alnum:]_-]*\\_>" . font-lock-preprocessor-face)
    ("\\_<\\.[[:alnum:]_][[:alnum:]_?!-]*\\_>" . font-lock-constant-face)
    (":[[:alnum:]_][[:alnum:]_?!-]*" . font-lock-builtin-face))
  "Extra font-lock rules for `odinl-mode'.")

(defun odinl--put-indent (symbol spec)
  "Install OdinL indentation SPEC for SYMBOL."
  (put symbol 'clojure-indent-function spec))

(defun odinl--setup-indentation ()
  "Install OdinL indentation rules on top of `clojure-mode'."
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
    (odinl--put-indent (car entry) (cdr entry))))

(defun odinl--project-root (&optional start)
  "Return a likely OdinL project root for START or the current buffer."
  (let* ((path (cond
                ((bufferp start) (or (buffer-file-name start) default-directory))
                ((stringp start) start)
                ((buffer-file-name) (buffer-file-name))
                (t default-directory)))
         (dir (if (and path (file-directory-p path))
                  path
                (file-name-directory (expand-file-name path)))))
    (or (locate-dominating-file dir "cmd/odinl/main.odin")
        (locate-dominating-file dir "LANGUAGE.md")
        (locate-dominating-file dir ".git")
        dir)))

(defun odinl--executable (&optional start)
  "Return the OdinL executable to use for START."
  (let* ((root (file-name-as-directory (odinl--project-root start)))
         (default-root (file-name-as-directory (odinl--project-root default-directory)))
         (local (expand-file-name "odinl" root))
         (default-local (expand-file-name "odinl" default-root))
         (fallback (executable-find odinl-command)))
    (cond
     ((file-executable-p local) local)
     ((file-executable-p default-local) default-local)
     (fallback fallback)
     (t (error "Could not find odinl executable; run `odin build cmd/odinl'")))))

(defun odinl--source-temp-file ()
  "Write the current OdinL buffer to a temporary .odinl file."
  (unless buffer-file-name
    (user-error "OdinL tooling requires a file-backed buffer"))
  (let* ((dir (file-name-directory (expand-file-name buffer-file-name)))
         (temp (make-temp-file (expand-file-name ".odinl-symbols-" dir) nil ".odinl")))
    (write-region (point-min) (point-max) temp nil 'silent)
    temp))

(defun odinl--call-string (program args)
  "Call PROGRAM with ARGS and return (EXIT-CODE . OUTPUT)."
  (with-temp-buffer
    (let ((exit-code (apply #'call-process program nil t nil args)))
      (cons exit-code (buffer-substring-no-properties (point-min) (point-max))))))

(defun odinl--parse-symbol-line (line file)
  "Parse one `odinl symbols' LINE for FILE."
  (let ((fields (split-string line "\t")))
    (when (>= (length fields) 4)
      (let ((kind (nth 0 fields))
            (name (nth 1 fields))
            (line-text (nth 2 fields))
            (column-text (nth 3 fields))
            (detail (or (nth 4 fields) ""))
            (doc (or (nth 5 fields) "")))
      (list :kind kind
            :name name
            :line (string-to-number line-text)
            :column (string-to-number column-text)
            :detail (or detail "")
              :doc (odinl--unescape-doc doc)
              :file file)))))

(defun odinl--unescape-doc (text)
  "Decode escaped documentation TEXT from `odinl symbols'."
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

(defun odinl--symbols (&optional file)
  "Return current buffer symbols from `odinl symbols'."
  (let* ((source-file (or file buffer-file-name))
         (temp (if file nil (odinl--source-temp-file)))
         (input (or temp source-file))
         (program (odinl--executable source-file)))
    (unwind-protect
        (pcase-let ((`(,exit-code . ,output) (odinl--call-string program (list "symbols" input))))
          (unless (zerop exit-code)
            (user-error "%s" (string-trim output)))
          (let ((lines (cdr (split-string output "\n" t))))
            (delq nil
                  (mapcar (lambda (line)
                            (odinl--parse-symbol-line line source-file))
                          lines))))
      (when temp
        (ignore-errors (delete-file temp))))))

(defun odinl--symbol-bounds ()
  "Return bounds of the OdinL symbol-like token at point."
  (let ((chars "[:alnum:]_?!+*/<>=.-:"))
    (save-excursion
      (skip-chars-backward chars)
      (let ((beg (point)))
        (skip-chars-forward chars)
        (when (< beg (point))
          (cons beg (point)))))))

(defun odinl--identifier-at-point ()
  "Return an OdinL identifier at point."
  (when-let ((bounds (odinl--symbol-bounds)))
    (string-trim
     (buffer-substring-no-properties (car bounds) (cdr bounds))
     "^:" ":$")))

(defun odinl--symbol-matches-identifier-p (symbol identifier)
  "Return non-nil if SYMBOL matches IDENTIFIER."
  (let ((name (plist-get symbol :name)))
    (or (string= name identifier)
        (string-suffix-p (concat "." identifier) name))))

(defun odinl--odin-root ()
  "Return the local Odin root, or nil if it cannot be discovered."
  (pcase-let ((`(,exit-code . ,output) (odinl--call-string "odin" '("root"))))
    (when (zerop exit-code)
      (string-trim output))))

(defun odinl--import-dir (import-path)
  "Return the local directory for Odin IMPORT-PATH."
  (when-let ((root (odinl--odin-root)))
    (cond
     ((string-prefix-p "core:" import-path)
      (expand-file-name (substring import-path 5) (expand-file-name "core" root)))
     ((string-prefix-p "vendor:" import-path)
      (expand-file-name (substring import-path 7) (expand-file-name "vendor" root)))
     (t nil))))

(defun odinl--package-definition-symbols (alias import-path)
  "Return exported-looking symbols for ALIAS from IMPORT-PATH."
  (let ((dir (odinl--import-dir import-path))
        symbols)
    (when (and dir (file-directory-p dir))
      (dolist (file (directory-files-recursively dir "\\.odin\\'"))
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (while (re-search-forward "^[ \t]*\\([[:alnum:]_][[:alnum:]_?!]*\\)[ \t]*::" nil t)
            (push (list :kind "odin"
                        :name (concat alias "." (match-string-no-properties 1))
                        :line (line-number-at-pos (match-beginning 1))
                        :column (1+ (- (match-beginning 1) (line-beginning-position)))
                        :detail import-path
                        :doc (odinl--preceding-odin-doc (match-beginning 0))
                        :file file)
                  symbols)))))
    (nreverse symbols)))

(defun odinl--clean-doc-comment-line (line)
  "Return LINE with a leading line-comment marker removed."
  (setq line (string-trim-left line))
  (cond
   ((string-prefix-p "///" line)
    (string-trim-left (substring line 3)))
   ((string-prefix-p "//" line)
    (string-trim-left (substring line 2)))
   (t line)))

(defun odinl--clean-block-doc-line (line)
  "Return cleaned block-comment documentation LINE."
  (setq line (string-trim line))
  (when (string-prefix-p "*" line)
    (setq line (string-trim-left (substring line 1))))
  line)

(defun odinl--clean-block-doc-comment (text)
  "Return cleaned documentation text from a /* ... */ block."
  (when (string-prefix-p "/*" text)
    (setq text (substring text 2)))
  (when (string-suffix-p "*/" text)
    (setq text (substring text 0 (- (length text) 2))))
  (let ((lines (mapcar #'odinl--clean-block-doc-line
                       (split-string text "\n")))
        result seen-content pending-blank)
    (dolist (line lines)
      (if (string-empty-p line)
          (when seen-content
            (setq pending-blank t))
        (when pending-blank
          (push "" result))
        (push line result)
        (setq seen-content t
              pending-blank nil)))
    (string-join (nreverse result) "\n")))

(defun odinl--preceding-odin-doc (pos)
  "Return contiguous comments immediately preceding POS."
  (save-excursion
    (goto-char pos)
    (beginning-of-line)
    (let (lines done)
      (while (not done)
        (let ((line-end (point)))
          (if (not (= 0 (forward-line -1)))
              (setq done t)
            (let ((line (buffer-substring-no-properties
                         (line-beginning-position)
                         (line-end-position))))
              (cond
               ((string-match-p "\\`[ \t]*//" line)
                (push (odinl--clean-doc-comment-line line) lines)
                (beginning-of-line))
               ((string-match-p "\\*/[ \t]*\\'" line)
                (let ((block-end (line-end-position)))
                  (if (search-backward "/*" nil t)
                      (progn
                        (push (odinl--clean-block-doc-comment
                               (buffer-substring-no-properties (point) block-end))
                              lines)
                        (beginning-of-line))
                    (goto-char line-end)
                    (setq done t))))
               ((string-match-p "\\`[ \t]*\\'" line)
                (goto-char line-end)
                (setq done t))
               (t
                (goto-char line-end)
                (setq done t)))))))
      (string-join lines "\n"))))

(defun odinl--import-symbols ()
  "Return import symbols from the current buffer."
  (seq-filter (lambda (symbol)
                (equal (plist-get symbol :kind) "import"))
              (ignore-errors (odinl--symbols))))

(defun odinl--package-symbols-for-current-buffer ()
  "Return imported Odin package symbols for current buffer imports."
  (apply #'append
         (mapcar (lambda (symbol)
                   (odinl--package-definition-symbols
                    (plist-get symbol :name)
                    (plist-get symbol :detail)))
                 (odinl--import-symbols))))

(defun odinl--package-definitions (identifier)
  "Return package definitions matching alias-qualified IDENTIFIER."
  (when (string-match "\\`\\([^.]\\{1,\\}\\)\\.\\([^.]\\{1,\\}\\)\\'" identifier)
    (let ((alias (match-string 1 identifier)))
      (seq-filter (lambda (symbol)
                    (and (string-prefix-p (concat alias ".") (plist-get symbol :name))
                         (string= (plist-get symbol :name) identifier)))
                  (odinl--package-symbols-for-current-buffer)))))

(defun odinl--xref-backend () 'odinl)

(cl-defmethod xref-backend-identifier-at-point ((_backend (eql odinl)))
  (odinl--identifier-at-point))

(cl-defmethod xref-backend-definitions ((_backend (eql odinl)) identifier)
  (let* ((symbols (append (odinl--symbols)
                          (odinl--package-definitions identifier)))
         (matches (seq-filter (lambda (symbol)
                                (odinl--symbol-matches-identifier-p symbol identifier))
                              symbols)))
    (mapcar
     (lambda (symbol)
       (let ((file (or (plist-get symbol :file) (buffer-file-name)))
             (line (plist-get symbol :line))
             (column (max 0 (1- (plist-get symbol :column)))))
         (xref-make
          (format "%s %s" (plist-get symbol :kind) (plist-get symbol :name))
          (xref-make-file-location file line column))))
     matches)))

(defun odinl--completion-bounds ()
  "Return completion bounds for OdinL symbols."
  (odinl--symbol-bounds))

(defun odinl--completion-candidates ()
  "Return simple OdinL completion candidates."
  (delete-dups
   (append odinl-completion-builtins
           (mapcar (lambda (symbol) (plist-get symbol :name))
                   (ignore-errors (append (odinl--symbols)
                                          (odinl--package-symbols-for-current-buffer)))))))

(defun odinl--symbol-doc-candidates (identifier)
  "Return documentation candidates for IDENTIFIER."
  (let* ((symbols (append (ignore-errors (odinl--symbols))
                          (ignore-errors (odinl--package-definitions identifier))))
         (matches (seq-filter (lambda (symbol)
                                (odinl--symbol-matches-identifier-p symbol identifier))
                              symbols)))
    (seq-filter (lambda (symbol)
                  (not (string-empty-p (or (plist-get symbol :doc) ""))))
                matches)))

(defun odinl--show-doc (symbol)
  "Show documentation for SYMBOL."
  (let ((buffer (get-buffer-create odinl-doc-buffer-name))
        (name (plist-get symbol :name))
        (kind (plist-get symbol :kind))
        (detail (plist-get symbol :detail))
        (doc (plist-get symbol :doc))
        (file (plist-get symbol :file))
        (line (plist-get symbol :line)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "%s %s\n" kind name))
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

;;;###autoload
(defun odinl-doc-at-point ()
  "Show documentation for the OdinL or imported Odin symbol at point."
  (interactive)
  (let* ((identifier (or (odinl--identifier-at-point)
                         (user-error "No symbol at point")))
         (matches (odinl--symbol-doc-candidates identifier)))
    (cond
     ((null matches)
      (user-error "No docs found for %s" identifier))
     ((= (length matches) 1)
      (odinl--show-doc (car matches)))
     (t
      (let* ((names (mapcar (lambda (symbol)
                              (format "%s %s" (plist-get symbol :kind) (plist-get symbol :name)))
                            matches))
             (choice (completing-read "Doc: " names nil t)))
        (odinl--show-doc (nth (cl-position choice names :test #'equal) matches)))))))

(defun odinl-completion-at-point ()
  "Complete OdinL special forms and symbols in the current file."
  (when-let ((bounds (odinl--completion-bounds)))
    (list (car bounds)
          (cdr bounds)
          (odinl--completion-candidates)
          :exclusive 'no)))

;;;###autoload
(define-derived-mode odinl-mode clojure-mode "OdinL"
  "Major mode for editing OdinL source files."
  (setq-local clojure-indent-style 'align-arguments)
  (setq-local clojure-align-forms-automatically nil)
  (setq-local lisp-body-indent odinl-indent-offset)
  (setq-local indent-tabs-mode nil)
  (add-hook 'xref-backend-functions #'odinl--xref-backend nil t)
  (add-hook 'completion-at-point-functions #'odinl-completion-at-point nil t)
  (font-lock-add-keywords nil odinl-font-lock-keywords)
  (odinl--setup-indentation))

(define-key odinl-mode-map (kbd "M-.") #'xref-find-definitions)
(define-key odinl-mode-map (kbd "C-c C-.") #'odinl-doc-at-point)

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.odinl\\'" . odinl-mode))

(provide 'odinl-mode)

;;; odinl-mode.el ends here
