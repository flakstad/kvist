# Benchmarks

The benchmark scripts in `scripts/` compare generated Kvist output against
direct Odin for the same workloads.

Current harnesses:

- `./scripts/bench_sequence_helpers.sh`
- `./scripts/bench_aggregate_helpers.sh`
- `./scripts/bench_mutation_helpers.sh`
- `./scripts/bench_closure_helpers.sh`
- `./scripts/bench_source_backed_arr.sh`
- `./scripts/bench_core_helpers.sh`
- `./scripts/bench_package_helpers.sh`

## What They Are For

Use these benchmarks to answer a small set of practical questions:

- whether Kvist lowering stays close to direct Odin when the source is already
  Odin-shaped
- whether helper-heavy code is paying for real intermediate allocations
- whether mutating helpers and core helpers stay on a parity path
- whether shipped source packages stay in the same performance band as the
  intrinsic or direct-Odin versions

## Reading The Results

The important distinction is semantic cost versus lowering cost.

When Kvist source already matches direct Odin control flow, mutation, and data
shape, the generated code should stay close to direct Odin in both timing and
allocation behavior.

When Kvist source uses eager helper pipelines that build intermediate owned
collections, the generated code may still be correct and readable while being
meaningfully slower than a hand-fused loop. That is a source-level tradeoff, not
necessarily a compiler regression.

## Practical Use

Use the benchmarks as regression checks:

- watch for generated-code shape drifting away from obvious Odin
- watch for unexpected allocation changes
- compare helper forms with direct loops when deciding what surface should stay
  eager and what should remain an explicit loop

For transform-heavy or helper-heavy paths, also inspect the generated Odin with
`kvist expand` when a benchmark moves unexpectedly.
