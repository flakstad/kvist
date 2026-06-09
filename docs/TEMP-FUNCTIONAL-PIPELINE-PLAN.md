# Temporary Plan: Functional-Style Pipelines

This is a temporary working note for making Kvist's functional-style collection
code more pleasant without changing the core language identity.

## Position

Kvist should make expression-oriented, pipeline-shaped code natural, but it
should not become a hidden Clojure runtime over Odin. Functional composition is
the default style to encourage; allocation, mutation, and ownership remain
explicit.

## First Workstream: Pipeline Ownership And Diagnostics

The first implementation focus is the existing eager pipeline path:

- keep `->>` and collection helpers as the user-facing composition surface;
- keep threaded `let` lowering cleanup-aware for owned intermediate arrays and
  maps;
- reject unsafe expression-position pipelines clearly;
- improve diagnostics for nested owned values so the error names the producing
  form and tells users to bind/delete or return it;
- add or adjust examples so users can see the intended style.

## Near-Term Follow-Ups

After the eager pipeline path feels solid:

- improve captured callback diagnostics and expand support where lowering
  remains obvious;
- design compile-time fused/transducer-like pipelines only after real eager
  examples show the allocation pressure.

## Implemented In This Branch

- improved nested owned-result diagnostics for pipeline misuse;
- fixed imported `arr.reduce` thread-step lowering;
- added executable functional pipeline examples;
- added shallow non-mutating struct updates:
  - preferred spelling: `(assoc value.field new-value)`;
  - preferred spelling: `(update value.field f args...)`;
  - compatibility spelling: `(assoc value .field new-value)` and
    `(update value .field f args...)`.

## Non-Goals

- no lazy sequence runtime;
- no persistent collections in core;
- no general heap closure model by default;
- no implicit ownership cleanup at API boundaries;
- no polymorphic collection protocol that hides Odin data shapes.
