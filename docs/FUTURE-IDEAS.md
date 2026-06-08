# Future Ideas

This file is for ideas that are worth preserving but should not drive the core
language/runtime implementation prematurely.

## Ownership And Dev Tooling

- Conservative automatic cleanup for obvious non-escaping temporaries.
- Keep manual ownership control available everywhere.
- Keep `with-temp-allocator` available, but do not make it the default answer
  for ordinary code too early.
- Add a `with-tracking-allocator` style helper for development builds so a
  function body can report leaks at shutdown.
- Add more allocator/debug helpers in a `dev` package once the ordinary
  ownership story is settled.

## CLI And Editor Tooling

- Expose structural s-expression formatting through the `kvist` CLI so Emacs or
  other editors can call into the language’s own formatter/manipulator.
- Consider richer structural editing helpers in the CLI, not just whitespace
  formatting.
- Keep these tools machine-friendly so editors can shell out to Kvist instead
  of each editor reimplementing language-aware transforms.

## Testing Surface

- Build on the shipped `kvist:test` package rather than designing a runtime
  framework first.
- Keep the user shape Clojure-like:
  - `(import t "kvist:test")`
  - `(t.deftest name ...)`
  - `(t.is expr)`
- Continue lowering that surface to ordinary Odin test declarations and
  assertions.

## Batteries-Included Surface

- Keep building a Kvist-level library layer on top of Odin core.vendor
  packages.
- Prefer a batteries-included experience similar to Odin: many useful things
  should be close at hand without third-party dependency hunting.
- Use the Kvist library/vendor layer where the user-facing surface is clearly
  better than raw host calls, while still lowering to readable Odin.
- Keep these packages shipped with the compiler/toolchain, but only pull them
  into a built program when the user imports them explicitly.
- The goal is "available by default", not "automatically linked".

### General-Purpose Packages To Explore

- `dev`
  - scratch-state helpers
  - simple file-backed development persistence
  - leak/debug helpers later
- `path`
  - common path composition and inspection helpers
  - a quieter Kvist surface over routine Odin path/filepath use
- `json`
  - a thinner Kvist surface for common marshal/unmarshal cases
  - only if it materially improves ordinary source without hiding ownership
- `io`
  - straightforward text/bytes/file flows
  - result/error handling that stays explicit
- `time`
  - date/time helpers that are common in application code
- `url`
  - parsing, path, and query helpers
- `html`
  - rendering and response helpers that complement `kvist:html`
- `http`
  - a broader batteries-included server/client story if that becomes a real
    direction

These should all be judged by the same bar:

- better user-facing Kvist source
- direct, readable Odin lowering
- no hidden runtime layer
- no automatic inclusion unless imported

### Collection Composition

- Keep a transducer-style path open for collection pipelines if it can compile
  to one plain Odin loop and one owned result.
- This is only interesting if it reduces the eager pipeline allocation cost
  without introducing a hidden interpreter, lazy seq runtime, or persistent
  collection system.
- The current eager helper surface should remain simple and direct until a
  transducer design is concrete enough to prove that it preserves readable
  lowering and explicit ownership.

### Data DSLs

- Continue exploring data-oriented DSLs shipped with Kvist, such as HTML-like
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

The current call surface already includes:

- positional calls
- named calls for known top-level `defn`
- mixed positional plus named-tail calls for known top-level `defn`
- trailing default parameters for known top-level `defn`

Future work here should focus on boundary decisions rather than re-arguing the
base feature:

- whether any of this should ever apply to function-valued expressions, not just
  statically known top-level functions
- whether destructuring and call-site named/default conventions should gain a
  shared "options object" story, or stay intentionally separate
- whether destructuring should widen beyond the current struct-backed
  `{:keys [...]}` subset
- whether `:or` defaults are worth supporting for destructuring, and under what
  semantics
- whether any broader call sugar would still preserve explicit, readable Odin
  lowering

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
