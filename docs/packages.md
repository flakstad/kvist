# Packages

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
- `kvist:data` - traversal and typed access for first-class quoted `Data`.
- `kvist:edn` - parse and render first-class `Data` as EDN text.
- `kvist:bit` - bitwise integer operations.
- `kvist:arr` - concrete array, slice, transform, and sorting helpers.
- `kvist:map` - map construction and update helpers.
- `kvist:set` - set operations over map-backed storage.
- `kvist:str` - string views, builders, transforms, and search helpers.
- `kvist:soa` - source macros around Odin struct-of-arrays storage.
- `kvist:parallel` - task and bounded parallel collection helpers.
- `kvist:test` - tests, assertions, fixtures, and table checks.
- `kvist:regex` - owned regular-expression compilation and matching helpers.

See [sequences.md](sequences.md), [parallel.md](parallel.md), and
[testing.md](testing.md) for the larger package surfaces.

## Odin Packages

Kvist can import Odin's `core:*` and `vendor:*` packages directly. This includes
the standard packages for operating-system access, networking, text, encodings,
cryptography, math, concurrency, and maintained bindings such as raylib, SDL,
Vulkan, miniaudio, curl, and Lua.

See [odin.md](odin.md) for the model and examples.

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
