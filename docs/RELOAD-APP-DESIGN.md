# Reload App Surface

Kvist reload apps use an Olive-style split:

- production source stays ordinary Kvist
- a reload adapter declares the durable state and reload cooperation point
- the CLI generates the resident host package and reloadable module package
- the vendored Olive runtime performs the native module swap

## Source Shape

Production owns the real app state:

```clojure
(package app)

(defstruct App-State {ticks: int})

(defn init [state: ^App-State]
  (set! state^.ticks 0))

(defn tick [state: ^App-State]
  (set! state^.ticks (+ state^.ticks 1)))
```

The reload adapter declares the reload contract:

```clojure
(package app-reload)

(import app "app")
(import reload "kvist:reload")

(def Reload_State app.App-State)

(defn init [state: ^Reload_State]
  (app.init state))

(defn run [state: ^Reload_State host: ^reload.Run-Host]
  (while true
    (app.tick state)
    (when (reload.checkpoint! host)
      (return))))
```

## Modes

`run` is the general mode. The app owns its loop and calls
`reload.checkpoint!` at a safe boundary. The durable state boundary is the
ordinary top-level `(def Reload_State <State-Type>)` alias; lifecycle hooks use
conventional names such as `init`, `on-load`, and `on-unload`.

## CLI

Current reload commands:

```sh
kvist dev --reload reload.kvist
kvist dev --reload reload.kvist --watch
kvist dev --reload reload.kvist --rebuild
kvist dev --reload reload.kvist --print-paths
kvist check --reload reload.kvist
kvist build --reload reload.kvist
kvist run --reload reload.kvist
```

The command generates:

1. a compiled app package from the user's `.kvist` source
2. a generated resident host package
3. a generated reloadable module package
4. the reloadable shared library
5. the running host process, unless `--rebuild` is used

## Runtime Model

The runtime model is one explicit callback boundary:

- the resident host owns one durable state value
- the reloadable module owns current code
- `run` owns the app loop in `run:` mode
- `reload.checkpoint!` marks safe boundaries
- when `checkpoint!` returns true, `run` returns to the host
- the host validates the state layout and swaps the module

State layout changes require restart. Behavior changes are the smooth reload
path.

## Backend

Kvist vendors Olive's reload runtime under `src/olive_reload` and should track
that runtime as upstream Olive code rather than a Kvist fork. The Kvist CLI owns
`.kvist` compilation, source import rebasing, generated paths, JSON command
discovery, `.kvist` watching, and the public `kvist:reload` package shape.

Generated reload modules export Olive-compatible symbols such as
`olive_reload_api_version`, `olive_reload_state_size`, and
`olive_reload_app_run`.

The public `kvist:reload` package re-exports the user-facing runtime types and
helpers:

```clojure
(import reload "kvist:reload")
(reload.checkpoint! host)
```

## Limits

Reload mode does not:

- hide ownership semantics
- remove the resident host process
- support arbitrary incompatible state-layout changes
- replace `Kvist/Live`

Use reload mode for broad compiled-code iteration. Use `Kvist/Live` for
reflective commands, runtime-programmable behavior, and host-driven live
modules.
