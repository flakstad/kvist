# Functional Transforms

This document describes the current fused-transform surface: reusable streaming
pipelines that lower to direct Odin loops. Use them when the item flow is clear
and you want fewer hand-written traversal loops.

## When To Use Them

Manual `for` loops are always available and remain the escape hatch for
anything unusual. A transform pipeline is only worth adding if it provides clear
benefits over hand-written fused loops:

- reusable transformation definitions
- direct expression of item flow without traversal boilerplate
- compiler-owned loop mechanics for filtering, appending, reducing, and cleanup
- fused Odin loops for common pipelines without intermediate arrays
- strict diagnostics when the compiler cannot keep the lowering obvious

The important distinction is that the pipeline describes per-item transforms,
while `into` and `transduce` choose the concrete execution target.

If a transform makes the code harder to read, use a direct `for` loop instead.

## Current Surface

Named transforms use `deftransform`:

```clojure
(deftransform paid-order-totals
  (filter paid?)
  (map order-total)
  (filter positive?))
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

`into` returns a fresh owned dynamic array. Use `arr.into!` when appending into
an existing dynamic array.

Scalar output is explicit with `transduce`:

```clojure
(defn paid-total [orders: []Order] -> int
  (transduce paid-order-totals + 0 orders))
```

Reusable `defiter` producers can feed `for`, `into`, and `transduce`. The
header says what the opener returns and what `:next` yields:

```clojure
(defstruct Log_Source {
  lines: []string
  index: int
})

(defn next-log-line [src: ^Log_Source] -> [line: string ok: bool]
  (if (< src.index (count src.lines))
    (let [line src.lines[src.index]]
      (set! src.index (+ src.index 1))
      (return line true))
    (return "" false)))

(defiter log-lines [lines: []string] -> Log_Source yields string
  :next next-log-line
  (Log_Source {lines: lines index: 0}))

(for [line (log-lines lines)]
  (println line))
```

Loops can consume the same transform directly:

```clojure
(for [total orders :transform paid-order-totals]
  (println total))
```

The same iterator call can be the input to a fused scalar reduction:

```clojure
(transduce
  (comp
    (filter error-line?)
    (map line-length))
  + 0
  (log-lines lines))
```

For a complete iterator example that exercises `for`, `into`, `transduce`, and
`:dispose` cleanup, see
[examples/collections/log-source.kvist](../examples/collections/log-source.kvist).

Supported transformer forms are deliberately small:

```clojure
(map f)
(map-indexed f)
(mapcat f)
(filter pred)
(remove pred)
(keep f)
(take n)
(take-while pred)
(drop n)
(drop-while pred)
```

Callbacks can be known one-argument functions or shallow field selectors:

```clojure
(deftransform active-ages
  (comp
    (filter .active?)
    (map .age)))
```

`keep` callbacks return `[value: T ok: bool]`.

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
  (filter paid?)
  (map order-total)
  (filter positive?))

(defn collect-paid-totals [orders: []Order] -> [dynamic]int
  (into [dynamic]int paid-order-totals orders))

(defn sum-paid-totals [orders: []Order] -> int
  (transduce paid-order-totals + 0 orders))
```

Without a reusable transform, `collect-paid-totals` and `sum-paid-totals`
usually duplicate the same filtering and mapping logic in two manual loops.

## Current Lowering

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

`transduce` lowers to the same fused item flow with an accumulator. `+` emits
direct accumulator addition; a known two-argument reducer emits a direct call:

```clojure
(transduce paid-order-totals + 0 orders)
(transduce paid-order-totals add-int 0 orders)
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

When the input is a `defiter` call, `transduce` uses the same protocol as
`for` and `into`: open iterator state, defer disposal if present, call `:next`
until `ok` is false, and update the accumulator without allocating an
intermediate collection. This is the main reason `defiter` exists.

The generated Odin should stay easy to inspect.

## Comparison With Manual `for`

The equivalent manual collection loop is clear, but it mixes traversal,
conditionals, temporary names, result allocation, and append placement:

```clojure
(defn collect-paid-totals-manual [orders: []Order] -> [dynamic]int
  (let [out (arr.empty int)]
    (for [order orders]
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

The current implementation is strict:

- `deftransform` is compile-time structure, not a runtime value;
- transform steps must be known forms in known positions;
- `map` and `filter` callbacks must be known one-argument functions or field
  selectors with obvious input and output types;
- `map-indexed` callbacks must be known two-argument functions taking
  `(int, current-item)`;
- `mapcat` callbacks must return borrowed slices or fixed arrays in the first
  version; owned dynamic-array results are rejected until cleanup semantics are
  explicit;
- `keep` callbacks must be known one-argument functions returning
  `[value: T ok: bool]`;
- `take` counts values that reach that step and breaks the source loop early
  when the count is exhausted;
- `drop` and `drop-while` skip values that reach that step without allocating;
- `into` must name the concrete output type;
- dynamic array `into` owns the returned array, and callers delete it using the
  existing ownership conventions; append into existing arrays with `arr.into!`;
- `transduce` requires an obvious accumulator type from the initial value or an
  annotation, and the reducer must be `+` or a known two-argument function;
- `defiter` calls are consumed directly by `for`, `into`, and `transduce`;
- `for` accepts `[value source :transform transform]` for the same fused item
  flow;
- no hidden lazy seqs, dynamic dispatch, or boxed elements.

When any of these rules are not met, the compiler rejects the pipeline and
suggests the direct `for` loop fallback.

Named `deftransform` declarations are checked for basic shape immediately.
The spec may be a single step, `(comp ...)`, or several step forms after the
name. Callback existence, callback arity, callback types, and output type
compatibility are checked at the `into` or `transduce` use site where the source
and accumulator types are known.

## Current Limits

- transform specs support `map`, `map-indexed`, `mapcat`, `filter`, `remove`,
  `keep`, `take`, `take-while`, `drop`, and `drop-while`
- `into` currently targets fresh owned `[dynamic]T` arrays
- `transduce` supports `+` and known two-argument reducers
- inputs may be slices, fixed arrays, dynamic arrays, or `defiter` calls
- anything cleverer should usually be a direct `for` loop

## Examples

- [examples/collections/transforms.kvist](../examples/collections/transforms.kvist) -
  reusable transforms over ordinary arrays
- [examples/collections/log-source.kvist](../examples/collections/log-source.kvist) -
  `defiter`, `for`, `into`, `transduce`, and cleanup in one place
- [examples/collections/sources.kvist](../examples/collections/sources.kvist) -
  smaller iterator declarations consumed by collection forms
