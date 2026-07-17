# Data-oriented programming in Kvist

`Data` is Kvist's immutable heterogeneous value for messages, application
state, configuration, queries, HTML-shaped trees, and evolving schemas. It
provides a Clojure-familiar vocabulary without importing Clojure's lazy
sequence or garbage-collected execution model.

```clojure
(import data "kvist:data")

(defn visible-titles [matters: Data] -> Data
  (->> matters
       (data.filter visible?)
       (data.remove archived?)
       (data.map title-data)
       (data.sort-by title-rank)))
```

Every operation above is eager. Each intermediate binding is an immutable,
owned `Data` value whose lifetime the compiler manages deterministically.

## Choosing Data or native values

Use `Data` when:

- values cross a dynamic boundary;
- keys or shapes evolve independently of compiled native code;
- collections contain heterogeneous values;
- the value should remain EDN-shaped for storage, transport, inspection, or
  structural transformation;
- immutable sharing is more useful than in-place mutation.

Prefer native structs and homogeneous arrays when:

- a shape is stable and used throughout an internal subsystem;
- field access and compact concrete representation dominate;
- numeric loops need maximum throughput;
- mutation is local, explicit, and useful;
- an API already has a natural native type.

Decode at a boundary when native code should own the resulting shape:

```clojure
(let [[settings error ok] (data.decode Settings message)]
  (if ok
    (start settings)
    (report error)))
```

Use `data.validate` when code should keep operating on the original Data after
checking the same native shape. Validation does not construct the native
target.

## Sequential Data

Sequential collection functions accept nil, list, vector, and set Data. Maps
use explicit map operations. Strings use string operations rather than an
implicit character sequence.

Accessors borrow from the input:

```clojure
(data.first values)
(data.second values)
(data.last values)
(data.peek stack)
(data.nth values 4)
```

`first`, `second`, `last`, `peek`, and `nth` return nil Data when the requested
item is absent. `peek` reads the front of a list and the back of a vector.
`pop` preserves list/vector stack behavior and rejects empty inputs.

Selection operations return owned vector Data:

```clojure
(data.rest values)
(data.take 10 values)
(data.drop 10 values)
(data.take-while active? values)
(data.drop-while active? values)
(data.take-nth 3 values)
```

Set traversal follows deterministic backing order, but set equality remains
order independent. Do not give backing order application meaning.

## Eager transformations

Transform callbacks receive borrowed items and have statically checked types:

```clojure
(defn summarize [matter: Data] -> Data
  {:id (get matter :id)
   :title (get matter :title)})

(data.map summarize matters)
(data.map-indexed label-by-index matters)
(data.filter visible? matters)
(data.remove archived? matters)
(data.keep optional-summary matters)
(data.mapcat child-matters matters)
```

`keep` drops Data nil and keeps every other value, including boolean false.
There is no ambient truthiness conversion.

Results are complete immutable values, normally vectors. `concat`, `reverse`,
`interpose`, `distinct`, and `distinct-by` follow the same eager rule.
`sort-by` accepts a native ordered callback key and computes it once per item;
`sort-with` accepts an explicit Data comparator.

Bulk functions append retained items to an internal native buffer and freeze
that buffer into one immutable node. They do not build flat vectors with
repeated immutable `conj`.

## Reduction and search

Reduction always has an explicit initial value:

```clojure
(data.reduce
  (fn [total: i64, matter: Data] -> i64
    (if (= (get matter :status) :done)
      total
      (+ total 1)))
  (i64 0)
  matters)
```

The explicit init fixes the accumulator type and defines the empty result.
There is no zero-argument or one-item reducer protocol.

Predicates return native `bool`:

```clojure
(data.some? urgent? matters)
(data.every? valid? matters)
(data.not-any? archived? matters)
```

Kvist uses `some?`, not Clojure's result-returning `some`. Use `data.find` when
the matching item is needed:

```clojure
(let [[matter ok] (data.find urgent? matters)]
  ...)
```

`find`, `find-indexed`, `min-by`, and `max-by` return borrowed input items plus
an `ok` flag.

## Maps and entries

Map functions traverse key/value backing directly where possible:

```clojure
(data.select-keys message [:id :status])
(data.merge defaults overrides)
(data.merge-with combine-count defaults overrides)
(data.update-keys canonical-key message)
(data.update-vals normalize-value message)
(data.filter-entries public-entry? message)
(data.reduce-kv add-entry init message)
```

`data.group-by`, `data.index-by`, and `data.frequencies` return immutable map
Data. Group values are vectors and preserve input order.

Use `data.entries` when entry vectors are the desired data representation.
`data.map-entries` passes key and value separately to avoid allocating input
entry vectors; its callback returns one `[key value]` Data value.

`data.keys` and `data.vals` return vector Data, so they remain composable:

```clojure
(->> (data.vals message)
     (data.filter valid?)
     (data.map normalize))
```

## Paths

Nested operations use list or vector Data paths:

```clojure
(data.get-in message [:request :credentials])
(data.assoc-in message [:request :attempts] 1)
(data.update-in message [:request :status] next-status)
(data.dissoc-in message [:request :credentials])
```

The expected `Data` parameter makes ordinary vector syntax contextual Data.
`get-in` accepts an empty path and borrows the input. `assoc-in` and
`update-in` require a non-empty path. Missing or nil intermediate map values
become maps. `dissoc-in` preserves empty parents.

## Ownership

The practical rules are:

- element access and successful search borrow from their input;
- collection transformations return owned Data;
- a result node retains every child it stores;
- static quoted Data is immortal, so retain/release are no-ops;
- ordinary bindings, assignment, arguments, and returns are compiler managed;
- native containers containing Data require an explicit ownership contract.

Use the native-array escape hatch only when an API requires concrete storage:

```clojure
(let [items (data.to-owned-array values)
      :defer-with data.delete-owned-array!]
  (call-native items[:]))
```

`to-owned-array`, `keys-owned-array`, and `vals-owned-array` retain every Data
element. `delete-owned-array!` releases those references and deletes the native
storage. A plain `delete` is insufficient for these arrays.

Owned and borrowed callback results are both safe. Eager builders retain the
value they accept, while compiler-managed callback temporaries release exactly
once. Fused transforms similarly clean Data intermediates that a later filter
rejects.

## Fused transforms

Several eager helpers in a row intentionally create intermediate immutable
results. When that allocation matters, use a fused transform:

```clojure
(deftransform visible-summaries
  (filter visible?)
  (remove archived?)
  (map matter-summary))

(into Data visible-summaries matters)
```

A list, vector, set, or nil Data value is a direct transform source.
`into Data` collects into one vector builder and freezes once. No lazy sequence
or intermediate array is created.

Use `transduce` for a scalar result:

```clojure
(transduce
  (filter visible?)
  count-visible
  (i64 0)
  matters)
```

Sorting still materializes because ordering requires all selected items.

## Construction

Contextual literals are the normal constructor:

```clojure
(defn response [id: string, values: Data] -> Data
  {:request-id id
   :values values})
```

`data.vec`, `data.list`, and `data.set` convert sequential Data. `data.into`
adds a sequential source to an existing list, vector, set, or map Data value.

Low-level native boundaries use `list-from-array`, `vector-from-array`,
`set-from-array`, and `map-from-alternating`. Application code rarely needs
them.

## Important false friends

- Data `map`, `filter`, and friends are eager, not lazy.
- Maps do not implicitly become sequences of entries.
- Predicates return native booleans; Data has no general truthiness.
- `some?` returns bool; `find` returns an item and `ok`.
- `reduce` always takes an init value.
- `rest`, `take`, and `drop` return vector Data.
- `contains?` is map/set membership. Use `data.includes?` for sequential value
  membership.
- Data paths are list/vector Data, not arbitrary seqable values.
- Immediate collection backing is flat; immutable updates share nested
  subtrees but copy the changed immediate collection.
- Deterministic reference counting replaces garbage collection.

See [the executable message pipeline](../examples/data/message-pipeline.kvist)
for a realistic transformation written almost entirely with Data.
