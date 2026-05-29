# Cluck Transfer Notes

This note captures which parts of the Cluck language design should move into
Kvist, which parts need Odin-shaped adaptation, and which parts should stay out.

The goal is not to rebuild Cluck on a different host. The goal is to carry over
as much of the settled language design as possible while preserving Kvist's core
constraint:

- generated Odin must stay readable;
- generated Odin must stay performant;
- lowering must stay inspectable;
- ownership and allocation behavior must stay explainable.

## Direction

Kvist should move beyond "Odin in parens" and become a richer Lisp-shaped
systems language targeting Odin.

That does not mean importing a hosted dynamic runtime model. It means:

- keep the Clojure/Lisp editing feel;
- keep source-level macros and compile-time expansion;
- keep concrete eager collections and loops;
- keep explicit mutation and ownership;
- add more language help at compile time where the generated Odin remains
  obvious.

The right test is not "is this Odin syntax?" The right test is:

- does this lower to boring Odin?
- can the ownership story still be read off the generated code?
- does the feature help express the program without hiding representation?

## Transfers Directly

These Cluck design choices fit Kvist well and should transfer with little or no
semantic change:

- package-by-directory with explicit imports;
- tiny core plus library split by data structure family;
- eager evaluation;
- loops as the primary style over pipelines;
- explicit mutation forms;
- explicit multi-return values and destructuring;
- fixed-shape declared types with keyword field access;
- type metadata as source data;
- compile-time validation of declaration shapes;
- compile-time checking of obvious literal construction mistakes;
- macro expansion as a frontend phase, not a runtime feature;
- docstrings attached directly to declarations.

These are all compatible with Odin as the execution model.

## Transfers With Adaptation

These parts should move, but only in Odin-shaped form.

### Arrays, Slices, And Sets

The language decisions carry over:

- dynamic arrays are central;
- fixed arrays and slices matter;
- maps and sets are real core data structures;
- loops should work directly over them;
- helper APIs should stay narrow and concrete.

But the implementation should lower to real Odin arrays, slices, dynamic arrays,
maps, and loops rather than building a hosted runtime container layer.

### Generic Access Helpers

Operations like `count`, `get`, and `slice` can still exist, but should lower
transparently to:

- `len`;
- Odin indexing;
- Odin slicing;
- Odin map lookup forms.

They should not become a universal collection abstraction that hides the target
representation.

### `update!`

`update!` is a good surface form if it lowers to ordinary Odin assignment:

```clojure
(update! xs 0 42)
(update! person :age 37)
```

should remain inspectable as ordinary element/field assignment in Odin.

### `defstruct`

Cluck's `defstruct` direction is a strong fit for Kvist.

Kvist should support a first-class declared fixed-shape type form with:

- keyword field names;
- field metadata;
- keyword field access;
- constructor syntax that stays close to Odin struct literals;
- compile-time declaration validation.

The important transfer is not the host representation. Odin already has the
representation. The transfer is the source language shape and the compile-time
checks around it.

### Type Metadata

Cluck landed on Malli-like metadata forms such as:

```clojure
:string
:int
[:arr :int]
[:set :string]
[:fixed-arr 3 :float]
```

This is worth keeping in Kvist source, at least as a source-language metadata
layer, because it is:

- readable in Lisp syntax;
- clearly not a runtime call form;
- easy to validate at compile time;
- extensible later.

Kvist can lower or translate this metadata into Odin-shaped type information
where appropriate. The important first step is to make the metadata useful for
compile-time checks, not to force it to be the emitted Odin type spelling.

## Automatic Handling: Allowed And Not Allowed

The biggest difference from Cluck is memory management.

Kvist can be more helpful than raw Odin, but only within a narrow rule:

- automatic handling is acceptable when it expands into clear Odin cleanup or
  construction patterns;
- automatic handling is not acceptable when it creates a hidden ownership
  runtime or makes allocation behavior hard to inspect.

### Acceptable

- `with-delete`-style cleanup helpers;
- allocator-scope helpers;
- compiler-inserted cleanup for obviously-owned threaded intermediates;
- default-filled struct construction when the emitted Odin remains explicit;
- compile-time rejection of obvious ownership mistakes;
- compile-time validation of literal constructor keys and values.

### Not Acceptable

- hidden garbage collection semantics;
- ambient dynamic runtime state;
- automatic lifetime management that cannot be seen in the emitted Odin;
- a broad host-style mutable runtime model;
- collection APIs that erase the distinction between arrays, slices, maps, and
  sets.

The practical line is:

Kvist may automate patterns, but it must not hide the underlying Odin model.

## What Should Not Transfer

These Cluck ideas do not fit Kvist well:

- dependence on a dynamic host runtime for core language semantics;
- runtime-extensible language behavior as a normal execution feature;
- "everything is a runtime object we can inspect and patch live";
- broad polymorphic collection semantics in the Clojure style.

Kvist can keep a useful eval workflow through scratch-file generation and Odin
execution. It should not try to simulate a hosted Scheme runtime inside the
compiled program.

## Compile-Time Direction

Kvist is a better place than Cluck for a stronger compile-time story, because
it already prefers:

- concrete collection kinds;
- narrow APIs;
- explicit ownership;
- explicit mutation;
- declared field shapes.

That should be used deliberately.

Good early compile-time checks to carry over from Cluck are:

- malformed type metadata in declarations;
- duplicate field names;
- unknown fields in literal struct construction;
- duplicate keys in literal struct construction;
- obvious literal/type mismatches;
- obvious nested constructor mismatches;
- known-field checks for keyword access when the struct type is statically
  obvious.

This is the right way for Kvist to become richer without becoming vague.

## Syntax Goal

Where possible, Kvist should take the Cluck surface syntax directly.

That includes:

- `defstruct`;
- declaration docstrings;
- metadata-as-data forms;
- explicit mutation/update forms;
- collection/package naming that stays regular and discoverable.

Where the Cluck syntax conflicts with Odin readability or the current Kvist
surface, Kvist should choose the Odin-readable lowering over host parity.

The target is not to mimic CHICKEN-hosted Cluck. The target is to keep the
language design gains and re-express them in a form that still compiles to
boring, performant Odin.

## Immediate Implications

The next useful Kvist experiments are:

1. add a `defstruct` surface over existing Odin struct lowering;
2. support source-level field metadata;
3. validate declaration metadata at compile time;
4. validate obvious literal constructor mistakes at compile time;
5. keep generated Odin plain enough that field layout, ownership, and mutation
   are still easy to audit.

If those work well, the Cluck-to-Kvist transfer is real. If they require hidden
runtime machinery or opaque lowering, then the boundary has been crossed too
far.
