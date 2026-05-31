# Reload Run Demo

This demo shows the first implemented `:run` reload mode: the app owns its
own runtime loop, and hot reload happens through one explicit checkpoint at the
runtime boundary.

Source:

- `main.kvist`

Canonical import:

```clojure
(import reload "kvist:reload")
```

Run the reloadable app:

```sh
./build/kvist dev --reload examples/reload_run_demo/main.kvist
```

Rebuild only the reloadable module after editing the app source:

```sh
./build/kvist dev --reload examples/reload_run_demo/main.kvist --rebuild
```

Run the same source without the resident reload shell:

```sh
./build/kvist run --reload examples/reload_run_demo/main.kvist
```

Check or build that production-style wrapper:

```sh
./build/kvist check --reload examples/reload_run_demo/main.kvist
./build/kvist build --reload examples/reload_run_demo/main.kvist
```

Current shape of the source contract:

- one top-level `(defstate Name {fields...} {metadata...})`
- fields map first, reload-lifetime/config map second
- required metadata for this mode: `:run`
- optional metadata: `:init`, `:on-load`, `:on-unload`, `:version`
- the `run` function takes the durable state plus `(ptr reload/Run_Host)`
- `reload/checkpoint!` is called at one explicit runtime boundary, and when it
  returns true the `run` function should return so the resident shell can
  perform the actual reload safely

In the non-dev `run/check/build --reload` path there is no resident reloader,
so `reload/checkpoint!` simply returns `false` and the `run` loop behaves like
an ordinary production loop.

This is the first general non-`:step` host shape. The user source stays pure
Kvist, while the generated host/module wrappers and the reload runtime remain
Odin implementation details.
