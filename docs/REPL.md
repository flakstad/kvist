# Native REPL and Live Console

Kvist has a persistent REPL without introducing an interpreter or a second,
dynamically typed version of the language. Each submission is ordinary Kvist:
it is read, macro-expanded, type checked, ownership checked, lowered to Odin,
compiled, loaded, and executed as native code.

## Start a Session

Build the compiler, then anchor the session to a Kvist source file:

```sh
odin build src/cli/kvist
./kvist repl examples/language/hello.kvist
```

The source file supplies the package graph, imports, compiler options, source
mapping, and symbol context for later forms.

```text
Kvist native REPL
Enter one expression per line; use :reset or :quit.
kvist=> (+ 1 1)
2
kvist=> (defn square [x: int] -> int (* x x))
kvist=> (square 11)
121
```

The terminal accepts one complete expression per line. Editor and protocol
clients may submit balanced multi-line forms or an atomic batch.

## Work with a Session

Successful definitions and supported typed values remain available to later
submissions. A compatible function redefinition updates later calls:

```text
kvist=> (defn scale [x: int] -> int (* x 2))
kvist=> (scale 21)
42
kvist=> (defn scale [x: int] -> int (* x 3))
kvist=> (scale 21)
63
```

The session retains concrete functions, native scalars and collections,
immutable `Data`, nominal declarations, imports, macros, transforms, iterators,
and package state where their native lifecycle is safe. Value-producing forms
rotate typed `*1`, `*2`, and `*3` results.

Runtime forms execute exactly once. A complete multi-form submission compiles
before any of its runtime forms run; if compilation fails, none of them run.
Earlier forms are never replayed to reconstruct the session.

The first successful generation makes context and imported package procedures
available to the resident worker. Later ordinary generations compile only the
native declarations reachable from the new submission. Inspection, tracing,
stepping, and native-debug requests retain their complete instrumented source.

Use `:reset` to replace the worker and clear definitions, values, imports, and
result history. Use `:quit` or end input to stop the session.

## Editors and the JSONL Protocol

The terminal is one client of an editor-neutral JSONL protocol:

```sh
./kvist repl examples/language/hello.kvist --protocol jsonl
```

Protocol clients can evaluate and expand code, complete symbols, show
documentation, inspect retained values and bindings, debug and trace native
execution, handle conditions and restarts, and manage session checkpoints.
Program output is emitted as structured events and does not corrupt protocol
framing.

The [Emacs client](../emacs/README.md) provides source-buffer evaluation,
completion, documentation, retained value inspection, source-level stepping,
execution traces, conditions and restarts, and project-scoped REPL sessions.

## Attach to a Running Application

An Olive application can expose an application-private local endpoint:

```sh
KVIST_REPL_ENDPOINT=.olive/repl kvist run app.kvist --reload
kvist repl app.kvist --attach .olive/repl --protocol jsonl
```

Attached requests run at application checkpoints declared with
`reload.checkpoint!`. This lets a client evaluate session code and invoke typed
application capabilities while the application stays alive. Olive remains
responsible for rebuilding and replacing ordinary application modules.

Attached evaluation runs native code inside the application process. It is a
development feature: a panic or crash in submitted code can terminate the
host, and clients cannot force-interrupt arbitrary native code safely.

## Session Boundaries

- Loaded native generations and session allocations are append-only until
  reset or process exit.
- Compatible redefinitions affect later session calls. Existing native
  generations retain the definitions and layouts they compiled against.
- Pointer, foreign-view, and opaque resource results may be rendered for one
  evaluation but are not retained unless the REPL has an explicit safe
  lifecycle for them.
- A standalone native crash clears runtime state. The controller reports the
  failure and starts a fresh worker for the next evaluation without replaying
  earlier submissions.
- A clean `check`, `test`, or `run` remains the reproducible truth. REPL history
  is development state, not an implicit part of the program.

For isolated evaluation that must not observe session history, use
`kvist eval CONTEXT FORMS`. See [Tooling](tooling.md) for the other compiler and
editor-oriented commands.
