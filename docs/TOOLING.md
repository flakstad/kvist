# OdinL Tooling Plan

Tooling comes after the compiler reaches the language draft's core target. The
editor story should feel close to Clojure editing while keeping Odin as the
execution model.

## References

- `../cluck/emacs`: useful model for a light Clojure-like major mode derived
  from `clojure-mode`, with inline eval overlays and a small command set.
- `../odineval`: useful model for Odin eval by generating temporary Odin,
  invoking `odin run` / `odin check`, showing generated code, and integrating
  with Emacs result buffers.

Do not merge OdinL into `odineval` prematurely. Reuse the execution ideas and
possibly code structure, but keep OdinL parsing/lowering/source mapping in this
repo.

## Major Mode

The first Emacs target should be `odinl-mode` for `*.odinl` files.

It should be very close to `clojure-mode`:

- derive from `clojure-mode`
- use structural editing packages such as paredit or smartparens
- keep Lisp navigation commands working
- use Clojure-like indentation with 2 spaces in `.odinl`
- font-lock OdinL special forms, keywords, Odin directive symbols, and raw
  `(odin "...")` escape hatches
- provide indentation overrides for OdinL forms such as `proc`, `struct`,
  `enum`, `union`, `let`, `switch`, `cond`, `for`, and `each`

The compiler's Odin source remains 4-space indented. The OdinL source format is
separate and should read like Clojure.

## Eval Tooling

OdinL eval must remain source generation plus Odin execution, not an
interpreter.

Initial commands should mirror the useful `odineval` and `cluck` workflows:

- eval form at point inline
- eval selected region inline
- eval current top-level form
- check form at point without running
- run/check current generated buffer
- show generated Odin for debugging
- clear inline results
- switch to result buffer

The eval path should be:

1. collect file context from the current `.odinl` buffer
2. lower OdinL to temporary Odin
3. inject a scratch `main` or scratch package runner when evaluating an
   expression/form
4. run `odin run` or `odin check` from the `odinl` CLI
5. map diagnostics back through OdinL source spans where possible
6. display results inline and in a result buffer

## Compiler Support Needed First

Before building the major mode deeply, the compiler should expose stable
tooling entry points:

- compile file to generated Odin
- compile with declaration source map
- check or run generated Odin with `odinl check` / `odinl run`
- evaluate a selected expression/form with surrounding file context using
  `odinl eval`
- optionally write generated Odin for editor inspection with `--generated`

The current `--map` output is declaration-level only. Eval forms do carry an
origin marker, so compiler errors in selected eval text can be reported against
`file:<eval>:line:column` instead of the surrounding file.
