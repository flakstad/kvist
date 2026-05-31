# Kvist Agent Notes

This repo is an experiment in building a Lisp-shaped systems language that
compiles to readable Odin.

## Direction

- Keep Odin as the code generation and execution target.
- Emit readable, boring `.odin`.
- Keep the core language tooling small and explicit where practical.
- Let `odin check` validate the generated code.
- Prefer explicit, inspectable lowering over opaque abstraction.
- Treat `.kvist` as the source extension and `.odin` as generated or ordinary
  Odin.
- Copy raw Odin through unchanged outside detected Lisp-Odin top-level forms.
- Do not require `#kvist` / `#end` markers for ordinary top-level forms unless
  implementation experience proves they are needed.
- Treat AOT compilation, hot reload, and live/runtime tooling as complementary
  parts of the project rather than forcing one execution model everywhere.
- Treat `[]` and `{}` as Kvist collection literals that lower honestly to Odin.

## Current Biases

- Do not introduce a hidden seq runtime, dynamic vars, or a fake interpreter
  environment.
- Do not hide Odin concepts behind new abstractions.
- Do not make generated Odin hard to inspect.
- Do not make mixed `.odin` files the primary workflow; use `.kvist` for mixed
  source.

## Implementation

- Main compiler: `src/kvist/*.odin`.
- CLI entry point: `cmd/kvist/main.odin`.
- Tests: `tests/compiler_test.odin`.
- Examples: `examples/*.kvist`.
- Run tests with `odin test tests`.
- Build the compiler with `odin build cmd/kvist`.
- Check generated Odin with `odin check <file>.odin -file`.
- Eval-selection support may use scratch Odin generation, native hot reload, or
  live/runtime machinery depending on which mode is being exercised.
- `probe` may be reused as the execution/editor tooling base if Kvist is
  pursued further: package/project detection, temp workspaces, internal package
  eval, Emacs overlays, result buffers, and build/check/test commands are
  relevant. Keep Kvist parsing/lowering/source mapping separate.
- Keep Kvist concerns separate from `probe` unless there is a clear
  architectural reason to merge pieces.

## Style

- Add forms only when the Odin output is obvious.
- Use 4 spaces for indentation in Odin `.odin` source files. Do not use tabs.
- Use Clojure-like 2-space indentation in `.kvist` source and examples.
- Keep raw escape hatch support via `(odin "...")`.
- Favor simple, explicit syntax over clever inference.
- Keep examples small and executable.
- Prefer Odin-shaped proc return syntax: `(proc name [...] -> type body...)`.
- Prefer implicit final returns for non-void procs instead of explicit
  `(return ...)` in ordinary kvist code.
- Treat `let` as Clojure-style scoped binding syntax: `(let [x value] body...)`.
- Do not use `^type` for type hints; `^` is Odin pointer syntax.
- Use explicit type ascription for typed literal lowering. `(as Type literal)`
  is the current placeholder until the syntax settles.
