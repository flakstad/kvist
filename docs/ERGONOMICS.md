# Kvist Ergonomics Roadmap

Kvist borrows Clojure's expression-oriented, data-first programming model
without adopting ambient laziness, universal boxing, runtime Vars, dynamic
ordinary dispatch, or tracing garbage collection. Native values retain Odin
representation and cost. Kvist infers transfer facts and diagnostics from
ordinary flow, but ordinary native storage retains explicit Odin-style
cleanup. Automatic deterministic management is confined to `Data`, aggregates
whose lifetime is structurally derived from `Data`, and typed decode results
whose complete acquisition shape is known. `Data` is the explicit immutable
dynamic island.

Ro and Vev are the primary application workloads used to validate this
direction. They are acceptance workloads, not sources of application-specific
compiler behavior.

## Current Stock

| Area | Status | Next work |
| --- | --- | --- |
| `:defer`, `:defer-with`, and `:errdefer` | Implemented | Improve introductory documentation and analyzer precision |
| Coded ownership diagnostics and audit mode | Implemented | Continue reducing the conservative Vev audit backlog |
| Inferred procedure lifetime boundaries | Implemented | Improve branch precision and foreign-binding metadata |
| Lifetime explanation tooling | Implemented | Add editor presentation over `kvist lifetimes` facts |
| Multi-return bindings and fallible guards | Implemented | Extend only when a concrete workload is not served by `:or-return`, `when-let`, `if-let`, `when-ok`, or `if-ok` |
| Runtime `Data`, quasiquote, EDN, and persistent updates | Implemented | Complete managed aggregate ownership |
| Transitive compilation cache and distinct entry keys | Implemented | Persist parsed and expanded package state |
| Source mapping | Partial | Cover more generated cleanup, specialization, and Data forms |
| Core `str` | Implemented | Validate rendering across Ro and Vev |
| Managed `Data` in native aggregates | Partial | Top-level Kvist structs are managed recursively; add containers, unions, closures, local/imported structs |
| Typed Data decoding and validated shapes | Implemented | Structs and direct arrays decode or validate from one native shape definition with precise paths; broaden only from concrete boundary needs |
| Structural Data matching and destructuring | Implemented | Broaden only from concrete Data-oriented workloads |
| Public Data builders/transients | Planned | Expose a safe freeze API based on the EDN reader's linear construction pattern |
| Vev Data result traversal and typed collection | Planned | Avoid unnecessary intermediate native arrays |
| Generated package compilation and cache | Implemented | Tune bounded cache policy from workload data |
| Fine-grained frontend incremental compilation | Partial | Dependency-specific emission reuse is implemented; parsing and macro expansion remain graph-wide on misses |
| Native struct/fixed-array destructuring | Design-gated | Add only with explicit copy and ownership rules |
| Generic `?` propagation | Deferred | Existing guarded bindings cover current Ro/Vev result shapes |
| Formatter-template linting | Deferred | Use `str` for construction; keep `fmt` explicit formatting |
| Native REPL and reload live console | Partial | Standalone and attached sessions, editor integration, persistent definitions and values, debugging, and fast redefinition are implemented. Continue hands-on testing with large projects and validate long-session resource use. |

## Milestones

### 1. Ergonomic Foundation

- Implemented: coded, confidence-aware, deduplicated ownership diagnostics.
  Normal commands show definite findings and `--ownership-audit` includes
  conservative findings. Further path-sensitive precision remains ongoing.
- Implemented: diagnostics and source maps persist in the compilation cache so
  cold and warm commands agree.
- Implemented: `--explain-cache`, `cache inspect`, and targeted or complete
  compile-cache clearing.
- Implemented: core `str` is owned, allocator-aware construction for ordinary
  Odin-printable values.
- Keep Ro's ordinary build quiet and make Vev audit output actionable.

### 2. Safe Data/Native Boundaries

- Implemented: ordinary procedure bodies infer allocating results, borrowed
  views, and consuming parameters. No ownership-qualified type syntax or
  declaration directives are required.
- Implemented: `kvist lifetimes` explains inferred boundaries without changing
  the source program.
- Deliberately not implemented: a custom native managed-type protocol.
  `Type-destroy`, `Type-clone`, and similar names remain ordinary procedures.
  Opaque native resources use explicit Odin-style cleanup.
- Continue by improving conservative inference and keeping foreign binding
  facts in one reviewed compiler registry.
- Implemented for top-level Kvist structs: recursive managed fields,
  construction, copying, `assoc`, ordinary-field `update`, overwrite,
  move, return, named-result destruction, discarded values, and destruction.
- Continue the managed-value behavior across arrays, maps, unions, closures,
  local structs, imported Odin structs, and managed-field `update`.
- Add typed Data decoding for scalars, enums, structs, explicit default fields,
  and selected homogeneous collections.
- Implemented: integer, float, and boolean scalar decoders plus recursive
  type-directed native struct decoding for nested structs, `Data`, scalar,
  string, enum, and `:default` fields. Missing defaulted keys
  use the native field default; present values remain validated. Decoded managed
  fields and path-carrying `Decode-Error` values clean up automatically.
- Implemented: `[dynamic]T` decoded fields for `Data`, boolean, integer,
  floating-point, enum, and Kvist struct elements. Validation completes before
  allocation, error paths include the failing vector index and nested struct
  field, invalid enum elements retain enum-specific diagnostics, and managed
  struct elements are copied and destroyed recursively.
- Implemented: direct `(data.decode (dynamic T) value [path])` targets for the
  same element set. Their destructured success bindings receive structural
  cleanup because the decode boundary proves the complete allocation shape;
  ordinary native arrays outside this boundary remain explicit.
- Implemented: `(data.validate Type value [path])` reuses the complete
  type-directed traversal without constructing structs, cloning managed
  fields, or allocating native arrays. Data can remain Data after one boundary
  check.
- Carry the exact Data path, expected shape, and actual kind in decode errors.
- Preserve the zero-allocation static quote path.

### 3. Structural Data Ergonomics And Vev Results

- Implemented: nested map/sequential patterns, literals, optional/default keys,
  rest bindings, structural `match`, and captured-value ownership, with
  executable examples and compiler properties.
- Use native-type validation as the reusable shape mechanism; add safe public
  Data builders.
- Add borrowed Vev row traversal, typed row decoding, typed collection, and
  Data-pattern row destructuring without unnecessary intermediate arrays.
- Evaluate native struct and fixed-array destructuring under the same explicit
  copy and lifetime rules.

### 4. Compiler Immediacy And Diagnostics

- Implemented: measure dependency discovery, reading/resolution, macro
  expansion, parsing, lowering, analysis, emission, source maps, Odin checking,
  code generation, and linking separately.
- Implemented: emit imported Kvist source directories as separate generated
  Odin packages, with one shared runtime-helper package.
- Implemented: cache exact generated package graphs, including source maps,
  warnings, and dependency metadata.
- Implemented: retain per-package frontend artifacts keyed by local content and
  the inferred interfaces of recorded direct dependencies. Body-only edits
  re-emit the changed package, while interface changes invalidate actual
  dependants and preserve unrelated packages.
- Continue by persisting parsed/macro-expanded state; graph-cache misses still
  perform graph-wide loading, expansion, and lightweight interface analysis.
- Map diagnostics through cleanup, quasiquote, literals, callback
  specialization, generic instantiation, and macro-generated declarations.

## Permanent Constraints

- Native structs and homogeneous collections remain the ordinary internal
  representation.
- Sequence operations do not become lazy by default.
- `Data` remains immutable, deterministic, cycle-free through its public API,
  and visible in signatures.
- Ordinary calls do not gain runtime dispatch or hidden boxing.
- Ownership crossings remain explicit and exceptions do not become the normal
  error path.
