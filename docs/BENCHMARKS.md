# Benchmark Notes

Current benchmark harness:

- `./scripts/bench_sequence_helpers.sh`
- `./scripts/bench_aggregate_helpers.sh`
- `./scripts/bench_mutation_helpers.sh`
- `./scripts/bench_closure_helpers.sh`
- `./scripts/bench_source_backed_arr.sh`
- `./scripts/bench_core_helpers.sh`
- `./scripts/bench_package_helpers.sh`

These compare generated Kvist output against hand-written Odin for the same
workloads.

## What The Current Numbers Say

There are two distinct cases.

### 1. Near-parity lowering

When Kvist source already looks close to Odin control flow and mutation, the
generated code is very close to the direct Odin version.

Examples from the current runs:

- aggregate report benchmark:
  - `report-group`: Kvist `45.881 ms`, direct Odin `46.303 ms`
  - `report-aggregate`: Kvist `42.632 ms`, direct Odin `42.864 ms`
  - `report-loop`: Kvist `17.950 ms`, direct Odin `18.232 ms`

- sequence/helper benchmark examples:
  - `sort`: Kvist `2.774 ms`, direct Odin `2.735 ms`
  - `sort-by`: Kvist `3.517 ms`, direct Odin `3.502 ms`
  - `orders-ptr-loop`: Kvist `3.158 ms`, direct Odin `3.069 ms`
  - `orders-map!`: Kvist `4.729 ms`, direct Odin `4.681 ms`

This is the encouraging case. It means the source-to-source lowering itself is
not introducing meaningful overhead when the source model already matches the
host model.

### 2. High-level helper pipelines versus fused loops

Some of the largest gaps are not "bad codegen" so much as "different
semantics":

- `pipe-map-filter`: Kvist `26.532 ms`, direct Odin `0.797 ms`
- `pipe-filter-map`: Kvist `10.806 ms`, direct Odin `0.013 ms`
- `orders-revenue`: Kvist `14.348 ms`, direct Odin `1.361 ms`
- `orders-threaded`: Kvist `14.039 ms`, direct Odin `1.319 ms`

In these cases the Kvist version is using eager helper pipelines that allocate
intermediate results, while the Odin version is a hand-fused loop with no
intermediate collections.

That is an important distinction:

- the generated Odin is still honest
- but the source abstraction carries real runtime cost

So these numbers are useful pressure, not a compiler bug by themselves.

## Current Conclusion

The compiler is already doing a good job of mechanical lowering.

The main performance questions are:

- where should Kvist expose high-level eager helpers with explicit cost?
- where should we encourage in-place or loop-oriented forms?
- where are explicit loops the right source-level tool?

## Mutation Surface Baseline

The focused mutation benchmark covers:

- `update!` on struct fields
- copy-update of struct values
- explicit pointer mutation
- `update!` on dynamic arrays
- `update!` on maps

Current focused mutation run:

- `struct-update`: Kvist `0.082 ms`, direct Odin `0.084 ms`
- `pointer-update`: Kvist `0.075 ms`, direct Odin `0.083 ms`
- `array-update!`: Kvist `0.303 ms`, direct Odin `0.324 ms`
- `map-update!`: Kvist `7.676 ms`, direct Odin `9.087 ms`

`update!` lowers simple arithmetic updater cases to compound assignment when
possible:

- `+=`
- `-=`
- `*=`
- `/=`
- unary `inc` / `dec`

The benchmark uses array-backed struct workloads so copy-update versus pointer
mutation is measurable.

The useful conclusion is:

- struct copy-update and pointer mutation are effectively at parity in this
  workload
- array `update!` is also at parity after the lowering fix
- the map `update!` path is also at parity here, with matching allocation
  counts and total allocated bytes versus direct Odin

## Focused Map Update Benchmark

The stripped-down map-only benchmark removes the broader mutation benchmark's
other costs and answers the remaining question directly.

Current focused map-only run:

- Kvist `map-update!`: `63.822 ms`
- direct Odin: `63.917 ms`
- both with `allocs=1800`, `total=19852800`, `peak=73984`, `live=0`

The generated hot loop is now:

```odin
counts[j % KEY_MOD] += 1
```

The focused map workload is effectively identical to direct Odin in both time
and allocation behavior.

## Source-Backed `arr` Benchmark

The source-backed `kvist:arr` benchmark covers:

- intrinsic `arr.*` lowering
- imported `kvist:arr` source-backed lowering
- direct Odin baselines
- one fused-loop lower bound for the eager pipeline case

Current run shape:

- `pipe-intrinsic`: `19.186 ms`
- `pipe-source`: `18.784 ms`
- `pipe-direct`: `17.983 ms`
- `pipe-fused`: `2.615 ms`
- `builders-intrinsic`: `9.763 ms`
- `builders-source`: `9.713 ms`
- `builders-direct`: `9.223 ms`
- `scan-intrinsic`: `10.685 ms`
- `scan-source`: `10.505 ms`
- `scan-direct`: `10.358 ms`
- `reorder-intrinsic`: `84.203 ms`
- `reorder-source`: `87.099 ms`
- `reorder-direct`: `77.709 ms`
- `remove-at-source`: `13.004 ms`
- `remove-at!-source`: `12.553 ms`
- `remove-at-direct`: `6.893 ms`
- `remove-at!-direct`: `7.639 ms`

The important result is not any one number, but the shape:

- intrinsic and source-backed paths match allocation counts exactly in the
  tested `arr` surface
- the source-backed path is within normal run-to-run noise of the intrinsic
  path on these workloads
- both stay close to the direct eager Odin baseline
- source-backed `reverse`, `interpose`, and `interleave` run in the same
  allocation and timing envelope as the intrinsic helpers on the reorder
  workload
- the source-backed remove-at returning helpers emit the same bulk-copy shape
  as raw Odin: `append(&out, ..xs)` followed by `ordered_remove` or
  `unordered_remove`
- the remove-at bang helpers lower directly to Odin's `ordered_remove` and
  `unordered_remove`; the benchmark setup uses the same inline bulk-copy
  shape as the direct Odin baseline so this row measures the bang wrapper rather
  than `arr.into`
- remove-at timings still show more run-to-run spread than the allocation shape;
  allocation equality and generated code shape are the stable regression signals
  until the benchmark harness is tightened further
- the fused loop is still much faster when the semantics avoid intermediate
  owned collections entirely

`scripts/bench_source_backed_arr.sh` compares the current working tree against
`HEAD` by default. Use `BASE_REF=skip` to run only the current compiler and
direct Odin baselines.

## Captured Callback Baseline

The focused captured-callback benchmark covers explicit helper-with-context
lowering:

- Kvist `map`, `filter`, `remove`, `keep`, and `map!` with captured outer locals
- Kvist-defined non-escaping callback APIs that receive captured callbacks
- direct Odin helper-with-context equivalents
- direct Odin loop baselines

Run it with:

```sh
./scripts/bench_closure_helpers.sh
```

This benchmark is meant to answer two separate questions:

1. whether the generated Kvist lowering is at parity with an explicit
   helper-with-context shape in direct Odin
2. how much overhead remains versus hand-written loop code when the source uses
   eager helper style instead of explicit loops

## Core Helper Baseline

The focused core helper benchmark covers the canonical collection kernel:

- `count`
- `get`
- `slice`
- `contains?`

Run it with:

```sh
./scripts/bench_core_helpers.sh
```

Current run shape:

- `index-core`: `2.884 ms`
- `index-direct`: `2.853 ms`
- `slice-core`: `0.000 ms`
- `slice-direct`: `0.000 ms`
- `map-core`: `199.146 ms`
- `map-direct`: `200.095 ms`

The important result is the shape:

- all measured core helper workloads ran with `allocs=0`, `total=0`, and `live=0`
- `count`, `get`, `slice`, and `contains?` lower
  essentially identically to direct Odin in these hot paths
- the canonical bare core helpers are performance-neutral on the tested workloads

## Package Surface Baseline

The focused package-surface benchmark covers package APIs that are hot and
runtime-safe:

- `str.*` transforms and queries
- `map.*` constructor plus bang mutation helpers
- `set.*` constructor plus bang mutation helpers

Run it with:

```sh
./scripts/bench_package_helpers.sh
```

Current run shape:

- `str-package`: Kvist `1.511 ms`, direct Odin `1.561 ms`
- `map-package`: Kvist `0.147 ms`, direct Odin `0.147 ms`
- `set-package`: Kvist `0.392 ms`, direct Odin `0.388 ms`

Allocation shape from the current run:

- `str-package` and `str-direct`: `allocs=6000`, `total=172800`, `peak=144`
- `map-package` and `map-direct`: `allocs=500`, `total=160000`, `peak=640`
- `set-package` and `set-direct`: `allocs=1250`, `total=432000`, `peak=1728`

What this says:

- the string package wrappers stay in the same performance band as direct Odin
- the map bang/package surface is effectively identical to direct Odin in both
  time and allocation behavior
- the set bang/package surface is also at parity
