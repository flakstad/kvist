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
model stays close to Odin: no hidden runtime, no lazy sequence abstraction, and
no garbage collection.

Kvist is alpha software. Syntax and package APIs are still moving.

## Quickstart

Install the [Odin compiler](https://odin-lang.org/docs/install/), clone this
repository, and build the Kvist CLI from the repo root:

```sh
git clone https://github.com/kvist-lang/kvist.git
cd kvist
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

Kvist exists to provide a Lisp-shaped way to write native systems programs
while staying close to Odin's execution model. Memory, ownership, mutation, and
cleanup remain explicit, but the source becomes more expression-oriented,
uniform, and macro-friendly.

In Kvist, calls, declarations, data literals, control flow, and macros all use
the same basic form. That regularity makes source code easier to read,
transform, and extend, while the generated program remains straightforward
native code without a dynamic runtime or garbage collection.

Odin is the target because it is a beautifully practical systems language: fast
builds, efficient native code, small binaries, explicit memory, clear data
layout, direct foreign and vendor package use, and a great core library. Kvist
keeps those qualities in the generated program while making the source more
expression-oriented and macro-friendly.

Kvist comes with live development support, form evaluation, macro expansion and
editor integration, providing some of the REPL-like immediacy people love from
Lisp environments, while the program still builds and runs as native code.

## If You Know Odin or Clojure

Kvist is best understood as Odin in parentheses, with a Lisp-shaped surface and
some significant affordances on top. The execution model, types, ownership, and
toolchain stay close to Odin; the main additions are expression-oriented syntax,
macros, source transforms, and more interactive development support.

### If You Know Odin

Most of what matters in Kvist is already Odin. Kvist transpiles to readable
Odin, and uses Odin for checking, building, and running. The same concrete
types, structs, enums, unions, pointers, slices, dynamic arrays, `defer`,
`delete`, and package model are all still there.

What changes is the source shape and the amount of leverage you get at the
syntax level. Kvist writes Odin-like programs as regular Lisp forms, which
makes code more uniform and gives you macros and source transformations when
they are worth using. Kvist code can call Odin packages freely, and `.kvist`
and `.odin` files can live in the same package, so dropping down to ordinary
Odin is always an option.

### If You Know Clojure

Kvist borrows many of Clojure's surface strengths: small forms, data literals,
`let`, `when`, `cond`, threading, macros, field selectors, and a collection
library that should feel familiar.

Kvist is designed to feel familiar to Clojure programmers, but its semantics
are those of a native, ownership-oriented systems language. There is no dynamic
runtime, no lazy sequence abstraction, no persistent collection model, and no
garbage collection. Package `kvist:arr` provides familiar functions such as
`map`, `filter`, and `reduce`, but they operate on concrete arrays and slices.
Some functions return new owned results, and mutation-oriented variants like
`map!` update existing storage directly. Kvist also provides transforms and
transducers.

## A Quick Look

Kvist uses Lisp-style forms, but the program model stays close to Odin. Types
follow names with `:`, values are concrete, and ownership stays explicit.

This is an ordinary Kvist entry file:

```clojure
(package main)
(import fmt "core:fmt")

(defn user-label [name: string score: int] -> string
  (fmt.tprintf "%s-%d" name score))

(defn main []
  (fmt.println (user-label "ada" 42)))
```

Structs are still plain values. You can work with them as values and return
updated copies, or mutate them explicitly through pointers when that is the right tool:

```clojure
(defstruct Score {
  value: int
  bonus: int
})

;; Returning a changed copy of `score`
(defn apply-bonus [score: Score] -> Score
  (-> score
      (update .value + score.bonus)
      (assoc .bonus 0)))

;; Mutating `score` in place through a pointer
(defn apply-bonus! [score: ^Score]
  (mut! score^.value += score^.bonus)
  (set! score^.bonus 0))
```

## Ownership Is Part Of The Code

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
[docs/LANGUAGE.md](docs/LANGUAGE.md) for the ownership and allocator rules.

For the full language surface, see [docs/LANGUAGE.md](docs/LANGUAGE.md). For
more runnable examples, see [examples/README.md](examples/README.md).

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

For the full surface, see [docs/TOOLING.md](docs/TOOLING.md). For live
development workflows, see [docs/LIVE-DEVELOPMENT.md](docs/LIVE-DEVELOPMENT.md).

## Repository Map

- `src/kvist/` - compiler implementation
- `cmd/kvist/` - CLI
- `packages/` - shipped Kvist source packages
- `examples/` - runnable examples and package coverage
- `tests/` - compiler tests
- `docs/` - focused notes for deeper topics
- `emacs/` - editor integration

## Documentation

- [docs/README.md](docs/README.md) - guide to the docs set
- [docs/LANGUAGE.md](docs/LANGUAGE.md) - language reference
- [docs/MACROS.md](docs/MACROS.md) - macro authoring
- [docs/SEQUENCES.md](docs/SEQUENCES.md) - collection helpers
- [docs/PACKAGES.md](docs/PACKAGES.md) - shipped package index
- [docs/HTML.md](docs/HTML.md) - HTML rendering
- [docs/HTTP.md](docs/HTTP.md) - HTTP server/client/SSE helpers
- [docs/TESTING.md](docs/TESTING.md) - tests, assertions, fixtures, and table checks
- [docs/FUNCTIONAL-TRANSFORMS.md](docs/FUNCTIONAL-TRANSFORMS.md) - `deftransform`, `defiter`, `into`, `transduce`
- [docs/PARALLEL.md](docs/PARALLEL.md) - tasks and parallel collection helpers
- [docs/TOOLING.md](docs/TOOLING.md) - CLI/editor tooling
- [docs/LIVE-DEVELOPMENT.md](docs/LIVE-DEVELOPMENT.md) - resident reload and scratch eval workflows
- [examples/README.md](examples/README.md) - example guide
