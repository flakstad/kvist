;;; odinl-mode.el --- Major mode for OdinL -*- lexical-binding: t; -*-

;; OdinL is a Clojure-shaped syntax that lowers to Odin.  Editing should behave
;; like Clojure editing first, with small OdinL-specific font-lock and
;; indentation adjustments.

(require 'clojure-mode)

(defgroup odinl nil
  "Editing support for OdinL."
  :group 'languages)

(defcustom odinl-indent-offset 2
  "Indentation offset for OdinL source."
  :type 'integer
  :group 'odinl)

(defconst odinl-special-forms
  '("package" "import" "const" "struct" "enum" "union" "proc" "odin"
    "let" "do" "if" "when" "cond" "switch" "set!" "return" "defer"
    "for" "each" "comment" "new" "make" "get" "nil?" "in" "not-in"
    "break" "continue" "->")
  "OdinL special forms and syntactic heads.")

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
                   (new . 1)
                   (make . 1)))
    (odinl--put-indent (car entry) (cdr entry))))

;;;###autoload
(define-derived-mode odinl-mode clojure-mode "OdinL"
  "Major mode for editing OdinL source files."
  (setq-local clojure-indent-style 'align-arguments)
  (setq-local clojure-align-forms-automatically nil)
  (setq-local lisp-body-indent odinl-indent-offset)
  (setq-local indent-tabs-mode nil)
  (font-lock-add-keywords nil odinl-font-lock-keywords)
  (odinl--setup-indentation))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.odinl\\'" . odinl-mode))

(provide 'odinl-mode)

;;; odinl-mode.el ends here
