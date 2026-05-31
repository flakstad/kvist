# Reload Step Demo

This is the convenience `:step` reload workflow with a more realistic file
split: one small reload-app shell file, one durable root state, and a separate
same-package program file that holds the logic you would keep extending.

Source:

- `main.kvist`
- `app.kvist`

Run the reloadable app:

```sh
./build/kvist dev --reload examples/reload_step_demo/main.kvist
```

Rebuild only the reloadable module after editing the app source:

```sh
./build/kvist dev --reload examples/reload_step_demo/main.kvist --rebuild
```

Run the same source without the resident reload shell:

```sh
./build/kvist run --reload examples/reload_step_demo/main.kvist
```

The same source also works directly with plain app commands now:

```sh
./build/kvist check examples/reload_step_demo/main.kvist
./build/kvist build examples/reload_step_demo/main.kvist
./build/kvist run examples/reload_step_demo/main.kvist
```

Check or build that production-style wrapper:

```sh
./build/kvist check --reload examples/reload_step_demo/main.kvist
./build/kvist build --reload examples/reload_step_demo/main.kvist
```

Print the generated paths and rebuild commands for editor/tool integration:

```sh
./build/kvist dev --reload examples/reload_step_demo/main.kvist --print-paths
```

Print the same information as JSON for Emacs or other external tooling:

```sh
./build/kvist dev --reload examples/reload_step_demo/main.kvist --print-paths --json
```

Rebuild with machine-readable status:

```sh
./build/kvist dev --reload examples/reload_step_demo/main.kvist --rebuild --json
```

Start the resident shell with structured status events for editor integration:

```sh
./build/kvist dev --reload examples/reload_step_demo/main.kvist --json
```

That stream includes lines prefixed with `KVIST_RELOAD_EVENT<TAB>` carrying
JSON payloads for `started`, `reloaded`, and reload failure events.

Current shape of the source contract:

- one top-level `(defstate Name {fields...} {metadata...})`
- fields map first, reload-lifetime/config map second
- convenience host mode: `:step`
- general companion host mode: `:run`
- optional metadata: `:init`, `:on-load`, `:on-unload`, `:version`, `:sleep-ms`

When to use `:step`:

- when a repeated step-and-sleep loop is already the right shape
- when you want Kvist to own the outer loop
- when the program is naturally loop-driven and does not need an app-owned
  runtime boundary

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
- `step` only wires the shell state into the app file

So the intended extension point is to keep growing `app.kvist` while
leaving the reload shell small and boring.

See `../reload_run_demo/` for the app-owned runtime shape that uses `:run` plus
one explicit `reload/checkpoint!` call at the runtime boundary.

The user source stays pure Kvist. The generated host/module wrappers and the
reload runtime remain Odin implementation details.
