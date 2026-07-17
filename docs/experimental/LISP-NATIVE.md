# Experimental: Lisp-Native Kvist

Kvist should combine Lisp data and development ergonomics with native types,
deterministic ownership, predictable layout, and Odin interoperation. This is
the current direction and build order, not a commitment to a dynamic runtime or
global garbage collector.

The active driver is Vev: named Datalog queries, pull patterns, rules, and
transaction data should read as ordinary quoted values in Kvist, while the same
database remains usable through EDN and native ABIs from other languages.

## Invariants

- Native structs and homogeneous collections remain the default representation.
- `Data` is the immutable heterogeneous representation for Lisp and EDN shapes.
- Management is type-scoped. Using `Data` does not make unrelated native values
  garbage collected.
- Static quotes remain zero-allocation immutable values.
- Runtime Data uses deterministic retain/release and cannot create cycles
  through its immutable public API.
- Source syntax and runtime values remain distinct. Macro expansion operates on
  source-aware `Syntax`; applications operate on source-independent `Data`.
- Text is an interchange boundary, not the internal representation of embedded
  queries or transaction values.
- Dynamism is local and visible. Ordinary bindings, calls, structs, and
  collections do not become boxed or dynamically dispatched because Data
  exists.
- Data remains immutable, cycle-free, structurally comparable, and
  serializable where its values permit. Native resources and mutable identity
  live outside Data behind explicit handles.

## Workstreams

### 1. Complete Managed Data

Current implementation covers static quotes, runtime backing nodes, local
bindings, single and named returns, destructured named results, explicit
`#owned`/`#borrowed` contracts, reassignment, nested owned call arguments,
discarded managed results, and recursively managed top-level Kvist structs.

Remaining compiler work:

1. Keep expression ownership normalized as new expression forms are added;
   `if`, `type-case`, `let`, and `do` are implemented.
2. Release unused owned Data expression results. Explicit discards and
   standalone managed constructor results are implemented; keep this invariant
   for new expression forms.
3. Define managed fields in native structs, including copy, overwrite, move,
   return, and aggregate destruction. Top-level Kvist structs are implemented;
   local structs, imported Odin structs, and managed-field `update` remain.
4. Define managed elements in arrays, dynamic arrays, maps, unions, and
   closures.
5. Generalize the implementation as a managed-value protocol rather than a
   collection of Data-only emitter checks.

This work is complete when retain/release accounting tests cover every path and
static quotes still produce no runtime node operations.

### 2. Build The Data Library

`kvist:data` owns ordinary immutable operations. Primitive runtime constructors,
core map/sequential updates, nested lookup/update, merge, and runtime
quasiquote with scalar unquote and list/vector/set splice exist. Continue with:

- sequence traversal without leaking managed elements in native result arrays;
- explicit conversion between Data and selected native scalar/collection types;
- structural-sharing tests and allocation accounting.

Runtime quasiquote should make application-built values direct:

```clojure
(defn rename-tx [entity: Data, name: Data] -> Data
  `[[:db/add ~entity :user/name ~name]])
```

Macro quasiquote continues to produce source forms. Runtime quasiquote produces
`Data`; the context determines which operation is intended.

### 3. Make Data Ergonomic At Native Boundaries

Data should be useful as an explicit dynamic region without making the
surrounding program dynamic. Build these facilities in order:

1. Typed decoding from Data into native structs, enums, scalar types, and
   selected homogeneous collections, with errors carrying the exact Data path.
   Integer, float, and boolean scalar decoders plus recursive type-directed
   native struct decoding for nested structs, scalar, explicitly owned string,
   enum, `Data`, explicit default fields, and owned dynamic arrays of scalar or
   `Data` elements are implemented.
2. Reusable shape validation/refinement so code can validate once and avoid
   repeating kind and key checks.
3. Structural pattern matching and destructuring for maps, sequential values,
   literals, kind guards, rest bindings, and nested patterns.
4. Mutable builders or transients for bulk construction followed by one
   immutable freeze. Persistent updates remain the ordinary API.
5. Explicit dispatch on Data tags or selected keys for message and protocol
   handling. This is opt-in application dispatch, not ordinary function-call
   semantics.

Provisional pattern syntax should stay recognizably data-shaped:

```clojure
(match message
  '{:op :query :query ?query}
    (run-query query)
  '{:op :transact :tx ?tx}
    (run-transaction tx)
  :else
    (error "unknown message"))
```

Typed decoding should make the dynamic/native boundary explicit and report
useful paths:

```clojure
(data.decode Person value)
;; expected int at [:address :postal-code], found string
```

`data.decode` now establishes this surface for the supported first struct
shapes and returns `[decoded err ok]`. Pattern matching belongs in the language
only where it improves exhaustiveness, binding, or lowering; traversal,
decoding, shapes, and builders belong in `kvist:data` wherever ordinary package
code is sufficient.

`kvist:edn` already uses the underlying implementation pattern internally: it
collects retained children in native buffers and constructs one immutable Data
node per completed collection. The remaining item is a safe public builder API
for application workloads, not linear-time EDN parsing.

### 4. Add `kvist:edn`

EDN is an official source package built on `kvist:data`, not a compiler
intrinsic. Reading with structured errors, file input, and canonical rendering
implement the initial surface:

```clojure
(edn.read text)
(edn.read-file path)
(edn.write value)
```

The reader covers namespaced symbols and keywords, sets, maps, lists, vectors,
numeric values, escapes, comments, commas, byte-offset diagnostics, and
lossless tagged values. Application-level tag-handler registration remains.
Vev's primary runtime and storage paths share this reader and apply their own
UUID, query, pull, rules, and transaction validation. Raw compatibility paths
remain before Vev can delete its old reader completely.

### 5. Finish Vev's Data Surface

Kvist Vev applications should be able to name and pass query data directly:

```clojure
(def releases-by-artist
  '[:find ?release
    :in $ ?artist-name
    :where
    [?release :release/artists ?artist]
    [?artist :artist/name ?artist-name]])

(d/q releases-by-artist db "John Lennon")
```

The same rule applies to pull patterns, rules, and transaction data. Runtime
EDN remains necessary for files, C/JVM/native ABI strings, and wire boundaries.
Quoted Data and parsed EDN must converge on one Vev semantic representation and
produce identical results and diagnostics.

Vev's primary query, query-input, rule, pull, transaction, storage transaction,
datom-log, and durable metadata paths now use `kvist:edn`. Prepared semantic
objects retain an explicit Data source owner or deep-own their values, making
prepare-now/execute-later safe. The duplicate Vev EDN reader and raw borrowed
parser wrappers have been removed. Remaining parity work concerns exact
Data/text diagnostics and the application-facing result surface.

The acceptance workload is parallel MusicBrainz/Day-of-Datomic material in
Kvist and Clojure, with Datomic comparison where practical.

### 6. Runtime Package Bindings

`def` remains an immutable package binding. Quoted values are emitted statically.
A non-static right-hand side should become an ordered runtime-initialized package
binding:

```clojure
(def config (edn.read-file "config.edn"))
```

Runtime package bindings now use deterministic declaration-order
initialization, reverse-order managed shutdown, and ordinary Kvist failure
behavior. They do not add Clojure Vars or mutable indirection to ordinary
reads.

Implemented:

1. Classify each `def` as a static binding or a runtime-initialized binding.
   Literal native constants, type aliases, overloads, and quoted static Data
   retain their existing direct lowering. Calls and other runtime expressions
   require package initialization.
2. Represent the initialization distinction on the declaration itself rather
   than checking individual RHS forms throughout the emitter.
3. Emit runtime definitions as typed package storage plus one generated
   initializer. Assign bindings in flattened package/declaration order so a
   binding can use earlier definitions deterministically.
4. Generate reverse-order finalization for managed values. Static Data remains
   immortal and must not gain retain/release traffic.
5. Preserve ordinary Kvist failure behavior inside initializers:
   expressions either produce their declared value or terminate through their
   explicit panic/error handling. Add structured package-startup failure
   propagation when a concrete fallible application API establishes its
   required shape.
6. Support direct reads after initialization, dependency order, exactly-once
   evaluation, reverse cleanup, static quote allocation counts, generated
   source maps, `kvist run`, `kvist build`, `kvist eval`, and imported source
   packages.

The first milestone is implemented. Calls to single-result Kvist functions
infer their return type, explicitly typed runtime expressions are also
supported, later definitions and `main` read the values directly, managed Data
is released once at shutdown, and ordinary static definitions retain their
existing lowering.

Remaining declaration work:

1. Consolidate shared name, visibility, phase, mutability, documentation, type,
   and source metadata while keeping `def`, `defn`, `defmacro`, `defvar`, and
   type declarations semantically distinct.
2. Broaden runtime binding inference only from principled expression typing,
   not an open-ended set of initializer special cases.
3. Add structured startup-error reporting when real workloads establish the
   required API.

### 7. Separate Syntax From Data

Longer term, compiler forms should expose a source-aware representation such as:

```text
Syntax { datum: Data, span: Span, context: Expansion_Context }
```

`Syntax` may share Data's immutable storage machinery, but it remains a
different semantic type. Source locations, hygiene, resolution, and expansion
context must not leak into application Data or EDN values. This is a compiler
architecture migration after the runtime Data model is stable.

### 8. Build A Standalone Native REPL

The first REPL milestone is local and session-oriented, before a resident app
console. `kvist repl` should maintain a synthetic session module, compile new
generations through the normal compiler, load native results, and retain named
session values with the managed Data protocol.

Initial commands:

```clojure
(def value ...)
(defn helper ...)
(helper value)
(doc helper)
(expand '(form ...))
(macroexpand '(form ...))
(reload)
(reset)
```

The session needs stable source mapping, generation cleanup, structured result
encoding, and predictable behavior when a generation fails to compile. An
interpreted Data evaluator is optional later only if measured native compile
latency makes it worthwhile.

### 9. Attach A Resident Console

After the standalone session model works, adapt it to a reload host. The
resident app owns state; the console executes prepared capabilities at explicit
safe points. Development-only eval can compile a command generation against
those capabilities. Remote transport requires authentication, authorization,
audit, deadlines, and arbitrary eval disabled by default.

See [RESIDENT-CONSOLE.md](./RESIDENT-CONSOLE.md) for the command and safety
model.

### 10. Consider A Deliberate Data Evaluator

After pattern matching, typed boundaries, and the native REPL exist, a small
interpreter over Data may be useful for rules, configuration expressions,
workflow definitions, sandboxed extensions, or resident-console commands. It
must be an explicit library/runtime facility with a supplied environment and
capability set. It must not become the execution model for ordinary Kvist code.

Do not add this merely to imitate a traditional Lisp evaluator. Build it only
for a concrete application workload or if measured native REPL compilation
latency requires an interpreted fast path.

## Non-Goals

- Dynamically typed ordinary bindings or universal boxed values.
- Runtime dispatch for every function call.
- A mandatory tracing garbage collector.
- Clojure Vars or mutable indirection for ordinary package bindings.
- Arbitrary native closures, pointers, or ownership-bearing resources stored
  directly in Data.
- Treating compiler syntax and application Data as the same semantic object.

## Verification Gates

- Lifetime tests count node creation and destruction across assignment,
  branches, blocks, returns, fields, containers, and closures.
- Static quote tests prove no runtime node allocation or cleanup is emitted.
- Persistent Data tests prove old values remain unchanged and shared children
  remain valid after either parent is released.
- Pattern tests cover nested binding, failure, rest values, and ownership of
  captured subvalues.
- Decoder tests cover native output, exact failure paths, defaults, and
  rejection of unknown or malformed values.
- Builder tests compare immutable results and allocation counts with repeated
  persistent construction.
- EDN conformance tests cover parsing, rendering, errors, and round trips.
- Vev runs the same query/pull/rules/transaction corpus through quoted Data and
  EDN text.
- MusicBrainz examples run in both Kvist and Clojure with matching results.
- REPL tests cover session definitions, failed generations, source maps, reset,
  and native-library retirement.
- Resident-console tests cover capabilities, safe points, reload compatibility,
  and production eval restrictions.

## Execution Order

Vev's reader convergence and runtime package bindings are complete. The active
order is completing managed fields and containers, then Data traversal, typed
decoding, structural matching, and builders. `Syntax`, standalone REPL,
resident console, and any Data evaluator remain later work so the language
keeps its native default while each dynamic facility is justified by a real
boundary or application.
