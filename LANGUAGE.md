# Kvist Language Reference

Kvist is a small Lisp-shaped source language that lowers to ordinary Odin.
The source should feel familiar to Clojure programmers while staying honest
about Odin's execution model: explicit mutation, explicit allocation, direct
interop, and readable generated `.odin`.

This document describes the current language surface. Deferred ideas belong in
`docs/FUTURE-IDEAS.md` or focused design notes, not here.

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

Raw Odin inside a `.kvist` file is explicit:

```clojure
(odin "foreign import sqlite \"system:sqlite3\"")
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

Slash package access such as `arr/map` is not canonical; use `arr.map`.

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

Structs, enums, and unions:

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
```

Functions:

```clojure
(defn distance [a: Point, b: Point] -> f32
  ...)

(defn- helper [x: int] -> int
  (+ x 1))

(defn callback :abi "c" [ctx: rawptr] -> void
  ...)
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

## Control Flow

```clojure
(if test then else)
(when test body...)
(while test body...)
(do body...)
(block body...)
```

`switch` uses `:else`:

```clojure
(switch status
  .Ready "ready"
  .Done "done"
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
xs[start:end]
xs[start:]
```

The call-shaped equivalents are available too:

```clojure
(get value .field)
(get xs i)
(slice xs start end)
(slice xs start)
```

Mutation forms:

```clojure
(set! place value)             ; assignment
(mut! place += value)          ; compound assignment
(update! place f args...)      ; read, apply, write
```

Examples:

```clojure
(set! robot.x nx)
(mut! particles.vx[i] += ax)
(update! point.y + 4)
(update! (get lookup "a") inc)
```

For a non-mutating copy update, bind a copy and mutate the copy:

```clojure
(let [next point]
  (update! next.y inc)
  next)
```

For shallow struct value updates, `assoc` and `update` return a modified copy:

```clojure
(assoc user.name "Ada")
(update user.age inc)
(update user.age + 10)

;; Compatibility spelling:
(assoc user .name "Ada")
(update user .age inc)
```

These forms currently require a shallow field place such as `user.name`, or the
compatibility pair `user .name`, with an obvious struct target type. They copy
the struct value, update one field on the copy, and return the copy. They do
not deep-copy owned fields or perform nested path updates.

In a `->` pipeline, use a shallow `.field` selector step:

```clojure
(-> user
  (update .age + 10)
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

The initial transform surface is intentionally small: `comp` supports `map` and
`filter` steps with known one-argument functions or field selectors. `into`
currently returns owned `[dynamic]T` arrays. `transduce` currently supports `+`
as the reducer. See `docs/FUNCTIONAL-TRANSFORMS.md` for limits and lowering.

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
(empty? xs)
(contains? lookup key)
(or-else maybe fallback)
(nil? value)
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
