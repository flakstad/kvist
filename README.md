<p align="center">
  <img src="kvist.png" alt="Kvist logo" width="288">
</p>

# Kvist

A practical Lisp for systems programming.

Kvist is a Lisp-shaped language for writing explicit, data-oriented systems
code. It combines expression-oriented syntax and macros with ownership and
memory semantics that stay close to the machine.

Kvist compiles to readable Odin and uses Odin for checking, building, and
running programs. It draws from Lisp and Clojure in its source shape and
metaprogramming model, but it does not introduce a hidden runtime, seq layer, or
garbage-collected object model. The generated Odin remains the program.

## What It Looks Like

```clojure
(defstruct Order {
  customer: string
  amount: int
  paid?: bool
})

(deftransform paid-amounts
  (comp
    (filter .paid?)
    (map .amount)))

(defn paid-total [orders: []Order] -> int
  (transduce paid-amounts + 0 orders))

(defn collect-paid-amounts [orders: []Order] -> [dynamic]int
  (into [dynamic]int paid-amounts orders))

(defn print-paid [orders: []Order]
  (for [order orders]
    (when order.paid?
      (println order.customer order.amount))))
```

Kvist lowers this to ordinary Odin shapes: structs become structs, transforms
become fused loops, dynamic arrays are owned values, and `for` is a direct loop.

## Why It Exists

Kvist is an experiment in bringing Lisp's source shape to systems programming:

- macros over a small, regular syntax
- source forms that are easy to transform and structurally edit
- concise expression-oriented code for ordinary systems work
- generated Odin that remains boring and readable
- eval/check/run tooling that uses Odin rather than a hidden interpreter

The intent is not to replace Odin's model. Kvist should make some programs
easier to write while keeping the underlying code honest.

## Quickstart

Build the compiler:

```sh
odin build cmd/kvist
```

Compile a file to Odin:

```sh
./kvist compile examples/language/hello.kvist -o /tmp/hello.odin
odin check /tmp/hello.odin -file
```

Or let Kvist invoke Odin:

```sh
./kvist check examples/language/hello.kvist
./kvist run examples/language/hello.kvist
```

Evaluate one form in file/package context:

```sh
./kvist eval examples/collections/higher-order.kvist '(threaded-total)'
```

Inspect generated code for an eval form:

```sh
./kvist expand examples/collections/higher-order.kvist '(threaded-total)'
```

Inspect macro expansion before Odin lowering:

```sh
./kvist macroexpand examples/language/data-literals.kvist \
  '(with-allocator [allocator context.temp_allocator] (temp-buffer-len))'
```

Run the example sweep:

```sh
./scripts/check_examples.sh
```

Run compiler tests:

```sh
odin test tests
```

## Core Ideas

### Odin Is The Target

Kvist compiles to Odin and relies on Odin for type checking, semantics, and
native code generation. Raw Odin remains available through ordinary `.odin`
sidecars and explicit `(odin "...")` escape hatches.

### Ownership Is Explicit

Owned values must be deleted, returned, or transferred. Helpers that allocate
owned dynamic arrays say so in their docs. Local owned values commonly use
`:defer`:

```clojure
(let [xs (arr.range 0 10) :defer]
  (println (count xs)))
```

### Forms Lower Directly

Kvist forms should have obvious Odin output:

```clojure
(for [x xs]
  (println x))

(while running?
  (step! state))

(set! state.count (+ state.count 1))
```

### Macros Are Source Rewrites

Macros run before ordinary parsing and lowering. They transform Kvist forms
into Kvist forms; they are not a runtime object system.

```clojure
(defmacro unless [condition & body]
  (quasiquote
    (if (unquote condition)
      (do)
      (do (splice body)))))
```

### Packages Are Thin Source Libraries

Kvist ships small source packages such as `kvist:arr`, `kvist:map`,
`kvist:set`, `kvist:str`, `kvist:html`, `kvist:http`, `kvist:soa`, and
`kvist:test`.

```clojure
(import arr "kvist:arr")
(import html "kvist:html")

(html.render
  [div {class "panel"}
   [button "Save"]])
```

## Small Tour

Data literals are typed explicitly:

```clojure
([]int [1 2 3])
(map[string]int {"a" 1 "b" 2})
(Point {x: 10 y: 20})
```

Function values use `fn`:

```clojure
(arr.map (fn [x: int] -> int
           (+ x 1))
         xs)
```

Reusable fused transforms collect with `into` or reduce with `transduce`:

```clojure
(deftransform paid-totals
  (comp
    (filter .paid?)
    (map .amount)))

(into [dynamic]int paid-totals orders)
(transduce paid-totals + 0 orders)
```

Existing dynamic arrays are mutated with bang forms:

```clojure
(arr.into! target xs)
(arr.sort-by! .name users)
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
- [docs/HOT-RELOAD.md](docs/HOT-RELOAD.md) - reload experiments
- [examples/README.md](examples/README.md) - example guide

## Status

Kvist is experimental. The useful parts are the small compiler, readable Odin
output, source packages, macro surface, ownership checks, and eval/check/run
tooling. The language should stay small: add forms only when the generated Odin
is obvious.
