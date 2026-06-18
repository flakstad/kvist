<p align="center">
  <img src="kvist.png" alt="Kvist logo" width="288">
</p>

# Kvist

A practical Lisp for systems programming.

Kvist is a general-purpose Lisp-shaped language for writing fast programs and
small binaries. It gives you expression-oriented syntax, macros, explicit
ownership, and direct memory management.

Kvist transpiles to readable Odin and uses Odin for checking, building, and
running programs. The syntax draws from Lisp and Clojure, but the execution
model stays close to Odin: no hidden runtime, no seq layer, no garbage-collected
object model.

## Quickstart

Install the [Odin compiler](https://odin-lang.org/docs/install/), then build
the Kvist CLI:

```sh
odin build cmd/kvist -out:kvist
```

Create `hello.kvist`. All it takes is a `defn main` in a `.kvist` file:

```clojure
(defn main []
  (println "hello from kvist"))
```

Run it:

```sh
$ ./kvist run hello.kvist
hello from kvist
```

## Coming From...

### Odin

Odin is a beautifully designed systems language: concrete data, explicit
allocation, fast builds, simple packages, strong tooling, and a standard library
with a lot of practical taste. Kvist is close to Odin by design. It transpiles
to Odin, uses Odin for checking and building, and tries to expose Odin's syntax
and features directly instead of inventing parallel meanings. Types are Odin
types, `^T` is still a pointer type, slices and dynamic arrays are still
Odin-shaped, and `defer`, `delete`, foreign imports, `core:*`, `base:*`, and
`vendor:*` packages are all part of the normal workflow.

Kvist code can sit next to Odin files in the same package, and the generated
Odin is meant to be readable. The extra layer is there for expression-oriented
code, macros, and source transformations. Put another way: Kvist likes Odin a
lot; it just wants to write it as a Lisp.

### Clojure

Kvist deliberately copies Clojure's excellent Lisp syntax as far as it fits an
eager, mutable systems language: small parenthesized forms, data literals,
`let`, `when`, `cond`, threading, macros, field selectors, and a collection
library that feels familiar. The similarity is at the source level. There is no
dynamic runtime, lazy sequence layer, persistent collection model, or
garbage-collected object graph.

Values are owned by ordinary generated code, and collection helpers allocate
owned buffers unless you call a bang variant that mutates existing storage.
`kvist:arr` brings over much of the spirit of Clojure's core sequence library
with fresh-result helpers such as `arr.map` and `arr.filter`, plus mutating
helpers such as `arr.map!`, `arr.filter!`, and `arr.into!`.

## Why It Exists

Kvist is for programs that need low-level control and still benefit from a
small, regular language:

- write data-oriented code directly
- keep ownership, allocation, and deletion visible
- use macros for declarations, DSLs, generated glue, and editor-friendly source
  transformations
- inspect the generated code when performance, debugging, or interop matters
- use `check`, `run`, `eval`, and reload tooling without a separate interpreter

The generated Odin is still there when you want to inspect it.

## What It Looks Like

A slightly larger example with a struct, a typed function, a loop, and owned
data cleaned up with `:defer`:

```clojure
(defstruct Order {
  customer: string
  amount: int
  paid?: bool
})

(defn paid-total [orders: []Order] -> int
  (let [total 0]
    (for [order orders]
      (when order.paid?
        (mut! total += order.amount)))
    total))

(defn main []
  (let [orders [(Order {customer: "Ada" amount: 120 paid?: true})
                (Order {customer: "Lin" amount: 80 paid?: false})] :defer]
    (println (paid-total orders))))
```

## Reading Kvist Syntax

Kvist uses Lisp-style forms: the first item says what is happening, and the rest
are arguments. Types are written after names with `:`. Commas are optional
whitespace; the examples usually omit them.

Files can start with a package and imports. For a tiny `main` program, both are
optional unless you need named imports:

```clojure
(package main)
(import fmt "core:fmt")
(import arr "kvist:arr")

(defn main []
  (fmt.println "hello"))
```

```clojure
(println "hello" 42)          ;; function call
(+ 1 2 3)                     ;; operator call
(fmt.tprintf "user-%d" (+ id 1))  ;; nested call
(len ([]int [10 20 30]))      ;; slice literal
(get {"Ada" 42 "Lin" 37} name 0)  ;; lookup name, fallback 0
```

Names are written in the source style and mapped to Odin names when needed:

```clojure
active?     ;; active_p
push!       ;; push_bang
user.name   ;; field access
fmt.println ;; package-qualified call
```

Top-level values use `def`. Mutable top-level state uses `defvar`:

```clojure
(def default-port: int 8080)
(defvar request-count 0)

(defn bump! [] -> int
  (inc! request-count)
  request-count)
```

Local bindings use square brackets, and the body returns its final expression:

```clojure
(let [name "Ada"
      score (+ 20 22)]
  (fmt.tprintf "%s: %d" name score))
```

Use `do` when a branch or callback needs several expressions:

```clojure
(do
  (println "loading")
  (load-users))
```

Conditionals are expressions:

```clojure
(defn label [score: int] -> string
  (if (>= score 100)
    "complete"
    "in progress"))

(when debug?
  (println "score" score))
```

`cond` and `case` cover the larger branches. `:else` is a keyword marker, not a
value:

```clojure
(cond
  (< n 0) "negative"
  (= n 0) "zero"
  :else "positive")

(case status
  .Pending "waiting"
  .Running "moving"
  .Done "finished"
  :else "unknown")
```

Loops read like other forms:

```clojure
(for [name names]
  (println name))

(for [name i names]
  (println i name))
```

Typed collection literals say what kind of Odin value they produce:

```clojure
([]int [1 2 3])                  ;; slice
([3]int [1 2 3])                 ;; fixed array
(map[string]int {"ok" 200})      ;; map
([dynamic]int [1 2 3])           ;; owned dynamic array
```

Structs are declared with fields, built with type-call syntax, and read with
field access:

```clojure
(defstruct User {
  name: string
  age: int
})

(let [user (User {name: "Ada" age: 36})]
  (println user.name user.age))
```

Threading works for left-to-right data flow:

```clojure
(-> (User {name: "Ada" age: 36})
    .name
    len)
```

Anonymous functions use `fn`. Captured callbacks work with helpers that call
the function directly:

```clojure
(arr.map (fn [x: int] -> int
           (+ x 1))
         xs)
```

Function parameters also use square brackets. This defines `paid-total`; it
takes `orders` as `[]Order`, returns `int`, and returns the final expression in
the body:

```clojure
(defn paid-total [orders: []Order] -> int
  (transduce paid-amounts + 0 orders))
```

Return specs can be a single type or named multiple return values:

```clojure
(defn parse-count [text: string] -> [value: int, ok: bool]
  ...)

(defn divmod [n: int, d: int] -> [q: int, r: int]
  ...)
```

Multiple return values bind by position:

```clojure
(let [[value ok] (parse-count "42")]  ;; destructures return values
  (when ok
    (println value)))
```

The `:or-*` markers are early-exit helpers for `value, ok` style calls:

```clojure
(defn parse-required [text: string] -> [value: int, ok: bool]
  (let [[value ok] (parse-count text) :or-return]
    (return value true)))
```

Kvist then adds syntax for the systems parts. Named arguments are passed with a
map form. Any omitted argument uses its explicit default, or the type's zero
value if it has no default:

```clojure
(draw-label "hud" "READY" {x: 40 y: 24})
(draw-label "hud" {text: "READY"})  ;; x and y use their zero values
```

Pointers are for shared identity, optional values, and in-place updates. `^T`
is a pointer type, `value^` dereferences, and `&value` takes an address. The
same operations are also available as forms: `(ptr T)`, `(deref value)`, and
`(addr value)`.

```clojure
(defstruct Score {
  value: int
  bonus: int
})

(defn apply-bonus [score: Score] -> Score
  ;; Value-style update: return a changed copy.
  (let [updated score]
    (mut! updated.value += updated.bonus)
    (set! updated.bonus 0)
    updated))

(defn apply-bonus! [score: ^Score]
  ;; Pointer-style update: mutate the caller's value.
  (mut! score^.value += score^.bonus)
  (set! score^.bonus 0))

(defn main []
  (let [score (Score {value: 10 bonus: 5})]
    (apply-bonus! &score)
    (println score.value)))
```

Use pointers in calls either positionally or with named arguments:

```clojure
(defn move! [x: ^f32 y: ^f32 dx: f32 dy: f32]
  (mut! x^ += dx)
  (mut! y^ += dy))

(move! &x &y 4 2)
(move! {x: &x y: &y dx: 4 dy: 2})
```

## Small Core, Real Libraries

Kvist keeps the core language small. Most programs are built from a short set of
declarations and control forms, plus explicit package imports:

```clojure
;; declarations
package import def defvar defstruct defenum defunion
defn defmacro deftransform defsource

;; local structure
let do block fn

;; control flow
if when cond case while for break continue return defer

;; mutation and places
set! mut! update! inc! dec! toggle! delete!
get slice addr deref

;; construction and interop
type-call make type foreign-import odin attr export exports
```

More functionality lives in libraries. Shipped Kvist packages provide array,
map, set, string, HTML, test, CLI, source, and struct-of-arrays helpers.
Odin's `core:*`, `base:*`, and `vendor:*` packages can be imported directly, so
Kvist code can use Odin's standard library and vendored packages without wrapper
APIs.

`.kvist` and `.odin` files can also live side by side in one package. Kvist
compiles its source into generated Odin and builds the package with sibling Odin
files included, so direct Odin code stays available for low-level boundaries,
bindings, and cases where the target language is the clearest tool. See the
[language reference](LANGUAGE.md) for the full file model.

## Whirlwind Tour

The main pieces fit on one page.

### Data, Loops, And Mutation

Kvist has concrete structs, enums, unions, pointers, slices, dynamic arrays,
loops, mutation, and typed literals:

```clojure
(defenum Status [
  Pending
  Running
  Done
])

(defstruct Counter {
  name: string
  value: int
  status: Status
})

(defunion Event {
  tick: int
  message: string
})

(defn tick! [counter: ^Counter amount: int]
  (mut! counter.value += amount))

(defn print-values [values: []int]
  (for [value i values]
    (println i value)))
```

`set!` is plain assignment. Prefer the mutation helpers when the operation is
more specific: `mut!` for compound assignment, `inc!` and `dec!` for counters,
and `toggle!` for booleans.

```clojure
(set! counter.status .Running)  ;; plain assignment
(mut! counter.value += amount)  ;; compound assignment
(inc! frame)                    ;; counter helper
(toggle! enabled?)              ;; boolean helper
```

Typed literals make the resulting shape explicit:

```clojure
([]int [1 2 3])                            ;; slice literal
(map[string]int {"ok" 200 "missing" 404})  ;; map literal
(Counter {name: "frames" value: 0 status: .Pending})
;; ^ struct literal
```

Kvist uses type-call syntax for construction and conversion: `(T value)` means
"construct or convert this value as `T`." There is no separate `new` form for
values. Struct construction is the struct type applied to a brace literal. Use
`make` for runtime allocation, such as creating an empty dynamic array with
capacity.

```clojure
(i32 count)                ;; conversion
(Counter {...})            ;; construction
(make [dynamic]int 0 128) ;; runtime allocation
```

### Control Flow

Use `if`, `when`, `case`, `while`, and `for` as expression-oriented forms:

```clojure
(defn describe [status: Status] -> string
  (case status
    .Pending "waiting"
    .Running "moving"
    .Done "finished"
    :else "unknown"))

(defn countdown [n: int]
  (let [i n]
    (while (> i 0)
      (println i)
      (dec! i))))
```

### Ownership Is Part Of The Code

Owned dynamic arrays and maps need cleanup. Use `defer` when a local owns
memory:

```clojure
(import arr "kvist:arr")

(defn print-range []
  (let [xs (arr.range 0 8)]
    ;; Explicit cleanup.
    (defer (delete xs))
    (for [x xs]
      (println x))))
```

For local bindings, `:defer` expands to cleanup at the end of the scope:

```clojure
(import arr "kvist:arr")

(defn print-squares []
  ;; :defer is let-binding sugar for defer/delete.
  (let [xs (arr.range 0 8) :defer
        squares (arr.map (fn [x: int] -> int (* x x)) xs) :defer]
    (for [square squares]
      (println square))))
```

Use `:defer`, return the owned value, or pass it to an API that takes ownership.
There is no hidden collector cleaning up behind the scenes. See
[Ownership](docs/OWNERSHIP.md) for the full rules.

### Results Can Be Direct Too

Multiple return values bind positionally. Guard markers handle the common
"return early on failure" cases:

```clojure
(import strconv "core:strconv")

(defn parse-or-zero [text: string] -> int
  ;; Many APIs return value, ok.
  (let [[value ok] (strconv.parse-int text)]
    (if ok value 0)))

(defn parse-required [text: string] -> [value: int, ok: bool]
  ;; :or-return returns named result values when ok is false.
  (let [[value ok] (strconv.parse-int text) :or-return]
    (return value true)))
```

For the common `value, ok` shape, `when-let` and `if-let` bind and branch in one
form:

```clojure
(when-let [value ok (strconv.parse-int "42")]
  (println value))
```

For `value, err` APIs, use `when-ok` and `if-ok`:

```clojure
(import os "core:os")

(defn byte-count [path: string] -> int
  (if-ok [data err (os.read_entire_file path context.allocator)]
    (do
      (defer (delete data))  ;; owned bytes from the allocator
      (len data))
    0))
```

### Fused Collection Pipelines

Kvist supports Clojure-style transformation pipelines without requiring a seq
runtime. `deftransform`, `into`, and `transduce` lower to fused loops. See
[Functional Transforms](docs/FUNCTIONAL-TRANSFORMS.md) for the details:

```clojure
(deftransform active-names
  ;; Compile-time transform structure, not a runtime seq.
  (comp
    (filter .active?)
    (map .name)))

(defn names [users: []User] -> [dynamic]string
  ;; into allocates a fresh owned dynamic array.
  (into [dynamic]string active-names users))

(defn active-count [users: []User] -> int
  ;; transduce lowers to one fused loop.
  (transduce active-names
             (fn [count: int _name: string] -> int (+ count 1))
             0
             users))
```

When you already have a collection to mutate, use package bang helpers such as
`arr.into!`, `arr.sort-by!`, and `map.put!`.

### Macros And DSLs

Kvist macros rewrite Kvist source before normal lowering. They are useful for
removing boilerplate while keeping the generated code visible. See
[Macros](docs/MACROS.md) for the full macro model:

```clojure
(defmacro unless [condition & body]
  (quasiquote
    (if (unquote condition)
      (do)
      (do (splice body)))))
```

The HTML package uses macros for Hiccup-style HTML:

```clojure
(import html "kvist:html")

(html.render
  [div {class "toolbar"}
   [button {type "button" data-action "save"} "Save"]
   [button {type "button" data-action "cancel"} "Cancel"]])
```

### Escape Hatches

Kvist imports both Kvist source packages and Odin target packages. Raw Odin is
available at the boundary. See the [language reference](LANGUAGE.md) for the
complete form list:

```clojure
(import fmt "core:fmt")

(odin "foreign import libc \"system:c\"")
```

## Tooling

The CLI is built around the normal edit/check/run loop:

```sh
./kvist check examples/language/hello.kvist
./kvist run examples/language/hello.kvist
./kvist test examples/coverage/packages/test-package-tests.kvist
```

It also supports source-aware evaluation and expansion:

```sh
./kvist eval examples/collections/higher-order.kvist '(threaded-total)'
./kvist expand examples/collections/higher-order.kvist '(threaded-total)'
./kvist macroexpand examples/language/data-literals.kvist \
  '(with-allocator [allocator context.temp_allocator] (temp-buffer-len))'
```

There is also editor-oriented symbol lookup, completion, xref, and document
lookup support in the CLI, plus native reload tooling for programs that opt into
that workflow.

## Packages

Kvist ships source packages for common work:

- `kvist:arr` for dynamic array helpers
- `kvist:map` and `kvist:set` for owned collection helpers
- `kvist:str` for string helpers
- `kvist:html` for Hiccup-style HTML generation
- `kvist:http` for small HTTP examples
- `kvist:soa` for struct-of-arrays helpers
- `kvist:test` for package-level tests

`kvist:arr` covers common dynamic-array operations. `arr.map`, `arr.filter`,
and `arr.sort-by` return fresh owned dynamic arrays. `arr.map!`, `arr.filter!`,
`arr.sort-by!`, and `arr.into!` mutate existing storage.

```clojure
(import arr "kvist:arr")

(defn paid-users [users: []User] -> [dynamic]User
  (arr.filter .paid? users))

(defn sort-users! [users: [dynamic]User]
  (arr.sort-by! .name users))
```

Odin packages are imported directly. Here is Raylib:

```clojure
(import rl "vendor:raylib")

(defn main []
  (rl.InitWindow 800 450 "Kvist + Raylib")
  (defer (rl.CloseWindow))
  (while (not (rl.WindowShouldClose))
    (rl.BeginDrawing)
    (rl.ClearBackground rl.RAYWHITE)
    (rl.DrawText "hello from kvist" 280 210 24 rl.DARKGRAY)
    (rl.EndDrawing)))
```

## Repository Map

- `src/kvist/` - compiler implementation
- `cmd/kvist/` - CLI
- `packages/` - shipped Kvist source packages
- `examples/` - runnable examples and package coverage
- `tests/` - compiler tests
- `docs/` - focused notes for deeper topics
- `emacs/` - editor integration

## Documentation

- [LANGUAGE.md](LANGUAGE.md) - language reference
- [docs/OWNERSHIP.md](docs/OWNERSHIP.md) - ownership and deletion rules
- [docs/MACROS.md](docs/MACROS.md) - macro authoring
- [docs/SEQUENCES.md](docs/SEQUENCES.md) - collection helpers
- [docs/FUNCTIONAL-TRANSFORMS.md](docs/FUNCTIONAL-TRANSFORMS.md) - `deftransform`, `into`, `transduce`
- [docs/POINTERS.md](docs/POINTERS.md) - pointer syntax
- [docs/TOOLING.md](docs/TOOLING.md) - CLI/editor tooling
- [docs/HOT-RELOAD.md](docs/HOT-RELOAD.md) - native reload workflow
- [examples/README.md](examples/README.md) - example guide

## Alpha Status

Kvist is alpha software: syntax and package APIs are still moving, but the
compiler, source packages, examples, tests, editor commands, and reload workflow
are active. New language forms should lower to readable Odin. When syntax
changes, the repository is kept canonical rather than carrying compatibility
spellings.
