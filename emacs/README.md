# Kvist Emacs Support

This directory contains lightweight Emacs support for Kvist.

## Install

```elisp
(add-to-list 'load-path "/path/to/kvist/emacs")
(require 'kvist-mode)
(require 'kvist-eval)
```

`kvist-mode` derives from `clojure-mode`, associates `*.kvist` files with the
mode, adds Kvist-specific font-locking, and uses Clojure-like 2-space
indentation for Kvist source. `TAB` explicitly runs mode indentation and `RET`
inserts an indented newline, including inside `(comment ...)`.

It also registers an xref backend and completion-at-point function. `M-.`
jumps to definitions indexed by `kvist symbols`, including current-file
declarations, compiler-provided Kvist package members such as `arr.push!`, and
imported Odin package definitions such as `fmt.println`. Dot package access is
canonical, and editor completion emits `pkg.member` candidates. For Kvist
language forms, `M-.` jumps to the compiler implementation.
Completion includes Kvist forms, current-file declarations, imported package
members, and compiler-provided package members. When point is inside a
qualified package prefix such as `map.` or `fmt.`, completion is limited to
that package. Typing or completing a canonical Kvist package prefix such as
`arr.`, `str.`, `map.`, `set.`, or `soa.` automatically inserts the matching
top-level `(import ... "kvist:...")` form when it is missing.
Compiler-provided Kvist package members and built-in forms also show
signatures in completion annotations and in the doc buffer.

`C-c C-.`, `C-c d`, and `C-c C-d` show docs for the symbol at point without jumping. They use the
source file at point even when it is an imported package in a larger live REPL.
Kvist declaration docs come from a declaration docstring or contiguous `;` comments immediately
preceding a top-level declaration. Compiler-defined forms such as `if-let` and
`if-ok`, mutation forms such as `inc!`, and operators such as `+` have built-in
signatures and docs. Imported Odin docs come from contiguous `//`
or `/* ... */` comments immediately preceding the imported package definition.
Compiler-provided Kvist packages such as `arr`, `str`, `map`, `set`, `soa`,
and `matrix` also provide docs through the editor integration.

At the language level, `(doc symbol)` prints the declaration or built-in prose
and returns `nil`; quoting the symbol is accepted but is not required. Qualified
package members work as expected, for example `(doc arr.range)`.

`kvist-eval` maintains one native JSONL REPL process per application package
graph. Form, top-level, region, comment-body, and whole-buffer evaluation share
that session, so definitions, mutable values, package state, imports, macros,
and the typed `*1` history remain available between commands. Local files
reached through transitive Kvist imports discover that same application worker
automatically. `C-c C-z`, `C-c C-q`, and `C-c C-s` from those buffers switch
to, stop, or reuse it. Evaluation from an imported source buffer uses that
package's own locals, imports, macros, and stable qualified live bindings. A
redefinition therefore updates the imported package immediately without
creating a same-named binding in the entry package. The CLI protocol remains
editor-neutral; buffer routing, overlays, and process lifecycle live entirely
in this Emacs package.

Definition and whole-buffer evaluation favor interactive latency. Before
stepping through a definition's local values, evaluate it with pause or trace
enabled. Set `kvist-repl-defer-definition-debug-values` to nil if every
definition should be ready for stepping immediately.

For an application, prefer an ordinary `dev/user.kvist` as the explicit REPL
entry point. It can import the application graph and contain development-only
start/stop helpers, fixtures, and `(comment ...)` experiments. This is a
convention, not a manifest or special compiler file; a REPL can still start
from any Kvist source file.

`M-x kvist-repl-start` explicitly starts the package session and opens its
project-specific interactive REPL buffer. `C-c C-s` starts it, paired with
`C-c C-q` for quit, while `C-c C-z` starts or switches to that same buffer.
Enter complete forms directly at its `kvist=>` prompt;
multiline input uses ordinary Kvist/Clojure indentation, `RET` submits a
balanced input, and `M-p` / `M-n` browse input history. Prompt evaluation and
source-buffer evaluation use exactly the same native session. The interactive
prompt prints a result directly, as Clojure does—`2`, not `=> 2`. The `=>`
prefix is reserved for source overlays, minibuffer presentation, and inserted
`;; =>` comments. In the REPL buffer, `C-c M-o` clears the visible transcript
without restarting the session or losing definitions, state, history, or
unsubmitted input.

Opening or focusing a Kvist file never starts a REPL. Eldoc, completion, xref,
and documentation use the live session when one exists and otherwise use
file-context tooling. Start explicitly with `C-c C-s` before evaluation.
`kvist-repl-auto-start` may be customized to non-nil for a lazy-start workflow.
`M-x kvist-repl-restart` replaces the process and opens a fresh interface.
`M-x kvist-repl-stop` or CIDER-compatible `C-c C-q` stops the session and
closes its interface buffer; `C-c M-q` remains an alias. Killing the interface
buffer asks for confirmation and, when confirmed, stops the associated REPL.

Completion, Eldoc, documentation lookup, and xref use the same live session.
Each request includes the unsaved buffer as a read-only overlay, so newly
typed forms and previously evaluated declarations are both visible without
creating a native generation. If no eval integration is loaded, the major mode
retains the hermetic one-shot CLI tooling as an offline fallback.
At an explicit package prefix such as `arr.`, `TAB` completes immediately at
point in both source and interactive REPL buffers. Candidates carry their
function or macro signatures as standard Emacs completion annotations, so
Corfu, Company/CAPF, and other completion frontends can render the same metadata
in their normal UI. Other `TAB` use continues to perform Clojure-style
indentation and alignment. Typing `.` alone does not start completion: TAB
fetches the package members once, after which further typing filters that set
locally without additional tooling requests.

Kvist uses Corfu's popup when Corfu is active. Otherwise, when Company is
installed, explicit completion enables it locally if necessary and starts its
popup with a dedicated Kvist backend. This avoids Company's CAPF bridge cache,
where a passive empty result at `arr.` could mask the explicit TAB request until
another edit changed the buffer. A Company failure is reported without silently
switching to `*Completions*`; that buffer is used only when no popup frontend is
available.
Company's idle completion is disabled locally in Kvist buffers, keeping the
interaction strictly TAB-driven and avoiding a conflicting empty session after
typing `.`.

For a running reload-enabled application, `kvist-repl-attach` replaces the
current package's standalone client with `kvist repl --attach ENDPOINT`. Emacs can
discover the live generation and typed capabilities, invoke a selected
capability, evaluate ordinary forms and buffers as session-local native
generations inside the application, and request reload. Attached definitions
and mutable REPL cells persist between submissions. Final expression values
return to the usual Emacs presentation; explicit process output remains on the
application stdout. Reload stays pending until the replacement generation
reaches an application checkpoint, so the success message names the new
generation rather than merely the generation that accepted the request.
Application-specific handlers and native evaluations run synchronously at
`reload.checkpoint!` on the application thread. Olive uses this integration,
but it is not required for ordinary standalone REPL sessions.
`C-c M-r` resets either session kind; for an attached session it unloads the
ad hoc generations at the next checkpoint without restarting the application
or discarding its Olive-owned state.
`C-c M-g` uses the same controller inventory in both modes, so attached
generation source, source maps, and DLL artifacts remain directly navigable.
`C-c M-i` also works while attached for scalar, nominal aggregate, sequence,
and map values, including their native ABI and structured schema. Field,
index, typed map-entry, and bounded page navigation use retained snapshots in
the application process, just as they do in a standalone session.
`C-c M-e` can pause an attached evaluation before execution, highlight its
source-mapped frame, and resume it with `C-c M-c`. The application remains
stopped on its declared checkpoint thread until continuation; Olive services
the generic frame and continue requests through its local mailbox. Attached
`debug.break` inside retained functions now exposes the definition's original
source frame and typed scalar/nominal local snapshots. `C-c M-n`, `C-c M-o`,
and `C-c M-u` use the same generic step-into/over/out requests while attached.
Every pause adds a compact CIDER-style command prompt after the paused source
line. While paused, that source buffer temporarily accepts `n` for the next
safe point (including inside a called function), `o` to step over, `u` to step
out, `c` to continue, `e` to evaluate a paused expression, `f` to show the full
frame, `p` to browse a collection, and `q` to abort the active evaluation.
Abort cooperatively unwinds instrumented Kvist frames, runs normal `defer`
cleanup, and preserves the resident REPL or attached application state.
The prompt and temporary bindings disappear as soon as execution resumes.
After `*Kvist Debug Frame*`
has been opened once, every subsequent pause or step refreshes that detailed
buffer automatically; it remains an optional secondary view.
Dynamic-array and map locals expose the same bounded `debug-page` browser used
by standalone frames; pages are rendered from the native value while the
application is stopped. Typed attached conditions now open the same condition
buffer and advertise the same compiled recovery buttons as standalone frames.
Invalid `use-value` input leaves the application paused; accepted input,
`continue`, `retry`, `skip`, and `abort-operation` resume only through the
recovery selected by the generic protocol. `C-c M-t` also works while attached:
timing samples stream through the generic CLI, resolve to retained definition
source, optionally include bounded ownership-safe lexical values, and finish
with the same navigable hotspot summary. Nested collection paging also works
while attached: paging a parent can discover children beyond the initial
frame window, and the generic client adds them to the active browser without
re-evaluation. The existing `C-c k s`, `C-c k l`, `C-c k r`, and `C-c k d`
checkpoint commands also work unchanged while attached. They snapshot only
mutable ad hoc REPL cells in the application process, not Olive-owned
application state, and are cleared by attached reset.

Build, check, run, test, and cache commands remain hermetic CLI invocations.
Put the compiler on Emacs' `exec-path`, or customize `kvist-command`:

```elisp
(setq kvist-command "kvist")
```

When the CLI reports Kvist diagnostics, the result buffer uses
`compilation-mode`, so standard Emacs navigation such as `next-error` / `M-g n`
can jump back to the reported `.kvist` source location.
Live evaluations consume structured warning and error records from the generic
protocol and render them into that buffer; Emacs does not parse native compiler
output to recover source positions.

Default keys:

Read-only `*Kvist …*` presentation buffers use the usual `q` binding to close
their window. The interactive REPL is deliberately excluded because `q` is
ordinary source input. While execution is paused, `q` in the detailed debug
frame retains its stronger meaning: abort the evaluation instead of merely
hiding the active pause.

- `M-.`: go to definition
- `C-c C-.`: show docs for symbol at point
- `C-c d`: show docs for symbol at point
- `C-c C-e`: eval form at point inline
- `C-c C-p`: eval form at point in the result buffer
- `C-c C-i`: eval form at point and insert a `;; =>` comment
- `C-c C-c`: eval current top-level form inline
- `C-c C-r`: eval selected region in the result buffer
- `C-c C-x`: eval the enclosing `(comment ...)` body inline
- `C-c C-k`: eval the whole buffer
- `C-c C-b`: compile buffer and run `odin build` on generated Odin
- `C-c C-v`: compile buffer and run `odin check` on generated Odin
- `C-c C-a`: save buffer and run `kvist run` asynchronously
- `C-c C-m`: expand form at point into generated Odin
- `C-c M-m`: macroexpand form at point into Kvist
- `C-c g g`: explicitly show generated Odin for the form at point
- `C-c C-d`: show docs for symbol at point
- `C-c C-w`: eval form at point and save stdout to the Kvist cache
- `C-c C-l`: list saved Kvist cache values
- `C-c C-o`: open a saved Kvist cache value
- `C-c M-d`: remove a saved Kvist cache value
- `C-c C-s`: start the package REPL and open its interactive buffer
- `C-c C-z`: start or switch to the interactive package REPL
- `C-c M-o` in the REPL buffer: clear its transcript without restarting
- `C-c M-r`: reset the current package REPL
- `C-c C-q`: stop the current package REPL
- `C-c M-q`: stop the current package REPL (alias)
- `C-c M-i`: inspect the form's live value, native type, ABI, and generation;
  point on a call head selects the enclosing call
- `C-c M-g`: show loaded native generations and open their Odin, source-map,
  or library artifacts
- `C-c v v`: show every retained native version of the definition at point
- `C-c v d`: show its transitive dependents and whether they are stale
- `C-c v r`: atomically recompile its stale transitive dependents
- `C-c k s`: save a named checkpoint of persistent mutable REPL state
- `C-c k l`: list named REPL checkpoints
- `C-c k r`: restore a named REPL checkpoint
- `C-c k d`: drop a named REPL checkpoint
- `C-c a a`: attach this package's generic client to an Olive endpoint
- `C-c a s`: show attached generation and typed capabilities
- `C-c a i`: discover and invoke a typed application capability
- `C-c a r`: reload and wait for the replacement generation's checkpoint
- `C-c a q`: close the attached or standalone package session
- `C-c M-b`: attach the configured native debugger to the live REPL worker
- `C-c M-s`: set native breakpoints for the Kvist source line at point
- `C-c M-e`: evaluate the form at point with a safe pause before execution
- `C-c M-c`: continue the currently paused instrumented evaluation
- `C-c M-k`: interrupt a paused standalone worker and discard its runtime
  session state
- `C-c M-x`: choose a recovery option for the active condition
- `C-c M-n`: step into the next instrumented Kvist form
- `C-c M-o`: step over deeper Kvist calls
- `C-c M-u`: step out of the current Kvist call
- `C-c M-t`: evaluate the form and show its bounded execution trace
- `C-c M-f`: query and display the active typed debug frame
- `C-c M-p`: browse a live pageable collection in the active debug frame
- `C-c t t`: run the `t/deftest` at point
- `C-c t p`: run Kvist tests for the current package
- `C-c t a`: run all Kvist test packages in the current project
- `C-c r s`: start `kvist dev --reload` for the current file
- `C-c r w`: start `kvist dev --reload --watch` for the current file
- `C-c r r`: rebuild the current reloadable app via `--rebuild --json`
- `C-c r p`: show generated reload paths and commands

Use a prefix argument with eval commands to treat the form/region as statements
instead of printing the expression result.

`C-c C-k` sends every active top-level form as one atomic native generation.
It omits the package declaration, inert top-level `(comment ...)` forms, and
the application `main` definition. Success is reported as `=> VALUE` in the
minibuffer (`=> nil` for a definitions-only buffer); only warnings or errors
open the result buffer. A DLL-level `main` is an Odin entrypoint
that runs during loading, so updating the running application entrypoint
belongs to Olive reload or an explicit program restart. Ordinary functions,
including functions called by `main`, remain freely redefinable.

Interactive evaluation is asynchronous. Native compilation does not block the
editor, and results arrive in the usual inline, comment, or result-buffer
presentation. `expand` and `macroexpand` use the same live session, so they see
the current session macros and bindings without executing code.

`C-c M-b` asks the editor-neutral protocol for the current worker PID, epoch,
and debugger capabilities, then launches `kvist-native-debugger-command` in an
interactive comint buffer (`lldb -p %d` on macOS, `gdb -p %d` elsewhere).
Customize `kvist-native-debugger-launch-function` to hand the same metadata to
a DAP client or another Emacs debugger package without changing the CLI.

Evaluation requests preserve the submitted form's buffer path, line, and
column. After evaluating a definition, `C-c M-s` asks the generic protocol for
all live generated locations corresponding to the current Kvist line and sends
deduplicated breakpoint commands to the attached LLDB/GDB process. Customize
`kvist-native-breakpoint-function` to register those locations with DAP or
another debugger frontend.

`C-c M-e` compiles the selected form with a pre-execution safe point. When the
worker reaches it, Emacs highlights and visits the original Kvist line while
the evaluation remains pending. `C-c M-c` sends the active pause ID back
through the generic protocol, resumes native execution, and lets the original
result arrive normally. `C-c M-n` resumes and steps into the next
compiler-inserted Kvist body-form safe point, including the first form reached
inside a called REPL function. `C-c M-o` skips safe points in deeper calls,
while `C-c M-u` resumes until the current instrumented Kvist call returns. If
the evaluation finishes before a qualifying point, the step expires instead
of affecting a later submission.
`C-c M-k` is the explicit destructive escape hatch for a paused standalone
worker. It is disabled for attached applications; after interruption the next
evaluation starts a fresh worker and prior REPL values are not replayed.
Customize `kvist-repl-evaluation-timeout-ms` to apply the same worker boundary
automatically when standalone native execution exceeds a deadline, including
code that never reaches an instrumented safe point. The option is deliberately
not sent to attached applications.
Unexpected worker exits are presented separately from both operations using
the generic `native-crash` event and include the native exit code when the
platform reports one.
Standalone native stdout and stderr arrive as separate generic `output`
events; the Emacs client presents both without parsing process output.
Pointer or opaque-resource results without a declared retention lifecycle
remain one-shot values. The compiler reports `KVR001` at the submitted source
range rather than allowing Emacs to expose a dangling recent result.
Standalone and attached inspection events also expose exact native size and
alignment for generic inspector clients; no editor-side ABI guessing is
required. Nominal values identify the precise historical definition version
and source range matching their native layout. Generic handle-only inspection
can replay the cached root snapshot safely after a nominal type is redefined;
the editor never asks native code to reinterpret the old value.
The generic `allocations` request also exposes the session's current logical
binding, result, and inspection allocations with owners, lifecycles, and exact
known inspection sizes; this is CLI protocol data rather than Emacs-specific
state.
The matching `ownership-history` request exposes the session-local sequence of
acquisition, retention, supersession, drop, and recent-result eviction events.
Editors can visualize it, but the journal remains a generic CLI protocol
facility.
The generic `runtime-allocations` request reports exact live and cumulative
allocation counts and bytes for checkpoint snapshot blocks and for managed
allocation calls made through the allocator shared with loaded native
generations. It also reports managed peak bytes. The operation works for
standalone and attached sessions; custom allocators and foreign code that
bypass the generation context remain outside its stated scope.
`physical-allocations` exposes the corresponding live managed blocks using
stable opaque IDs, allocation generation, exact size, and alignment. It never
publishes native addresses and is another generic CLI facility shared by
standalone and attached clients.
For retained results, the same response includes validated physical transfer
history from the allocating generation to the exact `result:gN` identity.
Compiler-known structs, fixed arrays, slices, dynamic arrays, and their
elements are walked recursively to find string and sequence roots. Each
allocation also exposes a primary owner and a retained-owner chain. Managed
`Data` graphs use shared retention: the generic runtime walks nodes and their
text, item, and entry backing stores with cycle detection, then records the
result as an additional owner rather than taking responsibility away from the
allocating generation. Native result maps are enumerated through Odin's runtime
API: the runtime transfers the canonical map table and recursively handles
typed keys and values, including shared `Data`.
Persistent definitions use the same traversal and report owners such as
`binding:user_settings:g12`; the generation keeps superseded native storage
honest while old compiled callers remain live. Custom allocators and opaque
resources remain outside the adapter. Emacs only renders this editor-neutral
protocol state; it does not implement ownership logic.

`C-c M-t` evaluates the selected form normally while collecting up to
`kvist-trace-limit` compiler safe points and, when
`kvist-trace-capture-values` is non-nil, values at up to
`kvist-trace-value-limit` of them. This works in standalone and attached
sessions through the same editor-neutral events. `*Kvist Trace*` shows each
defining Kvist file, line, column, monotonic elapsed and inter-point time,
logical call depth, stable trace ID, and captured top-level lexical values in
`compilation-mode`, so source locations are directly navigable. Tracing does
not pause execution. Values are ownership-aware and bounded: compact scalars
are rendered, strings are capped, and aggregates use typed placeholders rather
than recursively walking native graphs. The same buffer begins with a
descending, source-navigable hotspot summary and distinguishes unattributed
startup or post-truncation time from intervals that can be charged honestly to
a safe point. It clearly reports control-flow and value truncation separately.

Import `kvist:debug` as `debug` before using `(debug.break)`. REPL definitions
may contain these statements. The safe points
remain embedded in their defining native generation and therefore report the
definition's source even when called much later. `C-c M-f` queries the active
frame without resuming execution and shows its pause ID, generation, phase,
source location, and the compiler's lexically visible local names, types,
mutability, ownership, and read-only rendered values. These are copied
snapshots; Emacs receives no native address and cannot mutate a borrowed local.
Visible nominal structs and fixed arrays show compiler-described paths beneath
the owner, including `cursor.line`, `[0]`, and `samples[1]`, with each path's
type and copied value. Expansion is bounded to 256 paths per local. Top-level
dynamic arrays show their element type, exact total, truncation state, and up
to 64 expanded paths. Aggregate elements include paths such as `[1].line`, and
the displayed capture limit reflects the smaller element count required to
stay within that path budget. Top-level maps with string, integer, or boolean
keys show their key/value types, exact total, truncation state, and a
deterministically ordered bounded entry window. Entry and aggregate-value
paths use Kvist syntax such as `scores["alice"]` and
`users["alice"].active`. Runtime collections nested inside any captured
aggregate are shown as bounded count roots rather than rendering their entire
contents; an enclosing aggregate with such children is displayed as
`<aggregate type=T>`.
The generic protocol also supports bounded `debug-page` requests against a
top-level dynamic array or deterministically ordered map while paused,
including entries beyond the eager frame window and collections reached
through compiler-described struct/fixed-array paths, captured dynamic-array
elements, or deterministically selected map values. `C-c M-p` selects any
pageable path exposed by the frame and opens `*Kvist Debug Page*`; use `n`,
`p`, and `g` for next, previous, and refresh. Collection names in
`*Kvist Debug Frame*` are clickable. When paging discovers a nested collection
outside the eager frame window, its path appears as a clickable entry in the
page buffer and can be opened immediately. The pager is only a client of the
generic protocol and adds no Emacs-specific behavior to the CLI.
`C-c M-v` prompts for an expression and presents its typed snapshot result
without resuming execution. Visible locals of any type can be read directly;
children can be read as `pair.left`, `state.cursor.line`, or
`state.samples[1]`, `values[2]`, or `scores["alice"]`, and pure `int`/`bool`
arithmetic, comparisons, boolean forms, and conditionals can use captured
scalar paths. Calls, mutation, uncaptured dynamic collection traversal, and
managed-value operations remain unavailable.

`C-c M-l` compiles and evaluates the form at point in the same native worker
while execution is paused. It can call live session functions and install
compatible redefinitions. Newly compiled direct calls and refreshed dependents
see the new version; existing compiled functions retain the call targets from
their generation. A nested evaluation may itself pause, after which continuing
it restores the outer pause. This command uses the generic
`debug-eval-native` request—there is no Emacs behavior in the CLI. It does not
provide lexical access to the suspended frame; use `C-c M-v` for copied local
and path values. The suspended outer submission must be expression-only.

Import `kvist:condition` as `condition` before using the condition forms. REPL
definitions may then contain `(condition.signal :kvist/condition "message")`. On reaching
one, Emacs highlights the source and opens `*Kvist Condition*` with the
condition type, message, visible copied locals, and recovery options advertised by the
generic CLI protocol. The foundation offers `continue`; compiled
`(condition.use-value! local "message")` boundaries additionally advertise a
typed `use-value` restart for mutable `int`, `bool`, `f32`, `f64`, and
`string` locals. Choose recovery with `C-c M-x`, `r` in the condition buffer,
or its clickable name. Emacs prompts for required values using the protocol's
`value_type`. Invalid values are rejected while the condition remains active.
String values preserve whitespace and may be empty. A successful replacement
is copied into worker-owned storage, assigned by generated code, and then the
original evaluation resumes. A lexical `(condition.restart-case ...)` around code
containing `condition.signal` also advertises `retry` and `skip`; the same
condition buffer invokes them without special editor logic. Retry re-enters
the region and skip resumes after it. Earlier mutations are not rolled back.
This is explicit safe-point control flow, not recovery from segmentation
faults or arbitrary native unwinding.

A lexical `(condition.operation ...)` instead advertises `abort-operation`.
Selecting it exits that operation, runs its scoped cleanup, and resumes after
the boundary. The Emacs condition buffer needs no special case: it displays
and invokes the recovery advertised by the generic protocol.

Domain conditions use
`(condition.signal :io/not-found "configuration file is missing")` (or a
string literal type). Emacs displays the stable protocol type directly; the
CLI advertises `typed-conditions`, and no editor-specific condition registry is
required.

`C-c M-i` evaluates the form as a typed probe and presents its rendered value,
native type, exact ABI, generation, and structured shape in `*Kvist Inspect*`.
When point is on a call's head, including a compound type head such as
`[dynamic]int` or `map[string]int`, it inspects the enclosing call rather than
submitting the procedure or type value alone.
The buffer displays all commands relevant to its current shape, including
click/`RET`, `i`, `b` for back, collection paging, and `q` to close.
It is the detailed REPL equivalent of asking what type a value has.
`(type value)` returns the Clojure-facing runtime descriptor, while
`(typeid T)` passes a compile-time Odin type.
`Data` probes and ordinary evaluation render as readable EDN (`{:a 123}`,
`[1 2]`, `123`) rather than exposing the backing Odin structure.
Struct/enum/union members and collection element, key, value, target, or
fixed-length metadata are shown directly. Struct fields are buttons: press
`RET` on one, or press `i` and choose a field, to inspect it from the retained
native snapshot. On arrays and slices, `i` prompts for an index. On maps it
prompts for a Kvist key expression, such as `"name"` or `42`. Collections show
at most `kvist-inspection-page-size` entries at once (20 by default); entry
labels are buttons, and `n`/`p` move through pages without re-evaluating the
parent expression. Child values receive their own handle for further descent.
Inspection does not rotate `*1`, `*2`, or `*3` and does not commit definitions.
Initial expressions can still have effects. Handles live until REPL reset,
worker loss, or session close.

The reload commands use the CLI's JSON surface:

```sh
kvist dev --reload file.kvist --json
kvist dev --reload file.kvist --watch --json
kvist dev --reload file.kvist --print-paths --json
kvist dev --reload file.kvist --rebuild --json
```

`C-c C-a` now runs the current file in its own per-file compilation buffer, so
long-running programs do not block Emacs and multiple runs can stay open at the
same time.

`C-c r s` starts the long-running resident reload shell in its own per-file
compilation buffer.
The session uses `--json`, so the reload host emits structured event lines with
the prefix `KVIST_RELOAD_EVENT<TAB>` while ordinary app stdout/stderr still
flows through the same buffer.
`C-c r w` starts the same resident reload shell with `--watch`, so saving
`.kvist` files under the adapter directory rebuilds the reloadable module
automatically.
`C-c r r` saves the current buffer and rebuilds only the generated reloadable
module. `C-c r p` shows the generated host/module paths and canonical reload
commands for the current file.

If the current file is ordinary production source and a nearby `reload.kvist`
adapter exists, the CLI resolves that adapter automatically for these reload
commands.

For reload-app sources, `C-c C-a` runs the production-style wrapper (`kvist run
file.kvist`), while `C-c r s` starts the resident reload session.

Saved eval values use the CLI cache:

```sh
kvist eval file.kvist FORM --save NAME
kvist cache list
kvist cache path NAME
kvist cache rm NAME
```
