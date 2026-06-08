# Live Commands Demo

This is the first real iterative `kvist_live` demo.

It runs one compiled Odin process, loads a tiny live module file, invokes a
live command once per second, and reloads the module when the live source files
change. The live module owns the command counter state, so the count survives
reloads.

Run it from the repo root:

```sh
./kvist run examples/reload.live_commands_demo/main.kvist
```

Then edit:

```text
examples/reload.live_commands_demo/live.commands.kvist
examples/reload.live_commands_demo/live.helpers.kvist
```

Try changing:

- `version:`
- `message`
- `hook-message`
- `counter-key`
- the `host.log` strings in `helpers.kvist`
- how the hook payload is emitted or read

Save the file and keep watching the running process.

What should happen:

- the process stays alive
- the module reloads in place
- the printed message changes
- the counter continues from the previous value instead of resetting
- the hook log line reflects payload values emitted from the command

To demonstrate source-defined migration specifically:

1. change `version:` from `"v1"` to `"v2"`
2. change `counter-key` from `"run-count"` to `"tick-count"`

The module's own `defn migrate []` should copy the old counter value to the new
state key during reload, so the count keeps increasing instead of restarting.
The demo migration handles both `run-count -> tick-count` and
`tick-count -> run-count` while you experiment.

Press `ctrl-c` to stop the demo.

## Current Scope

This demo now reads a narrow real-Kvist module subset rather than the earlier
line-based placeholder format. The current loader and evaluator understand:

- ordinary top-level macro expansion before live loading, including core
  macros, file-local `defmacro` forms, and shipped source-package macros such
  as `(import live "kvist:live")`
- `(live.module {...})` plus the shipped `live.defmodule` wrapper
- `(import "path")` for helper files, with the imported definitions merged into
  the root live module
- ordinary top-level `(defn name [params...] body...)`
- `(live.command name)` or `(live.command name {...})`, with optional inline body
- `(live.hook name)` or `(live.hook name {...})`, with optional inline body
- shipped `live.defcommand` / `live.defhook` wrappers for the common zero-arg
  entrypoint case
- top-level `def` or `defvar` literal bindings
- optional source-defined lifecycle helpers:
  - `defn init [] ...`
  - `defn migrate [] ...`
  - `defn shutdown [] ...`
- behavior forms including `let`, `if`, `when`, `state.get`, `state.set!`,
  `state.inc!`, `module.name`, `module.version`, `reload.from-version`,
  `reload.state-get`, `args.count`, `args.get`, `payload.count`,
  `payload.get`, `host.call`, variadic `hook.emit`, `+`, `=`, `str`, `cond`,
  direct symbol lookup from module bindings, and ordinary calls to top-level
  `defn` helpers

If a `live.command` or `live.hook` has no inline body, the loader will use a
same-named zero-argument top-level `defn`. Options maps are optional too.

If the module defines zero-argument top-level `defn init`, `defn migrate`, or
`defn shutdown`, the runtime will invoke them on load, reload migration, and
unload/reload respectively.

The demo host now uses the reusable live host helper surface rather than
open-coding directory signatures:

- `new_module_reloader(...)`
- `load_initial_module(...)`
- `reload_module_if_source_changed(...)`

It watches the `examples/reload/live_commands_demo/live/` directory for `.kvist` file
changes, so edits to imported helper files trigger reload too.

The demo command now emits hook payload values explicitly:

- the `tick` command emits the current counter and message
- the `after-command` hook reads those values with `payload.get`
- the resulting host log line shows the live command/hook boundary carrying
  real runtime data

It still does not evaluate arbitrary Kvist code. This step is about moving the
live path onto actual language syntax, macro expansion, and a small executable
shared subset.

The host source is now pure `.kvist`. The example imports `kvist_live` and a
small Odin-side helper package with ordinary import forms, and the example file
itself no longer contains raw Odin escape hatches.

See [../../docs/LIVE-SHARED-SUBSET.md](../../docs/LIVE-SHARED-SUBSET.md) for
the explicit current overlap the project is treating as the live.compiled
shared surface.
