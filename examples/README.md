# Kvist Examples

Examples are grouped by what they demonstrate. Start with the small ones, then
move into the larger demos once the core syntax feels familiar. Coverage
fixtures live under `coverage/` so the tutorial path stays readable.

## Start Here

- [`language/hello.kvist`](./language/hello.kvist) - smallest program
- [`language/data-literals.kvist`](./language/data-literals.kvist) - typed arrays, maps, structs, allocators
- [`language/keywords.kvist`](./language/keywords.kvist) - first-class `keyword` values in structs, `case`, maps, and sets
- [`language/threading-forms.kvist`](./language/threading-forms.kvist) - `cond->`, `as->`, and value-oriented threading
- [`language/control-flow.kvist`](./language/control-flow.kvist) - `if`, `when`, `while`, `for`, `case`
- [`language/errdefer.kvist`](./language/errdefer.kvist) - failure-only cleanup for owned return values
- [`language/function-values.kvist`](./language/function-values.kvist) - `fn` and function types
- [`language/closures.kvist`](./language/closures.kvist) - captured callback boundaries
- [`language/polymorphism.kvist`](./language/polymorphism.kvist) - `$T`, `where`, generic formatting, and overload declarations
- [`language/macro-authoring.kvist`](./language/macro-authoring.kvist) - practical macro writing
- [`collections/sequences.kvist`](./collections/sequences.kvist) - collection helpers over structs with `:as` imports
- [`collections/package-tour.kvist`](./collections/package-tour.kvist) - `arr`/`map`/`set`/`str` ownership basics
- [`collections/unaliased-arr-import.kvist`](./collections/unaliased-arr-import.kvist) - explicit `:refer` import with bare array helpers
- [`collections/data-transforms.kvist`](./collections/data-transforms.kvist) - fused transforms with `into`, `transduce`, and `for`
- [`collections/transforms.kvist`](./collections/transforms.kvist) - broader transform feature coverage
- [`collections/log-source.kvist`](./collections/log-source.kvist) - `defiter` with `for`, `into`, `transduce`, and cleanup
- [`collections/orders-report.kvist`](./collections/orders-report.kvist) - realistic collection pipeline
- [`web/html-demo.kvist`](./web/html-demo.kvist) - HTML DSL
- [`web/http-server.kvist`](./web/http-server.kvist) - HTTP server
- [`visual/matrix-kinematics.kvist`](./visual/matrix-kinematics.kvist) - small raylib/linalg demo

## Layout

- `language/` - core syntax and declarations
- `collections/` - arrays, maps, ownership, transforms, pipelines
- `packages/` - package demos, tests, and measurements
- `coverage/` - compiler/package fixtures used by tests and scripts
- `interop/` - direct Odin package/vendor interop
- `web/` - HTML, HTTP, SSE, Datastar
- `visual/` - raylib demos and simulations
- `reload/` - live and native hot-reload experiments
- `support/` - source packages imported by examples

## Run

Compile/check one example:

```sh
./kvist check examples/language/hello.kvist
```

Run one example:

```sh
./kvist run examples/language/hello.kvist
```

Evaluate one form:

```sh
./kvist eval examples/collections/sequences.kvist '(age-for-ada)'
```

Check the ordinary example sweep:

```sh
./scripts/check_examples.sh
```

That script also checks `coverage/`.

## Package Examples

Package examples are the practical companion to the docs:

- [`packages/testing.kvist`](./packages/testing.kvist) - `kvist:test`
- [`packages/parallel.kvist`](./packages/parallel.kvist) - `kvist:parallel`
- [`packages/soa.kvist`](./packages/soa.kvist) - `kvist:soa`

For the package map, see [`../docs/PACKAGES.md`](../docs/PACKAGES.md).

## Visual Examples

Visual examples need the same native dependencies as the generated Odin code.
For a quick raylib check:

```sh
./kvist examples/visual/matrix-kinematics.kvist -o /tmp/matrix-kinematics.odin
odin run /tmp/matrix-kinematics.odin -file
```

Larger visual demos such as `particle-sim`, `stable-fluids`, and `robo-mower`
are useful stress tests, not first-reading material.

## Reload Examples

Reload examples have their own local notes:

- [`reload/live_reload_demo/README.md`](./reload/live_reload_demo/README.md)
- [`reload/live_commands_demo/README.md`](./reload/live_commands_demo/README.md)
- [`reload/reload_step_demo/README.md`](./reload/reload_step_demo/README.md)
- [`reload/reload_run_demo/README.md`](./reload/reload_run_demo/README.md)
- [`reload/hot_reload_demo/README.md`](./reload/hot_reload_demo/README.md)
- [`reload/hybrid_live_demo/README.md`](./reload/hybrid_live_demo/README.md)
