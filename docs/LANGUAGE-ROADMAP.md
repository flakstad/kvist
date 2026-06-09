# Kvist Language Surface

This document summarizes the current canonical "Clojure-shaped Odin" surface.
It is a current reference, not a historical roadmap.

## Runtime Construction

`make` is the explicit surface for Odin runtime-backed storage creation:

```clojure
(make [dynamic]int 0 capacity)
(make map[string]int capacity)
(make #soa[dynamic]Particle 0 n)
```

`make` allocates or initializes runtime containers. Type-call syntax constructs
or converts values:

```clojure
(f32 x)
(Point {x: 1.0 y: 2.0})
([3]int [1 2 3])
(matrix[2 2]f32 [1.0 2.0 3.0 4.0])
(quaternion [0.0 0.0 0.0 1.0])
```

## Loops

Canonical imperative loops are `while` and `each`:

```clojure
(while condition
  body...)

(each [x xs]
  body...)

(each [x i xs]
  body...)

(each [key value lookup]
  body...)
```

`for` is not a statement loop.

## Comprehensions

`for` is an expression comprehension. It builds an owned collection:

```clojure
(for [x xs]
  (* x x))

(for [user users :let [decade (* (/ user.age 10) 10)] :when user.active]
  :into [dynamic]Row
  (Row {name: user.name decade: decade}))

(for [user users :when user.active]
  :into map[string]User
  [user.id user])

(for [user users :while (< user.age 65) :when user.active]
  :into set[string]
  user.id)
```

Supported clauses are binding clauses, `:let`, `:when`, and `:while`.
Supported explicit outputs are `[dynamic]T`, `map[K]V`, and `set[T]`. Without
`:into`, Kvist infers a dynamic array result when the yielded expression gives
enough type information.

## Places

Direct place syntax works for field, index, and slice access:

```clojure
user.name
xs[i]
xs[start:end]
xs[start:]
xs[:end]
matrix[row][col]
particles.vx[i]
```

The Lispy helpers remain available where they read better or where a macro wants
a uniform call shape:

```clojure
(get user .name)
(get xs i)
(get lookup key default)
(slice xs)
(slice xs start)
(slice xs start end)
```

## Mutation

Kvist has three canonical mutation forms:

```clojure
(set! place value)          ;; assign
(mut! place += value)       ;; compound operator mutation
(update! place f args...)   ;; read, call f, write result
```

All three accept ordinary places, including fields, indexes, nested indexes, and
SOA column indexes:

```clojure
(set! robot.x nx)
(mut! particles.vx[i] += ax)
(update! counts[event-type] + 1)
(update! robot.heading clamp-angle)
```

## Operators

Kvist uses `=` for equality and lowers it to Odin `==`. Comparisons are n-ary
and evaluate adjacent values once:

```clojure
(= a b)
(= a b c)
(< a b c)
(<= min x max)
```

`!=` remains binary.

## Declarations

Top-level immutable declarations are public by default and package-private with
the trailing `-` form:

```clojure
(def answer 42)
(def- internal-answer 42)
(defn score [x: int] -> int x)
(defn- helper [x: int] -> int x)
(defstruct Point {x: f32 y: f32})
(defstruct- Internal {value: int})
(defenum Method [Get Post])
(defunion Result {value: int err: string})
```

Mutable top-level state uses `defvar`:

```clojure
(defvar request-count 0)
(defvar live-port: int 8080)
```

Inside a block, declaration forms are compile-time block scoped where Odin
supports them:

```clojure
(def max-code: int 10)
(defstruct Payload {code: int})
(defenum Status [OK Err])
(defunion Value {payload: Payload raw: int})
```

Local declaration forms do not allocate or run at runtime by themselves. They
emit scoped Odin declarations.

## Functions And Calls

Functions use `defn` at top level and `fn` for function values:

```clojure
(defn connect [host: string, port: int = 5432] -> string
  host)

(arr.map (fn [x: int] -> int (+ x 1)) xs)
```

Known top-level `defn` calls support positional, named, and mixed named-tail
calls, plus trailing defaults:

```clojure
(connect "localhost")
(connect host: "localhost" port: 15432)
(connect "localhost" port: 15432)
```

That rewriting is intentionally limited to known top-level `defn` declarations.
It does not apply to arbitrary function values.

## Callbacks

Non-capturing function values lower to ordinary Odin proc values. Captured
callbacks lower to explicit context-passing specializations when the compiler
can prove the callback does not escape:

```clojure
(let [offset 10]
  (arr.map (fn [x: int] -> int (+ x offset)) xs))
```

This works for known non-escaping package helpers and for Kvist-defined
functions whose callback parameter is only called directly or forwarded to
another non-escaping Kvist function. Kvist does not currently create general
heap closure objects.

## SOA

`kvist:soa` wraps Odin struct-of-arrays storage while keeping the underlying
layout visible:

```clojure
(defstruct Particle {x: f32 y: f32 vx: f32 vy: f32 mass: f32})

(let [particles (soa.make Particle 10000) defer]
  (soa.push! particles (Particle {x: 0 y: 0 vx: 1 vy: 0 mass: 1}))
  (soa.update! particles i
    .vx (+ vx (* ax dt))
    .vy (+ vy (* ay dt))
    .x  (+ x (* vx dt))
    .y  (+ y (* vy dt))))
```

Whole-column helpers such as `soa.axpy!`, `soa.clamp!`, `soa.sum-into!`, and
`soa.dot-into!` take dot field selectors and expand to direct loops.

## Odin Alignment

The rule for adding or keeping surface area is directness:

- generated Odin should stay readable
- ownership should remain visible
- allocation should be explicit
- package APIs should live in package source when possible
- compiler intrinsics should be a small substrate, not the primary user-facing
  style
