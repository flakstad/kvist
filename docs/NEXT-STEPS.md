# Next Steps

This note tracks the current areas worth exploring next. It is not a design
history log.

## Current State

Kvist has:

- package-by-directory source loading with package-private `def...-` forms
- source-package macros with quasiquote, shipped DSL packages, and recursive
  macro expansion
- inline array, map, and set literals
- positional calls, named calls, mixed positional plus named-tail calls, and
  trailing default parameters for known top-level `defn`
- positional multi-return binding in `let`
- dot access for package names, struct fields, and indexed storage paths
- a shipped `html` package with rendering
- explicit ownership helpers and stricter escape diagnostics
- a shipped `kvist:test` package with:
  - `t.deftest`
  - `t.is`
  - `t.are`
  - nested `t.testing`
  - `t.use-fixtures :each`
  - setup-only `t.use-fixtures :once`
- CLI and Emacs support for docs, completion, xref, eval, and tests

Current intentional limits worth remembering:

- named/default/mixed call rewriting is limited to known top-level `defn`
- named/default/mixed call rewriting does not apply to arbitrary function values
- field destructuring is intentionally not part of the language; use dot access
  or explicit locals

## Most Likely Next Areas

### 1. Closures And Higher-Order Function Depth

Non-capturing function values are supported, and there is a narrow pass of
captured callbacks for compiler-known non-escaping helper sites such as
`map`, `filter`, `remove`, `keep`, and their bang variants.

Questions:

- whether this should widen beyond the current helper subset
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
- which helpers belong in the preferred user-facing surface
- moving as much package behavior as possible into ordinary `.kvist` source
  macros/functions rather than compiler intrinsics, so long as the lowered Odin
  remains equally direct and does not add indirection or unnecessary allocation

Current rule of thumb:

- if something is conceptually package API, tooling and docs should point at a
  real package file first
- package macros are preferred over compiler-known helper spellings when a thin
  wrapper can preserve the same direct Odin shape
- compiler intrinsics should shrink toward a lower-level substrate used by
  package code, not remain the primary public surface

Current package boundary:

- `kvist:str`, `kvist:set`, `kvist:map`, `kvist:soa`, and `kvist:cli`
  are mostly real package code
- `kvist:arr` exposes a broad real package facade, but part of that facade
  still expands to `arr.*` compiler intrinsics under the hood
- public package entries in tooling point at package files rather than
  directly at `emit.odin`
- the remaining intrinsic `arr.*` cases are mostly the wider grouping,
  partitioning, sorting, and in-place transform helpers where array-family
  coverage, ownership rules, or callback specialization still need the smaller
  compiler substrate

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
language-level discussion should be closure/function-value depth: how much
capturing convenience Kvist should provide before explicit context remains the
clearer low-level story.
