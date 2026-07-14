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

Runtime quasiquote constructs Data with interpolation while retaining the
static literal path when no unquote is present:

```clojure
(let [entity (data.from-int 42)
      name (data.from-string "Ada")
      tx `[:db/add ~entity :user/name ~name]]
  tx)
```

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
returns, destructured named results, and reassignment. `#owned` and `#borrowed`
function contracts determine whether a returned value transfers a reference or
remains a view of an input.
Assignment retains borrowed replacements, moves owned replacements, and
releases overwritten values. Owned Data nested directly in call arguments is
released after the call. Data-valued `if`, `let`, `do`, and `type-case`
expressions normalize their result to one owned reference. Data stored in native
struct fields or native containers is not yet managed automatically across
every copy, move, overwrite, and destruction path.

## Managed Runtime Values

Runtime-created `Data` uses immutable, reference-counted backing storage.
`Data` itself remains a small value. Scalars are stored directly where useful;
text and collections refer to shared immutable nodes.

The compiler applies one general managed-value protocol:

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

This is deterministic memory management, not tracing garbage collection.
Immutable Data cannot create cycles through its public construction API.

The protocol should be representation-independent so future managed native
types can use it without adding another Data-specific ownership pass.

## Package Bindings

`def` denotes an immutable package binding. A quoted right-hand side is emitted
as static data. A later runtime-initialized right-hand side will run during
ordered package initialization and release managed storage during package
shutdown:

```clojure
(def config (edn.read-file "config.edn"))
```

This does not introduce Clojure Vars or mutable indirection. Reads remain direct
typed accesses after initialization. Runtime package bindings require defined
initialization order and explicit failure propagation before this form is
enabled.

## Direction

Data is an explicit immutable Lisp data world inside a native, statically typed
language. It should become more ergonomic and capable without becoming the
ambient representation or execution model for ordinary Kvist code.

Planned capabilities are:

- structural pattern matching and destructuring over Data;
- typed decoding into native values with path-aware validation errors;
- reusable validated shapes for dynamic/native boundaries;
- efficient builders or transients for bulk immutable construction;
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
   arguments, and block expressions are implemented.
2. Complete persistent update and traversal operations in `kvist:data`;
   constructors, core map/sequential updates, nested updates, and runtime
   quasiquote with collection splice are implemented.
3. Add typed decoding and path-aware validation at Data/native boundaries.
4. Design and implement structural Data matching with ownership-safe captured
   subvalues.
5. Add builders/transients and verify their allocation behavior against
   repeated persistent updates.
6. Extend `kvist:edn` with application tag handlers; lossless tagged Data,
   core reading, file input, structured errors, and canonical writing are
   implemented. Vev's primary runtime and storage paths already share this
   reader; raw compatibility shapes and exact diagnostics remain.
7. Add explicit tag/key dispatch only after message-shaped application
   workloads establish the required semantics.
8. Add ordered package initialization and runtime-valued `def`.

Each step must retain the existing zero-cleanup static quote path and must pass
ownership tests before the next layer depends on it.
