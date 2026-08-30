;;; kvist-cider-test.el --- CIDER integration test for Kvist -*- lexical-binding: t -*-

(require 'cider)
(require 'nrepl-dict)
(require 'seq)

(add-to-list 'load-path (or (getenv "KVIST_CIDER_EMACS_DIR")
                            (expand-file-name "../../../emacs"
                                              (file-name-directory load-file-name))))
(require 'kvist-mode)

(defun kvist-cider-test--assert (condition message &rest args)
  (unless condition
    (error (apply #'format message args))))

(defun kvist-cider-test--wait (predicate process timeout)
  (let ((deadline (+ (float-time) timeout)))
    (while (and (not (funcall predicate))
                (< (float-time) deadline))
      (accept-process-output process 0.05))
    (funcall predicate)))

(defun kvist-cider-test--eval-value (repl code)
  (nrepl-dict-get (cider-nrepl-sync-request:eval code repl "user") "value"))

(defun kvist-cider-test--run-interactive-eval (repl action label)
  "Run CIDER source ACTION and return the exact form sent to REPL.
Fail if LABEL does not receive a successful nREPL done response."
  (let ((original (symbol-function 'cider-interactive-eval))
        (eval-form nil)
        (eval-responses nil)
        (eval-done nil))
    (cl-letf (((symbol-function 'cider-interactive-eval)
               (lambda (form &optional _callback bounds additional-params)
                 (setq eval-form
                       (or form
                           (apply #'buffer-substring-no-properties bounds)))
                 (funcall
                  original form
                  (lambda (response)
                    (push response eval-responses)
                    (when (member "done" (nrepl-dict-get response "status"))
                      (setq eval-done t)))
                  bounds additional-params))))
      (funcall action))
    (kvist-cider-test--assert
     (kvist-cider-test--wait
      (lambda () eval-done) (get-buffer-process repl) 15)
     "CIDER %s timed out; sent %S" label eval-form)
    (kvist-cider-test--assert
     (not (seq-some
           (lambda (response)
             (let ((status (nrepl-dict-get response "status")))
               (or (member "eval-error" status)
                   (member "error" status))))
           eval-responses))
     "CIDER %s failed; sent %S, responses %S"
     label eval-form (nreverse eval-responses))
    eval-form))

(let* ((port (string-to-number (or (getenv "KVIST_CIDER_PORT") "0")))
       (project-dir (file-name-as-directory
                     (or (getenv "KVIST_CIDER_PROJECT_DIR") default-directory)))
       (source-file (or (getenv "KVIST_CIDER_SOURCE")
                        (error "KVIST_CIDER_SOURCE is required")))
       (cider-auto-mode nil)
       (cider-save-file-on-load nil)
       (cider-show-error-buffer nil)
       (cider-reuse-dead-repls nil)
       (nrepl-sync-request-timeout 30)
       (repl (cider-connect-clj
              (list :host "127.0.0.1"
                    :port port
                    :project-dir project-dir))))
  (unwind-protect
      (progn
        (with-current-buffer repl
          (kvist-cider-test--assert (process-live-p (get-buffer-process repl))
                                    "CIDER did not keep its nREPL connection open")
          (kvist-cider-test--assert (eq (cider-runtime) 'generic)
                                    "CIDER classified Kvist as %S" (cider-runtime))
          (kvist-cider-test--assert
           (cider-nrepl-op-supported-p "interrupt" repl)
           "CIDER did not discover the interrupt op"))

        ;; Exercise CIDER's real source-buffer commands.  These go through
        ;; clojure-mode's form parser and CIDER's file/line/column plumbing;
        ;; direct nREPL requests alone cannot catch failures in that layer.
        (let ((source (find-file-noselect source-file)))
          (unwind-protect
              (with-current-buffer source
                (kvist-mode)
                (cider-mode 1)
                (goto-char (point-min))
                (search-forward "(def cider-source-value: int 40)")
                (let* ((eval-form
                        (kvist-cider-test--run-interactive-eval
                         repl #'cider-eval-last-sexp "last-sexp evaluation"))
                       (response
                        (cider-nrepl-sync-request:eval
                         "cider-source-value" repl "user")))
                  (kvist-cider-test--assert
                   (equal (nrepl-dict-get response "value") "40")
                   "CIDER did not evaluate %S; lookup returned %S"
                   eval-form response))

                (goto-char (point-min))
                (search-forward "(+ cider-source-value 2)")
                (let ((start (match-beginning 0))
                      (end (match-end 0)))
                  (kvist-cider-test--run-interactive-eval
                   repl (lambda () (cider-eval-region start end))
                   "region evaluation"))
                (kvist-cider-test--assert
                 (equal (kvist-cider-test--eval-value repl "*1") "42")
                 "CIDER did not evaluate a top-level Kvist region")

                (goto-char (point-max))
                (insert "\n(def cider-loaded-from-buffer: int 43)\n")
                (let ((loaded nil)
                      (load-error nil)
                      (load-responses nil))
                  (cider-load-buffer
                   source
                   (lambda (response)
                     (push response load-responses)
                     (let ((status (nrepl-dict-get response "status")))
                       (when (or (member "eval-error" status)
                                 (member "error" status))
                         (setq load-error response))
                       (when (member "done" status)
                         (setq loaded t)))))
                  (kvist-cider-test--assert
                   (kvist-cider-test--wait
                    (lambda () loaded) (get-buffer-process repl) 30)
                   "CIDER load-buffer timed out")
                  (kvist-cider-test--assert (not load-error)
                                            "CIDER load-buffer failed: %S"
                                            (nreverse load-responses)))
                (kvist-cider-test--assert
                 (equal (kvist-cider-test--eval-value repl "*1") "44")
                 "CIDER load-buffer did not return its final top-level value")
                (kvist-cider-test--assert
                 (equal (kvist-cider-test--eval-value
                         repl "(+ cider-loaded-from-buffer 1)")
                        "44")
                 "CIDER did not load the complete unsaved source buffer"))
            (when (buffer-live-p source)
              (with-current-buffer source
                (set-buffer-modified-p nil))
              (kill-buffer source))))

        (with-current-buffer repl
          (cider-nrepl-sync-request:eval "(def cider-value: int 40)" repl "user")
          (let ((response
                 (cider-nrepl-sync-request:eval "(+ cider-value 2)" repl "user")))
            (kvist-cider-test--assert
             (equal (nrepl-dict-get response "value") "42")
             "CIDER eval returned %S" response))

          (let* ((completions (cider-sync-request:complete "pri" nil))
                 (names (mapcar (lambda (item)
                                  (nrepl-dict-get item "candidate"))
                                completions)))
            (kvist-cider-test--assert (member "println" names)
                                      "CIDER completion returned %S" names))

          (let ((info (cider-info-request :sym "println")))
            (kvist-cider-test--assert
             (equal (nrepl-dict-get info "name") "core.println")
             "CIDER info returned %S" info))

          (let ((interrupted nil)
                (process (get-buffer-process repl)))
            (nrepl-send-eval-request
             "(do (while true (discard 1)) 0)"
             (lambda (response)
               (let ((status (nrepl-dict-get response "status")))
                 (when (and (member "interrupted" status)
                            (member "done" status))
                   (setq interrupted t))))
             repl :ns "user")
            (accept-process-output process 0.25)
            (cider-interrupt-repl repl)
            (kvist-cider-test--assert
             (kvist-cider-test--wait (lambda () interrupted) process 15)
             "CIDER interrupt timed out")
            (let ((response
                   (cider-nrepl-sync-request:eval "(+ 1 2)" repl "user")))
              (kvist-cider-test--assert
               (equal (nrepl-dict-get response "value") "3")
               "CIDER did not recover after interrupt: %S" response)))

          (princ "cider nrepl: ok\n")))
    (when (buffer-live-p repl)
      (cider--close-connection repl))))

;;; kvist-cider-test.el ends here
