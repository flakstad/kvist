# Sequence Helper Direction

OdinL should grow a useful sequence helper surface, but it should remain Odin:
simple, eager, direct, and explicit about allocation.

This is not a Clojure seq runtime. There should be no hidden lazy sequence
layer, no persistent collection abstraction, and no implicit nil-as-empty
collection behavior. Helpers should lower to readable generic Odin procedures,
ordinary indexing, ordinary slicing, ordinary loops, ordinary maps, and ordinary
dynamic arrays.

There will not be lazy sequences in OdinL. Producers must always be bounded,
and helpers must always be one of: eager owned collection builders, borrowed
slice views, scalar operations, or explicit in-place mutation.

## Principles

- Preserve Odin semantics.
- Prefer eager helpers over lazy producers.
- Do not add unbounded producers.
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
(mapcat f xs)
(concat xs ys)
(reverse xs)
(sort xs)
(sort-by f xs)
(sort-by :field xs)
(reverse! xs)
(sort! xs)
(sort-by! f xs)
(sort-by! :field xs)
(map! f xs)
(map-indexed! f xs)
(filter! pred xs)
(filter! :field xs)
(remove! pred xs)
(remove! :field xs)
(keep! f xs)
(into! target xs)
(split-at n xs)
(partition n xs)
(partition-all n xs)
(partition-by f xs)
(partition-by :field xs)
(zipmap keys vals)
(index-by f xs)
(index-by :field xs)
(group-by f xs)
(group-by :field xs)
(frequencies xs)
(distinct xs)
(distinct-by f xs)
(distinct-by :field xs)
(range end)
(range start end)
(range start end step)
(repeat n x)
(repeatedly n f)
(iterate n f x)
(cycle n xs)
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
(count xs)
(contains? collection key)
```

The access and trimming helpers use the direct Odin representation where
possible. `first`, `second`, `last`, and `nth` lower to indexing. `empty?`
lowers to `len`. `rest`, `take`, `drop`, `take-while`, and `drop-while` return
non-owning slice views.

Builder helpers such as `map`, `filter`, `remove`, `map-indexed`, `keep`,
`mapcat`, `concat`, `reverse`, `range`, `repeat`, `repeatedly`, `iterate`, and
bounded `cycle` return owned dynamic arrays. `distinct` and `distinct-by` also
return owned dynamic arrays and use a temporary `map[key]bool` internally, so
the value or key must be valid as an Odin map key. `zipmap`, `index-by`, and
`frequencies` return owned maps. `group-by` returns an owned map whose values
are owned dynamic arrays; delete each group before deleting the map.
`partition`, `partition-all`, and `partition-by` return owned dynamic arrays of
borrowed slice chunks. `keep` is Odin-shaped: the callback returns `(value,
ok)`, and only `ok` values are appended. `mapcat` is also Odin-shaped: the
callback returns a borrowed slice, and `mapcat` appends those values into one
owned dynamic array.

`sort` and `sort-by` copy before sorting. They do not mutate the input
collection, and their result is owned.

Bang helpers are explicitly mutating statement forms. `reverse!`, `sort!`,
`sort-by!`, `map!`, and `map-indexed!` mutate the passed slice or dynamic array
in place and do not return an owned value. `filter!`, `remove!`, and `keep!`
resize the collection, so they require an owned dynamic array binding. `keep!`
uses an Odin-shaped callback returning `(value, ok)` and writes kept values back
into the same dynamic array; the value type must match the array element type.
`into!` appends the values from one collection into an existing dynamic array
target. It lowers directly to Odin `append(&target, ..xs)`-style code, mutates
the target, and does not create a new owned result.

Keyword callbacks are field-access shorthand in the supported higher-order
helpers:

```clojure
(map :name users)
(index-by :id users)
(group-by :status users)
(partition-by :status users)
(distinct-by :id users)
(sort-by :age users)
(sort-by! :age users)
(filter :verified users)
(remove :archived users)
(->> users
     (filter :verified)
     (map :name))
```

This means "call the field accessor" for structs and struct-like values. It is
not general keyword-as-function map lookup.

## Allocation And Performance

The default sequence helpers prefer clear ownership over minimum allocation. A
chain of owned helpers allocates at each owned step:

```clojure
(->> users
     (filter active?)
     (map :name)
     (sort))
```

That pipeline builds a filtered dynamic array, then a mapped dynamic array, then
a sorted copy. In a `let` binding, OdinL emits cleanup for owned threaded
intermediates, but the allocation and copy costs are still real.

This is intentional for the non-bang helpers:

- non-bang helpers do not mutate their inputs;
- allocations are visible in the generated Odin;
- ownership is either returned to the caller or bound where it can be deleted.

For hot paths, prefer one of these shapes:

- use slice-view helpers such as `take`, `drop`, `rest`, and `split-at` when a
  borrowed view is enough;
- use bang helpers such as `sort!`, `reverse!`, `map!`, `filter!`, `remove!`,
  `keep!`, and `into!` when mutating existing storage is the right Odin choice;
- write an explicit `each` loop when one pass and no intermediate collection is
  needed;
- later, use transducer-style lowering once it exists to fuse pipelines into one
  loop and one final allocation.

## Completion Before Transducers

The eager sequence library is close to complete enough for ordinary code. The
remaining pre-transducer work should stay small and direct:

- non-bang `into`: construct a new owned target once the target syntax is clear.
- broaden `into!` beyond dynamic arrays only when the target representation
  stays obvious, such as a direct map merge.
- `shuffle`: eager copy plus shuffle with an explicit random source.
- possibly `interpose` and `interleave`: owned dynamic-array builders when the
  output type remains obvious.

Avoid helpers that imply lazy sequence semantics, nil-as-empty behavior, or a
collection protocol. Prefer an explicit loop in user code when a helper's
lowering would be surprising.

## Useful Additions After That

These are valuable, but each needs one deliberate design choice before
implementation:

```clojure
(into target xs)
(into! target xs)
(shuffle rng xs)
```

The main questions are:

- `into!` currently means dynamic-array append and lowers directly to
  `append(&target, ..xs)`. Maps could later merge key/value pairs, and sets
  would first need a concrete Odin representation. Treat this as explicit eager
  mutation, not a polymorphic collection protocol. Non-bang `(into Type xs)`
  remains reserved for constructing a new owned target once that shape is worth
  adding.
- `shuffle` should probably require an explicit random source rather than hide
  one.
- `distinct` and `distinct-by` are implemented with temporary `map[key]bool`
  storage. Broader set-like helpers should keep using ordinary Odin map-backed
  representations unless a better concrete Odin shape appears.

## Bounded Producers

Producer helpers are eager and bounded. The amount of work and allocation is
visible in the call:

Avoid unbounded forms such as plain `cycle`, unbounded `repeat`, unbounded
`repeatedly`, or unbounded `iterate`. Use explicit counts:

```clojure
(range start end step)
(repeat n x)
(repeatedly n f)
(iterate n f x)
(cycle n xs)
```

`cycle` returns an owned dynamic array containing at most `n` items by cycling
over the input slice. It returns an empty owned dynamic array when `n <= 0` or
the input is empty.

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
  `keep`, `mapcat`, `concat`, `reverse`, `sort`, and `sort-by` allocate and
  return owned dynamic arrays.
- Chunking helpers `partition`, `partition-all`, and `partition-by` allocate the
  outer dynamic array, but their slice chunks borrow the input collection.
- `zipmap`, `index-by`, and `frequencies` allocate and return owned maps.
- `group-by` allocates an owned map and one owned dynamic array per key. Delete
  the groups, then delete the map.
- Owned helper results must be bound or returned. Nested owned results such as
  `(first (map f xs))` are rejected because there is no visible place to delete
  the intermediate dynamic array.
- Examples that use allocating helpers should show `defer delete(...)` when the
  result lives beyond a trivial expression.
- Future helper docs should clearly mark whether a helper returns a view or an
  owned dynamic array.

This is a documentation and examples requirement, not just an implementation
detail. OdinL should help make Odin ownership easier to see, not easier to
forget.

See `docs/OWNERSHIP.md` for the broader ownership rules used by examples and
tooling.
