# Typed Holes

This is a parking note for a possible future tooling feature. It is not a
current Kvist feature.

A typed hole is an intentional placeholder expression that asks the checker to
report the type expected at that source position. The goal is not synthesis or
runtime behavior. The goal is faster feedback while writing code, especially
when the expected callback type is hidden inside generic helpers, transform
pipelines, or foreign/package APIs.

Possible surface:

```clojure
(hole name)
```

The form would be valid only in expression position and would make `kvist check`
report the expected type if enough context is available.

Examples of useful diagnostics:

```clojure
(arr.map (hole f) orders)
```

If `orders` is `[]Order` and the surrounding context expects `[dynamic]int`,
the diagnostic could be:

```text
hole f expects fn [Order] -> int
```

For transforms:

```clojure
(into [dynamic]Label
  (comp
    (filter (hole pred))
    (map (hole label)))
  orders)
```

Expected diagnostics:

```text
hole pred expects fn [Order] -> bool
hole label expects fn [Order] -> Label
```

For reducers:

```clojure
(transduce paid-totals (hole reducer) 0 orders)
```

If `paid-totals` emits `int`, the diagnostic could be:

```text
hole reducer expects fn [int, int] -> int
```

This feature is likely only worth pursuing if Kvist has enough expected-type
context before Odin emission. If most of that information is currently only
available from Odin errors, typed holes may be disproportionately expensive.
