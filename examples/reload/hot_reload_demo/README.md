# Hot Reload Demo

This demo shows the new primary iterative-development direction for Kvist:

- a normal compiled host process
- a reloadable shared library
- host-owned state surviving module rebuilds and reloads
- a small `kvist_hot.Reloader` session object that owns the reload loop state

`Kvist/Live` is still useful, but this native hot-reload path is the intended
first answer for broad day-to-day compiled-code iteration.

## Files

- [host/main.kvist](./host/main.kvist): the long-running host process
- [module/main.kvist](./module/main.kvist): the reloadable shared library
- [shared/shared.kvist](./shared/shared.kvist): shared state layout used by both
  host and module

These sources are all `.kvist`.

The example files themselves are now pure Kvist source. The module side uses a
small shipped Kvist helper package instead of hand-writing the full export
contract:

- `(import alias :odin "path")` for existing Odin implementation packages
- `(import hot "kvist:hot")`
- `(hot.defmodule ...)`

Under that surface, the generated module still uses `(export)` and `:abi "c"`
for the actual C-ABI entrypoints.

The dynlib-tagged symbol table and rawptr/state-cast glue now live in the
implementation support package under `src/`, not inside the example sources.

The host intentionally uses the reusable `kvist_hot` helpers rather than
open-coding file timestamp checks:

- `new_reloader(...)`
- `load_initial_module(...)`
- `reload_module_if_source_changed(...)`

## Run It

From the repo root:

```sh
mkdir -p build/hot_reload_demo
mkdir -p build/generated/hot_reload_demo/shared build/generated/hot_reload_demo/module build/generated/hot_reload_demo/host
./kvist examples/reload/hot_reload_demo/shared/shared.kvist -o build/generated/hot_reload_demo/shared/shared.odin
./kvist examples/reload/hot_reload_demo/module/main.kvist -o build/generated/hot_reload_demo/module/main.odin
./kvist examples/reload/hot_reload_demo/host/main.kvist -o build/generated/hot_reload_demo/host/main.odin
odin build build/generated/hot_reload_demo/module -build-mode:dll -out:build/hot_reload_demo/hot_demo.dylib
odin run build/generated/hot_reload_demo/host
```

The host prints a tick every second.

## Iterate

While the host is still running:

1. Edit [module/main.kvist](./module/main.kvist).
2. Change the `hot-demo-version` string passed through `hot.defmodule`.
3. Rebuild only the shared library:

```sh
./kvist examples/reload/hot_reload_demo/module/main.kvist -o build/generated/hot_reload_demo/module/main.odin
odin build build/generated/hot_reload_demo/module -build-mode:dll -out:build/hot_reload_demo/hot_demo.dylib
```

The running host notices the file change, reloads the module, and continues
with the same host-owned state.

## What To Look For

- `tick_count` keeps increasing across reloads
- `reload_count` increments when the new module is loaded
- `unload_count` increments when the old module is torn down
- the host process never restarts

This is the important boundary:

- state lives in the host
- code lives in the shared library

## Real-Project Workflow

In Emacs or another editor, the workflow would be:

1. Start the host process once.
2. Keep it running in a terminal.
3. Edit reloadable Kvist module code.
4. Recompile that Kvist file to generated Odin.
5. Rebuild only the shared library.
5. Observe the running process continue with new code and old state.

For a real project, the host shape would usually be:

1. Define a shared state/layout package used by host and reloadable module.
2. Define one symbol table with:
   - the `kvist_hot` manifest exports
   - the app-specific callable exports
3. Start one `kvist_hot.Reloader`.
4. Keep your app loop ordinary.
5. Poll `reload_module_if_source_changed(...)` inside that loop.

## Current Limits

The actual workflow is now `.kvist`-first:

- edit `*.kvist`
- re-run `./kvist ... -o ...`
- rebuild only the reloadable DLL
- keep the host process alive

Some implementation packages under `src/` are still ordinary Odin, especially
where the current system needs field tags or other ABI-facing details. That is
an implementation boundary, not example-surface leakage.

If you change the shared state layout too much, you still need a restart. That
is the main native hot-reload constraint, and it is exactly why `Kvist/Live`
still has a separate role for more reflective/runtime-owned behavior.
