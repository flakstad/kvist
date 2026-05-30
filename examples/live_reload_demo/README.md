# Live Reload Demo

This is the smallest self-contained `kvist_live` example.

It loads one module definition, invokes a command, reloads the module with a
new version and message, invokes the command again, and prints the preserved
state.

Run it from the repo root:

```sh
odin run examples/live_reload_demo
```

You should see:

- version `v1` print once
- version `v2` print once after reload
- a final line showing that the counter state survived the reload

This example is intentionally non-interactive. It demonstrates the core reload
and migration model without file watching or a long-running process.
