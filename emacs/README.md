# OdinL Emacs Support

This directory contains lightweight Emacs support for OdinL.

## Install

```elisp
(add-to-list 'load-path "/path/to/odinl/emacs")
(require 'odinl-mode)
(require 'odinl-eval)
```

`odinl-mode` derives from `clojure-mode`, associates `*.odinl` files with the
mode, adds OdinL-specific font-locking, and uses Clojure-like 2-space
indentation for OdinL source.

It also registers an xref backend and completion-at-point function. `M-.`
jumps to definitions indexed by `odinl symbols`, including current-file
declarations and simple imported Odin package definitions like `fmt.println`.
For OdinL language forms and sequence helpers, `M-.` jumps to the compiler
implementation. Completion includes OdinL forms, sequence helpers, current-file
declarations, and imported package members.

`C-c C-.` shows docs for the symbol at point without jumping. OdinL declaration
docs come from contiguous `//`, `;`, or `/* ... */` comments immediately
preceding a top-level declaration. Compiler-defined forms such as `if-let` and
`if-ok` have small built-in docs. Imported Odin docs come from contiguous `//`
or `/* ... */` comments immediately preceding the imported package definition.

`odinl-eval` shells out to the `odinl` CLI for eval, build, check, and run commands.
The CLI generates temporary Odin and invokes Odin itself. Build the local
compiler first:

```sh
odin build cmd/odinl
```

When the CLI reports OdinL diagnostics, the result buffer uses
`compilation-mode`, so standard Emacs navigation such as `next-error` / `M-g n`
can jump back to the reported `.odinl` source location.

Default keys:

- `M-.`: go to definition
- `C-c C-.`: show docs for symbol at point
- `C-c C-e`: eval form at point inline
- `C-c C-p`: eval form at point in the result buffer
- `C-c C-i`: eval form at point and insert a `;; =>` comment
- `C-c C-c`: eval current top-level form inline
- `C-c C-r`: eval selected region in the result buffer
- `C-c C-x`: eval the enclosing `(comment ...)` body inline
- `C-c C-k`: eval the whole buffer
- `C-c C-b`: compile buffer and run `odin build` on generated Odin
- `C-c C-v`: compile buffer and run `odin check` on generated Odin
- `C-c C-a`: compile buffer and run generated Odin
- `C-c C-m`: expand form at point into generated Odin
- `C-c M-m`: macroexpand form at point into OdinL
- `C-c C-s`: toggle display of generated Odin
- `C-c C-w`: eval form at point and save stdout to the OdinL cache
- `C-c C-l`: list saved OdinL cache values
- `C-c C-o`: open a saved OdinL cache value
- `C-c C-d`: remove a saved OdinL cache value
- `C-c C-z`: switch to the result buffer

Use a prefix argument with eval commands to treat the form/region as statements
instead of printing the expression result.

Saved eval values use the CLI cache:

```sh
odinl eval file.odinl FORM --save NAME
odinl cache list
odinl cache path NAME
odinl cache rm NAME
```
