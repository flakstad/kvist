# Experimental: Live Shared Subset

This note defines the current practical overlap between `Kvist/AOT` and
`Kvist/Live`.

## Principle

Prefer ordinary Kvist forms whenever possible.

Keep live-only forms narrow and structural:

- `live.module`
- `live.command`
- `live.hook`

Everything else in this document is the currently supported shared surface.

## Current Ordinary Top-Level Forms

The live loader accepts these ordinary top-level forms:

- `import` in path-loaded live modules
- `def`
- `defvar`
- `defn`

Current constraints:

- path-loaded live modules may also import shipped Kvist source packages such
  as `(import live "kvist:live")` before macro expansion
- imported live helper files still support only the unaliased form
  `(import "path")`
- imported live helper files are merged into the root live module rather than
  loaded as separate runtime modules
- imported helper files support ordinary `def`, `defvar`, and
  `defn`
- imported helper files may not define `live.module`, `live.command`,
  `live.hook`, `init`, `shutdown`, or `migrate`
- top-level `def` / `defvar` values must still be simple literals
- top-level `defn` is used for live helper functions and same-named entrypoint
  implementations
- zero-arg top-level `defn init`, `defn migrate`, and `defn shutdown` are
  treated as optional source-defined lifecycle hooks

## Current Live-Only Top-Level Forms

- `live.module`
  - module metadata and initial literal state
- `live.command`
  - marks a command entrypoint
  - may have no body, an options map, an inline body, or both
  - with no inline body, a same-named zero-arg `defn` is used
- `live.hook`
  - marks a hook entrypoint
  - follows the same shape rules as `live.command`

The shipped `kvist:live` package wraps the most common source patterns with:

- `live.defmodule`
- `live.defcommand`
- `live.defhook`

Those macros lower back into the same structural `live.module`,
`live.command`, and `live.hook` forms above.

## Current Expression Subset

The live evaluator supports:

- literals:
  - string
  - int
  - bool
  - nil
- symbols:
  - local bindings
  - module bindings from top-level `def` / `defvar`
- control flow:
  - `do`
  - `if`
  - `when`
- `cond`
- `let`
- state.runtime interaction:
  - `state.get`
  - `state.set!`
  - `state.inc!`
  - `module.name`
  - `module.version`
  - `reload.from-version`
  - `reload.state-get`
  - `args.count`
  - `args.get`
  - `payload.count`
  - `payload.get`
  - `host.call`
  - `hook.emit`
- basic operations:
  - `+`
  - `=`
  - `str`
- function calls:
  - calls to top-level `defn` helpers inside the same live module

## Current Source-Defined Lifecycle Surface

The runtime recognizes these ordinary zero-arg top-level functions when present:

- `defn init [] ...`
- `defn migrate [] ...`
- `defn shutdown [] ...`

These are still runtime-specific conventions, but they deliberately reuse
ordinary Kvist `defn` rather than introducing more special top-level forms.

## Intentional Gaps

These are not part of the shared subset:

- closures / anonymous `fn`
- arrays, maps, and struct literals inside behavior bodies
- `for`
- `case`
- `match`-style branching
- user-defined data types
- multi-arity functions
- higher-order function values

Top-level macro expansion is available before live loading, including module
`defmacro` forms and shipped source-package macros such as `kvist:live`.
What is still out of scope is arbitrary macro-expanded behavior that lowers
outside the evaluator's supported runtime subset.

## Why This Matters

This document is the current contract for the ordinary Kvist forms that the
live loader and evaluator accept.
