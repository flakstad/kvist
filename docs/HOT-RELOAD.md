# Native Hot Reload

This note captures the current preferred direction for iterative development in
Kvist:

- native hot reload is the primary path for broad compiled-code iteration
- `Kvist/Live` is the secondary path for commands, tools, extensions, modding,
  automation, and runtime inspection

This keeps Kvist valuable as an Odin frontend first while still leaving room
for more reflective workflows later.

## Core Principle

`Kvist/AOT` stays the main product.

The first-class iterative workflow should be:

- keep the host process alive
- rebuild selected code as a shared library
- reload that code into the running process
- preserve host-owned state across reload

This should feel like a language-supported pattern, not an ad hoc engine trick.

## Why This Comes First

Compared to a hosted live runtime, native hot reload has one major advantage:
it works on ordinary compiled code.

That matters because the workflow gap being felt most strongly is not just
"scriptability." It is:

- making changes to real program code
- keeping the process alive
- keeping the current state alive
- avoiding full rebuild/restart loops

If Kvist can help standardize that pattern, it recovers a large share of the
iterative-development value without requiring the whole project to be organized
around a hosted subset.

## Role Split

The intended hybrid model is:

### Native hot reload first

Use native hot reload for:

- gameplay/app/domain logic under active iteration
- tools and views that still want ordinary compiled code
- high-level host behavior that should stay in the main compiled language
- broad day-to-day program iteration

### `Kvist/Live` second

Use `Kvist/Live` for:

- commands
- inspectors
- automation
- editor- or operator-style consoles
- extensions and modding
- runtime scripting
- semantic state migration for live-owned behavior

These two mechanisms should complement each other rather than compete.

## Native Reload Contract

The initial `kvist_hot` contract is intentionally small:

- the host owns the durable state root
- the reloadable module exports a manifest
- the host validates API version plus state layout
- the host calls lifecycle hooks around reload
- the host swaps only the code boundary, not the whole process
- a small reloader object tracks file changes and reload generations

This keeps the design honest:

- low-level/native state still needs compatible layout
- not every change can avoid restart
- the boundary has to be explicit

But it also avoids the worst hand-rolled DLL-reload problems by making the
reload shape standard and visible.

The current host-side helper surface is also intentionally small:

- `new_reloader(...)`
- `load_initial_module(...)`
- `reload_module_if_source_changed(...)`

The lower-level load/result helpers still exist underneath, but the preferred
host path is now the state-owning one above so `kvist_hot` itself sequences
`on_unload`, manifest validation, and `on_load` around library swaps.

On the module side, the first shipped Kvist helper package now exists too:

- `(import hot "kvist:hot")`
- `(hot/defmodule ...)`

That macro expands the standard `kvist_hot` manifest and exported entrypoints
for a host-owned state type, so reloadable modules stop hand-writing the same
ABI surface per demo.

There is now also a first-pass higher-level CLI surface on top of that runtime:

- top-level `(defstate Name {fields...} {metadata...})` in pure `.kvist` user code
- `kvist dev --reload app/main.kvist`
- `kvist dev --reload app/main.kvist --rebuild`
- `kvist dev --reload app/main.kvist --print-paths`
- `kvist dev --reload app/main.kvist --print-paths --json`
- `kvist dev --reload app/main.kvist --rebuild --json`
- `kvist check --reload app/main.kvist`
- `kvist build --reload app/main.kvist`
- `kvist run --reload app/main.kvist`

That path generates the resident shell and reloadable module underneath while
keeping the user source as one `.kvist` app file with one durable root state
and an explicit reload-lifetime contract.

The compiler now also owns the generated-Odin import rebasing for this path.
That means:

- `kvist compile ... -o some/output.odin`
- `kvist check|build|run --reload ...`
- `kvist dev --reload ...`

all write generated Odin with source-package-introduced Odin imports rewritten
relative to the final output location instead of leaking absolute repo paths.
This matters in practice for cache directories and symlinked temp roots like
`/tmp` on macOS.

Today the generated host supports both:

- `:run` for app-owned runtimes that cooperate through one explicit
  `reload/checkpoint!` boundary; this is the general mode for most programs
- `:step` for shell-owned loop-driven apps; this is the convenience mode when
  you want Kvist to provide the outer loop

Recommended default:

- prefer `:run` for most real applications
- use `:step` when you explicitly want Kvist to own the outer loop

Good `:run` fits:

- web servers
- GUI apps
- worker processes
- editors
- tools with their own event or request cycle

Good `:step` fits:

- games
- simulations
- polling tools
- immediate-mode interactive programs
- small demos where a step-and-sleep loop is already the right shape

In development, `kvist dev --reload ...` keeps the resident shell alive and
rebuilds only the reloadable side. In ordinary execution, `kvist check|build|run
--reload ...` generates a plain wrapper around the same `defstate` source:

- `:step` lowers to a normal step-and-sleep executable loop
- `:run` lowers to a normal app-owned runtime call
- `reload/checkpoint!` becomes a no-op when there is no resident reloader

For sources that clearly declare the reload-app contract through `defstate`
metadata, plain `kvist check|build|run app/main.kvist` now route through that
same production wrapper automatically. `--reload` remains valid, but is no
longer required for the common reload-app source shape.

Current state-layout behavior is intentionally conservative:

- the runtime validates state size and alignment on module load/reload
- if those checks fail, the reload is rejected and the running process keeps the
  previous code loaded
- there is no field-aware durable-state migration yet

That means behavior changes are the intended smooth path today, while durable
state-shape changes still require either a clean restart or a future explicit
migration/reset policy.

## `:run` Checkpoint Guidance

`reload/checkpoint!` is the single explicit cooperation point for `:run`.

Treat it as:

- "I am at a safe point where this runtime can stop and let the resident shell
  swap code"

Do not treat it as:

- "sprinkle reload checks anywhere in the codebase"

The guidance is:

- call it at one deliberate runtime boundary
- call it often enough that reload latency feels acceptable
- only call it where returning from `run` is safe

Good checkpoint boundaries:

- once per request cycle
- once per event-loop cycle
- once per frame
- once per job/batch item
- once per outer loop iteration

Bad checkpoint boundaries:

- mid-transaction
- while holding locks or fragile external resources
- deep inside leaf functions
- while shared state is only partially updated

Practical examples:

```clojure
(defn run [state: (ptr App_State) host: (ptr reload/Run_Host)]
  (for true
    (handle-one-request state)
    (when (reload/checkpoint! host)
      (return))))
```

```clojure
(defn run [state: (ptr App_State) host: (ptr reload/Run_Host)]
  (for true
    (pump-events state)
    (dispatch-ready-work state)
    (when (reload/checkpoint! host)
      (return))))
```

If reload feels sluggish, move the checkpoint to a slightly finer safe
boundary. Do not move it inward so far that correctness becomes unclear.

If a source package needs to publish raw Odin names in that flow, it can now do
so explicitly with:

```clojure
(exports [Run_Host reload__Run_Host])
```

That keeps the public source-package surface explicit instead of relying on
compiler hardcoding.

## Tooling Surface

The current editor-facing reload contract is:

- `kvist dev --reload app/main.kvist --json`
- `kvist dev --reload app/main.kvist --print-paths --json`
- `kvist dev --reload app/main.kvist --rebuild --json`

The first command starts the resident reload session and emits structured event
lines prefixed with `KVIST_RELOAD_EVENT<TAB>`. Those lines carry JSON payloads
such as `started`, `reloaded`, `reload_failed`, and `checkpoint_error`, while
ordinary app stdout/stderr still flows through the same terminal or editor
buffer.

The second command prints machine-readable generated paths and canonical reload
commands. The third prints a structured rebuild result with:

- `ok`
- `exit_code`
- `module_dir`
- `module_odin`
- `module_binary`

That is the intended integration point for Emacs and other external tooling.
The ordinary human-oriented text output remains available without `--json`.

## Recorded Decisions

These points should now be treated as the working product direction for native
hot reload.

### 1. Native hot reload stays the primary iterative path

For ordinary app code, native hot reload comes first. `Kvist/Live` remains the
secondary reflective/runtime layer for commands, inspection, and automation.

### 2. A stable resident shell is unavoidable

There is no honest native hot-reload design where literally 100% of the
program is replaced in place with no stable resident code at all.

Something must remain loaded in order to:

- own long-lived state
- load and unload the new code
- sequence reload lifecycle hooks
- survive the swap

So the long-term goal is not "remove the shell." It is "hide the shell from
the everyday user workflow."

### 3. The user should not have to think in host/module terms

The current explicit host plus module demos prove the mechanism, but they are
not the intended final user model.

The intended user story is:

- write ordinary Kvist/Odin-shaped code
- put durable state in one obvious place
- opt into hot reload explicitly
- run a reload development workflow
- let Kvist generate the resident shell and reloadable boundary underneath

### 4. One durable state root is the right default

The durable state that survives reload should have one explicit root.

That is a benefit, not a drawback, because it:

- makes the reload boundary explicit
- gives one stable ownership root for long-lived state
- simplifies reload validation and lifecycle hooks
- avoids scattered persistence rules

This should not mean "one giant blob." The good pattern is:

- one root state struct
- composed of subsystem structs
- pointer-oriented access to the pieces that matter
- explicit distinction between durable and transient state

### 5. The main risk is coupling, not raw performance

Requiring one root state struct is not inherently a performance problem if the
program passes pointers to that state or its subsystems rather than copying the
whole root by value.

The real design risk is letting the root degrade into an unstructured kitchen-
sink object where every subsystem reaches into every field.

So the hot-reload guidance should be:

- keep one durable root
- split it into subsystem state structs
- pass pointers to the needed subsystem or root
- keep transient scratch/runtime-only state outside the durable root when that
  is clearer

### 6. The real remaining ceremony should move into tooling/codegen

The current system still exposes:

- explicit host code
- explicit reloadable module code
- explicit shared state contracts

Those are useful implementation truths, but they should become Kvist's
responsibility rather than the end user's day-to-day concern.

That points directly toward a first-class reload-app design layered over the
existing `kvist_hot` runtime pieces.

## State Ownership

For native hot reload, the state model should be:

### 1. Host-owned durable state

- long-lived app/game/tool state
- survives code reload
- allocated and freed by the host

### 2. Reloaded module code

- behavior implementation
- stateless helpers
- functions that operate on host-owned state
- lifecycle hooks for reload entry/exit

### 3. Optional live runtime state

- only when `Kvist/Live` is embedded
- owned by the live runtime, not the native hot-reload layer
- useful for commands, extensions, and reflective tooling

## What This Does Not Solve

Native hot reload is strong, but it is not magic.

It does not remove the need for:

- compatible native state layout at the reload boundary
- clear ownership of long-lived allocations
- stable exported entrypoints
- occasional restarts when low-level structure changes too much

That is exactly why `Kvist/Live` still has a role.

## Relationship To `Kvist/Live`

`Kvist/Live` should now be read as a complementary continuity layer, not as the
main answer to iterative development.

The split is:

- `kvist_hot`: first-class native hot reload for ordinary compiled code
- `kvist_live`: reflective/runtime-programmable layer for commands, tooling,
  scripting, and inspection

This is the architecture that seems strongest right now.

## Demo

The first native hot-reload demo lives in
[`examples/hot_reload_demo`](../examples/hot_reload_demo/README.md).

It shows:

- a running host process
- a separately built shared library
- a host-owned state struct surviving reload
- rebuild-only iteration on the reloadable module
- the reusable `kvist_hot.Reloader` workflow in host code
- the shipped `kvist:hot` macro package on the module side
- `.kvist` demo sources compiled to Odin as part of the loop
- pure-Kvist native module contracts via `(hot/defmodule ...)`
- a clean place for later `Kvist/Live` embedding on top

The newer lowest-ceremony native path lives in
[`examples/reload_step_demo`](../examples/reload_step_demo/README.md). It demonstrates
the first `defstate` reload workflow and the CLI shape intended for editor
tooling.

Its companion app-owned runtime example lives in
[`examples/reload_run_demo`](../examples/reload_run_demo/README.md).

That follow-on combined example now lives in
[`examples/hybrid_live_demo`](../examples/hybrid_live_demo/README.md).

It shows:

- the same host-owned native state surviving DLL rebuilds
- an embedded `kvist_live` runtime in the same host
- live command reload from `.kvist` source without rebuilding the DLL
- the two continuity layers cooperating instead of being documented separately

## Next Surface Direction

The next strong step on the native side is to stop exposing the
mechanism-shaped host/module split directly to users and instead define one
first-class reload pattern.

That proposed surface is documented in
[RELOAD-APP-DESIGN.md](./RELOAD-APP-DESIGN.md).
