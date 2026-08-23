# Conditions And Restarts

Kvist conditions separate detecting a problem from deciding recovery policy.
The code that detects a problem signals a stable condition and establishes the
restarts that are mechanically safe there. A dynamically enclosing handler may
choose one automatically; otherwise a connected REPL presents the same
condition and restarts for an interactive decision.

Conditions are not native exceptions. They do not recover segmentation faults,
Odin panics, corrupted memory, or arbitrary stack frames. Every resumable path
is explicit compiled control flow.

```clojure
(import condition "kvist:condition")
(import data "kvist:data")
```

## Conditions And Handlers

`condition.signal` takes a stable keyword or string kind, a dynamic message,
and optional dynamic `Data` context:

```clojure
(condition.signal :config/not-found "configuration file is missing")
(condition.signal "validation/out-of-range" "port must be positive")
(condition.signal
  :config/not-found
  (str "configuration file is missing: " path)
  {:path (data.from-string path)
   :profile (data.from-string profile)})
```

The kind is deliberately a literal: handlers and clients can dispatch on it
without parsing prose. The message and context are ordinary runtime
expressions. Omit context to send an empty Data map. Use `:kvist/condition`
when no more specific kind is appropriate.

A handler is an ordinary procedure from `condition.Condition` to
`condition.Decision`. Install one or more handlers dynamically with a map:

```clojure
(defn handle-missing [problem: condition.Condition]
  -> condition.Decision
  (do
    (println problem.kind problem.message)
    (println "path" (data.string (:path problem.data)))
    (condition.retry)))

(condition.with-handlers {:config/not-found handle-missing
                          :* log-condition}
  (start-application))
```

The handler applies through transitive calls on the current thread, including
calls into imported Kvist source packages. The nearest matching handler runs
first. Return `(condition.decline)` to let the next matching handler decide.
Use `:*` as the handler kind to observe every condition. An exact handler in
the same map is tried before its `:*` fallback; map entry order has no semantic
effect.

Handler bindings are removed by scoped cleanup on ordinary return, retry,
skip, and operation abort. The current handler stack is bounded to 64 entries
per thread. Handler procedures are non-capturing native procedures in this
first implementation. `problem.data` is valid for the synchronous handler
call; explicitly retain values that must outlive it.

If no programmatic handler accepts a condition, a native REPL presents it with
its frame and advertised restarts. In an ordinary ahead-of-time program, an
unhandled condition terminates with a diagnostic. Applications should install
a top-level handler when they require another production policy.

## Restarts

A handler may select only a restart advertised by the signalling boundary:

```clojure
(condition.continue)
(condition.retry)
(condition.skip)
(condition.abort-operation)
(condition.use-value "42")
```

Selecting an unknown or unavailable restart is a runtime error. This check
keeps policy code from inventing a control transfer that the signalling code
did not compile.

### Continue

Every explicit signal advertises `continue`. It resumes immediately after the
signal:

```clojure
(condition.signal :cache/stale "using stale cached data" {:age-ms age-data})
(serve-cached-value)
```

### Retry And Skip

`condition.restart-case` establishes lexical `retry` and `skip` targets:

```clojure
(condition.restart-case
  (do
    (inc! attempts)
    (condition.signal :service/not-ready "service is not ready")
    (perform-request)))
```

`retry` enters the region again at its first form. `skip` leaves the region and
continues after it. Retrying is not rollback: mutation, output, I/O, and other
effects from previous attempts remain visible.

The restart belongs where the condition is signalled. A caller's
`restart-case` does not make arbitrary code in a separately compiled callee
resumable. A lower-level operation that can safely retry should establish the
boundary itself; a higher-level dynamically scoped handler can then choose
that advertised restart.

### Use Value

`condition.use-value!` signals a condition around a visible mutable `int`,
`bool`, `f32`, `f64`, or `string` local:

```clojure
(defvar port: int configured-port)
(condition.use-value! port "replace invalid port")
(listen port)
```

It advertises `continue` and `use-value`. A programmatic handler returns
`(condition.use-value "8080")`; an interactive client prompts for the value.
The boundary validates and converts the textual payload before assigning the
local and resuming.

### Abort Operation

`condition.operation` establishes `abort-operation`:

```clojure
(condition.operation
  (let [stream (open-config) :defer]
    (condition.signal :io/unavailable "configuration unavailable")
    (apply-config stream)))
```

Aborting leaves the operation and resumes after it. Ordinary `defer`,
`errdefer`, owned-local cleanup, and handler cleanup run while leaving the
region.

## Choosing An Error Mechanism

- Return an optional or result value when the immediate caller naturally owns
  the decision.
- Signal a condition when policy belongs at a dynamically higher layer or an
  interactive operator may reasonably choose recovery.
- Establish a restart only for continuations the local implementation can
  perform safely.
- Treat native memory faults and violated invariants as fatal.

The runnable [conditions example](../examples/language/conditions.kvist) shows
a handler in one package retrying an operation implemented by another package,
plus typed `use-value` repair.
