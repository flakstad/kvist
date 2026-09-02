# Data

Most Kvist values are native Odin-shaped values: structs have fixed fields,
arrays have one element type, and ownership is explicit. `Data` is the
alternative for Clojure-shaped data whose structure is useful at runtime.

A single `Data` value can contain nil, booleans, integers, floats, strings,
symbols, keywords, lists, vectors, maps, sets, tagged values, and any nesting of
those values:

```clojure
(import data "kvist:data")

(def contact: Data
  {:name "Ada Lovelace"
   :born 1815
   :active? true
   :roles [:mathematician :programmer]
   :address nil})
```

The `Data` annotation tells the compiler that the map and nested vector are
Data rather than native homogeneous collections. This is one immutable value,
not a native struct containing several native collections. Its shape can be
inspected, transformed, printed as EDN, stored, or passed to code that
interprets the structure.

In practical terms, `Data` is EDN in memory. EDN is its text representation;
`Data` is the value a Kvist program reads, builds, and transforms.

## Clojure-Shaped Programming

Code built around Data can be almost identical to Clojure. This Clojure
function:

```clojure
(defn contact [name]
  {:name name
   :active? true
   :roles [:author :admin]})
```

becomes:

```clojure
(defn contact [name: string] -> Data
  {:name name
   :active? true
   :roles [:author :admin]})
```

The important addition is `-> Data`. It tells the compiler that the map and
nested vector are Data rather than native homogeneous collections. Parameters
and local bindings can provide the same context.

Collection pipelines retain their Clojure shape:

```clojure
(import data "kvist:data")

(defn active? [user: Data] -> bool
  (data.bool (:active? user)))

(defn user-name [user: Data] -> Data
  (:name user))

(defn active-names [users: Data] -> Data
  (->> users
       (data.filter active?)
       (data.map user-name)))
```

The remaining differences are deliberate:

- Data parameters and results use the `Data` type;
- callbacks have statically checked parameter and return types;
- predicates return native `bool`;
- scalar accessors such as `data.string` cross back to native values;
- collection operations are eager, not lazy;
- memory is managed deterministically, without garbage collection.

## Native Values And Data

Use a native struct when the shape is part of the compiled program:

```clojure
(defstruct Contact [
  name: string
  born: int
  active?: bool
])

(defn contact [name: string, born: int] -> Contact
  (Contact :name name :born born :active? true))
```

Fields and types are checked statically. Native arrays and maps are similarly
homogeneous and use Odin's ordinary allocation and cleanup rules.

Use `Data` when the shape itself is a value:

```clojure
(defn contact [name: string, born: i64, roles: Data] -> Data
  {:name name
   :born born
   :active? true
   :roles roles})
```

The `Data` return type gives the map and nested collections Data context.
Runtime expressions such as `name`, `born`, and `roles` are evaluated and
inserted into the result.

The same collection syntax therefore has two meanings:

```clojure
[1 2 3]                 ; native homogeneous collection

(def number-list: Data
  [1 2 3])               ; runtime Data vector from expected type

(defn numbers [] -> Data
  [1 2 3])               ; runtime Data vector from expected type
```

Quote has its usual Lisp meaning: preserve a form as data instead of evaluating
it. The resulting value is `Data`, but quote is not merely another spelling of
a `Data` type annotation:

```clojure
(def name "Ada")

(def evaluated: Data
  {:name name})           ; {:name "Ada"}

(def literal
  '{:name name})          ; {:name name}
```

Use a `Data` annotation when the intent is to select the Data representation
while still evaluating expressions inside the collection. Use quote when the
form itself is the value, including any symbols or lists it contains. Quoted
Data literals are compiled into static storage and require no cleanup. Runtime
Data is deterministically managed by the compiler.

## Working With A Value

Data uses familiar Clojure-shaped operations:

```clojure
(let [contact: Data
      {:name "Ada"
       :roles [:admin :author]}
      name (:name contact)
      roles (:roles contact)
      updated (assoc contact :active? true)]
  (println (data.string name)
           (data.includes? roles :admin)
           (data.bool (:active? updated))))
```

Lookup borrows from the input. `assoc`, `update`, and collection
transformations return new immutable Data values; the original remains valid.
Native values are recovered explicitly with accessors such as `data.string`,
`data.int`, and `data.bool`.

Nested destructuring works directly:

```clojure
(let [{:keys [name roles]
       :or {roles []}}
      contact
      [primary & remaining] roles]
  ...)
```

## Good Uses

Use `Data` when:

- the structure is a small language or protocol;
- values cross a dynamic boundary such as EDN, a database, or a message bus;
- keys and shapes evolve independently of compiled native code;
- collections contain heterogeneous values;
- applications need to inspect or transform the structure generically;
- immutable sharing is more useful than in-place mutation.

Prefer native structs and homogeneous arrays when:

- a shape is stable and used throughout an internal subsystem;
- field access and compact concrete representation dominate;
- numeric loops need maximum throughput;
- mutation is local, explicit, and useful;
- an API already has a natural native type.

### HTML As Data

The official [kvist-lang/html](https://github.com/kvist-lang/html) package
renders Hiccup-shaped Data. A vector represents an element, a map holds
attributes, and nested vectors are children:

```clojure
(import html "deps/html")

(defn page [title: string] -> string
  (html.render
    [:main {:class "page"}
     [:h1 title]
     [:p "Ready"]]))
```

`html.render` declares its argument as `Data`, so this vector literal constructs
a `Data` value and inserts `title` normally. The document can be built,
traversed, and transformed as data before it is rendered.

### Datomic Data

[VevDB](https://github.com/vevdb/vev) uses Data for Datomic-style transaction
data, Datalog queries, rules, pull patterns, and query results:

```clojure
(def contact-tx
  '[{:db/id 1
     :contact/name "Ada"
     :contact/email "ada@example.com"}])

(def names-query
  '[:find ?name
    :where [?e :contact/name ?name]])

(d.transact conn contact-tx)
(d.q names-query (d.db conn))
```

The transaction and query are ordinary immutable values. They can be composed
in code, read from EDN, logged, stored, or sent across an API without defining
a native type for every clause.

### Configuration And Messages

EDN provides a text representation of the same data model:

```clojure
(import edn "kvist:edn")

(defn read-config [] -> Data
  (edn.read
    "{:port 8080
      :features #{:query :pull}}"))

(let [config (read-config)]
  (data.int (:port config)))
```

This is useful for configuration, command payloads, event data, syntax trees,
and other boundaries where retaining the original structure is valuable.

## Typed Boundaries

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

## Lookup shorthand

Keywords and Data maps are directly callable:

```clojure
(:owner matter)
(:owner matter :unknown)
(matter :owner)
(matter :owner :unknown)
```

These forms lower to borrowed map lookup. They do not introduce a universal
runtime function interface. The target must be map or nil Data, and the
optional fallback is returned only when the key is absent; a present Data nil
is preserved.

Use `get` when generic indexed/map access is clearer. Keyword invocation is
normally the most readable choice for map-shaped application data. Use
`data.lookup` when code needs the value and its presence in one map scan:

```clojure
(let [[address present?] (data.lookup contact :address)]
  (if present?
    (handle-address address)
    (handle-missing-address)))
```

This distinguishes an absent key from a present Data nil without a separate
`contains?` call.

Data-heavy files may refer selected eager helpers:

```clojure
(import "kvist:data" :refer [map filter remove reduce group-by])
```

Core already supplies unqualified statically dispatched `get`, `count`,
`empty?`, `contains?`, `assoc`, `update`, `dissoc`, and `dissoc-in`. Keep the
`data.` and `arr.` prefixes in files that mix Data with native arrays so their
different representation and ownership contracts remain visible.

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
(data.split-at 10 values)
(data.partition 3 values)
(data.partition-all 3 values)
(data.partition-by owner-id values)
(data.interleave ids titles)
```

Set traversal follows deterministic backing order, but set equality remains
order independent. Do not give backing order application meaning.

`split-at` returns two owned vectors. Partition functions return a vector of
owned vector groups. `partition` omits a short final group while
`partition-all` includes it. `interleave` stops at the shorter input.

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

`some?` returns a boolean. Use `data.find` when the matching item is needed:

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

`data.group-by`, `data.index-by`, `data.frequencies`, and `data.count-by`
return immutable map Data. Group values are vectors and preserve input order.

Use `data.entries` when entry vectors are the desired data representation.
`data.map-entries` passes key and value separately to avoid allocating input
entry vectors; its callback returns one `[key value]` Data value.

`data.keys` and `data.vals` return vector Data, so they remain composable:

```clojure
(->> (data.vals message)
     (data.filter valid?)
     (data.map normalize))
```

## Destructuring and structural matching

Data maps and sequential values support nested `let` destructuring with
`:keys`, `:strs`, `:syms`, `:or`, `:as`, and sequential rest bindings:

```clojure
(let [{:keys [name roles]
       :or {roles []}
       :as contact}
      value
      [primary & remaining] roles]
  ...)
```

Use `match` for exhaustive structural dispatch:

```clojure
(match message
  {:op :query :query query}
  (run-query query)

  (kind :vector [head & tail])
  (handle-sequence head tail)

  :else
  (unknown-message message))
```

Captured values remain Data and are ownership-managed. See the
[language reference](language.md#match) and
[pattern example](../examples/data_patterns.kvist) for the complete contract.

## Paths

Nested operations use list or vector Data paths:

```clojure
(data.get-in message [:request :credentials])
(data.assoc-in message [:request :attempts] 1)
(data.update-in message [:request :status] next-status)
(data.dissoc-in message [:request :credentials])
```

These functions declare the path parameter as `Data`, so the ordinary vector
literal constructs a `Data` vector.
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
(let [items (data.to-owned-array values) :defer-with data.delete-owned-array!]
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
  (map matter-summary)
  (distinct-by summary-id))

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
Fused `mapcat` accepts callbacks returning nil, list, vector, or set Data and
traverses each callback result directly while keeping owned intermediates
scoped correctly. Data pipelines also support `(distinct)` and
`(distinct-by f)` without materializing an intermediate collection.

## Inspection and readable printing

`data.kind` returns the native `Data-Kind` enum. `data.kind-keyword` returns a
Data keyword, and `data.describe` builds a shallow, immutable description:

```clojure
(data.describe {:id 7 :status :open})
;; => {:kind :map :count 2 :keys [:id :status]}
```

Descriptions intentionally omit backing nodes and reference counts.

Use the EDN package for readable output:

```clojure
(import edn "kvist:edn")

(edn.prn value)
(edn.pprint value)

(let [text (edn.pr-str value) :defer
      formatted (edn.pretty value) :defer]
  ...)
```

`pr-str` is an alias for canonical `edn.write`. `pr` and `prn` write canonical
one-line EDN. `pretty`, `pretty-with`, `pprint`, and
`pprint-with` provide multiline rendering. Plain native `println` remains an
Odin-level structural debug print and can expose Data backing details.

## Other Construction

`data.vec`, `data.list`, and `data.set` convert sequential Data. `data.into`
adds a sequential source to an existing list, vector, set, or map Data. Use
`data.tagged` for tagged values; the EDN reader also accepts tagged literals
such as `#app/id 42`.

Low-level native boundaries use `list-from-array`, `vector-from-array`,
`set-from-array`, and `map-from-alternating`. Application code rarely needs
them. `map-from-owned-unique!` is the ownership-transfer variant for parsers
and builders that already hold a retained alternating buffer and have already
validated key uniqueness.

## Rules To Remember

- Data `map`, `filter`, and friends are eager, not lazy.
- Keyword/map invocation is compiler-lowered lookup, not a universal `IFn`.
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

More examples:

- [Data from runtime values](../examples/data/contextual-data.kvist) - runtime
  values inside Data literals
- [EDN configuration](../examples/data/edn-config.kvist) - reading Data from
  text
- [message pipeline](../examples/data/message-pipeline.kvist) - nested lookup,
  transformation, grouping, and updates
