# Transforms

Transforms describe reusable item pipelines. The compiler lowers them to direct
loops without lazy sequences or intermediate collections.

```clojure
(deftransform paid-totals
  (filter paid?)
  (map order-total)
  (filter positive?))
```

A transform is compile-time syntax, not a runtime value.

## Using A Transform

Collect results with `into`:

```clojure
(let [totals (into [dynamic]int paid-totals orders) :defer]
  ...)
```

Reduce without collecting:

```clojure
(transduce paid-totals + 0 orders)
```

Run a loop:

```clojure
(for [total orders :transform paid-totals]
  (println total))
```

Append to an existing dynamic array:

```clojure
(arr.into! totals paid-totals orders)
```

Inline transforms use `comp`:

```clojure
(into [dynamic]string
  (comp
    (filter .active?)
    (map .name))
  users)
```

A single step can appear directly in any transform position.

## Steps

Supported steps are:

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
(distinct)
(distinct-by f)
```

`distinct` and `distinct-by` are available for `Data` pipelines. Native
pipelines should use `arr.distinct` or `arr.distinct-by`.

Callbacks can be named functions, typed inline `fn` forms, or field selectors
where supported:

```clojure
(let [minimum 40]
  (into [dynamic]int
    (comp
      (map (fn [order: Order] -> int order.amount))
      (filter (fn [amount: int] -> bool (> amount minimum))))
    orders))
```

`keep` callbacks return `[value ok]`. `map-indexed` callbacks receive the
output index and current item.

## Sources

Transforms accept:

- fixed arrays, slices, and dynamic arrays;
- maps, which feed values by default;
- `Data` lists, vectors, sets, and nil;
- `defiter` calls;
- bounded array producers such as `arr.range` and `arr.repeat`.

Use `map.entries` when a transform needs both keys and values:

```clojure
(transduce
  (map (fn [entry: (map.entry string int)] -> int
         (+ (count entry.key) entry.value)))
  + 0
  (map.entries scores))
```

Map loops can keep the key while transforming the value:

```clojure
(for [key total scores :transform (filter positive?)]
  (println key total))
```

## Outputs

`into` can create owned dynamic arrays, maps, sets, or vector `Data`.

Map output expects `(map.entry K V)` values:

```clojure
(into map[string]int
  (map normalize-entry)
  (map.entries source))
```

`transduce` accepts `+`, `min`, `max`, a named two-argument reducer, or a typed
inline reducer. Inline reducers can stop early with `reduced`:

```clojure
(transduce paid-totals
  (fn [sum: int, total: int] -> int
    (let [next (+ sum total)]
      (if (>= next 100)
        (reduced next)
        next)))
  0
  orders)
```

## Ownership

`into` returns an owned collection. `arr.into!` mutates its target.
`transduce` returns its accumulator. Transform callbacks may borrow their
inputs; managed intermediate `Data` values are cleaned up when rejected or
replaced by later steps.

Use a direct `for` loop when the pipeline needs unusual state or when it reads
more clearly.

See [the transform examples](../examples/collections/data-transforms.kvist) and
[the iterator example](../examples/collections/log-source.kvist).
