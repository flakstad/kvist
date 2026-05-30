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
- `load_initial(...)`
- `reload_if_source_changed(...)`

That is enough to keep the application loop ordinary while centralizing the
reload generations and file-change tracking in one place.

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
- a clean place for later `Kvist/Live` embedding on top
