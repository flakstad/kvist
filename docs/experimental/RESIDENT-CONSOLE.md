# Experimental: Resident Console

A future Kvist console should be a resident command console, not a classic
language REPL.

Kvist source is compiled, typed, ownership-aware, and lowered through Odin. A
traditional REPL that evaluates arbitrary forms into one mutable global language
runtime would work against that model. The useful version is a console attached
to a running development host:

- the host process owns durable/native state
- reload swaps compiled code at explicit checkpoints
- live modules provide command-shaped runtime behavior
- console commands usually dispatch to prepared functions
- optional ad hoc eval runs only through stable host capabilities or known app
  hooks

This gives REPL-like feedback without pretending Kvist has a hidden dynamic
runtime, garbage collector, or arbitrary live memory mutation model.

## Relation To Existing Work

Kvist already has three nearby pieces:

- `kvist eval file.kvist FORM` compiles and runs one scratch form in a file
  context.
- resident reload keeps a native host process alive and swaps compiled code at
  explicit safe boundaries.
- `Kvist/Live` loads semantic command modules over a stable host capability API.

The resident console would combine those ideas:

- scratch-style one-command feedback
- resident-process continuity
- reload-style safe points
- live-style command boundaries and host capabilities

It should not replace `eval`, `expand`, `macroexpand`, or resident reload. It
should be a client of those workflows.

The default user experience should be command dispatch, not arbitrary
evaluation. Ad hoc eval is useful during development, but prepared functions are
the safer and more useful center of the design.

## Why It Could Be Useful

The console would be valuable when the interesting program state only exists
after startup:

- a database connection is open
- a server has route/session/cache state
- a simulation has world state
- a tool has loaded project indexes
- a long-running worker has queues, counters, and recent errors

Restarting just to inspect or trigger one operation is slow. Letting arbitrary
code mutate live state is unsafe. A resident console sits between those two
extremes.

## Use Cases

### Call Prepared Reporting Functions

```clojure
(system.health)
(db.stats)
(routes.stats)
(jobs.failed 20)
(cache.stats)
(errors.recent 20)
```

This is likely the main use case. Instead of building a dashboard for every
operational question, expose prepared reporting functions and call them from a
console attached to the running system.

The command runs in the current process, so it can inspect resident state that a
separate process cannot see.

### Run App-Owned Mutations

```clojure
(reset-cache!)
(seed-demo-data!)
(compact-indexes!)
(flush-events!)
```

These should call ordinary app-defined functions. The console does not need a
general mutation language if the app exposes the operations it wants to allow.

### Query Domain State

For a database-backed app:

```clojure
(vev.q [:find ?e ?name
        :where
        [?e :user/name ?name]])

(vev.pull 42 [:user/name :user/email])

(vev.transact [[:db/add 1 :user/name "Ada"]])
```

For Kvist callers, Vev query, pull, and transaction input should be data forms,
not strings. Strings belong at C ABI, wire, or external text boundaries.

For a Vev-like project, this could become a native database workbench while the
same process owns the connection, indexes, recent transaction reports, and
application-level derived state.

### Run Ad Hoc Eval In Development

```clojure
(eval (db-stats state))
(eval (new-helper state))
```

`eval` is not required for prepared functions. It is an escape hatch for
development when compiling a one-off expression against the current command
context is useful. It should be easy to disable in production.

### Trigger Work At Safe Boundaries

```clojure
(tick-once!)
(process-next-job!)
(retry-failed!)
(send-test-event!)
```

This is useful for workers, simulations, games, servers, and import pipelines.
The command runs when the app reaches a checkpoint chosen by the app.

### Reload Then Probe

```clojure
(reload)
(new-report)
(new-debug-command!)
```

This matches the existing reload workflow: edit code freely, reload at a safe
point, then run a command against compatible state.

### Inspect Compiler Output

```clojure
(expand '(some-form))
(macroexpand '(my-dsl ...))
(doc transact)
(lookup transact)
```

These commands do not need resident app state, but having them in the same
console keeps the development loop tight.

## State Changes

Global state changes fall into three buckets.

### Allowed: Mutate Existing State Through Stable APIs

```clojure
(clear-cache!)
```

The state layout is unchanged. The app owns the function and can enforce
invariants.

### Allowed After Reload: New Code, Same Compatible State

```clojure
(reload)
(new-helper)
```

The app can call new compiled code as long as the state layout and ABI contract
remain compatible.

### Restart Or Migrate: State Layout Changed

If `App_State` gains a field, changes alignment, or changes ownership shape,
reload should reject the update or require an explicit migration path.

The console should make this visible instead of trying to patch native memory.

## Possible Command Model

A console command can be treated as a small compiled module:

```text
terminal console
  -> sends command text to dev host
  -> host writes or synthesizes a small Kvist command module
  -> module imports the app/shared API
  -> module exports one known entrypoint
  -> dev host compiles it
  -> resident app reaches a checkpoint
  -> host loads/runs the command
  -> result is encoded and printed back
```

The command entrypoint should receive a narrow context:

```text
command(ctx, app_state_or_capabilities) -> encoded_result
```

The context can expose:

- stdout/stderr or structured result output
- selected app capabilities
- command arguments
- cancellation/deadline
- logging
- access to command-local temporary allocation

The app should choose whether to expose a raw state pointer, an opaque handle,
or only named capabilities.

Most console commands should map to known exported functions:

```text
console form
  -> resolve command symbol
  -> validate arguments
  -> run prepared function at a checkpoint
  -> return structured result
```

An optional eval command can use the compiled-module path for one-off
expressions, but it should not be the default execution model.

## Possible User Surface

The CLI could grow in small steps:

```sh
kvist eval-string '(+ 1 2)'
kvist scratch
kvist console app.kvist
kvist dev --reload app.kvist --console
```

`eval-string` is the first useful primitive. `scratch` can be a simple loop over
that primitive. A resident console should come later, when the command boundary
and reload interaction are clear.

Inside a console, commands could be structural rather than magical:

```clojure
(SYMBOL ARG...)
(eval FORM)
(reload)
(expand FORM)
(macroexpand FORM)
(doc SYMBOL)
(quit)
```

The direct function-call shape invokes known exported commands. `eval` compiles
a one-off expression against the current command context. `reload` asks the
resident host to rebuild and swap code at the next checkpoint.

## Network And Production Use

A resident console could be exposed over a network transport, but that should be
treated as an admin/debug protocol, not a casual REPL port.

The useful production shape is closer to nREPL as a transport idea than nREPL as
an arbitrary eval model:

- authenticate strongly
- authorize command namespaces
- audit every command
- use timeouts and cancellation
- prefer read-only prepared reporting commands
- disable arbitrary eval by default
- return structured values as well as printed text

This makes the production use case clear:

```clojure
(system.health)
(jobs.failed 20)
(cache.stats)
(routes.stats)
(vev.stats)
(vev.q [:find ?e ?name
        :where
        [?e :user/name ?name]])
```

That can answer operational questions without building dashboards for every
report and without exposing arbitrary mutation as the default remote capability.

## Safety Rules

- Commands run only at explicit app checkpoints.
- The app chooses what state or capabilities commands can access.
- Prepared command functions are the default interface.
- Arbitrary eval is optional and should be disabled in production unless
  explicitly needed.
- Layout-incompatible state changes require restart or explicit migration.
- Command failures should not crash the host by default.
- The previous loaded code stays active when reload or command compilation
  fails.
- Results cross the console boundary as text or simple encoded values.

These rules match the current reload posture: keep the running process alive,
preserve host-owned state, and reject unsafe swaps.

## Vev As A Good Driver

Vev is a strong test case for this idea:

- it has meaningful resident state: connection, snapshots, indexes, storage
- it benefits from interactive query/transact/pull inspection
- it has a data-shaped command language already
- it needs native performance and explicit ownership
- it should remain usable through library and C ABI boundaries

A Vev console could start very small:

```clojure
(open "dev.vev")
(transact [[:db/add 1 :user/name "Ada"]])
(q [:find ?n
    :where
    [?e :user/name ?n]])
(pull 1 [:user/name])
(stats)
(reload)
```

That would test whether Kvist can provide REPL-like development ergonomics for
a real native data engine without weakening the compiled systems model.

Vev also has a simpler disk-inspection path: a separate CLI process can open the
same SQLite-backed database file and query committed data. That is better for
offline inspection, import/export, and scripts.

The resident console is useful when the question is about the running process:

- unflushed or in-memory state
- active connection options
- current snapshot and cache contents
- recently produced transaction reports
- app-level derived state
- locks, queues, sessions, workers, and recent errors

The two tools should coexist: Vev CLI for durable disk state, resident console
for live embedded process state.

## Non-Goals

- no classic global dynamic REPL runtime
- no arbitrary mutation of native memory
- no hidden object model
- no automatic migration of incompatible state layouts
- no requirement that production apps expose a console

## Likely Build Order

1. Add fileless `eval-string`.
2. Add an optional `scratch` loop over `eval-string` if shell usage is annoying.
3. Build a Vev or app-specific query/command shell.
4. Design resident console commands on top of reload/live once real use cases
   are clearer.

This keeps the first step useful without committing to the full console design.
