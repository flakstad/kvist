# Core Bootstrap

## Goal

Kvist should bootstrap like a small Lisp. Odin owns a compact compiler kernel;
ordinary language and package APIs are defined in Kvist source. Bundled and
third-party packages use the same source forms and public Odin interop.

`src/kvist/core/core.kvist` should read like Clojure's `core.clj`: start from
special forms and a small justified kernel, then define macros and helpers in
dependency order. It must not become a holding area for helpers moved out of
the compiler without a coherent source-level role.

Package names are not semantic compiler concepts. `foo.bar` means member `bar`
from imported alias `foo`, whether `foo` is shipped, official, or third-party.

## Design Gate

Every compiler change in this area must answer:

> Could a third-party package author reproduce this behavior using Kvist source
> and public Odin interop, without the compiler knowing the package name?

If yes, the behavior belongs in source. If not yet, first expose the smallest
general source or interop capability. Keep behavior in the compiler only when
it is an irreducible language responsibility.

The following fail the gate:

- recognizing public package APIs, package groups, or generated package names
  as semantic categories
- replacing a package special case with a renamed special case
- adding package metadata to recover semantics that belong in source
- adding a search path, dependency mechanism, annotation, lowering form, or
  evaluator model without explicit design approval
- using `#owned` or `#borrowed` as the ordinary answer when ownership follows
  from return types, allocation/slicing forms, public interop, or local flow
- optimizing public APIs by name rather than preserving efficient generic Odin
  shapes

## Kernel Boundary

The Odin compiler owns:

- reader/CST handling, source maps, analysis, emission, and package/import
  resolution
- declaration forms such as `package`, `import`, `odin`, `def`, `defn`,
  `defmacro`, `defiter`, and `deftransform`
- primitive control/local forms such as `if`, `do`, `let`, `fn`, loops,
  returns, mutation, and cleanup
- Odin-shaped interop requiring target type knowledge
- transform mini-language analysis and direct-loop lowering
- source-form macro evaluation, quotation, quasiquotation, unquote, and splice

`deftransform` and its use-site lowering are core language machinery. The
compiler may understand transform steps, but public package names must not
become transform semantics.

Everything else starts in Kvist source or an external package repository.
`kvist-prim-*` remains compiler-internal and is justified only for true kernel
behavior; it is not a public package authoring API.

## Package Model

Packages follow the Odin filesystem model. Relative Kvist and raw Odin imports
resolve from the declaring Kvist file. The compiler may rebase a relative Odin
folder internally when generated output is written elsewhere, but the source
path remains file-relative.

There is no dependency metadata or global source search path. Applications may
populate a local `deps/` folder by copying, cloning, or using Git submodules:

```clojure
(import json "deps/json")
(import http "deps/http")
```

`kvist:*` addresses packages shipped under the active Kvist root. Resolution
is deterministic:

1. `KVIST_ROOT`, when explicitly set to a root containing `core/core.kvist`.
2. The parent of an installed `bin/kvist`.
3. `src/kvist` beside a compiler binary built at the source checkout root.

The compiler does not probe the current directory, importing repository, or
package-group inventories. `kvist root` reports the selected root.

The installed layout is:

```text
kvist-root/
  bin/kvist
  core/
  arr/
  map/
  ...
  odin/olive_reload/
```

`scripts/install.sh <destination>` builds this layout and replaces only files
managed by the Kvist installation.

## Package Boundary

Shipped language/core packages are `core`, `bit`, `arr`, `map`, `set`, `str`,
`soa`, `parallel`, `test`, and `regex`.

Shipped development support is `reload`, `hot`, and `live`, with its internal
Odin runtime under `odin/olive_reload`.

Official non-core packages are independent repositories:

- <https://github.com/kvist-lang/io>
- <https://github.com/kvist-lang/json>
- <https://github.com/kvist-lang/cli>
- <https://github.com/kvist-lang/html>
- <https://github.com/kvist-lang/http>

They are optional, are not fetched by compiler builds, and are not part of a
Kvist installation. Their tests, examples, docs, and package dependencies live
with them. The compiler repository retains only synthetic package-neutral
boundary tests.

## Current Status

- Public collection, string, IO, JSON, CLI, HTML, and HTTP APIs are not
  compiler semantic categories.
- Shipped packages use ordinary source declarations, macros, generic source
  specialization, and public Odin interop.
- Core helpers are auto-referred and used bare, matching the Clojure-style
  source model; explicit `kvist:core` imports are namespace disambiguation.
- `core.kvist` is ordered from low-level wrappers through binding/control,
  threading, case, and developer conveniences. Incidental macro helpers are
  private, local to their cluster, or folded into their caller.
- Bundled packages do not require `#owned` or `#borrowed` for ordinary package
  patterns. Ownership and borrowed views are inferred from visible generic
  source and Odin shapes, including sequential transfer into aggregate state
  and borrowed map-entry transform loops.
- Macro-time public package helper branches have been removed. The evaluator
  supports kernel/source-form capabilities rather than package APIs.
- Relative package imports and relative raw Odin imports use the same
  declaring-file rule, including nested third-party packages.
- Vendor import mappings and compiler-owned package discovery probes are absent.
- Optional official packages have the same authoring boundary as third-party
  packages and live outside the compiler repository. Compiler-repository
  examples use shipped packages or public Odin interop and do not rely on an
  optional package being present.
- Generated Odin remains concrete, direct, and readable; package abstractions
  lower through ordinary source forms rather than runtime dispatch.

## Completion Criteria

Core-bootstrap architecture is complete when all of these remain true:

- a third-party package can reproduce every ordinary bundled-package pattern
  with Kvist source and public Odin interop
- no compiler branch classifies a public package API or package group
- `core.kvist` presents a readable top-to-bottom bootstrap spine
- ordinary bundled package code contains no ownership escape-hatch annotations
- package resolution is folder-relative and deterministic
- optional official packages can be removed, cloned, or updated without a
  compiler change
- compiler tests use synthetic package-neutral fixtures, while package API
  tests live in package repositories

## Remaining Work Focus

No material core-bootstrap blocker is currently known. Future changes should
begin with an audit against the completion criteria and should not be selected
from textual leftovers alone.

The following are separate design work and require explicit approval before
implementation:

- a dependency acquisition or versioning mechanism beyond ordinary folders
- a different macro evaluation model or broader compile-time runtime
- redesign of the experimental live-module interpreter protocol
- selective source-package declaration emission to reduce generated output
- new ownership annotations or public lowering forms

Diagnostics, editor behavior, naming, and documentation maintenance are normal
follow-up work, not reasons to reopen the package/compiler semantic boundary.
