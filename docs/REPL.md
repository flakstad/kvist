# REPL and Live Development

The Kvist REPL evaluates ordinary Kvist in a persistent native session.
Definitions, values, imports, macros, package state, and the three most recent
results remain available between submissions. Static types, ownership rules,
and Odin interoperability are the same as in a compiled program.

## Start a Session

Build Kvist, then give the REPL a source file from the project you want to work
with:

```sh
odin build src/cli/kvist
./kvist repl examples/language/hello.kvist
```

The file establishes the package, imports, and symbols available to the
session. Larger applications commonly use a small `dev/user.kvist` file that
imports the code under development and defines development helpers.

```text
Kvist native REPL
Enter one expression per line; use :reset or :quit.
kvist=> (+ 1 1)
2
kvist=> (defn square [x: int] -> int (* x x))
kvist=> (square 11)
121
```

The terminal accepts one complete expression per line. Editor clients can send
balanced multi-line forms or a group of forms together.

## Work with a Session

Successful definitions are immediately available to later submissions.
Compatible redefinitions affect later calls:

```text
kvist=> (defn scale [x: int] -> int (* x 2))
kvist=> (scale 21)
42
kvist=> (defn scale [x: int] -> int (* x 3))
kvist=> (scale 21)
63
```

Value-producing forms rotate through `*1`, `*2`, and `*3`. Runtime forms run
once; previous submissions are not replayed to rebuild session state.

A failed compilation leaves earlier session state intact. A crash in submitted
native code restarts the worker and clears runtime state. Use `:reset` to clear
the session deliberately and `:quit` to stop it.

Some submissions take longer than others, particularly the first use of a
large imported project. Kvist accelerates common interactive work where it can
do so without changing language behavior and otherwise uses its normal native
compiler path. This choice should normally be invisible apart from latency.

For isolated evaluation that must not observe session history, use:

```sh
kvist eval file.kvist '(form)'
```

## Editors

The [Emacs client](../emacs/README.md) provides source-buffer evaluation,
completion, documentation, retained-value inspection, stepping, traces,
conditions, restarts, and project-scoped sessions.

Kvist also provides an experimental nREPL adapter for Calva, CIDER, and
Conjure:

```sh
./kvist nrepl examples/language/hello.kvist
```

Use a real application entry file or development context so the server knows
which package graph and source files belong to the session. See the
[nREPL editor guide](NREPL.md) for setup and current limitations.

Other editor clients can use the JSONL protocol:

```sh
./kvist repl examples/language/hello.kvist --protocol jsonl
```

## Experimental: Attach to a Reload-Enabled Application

The normal REPL runs code in its own worker, so it does not share the live
state of an already-running application. Applications built around
`kvist:reload` can instead expose a private local endpoint and service REPL
requests at explicit safe points:

```sh
KVIST_REPL_ENDPOINT=.kvist/repl kvist run app.kvist --reload
kvist repl app.kvist --attach .kvist/repl --protocol jsonl
```

The application must reach `reload.checkpoint!` regularly. At a checkpoint, an
attached editor can evaluate code inside the application process, inspect live
values, invoke capabilities registered by the application, or request a
reload. Olive uses this mechanism for integrated live development, but it is
not part of the ordinary standalone REPL workflow.

See the [reload step example](../examples/reload/reload_step_demo/) for the
application structure. Because attached evaluations run inside the host, a
panic or crash in submitted code can terminate the application.

## Expectations and Boundaries

- A clean `check`, `test`, or `run` remains the reproducible truth. REPL
  history is development state, not an implicit part of the program.
- Compatible redefinitions affect later session calls. Code already running
  continues with the definitions it started with.
- Pointer and opaque resource results are retained only when Kvist has a safe
  lifecycle for them.
- Loaded code and session allocations are reclaimed by `:reset` or when the
  session exits.

If a result differs from a clean run, or a submission appears unexpectedly
slow, `--execution native` is available as a diagnostic comparison. It is not
needed for normal REPL use.
