# Benchmark Notes

Current benchmark harness:

- `./scripts/bench_sequence_helpers.sh`
- `./scripts/bench_aggregate_helpers.sh`
- `./scripts/bench_mutation_helpers.sh`
- `./scripts/bench_closure_helpers.sh`
- `./scripts/bench_source_backed_arr.sh`
- `./scripts/bench_destructuring_helpers.sh`

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

The main performance question is now:

- where should Kvist expose high-level eager helpers with explicit cost?
- where should we encourage in-place or loop-oriented forms?
- where do we want future optimization/fusion passes, if any?

## Mutation Surface Baseline

The focused mutation benchmark now covers:

- `update!` on struct fields
- `update` on struct fields
- explicit pointer mutation
- `update!` on dynamic arrays
- `update!` on maps

Current focused mutation run:

- `struct-update`: Kvist `0.080 ms`, direct Odin `0.080 ms`
- `pointer-update`: Kvist `0.076 ms`, direct Odin `0.075 ms`
- `array-update!`: Kvist `0.313 ms`, direct Odin `0.314 ms`
- `map-update!`: Kvist `12.174 ms`, direct Odin `8.140 ms`

Two fixes mattered here:

1. `update!` now lowers simple arithmetic updater cases to compound
   assignment when possible:
   - `+=`
   - `-=`
   - `*=`
   - `/=`
   - unary `inc` / `dec`

   That removed duplicate place reads for array and map updates.

2. The array benchmark was tightened so it measures update cost more directly
   instead of conflating it with avoidable growth churn from a zero-capacity
   buffer.

The old local-only struct microbenchmark was useless because Odin optimized it
below timer resolution. The benchmark now uses array-backed struct workloads so
copy-update versus pointer mutation is measurable.

The useful conclusion for now is:

- struct copy-update and pointer mutation are effectively at parity in this
  workload
- array `update!` is also at parity after the lowering fix
- the remaining `map/update!` gap should be treated as suspicious but not yet
  as proven codegen trouble, because the generated hot loop now matches the
  direct Odin shape

## Focused Map Update Benchmark

The stripped-down map-only benchmark removes the broader mutation benchmark's
other costs and answers the remaining question directly.

Current focused map-only run:

- Kvist `map-update!`: `62.642 ms`
- direct Odin: `66.551 ms`

The generated hot loop is now:

```odin
counts[j % KEY_MOD] += 1
```

So the earlier map gap was not a persistent lowering problem. After the
compound-assignment fix, the focused map workload is at parity and slightly
favors the Kvist-generated version in this run.

## Good Next Benchmarks

The new source-backed `kvist:arr` benchmark now covers:

- intrinsic `arr/*` lowering
- imported `kvist:arr` source-backed lowering
- direct Odin baselines
- one fused-loop lower bound for the eager pipeline case

Current run shape:

- `pipe-intrinsic`: `17.609 ms`
- `pipe-source`: `17.910 ms`
- `pipe-direct`: `27.008 ms`
- `pipe-fused`: `3.653 ms`
- `builders-intrinsic`: `9.430 ms`
- `builders-source`: `10.119 ms`
- `builders-direct`: `11.869 ms`
- `scan-intrinsic`: `10.061 ms`
- `scan-source`: `9.926 ms`
- `scan-direct`: `11.891 ms`

The important result is not any one number, but the shape:

- intrinsic and source-backed paths now match allocation counts exactly in the
  migrated `arr` surface
- the source-backed path is within normal run-to-run noise of the intrinsic
  path on these workloads
- both stay close to the direct eager Odin baseline
- the fused loop is still much faster when the semantics avoid intermediate
  owned collections entirely

The next benchmark additions should keep targeting language features we
recently added, not only older sequence helpers.

Recommended next cases:

1. `for` loops over arrays, maps, and sets
2. package-heavy real-world workloads using explicit `kvist:*` imports beyond
   the focused `arr` benchmark
3. ownership-helper patterns using `let ... defer` around collection builders
4. more map-heavy workloads with realistic surrounding code, not just the
   isolated hot loop

These would tell us whether the newer language surface is still lowering as
cleanly as the older helper benchmarks.

## Planned Destructuring Baseline

There is now also a focused baseline for the planned `let` destructuring shape:

```clojure
(let [{:keys [x y z w]} point]
  ...)
```

Run it with:

```sh
./scripts/bench_destructuring_helpers.sh
```

This benchmark is intentionally set up before the syntax lands. It compares the
lowering shapes we are deciding between:

- direct field reads from an already-bound local
- explicit local bindings for each field from that local
- direct field reads when the source is a nontrivial expression that should be
  evaluated once
- explicit local bindings after one temp-backed source evaluation

The important things to watch are:

- `allocs=0` for all four cases
- whether `*-bound` stays at or near parity with `*-direct`
- whether the expression-backed temp shape stays near parity with the simpler
  local-source shape

## Captured Callback Baseline

There is now also a focused captured-callback benchmark for the first closure
pass:

- Kvist `map`, `filter`, `remove`, `keep`, and `map!` with one captured outer local
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
