# Kvist Ergonomics

Kvist borrows Clojure's expression-oriented, data-first programming model
without adopting ambient laziness, universal boxing, runtime Vars, dynamic
ordinary dispatch, or tracing garbage collection. Native values retain Odin
representation and cost.

Kvist infers transfer facts from ordinary control flow. Native storage follows
Odin-style cleanup, while `Data` and supported aggregates have deterministic
automatic management.

## Design Constraints

- Native structs and homogeneous collections are the ordinary internal
  representation.
- Sequence operations are eager unless a transform explicitly fuses them.
- `Data` is immutable, deterministic, cycle-free through its public API, and
  visible in signatures.
- Ordinary calls do not use hidden boxing or runtime dispatch.
- Ownership crossings are explicit, and exceptions are not the normal error
  path.
- Opaque native resources use explicit cleanup. Procedure names such as
  `Type-destroy` and `Type-clone` do not define a managed-type protocol.

## Current Capabilities

- `:defer`, `:defer-with`, and `:errdefer` provide scoped cleanup.
- Ownership diagnostics distinguish definite findings from conservative audit
  findings. `kvist lifetimes` explains inferred allocation, borrowing, and
  transfer boundaries.
- Top-level Kvist structs manage `Data` fields through construction, copying,
  updates, moves, returns, and destruction.
- `data.decode` and `data.validate` support scalar values, enums, nested
  structs, defaults, and typed dynamic arrays with precise error paths.
- Structural `Data` destructuring and `match` support nested sequential and map
  patterns, literals, optional keys, defaults, and rest bindings.
- Source maps, diagnostics, generated package graphs, and per-package emission
  artifacts participate in the compilation cache.
- The native REPL supports persistent definitions and values, compatible
  redefinition, source tooling, debugging, and attachment to reload-enabled
  applications.

## Areas of Development

- More path-sensitive ownership analysis and foreign-binding metadata.
- Managed values inside native containers, unions, closures, local structs,
  and imported structs.
- Public builders for efficient incremental `Data` construction.
- Persisted parsed and macro-expanded package state.
- Source mapping for more generated cleanup, specialization, and macro forms.
- Dedicated editor presentation for lifetime information and Kvist language
  tooling.
