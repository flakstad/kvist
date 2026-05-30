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

(defconst kvist--builtin-doc-map
  '(("when-let" . ("kvist macro" "(when-let [value bool expr] body...)"
                   "Bind a value and explicit boolean result from a multi-return expression. Run the body only when the boolean is true. Expands to a destructuring let plus when."))
    ("if-let" . ("kvist macro" "(if-let [value bool expr] then else)"
                 "Bind a value and explicit boolean result from a multi-return expression. Evaluate the then branch when the boolean is true, otherwise the else branch. Expands to a destructuring let plus if."))
    ("when-ok" . ("kvist macro" "(when-ok [value err expr] body...)"
                  "Bind a value and Odin error result from a multi-return expression. Run the body only when the error equals Odin's zero value {}. Expands to a destructuring let plus when."))
    ("if-ok" . ("kvist macro" "(if-ok [value err expr] then else)"
                "Bind a value and Odin error result from a multi-return expression. Evaluate the then branch when the error equals Odin's zero value {}, otherwise the else branch. Expands to a destructuring let plus if."))
    ("println" . ("kvist core" "(println value...)"
                  "Print one or more values. Kvist lowers this to fmt output and auto-imports core:fmt when needed."))
    ("doc" . ("kvist core" "(doc 'symbol)"
              "Print the stored docstring for a declaration name."))
    ("update!" . ("kvist form" "(update! target key-or-field value-or-updater ...)"
                  "Mutate a struct field, array/slice slot, or map key in place. Supports replacement and updater forms such as inc or +."))
    ("update" . ("kvist form" "(update target key-or-field value-or-updater ...)"
                 "Return an updated copy. Currently supported for struct fields."))
    ("type" . ("kvist form" "(type Head Arg...)"
               "Instantiate an Odin polymorphic type constructor. For example, (type chan.Chan int) lowers to chan.Chan(int) in both type and value positions.")))
  "Static documentation for compiler-defined Kvist forms.")

(defconst kvist--kvist-package-member-map
  '(("kvist:arr"
     ("count" . ("src/kvist/emit.odin" "if head.text == \"arr/count\" || head.text == \"str/count\"" "kvist package" "(arr/count xs)"
                 "Count elements in an array, fixed array, or slice."))
     ("empty" . ("src/kvist/emit.odin" "if head.text == \"arr/empty\"" "kvist package" "(arr/empty T [capacity])"
                 "Construct an empty dynamic array, optionally with capacity."))
     ("dynamic" . ("src/kvist/emit.odin" "if head.text == \"arr/dynamic\"" "kvist package" "(arr/dynamic T [v1 v2 ...])"
                   "Construct a dynamic array from a vector literal."))
     ("fixed" . ("src/kvist/emit.odin" "if head.text == \"arr/fixed\"" "kvist package" "(arr/fixed T [v1 v2 ...])"
                 "Construct a fixed array from a vector literal."))
     ("get" . ("src/kvist/emit.odin" "if head.text == \"arr/get\" || head.text == \"str/get\" || head.text == \"map/get\"" "kvist package" "(arr/get xs index)"
               "Index into an array-family value."))
     ("slice" . ("src/kvist/emit.odin" "if head.text == \"arr/slice\" || head.text == \"str/slice\"" "kvist package" "(arr/slice xs start [end])"
                 "Take a slice view over an array-family value."))
     ("push!" . ("src/kvist/emit.odin" "if head.text == \"arr/push!\"" "kvist package" "(arr/push! xs value...)"
                 "Append one or more values to a dynamic array."))
     ("map" . ("src/kvist/emit.odin" "emit_core_map_helper :: proc" "kvist package" "(arr/map f xs)"
               "Map over an array-family input and return an owned dynamic array."))
     ("filter" . ("src/kvist/emit.odin" "emit_core_filter_helper :: proc" "kvist package" "(arr/filter pred xs)"
                  "Filter an array-family input and return an owned dynamic array."))
     ("map!" . ("src/kvist/emit.odin" "emit_core_map_in_place_helper :: proc" "kvist package" "(arr/map! f xs)"
                "Map in place over a dynamic array."))
     ("filter!" . ("src/kvist/emit.odin" "emit_core_filter_in_place_helper :: proc" "kvist package" "(arr/filter! pred xs)"
                   "Filter in place over a dynamic array."))
     ("take" . ("src/kvist/emit.odin" "emit_core_take_helper :: proc" "kvist package" "(arr/take n xs)"
                "Take a leading slice or owned result from an array-family input."))
     ("drop" . ("src/kvist/emit.odin" "emit_core_drop_helper :: proc" "kvist package" "(arr/drop n xs)"
                "Drop a leading prefix from an array-family input."))
     ("sort" . ("src/kvist/emit.odin" "emit_core_sort_helper :: proc" "kvist package" "(arr/sort xs)"
                "Return a sorted owned array."))
     ("sort!" . ("src/kvist/emit.odin" "emit_core_sort_in_place_helper :: proc" "kvist package" "(arr/sort! xs)"
                 "Sort a dynamic array in place.")))
    ("kvist:str"
     ("count" . ("src/kvist/emit.odin" "if head.text == \"arr/count\" || head.text == \"str/count\"" "kvist package" "(str/count s)"
                 "Count characters or bytes in a string."))
     ("get" . ("src/kvist/emit.odin" "if head.text == \"arr/get\" || head.text == \"str/get\" || head.text == \"map/get\"" "kvist package" "(str/get s index)"
               "Index into a string."))
     ("slice" . ("src/kvist/emit.odin" "if head.text == \"arr/slice\" || head.text == \"str/slice\"" "kvist package" "(str/slice s start [end])"
                 "Take a string slice."))
     ("contains?" . ("src/kvist/emit.odin" "if head.text == \"str/contains?\"" "kvist package" "(str/contains? s needle)"
                     "Return true when the string contains the needle.")))
    ("kvist:map"
     ("empty" . ("src/kvist/emit.odin" "if head.text == \"map/empty\"" "kvist package" "(map/empty K V [capacity])"
                 "Construct an empty map, optionally with capacity."))
     ("of" . ("src/kvist/emit.odin" "if head.text == \"map/of\"" "kvist package" "(map/of K V {k1 v1 ...})"
              "Construct a map from a brace literal."))
     ("get" . ("src/kvist/emit.odin" "if head.text == \"arr/get\" || head.text == \"str/get\" || head.text == \"map/get\"" "kvist package" "(map/get m key [default])"
               "Look up a key in a map, optionally with a default."))
     ("contains?" . ("src/kvist/emit.odin" "if head.text == \"map/contains?\" || head.text == \"set/contains?\"" "kvist package" "(map/contains? m key)"
                     "Return true when the map contains the key.")))
    ("kvist:set"
     ("empty" . ("src/kvist/emit.odin" "if head.text == \"set/empty\"" "kvist package" "(set/empty T [capacity])"
                 "Construct an empty set, optionally with capacity."))
     ("of" . ("src/kvist/emit.odin" "if head.text == \"set/of\"" "kvist package" "(set/of T [v1 v2 ...])"
              "Construct a set from a vector literal."))
     ("contains?" . ("src/kvist/emit.odin" "if head.text == \"map/contains?\" || head.text == \"set/contains?\"" "kvist package" "(set/contains? s value)"
                     "Return true when the set contains the value."))
     ("add!" . ("src/kvist/emit.odin" "if head.text == \"set/add!\"" "kvist package" "(set/add! s value)"
                "Insert a value into a set.")))
    ("kvist:struct"
     ("fields" . ("src/kvist/emit.odin" "if head.text == \"struct/fields\" || head.text == \"struct/types\"" "kvist package" "(struct/fields target)"
                  "Return source-level field names for a struct type or value."))
     ("types" . ("src/kvist/emit.odin" "if head.text == \"struct/fields\" || head.text == \"struct/types\"" "kvist package" "(struct/types target)"
                 "Return source-level field types for a struct type or value."))))
  "Static package members for compiler-provided Kvist packages.")

(defconst kvist--kvist-canonical-imports
  '(("arr" . "kvist:arr")
    ("str" . "kvist:str")
    ("map" . "kvist:map")
    ("set" . "kvist:set")
    ("struct" . "kvist:struct"))
  "Canonical explicit imports for compiler-provided Kvist packages.")

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
            (doc (or (nth 6 fields) "")))
      (list :kind kind
            :name name
            :line (string-to-number line-text)
            :column (string-to-number column-text)
            :detail (or detail "")
            :signature (and signature (not (string-empty-p signature)) signature)
              :doc (kvist--unescape-doc doc)
              :file file)))))

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

(defun kvist--odin-root ()
  "Return the local Odin root, or nil if it cannot be discovered."
  (pcase-let ((`(,exit-code . ,output) (kvist--call-string "odin" '("root"))))
    (when (zerop exit-code)
      (string-trim output))))

(defun kvist--import-dir (import-path)
  "Return the local directory for Odin IMPORT-PATH."
  (when-let ((root (kvist--odin-root)))
    (cond
     ((string-prefix-p "core:" import-path)
      (expand-file-name (substring import-path 5) (expand-file-name "core" root)))
     ((string-prefix-p "vendor:" import-path)
      (expand-file-name (substring import-path 7) (expand-file-name "vendor" root)))
     (t nil))))

(defun kvist--package-member-symbols (alias import-path)
  "Return compiler-provided Kvist package members for ALIAS and IMPORT-PATH."
  (when-let ((members (cdr (assoc import-path kvist--kvist-package-member-map))))
    (apply #'append
           (mapcar
            (lambda (entry)
              (pcase-let ((`(,member . (,relative ,regexp ,kind ,signature ,doc)) entry))
                (let* ((file (kvist--repo-file relative))
                       (location (kvist--file-location-for-regexp file (regexp-quote regexp)))
                       (line (or (plist-get location :line) 1))
                       (column (or (plist-get location :column) 1)))
                  (list
                   (list :kind kind
                         :name (concat alias "/" member)
                         :signature signature
                         :line line
                         :column column
                         :detail import-path
                         :doc doc
                         :file file)
                   (list :kind kind
                         :name (concat alias "." member)
                         :signature signature
                         :line line
                         :column column
                         :detail import-path
                         :doc doc
                         :file file)))))
            members))))

(defun kvist--cli-package-symbols (alias import-path)
  "Return package symbols for ALIAS and IMPORT-PATH from the Kvist CLI."
  (pcase-let ((`(,exit-code . ,output)
                (kvist--call-string (kvist--executable)
                                    (list "package-symbols" import-path alias))))
    (when (or (and (integerp exit-code) (zerop exit-code))
              (string-prefix-p "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\n" output))
      (let ((lines (cdr (split-string output "\n" t))))
        (delq nil
              (mapcar (lambda (line)
                        (kvist--parse-symbol-line line nil))
                      lines))))))

(defun kvist--merge-symbol-metadata (base updates)
  "Merge signature/doc metadata from UPDATES into BASE symbols by name."
  (let ((update-map (make-hash-table :test #'equal)))
    (dolist (symbol updates)
      (puthash (plist-get symbol :name) symbol update-map))
    (mapcar
     (lambda (symbol)
       (if-let ((update (gethash (plist-get symbol :name) update-map)))
           (let ((merged (copy-sequence symbol)))
             (when-let ((signature (plist-get update :signature)))
               (setq merged (plist-put merged :signature signature)))
             (when-let ((doc (plist-get update :doc)))
               (setq merged (plist-put merged :doc doc)))
             merged)
         symbol))
     base)))

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

(defun kvist--canonical-kvist-package-symbols ()
  "Return built-in Kvist package symbols under their canonical aliases."
  (apply #'append
         (mapcar (lambda (entry)
                   (kvist--package-member-symbols
                    (substring (car entry) (1+ (string-match ":" (car entry))))
                    (car entry)))
                 kvist--kvist-package-member-map)))

(defun kvist--package-definition-symbols (alias import-path)
  "Return exported-looking symbols for ALIAS from IMPORT-PATH."
  (or (let ((base (kvist--package-member-symbols alias import-path)))
        (when base
          (kvist--merge-symbol-metadata base
                                        (or (kvist--cli-package-symbols alias import-path)
                                            nil))))
      (let ((dir (kvist--import-dir import-path))
            symbols)
        (when (and dir (file-directory-p dir))
          (dolist (file (directory-files-recursively dir "\\.odin\\'"))
            (with-temp-buffer
              (insert-file-contents file)
              (goto-char (point-min))
              (while (re-search-forward "^[ \t]*\\([[:alnum:]_][[:alnum:]_?!]*\\)[ \t]*::" nil t)
                (let ((member (match-string-no-properties 1))
                      (line (line-number-at-pos (match-beginning 1)))
                      (column (1+ (- (match-beginning 1) (line-beginning-position))))
                      (signature (kvist--odin-signature-at-point))
                      (doc (kvist--preceding-odin-doc (match-beginning 0))))
                  (push (list :kind "odin"
                              :name (concat alias "." member)
                              :signature signature
                              :line line
                              :column column
                              :detail import-path
                              :doc doc
                              :file file)
                        symbols)
                  (push (list :kind "odin"
                              :name (concat alias "/" member)
                              :signature signature
                              :line line
                              :column column
                              :detail import-path
                              :doc doc
                              :file file)
                        symbols))))))
        (kvist--dedupe-odin-package-symbols (nreverse symbols)))))

(defun kvist--odin-signature-at-point ()
  "Return a scraped Odin declaration signature from the current line."
  (save-excursion
    (beginning-of-line)
    (let ((line (string-trim-right
                 (buffer-substring-no-properties
                  (line-beginning-position)
                  (line-end-position)))))
      (cond
       ((string-match "::[[:space:]]*proc[[:space:]]*{" line)
        (let ((parts (list (string-trim line)))
              (done nil))
          (while (and (not done) (= 0 (forward-line 1)))
            (let ((next-line (string-trim
                              (buffer-substring-no-properties
                               (line-beginning-position)
                               (line-end-position)))))
              (push next-line parts)
              (when (string-match-p "^[[:space:]]*}[[:space:]]*$" next-line)
                (setq done t))))
          (replace-regexp-in-string
           "[[:space:]\n]+"
           " "
           (string-join (nreverse parts) " "))))
       ((string-match "::" line)
        (replace-regexp-in-string
         "[[:space:]]+"
         " "
         (replace-regexp-in-string "[[:space:]]*{.*\\'" "" (string-trim line))))
       (t nil)))))

(defun kvist--odin-symbol-rank (symbol)
  "Return a preference rank for imported Odin SYMBOL. Lower is better."
  (let ((file (or (plist-get symbol :file) "")))
    (+ (if (string-match-p "/old/" file) 100 0)
       (if (string-match-p "_js\\.odin\\'" file) 10 0)
       (if (string-match-p "/example\\.odin\\'" file) 200 0))))

(defun kvist--dedupe-odin-package-symbols (symbols)
  "Deduplicate imported Odin SYMBOLS by name, keeping the best-ranked entry."
  (let ((best (make-hash-table :test #'equal))
        order)
    (dolist (symbol symbols)
      (let* ((name (plist-get symbol :name))
             (current (gethash name best)))
        (unless current
          (push name order))
        (when (or (null current)
                  (< (kvist--odin-symbol-rank symbol)
                     (kvist--odin-symbol-rank current)))
          (puthash name symbol best))))
    (mapcar (lambda (name) (gethash name best))
            (nreverse order))))

(defun kvist--clean-doc-comment-line (line)
  "Return LINE with a leading line-comment marker removed."
  (setq line (string-trim-left line))
  (cond
   ((string-prefix-p "///" line)
    (string-trim-left (substring line 3)))
   ((string-prefix-p "//" line)
    (string-trim-left (substring line 2)))
   (t line)))

(defun kvist--clean-block-doc-line (line)
  "Return cleaned block-comment documentation LINE."
  (setq line (string-trim line))
  (when (string-prefix-p "*" line)
    (setq line (string-trim-left (substring line 1))))
  line)

(defun kvist--clean-block-doc-comment (text)
  "Return cleaned documentation text from a /* ... */ block."
  (when (string-prefix-p "/*" text)
    (setq text (substring text 2)))
  (when (string-suffix-p "*/" text)
    (setq text (substring text 0 (- (length text) 2))))
  (let ((lines (mapcar #'kvist--clean-block-doc-line
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

(defun kvist--preceding-odin-doc (pos)
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
                (push (kvist--clean-doc-comment-line line) lines)
                (beginning-of-line))
               ((string-match-p "\\*/[ \t]*\\'" line)
                (let ((block-end (line-end-position)))
                  (if (search-backward "/*" nil t)
                      (progn
                        (push (kvist--clean-block-doc-comment
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

(defun kvist--import-symbols ()
  "Return import symbols from the current buffer."
  (seq-filter (lambda (symbol)
                (equal (plist-get symbol :kind) "import"))
              (ignore-errors (kvist--symbols))))

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

(defun kvist--package-symbols-for-current-buffer ()
  "Return imported Odin package symbols for current buffer imports."
  (kvist--dedupe-symbols-by-name
   (append
    (apply #'append
           (mapcar (lambda (symbol)
                     (kvist--package-definition-symbols
                      (plist-get symbol :name)
                      (plist-get symbol :detail)))
                   (kvist--import-symbols)))
    (kvist--canonical-kvist-package-symbols))))

(defun kvist--package-definitions (identifier)
  "Return package definitions matching alias-qualified IDENTIFIER."
  (let ((identifier (kvist--normalize-qualified-identifier identifier)))
    (when (string-match "\\`\\([^/]+\\)/\\(.+\\)\\'" identifier)
      (let ((alias (match-string 1 identifier)))
        (seq-filter (lambda (symbol)
                      (and (string-prefix-p (concat alias "/") (kvist--normalize-qualified-identifier (plist-get symbol :name)))
                           (string= (kvist--normalize-qualified-identifier (plist-get symbol :name)) identifier)))
                    (kvist--package-symbols-for-current-buffer))))))

(defun kvist--repo-file (relative)
  "Return RELATIVE inside the current Kvist checkout."
  (expand-file-name relative (file-name-as-directory (kvist--project-root))))

(defun kvist--file-location-for-regexp (file regexp)
  "Return a plist location for first REGEXP in FILE."
  (when (file-readable-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (when (re-search-forward regexp nil t)
        (list :file file
              :line (line-number-at-pos (match-beginning 0))
              :column (1+ (- (match-beginning 0) (line-beginning-position))))))))

(defconst kvist--language-implementation-map
  '(("package" . ("src/kvist/parse.odin" "case \"package\":" "kvist form"))
    ("import" . ("src/kvist/parse.odin" "case \"import\":" "kvist form"))
    ("const" . ("src/kvist/parse.odin" "case \"const\":" "kvist form"))
    ("struct" . ("src/kvist/parse.odin" "case \"struct\":" "kvist form"))
    ("enum" . ("src/kvist/parse.odin" "case \"enum\":" "kvist form"))
    ("union" . ("src/kvist/parse.odin" "case \"union\":" "kvist form"))
    ("proc" . ("src/kvist/parse.odin" "parse_proc_decl :: proc" "kvist form"))
    ("odin" . ("src/kvist/emit.odin" "case \"odin\":" "kvist form"))
    ("let" . ("src/kvist/emit.odin" "case \"let\":" "kvist form"))
    ("do" . ("src/kvist/emit.odin" "case \"do\":" "kvist form"))
    ("if" . ("src/kvist/emit.odin" "emit_if_like :: proc" "kvist form"))
    ("when" . ("src/kvist/emit.odin" "case \"when\":" "kvist form"))
    ("cond" . ("src/kvist/emit.odin" "emit_cond_stmt :: proc" "kvist form"))
    ("switch" . ("src/kvist/emit.odin" "emit_switch_stmt :: proc" "kvist form"))
    ("set!" . ("src/kvist/emit.odin" "case \"set!\":" "kvist form"))
    ("return" . ("src/kvist/emit.odin" "case \"return\":" "kvist form"))
    ("defer" . ("src/kvist/emit.odin" "case \"defer\":" "kvist form"))
    ("for" . ("src/kvist/emit.odin" "case \"for\":" "kvist form"))
    ("each" . ("src/kvist/emit.odin" "case \"each\":" "kvist form"))
    ("update" . ("src/kvist/emit.odin" "case \"update\":" "kvist form"))
    ("update!" . ("src/kvist/emit.odin" "case \"update!\":" "kvist form"))
    ("comment" . ("src/kvist/parse.odin" "case \"comment\":" "kvist form"))
    ("new" . ("src/kvist/emit.odin" "if head.text == \"new\"" "kvist form"))
    ("make" . ("src/kvist/emit.odin" "if head.text == \"make\"" "kvist form"))
    ("get" . ("src/kvist/emit.odin" "if head.text == \"get\"" "kvist form"))
    ("nil?" . ("src/kvist/emit.odin" "if head.text == \"nil?\"" "kvist form"))
    ("type" . ("src/kvist/parse.odin" "if is_symbol(form.items[0], \"type\")" "kvist form"))
    ("in" . ("src/kvist/emit.odin" "if op == \"in\" || op == \"not-in\"" "kvist form"))
    ("not-in" . ("src/kvist/emit.odin" "if op == \"in\" || op == \"not-in\"" "kvist form"))
    ("break" . ("src/kvist/emit.odin" "case \"break\":" "kvist form"))
    ("continue" . ("src/kvist/emit.odin" "case \"continue\":" "kvist form"))
    ("with-allocator" . ("src/kvist/emit.odin" "emit_with_allocator_stmt :: proc" "kvist form"))
    ("with-temp-allocator" . ("src/kvist/emit.odin" "emit_with_temp_allocator_stmt :: proc" "kvist form"))
    ("with-delete" . ("src/kvist/emit.odin" "emit_with_delete_stmt :: proc" "kvist form"))
    ("when-let" . ("src/kvist/macroexpand.odin" "expand_when_let_form :: proc" "kvist form"))
    ("if-let" . ("src/kvist/macroexpand.odin" "expand_if_let_form :: proc" "kvist form"))
    ("when-ok" . ("src/kvist/macroexpand.odin" "expand_when_ok_form :: proc" "kvist form"))
    ("if-ok" . ("src/kvist/macroexpand.odin" "expand_if_ok_form :: proc" "kvist form"))
    ("slurp" . ("src/kvist/emit.odin" "if head.text == \"slurp\"" "kvist form"))
    ("spit" . ("src/kvist/emit.odin" "if head.text == \"spit\"" "kvist form"))
    ("tap>" . ("src/kvist/emit.odin" "if head.text == \"tap>\"" "kvist form"))
    ("->" . ("src/kvist/emit.odin" "emit_thread_expr :: proc" "kvist form"))
    ("->>" . ("src/kvist/emit.odin" "emit_thread_expr :: proc" "kvist form")))
  "Implementation locations for Kvist special forms.")

(defconst kvist--core-helper-implementation-map
  '(("map" . ("src/kvist/emit.odin" "emit_core_map_helper :: proc" "kvist helper"))
    ("filter" . ("src/kvist/emit.odin" "emit_core_filter_helper :: proc" "kvist helper"))
    ("remove" . ("src/kvist/emit.odin" "emit_core_remove_helper :: proc" "kvist helper"))
    ("reduce" . ("src/kvist/emit.odin" "emit_core_reduce_helper :: proc" "kvist helper"))
    ("map-indexed" . ("src/kvist/emit.odin" "emit_core_map_indexed_helper :: proc" "kvist helper"))
    ("keep" . ("src/kvist/emit.odin" "emit_core_keep_helper :: proc" "kvist helper"))
    ("mapcat" . ("src/kvist/emit.odin" "emit_core_mapcat_helper :: proc" "kvist helper"))
    ("concat" . ("src/kvist/emit.odin" "emit_core_concat_helper :: proc" "kvist helper"))
    ("merge" . ("src/kvist/emit.odin" "emit_core_merge_helper :: proc" "kvist helper"))
    ("merge!" . ("src/kvist/emit.odin" "emit_core_merge_in_place_helper :: proc" "kvist helper"))
    ("into" . ("src/kvist/emit.odin" "emit_core_into_helper :: proc" "kvist helper"))
    ("into!" . ("src/kvist/emit.odin" "if head.text == \"into!\"" "kvist helper"))
    ("interpose" . ("src/kvist/emit.odin" "emit_core_interpose_helper :: proc" "kvist helper"))
    ("interleave" . ("src/kvist/emit.odin" "emit_core_interleave_helper :: proc" "kvist helper"))
    ("reverse" . ("src/kvist/emit.odin" "emit_core_reverse_helper :: proc" "kvist helper"))
    ("reverse!" . ("src/kvist/emit.odin" "emit_core_reverse_in_place_helper :: proc" "kvist helper"))
    ("shuffle" . ("src/kvist/emit.odin" "emit_core_shuffle_helper :: proc" "kvist helper"))
    ("shuffle!" . ("src/kvist/emit.odin" "emit_core_shuffle_in_place_helper :: proc" "kvist helper"))
    ("sort" . ("src/kvist/emit.odin" "emit_core_sort_helper :: proc" "kvist helper"))
    ("sort!" . ("src/kvist/emit.odin" "emit_core_sort_in_place_helper :: proc" "kvist helper"))
    ("sort-by" . ("src/kvist/emit.odin" "emit_core_sort_by_helper :: proc" "kvist helper"))
    ("sort-by!" . ("src/kvist/emit.odin" "emit_core_sort_by_in_place_helper :: proc" "kvist helper"))
    ("map!" . ("src/kvist/emit.odin" "emit_core_map_in_place_helper :: proc" "kvist helper"))
    ("map-indexed!" . ("src/kvist/emit.odin" "emit_core_map_indexed_in_place_helper :: proc" "kvist helper"))
    ("filter!" . ("src/kvist/emit.odin" "emit_core_filter_in_place_helper :: proc" "kvist helper"))
    ("remove!" . ("src/kvist/emit.odin" "emit_core_remove_in_place_helper :: proc" "kvist helper"))
    ("keep!" . ("src/kvist/emit.odin" "emit_core_keep_in_place_helper :: proc" "kvist helper"))
    ("split-at" . ("src/kvist/emit.odin" "emit_core_split_at_helper :: proc" "kvist helper"))
    ("partition" . ("src/kvist/emit.odin" "emit_core_partition_helper :: proc" "kvist helper"))
    ("partition-all" . ("src/kvist/emit.odin" "emit_core_partition_all_helper :: proc" "kvist helper"))
    ("partition-by" . ("src/kvist/emit.odin" "emit_core_partition_by_helper :: proc" "kvist helper"))
    ("zipmap" . ("src/kvist/emit.odin" "emit_core_zipmap_helper :: proc" "kvist helper"))
    ("index-by" . ("src/kvist/emit.odin" "emit_core_index_by_helper :: proc" "kvist helper"))
    ("group-by" . ("src/kvist/emit.odin" "emit_core_group_by_helper :: proc" "kvist helper"))
    ("frequencies" . ("src/kvist/emit.odin" "emit_core_frequencies_helper :: proc" "kvist helper"))
    ("keys" . ("src/kvist/emit.odin" "emit_core_keys_helper :: proc" "kvist helper"))
    ("vals" . ("src/kvist/emit.odin" "emit_core_vals_helper :: proc" "kvist helper"))
    ("distinct" . ("src/kvist/emit.odin" "emit_core_distinct_helper :: proc" "kvist helper"))
    ("distinct-by" . ("src/kvist/emit.odin" "emit_core_distinct_by_helper :: proc" "kvist helper"))
    ("range" . ("src/kvist/emit.odin" "emit_core_range_helper :: proc" "kvist helper"))
    ("repeat" . ("src/kvist/emit.odin" "emit_core_repeat_helper :: proc" "kvist helper"))
    ("repeatedly" . ("src/kvist/emit.odin" "emit_core_repeatedly_helper :: proc" "kvist helper"))
    ("iterate" . ("src/kvist/emit.odin" "emit_core_iterate_helper :: proc" "kvist helper"))
    ("cycle" . ("src/kvist/emit.odin" "emit_core_cycle_helper :: proc" "kvist helper"))
    ("take" . ("src/kvist/emit.odin" "emit_core_take_helper :: proc" "kvist helper"))
    ("drop" . ("src/kvist/emit.odin" "emit_core_drop_helper :: proc" "kvist helper"))
    ("butlast" . ("src/kvist/emit.odin" "if head.text == \"first\" || head.text == \"second\"" "kvist helper"))
    ("drop-last" . ("src/kvist/emit.odin" "emit_core_drop_last_helper :: proc" "kvist helper"))
    ("take-nth" . ("src/kvist/emit.odin" "emit_core_take_nth_helper :: proc" "kvist helper"))
    ("take-while" . ("src/kvist/emit.odin" "emit_core_take_while_helper :: proc" "kvist helper"))
    ("drop-while" . ("src/kvist/emit.odin" "emit_core_drop_while_helper :: proc" "kvist helper"))
    ("find" . ("src/kvist/emit.odin" "emit_core_find_helper :: proc" "kvist helper"))
    ("some?" . ("src/kvist/emit.odin" "emit_core_some_helper :: proc" "kvist helper"))
    ("every?" . ("src/kvist/emit.odin" "emit_core_every_helper :: proc" "kvist helper"))
    ("first" . ("src/kvist/emit.odin" "if head.text == \"first\" || head.text == \"second\"" "kvist helper"))
    ("second" . ("src/kvist/emit.odin" "if head.text == \"first\" || head.text == \"second\"" "kvist helper"))
    ("last" . ("src/kvist/emit.odin" "if head.text == \"first\" || head.text == \"second\"" "kvist helper"))
    ("nth" . ("src/kvist/emit.odin" "if head.text == \"nth\"" "kvist helper"))
    ("rest" . ("src/kvist/emit.odin" "if head.text == \"first\" || head.text == \"second\"" "kvist helper"))
    ("empty?" . ("src/kvist/emit.odin" "if head.text == \"first\" || head.text == \"second\"" "kvist helper"))
    ("count" . ("src/kvist/emit.odin" "if head.text == \"first\" || head.text == \"second\"" "kvist helper"))
    ("contains?" . ("src/kvist/emit.odin" "if op == \"in?\" || op == \"contains?\"" "kvist helper")))
  "Implementation locations for Kvist core helpers.")

(defun kvist--mapped-implementation-definition (identifier mapping fallback-detail)
  "Return xref symbol for IDENTIFIER using MAPPING."
  (when-let ((entry (cdr (assoc identifier mapping))))
    (pcase-let ((`(,relative ,regexp ,kind) entry))
      (let* ((file (kvist--repo-file relative))
             (location (kvist--file-location-for-regexp file (regexp-quote regexp))))
        (when location
          (append (list :kind kind
                        :name identifier
                        :detail (or fallback-detail relative))
                  location))))))

(defun kvist--language-form-definition (identifier)
  "Return an xref symbol for Kvist language form IDENTIFIER."
  (or (kvist--mapped-implementation-definition
       identifier kvist--language-implementation-map nil)
      (when (member identifier kvist-special-forms)
        (let* ((file (kvist--repo-file "LANGUAGE.md"))
               (quoted (regexp-quote identifier))
               (location (or (kvist--file-location-for-regexp file (format "^### `%s`" quoted))
                             (kvist--file-location-for-regexp file (format "`%s`" quoted))
                             (kvist--file-location-for-regexp file (format "\\_<%s\\_>" quoted)))))
          (when location
            (append (list :kind "kvist form"
                          :name identifier
                          :detail "LANGUAGE.md")
                    location))))))

(defun kvist--core-helper-definition (identifier)
  "Return an xref symbol for Kvist core helper IDENTIFIER."
  (or (kvist--mapped-implementation-definition
       identifier kvist--core-helper-implementation-map nil)
      (when (member identifier kvist-core-helpers)
        (let* ((file (kvist--repo-file "docs/SEQUENCES.md"))
               (quoted (regexp-quote identifier))
               (location (or (kvist--file-location-for-regexp file (format "(%s\\(?:[[:space:])]\\)" quoted))
                             (kvist--file-location-for-regexp file (format "`%s`" quoted)))))
          (when location
            (append (list :kind "kvist helper"
                          :name identifier
                          :detail "docs/SEQUENCES.md")
                    location))))))

(defun kvist--builtin-definitions (identifier)
  "Return built-in Kvist definitions matching IDENTIFIER."
  (delq nil
        (list (kvist--language-form-definition identifier)
              (kvist--core-helper-definition identifier)
              (when (string= identifier "println")
                (kvist--mapped-implementation-definition
                 "println"
                 '(("println" . ("src/kvist/emit.odin" "if form.items[0].text == \"println\" || form.items[0].text == \"doc\"" "kvist core")))
                 nil))
              (when (string= identifier "doc")
                (kvist--mapped-implementation-definition
                 "doc"
                 '(("doc" . ("src/kvist/emit.odin" "case \"doc\":" "kvist core")))
                 nil)))))

(defun kvist--xref-backend () 'kvist)

(cl-defmethod xref-backend-identifier-at-point ((_backend (eql kvist)))
  (kvist--identifier-at-point))

(cl-defmethod xref-backend-definitions ((_backend (eql kvist)) identifier)
  (let* ((symbols (append (ignore-errors (kvist--symbols))
                          (ignore-errors (kvist--package-definitions identifier))
                          (kvist--builtin-definitions identifier)))
         (matches (seq-filter (lambda (symbol)
                                (kvist--symbol-matches-identifier-p symbol identifier))
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

(defun kvist--completion-bounds ()
  "Return completion bounds for Kvist symbols."
  (kvist--symbol-bounds))

(defun kvist--package-prefix (identifier)
  "Return (ALIAS . SEP) when IDENTIFIER starts a qualified package symbol."
  (when (and identifier
             (string-match "\\`\\([^./]+\\)\\([./]\\)\\([^./]*\\)\\'" identifier))
    (cons (match-string 1 identifier) (match-string 2 identifier))))

(defun kvist--completion-candidates ()
  "Return completion candidates appropriate for the symbol at point."
  (let* ((identifier (kvist--identifier-at-point))
         (package-prefix (kvist--package-prefix identifier)))
    (if package-prefix
        (let* ((alias (car package-prefix))
               (sep (cdr package-prefix))
               (prefix (concat alias sep))
               (normalized-prefix (kvist--normalize-qualified-identifier prefix)))
          (delete-dups
           (mapcar
            (lambda (symbol)
              (let ((name (plist-get symbol :name)))
                (if (string= sep ".")
                    (replace-regexp-in-string "/" "." name t t)
                  (replace-regexp-in-string "\\." "/" name t t))))
            (seq-filter
             (lambda (symbol)
               (string-prefix-p normalized-prefix
                                (kvist--normalize-qualified-identifier
                                 (plist-get symbol :name))))
             (ignore-errors (kvist--package-symbols-for-current-buffer))))))
      (delete-dups
       (append kvist-completion-builtins
               (mapcar (lambda (symbol) (plist-get symbol :name))
                       (ignore-errors (append (kvist--symbols)
                                              (kvist--package-symbols-for-current-buffer)))))))))

(defun kvist--completion-exit (completed status)
  "Handle completion of COMPLETED with STATUS."
  (when (eq status 'finished)
    (kvist--maybe-auto-import-qualified-symbol completed)))

(defun kvist--completion-metadata (identifier)
  "Return symbol metadata alist keyed by display name for IDENTIFIER context."
  (let* ((identifier (or identifier (kvist--identifier-at-point)))
         (package-prefix (kvist--package-prefix identifier))
         (symbols (if package-prefix
                      (let* ((alias (car package-prefix))
                             (normalized-prefix
                              (kvist--normalize-qualified-identifier (concat alias "/"))))
                        (seq-filter
                         (lambda (symbol)
                           (string-prefix-p normalized-prefix
                                            (kvist--normalize-qualified-identifier
                                             (plist-get symbol :name))))
                         (ignore-errors (kvist--package-symbols-for-current-buffer))))
                    (append (ignore-errors (kvist--symbols))
                            (ignore-errors (kvist--package-symbols-for-current-buffer))
                            (mapcar (lambda (entry)
                                      (pcase-let ((`(,name . (,kind ,signature ,doc)) entry))
                                        (list :name name
                                              :kind kind
                                              :signature signature
                                              :doc doc)))
                                    kvist--builtin-doc-map)))))
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
  (let* ((symbols (append (ignore-errors (kvist--symbols))
                          (ignore-errors (kvist--package-definitions identifier))
                          (kvist--builtin-doc-candidates identifier)))
         (matches (seq-filter (lambda (symbol)
                                (kvist--symbol-matches-identifier-p symbol identifier))
                              symbols)))
    (seq-filter (lambda (symbol)
                  (or (not (string-empty-p (or (plist-get symbol :doc) "")))
                      (not (string-empty-p (or (plist-get symbol :signature) "")))))
                matches)))

(defun kvist--builtin-doc-candidates (identifier)
  "Return static documentation candidates for Kvist built-in IDENTIFIER."
  (when-let ((entry (cdr (assoc identifier kvist--builtin-doc-map))))
    (pcase-let ((`(,kind ,signature ,doc) entry))
      (list (list :kind kind
                  :name identifier
                  :signature signature
                  :line 1
                  :column 1
                  :detail ""
                  :doc doc)))))

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
  (let* ((candidates (all-completions identifier (kvist--completion-candidates)))
         (metadata (kvist--completion-metadata identifier)))
    (when (= (length candidates) 1)
      (when-let ((entry (assoc (car candidates) metadata)))
        (cdr entry)))))

(defun kvist-eldoc-function ()
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
  (let* ((identifier (or (kvist--identifier-at-point)
                         (user-error "No symbol at point")))
         (matches (kvist--symbol-doc-candidates identifier)))
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
        (kvist--show-doc (nth (cl-position choice names :test #'equal) matches)))))))

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
