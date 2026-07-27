# Benchmarks

The benchmark scripts compare generated Kvist programs with direct Odin
implementations of the same work.

```sh
./scripts/bench_sequence_helpers.sh
./scripts/bench_aggregate_helpers.sh
./scripts/bench_mutation_helpers.sh
./scripts/bench_closure_helpers.sh
./scripts/bench_source_backed_arr.sh
./scripts/bench_core_helpers.sh
./scripts/bench_package_helpers.sh
./scripts/bench_data_collections.sh
```

The sequence and source-backed array scripts accept `BASE_REF` to compare the
current checkout with another Git revision:

```sh
BASE_REF=main ./scripts/bench_sequence_helpers.sh
```

These are regression tools, not general performance claims. Compare equivalent
workloads and inspect generated Odin when a result changes unexpectedly.
