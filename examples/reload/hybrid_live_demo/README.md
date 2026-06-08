# Hybrid Live Demo

This demo combines the two iterative-development paths Kvist is steering
toward:

- native hot reload for ordinary compiled code
- `Kvist/Live` for commands and runtime inspection

The host process is written in `.kvist`, the reloadable module is written in
`.kvist`, and the embedded live module files are also `.kvist`.

On the native side, the example uses the same pure-Kvist surface as the
standalone hot-reload demo:

- `(import alias :odin "path")` for Odin implementation packages
- `(import hot "kvist:hot")` for the shipped native module-contract macro
- `(hot.defmodule ...)` to emit the standard `kvist_hot` entrypoints

On the live side, the example now uses the matching shipped live package:

- `(import live "kvist:live")`
- `(live/defmodule ...)`
- `live/defcommand` / `live/defhook` for the common zero-arg entrypoint shape

## Files

- [host/main.kvist](./host/main.kvist): long-running host process
- [module/main.kvist](./module/main.kvist): reloadable shared library
- [shared/shared.kvist](./shared/shared.kvist): host-owned state layout
- [live/commands.kvist](./live/commands.kvist): live command module
- [live/helpers.kvist](./live/helpers.kvist): imported live helper code

## Run It

From the repo root:

```sh
mkdir -p build/hybrid_live_demo
mkdir -p build/generated/hybrid_live_demo/shared build/generated/hybrid_live_demo/module build/generated/hybrid_live_demo/host
./kvist examples/reload/hybrid_live_demo/shared/shared.kvist -o build/generated/hybrid_live_demo/shared/shared.odin
./kvist examples/reload/hybrid_live_demo/module/main.kvist -o build/generated/hybrid_live_demo/module/main.odin
./kvist examples/reload/hybrid_live_demo/host/main.kvist -o build/generated/hybrid_live_demo/host/main.odin
odin build build/generated/hybrid_live_demo/module -build-mode:dll -out:build/hybrid_live_demo/hybrid_demo.dylib
odin run build/generated/hybrid_live_demo/host
```

## Two Edit Loops

While the host is still running, you can change either side independently.

### 1. Native hot reload

Edit [module/main.kvist](./module/main.kvist), then rebuild only the DLL:

```sh
./kvist examples/reload/hybrid_live_demo/module/main.kvist -o build/generated/hybrid_live_demo/module/main.odin
odin build build/generated/hybrid_live_demo/module -build-mode:dll -out:build/hybrid_live_demo/hybrid_demo.dylib
```

The host-owned `State` value survives while the native module code swaps.

### 2. Live command reload

Edit either live source file:

- [live/commands.kvist](./live/commands.kvist)
- [live/helpers.kvist](./live/helpers.kvist)

Save the file and keep watching the running host. The live command layer
reloads from source without rebuilding the DLL or restarting the process.

The live side of the host now uses the same reusable helper pattern as the
standalone live demo:

- `new_module_reloader(...)`
- `load_initial_module(...)`
- `reload_module_if_source_changed(...)`

The native side now uses the matching higher-level `kvist_hot` host path too:

- `new_reloader(...)`
- `load_initial_module(...)`
- `reload_module_if_source_changed(...)`

## What To Look For

- `tick_count` keeps increasing in the host across native module rebuilds
- `reload_count` and `unload_count` reflect native DLL swaps
- the live `inspect` command keeps running once per second
- the live module logs host-owned native state through `host.snapshot`
- the live host path is no longer open-coded per demo
- changing the native module and the live module exercises two different
  continuity layers in one process

## Current Limits

The example sources are now pure `.kvist`, but some implementation plumbing
still lives in ordinary Odin packages under `src/`:

- the dynlib-tagged symbol tables
- rawptr/state bridge helpers for the native module boundary
- the `kvist_hot` and `kvist_live` runtime implementations themselves
