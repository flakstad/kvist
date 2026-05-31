# Future Ideas

This file is for ideas that are worth preserving but should not drive the core
language/runtime implementation prematurely.

## Ownership And Dev Tooling

- Conservative automatic cleanup for obvious non-escaping temporaries.
- Keep manual ownership control available everywhere.
- Keep `with-temp-allocator` available, but do not make it the default answer
  for ordinary code too early.
- Add a `with-tracking-allocator` style helper for development builds so a proc
  body can report leaks at shutdown.
- Add more allocator/debug helpers in a `dev` package once the ordinary
  ownership story is settled.

## CLI And Editor Tooling

- Expose structural s-expression formatting through the `kvist` CLI so Emacs or
  other editors can call into the language’s own formatter/manipulator.
- Consider richer structural editing helpers in the CLI, not just whitespace
  formatting.
- Keep these tools machine-friendly so editors can shell out to Kvist instead
  of each editor reimplementing language-aware transforms.

## Batteries-Included Surface

- Keep building a Kvist-level library layer on top of Odin core/vendor
  packages.
- Prefer a batteries-included experience similar to Odin: many useful things
  should be close at hand without third-party dependency hunting.
- Use the Kvist library/vendor layer where the user-facing surface is clearly
  better than raw host calls, while still lowering to readable Odin.

### Data DSLs

- Continue exploring data-oriented DSLs shipped with Kvist, such as Hiccup-like
  tree builders.
- For these DSLs, the ideal user surface may allow ordinary Kvist expressions
  to appear directly inside the data shape, rather than forcing explicit
  wrapper markers everywhere.
- Do not push that surface wider until the macro expander handles nested helper
  macros and interpolation robustly.
- A Datomic-flavored Datalog DSL is a strong candidate here:
  - source query shape like `[:find ?e :where ...]`
  - macro validation and canonicalization
  - compilation to an efficient internal query representation
  - separate runtime/query engine execution layer
- A routing DSL is another strong candidate:
  - route table shape similar to Reitit-style data
  - macro validation of methods, params, and handler bindings
  - compilation to an efficient internal matcher/dispatch structure

### Call Surface

- Consider allowing functions to be called either positionally or with a
  named-argument map-like surface when that materially improves readability.
- This should remain a language-level design decision, not ad hoc per-library
  sugar.

## Dev And Runtime Workflow

- Add a `dev` package with helpers for storing/retrieving temporary state on
  disk to simulate in-memory continuity between runs.
- Explore pseudo-REPL/dev flows built on scratch files and cached generated
  code.
- Keep building first-class native hot-reload patterns separately from the core
  language surface. See [HOT-RELOAD.md](./HOT-RELOAD.md).
- Keep the optional embedded live runtime secondary and complementary to native
  hot reload. See [LIVE-RUNTIME.md](./LIVE-RUNTIME.md).
- Keep this work clearly separate from the current compiler surface until the
  language core and ownership model are stable.

## Current Bias

Near-term work should stay focused on:

- a clear source language;
- readable Odin lowering;
- explicit ownership with carefully chosen ergonomics;
- strong compile-time checks where the compiler can be obviously correct.

These ideas are intentionally deferred until they can be approached without
muddying those goals.
