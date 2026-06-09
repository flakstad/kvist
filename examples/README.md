# Kvist Examples

The examples are grouped by intent so the folder names answer what kind of
thing you are looking at. Most files are meant to be read and evaled form by
form from Emacs; many keep `main` small and put useful calls in a
`(comment ...)` block.

## Layout

- [`language/`](./language): core Kvist syntax, declarations, data literals,
  macros, structs, pointers, unions, control flow, and Cluck port examples.
- [`collections/`](./collections): sequence helpers, eager mutation, ownership
  patterns, `tap>`, and realistic collection pipelines.
- [`packages/`](./packages): executable coverage and examples for shipped
  packages such as `arr`, `builtin`, `cli`, `html`, `http`, `soa`, and
  `test`.
- [`interop/core/`](./interop/core): direct Odin core package interop:
  `core:time`, `core:slice`, `core:path`, `core:os`, `core:thread`,
  `core:encoding`, `core:math/linalg`, matrices, SIMD, and bit sets.
- [`interop/vendor/`](./interop/vendor): direct vendor package interop,
  currently raylib and stb/easy_font.
- [`interop/`](./interop): general interop directives and raw Odin escape
  hatches.
- [`web/`](./web): HTML rendering, interpolation, HTTP server/client/session,
  SSE, Datastar, and the stress-test server.
- [`visual/`](./visual): raylib demos and simulations: particles, flocking,
  cloth constraints, fluids, reaction diffusion, spatial hashing, waves, and
  matrix kinematics.
- [`reload/`](./reload): live runtime, source reload, native hot reload, and
  hybrid reload demos.
- [`support/`](./support): source packages imported by other examples.

## Good Starting Points

- [`language/hello.kvist`](./language/hello.kvist): package, import, struct
  literal, and tiny `main`.
- [`language/data-literals.kvist`](./language/data-literals.kvist): arrays,
  maps, type-call literals, allocator helpers, and literal expansion.
- [`language/cluck-port-packages.kvist`](./language/cluck-port-packages.kvist):
  relative `.kvist` source imports.
- [`language/multi-return-bindings.kvist`](./language/multi-return-bindings.kvist):
  positional binding for Odin-style multi-return values.
- [`collections/sequence-helpers.kvist`](./collections/sequence-helpers.kvist):
  broad sequence helper coverage.
- [`collections/functional-pipelines.kvist`](./collections/functional-pipelines.kvist):
  eager threaded pipelines, bang-buffer helpers, and direct loop fallback.
- [`collections/value-updates.kvist`](./collections/value-updates.kvist):
  shallow non-mutating struct updates with `assoc` and `update`.
- [`collections/transforms.kvist`](./collections/transforms.kvist):
  reusable fused `deftransform` pipelines with `into` and `transduce`.
- [`collections/orders-report.kvist`](./collections/orders-report.kvist):
  a more realistic eager data pipeline.
- [`packages/soa.kvist`](./packages/soa.kvist): struct-of-arrays helper usage.
- [`interop/core/matrix.kvist`](./interop/core/matrix.kvist): direct Odin
  matrix/vector constructors with `core:math/linalg`.
- [`interop/core/odin-types.kvist`](./interop/core/odin-types.kvist): Odin
  `bit_set` and `#simd` type constructors.
- [`web/http-server.kvist`](./web/http-server.kvist): stateful router/server
  lifecycle with the shipped `kvist:http` package.
- [`visual/matrix-kinematics.kvist`](./visual/matrix-kinematics.kvist): visual
  matrix/linalg demo.
- [`visual/particle-sim.kvist`](./visual/particle-sim.kvist): particle
  simulation with HUD stats and external CPU/RSS sampling.
- [`visual/robo-mower/`](./visual/robo-mower): top-down robotics sandbox with
  sensors, coverage, obstacle editing, and frontier-seeking control.
- [`visual/stable-fluids.kvist`](./visual/stable-fluids.kvist): stable
  smoke/fluid solver with mutable grid buffers.

## Visual Demos

Run a visual example from the repo root:

```sh
./kvist examples/visual/matrix-kinematics.kvist -o /tmp/matrix-kinematics.odin
odin run /tmp/matrix-kinematics.odin -file
```

Particle simulation with external process stats:

```sh
./kvist examples/visual/particle-sim.kvist -o /tmp/kvist-particle-sim.odin
odin build /tmp/kvist-particle-sim.odin -file -out:build/particle-sim
scripts/particle_stats.sh -- build/particle-sim
```

The in-window HUD reports FPS plus simulation update and draw time. The helper
script reports process CPU percentage and RSS/VSZ memory from outside the app.
See [`visual/particle-sim-results.md`](./visual/particle-sim-results.md) for
the measured Kvist/Odin vs Clojure results.

## Reload Demos

Run the source/live reload demos from the repo root:

```sh
./kvist run examples/reload/live_reload_demo/main.kvist
./kvist run examples/reload/live_commands_demo/main.kvist
./kvist dev --reload examples/reload/reload_step_demo/main.kvist
./kvist run --reload examples/reload/reload_run_demo/main.kvist
```

The native hot-reload demos have a compile/build workflow:

```sh
./kvist examples/reload/hot_reload_demo/shared/shared.kvist -o build/generated/hot_reload_demo/shared/shared.odin
./kvist examples/reload/hot_reload_demo/module/main.kvist -o build/generated/hot_reload_demo/module/main.odin
./kvist examples/reload/hot_reload_demo/host/main.kvist -o build/generated/hot_reload_demo/host/main.odin
odin build build/generated/hot_reload_demo/module -build-mode:dll -out:build/hot_reload_demo/hot_demo.dylib
odin run build/generated/hot_reload_demo/host
```

```sh
./kvist examples/reload/hybrid_live_demo/shared/shared.kvist -o build/generated/hybrid_live_demo/shared/shared.odin
./kvist examples/reload/hybrid_live_demo/module/main.kvist -o build/generated/hybrid_live_demo/module/main.odin
./kvist examples/reload/hybrid_live_demo/host/main.kvist -o build/generated/hybrid_live_demo/host/main.odin
odin build build/generated/hybrid_live_demo/module -build-mode:dll -out:build/hybrid_live_demo/hybrid_demo.dylib
odin run build/generated/hybrid_live_demo/host
```

See the demo-local guides for details:

- [`reload/live_reload_demo/README.md`](./reload/live_reload_demo/README.md)
- [`reload/live_commands_demo/README.md`](./reload/live_commands_demo/README.md)
- [`reload/reload_step_demo/README.md`](./reload/reload_step_demo/README.md)
- [`reload/reload_run_demo/README.md`](./reload/reload_run_demo/README.md)
- [`reload/hot_reload_demo/README.md`](./reload/hot_reload_demo/README.md)
- [`reload/hybrid_live_demo/README.md`](./reload/hybrid_live_demo/README.md)

## Useful Tooling Commands

```sh
kvist check examples/interop/core/core-time-slice.kvist
kvist eval examples/interop/core/core-time-slice.kvist '(duration-ms)'
kvist macroexpand examples/interop/core/error-handling.kvist '(if-ok [data err (os.read_entire_file "tmp/x" context.allocator)] (len data) 0)'
kvist expand examples/collections/sequences.kvist '(age-for-ada)'
```

To compile/check the ordinary example categories:

```sh
scripts/check_examples.sh
```
