# Kvist Language Reference

Kvist is a small Lisp-shaped source language that lowers to ordinary Odin.
The source should feel familiar to Clojure programmers while staying honest
about Odin's execution model: explicit mutation, explicit allocation, direct
interop, and readable generated `.odin`.

This document describes the current language surface.

## File Model

Kvist source files use the `.kvist` extension.

```clojure
(package main)
(import fmt "core:fmt")

(defn main []
  (fmt.println "hello"))
```

`package` is optional for simple entry files and defaults to `main`.

Ordinary `.odin` files remain ordinary Odin. A Kvist package directory may
contain both `.kvist` and `.odin` files:

- imported package directories are treated as Kvist source packages when they
  contain `.kvist` files;
- sibling `.odin` files in imported source-package directories are sidecars and
  are available through the package alias;
- root `run`, `build`, `check`, and `test` commands include sibling `.odin`
  files by generating a temporary Odin file into the source directory and
  building the package directory.

Use `foreign-import` for Odin foreign imports:

```clojure
(foreign-import sqlite "system:sqlite3")
```

Raw Odin inside a `.kvist` file is explicit and should be reserved for cases
without a canonical Kvist form:

```clojure
(odin "some_odin_only_construct()")
```

## Names

Kvist maps source identifiers predictably:

- `-` becomes `_`
- `?` becomes `_p`
- `!` becomes `_bang`
- case and existing underscores are preserved

Examples:

```clojure
(defn route-add [] ...)      ; route_add
(defn active? [] ...)        ; active_p
(defn push! [] ...)          ; push_bang
runtime.Allocator            ; unchanged qualified Odin name
```

Package and field access use dot syntax:

```clojure
(fmt.println user.name)
(arr.map .name users)
cells[(idx x y)]
```

Keywords are syntax markers. They are used for forms such as `:else`, `:when`,
`:while`, `:let`, `:into`, and `:abi`. They are not field lookup functions or
general values.

## Declarations

Top-level declarations are public by default. Add `-` to make immutable
top-level declarations package-private:

```clojure
(def answer 42)
(def- internal-scale 3)

(defvar counter 0)
(defvar- private-counter 0)
```

Typed declarations use `name: Type`:

```clojure
(def default-port: int 8080)
(defvar current-state: State (State {}))
```

Untyped `def` also declares Odin type aliases when the right-hand side is a
type expression:

```clojure
(def Handle (distinct rawptr))
(def Order-Groups map[int][dynamic]Order)
```

These lower to ordinary Odin aliases:

```odin
Handle :: distinct rawptr
Order_Groups :: map[int][dynamic]Order
```

Local declarations use the same names and are scoped to the current block.
Local `defstruct`, `defenum`, and `defunion` declare block-scoped Odin types;
the declarations themselves are compile-time declarations, not runtime
allocations.

```clojure
(let []
  (def limit 10)
  (defvar total 0)
  ...)
```

Structs, enums, unions, transforms, sources, and macros use the same public /
package-private split at top level:

```clojure
(defstruct Point {
  x: f32
  y: f32
})

(defenum Status {
  Ready: 1
  Done: 2
})

(defunion Payload {
  text: string
  code: int
})

(deftransform- internal-transform
  (comp (map normalize)))

(defsource- internal-source [] -> int
  (open-source)
  :next next-source-item)

(defmacro- internal-macro [x]
  ...)
```

Functions:

```clojure
(defn distance [a: Point, b: Point] -> f32
  ...)

(defn- helper [x: int] -> int
  (+ x 1))

(defn callback :abi "c" [ctx: rawptr] -> void
  ...)

(defn tiny-helper [x: int] -> int #force_inline
  (+ x 1))
```

`fn` is the anonymous function and function-type form:

```clojure
(arr.map (fn [x: int] -> int (+ x 1)) xs)
```

Non-capturing `fn` values lower to ordinary Odin procedure values. Captured
`fn` literals lower to explicit context-passing calls when the compiler can
prove the callback does not escape. This works for known non-escaping helpers
such as `arr.map`, `arr.filter`, `arr.remove`, `arr.keep`, `arr.map-indexed`,
`arr.reduce`, `arr.take-while`, `arr.find`, `arr.some?`, `arr.min-by`,
`arr.max-by`, related indexed/bang variants, and for Kvist-defined functions
whose callback parameter is only called directly or forwarded to another
non-escaping Kvist function.

```clojure
(defn apply-one [f: (fn [x: int] -> int), x: int] -> int
  (f x))

(let [offset 10]
  (apply-one (fn [x: int] -> int
               (+ x offset))
             5))
```

Captured callbacks are not general closure values. They cannot be stored,
returned, or passed to unknown escaping APIs. Captured locals become extra proc
parameters in generated Odin, not heap closure objects.

## Imports

Imports are uniform:

```clojure
(import "core:fmt")
(import fmt "core:fmt")
(import arr "kvist:arr")
(import support "support")
```

Relative imports are resolved by inspecting the target:

- a target with `.kvist` files is a Kvist source package;
- an Odin-only target remains an ordinary Odin import;
- `kvist:*` imports load shipped Kvist packages;
- `core:*`, `base:*`, `vendor:*`, and other Odin package paths remain Odin.

There is no `:odin` import marker.

Use `(export)` to attach Odin `@(export)` to the next top-level declaration.
Use `(attr name ...)` to attach other Odin declaration attributes to the next
top-level declaration. Use `(exports [Name ...])` when raw Odin sidecar
declarations should be exposed through a Kvist source-package import.

```clojure
(export)
(defn callback :abi "c" [ctx: rawptr] -> void
  ...)

(attr private)
(defn hidden [] -> int #force_inline
  42)

(exports [Raw_Handle])
```

## Types And Constructors

The rule is: a type in call position constructs a value of that type.

```clojure
(Point {x: 1.0 y: 2.0})
(rl.Vector2 [10.0 20.0])
(f32 x)
([3]i32 [1 2 3])
(matrix[2 2]f32 [1 2 3 4])
(#simd[4]f32 [1 2 3 4])
(bit_set[Permission; u8] [.Read .Execute])
(quaternion [0.0 0.0 0.0 1.0])
```

Use `(type T)` for Odin typeid expressions:

```clojure
(linalg.identity (type matrix[2 2]f32))
```

Use `make` for runtime or allocator-backed construction where Odin uses a
procedure-like allocation operation:

```clojure
(make [dynamic]int)
```

## Blocks And Bindings

`let` is an expression/block with named bindings:

```clojure
(let [xs ([dynamic]int [1 2 3])
      total (sum xs)]
  (defer (delete xs))
  total)
```

Flat positional multi-return binding is supported:

```clojure
(let [value ok (lookup key)]
  (if ok value fallback))
```

Field destructuring is not part of the language. Use dot access or explicit
local bindings.

Owned local bindings may use the `defer` marker:

```clojure
(let [xs (arr.empty int) defer]
  ...)
```

Result bindings may use `or-return`, `or-break`, or `or-continue` guards:

```clojure
(let [[value ok] (next-item) or-return]
  value)

(while running
  (let [[item ok] (next-item) or-break]
    (println item)))
```

`or-return` requires named proc returns matching the bound names.

## Control Flow

```clojure
(if test then else)
(when test body...)
(while test body...)
(do body...)
(block body...)
(return value...)
(break)
(continue)
(defer body...)
```

`defer` emits Odin `defer`. A single expression defers that expression; multiple
forms defer a block.

Allocator scopes are explicit:

```clojure
(with-allocator [allocator expr]
  body...)

(with-temp-allocator [allocator]
  body...)
```

`with-allocator` temporarily overrides `context.allocator` and restores it with
`defer`. `with-temp-allocator` temporarily overrides `context.temp_allocator`,
resets the temp allocator at scope exit, and rejects owned temp values that
escape the scope.

Use `cond` when each branch has its own predicate:

```clojure
(cond
  (< n 0) "negative"
  (= n 0) "zero"
  :else "positive")
```

Use `case` when one subject is being classified. Value cases, grouped value
cases, and union/type payload cases all lower to ordinary Odin switches:

```clojure
(case status
  .Ready "ready"
  .Done "done"
  :else "unknown")

(case method
  [.Get .Head] "read"
  .Post "write"
  :else "other")

(case event
  (Connected _) "connected"
  (Data data) data.payload
  :else "unknown")
```

Use `each` for side-effect iteration:

```clojure
(each [x xs]
  (println x))

(each [k v lookup]
  (println k v))

(each [x i xs]
  (println i x))
```

`defsource` defines a reusable stateful producer. A source has an opener
expression, a `:next` function, and an optional `:dispose` function. The `:next`
function takes a pointer to the source state and returns named `[item: T ok:
bool]` results.

```clojure
(defsource files [root: string] -> string
  (open-files root)
  :next next-file
  :dispose dispose-files)

(each [path (files root)]
  (println path))

(into [dynamic]string
  (comp
    (filter odin-path?))
  (files root))
```

Sources lower to explicit Odin loops around the state object. They are consumed
by `each` and transform `into`. They are not general lazy sequences or
first-class source values.

Use `for` for eager data-building comprehensions:

```clojure
(for [user users :let [decade (* (/ user.age 10) 10)] :when user.active]
  :into [dynamic]Row
  (Row {name: user.name decade: decade}))

(for [user users :when user.active]
  :into map[string]User
  [user.id user])

(for [user users :when user.active]
  :into set[string]
  user.id)
```

`for` supports `:let`, `:when`, `:while`, and `:into`.

## Places And Mutation

Kvist exposes direct Odin-style places:

```clojure
value.field
xs[i]
xs[:end]
xs[start:end]
xs[start:]
```

The call-shaped equivalents are available too:

```clojure
(get value .field)
(get xs i)
(get lookup key default)
(slice xs)
(slice xs start end)
(slice xs start)
(slice xs 0 end)       ; equivalent to xs[:end]
```

Mutation forms:

```clojure
(set! place value)             ; assignment
(mut! place += value)          ; compound assignment
(update! place f args...)      ; read, apply, write
(delete! target key)           ; remove map/set key in place
```

Examples:

```clojure
(set! robot.x nx)
(mut! particles.vx[i] += ax)
(update! point.y + 4)
(update! (get lookup "a") inc)
(delete! lookup "stale")
```

Unary mutation helpers are available for common place updates:

```clojure
(inc! point.x)
(dec! xs[i])
(toggle! enabled)
(negate! velocity.x)
```

For a non-mutating copy update, bind a copy and mutate the copy:

```clojure
(let [next point]
  (update! next.y inc)
  next)
```

For struct value field replacement, `assoc` returns a modified copy:

```clojure
(assoc user.name "Ada")
(assoc user.profile.name "Ada")
```

`assoc` requires a struct field place such as `user.name` or
`user.profile.name` with an obvious struct target type. It copies the root
struct value once, assigns the selected field path on the copy, and returns the
copy. Dynamic arrays, slices, maps, and sets are not path-updated this way; use
explicit copying or mutation for those.

For value updates that depend on the previous value, bind a copy and mutate the
copy with `update!`. In a `->` pipeline, use a `.field` selector step with
`assoc`:

```clojure
(-> user
  (assoc .profile.name "Ada")
  (assoc .name "Ada"))
```

## Functional Transforms

`deftransform` defines reusable compile-time transform structure. A transform can
be collected with `into` or reduced with `transduce`; both lower to fused Odin
loops rather than intermediate arrays.

```clojure
(deftransform paid-order-totals
  (comp
    (filter paid?)
    (map order-total)
    (filter positive?)))

(into [dynamic]int paid-order-totals orders)
(transduce paid-order-totals + 0 orders)
```

The transform surface is intentionally small: `comp` supports `map` and
`filter` steps with known one-argument functions or field selectors. `into`
returns owned `[dynamic]T` arrays. `transduce` supports `+` as the reducer. See
`docs/FUNCTIONAL-TRANSFORMS.md` for limits and lowering.

## Operators

Operators lower to ordinary Odin expressions:

```clojure
(+ a b)
(* x y)
(and ok ready)
(or cached fresh)
(not done)
```

`=`, `<`, `<=`, `>`, and `>=` support two or more operands and compare adjacent
values once:

```clojure
(= a b c)      ; a == b && b == c
(< a b c d)    ; a < b && b < c && c < d
```

`!=` is intentionally binary.

Directive expression wrappers attach Odin call directives to a call:

```clojure
(#force_inline inc 41)
(#force_inline (inc x))
```

`transmute` is explicit and lowers to Odin's `transmute(T)value` form:

```clojure
(transmute []byte text)
```

`type-assert` lowers to Odin's selector assertion `value.(T)` form:

```clojure
(type-assert handler.next ^h.Handler)
```

## Pointers

Pointer types and pointer operations stay close to Odin. `^T` and `(ptr T)`
are equivalent type spellings; use whichever is clearer in context.

```clojure
(defn init [state: (ptr App-State)]
  ...)

(defn bump! [x: ^int]
  (mut! x^ += 1))

(addr value)
(& value)
(deref ptr)
ptr^
```

`addr` is the canonical readable address-of form. `&` is supported as the
compact Odin-shaped alias.

## Core Helpers

Small core helpers are auto-exposed. Prefer the bare spelling:

```clojure
(println value)
(count xs)
(get xs i)
(get lookup key default)
(slice xs start end)
(slice xs start)
(slice xs)
(empty? xs)
(contains? lookup key)
(in value xs)
(not-in value xs)
(or-else maybe fallback)
(nil? value)
(when-let [value ok (lookup-value key)]
  ...)
(if-let [value ok (lookup-value key)]
  value
  fallback)
(when-ok [data err (read-file path)]
  ...)
(if-ok [data err (read-file path)]
  data
  fallback)
(tap> value)
(doc 'println)
(-> value steps...)
(->> value steps...)
```

Collection helper packages are explicit:

```clojure
(import arr "kvist:arr")
(import map "kvist:map")
(import set "kvist:set")
(import str "kvist:str")
(import cli "kvist:cli")
(import soa "kvist:soa")
```

Examples:

```clojure
(arr.map .name users)
(arr.filter .active users)
(map.get lookup key default)
(set.contains? tags "ready")
(str.trim input)
(cli.option args "--out" "out.txt")
```

## SOA Helpers

The `kvist:soa` package provides compile-time helpers for struct-of-arrays
storage:

```clojure
(import soa "kvist:soa")

(defstruct Particle {
  x: f32
  y: f32
  vx: f32
  vy: f32
})

(let [particles (soa.make Particle 10000)]
  (defer (delete particles))
  (soa.push! particles (Particle {x: 0 y: 0 vx: 1 vy: 1}))
  (soa.update! particles i .x (+ x dx) .y (+ y dy)))
```

Whole-column helpers include:

```clojure
(soa.fill! particles .x 0.0)
(soa.scale! particles .vx damping)
(soa.axpy! particles .x dt .vx)
(soa.sum-into! total particles .mass)
(soa.dot-into! total particles .vx .vx)
```

## Macros

`defmacro` defines source macros over Kvist forms:

```clojure
(defmacro name [arg ...]
  ...)
```

Macros expand before ordinary parse/lowering. Macro code should still emit
current Kvist syntax.

## Documentation And Comments

Line comments use `//`.

Docstrings attach to declarations that support them:

```clojure
(defn parse-port
  "Parse a port number from a string."
  [s: string] -> int
  ...)
```

Use `(comment ...)` for ignored forms in source examples:

```clojure
(comment
  (parse-port "8080"))
```

## Interop Rule

Kvist should not hide Odin. Imported Odin procedures, types, constants,
directives, matrices, arrays, slices, maps, bit sets, and pointer values are
used directly where possible. Add a Kvist form only when it gives a real Lisp
editing or composition win while still lowering to obvious Odin.
