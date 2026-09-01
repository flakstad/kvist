# Benchmarks

The benchmark scripts compare equivalent Kvist and Odin workloads. Treat their
timings as local diagnostics rather than general performance claims: use the
same machine and build configuration when comparing revisions.

## REPL Workflow

The maintained workflow checks that the normal REPL produces the same visible
results as forced native execution, then reports per-submission and whole-session
times:

```sh
./scripts/repl_workflow_report.sh \
  benchmarks/repl_native_packages.kvist \
  benchmarks/repl_workflow.jsonl
```

Use an existing optimized compiler with:

```sh
KVIST_WORKFLOW_COMPILER=/absolute/path/to/kvist \
  ./scripts/repl_workflow_report.sh \
    benchmarks/repl_native_packages.kvist \
    benchmarks/repl_workflow.jsonl
```

The first line should report `semantic parity: ok`. The remaining rows show
which requests were fast, which used the ordinary compiler path, and how the
complete session compared with native execution.

The reporter's additional execution modes isolate individual acceleration
mechanisms for development measurements. Override them with
`KVIST_WORKFLOW_MODES`, or use `KVIST_WORKFLOW_MODES='auto native'` for the
ordinary product comparison. It disables persistent compile artifacts by
default so one mode does not warm another; set
`KVIST_WORKFLOW_NO_COMPILE_CACHE=0` when deliberately measuring warm starts.

To use another project, pass its development context and a JSONL transcript.
The requests argument may be `-` to read the transcript from standard input.

The older phase and generated-source-size report remains available:

```sh
./scripts/bench_repl_source_packages.sh
```

Set `KVIST_BENCH_COMPILER` to use an existing compiler and
`KVIST_BENCH_CONTEXT` to use another project context.

## Compiler and Runtime Workloads

```sh
./scripts/bench_sequence_helpers.sh
./scripts/bench_aggregate_helpers.sh
./scripts/bench_mutation_helpers.sh
./scripts/bench_closure_helpers.sh
./scripts/bench_source_backed_arr.sh
./scripts/bench_core_helpers.sh
./scripts/bench_package_helpers.sh
./scripts/bench_data_collections.sh
./scripts/bench_data_messages.sh
```

The sequence and source-backed array scripts accept `BASE_REF` to compare the
current checkout with another Git revision:

```sh
BASE_REF=main ./scripts/bench_sequence_helpers.sh
```

Compare equivalent workloads and inspect generated Odin whenever a result
changes unexpectedly.
