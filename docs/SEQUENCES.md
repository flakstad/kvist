# Sequence Helper Direction

Kvist should grow a useful sequence helper surface, but it should remain Odin:
simple, eager, direct, and explicit about allocation.

This is not a Clojure seq runtime. There should be no hidden lazy sequence
layer, no persistent collection abstraction, and no implicit nil-as-empty
collection behavior. Helpers should lower to readable generic Odin procedures,
ordinary indexing, ordinary slicing, ordinary loops, ordinary maps, and ordinary
dynamic arrays.

There will not be lazy sequences in Kvist. Producers must always be bounded,
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
(merge a b)
(into [dynamic]T xs)
(interpose sep xs)
(interleave xs ys)
(reverse xs)
(shuffle pick xs)
(sort xs)
(sort-by f xs)
(sort-by :field xs)
(reverse! xs)
(shuffle! pick xs)
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
(merge! target source)
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
(count-by f xs)
(count-by :field xs)
(sum-by key-f value-f xs)
(sum-by :key-field :value-field xs)
(frequencies xs)
(keys m)
(vals m)
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
(butlast xs)
(drop-last n xs)
(take-nth n xs)
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
(get m k default)
(contains? collection key)
```

The access and trimming helpers use the direct Odin representation where
possible. `first`, `second`, `last`, and `nth` lower to indexing. `empty?`
lowers to `len`. `rest`, `take`, `drop`, `butlast`, `drop-last`, `take-while`,
and `drop-while` return non-owning slice views. Three-argument `get` is a map
helper: it uses Odin's
comma-ok lookup and returns the supplied default when the key is absent.

Builder helpers such as `map`, `filter`, `remove`, `map-indexed`, `keep`,
`mapcat`, `concat`, `into`, `interpose`, `interleave`, `reverse`, `shuffle`,
`range`, `repeat`, `repeatedly`, `iterate`, bounded `cycle`, and `take-nth`
return owned dynamic arrays. `into` is currently only for explicit dynamic-array
targets, for example `(into [dynamic]int xs)`. `distinct` and `distinct-by` also
return owned dynamic arrays and use a temporary `map[key]bool` internally, so
the value or key must be valid as an Odin map key. `zipmap`, `index-by`, and
`frequencies` return owned maps. `merge` returns an owned map that combines two
input maps, with right-hand values replacing duplicate keys. `keys` and `vals`
return owned dynamic arrays copied from a map. `group-by` returns an owned map
whose values are owned dynamic arrays; delete each group before deleting the map.
`count-by` and `sum-by` return owned maps for common aggregate cases where the
grouped items themselves are not needed. `partition`, `partition-all`, and
`partition-by` return owned dynamic arrays of borrowed slice chunks. `keep` is
Odin-shaped: the callback returns `(value, ok)`, and only `ok` values are
appended. `mapcat` is also Odin-shaped: the callback returns a borrowed slice,
and `mapcat` appends those values into one owned dynamic array.

`sort` and `sort-by` copy before sorting. They do not mutate the input
collection, and their result is owned.

`shuffle` also copies before shuffling. It takes an explicit picker function
instead of hiding a random generator:

```clojure
(proc pick [n: int] -> int
  (rand.int-max n))

(shuffle pick xs)
```

The picker must return an index in `[0, n)`. This keeps generated code simple
and lets user code choose whether the random source is deterministic, seeded,
or the current Odin context generator.

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
(count-by :status users)
(sum-by :region :amount orders)
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
a sorted copy. In a `let` binding, Kvist emits cleanup for owned threaded
intermediates, but the allocation and copy costs are still real.

This is intentional for the non-bang helpers:

- non-bang helpers do not mutate their inputs;
- allocations are visible in the generated Odin;
- ownership is either returned to the caller or bound where it can be deleted.

For hot paths, prefer one of these shapes:

- use slice-view helpers such as `take`, `drop`, `butlast`, `drop-last`,
  `rest`, and `split-at` when a borrowed view is enough;
- use bang helpers such as `sort!`, `reverse!`, `shuffle!`, `map!`, `filter!`,
  `remove!`, `keep!`, `into!`, and `merge!` when mutating existing storage is the
  right Odin choice;
- write an explicit `each` loop when one pass and no intermediate collection is
  needed;
- avoid `group-by` when only aggregate totals are needed. Use `count-by` or
  `sum-by` for simple aggregate maps, or accumulate directly into maps for
  custom stateful aggregates.

The useful distinction is not "helpers versus loops". It is whether the
intermediate collection is a real value in the program.

Use eager helpers when the intermediate value has meaning:

```clojure
(let [settled (map settle-order orders)
      paid (filter settled? settled)
      groups (group-by :region paid)]
  ...)
```

Use bang helpers when you own a working buffer:

```clojure
(let [work (map settle-order orders)]
  (filter! settled? work)
  ...)
```

Use aggregate helpers when grouped slices would be waste:

```clojure
(let [work (map settle-order orders)]
  (filter! settled? work)
  (let [revenue-by-region (sum-by :region :amount work)
        count-by-region (count-by :region work)]
    ...))
```

Use an explicit loop when even those aggregate maps are just implementation
detail before a scalar result, or when the update needs custom state:

```clojure
(let [revenue-by-region (make map[int]int)
      count-by-region (make map[int]int)]
  (each [order orders]
    (let [settled (settle-order order)]
      (when (settled? settled)
        (set! (get revenue-by-region (:region settled))
              (+ (get revenue-by-region (:region settled))
                 (:amount settled)))
        (set! (get count-by-region (:region settled))
              (+ (get count-by-region (:region settled))
                 1))))))
```

That loop is not a failure of the helper library. It is ordinary Odin-shaped
code for a stateful aggregate.

The benchmark suite includes direct Odin comparisons for these cases:

```sh
./scripts/bench_sequence_helpers.sh
BASE_REF=main ./scripts/bench_sequence_helpers.sh
./scripts/bench_aggregate_helpers.sh
```

The important benchmark patterns are:

- `pipe-map-filter`: eager `map -> filter -> reduce`; clear but allocates two
  intermediates.
- `pipe-bang-copy`: one owned working copy plus `filter!`; less allocation, but
  still not a fused reduction.
- `pipe-loop`: explicit loop; no allocation and close to direct Odin.
- `report-eager`: materialized report pipeline with `map`, `filter`, `group-by`,
  and `sort-by!`.
- `report-bang`: mutable working buffer before grouping.
- `report-loop`: direct aggregate maps and final report rows only.

At the time of writing, the report benchmark shows the intended shape:

```text
report-eager  materializes settled orders, paid orders, groups, and rows
report-bang   materializes one working order buffer, groups, and rows
report-loop   accumulates maps directly and materializes final rows only
```

`report-loop` is the fastest and least allocating version because the workload
only needs per-region totals, not actual grouped order slices. `count-by` and
`sum-by` cover the common middle ground where aggregate maps are meaningful
outputs. If a caller needs to inspect the grouped orders themselves, `group-by`
is still the right helper.

The `examples/orders-report.kvist` example also includes an
`aggregate-helper-report-score` variant that uses `sum-by` and `count-by`. The
focused aggregate benchmark compares that shape with the grouped version and a
direct aggregate loop. Its expected result is lower allocation than `group-by`,
but still slower and more allocating than the direct fused loop because
settling, filtering, summing, and counting remain separate passes.

## Completion Before Transducers

The eager sequence library is close to complete enough for ordinary code. The
remaining pre-transducer work should stay small and direct. Dynamic-array append
is covered by `into!`; map merge is covered by explicit `merge` and `merge!`.
Avoid broadening these into a polymorphic collection protocol.

Avoid helpers that imply lazy sequence semantics, nil-as-empty behavior, or a
collection protocol. Prefer an explicit loop in user code when a helper's
lowering would be surprising.

## Useful Additions After That

These are valuable, but each needs one deliberate design choice before
implementation:

The main questions are:

- `into` currently constructs an owned dynamic array from a borrowed collection,
  and `into!` currently means dynamic-array append lowering directly to
  `append(&target, ..xs)`. Map combination is explicit `merge`/`merge!`. Sets
  would first need a concrete Odin representation. Treat this as explicit eager
  construction or mutation, not a polymorphic collection protocol.
- `shuffle` and `shuffle!` are implemented with an explicit picker callback. The
  caller owns the randomness policy; Kvist only performs the swaps.
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

For threaded pipelines in `let` bindings, Kvist lowers allocating intermediate
steps to named temporaries and emits cleanup for those generated temporaries:

```odin
kvist_tmp_1 := kvist_filter(active_p, users[:])
defer delete(kvist_tmp_1)
kvist_tmp_2 := kvist_map_field_name(type_of(kvist_tmp_1[0].name), kvist_tmp_1[:])
defer delete(kvist_tmp_2)
active_names := kvist_take(10, kvist_tmp_2[:])
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

- Slice-view helpers such as `rest`, `take`, `drop`, `butlast`, `drop-last`,
  `take-while`, `drop-while`, and `split-at` do not own data and must not be
  deleted.
- Dynamic-array helpers such as `map`, `filter`, `remove`, `map-indexed`,
  `keep`, `mapcat`, `concat`, `reverse`, `shuffle`, `sort`, `sort-by`, and
  `take-nth` allocate and return owned dynamic arrays.
- Chunking helpers `partition`, `partition-all`, and `partition-by` allocate the
  outer dynamic array, but their slice chunks borrow the input collection.
- `merge`, `zipmap`, `index-by`, `count-by`, `sum-by`, and `frequencies`
  allocate and return owned maps.
- `keys` and `vals` allocate and return owned dynamic arrays copied from a map.
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
detail. Kvist should help make Odin ownership easier to see, not easier to
forget.

See `docs/OWNERSHIP.md` for the broader ownership rules used by examples and
tooling.
