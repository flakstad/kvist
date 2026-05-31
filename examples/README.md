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
- `macro-union-helpers.kvist`: recursive macro DSL that emits a union plus variant constructors.
- `macro-messages.kvist`: message-family DSL that emits payload structs, a tagged union, and constructors.
- `testing.kvist`: shipped `kvist:test` macros including `t/deftest`, `t/is`, nested `t/testing`, `t/are`, and `t/use-fixtures` with `:each` / `:once`.
- `hiccup-interpolation.kvist`: Hiccup attrs and child nodes with direct Kvist expression interpolation, including `if`, `when`, `nil` omission, and `[:<> ...]` fragments.
- `closures.kvist`: non-capturing `fn` literals plus first-cut captured callbacks for `map` / `map!`.
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
- `ownership-helpers.kvist`: `let ... defer`, `with-allocator`, and `with-temp-allocator`.
- `ownership-warnings.kvist`: intentionally warning-producing examples for the current ownership diagnostics.
- `update.kvist`: `update!` over arrays, maps, and defstruct fields.
- `orders-report.kvist`: a more realistic eager data pipeline.

Owned dynamic arrays, maps, allocated slices, `make`, and sequence helpers that
return new collections need local cleanup unless ownership is returned to the
caller. Prefer `let` bindings marked with trailing `defer` or plain `defer
delete(...)` for ordinary local scopes. See
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

## Live Runtime Demos

- `live_reload_demo`: smallest `.kvist`-hosted `kvist_live` demo; loads a
  module, reloads it, and shows state migration.
- `live_commands_demo`: long-running `.kvist` host process that reloads a tiny
  live module file while preserving command state.
- `reload_step_demo`: convenience single-file `defstate` reload workflow; `kvist dev --reload`
  generates the resident shell and reloadable module for you.
- `reload_run_demo`: general app-owned `:run` workflow with one explicit
  `reload/checkpoint!` boundary.
- `hot_reload_demo`: long-running compiled host plus a reloadable shared
  library; shows host-owned state surviving native code reload.
- `hybrid_live_demo`: `.kvist` host plus reloadable native DLL plus embedded
  `Kvist/Live` command module; shows both continuity layers in one process.

Run them from the repo root with:

```sh
./kvist run examples/live_reload_demo/main.kvist
./kvist run examples/live_commands_demo/main.kvist
./kvist dev --reload examples/reload_step_demo/main.kvist
./kvist run --reload examples/reload_run_demo/main.kvist
```

The native hot-reload demos have a compile/build workflow:

```sh
./kvist examples/hot_reload_demo/shared/package.kvist -o build/generated/hot_reload_demo/shared/package.odin
./kvist examples/hot_reload_demo/module/main.kvist -o build/generated/hot_reload_demo/module/main.odin
./kvist examples/hot_reload_demo/host/main.kvist -o build/generated/hot_reload_demo/host/main.odin
odin build build/generated/hot_reload_demo/module -build-mode:dll -out:build/hot_reload_demo/hot_demo.dylib
odin run build/generated/hot_reload_demo/host
```

```sh
./kvist examples/hybrid_live_demo/shared/package.kvist -o build/generated/hybrid_live_demo/shared/package.odin
./kvist examples/hybrid_live_demo/module/main.kvist -o build/generated/hybrid_live_demo/module/main.odin
./kvist examples/hybrid_live_demo/host/main.kvist -o build/generated/hybrid_live_demo/host/main.odin
odin build build/generated/hybrid_live_demo/module -build-mode:dll -out:build/hybrid_live_demo/hybrid_demo.dylib
odin run build/generated/hybrid_live_demo/host
```

The live commands demo watches the `.kvist` files in
`examples/live_commands_demo/live/`. Edit either `commands.kvist` or
`helpers.kvist` while the demo runs to see the process stay alive, the module
reload, the command/hook behavior change, imported helper code update, and the
command counter survive the edit. It now also shows source-defined reload
migration: change `counter-key` and `:version` in `commands.kvist` and the live
module carries the count forward itself. It also shows command args and hook
payload values flowing through the live layer rather than only zero-arg
ambient state. The host now uses the reusable `kvist_live.Module_Reloader`
helpers rather than open-coding the watched-directory loop.

The reload demos are the lowest-ceremony native path so far. They keep the
user source in one pure `.kvist` file with one `defstate` root and an explicit
trailing metadata map. `reload_run_demo` shows the general app-owned `:run`
mode with one explicit `reload/checkpoint!` cooperation point at the runtime
boundary. `reload_step_demo` shows the smaller convenience mode where Kvist
owns the outer loop. For editor integration, `kvist dev --reload ...
--rebuild --json` reports machine-readable rebuild status and `kvist dev
--reload ... --print-paths --json` prints generated paths and canonical
commands. The same sources can also be executed without the
resident reload shell via `kvist check|build|run --reload ...`. See
[`examples/reload_step_demo/README.md`](./reload_step_demo/README.md) and
[`examples/reload_run_demo/README.md`](./reload_run_demo/README.md).

The native hot-reload demo watches the shared library at
`build/hot_reload_demo/hot_demo.dylib`. Edit
`examples/hot_reload_demo/module/main.kvist`, recompile that file to generated
Odin, rebuild only the module shared library, and the running host reloads it
in place while preserving the host state struct. The demo sources themselves
are now pure `.kvist`, using
`(import hot "kvist:hot")` plus `(hot/defmodule ...)` for the standard native
module contract and `(import ... :odin "...")` for the implementation
packages. The host now uses the reusable `kvist_hot.Reloader` helpers rather
than open-coding the watch loop, with the higher-level host path
`new_reloader(...)`, `load_initial_module(...)`, and
`reload_module_if_source_changed(...)`. See
[`examples/hot_reload_demo/README.md`](./hot_reload_demo/README.md) for the
full workflow.

The hybrid demo extends that same native pattern by embedding a `kvist_live`
runtime beside it. Edit `examples/hybrid_live_demo/module/main.kvist` and
rebuild only the DLL to exercise native hot reload, or edit
`examples/hybrid_live_demo/live/*.kvist` to reload the reflective command layer
from source. See
[`examples/hybrid_live_demo/README.md`](./hybrid_live_demo/README.md) for the
combined workflow. The live host side now also uses the higher-level
`kvist_live` helper path:
`new_module_reloader(...)`, `load_initial_module(...)`, and
`reload_module_if_source_changed(...)`. The live module source now uses the
shipped `kvist:live` package too:
`(import live "kvist:live")`, `(live/defmodule ...)`,
`live/defcommand`, and `live/defhook`.

Useful commands while reading examples:

```sh
kvist check examples/core-time-slice.kvist
kvist eval examples/core-time-slice.kvist '(duration-ms)'
kvist macroexpand examples/error-handling.kvist '(if-ok [data err (os.read_entire_file "tmp/x" context.allocator)] (len data) 0)'
kvist expand examples/sequences.kvist '(age-for-ada)'
```
