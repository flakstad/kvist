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

(defcustom odinl-inline-result-prefix "=> "
  "Prefix used for inline OdinL eval overlays."
  :type 'string
  :group 'odinl)

(defcustom odinl-show-generated nil
  "When non-nil, show generated Odin for eval commands."
  :type 'boolean
  :group 'odinl)

(defvar odinl--last-source-buffer nil)

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
      (let ((inhibit-read-only t))
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
    (let ((inhibit-read-only t))
      (erase-buffer)))
  (apply #'call-process program nil output-buffer nil args))

(defun odinl--form-bounds-at-point ()
  "Return bounds of the form at point."
  (or (bounds-of-thing-at-point 'sexp)
      (user-error "No form at point")))

(defun odinl--form-at-point-string ()
  "Return the source text for the form at point."
  (let ((bounds (odinl--form-bounds-at-point)))
    (buffer-substring-no-properties (car bounds) (cdr bounds))))

(defun odinl--top-level-bounds ()
  "Return bounds of the current top-level form."
  (save-excursion
    (beginning-of-defun)
    (let ((beg (point)))
      (end-of-defun)
      (cons beg (point)))))

(defun odinl--show-generated (generated)
  "Show GENERATED Odin in `odinl-generated-buffer-name'."
  (when (and odinl-show-generated generated (file-exists-p generated))
    (let ((buffer (odinl--prepare-buffer odinl-generated-buffer-name)))
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (insert-file-contents generated)))
      (display-buffer buffer))))

(defun odinl--trim-output (text)
  "Trim TEXT for minibuffer and inline display."
  (string-trim (replace-regexp-in-string "[ \t\n\r]+" " " text)))

(defun odinl--show-inline-result (end text)
  "Show TEXT inline after END."
  (let ((trimmed (odinl--trim-output text)))
    (unless (string-empty-p trimmed)
      (dolist (ov (overlays-at end))
        (when (overlay-get ov 'odinl-result-overlay)
          (delete-overlay ov)))
      (let* ((start (if (> end (point-min)) (1- end) end))
             (finish (if (> end (point-min)) end (min (point-max) (1+ end))))
             (ov (make-overlay start finish)))
        (overlay-put ov 'odinl-result-overlay t)
        (overlay-put ov 'priority 1000)
        (overlay-put ov 'evaporate t)
        (overlay-put ov 'after-string
                     (propertize (concat " " odinl-inline-result-prefix trimmed)
                                 'face 'shadow))
        (odinl--enable-inline-result-clearing)))))

(defun odinl--eval-string (form &optional no-print check-only inline-end)
  "Evaluate FORM via generated Odin.
When NO-PRINT is non-nil, treat FORM as a statement.  When CHECK-ONLY is
non-nil, run `odin check' instead of `odin run'.  If INLINE-END is non-nil,
show the result inline at that position."
  (setq odinl--last-source-buffer (current-buffer))
  (let* ((source (odinl--source-temp-file))
         (generated (when odinl-show-generated
                      (make-temp-file "odinl-eval-" nil ".odin")))
         (output-buffer (odinl--prepare-buffer odinl-result-buffer-name))
         (args (append (list "eval" source form)
                       (when no-print (list "--no-print"))
                       (when check-only (list "--check"))
                       (when generated (list "--generated" generated))))
         (root (file-name-as-directory (odinl--project-root))))
    (unwind-protect
        (let ((default-directory root)
              (exit-code nil))
          (setq exit-code (odinl--call (odinl--executable) args output-buffer))
          (odinl--show-generated generated)
          (let ((result (with-current-buffer output-buffer
                          (buffer-substring-no-properties (point-min) (point-max)))))
            (if (zerop exit-code)
                (progn
                  (if inline-end
                      (odinl--show-inline-result inline-end result)
                    (message "%s" (odinl--trim-output result)))
                  (unless inline-end
                    (display-buffer output-buffer)))
              (display-buffer output-buffer)
              (message "%s" (odinl--trim-output result)))))
      (when (file-exists-p source)
        (delete-file source))
      (when (and generated (file-exists-p generated))
        (delete-file generated)))))

(defun odinl--compile-buffer-command (run)
  "Compile the current OdinL buffer, then check or run generated Odin.
When RUN is non-nil, run the generated file.  Otherwise run `odin check'."
  (setq odinl--last-source-buffer (current-buffer))
  (let* ((source (odinl--source-temp-file))
         (generated (when odinl-show-generated
                      (make-temp-file "odinl-buffer-" nil ".odin")))
         (output-buffer (odinl--prepare-buffer odinl-result-buffer-name))
         (root (file-name-as-directory (odinl--project-root))))
    (unwind-protect
        (let* ((default-directory root)
               (command (if run "run" "check"))
               (args (append (list command source)
                             (when generated (list "--generated" generated))))
               (exit-code nil))
          (setq exit-code (odinl--call (odinl--executable) args output-buffer))
          (odinl--show-generated generated)
          (if (zerop exit-code)
              (let ((result (with-current-buffer output-buffer
                              (buffer-substring-no-properties (point-min) (point-max)))))
                (message "%s"
                         (let ((trimmed (odinl--trim-output result)))
                           (if (string-empty-p trimmed)
                               (if run "odinl run: ok" "odinl check: ok")
                             trimmed))))
            (let ((result (with-current-buffer output-buffer
                            (buffer-substring-no-properties (point-min) (point-max)))))
              (display-buffer output-buffer)
              (message "%s" (odinl--trim-output result)))))
      (when (file-exists-p source)
        (delete-file source))
      (when (and generated (file-exists-p generated))
        (delete-file generated)))))

;;;###autoload
(defun odinl-eval-form-at-point (&optional no-print)
  "Evaluate the OdinL form at point and show the result inline.
With prefix argument NO-PRINT, treat the form as a statement."
  (interactive "P")
  (let ((bounds (odinl--form-bounds-at-point)))
    (odinl--eval-string
     (buffer-substring-no-properties (car bounds) (cdr bounds))
     no-print
     nil
     (cdr bounds))))

;;;###autoload
(defun odinl-eval-region (beg end &optional no-print)
  "Evaluate the OdinL region from BEG to END.
With prefix argument NO-PRINT, treat the region as a statement."
  (interactive "r\nP")
  (odinl--eval-string (buffer-substring-no-properties beg end) no-print nil end))

;;;###autoload
(defun odinl-eval-top-level-form (&optional no-print)
  "Evaluate the current top-level OdinL form and show the result inline.
With prefix argument NO-PRINT, treat the form as a statement."
  (interactive "P")
  (let ((bounds (odinl--top-level-bounds)))
    (odinl--eval-string
     (buffer-substring-no-properties (car bounds) (cdr bounds))
     no-print
     nil
     (cdr bounds))))

;;;###autoload
(defun odinl-check-form-at-point ()
  "Compile-check the generated Odin for the form at point."
  (interactive)
  (let ((bounds (odinl--form-bounds-at-point)))
    (odinl--eval-string
     (buffer-substring-no-properties (car bounds) (cdr bounds))
     nil
     t
     nil)))

;;;###autoload
(defun odinl-check-buffer ()
  "Compile the current OdinL buffer and run `odin check' on generated Odin."
  (interactive)
  (odinl--compile-buffer-command nil))

;;;###autoload
(defun odinl-run-buffer ()
  "Compile the current OdinL buffer and run generated Odin."
  (interactive)
  (odinl--compile-buffer-command t))

;;;###autoload
(defun odinl-toggle-show-generated ()
  "Toggle whether OdinL eval shows generated Odin."
  (interactive)
  (setq odinl-show-generated (not odinl-show-generated))
  (message "odinl-show-generated %s" (if odinl-show-generated "enabled" "disabled")))

;;;###autoload
(defun odinl-setup-mode-keys ()
  "Install default OdinL eval key bindings in `odinl-mode-map'."
  (define-key odinl-mode-map (kbd "C-c C-e") #'odinl-eval-form-at-point)
  (define-key odinl-mode-map (kbd "C-c C-c") #'odinl-eval-top-level-form)
  (define-key odinl-mode-map (kbd "C-c C-r") #'odinl-eval-region)
  (define-key odinl-mode-map (kbd "C-c C-k") #'odinl-check-form-at-point)
  (define-key odinl-mode-map (kbd "C-c C-v") #'odinl-check-buffer)
  (define-key odinl-mode-map (kbd "C-c C-a") #'odinl-run-buffer)
  (define-key odinl-mode-map (kbd "C-c C-s") #'odinl-toggle-show-generated)
  (define-key odinl-mode-map (kbd "C-c C-z")
              (lambda ()
                (interactive)
                (pop-to-buffer odinl-result-buffer-name))))

(with-eval-after-load 'odinl-mode
  (odinl-setup-mode-keys))

(provide 'odinl-eval)

;;; odinl-eval.el ends here
