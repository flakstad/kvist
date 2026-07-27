# Emacs

Kvist provides a major mode and CLI-backed evaluation commands.

## Install

```elisp
(add-to-list 'load-path "/path/to/kvist/emacs")
(require 'kvist-mode)
(require 'kvist-eval)
```

`kvist-mode` derives from `clojure-mode`, associates `*.kvist` files with the
mode, and uses two-space indentation.

Put `kvist` on Emacs' `exec-path`, or set its path:

```elisp
(setq kvist-command "/path/to/kvist")
```

## Language Support

The mode provides:

- syntax highlighting and indentation;
- completion for language forms, local declarations, and imported packages;
- automatic `kvist:*` imports for completed package members;
- xref definitions through `M-.`;
- documentation for Kvist and imported Odin symbols;
- `compilation-mode` navigation for diagnostics.

Declaration documentation comes from comments immediately before a top-level
declaration or from its docstring.

## Commands

- `M-.`: go to definition
- `C-c C-.`, `C-c d`, `C-c C-d`: show documentation
- `C-c C-e`: evaluate the form at point inline
- `C-c C-p`: evaluate the form at point in a result buffer
- `C-c C-i`: evaluate and insert a `;; =>` comment
- `C-c C-c`: evaluate the current top-level form
- `C-c C-r`: evaluate the selected region
- `C-c C-x`: evaluate the enclosing `comment` form
- `C-c C-k`: evaluate the buffer
- `C-c C-b`: build the buffer
- `C-c C-v`: check the buffer
- `C-c C-a`: run the buffer asynchronously
- `C-c C-m`: show generated Odin
- `C-c M-m`: show macro expansion
- `C-c C-s`: toggle generated Odin
- `C-c t t`: run the test at point
- `C-c t p`: run package tests
- `C-c t a`: run project tests

Use a prefix argument with evaluation commands to treat the selected source as
statements.

## Saved Evaluation Output

The editor uses the CLI cache commands:

```sh
kvist eval file.kvist FORM --save NAME
kvist cache list
kvist cache path NAME
kvist cache rm NAME
```

Editor commands can save, list, open, and remove these values.
