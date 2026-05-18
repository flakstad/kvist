# Sequence Helper Direction

OdinL should grow a useful sequence helper surface, but it should remain Odin:
simple, eager, direct, and explicit about allocation.

This is not a Clojure seq runtime. There should be no hidden lazy sequence
layer, no persistent collection abstraction, and no implicit nil-as-empty
collection behavior. Helpers should lower to readable generic Odin procedures,
ordinary indexing, ordinary slicing, ordinary loops, ordinary maps, and ordinary
dynamic arrays.

## Principles

- Preserve Odin semantics.
- Prefer eager helpers over lazy producers.
- Return slices when a helper can be a cheap view.
- Return dynamic arrays when a helper must build a new collection.
- Do not hide allocation; generated helpers that allocate should be easy to
  spot in the emitted Odin.
- Keep callbacks as plain Odin procedure values.
- Keep callback state explicit. Odin procedure literals do not capture.
- Let Odin bounds checks and type checking remain visible.
- Avoid names or behavior that imply Clojure's nullable lazy seq model.

## Current Core

These helpers are already in scope and should remain small:

```clojure
(map f xs)
(filter pred xs)
(remove pred xs)
(reduce f init xs)
(map-indexed f xs)
(keep f xs)
(concat xs ys)
(reverse xs)
(split-at n xs)
(partition n xs)
(partition-all n xs)
(zipmap keys vals)
(take n xs)
(drop n xs)
(take-while pred xs)
(drop-while pred xs)
(find pred xs)
(some? pred xs)
(every? pred xs)
(first xs)
(second xs)
(last xs)
(nth xs n)
(rest xs)
(empty? xs)
```

The access and trimming helpers use the direct Odin representation where
possible. `first`, `second`, `last`, and `nth` lower to indexing. `empty?`
lowers to `len`. `rest`, `take`, `drop`, `take-while`, and `drop-while` return
non-owning slice views.

Builder helpers such as `map`, `filter`, `remove`, `map-indexed`, `keep`,
`concat`, and `reverse` return owned dynamic arrays. `zipmap` returns an owned
map. `partition` and `partition-all` return owned dynamic arrays of borrowed
slice chunks. `keep` is Odin-shaped: the callback returns `(value, ok)`, and
only `ok` values are appended.

Keyword callbacks are field-access shorthand in the supported higher-order
helpers:

```clojure
(map :name users)
(filter :verified users)
(remove :archived users)
(->> users
     (filter :verified)
     (map :name))
```

This means "call the field accessor" for structs and struct-like values. It is
not general keyword-as-function map lookup.

## Near-Term Additions

These fit the current eager model well:

```clojure
```

Expected lowering:

- `split-at` should return two slices when the input is sliceable, because that
  is the direct Odin representation and does not allocate.

## Useful Additions After That

These are valuable, but each needs one deliberate design choice before
implementation:

```clojure
(partition-by f xs)
(frequencies xs)
(group-by f xs)
(index-by f xs)
(mapcat f xs)
(sort xs)
(sort-by f xs)
(shuffle rng xs)
```

The main questions are:

- Should grouping helpers require explicit allocator arguments, use
  `context.allocator`, or follow the default dynamic-array helper convention?
- Should `sort` copy before sorting, or should there be a separate in-place
  helper?
- `shuffle` should probably require an explicit random source rather than hide
  one.

## Bounded Producers

Clojure's producer functions lean on laziness. OdinL should use explicit bounds:

```clojure
(range end)
(range start end)
(range start end step)
(repeat n x)
(repeatedly n f)
(iterate n f x)
```

These are acceptable as eager constructors because the amount of work and
allocation is visible in the call.

Avoid unbounded forms such as plain `cycle`, `repeat`, `repeatedly`, or
`iterate`. If a cyclic helper is ever added, it should be bounded:

```clojure
(cycle n xs)
```

## Transducer Path

The current eager helper shape should keep a transducer path open without
committing to it now.

Today:

```clojure
(->> users
     (filter active?)
     (map :name)
     (take 10))
```

Possible later design:

```clojure
(comp (filter active?)
      (map :name)
      (take 10))
```

That later design should still produce plain Odin code. It should not introduce
a hidden interpreter, persistent collection runtime, or lazy seq system.

## Threading And Cleanup

Threading forms should remain part of the language because they make nested
data flow much easier to read:

```clojure
(->> users
     (filter active?)
     (map :name)
     (take 10))
```

The hard part is ownership. If a thread step allocates and its result is passed
directly into the next step, the compiler must not lose the only handle to that
owned value.

Production-style code can always bind owned intermediate results explicitly:

```clojure
(let [active-users (filter active? users)
      active-names-all (map :name active-users)
      active-names (take 10 active-names-all)]
  (defer (delete active-users))
  (defer (delete active-names-all))
  ...)
```

This is slightly noisier, but it is honest and emits obvious Odin.

For threaded pipelines in `let` bindings, OdinL lowers allocating intermediate
steps to named temporaries and emits cleanup for those generated temporaries:

```odin
odinl_tmp_1 := odinl_filter(active_p, users[:])
defer delete(odinl_tmp_1)
odinl_tmp_2 := odinl_map_field_name(type_of(odinl_tmp_1[0].name), odinl_tmp_1[:])
defer delete(odinl_tmp_2)
active_names := odinl_take(10, odinl_tmp_2[:])
```

This only happens where the compiler is emitting statements and has a real scope
for the generated `defer`s. In pure expression position, automatic cleanup is
much harder to make correct without hidden control flow. For now, returning a
threaded pipeline with allocating intermediates is rejected; bind the pipeline in
`let` so the compiler can emit cleanup, or return the final owned value directly
from a non-pipelined allocation.

Transducers would improve this by compiling a composed transformation into one
loop and one owned result:

```clojure
(into [dynamic]string
      (comp (filter active?)
            (map :name)
            (take 10))
      users)
```

That shape can avoid most intermediate allocations, but the final result is
still owned and must be deleted or returned to transfer ownership.

## Ownership And Allocation

Sequence helpers need an explicit ownership story:

- Slice-view helpers such as `rest`, `take`, `drop`, `take-while`,
  `drop-while`, and `split-at` do not own data and must not be deleted.
- Dynamic-array helpers such as `map`, `filter`, `remove`, `map-indexed`,
  `keep`, `concat`, and `reverse` allocate and return owned dynamic arrays.
- Chunking helpers `partition` and `partition-all` allocate the outer dynamic
  array, but its slice chunks borrow the input collection.
- `zipmap` allocates and returns an owned map.
- Examples that use allocating helpers should show `defer delete(...)` when the
  result lives beyond a trivial expression.
- Future helper docs should clearly mark whether a helper returns a view or an
  owned dynamic array.

This is a documentation and examples requirement, not just an implementation
detail. OdinL should help make Odin ownership easier to see, not easier to
forget.

See `docs/OWNERSHIP.md` for the broader ownership rules used by examples and
tooling.
