# Live Commands Demo

This is the first real iterative `kvist_live` demo.

It runs one compiled Odin process, loads a tiny live module file, invokes a
live command once per second, and reloads the module when the file changes.
The live module owns the command counter state, so the count survives reloads.

Run it from the repo root:

```sh
odin run examples/live_commands_demo
```

Then edit:

```text
examples/live_commands_demo/live/commands.kvist
```

Try changing:

- `:version`
- `message`
- `hook-message`
- the `host.log` strings in the command or hook bodies

Save the file and keep watching the running process.

What should happen:

- the process stays alive
- the module reloads in place
- the printed message changes
- the counter continues from the previous value instead of resetting

Press `ctrl-c` to stop the demo.

## Current Scope

This demo now reads a narrow real-Kvist module subset rather than the earlier
line-based placeholder format. The current loader and evaluator understand:

- `(live/module {...})`
- ordinary top-level `(defn name [params...] body...)`
- `(live/command name)` or `(live/command name {...})`, with optional inline body
- `(live/hook name)` or `(live/hook name {...})`, with optional inline body
- top-level `def`, `defconst`, or `defvar` literal bindings
- behavior forms including `let`, `if`, `when`, `state/get`, `state/set!`,
  `state/inc!`, `module/name`, `module/version`, `host/call`, `hook/emit`,
  `+`, `=`, `str`, direct symbol lookup from module bindings, and ordinary
  calls to top-level `defn` helpers

If a `live/command` or `live/hook` has no inline body, the loader will use a
same-named zero-argument top-level `defn`. Options maps are optional too.

It still does not evaluate arbitrary Kvist code. This step is about moving the
live path onto actual language syntax and a small executable shared subset.
