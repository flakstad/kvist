# Kvist Packages

Kvist ships its language and runtime support as source packages. Installed
packages live directly under the Kvist root and use `kvist:*` imports:

```clojure
(import arr "kvist:arr")
(import test "kvist:test")
```

`core` is referred automatically. Use an explicit `kvist:core` import only to
disambiguate a package definition that shadows a core name.

Run `kvist root` to print the active package root. Resolution uses `KVIST_ROOT`
when set; otherwise it uses the installed `bin/kvist` layout or `src/kvist`
beside a source-built compiler. It never searches the current directory or an
importing repository for shipped packages.

## Shipped Language Packages

- `kvist:core` - auto-referred macros and basic helpers.
- `kvist:bit` - bitwise integer operations.
- `kvist:arr` - concrete array, slice, transform, and sorting helpers.
- `kvist:map` - map construction and update helpers.
- `kvist:set` - set operations over map-backed storage.
- `kvist:str` - string views, builders, transforms, and search helpers.
- `kvist:soa` - source macros around Odin struct-of-arrays storage.
- `kvist:parallel` - task and bounded parallel collection helpers.
- `kvist:test` - tests, assertions, fixtures, and table checks.
- `kvist:regex` - owned regular-expression compilation and matching helpers.

See [SEQUENCES.md](SEQUENCES.md), [PARALLEL.md](PARALLEL.md), and
[TESTING.md](TESTING.md) for the larger package surfaces.

## Shipped Development Support

- `kvist:reload` - checkpoints for resident reload hosts.
- `kvist:hot` - hot-reload module export macros.
- `kvist:live` - live module, command, and hook declarations.

The supporting Odin runtime is installed under `odin/olive_reload`. See
[LIVE-DEVELOPMENT.md](LIVE-DEVELOPMENT.md) for the workflow.

## Optional Official Packages

Official non-core packages are maintained as independent source repositories:

- [kvist-lang/io](https://github.com/kvist-lang/io)
- [kvist-lang/json](https://github.com/kvist-lang/json)
- [kvist-lang/cli](https://github.com/kvist-lang/cli)
- [kvist-lang/html](https://github.com/kvist-lang/html)
- [kvist-lang/http](https://github.com/kvist-lang/http)

Place dependencies in the application repository and import their folders
relative to the declaring Kvist file:

```clojure
(import json "deps/json")
(import http "deps/http")
```

The compiler does not fetch, register, or recognize these package names.
Copied directories, Git submodules, and other ways of populating `deps/` have
the same semantics because a dependency is simply a folder.

## Ownership

Helpers ending in `!` generally mutate existing storage. Helpers returning new
dynamic arrays, maps, sets, strings, or compiled regular expressions return
owned values; delete them explicitly, bind them with `:defer`, or return the
ownership. Slice and string-view helpers return borrowed views.
