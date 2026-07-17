# Kvist Ergonomics Roadmap

Kvist borrows Clojure's expression-oriented, data-first programming model
without adopting ambient laziness, universal boxing, runtime Vars, dynamic
ordinary dispatch, tracing garbage collection, or hidden ownership. Native
values retain Odin representation, cost, and lifecycle. `Data` is the explicit
immutable dynamic island.

Ro and Vev are the primary application workloads used to validate this
direction. They are acceptance workloads, not sources of application-specific
compiler behavior.

## Current Stock

| Area | Status | Next work |
| --- | --- | --- |
| `:defer`, `:defer-with`, and `:errdefer` | Implemented | Improve introductory documentation and analyzer precision |
| Coded ownership diagnostics and audit mode | Implemented | Continue reducing the conservative Vev audit backlog |
| Multi-return bindings and fallible guards | Implemented | Extend only when a concrete workload is not served by `:or-return`, `when-let`, `if-let`, `when-ok`, or `if-ok` |
| Runtime `Data`, quasiquote, EDN, and persistent updates | Implemented | Complete managed aggregate ownership |
| Transitive compilation cache and distinct entry keys | Implemented | Measure and split reusable package frontend artifacts |
| Source mapping | Partial | Cover more generated cleanup, specialization, and Data forms |
| Core `str` | Implemented | Validate rendering across Ro and Vev |
| Managed `Data` in native aggregates | Partial | Top-level Kvist structs are managed recursively; add containers, unions, closures, local/imported structs |
| Typed Data decoding and validated shapes | Partial | Scalars, owned strings, enums, defaults, recursive native structs, and selected owned dynamic arrays decode with paths; broaden collection elements and direct targets |
| Structural Data matching and destructuring | Planned | Design after aggregate ownership and decoding |
| Public Data builders/transients | Planned | Expose a safe freeze API based on the EDN reader's linear construction pattern |
| Vev Data result traversal and typed collection | Planned | Avoid unnecessary intermediate native arrays |
| Fine-grained incremental compilation | Planned | Measure phases, then cache package frontend artifacts |
| Native struct/fixed-array destructuring | Design-gated | Add only with explicit copy and ownership rules |
| Generic `?` propagation | Deferred | Existing guarded bindings cover current Ro/Vev result shapes |
| Formatter-template linting | Deferred | Use `str` for construction; keep `fmt` explicit formatting |
| Standalone native REPL and resident console | Later | Continue after incremental compilation and source mapping |

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

- Implemented for top-level Kvist structs: recursive managed fields,
  construction, copying, `assoc`, ordinary-field `update`, overwrite,
  move, return, named-result destruction, discarded values, and destruction.
- Continue the managed-value behavior across arrays, maps, unions, closures,
  local structs, imported Odin structs, and managed-field `update`.
- Add typed Data decoding for scalars, enums, structs, explicit default fields,
  and selected homogeneous collections.
- Implemented: integer, float, and boolean scalar decoders plus recursive
  type-directed native struct decoding for nested structs, `Data`, scalar,
  explicitly owned string, enum, and `:default` fields. Missing defaulted keys
  use the native field default; present values remain validated. Decoded managed
  fields and path-carrying `Decode-Error` values clean up automatically.
- Implemented: `(owned [dynamic]T)` fields for `Data`, boolean, integer, and
  floating-point elements. Validation completes before allocation and error
  paths include the failing vector index.
- Carry the exact Data path, expected shape, and actual kind in decode errors.
- Preserve the zero-allocation static quote path.

### 3. Structural Data Ergonomics And Vev Results

- Specify nested map/sequential patterns, literals, optional/default keys, rest
  bindings, exhaustiveness, and captured-value ownership using executable
  Ro/Vev examples.
- Add reusable validated shapes and safe public Data builders.
- Add borrowed Vev row traversal, typed row decoding, typed collection, and
  Data-pattern row destructuring without unnecessary intermediate arrays.
- Evaluate native struct and fixed-array destructuring under the same explicit
  copy and lifetime rules.

### 4. Compiler Immediacy And Diagnostics

- Measure package loading, expansion, lowering, emission, Odin checking, and
  linking separately.
- Cache package frontend artifacts and recompute only affected packages and
  dependents.
- Reuse unchanged Vev artifacts when editing Ro.
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
