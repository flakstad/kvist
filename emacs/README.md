# Kvist Emacs Support

This directory contains lightweight Emacs support for Kvist.

## Install

```elisp
(add-to-list 'load-path "/path/to/kvist/emacs")
(require 'kvist-mode)
(require 'kvist-eval)
```

`kvist-mode` derives from `clojure-mode`, associates `*.kvist` files with the
mode, adds Kvist-specific font-locking, and uses Clojure-like 2-space
indentation for Kvist source.

It also registers an xref backend and completion-at-point function. `M-.`
jumps to definitions indexed by `kvist symbols`, including current-file
declarations, compiler-provided Kvist package members such as `arr.push!`, and
imported Odin package definitions such as `fmt.println`. Dot package access is
canonical, and editor completion emits `pkg.member` candidates. For Kvist
language forms, `M-.` jumps to the compiler implementation.
Completion includes Kvist forms, current-file declarations, imported package
members, and compiler-provided package members. When point is inside a
qualified package prefix such as `map.` or `fmt.`, completion is limited to
that package. Typing or completing a canonical Kvist package prefix such as
`arr.`, `str.`, `map.`, `set.`, or `soa.` automatically inserts the matching
top-level `(import ... "kvist:...")` form when it is missing.
Compiler-provided Kvist package members and built-in forms also show
signatures in completion annotations and in the doc buffer.

`C-c C-.`, `C-c d`, and `C-c C-d` show docs for the symbol at point without jumping. Kvist declaration
docs come from contiguous `//`, `;`, or `/* ... */` comments immediately
preceding a top-level declaration. Compiler-defined forms such as `if-let` and
`if-ok` have small built-in docs. Imported Odin docs come from contiguous `//`
or `/* ... */` comments immediately preceding the imported package definition.
Compiler-provided Kvist packages such as `arr`, `str`, `map`, `set`, `soa`,
and `matrix` also provide docs through the editor integration.

`kvist-eval` shells out to the `kvist` CLI for eval, build, check, and run commands.
The CLI generates temporary Odin and invokes Odin itself. Put the compiler on
Emacs' `exec-path`, or customize `kvist-command` to an executable path:

```elisp
(setq kvist-command "kvist")
```

When the CLI reports Kvist diagnostics, the result buffer uses
`compilation-mode`, so standard Emacs navigation such as `next-error` / `M-g n`
can jump back to the reported `.kvist` source location.

Default keys:

- `M-.`: go to definition
- `C-c C-.`: show docs for symbol at point
- `C-c d`: show docs for symbol at point
- `C-c C-e`: eval form at point inline
- `C-c C-p`: eval form at point in the result buffer
- `C-c C-i`: eval form at point and insert a `;; =>` comment
- `C-c C-c`: eval current top-level form inline
- `C-c C-r`: eval selected region in the result buffer
- `C-c C-x`: eval the enclosing `(comment ...)` body inline
- `C-c C-k`: eval the whole buffer
- `C-c C-b`: compile buffer and run `odin build` on generated Odin
- `C-c C-v`: compile buffer and run `odin check` on generated Odin
- `C-c C-a`: save buffer and run `kvist run` asynchronously
- `C-c C-m`: expand form at point into generated Odin
- `C-c M-m`: macroexpand form at point into Kvist
- `C-c C-s`: toggle display of generated Odin
- `C-c C-d`: show docs for symbol at point
- `C-c C-w`: eval form at point and save stdout to the Kvist cache
- `C-c C-l`: list saved Kvist cache values
- `C-c C-o`: open a saved Kvist cache value
- `C-c M-d`: remove a saved Kvist cache value
- `C-c C-z`: switch to the result buffer
- `C-c t t`: run the `t/deftest` at point
- `C-c t p`: run Kvist tests for the current package
- `C-c t a`: run all Kvist test packages in the current project
- `C-c r s`: start `kvist dev --reload` for the current file
- `C-c r w`: start `kvist dev --reload --watch` for the current file
- `C-c r r`: rebuild the current reloadable app via `--rebuild --json`
- `C-c r p`: show generated reload paths and commands

Use a prefix argument with eval commands to treat the form/region as statements
instead of printing the expression result.

The reload commands use the CLI's JSON surface:

```sh
kvist dev --reload file.kvist --json
kvist dev --reload file.kvist --watch --json
kvist dev --reload file.kvist --print-paths --json
kvist dev --reload file.kvist --rebuild --json
```

`C-c C-a` now runs the current file in its own per-file compilation buffer, so
long-running programs do not block Emacs and multiple runs can stay open at the
same time.

`C-c r s` starts the long-running resident reload shell in its own per-file
compilation buffer.
The session uses `--json`, so the reload host emits structured event lines with
the prefix `KVIST_RELOAD_EVENT<TAB>` while ordinary app stdout/stderr still
flows through the same buffer.
`C-c r w` starts the same resident reload shell with `--watch`, so saving
`.kvist` files under the adapter directory rebuilds the reloadable module
automatically.
`C-c r r` saves the current buffer and rebuilds only the generated reloadable
module. `C-c r p` shows the generated host/module paths and canonical reload
commands for the current file.

If the current file is ordinary production source and a nearby `reload.kvist`
adapter exists, the CLI resolves that adapter automatically for these reload
commands.

For reload-app sources, `C-c C-a` runs the production-style wrapper (`kvist run
file.kvist`), while `C-c r s` starts the resident reload session.

Saved eval values use the CLI cache:

```sh
kvist eval file.kvist FORM --save NAME
kvist cache list
kvist cache path NAME
kvist cache rm NAME
```
