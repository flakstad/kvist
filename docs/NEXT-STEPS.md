# Next Steps

This note tracks the current areas worth exploring next. It is not a design
history log.

## Current State

Kvist now has:

- package-by-directory source loading with package-private `def...-` forms
- package-local macros with quasiquote, shipped DSL packages, and recursive
  macro expansion
- inline array, map, and set literals
- a shipped `hiccup` package with rendering
- explicit ownership helpers and stricter escape diagnostics
- a shipped `kvist:test` package with:
  - `t/deftest`
  - `t/is`
  - `t/are`
  - nested `t/testing`
  - `t/use-fixtures :each`
  - setup-only `t/use-fixtures :once`
- CLI and Emacs support for docs, completion, xref, eval, and tests

## Most Likely Next Areas

### 1. Closures And Higher-Order Function Depth

Non-capturing proc values are supported, and there is now a first narrow pass
of captured callbacks for compiler-known non-escaping helper sites such as
`map`, `filter`, `remove`, `keep`, and their bang variants.

Questions:

- whether this should widen beyond `map` / `map!`
- whether more than one captured outer local should be supported
- how far to take captured callbacks before explicit context should remain the
  preferred style

### 2. Package And Tooling Polish

The package model is in place, but there is still room to tighten:

- package diagnostics and error messages
- project-wide test discovery/reporting polish
- package-aware editor commands and CLI inspection helpers
- docs that describe package layout and visibility concisely

### 3. Standard Library Shape

The library surface is real, but it should keep being reviewed against the
current language direction:

- package boundaries
- helper naming
- ownership conventions
- what belongs in the preferred user-facing surface vs raw Odin interop

### 4. Future DSL Work

High-value data DSLs remain attractive, but they are not the next foundational
step.

Strong candidates:

- routing
- a Datomic-flavored Datalog query DSL

These should build on the current macro system and still lower to explicit,
typed internal structures.

### 5. Hot Reload And Live Workflow

This work is real but should remain clearly separate from the core language
surface:

- native hot reload over ordinary compiled Kvist/Odin code
- optional embedded live runtime where it materially helps development

See:

- [HOT-RELOAD.md](./HOT-RELOAD.md)
- [RELOAD-APP-DESIGN.md](./RELOAD-APP-DESIGN.md)
- [LIVE-RUNTIME.md](./LIVE-RUNTIME.md)

## Current Bias

If there is no stronger pressure from a concrete use case, the next serious
language-level discussion should be closures and higher-order function depth.
