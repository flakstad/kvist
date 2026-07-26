# First-Class Data

`Data` is Kvist's immutable, heterogeneous value type for Lisp and EDN-shaped
data. It complements native structs and homogeneous collections; it does not
replace them.

```clojure
(import data "kvist:data")

(def config
  '{:port 8080
    :features #{:query :pull}})

(data.int (get config :port))
```

## Language Boundary

The compiler and runtime own only the facilities that depend on representation
or lifetime:

- the `Data`, `Data-Kind`, and backing-storage types;
- quote lowering and immutable static literals;
- primitive payload access and construction;
- managed-value retain, release, and move operations.

The shipped `kvist:data` source package owns traversal and persistent collection
operations. Parsing and rendering EDN belongs in the ordinary official
`kvist:edn` package built on the runtime construction primitives. Reading,
structured parse errors, file input, and canonical rendering are implemented.
The reader collects sequence and map children in temporary native buffers and
freezes each completed form once; parsing a large collection does not apply a
persistent update for every input form.

## Current Values

Quoted forms support nil, booleans, integers, floats, strings, symbols,
keywords, lists, vectors, maps, and sets. Their backing arrays and text are
static. Runtime Data additionally represents EDN tagged literals as a tag plus
one immutable payload. `Data` is a compact tagged value with a raw-union
payload, so it stores only one scalar, text view, item slice, or entry slice at
a time. Copying or returning a quoted `Data` value is cheap and no cleanup is
required. Top-level quoted `def` values emit their literal directly and do not
depend on runtime global initialization order.

Runtime construction and the first persistent updates are available through
`kvist:data`. Scalar constructors store their value directly. Text and
collection constructors allocate an immutable backing node, remember its
allocator, and retain child Data values. `assoc`, `assoc-in`, `update`,
`update-in`, `dissoc`, `conj`, and `merge` return new values while preserving
their inputs. Static literals continue to leave the runtime node pointer nil.

The package also provides eager collection processing: sequential access,
`map`, `filter`, `remove`, `keep`, reduction/search, sorting, grouping, map
utilities, Data-returning `keys`/`vals`, and explicit native-array conversion.
Bulk results use retained temporary buffers that freeze once into immutable
nodes. See [Data-oriented programming in Kvist](DATA-ORIENTED-PROGRAMMING.md).

Keywords and Data maps can be invoked for direct borrowed lookup:

```clojure
(:status message)
(:status message :unknown)
(message :status)
```

This is statically lowered lookup rather than a universal callable-value
protocol. `data.describe` provides shallow structural inspection, while
`edn.pr-str`, `edn.prn`, and `edn.pprint` provide readable Data rendering.

Runtime quasiquote constructs Data with interpolation while retaining the
static literal path when no unquote is present:

```clojure
(let [entity (data.from-int 42)
      name (data.from-string "Ada")
      tx `[:db/add ~entity :user/name ~name]]
  tx)
```

When a collection literal appears where its expected type is `Data`, Kvist
constructs runtime Data directly. Literal keywords remain keywords while
symbols and calls are evaluated and converted from Data or native scalar
values:

```clojure
(defn contact-tx [id: i64, name: string] -> Data
  [{:db/id id
    :contact/name name}])

(data.conj tx
  [:db/add [:ro/id condition-id] :attention/not-before instant])
```

The expected type can come from a function return, a typed binding, a direct
function parameter, or the unique compatible member of an overload set.
Use quote for static symbolic Data and quasiquote when code itself must control
which forms are evaluated or spliced.

Unquoted Data and native booleans, integers, floats, strings, and keywords are
supported. `~@` splices a Data list, vector, or set into a runtime list, vector,
or set:

```clojure
(let [tail '[2 3]]
  `[1 ~@tail 4])
```

Map splicing is deliberately not implicit because alternating entries and maps
have different useful meanings. Compose runtime maps with `data.merge`.

The compiler manages ordinary local `Data` bindings, single and named function
returns, destructured named results, and reassignment. It infers whether a
parameter is consumed from explicit deletion or onward transfer in the body,
and whether a return transfers a new reference or aliases an input. No
ownership qualifiers are added to the native `Data` type.
Assignment retains borrowed replacements, moves owned replacements, and
releases overwritten values. Owned managed values nested directly in call
arguments or discarded explicitly are released after use. Data-valued `if`,
`let`, `do`, `type-case`, and `match` expressions normalize their result to one
owned reference. Scope cleanup follows the binding by address, so a reassigned
managed local releases its final value rather than the value present when
cleanup was registered.

`let` can destructure Data maps, lists, and vectors. Captured subvalues are
managed locals, so no cleanup marker is needed:

```clojure
(let [{:person/keys [name email]
       :keys [roles]
       :or {roles []}
       :as contact}
      value
      [primary & remaining] roles]
  ...)
```

Map defaults apply only when a key is absent; explicit Data nil is preserved.
Sequential destructuring is permissive, with missing positions and empty rest
bindings producing Data nil. Structural `match` is strict and exhaustive.

Top-level Kvist structs whose fields contain `Data`, directly or through
another managed Kvist struct, now follow the same protocol. Construction,
binding copies, `assoc`, `update` of ordinary native fields, assignment,
returns, named-result destructuring, discarded results, and scope destruction
retain or release recursively. `update` of a managed field is temporarily
rejected; compute the replacement first and use `assoc`.
Native arrays, dynamic arrays, maps, unions, closures, local structs, imported
Odin structs, and copies performed outside generated Kvist code still require
explicit `data.retain`/`data.release`.

The unqualified core `assoc` and `update` operations dispatch statically for
both native structs and `Data`. Core `dissoc` and `dissoc-in` operate on Data
maps; `dissoc-in` removes the leaf association without pruning empty parents.
The package-qualified `data.assoc`, `data.update`, `data.dissoc`, and
`data.dissoc-in` forms remain available when the boundary should be explicit.

## Managed Runtime Values

Runtime-created `Data` uses immutable, reference-counted backing storage.
`Data` itself remains a small value. Scalars are stored directly where useful;
text and collections refer to shared immutable nodes.

The compiler applies built-in `Data` lifetime rules:

- binding or storing another live copy retains its backing storage;
- leaving the owning scope releases it;
- returning or moving a final value transfers ownership without retain/release;
- overwritten managed bindings release their previous value;
- static quoted values are immortal, making retain and release no-ops;
- borrowed payload views cannot outlive their owning `Data` value.

`data.retain` and `data.release` expose the same protocol for package code that
stores Data inside native containers, opaque handles, or other lifetimes the
compiler cannot infer. Ordinary local and returned values should continue to
use automatic management.

The private Data runtime ABI has explicit compiler-known result contracts.
Constructors and buffer-freezing operations return one owned reference; view
and accessor operations return borrowed values. Kvist package wrappers inherit
those contracts, preventing either a hidden extra retain or a missing retain at
the `odin-call` boundary. New Data ABI operations must be added to this audited
contract table and covered by allocation-tracked tests.

Quoted Data constants emitted into a shared generated package retain
package-qualified identities. Literal numbering is local to an emitter and
must never make unrelated constants from separate source packages alias.

This is deterministic memory management, not tracing garbage collection.
Immutable Data cannot create cycles through its public construction API.

The internal flow machinery is representation-independent, but this does not
create a user-declared managed-type protocol. Kvist applies it when the
compiler has structural evidence, such as a typed Data decoding boundary.
Opaque native structs and handles retain explicit Odin-style cleanup.

## Package Bindings

`def` denotes an immutable package binding. A quoted right-hand side is emitted
as static data. A runtime right-hand side runs once during ordered package
initialization and releases managed storage during package shutdown:

```clojure
(def config (edn.read-file "config.edn"))
```

This does not introduce Clojure Vars or mutable indirection. Reads remain direct
typed accesses after initialization. Calls to single-result Kvist functions
infer their return type; other runtime expressions require an explicit binding
type. Initialization uses normal Kvist failure behavior, so a failed assertion
or panic terminates startup.

The implementation classifies bindings once in the declaration model. Static
constants and quoted Data keep direct zero-initialization lowering; runtime
expressions lower to typed package storage initialized in declaration order and
released in reverse order. This preserves direct typed reads and avoids
Clojure-style Var indirection.

## Direction

Data is an explicit immutable Lisp data world inside a native, statically typed
language. It should become more ergonomic and capable without becoming the
ambient representation or execution model for ordinary Kvist code.

Planned capabilities are:

- structural pattern matching and destructuring over Data;
- typed decoding into native values with path-aware validation errors; safe
  integer, float, and boolean decoders and recursive required-field native
  struct, owned-string, enum, and explicit default-field decoding are
  available, along with owned dynamic arrays of scalar, enum, `Data`, or
  recursively decoded Kvist struct elements as struct fields or direct decode
  targets;
- reusable validation of native struct and dynamic-array shapes at
  dynamic/native boundaries without constructing the native target;
- efficient internal builders for bulk immutable construction; public scoped
  builders remain deferred until call sites require them;
- explicit dispatch on tags or selected keys for messages and protocols;
- optionally, a small capability-scoped evaluator for concrete data-driven
  application workloads.

Native structs and homogeneous collections remain the default for internal,
performance-sensitive state. Data is the preferred representation for queries,
configuration, messages, protocols, evolving schemas, and interchange values.
Dynamism should therefore remain local and visible in function signatures.

Data should continue to be immutable, cycle-free, structurally comparable, and
serializable where its contents permit. Arbitrary pointers, native closures,
mutable resources, and ownership-bearing objects should stay outside Data and
be referred to through explicit application-managed handles when necessary.

## Native Boundary

The C ABI exposes runtime Data through opaque retained handles. C callers use
explicit retain/release; Rust and other deterministic wrappers use RAII. JVM
wrappers may use explicit close for prompt release and a cleaner only as a
fallback. Static and runtime Data have the same public handle shape.

## Implementation Order

1. Complete the managed-value compiler protocol for fields and containers;
   local bindings, returns, ownership contracts, reassignment, nested call
   arguments, block expressions, and recursively managed top-level Kvist
   structs are implemented. Native containers and the other aggregate forms
   listed above remain.
2. Complete persistent update and traversal operations in `kvist:data`;
   constructors, core map/sequential updates, nested updates, and runtime
   quasiquote with collection splice are implemented.
3. Add typed decoding and path-aware validation at Data/native boundaries.
   `data.decode-int[-at]`, `data.decode-float[-at]`, and
   `data.decode-bool[-at]` return a native scalar, `data.Decode-Error`, and an
   `ok` boolean. `(data.decode Struct value [path])` recursively decodes
   required nested Kvist structs and `Data`, boolean, integer, and
   floating-point and enum fields, retaining managed leaves and reporting the
   exact failing field path. Enum variants use lowercase source spelling:
   `.Read-Only` decodes from `:read-only`. String-field acquisition and
   cleanup are inferred from the struct's use as a decode target. A `:default`
   field is optional when its
   map key is absent but still validates a present value, including explicit
   Data `nil`. `[dynamic]T` fields and direct `(dynamic T)` targets
   decode Data vectors for `Data`, boolean, integer, floating-point, enum, and
   Kvist struct element types, with failing indices appended to the error path.
   Struct elements recursively validate their fields and extend paths beyond
   the index. String arrays remain.
4. `(data.validate Type value [path])` reuses the same generated shape checks
   as `data.decode`, returns `[Decode-Error ok]`, and performs no native target
   construction. It leaves the original Data available to Data-oriented code.
5. Design and implement structural Data matching with ownership-safe captured
   subvalues.
6. Internal freeze-once builders are implemented for eager collection
   transforms and fused `into Data`; benchmark results cover them against
   repeated persistent updates. Public transients remain evidence driven.
7. Extend `kvist:edn` with application tag handlers; lossless tagged Data,
   core reading, file input, structured errors, and canonical writing are
   implemented. Vev's runtime, storage, ABI, and literal-macro paths share this
   reader; its duplicate EDN reader and raw borrowed parser wrappers are gone.
8. Add explicit tag/key dispatch only after message-shaped application
   workloads establish the required semantics.
8. Extend runtime-valued `def` beyond single-result call inference only when
   concrete application examples justify additional inference rules; ordered
   initialization and reverse managed cleanup are implemented.

Each step must retain the existing zero-cleanup static quote path and must pass
ownership tests before the next layer depends on it.
