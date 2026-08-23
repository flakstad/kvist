;;; kvist-eval.el --- REPL-like eval helpers for Kvist -*- lexical-binding: t; -*-
;; Copyright (c) Andreas Flakstad and Kvist contributors
;; SPDX-License-Identifier: MIT

;; Interactive evaluation uses the generic native JSONL REPL protocol.
;; Build, check, run, test, and cache commands remain hermetic CLI operations.

(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'subr-x)
(require 'compile)
(require 'kvist-mode)

(defcustom kvist-result-buffer-name "*Kvist Eval*"
  "Buffer name used for Kvist eval output."
  :type 'string
  :group 'kvist)

(defcustom kvist-repl-buffer-name "*Kvist REPL*"
  "Base name used for interactive Kvist REPL buffers."
  :type 'string
  :group 'kvist)

(defcustom kvist-repl-auto-start nil
  "When non-nil, evaluation may start a package REPL.
The default is nil: opening or focusing a Kvist file never starts a REPL.
Use `kvist-repl-start' before evaluation.  Tooling uses a live session when
one already exists and otherwise falls back to file-context commands."
  :type 'boolean
  :group 'kvist)

(defcustom kvist-generated-buffer-name "*Kvist Generated*"
  "Buffer name used to show generated Odin."
  :type 'string
  :group 'kvist)

(defcustom kvist-macroexpand-buffer-name "*Kvist Macroexpand*"
  "Buffer name used to show Kvist macro expansion output."
  :type 'string
  :group 'kvist)

(defcustom kvist-inspect-buffer-name "*Kvist Inspect*"
  "Buffer name used to show typed live-value inspection."
  :type 'string
  :group 'kvist)

(defcustom kvist-generations-buffer-name "*Kvist Generations*"
  "Buffer name used to show loaded native REPL generations."
  :type 'string
  :group 'kvist)

(defcustom kvist-versions-buffer-name "*Kvist Versions*"
  "Buffer name used to show native versions of a REPL definition."
  :type 'string
  :group 'kvist)

(defcustom kvist-dependents-buffer-name "*Kvist Dependents*"
  "Buffer name used to show dependents of a REPL definition."
  :type 'string
  :group 'kvist)

(defcustom kvist-checkpoints-buffer-name "*Kvist Checkpoints*"
  "Buffer name used to show named REPL state checkpoints."
  :type 'string
  :group 'kvist)

(defcustom kvist-attached-buffer-name "*Kvist Attached*"
  "Buffer name used to show an Olive-attached REPL session."
  :type 'string
  :group 'kvist)

(defcustom kvist-native-debugger-buffer-name "*Kvist Native Debugger*"
  "Buffer name used for the native debugger attached to the REPL worker."
  :type 'string
  :group 'kvist)

(defcustom kvist-debug-frame-buffer-name "*Kvist Debug Frame*"
  "Buffer name used to present the active instrumented debug frame."
  :type 'string
  :group 'kvist)

(defcustom kvist-debug-value-buffer-name "*Kvist Debug Value*"
  "Buffer name used to present evaluation in the active debug frame."
  :type 'string
  :group 'kvist)

(defcustom kvist-condition-buffer-name "*Kvist Condition*"
  "Buffer name used to present a recoverable Kvist condition."
  :type 'string
  :group 'kvist)

(defcustom kvist-debug-page-buffer-name "*Kvist Debug Page*"
  "Buffer name used to browse live collections in a paused debug frame."
  :type 'string
  :group 'kvist)

(defface kvist-debug-paused-line-face
  '((t :inherit highlight))
  "Face used for the source line at an instrumented Kvist pause."
  :group 'kvist)

(defface kvist-debug-prompt-face
  '((t :inherit font-lock-comment-face :extend t))
  "Face used for the source-buffer debugger command prompt."
  :group 'kvist)

(defface kvist-debug-prompt-key-face
  '((t :inherit font-lock-keyword-face :weight bold))
  "Face used for keys in the source-buffer debugger command prompt."
  :group 'kvist)

(defcustom kvist-trace-buffer-name "*Kvist Trace*"
  "Buffer name used to present instrumented Kvist execution traces."
  :type 'string
  :group 'kvist)

(defcustom kvist-trace-limit 1000
  "Maximum safe-point events retained by one traced evaluation."
  :type 'integer
  :group 'kvist)

(defcustom kvist-trace-capture-values t
  "Whether traced evaluations capture bounded top-level lexical values."
  :type 'boolean
  :group 'kvist)

(defcustom kvist-trace-value-limit 100
  "Maximum safe points retaining lexical values in one trace."
  :type 'integer
  :group 'kvist)

(defcustom kvist-native-debugger-command
  (if (eq system-type 'darwin) "lldb -p %d" "gdb -p %d")
  "Command template used to attach to a Kvist native worker.
The template receives the worker process id as its single `%d' argument."
  :type 'string
  :group 'kvist)

(defcustom kvist-native-debugger-launch-function
  #'kvist--launch-native-debugger
  "Function called with debug-session metadata to attach a native debugger."
  :type 'function
  :group 'kvist)

(defcustom kvist-native-breakpoint-function
  #'kvist--set-native-breakpoints
  "Function called with translated Kvist breakpoint locations."
  :type 'function
  :group 'kvist)

(defcustom kvist-inspection-page-size 20
  "Maximum number of collection entries requested per inspection page."
  :type 'integer
  :group 'kvist)

(defcustom kvist-debug-page-size 20
  "Maximum number of live paused-collection entries requested per page."
  :type 'integer
  :group 'kvist)

(defcustom kvist-inline-result-prefix "=> "
  "Prefix used for inline Kvist eval overlays."
  :type 'string
  :group 'kvist)

(defcustom kvist-default-no-print nil
  "When non-nil, default eval commands run snippets as statements."
  :type 'boolean
  :group 'kvist)

(defcustom kvist-repl-evaluation-timeout-ms nil
  "Standalone native execution deadline in milliseconds.
When nil, evaluations have no deadline.  A deadline terminates the disposable
worker and discards its runtime session state; it is never sent to an attached
application."
  :type '(choice (const :tag "No deadline" nil) integer)
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
  '("comment" "package" "import" "odin"
    "def" "def-" "defconst" "defconst-" "defvar" "defvar-"
    "defstruct" "defstruct-" "defenum" "defenum-" "defunion" "defunion-"
    "defn" "defn-" "defmacro" "defmacro-")
  "Kvist forms that are declarations at top level.")

(defvar kvist--last-source-buffer nil)

(defvar-local kvist--inspection-handle nil)
(defvar-local kvist--inspection-members nil)
(defvar-local kvist--inspection-shape nil)
(defvar-local kvist--inspection-expression nil)
(defvar-local kvist--inspection-offset nil)
(defvar-local kvist--inspection-limit nil)
(defvar-local kvist--inspection-total nil)
(defvar-local kvist--inspection-source-file nil)
(defvar-local kvist--inspection-source-buffer nil)
(defvar-local kvist--inspection-current nil)
(defvar-local kvist--inspection-history nil)

(defvar kvist--inspection-restoring nil)
(defvar kvist--inspection-restored-history nil)

(defvar-local kvist--debug-page-path nil)
(defvar-local kvist--debug-page-offset nil)
(defvar-local kvist--debug-page-limit nil)
(defvar-local kvist--debug-page-total nil)
(defvar-local kvist--debug-page-source-file nil)
(defvar-local kvist--debug-page-source-buffer nil)
(defvar-local kvist--debug-page-pause-id nil)
(defvar-local kvist--debug-frame-collections nil)
(defvar-local kvist--debug-frame-source-file nil)
(defvar-local kvist--debug-frame-source-buffer nil)
(defvar-local kvist--condition-context-file nil)
(defvar-local kvist--debug-source-context-file nil)

(defun kvist--debug-context-source-file ()
  "Return the source file owning the active debug UI context."
  (or kvist--debug-frame-source-file
      kvist--debug-page-source-file
      kvist--condition-context-file
      kvist--debug-source-context-file
      buffer-file-name))

(defun kvist--inspection-page-size ()
  "Return the configured inspection page size within protocol bounds."
  (min 100 (max 1 kvist-inspection-page-size)))

(defun kvist--debug-page-size ()
  "Return the configured paused collection page size within protocol bounds."
  (min 100 (max 1 kvist-debug-page-size)))

(cl-defstruct (kvist--repl-session
               (:constructor kvist--make-repl-session))
  key
  context-file
  root
  process
  process-buffer
  interface-buffer
  partial
  pending
  next-id
  generation
  application-generation
  attached
  endpoint
  attached-capabilities
  pause-id
  pause-overlay
  pause-return-buffer
  pause-return-marker
  paused-during-request
  debug-frame
  condition)

(defvar-local kvist--repl-interface-key nil)
(defvar-local kvist--repl-input-marker nil)
(defvar-local kvist--repl-prompt-marker nil)
(defvar-local kvist--repl-history nil)
(defvar-local kvist--repl-history-index -1)
(defvar-local kvist--repl-history-draft "")
(defvar-local kvist--repl-input-pending nil)
(defvar-local kvist--repl-buffer-stopping nil)

(defvar kvist--repl-sessions (make-hash-table :test #'equal)
  "Native REPL sessions keyed by canonical package entry file.")

(defvar-local kvist-repl-context-file nil
  "Application entry file whose live REPL owns this source buffer.")

(defvar kvist-cache-name-history nil
  "Minibuffer history for Kvist cache names.")

(defvar kvist-checkpoint-name-history nil
  "Minibuffer history for Kvist REPL checkpoint names.")

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
    (define-key map (kbd "C-c C-s") #'kvist-repl-start)
    (define-key map (kbd "C-c g g") #'kvist-expand-form-at-point)
    (define-key map (kbd "C-c d") #'kvist-doc-at-point)
    (define-key map (kbd "C-c C-d") #'kvist-doc-at-point)
    (define-key map (kbd "C-c C-w") #'kvist-save-form-result)
    (define-key map (kbd "C-c C-l") #'kvist-cache-list)
    (define-key map (kbd "C-c C-o") #'kvist-cache-open)
    (define-key map (kbd "C-c M-d") #'kvist-cache-rm)
    (define-key map (kbd "C-c C-z") #'kvist-repl)
    (define-key map (kbd "C-c M-r") #'kvist-repl-reset)
    (define-key map (kbd "C-c C-q") #'kvist-repl-stop)
    (define-key map (kbd "C-c M-q") #'kvist-repl-stop)
    (define-key map (kbd "C-c M-i") #'kvist-inspect-form-at-point)
    (define-key map (kbd "C-c M-g") #'kvist-repl-generations)
    (define-key map (kbd "C-c v v") #'kvist-repl-versions-at-point)
    (define-key map (kbd "C-c v d") #'kvist-repl-dependents-at-point)
    (define-key map (kbd "C-c v r") #'kvist-repl-refresh-dependents-at-point)
    (define-key map (kbd "C-c k s") #'kvist-repl-checkpoint)
    (define-key map (kbd "C-c k l") #'kvist-repl-checkpoints)
    (define-key map (kbd "C-c k r") #'kvist-repl-checkpoint-restore)
    (define-key map (kbd "C-c k d") #'kvist-repl-checkpoint-drop)
    (define-key map (kbd "C-c a a") #'kvist-repl-attach)
    (define-key map (kbd "C-c a s") #'kvist-repl-attached-status)
    (define-key map (kbd "C-c a i") #'kvist-repl-invoke-capability)
    (define-key map (kbd "C-c a r") #'kvist-repl-attached-reload)
    (define-key map (kbd "C-c a q") #'kvist-repl-stop)
    (define-key map (kbd "C-c M-b") #'kvist-debug-native-worker)
    (define-key map (kbd "C-c M-s") #'kvist-debug-breakpoint-at-point)
    (define-key map (kbd "C-c M-e") #'kvist-debug-eval-form-at-point)
    (define-key map (kbd "C-c M-c") #'kvist-debug-continue)
    (define-key map (kbd "C-c M-k") #'kvist-repl-interrupt)
    (define-key map (kbd "C-c M-x") #'kvist-debug-recover)
    (define-key map (kbd "C-c M-n") #'kvist-debug-step)
    (define-key map (kbd "C-c M-o") #'kvist-debug-step-over)
    (define-key map (kbd "C-c M-u") #'kvist-debug-step-out)
    (define-key map (kbd "C-c M-t") #'kvist-trace-form-at-point)
    (define-key map (kbd "C-c M-f") #'kvist-debug-show-frame)
    (define-key map (kbd "C-c M-p") #'kvist-debug-page)
    (define-key map (kbd "C-c M-v") #'kvist-debug-eval-expression)
    (define-key map (kbd "C-c M-l") #'kvist-debug-eval-native-form-at-point)
    (define-key map (kbd "C-c t t") #'kvist-test-at-point)
    (define-key map (kbd "C-c t p") #'kvist-test-package)
    (define-key map (kbd "C-c t a") #'kvist-test-project)
    map)
  "Keymap for `kvist-eval-mode'.")

;; Keep newly added lifecycle bindings effective when this file is reloaded
;; into an existing Emacs session where `defvar' preserves the old keymap.
(define-key kvist-eval-mode-map (kbd "C-c C-q") #'kvist-repl-stop)
(define-key kvist-eval-mode-map (kbd "C-c C-s") #'kvist-repl-start)
(define-key kvist-eval-mode-map (kbd "C-c C-z") #'kvist-repl)
(define-key kvist-eval-mode-map (kbd "C-c M-j") nil)
(define-key kvist-eval-mode-map (kbd "C-c g g") #'kvist-expand-form-at-point)
(define-key kvist-eval-mode-map (kbd "C-c v v") #'kvist-repl-versions-at-point)
(define-key kvist-eval-mode-map (kbd "C-c v d") #'kvist-repl-dependents-at-point)
(define-key kvist-eval-mode-map (kbd "C-c v r") #'kvist-repl-refresh-dependents-at-point)

(defconst kvist--debug-key-bindings
  '(("C-c M-b" . kvist-debug-native-worker)
    ("C-c M-s" . kvist-debug-breakpoint-at-point)
    ("C-c M-e" . kvist-debug-eval-form-at-point)
    ("C-c M-c" . kvist-debug-continue)
    ("C-c M-k" . kvist-repl-interrupt)
    ("C-c M-x" . kvist-debug-recover)
    ("C-c M-n" . kvist-debug-step)
    ("C-c M-o" . kvist-debug-step-over)
    ("C-c M-u" . kvist-debug-step-out)
    ("C-c M-t" . kvist-trace-form-at-point)
    ("C-c M-f" . kvist-debug-show-frame)
    ("C-c M-p" . kvist-debug-page)
    ("C-c M-v" . kvist-debug-eval-expression)
    ("C-c M-l" . kvist-debug-eval-native-form-at-point))
  "Debugger bindings that must survive reloading `kvist-eval.el'.")

(defun kvist--install-debug-keybindings (map)
  "Install all Kvist debugger bindings into keymap MAP."
  (dolist (binding kvist--debug-key-bindings)
    (define-key map (kbd (car binding)) (cdr binding))))

;; `defvar' preserves an older keymap in a long-running Emacs.  Reinstall the
;; complete debugger set on every load rather than relying on initial creation.
(kvist--install-debug-keybindings kvist-eval-mode-map)

(defvar kvist-debug-source-mode-map
  (make-sparse-keymap)
  "Temporary single-key controls active at a Kvist source pause.")

(defconst kvist--debug-source-key-bindings
  '(("n" . kvist-debug-step)
    ("o" . kvist-debug-step-over)
    ("u" . kvist-debug-step-out)
    ("c" . kvist-debug-continue)
    ("e" . kvist-debug-eval-expression)
    ("f" . kvist-debug-show-frame)
    ("p" . kvist-debug-page)
    ("q" . kvist-debug-abort)
    ("r" . kvist-debug-recover))
  "Single-key commands active in a paused Kvist source buffer.")

(defun kvist--install-debug-source-keybindings (map)
  "Install the current paused-source debugger bindings into MAP."
  ;; Remove keys used by earlier source prompts when reloading this file in a
  ;; long-running Emacs session.
  (define-key map (kbd "i") nil)
  (define-key map (kbd "v") nil)
  (dolist (binding kvist--debug-source-key-bindings)
    (define-key map (kbd (car binding)) (cdr binding))))

;; `defvar' preserves this map across `load-file', including while a debug
;; pause is active.  Repair it unconditionally so the prompt and keys agree.
(kvist--install-debug-source-keybindings kvist-debug-source-mode-map)

(define-minor-mode kvist-debug-source-mode
  "Temporary source-buffer controls for an active Kvist debug pause.

The mode is enabled only while execution is paused and removed when execution
resumes.  Its commands are also rendered immediately above the paused source
line, following the source-oriented interaction used by CIDER's debugger."
  :init-value nil
  :lighter " Kvist-Debug"
  :keymap kvist-debug-source-mode-map)

;;;###autoload
(define-minor-mode kvist-eval-mode
  "Minor mode for Kvist eval keybindings."
  :lighter " Kvist-Eval"
  :keymap kvist-eval-mode-map)

(defvar-local kvist-presentation-quit-command #'quit-window
  "Command invoked by `q' in the current Kvist presentation buffer.")

(defun kvist-presentation-quit ()
  "Close the current Kvist presentation or perform its stronger quit action."
  (interactive)
  (call-interactively kvist-presentation-quit-command))

(defvar kvist-presentation-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") #'kvist-presentation-quit)
    map)
  "Keymap shared by non-REPL Kvist presentation buffers.")

(define-key kvist-presentation-mode-map (kbd "q") #'kvist-presentation-quit)

(define-minor-mode kvist-presentation-mode
  "Minor mode for consistent controls in read-only Kvist buffers."
  :init-value nil
  :lighter nil
  :keymap kvist-presentation-mode-map)

(defun kvist--enable-presentation-mode (&optional quit-command)
  "Enable Kvist presentation keys, using QUIT-COMMAND for `q'."
  (setq-local kvist-presentation-quit-command
              (or quit-command #'quit-window))
  (kvist-presentation-mode 1))

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
        (kvist--enable-presentation-mode)
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
        (kvist--enable-presentation-mode)
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
  (kvist--enable-presentation-mode)
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

(defun kvist--source-file-text (file)
  "Return current editor text for FILE, falling back to its saved contents."
  (let ((buffer (find-buffer-visiting file)))
    (if (buffer-live-p buffer)
        (with-current-buffer buffer
          (buffer-substring-no-properties (point-min) (point-max)))
      (with-temp-buffer
        (insert-file-contents file)
        (buffer-string)))))

(defun kvist--package-source-files (path)
  "Return canonical Kvist source files represented by PATH."
  (cond
   ((file-directory-p path)
    (mapcar #'file-truename
            (directory-files path t "\\.kvist\\'" t)))
   ((file-exists-p path)
    (list (file-truename path)))
   ((file-exists-p (concat path ".kvist"))
    (list (file-truename (concat path ".kvist"))))
   (t nil)))

(defun kvist--resolve-local-import-source-files (source-file import-path)
  "Resolve local IMPORT-PATH from SOURCE-FILE to Kvist package files."
  (let ((target
         (cond
          ((string-prefix-p "kvist:" import-path)
           (expand-file-name
            (substring import-path (length "kvist:"))
            (expand-file-name "src/kvist"
                              (kvist--project-root source-file))))
          ((or (string-prefix-p "." import-path)
               (file-name-absolute-p import-path))
           (expand-file-name import-path
                             (file-name-directory source-file)))
          (t nil))))
    (when target
      (kvist--package-source-files target))))

(defun kvist--source-local-imports (source-file)
  "Return local Kvist source files imported directly by SOURCE-FILE."
  (with-temp-buffer
    (insert (kvist--source-file-text source-file))
    (set-syntax-table kvist-mode-syntax-table)
    (goto-char (point-min))
    (let (files)
      (while (re-search-forward "(import\\_>" nil t)
        (let* ((start (match-beginning 0))
               (end (condition-case nil
                        (scan-sexps start 1)
                      (error nil))))
          (when end
            (save-restriction
              (narrow-to-region start end)
              (goto-char (point-min))
              (when (re-search-forward "\\\"\\([^\\\"]+\\)\\\"" nil t)
                (setq files
                      (nconc
                       files
                       (kvist--resolve-local-import-source-files
                        source-file
                        (match-string-no-properties 1))))))
            (goto-char end))))
      (delete-dups files))))

(defun kvist--repl-context-source-files (context-file)
  "Return source files in the local package graph rooted at CONTEXT-FILE."
  (let ((queue (list (file-truename context-file)))
        (seen (make-hash-table :test #'equal))
        files)
    (while queue
      (let ((file (pop queue)))
        (unless (gethash file seen)
          (puthash file t seen)
          (push file files)
          (setq queue
                (nconc (kvist--source-local-imports file) queue)))))
    (nreverse files)))

(defun kvist--live-repl-session-for-source (source-file)
  "Return the unique live session whose package graph contains SOURCE-FILE."
  (let ((source (file-truename source-file))
        candidates)
    (maphash
     (lambda (_key session)
       (when (and (process-live-p (kvist--repl-session-process session))
                  (member source
                          (kvist--repl-context-source-files
                           (kvist--repl-session-context-file session))))
         (push session candidates)))
     kvist--repl-sessions)
    (cond
     ((null candidates) nil)
     ((= (length candidates) 1) (car candidates))
     ((and kvist-repl-context-file
           (cl-find (file-truename kvist-repl-context-file)
                    candidates
                    :key #'kvist--repl-session-context-file
                    :test #'equal)))
     (t
      (user-error
       "This file belongs to multiple live Kvist REPLs; stop one or select its REPL buffer")))))

(defun kvist--repl-key-for-file (&optional source-file)
  "Return the live package-graph session key for SOURCE-FILE when available."
  (let ((file (or source-file buffer-file-name)))
    (unless file
      (user-error "Kvist REPL evaluation requires a file-backed buffer"))
    (let* ((source (file-truename file))
           (entry (file-truename (kvist--package-entry-file source)))
           (preferred-key
            (and kvist-repl-context-file
                 (file-exists-p kvist-repl-context-file)
                 (file-truename kvist-repl-context-file)))
           (preferred-context
            (and preferred-key
                 (member source
                         (kvist--repl-context-source-files preferred-key))
                 preferred-key))
           (exact (gethash entry kvist--repl-sessions))
           (preferred
            (and preferred-key
                 (gethash preferred-key kvist--repl-sessions)))
           (session
            (cond
             ((and exact
                   (process-live-p (kvist--repl-session-process exact)))
              exact)
             ((and preferred
                   (process-live-p (kvist--repl-session-process preferred))
                   (member source
                           (kvist--repl-context-source-files
                            (kvist--repl-session-context-file preferred))))
              preferred)
             (t (kvist--live-repl-session-for-source source)))))
      (if session
          (progn
            (when (and buffer-file-name
                       (equal source (file-truename buffer-file-name)))
              (setq-local kvist-repl-context-file
                          (kvist--repl-session-context-file session)))
            (kvist--repl-session-key session))
        (or preferred-context entry)))))

(defun kvist--current-repl-key ()
  "Return the current source or interactive buffer's package key."
  (or kvist--repl-interface-key
      (kvist--repl-key-for-file)))

(defun kvist--repl-process-buffer-name (context-file)
  "Return a process buffer name for CONTEXT-FILE."
  (format " *Kvist REPL %s*" (kvist--file-label context-file)))

(defun kvist--repl-interface-buffer-name (context-file)
  "Return the interactive REPL buffer name for CONTEXT-FILE."
  (let ((label (kvist--file-label context-file)))
    (if (string-match "\\`\\*\\(.*\\)\\*\\'" kvist-repl-buffer-name)
        (format "*%s %s*" (match-string 1 kvist-repl-buffer-name) label)
      (format "%s<%s>" kvist-repl-buffer-name label))))

(defun kvist--repl-interface-session ()
  "Return the live session belonging to the current REPL buffer."
  (let ((session (and kvist--repl-interface-key
                      (gethash kvist--repl-interface-key
                               kvist--repl-sessions))))
    (unless (and session
                 (process-live-p
                  (kvist--repl-session-process session)))
      (user-error "This Kvist REPL is not running"))
    session))

(defun kvist--repl-insert-prompt ()
  "Insert a new editable prompt at the end of the current REPL buffer."
  (let ((inhibit-read-only t))
    (goto-char (point-max))
    (set-marker kvist--repl-prompt-marker (point))
    (insert (propertize "kvist=> "
                        'read-only t
                        'field 'prompt
                        'rear-nonsticky '(read-only field)))
    (set-marker kvist--repl-input-marker (point))
    (setq kvist--repl-history-index -1)
    (setq kvist--repl-history-draft "")))

(defun kvist--repl-replace-input (text)
  "Replace the editable REPL input with TEXT."
  (let ((inhibit-read-only t))
    (delete-region (marker-position kvist--repl-input-marker)
                   (point-max))
    (goto-char (point-max))
    (insert text)))

(defun kvist-repl-previous-input ()
  "Replace the current prompt with an older REPL input."
  (interactive)
  (unless kvist--repl-history
    (user-error "No earlier Kvist REPL input"))
  (when (< kvist--repl-history-index 0)
    (setq kvist--repl-history-draft
          (buffer-substring-no-properties
           (marker-position kvist--repl-input-marker)
           (point-max))))
  (setq kvist--repl-history-index
        (min (1- (length kvist--repl-history))
             (1+ kvist--repl-history-index)))
  (kvist--repl-replace-input
   (nth kvist--repl-history-index kvist--repl-history)))

(defun kvist-repl-next-input ()
  "Replace the current prompt with a newer REPL input."
  (interactive)
  (when (< kvist--repl-history-index 0)
    (user-error "Already at the newest Kvist REPL input"))
  (setq kvist--repl-history-index
        (1- kvist--repl-history-index))
  (kvist--repl-replace-input
   (if (< kvist--repl-history-index 0)
       kvist--repl-history-draft
     (nth kvist--repl-history-index kvist--repl-history))))

(defun kvist--repl-input-complete-p ()
  "Return non-nil when the editable input is structurally complete."
  (let* ((state
          (parse-partial-sexp
           (marker-position kvist--repl-input-marker)
           (point-max)))
         (depth (car state)))
    (and (not (nth 3 state))
         (<= depth 0))))

(defun kvist--repl-newline-and-indent ()
  "Insert a continuation line indented as prompt-free Kvist source."
  (newline)
  (let* ((input-start (marker-position kvist--repl-input-marker))
         (source
          (buffer-substring-no-properties input-start (point)))
         (source-point (1+ (length source)))
         indentation)
    (with-temp-buffer
      (delay-mode-hooks (kvist-mode))
      (insert source)
      (goto-char (min source-point (point-max)))
      (indent-according-to-mode)
      (setq indentation (current-indentation)))
    (indent-line-to indentation)))

(defun kvist--repl-insert-response (result)
  "Append protocol RESULT and open the next prompt."
  (let ((inhibit-read-only t)
        (success (plist-get result :success))
        (text (string-trim-right (or (plist-get result :text) "")))
        (message-text
         (string-trim-right (or (plist-get result :message) ""))))
    (goto-char (point-max))
    (cond
     (success
      (insert (if (string-empty-p text)
                  "nil\n"
                (concat text "\n"))))
     (t
      (insert (format ";; Error: %s\n"
                      (if (string-empty-p message-text)
                          "evaluation failed"
                        message-text)))))
    (add-text-properties (marker-position kvist--repl-prompt-marker)
                         (point-max)
                         '(read-only t rear-nonsticky (read-only)))
    (setq kvist--repl-input-pending nil)
    (kvist--repl-insert-prompt)))

(defun kvist--repl-insert-stream-output (session text)
  "Append streamed TEXT to SESSION's visible REPL transcript."
  (when-let ((buffer (kvist--repl-session-interface-buffer session)))
    (when (and (buffer-live-p buffer)
               (not (string-empty-p text)))
      (with-current-buffer buffer
        (let ((inhibit-read-only t)
              (start nil)
              (prompt-position (marker-position kvist--repl-prompt-marker))
              (input-position (marker-position kvist--repl-input-marker)))
          (if kvist--repl-input-pending
              (goto-char (point-max))
            (goto-char (marker-position kvist--repl-prompt-marker)))
          (setq start (point))
          (insert text)
          (unless (string-suffix-p "\n" text)
            (insert "\n"))
          (add-text-properties start (point)
                               '(read-only t rear-nonsticky (read-only)))
          (unless kvist--repl-input-pending
            (let ((inserted (- (point) start)))
              (set-marker kvist--repl-prompt-marker
                          (+ prompt-position inserted))
              (set-marker kvist--repl-input-marker
                          (+ input-position inserted)))))))))

(defun kvist-repl-return ()
  "Submit complete prompt input, or insert and indent a continuation line."
  (interactive)
  (when kvist--repl-input-pending
    (user-error "The previous Kvist REPL input is still running"))
  (goto-char (point-max))
  (if (not (kvist--repl-input-complete-p))
      (kvist--repl-newline-and-indent)
    (let ((source
           (string-trim
            (buffer-substring-no-properties
             (marker-position kvist--repl-input-marker)
             (point-max))))
          (buffer (current-buffer))
          (session (kvist--repl-interface-session)))
      (unless (string-empty-p source)
        (unless (equal source (car kvist--repl-history))
          (push source kvist--repl-history))
        (setq kvist--repl-input-pending t)
        (let ((inhibit-read-only t))
          (goto-char (point-max))
          (insert "\n"))
        (kvist--repl-request
         "eval"
         source
         (lambda (result)
           (when (and (buffer-live-p buffer)
                      (process-live-p
                       (kvist--repl-session-process session)))
             (with-current-buffer buffer
               (kvist--repl-insert-response result))))
         nil
         (kvist--repl-session-context-file session))))))

(defun kvist--repl-buffer-kill-query ()
  "Confirm that killing this interface also stops its live REPL."
  (if (or kvist--repl-buffer-stopping
          (not kvist--repl-interface-key))
      t
    (let ((session (gethash kvist--repl-interface-key
                            kvist--repl-sessions)))
      (if (not (and session
                    (process-live-p
                     (kvist--repl-session-process session))))
          t
        (when (yes-or-no-p
               "Kill this buffer and stop its Kvist REPL? ")
          (let ((kvist--repl-buffer-stopping t))
            (kvist--repl-stop-session session nil))
          t)))))

(defun kvist--repl-insert-banner (context-file)
  "Insert the read-only interactive REPL banner for CONTEXT-FILE."
  (let ((start (point)))
    (insert (format ";; Kvist REPL: %s\n" context-file))
    (insert ";; RET evaluates complete input; M-p/M-n browse history; C-c M-o clears output.\n\n")
    (add-text-properties start (point)
                         '(read-only t rear-nonsticky (read-only)))))

(defun kvist--repl-clear-interface (context-file)
  "Clear this interface transcript for CONTEXT-FILE, preserving current input."
  (let ((input
         (buffer-substring-no-properties
          (marker-position kvist--repl-input-marker)
          (point-max)))
        (inhibit-read-only t))
    (erase-buffer)
    (kvist--repl-insert-banner context-file)
    (kvist--repl-insert-prompt)
    (insert input)))

;;;###autoload
(defun kvist-repl-clear-buffer ()
  "Clear the interactive REPL transcript without restarting its session.
Input history, native definitions, mutable state, and unsubmitted input are
preserved."
  (interactive)
  (unless (derived-mode-p 'kvist-repl-mode)
    (user-error "This command must be used in a Kvist REPL buffer"))
  (when kvist--repl-input-pending
    (user-error "Wait for or interrupt the pending Kvist evaluation first"))
  (let ((session (kvist--repl-interface-session)))
    (kvist--repl-clear-interface
     (kvist--repl-session-context-file session)))
  (message "Kvist REPL buffer cleared"))

(defvar kvist-repl-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map kvist-mode-map)
    (define-key map (kbd "RET") #'kvist-repl-return)
    (define-key map (kbd "<return>") #'kvist-repl-return)
    (define-key map (kbd "M-p") #'kvist-repl-previous-input)
    (define-key map (kbd "M-n") #'kvist-repl-next-input)
    (define-key map (kbd "C-c C-q") #'kvist-repl-stop)
    (define-key map (kbd "C-c M-q") #'kvist-repl-stop)
    (define-key map (kbd "C-c M-o") #'kvist-repl-clear-buffer)
    map)
  "Keymap for `kvist-repl-mode'.")

(define-key kvist-repl-mode-map (kbd "C-c C-q") #'kvist-repl-stop)
(define-key kvist-repl-mode-map (kbd "C-c M-o") #'kvist-repl-clear-buffer)

(define-derived-mode kvist-repl-mode kvist-mode "Kvist-REPL"
  "Interactive buffer for one package's persistent Kvist REPL."
  (kvist-eval-mode -1)
  (local-set-key (kbd "C-c M-o") #'kvist-repl-clear-buffer)
  (setq-local completion-at-point-functions '(kvist-completion-at-point t))
  (setq-local kvist--repl-input-marker (copy-marker (point-min)))
  (setq-local kvist--repl-prompt-marker (copy-marker (point-min)))
  (add-hook 'kill-buffer-query-functions
            #'kvist--repl-buffer-kill-query nil t))

(defun kvist--repl-mode-finalize ()
  "Apply REPL-specific bindings after inherited `kvist-mode' hooks."
  (kvist-eval-mode -1)
  (setq-local completion-at-point-functions '(kvist-completion-at-point t))
  (local-set-key (kbd "C-c M-o") #'kvist-repl-clear-buffer))

(add-hook 'kvist-repl-mode-hook #'kvist--repl-mode-finalize)

;; Repair already-open REPL buffers when this file is reloaded.
(dolist (buffer (buffer-list))
  (with-current-buffer buffer
    (when (derived-mode-p 'kvist-repl-mode)
      (kvist--repl-mode-finalize))))

(defun kvist--repl-create-interface (session)
  "Create and return SESSION's interactive REPL buffer."
  (let ((buffer
         (get-buffer-create
          (kvist--repl-interface-buffer-name
           (kvist--repl-session-context-file session)))))
    (with-current-buffer buffer
      (unless (derived-mode-p 'kvist-repl-mode)
        (kvist-repl-mode))
      (setq-local kvist--repl-interface-key
                  (kvist--repl-session-key session))
      (setq-local kvist--repl-history nil)
      (setq-local kvist--repl-history-index -1)
      (setq-local kvist--repl-input-pending nil)
      (setq-local kvist--repl-buffer-stopping nil)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (kvist--repl-insert-banner
         (kvist--repl-session-context-file session))
        (kvist--repl-insert-prompt)))
    (setf (kvist--repl-session-interface-buffer session) buffer)
    buffer))

(defun kvist--repl-delete-session (session)
  "Remove SESSION and release its pending callbacks."
  (when session
    (kvist--clear-debug-pause session)
    (when-let ((buffer (kvist--repl-session-interface-buffer session)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (unless kvist--repl-buffer-stopping
            (let ((inhibit-read-only t))
              (goto-char (point-max))
              (insert "\n;; Kvist REPL stopped.\n")
              (add-text-properties (point-min) (point-max)
                                   '(read-only t)))
            (setq kvist--repl-input-pending nil)))))
    (maphash
     (lambda (_id callback)
       (when callback
         (funcall callback
                  (list :success nil
                        :text ""
                        :message "Kvist REPL process exited"
                        :generation (kvist--repl-session-generation session)))))
     (kvist--repl-session-pending session))
    (clrhash (kvist--repl-session-pending session))
    (when (eq session
              (gethash (kvist--repl-session-key session)
                       kvist--repl-sessions))
      (remhash (kvist--repl-session-key session) kvist--repl-sessions))))

(defun kvist--repl-process-sentinel (process _event)
  "Clean up the session owned by PROCESS when it exits."
  (unless (process-live-p process)
    (when-let ((session (process-get process 'kvist-repl-session)))
      (kvist--repl-delete-session session))))

(defun kvist--repl-complete-request (session event)
  "Complete the pending SESSION request described by EVENT."
  (let* ((id (alist-get 'id event))
         (callback (and id (gethash id (kvist--repl-session-pending session)))))
    (when callback
      (remhash id (kvist--repl-session-pending session))
      (let* ((success (alist-get 'success event))
             (message-text (or (alist-get 'message event) ""))
             (request-state (process-get
                             (kvist--repl-session-process session)
                             (intern (concat "kvist-request-" id))))
             (text (or (plist-get request-state :text) "")))
        (process-put (kvist--repl-session-process session)
                     (intern (concat "kvist-request-" id))
                     nil)
        (funcall callback
                 (list :success success
                       :text text
                       :type (plist-get request-state :type)
                       :abi (plist-get request-state :abi)
                       :handle (plist-get request-state :handle)
                       :path (plist-get request-state :path)
                       :index (plist-get request-state :index)
                       :key-source (plist-get request-state :key-source)
                       :shape (plist-get request-state :shape)
                       :element-type (plist-get request-state :element-type)
                       :key-type (plist-get request-state :key-type)
                       :value-type (plist-get request-state :value-type)
                       :length (plist-get request-state :length)
                       :members (plist-get request-state :members)
                       :offset (plist-get request-state :offset)
                       :limit (plist-get request-state :limit)
                       :total (plist-get request-state :total)
                       :entries (plist-get request-state :entries)
                       :collections (plist-get request-state :collections)
                       :checkpoint (plist-get request-state :checkpoint)
                       :checkpoint-bindings
                       (plist-get request-state :checkpoint-bindings)
                       :checkpoints (plist-get request-state :checkpoints)
                       :collection-path
                       (plist-get request-state :collection-path)
                       :generations (plist-get request-state :generations)
                       :bindings (plist-get request-state :bindings)
                       :versions (plist-get request-state :versions)
                       :worker-pid (plist-get request-state :worker-pid)
                       :worker-epoch (plist-get request-state :worker-epoch)
                       :capabilities (plist-get request-state :capabilities)
                       :attached
                       (kvist--repl-session-attached session)
                       :endpoint
                       (kvist--repl-session-endpoint session)
                       :attached-capabilities
                       (or (plist-get request-state :attached-capabilities)
                           (kvist--repl-session-attached-capabilities session))
                       :reload-requested
                       (plist-get request-state :reload-requested)
                       :breakpoints (plist-get request-state :breakpoints)
                       :frames (plist-get request-state :frames)
                       :traces (plist-get request-state :traces)
                       :trace-values (plist-get request-state :trace-values)
                       :trace-values-truncated
                       (plist-get request-state :trace-values-truncated)
                       :trace-summary
                       (plist-get request-state :trace-summary)
                       :symbols (plist-get request-state :symbols)
                       :diagnostics (plist-get request-state :diagnostics)
                       :trace-truncated
                       (plist-get request-state :trace-truncated)
                       :message message-text
                       :generation (or (alist-get 'generation event) 0)
                       :application-generation
                       (kvist--repl-session-application-generation
                        session)
                       :attached-generation
                       (kvist--repl-session-generation session)))))))

(defun kvist--debug-prompt-command (label key)
  "Return debugger command LABEL with its mnemonic KEY emphasized."
  (let* ((text (propertize (copy-sequence label)
                           'face 'kvist-debug-prompt-face))
         (position (string-match (regexp-quote key) text)))
    (when position
      (add-text-properties
       position (1+ position)
       (list 'face '(kvist-debug-prompt-key-face kvist-debug-prompt-face)
             'help-echo (format "Press %s" key))
       text))
    text))

(defun kvist--debug-source-prompt (conditionp)
  "Return the inline source debugger prompt.
Include the recovery command when CONDITIONP is non-nil."
  (concat
   (propertize "  " 'face 'kvist-debug-prompt-face)
   (mapconcat
    #'identity
    (append
     (list (kvist--debug-prompt-command "next" "n")
           (kvist--debug-prompt-command "over" "o")
           (kvist--debug-prompt-command "out" "u")
           (kvist--debug-prompt-command "continue" "c")
           (kvist--debug-prompt-command "eval" "e")
           (kvist--debug-prompt-command "frame" "f")
           (kvist--debug-prompt-command "page" "p")
           (kvist--debug-prompt-command "quit" "q"))
     (when conditionp
       (list (kvist--debug-prompt-command "recover" "r"))))
    "  ")))

(defun kvist--clear-debug-pause (session)
  "Remove SESSION's active source pause indication and controls."
  (when-let ((overlay (kvist--repl-session-pause-overlay session)))
    (when-let ((buffer (overlay-buffer overlay)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (kvist-debug-source-mode -1)
          (setq-local kvist--debug-source-context-file nil))))
    (delete-overlay overlay))
  (setf (kvist--repl-session-pause-overlay session) nil)
  (setf (kvist--repl-session-pause-id session) nil)
  (setf (kvist--repl-session-debug-frame session) nil)
  (setf (kvist--repl-session-condition session) nil))

(defun kvist--show-debug-pause (session event)
  "Record and display the paused source location from EVENT for SESSION."
  (kvist--clear-debug-pause session)
  (let ((pause-id (alist-get 'pause_id event))
        (source-path (alist-get 'source_path event))
        (line (alist-get 'line event))
        (column (alist-get 'column event))
        (frame (car (alist-get 'frames event)))
        (conditionp (equal (alist-get 'kind event) "condition"))
        pause-position)
    (setf (kvist--repl-session-pause-id session) pause-id)
    (setf (kvist--repl-session-debug-frame session) frame)
    (setf (kvist--repl-session-paused-during-request session) t)
    (when (and (stringp source-path)
               (numberp line)
               (> line 0))
      (let ((buffer (or (find-buffer-visiting source-path)
                        (find-file-noselect source-path))))
        (with-current-buffer buffer
          (setq-local kvist--debug-source-context-file
                      (kvist--repl-session-context-file session))
          (kvist-debug-source-mode 1)
          (save-excursion
            (goto-char (point-min))
            (forward-line (1- line))
            (when (and (numberp column) (> column 1))
              (move-to-column (1- column)))
            (when conditionp
              (let ((condition-form
                     (save-excursion
                       (ignore-errors
                         (backward-up-list)
                         (when (looking-at-p "(condition\\.signal\\_>")
                           (point))))))
                (when condition-form
                  (goto-char condition-form))))
            (setq pause-position (point))
            (let ((overlay (make-overlay
                            (line-beginning-position)
                            (line-end-position)
                            buffer)))
              (overlay-put overlay 'face 'kvist-debug-paused-line-face)
              (overlay-put overlay 'after-string
                           (kvist--debug-source-prompt conditionp))
              (overlay-put overlay 'priority 1001)
              (setf (kvist--repl-session-pause-overlay session) overlay))))
        (pop-to-buffer buffer)
        ;; An overlay's `after-string' is rendered at its end.  Explicitly
        ;; restore point to the source-mapped pause position so the cursor is
        ;; never displayed after the inline command prompt.
        (when pause-position
          (goto-char pause-position))))
    (message "Kvist paused at %s:%s (pause %s)"
             (or source-path "<eval>")
             (or line "?")
             pause-id)
    (kvist--maybe-refresh-debug-frame-buffer session frame)))

(defun kvist--repl-handle-event (session event)
  "Route one parsed protocol EVENT for SESSION."
  (let ((kind (alist-get 'kind event))
        (id (alist-get 'id event)))
    (when (numberp (alist-get 'generation event))
      (setf (kvist--repl-session-generation session)
            (alist-get 'generation event)))
    (when (numberp (alist-get 'application_generation event))
      (setf (kvist--repl-session-application-generation session)
            (alist-get 'application_generation event)))
    (when (numberp (alist-get 'attached_generation event))
      (setf (kvist--repl-session-generation session)
            (alist-get 'attached_generation event)))
    (cond
     ((equal kind "ready")
      (when (alist-get 'attached event)
        (setf (kvist--repl-session-attached session) t)
        (setf (kvist--repl-session-application-generation session)
              (alist-get 'generation event))
        (setf (kvist--repl-session-attached-capabilities session)
              (alist-get 'attached_capabilities event))))
     ((member kind '("attached-session"
                     "capability-result"
                     "reload-requested"
                     "reload-complete"))
      (let ((capabilities (alist-get 'attached_capabilities event)))
        (setf (kvist--repl-session-attached-capabilities session)
              capabilities))
      (when id
        (let* ((process (kvist--repl-session-process session))
               (property (intern (concat "kvist-request-" id)))
               (state (process-get process property)))
          (when (equal kind "capability-result")
            (setq state
                  (plist-put state :text
                             (or (alist-get 'text event) ""))))
          (when (equal kind "reload-requested")
            (setq state
                  (plist-put state :reload-requested
                             (alist-get 'reload_requested event))))
          (setq state
                (plist-put state :attached-capabilities
                           (alist-get 'attached_capabilities event)))
          (process-put process property state))))
     ((equal kind "trace")
      (when id
        (let* ((process (kvist--repl-session-process session))
               (property (intern (concat "kvist-request-" id)))
               (state (process-get process property))
               (traces (plist-get state :traces)))
          (setq state
                (plist-put state :traces
                           (append traces (list event))))
          (process-put process property state))))
     ((equal kind "stream-output")
      (kvist--repl-insert-stream-output
       session
       (or (alist-get 'text event) "")))
     ((member kind '("completions" "lookup" "documentation" "xref"))
      (when id
        (let* ((process (kvist--repl-session-process session))
               (property (intern (concat "kvist-request-" id)))
               (state (process-get process property)))
          (setq state
                (plist-put state :symbols
                           (alist-get 'symbols event)))
          (process-put process property state))))
     ((equal kind "diagnostics")
      (when id
        (let* ((process (kvist--repl-session-process session))
               (property (intern (concat "kvist-request-" id)))
               (state (process-get process property)))
          (setq state
                (plist-put state :diagnostics
                           (alist-get 'diagnostics event)))
          (process-put process property state))))
     ((equal kind "trace-summary")
      (when id
        (let* ((process (kvist--repl-session-process session))
               (property (intern (concat "kvist-request-" id)))
               (state (process-get process property)))
          (setq state (plist-put state :trace-summary event))
          (process-put process property state))))
     ((equal kind "trace-values")
      (when id
        (let* ((process (kvist--repl-session-process session))
               (property (intern (concat "kvist-request-" id)))
               (state (process-get process property))
               (values (plist-get state :trace-values)))
          (setq state
                (plist-put state :trace-values
                           (append values (list event))))
          (process-put process property state))))
     ((equal kind "trace-values-limit")
      (when id
        (let* ((process (kvist--repl-session-process session))
               (property (intern (concat "kvist-request-" id)))
               (state (process-get process property)))
          (setq state
                (plist-put state :trace-values-truncated t))
          (process-put process property state))))
     ((equal kind "trace-limit")
      (when id
        (let* ((process (kvist--repl-session-process session))
               (property (intern (concat "kvist-request-" id)))
               (state (process-get process property)))
          (setq state (plist-put state :trace-truncated t))
          (process-put process property state))))
     ((member kind '("output" "expansion" "inspection" "inspection-page"
                     "debug-page" "debug-value"))
      (when id
        (let* ((process (kvist--repl-session-process session))
               (property (intern (concat "kvist-request-" id)))
               (state (process-get process property))
               (prior (or (plist-get state :text) "")))
          (setq state
                (plist-put state :text
                           (concat prior (or (alist-get 'text event) ""))))
          (when (member kind '("inspection" "inspection-page"))
            (setq state (plist-put state :type (alist-get 'type event)))
            (setq state (plist-put state :abi (alist-get 'abi event)))
            (setq state (plist-put state :handle (alist-get 'handle event)))
            (setq state (plist-put state :path (alist-get 'path event)))
            (setq state (plist-put state :index (alist-get 'index event)))
            (setq state
                  (plist-put state :key-source (alist-get 'key_source event)))
            (setq state (plist-put state :shape (alist-get 'shape event)))
            (setq state
                  (plist-put state :element-type
                             (alist-get 'element_type event)))
            (setq state (plist-put state :key-type (alist-get 'key_type event)))
            (setq state
                  (plist-put state :value-type (alist-get 'value_type event)))
            (setq state (plist-put state :length (alist-get 'length event)))
            (setq state (plist-put state :members (alist-get 'members event)))
            (setq state (plist-put state :offset (alist-get 'offset event)))
            (setq state (plist-put state :limit (alist-get 'limit event)))
            (setq state (plist-put state :total (alist-get 'total event)))
            (setq state (plist-put state :entries (alist-get 'entries event))))
          (when (equal kind "debug-page")
            (setq state (plist-put state :shape (alist-get 'shape event)))
            (setq state
                  (plist-put state :element-type
                             (alist-get 'element_type event)))
            (setq state (plist-put state :key-type (alist-get 'key_type event)))
            (setq state
                  (plist-put state :value-type (alist-get 'value_type event)))
            (setq state
                  (plist-put state :collection-path
                             (alist-get 'collection_path event)))
            (setq state (plist-put state :offset (alist-get 'offset event)))
            (setq state (plist-put state :limit (alist-get 'limit event)))
            (setq state (plist-put state :total (alist-get 'total event)))
            (setq state (plist-put state :entries (alist-get 'entries event)))
            (setq state
                  (plist-put state :collections
                             (alist-get 'collections event))))
          (when (equal kind "debug-value")
            (setq state (plist-put state :type (alist-get 'type event))))
          (process-put process property state))))
     ((equal kind "generations")
      (when id
        (let* ((process (kvist--repl-session-process session))
               (property (intern (concat "kvist-request-" id)))
               (state (process-get process property)))
          (setq state
                (plist-put state :generations
                           (alist-get 'generations event)))
          (process-put process property state))))
     ((member kind '("bindings" "versions" "dependents"))
      (when id
        (let* ((process (kvist--repl-session-process session))
               (property (intern (concat "kvist-request-" id)))
               (state (process-get process property)))
          (setq state
                (plist-put state
                           (if (equal kind "versions")
                               :versions
                             :bindings)
                           (if (equal kind "versions")
                               (alist-get 'versions event)
                             (alist-get 'bindings event))))
          (process-put process property state))))
     ((member kind '("checkpoint-saved"
                     "checkpoint-restored"
                     "checkpoint-dropped"))
      (when id
        (let* ((process (kvist--repl-session-process session))
               (property (intern (concat "kvist-request-" id)))
               (state (process-get process property)))
          (setq state
                (plist-put state :checkpoint
                           (alist-get 'checkpoint event)))
          (setq state
                (plist-put state :checkpoint-bindings
                           (alist-get 'checkpoint_bindings event)))
          (process-put process property state))))
     ((equal kind "checkpoints")
      (when id
        (let* ((process (kvist--repl-session-process session))
               (property (intern (concat "kvist-request-" id)))
               (state (process-get process property)))
          (setq state
                (plist-put state :checkpoints
                           (alist-get 'checkpoints event)))
          (process-put process property state))))
     ((equal kind "debug-session")
      (when id
        (let* ((process (kvist--repl-session-process session))
               (property (intern (concat "kvist-request-" id)))
               (state (process-get process property)))
          (setq state (plist-put state :worker-pid
                                 (alist-get 'worker_pid event)))
          (setq state (plist-put state :worker-epoch
                                 (alist-get 'worker_epoch event)))
          (setq state (plist-put state :capabilities
                                 (alist-get 'capabilities event)))
          (process-put process property state))))
     ((equal kind "breakpoint-locations")
      (when id
        (let* ((process (kvist--repl-session-process session))
               (property (intern (concat "kvist-request-" id)))
               (state (process-get process property)))
          (setq state
                (plist-put state :breakpoints
                           (alist-get 'breakpoints event)))
          (process-put process property state))))
     ((equal kind "debug-frame")
      (when id
        (let* ((process (kvist--repl-session-process session))
               (property (intern (concat "kvist-request-" id)))
               (state (process-get process property))
               (frames (alist-get 'frames event)))
          (setq state (plist-put state :frames frames))
          (when frames
            (setf (kvist--repl-session-debug-frame session)
                  (car frames)))
          (process-put process property state))))
     ((equal kind "paused")
      (kvist--show-debug-pause session event))
     ((equal kind "condition")
      (kvist--show-debug-pause session event)
      (setf (kvist--repl-session-condition session) event)
      (kvist--present-condition session event))
     ((equal kind "resumed")
      (kvist--clear-debug-pause session)
      (message "Kvist evaluation resumed"))
     ((equal kind "abort-requested")
      (kvist--clear-debug-pause session)
      (message "Kvist evaluation abort requested"))
     ((equal kind "aborted")
      (kvist--clear-debug-pause session)
      (message "Kvist evaluation aborted"))
     ((equal kind "interrupted")
      (kvist--clear-debug-pause session)
      (message "Kvist evaluation interrupted; runtime session state was discarded"))
     ((equal kind "deadline-exceeded")
      (kvist--clear-debug-pause session)
      (message "Kvist evaluation deadline exceeded; runtime session state was discarded"))
     ((equal kind "native-crash")
      (kvist--clear-debug-pause session)
      (message "Kvist native worker crashed%s; runtime session state was discarded"
               (if-let ((code (alist-get 'exit_code event)))
                   (format " (exit %s)" code)
                 "")))
     ((equal kind "restart-invoked")
      (kvist--clear-debug-pause session)
      (message "Kvist recovery selected: %s"
               (or (alist-get 'restart event) "unknown")))
     ((equal kind "stepping")
      (kvist--clear-debug-pause session)
      (message "Kvist evaluation stepping"))
     ((member kind '("complete" "reset"))
      (kvist--repl-complete-request session event)))))

(defun kvist--repl-process-filter (process chunk)
  "Parse JSONL protocol CHUNK emitted by PROCESS."
  (when-let ((session (process-get process 'kvist-repl-session)))
    (let* ((combined (concat (or (kvist--repl-session-partial session) "")
                             chunk))
           (lines (split-string combined "\n"))
           (partial (car (last lines))))
      (setf (kvist--repl-session-partial session) partial)
      (dolist (line (butlast lines))
        (unless (string-empty-p line)
          (condition-case err
              (kvist--repl-handle-event
               session
               (json-parse-string line
                                  :object-type 'alist
                                  :array-type 'list
                                  :null-object nil
                                  :false-object nil))
            (error
             (message "Invalid Kvist REPL event: %s" (error-message-string err)))))))))

(defun kvist--repl-start-session (&optional source-file endpoint)
  "Start and return the package session for SOURCE-FILE.
When ENDPOINT is non-nil, connect the generic client to that Olive endpoint."
  (let* ((context-file (kvist--repl-key-for-file source-file))
         (root (file-name-as-directory (kvist--project-root context-file)))
         (default-directory root)
         (process-buffer
          (get-buffer-create (kvist--repl-process-buffer-name context-file)))
         (session
          (kvist--make-repl-session
           :key context-file
           :context-file context-file
           :root root
           :process-buffer process-buffer
           :partial ""
           :pending (make-hash-table :test #'equal)
           :next-id 0
           :generation 0
           :attached (and endpoint t)
           :endpoint endpoint
           :attached-capabilities nil))
         (process
          (make-process
           :name (format "kvist-repl-%s%s"
                         (file-name-base context-file)
                         (if endpoint "-attached" ""))
           :buffer process-buffer
           :command (if endpoint
                        (list (kvist--executable context-file)
                              "repl" context-file
                              "--attach" endpoint
                              "--protocol" "jsonl")
                      (list (kvist--executable context-file)
                            "repl" context-file
                            "--protocol" "jsonl"))
           :connection-type 'pipe
           :coding 'utf-8-unix
           :noquery t
           :filter #'kvist--repl-process-filter
           :sentinel #'kvist--repl-process-sentinel)))
    (setf (kvist--repl-session-process session) process)
    (process-put process 'kvist-repl-session session)
    (puthash context-file session kvist--repl-sessions)
    (display-buffer (kvist--repl-create-interface session))
    (message "Kvist REPL started: %s" context-file)
    session))

(defun kvist--repl-session (&optional source-file)
  "Return a live package session for SOURCE-FILE, starting it when needed."
  (let* ((key (kvist--repl-key-for-file source-file))
         (session (gethash key kvist--repl-sessions)))
    (if (and session
             (process-live-p (kvist--repl-session-process session)))
        session
      (if kvist-repl-auto-start
          (kvist--repl-start-session source-file)
        (user-error
         "No active Kvist REPL; run M-x kvist-repl-start")))))

(defun kvist--repl-ensure-tooling-context (session source-file op)
  "Reject package-local tooling OP that still requires the entry context."
  (when (and source-file
             (member op '("expand" "macroexpand"))
             (not (equal (file-truename source-file)
                         (file-truename
                          (kvist--repl-session-context-file session)))))
    (user-error
     (concat
      "Package-local %s from imported source is not implemented yet; "
      "evaluation and inspection are package-aware")
     op)))

(defun kvist--repl-request
    (op source callback &optional no-print source-file handle path index key-source
        offset limit source-line source-column pause-id pause-before trace
        trace-limit trace-values trace-value-limit request-name request-abi)
  "Send OP with SOURCE to the package session and invoke CALLBACK on completion."
  (let* ((session (kvist--repl-session source-file))
         (next (1+ (kvist--repl-session-next-id session)))
         (id (format "emacs-%d" next))
         (request `((id . ,id) (op . ,op) (source . ,source))))
    (kvist--repl-ensure-tooling-context session source-file op)
    (setf (kvist--repl-session-next-id session) next)
    (when no-print
      (setq request (append request '((no_print . t)))))
    (when handle
      (setq request (append request `((handle . ,handle)))))
    (when path
      (setq request (append request `((path . ,path)))))
    (when (numberp index)
      (setq request (append request `((index . ,index)))))
    (when key-source
      (setq request (append request `((key_source . ,key-source)))))
    (when (numberp offset)
      (setq request (append request `((offset . ,offset)))))
    (when (numberp limit)
      (setq request (append request `((limit . ,limit)))))
    (when source-file
      (setq request
            (append request
                    `((source_path . ,(expand-file-name source-file))))))
    (when (numberp source-line)
      (setq request (append request `((line . ,source-line)))))
    (when (numberp source-column)
      (setq request (append request `((column . ,source-column)))))
    (when pause-id
      (setq request (append request `((pause_id . ,pause-id)))))
    (when pause-before
      (setq request (append request '((pause_before . t)))))
    (when trace
      (setq request (append request '((trace . t)))))
    (when (numberp trace-limit)
      (setq request (append request `((trace_limit . ,trace-limit)))))
    (when trace-values
      (setq request (append request '((trace_values . t)))))
    (when (and (numberp kvist-repl-evaluation-timeout-ms)
               (> kvist-repl-evaluation-timeout-ms 0)
               (not (kvist--repl-session-attached session))
               (member op '("eval" "inspect" "inspect-page")))
      (setq request
            (append request
                    `((timeout_ms . ,kvist-repl-evaluation-timeout-ms)))))
    (when (numberp trace-value-limit)
      (setq request
            (append request
                    `((trace_value_limit . ,trace-value-limit)))))
    (when request-name
      (setq request (append request `((name . ,request-name)))))
    (when request-abi
      (setq request (append request `((abi . ,request-abi)))))
    (puthash id callback (kvist--repl-session-pending session))
    (process-put (kvist--repl-session-process session)
                 (intern (concat "kvist-request-" id))
                 (list :text ""))
    (process-send-string
     (kvist--repl-session-process session)
     (concat (json-encode request) "\n"))
    id))

(defun kvist-repl-wait (&optional timeout)
  "Wait for current package requests, primarily for scripts and tests.
TIMEOUT defaults to 120 seconds."
  (interactive)
  (let* ((session (kvist--repl-session))
         (deadline (+ (float-time) (or timeout 120.0))))
    (while (and (> (hash-table-count
                    (kvist--repl-session-pending session))
                   0)
                (< (float-time) deadline)
                (process-live-p (kvist--repl-session-process session)))
      (accept-process-output (kvist--repl-session-process session) 0.1))
    (when (> (hash-table-count (kvist--repl-session-pending session)) 0)
      (error "Timed out waiting for Kvist REPL"))))

;;;###autoload
(defun kvist-repl-start ()
  "Start this package's REPL and select its interactive buffer."
  (interactive)
  (let* ((key (kvist--current-repl-key))
         (existing (gethash key kvist--repl-sessions))
         (session
          (if (and existing
                   (process-live-p
                    (kvist--repl-session-process existing)))
              existing
            (kvist--repl-start-session key)))
         (buffer
          (or (kvist--repl-session-interface-buffer session)
              (kvist--repl-create-interface session))))
    (pop-to-buffer buffer)
    (message "Kvist REPL running: %s"
             (kvist--repl-session-context-file session))))

;;;###autoload
(defun kvist-repl ()
  "Start or switch to this package's interactive REPL."
  (interactive)
  (kvist-repl-start))

;;;###autoload
(defun kvist-repl-restart ()
  "Restart this package's REPL and select a fresh interface buffer."
  (interactive)
  (let* ((key (kvist--current-repl-key))
         (session (gethash key kvist--repl-sessions)))
    (when session
      (kvist--repl-stop-session session t))
    (kvist--repl-start-session key)
    (pop-to-buffer
     (kvist--repl-session-interface-buffer
      (gethash key kvist--repl-sessions)))))

(defun kvist-repl-reset ()
  "Reset the current package's native REPL state."
  (interactive)
  (kvist--repl-request
   "reset" ""
   (lambda (result)
     (message "%s"
              (if (plist-get result :success)
                  "Kvist REPL reset"
                (plist-get result :message))))))

(defun kvist--repl-named-request (op name callback)
  "Send named protocol operation OP for NAME and invoke CALLBACK."
  (apply #'kvist--repl-request
         op
         ""
         callback
         (append (make-list 16 nil) (list name))))

(defun kvist--repl-tooling-sync (op name source source-file &optional timeout)
  "Return structured live tooling result for OP and NAME.
SOURCE is the current unsaved buffer text and SOURCE-FILE selects its package
session.  Wait at most TIMEOUT seconds, defaulting to five.  Return nil when
there is no existing live session; passive editor tooling must never start
one."
  (let* ((key (kvist--repl-key-for-file source-file))
         (session (gethash key kvist--repl-sessions)))
    (when (and session
               (process-live-p (kvist--repl-session-process session)))
      (let ((result nil)
            (finished nil)
            (args (make-list 17 nil)))
        (setf (nth 1 args) source-file)
        (setf (nth 16 args) name)
        (apply #'kvist--repl-request
               op source
               (lambda (value)
                 (setq result value)
                 (setq finished t))
               args)
        (let ((process (kvist--repl-session-process session))
              (deadline (+ (float-time) (or timeout 5.0))))
          (while (and (not finished)
                      (< (float-time) deadline)
                      (process-live-p process))
            (accept-process-output process 0.05)))
        (unless finished
          (error "Timed out waiting for Kvist session tooling"))
        result))))

(defun kvist--repl-completion-symbols (prefix)
  "Return live completion symbols for PREFIX at the current REPL prompt."
  (let* ((session (kvist--repl-interface-session))
         (source-file (kvist--repl-session-context-file session))
         (source
          (if (kvist--package-prefix prefix)
              ""
            (buffer-substring-no-properties
             (marker-position kvist--repl-input-marker)
             (point-max))))
         (result
          (kvist--repl-tooling-sync
           "complete" prefix source source-file 1.0)))
    (when (plist-get result :success)
      (mapcar #'kvist--protocol-symbol (plist-get result :symbols)))))

(defun kvist--repl-stop-session (session &optional kill-interface)
  "Stop and forget SESSION.
When KILL-INTERFACE is non-nil, also kill its interactive buffer."
  (when session
    (let ((interface (kvist--repl-session-interface-buffer session)))
      (when (and kill-interface (buffer-live-p interface))
        (with-current-buffer interface
          (setq kvist--repl-buffer-stopping t))
        (kill-buffer interface)))
    (when (process-live-p (kvist--repl-session-process session))
      (process-send-string (kvist--repl-session-process session)
                           "{\"id\":\"emacs-close\",\"op\":\"close\"}\n")
      (delete-process (kvist--repl-session-process session)))
    (kvist--repl-delete-session session)))

(defun kvist--attached-session ()
  "Return the current live attached session or signal a user error."
  (let* ((key (kvist--repl-key-for-file))
         (session (gethash key kvist--repl-sessions)))
    (unless (and session
                 (process-live-p (kvist--repl-session-process session))
                 (kvist--repl-session-attached session))
      (user-error "This package has no Olive-attached Kvist REPL"))
    session))

(defun kvist--present-attached-session (result)
  "Present attached session RESULT in the generic status buffer."
  (if (not (plist-get result :success))
      (message "Kvist attached session: %s"
               (or (plist-get result :message) "unknown error"))
    (let ((buffer (kvist--prepare-buffer kvist-attached-buffer-name))
          (capabilities (plist-get result :attached-capabilities)))
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (insert (format "Endpoint: %s\n"
                          (or (plist-get result :endpoint) "unknown")))
          (insert (format "Application generation: %s\n"
                          (plist-get result :application-generation)))
          (insert (format "Attached REPL generation: %s\n\n"
                          (plist-get result :attached-generation)))
          (insert "Capabilities:\n")
          (if capabilities
              (dolist (capability capabilities)
                (insert (format "  %s\n    %s\n"
                                (alist-get 'name capability)
                                (alist-get 'signature capability))))
            (insert "  none\n"))))
      (pop-to-buffer buffer))))

;;;###autoload
(defun kvist-repl-attach (endpoint)
  "Connect this package's generic REPL client to Olive ENDPOINT."
  (interactive "DOlive REPL endpoint: ")
  (let* ((canonical-endpoint
          (directory-file-name (expand-file-name endpoint)))
         (key (kvist--repl-key-for-file))
         (existing (gethash key kvist--repl-sessions)))
    (unless (file-directory-p canonical-endpoint)
      (user-error "Olive REPL endpoint does not exist: %s"
                  canonical-endpoint))
    (kvist--repl-stop-session existing t)
    (kvist--repl-start-session buffer-file-name canonical-endpoint)
    (message "Connecting Kvist REPL to %s" canonical-endpoint)))

;;;###autoload
(defun kvist-repl-attached-status ()
  "Discover and display the current Olive-attached session."
  (interactive)
  (kvist--attached-session)
  (kvist--repl-request
   "attached-session" ""
   #'kvist--present-attached-session))

;;;###autoload
(defun kvist-repl-invoke-capability ()
  "Discover and invoke a typed capability in the attached application."
  (interactive)
  (let ((context-file
         (kvist--repl-session-context-file (kvist--attached-session))))
    (kvist--repl-request
     "capabilities" ""
     (lambda (status)
       (if (not (plist-get status :success))
           (message "Kvist capability discovery: %s"
                    (plist-get status :message))
         (let* ((capabilities (plist-get status :attached-capabilities))
                (names (mapcar (lambda (capability)
                                 (alist-get 'name capability))
                               capabilities)))
           (if (not names)
               (message "The attached application exposes no capabilities")
             (let* ((name (completing-read "Capability: " names nil t))
                    (capability
                     (seq-find (lambda (candidate)
                                 (equal name (alist-get 'name candidate)))
                               capabilities))
                    (signature (alist-get 'signature capability))
                    (input (read-string (format "%s input: " name))))
               (apply #'kvist--repl-request
                      "invoke-capability"
                      input
                      (lambda (result)
                        (if (plist-get result :success)
                            (message "%s" (plist-get result :text))
                          (message "Kvist capability %s: %s"
                                   name
                                   (plist-get result :message))))
                      (append (list nil context-file)
                              (make-list 14 nil)
                              (list name signature)))))))))))

;;;###autoload
(defun kvist-repl-attached-reload ()
  "Reload the attached application and wait for its next generation."
  (interactive)
  (kvist--attached-session)
  (kvist--repl-request
   "reload" ""
   (lambda (result)
     (message "%s"
              (if (plist-get result :success)
                  (format "Kvist application reloaded at generation %s"
                          (plist-get result :generation))
                (format "Kvist application reload failed: %s"
                        (or (plist-get result :message)
                            "unknown error")))))))

(defun kvist--read-checkpoint-name (prompt)
  "Read a non-empty checkpoint name using PROMPT."
  (let ((name (string-trim
               (read-string prompt nil 'kvist-checkpoint-name-history))))
    (when (string-empty-p name)
      (user-error "Checkpoint name must not be empty"))
    name))

(defun kvist-repl-checkpoint (name)
  "Capture mutable persistent REPL state in checkpoint NAME."
  (interactive (list (kvist--read-checkpoint-name "Save checkpoint: ")))
  (kvist--repl-named-request
   "checkpoint"
   name
   (lambda (result)
     (if (plist-get result :success)
         (let ((count (or (plist-get result :checkpoint-bindings) 0)))
           (message "Saved Kvist checkpoint %s (%s mutable binding%s)"
                    name count (if (= count 1) "" "s")))
       (message "Kvist checkpoint failed: %s"
                (or (plist-get result :message) "unknown error"))))))

(defun kvist-repl-checkpoint-restore (name)
  "Restore mutable persistent REPL state from checkpoint NAME."
  (interactive (list (kvist--read-checkpoint-name "Restore checkpoint: ")))
  (kvist--repl-named-request
   "checkpoint-restore"
   name
   (lambda (result)
     (message "%s"
              (if (plist-get result :success)
                  (format "Restored Kvist checkpoint %s" name)
                (format "Kvist restore failed: %s"
                        (plist-get result :message)))))))

(defun kvist-repl-checkpoint-drop (name)
  "Drop named REPL checkpoint NAME."
  (interactive (list (kvist--read-checkpoint-name "Drop checkpoint: ")))
  (kvist--repl-named-request
   "checkpoint-drop"
   name
   (lambda (result)
     (message "%s"
              (if (plist-get result :success)
                  (format "Dropped Kvist checkpoint %s" name)
                (format "Kvist checkpoint drop failed: %s"
                        (plist-get result :message)))))))

(defun kvist-repl-checkpoints ()
  "Show named checkpoints in the current package REPL."
  (interactive)
  (kvist--repl-request
   "checkpoints"
   ""
   (lambda (result)
     (if (not (plist-get result :success))
         (message "Kvist checkpoints: %s" (plist-get result :message))
       (let ((buffer (kvist--prepare-buffer kvist-checkpoints-buffer-name))
             (checkpoints (plist-get result :checkpoints)))
         (with-current-buffer buffer
           (let ((inhibit-read-only t))
             (insert (format "Named REPL checkpoints: %d\n\n"
                             (length checkpoints)))
             (dolist (checkpoint checkpoints)
               (insert
                (format "%s  (%s mutable binding%s)\n"
                        (alist-get 'name checkpoint)
                        (alist-get 'bindings checkpoint)
                        (if (= (alist-get 'bindings checkpoint) 1)
                            ""
                          "s"))))))
         (display-buffer buffer))))))

(defun kvist-repl-generations ()
  "Show native generations loaded by the current package REPL."
  (interactive)
  (kvist--repl-request
   "generations"
   ""
   (lambda (result)
     (if (not (plist-get result :success))
         (message "Kvist generations: %s" (plist-get result :message))
       (let ((buffer (kvist--prepare-buffer kvist-generations-buffer-name))
             (generations (plist-get result :generations)))
         (with-current-buffer buffer
           (let ((inhibit-read-only t))
             (insert (format "Loaded native generations: %d\n\n"
                             (length generations)))
             (dolist (generation generations)
               (insert (format "Generation %s\n"
                               (alist-get 'generation generation)))
               (dolist (field '((source_path . "Odin")
                                (map_path . "Source map")
                                (library_path . "Library")))
                 (let ((path (alist-get (car field) generation)))
                   (when path
                     (insert (format "  %s: " (cdr field)))
                     (insert-text-button
                      path
                      'follow-link t
                      'help-echo "Open this generation artifact"
                      'action
                      (lambda (_button) (find-file path)))
                     (insert "\n"))))
               (insert "\n"))))
         (display-buffer buffer))))))

(defun kvist--repl-binding-name (prompt)
  "Read a live binding name with the symbol at point as PROMPT's default."
  (let ((default (kvist--identifier-at-point)))
    (read-string
     (if default
         (format "%s (default %s): " prompt default)
       (format "%s: " prompt))
     nil nil default)))

(defun kvist--insert-definition-location (definition)
  "Insert a navigable source location for protocol DEFINITION metadata."
  (let ((path (alist-get 'source_path definition))
        (line (or (alist-get 'source_start_line definition) 1))
        (column (or (alist-get 'source_start_column definition) 1)))
    (when path
      (insert "  ")
      (insert-text-button
       (format "%s:%s:%s" path line column)
       'follow-link t
       'help-echo "Visit this definition"
       'action
       (lambda (_button)
         (find-file path)
         (goto-char (point-min))
         (forward-line (1- line))
         (move-to-column (1- column))))
      (insert "\n"))))

(defun kvist-repl-versions-at-point (&optional name)
  "Show all retained native versions of live binding NAME.
Interactively, use the symbol at point as the default."
  (interactive)
  (let ((binding (or name (kvist--repl-binding-name "Versions for binding"))))
    (kvist--repl-named-request
     "versions" binding
     (lambda (result)
       (if (not (plist-get result :success))
           (message "Kvist versions: %s" (plist-get result :message))
         (let ((buffer (kvist--prepare-buffer kvist-versions-buffer-name))
               (versions (plist-get result :versions)))
           (with-current-buffer buffer
             (let ((inhibit-read-only t))
               (insert (format "Native versions of %s: %d\n\n"
                               binding (length versions)))
               (dolist (version versions)
                 (insert (format "Version %s  generation %s  %s\n"
                                 (alist-get 'version version)
                                 (alist-get 'generation version)
                                 (or (alist-get 'abi version) "")))
                 (kvist--insert-definition-location version)
                 (when-let ((dependencies (alist-get 'dependencies version)))
                   (insert (format "  depends on: %s\n"
                                   (string-join dependencies ", "))))
                 (insert "\n"))))
           (display-buffer buffer)))))))

(defun kvist-repl-dependents-at-point (&optional name)
  "Show transitive live dependents of binding NAME and their stale status.
Interactively, use the symbol at point as the default."
  (interactive)
  (let ((binding (or name (kvist--repl-binding-name "Dependents of binding"))))
    (kvist--repl-named-request
     "dependents" binding
     (lambda (result)
       (if (not (plist-get result :success))
           (message "Kvist dependents: %s" (plist-get result :message))
         (let ((buffer (kvist--prepare-buffer kvist-dependents-buffer-name))
               (dependents (plist-get result :bindings)))
           (with-current-buffer buffer
             (let ((inhibit-read-only t))
               (insert (format "Transitive dependents of %s: %d\n\n"
                               binding (length dependents)))
               (if (null dependents)
                   (insert "No live dependents.\n")
                 (dolist (dependent dependents)
                   (insert (format "%s  version %s  generation %s  %s\n"
                                   (alist-get 'name dependent)
                                   (alist-get 'version dependent)
                                   (alist-get 'generation dependent)
                                   (if (alist-get 'stale dependent)
                                       "STALE"
                                     "current")))
                   (insert (format "  %s\n"
                                   (or (alist-get 'abi dependent) "")))
                   (when-let ((dependencies
                               (alist-get 'dependencies dependent)))
                     (insert (format "  depends on: %s\n"
                                     (string-join dependencies ", "))))))
               (insert "\nC-c v r refreshes stale dependents atomically.\n")))
           (display-buffer buffer)))))))

(defun kvist-repl-refresh-dependents-at-point (&optional name)
  "Recompile stale transitive dependents of live binding NAME atomically.
Interactively, use the symbol at point as the default."
  (interactive)
  (let ((binding
         (or name (kvist--repl-binding-name "Refresh dependents of binding"))))
    (kvist--repl-named-request
     "refresh-dependents" binding
     (lambda (result)
       (message "%s"
                (if (plist-get result :success)
                    (format "Refreshed stale dependents of %s" binding)
                  (format "Kvist refresh failed: %s"
                          (plist-get result :message))))))))

(defun kvist--launch-native-debugger (debug-session)
  "Launch the configured native debugger for DEBUG-SESSION metadata."
  (require 'comint)
  (let* ((pid (plist-get debug-session :worker-pid))
         (command (and (numberp pid)
                       (format kvist-native-debugger-command pid)))
         (buffer (get-buffer-create kvist-native-debugger-buffer-name)))
    (unless (and command (> pid 0))
      (user-error "Kvist REPL did not report a live native worker"))
    (when-let ((process (get-buffer-process buffer)))
      (unless (yes-or-no-p "Replace the existing Kvist debugger process? ")
        (user-error "Debugger launch cancelled"))
      (delete-process process))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)))
    (make-comint-in-buffer
     "Kvist Native Debugger"
     buffer
     shell-file-name
     nil
     shell-command-switch
     command)
    (pop-to-buffer buffer)
    (message "Attached native debugger to Kvist worker %d (epoch %s)"
             pid
             (or (plist-get debug-session :worker-epoch) "?"))))

(defun kvist-debug-native-worker ()
  "Attach the configured native debugger to the current REPL worker."
  (interactive)
  (kvist--repl-request
   "debug-session"
   ""
   (lambda (result)
     (if (plist-get result :success)
         (funcall kvist-native-debugger-launch-function result)
       (message "Kvist debugger: %s" (plist-get result :message))))))

(defun kvist--set-native-breakpoints (locations)
  "Send translated native breakpoint LOCATIONS to the debugger comint buffer."
  (let* ((buffer (get-buffer kvist-native-debugger-buffer-name))
         (process (and buffer (get-buffer-process buffer)))
         (seen (make-hash-table :test #'equal))
         (count 0))
    (unless (process-live-p process)
      (user-error "Attach the Kvist native debugger first with C-c M-b"))
    (dolist (location locations)
      (let* ((path (alist-get 'generated_path location))
             (line (alist-get 'generated_start_line location))
             (key (cons path line)))
        (when (and (stringp path)
                   (numberp line)
                   (> line 0)
                   (not (gethash key seen)))
          (puthash key t seen)
          (comint-send-string
           process
           (if (eq system-type 'darwin)
               (format "breakpoint set --file %s --line %d\n"
                       (shell-quote-argument path) line)
             (format "break %s:%d\n"
                     (shell-quote-argument path) line)))
          (setq count (1+ count)))))
    (message "Set %d native breakpoint%s for Kvist source"
             count
             (if (= count 1) "" "s"))))

(defun kvist-debug-breakpoint-at-point ()
  "Translate the current Kvist line and register native breakpoints."
  (interactive)
  (unless buffer-file-name
    (user-error "Kvist breakpoints require a file-backed buffer"))
  (let ((source-file (expand-file-name buffer-file-name))
        (source-line (line-number-at-pos)))
    (kvist--repl-request
     "breakpoint-locations"
     ""
     (lambda (result)
       (if (not (plist-get result :success))
           (message "Kvist breakpoint: %s" (plist-get result :message))
         (let ((locations (plist-get result :breakpoints)))
           (if locations
               (funcall kvist-native-breakpoint-function locations)
             (message
              "No loaded native code maps to %s:%d; evaluate the definition first"
              source-file source-line)))))
     nil source-file nil nil nil nil nil nil source-line)))

(defun kvist-debug-continue ()
  "Continue the current instrumented Kvist evaluation."
  (interactive)
  (let* ((session (kvist--repl-session
                   (kvist--debug-context-source-file)))
         (pause-id (kvist--repl-session-pause-id session)))
    (unless pause-id
      (user-error "The Kvist REPL is not paused"))
    (kvist--repl-request
     "debug-continue"
     ""
     (lambda (result)
       (unless (plist-get result :success)
         (message "Kvist continue: %s" (plist-get result :message))))
     nil
     (kvist--repl-session-context-file session)
     nil nil nil nil nil nil nil nil
     pause-id)))

(defun kvist-debug-abort ()
  "Abort the current instrumented evaluation without resetting the REPL.
The runtime unwinds cooperatively through instrumented Kvist frames, running
normal `defer' cleanup and preserving retained session state."
  (interactive)
  (let* ((session (kvist--repl-session
                   (kvist--debug-context-source-file)))
         (pause-id (kvist--repl-session-pause-id session)))
    (unless pause-id
      (user-error "The Kvist REPL is not paused"))
    (kvist--repl-request
     "debug-abort"
     ""
     (lambda (result)
       (unless (plist-get result :success)
         (message "Kvist abort: %s" (plist-get result :message))))
     nil
     (kvist--repl-session-context-file session)
     nil nil nil nil nil nil nil nil
     pause-id)))

(defun kvist-repl-interrupt ()
  "Terminate the disposable worker for the current paused evaluation.
This is intentionally available only for a standalone REPL safe-point pause.
The next evaluation starts a clean worker; native session values are not
replayed."
  (interactive)
  (let* ((session (kvist--repl-session))
         (pause-id (kvist--repl-session-pause-id session)))
    (when (kvist--repl-session-attached session)
      (user-error "Forced interrupt is unavailable for an attached application"))
    (unless pause-id
      (user-error "The Kvist REPL is not paused"))
    (kvist--repl-request
     "interrupt"
     ""
     (lambda (result)
       (if (plist-get result :success)
           (message "Kvist worker interrupted")
         (message "Kvist interrupt: %s" (plist-get result :message))))
     nil
     (kvist--repl-session-context-file session)
     nil nil nil nil nil nil nil nil
     pause-id)))

(defun kvist--present-condition (session event)
  "Present recoverable condition EVENT belonging to SESSION."
  (let* ((buffer (kvist--prepare-buffer kvist-condition-buffer-name))
         (frame (car (alist-get 'frames event)))
         (locals (and frame (alist-get 'locals frame)))
         (restarts (alist-get 'restarts event)))
    (with-current-buffer buffer
      (setq-local kvist--condition-context-file
                  (kvist--repl-session-context-file session))
      (local-set-key (kbd "r") #'kvist-debug-recover)
      (let ((inhibit-read-only t))
        (insert (format "Condition: %s\n"
                        (or (alist-get 'condition_type event)
                            "kvist/condition")))
        (insert (format "Message: %s\n"
                        (or (alist-get 'message event) "")))
        (when-let ((data (alist-get 'condition_data event)))
          (unless (string-empty-p data)
            (insert (format "Data: %s\n" data))))
        (insert (format "Source: %s:%s:%s\n"
                        (or (alist-get 'source_path event) "<eval>")
                        (or (alist-get 'line event) "?")
                        (or (alist-get 'column event) "?")))
        (insert (format "Pause: %s\n\n"
                        (or (alist-get 'pause_id event) "unknown")))
        (if locals
            (progn
              (insert "Locals:\n")
              (dolist (local locals)
                (insert
                 (format "  %s: %s = %s\n"
                         (or (alist-get 'name local) "unknown")
                         (or (alist-get 'type local) "unknown")
                         (or (alist-get 'value local)
                             "<unavailable>")))))
          (insert "Locals: none exposed at this safe point\n"))
        (insert "\nRecovery options:\n")
        (if restarts
            (dolist (restart restarts)
              (let ((name (alist-get 'name restart)))
                (insert "  ")
                (insert-text-button
                 name
                 'follow-link t
                 'help-echo (or (alist-get 'label restart)
                                "Select this recovery")
                 'action
                 (lambda (_button)
                   (kvist-debug-recover name)))
                (insert (format "  %s\n"
                                (concat
                                 (or (alist-get 'label restart) "")
                                 (if (alist-get 'requires_value restart)
                                     (format "  [value: %s]"
                                             (or
                                              (alist-get 'value_type restart)
                                              "unknown"))
                                   ""))))))
          (insert "  none\n"))
        (insert "\nPress r to recover.\n")))
    (display-buffer buffer)))

(defun kvist-debug-recover (&optional recovery-name recovery-value)
  "Choose RECOVERY-NAME with optional RECOVERY-VALUE for the active condition."
  (interactive)
  (let* ((source-file (or kvist--condition-context-file
                          buffer-file-name))
         (session (kvist--repl-session source-file))
         (condition-event (kvist--repl-session-condition session))
         (pause-id (kvist--repl-session-pause-id session))
         (restarts (and condition-event
                        (alist-get 'restarts condition-event)))
         (names (delq nil
                      (mapcar (lambda (restart)
                                (alist-get 'name restart))
                              restarts)))
         (chosen (or recovery-name
                     (and names
                          (completing-read
                           "Kvist recovery: "
                           names nil t nil nil (car names)))))
         (selected (seq-find
                    (lambda (restart)
                      (equal (alist-get 'name restart) chosen))
                    restarts))
         (requires-value (and selected
                              (alist-get 'requires_value selected)))
         (value-type (and selected
                          (alist-get 'value_type selected)))
         (value (if requires-value
                    (or recovery-value
                        (read-string
                         (format "Value (%s): "
                                 (or value-type "unknown"))))
                  "")))
    (unless (and pause-id condition-event)
      (user-error "No recoverable Kvist condition is active"))
    (unless (member chosen names)
      (user-error "Recovery is not available: %s" chosen))
    (kvist--repl-request
     "debug-restart"
     value
     (lambda (result)
       (unless (plist-get result :success)
         (message "Kvist recovery: %s" (plist-get result :message))))
     nil
     (kvist--repl-session-context-file session)
     nil nil nil nil nil nil nil nil
     pause-id
     nil nil nil nil nil
     chosen)))

(defun kvist--debug-step-command (operation label)
  "Send depth-aware debug step OPERATION described by LABEL."
  (let* ((session (kvist--repl-session
                   (kvist--debug-context-source-file)))
         (pause-id (kvist--repl-session-pause-id session)))
    (unless pause-id
      (user-error "The Kvist REPL is not paused"))
    (kvist--repl-request
     operation
     ""
     (lambda (result)
       (unless (plist-get result :success)
         (message "Kvist %s: %s"
                  label
                  (plist-get result :message))))
     nil
     (kvist--repl-session-context-file session)
     nil nil nil nil nil nil nil nil
     pause-id)))

(defun kvist-debug-step ()
  "Resume until the next instrumented Kvist form safe point."
  (interactive)
  (kvist--debug-step-command "debug-step" "step"))

(defun kvist-debug-step-over ()
  "Resume to the next safe point outside deeper Kvist calls."
  (interactive)
  (kvist--debug-step-command "debug-step-over" "step over"))

(defun kvist-debug-step-out ()
  "Resume to the next safe point after leaving the current Kvist call."
  (interactive)
  (kvist--debug-step-command "debug-step-out" "step out"))

(defun kvist--present-debug-frame (frame source-file source-buffer)
  "Present editor-neutral debug FRAME metadata."
  (let ((buffer (kvist--prepare-buffer kvist-debug-frame-buffer-name))
        (locals (alist-get 'locals frame))
        (collections (alist-get 'collections frame)))
    (with-current-buffer buffer
      (setq-local kvist--debug-frame-collections collections)
      (setq-local kvist--debug-frame-source-file source-file)
      (setq-local kvist--debug-frame-source-buffer source-buffer)
      (setq-local kvist-presentation-quit-command #'kvist-debug-abort)
      (local-set-key (kbd "n") #'kvist-debug-step)
      (local-set-key (kbd "o") #'kvist-debug-step-over)
      (local-set-key (kbd "u") #'kvist-debug-step-out)
      (local-set-key (kbd "c") #'kvist-debug-continue)
      (local-set-key (kbd "e") #'kvist-debug-eval-expression)
      (local-set-key (kbd "p") #'kvist-debug-page)
      (local-set-key (kbd "g") #'kvist-debug-show-frame)
      (local-set-key (kbd "q") #'kvist-debug-abort)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Commands: n next/into   o step over  u step out   c continue\n")
        (insert "          e eval        p page       g refresh    q abort\n\n")
        (insert (format "Frame: %s\n"
                        (or (alist-get 'frame_id frame) "unknown")))
        (insert (format "Pause: %s\n"
                        (or (alist-get 'pause_id frame) "unknown")))
        (insert (format "Generation: %s\n"
                        (or (alist-get 'generation frame) "unknown")))
        (insert (format "Phase: %s\n"
                        (or (alist-get 'phase frame) "unknown")))
        (insert (format "Source: %s:%s:%s\n\n"
                        (or (alist-get 'source_path frame) "<eval>")
                        (or (alist-get 'line frame) "?")
                        (or (alist-get 'column frame) "?")))
        (if (not locals)
            (insert "Locals: none exposed at this safe point\n")
          (insert "Locals:\n")
          (dolist (local locals)
            (insert
             (format "  %s: %s  %s  %s  = %s\n"
                     (or (alist-get 'name local) "unknown")
                     (or (alist-get 'type local) "unknown")
                     (if (alist-get 'mutable local)
                         "mutable"
                       "immutable")
                     (or (alist-get 'ownership local) "unknown")
                     (or (alist-get 'value local) "<unavailable>")))
            (when (alist-get 'element_type local)
              (insert
               (format "    elements: %s  capture: %s  total: %s%s\n"
                       (alist-get 'element_type local)
                       (or (alist-get 'capture_limit local) "?")
                       (or (alist-get 'total local) "?")
                       (if (eq (alist-get 'truncated local) t)
                           "  truncated"
                         ""))))
            (when (alist-get 'key_type local)
              (insert
               (format "    entries: %s -> %s  capture: %s  total: %s%s\n"
                       (alist-get 'key_type local)
                       (or (alist-get 'value_type local) "unknown")
                       (or (alist-get 'capture_limit local) "?")
                       (or (alist-get 'total local) "?")
                       (if (eq (alist-get 'truncated local) t)
                           "  truncated"
                         ""))))
            (dolist (path (alist-get 'paths local))
              (insert
               (format "    %s: %s = %s\n"
                       (or (alist-get 'path path) "unknown")
                       (or (alist-get 'type path) "unknown")
                       (or (alist-get 'value path)
                           "<unavailable>")))))))
        (when collections
          (insert "\nPageable collections:\n")
          (dolist (collection collections)
            (let ((path (alist-get 'path collection))
                  (shape (alist-get 'shape collection))
                  (element-type (alist-get 'element_type collection))
                  (key-type (alist-get 'key_type collection))
                  (value-type (alist-get 'value_type collection))
                  (pause-id (alist-get 'pause_id frame)))
              (insert "  ")
              (insert-text-button
               path
               'follow-link t
               'help-echo "Browse this live collection while paused"
               'action
               (lambda (_button)
                 (kvist--debug-page-submit
                  path 0 source-file source-buffer pause-id)))
              (insert
               (format "  %s%s\n"
                       shape
                       (cond
                        (element-type
                         (format " of %s" element-type))
                        (key-type
                         (format " %s -> %s"
                                 key-type
                                 (or value-type "unknown")))
                        (t ""))))))))
    (display-buffer buffer)))

(defun kvist--maybe-refresh-debug-frame-buffer (session frame)
  "Refresh an existing debug frame buffer for SESSION with FRAME.

The frame buffer is created only by an explicit initial inspection.  Once it
exists, every subsequent pause keeps it synchronized automatically."
  (when-let ((buffer (get-buffer kvist-debug-frame-buffer-name)))
    (let ((source-buffer
           (with-current-buffer buffer
             (or kvist--debug-frame-source-buffer
                 (and (overlayp (kvist--repl-session-pause-overlay session))
                      (overlay-buffer
                       (kvist--repl-session-pause-overlay session))))))
          (source-file (kvist--repl-session-context-file session)))
      (if frame
          (kvist--present-debug-frame frame source-file source-buffer)
        (let ((pause-id (kvist--repl-session-pause-id session)))
          (kvist--repl-request
           "debug-frame" ""
           (lambda (result)
             (when-let ((queried-frame (car (plist-get result :frames))))
               (kvist--present-debug-frame
                queried-frame source-file source-buffer)))
           nil source-file nil nil nil nil nil nil nil nil pause-id))))))

(defun kvist-debug-show-frame ()
  "Request and display the active instrumented Kvist frame."
  (interactive)
  (let* ((source-buffer (or kvist--debug-frame-source-buffer
                            (current-buffer)))
         (session (kvist--repl-session
                   (kvist--debug-context-source-file)))
         (source-file (kvist--repl-session-context-file session))
         (pause-id (kvist--repl-session-pause-id session)))
    (unless pause-id
      (user-error "The Kvist REPL is not paused"))
    (kvist--repl-request
     "debug-frame"
     ""
     (lambda (result)
       (if-let ((frame (car (plist-get result :frames))))
           (kvist--present-debug-frame
            frame source-file source-buffer)
         (message "Kvist frame: %s"
                  (or (plist-get result :message)
                      "no frame descriptor"))))
     nil
     (kvist--repl-session-context-file session)
     nil nil nil nil nil nil nil nil
     pause-id)))

(defun kvist--present-debug-page
    (result path source-file source-buffer pause-id)
  "Present live collection page RESULT for PATH at PAUSE-ID."
  (if (not (plist-get result :success))
      (message "Kvist collection page: %s" (plist-get result :message))
    (let ((buffer (kvist--prepare-buffer kvist-debug-page-buffer-name))
          (entries (plist-get result :entries))
          (shape (plist-get result :shape))
          (offset (or (plist-get result :offset) 0))
          (limit (or (plist-get result :limit)
                     (kvist--debug-page-size)))
          (total (or (plist-get result :total) 0)))
      (with-current-buffer buffer
        (setq-local kvist--debug-page-path path)
        (setq-local kvist--debug-page-offset offset)
        (setq-local kvist--debug-page-limit limit)
        (setq-local kvist--debug-page-total total)
        (setq-local kvist--debug-page-source-file source-file)
        (setq-local kvist--debug-page-source-buffer source-buffer)
        (setq-local kvist--debug-page-pause-id pause-id)
        (local-set-key (kbd "n") #'kvist-debug-page-next)
        (local-set-key (kbd "p") #'kvist-debug-page-previous)
        (local-set-key (kbd "g") #'kvist-debug-page-refresh)
        (let ((inhibit-read-only t))
          (insert (format "Paused collection: %s\n" path))
          (insert (format "Shape: %s\n" (or shape "unknown")))
          (when-let ((element-type (plist-get result :element-type)))
            (insert (format "Element type: %s\n" element-type)))
          (when-let ((key-type (plist-get result :key-type)))
            (insert (format "Key type: %s\n" key-type)))
          (when-let ((value-type (plist-get result :value-type)))
            (insert (format "Value type: %s\n" value-type)))
          (insert (format "Pause: %s\n\n" pause-id))
          (if entries
              (progn
                (insert "Entries:\n")
                (dolist (entry entries)
                  (let ((index (alist-get 'index entry))
                        (key (alist-get 'key entry))
                        (value (alist-get 'value entry)))
                    (insert
                     (cond
                      (key
                       (format "  [%s]  %s\n" key value))
                      ((numberp index)
                       (format "  [%d]  %s\n" index value))
                      (t
                       (format "  %s\n" (or value "unknown"))))))))
            (insert "Entries: none\n"))
          (let ((shown-end (min total (+ offset limit))))
            (insert
             (format "\nPage: %d-%d of %d"
                     (if (< offset total) (1+ offset) 0)
                     shown-end
                     total))
            (when (> offset 0)
              (insert "  p: previous"))
            (when (< shown-end total)
              (insert "  n: next"))
            (insert "  g: refresh\n"))
          (when-let ((collections (plist-get result :collections)))
            (insert "\nDiscovered collections:\n")
            (dolist (collection collections)
              (let ((child-path (alist-get 'path collection)))
                (insert "  ")
                (insert-text-button
                 child-path
                 'follow-link t
                 'help-echo "Browse this newly discovered live collection"
                 'action
                 (lambda (_button)
                   (kvist--debug-page-submit
                    child-path
                    0
                    source-file
                    source-buffer
                    pause-id)))
                (insert
                 (format
                  "  %s\n"
                  (or (alist-get 'shape collection) "unknown")))))))
      (display-buffer buffer)))))

(defun kvist--debug-page-submit
    (path offset source-file source-buffer pause-id)
  "Request PATH at OFFSET from the active paused frame."
  (kvist--repl-request
   "debug-page"
   path
   (lambda (result)
     (kvist--present-debug-page
      result path source-file source-buffer pause-id))
   nil source-file nil nil nil nil
   offset (kvist--debug-page-size)
   nil nil pause-id))

(defun kvist-debug-page (&optional path)
  "Browse pageable collection PATH in the active paused frame."
  (interactive)
  (let* ((source-buffer (or kvist--debug-frame-source-buffer
                            (current-buffer)))
         (session (kvist--repl-session
                   (kvist--debug-context-source-file)))
         (pause-id (kvist--repl-session-pause-id session))
         (frame (kvist--repl-session-debug-frame session))
         (collections (and frame (alist-get 'collections frame)))
         (paths (delq nil
                      (mapcar
                       (lambda (collection)
                         (alist-get 'path collection))
                       collections)))
         (selected
          (or path
              (and paths
                   (completing-read
                    "Paused collection: " paths nil t)))))
    (unless pause-id
      (user-error "The Kvist REPL is not paused"))
    (unless collections
      (user-error "The active frame exposes no pageable collections"))
    (unless (and selected (member selected paths))
      (user-error "Unknown pageable collection in the active frame"))
    (kvist--debug-page-submit
     selected
     0
     (kvist--repl-session-context-file session)
     source-buffer
     pause-id)))

(defun kvist-debug-page-next ()
  "Show the next page of the current live paused collection."
  (interactive)
  (let ((next (+ (or kvist--debug-page-offset 0)
                 (or kvist--debug-page-limit
                     (kvist--debug-page-size)))))
    (if (>= next (or kvist--debug-page-total 0))
        (user-error "Already at the final paused collection page")
      (kvist--debug-page-submit
       kvist--debug-page-path
       next
       kvist--debug-page-source-file
       kvist--debug-page-source-buffer
       kvist--debug-page-pause-id))))

(defun kvist-debug-page-previous ()
  "Show the previous page of the current live paused collection."
  (interactive)
  (let* ((offset (or kvist--debug-page-offset 0))
         (limit (or kvist--debug-page-limit
                    (kvist--debug-page-size))))
    (if (<= offset 0)
        (user-error "Already at the first paused collection page")
      (kvist--debug-page-submit
       kvist--debug-page-path
       (max 0 (- offset limit))
       kvist--debug-page-source-file
       kvist--debug-page-source-buffer
       kvist--debug-page-pause-id))))

(defun kvist-debug-page-refresh ()
  "Refresh the current page of the live paused collection."
  (interactive)
  (kvist--debug-page-submit
   kvist--debug-page-path
   (or kvist--debug-page-offset 0)
   kvist--debug-page-source-file
   kvist--debug-page-source-buffer
   kvist--debug-page-pause-id))

(defun kvist--present-debug-value (expression result)
  "Present paused-frame EXPRESSION and typed RESULT."
  (let ((buffer (kvist--prepare-buffer kvist-debug-value-buffer-name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "%s: %s\n\n%s"
                        expression
                        (or (plist-get result :type) "unknown")
                        (or (plist-get result :text) "")))))
    (display-buffer buffer)))

(defun kvist-debug-eval-expression (expression)
  "Evaluate a pure scalar EXPRESSION in the active paused frame."
  (interactive
   (list
    (read-string "Paused expression: "
                 (or (thing-at-point 'symbol t) ""))))
  (let* ((session (kvist--repl-session
                   (kvist--debug-context-source-file)))
         (pause-id (kvist--repl-session-pause-id session)))
    (unless pause-id
      (user-error "The Kvist REPL is not paused"))
    (kvist--repl-request
     "debug-eval"
     expression
     (lambda (result)
       (if (plist-get result :success)
           (kvist--present-debug-value expression result)
         (message "Kvist frame evaluation: %s"
                  (plist-get result :message))))
     nil
     (kvist--repl-session-context-file session)
     nil nil nil nil nil nil nil nil
     pause-id)))

;;;###autoload
(defun kvist-debug-eval-native-form-at-point (&optional no-print)
  "Compile and evaluate the form at point while native execution is paused.
The form runs in the same worker as the suspended program, so it may call or
compatibly redefine live functions.  Prefix argument NO-PRINT treats it as a
statement.  This is distinct from `kvist-debug-eval-expression', which only
interprets copied scalar values from the selected frame."
  (interactive "P")
  (let* ((bounds (kvist--form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (source-buffer (current-buffer))
         (source-file
          (expand-file-name
           (or buffer-file-name
               (user-error
                "Native break evaluation requires a file-backed buffer"))))
         (source-line (line-number-at-pos (car bounds)))
         (source-column
          (save-excursion
            (goto-char (car bounds))
            (1+ (current-column))))
         (markers (cons (copy-marker (car bounds))
                        (copy-marker (cdr bounds) t)))
         (session (kvist--repl-session source-file))
         (pause-id (kvist--repl-session-pause-id session)))
    (unless pause-id
      (user-error "The Kvist REPL is not paused"))
    (cl-labels
        ((submit
          (effective-no-print)
          (kvist--repl-request
           "debug-eval-native"
           form
           (lambda (result)
             (if (and (not effective-no-print)
                      (not (plist-get result :success))
                      (kvist--void-value-error-p
                       (or (plist-get result :message) "")))
                 (submit t)
               (unwind-protect
                   (kvist--present-repl-result
                    source-buffer 'buffer markers result)
                 (set-marker (car markers) nil)
                 (set-marker (cdr markers) nil))))
           effective-no-print
           source-file
           nil nil nil nil nil nil
           source-line
           source-column
           pause-id)))
      (submit no-print))))

(defun kvist-debug-wait-for-pause (&optional timeout)
  "Wait until the current session pauses, primarily for scripts and tests."
  (let* ((session (kvist--repl-session))
         (deadline (+ (float-time) (or timeout 120.0))))
    (while (and (not (kvist--repl-session-pause-id session))
                (< (float-time) deadline)
                (process-live-p (kvist--repl-session-process session)))
      (accept-process-output (kvist--repl-session-process session) 0.1))
    (unless (kvist--repl-session-pause-id session)
      (error "Timed out waiting for Kvist debug pause"))))

(defun kvist-repl-stop ()
  "Stop and forget the current package's native REPL session."
  (interactive)
  (let* ((key (kvist--current-repl-key))
         (session (gethash key kvist--repl-sessions)))
    (if (not session)
        (message "No Kvist REPL session for this package")
      (kvist--repl-stop-session session t)
      (message "Kvist REPL stopped"))))

(defun kvist--present-inspection
    (result expression source-file source-buffer)
  "Present inspection RESULT for EXPRESSION and remember its stable handle."
  (if (plist-get result :success)
      (let* ((existing-buffer (get-buffer kvist-inspect-buffer-name))
             (previous-current
              (and existing-buffer
                   (buffer-local-value
                    'kvist--inspection-current existing-buffer)))
             (history
              (if kvist--inspection-restoring
                  kvist--inspection-restored-history
                (and existing-buffer
                     (buffer-local-value
                      'kvist--inspection-history existing-buffer))))
             (handle (plist-get result :handle))
             (entry (list :result result
                          :expression expression
                          :source-file source-file
                          :source-buffer source-buffer))
             (previous-handle
              (and previous-current
                   (plist-get (plist-get previous-current :result) :handle)))
             (members (plist-get result :members))
             (entries (plist-get result :entries)))
        (when (and (not kvist--inspection-restoring)
                   previous-current
                   (not (equal previous-handle handle)))
          (push previous-current history))
        (let ((buffer (kvist--prepare-buffer kvist-inspect-buffer-name)))
        (with-current-buffer buffer
          (setq-local kvist--inspection-handle handle)
          (setq-local kvist--inspection-members members)
          (setq-local kvist--inspection-shape (plist-get result :shape))
          (setq-local kvist--inspection-expression expression)
          (setq-local kvist--inspection-offset (plist-get result :offset))
          (setq-local kvist--inspection-limit (plist-get result :limit))
          (setq-local kvist--inspection-total (plist-get result :total))
          (setq-local kvist--inspection-source-file source-file)
          (setq-local kvist--inspection-source-buffer source-buffer)
          (setq-local kvist--inspection-current entry)
          (setq-local kvist--inspection-history history)
          (local-set-key (kbd "i") #'kvist-inspect-child)
          (local-set-key (kbd "b") #'kvist-inspect-back)
          (local-set-key (kbd "n") #'kvist-inspect-next-page)
          (local-set-key (kbd "p") #'kvist-inspect-previous-page)
          (let ((inhibit-read-only t))
            (when history
              (insert "Navigation: ")
              (insert-text-button
               "Back"
               'follow-link t
               'help-echo "Return to the previous retained inspection"
               'action (lambda (_button) (kvist-inspect-back)))
              (insert " (b)\n"))
            (insert (format "Expression: %s\n" expression))
            (insert (format "Handle: %s\n" (or handle "none")))
            (insert (format "Type: %s\n"
                            (or (plist-get result :type) "unknown")))
            (insert (format "ABI: %s\n"
                            (or (plist-get result :abi) "unknown")))
            (insert (format "Shape: %s\n"
                            (or (plist-get result :shape) "unknown")))
            (when-let ((element-type (plist-get result :element-type)))
              (insert (format "Element type: %s\n" element-type)))
            (when-let ((key-type (plist-get result :key-type)))
              (insert (format "Key type: %s\n" key-type)))
            (when-let ((value-type (plist-get result :value-type)))
              (insert (format "Value type: %s\n" value-type)))
            (when-let ((length (plist-get result :length)))
              (insert (format "Length: %s\n" length)))
            (insert "Commands:\n")
            (pcase (plist-get result :shape)
              ("struct"
               (insert "  RET/click  inspect field at point\n")
               (insert "  i          choose and inspect a field\n"))
              ((or "dynamic-array" "slice" "fixed-array")
               (insert "  RET/click  inspect element at point\n")
               (insert "  i          choose and inspect an index\n"))
              ("map"
               (insert "  RET/click  inspect entry at point\n")
               (insert "  i          inspect a key expression\n")))
            (when history
              (insert "  b          return to previous inspection\n"))
            (when (and (numberp (plist-get result :offset))
                       (> (plist-get result :offset) 0))
              (insert "  p          previous collection page\n"))
            (when (and (numberp (plist-get result :total))
                       (< (+ (or (plist-get result :offset) 0)
                             (or (plist-get result :limit)
                                 kvist-inspection-page-size))
                          (plist-get result :total)))
              (insert "  n          next collection page\n"))
            (insert "  q          close inspector window\n\n")
            (when members
              (insert "Members:\n")
              (dolist (member members)
                (let ((name (alist-get 'name member))
                      (type (alist-get 'type member)))
                  (insert "  ")
                  (if (and handle name type)
                      (insert-text-button
                       (format "%s: %s" name type)
                       'follow-link t
                       'help-echo "Inspect this field from the retained snapshot"
                       'action
                       (lambda (_button)
                         (kvist--inspect-child
                          handle name source-file source-buffer)))
                    (insert
                     (cond
                      ((and name type) (format "%s: %s" name type))
                      (name name)
                      (type type)
                      (t "unknown"))))
                  (insert "\n"))))
            (when entries
              (insert "Entries:\n")
              (dolist (entry entries)
                (let ((index (alist-get 'index entry))
                      (key (alist-get 'key entry))
                      (value (alist-get 'value entry)))
                  (insert "  ")
                  (cond
                   ((numberp index)
                    (insert-text-button
                     (format "[%d] %s" index value)
                     'follow-link t
                     'help-echo "Inspect this element from the retained snapshot"
                     'action
                     (lambda (_button)
                       (kvist--inspect-submit
                        "" source-file source-buffer handle nil index))))
                   (key
                    (let ((key-source
                           (if (member (plist-get result :key-type)
                                       '("string" "cstring"))
                               (prin1-to-string key)
                             key)))
                      (insert-text-button
                       (format "[%s] %s" key value)
                       'follow-link t
                       'help-echo "Inspect this map value from the retained snapshot"
                       'action
                       (lambda (_button)
                         (kvist--inspect-submit
                          "" source-file source-buffer
                          handle nil nil key-source)))))
                   (t
                    (insert (or value "unknown"))))
                  (insert "\n"))))
            (when (numberp (plist-get result :total))
              (let* ((offset (or (plist-get result :offset) 0))
                     (limit (or (plist-get result :limit)
                                kvist-inspection-page-size))
                     (total (plist-get result :total))
                     (shown-end (min total (+ offset limit))))
                (insert (format "Page: %d-%d of %d"
                                (if (< offset total) (1+ offset) 0)
                                shown-end
                                total))
                (when (> offset 0)
                  (insert "  p: previous"))
                (when (< shown-end total)
                  (insert "  n: next"))
                (insert "\n")))
            (insert (format "Generation: %s\n\n"
                            (plist-get result :generation)))
            (insert (or (plist-get result :text) ""))))
        (display-buffer buffer)
        (message "Kvist inspect: %s"
                 (or (plist-get result :type) "unknown"))))
    (when (buffer-live-p source-buffer)
      (with-current-buffer source-buffer
        (kvist--display-output
         (kvist--prepare-diagnostic-buffer kvist-result-buffer-name)
         (plist-get result :message)
         1
         t)))))

(defun kvist-inspect-back ()
  "Return to the previous retained inspection without re-evaluating it."
  (interactive)
  (unless kvist--inspection-history
    (user-error "No previous Kvist inspection"))
  (let ((entry (car kvist--inspection-history))
        (remaining (cdr kvist--inspection-history)))
    (let ((kvist--inspection-restoring t)
          (kvist--inspection-restored-history remaining))
      (kvist--present-inspection
       (plist-get entry :result)
       (plist-get entry :expression)
       (plist-get entry :source-file)
       (plist-get entry :source-buffer)))))

(defun kvist--inspect-submit
    (expression source-file source-buffer
                &optional handle path index key-source)
  "Inspect EXPRESSION or a child selector beneath retained HANDLE."
  (kvist--repl-request
   "inspect"
   expression
   (lambda (result)
     (kvist--present-inspection
      result
      (cond
       (path (format "%s / %s" handle (string-join path ".")))
       ((numberp index) (format "%s / [%d]" handle index))
       (key-source (format "%s / [%s]" handle key-source))
       (t expression))
      source-file
      source-buffer))
   nil
   source-file
   handle
   path
   index
   key-source
   0
   (kvist--inspection-page-size)))

(defun kvist--inspect-child (handle member source-file source-buffer)
  "Inspect MEMBER beneath retained inspection HANDLE."
  (kvist--inspect-submit "" source-file source-buffer handle (list member)))

(defun kvist-inspect-member (member)
  "Inspect MEMBER from the stable snapshot shown in the inspect buffer."
  (interactive
   (list
    (completing-read
     "Inspect member: "
     (delq nil
           (mapcar (lambda (member) (alist-get 'name member))
                   kvist--inspection-members))
     nil t)))
  (unless (and kvist--inspection-handle
               kvist--inspection-source-file)
    (user-error "No retained Kvist inspection in this buffer"))
  (kvist--inspect-child
   kvist--inspection-handle
   member
   kvist--inspection-source-file
   kvist--inspection-source-buffer))

(defun kvist-inspect-index (index)
  "Inspect INDEX from the retained sequence snapshot."
  (interactive (list (read-number "Inspect index: " 0)))
  (unless (and kvist--inspection-handle
               kvist--inspection-source-file)
    (user-error "No retained Kvist inspection in this buffer"))
  (when (< index 0)
    (user-error "Inspection index must be non-negative"))
  (kvist--inspect-submit
   ""
   kvist--inspection-source-file
   kvist--inspection-source-buffer
   kvist--inspection-handle
   nil
   index))

(defun kvist-inspect-map-key (key-source)
  "Inspect the map entry selected by Kvist KEY-SOURCE."
  (interactive "sKvist map key expression: ")
  (unless (and kvist--inspection-handle
               kvist--inspection-source-file)
    (user-error "No retained Kvist inspection in this buffer"))
  (when (string-empty-p (string-trim key-source))
    (user-error "Map key expression cannot be empty"))
  (kvist--inspect-submit
   ""
   kvist--inspection-source-file
   kvist--inspection-source-buffer
   kvist--inspection-handle
   nil
   nil
   key-source))

(defun kvist-inspect-child ()
  "Inspect a child selected according to the retained value's shape."
  (interactive)
  (cond
   ((equal kvist--inspection-shape "struct")
    (call-interactively #'kvist-inspect-member))
   ((member kvist--inspection-shape
            '("dynamic-array" "slice" "fixed-array"))
    (call-interactively #'kvist-inspect-index))
   ((equal kvist--inspection-shape "map")
    (call-interactively #'kvist-inspect-map-key))
   (t
    (user-error "This inspected value has no navigable children yet"))))

(defun kvist-inspect-form-at-point ()
  "Evaluate and retain the form at point for recursive native inspection."
  (interactive)
  (setq kvist--last-source-buffer (current-buffer))
  (let* ((bounds (kvist--inspect-form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (source-buffer (current-buffer))
         (source-file (expand-file-name
                       (or buffer-file-name
                           (user-error
                            "Kvist inspection requires a file-backed buffer")))))
    (kvist--inspect-submit form source-file source-buffer)))

(defun kvist--inspect-page-submit (offset)
  "Request the retained collection page beginning at OFFSET."
  (unless (and kvist--inspection-handle
               kvist--inspection-source-file)
    (user-error "No retained Kvist inspection in this buffer"))
  (let ((handle kvist--inspection-handle)
        (expression kvist--inspection-expression)
        (source-file kvist--inspection-source-file)
        (source-buffer kvist--inspection-source-buffer))
    (kvist--repl-request
     "inspect-page"
     ""
     (lambda (result)
       (kvist--present-inspection
        result expression source-file source-buffer))
     nil source-file handle nil nil nil
     offset (kvist--inspection-page-size))))

(defun kvist-inspect-next-page ()
  "Show the next bounded page of the retained collection."
  (interactive)
  (let* ((offset (or kvist--inspection-offset 0))
         (limit (or kvist--inspection-limit kvist-inspection-page-size))
         (total (or kvist--inspection-total 0))
         (next (+ offset limit)))
    (if (>= next total)
        (user-error "Already at the final inspection page")
      (kvist--inspect-page-submit next))))

(defun kvist-inspect-previous-page ()
  "Show the previous bounded page of the retained collection."
  (interactive)
  (let* ((offset (or kvist--inspection-offset 0))
         (limit (or kvist--inspection-limit kvist-inspection-page-size)))
    (if (<= offset 0)
        (user-error "Already at the first inspection page")
      (kvist--inspect-page-submit (max 0 (- offset limit))))))

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

(defun kvist--compound-call-head-bounds (open)
  "Return the possibly compound call head following opening paren OPEN.
Kvist type-call heads such as `[dynamic]int' and `map[string]int' comprise
multiple Lisp sexps without intervening whitespace."
  (save-excursion
    (goto-char (1+ open))
    (skip-chars-forward " \t\n")
    (let ((start (point))
          end)
      (condition-case nil
          (progn
            (forward-sexp 1)
            (setq end (point))
            (while (and (not (eobp))
                        (not (memq (char-after) '(?\s ?\t ?\n ?\r ?\)))))
              (forward-sexp 1)
              (setq end (point)))
            (cons start end))
        (error nil)))))

(defun kvist--inspect-form-bounds-at-point ()
  "Return useful inspection bounds at point.
When point is anywhere on a call head, inspect the enclosing call rather than
the procedure or type value.  This includes compound type-call heads such as
`[dynamic]int' and `map[string]int'.  Arguments and other nested forms remain
directly inspectable."
  (let* ((bounds (kvist--form-bounds-at-point))
         (selection-start (car bounds))
         (selection-end (cdr bounds))
         (open (nth 1 (syntax-ppss selection-start)))
         call-bounds)
    (save-excursion
      (while (and open (not call-bounds))
        (when (eq (char-after open) ?\()
          (when-let ((head (kvist--compound-call-head-bounds open)))
            (when (and (>= selection-start (car head))
                       (<= selection-end (cdr head)))
              (setq call-bounds (cons open (scan-sexps open 1))))))
        (unless call-bounds
          (setq open (nth 1 (syntax-ppss open)))))
      (or call-bounds bounds))))

(defun kvist--declaration-form-string-p (form)
  "Return non-nil when FORM text starts with a Kvist declaration head."
  (when (string-match "\\`[[:space:]]*(\\([[:word:]!?._+-]+\\)" form)
    (member (match-string 1 form) kvist-declaration-heads)))

(defun kvist--main-definition-string-p (form)
  "Return non-nil when FORM defines the native application entrypoint."
  (string-match-p
   "\\`[[:space:]]*(defn-?[[:space:]\n]+main\\_>"
   form))

(defun kvist--top-level-bounds ()
  "Return bounds of the current top-level evaluable form.
Inside an inert `(comment ...)' wrapper, return the direct child form at or
immediately before point rather than the wrapper itself."
  (let ((comment-bounds
         (ignore-errors (kvist--enclosing-comment-form-bounds))))
    (if (not comment-bounds)
        (save-excursion
          (beginning-of-defun)
          (let ((beg (point)))
            (end-of-defun)
            (cons beg (point))))
      (save-excursion
        (let* ((origin (point))
               (near (kvist--form-bounds-at-point))
               (candidate near)
               (done nil))
          (goto-char (car near))
          (while (not done)
            (let ((parent
                   (save-excursion
                     (condition-case nil
                         (progn
                           (backward-up-list)
                           (point))
                       (error nil)))))
              (cond
               ((or (null parent)
                    (< parent (car comment-bounds)))
                (setq done t))
               ((= parent (car comment-bounds))
                (setq done t))
               (t
                (goto-char parent)
                (setq candidate
                      (cons parent (scan-sexps parent 1)))))))
          (unless (and candidate
                       (> (car candidate) (car comment-bounds))
                       (<= (cdr candidate) (cdr comment-bounds)))
            (goto-char origin)
            (user-error "No evaluable form at point inside comment"))
          candidate)))))

(defun kvist--enclosing-comment-form-bounds ()
  "Return bounds of the enclosing `(comment ...)' form."
  (or
   (save-excursion
     (let ((found nil))
       (condition-case nil
           (while (not found)
             (backward-up-list)
             (let ((beg (point)))
               ;; Inspect without moving the climbing cursor inside the form.
               ;; Otherwise the next `backward-up-list' returns to this same
               ;; opening delimiter forever for a non-comment child form.
               (save-excursion
                 (forward-char 1)
                 (skip-chars-forward " \t\n")
                 (when (looking-at-p "comment\\_>")
                   (setq found (cons beg (scan-sexps beg 1)))))))
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

(defun kvist--buffer-repl-source ()
  "Return evaluable top-level forms from the current buffer.
The package declaration is already supplied by the session context, and
top-level comment forms remain deliberately inert."
  (save-excursion
    (goto-char (point-min))
    (let (forms)
      (while (< (point) (point-max))
        (forward-comment (point-max))
        (skip-chars-forward " \t\r\n")
        (when (< (point) (point-max))
          (let ((beg (point))
                end)
            (condition-case err
                (setq end (scan-sexps beg 1))
              (error
               (user-error "Cannot read buffer form: %s"
                           (error-message-string err))))
            (unless end
              (user-error "Incomplete top-level form"))
            (let ((form (buffer-substring-no-properties beg end)))
              (unless (string-match-p
                       (concat
                        "\\`[[:space:]]*(\\(?:package\\|comment\\)\\_>"
                        "\\|"
                        "\\`[[:space:]]*(defn-?[[:space:]\n]+main\\_>")
                       form)
                (push form forms)))
            (goto-char end))))
      (string-join (nreverse forms) "\n"))))

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

(defun kvist--format-protocol-diagnostics (diagnostics)
  "Render structured protocol DIAGNOSTICS for `compilation-mode'."
  (mapconcat
   (lambda (diagnostic)
     (let* ((severity (or (alist-get 'severity diagnostic) "error"))
            (code (alist-get 'code diagnostic))
            (confidence (alist-get 'confidence diagnostic))
            (label (concat severity
                           (if code (format "[%s%s]"
                                            code
                                            (if (equal confidence "conservative")
                                                "?" ""))
                             ""))))
       (format "%s:%s:%s: %s: %s"
               (or (alist-get 'source_path diagnostic) "<eval>")
               (or (alist-get 'line diagnostic) 1)
               (or (alist-get 'column diagnostic) 1)
               label
               (or (alist-get 'message diagnostic) ""))))
   diagnostics
   "\n"))

(defun kvist--eval-string-stateless
    (form &optional no-print check-only display bounds save-name)
  "Evaluate FORM through the hermetic `kvist eval' command.
When NO-PRINT is non-nil, treat FORM as a statement.  When CHECK-ONLY is
non-nil, run `odin check' instead of `odin run'.  DISPLAY may be `inline',
`comment', or `buffer'.  SAVE-NAME stores successful stdout in the Kvist
CLI cache."
  (when (and check-only save-name)
    (user-error "Cannot save a check-only Kvist eval"))
  (setq kvist--last-source-buffer (current-buffer))
  (let* ((source-buffer (current-buffer))
         (source (kvist--source-temp-file))
         (output-buffer (kvist--prepare-diagnostic-buffer kvist-result-buffer-name))
         (args (append (list "eval" source form)
                       (when no-print (list "--no-print"))
                       (when check-only (list "--check"))
                       (when save-name (list "--save" save-name))))
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
                               (when save-name (list "--save" save-name))))
            (setq exit-code (kvist--call (kvist--executable) args output-buffer t))
            (setq result (with-current-buffer output-buffer
                           (buffer-substring-no-properties (point-min) (point-max)))))
          (setq result (kvist--remap-output-source-path result source source-buffer))
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
        (delete-file source)))))

(defun kvist--present-repl-result
    (source-buffer display bounds result)
  "Present one asynchronous RESULT for SOURCE-BUFFER and DISPLAY."
  (let* ((success (plist-get result :success))
         (output (or (plist-get result :text) ""))
         (message-text (or (plist-get result :message) ""))
         (diagnostics (plist-get result :diagnostics))
         (diagnostic-text
          (and diagnostics
               (kvist--format-protocol-diagnostics diagnostics)))
         (text (if success
                   (if (and diagnostic-text
                            (not (string-empty-p diagnostic-text)))
                       (concat diagnostic-text
                               (unless (string-empty-p output) "\n")
                               output)
                     output)
                 (or diagnostic-text message-text)))
         (exit-code (if success 0 1))
         (output-buffer
          (kvist--prepare-diagnostic-buffer kvist-result-buffer-name)))
    (when (buffer-live-p source-buffer)
      (with-current-buffer source-buffer
        (pcase display
          ('inline
           (when (and (markerp (car bounds))
                      (markerp (cdr bounds))
                      (marker-position (car bounds))
                      (marker-position (cdr bounds)))
             (kvist--show-inline-result
              (marker-position (car bounds))
              (marker-position (cdr bounds))
              text
              exit-code))
           (kvist--message-result text exit-code))
          ('comment
           (when (and (markerp (cdr bounds))
                      (marker-position (cdr bounds)))
             (kvist--insert-comment-result
              source-buffer
              (marker-position (cdr bounds))
              text
              exit-code))
           (kvist--message-result text exit-code))
          ('minibuffer
           (if success
               (let ((trimmed (kvist--trim-output text)))
                 (message "=> %s"
                          (if (string-empty-p trimmed)
                              "nil"
                            trimmed)))
             (kvist--display-output
              output-buffer text exit-code t)))
          (_
           (kvist--display-output
            output-buffer text exit-code (not success))))))))

(defun kvist--restore-debug-return-location (session)
  "Return to the source submission that entered SESSION's debugger."
  (when (kvist--repl-session-paused-during-request session)
    (let ((buffer (kvist--repl-session-pause-return-buffer session))
          (marker (kvist--repl-session-pause-return-marker session)))
      (when (and (buffer-live-p buffer)
                 (markerp marker)
                 (marker-position marker))
        (pop-to-buffer buffer)
        (goto-char marker)))
    (setf (kvist--repl-session-paused-during-request session) nil)
    (setf (kvist--repl-session-pause-return-buffer session) nil)
    (setf (kvist--repl-session-pause-return-marker session) nil)))

(defun kvist--present-trace
    (traces truncated &optional summary value-events values-truncated)
  "Present TRACES, truncation state, SUMMARY, and bounded VALUE-EVENTS."
  (let ((buffer (kvist--prepare-buffer kvist-trace-buffer-name))
        (values-by-trace (make-hash-table :test #'equal)))
    (dolist (event value-events)
      (let ((trace-id (alist-get 'trace_id event)))
        (puthash trace-id
                 (cons event (gethash trace-id values-by-trace))
                 values-by-trace)))
    (maphash (lambda (trace-id events)
               (puthash trace-id (nreverse events) values-by-trace))
             values-by-trace)
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Kvist execution trace: %d safe points\n\n"
                        (length traces)))
        (when summary
          (insert
           (format "Native evaluation: %.3f ms total; %.3f ms unattributed\n\n"
                   (/ (or (alist-get 'trace_total_ns summary) 0) 1000000.0)
                   (/ (or (alist-get 'trace_unattributed_ns summary) 0)
                      1000000.0)))
          (insert "Hotspots (time after each safe point)\n\n")
          (dolist (hotspot (alist-get 'hotspots summary))
            (insert
             (format "%s:%s:%s: %.3f ms total  %s hits  %.3f ms max\n"
                     (or (alist-get 'source_path hotspot) "<eval>")
                     (or (alist-get 'line hotspot) "?")
                     (or (alist-get 'column hotspot) "?")
                     (/ (or (alist-get 'total_ns hotspot) 0) 1000000.0)
                     (or (alist-get 'hits hotspot) 0)
                     (/ (or (alist-get 'max_ns hotspot) 0) 1000000.0))))
          (insert "\nTimeline\n\n"))
        (dolist (trace traces)
          (insert
           (format "%s:%s:%s: +%.3f ms  Δ%.3f ms  depth %s\n"
                   (or (alist-get 'source_path trace) "<eval>")
                   (or (alist-get 'line trace) "?")
                   (or (alist-get 'column trace) "?")
                   (/ (or (alist-get 'elapsed_ns trace) 0) 1000000.0)
                   (/ (or (alist-get 'delta_ns trace) 0) 1000000.0)
                   (or (alist-get 'depth trace) "?")))
          (let* ((trace-id (alist-get 'trace_id trace))
                 (queued-values (gethash trace-id values-by-trace))
                 (value-event (car queued-values)))
            (when queued-values
              (puthash trace-id (cdr queued-values) values-by-trace))
            (when value-event
            (dolist (value (alist-get 'trace_values value-event))
              (insert
               (format "    %s: %s  %s = %s\n"
                       (or (alist-get 'name value) "?")
                       (or (alist-get 'type value) "?")
                       (or (alist-get 'ownership value) "value")
                       (or (alist-get 'value value) "")))))))
        (when truncated
          (insert
           "\nTrace limit reached; later safe points were omitted.\n"))
        (when values-truncated
          (insert
           "\nTrace value limit reached; later values were omitted.\n"))
        (compilation-mode)
        (kvist--enable-presentation-mode)))
    (display-buffer buffer)))

(defun kvist--eval-string
    (form &optional no-print check-only display bounds save-name pause-before
          trace)
  "Evaluate FORM in the persistent native package session.
CHECK-ONLY and SAVE-NAME deliberately use the hermetic CLI paths."
  (when (and (not check-only)
             (not save-name)
             (kvist--main-definition-string-p form))
    (user-error
     "Native main is an application entrypoint; use Olive reload or restart the program"))
  (if (or check-only save-name)
      (kvist--eval-string-stateless
       form no-print check-only display bounds save-name)
    (setq kvist--last-source-buffer (current-buffer))
    (let* ((source-buffer (current-buffer))
           (display (or display 'buffer))
           (markers (cons (copy-marker (car bounds))
                          (copy-marker (cdr bounds) t)))
           (source-line (line-number-at-pos (car bounds)))
           (source-column
            (save-excursion
              (goto-char (car bounds))
              (1+ (current-column))))
           (source-file (expand-file-name
                         (or buffer-file-name
                             (user-error
                              "Kvist REPL evaluation requires a file-backed buffer")))))
      (let ((session (kvist--repl-session source-file)))
        (setf (kvist--repl-session-pause-return-buffer session) source-buffer)
        (setf (kvist--repl-session-pause-return-marker session) (car markers))
        (setf (kvist--repl-session-paused-during-request session) nil))
      (cl-labels
          ((submit
            (effective-no-print)
            (kvist--repl-request
             "eval"
             form
             (lambda (result)
               ;; Failed compilation does not alter native session state, so a
               ;; void call can be retried safely as an effect-only submission.
               (if (and (not effective-no-print)
                        (not (plist-get result :success))
                        (kvist--void-value-error-p
                         (or (plist-get result :message) "")))
                   (submit t)
                 (unwind-protect
                     (progn
                       (kvist--present-repl-result
                       source-buffer display markers result)
                       (kvist--restore-debug-return-location
                        (kvist--repl-session source-file))
                       (when trace
                         (kvist--present-trace
                          (plist-get result :traces)
                          (plist-get result :trace-truncated)
                          (plist-get result :trace-summary)
                          (plist-get result :trace-values)
                          (plist-get result
                                     :trace-values-truncated))))
                   (set-marker (car markers) nil)
                   (set-marker (cdr markers) nil))))
             effective-no-print
             source-file
             nil nil nil nil nil nil
             source-line
             source-column
             nil
             pause-before
             trace
             (when trace
               (min 10000 (max 1 kvist-trace-limit)))
             (and trace kvist-trace-capture-values)
             (when (and trace kvist-trace-capture-values)
               (min 1000 (max 1 kvist-trace-value-limit))))))
        (submit no-print)))))

(defun kvist--buffer-command (command)
  "Run Kvist buffer COMMAND, one of build, check, or run."
  (setq kvist--last-source-buffer (current-buffer))
  (unless buffer-file-name
    (user-error "Kvist %s requires a file-backed buffer" command))
  (save-buffer)
  (let* ((source-buffer (current-buffer))
         (source (expand-file-name buffer-file-name))
         (output-buffer (kvist--prepare-diagnostic-buffer kvist-result-buffer-name))
         (root (file-name-as-directory (kvist--project-root source))))
    (let* ((default-directory root)
           (args (list command source))
           (exit-code (kvist--call (kvist--executable source) args output-buffer t))
           (result (with-current-buffer output-buffer
                     (buffer-substring-no-properties (point-min) (point-max)))))
      (setq result (kvist--remap-output-source-path result source source-buffer))
      (if (zerop exit-code)
          (let ((trimmed (kvist--trim-output result)))
            (message "%s"
                     (if (string-empty-p trimmed)
                         (format "kvist %s: ok" command)
                       trimmed)))
        (kvist--display-output output-buffer result exit-code t)))))

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
         (source-buffer (current-buffer))
         (source-file (expand-file-name buffer-file-name)))
    (kvist--repl-request
     "expand"
     form
     (lambda (result)
       (if (plist-get result :success)
           (let ((generated-buffer
                  (kvist--prepare-buffer kvist-generated-buffer-name)))
             (with-current-buffer generated-buffer
               (let ((inhibit-read-only t))
                 (erase-buffer)
                 (insert (plist-get result :text))
                 (when (fboundp 'odin-mode)
                   (odin-mode))))
             (display-buffer generated-buffer)
             (message "kvist expand: ok"))
         (when (buffer-live-p source-buffer)
           (with-current-buffer source-buffer
             (kvist--display-output
              (kvist--prepare-diagnostic-buffer kvist-result-buffer-name)
              (plist-get result :message)
              1
              t)))))
     no-print
     source-file)))

;;;###autoload
(defun kvist-macroexpand-form-at-point ()
  "Show Kvist macro expansion for the form at point."
  (interactive)
  (setq kvist--last-source-buffer (current-buffer))
  (let* ((bounds (kvist--form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (source-buffer (current-buffer))
         (source-file (expand-file-name buffer-file-name)))
    (kvist--repl-request
     "macroexpand"
     form
     (lambda (result)
       (if (plist-get result :success)
           (let ((macro-buffer
                  (kvist--prepare-buffer kvist-macroexpand-buffer-name)))
             (with-current-buffer macro-buffer
               (let ((inhibit-read-only t))
                 (erase-buffer)
                 (insert (plist-get result :text))))
             (display-buffer macro-buffer)
             (message "kvist macroexpand: ok"))
         (when (buffer-live-p source-buffer)
           (with-current-buffer source-buffer
             (kvist--display-output
              (kvist--prepare-diagnostic-buffer kvist-result-buffer-name)
              (plist-get result :message)
              1
              t)))))
     nil
     source-file)))

;;;###autoload
(defun kvist-eval-form-at-point (&optional no-print)
  "Evaluate the Kvist form at point and show the result inline.
With prefix argument NO-PRINT, treat the form as a statement."
  (interactive "P")
  (let* ((bounds (kvist--form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds))))
    (kvist--eval-string
     form
     (or no-print kvist-default-no-print)
     nil
     'inline
     bounds)))

;;;###autoload
(defun kvist-debug-eval-form-at-point (&optional no-print)
  "Evaluate the form at point with a safe pause before native execution.
Use `kvist-debug-continue' to resume the suspended evaluation."
  (interactive "P")
  (let* ((bounds (kvist--form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds))))
    (kvist--eval-string
     form
     (or no-print kvist-default-no-print)
     nil
     'buffer
     bounds
     nil
     t)))

;;;###autoload
(defun kvist-trace-form-at-point (&optional no-print)
  "Evaluate the form at point and show its native Kvist safe-point trace."
  (interactive "P")
  (let* ((bounds (kvist--form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds))))
    (kvist--eval-string
     form
     (or no-print kvist-default-no-print)
     nil
     'buffer
     bounds
     nil
     nil
     t)))

;;;###autoload
(defun kvist-popup-form-at-point (&optional no-print)
  "Evaluate the Kvist form at point and show the result buffer."
  (interactive "P")
  (let* ((bounds (kvist--form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds))))
    (kvist--eval-string
     form
     (or no-print kvist-default-no-print)
     nil
     'buffer
     bounds)))

;;;###autoload
(defun kvist-insert-form-result (&optional no-print)
  "Evaluate the Kvist form at point and insert its result as a ;; => comment."
  (interactive "P")
  (let* ((bounds (kvist--form-bounds-at-point))
         (form (buffer-substring-no-properties (car bounds) (cdr bounds))))
    (kvist--eval-string
     form
     (or no-print kvist-default-no-print)
     nil
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
         (form (buffer-substring-no-properties (car bounds) (cdr bounds))))
    (kvist--eval-string
     form
     (or no-print kvist-default-no-print)
     nil
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
  "Evaluate all active forms in the current buffer as one atomic REPL batch.
Successful completion is reported in the minibuffer; diagnostics still open
the result buffer."
  (interactive)
  (let ((source (kvist--buffer-repl-source))
        (bounds (cons (point-min) (point-max))))
    (when (string-empty-p (string-trim source))
      (user-error "Buffer has no active forms to evaluate"))
    (kvist--eval-string source nil nil 'minibuffer bounds)))

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
  (local-set-key (kbd "C-c C-s") #'kvist-repl-start)
  (local-set-key (kbd "C-c g g") #'kvist-expand-form-at-point)
  (local-set-key (kbd "C-c d") #'kvist-doc-at-point)
  (local-set-key (kbd "C-c C-d") #'kvist-doc-at-point)
  (local-set-key (kbd "C-c C-w") #'kvist-save-form-result)
  (local-set-key (kbd "C-c C-l") #'kvist-cache-list)
  (local-set-key (kbd "C-c C-o") #'kvist-cache-open)
  (local-set-key (kbd "C-c M-d") #'kvist-cache-rm)
  (local-set-key (kbd "C-c C-z") #'kvist-repl)
  (local-unset-key (kbd "C-c M-j"))
  (local-set-key (kbd "C-c M-r") #'kvist-repl-reset)
  (local-set-key (kbd "C-c C-q") #'kvist-repl-stop)
  (local-set-key (kbd "C-c M-q") #'kvist-repl-stop)
  (local-set-key (kbd "C-c M-i") #'kvist-inspect-form-at-point)
  (dolist (binding kvist--debug-key-bindings)
    (local-set-key (kbd (car binding)) (cdr binding)))
  (local-set-key (kbd "C-c t t") #'kvist-test-at-point)
  (local-set-key (kbd "C-c t p") #'kvist-test-package)
  (local-set-key (kbd "C-c t a") #'kvist-test-project))

(add-hook 'kvist-mode-hook #'kvist-setup-mode-keys)

(provide 'kvist-eval)

;;; kvist-eval.el ends here
