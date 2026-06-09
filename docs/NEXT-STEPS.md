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

Non-capturing function values are supported, and captured callbacks now lower to
explicit context-passing calls when the compiler can prove the callback does not
escape. This covers known non-escaping helpers such as `map`, `filter`,
`remove`, `keep`, `map-indexed`, reducers, scans, min/max helpers, and their
safe indexed/bang variants, plus Kvist-defined functions whose callback
parameter is only called directly or forwarded to another non-escaping Kvist
function.

Open questions:

- whether to support captured callbacks for indirect callback contexts such as
  `sort-by`
- whether explicit context parameters should remain preferred for APIs where
  callback lifetime or storage is part of the design

### 2. Reusable Functional Transforms

Reusable fused transforms are now a small functional-programming prototype. The
next question is whether examples prove clear value over direct `each` loops
before expanding the surface.

The current prototype uses:

- `deftransform` for named compile-time transform definitions
- `comp` for top-to-bottom item-flow composition
- `into` for explicit collection output
- `transduce` for explicit scalar accumulation

See [FUNCTIONAL-TRANSFORMS.md](./FUNCTIONAL-TRANSFORMS.md).

### 3. Functional Programming Discussion Backlog

These are candidate FP-adjacent directions to discuss one by one before any
implementation decision. They are notes, not accepted feature plans.

1. Immutable-by-default value workflows

   Build on shallow `assoc` / `update` and ordinary Odin value structs. Possible
   discussion topics: nested value updates, state-transition examples, copy
   diagnostics, and whether generated `with-*` helpers are useful.

   Decision from discussion: nested `assoc` / `update` over struct fields is a
   desired future direction. It should lower as one root value copy followed by
   nested assignment into that copy. Dynamic arrays, slices, maps, and sets are
   out of scope for this feature because immutable element updates there require
   explicit copying or persistent data structures.

2. Algebraic data and case analysis

   Build on `defunion` with a readable `case` form that handles both ordinary
   subject-based value cases and union/type payload cases. This may be the
   highest-value FP direction because it improves domain modeling without adding
   a runtime collection abstraction.

   Decision from discussion: prefer `cond` for ordered predicate branching and
   `case` for subject-based case analysis. `case` should cover value cases,
   grouped value cases, and union/type payload cases such as `(Connected conn)`.
   The existing `switch` form should be dropped from the user-facing language
   after a migration path, rather than growing into a second public case-analysis
   surface.

3. Explicit parallel processing

   Explore constrained parallel loops or maps over slices/arrays, probably
   chunked and lowered to `core:thread` / thread-pool work. Any design must make
   ordering, mutation, output ownership, errors, cancellation, and chunking
   inspectable.

   Decision from discussion: do not add core `par-each` / `par-map` forms.
   Parallelism should be explored, if at all, as a higher-level package such as
   a future `kvist:par`, built over Odin's `core:thread`, thread pools, and
   typed channels. Promising directions are typed futures/await and eager
   ordered parallel map over explicit pools, but naming and API surface remain
   open and must be discussed in detail before any implementation.

4. Immutable data structures

   Persistent vectors/maps/sets would require a real runtime data-structure and
   allocator story. Near-term alternatives are value structs, explicit owned
   arrays/maps, immutable views/slices, and possible builder-then-freeze
   patterns.

   Decision from discussion: defer persistent immutable collections. Kvist
   should first make typed struct/value workflows excellent with nested
   `assoc` / `update`, state-transition examples, algebraic data, and explicit
   owned mutable containers. Full-copy array/map/set helpers may be considered
   later, but they must be visibly allocating O(n) operations. Persistent
   vectors/maps/sets should only be revisited as a package-level runtime
   commitment if concrete app-state use cases make full-copy helpers or explicit
   mutation insufficient.

5. Function composition and partial application

   Consider only where lowering remains explicit. General heap closures should
   not become the default; compile-time or non-escaping composition is a better
   fit unless a concrete use case proves otherwise.

### 4. Package And Tooling Polish

The package model is in place, but there is still room to tighten:

- package diagnostics and error messages
- project-wide test discovery/reporting polish
- package-aware editor commands and CLI inspection helpers
- docs that describe package layout and visibility concisely

### 5. Standard Library Shape

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

### 6. Future DSL Work

High-value data DSLs remain attractive, but they are not the next foundational
step.

Strong candidates:

- routing
- a Datomic-flavored Datalog query DSL

These should build on the current macro system and still lower to explicit,
typed internal structures.

### 7. Hot Reload And Live Workflow

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
language-level discussion should be reusable transforms: whether named fused
pipelines provide enough reuse, correctness, and performance benefit over manual
`each` loops.
