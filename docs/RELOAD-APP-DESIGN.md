# Reload App Design

This note proposes the next user-facing layer on top of the existing
`kvist_hot` runtime.

The problem is clear:

- the current host + module demos are honest
- but they still expose too much mechanism
- the desired user model is closer to ordinary Kvist with one durable state
  root and one explicit reload opt-in

This note is about that higher-level surface.

## Design Goal

The user should be able to:

- write ordinary Kvist
- define one durable state root
- opt into native hot reload explicitly
- run a reload development command
- let Kvist generate the resident shell and reloadable module boundary

The same source should also be able to run without the resident reload shell
for ordinary execution and production-style builds.

The user should not have to hand-write:

- dynlib symbol tables
- native reload manifests
- a parallel host project just to keep a loop alive

## Mental Model

The intended mental model is:

- almost all app logic is reloadable
- one small generated shell stays resident
- one durable state root survives reload
- lifecycle hooks are available when needed

So "all my code reloads" really means:

- all normal app behavior reloads
- except the small irreducible shell that owns the process and durable state

That is the honest native model.

## Proposed User Pattern

The core pattern should be:

1. one durable root state type
2. a trailing metadata map on that state declaration for reload hooks/config
3. ordinary top-level behavior `defn`s referenced from that metadata
4. one reload development command

For the shipped runtime helper package, the canonical import is:

```clojure
(import reload "kvist:reload")
```

The current reload wrapper generation expects that canonical alias rather than
arbitrary renaming of the package import.

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
  (for true
    (process-one-job state)
    (core/when (reload/checkpoint! host)
      (return))))
```

If one unit of work is very long-running, then reload responsiveness will also
be long. In that case the right fix is usually to introduce a finer safe
boundary inside that runtime shape, not to scatter checkpoints randomly.

## Why One Root State

The default should be one durable root state struct.

That is a benefit because it gives:

- one explicit ownership root
- one clear reload boundary
- one obvious place for compatibility checks
- one obvious place for state migration hooks

This does not mean "one giant blob." The intended pattern is:

- one root
- composed subsystem structs inside it
- pointer-oriented access to root or subsystems

Good:

```clojure
(defstate App_State
  {:world World_State
   :ui UI_State
   :audio Audio_State
   :assets Asset_Cache})
```

Bad:

- every system reaches into every field
- the entire state is copied around by value
- transient scratch state is dumped into the durable root by default

## Durable vs Transient State

The reload-app design should distinguish two broad classes of state.

### Durable state

- lives in the root `App_State`
- survives code reload
- owned by the generated shell
- validated for layout compatibility

Examples:

- world/app/model data
- long-lived caches that should persist
- editor/session state that should survive rebuilds

### Transient state

- rebuilt on reload
- not part of durable compatibility guarantees
- can remain module-local or reload-local

Examples:

- frame scratch
- temporary algorithm work buffers
- ephemeral render command state
- one-shot runtime glue

The language surface does not need to force a single exact transient-state
mechanism yet. It only needs to make the durable root explicit.

## Current State-Shape Rules

Today the safe rule is:

- change behavior freely
- keep durable `defstate` shape stable during a resident reload session
- restart the app when changing durable state layout

The current runtime validates:

- state size
- state alignment

That is enough to reject many incompatible reloads, but it is not enough to
prove semantic compatibility. Two layouts can still be logically different even
when size and alignment happen to match.

So the product message should stay explicit:

- code changes are the intended smooth reload path
- durable state-schema changes are not transparently migrated yet

## Proposed State Schema Design

The next real step is to make durable-state compatibility explicit on
`defstate`, rather than relying only on raw layout checks.

The shape should stay close to the current source form:

```clojure
(defstate App_State
  {:world (ptr World_State)
   :ui (ptr UI_State)
   :assets (ptr Asset_Cache)}
  {:run run
   :version "3"
   :migrate migrate
   :on-schema-change :warn-reset
   :init init
   :on-load on-load
   :on-unload on-unload})
```

Meaning:

- `:version`
  - durable-state schema version, not just app display version
- `:migrate`
  - explicit migration hook for compatible upgrade paths
- `:on-schema-change`
  - explicit policy when the new durable state cannot be reused directly

## Proposed Reload Decision Flow

On reload:

1. load the new module
2. compare runtime ABI and state layout as today
3. compare durable-state schema version
4. choose one of these paths:

- compatible layout and same schema version:
  - keep state in place
  - run normal `on-load`
- compatible layout but different schema version and migration exists:
  - run `migrate`
  - if migration succeeds, swap to new code
  - if migration fails, keep old code running
- incompatible layout or incompatible schema with no valid migration:
  - warn clearly
  - do not silently discard state
  - require an explicit reset/restart choice

The important policy is that state reset should never be the invisible default.

## Proposed Schema-Change Policies

Suggested policy values:

- `:reject`
  - incompatible reload is refused
  - old code keeps running
  - user must restart explicitly
- `:warn-reset`
  - incompatible reload prints a warning and offers reset as an explicit choice
  - reset is allowed, but never automatic
- `:migrate-required`
  - incompatible reload is refused unless a migration hook succeeds

Current recommendation:

- default to `:reject`
- allow `:warn-reset` as the practical development option
- do not add a silent `:reset` default

That matches the intended user experience:

- smooth behavior reloads by default
- explicit warning for incompatible state changes
- optional reset when the developer chooses it

## Proposed Migration Hook Shape

The migration surface should avoid raw reinterpretation of arbitrary memory.
The safer model is explicit construction of the new state from a versioned view
of the old one.

Conceptually:

```clojure
(defn migrate [ctx: reload/Migration old-version: string new-state: (ptr App_State)]
  ...)
```

Where `ctx` gives controlled access to the previous durable state by stable
field identity rather than by unchecked casting.

That allows migrations like:

- populate a newly added field with defaults
- rename or split older fields
- rebuild one subsystem while preserving others

## Large App-State Guidance

For large applications, the durable root should still be one `defstate`, but it
should usually be a root of subsystem handles or pointers rather than one giant
flat by-value blob.

Good shape:

```clojure
(defstate App_State
  {:world (ptr World_State)
   :renderer (ptr Renderer_State)
   :editor (ptr Editor_State)
   :assets (ptr Asset_Cache)}
  {:run run
   :version "7"
   :migrate migrate
   :on-schema-change :warn-reset})
```

That makes migration tractable because changes can happen at subsystem
boundaries:

- preserve still-valid subsystem pointers
- initialize newly added subsystems
- rebuild removed or transient subsystems
- migrate changed subsystem-owned data explicitly

## Lifecycle Surface

The higher-level reload path should support a small explicit lifecycle.

At minimum:

- `init`
- `on-load`
- `on-unload`

Possibly later:

- `migrate`
- `validate`

Initial working assumption:

- `init` is for first-time setup of the durable state
- `on-load` runs when a new module instance becomes active
- `on-unload` runs before the old module is replaced

Example shape:

```clojure
(defstate App_State
  {:world World_State}
  {:step step
   :init init
   :on-load on-load
   :on-unload on-unload})
```

The generated shell should wire those named functions through the existing
`kvist_hot` mechanism.

## Production Story

Reload mode should stay a development affordance, not a deployment
architecture requirement.

The intended split is:

- `kvist dev --reload ...` for iterative development with a resident shell and
  reloadable module boundary
- `kvist dev --reload ... --print-paths --json` for machine-readable path and
  command discovery
- `kvist dev --reload ... --rebuild --json` for machine-readable rebuild
  status
- `kvist check --reload ...` / `kvist build --reload ...` /
  `kvist run --reload ...` for ordinary execution of the same source without
  the resident reload shell

That means the same `defstate` source has two host contexts:

- development context: resident reload shell, `reload/checkpoint!` can request
  a reload
- ordinary execution context: plain executable wrapper, `reload/checkpoint!`
  returns `false`

So production does not need the DLL boundary or the resident shell. The reload
metadata remains useful as a source-level declaration of durable state and
runtime shape, but the non-dev path lowers to a normal executable wrapper.

The generated Odin for those wrappers is now rebased relative to its output
destination, so `kvist compile ... -o ...` and `kvist check|build|run --reload`
do not depend on absolute repo-root import paths in emitted Odin.

## Host Modes

The current generated shell is loop-driven. That is a good first pattern, but
it is too narrow to be the final reload-app model for Kvist.

The design should separate:

- the durable-state and reload contract
- the generated host mode that drives the program

The durable-state part should stay stable:

- one `defstate`
- one explicit metadata map for hot behavior
- optional load/unload hooks
- one CLI surface: `kvist dev --reload ...`

What should vary is how the generated host drives the running program.

### `:step`

`:`step` is the current mode.

Example:

```clojure
(defstate App_State
  {:world World_State
   :ui UI_State}
  {:step step
   :init init
   :on-load on-load
   :on-unload on-unload
   :sleep-ms 16})
```

This means the generated shell owns the steady-state loop.

Conceptually:

```odin
init if first load
on_load every activation

for {
    step(&state)
    reload_if_changed(...)
    sleep(...)
}
```

This fits naturally for:

- games
- simulations
- editors
- polling tools
- immediate-mode applications

So `:step` is not a special reload hook. It is the generated host's repeated
main callback, and it should be understood as the convenience mode rather than
the universal default.

### `:run`

The second mode should be `:run`.

Example:

```clojure
(defstate App_State
  {:router Router
   :db DB
   :config Config}
  {:run run
   :init init
   :on-load on-load
   :on-unload on-unload})
```

This mode is for applications that want to own their own runtime shape rather
than being driven by a generated step-and-sleep loop.

Examples:

- GUI applications with framework-owned event loops
- servers
- workers
- tools that block inside an existing runtime
- runtimes that already have their own scheduling model

The critical design constraint is:

- `:run` must not require scattered special reload calls throughout user code

If `:run` is good, the cooperation point must be explicit and architectural,
not ambient and easy to forget.

### Why `:run` Is Different

A purely blocking `run(state)` is not enough for hot reload by itself.

If the generated shell does this:

```odin
run(&state)
```

then the shell cannot reload while `run` is blocking unless the app-owned
runtime cooperates.

So `:run` needs one explicit reload checkpoint model. The user should not
sprinkle low-level reload calls throughout ordinary app code. Instead, Kvist
should make the cooperation point singular and easy to reason about.

That means `:run` should evolve toward one of these shapes:

- generated adapters around known loop styles
- a single explicit host handle passed into `run`
- a single runtime-boundary polling/checkpoint API

The important rule is that the user should only have to think about one
integration point per runtime boundary, not "remember to call hot reload
everywhere."

## Editor Integration

The first stable editor-facing contract is intentionally small:

- `kvist dev --reload app/main.kvist --print-paths --json`
- `kvist dev --reload app/main.kvist --rebuild --json`

The first command reports generated reload paths and canonical reload commands
in machine-readable form. The second reports rebuild success or failure
together with the generated module locations. That is the preferred surface
for Emacs and other external tooling.

## Proposed `:run` Contract

The most likely first useful `:run` contract is:

- the generated shell still owns the durable state and reload bookkeeping
- the reloadable module exports one `run` function
- that `run` function receives the durable state and a small host handle
- user code calls one checkpoint operation only at an architectural boundary

Conceptually:

```clojure
(defstate Server_State
  {:router Router
   :db DB
   :config Config}
  {:run run
   :init init
   :on-load on-load
   :on-unload on-unload})

(defn run [state: (ptr Server_State) host: reload/Run_Host]
  ...)
```

The important part is not the exact name `Run_Host`. The important part is:

- one explicit value from the generated shell
- one place where reload coordination enters the app-owned runtime

### Single Checkpoint API

The hot runtime side of that handle should stay small.

Conceptually, something like:

```clojure
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
(defn run [state: (ptr Server_State) host: reload/Run_Host]
  (for true
    (accept-or-process-one-thing state)
    (reload/checkpoint! host)))
```

For a framework-owned event loop, the checkpoint may sit in one adapter
callback:

```clojure
(defn run [state: (ptr App_State) host: reload/Run_Host]
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
