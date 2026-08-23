# Immutable Data collection API: audit and proposal

Status: implemented initial surface. The historical audit in “Current surface”
describes the pre-implementation surface at `f4a57647`; the decisions and API
tables that follow describe the cleaned contract now implemented.

The goal is Clojure's collection vocabulary over immutable `Data`, with eager
execution, static callback types, deterministic ownership, and no universal
sequence abstraction. Native arrays and fused transforms remain the alternatives
when representation or allocation control matters.

## Decisions in brief

- Collection operations are eager. Transforming operations normally return
  owned vector `Data`.
- `nil`, lists, vectors, and sets form the sequential input domain. Maps use
  explicit entry or key/value operations. Strings stay with string operations.
- There is no general `seq`, truthiness protocol, lazy result, or zero-argument
  reduction.
- Callbacks are statically typed. Predicates return native `bool`, reducers may
  use a native or `Data` accumulator, and collection-producing callbacks return
  `Data`.
- `data.some?` returns native `bool`; there is no Clojure-style `some` returning
  an arbitrary truthy predicate result. `data.find` returns the matching input
  element and an `ok` flag.
- Map iteration uses key/value callbacks where possible. `data.entries` is the
  explicit entry-vector representation.
- `data.map` becomes the eager transformation. The alternating native-array map
  constructor becomes `data.map-from-alternating` and should normally remain an
  implementation boundary.
- `data.keys` and `data.vals` return `Data`. Native-array conversions are
  explicit and own retained element references.
- All nested operations accept list or vector `Data` paths. Ordinary contextual
  vectors such as `[:request :credentials]` are the normal spelling.
- Bulk operations use an internal builder and freeze once. The initial public
  API does not expose transients.
- A `Data` list, vector, or set can become a fused-transform source. `into Data`
  means collect transformed `Data` items into vector `Data`.

## Current surface

### `kvist:data`

| Area | Current names | Current contract |
| --- | --- | --- |
| Scalar construction | `from-nil`, `from-bool`, `from-int`, `from-float`, `from-string`, `from-symbol`, `from-keyword` | Owned `Data`; text is cloned |
| Collection construction | `list`, `vector`, `set`, `map`, `empty-map`, `tagged` | Owned `Data`; children are retained; `map` consumes alternating values from `[]Data` |
| Explicit lifetime | `retain`, `release`, `append-retained!` | Manual ownership for native storage |
| Persistent updates | `assoc`, `dissoc`, `dissoc-in`, `conj`, `append`, `merge`, `update`, `assoc-in`, `update-in` | Owned results; immediate flat backing is copied and children are retained |
| Payload access | `int`, `float`, `bool`, `string`, `symbol`, `keyword`, `text`, `tag`, `tagged-value`, `kind` | Scalars by value; text and tagged payload are borrowed |
| Kind predicates | `nil?`, `bool?`, `int?`, `float?`, `string?`, `symbol?`, `keyword?`, `list?`, `vector?`, `map?`, `set?`, `tagged?` | Native `bool` |
| Traversal | `count`, `key-at`, `value-at`, `item-at`, `nth`, `get-in`, `keys`, `vals` | Indexed access is borrowed; `get-in` currently returns owned `Data`; `keys` and `vals` return owned native arrays whose elements borrow from the source |
| Boundary checks | `decode-error`, `decode`, `validate`, `decode-int`, `decode-int-at`, `decode-float`, `decode-float-at`, `decode-bool`, `decode-bool-at` | Typed native result/error tuples; paths are `Data` |

Important implementation properties:

- Runtime nodes are atomically reference counted. Quoted static values have no
  node and retain/release are no-ops.
- Collection constructors reserve their final input capacity and retain each
  accepted child. Set and map duplicate detection is linear because backing is
  flat.
- `assoc`, `dissoc`, `conj`, and `append` allocate one new immediate backing
  node and retain unchanged children. Nested subtrees are therefore shared, but
  immediate maps and collections are copied.
- `merge` is currently repeated immutable `assoc`; it can copy the growing map
  once per right-hand entry.
- `assoc-in` and `update-in` currently take native `[]Data`. `dissoc-in` takes
  list or vector `Data`. `get-in` also takes native `[]Data`.
- `data.keys` and `data.vals` allocate only the native array backing. They do not
  retain its elements, so the source map must outlive every array use.
- `data.nth` delegates to `get`, returns borrowed nil for an out-of-range list
  or vector index, and does not traverse sets. `item-at` traverses set backing
  order but asserts on an invalid index.

### Unqualified compiler/core operations on `Data`

| Operation | Current `Data` behavior |
| --- | --- |
| `get` | Borrowed map value or list/vector item; missing returns nil `Data`; optional default is supported |
| `count` | Map entry count, list/vector/set item count, or string byte count; other kinds return zero |
| `empty?` | Expands through `count`; consequently scalar `Data` currently appears empty |
| `contains?` | Map key membership; set membership; currently also value membership for lists and vectors |
| `=` / `!=` | Structural equality/inequality; map and set equality are order independent |
| `assoc` | Owned map update or in-range vector replacement |
| `update` | Owned map/vector update with statically checked updater and optional extra arguments |
| `dissoc` | Owned map result; accepts one or more keys |
| `dissoc-in` | Owned map result; path is list/vector `Data` |

These are compiler-supported because their lowering depends on the target type
or managed lifetime. The qualified package forms remain useful at an explicit
boundary.

Current false friends to fix or document:

- `(get m k fallback)` uses nil as the fallback test. A present key whose value
  is nil therefore returns `fallback`, unlike Clojure.
- `contains?` on list/vector tests values. Clojure rejects lists and tests
  vector indices.
- `empty?` reports true for scalar `Data` because non-collection `count` is zero.
- `nth` is currently package-qualified and has argument order
  `(data.nth collection index)`, while `arr.nth` is `(arr.nth index xs)`.

The cleaned contract should preserve `contains?` as existing `Data` membership
for set and map only. List/vector value membership should move to a deliberately
named operation such as `data.includes?`; vector index presence is better
expressed as an explicit bounds check. `get` with a default must distinguish
absence from a present nil value.

### Equivalent native-array surface

`kvist:arr` already provides much of the vocabulary and establishes useful
strict contracts:

| Area | `kvist:arr` |
| --- | --- |
| Access/views | `first`, `second`, `nth`, `last`, `rest`, `take`, `drop`, `drop-last`, `butlast`, `slice`, `split-at` |
| Eager transforms | `map`, `map-indexed`, `filter`, `remove`, `keep`, `mapcat`, `concat`, `reverse`, `interpose`, `interleave`, `distinct`, `distinct-by`, `sort`, `sort-by` |
| Reduction/search | `reduce`, `reduce-indexed`, `some?`, `every?`, `find`, `find-indexed`, `min-by`, `max-by` |
| Grouping | `partition`, `partition-all`, `partition-by`, `index-by`, `group-by`, `count-by`, `sum-by`, `frequencies` |
| Construction | `empty`, `dynamic`, `fixed`, `into` |
| Mutating variants | `map!`, `map-indexed!`, `filter!`, `remove!`, `keep!`, `reverse!`, `sort!`, `sort-by!`, `into!`, removal helpers |
| Sources | `range`, `take-nth`, `repeat`, `repeatedly`, `iterate`, `cycle` |

Array access and slice-returning helpers borrow or alias input storage. Eager
array transforms return an owned native dynamic array, whose elements follow
their native type's ownership rules. `arr` does not automatically make native
containers of `Data` own their elements.

The Data API should align callback order and edge behavior with `arr` where
that does not violate the immutable Data model. It should not duplicate
mutating `!` operations.

## Common domains, ordering, and result kinds

The proposal uses these terms:

- **Sequential Data**: nil, list, vector, or set.
- **Indexed Data**: list or vector.
- **Associative Data**: map or vector where the operation explicitly permits
  vector indices.
- **Map-like Data**: map or nil, with nil treated as an empty map.

Sequential traversal order is list/vector item order and set backing order.
Map traversal order is backing entry order. Runtime and quoted backing order is
deterministic, but map/set equality remains order independent and callers
should not use that order as domain meaning.

Unless stated otherwise:

- nil is an empty sequential input;
- map input is rejected by sequential functions;
- strings and scalar Data are rejected;
- collection-producing functions return owned vector `Data`;
- access/search results borrow from their input;
- predicates return native `bool`;
- negative counts are clamped to zero and oversized counts are clamped to the
  collection count, matching `kvist:arr`;
- `take-nth` with a non-positive step returns an empty vector, deliberately
  matching `kvist:arr` rather than Clojure's error.

## Proposed API

Signatures below are contracts, not a commitment to whether the implementation
is a `defn`, macro, overload, or compiler-recognized package call. `$A` is a
statically inferred accumulator type and `$K` is a statically checked key type.

### Sequential access

| Operation | Result and behavior |
| --- | --- |
| `empty? collection` | Native `bool`. True for nil and empty list/vector/set/string. Non-collection scalar Data is an error. Keep unqualified static dispatch. |
| `data.first collection` | Borrowed first item or nil for nil/empty sequential Data. |
| `data.second collection` | Borrowed index 1 or nil when absent. |
| `data.last collection` | Borrowed last item or nil when absent. |
| `data.rest collection` | Owned vector of all but the first item; nil/empty becomes `[]`. |
| `data.butlast collection` | Owned vector of all but the last item; nil/empty becomes `[]`. |
| `data.take n collection` | Owned prefix vector. |
| `data.drop n collection` | Owned suffix vector. |
| `data.take-while pred collection` | Owned longest prefix vector; `pred: Data -> bool`. |
| `data.drop-while pred collection` | Owned suffix vector; `pred: Data -> bool`. |
| `data.take-nth n collection` | Owned vector containing backing indexes `0, n, 2n...`; non-positive `n` gives `[]`. |
| `data.split-at n collection` | Two owned vectors; `n` clamps to the input bounds. |
| `data.partition n collection` | Owned vector of exact-size vector groups; short tail omitted. |
| `data.partition-all n collection` | Owned vector of vector groups; short tail included. |
| `data.partition-by f collection` | Owned adjacent groups split when structural Data callback keys change. |
| `data.peek collection` | Borrowed last vector item or first list item; nil for nil/empty. Sets are rejected. |
| `data.pop collection` | Owned same-kind list/vector without its stack item. Empty and nil inputs are errors. Sets are rejected. |

`rest`, `butlast`, `take`, and `drop` return vectors even for list and set
inputs. Without a lazy sequence abstraction, a consistent eager result is more
useful than reproducing Clojure's concrete sequence types. `pop` is the
exception because its stack semantics are specifically collection preserving.

Keep `data.nth collection index` as borrowed nil-on-missing indexed access.
Add an optional fallback overload only after `get` correctly distinguishes a
missing item from a present nil value.

### Transformation and ordering

| Operation | Callback/result |
| --- | --- |
| `data.map f collection` | `f: Data -> Data`; owned vector |
| `data.map-indexed f collection` | `f: (int, Data) -> Data`; owned vector |
| `data.filter pred collection` | `pred: Data -> bool`; owned vector of original items |
| `data.remove pred collection` | Complement of `filter`; owned vector |
| `data.keep f collection` | `f: Data -> Data`; drop nil results, retain all other Data including `false` |
| `data.keep-indexed f collection` | Indexed `keep` |
| `data.mapcat f collection` | `f: Data -> Data`; each result must be sequential Data; owned flattened vector |
| `data.concat collections...` | Eager concatenation of sequential Data into an owned vector; zero inputs gives `[]` |
| `data.reverse collection` | Owned vector |
| `data.interpose separator collection` | Owned vector; separator is retained for each insertion |
| `data.interleave left right` | Owned alternating vector; stops at the shorter input |
| `data.distinct collection` | Stable first occurrence by structural Data equality; owned vector |
| `data.distinct-by f collection` | Stable first key; `f: Data -> $K`, where `$K` supports equality |
| `data.sort-by f collection` | Stable ascending sort; `f: Data -> $K`, where `$K` is a native ordered type |
| `data.sort-with before? collection` | Stable sort with `before?: (Data, Data) -> bool` |

There is no initial `data.sort` over arbitrary `Data`: heterogeneous Data has
no honest natural ordering. `sort-by` covers the common statically typed case
and computes each key once. A comparator form covers application-defined Data
ordering.

`keep` uses Data nil as an explicit filtering sentinel, not general truthiness.
Owned callback results are consumed exactly once; borrowed callback results are
retained by the output builder.

### Reduction, predicates, and search

| Operation | Contract |
| --- | --- |
| `data.reduce f init collection` | `f: ($A, Data) -> $A`; eager left fold; empty returns `init` |
| `data.reduce-kv f init map` | `f: ($A, Data, Data) -> $A`; direct key/value traversal with no entry allocation |
| `data.some? pred collection` | `pred: Data -> bool`; native `bool`, stops at first true |
| `data.every? pred collection` | Native `bool`; empty is true |
| `data.not-any? pred collection` | Native `bool`; complement of `some?` |
| `data.not-every? pred collection` | Native `bool`; complement of `every?` |
| `data.find pred collection` | `[value: Data, ok: bool]`; borrowed matching item, or nil/false |
| `data.find-indexed pred collection` | `[index: int, value: Data, ok: bool]`; borrowed item, or `-1`/nil/false |
| `data.min-by f collection` | `[value: Data, ok: bool]`; borrowed first minimum; native ordered key |
| `data.max-by f collection` | `[value: Data, ok: bool]`; borrowed first maximum; native ordered key |

Only the explicit-init reduction is proposed. It gives the accumulator a
static type, has an unambiguous empty result, and avoids requiring a zero-arity
or one-arity reducer protocol.

Kvist predicates are native booleans and Data has no ambient truthiness.
Consequently the Clojure name `some` would promise the wrong contract.
`some?` answers the boolean question; `find` returns an input item; `keep`
implements optional Data production. A callback that needs a typed optional
native result should use native arrays/transforms and `[value, ok]`.

Map input is intentionally restricted to `reduce-kv` and entry operations.
There is no hidden conversion from a map to a sequence of pair objects.

### Map operations

| Operation | Contract |
| --- | --- |
| `data.select-keys map keys` | Owned map; key traversal order follows `keys`; absent keys omitted |
| `data.merge left right` | Owned map; right values win; nil is an empty map; build once |
| `data.merge-with f left right` | `f: (Data, Data) -> Data`; callback receives left then right value on collision |
| `data.update-keys f map` | `f: Data -> Data`; later transformed-key collisions win |
| `data.update-vals f map` | `f: Data -> Data`; source keys retained |
| `data.zipmap keys values` | Owned map; stops at shorter sequential input; later duplicate keys win |
| `data.map-entries f map` | `f: (Data, Data) -> Data`; callback returns `[key value]`; owned map |
| `data.filter-entries pred map` | `pred: (Data, Data) -> bool`; owned map |
| `data.group-by f collection` | `f: Data -> Data`; owned map from key to vector Data; groups preserve input order |
| `data.index-by f collection` | `f: Data -> Data`; owned map from key to item; later items win |
| `data.frequencies collection` | Owned map from item Data to integer Data count |
| `data.count-by f collection` | Owned map from structural Data callback key to integer Data count |

Key/value callbacks avoid allocating an entry vector per input map entry.
`map-entries` represents each transformed output pair as `[key value]` Data;
the entry value is validated before insertion.

Flat backing makes lookup and duplicate detection linear. These operations
should still use one output builder so they copy/freeze once; no HAMT is
required. Result entry order is:

- selected key order for `select-keys`;
- left entry order followed by new right keys for merge operations;
- source order, with replacement in the first insertion slot, for update and
  entry transformations;
- first-seen group/key order for `group-by`, `index-by`, and `frequencies`.

### Construction and conversion

| Operation | Contract |
| --- | --- |
| `data.vec collection` | Owned vector conversion; sequential Data input |
| `data.list collection` | Owned list conversion; sequential Data input |
| `data.set collection` | Owned set conversion, keeping first occurrences |
| `data.entries map` | Owned vector of owned two-item vector Data entries |
| `data.keys map` | Owned vector Data |
| `data.vals map` | Owned vector Data |
| `data.into target source` | Eagerly `conj` source items into list/vector/set Data target; list targets therefore prepend each item; maps require entry Data |
| `into Data transform source` | Compiler-supported fused collection into owned vector Data |
| `data.to-owned-array collection` | Owned `[dynamic]Data`; every element is retained |
| `data.keys-owned-array map` | Owned retained native array of keys |
| `data.vals-owned-array map` | Owned retained native array of values |
| `data.delete-owned-array! array` | Release all Data elements and delete native storage |

`data.into` is the ordinary eager value operation. The unqualified
three-argument `into` remains the fused transform consumer; `Data` as its
output type has the precise meaning “vector Data output”.

Rename native constructors:

| Current | Proposed |
| --- | --- |
| `data.list []Data` | `data.list-from-array []Data` |
| `data.vector []Data` | `data.vector-from-array []Data` |
| `data.set []Data` | `data.set-from-array []Data` |
| `data.map []Data` | `data.map-from-alternating []Data` |

Contextual literals are the normal public construction syntax. The
`*-from-array` functions are explicit native boundaries used by EDN, decoding,
and low-level packages. `map-from-alternating` should be private if package
visibility permits all required call sites to use an internal primitive.

Changing `keys` and `vals` is intentionally breaking. Kvist is alpha, and Data
results compose much better. The explicit owned native-array functions replace
the current arrays of borrowed references; no public API should return an
“owned array of borrowed Data” without making the source lifetime part of its
name and contract.

### Nested operations

Use the following common path contract:

```clojure
(data.get-in message [:request :credentials])
(data.assoc-in message [:request :credentials] credentials)
(data.update-in message [:request :attempts] increment)
(data.dissoc-in message [:request :credentials])
```

The expected `Data` parameter makes each ordinary vector a contextual vector
Data. Quoted list/vector paths continue to work. Native `[]Data` is not part of
the public path API.

| Operation | Empty path | Traversal/update |
| --- | --- | --- |
| `data.get-in` | Borrowed input value | Maps and existing list/vector indices; missing returns nil |
| `data.assoc-in` | Error: path must be non-empty | Maps and existing vector indices; missing/nil intermediate values become maps |
| `data.update-in` | Error: path must be non-empty | Same as `assoc-in`; accepts optional extra callback arguments |
| `data.dissoc-in` | Owned unchanged value | Map leaves; missing/non-map path returns owned unchanged value; empty parents remain |

Unqualified `dissoc-in` should use this same contract. `assoc-in` and
`update-in` may remain package-qualified until static core dispatch has another
target type that justifies unqualified forms.

Lists can be read by index but are not associatively updated. Set traversal is
not a valid nested path step. Vector updates require an existing in-range
index; nested operations do not silently grow vectors.

## Ownership contract

| Category | Contract |
| --- | --- |
| `first`, `second`, `last`, `peek`, `nth`, successful `find`, `min-by`, `max-by` | Borrow from the input; compiler-managed binding/return retains when a longer lifetime is needed |
| Collection-producing operation | Returns one owned `Data` reference |
| Reducer/predicate input items | Borrowed for the callback duration |
| Output item copied from input | Builder retains once |
| Borrowed callback `Data` result | Builder retains once |
| Owned callback `Data` result | Ownership transfers to builder or is released once when discarded |
| Native accumulator | Ordinary native value rules |
| `Data` accumulator | Compiler-managed move/retain/release on each replacement |
| Static quoted item | Retain/release are no-ops |
| Owned native Data array | Array owns one retained reference per element; deletion releases elements then storage |

Collection code must not infer callback ownership from naming. It must use the
inferred owned/borrowed result boundary, including specialized symbols,
inline functions, captures, and named multiple returns.

Panic/unwind and ordinary early-return paths must run builder cleanup. If a
callback result has been produced but not transferred, that result is cleaned
before leaving the iteration.

## Internal builders

Repeated immutable `conj` is quadratic for flat vectors. Every bulk operation
should instead lower to:

```text
Data input
  -> one direct traversal
  -> temporary vector/map builder with capacity hint
  -> one frozen immutable Data node
```

The minimum internal primitive set is:

- initialize vector/list/set builder with capacity;
- append a borrowed child by retaining it;
- append an owned child by transfer;
- initialize map builder with capacity;
- associate borrowed or owned key/value pairs;
- freeze once into owned `Data`;
- abort and release every accepted child.

The builder should own its dynamic storage and accepted references from
initialization until freeze/abort. A deferred abort guard makes callback or
validation failure cleanup deterministic. Freeze transfers the backing storage
to a runtime node and disables the guard.

Set/map builders may retain linear duplicate detection while backing is flat.
Capacity should be exact for map/filter/map-indexed/reverse/keys/vals when
known, an upper bound for filter/keep/distinct, and grown geometrically for
mapcat/group-by when output size is not known.

Keep this builder private initially. Add scoped public builders only when real
call sites cannot be served by contextual literals, eager functions, or fused
transforms.

## Fused transform integration

The current transform implementation does not accept `Data`:

- source inference recognizes native arrays, slices, maps, and `defiter`
  sources, but not `Data`;
- output inference recognizes native dynamic arrays, maps, and sets, but not
  `Data`;
- generated loops use native `len`/iteration and native append/assignment.

Add direct compiler lowering rather than a universal sequence interface:

- list/vector/set Data sources expose borrowed items and a count capacity hint;
- map Data is not an implicit value source; use an explicit entry/key-value
  source;
- `transduce` and `for :transform` iterate Data items directly;
- `into Data xf source` creates one vector builder, writes accepted Data values,
  and freezes once;
- `(data.entries map)` in a transform source position should be recognized as a
  direct map-entry source so the eager entry collection can be elided;
- transform pipeline lowering must track owned Data intermediates and release
  values filtered out or replaced by later map steps.

This makes the high-performance spelling concrete:

```clojure
(into Data
  (comp
    (filter visible?)
    (remove archived?)
    (map matter-summary))
  matters)
```

Sorting is necessarily a separate eager operation because it requires
materialization. A transform can fuse the prefix, then `data.sort-by` the one
materialized result.

## Intentional differences from Clojure

| Clojure expectation | Kvist decision |
| --- | --- |
| `map`, `filter`, `concat`, and friends are lazy | All Data collection functions are eager and owned |
| Most collections participate through `seq` | No universal sequence interface; accepted Data kinds are explicit |
| Maps implicitly sequence as entry vectors | Map APIs use key/value callbacks or explicit `entries` |
| Predicates use truthiness | Predicates return native `bool`; only `keep` treats Data nil specially |
| `some` returns a truthy predicate result | `some?` returns native `bool`; `find` returns an item plus `ok` |
| Two-arity `reduce` derives its init | Data `reduce` always requires a statically typed init |
| `rest` returns a sequence abstraction | Data `rest` returns owned vector Data |
| `sort` has a broad runtime comparison model | Use a statically ordered key or explicit comparator |
| Persistent collections imply trie-like asymptotics | Immediate backing remains flat until benchmarks justify a hybrid |
| GC hides retained substructure | Result and callback ownership is explicit and deterministic |
| `contains?` on a vector tests index presence | Data sequential value membership, if retained, uses `includes?`; `contains?` is map/set membership |
| Paths are any seqable value | Paths are list or vector Data |

## Delivery slices

The initial delivery completed all seven slices:

1. Renamed the native constructors; changed `keys`/`vals` to Data results; added
   explicit owned-array conversions; unified all path parameters as Data.
2. Added borrowed sequential access and direct reduction/search primitives.
3. Added private builders with abort cleanup and ownership-focused tests.
4. Added eager transformation and ordering functions.
5. Added fused Data source and `into Data` lowering.
6. Added map utilities using direct key/value traversal.
7. Added representative benchmarks without changing the flat backing.

Each slice should compile representative generated Odin in tests, run normal
tests and `--ownership-audit`, and include nested owned callback results.

## Test and benchmark checklist

Behavior tests:

- nil and empty list/vector/set/map inputs;
- list/vector/set traversal and duplicate behavior;
- stable backing order without treating map/set order as equality;
- map entry callbacks and entry-vector conversion;
- nested heterogeneous and contextual runtime values;
- static quoted inputs and zero-cleanup results;
- borrowed and owned callback results, including nested owned results;
- an owned callback result rejected by `filter` or discarded by `keep`;
- old values remain valid after updates and unaffected nested nodes are shared;
- builder abort/early-return cleanup;
- present nil versus missing map key with `get` default;
- every intentional difference in the table above.

Representative benchmark sizes are 8, 32, 128, 1,000, and 10,000 items. Measure:

- vector `map`, `filter`, `reduce`, and `group-by`;
- maps at useful corresponding sizes;
- repeated `assoc` and nested `assoc-in`;
- builder construction versus repeated `conj`;
- eager Data pipelines with intermediates versus fused `into Data`;
- Data transforms versus equivalent native-array transforms;
- retained/released callback results under ownership audit.

The first optimization target is eliminating avoidable intermediate backing
arrays and repeated flat copies. Representation changes remain evidence driven.
