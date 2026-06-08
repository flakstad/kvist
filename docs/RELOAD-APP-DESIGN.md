# Reload App Design

Kvist reload apps now follow the Olive-style split:

- production source stays ordinary Kvist
- a reload adapter is used for development
- the adapter points at the durable production state type
- the generated host/module code uses the vendored Olive reload runtime

## Source Shape

Production owns the real app state:

```clojure
;; main.kvist
(package app)

(defstruct App_State
  {:ticks int})

(defn init [state: (ptr App_State)]
  (set! (:ticks state^) 0))

(defn tick [state: (ptr App_State)]
  (set! (:ticks state^) (+ (:ticks state^) 1)))

(defn main []
  (let [state (App_State {})]
    (init &state)
    (while true
      (tick &state))))
```

The reload adapter declares the reload contract:

```clojure
;; reload.kvist
(package app_reload)

(import app "app")
(import reload "kvist:reload")

(defstate app/App_State
  {:run run
   :init app/init})

(defn run [state: (ptr app/App_State) host: (ptr reload/Run_Host)]
  (while true
    (app/tick state)
    (core/when (reload/checkpoint! host)
      (return))))
```

## Recommended Host Mode Choice

The intended default mental model is:

- prefer `:run` for general applications
- use `:step` when you explicitly want Kvist to provide the outer loop

The relationship is:

- `:run` is the general mode
- `:step` is the convenience mode

So users should not think of them as two unrelated systems. They share the
same `defstate` contract and reload shell; the only real difference is who
owns the outer runtime loop.

### Use `:run` when

- your app already has a request loop, event loop, frame loop, or worker loop
- your runtime shape belongs to the program, not to Kvist
- you want one explicit safe boundary for reload cooperation

Examples:

- servers
- GUI applications
- editors
- workers
- larger tools

### Use `:step` when

- a repeated step-and-sleep loop is already the right shape
- you want the smallest possible reload shell surface
- you want Kvist to own the outer loop entirely

Examples:

- games
- simulations
- polling tools
- small interactive demos

That keeps the source surface broad enough for servers, GUI apps, workers, and
other app-owned runtimes while still offering a smaller convenience mode for
loop-driven programs.

For example:

```clojure
(defstruct World_State
  {:player Player_State
   :camera Camera_State
   :ui UI_State})

(defstate App_State
  {:world World_State
   :audio Audio_State
   :assets Asset_Cache
   :editor Editor_State}
  {:step step
   :init init
   :on-load on-load
   :on-unload on-unload
   :version "v1"
   :sleep-ms 1000})

(defn init [state: (ptr App_State)]
  ...)

(defn step [state: (ptr App_State)]
  ...)

(defn draw [state: (ptr App_State)]
  ...)

```

That should be enough to say:

- `App_State` is the durable reload root
- the reload shell should keep an instance of it alive
- reloadable behavior is compiled around that root

## `:run` Safe-Boundary Guidance

For `:run`, the most important user obligation is where to place
`reload/checkpoint!`.

The rule is:

- call it at one or a small number of explicit safe boundaries
- when it returns `true`, return from `run`

The checkpoint should sit at the runtime boundary, not in ordinary application
logic.

Good boundaries:

- one request completed
- one event-loop cycle completed
- one frame completed
- one job completed
- one outer loop iteration completed

Bad boundaries:

- halfway through mutating shared state
- inside leaf functions
- while a transaction or lock must remain uninterrupted
- inside arbitrary utility code just because it is convenient

So the user guidance is not "call checkpoint every N milliseconds". It is:

- call it where stopping is correct
- call it often enough that reload latency feels reasonable

For example:

```clojure
(defn run [state: (ptr App_State) host: (ptr reload/Run_Host)]
  (while true
    (process-one-job state)
    (core/when (reload/checkpoint! host)
      (return))))
```

The metadata-only `defstate` form is reload adapter metadata. It does not emit
a new struct. It tells the generator which existing state type should be
preserved and which lifecycle procs should be called.

The older inline form still works for tiny demos:

```clojure
(defstate App_State
  {:ticks int}
  {:run run})
```

But larger projects should prefer the adapter split so production is not locked
into the reload harness.

## Commands

Production commands point at the ordinary entrypoint:

```sh
kvist check main.kvist
kvist build main.kvist
kvist run main.kvist
```

Reload commands point at the adapter:

```sh
kvist dev --reload reload.kvist --watch
kvist dev --reload reload.kvist
kvist dev --reload reload.kvist --rebuild
kvist dev --reload reload.kvist --print-paths --json
```

`--watch` starts the resident host and polls the adapter directory recursively
for `.kvist` changes. On change, Kvist recompiles the adapter package to Odin,
rebuilds the reloadable dynamic library, and the running app picks it up at the
next `reload/checkpoint!` boundary.

## Runtime Model

The runtime model is one callback:

- the resident host owns one durable state value
- the reloadable module owns current code
- `run` owns the app loop
- `reload/checkpoint!` marks safe boundaries
- when `checkpoint!` returns true, `run` returns to the host
- the host validates state layout and swaps the module

State layout changes still require restart for now. Behavior changes are the
smooth path.

## Backend

Kvist vendors Olive's reload runtime under `src/olive_reload`. The Kvist CLI
still owns `.kvist` compilation, source import rebasing, generated paths, JSON
command discovery, and `.kvist` watching.

Generated reload modules export Olive-compatible symbols such as
`olive_reload_api_version`, `olive_reload_state_size`, and
`olive_reload_app_run`. The public Kvist package `kvist:reload` re-exports
`olive_reload.Run_Host` and `olive_reload.checkpoint` so user source keeps the
Kvist-facing syntax:

```clojure
(import reload "kvist:reload")
(reload/checkpoint! host)
```

or:

```clojure
(hot/poll-reload! host)
```

The rule should be:

- this is called only at safe boundaries already present in the runtime shape
- not from arbitrary business logic
- not sprinkled across unrelated code paths

For example, in a server-style loop:

```clojure
(defn run [state: (ptr Server_State) host: (ptr reload/Run_Host)]
  (while true
    (accept-or-process-one-thing state)
    (reload/checkpoint! host)))
```

For a framework-owned event loop, the checkpoint may sit in one adapter
callback:

```clojure
(defn run [state: (ptr App_State) host: (ptr reload/Run_Host)]
  (framework/start
    {:on-cycle (fn []
                 (reload/checkpoint! host))}))
```

Those are not final syntax promises. They show the intended architectural
shape:

- one runtime boundary
- one explicit checkpoint
- zero ambient magic inside ordinary application logic

### What `reload/checkpoint!` Would Mean

The checkpoint operation should mean:

1. ask the resident shell whether rebuilt code is available
2. if not, return immediately
3. if yes, sequence `on-unload` on the old module
4. swap the module
5. validate the manifest/state layout
6. sequence `on-load` on the new module
7. return a small status to the caller if useful

The simplest first version may return nothing and simply perform the swap.
Later it may be useful to expose:

- whether a reload occurred
- whether reload failed
- whether the runtime should stop or restart part of its loop

### Why A Host Handle Is Better

Passing a host handle into `run` is better than expecting ambient global
helpers because it makes the cooperation point explicit:

- you can see where hot reload enters the app-owned runtime
- the generated shell can evolve the handle without exposing the full runtime
- adapters can be written against one concrete value
- testing and tooling can reason about that value directly

This also avoids turning hot reload into invisible language magic.

### What `:run` Should Not Do

`:`run` should not mean:

- "call hidden reload machinery from anywhere"
- "poll from every request handler"
- "add low-level reload concerns to ordinary domain code"
- "force a dedicated server-specific top-level mode"

That is why a third `:serve` mode should probably wait. If `:run` plus one
explicit host-handle checkpoint is designed well, it should already cover:

- web servers
- daemons
- workers
- GUI/event-loop applications
- other framework-owned runtimes

## Why Two Modes

`:`step` and `:run` is probably enough for the initial host-mode story.

That split gives:

- `:step` for shell-owned loops
- `:run` for app-owned loops

This should cover most programs without adding a third mode like `:serve`
prematurely. A web server, for example, should usually fit inside `:run`
rather than needing a dedicated top-level reload-app mode.

## Current Recommendation

The current product story should be:

- keep `:step` as the right default for loop-driven apps
- keep `:run` as the companion mode for app-owned runtimes
- keep the `:run` cooperation surface small: one host handle and one explicit
  checkpoint API
- do not add a separate `:serve` mode unless `:run` proves insufficient

That keeps the model small while covering both loop-driven and framework-owned
program shapes.

## CLI Direction

The workflow has now started moving toward a direct development command.

For example:

```sh
kvist dev --reload app/main.kvist
```

The current first pass already exists:

- top-level `(defstate Name {fields...} {metadata...})`
- `kvist dev --reload app/main.kvist`
- `kvist dev --reload app/main.kvist --rebuild`
- `kvist dev --reload app/main.kvist --print-paths`
- `kvist check --reload app/main.kvist`
- `kvist build --reload app/main.kvist`
- `kvist run --reload app/main.kvist`

The current command generates:

1. a compiled app package from the user's `.kvist` source
2. a generated resident host package
3. a generated reloadable module package
4. the reloadable shared library
5. the running host process, unless `--rebuild` is used

The remaining work is to make this path broader, cleaner, and better
integrated with tooling.

The full intended command should eventually:

1. compile the user's Kvist source
2. generate the resident shell package
3. generate the reloadable module package
4. build the shell and shared library
5. run the shell
6. provide a rebuild path for the reloadable side

The point is that the user launches "reload development mode", not "my manually
split host and module projects."

## Generation Strategy

Under the hood, the reload-app surface can still lower to the existing native
pattern:

- generated resident shell
- generated shared state contract
- generated reloadable module entrypoints
- existing `kvist_hot` runtime helpers

That means this design is additive. It does not require replacing the current
runtime mechanism first.

## Compatibility Story

The generated reload shell still needs an explicit compatibility story.

The durable root state type means:

- layout changes may require restart
- some changes may later support migration
- ownership-sensitive resources still need discipline

So the product message should stay honest:

- hot reload is the default dev path for compatible behavior changes
- restarts still happen for some low-level structural changes

## Initial Surface Candidates

There are several plausible syntax directions.

### Option A: source-level state declaration

```clojure
(defstate App_State
  {:world World_State}
  {:step step})
```

Pros:

- durable boundary is explicit
- no second wrapper form
- matches the real design primitive

### Option B: main-wrapping declaration

```clojure
(defstate App_State
  {:world World_State})

(defn main []
  ...)
```

Pros:

- no extra form beyond ordinary declarations

Cons:

- says nothing extra about hot mode beyond the CLI

### Option C: CLI-only first step

```sh
kvist dev --reload app/main.kvist --state App_State
```

Pros:

- smallest compiler-surface change first

Cons:

- pushes too much structure into flags
- weaker source-level clarity

Current recommendation:

- prefer a source-level durable-state declaration via `defstate`
- keep the hot contract in the trailing metadata map on that form
- keep reload enablement in `kvist dev --reload ...`
- support `:step` and `:run` as the initial host-mode pair
- optionally support CLI conveniences later

## Recommended First Implementation Slice

The smallest meaningful reload slice would be:

1. require one explicit durable root state type
2. require explicit `defstate` metadata naming `:step` and optional reload hooks
3. add a `kvist dev --reload ...` command that generates shell/module output
4. lower that to the existing `kvist_hot` machinery

That would move the product from:

- "honest host/module mechanism"

to:

- "ordinary Kvist app with `defstate` and reload CLI opt-in"

without pretending the native boundary has disappeared.

The next slices after that should be:

1. harden the implemented `:run` contract around one explicit reload
   cooperation point at the runtime boundary
2. broaden validation and docs/tooling around which mode to use when
3. keep shrinking one-off implementation seams where reload mode still depends
   on CLI-owned wrapper behavior rather than ordinary compiler surfaces

## Non-Goals

This design should not try to:

- hide ownership semantics
- pretend there is no stable shell
- promise reload across arbitrary incompatible state-layout changes
- replace `Kvist/Live`

The right relationship is still:

- reload mode for broad compiled-code iteration
- `Kvist/Live` for reflective/runtime-programmable layers on top
