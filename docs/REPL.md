# Native REPL and Live Console

Status: canonical design under active implementation.

Implemented foundation:

- `kvist repl CONTEXT` terminal entrypoint and editor-neutral
  `--protocol jsonl` mode
- a controller-owned session directory and disposable worker process
- one uniquely versioned native dynamic library per successful submission
- append-only generation loading and exactly-once execution
- compile-all-then-run multi-form runtime batches
- structured ready, output, completion, reset, compile-failure, and
  worker-failure behavior
- automatic fresh-worker recovery after a native panic or crash
- persistent concrete `defn` submissions in the compiler session environment
- a worker-owned procedure registry keyed by logical name and exact native
  signature
- compatible function replacement: existing session callers observe a
  same-signature redefinition without recompilation
- signature evolution: future forms resolve the newest signature while
  already-compiled callers remain pinned to their compatible signature slot
- atomic mixed submissions containing any number of concrete `defn`s followed
  or interleaved with runtime forms; the runtime forms execute in source order
  only after the complete generation builds
- eager persistent `def` storage for explicitly typed strings, numeric, and
  boolean scalars, including compatible replacement and multi-type retention
- persistent reference-counted `Data` values and mutable `Data` cells; getters
  retain across generation boundaries and `set!` performs managed replacement
- persistent immutable dynamic-array `def` values whose getters return an
  independent owned copy rather than exposing session storage
- persistent mutable dynamic-array cells, including arrays of `Data`; managed
  `set!` clones or moves the replacement and destroys the previous contents
- persistent string/scalar `defvar` cells whose reads, address-taking, `set!`, and
  mutation helpers share typed storage across old and new generations
- persistent `defstruct`, `defenum`, and `defunion` declarations
- retained fixed-size and nominal aggregates whose field reads and mutations
  use the same cross-generation cells
- recursive nominal-layout fingerprints in procedure, value, and var slots, so
  a layout change creates a distinct ABI instead of casting old storage
- persistent fused `deftransform` declarations; future compilation uses the
  newest pipeline while previously compiled functions retain their original
  lowered pipeline
- persistent `defiter` declarations for custom eager sources consumed by
  later `for`, `into`, and `transduce` forms
- persistent explicit-alias imports, including Kvist package functions and
  package macros in the same submitted buffer and in later generations
- once-per-worker package state: context-package and imported-package
  `defvar` cells keep one typed storage location across generations, while
  runtime-initialized immutable `def`s run once and retain their first value
- persistent `defmacro` declarations with same-buffer expansion,
  future-generation redefinition, version history, stale-dependent detection,
  and function refresh against the newest expansion
- generic binding inspection reporting committed kinds, generations, exact
  emitted native ABIs, dependencies, version history, and stale state
- live expression inspection reporting the rendered value, inferred native
  type, exact ABI, generation, and editor-neutral value shape without rotating
  recent-result history
- retained inspection handles backed by typed native getter slots; child field
  requests read the exact captured snapshot in later generations without
  re-evaluating the parent expression
- retained sequence-index and map-key selection; element/entry values receive
  new handles and leave both the source snapshot and recent-result history
  unchanged
- bounded first-page collection inspection and explicit `inspect-page`
  requests, with absolute sequence indexes and deterministic map-entry ordering
- retained generated Odin/source-map/library artifacts plus a generic loaded
  generation inventory for debugger discovery
- native worker PID/epoch capability discovery and replacement notifications
  for editor-owned debugger attachment
- submitted-form source origins and retained Kvist-to-native breakpoint
  candidates across every live generation
- compiler-inserted pre-form safe points with blocking pause/continue and
  source-level step-into control, typed frames, and source-location events
- opt-in bounded execution traces over the same safe points, carrying exact
  Kvist source locations, monotonic elapsed/inter-point timing, and logical
  call depth without pausing or rendering locals, followed by an
  interval-attributed hotspot summary, with separately bounded top-level
  lexical value capture
- persistent `(debug.break)` safe points inside REPL definitions with
  generation-aware typed frame descriptors
- explicit `(condition.signal :kind message data)` safe conditions with captured typed
  frames and editor-neutral restart discovery/invocation
- compiled `(condition.use-value! local "message")` boundaries for replacing
  mutable `int`, `bool`, `f32`, `f64`, and `string` locals with
  controller-validated values
- lexical `(condition.restart-case ...)` regions whose conditions can safely
  continue, retry the region, or skip its remaining forms
- lexical `(condition.operation ...)` regions whose conditions can abort the
  operation, run normal scoped cleanup, and resume after the boundary
- transitive stale-dependent detection when a native ABI, nominal declaration,
  transform, or iterator identity changes
- atomic function refresh: `refresh` and `refresh-dependents` compile the
  selected sources as one generation and commit only after successful native
  execution, without replaying value initializers
- safe logical `drop`: remove a binding from future compilation only when it
  has no session dependents, while retaining old native storage for old
  generations until reset
- native typed recent results: each value-producing submission evaluates once,
  atomically rotates heterogeneous `*1`, `*2`, and `*3` worker slots, and
  exposes result type, ABI, and generation through the generic protocol
- managed recent `Data` and dynamic-array results; later reads retain or clone
  them instead of borrowing generation-local storage
- persistent native maps in typed `def` and `defvar` cells, including ordinary
  entry mutation, safe whole-map replacement, and independently cloned reads
  through named values and recent-result slots
- tail-position result snapshots run before form-local cleanup: borrowed
  strings are cloned, `Data` is retained, and dynamic arrays, native maps, or
  managed aggregates are cloned while their complete owner chain is still
  alive
- generic lifecycle metadata on recent results, persistent values, retained
  inspections, and paused locals: clients receive ownership/storage class plus
  clone, destruction, checkpoint, and rendering capabilities; retained
  results and inspections also expose logical allocation and owner identities

The procedure path accepts concrete `defn` signatures with caller-expanded
defaults, procedure directives, concrete constraints, and custom ABIs.
Custom-ABI implementations are reached through an ordinary internal adapter
whose lookup type preserves the declared convention. Generic parameter or
result types persist as compiler templates. Odin materializes their concrete
specializations in each future generation that calls them; old native callers
retain the template version they compiled against, while dependency and stale
queries identify callers that can be atomically refreshed. Unspecialized
generic procedures are never cast to a runtime slot.
The initial value paths require an explicit retainable type: `Data`, strings,
numeric and boolean scalars, fixed arrays of retainable unmanaged values,
nominal aggregates whose fields or variants are themselves retainable, or a
dynamic array or native map with retainable element types.
String and dropped-binding backing storage follow the session's append-only
lifetime and are reclaimed only at reset/process exit; replacement may
intentionally leak during a development session. `Data` now uses explicit
retain/release behavior at generated access and assignment boundaries.
Native map crossings make recursively independent copies of string, `Data`,
dynamic-array, map, and managed-aggregate entries. Replacement reclaims the old
map backing store but does not recursively destroy entry payloads: ordinary map
entry assignment can introduce static or borrowed descriptors, so cloned entry
payloads deliberately have worker lifetime. This is a bounded development
session leak, not a dangling reference or double free. Opaque
resource-owning aggregates remain gated pending explicit lifecycle hooks.
Pointer, `cstring`, raw-pointer, foreign-view, and opaque-resource result
types are recognized recursively through aggregates and aliases. A normal
evaluation may render such a value while its form is active, but emits
structured warning `KVR001` and does not rotate it into `*1`. Persistent
`def`/`defvar` and retained native inspection reject the same type with an
ownership diagnostic. This makes the unsupported boundary explicit: clients
never mistake an address rendered once for a retained live value. Capability
`unretained-lifecycle-diagnostics` advertises this behavior.
Recent-result capture snapshots supported owned values before form-local
`:defer` cleanup runs. A local dynamic array such as
`(let [xs ([dynamic]int [1 2]) :defer] xs)` therefore produces an independent
retained `*1`; the original `xs` is still deleted when the submitted form
finishes. This exception belongs only to the compiler-inserted REPL snapshot
boundary. Returning the same deferred binding from an ordinary function
remains an ownership error.
Native slice results with retainable element types are promoted in the same
way, including slices nested through structs, fixed arrays, dynamic arrays,
and native maps. The REPL recursively copies selected elements into
worker-owned backing storage and retains the resulting slice descriptors.
Managed elements receive their normal recursive clone. This allows a slice of
a form-local dynamic array to remain usable through `*1` after its original
owner is deleted, without changing ordinary borrowed-slice semantics outside
the REPL boundary.
Explicitly typed persistent `def` and `defvar` initializers use the same
recursive promotion. The compiler inserts the snapshot into each initializer's
tail branches before local `:defer` cleanup, instead of wrapping an
already-returned borrowed descriptor.
Package globals are externalized through the worker's typed registry. Each
generation contains adapters, but only the first compatible generation
registers and initializes a mutable cell or runtime-initialized immutable
value. Later generations use the same storage and do not replay initializer
side effects. A signature or recursive layout change creates a distinct typed
slot rather than casting old state. Reset, worker crash, or process exit is the
package-state reclamation boundary. Dependency discovery is currently
conservative and form-based; it may report an extra edge when a local shadows
a session binding.
Refresh deliberately recompiles only `defn` sources. Values and vars must be
re-evaluated explicitly so refresh can never replay an initializer. The next
retention layer covers explicitly declared pointer/resource lifecycles and
foreign views whose owners cannot be inferred structurally. The standalone
worker captures native stdout through its control pipe and native stderr
through a worker-private file, then emits separate request-attributed output
events. The worker flushes stderr before its completion marker, so even output
larger than a pipe buffer cannot deadlock execution or leak into protocol
stdout. Ordering is preserved within each stream; clients must not infer a
total ordering between arbitrary raw writes to different file descriptors.

Kvist should have a genuine REPL without introducing an interpreter or a
second, dynamically typed version of the language. A REPL submission is normal
Kvist: it is read, expanded, type checked, ownership checked, lowered to Odin,
compiled to a small native generation, loaded, and executed exactly once.
The bounded paused-frame scalar evaluator is debugger tooling over copied
snapshots, not an alternate execution path for Kvist programs.

The first implementation is a standalone developer session. The same generic
session protocol then attaches to an Olive development host so one workflow can
both evaluate ad hoc code and reload a running application. Olive remains the
mechanism for replacing application code that is already wired into ordinary
native call sites.

## Product Model

`kvist repl` starts an interactive session anchored to a Kvist package. With no
input file it starts a synthetic core-only package. With an input file it uses
the same package graph, imports, compiler options, source mapping, and symbol
context as `kvist eval`.

The REPL supports the full language, including native scalars, arrays, structs,
resources, Odin and Kvist packages, `Data`, macros, transforms, iterators, and
ordinary side effects. `Kvist/Live` is not its evaluator and is not expanded
into a shadow implementation of Kvist. The former interpreted `Kvist/Live`
prototype and the pre-Olive `kvist_hot` stack have been removed; their useful
capability and reload ideas are incorporated here and in Olive.

The defining rules are:

- A submitted runtime form executes exactly once. Old forms are never replayed
  to reconstruct a session.
- A multi-form submission is compiled completely before any of it executes.
  If compilation fails, none of its runtime forms run.
- A successful batch is one generation. Its runtime forms execute once in
  source order.
- Re-sending a form, region, or buffer is a new submission and deliberately
  runs its runtime forms again.
- Loaded generations and session allocations are append-only until reset or
  process exit. Development-session leaks are acceptable.
- Imports may be added at any time. A package is loaded and initialized once
  per worker, by canonical package identity; repeated imports reuse it.
- Evaluating a declaration from an already loaded source package replaces that
  package's qualified live binding immediately. Merely saving source does not
  execute it; package initialization and non-live structural changes still use
  an explicit session reset, or Olive reload when attached to an application.

An editor session is associated with the complete local package graph rooted
at its application entry file. REPL switching, stopping, and restarting from a
transitively imported source buffer operate on that same worker. The controller
maps the submitted source path to its package in that graph, rewrites it into
the same qualified symbol space as ordinary compilation, and retains identities
such as `service__state__base`. Package-local references and imports therefore
resolve correctly, and equal unqualified names in separate packages do not
collide. Source files outside the active graph are rejected.

Projects are encouraged to use an ordinary `dev/user.kvist` as the explicit
development entry point. It imports the application graph and may define
development-only lifecycle helpers, fixtures, and comment forms. It is a
convention rather than metadata: Kvist still has folder/relative-import package
management, and the REPL may start from any source file.

The terminal prompt is one client. Editors use the same protocol and may send
one form, a region, a comment body, or an entire buffer in one request.

## Development Experience

The primary Emacs workflow should feel like CIDER without changing Kvist's
native semantics:

1. Start or connect to the project/package session.
2. Evaluate the source buffer to establish imports and definitions.
3. Explore from `(comment ...)` forms, retaining native values and resources.
4. Inspect inline results and `*1`, `*2`, and `*3`.
5. Edit and re-evaluate a function, then invoke it again against existing
   session values.
6. Turn discoveries into source and tests, then verify with a clean
   `check`, `test`, or `run`.

Clojure keeps dynamically typed objects in a garbage-collected JVM and routes
function calls through Vars. Kvist instead keeps statically typed native values
in an append-only worker and uses versioned typed cells and session-only
function slots. The interactive loop is similar, but type, layout, ownership,
and native ABI facts remain visible.

Olive and the REPL are complementary. The standalone REPL is optimized for
exploration and disposable state. Olive keeps a real application, event loop,
and host-owned state alive while replacing coherent application modules. An
attached REPL adds temporary helpers and invokes typed capabilities; Olive
still updates ordinary application call sites.

A clean compile and run remains the reproducible truth. REPL history is
development state, not an implicit part of the program. Tooling should make it
easy to copy a successful interaction into a test or source comment form.

## Session Semantics

### Bindings and generations

The controller retains the compile-time session environment: symbols, resolved
types and layout fingerprints, macros, imports, documentation, source origins,
and generation metadata. The worker retains native code and values.

Every logical name has one or more definition versions. Every runtime version
is registered in a host-owned typed cell or function slot:

```text
Definition_Version {
  logical_name
  version
  type_fingerprint
  storage
  mutable
  callable
  generation_id
  dependencies
  source
}
```

Generated code resolves a binding, verifies its fingerprint, casts its storage
to the statically known type, and then performs ordinary compiled operations.
Kvist does not box all values into `Data`; `Data` is simply one supported native
binding type.

Session `def` and `defvar` create typed cells. Re-evaluating either with the
same type replaces the cell value. `def` remains immutable to ordinary Kvist
assignment; replacement is a REPL submission operation. Old compiled session
code reads the current compatible named value.

Session functions use stable, session-only call slots. Re-evaluating a function
with the same native signature updates its slot, so previously compiled session
callers invoke the latest implementation. This indirection is not added to
normal production builds.

Submitting an exactly unchanged, current `defn` is idempotent. The controller
returns success at the existing generation without compiling, loading, or
recording another definition version. An unchanged function that is stale
because one of its dependencies crossed an ABI boundary is deliberately not a
no-op: evaluating it recompiles that caller against current definitions.

Macros are controller-side compiler definitions. Redefining a macro affects
future expansion only. Previously compiled code is unchanged until explicitly
re-evaluated.

Compiler-side identities for macros, transforms, and iterators include their
resolved dependency identities as well as their own source. Consequently, a
textually unchanged `defiter` still changes identity when its source-state
layout or typed open/next procedures cross an ABI boundary. Existing consumers
remain executable against the retained iterator version, are reported stale,
and can be refreshed deliberately.

### Signature and type evolution

Changing a function signature is supported by creating a new definition
version:

```clojure
;; foo v1
(defn foo [x: int] -> int ...)
(defn caller [] -> int (foo 42))

;; foo v2: future source resolves this definition
(defn foo [text: string] -> int ...)
```

- Future source resolution of `foo` selects the newest version.
- Already compiled callers remain pinned to the old ABI-compatible `foo`
  version and continue to work.
- Definitions compiled against an older version are reported as stale, not
  invalidated or silently redirected across an ABI boundary.
- `:refresh name` recompiles one retained function definition and
  `:refresh :dependents foo` recompiles its transitive session-function
  dependents against the newest definitions. Refresh compiles the complete
  closure before committing any slot updates.
- Refresh never replays arbitrary top-level expressions or value initializers.
  A value with effects must be explicitly re-evaluated by the user.
- `:versions foo`, `:deps foo`, and `:stale` expose the version graph.
- `:alias-version old-foo foo 1` creates a compiler-side session alias when
  source must call, inspect, or migrate an older version explicitly.

After the example, `caller` continues to use `foo` v1 until its source is
updated and refreshed. A failed refresh leaves the old caller active.

Changing a value's type likewise creates a new typed cell version. Future code
sees the new version; old compiled code keeps its old typed cell.

Changing a struct, enum, union, alias, or other layout-bearing declaration
creates a new nominal type version with a unique generated native identity.
Old values and code retain the old layout and remain inspectable. New code sees
the new layout. Values cross the boundary only through an explicit user-written
conversion or migration function; the runtime never reinterprets old memory as
the new type. A version alias gives the migration function an ordinary source
name for the old nominal type.

Session generations are therefore multi-version rather than edit-in-place.
They remain loaded until reset. `:drop name` removes the newest version from
future name resolution without reclaiming old versions. The previous version
does not become current implicitly; version selection remains explicit in
inspection tooling.

When attached to Olive, an application module is rebuilt coherently so its
internal call sites may adopt new signatures together. Versioned capability
ABIs protect the host boundary. Changing the durable `Reload_State` layout
still requires an explicit old-to-new state migration at a checkpoint or a
host restart.

### Ownership across submissions

Owned strings, arrays, maps, structs, closures, resources, `Data`, static
values, and non-capturing procedures may persist because their defining
generations remain loaded.

A borrowed result may persist when the compiler can retain its complete owner
chain. Owners already in session cells are recorded as dependencies. A
form-local owner may be promoted into a hidden session cell and kept alive
alongside the borrowed result. If the compiler cannot prove or retain an owner,
it diagnoses the escape and suggests retaining the owner explicitly or
creating an owned copy.

Users may explicitly close or delete resources; forgotten cleanup is recovered
when the worker exits. Redefinition and drop do not eagerly destroy old values,
because old generations may still refer to them.

### Results

Each successful expression with a retainable inferred type is evaluated
exactly once into generation-owned native storage, printed using the normal
Kvist/Odin rendering path, and retained as one of `*1`, `*2`, and `*3`. These
names are compiler-side aliases to typed result cells and may change type
between submissions.
Future forms see the current aliases. Previously compiled code that mentioned a
recent-result alias retains the particular typed cell it compiled against.
Evaluating bare `*1`, `*2`, or `*3` reads that cell without rotating the
history. An expression that uses a recent result, such as `(+ *1 1)`, is an
ordinary new result and does rotate the history.
Strings are cloned before becoming result storage. `Data` is retained and
dynamic arrays, native maps, or managed aggregates are cloned before a
form-local owner can be cleaned up. Later `Data` reads retain the stored value,
and collection reads clone it, so a later form may safely mutate or release
its own result copy. Snapshotting is pushed into the tail of `let`, `do`, `if`,
`type-case`, and `match`, preserving branch and cleanup order.
Slices nested in retainable aggregate and collection values are recursively
promoted at this boundary. Their ordinary compiled-language semantics remain
borrowed everywhere else.

If a retainable copy cannot be constructed, the normal ownership checker
rejects the escape. For example, returning a `:defer` dynamic-array binding is
diagnosed instead of installing a dangling descriptor in `*1`. Session
generations intentionally tolerate leaked original owned results; reset or
worker exit is the reclamation boundary.

Declarations report their defined name and signature rather than manufacturing
a universal result value and do not rotate the history. A no-print request
still evaluates and retains its final value; it suppresses rendering only.
Effect-only forms whose result has no retainable native type execute without
rotating the history.

### Failure, interruption, and reset

Frontend or Odin compilation failure leaves the running worker and session
environment unchanged. Generation loading and ABI validation complete before
the batch is committed.

Standalone native execution occurs in a disposable worker process. A panic,
segmentation fault, forced interrupt, or unexpected worker exit loses all
runtime values and loaded generations. The controller preserves source history
and the failure report, but does not replay submissions. The next evaluation
starts a fresh session in the same package context.
Unexpected exits emit `native-crash` with failure kind and the operating-system
exit code when available, followed by the failed request's ordinary `complete`
event. This is deliberately distinct from `interrupted` and
`deadline-exceeded`; clients never need to classify cancellation by parsing an
error message. Capability `native-crash-events` advertises the distinction.

At an instrumented standalone pause, `interrupt` terminates the disposable
worker, emits an attributed `interrupted` event, clears runtime/compiler
session state, and lets the following evaluation start a fresh worker. An idle
interrupt reports that no evaluation is active. An `eval` or `inspect` request
may instead supply `timeout_ms`; a controller watchdog terminates native
execution even when it never reaches another safe point, emits
`deadline-exceeded`, and applies the same clear-and-replace boundary. Values
from the expired worker are never replayed. Attached clients never
force-terminate the application host and must use cooperative restarts.
`debug-abort` is the preferred source-level cancellation operation for both
standalone and attached sessions because it preserves the resident runtime.

`:reset` intentionally terminates the worker, clears the compiler session
environment and history aliases, and starts again from the package anchor.
Worker exit is the primary reclamation mechanism; per-binding unloading and a
generation garbage collector are non-goals.

## Architecture

### Controller and worker

The long-running controller owns reading, expansion, analysis, incremental
session state, Odin generation, compilation, diagnostics, request ordering, and
history. It compiles only the new batch plus the small adapters needed to reach
registered bindings and function slots.

The worker owns:

- the typed binding registry and stable function-slot table
- package initialization records
- loaded dynamic libraries, which are never unloaded during the session
- execution and result retention
- captured stdout and stderr

Each dynamic library exports a versioned generation descriptor containing its
ABI version, required bindings and type fingerprints, declared bindings,
function-slot updates, package dependencies, initializer, and one batch entry
point. The worker validates the complete descriptor before committing it.
Registration must be transactional with respect to load and validation;
execution effects are not transactional.

Imports compile to permanent package generations. The worker deduplicates them
before initialization. Import dependency order remains the ordinary Kvist
package order, and a failed package load does not mark the package initialized.

Temporary source, Odin, object, and dynamic-library artifacts use a
session-specific build directory. They may be cached by content while the
session lives and are removed best-effort after worker exit. Compiler caches
remain reusable across sessions.

### Generic CLI protocol

The CLI contains no editor-specific behavior. It provides:

```text
kvist repl [context.kvist]
kvist repl [context.kvist] --protocol jsonl
kvist repl --attach ENDPOINT
```

Interactive mode is a terminal client over the same internal request/event
model. Protocol mode reads newline-delimited JSON requests from stdin and
writes only newline-delimited JSON events to stdout. Program stdout and stderr
are captured and emitted as attributed events, so they cannot corrupt protocol
framing. Capability `separate-worker-streams` advertises distinct standalone
stdout and stderr events.

Every request has a client-generated request id. Evaluation requests contain
source text, a stable source identity, the source range or starting position,
and flags such as no-print, `native_debug_symbols`, or a standalone native
`timeout_ms` deadline between 1 and 3,600,000 milliseconds. Ordinary
evaluations omit native debug symbols for a faster Odin build. A client that is
attaching a native debugger sets `native_debug_symbols: true`; instrumented
Kvist stepping, tracing, values, conditions, and source maps do not require
that flag. Generic requests cover:

- handshake and capability discovery
- evaluate a batch
- interrupt the active batch
- reset, drop, refresh, session checkpoints, version inspection, and close
- session status and binding inspection
- documentation, lookup, completion, expansion, and macroexpansion
- debug-frame inspection, stepping, tracing, conditions, and restarts
- attached-host reload and reload status

The implemented JSONL subset currently accepts `eval`, `inspect`,
`inspect-page`, `expand`, `macroexpand`, `bindings`, `results`, `allocations`,
`ownership-history`, `runtime-allocations`, `physical-allocations`,
`generations`,
`debug-session`, `breakpoint-locations`, `versions`, `dependents`, `refresh`,
`refresh-dependents`, `definition-location`, `drop`, `checkpoint`,
`checkpoints`, `checkpoint-restore`, `checkpoint-drop`, `reset`, and `close`.
While an instrumented
evaluation is paused, the nested control loop additionally accepts
`debug-frame`, `debug-page`, `debug-eval`, `debug-eval-native`, `debug-step`,
`debug-step-over`, `debug-step-out`, `debug-restart`, `debug-continue`, and
`debug-abort`. A
standalone paused loop also accepts `interrupt`; capability
`paused-force-interrupt` distinguishes this destructive worker boundary from
cooperative attached-host control. Capability `evaluation-deadlines` advertises
the watchdog path.

Capability `evaluation-phase-timings` advertises an editor-neutral timing event
for every native evaluation attempt. It is emitted immediately before
`complete`, whether the attempt succeeds or fails:

```json
{"protocol_version":1,"id":"eval-1","kind":"timings","success":true,"generation":1,"timings":[{"phase":"controller-preparation","elapsed_ns":11875},{"phase":"frontend-total","elapsed_ns":3201459},{"phase":"frontend-load-resolve","elapsed_ns":1059750},{"phase":"frontend-macro-expansion","elapsed_ns":1179833},{"phase":"frontend-post-expand-resolution","elapsed_ns":127750},{"phase":"frontend-parse","elapsed_ns":44792},{"phase":"frontend-lowering","elapsed_ns":1833},{"phase":"frontend-analysis","elapsed_ns":0},{"phase":"frontend-emission","elapsed_ns":0},{"phase":"frontend-source-map","elapsed_ns":0},{"phase":"frontend-legacy-analysis-emission","elapsed_ns":556084},{"phase":"frontend-unattributed","elapsed_ns":231417},{"phase":"generated-source","elapsed_ns":466875},{"phase":"odin-build","elapsed_ns":469766292},{"phase":"worker-roundtrip","elapsed_ns":145400125},{"phase":"worker-load","elapsed_ns":145180125},{"phase":"native-run","elapsed_ns":112000},{"phase":"worker-unattributed","elapsed_ns":108000},{"phase":"session-commit","elapsed_ns":88084},{"phase":"controller-total","elapsed_ns":619244041}],"generated_bytes":10241}
```

`frontend-total` covers Kvist reading, resolution, expansion, analysis, and
emission. Its more specific entries come from compiler instrumentation;
`frontend-unattributed` is the remaining frontend controller overhead.
`generated-source` covers REPL instrumentation, import rebasing, source-map
formatting, and writing generation files. `odin-build` covers the combined Odin
compile and link command. `worker-roundtrip` covers controller/worker IPC;
`worker-load` is dynamic library loading and registration, `native-run` is the
submitted program, and `worker-unattributed` is the small remainder.
`session-commit` covers the logical binding/result update after successful execution.
`controller-total` is wall-clock request work inside evaluation handling.
Clients should use phase names rather than array positions and tolerate new
phases in later protocol-compatible releases.

Successful timing and completion events also report `native_cache_hit` and
`frontend_cache_hit`. Capability `frontend-generation-cache` advertises the
latter. An exact in-session frontend hit means the submitted source, retained
session declarations, result-history types, source coordinates, compile
options, context dependency fingerprint, and imported source metadata are all
unchanged. Kvist then copies the prior immutable generation artifacts to new
generation-specific paths and executes them again. Execution is never
memoized: mutations, output, allocation, conditions, and other side effects
still happen on every submission. Editing the context or an imported package
invalidates the hit before evaluation.

`native_cache_hit` without `frontend_cache_hit` means Kvist reran the frontend
but found identical instrumented Odin and skipped the Odin build. Explicit
pause-before submissions and native debug-symbol builds remain uncached.

A `bindings` request emits an editor-neutral inventory such as:

```json
{"id":"inspect-1","op":"bindings"}
{"protocol_version":1,"id":"inspect-1","kind":"bindings","success":true,"generation":12,"bindings":[{"name":"foo","kind":"defn","version":2,"generation":10,"abi":"proc(int:borrowed)->i64","stale":false},{"name":"caller","kind":"defn","version":1,"generation":4,"abi":"proc(int:borrowed)->string:owned","dependencies":["foo"],"stale":true}]}
{"protocol_version":1,"id":"inspect-1","kind":"complete","success":true,"generation":12}
```

`versions` returns every committed native version of one logical binding,
including the exact submitted source range that produced it:

```json
{"id":"versions-foo","op":"versions","name":"foo"}
{"protocol_version":1,"id":"versions-foo","kind":"versions","success":true,"generation":12,"versions":[{"version":1,"generation":2,"kind":"defn","abi":"proc(int:borrowed)->int","source_path":"/work/app.kvist","source_start_line":18,"source_start_column":1,"source_end_line":18,"source_end_column":39},{"version":2,"generation":10,"kind":"defn","abi":"proc(int:borrowed)->i64","source_path":"/work/app.kvist","source_start_line":24,"source_start_column":1,"source_end_line":24,"source_end_column":41}]}
{"protocol_version":1,"id":"versions-foo","kind":"complete","success":true,"generation":12}
```

The range is retained independently for each version, so an editor can jump
to an older definition after later compatible or ABI-changing redefinitions.
Refreshing a retained function creates a new executable version but preserves
the location of the source being recompiled. Explicitly evaluating edited
source records its newly submitted path and range. These are generic protocol
fields; Emacs, terminal tooling, DAP clients, and other editors share the same
inventory.

Clients that only need one navigation target use `definition-location`.
Omitting `version` selects the current binding; supplying it selects retained
history without changing session resolution:

```json
{"id":"definition-foo-v1","op":"definition-location","name":"foo","version":1}
{"protocol_version":1,"id":"definition-foo-v1","kind":"definition-location","success":true,"generation":12,"abi":"proc(int:borrowed)->int","source_path":"/work/app.kvist","line":18,"column":1,"end_line":18,"end_column":39,"name":"foo","definition_kind":"defn","version":1,"definition_generation":2}
{"protocol_version":1,"id":"definition-foo-v1","kind":"complete","success":true,"generation":12}
```

`results` reports the current typed aliases without evaluating them:

```json
{"id":"results-1","op":"results"}
{"protocol_version":1,"id":"results-1","kind":"results","success":true,"generation":14,"results":[{"slot":1,"name":"*1","type":"Data","abi":"value:Data","generation":14},{"slot":2,"name":"*2","type":"string","abi":"value:string","generation":13},{"slot":3,"name":"*3","type":"int","abi":"value:int","generation":12}]}
{"protocol_version":1,"id":"results-1","kind":"complete","success":true,"generation":14}
```

`allocations` joins the controller's current binding, recent-result, and
retained-inspection inventories by logical allocation identity:

```json
{"id":"allocations-1","op":"allocations"}
{"protocol_version":1,"id":"allocations-1","kind":"allocations","success":true,"generation":14,"allocations":[{"allocation_id":"binding:answer:v2","owner_id":"repl-worker","kind":"binding","name":"answer","type":"int","abi":"value:int","generation":10,"version":2,"lifecycle":{"ownership":"value","storage":"inline","clone":"copy","destroy":"none","checkpoint":"copy","render":"native"},"retained_owner_chain":["repl-worker"]},{"allocation_id":"inspection-1","owner_id":"repl-worker","kind":"inspection","name":"inspection-1","type":"Point","abi":"value:Point|layout:Point=struct{x:int;y:int;}","generation":13,"lifecycle":{"ownership":"value","storage":"inline","clone":"copy","destroy":"none","checkpoint":"copy","render":"native"},"retained_owner_chain":["repl-worker"],"size":16,"alignment":8}],"allocation_count":2,"known_allocation_bytes":16,"known_allocation_count":1}
```

This is deliberately a logical live inventory, not a heap profiler. Exact
native byte counts are currently known for retained inspections and contribute
to `known_allocation_bytes` and `known_allocation_count`; bindings and recent
results remain counted but do not pretend to have measured sizes. Standalone
and attached controllers advertise `logical-allocation-inventory` and
`attached-logical-allocation-inventory`.

`ownership-history` returns the controller's append-only lifecycle journal for
those logical allocations:

```json
{"id":"ownership-1","op":"ownership-history"}
{"protocol_version":1,"id":"ownership-1","kind":"ownership-history","success":true,"generation":14,"ownership_events":[{"sequence":1,"allocation_id":"binding:answer:v1","action":"acquired","generation":3,"name":"answer","type":"int","owner_to":"repl-worker","reason":"binding definition retained"},{"sequence":2,"allocation_id":"binding:answer:v1","action":"superseded","generation":10,"name":"answer","type":"int","owner_from":"repl-worker","reason":"binding definition replaced"},{"sequence":3,"allocation_id":"binding:answer:v2","action":"acquired","generation":10,"name":"answer","type":"int","owner_to":"repl-worker","reason":"binding definition retained"}],"ownership_event_count":3}
```

The journal distinguishes acquisition, retained inspection snapshots, binding
supersession, explicit drops, and eviction from the three-value recent-result
window. Sequence numbers are session-local and monotonic. `owner_from` and
`owner_to` keep the schema ready for explicit ownership-transfer adapters;
current events describe controller lifecycle changes and do not claim that
arbitrary native pointers moved safely. Reset begins a fresh journal.
Capabilities `ownership-lifecycle-history` and
`attached-ownership-lifecycle-history` advertise the operation.

`runtime-allocations` reports exact physical counters for both checkpoint
snapshot blocks and allocations performed through the allocator shared by
loaded native generations:

```json
{"id":"runtime-memory-1","op":"runtime-allocations"}
{"protocol_version":1,"id":"runtime-memory-1","kind":"runtime-allocations","success":true,"generation":14,"runtime_live_allocations":2,"runtime_live_bytes":24,"runtime_total_allocations":5,"runtime_total_allocated_bytes":56,"runtime_total_frees":3,"runtime_total_freed_bytes":32,"managed_live_allocations":4,"managed_live_bytes":160,"managed_peak_bytes":256,"managed_total_allocations":12,"managed_total_allocated_bytes":640,"managed_total_frees":8,"managed_total_freed_bytes":480}
```

The `runtime_*` fields describe checkpoint blocks still owned by named
checkpoints. The `managed_*` fields measure allocation, resize, and free calls
made by generated code through the host-provided allocator; peak bytes are
reported in addition to current and cumulative totals. All cumulative counters
are monotonic for the lifetime of the native worker. This includes managed
strings, arrays, maps, and explicit default-allocator allocations across loaded
generations without attributing them from guessed layouts. It deliberately
excludes controller strings, loaded-library internals, OS resources, custom
allocators supplied by application code, and allocations made by foreign code
that bypasses the generation context. Standalone and attached controllers
advertise `runtime-checkpoint-allocation-stats`,
`generation-managed-allocation-stats`,
`attached-runtime-checkpoint-allocation-stats`, and
`attached-generation-managed-allocation-stats`.

`physical-allocations` returns the live blocks behind the managed counters:

```json
{"id":"physical-memory-1","op":"physical-allocations"}
{"protocol_version":1,"id":"physical-memory-1","kind":"physical-allocations","success":true,"generation":14,"physical_allocations":[{"allocation_id":"managed:7","owner_id":"generation:9","kind":"managed","size":128,"alignment":8,"generation":9,"retained_owner_chain":["generation:9","result:g14"]},{"allocation_id":"managed:11","owner_id":"result:g14","kind":"managed","size":32,"alignment":8,"generation":14,"retained_owner_chain":["result:g14"]}],"physical_allocation_count":2,"physical_transfers":[{"sequence":1,"allocation_id":"managed:7","owner_from":"generation:9","owner_to":"result:g14","generation":14,"action":"retained","reason":"shared Data result retained"},{"sequence":2,"allocation_id":"managed:11","owner_from":"generation:14","owner_to":"result:g14","generation":14,"action":"transferred","reason":"exclusive result allocation transferred"}],"physical_transfer_count":2}
```

Allocation IDs are worker-local, monotonic, and opaque; native addresses are
never exposed. `owner_id` initially identifies the generation responsible for
the allocation call. A resize retires the old identity and creates a new one,
while a free removes the block from the live inventory. Ordering is stable by
allocation identity. This is physical allocator state, not a claim that the
controller has already discovered every logical value that can reach a block.
`retained_owner_chain` begins with that primary owner and lists any additional
result identities that retain the same block. Transfer history distinguishes
an exclusive `transferred` ownership change from a shared `retained`
relationship.

Result adapters recursively walk compiler-known structs, fixed arrays, slices,
dynamic arrays, and their elements. Every retained string or sequence backing
address encountered is validated against the live allocator map before
responsibility transfers to the exact `result:gN` identity. Traversal is
depth-bounded, and duplicate roots produce only one transfer. An address not
owned by the host allocator is ignored rather than producing a fictional
transfer.

Managed `Data` uses shared attribution instead. Its generated adapter walks
every reachable `Data_Node`, text buffer, item array, and entry array. A
visited-node map makes traversal safe for shared subgraphs and cycles. Each
validated block keeps its allocating generation as primary owner while adding
the exact result identity to `retained_owner_chain`; history records this as
`action:"retained"`. Static quoted `Data` with no allocated node naturally
adds no physical entry.

Native map snapshots transfer their canonical Odin map backing allocation
exclusively to the result. The generated adapter obtains that address through
Odin's runtime map API, then walks every typed key and value through the same
recursive adapters. A map can therefore transfer its own table and nested
strings or sequences while retaining nested `Data` graphs. Empty maps and
backing stores supplied by a custom allocator produce no fictional host
transfer.

Persistent `def` and `defvar` storage uses the same adapters after its
initializer has populated the generation's native cell. Exclusive backing
stores move to `binding:<native-name>:gN`; shared `Data` blocks add that
identity to their retained-owner chain. The generation qualifier matters:
redefinition can leave old compiled callers and old native storage alive, so
the inventory never rewrites an older binding allocation to look like the
new definition. `<native-name>` is the emitted Odin-safe binding identifier
(`user-settings` is represented as `user_settings`) and is therefore
unambiguous at the native boundary. Scalar cells have no allocator block and
naturally add no physical entry.

Custom allocators, pointers, and opaque resources remain attributed to their
allocating generation until a declared adapter can enumerate them safely.
Capabilities
`physical-allocation-inventory` and
`attached-physical-allocation-inventory` advertise the operation;
`physical-result-ownership-transfers` and
`attached-physical-result-ownership-transfers` advertise the history, while
`shared-data-physical-ownership` and
`attached-shared-data-physical-ownership` advertise `Data` graph retention;
`map-result-physical-ownership` and
`attached-map-result-physical-ownership` advertise native map traversal;
`binding-physical-ownership` and
`attached-binding-physical-ownership` advertise persistent binding
attribution.

`inspect` evaluates one expression against the live native session and returns
its rendered value together with the inferred native type and exact ABI:

```json
{"id":"inspect-2","op":"inspect","source":"(+ *1 1)"}
{"protocol_version":1,"id":"inspect-2","kind":"inspection","success":true,"generation":15,"text":"43\n","type":"int","abi":"value:int"}
{"protocol_version":1,"id":"inspect-2","kind":"complete","success":true,"generation":15}
```

Inspection loads a read-only-result generation, so it advances the loaded
generation number and may execute effects in the submitted expression. It does
not register a recent result, rotate `*1`/`*2`/`*3`, or commit definitions.
Persistent declarations are rejected in an inspection request.

The same event carries structural type metadata. Nominal structs, enums, and
unions expose ordered members derived from the exact layout fingerprint.
Dynamic arrays, slices, fixed arrays, maps, pointers, aliases, strings, `Data`,
procedures, and scalars report a stable `shape` plus their relevant element,
key, value, target, or fixed-length metadata. Collection values are rendered as
a bounded first page rather than one unbounded value dump. The default page is
20 entries and the protocol rejects limits above 100. For example:

```json
{"protocol_version":1,"id":"inspect-point","kind":"inspection","success":true,"generation":16,"text":"Point{x = 2, y = 3}\n","type":"Point","abi":"value:Point|layout:Point=struct{x:int;y:int;}","handle":"inspection-1","shape":"struct","members":[{"name":"x","type":"int"},{"name":"y","type":"int"}]}
```

This lets editors present and navigate a type-aware schema without parsing
compiler ABI strings. Each inspection whose native type can be retained also
registers a typed native getter and returns an opaque handle; values outside the
current retention set remain render-only. A child request selects a field from
the retained snapshot:

```json
{"id":"inspect-x","op":"inspect","handle":"inspection-1","path":["x"]}
{"protocol_version":1,"id":"inspect-x","kind":"inspection","success":true,"generation":17,"text":"2\n","type":"int","abi":"value:int","handle":"inspection-2","path":["x"],"shape":"scalar"}
{"protocol_version":1,"id":"inspect-x","kind":"complete","success":true,"generation":17}
```

The parent expression is not run again. The child value receives another
handle, so clients can descend recursively through nested nominal values.
Handles and their generation-owned snapshots live until reset, worker loss, or
session close; this deliberately follows the REPL's relaxed memory policy.
Invalid or expired handles fail normally.

An `inspect` request containing only a handle replays the controller-cached
root snapshot. It does not load a generation, call native code, or reinterpret
the value through the currently visible nominal declaration:

```json
{"id":"inspect-point-again","op":"inspect","handle":"inspection-1"}
```

The replay keeps the original ABI, rendering, layout, allocation identity, and
definition-version metadata. It therefore remains safe after the source name
has been redefined with another layout. Capabilities
`cached-inspection-snapshots` and `attached-cached-inspection-snapshots`
advertise this behavior.

Sequences and maps use the same retained mechanism. An `index` selects from a
dynamic array, slice, or fixed array. A `key_source` is a Kvist expression
compiled with the map lookup and therefore retains the map's native key type:

```json
{"id":"inspect-index","op":"inspect","handle":"inspection-3","index":4}
{"id":"inspect-key","op":"inspect","handle":"inspection-5","key_source":"\"session\""}
```

Selectors are checked against the retained value's shape before compilation.
The source collection is never reconstructed or re-evaluated. Index bounds and
map-key presence retain ordinary native Kvist behavior.

`inspect-page` retrieves another bounded batch from the same retained snapshot:

```json
{"id":"page-2","op":"inspect-page","handle":"inspection-3","offset":20,"limit":20}
{"protocol_version":1,"id":"page-2","kind":"inspection-page","success":true,"generation":18,"type":"[dynamic]int","abi":"value:[dynamic]int","handle":"inspection-3","shape":"dynamic-array","element_type":"int","offset":20,"limit":20,"total":35,"entries":[{"index":20,"value":"42"}]}
{"protocol_version":1,"id":"page-2","kind":"complete","success":true,"generation":18}
```

Sequence entries carry their absolute index. Map entries carry rendered keys
and values and are sorted by their rendered entry text before paging, giving a
stable page order for an unchanged retained snapshot. Entry values are display
previews; selecting one still uses the typed `index` or `key_source` child
request and returns a new recursively navigable handle. Paging does not rotate
recent-result history. Ownership metadata and paused-frame inspection remain
later layers.

The version is the number of distinct successful definitions committed under
that logical name in the current worker session; exact repeated current
function submissions do not increase it. Reset or native-worker loss clears
the inventory along with the executable registry. `versions` returns the
binding's committed history. `dependents` returns its transitive dependency
closure. `refresh` recompiles one function from its retained source;
`refresh-dependents` recompiles the stale function closure that depends on the
named binding. Compilation is all-or-nothing, and a failure preserves the
loaded worker and prior metadata. `drop` refuses a binding with dependents and
otherwise removes it from future compiler state. It does not unload a library
or free storage that an old generation could still reference; reset remains
the deterministic reclamation boundary.

`macroexpand` expands one form using the context package plus the session's
current imports and macros. `expand` emits the exact native-generation Odin
source that the same form would compile through, including current binding and
recent-result adapters. Both return an `expansion` event followed by
`complete`; neither executes code, commits definitions, rotates results, or
advances the generation. Like the standalone `kvist expand` command, generated
Odin inspection stops before the Odin compiler's final name and type checks.

`complete`, `lookup`, `documentation`, and `xref` are read-only compiler
tooling requests. They resolve against the context package, committed session
declarations, and an optional unsaved source overlay. They return structured
symbol records—kind, name, signature, documentation, and source location—and
never evaluate code or advance the generation. Completion results use the
`completions` event kind so they cannot be confused with the terminal
`complete` event. The standalone CLI commands remain useful offline clients of
the same compiler tooling.

The request's `source_path` selects the package and source overlay used for
tooling, including when an editor is visiting a transitively imported file in
an application REPL. `(doc symbol)` provides the corresponding language-level
operation for local declarations, qualified imported members such as
`arr.range`, and compiler forms such as `package`, `defn`, `inc!`, and `+`; the
symbol need not be quoted, and the form returns `nil` after printing.

Documentation is part of the public surface contract. Compiler forms carry a
signature, concise reference prose, and practical examples where useful.
Public declarations in shipped `kvist:*` packages must have declaration docs;
the compiler test suite audits that coverage. Private package implementation
details are excluded from completion and documentation results.

Events cover acknowledgement, compile phase and timings, stdout, stderr,
rendered results with type information, binding changes, diagnostics with
source spans, stale-definition changes, debug pauses, conditions, worker exit,
reset, reload state, and request completion.
Evaluation diagnostics are structured records containing severity, code,
confidence, compiler phase, message, and exact source range. Human-readable
terminal formatting is a client concern; protocol clients do not need to parse
compiler prose to navigate an error or warning.
Protocol versions and generation ABI versions are explicit and negotiated
independently.

The CLI does not know about buffers, regions, overlays, keybindings, Emacs
projects, or editor presentation. Those are client concerns.

### Emacs client

The Emacs package now maintains one asynchronous session per Kvist package
entry file. Buffers routed to the same entry file share the process and native
state. `kvist-repl-start` explicitly starts a session and displays a
project-specific interactive prompt buffer; `C-c C-s` starts it, paired with
`C-c C-q` for quit, and `C-c C-z` starts or switches to it. Forms entered
there use the same protocol session as source-buffer evaluation. Lazy startup
is disabled by default: opening or focusing a Kvist file and passive Eldoc,
completion, xref, or documentation requests never create a session. Those
tools use a live session when one exists and otherwise fall back to file
context. `C-c C-s` is the explicit start boundary; `kvist-repl-auto-start` may
be enabled for a lazy-start workflow. `kvist-repl-restart`, reset, and stop are
explicit editor commands.
The CIDER-compatible `C-c C-q` stops the session; `C-c M-q` remains an alias.
Killing the interactive buffer confirms before stopping its associated
session. In that buffer, the CIDER-familiar `C-c M-o` clears only the visible
transcript. It preserves the native session, definitions, mutable state, input
history, and any unsubmitted prompt input.

The prompt accepts Kvist forms, including the language's explicit Odin escape.
For example, `(odin "1 + 1")` evaluates the embedded expression and prints
`2`. It does not accept bare Odin source. Since an untyped Odin escape is opaque
to Kvist's type analysis, its result is printed but is not retained as a typed
`*1` value. Put Odin statements inside `(odin "...")` in a context that expects
a statement; package-scope raw Odin declarations continue to use the same form
in ordinary source files.

Interactive prompt results use Clojure-style presentation:

```text
kvist=> (+ 1 1)
2
kvist=>
```

They do not carry an additional `=>` prefix. Source-buffer overlays,
minibuffer results, and inserted result comments retain `=>` because it marks
editor-added presentation rather than prompt output.

Existing form, top-level form, region, comment-body, and buffer commands send
their actual source through the protocol. `eval-buffer` submits all active
definitions as one atomic generation rather than running `check`. Package and
inert comment forms are omitted, as is native `main`: Odin treats a DLL-level
`main` as a load-time entrypoint, so application entrypoint replacement stays
an Olive/restart boundary. Emacs owns process lifecycle, package routing,
result overlays, compilation-mode diagnostic navigation, and reset/stop
commands.

The Emacs implementation must not require an Emacs-only CLI command or event.
Protocol fixtures are tested independently of Emacs, and Emacs tests consume
the public protocol like any other client.

## Inspection and Debugging

Kvist should support two complementary debugging layers through editor-neutral
protocols.

### Native source debugging

REPL generations always emit mappings from generated Odin back to Kvist spans.
They emit native debug symbols when the generic evaluation request sets
`native_debug_symbols: true`; ordinary instrumented REPL debugging does not pay
that compile-time cost. Olive development modules retain their native debug
configuration. A standard native debugger adapter provides breakpoints, step
in/over/out, threads, stack frames, watches, and native crash inspection.
Dynamically loaded generation paths, their debug-symbol status, and source maps
are announced as they commit.

The REPL side of that discovery substrate is implemented. Every successfully
loaded generation preserves `generation_NNNN.odin`, `generation_NNNN.map`, and
the platform-native library in the session directory. A generic inventory
request exposes their absolute paths without editor-specific behavior:

```json
{"id":"debug-generations","op":"generations"}
{"protocol_version":1,"id":"debug-generations","kind":"generations","success":true,"generation":12,"generations":[{"generation":12,"source_path":"/tmp/kvist-repl/generation_0012.odin","map_path":"/tmp/kvist-repl/generation_0012.map","library_path":"/tmp/kvist-repl/generation_0012.dylib","debug_symbols":true}]}
{"protocol_version":1,"id":"debug-generations","kind":"complete","success":true,"generation":12}
```

The inventory is append-only while the worker is alive and clears with reset,
worker loss, or session close. Each successful load also emits a
`generation-loaded` event carrying the new inventory row, so an attached
debugger does not need to poll between submissions. Generation libraries are
built with native debug information.

The controller also exposes the child process that owns those libraries:

```json
{"id":"debug-native","op":"debug-session"}
{"protocol_version":1,"id":"debug-native","kind":"debug-session","success":true,"generation":12,"worker_pid":48152,"worker_epoch":2,"capabilities":["compiled-abort-operation-restarts","compiled-retry-skip-restarts","native-attach","nested-break-eval","typed-conditions","debug-symbols","generation-loaded-events","generated-source-maps","kvist-breakpoint-locations","instrumented-conditions","instrumented-pause-before","instrumented-step-into","instrumented-step-out","instrumented-step-over","instrumented-trace","instrumented-trace-summary","instrumented-trace-timing","instrumented-trace-values","paused-direct-struct-fields","paused-dynamic-array-paths","paused-dynamic-array-pages","paused-fixed-array-paths","paused-frame-eval","paused-local-snapshots","paused-map-pages","paused-map-paths","paused-nested-collection-pages","paused-nested-collection-roots","paused-nested-struct-fields","paused-runtime-nested-collection-pages","paused-runtime-page-discovery","typed-frame-descriptors","typed-use-value-restarts","worker-replacement-events"]}
{"protocol_version":1,"id":"debug-native","kind":"complete","success":true,"generation":12}
```

The epoch distinguishes successive workers even if the operating system later
reuses a PID. Initial `ready` and successful `reset` events carry the same
metadata. Automatic recovery after a native crash emits `worker-replaced`
before compiling into the replacement. An adapter can therefore attach to the
worker, register every `generation-loaded` library and map, and reliably detect
when it must reattach.

Evaluations may include their editor origin:

```json
{"id":"define-total","op":"eval","source":"(defn total [xs: []int] -> int (reduce + 0 xs))","source_path":"/work/app.kvist","line":18,"column":1}
```

Program output and the submitted form's value are distinct protocol events.
Calls such as `println` emit ordered `stream-output` events while the native
evaluation is running; the final rendered value remains an `output` event.
Clients can therefore route program output to a transcript without including
it in an inline result:

```json
{"protocol_version":1,"id":"score","kind":"stream-output","success":true,"generation":13,"stream":"stdout","text":"scoring item\n"}
{"protocol_version":1,"id":"score","kind":"output","success":true,"generation":13,"stream":"stdout","text":"42\n"}
{"protocol_version":1,"id":"score","kind":"complete","success":true,"generation":13}
```

The controller retains the resulting source spans with the loaded generation.
An editor can translate a Kvist line without parsing generated Odin:

```json
{"id":"break-total","op":"breakpoint-locations","source_path":"/work/app.kvist","line":18}
{"protocol_version":1,"id":"break-total","kind":"breakpoint-locations","success":true,"generation":12,"breakpoints":[{"generation":12,"source_path":"/work/app.kvist","source_start_line":18,"source_start_column":1,"source_end_line":18,"source_end_column":57,"generated_path":"/tmp/kvist-repl/generation_0012.odin","generated_start_line":141,"generated_end_line":143}]}
{"protocol_version":1,"id":"break-total","kind":"complete","success":true,"generation":12}
```

Locations belong to the live worker: reset and native crash recovery discard
them together with the unloaded generations. Multiple candidates may be
returned when nested forms or retained versions overlap the requested line.

The Emacs package provides default interactive LLDB/GDB attachment and
breakpoint commands, plus customizable launch and breakpoint functions for DAP
or other integrations. The generic CLI reports metadata and translations only.
Pure scalar frame expressions and same-worker native break evaluation use that
same generic protocol. Managed-value traversal through a suspended frame still
requires compiler-described accessors.

Emacs presents this through its debugger package; the Kvist CLI does not contain
Emacs-specific commands. Other editors can consume the same debugger and REPL
protocols.

### Kvist form debugging

Instrumented pause and source-level step-into are implemented. An `eval`
request can ask the compiler to pause before the submitted form begins native
execution:

```json
{"id":"debug-eval","op":"eval","source":"(calculate-order cart)","source_path":"/work/app.kvist","line":84,"column":3,"pause_before":true}
{"protocol_version":1,"id":"debug-eval","kind":"paused","success":true,"generation":13,"pause_id":"pause-13","source_path":"/work/app.kvist","line":84,"column":3}
```

The evaluation remains pending and the native worker is genuinely blocked.
While paused, the controller accepts frame queries and a matching continuation:

```json
{"id":"frame-1","op":"debug-frame","pause_id":"pause-13"}
{"id":"continue-1","op":"debug-continue","pause_id":"pause-13"}
{"protocol_version":1,"id":"continue-1","kind":"resumed","success":true,"generation":13,"pause_id":"pause-13"}
{"protocol_version":1,"id":"continue-1","kind":"complete","success":true,"generation":13}
```

The original `debug-eval` request then produces its normal output and
completion. This nested control loop prevents unrelated evaluation from
silently entering a worker whose stack is suspended.

The same loop accepts cooperative cancellation without replacing the worker:

```json
{"id":"abort-1","op":"debug-abort","pause_id":"pause-13"}
{"protocol_version":1,"id":"abort-1","kind":"abort-requested","success":true,"generation":13,"pause_id":"pause-13"}
{"protocol_version":1,"id":"debug-eval","kind":"aborted","success":true,"generation":13,"message":"evaluation aborted"}
{"protocol_version":1,"id":"debug-eval","kind":"complete","success":false,"generation":13,"message":"evaluation aborted"}
```

`debug-abort` propagates through generated safe-point guards and ordinary
returns. It runs `defer` cleanup and suppresses the abandoned result while
retaining the worker, loaded generations, and state changes that happened
before the pause. Capability `instrumented-debug-abort` advertises this path.

Because a worker has only one active pause, these nested operations may omit
`pause_id` to address it directly. Supplying the ID remains preferable for
asynchronous clients because a stale command then cannot affect a later pause.

Emacs exposes the flow as `C-c M-e` (debug-evaluate form) and `C-c M-c`
(continue), highlights the paused Kvist line, and clears the indication on
resume.

The pause loop can also compile and run a new generation without unwinding the
suspended stack:

```json
{"id":"probe-helper","op":"debug-eval-native","source":"(helper 20)","pause_id":"pause-13"}
{"protocol_version":1,"id":"probe-helper","kind":"generation-loaded","success":true,"generation":14,"generations":[{"generation":14,"source_path":"/tmp/kvist-repl/generation_0014.odin","map_path":"/tmp/kvist-repl/generation_0014.map","library_path":"/tmp/kvist-repl/generation_0014.dylib","debug_symbols":true}]}
{"protocol_version":1,"id":"probe-helper","kind":"output","success":true,"generation":14,"stream":"stdout","text":"21\n"}
{"protocol_version":1,"id":"probe-helper","kind":"complete","success":true,"generation":14}
{"protocol_version":1,"id":"debug-eval","kind":"paused","success":true,"generation":13,"pause_id":"pause-13","source_path":"/work/app.kvist","line":84,"column":3}
```

`debug-eval-native` uses the same worker and live procedure/value registries as
the suspended program. It can call session functions, inspect globals through
ordinary Kvist code, and install a compatible redefinition. Newly compiled
calls and explicitly refreshed dependents resolve that version. Existing
compiled functions retain their call targets, whether they are already on the
stack or entered later; Kvist does not rewrite machine code underneath a live
generation. The outer pause event is emitted again after the
nested request completes so stateful clients can restore its frame after an
inner pause. A nested native evaluation may itself reach `debug.break` or a
condition; its controls nest recursively, to a bounded depth, before returning
to the outer break session.

This operation does not expose suspended lexical locals or native addresses;
use `debug-eval` for copied-frame scalar/path expressions. The suspended
request must also be expression-only: definitions in that still-uncommitted
outer generation are rejected to keep session commit order unambiguous.
Tracing is not supported inside the break session. Native crashes retain their
ordinary worker-failure semantics rather than becoming conditions.

Emacs exposes same-worker evaluation as `C-c M-l` on the form at point.
Definitions can be sent with a prefix argument to suppress result printing.
This remains an editor-neutral CLI operation; other clients use the same
`debug-eval-native` request and `nested-break-eval` capability.

`debug-step` resumes the current pause and arms exactly one compiler-inserted
safe point:

```json
{"id":"step-1","op":"debug-step","pause_id":"pause-13-84-97"}
{"protocol_version":1,"id":"step-1","kind":"stepping","success":true,"generation":14,"pause_id":"pause-13-84-97"}
{"protocol_version":1,"id":"step-1","kind":"complete","success":true,"generation":14}
{"protocol_version":1,"id":"debug-call","kind":"paused","success":true,"generation":14,"pause_id":"pause-13-101-126","source_path":"/work/app.kvist","line":22,"column":5}
```

The compiler places optional safe points before executable body forms in REPL
generations. They are inert during ordinary execution and block only when a
step is armed. Because called REPL functions contain the same points,
`debug-step` has step-into semantics: the next point may be in the current
function or the first executable form of a called function. The command does
not recompile, replay, or interpret the expression. If execution returns
without encountering another point, the step request expires with that
evaluation and cannot stop an unrelated later submission.

The worker also tracks the logical depth of instrumented Kvist calls. Two
additional commands use that depth without exposing native stack addresses:

```json
{"id":"over-1","op":"debug-step-over","pause_id":"pause-13-101-126"}
{"id":"out-1","op":"debug-step-out","pause_id":"pause-13-140-155"}
```

`debug-step-over` ignores safe points in deeper calls and stops at the next
point at the current or a shallower depth. `debug-step-out` ignores the rest
of the current call and stops after control reaches a shallower instrumented
Kvist frame. Explicit `debug.break` points still pause immediately and take
precedence over an armed depth step. At top level, or when no qualifying later
point exists, either operation simply lets the evaluation finish and expires.
Procedure literals, compiler specializations, and source constructors use the
same frame accounting as named REPL procedures.

Emacs binds step-into to `C-c M-n`, step-over to `C-c M-o`, and step-out to
`C-c M-u`. More importantly, each pause installs a temporary debugger mode in
the paused source buffer and renders a compact command prompt after the
highlighted source line. The prompt exposes `n`, `o`, `u`, `c`, `e`, `f`, `p`,
and `q` for next/step-into, step-over, step-out, continuing, evaluating a frame
expression, opening the detailed frame, paging a collection, and aborting the
active evaluation. `q` sends `debug-abort`; it does not kill the standalone
worker or detach the application. Generated safe points cooperatively unwind
instrumented Kvist frames through normal returns, so `defer` cleanup runs while
the resident REPL state remains available. Side effects completed before the
pause remain visible, just as they do after an interrupted Clojure evaluation.
These bindings exist
only while execution is paused and are removed on resume. This follows CIDER's
source-first debugger interaction; the automatically refreshed debug-frame
buffer is a secondary detailed view. Native LLDB/GDB attachment remains
available for instruction-level or non-Kvist stack control.

Definitions evaluated in the REPL may also contain an explicit persistent safe
point:

```clojure
(import "kvist:debug" :as debug)

(defn calculate-order [cart: Cart] -> Order
  (let [subtotal (cart-total cart)]
    (debug.break)
    (apply-discounts cart subtotal)))
```

`debug.break` is a statement with no arguments and is rejected by ordinary
ahead-of-time builds. Its native callback retains the generation and exact
source span that defined it. If generation 20 later calls a function defined
in generation 13, the pause frame still identifies generation 13 rather than
the caller. Reset and worker replacement invalidate the point together with
its native library.

An explicit recoverable condition uses the same safe machinery:

```clojure
(import "kvist:condition" :as condition)

(defn validate-count [count: int] -> int
  (do
    (condition.signal :validation/invalid-count "inspect invalid count")
    count))
```

`condition.signal` is part of the general `kvist:condition` system and works in
ordinary compiled programs as well as native REPL generations. Dynamically
scoped program handlers get the first opportunity to choose an advertised
restart. When none accepts the condition, the REPL emits a `condition` event
instead of an ordinary `paused` event, including `condition_type`, the message,
EDN-rendered `condition_data`, the captured typed frame, and available
restarts. Clients can display the context without implementing Kvist's reader;
they may parse it as EDN when structured navigation is useful:

```json
{"protocol_version":1,"id":"validate","kind":"condition","success":true,"generation":14,"message":"inspect invalid count","pause_id":"pause-14-20-31","condition_type":"validation/invalid-count","condition_data":"{}","restarts":[{"name":"continue","label":"Continue from this safe point","requires_value":false}],"frames":[{"frame_id":"frame-pause-14-20-31","locals":[{"name":"count","type":"int","value":"-1"}]}]}
{"id":"resume-condition","op":"debug-restart","name":"continue","pause_id":"pause-14-20-31"}
{"protocol_version":1,"id":"resume-condition","kind":"restart-invoked","success":true,"generation":14,"pause_id":"pause-14-20-31","restart":"continue"}
{"protocol_version":1,"id":"resume-condition","kind":"complete","success":true,"generation":14}
```

`continue` resumes immediately after the explicit condition safe point.
Ordinary `debug-frame`,
`debug-page`, and `debug-eval` requests remain available while the condition
is active. The restart list and invocation are generic protocol data; Emacs,
terminal clients, DAP adapters, and other editors use the same operations.

A compiled typed replacement boundary is also implemented:

```clojure
(defn repaired-count [input: int] -> int
  (do
    (defvar count: int input)
    (condition.use-value! count "replace invalid count")
    count))
```

`condition.use-value!` requires a visible mutable `int`, `bool`, `f32`, `f64`, or
`string` local. Its condition advertises both `continue` and a value-taking
`use-value` restart:

```json
{"protocol_version":1,"id":"repair","kind":"condition","success":true,"generation":15,"message":"replace invalid count","condition_type":"kvist/condition","restarts":[{"name":"continue","label":"Continue from this safe point","requires_value":false},{"name":"use-value","label":"Replace the mutable local and continue","requires_value":true,"value_type":"int"}]}
{"id":"replace","op":"debug-restart","name":"use-value","source":"42","pause_id":"pause-15-30-70"}
{"protocol_version":1,"id":"replace","kind":"restart-invoked","success":true,"generation":15,"restart":"use-value"}
```

The controller validates the submitted value against `value_type` before
resuming. An invalid value returns a failed `complete` event and leaves the
condition active, so the client can correct it or choose another restart. The
worker returns the selected restart and copied payload to generated code; only
then does the compiled boundary assign the local and continue. Choosing
`continue` leaves the local unchanged. No native stack is unwound and no
address is exposed to the client.

Numeric and boolean payloads are parsed independently by the controller and
the generated boundary. Strings preserve their exact submitted bytes,
including whitespace and the empty string. The worker retains restart payload
storage for its lifetime, so a replaced string remains valid across later
pauses and retained REPL results. Worker reset or replacement discards that
storage together with the rest of the worker-owned session state.

Retry and skip are explicit compiled control-flow boundaries:

```clojure
(defn read-config [] -> int
  (do
    (defvar attempts: int 0)
    (condition.restart-case
      (do
        (inc! attempts)
        (condition.signal :config/unavailable "configuration unavailable")
        (apply-config)))
    attempts))
```

A `condition.signal` lexically inside `condition.restart-case` advertises
`continue`, `retry`, and `skip`. `continue` resumes after the condition,
`retry` re-enters the region at its first form, and `skip` exits the region
and resumes after it. Nested cases use the nearest lexical region. Conditions
raised inside a separately compiled callee do not acquire the caller's
restarts; put the condition at the boundary where native control flow is
explicit.

Retry is not rollback. Mutations and external effects from an earlier attempt
remain visible, while locals declared inside the region are entered again.
This is useful in the REPL because a retry can call a newly redefined,
signature-compatible function implementation. It is also honest about native
execution: generated labeled control flow performs the branch, with no stack
capture or synthesized continuation.

`condition.operation` establishes the narrower abort boundary:

```clojure
(condition.operation
  (let [stream (open-config) :defer]
    (condition.signal :io/unavailable "configuration unavailable")
    (apply-config stream)))
```

A condition lexically inside this form advertises `continue` and
`abort-operation`. Choosing `abort-operation` exits the enclosing operation
and resumes at the form after it. Odin scope exit runs ordinary `defer`,
`errdefer`, and compiler-generated owned-local cleanup before control leaves
the region. Nested operations target the nearest lexical operation.

This is intentionally distinct from terminating the evaluation or unwinding
an arbitrary callee. A condition compiled in another function does not inherit
the caller's operation boundary. Put the condition inside the operation where
the transfer is explicit, or return a typed failure to that boundary. Generic
clients discover this facility through
`compiled-abort-operation-restarts`; Emacs presents the advertised restart
without implementing the control flow.

Every pause includes a typed frame descriptor, also queryable with
`debug-frame` while execution remains suspended:

```json
{"frame_id":"frame-pause-13-84-97","pause_id":"pause-13-84-97","generation":13,"definition_name":"checkout","definition_version":2,"source_path":"/work/app.kvist","line":21,"column":5,"phase":"before-form","locals":[{"name":"cart","type":"Cart","mutable":false,"ownership":"borrowed","value":"Cart{...}","paths":[{"path":"subtotal","type":"int","value":"42"},{"path":"paid","type":"bool","value":"false"},{"path":"samples","type":"[2]int","value":"[2]int{40, 42}"},{"path":"samples[0]","type":"int","value":"40"},{"path":"samples[1]","type":"int","value":"42"}]},{"name":"discount","type":"int","mutable":false,"ownership":"value","value":"3"}]}
```

The compiler records the lexically visible local names, types, mutability, and
ownership at each `before-form` point. Shadowed bindings resolve to the
innermost binding. This is durable generation metadata, not reconstructed from
native debugger symbols, so every protocol client sees the same frame.
Frames executing retained session definitions also identify the logical
definition and exact version. A client can therefore correlate a pause with
`versions` or request its `definition-location` directly, even when a later
redefinition is current. The `versioned-definition-frames` debug capability
advertises this contract. Refresh-created versions retain and reuse the
original editor source range rather than exposing the controller's generated
refresh batch as user source.

At the safe point, generated code renders each described local while it is
still live. The worker copies those renderings onto its private control
channel, and the controller attaches them to an ephemeral paused frame. The
temporary byte pointers exist only for the synchronous in-process callback;
no local address reaches the controller or a client. Borrowed storage is never
accessed after continuation, and a later `debug-frame` query reads the copied
snapshot rather than touching suspended native memory. The
`paused-local-snapshots` capability advertises this behavior.

For a visible nominal struct, the compiler also describes and snapshots its
fields in deterministic preorder. Nested nominal fields use flat relative
paths such as `cursor.line` in the local's `paths` array. Fixed arrays use the
same representation, including paths such as `[0]` on an array local and
`samples[1]` inside a struct. Structs nested in fixed arrays and fixed arrays
nested in structs are traversed consistently. The frame therefore exposes
typed aggregate paths without parsing display text, retaining the aggregate,
or making a native address available after the synchronous callback.

Snapshot expansion is capped at 256 paths per local in deterministic preorder,
preventing a very large fixed array from making a pause unexpectedly
unbounded. The root rendering remains available when the cap is reached.
Generic clients can feature-detect these schemas through
`paused-direct-struct-fields`, `paused-nested-struct-fields`, and
`paused-fixed-array-paths`.

A visible top-level dynamic array carries `element_type`, `capture_limit`,
exact runtime `total`, and `truncated` metadata. Scalar elements use the full
64-path budget, producing `[0]` through `[63]`. Aggregate elements reuse their
compiler-described nominal/fixed-array path templates: a one-field struct
therefore captures at most 32 elements as `[i]` plus `[i].field`. The capture
limit is always at least one and the complete local remains bounded to 64
expanded paths. An empty array reports `total: 0`; a larger array reports
`truncated: true`.

Its root `value` is a bounded count summary rather than a rendering of the
entire collection. This work is synchronous and bounded inside the safe-point
callback. It does not retain the dynamic array or permit later reads outside
the captured window. Direct and pure scalar evaluation use normal paths such
as `points[1].line`; they still operate only on copied snapshots. Generic
clients feature-detect this through `paused-dynamic-array-paths`.

While execution is suspended, a client may request any bounded page from a
top-level dynamic-array local, including data beyond the eager 64-path
snapshot:

```json
{"id":"tail","op":"debug-page","source":"values","offset":64,"limit":2,"pause_id":"pause-13-84-97"}
{"protocol_version":1,"id":"tail","kind":"debug-page","success":true,"generation":14,"shape":"dynamic-array","element_type":"int","offset":64,"limit":2,"total":66,"entries":[{"index":64,"value":"64"},{"index":65,"value":"65"}],"pause_id":"pause-13-84-97","collection_path":"values"}
{"protocol_version":1,"id":"tail","kind":"complete","success":true,"generation":14}
```

`limit` defaults to 20 and may not exceed 100. The request is serviced
synchronously by a type-specialized renderer while the owner and native stack
are still live. Only rendered page values cross the worker boundary; the
descriptor and collection address cease to exist on continuation. Page
renderings of aggregate elements containing further runtime collections use
the same bounded summaries as frame snapshots. The generation ABI carries
this paging descriptor independently of any editor, and generic clients
feature-detect it through `paused-dynamic-array-pages`.

The same request pages a top-level map. Entries are ordered by key, and carry
both their stable page index and rendered key:

```json
{"id":"scores","op":"debug-page","source":"scores","offset":1,"limit":2,"pause_id":"pause-13-84-97"}
{"protocol_version":1,"id":"scores","kind":"debug-page","success":true,"generation":14,"shape":"map","key_type":"string","value_type":"int","offset":1,"limit":2,"total":3,"entries":[{"index":1,"key":"bob","value":"8"},{"index":2,"key":"zoe","value":"9"}],"pause_id":"pause-13-84-97","collection_path":"scores"}
{"protocol_version":1,"id":"scores","kind":"complete","success":true,"generation":14}
```

Map paging supports the same string, integer, and boolean keys as eager map
paths. The renderer retains only the ordered prefix needed to answer the
requested page, rather than copying every entry. Aggregate map values preserve
the bounded runtime-collection summaries described above. Clients detect this
operation through `paused-map-pages`.

A visible top-level map with a `string`, integer, or `bool` key exposes
`key_type`, `value_type`, `capture_limit`, exact runtime `total`, and
`truncated` metadata. Its root is the bounded summary `<map count=N>`.
Captured entries appear in the same `paths` array using ordinary Kvist source
paths such as `["alice"]`, `[7]`, and `[false]`. Aggregate values reuse the
compiler's struct/fixed-array templates, so `users["alice"].active` is
available when that scalar path falls inside the local's 64-path budget.

Map iteration order is not exposed. Generated safe-point code retains the
smallest capture window according to the key type's ordering and emits that
window in sorted order, making snapshots deterministic between pauses without
copying an unbounded key set. The snapshot's memory and protocol output are
bounded, although selecting a deterministic window must scan the map.
Unsupported map key types still receive the bounded root count summary but no
entry paths.
Direct and pure scalar paused evaluation can use captured map paths such as
`scores["alice"]` and `(+ scores["bob"] 2)`. Generic clients feature-detect
this schema through `paused-map-paths`.

Runtime collections nested inside a nominal struct, fixed array, captured
dynamic-array element, or captured map value never fall back to `%#v`
rendering of the complete collection. Their path value is a bounded
`<dynamic-array count=N>` or `<map count=N>` summary. Any enclosing aggregate
whose normal rendering would recursively include such a collection uses
`<aggregate type=T>` at that path; its ordinary scalar child paths and nested
collection count roots remain available separately. This rule applies to
unsupported map key types as well, so merely stopping at a safe point cannot
accidentally stringify an arbitrarily large nested map.

Collections at compiler-described paths inside structs and fixed arrays are
also pageable without recursively expanding them at pause time:

```json
{"id":"history","op":"debug-page","source":"state.history","offset":2,"limit":2,"pause_id":"pause-15-143-156"}
{"protocol_version":1,"id":"history","kind":"debug-page","success":true,"generation":16,"shape":"dynamic-array","element_type":"int","offset":2,"limit":2,"total":4,"entries":[{"index":2,"value":"30"},{"index":3,"value":"40"}],"pause_id":"pause-15-143-156","collection_path":"state.history"}
```

This includes paths through arbitrary nominal-struct and fixed-array nesting,
such as `state.workers[1].labels`. Runtime-indexed paths within the eager
collection window are pageable too:

```json
{"id":"events","op":"debug-page","source":"groups[7].events","offset":20,"limit":10}
{"id":"user-events","op":"debug-page","source":"users[\"alice\"].events","offset":20,"limit":10}
```

Generated code reserves fixed-capacity pools for shallow collection headers
before traversing dynamic-array elements or deterministically selected map
values. Descriptor addresses therefore remain stable across generated loops
and repeated page requests, without retaining the native owners after
continuation. Runtime paths and pools are reclaimed when the safe point
returns. The number of initially advertised runtime-indexed descriptors
follows the same compiler-derived eager element/map-entry budget as frame
paths.

Paging a dynamic-array or map parent now acquires descriptors for nested
dynamic arrays and maps reached through the returned elements or values,
including entries beyond that initial budget. The `debug-page` event returns
newly acquired descriptors in `collections`; they are immediately usable by
later `debug-page` requests and also appear in subsequent `debug-frame`
responses:

```json
{"id":"parent","op":"debug-page","source":"items","offset":23,"limit":1}
{"protocol_version":1,"id":"parent","kind":"debug-page","success":true,"shape":"dynamic-array","element_type":"Item","offset":23,"limit":1,"total":24,"entries":[{"index":23,"value":"<aggregate type=Item>"}],"collections":[{"path":"items[23].events","shape":"dynamic-array","element_type":"int"}],"collection_path":"items"}
{"id":"child","op":"debug-page","source":"items[23].events","offset":0,"limit":2}
```

Acquisition remains page-bounded and only copies descriptor metadata across
the worker boundary. Array-element descriptors can address their stable live
element directly. Map values instead contribute a shallow, worker-owned copy
of the dynamic-array or map header; the backing storage remains owned by the
paused program, and the copied header is released on continuation. Repeated
parent pages deduplicate paths. Generated discovery renderers are bounded to
eight nested runtime-collection layers so recursive native types cannot cause
unbounded code generation.

Generic clients detect compiler-described nesting through
`paused-nested-collection-pages`, runtime-indexed nesting through
`paused-runtime-nested-collection-pages`, demand acquisition through
`paused-runtime-page-discovery`, and bounded-root rendering through
`paused-nested-collection-roots`.

A lexical slot whose owned value was transferred renders as `<moved>`. A slot
explicitly released before the safe point renders as `<unavailable>` and is
never dereferenced for debugging. Its described paths receive the same marker
without accessing the dead or transferred owner.

While paused, `debug-eval` returns any visible local's copied rendering with
the compiler-recorded type. Aggregate children use ordinary Kvist paths such
as `cart.subtotal`, `state.cursor.line`, or `state.samples[1]`. It also
evaluates pure expressions over `int` and `bool` local or path snapshots:

```json
{"id":"check-subtotal","op":"debug-eval","source":"(and (> cart.subtotal 0) (< cart.subtotal 100))","pause_id":"pause-13-84-97"}
{"protocol_version":1,"id":"check-subtotal","kind":"debug-value","success":true,"generation":14,"text":"true","type":"bool","pause_id":"pause-13-84-97"}
{"protocol_version":1,"id":"check-subtotal","kind":"complete","success":true,"generation":14}
```

The `paused-frame-eval` subset includes integer and boolean literals, visible
scalar locals, nominal field paths, and captured fixed-array, dynamic-array,
and map paths; checked
`+`, `-`, `*`, `/`, `%`, `min`, and `max`; comparisons; short-circuit
`and`/`or`/`not`; and lazy three-branch `if`. Integer overflow and zero
division return diagnostics. Calls, mutation, uncaptured dynamic collection
traversal, floating-point arithmetic, and managed values are rejected.
Evaluation occurs solely over copied snapshots in the controller; it neither
invokes suspended native code nor pretends rendered aggregates are live
values.

Mutation of paused locals is excluded initially. Later mutation must use an
explicit operation or restart that can enforce type and ownership invariants.
Raw native-debugger memory editing remains a low-level escape hatch, not a
language guarantee.

The live inspector returns a rendered expression value, its inferred native
type, exact ABI, generation, structured type schema, lifecycle descriptor,
exact native size/alignment, logical owner/allocation identities, and a
retained typed handle without
rotating recent-result history. The descriptor reports ownership and storage
classes and the available clone, destruction, checkpoint, and render
operations. Nominal members and collection element/key/value types are
editor-neutral protocol data. The Emacs client treats point anywhere on a
call's head—including compound type heads such as `[dynamic]int` and
`map[string]int`—as selection of the enclosing call, while arguments remain
individually inspectable. Every inspector page renders its context-sensitive
commands so field/entry activation, explicit child selection, back navigation,
paging, and window closing are discoverable without knowing bindings in
advance. Struct
fields can be retrieved recursively from the captured snapshot, as can indexed
sequence elements and typed map entries. Collection rendering is bounded and
paged from the retained snapshot. Capabilities `native-layout-metadata` and
`attached-native-layout-metadata` advertise `size` and `alignment` fields
measured inside the generated native generation. Nominal definitions also
publish a layout ABI per version. Capabilities
`inspection-definition-versions` and
`attached-inspection-definition-versions` advertise exact definition name,
kind, version, generation, and source range on matching inspection events,
so an inspection remains attributable to its precise nominal layout even after
the client later observes a type redefinition. Handle-only inspection replays
that cached snapshot without touching native storage. Logical allocation
inventory, exact known-size counters, and physical checkpoint-block counters
are now exposed. Generated code also allocates through a host-tracked allocator,
providing exact generation-local managed-memory totals and an opaque live-block
inventory. Verified strings and sequence roots nested through compiler-known
structs, fixed arrays, slices, and dynamic-array elements also transfer to
their logical result identities. Native maps now transfer their canonical
backing table and recursively adapt typed keys and values; managed `Data`
graphs publish shared physical retention. The next inspector layer should
extend those adapters through declared resource lifecycles.

Bounded source-level tracing is implemented over the REPL instrumentation
already present in live generations. A normal `eval` request opts in without
changing the language expression:

```json
{"id":"trace-order","op":"eval","source":"(calculate-order cart)","trace":true,"trace_limit":1000,"trace_values":true,"trace_value_limit":100}
{"protocol_version":1,"id":"trace-order","kind":"trace","success":true,"generation":14,"source_path":"/work/app.kvist","line":21,"column":5,"trace_id":"pause-13-84-97","depth":1,"elapsed_ns":18492,"delta_ns":18492}
{"protocol_version":1,"id":"trace-order","kind":"trace-values","success":true,"generation":14,"source_path":"/work/app.kvist","line":21,"column":5,"trace_id":"pause-13-84-97","trace_values":[{"name":"subtotal","type":"int","mutable":false,"ownership":"value","value":"4200"},{"name":"cart","type":"Cart","mutable":false,"ownership":"borrowed","value":"<not-captured type=Cart>"}]}
{"protocol_version":1,"id":"trace-order","kind":"trace","success":true,"generation":14,"source_path":"/work/app.kvist","line":22,"column":5,"trace_id":"pause-13-101-126","depth":2,"elapsed_ns":23107,"delta_ns":4615}
{"protocol_version":1,"id":"trace-order","kind":"trace-summary","success":true,"generation":14,"trace_points":2,"trace_total_ns":28144,"trace_unattributed_ns":18492,"hotspots":[{"source_path":"/work/app.kvist","line":21,"column":5,"trace_id":"pause-13-84-97","hits":1,"total_ns":4615,"max_ns":4615},{"source_path":"/work/app.kvist","line":22,"column":5,"trace_id":"pause-13-101-126","hits":1,"total_ns":5037,"max_ns":5037}]}
```

Trace callbacks report the safe-point identity, logical Kvist call depth,
`elapsed_ns` since native evaluation began, and `delta_ns` since the preceding
emitted safe point. Both clocks are monotonic and exclude compilation,
generation loading, and controller transport. The first event's delta equals
its elapsed time. A later delta describes execution along the path from the
previous safe point to the current one; it is not exact inclusive or exclusive
time for the current source form. Callbacks do not pause, allocate frame
snapshots, render locals, or expose native addresses. Events stream while the
native evaluation runs and retain the original defining generation's source
mapping even when a newer generation calls an older function.

Every traced evaluation ends with one `trace-summary`. Its hotspots are sorted
by descending `total_ns` and aggregate intervals by stable safe-point identity.
An interval is charged to the preceding safe point because it measures
execution after that point and before the next callback. `hits` counts charged
intervals and `max_ns` preserves the slowest one. Time before the first safe
point is reported as `trace_unattributed_ns`.

`trace_values` opts into non-blocking lexical value events and requires
`trace:true`. `trace_value_limit` defaults to 100 captured safe points and is
capped at 1000 independently of `trace_limit`; reaching it emits one
`trace-values-limit` event while timing and control-flow tracing continue.
Each event carries at most 32 top-level visible locals in compiler lexical
order. Numeric, boolean, enum, pointer-like, keyword, and other compact scalar
values are rendered directly. Strings are capped at 256 bytes and marked when
truncated. Aggregates, `Data`, dynamic arrays, maps, and other potentially
large values carry a typed `<not-captured ...>` placeholder. Moved and
unavailable locals remain explicit. This makes tracing safe and predictable;
recursive values and live collection pages remain debugger-pause operations.

`trace_limit` defaults to 1000 and is capped at 10000. On the first safe point
beyond the limit, the controller emits one `trace-limit` event and lets native
execution continue without further trace events for the remainder of that
evaluation. Trace state is cleared at generation completion, worker
replacement, or reset, so it cannot leak into an unrelated later submission.
The worker timestamps both truncation and native completion. Consequently,
time after the first omitted safe point remains unattributed in the summary
instead of being falsely charged to the last visible source form.

The next trace layers should add allocation counts, ownership transfers, exact
form spans where their overhead is justified, and recent traced values as
first-class inspection results. Those require richer instrumentation than the
current timed control-flow trace and should remain absent from production
builds unless explicitly requested.

## Conditions, Restarts, and the Break REPL

The first conditions/restarts foundation is implemented without pretending
native faults are recoverable. `condition.signal` establishes an explicit safe
point with a stable keyword or string identity, a dynamic message, and optional
dynamic `Data` context:

```clojure
(condition.signal :io/not-found "configuration file is missing")
(condition.signal "validation/out-of-range" "port must be positive")
(condition.signal :io/not-found message {:path path-data})
```

The keyword's leading colon is syntax and is omitted from the protocol value,
so the first event has `condition_type:"io/not-found"`. Kvist first searches
the dynamically scoped `condition.with-handlers` stack on the current thread. A
matching handler may select an advertised restart, and the compiled program
continues without involving a client. If every handler declines, the controller
reports the stable condition type, message, Data context, source, ownership-safe frame
snapshot, and restart list, then runs the same nested inspection loop used by a
debug pause. This lets clients dispatch presentation or policy by identity
rather than parsing prose. Generic clients advertise support as
`typed-conditions`.
`debug-restart` invokes a named restart. The current foundation exposes
`continue`, plus typed `use-value` at explicit `condition.use-value!` mutation
boundaries.

The Emacs client opens `*Kvist Condition*`, shows the condition and visible
locals, and presents the advertised restarts as recovery options. `C-c M-x`
(or `r` in the condition buffer) chooses recovery. This is presentation over the generic
JSONL protocol, not an Emacs command embedded in the CLI.

Programmatic handlers and the interactive client use the same compiled restart
set: continue, retry, skip, use-value, and abort-operation. Arbitrary named
application restarts such as reopen-resource remain a future layer. A
recoverable condition carries source context and typed values to the
controller when program policy declines it. Emacs can then open a nested break
session showing the condition, stack, locals, and available restarts.

While stopped, the user may inspect values, redefine compatible functions, and
choose a restart. Retrying then runs from the explicit restart boundary and may
observe the new function implementation. Restarts are compiled control-flow
points; the runtime does not synthesize continuations from arbitrary native
frames.

Language conditions, validation failures, and expected I/O failures may be
recoverable. Memory corruption, illegal instructions, and segmentation faults
are not. In standalone mode such a fault terminates the disposable worker while
the controller preserves diagnostics and source history. In attached mode it
may terminate the application host, which should be supervised when crash
recovery matters.

### Session checkpoints

Standalone and Olive-attached REPL workers support named, in-memory
checkpoints of mutable persistent `defvar` cells:

```json
{"id":"save-1","op":"checkpoint","name":"before-experiment"}
{"id":"list-1","op":"checkpoints"}
{"id":"restore-1","op":"checkpoint-restore","name":"before-experiment"}
{"id":"drop-1","op":"checkpoint-drop","name":"before-experiment"}
```

The compiler emits a typed snapshot/restore codec beside every supported
persistent mutable cell. Capture clones managed values instead of retaining
aliases to the live string, array, map, `Data`, or aggregate. Restore validates
the complete captured set before changing any cell. If a captured binding has
disappeared or its type/layout signature changed, the operation fails
atomically and reports the incompatible binding. Compatible redefinitions
continue to use the checkpoint.

Checkpoints contain mutable `defvar` state, not immutable `def` values,
procedures, recent results, native handles, borrowed views, threads, sockets,
or arbitrary foreign memory. Bindings created after capture remain unchanged.
A checkpoint is local to one native worker and disappears on reset, crash, or
session close. Replacing or dropping a named checkpoint releases its
worker-owned snapshot shells; backing allocations for managed snapshots may be
retained until worker exit, which is an intentional REPL lifetime tradeoff.
An attached checkpoint belongs only to the ad hoc REPL worker inside the
application. It neither captures nor restores Olive's application-owned
`Reload_State`. It survives a compatible Olive module reload because the
attached worker survives, and is cleared by attached `reset`.

The `session-state-checkpoints` capability advertises this behavior. The
operations are part of the generic JSONL protocol so terminal, Emacs, and
future clients share the same mechanism.

## Attaching to Olive

The first attached-console slice is implemented. Set `KVIST_REPL_ENDPOINT` to
an application-private directory before starting an Olive host, then connect:

```sh
KVIST_REPL_ENDPOINT=.olive/repl kvist run app.kvist --reload
kvist repl --attach .olive/repl --protocol jsonl
kvist repl app.kvist --attach .olive/repl --protocol jsonl
```

Olive creates the endpoint and processes its mailbox only when application
code calls `reload.checkpoint!`. Capability handlers therefore execute
synchronously on the application thread at a boundary the program already
declared safe; no console listener thread races application state.

Applications register or refresh capabilities through
`reload.register-console-capability!`. Each capability has a stable name and
exact ABI string. The generic client protocol provides `attached-session`,
`capabilities`, `reload-status`, `invoke-capability`, `reload`, and `close`.
An invocation supplies `name`, `abi`, and `source`; Olive rejects an ABI
mismatch before calling application code. `reload` schedules a coherent Olive
module replacement at the same checkpoint. The request first emits
`reload-requested` for the old generation, remains open while Olive replaces
the module, then emits `reload-complete` and `complete` only after a newer
generation services a checkpoint and advertises its freshly registered
capabilities. A timeout or a checkpoint that does not advance the generation
is a failed reload, never a false success.

The initial transport is a local atomic filesystem mailbox rather than a
network listener. It is deliberately application-private, single-host, and
development-only. Request ids use a bounded path-safe alphabet, the filename
identity must match the decoded request identity and protocol version, request
payloads are bounded, and a client cannot reuse an id while any request,
temporary, or response file with that id exists. First activation removes
stale mailbox artifacts while preserving unrelated endpoint files; repeated
activation of the same live endpoint does not discard in-flight work.
Authentication, remote transport, endpoint permission enforcement, and
multiple concurrent clients remain later hardening work.

Attached session-local native generations are now implemented when the client
supplies a context file. The controller compiles through the same compiler
session used by the standalone REPL, then asks Olive to load and execute the
resulting DLL at `reload.checkpoint!`. Olive owns a separate append-only
`kvist_repl.Worker` inside the application process, so later generations reuse
typed function slots, mutable cells, imports, macros, and recent-result
storage without replaying earlier forms. Application generations and attached
REPL generations are distinct counters.

The final value of an ordinary expression is returned through the native host
ABI and becomes the normal JSONL `output` event. A root `inspect` request uses
the same path and returns the rendered live value, inferred native type, exact
ABI, structured schema, and an opaque retained handle. Scalar and nominal
aggregate inspection therefore work unchanged in generic clients and Emacs
while attached. Inspection advances the attached generation but does not
rotate `*1`/`*2`/`*3` or commit definitions. Later `inspect` requests can use
the handle to select retained struct fields, sequence elements, or typed map
keys without re-evaluating the parent expression. Bounded initial collection
entries and `inspect-page` use the same retained snapshot. Inspection
rendering travels through the native host ABI rather than leaking onto
application stdout.

Compiler-routed output from evaluated `println` calls crosses the native host
ABI as request-scoped `output` events. Each call is delivered in execution
order, before the separate final-value event, and works inside retained
functions as well as the submitted top-level form. The application process is
not globally redirected: its own logging, foreign procedures that write
directly to a file descriptor, and raw Odin output remain on application
stdout or stderr. This keeps unrelated application traffic out of the generic
client protocol while making ordinary evaluated language output available to
terminal, Emacs, and other clients.

Attached evaluation also supports the generic `pause_before` safe point. The
original evaluation request publishes a `paused` event while remaining active
on the application checkpoint thread. During that pause, clients may request
the source-mapped frame with `debug-frame` and resume with `debug-continue`;
after resumption, the original request emits its normal generation, output,
and completion events. Olive services these control requests re-entrantly
through the same local mailbox—there is still no listener thread racing
application state.

`debug-abort` uses that same re-entrant control path. It cooperatively unwinds
the submitted evaluation on the checkpoint thread, runs its normal `defer`
cleanup, and leaves the surrounding application and attached worker resident.
The original request completes as aborted rather than publishing a result.

An explicit `debug.break` inside a retained function also stops the attached
evaluation. The pause resolves the function definition's retained source frame
rather than pretending the call site owns the function body. Compiler-described
scalar and nominal local snapshots cross the mailbox as rendered values and
are attached to their exact native types and ownership metadata. Generic
`debug-step`, `debug-step-over`, and `debug-step-out` requests arm the same
depth-aware native safe-point machinery as the standalone worker; the original
evaluation may consequently publish multiple paused responses before its final
completion.

Dynamic-array and map locals additionally publish editor-neutral collection
descriptors. A bounded `debug-page` request invokes the retained native page
callback while the application remains paused, returning deterministic array
indexes or map entries without copying the whole collection or re-evaluating
the function. Nested struct fields, fixed-array entries, and the compiler's
bounded initial set of dynamic-array and map entries publish their pageable
children in the same frame.

Paging a collection can also discover nested dynamic-array or map children
beyond that initial set. Olive copies the page callback's small descriptor
context into pause-owned storage, returns the new descriptors in the
`debug-page` event, and keeps them in the active frame registry. A client can
therefore page `items` at index 23 and immediately page
`items[23].events`; subsequent `debug-frame` requests include the discovered
path. Acquisition is bounded by the requested parent page and neither copies
the full collection graph nor re-evaluates application code. All descriptors,
copied callback contexts, and rendered page values are released on
continuation. They are never valid beyond that pause.

`condition.signal` publishes its stable condition type, dynamic message,
EDN-rendered Data context, typed frame, and compiled restart set through the
same paused response. `debug-restart`
validates the advertised restart before resuming native code. Typed
`use-value` validates scalar input while remaining paused, then copies the
accepted value into worker-owned storage before the compiled frame consumes
it. `continue`, `retry`, `skip`, and `abort-operation` remain explicit
compiler-emitted control-flow boundaries; this does not introduce arbitrary
native unwinding or continuations.

An attached request with `trace:true` uses the same bounded, compiler-inserted
safe points as a standalone request. Olive publishes each timing sample as an
intermediate response on the still-active evaluation, and the generic
controller resolves its stable trace ID against both the pending generation
and retained definition generations. Clients therefore receive defining
Kvist source, logical depth, monotonic elapsed/inter-point timing, and a final
sorted hotspot summary while the native application continues toward the
ordinary result. `trace_limit` has the same default and maximum as standalone
tracing; reaching it stops capture rather than stopping application code.
Transport markers never enter application stdout. Opt-in `trace_values` uses
the same ownership-safe bounded renderers and independent value limit as the
standalone worker; values are paired with the retained frame's typed lexical
descriptors in the controller.

Attached `checkpoint`, `checkpoints`, `checkpoint-restore`, and
`checkpoint-drop` requests execute synchronously at an application checkpoint
against the in-process REPL worker. Capture and restore therefore cannot race
an attached evaluation or application-thread access to a REPL cell. They use
the same atomic signature validation, managed-value cloning, inventory events,
and generic JSONL operations as standalone sessions. Reset runs at a
checkpoint, unloads every attached REPL generation, clears its checkpoints,
typed slot/state and pending-condition registries, and clears the client
compiler session so the next successful submission is generation one.
The controller-owned `generations`, `bindings`, `versions`, and `results`
operations are shared with standalone sessions. They expose attached source,
source-map, DLL, ABI, dependency, stale-state, and recent-result metadata
without touching application memory; Emacs generation navigation therefore
works unchanged while attached.
Clients still cannot access arbitrary untyped host memory. Capability names
and ABI metadata remain the authority boundary for application-owned state.

Updating a running program has two coordinated paths:

- REPL generations add and redefine ad hoc session code through session slots.
- Olive rebuilds and swaps ordinary application modules while retaining
  compatible host-owned `Reload_State`.

Existing production call sites are direct native calls and are not redirected
by a REPL definition. A REPL `:reload` request asks the Olive workflow to
rebuild and replace application code, then reports the structured reload result
through the generic protocol.

Code that directly accesses application memory must execute in the application
process. Unlike the standalone worker, an attached evaluation can therefore
panic or crash the host. Attached eval is development-only, disabled unless the
host opts in, queued at safe points, and visibly distinguished by clients.
Deadlines may request cooperative cancellation, but forced interruption of
native attached code is not promised.

The first attached milestone is local development attachment. Authenticated
remote transport, authorization, auditing, production enablement, and
multi-user concurrency are later work and arbitrary eval remains off by
default.

## One-Shot Scratch Evaluation

`kvist eval` is the hermetic command-line form of the same architecture.
It is useful for scripts, CI, reproducible isolated checks, compiler tests, and
evaluations that deliberately must not observe session history.

The ordinary `kvist eval file.kvist FORMS` path starts an ephemeral
package-anchored session, submits one batch through the normal generation ABI,
prints the rendered output, and exits. `--no-print` suppresses result rendering
through that same path. The worker process provides deterministic cleanup and
native crashes cannot take down a persistent controller.

Artifact-oriented compatibility modes—`--check`, `--generated`, and
`--save`—still use the direct one-shot compiler because their contract is to
produce or validate an Odin/executable artifact rather than execute a session
request. They are compiler modes, not an alternate interactive evaluator.

Persistent REPL evaluation becomes the default editor workflow. `expand` and
`macroexpand` remain direct compiler-inspection commands and are now also
session-aware generic protocol requests.

## Hands-On Workflow Findings And Immediate Milestone

Hands-on Emacs testing on 2026-07-30 exposed the following requirements. These
are part of the canonical REPL workflow, not optional editor polish.

### Imported-package completion and calls

After an import such as:

```clojure
(import data "kvist:data")
```

typing `(data.` and requesting completion must offer every exported member of
that imported package, with signatures and documentation where available.
This must work from the live session environment as well as the unsaved buffer
overlay. Completion remains a generic CLI/session-tooling capability; Emacs
only presents the returned candidates.

Qualified imported-package calls must resolve before any compiler shortcut
that happens to use the same textual prefix. The current emitter intercepts
all `data.*` heads as a closed intrinsic namespace, which incorrectly produces
errors such as:

```text
unknown Data operation: data.from-int
unknown Data operation: data.from-string
data.empty-map expects one Data value
unknown Data operation: data.kind-keyword
```

The following ordinary package calls must compile and evaluate:

```clojure
(data.from-int 123)
(data.from-string "hello")
(data.empty-map)
(data.kind-keyword '{})
```

Compiler intrinsics must either use names that cannot collide with imported
packages or be selected only after normal package resolution proves that the
call denotes the intrinsic.

### Clojure-like editing behavior

Kvist mode is and must remain a thin mode derived from `clojure-mode`; it
should not independently recreate Lisp navigation, indentation, structural
editing, or comment behavior. Kvist-specific code should be limited to syntax
and tooling differences that Clojure mode cannot represent directly.

Kvist mode must preserve the editing behavior inherited from Clojure mode:

- `TAB` indents or realigns the current form using two-space Lisp indentation;
  after an explicit package prefix such as `arr.` it completes package members
  at point instead. The same completion and signature metadata is available at
  the prompt in the interactive REPL buffer. Typing the qualifier alone does
  not invoke tooling; TAB fetches once and continued typing filters locally.
- `RET` inserts a newline and automatically indents it.
- Forms nested inside `(comment ...)` receive the same indentation behavior.
- Completion remains conveniently available, but must not replace ordinary
  indentation on `TAB`. Context-sensitive indent-then-complete behavior is
  acceptable.

These are explicit Kvist-mode bindings rather than assumptions about a
particular installed `clojure-mode`: `TAB` invokes
`kvist-indent-or-complete`, which delegates ordinary input to mode indentation,
and `RET` invokes `newline-and-indent`.

### Runtime type and `Data` construction

Kvist provides a Clojure-familiar `(type expression)` operation. The previous
compile-time spelling is now `(typeid T)`, a low-risk canonical change because
the old spelling had only six real uses in three repository interop examples
and none in the official packages, Vev, or Kimen. The runtime operation:

- evaluates value operands exactly once; type-name operands are resolved at
  compile time;
- reports native scalar, collection, and nominal type names;
- reports concrete named-function signatures and `typeid` for type names;
- reports the runtime kind for a `Data` value;
- contextualizes bare collection literals as `Data`, so `(type {})` is `Map`;
- returns a comparable descriptor that renders as the familiar type name.

`(Data value)` is valid, consistently with the general `(T value)`
construction/conversion rule. It is identity for `Data`, lifts supported
native scalars, and contextually constructs `Data` collections. Unsupported
native-to-Data conversions must produce a precise conversion diagnostic.
Package constructors remain useful but must not be the only direct spelling.

### Evaluation commands

The Emacs package must expose and test both workflows:

- Evaluate the form at or immediately before point and insert its rendered
  result as a `;; => ...` comment immediately below it.
- Evaluate the current enclosing top-level evaluable form without requiring
  point to be on its final parenthesis.

`C-c C-i` is confirmed to provide form-result insertion. `C-c C-c` is already
intended to provide enclosing-form evaluation, so its present failure is a
behavior regression rather than missing design. Inside a `(comment ...)`
block, `C-c C-c` must evaluate the relevant contained form, not submit the
inert `comment` wrapper as a macro form and fail with
`expected single macro form value`. `C-c C-e` retains its useful
form-at-or-before-point behavior.

All form-selection and insertion behavior belongs in editor clients. The CLI
continues to accept source plus source coordinates through the generic
protocol.

### Latency measurement and optimization

Interactive latency remains a continuing architectural concern, but the first
measured optimization is implemented. The REPL fingerprints phase output and
retains exact native generations in-session. Once typed result history has
stabilized, an unchanged submission can skip both the Kvist frontend and Odin
build while still loading a distinct generation and executing it normally.
Dependency and imported-source metadata are validated before that fast path.

The generic protocol must report timings for at least:

- session/context preparation and frontend load/resolve;
- macro expansion, parsing, lowering, analysis, and emission;
- generated source size and unchanged support/package code reused;
- Odin checking/native compilation;
- linking and dynamic-library publication;
- worker loading, registration, initialization, and submitted-form execution;
- controller and client-observed end-to-end latency.

Establish cold and warm baselines for a scalar form, a call, a compatible
function redefinition, a declaration-only submission, a multi-form buffer, and
an attached running program. Record multiple samples and report median and
tail latency rather than a single favorable run.

Use those measurements to prioritize:

1. Keep compiler/session context, resolved packages, and package artifacts warm.
2. Stop regenerating unchanged runtime, adapter, and support source.
3. Cache native checking and compilation inputs by exact content and ABI.
4. Make declaration-only and same-signature replacement generations smaller.
5. Avoid redundant Odin checking before the compilation step when compilation
   already performs the same validation.
6. Reduce link/load/registration work where append-only generation semantics
   permit it.
7. Consider a short, opt-in editor submission coalescing window only after
   single-form latency is understood; it must not make deliberate interactive
   evaluation feel delayed.

Every optimization must preserve once-only execution, atomic multi-form
submission, crash isolation, typed history, live dispatch, source-mapped
diagnostics, and the editor-neutral protocol. Keep a reproducible benchmark
command and regression thresholds so latency does not silently drift back.

### Embedded Odin development

The REPL accepts Odin only through Kvist's explicit escape form. A submitted
`(odin "1 + 1")` is compiled as a native expression and prints `2`; multiline
procedural Odin can occupy a statement position inside a Kvist form:

```clojure
(do
  (odin "
    xs := []int{1, 2, 3}
    total := 0
    for x in xs {
        total += x
    }
  ")
  (odin "total"))
;; => 6
```

This is already useful as an Odin scratch environment hosted by the Kvist
REPL, but it is not yet a complete Odin REPL. An untyped escape is opaque to
Kvist's type analysis, so its result is printed without entering typed
`*1` history. A name or package-scope declaration introduced only inside one
native generation does not automatically become a persistent Kvist session
definition. Bare Odin input remains deliberately unsupported: the reader,
protocol, source identity, and editor workflow continue to be Kvist.

Investigate a fuller embedded-Odin layer after hands-on use establishes the
need. Candidate surface forms, not yet canonical syntax, are:

```clojure
(odin int "1 + 1")                    ; typed result retained in *1
(odin-decl "Native_Point :: struct { x, y: int }")
(odin-import native_math "core:math")
```

The design must answer more than how to splice text:

- validate a declared result type and use the normal result snapshot,
  rendering, inspection, and history machinery;
- retain raw declaration source in the compiler session and define how later
  generations resolve its newest version without invalidating old callers;
- fingerprint raw procedure and type ABIs, preserving the same signature and
  layout evolution guarantees as Kvist declarations;
- make persistent Odin imports package-scoped, explicit, and collision-safe;
- expose source-mapped Odin diagnostics without pretending arbitrary raw text
  has Kvist form structure;
- define what, if anything, makes a raw declaration visible to ordinary Kvist
  name resolution;
- preserve crash isolation and the rule that native faults are not resumable
  language conditions.

The attractive outcome is an Odin development environment with Kvist's
persistent native session, editor-neutral protocol, Emacs workflow, inspection,
debugging, live application attachment, and conditions machinery—not a second
parallel evaluator.

### Follow-up investigations

The implementation order below records the completed architecture in detail.
The practical follow-up queue is:

1. Continue hands-on Emacs and attached-program testing against real Kvist
   work, fixing workflow and semantic regressions before expanding the model.
2. Explore the typed-result and persistent-declaration portions of the
   embedded-Odin design above. Keep the initial experiment narrow and preserve
   explicit `(odin ...)` boundaries.
3. Add a generic client-level connect lifecycle when there is a concrete
   non-Olive endpoint workflow. `C-c C-s` is REPL start; `C-c M-c` remains
   debugger continue, and editor-neutral connection semantics belong in the
   CLI protocol rather than an Emacs-specific subprocess convention.
4. Continue latency work from the implemented exact frontend/native generation
   cache. Persistent incremental frontend state, smaller first-time
   generations, and reduced link/load work remain; exact repeated submissions
   already avoid frontend emission and Odin compilation.
5. Add pointer, foreign-view, opaque-resource, and declared-resource lifecycle
   adapters only for types with an explicit safe clone/retain/release contract.
   Extend live inspection and physical ownership tracking through those same
   declarations.
6. Extend the implemented dynamically scoped production handlers with richer
   application-defined restart names and resource recovery, while keeping
   recovery points explicit and native crashes fatal to the worker.
7. Consider richer trace allocation/ownership events, durable checkpoint
   codecs, authenticated remote attachment, and process-wide foreign output
   capture only when a concrete workload justifies their complexity.

The guided hands-on sequence includes a package-graph exercise at
`playground/repl-packages/dev/user.kvist`, using the recommended ordinary
development entry file:

- start one explicit REPL for the application entry package and call functions
  through several levels of transitive imports;
- give imported packages observable initializers and confirm dependency-order,
  once-per-worker initialization;
- submit the same import repeatedly and confirm that initialization does not
  run again;
- mutate imported package state, evaluate unrelated generations, and confirm
  that the state remains live;
- evaluate a declaration from an already loaded imported package and confirm
  that callers and direct forms see the new package-qualified live binding;
- save without evaluating and confirm that a fresh reset loads the edited file
  and initializes a fresh worker package;
- repeat the source-edit case while attached to a running program and confirm
  that Olive adopts it only through an explicit reload checkpoint;
- make one dependency fail during load and confirm that it is not recorded as
  initialized and that previously committed session state remains valid.

One-shot `kvist eval`, `expand`, and `macroexpand` remain useful for scripts,
CI, reproducible clean evaluation, and compiler inspection. The persistent
REPL supersedes scratch evaluation for ordinary interactive editor work but
does not make those commands obsolete.

## Implementation Order

1. Implemented foundation: build the disposable worker and controller, expose
   terminal and generic JSONL clients through `kvist repl`, and load
   append-only native generations without replay.
2. In progress: build the multi-version compiler session. Concrete procedures
   now use per-signature worker slots and generated call adapters; explicitly
   typed values and vars use eager versioned storage. Retainable aggregates and
   nominal type versions now work with layout-aware slots. Fused transform
   and iterator definitions persist as compile-time session declarations, and
   the generic protocol exposes exact ABI/version metadata, transitive
   dependency and stale-state inspection, atomic function refresh, and
   per-version retained definition source ranges for editor navigation.
   Managed `Data`, immutable
   dynamic arrays, native maps, package-once runtime state, logical drop,
   persistent imports, and persistent macros already share the native session
   lifecycle. Concrete
   declaration-containing batches are already atomic.
3. Full-language procedure declarations are implemented: defaults expand in
   callers, concrete procedures with directives or custom ABIs use versioned
   slots, and generic/`where` declarations persist as specialization
   templates. Nested native slices in results and explicitly typed persistent
   values now receive recursive worker-owned snapshots, and
   lifecycle/owner/allocation metadata is available to generic clients.
   Standalone safe-point interruption, execution deadlines for code that does
   not reach safe points, structured native-crash events, and separately
   attributed native stdout/stderr are implemented.
   Unsupported pointer, foreign-view, and opaque-resource retention is now
   diagnosed explicitly. Add opt-in lifecycle adapters for types that can
   safely clone, retain, or release such values.
   Session-aware completion, lookup,
   documentation, xref, and structured compiler diagnostics are implemented.
   Typed recent
   results,
   native maps, package-once initialization, drop, reset, and fresh worker
   recovery are implemented. Borrowable strings, `Data`, dynamic arrays,
   native maps, and managed aggregates now snapshot before form-local cleanup,
   including explicitly deferred form-local owners. Top-level native slices
   with retainable elements are promoted to independent worker-owned backing
   storage. Pointers, foreign views, opaque resources, and views whose elements
   cannot be cloned still require explicit lifecycle or retained-owner
   analysis.
4. The default `kvist eval` command is now a one-batch ephemeral client of the
   same worker, generation ABI, ownership snapshots, diagnostics, and rendering
   machinery. Artifact-producing `--check`, `--generated`, and `--save` modes
   remain direct compiler operations. The Emacs package uses persistent
   per-package protocol sessions, including asynchronous
   form/region/comment evaluation and true multi-form `eval-buffer`.
5. Bounded native element/map-entry pages, loaded-generation source-map
   discovery, debug-symbol builds, worker attachment metadata, replacement
   notifications, Kvist-aware breakpoint translation/registration, and a
   blocking pre-execution pause/continue, persistent in-definition safe points,
   typed frame descriptors, compiler-derived lexical local descriptors,
   ownership-safe rendered local snapshots, recursive compiler-backed nominal
   field, bounded fixed-array, bounded top-level dynamic-array and map path
   snapshots—including aggregate element/value templates—bounded nested
   collection roots, client-directed live top-level dynamic-array and map
   pages, compiler-described and runtime-indexed nested collection pages, an
   Emacs browser over the generic live-page protocol, pure typed scalar frame
   evaluation, and depth-aware source-level step-into/over/out over
   compiler-inserted form safe points are implemented. Dynamic-array and map
   pages also acquire nested dynamic-array and map descriptors beyond the eager
   parent window. Bounded non-blocking source/depth tracing, timing, hotspot
   summaries, lexical-value capture, logical allocation and ownership-history
   views, and exact shared-runtime checkpoint allocation counters are
   implemented. Generation-local managed allocation, free, live-byte, and peak
   counters and opaque live-block inventory are also implemented through the
   generation host ABI. Validated strings and sequence roots nested through
   compiler-known structs and arrays now publish physical ownership-transfer
   history. Managed `Data` graphs publish cycle-safe shared physical retention.
   Native maps publish their backing allocation and recursively adapt keys and
   values. Persistent bindings publish generation-qualified native ownership.
   Extend adapters through declared resources.
6. The opt-in Olive console endpoint, typed capability discovery/invocation,
   checkpoint-thread scheduling, generic `kvist repl --attach` client,
   cross-generation reload completion, and Emacs attached-session lifecycle,
   status, invocation, and reload presentation are implemented. Context-backed
   attached native generations now load in the application process and retain
   typed session definitions and final values; checkpoint-scheduled attached
   reset and controller-owned generation/binding/version/result inventory are
   implemented. Attached live inspection now returns scalar, nominal aggregate,
   dynamic-array, and map values with exact native ABI/schema metadata;
   retained struct fields, sequence elements, typed map entries, and bounded
   collection pages work without re-evaluation or perturbing recent-result
   history. Attached pre-execution pauses, source-mapped frame discovery, and
   explicit continuation now keep the original evaluation pending at the
   application checkpoint while generic control requests are served
   re-entrantly. Retained definition frames, rendered scalar/nominal locals,
   explicit nested breaks, and depth-aware step-into/over/out now share the
   standalone source-level model. Attached top-level dynamic-array and map
   locals expose bounded native pages through pause-scoped descriptors. Typed
   attached conditions and their
   advertised compiled `continue`, `use-value`, `retry`, `skip`, and
   `abort-operation` restarts are implemented. Attached bounded source/depth
   tracing streams retained-source timing events and a sorted hotspot summary
   without using application stdout, including bounded ownership-safe lexical
   value events. Attached nested struct/fixed-array roots and demand discovery
   from dynamic-array and map pages share the standalone pause-scoped paging
   model. Named snapshot/inventory/restore/drop operations now checkpoint
   attached mutable REPL cells independently of Olive-owned application state.
   Compiler-routed `println` output now streams as ordered, evaluation-scoped
   generic output events without redirecting application stdout. The mailbox
   now rejects unsafe/mismatched request identities, oversized payloads, and
   request-id collisions, and reclaims stale protocol artifacts on first
   activation. Add authenticated or remote transport and endpoint permission
   enforcement only with a concrete non-local workflow; add opt-in foreign
   stdout/stderr capture only if process-wide interception is required.
7. The typed explicit condition event, ownership-safe break view, generic
   restart discovery/invocation, dynamically scoped production handlers,
   `continue`, compiled core-scalar `use-value`,
   lexical retry/skip boundaries, recursively nested native break evaluation,
   explicit abort-operation boundaries, and Emacs recovery/value-entry UI are
   implemented. Named in-memory checkpoints for compiler-supported mutable
   session state are implemented. Add opt-in application codecs and durable
   checkpoint serialization only if concrete workflows require them.

Do not build an interpreted fallback to mask native compilation latency.
Measure cold start, warm one-form evaluation, warm buffer evaluation, and
reload latency after the native path works, then optimize incremental compiler
and Odin work using those measurements.

## Acceptance Tests

- A form with a side effect runs once; later submissions do not replay it.
- A multi-form batch with a compile error runs no forms. A valid batch runs in
  source order and produces correctly attributed results and output.
- Named values, mutable values, owned native collections, structs, resources,
  `Data`, macros, transforms, iterators, foreign imports, and Odin package calls
  persist and work across generations.
- `(data.` completion includes all exports of an imported `kvist:data`
  package, and qualified package calls are not captured by similarly named
  compiler intrinsics.
- `TAB`, newline indentation, form-result insertion, and current-form
  evaluation behave like their Clojure-mode counterparts, including inside
  `(comment ...)`.
- Runtime type queries and `(Data value)` construction follow the canonical
  surface chosen above and have compiler, protocol, and editor tests.
- Explicit `(odin "...")` expressions and statement bodies compile through the
  normal native REPL path while bare Odin prompt input remains rejected.
- Any future typed Odin result uses normal typed history and inspection; any
  persistent raw declaration obeys the same ABI/version safety rules as a
  native Kvist declaration.
- Cold and warm native-evaluation benchmarks attribute frontend, native
  compile, link, load, registration, and execution time separately.
- Borrowed values with provable owner chains retain or promote those owners.
  Unprovable borrow escapes fail with a source-mapped ownership diagnostic.
- Same-type values and same-signature functions redefine successfully; old
  session callers observe compatible named replacements.
- A signature-changing `foo` creates a new version for future callers while old
  callers continue using the old ABI. Stale/dependency queries identify old
  callers, and atomic refresh moves selected function closures to the newest
  version without replaying value initializers.
- A layout-changing type declaration leaves old values valid under their old
  nominal type. New values use the new layout, unsafe crossing is rejected,
  and an explicit migration function can construct a new value.
- `*1`, `*2`, and `*3` rotate across unlike native result types with snapshot
  behavior for previously compiled references.
- Repeated imports initialize a package once. Imports added by a later
  submission become available without reinitializing earlier packages.
- A failed compile or generation validation preserves the prior session. A
  worker crash or interrupt produces a structured event and no automatic
  replay. Reset releases the process arena.
- Protocol stdout is valid JSONL even when evaluated code writes arbitrary
  stdout/stderr. Concurrent requests are serialized and every event is
  attributable to a request and source origin.
- Terminal and Emacs clients pass the same protocol conformance fixtures.
  Emacs form, region, comment, and buffer evaluation share a per-package
  session and retain accurate next-error locations.
- Native breakpoints and instrumented form stepping map to Kvist source.
  Read-only paused-frame lookup sees valid typed locals; compound evaluation
  follows the same ownership restrictions. The inspector reports layouts,
  ownership, retained owners, and definition versions.
- A recoverable condition enters a break session, permits a compatible helper
  redefinition, and resumes only through an explicit restart. A segmentation
  fault terminates the standalone worker and is never reported as resumable.
- A named session checkpoint clones compiler-supported persistent mutable
  cells, restores managed values without aliasing later mutations, and rejects
  a type/layout mismatch before changing any captured cell.
- An attached session calls a typed host capability only at a checkpoint,
  rejects an ABI mismatch, retains host state across Olive reload, and observes
  the new application implementation after a REPL-triggered reload.
- An attached endpoint rejects unsafe ids, filename/body identity mismatches,
  oversized requests, and live id collisions without executing the request;
  first activation removes only protocol-owned stale files.
- `kvist eval` and persistent REPL evaluation use the same compiler,
  generation ABI, diagnostics, and result rendering; the former exits after
  one clean session.
