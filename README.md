# Kvist

Kvist - A Practical Lisp for Systems Programming

Kvist is a Lisp-shaped systems language with explicit ownership and
data-oriented execution, targeting readable Odin.

An experiment in writing Odin with a small Clojure/Lisp-shaped syntax: Odin in
parens, not Clojure on Odin.

Kvist is a systems programming language that combines expression-oriented
syntax and macros with explicit memory and ownership semantics. It is designed
to make low-level code more composable without introducing a hidden runtime or
abstracting away the underlying execution model.

Kvist compiles to readable Odin and relies on Odin for checking, building, and
running generated programs. The language is influenced by Lisp and Clojure in
its surface shape and metaprogramming model, but it preserves the manual,
inspectable character of systems programming.

The current language draft is [LANGUAGE.md](LANGUAGE.md). Deferred ideas that
should not drive the core implementation yet live in
[docs/FUTURE-IDEAS.md](docs/FUTURE-IDEAS.md). The current preferred iterative
development direction is documented in
[docs/HOT-RELOAD.md](docs/HOT-RELOAD.md). A longer speculative note on an
optional embedded live runtime lives in
[docs/LIVE-RUNTIME.md](docs/LIVE-RUNTIME.md), and a more workflow-focused note
on live iterative development lives in
[docs/LIVE-DEVELOPMENT.md](docs/LIVE-DEVELOPMENT.md). The current live/compiled
overlap is tracked in
[docs/LIVE-SHARED-SUBSET.md](docs/LIVE-SHARED-SUBSET.md). The larger unresolved
language areas are tracked in [docs/NEXT-STEPS.md](docs/NEXT-STEPS.md).
Ownership rules live in [docs/OWNERSHIP.md](docs/OWNERSHIP.md), and
pointer/value guidance lives in [docs/POINTERS.md](docs/POINTERS.md).
Benchmark notes live in [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

This is intentionally a source-to-source translator, not a new runtime or a
new semantic layer. The goal is:

- keep Odin semantics
- write paren-shaped source for editing comfort
- emit boring, readable `.odin`
- use `odin check` as the real validator

## Why Kvist

Odin is already a good language. Kvist does not need to justify itself by being
shorter or prettier in every case, and it should not be framed as a generic
attempt to out-syntax Odin.

The stronger case for Kvist is narrower:

- a macro-capable frontend for Odin
- structural editing and source transformation over a uniform Lisp surface
- source-level composition experiments that still lower to plain, readable Odin
- richer tooling and eval workflows without introducing a hidden runtime
- first-class native hot-reload patterns over ordinary compiled code

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

## Plan

The first milestone is a small Odin compiler/transpiler that is pleasant enough
for small pure `.kvist` files:

- one `.kvist` file emits one `.odin` file
- `.kvist` files use Kvist forms rather than mixed raw Odin top-level text
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
- no runtime library unless Odin interop absolutely needs a helper
- no semantic gap between source and generated Odin

If this grows, it should grow by covering more Odin syntax directly where the
lowering remains obvious: structs, enums, unions, pointers, slices, arrays,
`defer`, `when`, procedures, packages, and imports. It should not grow by
inventing a new language on top of Odin.

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

For file-backed `.kvist` programs, `package` is optional. Kvist will inject a
root `package main` when compiling from a path if you omit it. Raw source APIs
such as `compile_source` still require an explicit package for now.

## Usage

```sh
odin build cmd/kvist
./kvist examples/hello.kvist -o /tmp/hello.odin
odin check /tmp/hello.odin -file
```

If `-o` is omitted, generated Odin is written to stdout.
Pass `--map /tmp/hello.map` to also write a declaration-level source map:

```sh
./kvist examples/hello.kvist -o /tmp/hello.odin --map /tmp/hello.map
```

Run the executable examples through Kvist and then `odin check` with:

```sh
./scripts/check_examples.sh
```

Ownership stays explicit. Known owned-producing helpers are documented in
[docs/OWNERSHIP.md](docs/OWNERSHIP.md), and the compiler is expected to grow
conservative warnings for obvious local leaks rather than relying on hidden
automatic cleanup. The current warning pass catches discarded owned
constructors, leaked owned `let` locals, and overwritten owned locals in
obvious cases.

Run CLI and Emacs-tooling integration checks with:

```sh
./scripts/test_tooling.sh
```

Generate a scratch runner for one selected form with:

```sh
./kvist eval examples/higher-order.kvist '(reduce add 0 (new []int [1 2 3]))'
```

Inspect the generated scratch Odin without running it with:

```sh
./kvist expand examples/higher-order.kvist '(reduce add 0 (new []int [1 2 3]))'
```

Inspect frontend macro-style expansion before Odin lowering with:

```sh
./kvist macroexpand examples/data-literals.kvist '(with-allocator [allocator context.temp_allocator] (temp-buffer-len))'
```

The CLI can also invoke Odin for generated files directly:

```sh
./kvist check examples/hello.kvist
./kvist run examples/hello.kvist
```

The examples cover control flow, collection literals, procedure values,
core sequence helpers over scalars and structs, pointer/raw interop,
source-level procedure directives, named returns, flat multi-return
destructuring, struct-field destructuring, in-place mutation, and a small
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

The compiler implementation is in Odin under `src/kvist`; the CLI entry point
is `cmd/kvist/main.odin`.

Tooling notes for the post-compiler Emacs/eval work are in
[docs/TOOLING.md](docs/TOOLING.md).
The eager sequence helper direction is documented in
[docs/SEQUENCES.md](docs/SEQUENCES.md).
Ownership and deletion rules are documented in
[docs/OWNERSHIP.md](docs/OWNERSHIP.md).
Notes on carrying richer language design over from Cluck while preserving
inspectable Odin lowering are in
[docs/CLUCK-TRANSFER.md](docs/CLUCK-TRANSFER.md).
The runnable example guide is in [examples/README.md](examples/README.md).
Emacs support is in [emacs/kvist-mode.el](emacs/kvist-mode.el) and
[emacs/kvist-eval.el](emacs/kvist-eval.el).

## File Model

The intended source extension is `.kvist`.

Normal `.odin` files should remain ordinary Odin and should not require this
translator. For v0.1, `.kvist` files are pure Kvist source. Raw Odin is
available through explicit `(odin "...")` escape hatches rather than implicit
passthrough.

Example:

```clojure
(defstruct Point {
  :x int
  :y int
})

(defn add [a: int, b: int] -> int
  (+ a b))

(defn main []
  (println (add 1 2)))
```

The Odin compiler should only see generated `.odin` files. That keeps normal
Odin tooling honest while Kvist remains a source-to-source layer.

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

Odin does not have a Lisp-style stateful REPL, but `kvist` can still aim for
a useful eval-selection workflow.

The idea is to make editor tooling that takes one selected form, generates a
temporary Odin file around it, runs `odin run`, and prints the result. This is
not an interpreter and not a persistent runtime. It is source generation plus
Odin's normal compiler.

Possible levels:

- expression eval: wrap one expression in a generated `main` and print it
- file-context eval: include package imports, constants, types, and procedures
  from the current file before running the selected form
- package eval: compile the current package plus a generated scratch entry point
- watch/eval loop: keep the temp-file generation and `odin run` invocation fast
  enough to feel interactive from Emacs

The constraint is important: eval should preserve Odin semantics exactly. If a
form only works because `kvist` invented a hidden dynamic environment, that
is the wrong direction.

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
- syntax decisions around `let`, literals, proc forms, implicit returns, and
  raw Odin escape hatches

The likely architecture, if this project moves forward, is:

```text
kvist
  parser/lowering: .kvist -> .odin
  basic execution: compile/check/run/eval generated Odin

probe
  reference implementation and inspiration for richer Odin eval workflows

shared later
  package discovery, temp workspace, command runner, Emacs result display
```

The current `kvist` CLI already owns the basic eval/check/run loop so editor
tooling can call one tool. `probe` remains useful as a design reference for
larger package-aware workflows and polished editor interaction.

Do not merge the projects prematurely. `probe` is useful because it makes
ordinary Odin more interactive. Kvist is a syntax experiment. Keeping them
separate avoids contaminating a practical tool with speculative syntax work.

## Data Literals

Inline data literals are valuable for editing comfort, but they should lower to
Odin literals rather than introduce a Clojure data model.

Useful targets:

- vector/list-looking syntax for Odin array or slice literals
- map-looking syntax for Odin map literals when key/value types are explicit
- map-looking syntax for Odin struct literals when a struct type is explicit

Examples of the intended shape:

```clojure
(new []int [1 2 3])
(new map[string]int {"a" 1 "b" 2})
(Person {:name "Andreas" :age 42})
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

Use named constructors for nominal types and `new` for anonymous typed
composite literals.

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

## Odin Feature Sketches

These examples are design sketches. They are here to make the proposed surface
syntax concrete before the implementation commits too hard.

Common top-level Odin should usually stay raw because Odin's syntax is already
compact and readable:

```odin
package http

import "base:runtime"
import "core:net"
import http "../odin-http/"

Requestline_Error :: enum {
    None,
    Method_Not_Implemented,
    Not_Enough_Fields,
    Invalid_Version_Format,
}

Requestline :: struct {
    method: Method,
    target: union {
        string,
        URL,
    },
    version: Version,
}
```

The Lisp layer should focus first on procedure bodies and expression-heavy code.

Struct literals:

```clojure
Person :: struct {
    name: string,
    age: int,
}

(proc make-person [] -> Person
  (as Person {:name "Andreas"
              :age 42}))
```

Maps, dynamic arrays, compound literals, and calls:

```clojure
(proc route-get [(router ^Router) (pattern string) (handler Handler)]
  (route-add
    router
    .Get
    (as Route {:handler handler
               :pattern (strings.concatenate
                          (as []string ["^" pattern "$"])
                          router.allocator)})))
```

emits Odin-shaped code like:

```odin
route_get :: proc(router: ^Router, pattern: string, handler: Handler) {
    route_add(
        router,
        .Get,
        Route{handler = handler, pattern = strings.concatenate([]string{"^", pattern, "$"}, router.allocator)},
    )
}
```

Slices, loops, and mutation:

```clojure
(proc sum [(xs []int)] -> int
  (let [total 0]
    (for-in x xs
      (set! total (+ total x)))
    total))
```

Named and multi-value returns:

```clojure
(proc query-get [(url URL) (key string)] -> (val string, ok bool) #optional_ok
  (let [q url.query]
    (for-in entry (#force_inline query-iter (& q))
      (when (== entry.key key)
        (return entry.value true)))))
```

This is one place where explicit `return` remains useful. Implicit final return
is for the common final-expression case, not a ban on early returns.

`or_return` should probably stay as an Odin postfix operator:

```clojure
(proc decoded [(url URL) (key string) (allocator runtime.Allocator)] -> (val string, ok bool)
  (let [s (or-return (query-get url key))]
    (net.percent-decode s allocator)))
```

or, if postfix forms prove clearer:

```clojure
(let [s (query-get url key or-return)]
  ...)
```

This syntax is unsettled. The important point is that `or_return` is a core Odin
control-flow feature and should not be hidden behind a fake exception/result
abstraction.

Pointers should keep Odin's spelling:

```clojure
(proc bump [(x ^int)]
  (set! (^ x) (+ (^ x) 1)))
```

Address-of also needs a readable spelling:

```clojure
(headers-init (& r.headers) allocator)
```

Switch:

```clojure
(proc method-string [(m Method)] -> string #no_bounds_check
  (switch m
    .Get "GET"
    .Post "POST"
    .Delete "DELETE"
    :else ""))
```

Type switches and partial switches need to preserve Odin's syntax closely:

```clojure
(switch-in t rline.target
  string (io.write-string w t)
  URL    (request-path-write w t))

(#partial switch mode
  .Flush
  (do
    (assert (not rw.ended))
    (write-chunk b (slice rw.buf))))
```

Anonymous procs and callbacks:

```clojure
(http.route-get
  (& router)
  "/users/(%w+)/comments/(%d+)"
  (http.handler
    (proc [(req ^http.Request) (res ^http.Response)]
      (http.respond-plain
        res
        (fmt.tprintf "user %s, comment: %s"
                     (get req.url_params 0)
                     (get req.url_params 1))))))
```

Generated Odin should remain a normal anonymous proc passed to `http.handler`.

Attributes and directives should attach to the following form without forcing
everything into parens:

```clojure
@(private)
(proc route-add [(router ^Router) (method Method) (route Route)]
  (when (not (in? router.routes method))
    (set! (get router.routes method)
          (make [dynamic]Route router.allocator)))
  (append (& (get router.routes method)) route))

(proc headers-count [(h Headers)] -> int #force_inline
  (len h._kv))

(let [entry (#force_inline query-iter (& q))]
  ...)
```

Some attributes/directives may be better left as raw Odin until the syntax is
obvious.

`defer` and conditional defer:

```clojure
(proc header-parse [(headers ^Headers) (line string) (allocator runtime.Allocator)] -> (key string, ok bool)
  (let [value (strings.trim-space (slice line (+ colon 1)))
        key   (sanitize-key (^ headers) (slice line 0 colon))]
    (defer
      (when (not ok)
        (delete key allocator)
        (set! key "")))
    ...))
```

Conditionals as expressions when useful:

```clojure
(proc classify [(n int)] -> string
  (if (< n 0)
    "negative"
    (if (== n 0)
      "zero"
      "positive")))
```

Raw Odin should remain available directly in `.kvist`:

```odin
Foreign_Handle :: distinct rawptr

@(link_name = "foreign_call")
foreign_call :: proc(handle: Foreign_Handle) ---

(proc call [(handle Foreign_Handle)]
  (foreign_call handle))
```

## Target Forms

- `(package name)`, `(import "path")`, `(import alias "path")`
  - host imports keep Odin package paths like `"core:fmt"`
  - source-package imports can load `.kvist` packages by relative path, e.g. `(import "support/math")`
  - Kvist library packages are imported explicitly, e.g. `(import arr "kvist:arr")`, `(import str "kvist:str")`, `(import map "kvist:map")`, `(import set "kvist:set")`, `(import struct "kvist:struct")`
- `(defconst name expr)` -> `name :: expr`
- `(defconst name type expr)` -> `name: type : expr`
- `(defvar name expr)` -> `name := expr`
- `(defvar name type expr)` -> `name: type = expr`
- `(defstruct Name {:field Type ...})`
- `(defstruct Name "Doc..." {:field type ...})`
- `(defenum Name [A B C])` and `(defenum Name {:A 1 :B 2})`
- `(defenum Name "Doc..." [A B C])` and `(defenum Name "Doc..." {:A 1 :B 2})`
- `(defunion Name {:variant Type ...})`
- `(defunion Name "Doc..." {:variant Type ...})`
- `(defn name [arg: type, ...] -> return-type body...)`
  - `defn` is the preferred source-level declaration form
  - `proc` remains available for direct Odin-shaped code and proc types
  - params and returns use ordinary types like `int`, `string`, `Person`, plus Odin-style container types like `[]string`, `[dynamic]int`, `map[string]int`, and Kvist set types like `set[keyword]`
  - `println` and `doc` stay implicitly available; most library helpers come from explicit Kvist package imports
- `(defmacro name [arg ...] body...)`
  - package-local for now
  - expands over Kvist forms before ordinary parse/lowering
  - resource-scope bootstrap macros still exist alongside it during bootstrap
- top-level and statement `(odin "...")` raw escape hatches
- `(let [binding value ...] body...)` scoped expression/block, including
  multi-return and struct-field destructuring; a local binding may be followed
  by `defer` to lower to `defer delete(...)` at scope exit
- `(with-allocator [allocator expr] body...)` scoped `context.allocator`
  override with `defer` restoration
- `(with-temp-allocator [allocator] body...)` scoped `context.temp_allocator`
  override with temp allocator reset; requires `base:runtime`
- `(set! place expr)` -> `place = expr`
- `(update! target key-or-field expr)` -> direct index/key/field assignment
- final expression in a non-void proc emits `return <expr>`
- `(if test then else)`
- `(when test body...)`
- `(for test body...)`
- `(each [name collection] body...)` and `(each [key value map] body...)`
- `(do body...)`
- `(new Type literal)` typed composite literals
- `(make Type args...)` runtime/allocator-backed construction
- `(arr/empty elem-type [capacity])`, `(arr/dynamic elem-type [items...])`, `(arr/fixed elem-type [items...])`
- `(map/empty key-type value-type [capacity])`, `(map/of key-type value-type {:k v ...})`
- `(set/empty elem-type [capacity])`, `(set/of elem-type [a b c])`
- `(map f xs)`, `(filter pred xs)`, `(reduce f init xs)`, `(take n xs)`,
  `(drop n xs)`, `(take-while pred xs)`, `(drop-while pred xs)`,
  `(find pred xs)`, `(some? pred xs)`, `(every? pred xs)`, `(first xs)`,
  `(second xs)`, `(last xs)`, `(nth xs n)`, `(rest xs)`, `(empty? xs)`,
  `(remove pred xs)`, `(map-indexed f xs)`, `(keep f xs)`, `(mapcat f xs)`,
  `(concat xs ys)`, `(merge a b)`, `(into [dynamic]T xs)`, `(interpose sep xs)`,
  `(interleave xs ys)`, `(reverse xs)`, `(shuffle pick xs)`, `(sort xs)`, `(sort-by f xs)`,
  `(sort-by :field xs)`, mutating `(reverse! xs)`, `(shuffle! pick xs)`,
  `(sort! xs)`, `(sort-by! f xs)`, `(sort-by! :field xs)`, `(map! f xs)`,
  `(map-indexed! f xs)`, `(filter! pred xs)`, `(filter! :field xs)`,
  `(remove! pred xs)`, `(remove! :field xs)`, `(keep! f xs)`,
  `(into! target xs)`, `(merge! target source)`,
  `(split-at n xs)`,
  `(partition n xs)`, `(partition-all n xs)`, `(partition-by f xs)`,
  `(partition-by :field xs)`, `(zipmap keys vals)`, `(index-by f xs)`,
  `(index-by :field xs)`, `(group-by f xs)`, `(group-by :field xs)`,
  `(count-by f xs)`, `(count-by :field xs)`, `(sum-by key-f value-f xs)`,
  `(sum-by :key-field :value-field xs)`, `(frequencies xs)`, `(keys m)`,
  `(vals m)`, `(distinct xs)`, `(distinct-by f xs)`,
  and `(distinct-by :field xs)`, plus bounded producers
  `(range ...)`, `(repeat n x)`, `(repeatedly n f)`, `(iterate n f x)`,
  and `(cycle n xs)`
- file-backed dev helpers `(slurp path)` and `(spit path data)`, which require
  an explicit `core:os` import and lower directly to Odin core calls; JSON
  marshal/unmarshal stays explicit through `core:encoding/json`
- `(tap> value)` and `(tap> :label value)` for explicit stdout inspection;
  require `core:fmt` and return the tapped value
- keywords can stand in for field callbacks in those helpers, e.g. `(map :name users)`,
  `(index-by :id users)`, `(group-by :status users)`, `(count-by :status users)`,
  `(sum-by :region :amount orders)`, `(partition-by :status users)`,
  `(sort-by :age users)`, and `(filter :verified users)`
- `(:field value)`, `(get value key)`, `(get map key default)`, `(-> value steps...)`, and `(->> value steps...)`
- `(type Head Arg...)` for Odin polymorphic type instantiation in type/value positions
- `(^ ptr)` and `(& place)` as compatibility sugar; prefer `(deref ptr)` and
  `(addr place)` in user-facing code
- numbers, booleans, `nil`, and `(nil? value)`
- calls: `(foo a b)` -> `foo(a, b)`
- operators: `(+ a b)`, `(<= i 10)`, `(and a b)`, etc. emit infix

Current pragmatic Odin conveniences beyond the original core target include
`(in? collection key)`, `(contains? collection key)`, `(count xs)`, `(break)`,
`(continue)`, and directive expression wrappers like `(#force_inline call arg)`.

This is deliberately incomplete. Add only forms that map cleanly to Odin.

## Design Rules

- Prefer transparent lowering over clever abstraction.
- Keep generated Odin idiomatic enough to read and edit.
- Use Odin syntax and names for types.
- Add forms only when their Odin output is obvious.
- Prefer an explicit raw Odin escape hatch over guessing.
- Treat `odin check` as the source of truth.
