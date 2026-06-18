# Reload Run Demo

This demo uses the Olive-like Kvist reload shape:

- `main.kvist` is the ordinary production app and entrypoint.
- `reload.kvist` is the development reload adapter.

Production stays normal:

```sh
./build/kvist check examples/reload/reload_run_demo/main.kvist
./build/kvist build examples/reload/reload_run_demo/main.kvist
./build/kvist run examples/reload/reload_run_demo/main.kvist
```

Run the live reload adapter and rebuild automatically when `.kvist` files in
this demo change:

```sh
./build/kvist dev --reload examples/reload/reload_run_demo/reload.kvist --watch
```

You can also start reload from the production file; the CLI discovers the
sibling `reload.kvist` adapter:

```sh
./build/kvist dev --reload examples/reload/reload_run_demo/main.kvist --watch
```

Run the resident reload host without the source watcher:

```sh
./build/kvist dev --reload examples/reload/reload_run_demo/reload.kvist
```

Rebuild only the reloadable module after editing source:

```sh
./build/kvist dev --reload examples/reload/reload_run_demo/reload.kvist --rebuild
```

Rebuild with machine-readable status for editor integration:

```sh
./build/kvist dev --reload examples/reload/reload_run_demo/reload.kvist --rebuild --json
```

Print generated paths and canonical commands:

```sh
./build/kvist dev --reload examples/reload/reload_run_demo/reload.kvist --print-paths --json
```

The adapter form points at the production state type:

```clojure
(def Reload_State app.App_State)

(defn init [state: ^Reload_State]
  (app.init state))
```

The production app owns `App_State`; the reload adapter imports `main.kvist` as
`app`, aliases the durable state as `Reload_State`, and provides conventional
lifecycle functions for the resident host.

The reload `run` function takes the durable state plus `^reload.Run_Host`.
When `reload.checkpoint!` returns true, `run` should return so the resident
host can swap the rebuilt module at a safe boundary.
