# Live Development

Kvist supports two complementary live-development loops:

- a resident reload session for long-running native programs
- scratch evaluation for running or inspecting one form in a file's context

Both keep the code ordinary Kvist. The difference is whether you are swapping a
reloadable module inside a resident process or just compiling and running one
selected form.

## Resident Reload Sessions

The resident workflow keeps a host process alive, rebuilds a reloadable module,
and swaps code at explicit safe boundaries. Reload happens only when the program
reaches a checkpoint.

The current contract is:

- the host owns the durable state root
- the reloadable module exports the expected manifest and entrypoints
- the host validates API version and state layout before activating new code
- app code chooses explicit safe swap points with `reload.checkpoint!`

State-layout changes are not migrated automatically. If state size or alignment
changes, reload is rejected and the current process keeps running with the
previous module.

## Source Shapes

There are two common source shapes.

The direct module form uses the shipped hot package:

```clojure
(import hot "kvist:hot")
(hot.defmodule ...)
```

The reload-adapter form keeps production code ordinary and puts the reload
boundary in a small adapter:

```clojure
(package app-reload)

(import app "app")
(import reload "kvist:reload")

(def Reload_State app.App-State)

(defn init [state: ^Reload_State]
  (app.init state))

(defn run [state: ^Reload_State host: ^reload.Run_Host]
  (while true
    (app.tick state)
    (when (reload.checkpoint! host)
      (return))))
```

The common shape is:

- one durable state type
- `init`
- optional `on-load` and `on-unload`
- `run`
- explicit `reload.checkpoint!` calls at safe boundaries

## CLI

Current commands:

```sh
kvist dev --reload reload.kvist
kvist dev --reload reload.kvist --watch
kvist dev --reload reload.kvist --rebuild
kvist dev --reload reload.kvist --print-paths
kvist dev --reload reload.kvist --print-paths --json
kvist dev --reload reload.kvist --rebuild --json
kvist check --reload reload.kvist
kvist build --reload reload.kvist
kvist run --reload reload.kvist
```

`kvist dev --reload ...` starts the resident session. `--watch` rebuilds the
reloadable side when source changes are detected. `--rebuild` performs one
rebuild against an existing resident session.

The editor-facing machine-readable commands are:

- `kvist dev --reload reload.kvist --json`
- `kvist dev --reload reload.kvist --print-paths --json`
- `kvist dev --reload reload.kvist --rebuild --json`

The JSON event stream uses `KVIST_RELOAD_EVENT<TAB>` lines for structured
events while ordinary stdout and stderr continue to flow normally.

## Checkpoints

`reload.checkpoint!` is the explicit cooperation point between app code and the
resident host.

Good checkpoint boundaries:

- once per request cycle
- once per event-loop cycle
- once per frame
- once per outer job or batch iteration

Avoid calling it:

- mid-transaction
- while holding locks
- while external resources are half-updated
- deep inside helper code where returning from `run` would be surprising

Typical shape:

```clojure
(defn run [state: ^App_State host: ^reload.Run_Host]
  (while true
    (handle-one-request state)
    (when (reload.checkpoint! host)
      (return))))
```

## Scratch Evaluation

Scratch evaluation is the faster loop when you want to inspect a value, run one
helper, or study generated output without starting a resident session. It is the
"what does this form do?" button.

The core commands are:

```sh
kvist eval file.kvist '(form)'
kvist expand file.kvist '(form)'
kvist macroexpand file.kvist '(form)'
```

`kvist eval` compiles a scratch program using the surrounding file context and
runs it.

`kvist expand` shows the generated Odin for that scratch form after ordinary
lowering.

`kvist macroexpand` shows frontend macro expansion before Odin lowering.

This is useful for:

- checking a helper against real imports and declarations
- inspecting allocation or ownership behavior in generated Odin
- testing a transformation or pipeline without creating a permanent entrypoint
- debugging macros separately from backend lowering

Example:

```sh
kvist eval examples/collections/higher-order.kvist '(threaded-total)'
kvist expand examples/collections/higher-order.kvist '(threaded-total)'
kvist macroexpand examples/language/data-literals.kvist \
  '(with-allocator [allocator context.temp_allocator] (temp-buffer-len))'
```

## Choosing A Loop

Use a resident reload session when:

- the program owns durable process state
- you need to keep a server, app loop, or tool process alive
- the interesting behavior only appears after initialization

Use scratch evaluation when:

- you want to run one form quickly
- you want generated Odin or macro output
- you are exploring APIs, allocation behavior, or helper semantics

These workflows complement each other. A common pattern is to use scratch eval
to develop helpers and inspect generated code, then run the full resident
reload session when integrating behavior into a long-running app.

## Current Limits

- resident reload preserves host-owned state, not arbitrary incompatible state
  layouts
- low-level ABI compatibility still matters
- the host process remains resident
- scratch eval is for one selected form, not arbitrary mutation of a running
  resident process

## Examples

- [`examples/reload/reload_step_demo`](../examples/reload/reload_step_demo/README.md)
- [`examples/reload/reload_run_demo`](../examples/reload/reload_run_demo/README.md)
- [`examples/reload/hot_reload_demo`](../examples/reload/hot_reload_demo/README.md)
- [`examples/reload/hybrid_live_demo`](../examples/reload/hybrid_live_demo/README.md)
