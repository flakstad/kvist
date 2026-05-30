# Next Steps

This note captures the larger unresolved language areas after the recent
surface-syntax cleanup. It is intended as a working backlog for design and
implementation, not as a promise that all of these should happen immediately.

## Still Valid, Not Yet Idiomatic

Many existing examples are still valid Kvist, but some are not yet written in
the preferred surface style. That cleanup can continue later. The items below
are more important than example polish.

## Major Open Areas

### 1. Package System Depth

Basic source-package loading works, but the broader package story is not fully
designed yet:

- project/package roots
- visibility rules
- import cycle diagnostics
- larger multi-package layout conventions

### 2. Macro System

Macros are part of the intended language direction, but the real user-facing
macro system has not been designed or implemented yet.

Open questions:

- macro declaration surface
- expansion phase boundaries
- how macros interact with source packages
- what should remain available for explicit raw Odin escape

Additional pressure from real DSL work is now clear:

- data-oriented DSLs like Hiccup want a cleaner interpolation story
- ideally, a macro should be able to distinguish structural data from ordinary
  Kvist expressions without forcing verbose wrapper markers around every
  runtime hole
- this likely requires better macro-expander handling for nested package-local
  helper macros, `quasiquote`/`splice`, and expression-vs-data interpolation
  rules before the DSL surface should be widened further

### 3. Fixed-Shape Type Depth

`defstruct` is real and already useful, but the broader fixed-shape type story
is still incomplete:

- `defenum` and `defunion` need more deliberate design and example pressure
- constructor ergonomics can be improved
- richer compile-time checks are still possible
- usage patterns for enums/unions in real code are not yet settled

### 4. Ownership Ergonomics

Ownership warnings and helper forms exist, but the everyday user story is only
first-pass.

Still open:

- clearer library conventions for owned producers
- more helper patterns around local owned values
- better documentation for common ownership workflows
- development helpers such as tracking allocators

### 5. Function And Type Surface Consistency

The type surface is much better now, but some areas still need a final shape:

- proc types and higher-order function syntax
- generic type surface
- interop-facing type forms
- where Kvist should stay close to Odin versus where it should own a richer
  source notation

Call conventions are also still open:

- ordinary positional function calls should remain available
- it may be valuable to support a named-argument call style using a map-like
  surface for functions that benefit from self-documenting call sites
- that design needs to be weighed against Odin interop clarity, overload
  ambiguity, and how much compile-time checking Kvist can provide

### 6. Error And Result Ergonomics

Multiple returns work, but the language-level conventions around result/error
handling are still light.

This includes:

- common result patterns
- helper forms, if any
- interaction with ownership and early returns

### 7. Closures And Higher-Order Functions

`fn` exists, but captured closures are still not designed.

This remains open both semantically and in lowering strategy:

- do we want captured closures at all?
- if yes, what does the lowered Odin model look like?
- how much value do they add relative to explicit data + top-level procs?

### 8. Tooling And Dev Workflow

Several important ideas are noted but not yet built:

- structural formatting/manipulation through the CLI
- stronger editor integration
- dev/repl package ideas
- scratch-state helpers
- first-class native hot-reload patterns
- tighter cooperation between native hot reload and `Kvist/Live`

### 9. Standard Library Shape

Useful library surface exists, but the stdlib is still partly inherited from
earlier Kvist work rather than fully reorganized around the newer language
direction.

This matters especially for:

- collection helper placement
- package boundaries
- ownership conventions
- which helpers belong in the preferred user-facing surface

## Highest-Priority Design Topics

If work should focus on the most language-shaping open areas rather than
cleanup, the priority order is currently:

1. macros
2. package/module depth
3. ownership ergonomics
4. enum/union story
5. higher-order functions / closures

Those are the places most likely to change the language materially rather than
just making it more polished.
