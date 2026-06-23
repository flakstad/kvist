# Functional Transforms

Functional transforms are Kvist's main tool for reusable data shaping. They
let you write one item-flow pipeline and consume it as a collection, scalar
reduction, or loop, while the compiler still emits direct fused Odin loops.

Use them when you would otherwise duplicate the same filtering and mapping in
several hand-written loops.

```clojure
(deftransform paid-order-totals
  (filter paid?)
  (map order-total)
  (filter positive?))

(into [dynamic]int paid-order-totals orders)
(transduce paid-order-totals + 0 orders)
(for [total orders :transform paid-order-totals]
  (println total))
```

No lazy sequences are built. No intermediate arrays are created unless you ask
for one with `into`.

Files that lean heavily on array-style data shaping can import `kvist:arr`
without an alias and use the package helpers bare:

```clojure
(import "kvist:arr")

(defn active-names [users: []User] -> [dynamic]string
  (let [active (filter .active? users) :defer]
    (map .name active)))
```

That style keeps eager helper calls visually close to transform specs. It is
available for unaliased Kvist source-package imports; explicit aliases such as
`(import arr "kvist:arr")` still use `arr.map`, `arr.filter`, and so on.

## When To Use Them

Manual `for` loops are always available and remain the escape hatch for
anything unusual. A transform pipeline is worth using when it provides clear
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

A single step can also stand alone in a transform position:

```clojure
(into [dynamic]int (map score) users)
(transduce (filter active?) + 0 users)
(for [score users :transform (map .score)]
  (println score))
```

These forms are contextual compile-time transform syntax. They are accepted by
`deftransform`, `into`, `arr.into!`, `transduce`, and `for :transform`; they
are not runtime values.

Inline `fn` callbacks are also accepted in transform steps when their parameter
and return types are explicit. Captured locals are passed into the generated
Odin helper proc as ordinary parameters, so the item loop still fuses:

```clojure
(let [minimum 40]
  (into [dynamic]int
    (comp
      (filter (fn [order: Order] -> bool (= order.status 2)))
      (map (fn [order: Order] -> int (- order.amount order.discount)))
      (filter (fn [total: int] -> bool (> total minimum))))
    orders))
```

Collection output is explicit with `into`:

```clojure
(defn paid-totals [orders: []Order] -> [dynamic]int
  (into [dynamic]int paid-order-totals orders))

(defn order-statuses [orders: []Order] -> set[int]
  (into set[int] (map .status) orders))
```

`into` returns a fresh owned dynamic array, map, or set. Use `arr.into!` when
appending into an existing dynamic array:

```clojure
(arr.into! existing paid-order-totals orders)
```

When the source has an obvious count, `into` reserves output capacity in the
generated Odin loop. This is only a capacity hint; filters can still produce
fewer values.

Scalar output is explicit with `transduce`:

```clojure
(defn paid-total [orders: []Order] -> int
  (transduce paid-order-totals + 0 orders))
```

Reducers can be `+`, `min`, `max`, a known two-argument function, or an inline
`fn` literal:

```clojure
(transduce paid-order-totals min 999 orders)
(transduce paid-order-totals max 0 orders)

(let [weight 2]
  (transduce paid-order-totals
    (fn [acc: int, total: int] -> int (+ acc (* total weight)))
    0 orders))
```

Inline reducers can stop the source loop early with `reduced`:

```clojure
(transduce paid-order-totals
  (fn [sum: int, total: int] -> int
    (let [next (+ sum total)]
      (if (>= next 100)
        (reduced next)
        next)))
  0 orders)
```

`reduced` is reducer control flow, not a runtime wrapper value. It is currently
only valid as a direct branch in an inline `transduce` reducer body, optionally
inside a simple reducer-local `let`.

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

(for [idx total orders :transform paid-order-totals]
  (println idx total))
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

Map sources feed their values through transforms. This keeps the existing map
loop syntax for keys and values separate:

```clojure
(transduce
  (comp
    (filter positive?)
    (map inc))
  + 0
  lookup)
```

When a loop needs keys too, use the map-shaped `for :transform` binding. The
transform still runs on values:

```clojure
(for [key total lookup :transform paid-totals]
  (println key total))
```

When a transform itself should consume both key and value, opt in with
`map.entries`. Entry values have type `(map.entry K V)` and fields `key` and
`value`:

```clojure
(transduce
  (map (fn [entry: (map.entry string int)] -> int
         (+ (count entry.key) entry.value)))
  + 0
  (map.entries lookup))

(into map[string]int
  (map (fn [entry: (map.entry string int)] -> (map.entry string int)
         ((map.entry string int) {key: entry.key value: (+ entry.value 1)})))
  (map.entries lookup))

(into set[string]
  (map (fn [entry: (map.entry string int)] -> string entry.key))
  (map.entries lookup))
```

`arr.range` and `arr.repeat` are normally eager owned array helpers. In
transform-source position, the compiler lowers them directly to counted loops
instead:

```clojure
(transduce (filter even?) max 0 (arr.range 0 100))
(transduce (map inc) + 0 (arr.repeat 4 2))
(for [x (arr.range 10 0 -1) :transform (map inc)]
  (println x))
```

### Transform Source Optimizations

| Source form | Transform positions | Lowering |
| --- | --- | --- |
| slices, fixed arrays, dynamic arrays | `into`, `arr.into!`, `transduce`, `for :transform` | direct `for` loop over elements |
| maps | `into`, `arr.into!`, `transduce`, `for :transform` | direct map loop over values |
| maps with keys | `for [key value map :transform xf]` | direct map loop, transform values, bind key separately |
| `map.entries` | `into`, `arr.into!`, `transduce`, `for :transform` | direct map loop over explicit `(map.entry K V)` values |
| `defiter` calls | `into`, `arr.into!`, `transduce`, `for :transform` | direct `next` loop with `:dispose` cleanup when present |
| `arr.range` | `into`, `arr.into!`, `transduce`, `for :transform` | direct counted loop, no range array allocation |
| `arr.repeat` | `into`, `arr.into!`, `transduce`, `for :transform` | direct counted loop over a cached repeated value, no repeat array allocation |

Ordinary calls still keep their ordinary semantics: `(arr.range ...)` and
`(arr.repeat ...)` outside transform-source position return owned dynamic
arrays.

### Map Entries

Map transforms consume values by default. `for [key value map :transform xf]`
keeps the key available while transforming values. `map.entries` is the
explicit entry surface for `into`, `arr.into!`, `transduce`, and
`for :transform`; it does not allocate an entries array.

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

Callbacks can be known functions, inline `fn` literals, or shallow field
selectors where the step allows selectors:

```clojure
(deftransform active-ages
  (comp
    (filter .active?)
    (map .age)))
```

`map-indexed` callbacks take `(int, current-item)`. `keep` callbacks return
`[value: T ok: bool]`.

```clojure
(into [dynamic]int
  (keep (fn [order: Order] -> [value: int ok: bool]
          (return order.discount (> order.discount 0))))
  orders)

(transduce
  (map-indexed (fn [idx: int, age: int] -> int (+ idx age)))
  + 0 ages)
```

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
    kvist_out := make([dynamic]int, 0, len(kvist_source))
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

`transduce` lowers to the same fused item flow with an accumulator. `+`, `min`,
and `max` emit direct accumulator updates; known two-argument reducers and
inline `fn` reducers emit direct calls:

```clojure
(transduce paid-order-totals + 0 orders)
(transduce paid-order-totals min 999 orders)
(transduce paid-order-totals max 0 orders)
(transduce paid-order-totals add-int 0 orders)
(transduce paid-order-totals
  (fn [acc: int, total: int] -> int (+ acc total))
  0 orders)
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
- `map`, `filter`, `remove`, `take-while`, `drop-while`, and `mapcat`
  callbacks must be known one-argument functions or inline `fn` literals with
  obvious input and output types;
- `map`, `filter`, `remove`, `take-while`, and `drop-while` also accept shallow
  field selectors where the field type matches the step;
- `map-indexed` callbacks must be known two-argument functions or inline `fn`
  literals taking `(int, current-item)`;
- `mapcat` callbacks must return borrowed slices or fixed arrays in the first
  version; owned dynamic-array results are rejected until cleanup semantics are
  explicit;
- `keep` callbacks must be known one-argument functions or inline `fn`
  literals returning `[value: T ok: bool]`;
- inline `fn` transform callbacks require explicit parameter and return types;
- captured locals inside inline `fn` callbacks must have obvious local types;
- `take` counts values that reach that step and breaks the source loop early
  when the count is exhausted;
- `drop` and `drop-while` skip values that reach that step without allocating;
- `into` must name the concrete output type;
- dynamic array `into` owns the returned array, and callers delete it using the
  existing ownership conventions; append into existing arrays with
  `(arr.into! target transform source)`;
- `into` reserves capacity for counted collection sources when the count is
  obvious to the lowering;
- map `into` owns the returned map and expects the pipeline to produce
  `(map.entry K V)` values for an output type `map[K]V`;
- set `into` owns the returned set and expects the pipeline to produce values
  of the set element type;
- `transduce` requires an obvious accumulator type from the initial value or an
  annotation, and the reducer must be `+`, `min`, `max`, a known two-argument
  function, or an inline `fn` literal returning the accumulator type;
- `reduced` is supported only inside inline `transduce` reducers, as a direct
  reducer branch such as `(if test (reduced value) next-acc)`, optionally inside
  a simple reducer-local `let`;
- map sources feed values into `into`, `arr.into!`, `transduce`, and
  `for :transform`; `(for [key value m :transform transform] ...)` keeps the
  key available while transforming the value;
- `map.entries` feeds explicit `(map.entry K V)` values with `key` and `value`
  fields through the same fused transform positions;
- `arr.range` and `arr.repeat` sources in transform positions lower to direct
  loops and do not allocate the owned arrays that ordinary calls return;
- `defiter` calls are consumed directly by `for`, `into`, and `transduce`;
- `for` accepts `[value source :transform transform]` for the same fused item
  flow;
- `for` also accepts `[index value source :transform transform]` for arrays and
  slices; `index` counts values that reach the loop body after filtering,
  dropping, and expanding;
- for maps, `[key value source :transform transform]` binds the map key and the
  transformed value;
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
- `into` currently targets fresh owned `[dynamic]T` arrays, owned `map[K]V`
  maps, and owned `set[T]` sets; `arr.into!` appends into existing dynamic
  arrays
- `transduce` supports `+`, `min`, `max`, known two-argument reducers, and
  inline `fn` reducers; inline reducers can use direct-branch `reduced` to
  stop early
- inputs may be slices, fixed arrays, dynamic arrays, maps, or `defiter` calls
- inline `fn` callbacks are compile-time syntax in transform positions, not
  runtime closure values
- anything cleverer should usually be a direct `for` loop

## Examples

- [examples/collections/data-transforms.kvist](../examples/collections/data-transforms.kvist) -
  small first-read example for `into`, `transduce`, `for :transform`, set
  output, and `reduced`
- [benchmarks/transform_fusion.kvist](../benchmarks/transform_fusion.kvist) -
  focused manual loop / `into` / `transduce` / `reduced` comparison
- [examples/collections/transforms.kvist](../examples/collections/transforms.kvist) -
  reusable transforms over ordinary arrays
- [examples/collections/log-source.kvist](../examples/collections/log-source.kvist) -
  `defiter`, `for`, `into`, `transduce`, and cleanup in one place
- [examples/collections/sources.kvist](../examples/collections/sources.kvist) -
  smaller iterator declarations consumed by collection forms
