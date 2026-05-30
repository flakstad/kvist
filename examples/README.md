# Kvist Examples

The examples are meant to be read and evaled form by form from Emacs. Most
files keep `main` small and put the useful calls in a rich `(comment ...)`
block so `C-c C-e` and `C-c C-c` are practical.

## Language Basics

- `cluck-port-arrays.kvist`: Cluck reset arrays demo, showing owned dynamic arrays.
- `cluck-port-maps-sets.kvist`: Cluck reset maps/sets demo; sets are still `map[T]bool`.
- `cluck-port-multi-return.kvist`: Cluck reset multi-return demo.
- `cluck-port-packages.kvist`: Cluck reset package demo using relative `.kvist` source imports.
- `cluck-port-loops.kvist`: Cluck reset loop demos using Cluck-style `for` bindings.
- `cluck-port-records.kvist`: Cluck reset records demo via `defstruct`.
- `cluck-port-strings.kvist`: Cluck reset string demo using Odin string ops.
- `cluck-port-struct-defaults.kvist`: Cluck reset omitted-field/default demo.
- `cluck-port-docs.kvist`: Cluck reset docstring/doc lookup demo.
- `cluck-port-struct-introspection.kvist`: Cluck reset struct type lookup demo.
- `cluck-port-struct-types.kvist`: Cluck reset struct type vocabulary demo.
- `macros.kvist`: package-local `defmacro` with a real control-flow rewrite.
- `macro-dsl.kvist`: package-local declaration DSL that expands into multiple top-level forms.
- `closures.kvist`: non-capturing `fn` literals and explicit callback context.
- `hello.kvist`: package, import, struct literal, and a tiny `main`.
- `declarations.kvist`: doc comments, import aliases, constants, enums, structs.
- `defstructs.kvist`: `defstruct` docstrings, typed fields, nested structs.
- `control-flow.kvist`: `cond`, `switch`, loops, `when-let`, and `if-let`.
- `data-literals.kvist`: arrays, maps, `make`, `new`, allocator macros.
- `vars-and-state.kvist`: `defconst`, `defvar`, and explicit top-level mutation.
- `pointers-and-raw.kvist`: pointers and explicit raw Odin escape hatches.
- `pointer-vs-value.kvist`: by-value struct updates versus in-place pointer mutation.
- `unions.kvist`: union constructors and narrow union switches.
- `proc-values.kvist`: proc values and proc types.

## Sequences And Ownership

- `higher-order.kvist`: small `map`/`filter`/`reduce` style examples.
- `sequences.kvist`: sequence helpers over structs, enums, and strings.
- `sequence-helpers.kvist`: broad sequence helper coverage.
- `mutation-and-bang.kvist`: mutating helper variants such as `map!`.
- `ownership-helpers.kvist`: `with-delete`, `with-allocator`, and `with-temp-allocator`.
- `ownership-warnings.kvist`: intentionally warning-producing examples for the current ownership diagnostics.
- `update.kvist`: `update!` over arrays, maps, and defstruct fields.
- `orders-report.kvist`: a more realistic eager data pipeline.

Owned dynamic arrays, maps, allocated slices, `make`, and sequence helpers that
return new collections need local cleanup unless ownership is returned to the
caller. Prefer `let` bindings marked with trailing `defer` or plain `defer
delete(...)` for ordinary local scopes, and use `with-delete` when a scoped
cleanup wrapper reads better than repeated local cleanup lines. See
[`docs/OWNERSHIP.md`](../docs/OWNERSHIP.md) for the rule of thumb.

## Odin Core Interop

- `core-concurrency.kvist`: `core:thread`, `core:sync`, and `sync/chan`.
- `core-container-queue.kvist`: `core:container/queue` owned generic queue.
- `core-encoding-formats.kvist`: `core:encoding/csv` and `core:encoding/ini`.
- `core-os-paths.kvist`: `core:os` path, directory, file IO, owned bytes.
- `core-paths.kvist`: `core:path/slashpath` and `core:path/filepath`.
- `core-text-encoding.kvist`: `core:strings`, `strconv`, base64, hex, sha2.
- `core-math-linalg.kvist`: `core:math`, `math/rand`, and `math/linalg`.
- `core-time-slice.kvist`: `core:time` durations/buffers and `core:slice`.
- `dev-io.kvist`: explicit JSON marshal/unmarshal plus text file helpers.
- `error-handling.kvist`: bool-return vs error-return API conventions.

These examples intentionally keep Odin package names visible. Kvist should make
Odin calls nicer to write, not hide the host API or its ownership rules.

## Vendor Interop

- `vendor-stb-easy-font.kvist`: terminal-safe `vendor:stb/easy_font`.
- `vendor-raylib.kvist`: terminal-safe raylib data calls plus an explicit
  windowed demo proc.

Vendor examples should keep GUI/window/audio/network side effects out of
ordinary `main`; put those behind explicit procs in the comment block so they
are run deliberately.

## Tooling

- `tap.kvist`: `tap>` for expression-friendly inspection.
- `interop-directives.kvist`: direct Odin directives and escape hatches.

Useful commands while reading examples:

```sh
kvist check examples/core-time-slice.kvist
kvist eval examples/core-time-slice.kvist '(duration-ms)'
kvist macroexpand examples/error-handling.kvist '(if-ok [data err (os.read_entire_file "tmp/x" context.allocator)] (len data) 0)'
kvist expand examples/sequences.kvist '(age-for-ada)'
```
