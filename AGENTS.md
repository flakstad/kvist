# odinl Agent Notes

This repo is an experiment in writing Odin with a Lisp/Clojure-shaped surface.
The project goal is **Odin in parens**, not Clojure semantics on Odin.

## Direction

- Preserve Odin semantics.
- Emit readable, boring `.odin`.
- Keep the translator small and source-to-source.
- Let `odin check` validate the generated code.
- Prefer mechanical syntax lowering over abstraction.
- Treat `.odinl` as the source extension and `.odin` as generated or ordinary
  Odin.
- Copy raw Odin through unchanged outside detected Lisp-Odin top-level forms.
- Do not require `#odinl` / `#end` markers for ordinary top-level forms unless
  implementation experience proves they are needed.
- Treat REPL-like tooling as temp Odin generation plus `odin run`, not as an
  interpreter.
- Treat `[]` and `{}` as Odin literal sugar, not as Clojure collections.

## Non-Goals

- Do not add a runtime unless a tiny helper is unavoidable.
- Do not introduce persistent collections, seqs, dynamic vars, namespaces, or
  other Clojure semantics.
- Do not hide Odin concepts behind new abstractions.
- Do not make generated Odin hard to inspect.
- Do not build a fake stateful REPL or hidden dynamic environment.
- Do not make mixed `.odin` files the primary workflow; use `.odinl` for mixed
  source.

## Implementation

- Main compiler: `src/odinl/*.odin`.
- CLI entry point: `cmd/odinl/main.odin`.
- Tests: `tests/compiler_test.odin`.
- Examples: `examples/*.odinl`.
- Run tests with `odin test tests`.
- Build the compiler with `odin build cmd/odinl`.
- Check generated Odin with `odin check <file>.odin -file`.
- Future eval-selection support should generate a scratch Odin entry point and
  run/check that with Odin itself.
- `odineval` may be reused as the execution/editor tooling base if OdinL is
  pursued further: package/project detection, temp workspaces, internal package
  eval, Emacs overlays, result buffers, and build/check/test commands are
  relevant. Keep OdinL parsing/lowering/source mapping separate.
- Do not merge OdinL into `odineval` prematurely. `odineval` should remain a
  practical ordinary-Odin tool; OdinL is a syntax experiment.

## Style

- Add forms only when the Odin output is obvious.
- Use 4 spaces for indentation in Odin `.odin` source files. Do not use tabs.
- Use Clojure-like 2-space indentation in `.odinl` source and examples.
- Keep raw escape hatch support via `(odin "...")`.
- Favor simple, explicit syntax over clever inference.
- Keep examples small and executable.
- Prefer Odin-shaped proc return syntax: `(proc name [...] -> type body...)`.
- Prefer implicit final returns for non-void procs instead of explicit
  `(return ...)` in ordinary odinl code.
- Treat `let` as Clojure-style scoped binding syntax: `(let [x value] body...)`.
- Do not use `^type` for type hints; `^` is Odin pointer syntax.
- Use explicit type ascription for typed literal lowering. `(as Type literal)`
  is the current placeholder until the syntax settles.
