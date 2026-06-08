# Live Development

This note narrows the optional live-runtime idea to the specific workflow gap
that matters most right now:

- recovering stateful, iterative development workflows closer to Clojure,
  Lisp, and Smalltalk while keeping Kvist valuable as an Odin frontend

This is a design note for an optional layer. It must not distort the main
value of Kvist as a source-to-source compiler for readable Odin.

The preferred architecture is hybrid:

- native hot reload is the primary answer for broad compiled-code iteration
- `Kvist/Live` is the secondary reflective layer for commands, tools,
  extensions, modding, automation, and runtime inspection

See [HOT-RELOAD.md](./HOT-RELOAD.md) for the primary iterative-development
direction.

## Core Principle

`Kvist/AOT` stays the main product.

`Kvist/Live` is an optional continuity layer for:

- process continuity
- state continuity
- behavioral continuity across reloads

The goal is not "make Odin dynamic everywhere."

The goal is:

- make selected semantic modules live and reloadable over a compiled host

## Goals

1. Recover stateful attached-REPL style development.
2. Allow redefining behavior in a running system.
3. Preserve process and state when changing selected modules.
4. Keep Odin's machine model visible and trustworthy.
5. Keep the same runtime architecture useful later for scripting, extensions,
   tools, and automation.

## Non-Goals

- arbitrary hot-swapping of low-level engine code
- making every Kvist program implicitly dynamic
- hiding ownership or resource semantics
- replacing Odin build, debug, or deployment tools
- requiring full feature parity between AOT and Live modes

## Why Keep This Alongside Native Hot Reload

The usual DLL hot-reload approach gives:

- native code swap
- preserved native memory
- strong dependence on stable struct layout
- restarts when state shape changes

That model is useful, but it often forces:

- one large state blob
- tightly frozen binary boundaries
- awkward evolution of data structures

The live-runtime idea aims for a better reload boundary:

- reload behavior modules rather than arbitrary engine code
- keep host state private behind stable capabilities
- let the live layer own its own state directly
- support explicit migration of live-owned state on reload

So the distinction is:

- DLL reload swaps native code against frozen native memory
- Kvist/Live reload swaps semantic modules over a stable host API

That means `Kvist/Live` is not the whole iterative-development strategy. It is
the complementary layer for the parts native reload does poorly:

- runtime commands
- inspectors
- automation
- scripting
- extensions/modding
- source-level migration of live-owned behavior state

The host-side reload loop should also be a standard pattern rather than copied
per app. The current reusable helper surface is intentionally small:

- `new_module_reloader(...)`
- `load_initial_module(...)`
- `reload_module_if_source_changed(...)`

The lower-level definition-oriented helpers still exist underneath, but the
preferred host path is the runtime-oriented one above. That keeps hosts
from open-coding file signatures, imported-helper watching, parsed-definition
cleanup, and initial-load bookkeeping.

Live modules pass through ordinary top-level macro expansion before
loading, including core macros plus top-level module `defmacro` forms. The runtime
surface is still intentionally smaller after expansion than full compiled
Kvist; the important point is that live modules no longer bypass Kvist's macro
layer entirely.

There is a matching shipped source package on the live side too:

- `(import live "kvist:live")`
- `live.defmodule`
- `live.defcommand`
- `live.defhook`

That mirrors the native side's `kvist:hot` direction: keep the underlying
runtime contract explicit, but stop making every user-land demo spell the same
structural scaffolding by hand.

## The Runtime Object

The live layer should be modeled as a real embeddable runtime, not as a debug
hack.

It should have:

- a runtime instance
- a capability registry
- a module registry
- a persistent environment
- a reload protocol
- event/log history for tooling

The console is a client of that runtime, not the runtime itself.

That keeps the door open to:

- editor-attached consoles
- in-app consoles
- user extension packs
- headless automation
- future remote admin/dev surfaces

## Host / Live Split

Static host responsibilities:

- rendering
- storage
- networking
- core engine
- ownership-sensitive code
- heavy compute
- durable state model

Live module responsibilities:

- commands
- tools
- queries
- reports
- automations
- rules
- inspectors
- dev instrumentation

This is not "the whole engine is reloadable."

It is "the host exposes stable semantic capabilities and the live layer
reloads behavior modules that consume them."

## Shared Subset

The first shared subset between `Kvist/AOT` and `Kvist/Live` should stay small:

- `def`
- `defvar`
- `defn`
- `fn`
- `let`
- `if`
- `when`
- `cond`
- `for`
- arrays
- maps
- struct-like values
- imports

Keep out initially:

- raw pointers
- ownership-sensitive low-level operations
- exact native layout assumptions
- the full Odin type surface

See [LIVE-SHARED-SUBSET.md](./LIVE-SHARED-SUBSET.md) for the current concrete
surface that the live-runtime spike actually supports today.

## Host Capability Model

The live layer must not rely on arbitrary raw memory access.

Use a host capability API instead:

```clojure
(defhostapi app
  (find-items [query] -> [arr item])
  (load-item [id] -> item)
  (save-item! [id patch] -> item)
  (append-event! [event] -> ok)
  (log! [level text] -> ok))
```

That implies:

- host registers named capabilities
- live modules call those capabilities
- host may invoke live handlers by name
- complex native objects cross as opaque handles when needed

## Module Lifecycle

Live modules need explicit lifecycle hooks from the start.

Conceptually:

```clojure
(defmodule inventory-tools
  (def state {version: 1 filters: []})

  (defn init [ctx] ...)
  (defn reload [ctx old-module] ...)
  (defn migrate-state [old-state] ...)
  (defn shutdown [ctx] ...))
```

Even if syntax changes, the runtime model should already support:

- `init`
- `migrate`
- `reload`
- `migrate-state`
- `shutdown`

## State Ownership

Split state three ways.

### 1. Host state

- native compiled structures
- owned by the host
- private unless exposed through capabilities

### 2. Live module state

- owned by the live runtime
- survives reload when possible
- eligible for migration

### 3. Boundary values

- plain portable values
- arrays/maps/struct-like shared values
- opaque host handles for native objects

This prevents the "one giant struct that must never change" trap.

## Reload Flow

Reload should mean:

1. detect changed module source
2. parse/validate it
3. build a new module definition
4. migrate live-owned module state if needed
5. rebind handlers/commands/hooks
6. keep host process alive
7. on failure, keep the previous module active

Reload failure should not tear down the whole system.

## Migration

State migration is one of the most important improvements over ordinary native
hot reload.

When a module changes its live-owned state shape:

- the runtime keeps the old module state
- the new module may provide a migration hook
- the runtime swaps the module only if migration succeeds

That allows evolution of behavior-owned state without forcing a full restart.

## Failure Handling

The live path should be conservative:

- failed parse/validation: keep old module
- failed migration: keep old module
- failed init/reload hook: keep old module
- failed host capability call: report error through runtime and console

The runtime should be biased toward preserving continuity rather than forcing
restarts.

## Development Mode

An app using the live layer should eventually be able to run in a mode like:

- `--live`

That mode could provide:

- attached console
- watched modules
- reload on change
- persistent runtime state
- graceful failed reloads
- optional module-state inspection

This should be built on top of the runtime, not baked into the compiler as a
special one-off trick.

## Future Uses To Keep Open

The first justification may be developer workflow, but the design must preserve
the door to:

- user scripting
- plugin packs
- app automation
- live tools
- modding
- programmable command palettes
- in-app consoles

That means no "dev-only" abstractions that would make later embedding awkward.

The right principle is:

- design for general live programmability
- validate first with developer workflow
