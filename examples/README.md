# OdinL Examples

The examples are meant to be read and evaled form by form from Emacs. Most
files keep `main` small and put the useful calls in a rich `(comment ...)`
block so `C-c C-e` and `C-c C-c` are practical.

## Language Basics

- `hello.odinl`: package, import, struct literal, and a tiny `main`.
- `declarations.odinl`: doc comments, import aliases, constants, enums, structs.
- `control-flow.odinl`: `cond`, `switch`, loops, `when-let`, and `if-let`.
- `data-literals.odinl`: arrays, maps, `make`, `new`, allocator macros.
- `pointers-and-raw.odinl`: pointers and explicit raw Odin escape hatches.
- `unions.odinl`: union constructors and narrow union switches.
- `proc-values.odinl`: proc values and proc types.

## Sequences And Ownership

- `higher-order.odinl`: small `map`/`filter`/`reduce` style examples.
- `sequences.odinl`: sequence helpers over structs, enums, and strings.
- `sequence-helpers.odinl`: broad sequence helper coverage.
- `mutation-and-bang.odinl`: mutating helper variants such as `map!`.
- `orders-report.odinl`: a more realistic eager data pipeline.

Owned dynamic arrays, maps, allocated slices, `make`, and sequence helpers that
return new collections need local `defer delete` unless ownership is returned
to the caller. See [`docs/OWNERSHIP.md`](../docs/OWNERSHIP.md) for the rule of
thumb.

## Odin Core Interop

- `core-os-paths.odinl`: `core:os` path, directory, file IO, owned bytes.
- `core-text-encoding.odinl`: `core:strings`, `strconv`, base64, hex, sha2.
- `core-math-linalg.odinl`: `core:math`, `math/rand`, and `math/linalg`.
- `core-time-slice.odinl`: `core:time` durations/buffers and `core:slice`.
- `dev-io.odinl`: explicit JSON marshal/unmarshal plus text file helpers.
- `error-handling.odinl`: bool-return vs error-return API conventions.

These examples intentionally keep Odin package names visible. OdinL should make
Odin calls nicer to write, not hide the host API or its ownership rules.

## Vendor Interop

- `vendor-stb-easy-font.odinl`: terminal-safe `vendor:stb/easy_font`.
- `vendor-raylib.odinl`: terminal-safe raylib data calls plus an explicit
  windowed demo proc.

Vendor examples should keep GUI/window/audio/network side effects out of
ordinary `main`; put those behind explicit procs in the comment block so they
are run deliberately.

## Tooling

- `tap.odinl`: `tap>` for expression-friendly inspection.
- `interop-directives.odinl`: direct Odin directives and escape hatches.

Useful commands while reading examples:

```sh
odinl check examples/core-time-slice.odinl
odinl eval examples/core-time-slice.odinl '(duration-ms)'
odinl macroexpand examples/error-handling.odinl '(if-ok [data err (os.read_entire_file "tmp/x" context.allocator)] (len data) 0)'
odinl expand examples/sequences.odinl '(age-for-ada)'
```
