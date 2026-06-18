<div align="center">
  <img src="kvist.png" alt="Kvist logo" width="288">
</div>

# Kvist

A practical Lisp for systems programming.

Kvist is a general-purpose Lisp-shaped language for writing fast programs and
small binaries. It gives you expression-oriented syntax, macros, explicit
ownership, and direct memory management.

Kvist transpiles to readable Odin and uses Odin for checking, building, and
running programs. The syntax draws from Lisp and Clojure, but the execution
model stays close to Odin: no hidden runtime, no seq layer, no garbage-collected
object model.

Kvist is alpha software. Syntax and package APIs are still moving.

## Quickstart

Install the [Odin compiler](https://odin-lang.org/docs/install/), then build
the Kvist CLI:

```sh
odin build cmd/kvist
```

Add a main function to a `hello.kvist` file:

```clojure
(defn main []
  (println "hello from kvist"))
```

And run it:

```sh
$ ./kvist run hello.kvist
hello from kvist
```

## Why It Exists

Kvist exists because native systems programming can be made more malleable, more
interactive, and still stay close to the machine. It keeps memory, ownership,
mutation, and cleanup explicit, but gives the source the small regular shape of
a Lisp.

Lisp syntax brings a lot with very little machinery. Calls, declarations, data
literals, control flow, and macros all share the same basic structure. Code is
easy to read as data, easy to transform, and easy to extend with local language
features when a project needs them. Kvist enables this without bringing
over a dynamic runtime or garbage-collected object model.

Odin is the target because it is a beautifully practical systems language: fast
builds, efficient native code, small binaries, explicit memory, clear data
layout, direct foreign and vendor package use, and a great core library. Kvist
keeps those qualities in the generated program while making the source more
expression-oriented and macro-friendly.

Kvist comes with native hot reloading, form evaluation, macro expansion and
editor integration, providing some of the REPL-like immediacy people love from
Lisp environments, while the program still builds and runs as native code.

## Coming From...

### Odin

Kvist transpiles to Odin, and uses Odin for checking, building, and running.
Odin concepts are visible in the source: concrete types, structs, enums, unions,
pointers, slices, dynamic arrays, `defer`, `delete`, and so on.

The main difference is the source shape. Kvist writes those pieces as
expression-oriented Lisp forms, with macros and source transformations available
when a project benefits from them. Kvist code can call Odin packages freely and
`.kvist` and `.odin` files can even live in the same package, so ordinary Odin
remains available wherever it is the clearest tool.

### Clojure

Kvist borrows Clojure's surface strengths: small forms, data literals, `let`,
`when`, `cond`, threading, macros, field selectors, and a collection library
that feels familiar. The syntax is intentionally welcoming if Clojure has been
your home base.

Underneath, Kvist is very different. It is eager, mutable, native, and
ownership-oriented. There is no dynamic runtime, lazy seq abstraction,
persistent collection model, or garbage-collected object graph. `kvist:arr`
provides many familiar core sequence functions, such as `map`, `filter` and
`reduce`, but they operate on concrete arrays and slices. There are functions
that return new owned result, and also variants like `map!` that mutate existing
storage directly. Kvist also provides transforms and transducers.

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
(println "hello" 42)              ;; function call
(+ 1 2 3)                         ;; operator call
(fmt.tprintf "user-%d" (+ 41 1))  ;; nested call
(len ([]int [10 20 30]))          ;; create slice literal and call `len`
(get {"Ada" 42 "Lin" 37} "Ada" 0) ;; lookup key in map, fallback 0
```

Define constants with `def`, mutable vars with `defvar`:

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

(let [debug? true
      score 42]
  (when debug?
    (println "score" score)))
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

Loops

```clojure
(let [names ([]string ["Ada" "Lin"])]
  (for [name names]
    (println name)))

(let [names ([]string ["Ada" "Lin"])]
  (for [name i names] ; bind value and index
    (println i name)))
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

Anonymous functions use `fn`. They work well with helpers that call the
function directly:

```clojure
(arr.map (fn [x: int] -> int (+ x 1)) ([]int [1 2 3]))
```

Function parameters also use square brackets. This defines `paid-total`; it
takes `orders` as `[]Order`, returns `int`, and returns the final expression in
the body:

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
```

Return specs can be a single type or named multiple return values:

```clojure
(defn parse-count [text: string] -> [value: int, ok: bool]
  (return (len text) true))

(defn divmod [n: int, d: int] -> [q: int, r: int]
  (return (/ n d) (% n d)))
```

Multiple return values bind by position:

```clojure
(let [[value ok] (parse-count "42")]  ; destructures return values
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
(defn draw-label [target: string, text: string, x: int, y: int, color: string =
  "white"]
  ;; draw label here
  )

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
  (-> score ; Value-style update: return a changed copy.
      (update .value + score.bonus)
      (assoc .bonus 0)))

(defstruct Player {
  name: string
  score: Score
})

(defn award-bonus [player: Player] -> Player
  (-> player ; Nested field update: copy Player, then update score.value.
      (update .score.value + player.score.bonus)
      (assoc .score.bonus 0)))

(defn apply-bonus-manual [score: Score] -> Score
  (let [updated score] ; Same idea written out with a local copy.
    (mut! updated.value += updated.bonus)
    (set! updated.bonus 0)
    updated))

(defn apply-bonus! [score: ^Score]
  (mut! score^.value += score^.bonus) ; Pointer-style update: mutate the caller's value.
  (set! score^.bonus 0))

(defn main []
  (let [score (Score {value: 10 bonus: 5})
        updated (apply-bonus score)]
    (println score.value updated.value)  ;; original and copy
    (apply-bonus! &score)
    (println score.value)))              ;; mutated original
```

Use pointers in calls either positionally or with named arguments:

```clojure
(defn move! [x: ^f32 y: ^f32 dx: f32 dy: f32]
  (mut! x^ += dx)
  (mut! y^ += dy))

(move! &x &y 4 2)
(move! {x: &x y: &y dx: 4 dy: 2})
```

## Core Forms, Real Libraries

Kvist keeps the core language small. Most programs use a short set of
declarations, control forms, mutation helpers, and explicit package imports:

```clojure
; declarations
package import def defvar defstruct defenum defunion defn defmacro deftransform defsource

; local structure
let do block fn

; control flow
if when cond case while for break continue return defer

; mutation and places
set! mut! update! inc! dec! toggle! delete! assoc update get slice addr deref

; construction and interop
make type foreign-import odin attr export exports 
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
[language reference](docs/LANGUAGE.md) for the full file model.

## Whirlwind Tour

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
  (mut! counter^.value += amount))

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
(Counter {name: "frames" value: 0 status: .Pending})  ; struct literal
```

Kvist uses type-call syntax for construction and conversion: `(T value)` means
"construct or convert this value as `T`." There is no separate `new` form for
values. Struct construction is the struct type applied to a brace literal. Use
`make` for runtime allocation, such as creating an empty dynamic array with
capacity.

```clojure
(i32 count)                ;; conversion
(Counter {name: "frames" value: 0 status: .Pending})  ;; construction
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
    (defer (delete xs)) ; Explicit cleanup.
    (for [x xs]
      (println x))))
```

For local bindings, `:defer` expands to cleanup at the end of the scope:

```clojure
(import arr "kvist:arr")

(defn print-squares []
  (let [xs (arr.range 0 8) :defer ; :defer is let-binding sugar for defer/delete.
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
  (let [[value ok] (strconv.parse-int text)] ; Many APIs return value, ok.
    (if ok value 0)))

(defn parse-required [text: string] -> [value: int, ok: bool]
  (let [[value ok] (strconv.parse-int text) :or-return] ; :or-return returns named result values when ok is false.
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
  (comp ; Compile-time transform structure, not a runtime seq.
    (filter .active?)
    (map .name)))

(defn names [users: []User] -> [dynamic]string
  (into [dynamic]string active-names users)) ; into allocates a fresh owned dynamic array.

(defn active-count [users: []User] -> int
  (transduce active-names
             (fn [count: int _name: string] -> int (+ count 1))
             0
             users)) ; transduce lowers to one fused loop.
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
available at the boundary. See the [language reference](docs/LANGUAGE.md) for the
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

The CLI also includes editor-oriented symbol lookup, completion, xref, and
document lookup support. `eval`, `expand`, and `macroexpand` are there for
scratch work and for understanding generated forms.

Kvist vendors much of [Olive](https://github.com/flakstad/olive), the sister
project for live development in Odin. That machinery powers the native hot
reload and scratch evaluation workflows while still compiling through Odin. See
[Live Development](docs/LIVE-DEVELOPMENT.md) and
[Hot Reload](docs/HOT-RELOAD.md) for the details.

## Packages

Kvist ships source packages for common work:

- `kvist:arr` for dynamic array helpers
- `kvist:map` and `kvist:set` for owned collection helpers
- `kvist:str` for string helpers
- `kvist:parallel` for OS-thread tasks and parallel collection helpers
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

`kvist:parallel` wraps common `core:thread` and channel cleanup for coarse
parallel work:

```clojure
(import p "kvist:parallel")

(defn square [x: int] -> int
  (* x x))

(defn one-task [] -> int
  (let [task (p.start square 12)]
    (p.result task)))

(defn squares [xs: []int] -> [dynamic]int
  (p.map square xs))

(defn print-squares [xs: []int]
  (p.for (fn [x: int]
           (println (square x)))
         xs))

(p.detach send-email user)
```

`p.map` preserves input order and returns an owned dynamic array. `p.for` is for
side-effecting work that does not return a value. Use `p.map-with {workers: 4}`
or `p.for-with {workers: 4}` when you want to choose the worker count. See
[docs/PARALLEL.md](docs/PARALLEL.md) for the full shape.

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

- [docs/LANGUAGE.md](docs/LANGUAGE.md) - language reference
- [docs/OWNERSHIP.md](docs/OWNERSHIP.md) - ownership and deletion rules
- [docs/MACROS.md](docs/MACROS.md) - macro authoring
- [docs/SEQUENCES.md](docs/SEQUENCES.md) - collection helpers
- [docs/FUNCTIONAL-TRANSFORMS.md](docs/FUNCTIONAL-TRANSFORMS.md) - `deftransform`, `into`, `transduce`
- [docs/POINTERS.md](docs/POINTERS.md) - pointer syntax
- [docs/PARALLEL.md](docs/PARALLEL.md) - tasks and parallel collection helpers
- [docs/TOOLING.md](docs/TOOLING.md) - CLI/editor tooling
- [docs/LIVE-DEVELOPMENT.md](docs/LIVE-DEVELOPMENT.md) - scratch eval and live workflows
- [docs/HOT-RELOAD.md](docs/HOT-RELOAD.md) - native reload workflow
- [examples/README.md](examples/README.md) - example guide
