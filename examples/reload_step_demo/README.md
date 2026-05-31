# Reload Step Demo

This is the first-pass `defstate` reload workflow: one pure `.kvist` app
source, one durable root state, and a CLI-generated resident shell plus
reloadable module underneath.

Source:

- `main.kvist`

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

Check or build that production-style wrapper:

```sh
./build/kvist check --reload examples/reload_step_demo/main.kvist
./build/kvist build --reload examples/reload_step_demo/main.kvist
```

Print the generated paths and rebuild commands for editor/tool integration:

```sh
./build/kvist dev --reload examples/reload_step_demo/main.kvist --print-paths
```

Current shape of the source contract:

- one top-level `(defstate Name {fields...} {metadata...})`
- fields map first, reload-lifetime/config map second
- currently implemented host mode: `:step`
- companion implemented host mode: `:run`
- optional metadata: `:init`, `:on-load`, `:on-unload`, `:version`, `:sleep-ms`

See `../reload_run_demo/` for the app-owned runtime shape that uses `:run` plus
one explicit `reload/checkpoint!` call at the runtime boundary.

The user source stays pure Kvist. The generated host/module wrappers and the
reload runtime remain Odin implementation details.
