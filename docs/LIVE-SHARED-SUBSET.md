# Live Shared Subset

This note defines the current practical overlap between `Kvist/AOT` and
`Kvist/Live`.

The goal is not to claim full parity. The goal is to make the shared surface
explicit so live-runtime work grows toward a future "same source, different
execution mode" model instead of drifting into a separate live-only DSL.

## Principle

Prefer ordinary Kvist forms whenever possible.

Keep live-only forms narrow and structural:

- `live/module`
- `live/command`
- `live/hook`

Everything else should move toward ordinary Kvist surface area unless there is
a strong reason not to.

## Current Ordinary Top-Level Forms

The live loader currently accepts these ordinary top-level forms:

- `def`
- `defconst`
- `defvar`
- `defn`

Current constraints:

- top-level `def` / `defconst` / `defvar` values must still be simple literals
- top-level `defn` is used for live helper functions and same-named entrypoint
  implementations
- zero-arg top-level `defn init` and `defn shutdown` are treated as optional
  source-defined lifecycle hooks

## Current Live-Only Top-Level Forms

- `live/module`
  - module metadata and initial literal state
- `live/command`
  - marks a command entrypoint
  - may have no body, an options map, an inline body, or both
  - with no inline body, a same-named zero-arg `defn` is used
- `live/hook`
  - marks a hook entrypoint
  - follows the same shape rules as `live/command`

## Current Expression Subset

The live evaluator currently supports:

- literals:
  - string
  - int
  - bool
  - nil
  - keyword
- symbols:
  - local bindings
  - module bindings from top-level `def` / `defconst` / `defvar`
- control flow:
  - `do`
  - `if`
  - `when`
- `cond`
- `let`
- state/runtime interaction:
  - `state/get`
  - `state/set!`
  - `state/inc!`
  - `module/name`
  - `module/version`
  - `host/call`
  - `hook/emit`
- basic operations:
  - `+`
  - `=`
  - `str`
- function calls:
  - calls to top-level `defn` helpers inside the same live module

## Current Source-Defined Lifecycle Surface

The runtime now recognizes these ordinary zero-arg top-level functions when
present:

- `defn init [] ...`
- `defn shutdown [] ...`

These are still runtime-specific conventions, but they deliberately reuse
ordinary Kvist `defn` rather than introducing more special top-level forms.

## Intentional Gaps

These are not part of the current shared subset yet:

- imports between live modules
- macros
- closures / anonymous `fn`
- arrays, maps, and struct literals inside behavior bodies
- `for`
- `case`
- `match`-style branching
- user-defined data types
- source-defined lifecycle hooks
- multi-arity functions
- higher-order function values

## Why This Matters

If the live path is worth continuing, it has to converge on this shape:

- ordinary Kvist definitions for most source
- a thin live annotation layer for runtime-only concerns
- the possibility that the same module body could eventually run:
  - interpreted in development
  - compiled ahead-of-time in production

That makes this document a design constraint, not just a feature list.
