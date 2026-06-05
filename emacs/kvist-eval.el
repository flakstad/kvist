;;; kvist-eval.el --- REPL-like eval helpers for Kvist -*- lexical-binding: t; -*-

;; This shells out to kvist.  It does not interpret Kvist and it does not
;; maintain hidden runtime state.

(require 'subr-x)
(require 'compile)
(require 'kvist-mode)

(defcustom kvist-result-buffer-name "*Kvist Eval*"
  "Buffer name used for Kvist eval output."
  :type 'string
  :group 'kvist)

(defcustom kvist-generated-buffer-name "*Kvist Generated*"
  "Buffer name used to show generated Odin."
  :type 'string
  :group 'kvist)

(defcustom kvist-macroexpand-buffer-name "*Kvist Macroexpand*"
  "Buffer name used to show Kvist macro expansion output."
  :type 'string
  :group 'kvist)

(defcustom kvist-inline-result-prefix "=> "
  "Prefix used for inline Kvist eval overlays."
  :type 'string
  :group 'kvist)

(defcustom kvist-show-generated nil
  "When non-nil, show generated Odin for eval commands."
  :type 'boolean
  :group 'kvist)

(defcustom kvist-default-no-print nil
  "When non-nil, default eval commands run snippets as statements."
  :type 'boolean
  :group 'kvist)

(defcustom kvist-test-buffer-name "*Kvist Test*"
  "Buffer name used for Kvist test output."
  :type 'string
  :group 'kvist)

(defcustom kvist-run-buffer-name "*Kvist Run*"
  "Buffer name used for long-running `kvist run' sessions."
  :type 'string
  :group 'kvist)

(defconst kvist-declaration-heads
  '("comment" "package" "import" "const" "struct" "enum" "union" "odin" "proc")
  "Kvist forms that are declarations at top level.")

(defvar kvist--last-source-buffer nil)

(defvar kvist-cache-name-history nil
  "Minibuffer history for Kvist cache names.")

(defconst kvist--compilation-error-regexp
  '("^\\([^:\n]+\\.kvist\\):\\(?:<eval>:\\)?\\([0-9]+\\):\\([0-9]+\\)\\(?::\\| \\)"
    1 2 3)
  "Compilation regexp for Kvist and Kvist eval diagnostics.")

(defun kvist--install-compilation-regexp ()
  "Install Kvist diagnostic matching for `compilation-mode'."
  (unless (assq 'kvist compilation-error-regexp-alist-alist)
    (add-to-list 'compilation-error-regexp-alist-alist
                 (cons 'kvist kvist--compilation-error-regexp)))
  (unless (memq 'kvist compilation-error-regexp-alist)
    (add-to-list 'compilation-error-regexp-alist 'kvist)))

(kvist--install-compilation-regexp)

(defvar kvist-eval-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-e") #'kvist-eval-form-at-point)
    (define-key map (kbd "C-c C-p") #'kvist-popup-form-at-point)
    (define-key map (kbd "C-c C-i") #'kvist-insert-form-result)
    (define-key map (kbd "C-c C-r") #'kvist-eval-region)
    (define-key map (kbd "C-c C-c") #'kvist-eval-top-level-form)
    (define-key map (kbd "C-c C-x") #'kvist-eval-comment-form)
    (define-key map (kbd "C-c C-k") #'kvist-eval-buffer)
    (define-key map (kbd "C-c C-a") #'kvist-run-buffer)
    (define-key map (kbd "C-c C-b") #'kvist-build-buffer)
    (define-key map (kbd "C-c C-v") #'kvist-check-buffer)
    (define-key map (kbd "C-c C-m") #'kvist-expand-form-at-point)
    (define-key map (kbd "C-c M-m") #'kvist-macroexpand-form-at-point)
    (define-key map (kbd "C-c C-s") #'kvist-toggle-show-generated)
    (define-key map (kbd "C-c d") #'kvist-doc-at-point)
    (define-key map (kbd "C-c C-d") #'kvist-doc-at-point)
    (define-key map (kbd "C-c C-w") #'kvist-save-form-result)
    (define-key map (kbd "C-c C-l") #'kvist-cache-list)
    (define-key map (kbd "C-c C-o") #'kvist-cache-open)
    (define-key map (kbd "C-c M-d") #'kvist-cache-rm)
    (define-key map (kbd "C-c C-z") #'kvist-switch-to-result)
    (define-key map (kbd "C-c t t") #'kvist-test-at-point)
    (define-key map (kbd "C-c t p") #'kvist-test-package)
    (define-key map (kbd "C-c t a") #'kvist-test-project)
    map)
  "Keymap for `kvist-eval-mode'.")

;;;###autoload
(define-minor-mode kvist-eval-mode
  "Minor mode for Kvist eval keybindings."
  :lighter " Kvist-Eval"
  :keymap kvist-eval-mode-map)

(defun kvist-clear-inline-results ()
  "Delete Kvist inline result overlays in the current buffer."
  (remove-overlays (point-min) (point-max) 'kvist-result-overlay t))

(defun kvist--enable-inline-result-clearing ()
  "Clear Kvist overlays before the next command in this buffer."
  (add-hook 'pre-command-hook #'kvist-clear-inline-results nil t))

(defun kvist--prepare-buffer (name)
  "Create and clear buffer NAME."
  (let ((buffer (get-buffer-create name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t)
            (buffer-read-only nil))
        (erase-buffer)
        (special-mode)
        (setq-local truncate-lines nil)
        (setq-local word-wrap t)
        (visual-line-mode 1)))
    buffer))

(defun kvist--prepare-diagnostic-buffer (name)
  "Create and clear diagnostic buffer NAME."
  (let ((buffer (get-buffer-create name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t)
            (buffer-read-only nil))
        (erase-buffer)
        (compilation-mode)
        (setq-local compilation-directory default-directory)
        (setq-local truncate-lines nil)
        (setq-local word-wrap t)
        (visual-line-mode 1)))
    buffer))

(defun kvist--diagnostic-buffer-p (text)
  "Return non-nil when TEXT looks like Kvist compiler diagnostics."
  (string-match-p "\\.kvist:\\(?:<eval>:\\)?[0-9]+:[0-9]+\\(?::\\| \\)" text))

(defun kvist--finish-output-buffer (diagnostic)
  "Put the current output buffer in the right display mode.
When DIAGNOSTIC is non-nil, use `compilation-mode'."
  (goto-char (point-min))
  (if diagnostic
      (progn
        (compilation-mode)
        (setq-local compilation-directory default-directory)
        (setq next-error-last-buffer (current-buffer)))
    (special-mode))
  (setq-local truncate-lines nil)
  (setq-local word-wrap t)
  (visual-line-mode 1))

(defun kvist--remap-output-source-path (text temp-source source-buffer)
  "Replace TEMP-SOURCE diagnostic paths in TEXT with SOURCE-BUFFER's file."
  (if (and temp-source
           (buffer-live-p source-buffer)
           (buffer-file-name source-buffer))
      (replace-regexp-in-string
       (regexp-quote (expand-file-name temp-source))
       (expand-file-name (buffer-file-name source-buffer))
       text
       t
       t)
    text))

(defun kvist--call (program args output-buffer &optional diagnostic)
  "Call PROGRAM with ARGS, writing output to OUTPUT-BUFFER."
  (with-current-buffer output-buffer
    (let ((inhibit-read-only t)
          (buffer-read-only nil))
      (erase-buffer)
      (prog1
          (apply #'call-process program nil t nil args)
        (kvist--finish-output-buffer diagnostic)))))

(defun kvist--cache-name-prompt (prompt)
  "Read a cache name using PROMPT."
  (read-string prompt nil 'kvist-cache-name-history))

(defun kvist--cache-command (args &optional display)
  "Run `kvist cache' with ARGS.
When DISPLAY is non-nil, show command output in the result buffer."
  (let* ((output-buffer (kvist--prepare-buffer kvist-result-buffer-name))
         (root (file-name-as-directory (kvist--project-root)))
         (default-directory root)
         (exit-code (kvist--call (kvist--executable) (append (list "cache") args) output-buffer))
         (result (with-current-buffer output-buffer
                   (buffer-substring-no-properties (point-min) (point-max)))))
    (if (or display (not (zerop exit-code)))
        (kvist--display-output output-buffer result exit-code)
      (kvist--message-result result exit-code))
    (cons exit-code result)))

(defun kvist--sexp-bounds-near-point ()
  "Return bounds for the list at or immediately before point."
  (save-excursion
    (skip-chars-forward " \t")
    (cond
     ((eq (char-after) ?\()
      (let ((beg (point)))
        (cons beg (scan-sexps beg 1))))
     ((eq (char-before) ?\))
      (let ((end (point)))
        (backward-sexp 1)
        (cons (point) end)))
     ((progn
        (skip-chars-backward " \t\n")
        (eq (char-before) ?\)))
      (let ((end (point)))
        (backward-sexp 1)
        (cons (point) end)))
     ((eq (char-after) ?\))
      (let ((end (1+ (point))))
        (forward-char 1)
        (backward-sexp 1)
        (cons (point) end)))
     (t nil))))

(defun kvist--form-bounds-at-point ()
  "Return bounds of the form at or immediately before point."
  (or (kvist--sexp-bounds-near-point)
      (bounds-of-thing-at-point 'sexp)
      (user-error "No form at point")))

(defun kvist--declaration-form-string-p (form)
  "Return non-nil when FORM text starts with a Kvist declaration head."
  (when (string-match "\\`[[:space:]]*(\\([[:word:]!?._+-]+\\)" form)
    (member (match-string 1 form) kvist-declaration-heads)))

(defun kvist--top-level-bounds ()
  "Return bounds of the current top-level form."
  (save-excursion
    (beginning-of-defun)
    (let ((beg (point)))
      (end-of-defun)
      (cons beg (point)))))

(defun kvist--enclosing-comment-form-bounds ()
  "Return bounds of the enclosing `(comment ...)' form."
  (or
   (save-excursion
     (let ((found nil))
       (condition-case nil
           (while (not found)
             (backward-up-list)
             (let ((beg (point)))
               (forward-char 1)
               (skip-chars-forward " \t\n")
               (when (looking-at-p "comment\\_>")
                 (setq found (cons beg (scan-sexps beg 1))))))
         (error nil))
       found))
   (user-error "Point is not inside a (comment ...) form")))

(defun kvist--comment-form-code ()
  "Return a statement form for the body of the enclosing `(comment ...)' form."
  (let ((bounds (kvist--enclosing-comment-form-bounds)))
    (save-excursion
      (goto-char (car bounds))
      (forward-char 1)
      (skip-chars-forward " \t\n")
      (forward-sexp 1)
      (skip-chars-forward " \t\n")
      (let ((body-start (point)))
        (goto-char (cdr bounds))
        (backward-char 1)
        (skip-chars-backward " \t\n")
        (let ((body (buffer-substring-no-properties body-start (point))))
          (if (string-empty-p (string-trim body))
              (user-error "Empty (comment ...) form")
            (concat "(do\n" body "\n)")))))))

(defun kvist--show-generated (generated)
  "Show GENERATED Odin in `kvist-generated-buffer-name'."
  (when (and kvist-show-generated generated (file-exists-p generated))
    (let ((buffer (kvist--prepare-buffer kvist-generated-buffer-name)))
      (with-current-buffer buffer
        (let ((inhibit-read-only t)
              (buffer-read-only nil))
          (erase-buffer)
          (insert-file-contents generated)
          (when (fboundp 'odin-mode)
            (odin-mode))))
      (display-buffer buffer))))

(defun kvist--trim-output (text)
  "Trim TEXT for minibuffer and inline display."
  (string-trim (replace-regexp-in-string "[ \t\n\r]+" " " text)))

(defun kvist--show-inline-result (beg end text exit-code)
  "Show TEXT inline after BEG and END."
  (remove-overlays beg end 'kvist-result-overlay t)
  (let* ((trimmed (string-trim text))
         (display-text (if (string-empty-p trimmed)
                           (format " %s%s" kvist-inline-result-prefix
                                   (if (zerop exit-code) "ok" (format "<exit %s>" exit-code)))
                         (format " %s%s" kvist-inline-result-prefix
                                 (replace-regexp-in-string "[\n\r\t ]+" " " trimmed))))
         (ov (make-overlay beg end)))
    (put-text-property 0 1 'cursor 0 display-text)
    (put-text-property 0 (length display-text) 'face
                       (if (zerop exit-code) 'shadow 'error)
                       display-text)
    (overlay-put ov 'kvist-result-overlay t)
    (overlay-put ov 'priority 1000)
    (overlay-put ov 'evaporate t)
    (overlay-put ov 'after-string display-text)
    (kvist--enable-inline-result-clearing)))

(defun kvist--message-result (text exit-code)
  "Show a concise minibuffer message for TEXT and EXIT-CODE."
  (let ((trimmed (kvist--trim-output text)))
    (message "%s"
             (cond
              ((not (zerop exit-code))
               (if (string-empty-p trimmed)
                   (format "kvist exited %s" exit-code)
                 trimmed))
              ((string-empty-p trimmed) "")
              (t trimmed)))))

(defun kvist--insert-comment-result (buffer line-end text exit-code)
  "Insert TEXT as a ;; => result comment in BUFFER after LINE-END."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (save-excursion
        (goto-char line-end)
        (end-of-line)
        (if (eobp)
            (insert "\n")
          (forward-line 1))
        (while (and (not (eobp))
                    (looking-at-p "[[:space:]]*;;[[:space:]]*=>"))
          (delete-region (line-beginning-position)
                         (min (point-max) (1+ (line-end-position)))))
        (let* ((trimmed (string-trim text))
               (single-line (if (string-empty-p trimmed)
                                (if (zerop exit-code) "ok" "")
                              (replace-regexp-in-string "[\n\r\t ]+" " " trimmed))))
          (insert (format ";; => %s%s\n"
                          (if (zerop exit-code) "" (format "<exit %s> " exit-code))
                          single-line)))))))

(defun kvist--display-output (output-buffer text exit-code &optional diagnostic)
  "Display TEXT in OUTPUT-BUFFER with EXIT-CODE."
  (with-current-buffer output-buffer
    (let ((inhibit-read-only t)
          (buffer-read-only nil))
      (erase-buffer)
      (insert (format "$ kvist exited %s\n\n" exit-code))
      (unless (string-empty-p text)
        (insert text)
        (unless (string-suffix-p "\n" text)
          (insert "\n")))
      (kvist--finish-output-buffer (or diagnostic (kvist--diagnostic-buffer-p text)))))
  (display-buffer output-buffer)
  (message "kvist exited %s" exit-code))

(defun kvist--void-value-error-p (text)
  "Return non-nil when TEXT is Odin's diagnostic for printing a void call."
  (string-match-p "call does not return a value and cannot be used as a value" text))

(defun kvist--eval-string (form &optional no-print check-only display bounds save-name)
  "Evaluate FORM via generated Odin.
When NO-PRINT is non-nil, treat FORM as a statement.  When CHECK-ONLY is
non-nil, run `odin check' instead of `odin run'.  DISPLAY may be `inline',
`comment', or `buffer'.  SAVE-NAME stores successful stdout in the Kvist
CLI cache."
  (when (and check-only save-name)
    (user-error "Cannot save a check-only Kvist eval"))
  (setq kvist--last-source-buffer (current-buffer))
  (let* ((source-buffer (current-buffer))
         (source (kvist--source-temp-file))
         (generated (when kvist-show-generated
                      (make-temp-file "kvist-eval-" nil ".odin")))
         (output-buffer (kvist--prepare-diagnostic-buffer kvist-result-buffer-name))
         (args (append (list "eval" source form)
                       (when no-print (list "--no-print"))
                       (when check-only (list "--check"))
                       (when save-name (list "--save" save-name))
                       (when generated (list "--generated" generated))))
         (root (file-name-as-directory (kvist--project-root)))
         (display (or display 'buffer)))
    (unwind-protect
        (let* ((default-directory root)
               (exit-code (kvist--call (kvist--executable) args output-buffer t))
               (result (with-current-buffer output-buffer
                         (buffer-substring-no-properties (point-min) (point-max)))))
          (when (and (not no-print)
                     (not check-only)
                     (not (zerop exit-code))
                     (kvist--void-value-error-p result))
            (setq args (append (list "eval" source form "--no-print")
                               (when save-name (list "--save" save-name))
                               (when generated (list "--generated" generated))))
            (setq exit-code (kvist--call (kvist--executable) args output-buffer t))
            (setq result (with-current-buffer output-buffer
                           (buffer-substring-no-properties (point-min) (point-max)))))
          (setq result (kvist--remap-output-source-path result source source-buffer))
          (kvist--show-generated generated)
          (pcase display
            ('inline
             (kvist--show-inline-result (car bounds) (cdr bounds) result exit-code)
             (kvist--message-result result exit-code))
            ('comment
             (kvist--insert-comment-result source-buffer (cdr bounds) result exit-code)
             (kvist--message-result result exit-code))
            (_
             (kvist--display-output output-buffer result exit-code))))
      (when (file-exists-p source)
        (delete-file source))
      (when (and generated (file-exists-p generated))
        (delete-file generated)))))

(defun kvist--buffer-command (command)
  "Run Kvist buffer COMMAND, one of build, check, or run."
  (setq kvist--last-source-buffer (current-buffer))
  (unless buffer-file-name
    (user-error "Kvist %s requires a file-backed buffer" command))
  (save-buffer)
  (let* ((source-buffer (current-buffer))
         (source (expand-file-name buffer-file-name))
         (generated (when kvist-show-generated
                      (make-temp-file "kvist-buffer-" nil ".odin")))
         (output-buffer (kvist--prepare-diagnostic-buffer kvist-result-buffer-name))
         (root (file-name-as-directory (kvist--project-root source))))
    (unwind-protect
        (let* ((default-directory root)
               (args (append (list command source)
                             (when generated (list "--generated" generated))))
               (exit-code (kvist--call (kvist--executable source) args output-buffer t))
               (result (with-current-buffer output-buffer
                         (buffer-substring-no-properties (point-min) (point-max)))))
          (setq result (kvist--remap-output-source-path result source source-buffer))
          (kvist--show-generated generated)
          (if (zerop exit-code)
              (let ((trimmed (kvist--trim-output result)))
                (message "%s"
                         (if (string-empty-p trimmed)
                             (format "kvist %s: ok" command)
                           trimmed)))
            (kvist--display-output output-buffer result exit-code t)))
      (when (and generated (file-exists-p generated))
        (delete-file generated)))))

(defun kvist--test-import-aliases ()
  "Return likely aliases used for `kvist:test' in the current buffer."
  (let ((aliases '("t")))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward
              "^[[:space:]]*(import\\(?:[[:space:]\n]+\\([[:word:]!?+._/-]+\\)\\)?[[:space:]\n]+\"kvist:test\")"
              nil t)
        (let ((alias (match-string-no-properties 1)))
          (when (and alias (not (member alias aliases)))
            (push alias aliases)))))
    aliases))

(defun kvist--deftest-name-at-point ()
  "Return the enclosing Kvist test name at point."
  (save-excursion
    (let ((aliases (kvist--test-import-aliases))
          found)
      (condition-case nil
          (while (not found)
            (backward-up-list)
            (let ((beg (point))
                  (end (scan-sexps (point) 1)))
              (when (and beg end)
                (let ((form (buffer-substring-no-properties
                             beg
                             (min end (+ beg 200)))))
                  (when (or (string-match
                             (concat "\\`[[:space:]\n]*(deftest\\_>[[:space:]\n]+\\([[:word:]!?+._/-]+\\)") form)
                            (cl-some
                             (lambda (alias)
                               (string-match
                                (format "\\`[[:space:]\n]*(%s/deftest\\_>[[:space:]\n]+\\([[:word:]!?+._/-]+\\)" (regexp-quote alias))
                                form))
                             aliases))
                    (setq found (match-string 1 form)))))))
        (error nil))
      found)))

(defun kvist--package-entry-file (&optional file)
  "Return the package entry file for FILE or the current buffer."
  (let* ((file (expand-file-name (or file (or buffer-file-name default-directory))))
         (dir (if (file-directory-p file) file (file-name-directory file)))
         (dir-entry (expand-file-name
                     (concat (file-name-nondirectory (directory-file-name dir)) ".kvist")
                     dir))
         (main-entry (expand-file-name "main.kvist" dir)))
    (cond
     ((file-exists-p dir-entry) dir-entry)
     ((file-exists-p main-entry) main-entry)
     (t file))))

(defun kvist--project-test-entry-files ()
  "Return deduplicated package entry files that use `kvist:test'."
  (let* ((root (file-name-as-directory (kvist--project-root)))
         (matches (directory-files-recursively root "\\.kvist\\'"))
         (entries nil))
    (dolist (match matches)
      (when (with-temp-buffer
              (insert-file-contents match)
              (and (re-search-forward "kvist:test" nil t)
                   (re-search-forward "(\\(?:[[:word:]!?+._/-]+/\\)?deftest\\_>" nil t)))
        (let ((entry (kvist--package-entry-file match)))
          (when (and (file-exists-p entry)
                     (not (member entry entries)))
            (push entry entries)))))
    (nreverse entries)))

(defun kvist--test-command-string (file &optional names)
  "Return a shell command string for `kvist test' on FILE and optional NAMES."
  (mapconcat
   #'identity
   (append
    (list (shell-quote-argument (kvist--executable))
          "test"
          (shell-quote-argument file))
    (when names
      (list "--names" (shell-quote-argument names))))
   " "))

(defun kvist--start-test-compilation (command)
  "Run test COMMAND in a compilation buffer."
  (let ((default-directory (file-name-as-directory (kvist--project-root))))
    (compilation-start command 'compilation-mode
                       (lambda (_) kvist-test-buffer-name))))

(defun kvist--file-label (source-file)
  "Return a readable project-relative label for SOURCE-FILE."
  (let* ((root (file-name-as-directory (kvist--project-root source-file)))
         (file (expand-file-name source-file)))
    (if (string-prefix-p root file)
        (file-relative-name file root)
      (file-name-nondirectory file))))

(defun kvist--run-buffer-instance-name (source-file)
  "Return a readable run buffer name for SOURCE-FILE."
  (format "%s<%s>" kvist-run-buffer-name (kvist--file-label source-file)))

(defun kvist--buffer-command-string (command file &optional generated)
  "Return a shell command string for Kvist COMMAND on FILE.
When GENERATED is non-nil, include `--generated GENERATED'."
  (mapconcat
   #'identity
   (append
    (list (shell-quote-argument (kvist--executable file))
          command
          (shell-quote-argument file))
    (when generated
      (list "--generated" (shell-quote-argument generated))))
   " "))

(defun kvist--start-buffer-run ()
  "Run the current Kvist buffer asynchronously in a compilation buffer."
  (setq kvist--last-source-buffer (current-buffer))
  (unless buffer-file-name
    (user-error "Kvist run requires a file-backed buffer"))
  (save-buffer)
  (let* ((source-file (expand-file-name buffer-file-name))
         (default-directory (file-name-as-directory (kvist--project-root source-file)))
         (command (kvist--buffer-command-string "run" source-file))
         (buffer-name (kvist--run-buffer-instance-name source-file)))
    (compilation-start command 'compilation-mode
                       (lambda (_) buffer-name))
    (message "Started plain Kvist run in %s" buffer-name)))

(defun kvist--project-test-command ()
  "Return a shell command string that runs all project Kvist tests."
  (let ((entries (kvist--project-test-entry-files)))
    (unless entries
      (user-error "No Kvist test packages found in project"))
    (mapconcat
     (lambda (entry)
       (kvist--test-command-string entry))
     entries
     " && ")))

;;;###autoload
(defun kvist-expand-form-at-point (&optional no-print)
  "Show generated Odin for the form at point.
With prefix argument NO-PRINT, lower the form as a statement."
  (interactive "P")
  (setq kvist--last-source-buffer (current-buffer))
  (let* ((bounds (kvist--form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (source (kvist--source-temp-file))
         (generated-buffer (kvist--prepare-buffer kvist-generated-buffer-name))
         (result-buffer (kvist--prepare-buffer kvist-result-buffer-name))
         (args (append (list "expand" source form)
                       (when no-print (list "--no-print"))))
         (root (file-name-as-directory (kvist--project-root))))
    (unwind-protect
        (let* ((default-directory root)
               (exit-code (kvist--call (kvist--executable) args generated-buffer))
               (result (with-current-buffer generated-buffer
                         (buffer-substring-no-properties (point-min) (point-max)))))
          (if (zerop exit-code)
              (progn
                (display-buffer generated-buffer)
                (message "kvist expand: ok"))
            (kvist--display-output result-buffer result exit-code)))
      (when (file-exists-p source)
        (delete-file source)))))

;;;###autoload
(defun kvist-macroexpand-form-at-point ()
  "Show Kvist macro expansion for the form at point."
  (interactive)
  (setq kvist--last-source-buffer (current-buffer))
  (let* ((bounds (kvist--form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (source (kvist--source-temp-file))
         (macro-buffer (kvist--prepare-buffer kvist-macroexpand-buffer-name))
         (result-buffer (kvist--prepare-buffer kvist-result-buffer-name))
         (args (list "macroexpand" source form))
         (root (file-name-as-directory (kvist--project-root))))
    (unwind-protect
        (let* ((default-directory root)
               (exit-code (kvist--call (kvist--executable) args macro-buffer))
               (result (with-current-buffer macro-buffer
                         (buffer-substring-no-properties (point-min) (point-max)))))
          (if (zerop exit-code)
              (progn
                (display-buffer macro-buffer)
                (message "kvist macroexpand: ok"))
            (kvist--display-output result-buffer result exit-code)))
      (when (file-exists-p source)
        (delete-file source)))))

;;;###autoload
(defun kvist-eval-form-at-point (&optional no-print)
  "Evaluate the Kvist form at point and show the result inline.
With prefix argument NO-PRINT, treat the form as a statement."
  (interactive "P")
  (let* ((bounds (kvist--form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (declaration (kvist--declaration-form-string-p form)))
    (kvist--eval-string
     form
     (or no-print kvist-default-no-print)
     declaration
     'inline
     bounds)))

;;;###autoload
(defun kvist-popup-form-at-point (&optional no-print)
  "Evaluate the Kvist form at point and show the result buffer."
  (interactive "P")
  (let* ((bounds (kvist--form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (declaration (kvist--declaration-form-string-p form)))
    (kvist--eval-string
     form
     (or no-print kvist-default-no-print)
     declaration
     'buffer
     bounds)))

;;;###autoload
(defun kvist-insert-form-result (&optional no-print)
  "Evaluate the Kvist form at point and insert its result as a ;; => comment."
  (interactive "P")
  (let* ((bounds (kvist--form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (declaration (kvist--declaration-form-string-p form)))
    (kvist--eval-string
     form
     (or no-print kvist-default-no-print)
     declaration
     'comment
     bounds)))

;;;###autoload
(defun kvist-save-form-result (name &optional no-print)
  "Evaluate the Kvist form at point and save stdout to cache NAME.
With prefix argument NO-PRINT, treat the form as a statement."
  (interactive (list (kvist--cache-name-prompt "Save Kvist eval output as: ")
                     current-prefix-arg))
  (let* ((bounds (kvist--form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds))))
    (when (kvist--declaration-form-string-p form)
      (user-error "Declaration forms can be checked, but their eval output cannot be saved"))
    (kvist--eval-string
     form
     (or no-print kvist-default-no-print)
     nil
     'inline
     bounds
     name)))

;;;###autoload
(defun kvist-eval-region (beg end &optional no-print)
  "Evaluate the Kvist region from BEG to END.
With prefix argument NO-PRINT, treat the region as a statement."
  (interactive "r\nP")
  (kvist--eval-string
   (buffer-substring-no-properties beg end)
   (or no-print kvist-default-no-print)
   nil
   'buffer
   (cons beg end)))

;;;###autoload
(defun kvist-eval-top-level-form (&optional no-print)
  "Evaluate the current top-level Kvist form and show the result inline.
With prefix argument NO-PRINT, treat the form as a statement."
  (interactive "P")
  (let* ((bounds (kvist--top-level-bounds))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (declaration (kvist--declaration-form-string-p form)))
    (kvist--eval-string
     form
     (or no-print kvist-default-no-print)
     declaration
     'inline
     bounds)))

;;;###autoload
(defun kvist-eval-comment-form (&optional no-print)
  "Evaluate the body of the enclosing `(comment ...)' form as statements."
  (interactive "P")
  (let ((bounds (kvist--enclosing-comment-form-bounds)))
    (kvist--eval-string
     (kvist--comment-form-code)
     (or no-print kvist-default-no-print t)
     nil
     'inline
     bounds)))

;;;###autoload
(defun kvist-insert-comment-form-result (&optional no-print)
  "Evaluate the enclosing `(comment ...)' body and insert a ;; => comment."
  (interactive "P")
  (let ((bounds (kvist--enclosing-comment-form-bounds)))
    (kvist--eval-string
     (kvist--comment-form-code)
     (or no-print kvist-default-no-print t)
     nil
     'comment
     bounds)))

;;;###autoload
(defun kvist-check-form-at-point (&optional no-print)
  "Compile-check the generated Odin for the form at point."
  (interactive "P")
  (let ((bounds (kvist--form-bounds-at-point)))
    (kvist--eval-string
     (buffer-substring-no-properties (car bounds) (cdr bounds))
     (or no-print kvist-default-no-print)
     t
     'buffer
     bounds)))

;;;###autoload
(defun kvist-check-region (beg end &optional no-print)
  "Compile-check the generated Odin for the selected region."
  (interactive "r\nP")
  (kvist--eval-string
   (buffer-substring-no-properties beg end)
   (or no-print kvist-default-no-print)
   t
   'buffer
   (cons beg end)))

;;;###autoload
(defun kvist-check-buffer ()
  "Compile the current Kvist buffer and run `odin check' on generated Odin."
  (interactive)
  (kvist--buffer-command "check"))

;;;###autoload
(defun kvist-eval-buffer ()
  "Compile the current Kvist buffer and check generated Odin."
  (interactive)
  (kvist--buffer-command "check"))

;;;###autoload
(defun kvist-build-buffer ()
  "Compile the current Kvist buffer and run `odin build' on generated Odin."
  (interactive)
  (kvist--buffer-command "build"))

;;;###autoload
(defun kvist-run-buffer ()
  "Run the current Kvist buffer asynchronously in a compilation buffer."
  (interactive)
  (kvist--start-buffer-run))

;;;###autoload
(defun kvist-test-at-point ()
  "Run the Kvist test at point."
  (interactive)
  (let ((name (or (kvist--deftest-name-at-point)
                  (user-error "Point is not inside a t/deftest form"))))
    (kvist--start-test-compilation
     (kvist--test-command-string (kvist--package-entry-file) name))))

;;;###autoload
(defun kvist-test-package ()
  "Run Kvist tests for the current package."
  (interactive)
  (kvist--start-test-compilation
   (kvist--test-command-string (kvist--package-entry-file))))

;;;###autoload
(defun kvist-test-project ()
  "Run all Kvist test packages in the current project."
  (interactive)
  (kvist--start-test-compilation
   (kvist--project-test-command)))

;;;###autoload
(defun kvist-toggle-show-generated ()
  "Toggle whether Kvist eval shows generated Odin."
  (interactive)
  (setq kvist-show-generated (not kvist-show-generated))
  (message "kvist-show-generated: %s" kvist-show-generated))

;;;###autoload
(defun kvist-cache-list ()
  "List names in the Kvist eval cache."
  (interactive)
  (kvist--cache-command (list "list") t))

;;;###autoload
(defun kvist-cache-path (name)
  "Show the cache file path for NAME."
  (interactive (list (kvist--cache-name-prompt "Kvist cache name: ")))
  (let* ((result (kvist--cache-command (list "path" name)))
         (exit-code (car result))
         (path (string-trim (cdr result))))
    (when (zerop exit-code)
      (kill-new path)
      (message "%s" path))))

;;;###autoload
(defun kvist-cache-open (name)
  "Open the cache file for NAME."
  (interactive (list (kvist--cache-name-prompt "Open Kvist cache name: ")))
  (let* ((result (kvist--cache-command (list "path" name)))
         (exit-code (car result))
         (path (string-trim (cdr result))))
    (when (zerop exit-code)
      (if (file-exists-p path)
          (find-file-other-window path)
        (user-error "No cached value named %s" name)))))

;;;###autoload
(defun kvist-cache-rm (name)
  "Remove cached value NAME."
  (interactive (list (kvist--cache-name-prompt "Remove Kvist cache name: ")))
  (let ((result (kvist--cache-command (list "rm" name))))
    (when (zerop (car result))
      (message "Removed Kvist cache value: %s" name))))

;;;###autoload
(defun kvist-switch-to-result ()
  "Display the Kvist result buffer."
  (interactive)
  (pop-to-buffer kvist-result-buffer-name))

;;;###autoload
(defun kvist-switch-to-source ()
  "Return to the most recent Kvist source buffer."
  (interactive)
  (if (buffer-live-p kvist--last-source-buffer)
      (pop-to-buffer kvist--last-source-buffer)
    (message "No Kvist source buffer recorded.")))

;;;###autoload
(defun kvist-setup-mode-keys ()
  "Install default Kvist eval key bindings in the current Kvist buffer."
  (when (and (bound-and-true-p cider-mode)
             (fboundp 'cider-mode))
    (cider-mode -1))
  (when (and (bound-and-true-p clj-refactor-mode)
             (fboundp 'clj-refactor-mode))
    (clj-refactor-mode -1))
  (kvist--enable-inline-result-clearing)
  (kvist-eval-mode 1)
  (local-set-key (kbd "C-c C-e") #'kvist-eval-form-at-point)
  (local-set-key (kbd "C-c C-p") #'kvist-popup-form-at-point)
  (local-set-key (kbd "C-c C-i") #'kvist-insert-form-result)
  (local-set-key (kbd "C-c C-r") #'kvist-eval-region)
  (local-set-key (kbd "C-c C-c") #'kvist-eval-top-level-form)
  (local-set-key (kbd "C-c C-x") #'kvist-eval-comment-form)
  (local-set-key (kbd "C-c C-k") #'kvist-eval-buffer)
  (local-set-key (kbd "C-c C-a") #'kvist-run-buffer)
  (local-set-key (kbd "C-c C-b") #'kvist-build-buffer)
  (local-set-key (kbd "C-c C-v") #'kvist-check-buffer)
  (local-set-key (kbd "C-c C-m") #'kvist-expand-form-at-point)
  (local-set-key (kbd "C-c M-m") #'kvist-macroexpand-form-at-point)
  (local-set-key (kbd "C-c C-s") #'kvist-toggle-show-generated)
  (local-set-key (kbd "C-c d") #'kvist-doc-at-point)
  (local-set-key (kbd "C-c C-d") #'kvist-doc-at-point)
  (local-set-key (kbd "C-c C-w") #'kvist-save-form-result)
  (local-set-key (kbd "C-c C-l") #'kvist-cache-list)
  (local-set-key (kbd "C-c C-o") #'kvist-cache-open)
  (local-set-key (kbd "C-c M-d") #'kvist-cache-rm)
  (local-set-key (kbd "C-c C-z") #'kvist-switch-to-result)
  (local-set-key (kbd "C-c t t") #'kvist-test-at-point)
  (local-set-key (kbd "C-c t p") #'kvist-test-package)
  (local-set-key (kbd "C-c t a") #'kvist-test-project))

(add-hook 'kvist-mode-hook #'kvist-setup-mode-keys)

(provide 'kvist-eval)

;;; kvist-eval.el ends here
