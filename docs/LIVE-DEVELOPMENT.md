# Live Development

Kvist live development is an optional continuity layer on top of a compiled
host. It is separate from native hot reload:

- native hot reload swaps compiled code across a stable native boundary
- `Kvist/Live` reloads semantic modules over a stable host capability API

The main product remains `Kvist/AOT`: source-to-source compilation to readable
Odin.

## Role

Use `Kvist/Live` for:

- commands
- tools
- queries
- reports
- automations
- inspectors
- development instrumentation

Do not use it for arbitrary low-level engine replacement, hidden ownership, or
full Odin-layout programming inside the live evaluator.

## Runtime Object

The live layer is an embeddable runtime with:

- a runtime instance
- a module registry
- a capability registry
- persistent live-owned module state
- reload hooks
- event/log history for tooling

The console is a client of that runtime. The runtime itself owns module loading,
handler lookup, state storage, and reload failure behavior.

## Host / Live Split

Static host responsibilities:

- rendering
- storage
- networking
- core engine behavior
- ownership-sensitive code
- heavy compute
- durable native state

Live module responsibilities:

- commands
- tools
- queries
- reports
- automations
- rules
- inspectors
- development instrumentation

The host exposes stable semantic capabilities. Live modules call those
capabilities rather than mutating arbitrary host memory.

## Source Surface

Live modules pass through ordinary top-level macro expansion before loading.
They may import the shipped `kvist:live` package:

```clojure
(import live "kvist:live")

(live.defmodule demo {count: 0})

(live.defcommand tick []
  ...)
```

The package macros lower to the structural live forms:

- `live.module`
- `live.command`
- `live.hook`

See [LIVE-SHARED-SUBSET.md](./LIVE-SHARED-SUBSET.md) for the ordinary Kvist
forms accepted by the live loader and evaluator.

## Module Lifecycle

The live runtime supports:

- initial module load
- command and hook lookup
- reload from changed `.kvist` source
- source-defined `init`, `migrate`, and `shutdown` hooks
- preserving the previous module on failed parse, validation, migration, or hook
  execution

Reload failure does not tear down the host process. The runtime keeps the
previous loaded module active.

## State Ownership

The host owns host state. Live modules own live module state. State crossing the
host/live boundary should use explicit capabilities, values, or opaque handles.

When a module changes its live-owned state shape, the runtime can call a
source-defined migration hook. The new module becomes active only if migration
succeeds.

## Demos

Current examples:

- `examples/reload/live_commands_demo`
- `examples/reload/live_reload_demo`
- `examples/reload/hybrid_live_demo`

The hybrid demo combines native hot reload for compiled host/module code with
`Kvist/Live` for runtime command reload.
