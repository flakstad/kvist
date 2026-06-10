# Sequence Helpers

Kvist's sequence helper surface is Odin-shaped: simple, eager, direct, and
explicit about allocation.

This is not a Clojure seq runtime. There is no hidden lazy sequence layer, no
persistent collection abstraction, and no implicit nil-as-empty collection
behavior. Helpers lower to readable generic Odin procedures, ordinary indexing,
ordinary slicing, ordinary loops, ordinary maps, and ordinary dynamic arrays.

Kvist has no lazy sequences. Producers are always bounded, and helpers are
always one of: eager owned collection builders, borrowed slice views, scalar
operations, or explicit in-place mutation.

## Principles

- Preserve Odin semantics.
- Prefer eager helpers over lazy producers.
- Do not add unbounded producers.
- Return slices when a helper can be a cheap view.
- Return dynamic arrays when a helper must build a new collection.
- Do not hide allocation; generated helpers that allocate should be easy to
  spot in the emitted Odin.
- Keep callbacks as plain Odin procedure values when they do not capture.
- Keep captured callback lowering explicit. Captured callbacks are allowed when
  the compiler can prove the callback does not escape: builder helpers,
  indexed helpers, reducers, scans, direct calls inside Kvist-defined
  functions, and forwarding to other non-escaping Kvist functions. Captures
  lower to extra proc parameters, not heap closure objects.
- Let Odin bounds checks and type checking remain visible.
- Avoid names or behavior that imply Clojure's nullable lazy seq model.

## Current Core

These helpers are already in scope and should remain small:

```clojure
(arr.map f xs)
(arr.filter pred xs)
(arr.remove pred xs)
(arr.reduce f init xs)
(arr.reduce-indexed f init xs)
(arr.map-indexed f xs)
(arr.keep f xs)
(arr.mapcat f xs)
(concat xs ys)
(map.merge a b)
(arr.into [dynamic]T xs)
(arr.interpose sep xs)
(arr.interleave xs ys)
(arr.reverse xs)
(arr.shuffle pick xs)
(arr.sort xs)
(arr.sort-by f xs)
(arr.sort-by .field xs)
(arr.reverse! xs)
(arr.shuffle! pick xs)
(arr.sort! xs)
(arr.sort-by! f xs)
(arr.sort-by! .field xs)
(arr.map! f xs)
(arr.map-indexed! f xs)
(arr.filter! pred xs)
(arr.filter! .field xs)
(arr.remove! pred xs)
(arr.remove! .field xs)
(arr.keep! f xs)
(arr.into! target xs)
(map.merge! target source)
(arr.split-at n xs)
(arr.partition n xs)
(arr.partition-all n xs)
(arr.partition-by f xs)
(arr.partition-by .field xs)
(map.zip keys vals)
(arr.index-by f xs)
(arr.index-by .field xs)
(arr.group-by f xs)
(arr.group-by .field xs)
(arr.count-by f xs)
(arr.count-by .field xs)
(arr.sum-by key-f value-f xs)
(arr.sum-by .key-field .value-field xs)
(arr.frequencies xs)
(map.keys m)
(map.vals m)
(arr.distinct xs)
(arr.distinct-by f xs)
(arr.distinct-by .field xs)
(arr.range end)
(arr.range start end)
(arr.range start end step)
(arr.repeat n x)
(arr.repeatedly n f)
(arr.iterate n f x)
(arr.cycle n xs)
(arr.take n xs)
(arr.drop n xs)
(arr.butlast xs)
(arr.drop-last n xs)
(arr.take-nth n xs)
(arr.take-while pred xs)
(arr.drop-while pred xs)
(arr.find pred xs)
(arr.find-indexed pred xs)
(arr.some? pred xs)
(arr.every? pred xs)
(arr.min-by f xs)
(arr.max-by f xs)
(arr.first xs)
(arr.second xs)
(arr.last xs)
(arr.nth xs n)
(arr.rest xs)
(str.count s)
(str.get s index)
(str.slice s start [end])
(str.contains? s needle)
(str.split s sep)
(str.join parts sep)
(str.trim s)
(str.trim-prefix s prefix)
(str.trim-suffix s suffix)
(str.starts-with? s prefix)
(str.ends-with? s suffix)
(str.index-of s needle)
(str.last-index-of s needle)
(str.replace s old new [count])
(str.lower s)
(str.upper s)
(set.contains? s value)
(set.union lhs rhs)
(set.intersection lhs rhs)
(set.difference lhs rhs)
(set.union! target source)
(set.intersection! target source)
(set.difference! target source)
(set.subset? lhs rhs)
(set.superset? lhs rhs)
(set.disjoint? lhs rhs)
(set.add s value)
(set.add! s value)
(set.remove s value)
(set.remove! s value)
(empty? xs)
(count xs)
(get xs i)
(get user .name)
(get m k default)
(slice xs start end)
(contains? collection key)
(in value collection)
(not-in value collection)
(update! place f args...)
(assoc value.field new-value)
(delete! map key)
```

Cross-family collection helpers live in `kvist:core`: `count`,
`empty?`, `get`, `slice`, `contains?`, `in`, `not-in`, `update!`, `assoc`,
and `delete!`. Other collection operations should use explicit package names
such as `arr.*`, `map.*`, `str.*`, or `set.*`.

The access and trimming helpers use the direct Odin representation where
possible. Direct access syntax and call-shaped helpers are equivalent where both
apply:

```clojure
user.name      ;; (get user .name)
xs[i]          ;; (get xs i)
xs[start:end]  ;; (slice xs start end)
```

Mutation uses the same place model:

```clojure
(set! place value)         ;; assign
(mut! place += value)      ;; compound operator mutation
(update! place f args...)  ;; functional mutation
(delete! map key)          ;; remove a map key in place
(inc! place)               ;; unary place mutation; also dec!, toggle!, negate!
(discard expr...)          ;; intentional ignore for non-owned values
```

`assoc` is the shallow non-mutating value-update counterpart:

```clojure
(assoc user.name "Ada")
(-> user
  (assoc .name "Ada")
  (assoc .active? true))
```

It copies the root struct value, updates the selected field on the copy, and
returns the copy. It does not deep-copy owned fields.

`for` is the expression form for building owned collections from other
collections:

```clojure
(for [user users :let [decade (* (/ user.age 10) 10)] :when user.active]
  :into [dynamic]Row
  (Row {name: user.name decade: decade}))

(for [user users :when user.active]
  :into map[string]User
  [user.id user])

(for [user users :while (< user.age 65) :when user.active]
  :into set[string]
  user.id)
```

Without `:into`, Kvist infers a `[dynamic]T` result when the yielded expression
has an obvious type. Map output requires a yielded `[key value]` vector. Set
output inserts the yielded value as the member. Use `each` when the loop exists
for side effects, mutation, logging, or early return.

`arr.first`, `arr.second`, `arr.last`, and `arr.nth` lower to indexing.
Direct expression indexes can be written as attached brackets, for example
`cells[(idx x y)]`, and work in reads, `set!`, and `mut!` places.
`empty?` lowers to `len`. `arr.rest`, `arr.take`, `arr.drop`, `arr.butlast`,
`arr.drop-last`, `arr.take-while`, and `arr.drop-while` return non-owning slice
views. Three-argument `get` is a map
helper: it uses Odin's
comma-ok lookup and returns the supplied default when the key is absent.

Builder helpers such as `arr.map`, `arr.filter`, `arr.remove`,
`arr.map-indexed`, `arr.keep`, `arr.mapcat`, `concat`, `arr.into`,
`arr.interpose`, `arr.interleave`, `arr.reverse`, `arr.shuffle`,
`arr.range`, `arr.repeat`, `arr.repeatedly`, `arr.iterate`, bounded
`arr.cycle`, and `arr.take-nth`
return owned dynamic arrays. `into` is for explicit dynamic-array
targets, for example `(arr.into [dynamic]int xs)`. `arr.distinct` and
`arr.distinct-by` also
return owned dynamic arrays and use a temporary `map[key]bool` internally, so
the value or key must be valid as an Odin map key. `map.zip`, `arr.index-by`,
and `arr.frequencies` return owned maps. `map.merge` returns an owned map that combines
two input maps, with right-hand values replacing duplicate keys. `map.keys` and
`map.vals` return owned dynamic arrays copied from a map. `arr.group-by` returns
an owned map whose values are owned dynamic arrays; delete each group before deleting
the map. `arr.count-by` and `arr.sum-by` return owned maps for common aggregate
cases where the grouped items themselves are not needed. `arr.partition`,
`arr.partition-all`, and `arr.partition-by` return owned dynamic arrays of
borrowed slice chunks. `arr.keep` is
Odin-shaped: the callback returns `(value, ok)`, and only `ok` values are
appended. `arr.mapcat` is also Odin-shaped: the callback returns a borrowed
slice, and `arr.mapcat` appends those values into one owned dynamic array.

Scalar scan helpers such as `arr.reduce`, `arr.reduce-indexed`, `arr.find`,
`arr.find-indexed`, `arr.some?`, `arr.every?`, `arr.min-by`, and `arr.max-by`
scan in place and return a scalar or small tuple. They do not allocate output
collections.

Captured callbacks are supported for the ordinary package helper path when the
callback is non-escaping. This includes helpers such as `arr.map-indexed`,
`arr.reduce`, `arr.reduce-indexed`, `arr.take-while`, `arr.drop-while`,
`arr.find`, `arr.find-indexed`, `arr.some?`, `arr.every?`, `arr.min-by`, and
`arr.max-by`.

`sort` and `sort-by` copy before sorting. They do not mutate the input
collection, and their result is owned.
Captured callbacks are not supported for `sort-by`; use a named
non-capturing key function or an explicit context-aware sort helper.

`shuffle` also copies before shuffling. It takes an explicit picker function
instead of hiding a random generator:

```clojure
(defn pick [n: int] -> int
  (rand.int-max n))

(arr.shuffle pick xs)
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

String helpers stay close to Odin `core:strings`. `kvist:str` is a shipped
`.kvist` package. `str.count`, `str.get`, `str.slice`, `str.contains?`,
`str.split`, `str.join`, `str.trim`, `str.trim-prefix`, `str.trim-suffix`,
`str.starts-with?`, `str.ends-with?`, `str.index-of`, `str.last-index-of`,
`str.replace`, `str.lower`, and `str.upper` lower to direct indexing,
slicing, or `strings.*` calls.
`str.split` returns an owned dynamic array of string slices. `str.join` and
`str.replace` return owned strings and should be deleted or returned like
other owned values.

Set helpers stay explicit about the underlying Odin representation: a set is
`map[T]bool` in the emitted code. `kvist:set` is a shipped `.kvist` package.
Helpers such as `set.empty`, `set.of`, `set.contains?`, `set.union`,
`set.intersection`, `set.difference`, `set.union!`, `set.intersection!`,
`set.difference!`, `set.add`, `set.add!`, `set.remove`, `set.remove!`,
`set.subset?`, `set.superset?`, and `set.disjoint?` lower to tight loops,
direct constructors, or direct in-place mutations over that map
representation.

Map helpers follow the same hybrid rule. `kvist:map` is a shipped `.kvist`
package with helpers such as `map.empty`, `map.of`, `map.get`,
`map.contains?`, `map.keys`, `map.vals`, `map.zip`, `map.assoc`,
`map.assoc!`, `map.dissoc`, `map.dissoc!`, `map.merge`, and `map.merge!`.
Those lower to plain Odin
constructors, membership checks, preallocated dynamic arrays, raw indexing,
optional-default helpers, direct key/value loops, or direct in-place mutation.

`kvist:arr` is a shipped `.kvist` package with the broad sequence helper
surface. Many helpers are implemented directly in package source, including
the indexing/slicing layer, the ordinary function-callback path for `arr.map`,
`arr.filter`, `arr.remove`, `arr.reduce`, `arr.reduce-indexed`, `arr.min-by`,
and `arr.max-by`, and the ordinary function-predicate path for
`arr.take-while`, `arr.drop-while`, `arr.find`, `arr.find-indexed`,
`arr.some?`, and `arr.every?` via `#force_inline` loops. Constructors like `arr.empty`,
`arr.dynamic`, `arr.fixed`, mutators like `arr.push!`, `arr.map!`,
`arr.filter!`, `arr.remove!`, `arr.keep!`, and the wider grouping,
partitioning, and sorting helper surface still lower through a smaller
intrinsic substrate where that keeps codegen and allocation behavior direct.

Dot selectors are field selectors in supported higher-order helper positions.
They read a field from the current element without requiring a tiny anonymous
function:

```clojure
(arr.map .name users)
(arr.index-by .id users)
(arr.group-by .status users)
(arr.count-by .status users)
(arr.sum-by .region .amount orders)
(arr.partition-by .status users)
(arr.distinct-by .id users)
(arr.sort-by .age users)
(arr.sort-by! .age users)
(arr.filter .verified users)
(arr.remove .archived users)
(->> users
     (arr.filter .verified)
     (arr.map .name))
```

For example, `(arr.map .name users)` is the field-selector form of
`(arr.map (fn [user] user.name) users)`. This is field access for structs and
struct-like values, not map lookup.

## Allocation And Performance

The default sequence helpers prefer clear ownership over minimum allocation. A
chain of owned helpers allocates at each owned step:

```clojure
(->> users
     (arr.filter active?)
     (arr.map .name)
     (arr.sort))
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
- use bang helpers such as `arr.sort!`, `arr.reverse!`, `arr.shuffle!`, `arr.map!`, `arr.filter!`,
  `arr.remove!`, `arr.keep!`, `arr.into!`, and `map.merge!` when mutating existing storage is the
  right Odin choice;
- write an explicit `each` loop when one pass and no intermediate collection is
  needed;
- avoid `arr.group-by` when only aggregate totals are needed. Use `arr.count-by` or
  `arr.sum-by` for simple aggregate maps, or accumulate directly into maps for
  custom stateful aggregates.

The useful distinction is not "helpers versus loops". It is whether the
intermediate collection is a real value in the program.

Use eager helpers when the intermediate value has meaning:

```clojure
(let [settled (arr.map settle-order orders)
      paid (arr.filter settled? settled)
      groups (arr.group-by .region paid)]
  ...)
```

Use bang helpers when you own a working buffer:

```clojure
(let [work (arr.map settle-order orders)]
  (arr.filter! settled? work)
  ...)
```

Use aggregate helpers when grouped slices would be waste:

```clojure
(let [work (arr.map settle-order orders)]
  (arr.filter! settled? work)
  (let [revenue-by-region (arr.sum-by .region .amount work)
        count-by-region (arr.count-by .region work)]
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
        (set! revenue-by-region[settled.region]
              (+ revenue-by-region[settled.region]
                 settled.amount))
        (set! count-by-region[settled.region]
              (+ count-by-region[settled.region]
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

The `examples/collections/orders-report.kvist` example also includes an
`aggregate-helper-report-score` variant that uses `sum-by` and `count-by`. The
focused aggregate benchmark compares that shape with the grouped version and a
direct aggregate loop. Its expected result is lower allocation than `group-by`,
but still slower and more allocating than the direct fused loop because
settling, filtering, summing, and counting remain separate passes.

## Helper Boundaries

The eager sequence library is deliberately small and direct. Dynamic-array
append is covered by `into!`; map merge is covered by explicit `merge` and
`merge!`. These are concrete helpers, not a polymorphic collection protocol.

Avoid helpers that imply lazy sequence semantics, nil-as-empty behavior, or a
collection protocol. Prefer an explicit loop in user code when a helper's
lowering would be surprising.

Concrete rules:

- `into` constructs an owned dynamic array from a borrowed collection,
  and `into!` means dynamic-array append lowering directly to
  `append(&target, ..xs)`.
- map combination is explicit `merge`/`merge!`.
- `shuffle` and `shuffle!` are implemented with an explicit picker callback. The
  caller owns the randomness policy; Kvist only performs the swaps.
- `distinct` and `distinct-by` are implemented with temporary `map[key]bool`
  storage.

## Bounded Producers

Producer helpers are eager and bounded. The amount of work and allocation is
visible in the call:

Avoid unbounded forms such as plain `cycle`, unbounded `repeat`, unbounded
`repeatedly`, or unbounded `iterate`. Use explicit counts:

```clojure
(arr.range start end step)
(arr.repeat n x)
(arr.repeatedly n f)
(arr.iterate n f x)
(arr.cycle n xs)
```

`cycle` returns an owned dynamic array containing at most `n` items by cycling
over the input slice. It returns an empty owned dynamic array when `n <= 0` or
the input is empty.

## Threading And Cleanup

Threading forms should remain part of the language because they make nested
data flow much easier to read:

```clojure
(->> users
     (arr.filter active?)
     (arr.map .name)
     (arr.take 10))
```

The hard part is ownership. If a thread step allocates and its result is passed
directly into the next step, the compiler must not lose the only handle to that
owned value.

Production-style code can always bind owned intermediate results explicitly:

```clojure
(let [active-users (arr.filter active? users)
      active-names-all (arr.map .name active-users)
      active-names (arr.take 10 active-names-all)]
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

## Ownership And Allocation

Sequence helpers need an explicit ownership story:

- Slice-view helpers such as `rest`, `take`, `drop`, `butlast`, `drop-last`,
  `take-while`, `drop-while`, and `split-at` do not own data and must not be
  deleted.
- Dynamic-array helpers such as `arr.map`, `arr.filter`, `arr.remove`, `arr.map-indexed`,
  `arr.keep`, `arr.mapcat`, `concat`, `arr.reverse`, `arr.shuffle`, `arr.sort`, `arr.sort-by`, and
  `arr.take-nth` allocate and return owned dynamic arrays.
- Scalar scan helpers such as `arr.reduce`, `arr.reduce-indexed`, `arr.find`,
  `arr.find-indexed`, `arr.some?`, `arr.every?`, `arr.min-by`, and `arr.max-by`
  do not allocate output collections.
- Chunking helpers `arr.partition`, `arr.partition-all`, and `arr.partition-by` allocate the
  outer dynamic array, but their slice chunks borrow the input collection.
- `map.merge`, `map.zip`, `arr.index-by`, `arr.count-by`, `arr.sum-by`, and `arr.frequencies`
  allocate and return owned maps.
- `map.keys` and `map.vals` allocate and return owned dynamic arrays copied from a map.
- `arr.group-by` allocates an owned map and one owned dynamic array per key. Delete
  the groups, then delete the map.
- Owned helper results must be bound or returned. Nested owned results such as
  `(arr.first (arr.map f xs))` are rejected because there is no visible place to delete
  the intermediate dynamic array.
- Examples that use allocating helpers should show `defer delete(...)` when the
  result lives beyond a trivial expression.
This is a documentation and examples requirement, not just an implementation
detail. Kvist should help make Odin ownership easier to see, not easier to
forget.

See `docs/OWNERSHIP.md` for the broader ownership rules used by examples and
tooling.
