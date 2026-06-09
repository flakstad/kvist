# Functional Transforms

This note describes the initial reusable fused transform prototype.

The goal is to let reusable, fused functional transforms earn their place in
Kvist without adding a lazy sequence runtime, hidden collection protocols, or
opaque lowering.

## Motivation

Manual `each` loops are always available and should remain the escape hatch for
anything unusual. A transform pipeline is only worth adding if it provides clear
benefits over hand-written fused loops:

- reusable transformation definitions;
- direct expression of item flow without traversal boilerplate;
- compiler-owned loop mechanics for filtering, appending, reducing, and cleanup;
- fused Odin loops for common pipelines without intermediate arrays;
- strict diagnostics when the compiler cannot keep the lowering obvious.

The important distinction is that the pipeline describes per-item transforms,
while `into` and `transduce` choose the concrete execution target.

## Current Surface

Named transforms use `deftransform`:

```clojure
(deftransform paid-order-totals
  (comp
    (filter paid?)
    (map order-total)
    (filter positive?)))
```

Anonymous transforms use the same `comp` form inline:

```clojure
(into [dynamic]int
  (comp
    (filter active?)
    (map score))
  users)
```

Collection output is explicit with `into`:

```clojure
(defn paid-totals [orders: []Order] -> [dynamic]int
  (into [dynamic]int paid-order-totals orders))
```

Scalar output is explicit with `transduce`:

```clojure
(defn paid-total [orders: []Order] -> int
  (transduce paid-order-totals + 0 orders))
```

The initial transformer forms are deliberately small:

```clojure
(map f)
(filter pred)
```

Callbacks can be known one-argument functions or shallow field selectors:

```clojure
(deftransform active-ages
  (comp
    (filter .active?)
    (map .age)))
```

`keep` is not implemented yet.

## Reuse Example

The same transformation can feed a collected result or a scalar result:

```clojure
(defstruct Order {
  id: int
  status: int
  subtotal: int
  discount: int
})

(defn paid? [order: Order] -> bool
  (= order.status 2))

(defn order-total [order: Order] -> int
  (- order.subtotal order.discount))

(defn positive? [n: int] -> bool
  (> n 0))

(deftransform paid-order-totals
  (comp
    (filter paid?)
    (map order-total)
    (filter positive?)))

(defn collect-paid-totals [orders: []Order] -> [dynamic]int
  (into [dynamic]int paid-order-totals orders))

(defn sum-paid-totals [orders: []Order] -> int
  (transduce paid-order-totals + 0 orders))
```

Without a reusable transform, `collect-paid-totals` and `sum-paid-totals` would
usually duplicate the same filtering and mapping logic in two manual loops.

## Intended Lowering

`into` over a dynamic array lowers to one readable Odin loop:

```clojure
(into [dynamic]int paid-order-totals orders)
```

Rough Odin shape:

```odin
(proc(kvist_source: []Order) -> [dynamic]int {
    kvist_out := make([dynamic]int)
    for kvist_item in kvist_source {
        if paid_p(kvist_item) {
            kvist_value_1 := order_total(kvist_item)
            if positive_p(kvist_value_1) {
                append(&kvist_out, kvist_value_1)
            }
        }
    }
    return kvist_out
})(orders)
```

`transduce` lowers to the same fused item flow with an accumulator:

```clojure
(transduce paid-order-totals + 0 orders)
```

Rough Odin shape:

```odin
(proc(kvist_source: []Order, kvist_init: int) -> int {
    kvist_acc := kvist_init
    for kvist_item in kvist_source {
        if paid_p(kvist_item) {
            kvist_value_1 := order_total(kvist_item)
            if positive_p(kvist_value_1) {
                kvist_acc += kvist_value_1
            }
        }
    }
    return kvist_acc
})(orders, 0)
```

These lowerings are intentionally boring. If the generated Odin becomes hard to
inspect, the feature is drifting.

## Comparison With Manual `each`

The equivalent manual collection loop is clear, but it mixes traversal,
conditionals, temporary names, result allocation, and append placement:

```clojure
(defn collect-paid-totals-manual [orders: []Order] -> [dynamic]int
  (let [out (arr.empty int)]
    (each [order orders]
      (when (paid? order)
        (let [total (order-total order)]
          (when (positive? total)
            (arr.push! out total)))))
    out))
```

That is acceptable code. The transform version is justified only if the same
item-flow logic is reused, if allocation avoidance matters, or if the pipeline
is meaningfully easier to verify:

```clojure
(defn collect-paid-totals [orders: []Order] -> [dynamic]int
  (into [dynamic]int paid-order-totals orders))

(defn sum-paid-totals [orders: []Order] -> int
  (transduce paid-order-totals + 0 orders))
```

## Type And Ownership Rules

The first implementation is strict:

- `deftransform` is compile-time structure, not a runtime value;
- transform steps must be known forms in known positions;
- `map` and `filter` callbacks must be known one-argument functions or field
  selectors with obvious input and output types;
- `into` must name the concrete output type;
- dynamic array `into` owns the returned array, and callers delete it using the
  existing ownership conventions;
- `transduce` requires an obvious accumulator type from the initial value or an
  annotation;
- no hidden lazy seqs, iterators, dynamic dispatch, or boxed elements.

When any of these rules are not met, the compiler should reject the pipeline and
suggest the direct `each` loop fallback.

Named `deftransform` declarations are checked for basic shape immediately:
the spec must be `(comp ...)`, and each step must currently be `(map f)` or
`(filter pred)`. Callback existence, callback arity, callback types, and output
type compatibility are checked at the `into` or `transduce` use site where the
source and accumulator types are known.

## Open Questions

- Should `comp` order permanently read top-to-bottom as item flow, as implemented
  here, rather than classic mathematical composition order?
- Should `into` support `[]T` output at all, or only owned targets such as
  `[dynamic]T`, maps, and sets?
- Should `transduce` support reducer procs beyond the current `+` reducer?
- Should named transforms be allowed to reference other named transforms?
- How should source maps represent fused transform steps inside generated loops?

## Implemented Prototype Slice

The first prototype implements:

1. Parse and store top-level `deftransform` declarations.
2. Support inline and named `(comp (filter f) (map g))` transform specs.
3. Implement `(into [dynamic]T transform source)` for slices, fixed arrays, and
   dynamic arrays.
4. Implement `(transduce transform + init source)` for numeric accumulators.
5. Add one example that compares reusable transform usage to the manual `each`
   version.

Do not expand beyond this until the examples show clear reuse or correctness
benefit over manual loops.
