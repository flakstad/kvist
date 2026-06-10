# Kvist

Kvist - A Practical Lisp for Systems Programming

Kvist is a Lisp-shaped systems language with explicit ownership and
data-oriented execution, targeting readable Odin.

Kvist is a systems programming language that combines expression-oriented
syntax and macros with explicit memory and ownership semantics. It is designed
to make low-level code more composable without introducing a hidden runtime or
abstracting away the underlying execution model.

Kvist compiles to readable Odin and relies on Odin for checking, building, and
running generated programs. The language is influenced by Lisp and Clojure in
its surface shape and metaprogramming model, but it preserves the manual,
inspectable character of systems programming while also exploring native hot
reload and live development modes.

The current language reference is [LANGUAGE.md](LANGUAGE.md). Iterative
development and reload behavior are documented in
[docs/HOT-RELOAD.md](docs/HOT-RELOAD.md),
[docs/LIVE-DEVELOPMENT.md](docs/LIVE-DEVELOPMENT.md),
[docs/LIVE-SHARED-SUBSET.md](docs/LIVE-SHARED-SUBSET.md), and
[docs/RELOAD-APP-DESIGN.md](docs/RELOAD-APP-DESIGN.md).
Ownership rules live in [docs/OWNERSHIP.md](docs/OWNERSHIP.md), and
pointer/value guidance lives in [docs/POINTERS.md](docs/POINTERS.md).
Benchmark notes live in [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

The center of gravity today is still explicit lowering to Odin. The goal is:

- build a small Lisp-shaped source language
- keep Odin as the code generation and execution target
- emit boring, readable `.odin`
- use `odin check` as the real validator

That does not rule out optional runtime support, native hot reload, or a Kvist
live mode where those help the language and tooling story.

## Why Kvist

Odin is already a good language. Kvist does not need to justify itself by being
shorter or prettier in every case, and it should not be framed as a generic
attempt to out-syntax Odin.

The stronger case for Kvist is narrower:

- a macro-capable frontend for Odin
- structural editing and source transformation over a uniform Lisp surface
- source-level composition experiments that still lower to plain, readable Odin
- richer tooling, eval workflows, and live development support
- first-class native hot-reload patterns over ordinary compiled code
- optional live-module reload over a stable host capability surface

The important win is not "Odin, but with parens". The important win is:

- Lisp-grade metaprogramming over systems code
- structurally editable source
- explicit, inspectable lowering
- keeping Odin's ownership, layout, and execution model visible

That also sets the bar for new features. A Kvist form or helper should usually
earn its place through one of:

- better macroability
- better structural tooling
- clearer source composition
- a genuine ergonomic improvement that still lowers honestly

If a feature is only a different spelling for ordinary Odin, that is usually
not enough by itself.

## Current Shape

Kvist is a small Odin compiler/transpiler for ordinary `.kvist` packages:

- source packages are directories with `.kvist` files, optionally alongside
  ordinary `.odin` sidecar files
- top-level Kvist forms use Kvist syntax; raw Odin sidecars remain normal Odin
- forms map mechanically to Odin constructs
- generated Odin stays readable and debuggable
- Odin remains responsible for type checking, semantics, and diagnostics
- raw `(odin "...")` escape hatches are available when explicit interop is
  clearer than a dedicated surface form

The non-goals are just as important:

- no Clojure data model
- no persistent collections
- no seq abstraction
- no lazy sequences or unbounded sequence producers
- no semantic gap between source and generated Odin

The language grows by covering Odin syntax directly where the lowering remains
obvious, not by inventing a new runtime on top of Odin.

## Example

```clojure
(defn add [a: int, b: int] -> int
  (+ a b))

(defn main []
  (println (add 20 22)))
```

emits:

```odin
package main

import "core:fmt"

add :: proc(a: int, b: int) -> int {
    return a + b
}

main :: proc() {
    fmt.println(add(20, 22))
}
```

For file-backed `.kvist` programs, `package` is optional. Kvist injects a root
`package main` when compiling from a path if you omit it. Raw source APIs
such as `compile_source` still require an explicit package for now.

## Usage

```sh
odin build cmd/kvist
./kvist examples/language/hello.kvist -o /tmp/hello.odin
odin check /tmp/hello.odin -file
```

If `-o` is omitted, generated Odin is written to stdout.
When `-o` is used, absolute Odin import paths introduced by source-package
loading are rewritten relative to the destination file, so the generated output
can be moved under `/tmp`, cache directories, or checked-in build folders and
still pass `odin check`.
Pass `--map /tmp/hello.map` to also write a declaration-level source map:

```sh
./kvist examples/language/hello.kvist -o /tmp/hello.odin --map /tmp/hello.map
```

Run the executable examples through Kvist and then `odin check` with:

```sh
./scripts/check_examples.sh
```

Ownership stays explicit. Known owned-producing helpers are documented in
[docs/OWNERSHIP.md](docs/OWNERSHIP.md), and the compiler emits
conservative warnings for obvious local leaks rather than relying on hidden
automatic cleanup. The warning pass catches discarded owned
constructors, leaked owned `let` locals, and overwritten owned locals in
obvious cases.

Run CLI and Emacs-tooling integration checks with:

```sh
./scripts/test_tooling.sh
```

Generate a scratch runner for one selected form with:

```sh
./kvist eval examples/collections/higher-order.kvist '(threaded-total)'
```

Inspect the generated scratch Odin without running it with:

```sh
./kvist expand examples/collections/higher-order.kvist '(threaded-total)'
```

Inspect frontend macro-style expansion before Odin lowering with:

```sh
./kvist macroexpand examples/language/data-literals.kvist '(with-allocator [allocator context.temp_allocator] (temp-buffer-len))'
```

The CLI can also invoke Odin for generated files directly:

```sh
./kvist check examples/language/hello.kvist
./kvist run examples/language/hello.kvist
```

The examples cover control flow, collection literals, procedure values,
core sequence helpers over scalars and structs, pointer/raw interop,
source-level declaration attributes and procedure directives, named returns, flat multi-return
binding, in-place mutation, and a small
order-report workload that compares eager helpers, bang helpers, and explicit
aggregate loops.

Run the sequence/helper benchmark suite with:

```sh
./scripts/bench_sequence_helpers.sh
```

Set `BASE_REF` to compare the current compiler against a specific revision:

```sh
BASE_REF=main ./scripts/bench_sequence_helpers.sh
```

For the current-only aggregate helper comparison against direct Odin, run:

```sh
./scripts/bench_aggregate_helpers.sh
```

For the focused mutation/update comparison against direct Odin, run:

```sh
./scripts/bench_mutation_helpers.sh
```

For the focused captured-callback `map` / `map!` comparison against direct
Odin, run:

```sh
./scripts/bench_closure_helpers.sh
```

For the focused intrinsic-vs-source-backed `kvist:arr` comparison against
direct Odin, run:

```sh
./scripts/bench_source_backed_arr.sh
```

The compiler implementation is in Odin under `src/kvist`; the CLI entry point
is `cmd/kvist/main.odin`.

Tooling notes for the post-compiler Emacs/eval work are in
[docs/TOOLING.md](docs/TOOLING.md).
The eager sequence helper direction is documented in
[docs/SEQUENCES.md](docs/SEQUENCES.md).
Ownership and deletion rules are documented in
[docs/OWNERSHIP.md](docs/OWNERSHIP.md).
The runnable example guide is in [examples/README.md](examples/README.md).
Emacs support is in [emacs/kvist-mode.el](emacs/kvist-mode.el) and
[emacs/kvist-eval.el](emacs/kvist-eval.el).

## File Model

The intended source extension is `.kvist`.

Normal `.odin` files remain ordinary Odin and do not require this translator.
Kvist source packages are detected by `.kvist` files. If a source-package
directory also contains `.odin` files, those files are treated as raw Odin
sidecars. Imported package sidecars are available through the package alias.
For root `run`, `build`, `check`, and `test` commands, Kvist writes a temporary
generated `.odin` file into the source directory and asks Odin to build the
whole package directory, so sibling `.odin` files in the same package are
included. Raw snippets inside a `.kvist` file are still available through
explicit `(odin "...")` escape hatches.

Example:

```clojure
(defstruct Point {
  x: int
  y: int
})

(defn add [a: int, b: int] -> int
  (+ a b))

(defn main []
  (println (add 1 2)))
```

The Odin compiler sees generated `.odin` files plus any ordinary `.odin`
sidecars imported by the generated output. That keeps normal Odin tooling
honest while Kvist remains a source-to-source layer.

## Syntax Shape

The syntax should earn its keep. Merely moving parens around is not enough.
Forms should make editing more Lisp-like where that has real value.

`let` should be Clojure-like: a scoped expression with bindings, not just a
renamed Odin declaration.

```clojure
(let [x 20
      y 22]
  (+ x y))
```

Inside a function with a return type, the final expression should return
implicitly:

```clojure
(defn answer [] -> int
  (let [x 20
        y 22]
    (+ x y)))
```

emits:

```odin
answer :: proc() -> int {
    x := 20
    y := 22
    return x + y
}
```

## REPL-Like Development

Odin does not have a Lisp-style stateful REPL, but `kvist eval` supports a
useful eval-selection workflow. It takes one selected form, generates temporary
Odin around it with file/package context, runs `odin run`, and prints the
result. This is not an interpreter and not a persistent runtime. It is source
generation plus Odin's normal compiler.

Eval preserves Odin semantics exactly. A form works because it compiles as Odin,
not because `kvist` invented a hidden dynamic environment.

## Relationship to probe

`probe` can be a useful base for Kvist tooling, but not for the Kvist
language layer itself.

The parts that should transfer well are execution and editor workflow:

- package and project detection
- temporary workspace generation
- internal package eval by copying a package and injecting a scratch runner
- Emacs result display, inline overlays, popup buffers, and build/check/test
  commands
- generated-code inspection and compiler failure handling

The parts that should remain Kvist-specific are:

- `.kvist` parsing
- Kvist-to-Odin lowering
- source mapping from `.kvist` locations to generated `.odin` locations
- syntax decisions around `let`, literals, function forms, implicit returns, and
  raw Odin escape hatches

The current split is:

```text
kvist
  parser/lowering: .kvist -> .odin
  basic execution: compile/check/run/eval generated Odin

probe
  separate Odin eval workflow reference
```

`probe` remains separate. It is useful because it makes ordinary Odin more
interactive. Kvist owns its parser, lowering, source mapping, and CLI tooling.

## Data Literals

Inline data literals are valuable for editing comfort, but they should lower to
Odin literals rather than introduce a Clojure data model.

Useful targets:

- vector/list-looking syntax for Odin array or slice literals
- map-looking syntax for Odin map literals when key/value types are explicit
- map-looking syntax for Odin struct literals when a struct type is explicit

Examples of the intended shape:

```clojure
([]int [1 2 3])
(map[string]int {"a" 1 "b" 2})
(Person {name: "Andreas" age: 42})
```

These should lower to ordinary Odin constructs such as:

```odin
[]int{1, 2, 3}
map[string]int{"a" = 1, "b" = 2}
Person{name = "Andreas", age = 42}
```

The rule is: `[]` and `{}` are syntax for Odin literals, not universal
Clojure-style collections. Prefer explicit type ascription over guessing.

Do not use Clojure-style `^type` hints for this. In Odin, `^` already means
pointer, so using it for type hints would make the surface language harder to
read.

Use type-call syntax for both nominal and anonymous typed composite literals.

```clojure
(Person {name: "Ada" age: 36})
([3]f32 [1 2 3])
(matrix[2 2]f32 [1 0
                  0 1])
(#simd[4]f32 [1 2 3 4])
(bit_set[Permission; u8] [.Read .Execute])
(quaternion [0.0 0.0 0.0 1.0])
```

For Odin polymorphic type constructors, use `(type Head Arg...)` where Odin
would write `Head(Arg, ...)`. This is intentionally mechanical and exists for
host interop such as channels:

```clojure
(type chan.Chan int)
```

which lowers to:

```odin
chan.Chan(int)
```

## Target Forms

Top-level declarations are public by default when loaded through a Kvist source
package. Use the `-` suffixed declaration forms for package-private names.
Local declarations do not have public/private variants; they are scoped to the
current Odin block or procedure.

- `(package name)`, `(import "path")`, `(import alias "path")`
  - host imports keep Odin package paths like `"core:fmt"`
  - relative imports are resolved by inspecting the target: directories or files
    with `.kvist` source are loaded as Kvist source packages; Odin-only targets
    remain ordinary Odin imports
  - mixed source-package directories may contain `.kvist` files and `.odin`
    sidecars; imported package Kvist declarations are flattened, and raw Odin
    sidecar declarations are available through the package alias
  - root package directories may also contain sibling `.odin` sidecars; root
    `run`, `build`, `check`, and `test` commands build the package directory so
    those files participate as normal Odin package files
  - Kvist library packages are imported explicitly, e.g. `(import arr "kvist:arr")`, `(import cli "kvist:cli")`, `(import str "kvist:str")`, `(import map "kvist:map")`, `(import set "kvist:set")`, `(import soa "kvist:soa")`
  - raw Odin names re-exported from a source package can be declared with `(exports [Name ...])`
- top-level `(def name expr)` -> `name :: expr`
- top-level `(def name: type expr)` -> `name: type : expr`
- top-level `(def Name Type)` declares an Odin type alias, e.g.
  `(def Handle (distinct rawptr))` and
  `(def Order-Groups map[int][dynamic]Order)`
- top-level `(def- name expr)` and `(def- name: type expr)` package-private constants
- top-level `(defvar name expr)` -> `name := expr`
- top-level `(defvar name: type expr)` -> `name: type = expr`
- top-level `(defvar name: type)` -> `name: type`, a typed zero-value mutable
  declaration
- top-level `(defvar- name expr)` and `(defvar- name: type expr)` package-private variables
- top-level `(foreign-import alias "path")` -> `foreign import alias "path"`
- `(export)` -> attaches `@(export)` to the next top-level declaration
- `(attr name ...)` -> attaches Odin `@(name, ...)` to the next top-level declaration
- `(exports [Name ...])` -> declares additional public source-package names provided by raw Odin forms
- top-level `(defstruct Name {field: Type ...})`
- top-level `(defstruct Name "Doc..." {field: type ...})`
- top-level `(defstruct- Name {field: Type ...})` package-private struct
- top-level `(defenum Name [A B C])` and `(defenum Name {A: 1 B: 2})`
- top-level `(defenum Name "Doc..." [A B C])` and `(defenum Name "Doc..." {A: 1 B: 2})`
- top-level `(defenum- Name [A B C])` package-private enum
- top-level `(defunion Name {variant: Type ...})`
- top-level `(defunion Name "Doc..." {variant: Type ...})`
- top-level `(defunion- Name {variant: Type ...})` package-private union
- top-level `(defn name [arg: type, ...] -> return-type body...)`
- top-level `(defn name :abi "c" [arg: type, ...] -> return-type body...)`
  - procedure directives such as `#force_inline` and `#optional_ok` are written after the return spec
  - Odin polymorphic constraints are written after directives as
    `(where expr)`, e.g. `(where (intrinsics.type-is-comparable T))`
  - `defn-` is the package-private named function form
  - `fn` is the canonical source-level form for function types and anonymous function literals
  - `:abi "c"` is available for explicit foreign/native entrypoints
  - params and returns use ordinary types like `int`, `string`, `Person`, plus Odin-style container types like `[]string`, `[dynamic]int`, `map[string]int`, and Kvist set types like `set[string]`
  - `println` is the canonical print helper; `doc` and the rest of the non-syntax surface live in real Kvist packages
- top-level `(defmacro name [arg ...] body...)`
  - `defmacro-` is the package-private macro form
  - expands over Kvist forms before ordinary parse/lowering
  - resource-scope bootstrap macros still exist alongside it during bootstrap
- top-level and statement `(odin "...")` raw escape hatches
- `(let [binding value ...] body...)` scoped expression/block, including
  positional multi-return binding; a local binding may be followed
  by `defer` to lower to `defer delete(...)` at scope exit
- local `(def name expr)` and `(def name: type expr)` declare Odin constants scoped to the current block
- local `(defvar name expr)`, `(defvar name: type expr)`, and
  `(defvar name: type)` create mutable runtime locals scoped to the current block
- local `(defstruct Name ...)`, `(defenum Name ...)`, and `(defunion Name ...)` declare compile-time block-scoped Odin types; the declarations themselves do not allocate or run at runtime
- `(block body...)` -> scoped Odin block
- `(with-allocator [allocator expr] body...)` scoped `context.allocator`
  override with `defer` restoration
- `(with-temp-allocator [allocator] body...)` scoped `context.temp_allocator`
  override with temp allocator reset; requires `base:runtime`
- `(set! place expr)` -> `place = expr`
- `(mut! place += expr)` and other compound operators -> direct compound assignment
- place mutation forms:
  - `(set! place value)` assigns a value
  - `(mut! place += value)` applies a compound operator mutation
  - `(update! place f args...)` reads `place`, applies `f`, and writes the result
- `(discard expr...)` intentionally emits `_ = expr` for ignored non-owned
  values, such as callback parameters that must keep a required signature
- final expression in a non-void `defn` emits `return <expr>`
- `(if test then else)`
- `(when test body...)`
- `(while test body...)`
- `(each [name collection] body...)` and `(each [key value map] body...)`
- `(for [x xs :let [y expr] :when pred :while pred] :into [dynamic]T value)`
  builds an owned dynamic array; `:into map[K]V` expects yielded `[key value]`,
  and `:into set[T]` inserts yielded member values
- `(do body...)`
- `(Type literal)` typed composite literals, including compact Odin type heads
  such as `(matrix[2 2]f32 [1 2 3 4])`, `(#simd[4]f32 [1 2 3 4])`,
  `(bit_set[Permission; u8] [.Read .Execute])`, and `([3]f32 [1 2 3])`
  - Odin's quaternion constructor is available as `(quaternion [x y z w])`,
    lowering to `quaternion(x=x, y=y, z=z, w=w)`
- `(type Type)` typeid expressions, such as
  `(linalg.identity (type matrix[2 2]f32))`
- `(make Type args...)` runtime/allocator-backed construction, using the same
  type parser as declarations, e.g. `(make map[string][dynamic]int)`
- `(alloc Type)` and `(alloc Type allocator)` heap allocation, lowering to
  Odin `new(Type)` and `new(Type, allocator)`
- `(arr.empty elem-type [capacity])`, `(arr.dynamic elem-type [items...])`, `(arr.fixed elem-type [items...])`
- `(map.empty key-type value-type [capacity])`, `(map.of key-type value-type {"k" v ...})`
- `(set.empty elem-type [capacity])`, `(set.of elem-type [a b c])`
- `(soa.make Particle [capacity])`, `(soa.push! particles value...)`, and
  `(soa.update! particles i .field expr ...)` for dynamic SOA storage and
  direct indexed column updates
- `(soa.fill! particles .field value)`, `(soa.scale! particles .field factor)`,
  `(soa.axpy! particles .dst a .src)`, `(soa.sum-into! total particles .field)`,
  and `(soa.dot-into! total particles .a .b)` for whole-column SOA loops
- use `core:math/linalg` directly for matrix/vector operations such as
  `linalg.mul`, `linalg.transpose`, and `linalg.dot`; matrix values are ordinary
  typed constructors like `(matrix[2 2]f32 [1 2 3 4])`
- `cli.*` helpers such as `(cli.flag args "--verbose")`,
  `(cli.option args "--out" "default")`, `(cli.int-option args "--port" 8080)`,
  `(or-else (cli.command args) "help")`, `(cli.env "HOME" "")`,
  `(cli.terminal-size 80 24)`, `(cli.stdout-tty?)`, `(cli.stderr-tty?)`,
  `(cli.println ...)`, `(cli.eprintln ...)`, and `(cli.exit! code)`
- `str.*` helpers such as `(str.count s)`, `(str.get s i)`, `(str.slice s start [end])`,
  `(str.contains? s needle)`, `(str.split s sep)`, `(str.join parts sep)`,
  `(str.trim s)`, `(str.trim-prefix s prefix)`, `(str.trim-suffix s suffix)`,
  `(str.starts-with? s prefix)`, `(str.ends-with? s suffix)`,
  `(str.index-of s needle)`, `(str.last-index-of s needle)`,
  `(str.replace s old new [count])`, `(str.lower s)`, `(str.upper s)`
  - `kvist:str` is a shipped `.kvist` package. These helpers lower to direct
    Odin indexing, slicing, or `core:strings` calls.
- `set.*` helpers such as `(set.contains? s value)`, `(set.union lhs rhs)`,
  `(set.intersection lhs rhs)`, `(set.difference lhs rhs)`,
  `(set.union! target source)`, `(set.intersection! target source)`,
  `(set.difference! target source)`,
  `(set.subset? lhs rhs)`, `(set.superset? lhs rhs)`,
  `(set.disjoint? lhs rhs)`, `(set.add s value)`, `(set.add! s value)`,
  `(set.remove s value)`, `(set.remove! s value)`
  - `kvist:set` is a shipped `.kvist` package. These helpers lower to direct
    loops, direct constructors, or direct in-place mutations over `map[T]bool`.
- `map.*` helpers such as `(map.get m key [default])`, `(map.contains? m key)`,
  `(map.keys m)`, `(map.vals m)`, `(map.zip keys vals)`, `(map.assoc m key value)`,
  `(map.assoc! target key value)`, `(map.dissoc m key)`, `(map.dissoc! target key)`,
  `(map.merge lhs rhs)`, `(map.merge! target source)`
  - `kvist:map` is a shipped `.kvist` package. These helpers lower to direct
    constructors, membership checks, loops with explicit preallocation, raw
    indexing, optional-default helpers, or direct in-place mutation.
- auto-exposed core helpers such as `(count collection)`, `(get target key [default])`,
  `(slice target start [end])`, `(empty? collection)`, `(contains? collection key)`,
  and `(update! place f args...)`
  - `kvist:core` is the small auto-exposed core library.
  - Use the bare spelling in user code.
  - These helpers are defined in shipped `.kvist` source and lower through a
    small intrinsic substrate where direct Odin codegen needs it.
- `arr.*` sequence helpers such as `(arr.map f xs)`, `(arr.filter pred xs)`,
  `(arr.reduce f init xs)`, `(arr.reduce-indexed f init xs)`,
  `(arr.take n xs)`, `(arr.drop n xs)`,
  `(arr.take-while pred xs)`, `(arr.drop-while pred xs)`, `(arr.find pred xs)`,
  `(arr.find-indexed pred xs)`, `(arr.some? pred xs)`,
  `(arr.every? pred xs)`, `(arr.min-by f xs)`, `(arr.max-by f xs)`,
  `(arr.first xs)`,
  `(arr.second xs)`, `(arr.last xs)`, `(arr.nth xs n)`, `(arr.rest xs)`,
  `(arr.remove pred xs)`, `(arr.map-indexed f xs)`, `(arr.keep f xs)`,
  `(arr.mapcat f xs)`, `(arr.into [dynamic]T xs)`, `(arr.interpose sep xs)`,
  `(arr.interleave xs ys)`, `(arr.reverse xs)`, `(arr.shuffle pick xs)`,
  `(arr.sort xs)`, `(arr.sort-by f xs)`, `(arr.sort-by .field xs)`, mutating
  `(arr.reverse! xs)`, `(arr.shuffle! pick xs)`, `(arr.sort! xs)`,
  `(arr.sort-by! f xs)`, `(arr.sort-by! .field xs)`, `(arr.map! f xs)`,
  `(arr.map-indexed! f xs)`, `(arr.filter! pred xs)`, `(arr.filter! .field xs)`,
  `(arr.remove! pred xs)`, `(arr.remove! .field xs)`, `(arr.keep! f xs)`,
  `(arr.into! target xs)`, `(arr.split-at n xs)`, `(arr.partition n xs)`,
  `(arr.partition-all n xs)`, `(arr.partition-by f xs)`,
  `(arr.partition-by .field xs)`, `(arr.index-by f xs)`,
  `(arr.index-by .field xs)`, `(arr.group-by f xs)`, `(arr.group-by .field xs)`,
  `(arr.count-by f xs)`, `(arr.count-by .field xs)`,
  `(arr.sum-by key-f value-f xs)`, `(arr.sum-by .key-field .value-field xs)`,
  `(arr.frequencies xs)`, `(arr.distinct xs)`, `(arr.distinct-by f xs)`,
  `(arr.distinct-by .field xs)`, plus bounded producers `(arr.range ...)`,
  `(arr.repeat n x)`, `(arr.repeatedly n f)`, `(arr.iterate n f x)`, and
  `(arr.cycle n xs)`
  - `kvist:arr` is a shipped `.kvist` package with the broad sequence helper
    surface. Many helpers are implemented directly in package source; the rest
    lower through a small intrinsic substrate where array-family coverage,
    specialization, or allocation behavior still needs compiler support.
- `soa.*` helpers such as `(soa.fields T)`, `(soa.types T)`,
  `(soa.make T capacity)`, `(soa.push! particles particle)`, and
  `(soa.update! particles i .x (+ x dx) .y (+ y dy))`
  - `kvist:soa` owns compile-time struct metadata helpers and SOA
    convenience macros. SOA updates expand to same-named local reads plus direct
    indexed column writes.
  - Whole-column helpers such as `(soa.axpy! particles .x dt .vx)` and
    `(soa.dot-into! total particles .vx .vx)` expand to direct loops over
    `(len particles)`.
- `cli.*` helpers for command-line programs:
  `(cli.flag args name)`, `(cli.option args name fallback)`,
  `(cli.int-option args name fallback)`, `(cli.command args)`,
  `(cli.env name fallback)`, `(cli.env? name)`, `(cli.env-int name fallback)`,
  `(cli.terminal-size fallback-columns fallback-rows)`, `(cli.stdout-tty?)`,
  `(cli.stderr-tty?)`, stdout/stderr print macros, and `(cli.exit! code)`
  - `kvist:cli` keeps process/terminal APIs thin over Odin `core:os`,
    `core:terminal`, and `core:fmt`.
- map helpers `(map.merge a b)`, `(map.merge! target source)`,
  `(map.zip keys vals)`, `(map.keys m)`, and `(map.vals m)`
- file-backed dev helpers `(io.read path)` and `(io.write path data)` from
  `(import io "kvist:io")`; typed JSON file helpers from
  `(import json "kvist:json")`
- `(tap> value)` and `(tap> "label" value)` for explicit stdout inspection;
  require `core:fmt` and return the tapped value
- `value.field` reads a field directly
- `.field` is a field selector in supported callback positions. It means
  "read this field from the current element", e.g. `(arr.map .name users)`,
  `(arr.index-by .id users)`, `(arr.group-by .status users)`,
  `(arr.count-by .status users)`, `(arr.sum-by .region .amount orders)`,
  `(arr.partition-by .status users)`, `(arr.sort-by .age users)`, and
  `(arr.filter .verified users)`.
- direct attached indexing such as `cells[(idx x y)]` works in reads, `set!`,
  and `mut!`
- direct access syntax has call-shaped equivalents:
  - `value.field` <=> `(get value .field)`
  - `value[index]` <=> `(get value index)`
  - `value[start:end]` <=> `(slice value start end)`
  - `value[start:]` <=> `(slice value start)`
- `(get map key default)`, `(-> value steps...)`, and `(->> value steps...)`
- `(type Head Arg...)` for Odin polymorphic type instantiation in type/value positions
- `(transmute Type value)` -> `transmute(Type)value`
- `(type-assert value Type)` -> `value.(Type)`
- `(zero Type)` -> `Type{}` for an explicit Odin zero value
- pointer types can be written as `^T` or `(ptr T)`
- `x^` and `(deref expr)` for pointer dereference; `(addr place)` and `(& place)` for addresses
- numbers, booleans, `nil`, and `(nil? value)`
- calls: `(foo a b)` -> `foo(a, b)`; field-label brace arguments lower to
  Odin named arguments, e.g. `(foo a {timeout-ms: 50})` -> `foo(a, timeout_ms = 50)`
- operators: `(= a b)`, `(+ a b)`, `(<= i 10)`, `(and a b)`, etc. emit infix
  - `=`, `<`, `<=`, `>`, and `>=` accept two or more operands and compare
    adjacent values once, e.g. `(< a b c)` means `a < b && b < c`
  - `!=` is intentionally binary

Pragmatic Odin conveniences beyond the minimal special-form core include
`(contains? collection key)` for generic collection membership,
`(in value collection)`,
`(not-in value collection)`, `(break)`, `(continue)`, and directive expression
wrappers like `(#force_inline call arg)`. Caller intrinsics can be written
directly as `#caller_location` and `(#caller_expression expr)`.

For collection helpers, prefer explicit package names. Cross-family helpers now
live as bare names, for example `count`, `empty?`, `contains?`, and `update!`.
Other collection operations should be package-qualified under `arr.`, `map.`, `str.`, or `set.`.

This is deliberately incomplete. Add only forms that map cleanly to Odin.

## Design Rules

- Prefer transparent lowering over clever abstraction.
- Keep generated Odin idiomatic enough to read and edit.
- Use Odin syntax and names for types.
- Add forms only when their Odin output is obvious.
- Prefer an explicit raw Odin escape hatch over guessing.
- Treat `odin check` as the source of truth.
