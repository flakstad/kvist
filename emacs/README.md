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

`odinl-eval` shells out to the `odinl` CLI for eval, check, and run commands.
The CLI generates temporary Odin and invokes Odin itself. Build the local
compiler first:

```sh
odin build cmd/odinl
```

Default keys:

- `C-c C-e`: eval form at point inline
- `C-c C-c`: eval current top-level form inline
- `C-c C-r`: eval selected region inline
- `C-c C-k`: check generated Odin for form at point
- `C-c C-v`: compile buffer and run `odin check` on generated Odin
- `C-c C-a`: compile buffer and run generated Odin
- `C-c C-s`: toggle display of generated Odin
- `C-c C-z`: switch to the result buffer

Use a prefix argument with eval commands to treat the form/region as statements
instead of printing the expression result.
