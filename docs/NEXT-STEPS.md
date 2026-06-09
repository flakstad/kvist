# Next Steps

This note tracks the current areas worth improving next. It is not a design
history log.

## Current State

Kvist now has a coherent small language surface:

- package-by-directory source loading with package-private `def...-` forms
- `.kvist` packages that may live beside ordinary `.odin` sidecar files
- source-package macros with quasiquote and recursive macro expansion
- inline array, map, set, struct, enum, union, matrix, SOA, SIMD, and compact
  type forms that lower to Odin-shaped values
- type-call construction and conversion with `(T value)`
- positional calls, named calls, mixed positional plus named-tail calls, and
  trailing default parameters for known top-level `defn`
- positional multi-return binding in `let`
- dot access for package names, struct fields, and indexed storage paths
- indexed and sliced places such as `xs[i]`, `xs[start:end]`, and
  `particles.vx[i]`
- `set!`, `mut!`, and place-first `update!`
- `each` and `while` for loops
- expression `for` comprehensions with `:let`, `:when`, `:while`, and `:into`
  for dynamic arrays, maps, and sets
- non-capturing function values
- captured callback specialization for known non-escaping helper and user
  function calls
- explicit ownership helpers and conservative ownership warnings
- CLI and editor-oriented commands for compile/check/run/eval/expand,
  macroexpand, docs, completion, lookup, xref, symbols, and tests

The shipped package layer is also substantial:

- `kvist:arr`
- `kvist:map`
- `kvist:set`
- `kvist:str`
- `kvist:soa`
- `kvist:cli`
- `kvist:html`
- `kvist:http`
- `kvist:test`
- `kvist:hot`, `kvist:reload`, and `kvist:live`

## Intentional Boundaries

These are deliberate boundaries, not accidental missing features:

- no Clojure data model
- no hidden seq runtime
- no lazy sequence abstraction
- no general heap-allocated closure objects
- no field destructuring; use dot access or explicit locals
- no broad keyword-as-data model; keywords are used for structural markers such
  as `:else`, `:when`, `:let`, `:while`, and `:into`
- named/default/mixed call rewriting is limited to known top-level `defn`
- named/default/mixed call rewriting does not apply to arbitrary function
  values

## Most Useful Work Now

### 1. Tooling Polish

The compiler and CLI already expose the right basic operations. The next work is
to make them feel finished:

- better `help` output and command-specific help
- package-aware test discovery/reporting polish
- clearer package/workspace discovery behavior
- editor command polish around `eval`, `expand`, `macroexpand`, `doc`,
  `lookup`, completion, and xref
- stable diagnostic output that is friendly to `compilation-mode` and
  `next-error`

### 2. Diagnostics

Kvist deliberately relies on Odin for semantic validation, but frontend errors
should still be specific when the frontend knows what went wrong.

Good targets:

- improve generic `unsupported ...` errors where the expected shape is known
- improve errors around type-call construction, inline typed literals, and
  callback specialization
- keep macro/source maps precise enough that generated Odin errors point back
  to useful Kvist source spans
- keep ownership warnings conservative but make remediation text concrete

### 3. Package Boundary Cleanup

The package API is real, but some helpers still lower through compiler-known
intrinsics when that is the only way to preserve direct Odin output.

Current rule of thumb:

- user-facing helpers should live in package files when possible
- package macros are preferred over compiler-known public spellings when they
  preserve the same generated Odin shape
- compiler intrinsics should remain a small substrate for cases that need
  frontend knowledge, ownership diagnostics, or callback specialization
- docs and tooling should point users at package APIs first

The main package to keep reviewing is `kvist:arr`, because it exposes the
broadest helper surface and still uses the most compiler substrate.

### 4. Functional Programming Surface

Kvist now has a small functional-programming layer that still lowers to explicit
Odin:

- `assoc` / `update` for value-style struct updates, including nested fields
- `->` for single-value function pipelines
- `deftransform`, `comp`, `into`, and `transduce` for reusable fused transform
  pipelines
- `defsource` for reusable stateful producers consumed by `each` and `into`
- `case` / `cond` as the preferred direction for expression-oriented branching

The next FP-adjacent discussions should be design discussions before more
implementation:

- source protocol generalization: `transduce`, first-class source values,
  inline callbacks, richer stop/error signaling, and stream/event sources
- parallel processing as a package surface rather than core syntax, probably
  around futures, pools, ordered maps, cancellation, and typed channels
- pattern matching over unions and structs, including whether `switch` remains
  only a compatibility spelling while `case` becomes the user-facing form
- persistent immutable data structures, deferred until concrete app-state use
  cases justify a package-level runtime commitment

See [FUNCTIONAL-TRANSFORMS.md](./FUNCTIONAL-TRANSFORMS.md).

### 5. Test And Memory Hygiene

The current compiler and example suites pass, but Odin's test memory tracker
still reports noisy warnings in some negative compiler tests and tooling/symbol
tests. Those warnings do not currently indicate failing language behavior, but
they make the test baseline harder to scan and should be cleaned up.

### 6. Future DSL Work

High-value data DSLs remain attractive, but they are not the next foundational
step.

Strong candidates:

- routing
- a Datomic-flavored Datalog query DSL

These should build on the current macro system and still lower to explicit,
typed internal structures.

### 7. Hot Reload And Live Workflow

Native hot reload and the embedded live runtime are useful experiments, but
they should stay clearly separated from the core language surface.

The current split is:

- native hot reload: ordinary compiled Kvist/Odin code with reload lifecycle
  support
- live runtime: a smaller interpreted/shared subset for development-time
  continuity and host-driven commands/hooks

See:

- [HOT-RELOAD.md](./HOT-RELOAD.md)
- [RELOAD-APP-DESIGN.md](./RELOAD-APP-DESIGN.md)
- [LIVE-RUNTIME.md](./LIVE-RUNTIME.md)
- [LIVE-SHARED-SUBSET.md](./LIVE-SHARED-SUBSET.md)

## Lower Priority

These ideas are worth preserving, but they should wait for concrete pressure:

- captured callbacks for indirect callback contexts such as `sort-by`
- broader function-value convenience beyond non-escaping specialization
- routing DSLs
- Datalog-style query DSLs
- larger standard library expansion
