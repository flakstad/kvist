# Kvist Language Roadmap

This is the current canonical cleanup/build list for the "Clojure-shaped Odin"
surface. New work should remove old spellings instead of keeping compatibility
aliases.

## 1. Keep `make` for Odin Runtime Construction

`make` remains the explicit surface for Odin runtime-backed storage creation:

```clojure
(make [dynamic]int 0 capacity)
(make map[string]int capacity)
(make #soa[dynamic]Particle 0 n)
```

It should not be overloaded into `(T ...)`; type-call syntax constructs or
converts values, while `make` allocates/initializes runtime containers.

## 2. Use `each` and `while` for Loops

Canonical loops are:

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

`for` is no longer a loop form.

## 3. Build `for` as Comprehension

`for` should construct a dynamic array from binding clauses:

```clojure
(for [x xs]
  (* x x))

(for [x xs
      :when (even? x)
      y ys]
  (+ x y))
```

The result type is inferred from the yielded expression where practical. When
inference is not enough, the form should support an explicit output type.

## 4. Add Indexed Field/Place Syntax

SOA and array code should support direct indexed places:

```clojure
(mut! particles.vx[i] += ax)
(set! particles.x[i] radius)
```

This should work anywhere a normal place is accepted.

## 5. Add `kvist:cli`

The standard packages should include CLI helpers for:

- flag and option parsing;
- subcommands;
- environment lookup;
- stdout/stderr and exit helpers;
- terminal size or TTY helpers where useful.

Status: `kvist:cli` provides argv flag/option helpers, first subcommand lookup,
environment lookup, stdout/stderr print macros, `exit!`, TTY checks, and
`COLUMNS`/`LINES`-backed terminal-size fallback.

## 6. Document and Tighten `(T value)`

Type-call syntax is canonical for:

- scalar conversions;
- pointer/slice/array/map conversions;
- typed composite literals;
- struct and union construction.

Diagnostics should explain arity and expected literal/value shapes clearly.

## 7. Add SOA Convenience Macros

After indexed places are solid, add macros that reduce SOA column boilerplate:

```clojure
(soa/update! particles i
  :vx (+ vx (* ax dt))
  :vy (+ vy (* ay dt))
  :x  (+ x (* vx dt))
  :y  (+ y (* vy dt)))
```

The macro should expand to explicit column access and mutation.

Status: `kvist:soa` provides `soa/make`, `soa/push!`, and
`soa/update!`. `soa/update!` binds mentioned fields to same-named locals,
then emits direct indexed column writes. Whole-column helpers such as
`soa/axpy!`, `soa/clamp!`, `soa/sum-into!`, and `soa/dot-into!` take the SOA
buffer plus keyword field names and expand to direct loops over `(len
particles)`.

## 8. Prune Redundant Collection Helpers

Typed literals make some helpers redundant:

```clojure
([3]int [1 2 3])
([dynamic]int [1 2 3])
(map[string]int {"a" 1})
```

Keep helpers only where they add real runtime behavior or readability.

## 9. Keep Odin Alignment Visible

Prefer direct, inspectable lowering and names that make the Odin concept clear.
Do not add compatibility aliases for removed forms such as `as`, `new`, `loop`,
or old loop-shaped `for`.
