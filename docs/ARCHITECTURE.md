# Kvist Architecture

Kvist is a small Lisp-shaped language that compiles to Odin. The compiler owns
language mechanics; ordinary language and package APIs are written in Kvist
source and use public Odin interop.

This boundary applies equally to packages shipped with Kvist, optional official
packages, and third-party packages.

## Design Gate

Compiler changes that affect source or package behavior should answer:

> Could a third-party package author reproduce this behavior using Kvist source
> and public Odin interop, without the compiler knowing the package name?

If so, the behavior belongs in source. If the source language cannot express it,
prefer the smallest package-neutral language or interop capability that makes it
expressible. Keep behavior in the compiler only when it is an irreducible
language responsibility.

In particular, do not:

- recognize public package APIs, package groups, or generated package names as
  semantic categories
- replace a package special case with a differently named special case
- add package metadata to recover semantics that belong in source
- optimize public APIs by name instead of preserving efficient generic Odin
  shapes
- use ownership annotations as the ordinary answer when ownership or borrowing
  follows from return types, allocation and slicing forms, emitted Odin shape,
  or local flow

New dependency mechanisms, search paths, ownership annotations, lowering forms,
or macro evaluation models require explicit design approval. Folder-relative
package use and the installed `kvist:*` root are described in
[PACKAGES.md](PACKAGES.md).

## Compiler Kernel

The compiler owns:

- reading, concrete syntax, source maps, analysis, emission, and import
  resolution
- declaration forms such as `package`, `import`, `odin`, `def`, `defn`,
  `defmacro`, `defiter`, and `deftransform`
- primitive control, local binding, procedure, loop, return, mutation, and
  cleanup forms
- Odin-shaped interop that requires target type knowledge
- transform analysis and direct-loop lowering
- source-form macro evaluation, quotation, quasiquotation, unquote, and splice

`deftransform` and transform use-site lowering are language machinery. The
compiler may understand transform steps and their direct loop shapes, but it
must not assign transform semantics to public package names.

Compiler-internal `kvist-prim-*` operations are justified only for this kernel.
They are not a public package authoring API.

## Source Bootstrap

The automatically referred core API is built in
`src/kvist/core/core.kvist`. It should read top to bottom like a Clojure-style
bootstrap spine: a small kernel followed by source macros and helpers in
dependency order.

Incidental implementation helpers should be private, local to the source
feature that needs them, or folded into their caller. Moving compiler helpers
into `core.kvist` without giving them a coherent source-level role does not
improve the boundary.

Shipped packages must use the same source declarations, macros, ownership
inference, and public Odin interop available to third-party packages. Public
package behavior should remain reproducible outside the compiler repository.

## Generated Odin

Package-neutral source abstractions must still produce concrete, efficient,
readable Odin. Kvist should lower ordinary source structure directly rather
than introduce runtime dispatch or hidden package-specific machinery.

