;;; odinl-eval.el --- REPL-like eval helpers for OdinL -*- lexical-binding: t; -*-

;; This shells out to odinl.  It does not interpret OdinL and it does not
;; maintain hidden runtime state.

(require 'subr-x)
(require 'odinl-mode)

(defcustom odinl-command "odinl"
  "Fallback OdinL executable used when no local checkout binary is found."
  :type 'string
  :group 'odinl)

(defcustom odinl-result-buffer-name "*OdinL Eval*"
  "Buffer name used for OdinL eval output."
  :type 'string
  :group 'odinl)

(defcustom odinl-generated-buffer-name "*OdinL Generated*"
  "Buffer name used to show generated Odin."
  :type 'string
  :group 'odinl)

(defcustom odinl-macroexpand-buffer-name "*OdinL Macroexpand*"
  "Buffer name used to show OdinL macro expansion output."
  :type 'string
  :group 'odinl)

(defcustom odinl-inline-result-prefix "=> "
  "Prefix used for inline OdinL eval overlays."
  :type 'string
  :group 'odinl)

(defcustom odinl-show-generated nil
  "When non-nil, show generated Odin for eval commands."
  :type 'boolean
  :group 'odinl)

(defcustom odinl-default-no-print nil
  "When non-nil, default eval commands run snippets as statements."
  :type 'boolean
  :group 'odinl)

(defconst odinl-declaration-heads
  '("comment" "package" "import" "const" "struct" "enum" "union" "odin" "proc")
  "OdinL forms that are declarations at top level.")

(defvar odinl--last-source-buffer nil)

(defvar odinl-eval-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-e") #'odinl-eval-form-at-point)
    (define-key map (kbd "C-c C-p") #'odinl-popup-form-at-point)
    (define-key map (kbd "C-c C-i") #'odinl-insert-form-result)
    (define-key map (kbd "C-c C-r") #'odinl-eval-region)
    (define-key map (kbd "C-c C-c") #'odinl-eval-top-level-form)
    (define-key map (kbd "C-c C-x") #'odinl-eval-comment-form)
    (define-key map (kbd "C-c C-k") #'odinl-eval-buffer)
    (define-key map (kbd "C-c C-a") #'odinl-run-buffer)
    (define-key map (kbd "C-c C-b") #'odinl-build-buffer)
    (define-key map (kbd "C-c C-v") #'odinl-check-buffer)
    (define-key map (kbd "C-c C-m") #'odinl-expand-form-at-point)
    (define-key map (kbd "C-c M-m") #'odinl-macroexpand-form-at-point)
    (define-key map (kbd "C-c C-s") #'odinl-toggle-show-generated)
    (define-key map (kbd "C-c C-z") #'odinl-switch-to-result)
    map)
  "Keymap for `odinl-eval-mode'.")

;;;###autoload
(define-minor-mode odinl-eval-mode
  "Minor mode for OdinL eval keybindings."
  :lighter " OdinL-Eval"
  :keymap odinl-eval-mode-map)

(defun odinl-clear-inline-results ()
  "Delete OdinL inline result overlays in the current buffer."
  (remove-overlays (point-min) (point-max) 'odinl-result-overlay t))

(defun odinl--enable-inline-result-clearing ()
  "Clear OdinL overlays before the next command in this buffer."
  (add-hook 'pre-command-hook #'odinl-clear-inline-results nil t))

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
         (local (expand-file-name "odinl" root))
         (fallback (executable-find odinl-command)))
    (cond
     ((file-executable-p local) local)
     (fallback fallback)
     (t (error "Could not find odinl executable; run `odin build cmd/odinl'")))))

(defun odinl--prepare-buffer (name)
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

(defun odinl--source-temp-file ()
  "Write current buffer to a temporary .odinl file near the source file."
  (unless buffer-file-name
    (user-error "OdinL eval requires a file-backed buffer"))
  (let* ((dir (file-name-directory (expand-file-name buffer-file-name)))
         (temp (make-temp-file (expand-file-name ".odinl-eval-" dir) nil ".odinl")))
    (write-region (point-min) (point-max) temp nil 'silent)
    temp))

(defun odinl--call (program args output-buffer)
  "Call PROGRAM with ARGS, writing output to OUTPUT-BUFFER."
  (with-current-buffer output-buffer
    (let ((inhibit-read-only t)
          (buffer-read-only nil))
      (erase-buffer)
      (prog1
          (apply #'call-process program nil t nil args)
        (goto-char (point-min))
        (special-mode)
        (setq-local truncate-lines nil)
        (setq-local word-wrap t)
        (visual-line-mode 1)))))

(defun odinl--sexp-bounds-near-point ()
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

(defun odinl--form-bounds-at-point ()
  "Return bounds of the form at or immediately before point."
  (or (odinl--sexp-bounds-near-point)
      (bounds-of-thing-at-point 'sexp)
      (user-error "No form at point")))

(defun odinl--declaration-form-string-p (form)
  "Return non-nil when FORM text starts with an OdinL declaration head."
  (when (string-match "\\`[[:space:]]*(\\([[:word:]!?._+-]+\\)" form)
    (member (match-string 1 form) odinl-declaration-heads)))

(defun odinl--top-level-bounds ()
  "Return bounds of the current top-level form."
  (save-excursion
    (beginning-of-defun)
    (let ((beg (point)))
      (end-of-defun)
      (cons beg (point)))))

(defun odinl--enclosing-comment-form-bounds ()
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

(defun odinl--comment-form-code ()
  "Return a statement form for the body of the enclosing `(comment ...)' form."
  (let ((bounds (odinl--enclosing-comment-form-bounds)))
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

(defun odinl--show-generated (generated)
  "Show GENERATED Odin in `odinl-generated-buffer-name'."
  (when (and odinl-show-generated generated (file-exists-p generated))
    (let ((buffer (odinl--prepare-buffer odinl-generated-buffer-name)))
      (with-current-buffer buffer
        (let ((inhibit-read-only t)
              (buffer-read-only nil))
          (erase-buffer)
          (insert-file-contents generated)
          (when (fboundp 'odin-mode)
            (odin-mode))))
      (display-buffer buffer))))

(defun odinl--trim-output (text)
  "Trim TEXT for minibuffer and inline display."
  (string-trim (replace-regexp-in-string "[ \t\n\r]+" " " text)))

(defun odinl--show-inline-result (beg end text exit-code)
  "Show TEXT inline after BEG and END."
  (remove-overlays beg end 'odinl-result-overlay t)
  (let* ((trimmed (string-trim text))
         (display-text (if (string-empty-p trimmed)
                           (format " %s%s" odinl-inline-result-prefix
                                   (if (zerop exit-code) "ok" (format "<exit %s>" exit-code)))
                         (format " %s%s" odinl-inline-result-prefix
                                 (replace-regexp-in-string "[\n\r\t ]+" " " trimmed))))
         (ov (make-overlay beg end)))
    (put-text-property 0 1 'cursor 0 display-text)
    (put-text-property 0 (length display-text) 'face
                       (if (zerop exit-code) 'shadow 'error)
                       display-text)
    (overlay-put ov 'odinl-result-overlay t)
    (overlay-put ov 'priority 1000)
    (overlay-put ov 'evaporate t)
    (overlay-put ov 'after-string display-text)
    (odinl--enable-inline-result-clearing)))

(defun odinl--message-result (text exit-code)
  "Show a concise minibuffer message for TEXT and EXIT-CODE."
  (let ((trimmed (odinl--trim-output text)))
    (message "%s"
             (cond
              ((not (zerop exit-code))
               (if (string-empty-p trimmed)
                   (format "odinl exited %s" exit-code)
                 trimmed))
              ((string-empty-p trimmed) "")
              (t trimmed)))))

(defun odinl--insert-comment-result (buffer line-end text exit-code)
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

(defun odinl--display-output (output-buffer text exit-code)
  "Display TEXT in OUTPUT-BUFFER with EXIT-CODE."
  (with-current-buffer output-buffer
    (let ((inhibit-read-only t)
          (buffer-read-only nil))
      (erase-buffer)
      (insert (format "$ odinl exited %s\n\n" exit-code))
      (unless (string-empty-p text)
        (insert text)
        (unless (string-suffix-p "\n" text)
          (insert "\n")))
      (goto-char (point-min))
      (special-mode)
      (setq-local truncate-lines nil)
      (setq-local word-wrap t)
      (visual-line-mode 1)))
  (display-buffer output-buffer)
  (message "odinl exited %s" exit-code))

(defun odinl--void-value-error-p (text)
  "Return non-nil when TEXT is Odin's diagnostic for printing a void call."
  (string-match-p "call does not return a value and cannot be used as a value" text))

(defun odinl--main-call-form-p (form)
  "Return non-nil when FORM is a direct `(main)' call."
  (string-match-p "\\`[[:space:]]*(main[[:space:]]*)[[:space:]]*\\'" form))

(defun odinl--eval-string (form &optional no-print check-only display bounds)
  "Evaluate FORM via generated Odin.
When NO-PRINT is non-nil, treat FORM as a statement.  When CHECK-ONLY is
non-nil, run `odin check' instead of `odin run'.  DISPLAY may be `inline',
`comment', or `buffer'."
  (setq odinl--last-source-buffer (current-buffer))
  (let* ((source-buffer (current-buffer))
         (source (odinl--source-temp-file))
         (generated (when odinl-show-generated
                      (make-temp-file "odinl-eval-" nil ".odin")))
         (output-buffer (odinl--prepare-buffer odinl-result-buffer-name))
         (args (append (list "eval" source form)
                       (when no-print (list "--no-print"))
                       (when check-only (list "--check"))
                       (when generated (list "--generated" generated))))
         (root (file-name-as-directory (odinl--project-root)))
         (display (or display 'buffer)))
    (unwind-protect
        (let* ((default-directory root)
               (exit-code (odinl--call (odinl--executable) args output-buffer))
               (result (with-current-buffer output-buffer
                         (buffer-substring-no-properties (point-min) (point-max)))))
          (when (and (not no-print)
                     (not check-only)
                     (not (zerop exit-code))
                     (odinl--void-value-error-p result))
            (setq args (if (odinl--main-call-form-p form)
                           (append (list "run" source)
                                   (when generated (list "--generated" generated)))
                         (append (list "eval" source form "--no-print")
                                 (when generated (list "--generated" generated)))))
            (setq exit-code (odinl--call (odinl--executable) args output-buffer))
            (setq result (with-current-buffer output-buffer
                           (buffer-substring-no-properties (point-min) (point-max)))))
          (odinl--show-generated generated)
          (pcase display
            ('inline
             (odinl--show-inline-result (car bounds) (cdr bounds) result exit-code)
             (odinl--message-result result exit-code))
            ('comment
             (odinl--insert-comment-result source-buffer (cdr bounds) result exit-code)
             (odinl--message-result result exit-code))
            (_
             (odinl--display-output output-buffer result exit-code))))
      (when (file-exists-p source)
        (delete-file source))
      (when (and generated (file-exists-p generated))
        (delete-file generated)))))

(defun odinl--buffer-command (command)
  "Run OdinL buffer COMMAND, one of build, check, or run."
  (setq odinl--last-source-buffer (current-buffer))
  (let* ((source (odinl--source-temp-file))
         (generated (when odinl-show-generated
                      (make-temp-file "odinl-buffer-" nil ".odin")))
         (output-buffer (odinl--prepare-buffer odinl-result-buffer-name))
         (root (file-name-as-directory (odinl--project-root))))
    (unwind-protect
        (let* ((default-directory root)
               (args (append (list command source)
                             (when generated (list "--generated" generated))))
               (exit-code (odinl--call (odinl--executable) args output-buffer))
               (result (with-current-buffer output-buffer
                         (buffer-substring-no-properties (point-min) (point-max)))))
          (odinl--show-generated generated)
          (if (zerop exit-code)
              (let ((trimmed (odinl--trim-output result)))
                (message "%s"
                         (if (string-empty-p trimmed)
                             (format "odinl %s: ok" command)
                           trimmed)))
            (odinl--display-output output-buffer result exit-code)))
      (when (file-exists-p source)
        (delete-file source))
      (when (and generated (file-exists-p generated))
        (delete-file generated)))))

;;;###autoload
(defun odinl-expand-form-at-point (&optional no-print)
  "Show generated Odin for the form at point.
With prefix argument NO-PRINT, lower the form as a statement."
  (interactive "P")
  (setq odinl--last-source-buffer (current-buffer))
  (let* ((bounds (odinl--form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (source (odinl--source-temp-file))
         (generated-buffer (odinl--prepare-buffer odinl-generated-buffer-name))
         (result-buffer (odinl--prepare-buffer odinl-result-buffer-name))
         (args (append (list "expand" source form)
                       (when no-print (list "--no-print"))))
         (root (file-name-as-directory (odinl--project-root))))
    (unwind-protect
        (let* ((default-directory root)
               (exit-code (odinl--call (odinl--executable) args generated-buffer))
               (result (with-current-buffer generated-buffer
                         (buffer-substring-no-properties (point-min) (point-max)))))
          (if (zerop exit-code)
              (progn
                (display-buffer generated-buffer)
                (message "odinl expand: ok"))
            (odinl--display-output result-buffer result exit-code)))
      (when (file-exists-p source)
        (delete-file source)))))

;;;###autoload
(defun odinl-macroexpand-form-at-point ()
  "Show OdinL macro expansion for the form at point."
  (interactive)
  (setq odinl--last-source-buffer (current-buffer))
  (let* ((bounds (odinl--form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (source (odinl--source-temp-file))
         (macro-buffer (odinl--prepare-buffer odinl-macroexpand-buffer-name))
         (result-buffer (odinl--prepare-buffer odinl-result-buffer-name))
         (args (list "macroexpand" source form))
         (root (file-name-as-directory (odinl--project-root))))
    (unwind-protect
        (let* ((default-directory root)
               (exit-code (odinl--call (odinl--executable) args macro-buffer))
               (result (with-current-buffer macro-buffer
                         (buffer-substring-no-properties (point-min) (point-max)))))
          (if (zerop exit-code)
              (progn
                (display-buffer macro-buffer)
                (message "odinl macroexpand: ok"))
            (odinl--display-output result-buffer result exit-code)))
      (when (file-exists-p source)
        (delete-file source)))))

;;;###autoload
(defun odinl-eval-form-at-point (&optional no-print)
  "Evaluate the OdinL form at point and show the result inline.
With prefix argument NO-PRINT, treat the form as a statement."
  (interactive "P")
  (let* ((bounds (odinl--form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (declaration (odinl--declaration-form-string-p form)))
    (odinl--eval-string
     form
     (or no-print odinl-default-no-print)
     declaration
     'inline
     bounds)))

;;;###autoload
(defun odinl-popup-form-at-point (&optional no-print)
  "Evaluate the OdinL form at point and show the result buffer."
  (interactive "P")
  (let* ((bounds (odinl--form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (declaration (odinl--declaration-form-string-p form)))
    (odinl--eval-string
     form
     (or no-print odinl-default-no-print)
     declaration
     'buffer
     bounds)))

;;;###autoload
(defun odinl-insert-form-result (&optional no-print)
  "Evaluate the OdinL form at point and insert its result as a ;; => comment."
  (interactive "P")
  (let* ((bounds (odinl--form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (declaration (odinl--declaration-form-string-p form)))
    (odinl--eval-string
     form
     (or no-print odinl-default-no-print)
     declaration
     'comment
     bounds)))

;;;###autoload
(defun odinl-eval-region (beg end &optional no-print)
  "Evaluate the OdinL region from BEG to END.
With prefix argument NO-PRINT, treat the region as a statement."
  (interactive "r\nP")
  (odinl--eval-string
   (buffer-substring-no-properties beg end)
   (or no-print odinl-default-no-print)
   nil
   'buffer
   (cons beg end)))

;;;###autoload
(defun odinl-eval-top-level-form (&optional no-print)
  "Evaluate the current top-level OdinL form and show the result inline.
With prefix argument NO-PRINT, treat the form as a statement."
  (interactive "P")
  (let* ((bounds (odinl--top-level-bounds))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (declaration (odinl--declaration-form-string-p form)))
    (odinl--eval-string
     form
     (or no-print odinl-default-no-print)
     declaration
     'inline
     bounds)))

;;;###autoload
(defun odinl-eval-comment-form (&optional no-print)
  "Evaluate the body of the enclosing `(comment ...)' form as statements."
  (interactive "P")
  (let ((bounds (odinl--enclosing-comment-form-bounds)))
    (odinl--eval-string
     (odinl--comment-form-code)
     (or no-print odinl-default-no-print t)
     nil
     'inline
     bounds)))

;;;###autoload
(defun odinl-insert-comment-form-result (&optional no-print)
  "Evaluate the enclosing `(comment ...)' body and insert a ;; => comment."
  (interactive "P")
  (let ((bounds (odinl--enclosing-comment-form-bounds)))
    (odinl--eval-string
     (odinl--comment-form-code)
     (or no-print odinl-default-no-print t)
     nil
     'comment
     bounds)))

;;;###autoload
(defun odinl-check-form-at-point (&optional no-print)
  "Compile-check the generated Odin for the form at point."
  (interactive "P")
  (let ((bounds (odinl--form-bounds-at-point)))
    (odinl--eval-string
     (buffer-substring-no-properties (car bounds) (cdr bounds))
     (or no-print odinl-default-no-print)
     t
     'buffer
     bounds)))

;;;###autoload
(defun odinl-check-region (beg end &optional no-print)
  "Compile-check the generated Odin for the selected region."
  (interactive "r\nP")
  (odinl--eval-string
   (buffer-substring-no-properties beg end)
   (or no-print odinl-default-no-print)
   t
   'buffer
   (cons beg end)))

;;;###autoload
(defun odinl-check-buffer ()
  "Compile the current OdinL buffer and run `odin check' on generated Odin."
  (interactive)
  (odinl--buffer-command "check"))

;;;###autoload
(defun odinl-eval-buffer ()
  "Compile the current OdinL buffer and check generated Odin."
  (interactive)
  (odinl--buffer-command "check"))

;;;###autoload
(defun odinl-build-buffer ()
  "Compile the current OdinL buffer and run `odin build' on generated Odin."
  (interactive)
  (odinl--buffer-command "build"))

;;;###autoload
(defun odinl-run-buffer ()
  "Compile the current OdinL buffer and run generated Odin."
  (interactive)
  (odinl--buffer-command "run"))

;;;###autoload
(defun odinl-toggle-show-generated ()
  "Toggle whether OdinL eval shows generated Odin."
  (interactive)
  (setq odinl-show-generated (not odinl-show-generated))
  (message "odinl-show-generated: %s" odinl-show-generated))

;;;###autoload
(defun odinl-switch-to-result ()
  "Display the OdinL result buffer."
  (interactive)
  (pop-to-buffer odinl-result-buffer-name))

;;;###autoload
(defun odinl-switch-to-source ()
  "Return to the most recent OdinL source buffer."
  (interactive)
  (if (buffer-live-p odinl--last-source-buffer)
      (pop-to-buffer odinl--last-source-buffer)
    (message "No OdinL source buffer recorded.")))

;;;###autoload
(defun odinl-setup-mode-keys ()
  "Install default OdinL eval key bindings in the current OdinL buffer."
  (when (and (bound-and-true-p cider-mode)
             (fboundp 'cider-mode))
    (cider-mode -1))
  (when (and (bound-and-true-p clj-refactor-mode)
             (fboundp 'clj-refactor-mode))
    (clj-refactor-mode -1))
  (odinl--enable-inline-result-clearing)
  (odinl-eval-mode 1)
  (local-set-key (kbd "C-c C-e") #'odinl-eval-form-at-point)
  (local-set-key (kbd "C-c C-p") #'odinl-popup-form-at-point)
  (local-set-key (kbd "C-c C-i") #'odinl-insert-form-result)
  (local-set-key (kbd "C-c C-r") #'odinl-eval-region)
  (local-set-key (kbd "C-c C-c") #'odinl-eval-top-level-form)
  (local-set-key (kbd "C-c C-x") #'odinl-eval-comment-form)
  (local-set-key (kbd "C-c C-k") #'odinl-eval-buffer)
  (local-set-key (kbd "C-c C-a") #'odinl-run-buffer)
  (local-set-key (kbd "C-c C-b") #'odinl-build-buffer)
  (local-set-key (kbd "C-c C-v") #'odinl-check-buffer)
  (local-set-key (kbd "C-c C-m") #'odinl-expand-form-at-point)
  (local-set-key (kbd "C-c M-m") #'odinl-macroexpand-form-at-point)
  (local-set-key (kbd "C-c C-s") #'odinl-toggle-show-generated)
  (local-set-key (kbd "C-c C-z") #'odinl-switch-to-result))

(add-hook 'odinl-mode-hook #'odinl-setup-mode-keys)

(provide 'odinl-eval)

;;; odinl-eval.el ends here
