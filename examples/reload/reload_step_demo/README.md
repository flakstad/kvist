# Reload Loop Demo

This is a loop-driven `defstate` reload workflow with a more realistic file
split: one small reload-app shell file, one durable root state, and a separate
same-package program file that holds the logic you would keep extending.

The loop is ordinary Kvist code in `run`. If your app wants a step-and-sleep
loop, write that loop directly and call `reload.checkpoint!` at the safe
boundary.

Source:

- `main.kvist`
- `app.kvist`

Run the reloadable app and rebuild automatically when `.kvist` files in this
package directory change:

```sh
./build/kvist dev --reload examples/reload/reload_step_demo/main.kvist --watch
```

Run the reloadable app without the source watcher:

```sh
./build/kvist dev --reload examples/reload/reload_step_demo/main.kvist
```

Rebuild only the reloadable module after editing the app source:

```sh
./build/kvist dev --reload examples/reload/reload_step_demo/main.kvist --rebuild
```

Run the same source without the resident reload shell:

```sh
./build/kvist run --reload examples/reload/reload_step_demo/main.kvist
```

The same source also works directly with plain app commands now:

```sh
./build/kvist check examples/reload/reload_step_demo/main.kvist
./build/kvist build examples/reload/reload_step_demo/main.kvist
./build/kvist run examples/reload/reload_step_demo/main.kvist
```

Check or build that production-style wrapper:

```sh
./build/kvist check --reload examples/reload/reload_step_demo/main.kvist
./build/kvist build --reload examples/reload/reload_step_demo/main.kvist
```

Print the generated paths and rebuild commands for editor/tool integration:

```sh
./build/kvist dev --reload examples/reload/reload_step_demo/main.kvist --print-paths
```

Print the same information as JSON for Emacs or other external tooling:

```sh
./build/kvist dev --reload examples/reload/reload_step_demo/main.kvist --print-paths --json
```

That output includes `watch_command`, `run_command`, and `rebuild_command`.

Rebuild with machine-readable status:

```sh
./build/kvist dev --reload examples/reload/reload_step_demo/main.kvist --rebuild --json
```

Start the resident shell with structured status events for editor integration:

```sh
./build/kvist dev --reload examples/reload/reload_step_demo/main.kvist --json
```

That stream includes lines prefixed with `KVIST_RELOAD_EVENT<TAB>` carrying
JSON payloads for `started`, `reloaded`, and reload failure events.

Current shape of the source contract:

- one top-level `(defstate Name {fields...} {metadata...})`
- fields map first, reload-lifetime/config map second
- required metadata: `run:`
- optional metadata: `init:`, `on-load:`, `on-unload:`, `version:`

When to use this shape:

- when a repeated step-and-sleep loop is already the right shape
- when the program is naturally loop-driven
- when the reload boundary is one frame, tick, poll, or small batch

Typical fits:

- games
- simulations
- polling tools
- small interactive demos

In this demo:

- `main.kvist` is the reload-app shell
- `app.kvist` is the "real program" file in the same package
- the durable root keeps the reload counters plus one `Program_State`
  subsystem
- `step` is an ordinary helper called by `run`
- `run` owns the outer loop, sleeps between steps, and calls
  `reload.checkpoint!` before returning to the resident host

So the intended extension point is to keep growing `app.kvist` while
leaving the reload shell small and boring.

The user source stays pure Kvist. The generated host/module wrappers and the
reload runtime remain Odin implementation details.
