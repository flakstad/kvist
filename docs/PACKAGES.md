# Shipped Packages

Kvist ships source packages under `packages/`. Import them with `kvist:*`
paths:

```clojure
(import arr "kvist:arr")
(import http "kvist:http")
```

Installed tools resolve these packages without depending on cwd. Set
`KVIST_PACKAGES_DIR` to a packages directory, or `KVIST_HOME` to a Kvist install
root containing `packages/`, when packaging Kvist outside the source checkout.

This is an index, not a full API reference. For exact signatures, read the
package source and runnable examples.

## Start With Examples

- [examples/collections/package-tour.kvist](../examples/collections/package-tour.kvist) -
  `arr`, `map`, `set`, and `str` together with `:defer` cleanup.
- [examples/collections/sequences.kvist](../examples/collections/sequences.kvist) -
  array helpers over structs, grouping, sorting, and lookup.
- [examples/collections/transforms.kvist](../examples/collections/transforms.kvist) -
  `deftransform`, `into`, and `transduce`.
- [examples/collections/log-source.kvist](../examples/collections/log-source.kvist) -
  `defiter` with `for`, `into`, `transduce`, and cleanup.

## Ownership Rules

- Helpers ending in `!` mutate an existing value and do not return a new owned
  collection.
- Helpers that build dynamic arrays, maps, sets, or strings return owned values;
  bind them with `:defer`, delete them manually, or return ownership.
- Slice helpers such as `arr.slice`, `arr.take`, `arr.drop`, and `str.slice`
  return borrowed views.
- `arr.group-by` returns an owned map whose values are owned dynamic arrays;
  delete each group before deleting the map.

## Core

- `kvist:core` - auto-exposed core macros and helpers such as `when`, `cond`,
  `case`, threading, `count`, `get`, `slice`, `contains?`, guards, value update,
  `doc`, `nil?`, `tap>`, and `println`.
- `kvist:bit` - bitwise integer operators such as `and`, `or`, `xor`,
  `shift-left`, `shift-right`, `test`, `set`, `clear`, and `flip`.

## Collections And Text

- `kvist:arr` - dynamic-array, slice, indexing, mapping, filtering, reducing,
  grouping, sorting, partitioning, and in-place array helpers.
- `kvist:map` - map constructors, lookup, merge, association, dissociation,
  keys, values, and zip helpers.
- `kvist:set` - set constructors and set operations over Kvist's
  `map[T]struct{}` representation.
- `kvist:str` - string count, indexing, slicing, split, join, replace, trim,
  prefix/suffix checks, case conversion, and search helpers.

See [SEQUENCES.md](SEQUENCES.md) for collection ownership and helper behavior.

## IO And Data

- `kvist:io` - small read/write wrappers around Odin file IO.
- `kvist:json` - JSON read/write helpers built on Odin
  `core:encoding/json`.
- `kvist:cli` - command-line flags, options, environment variables, terminal
  size, TTY checks, temp directories, process execution, env overlays, exit,
  and print helpers.

## Web

- `kvist:html` - HTML rendering macros and runtime renderer helpers.
- `kvist:http` - HTTP server/router helpers over `kvist_vendor:http`.
- `kvist:http/client` - HTTP client request helpers.
- `kvist:http/session` - cookie session and CSRF planning helpers.
- `kvist:http/sse` - server-sent events stream helpers.
- `kvist:http/datastar` - Datastar SSE patch helpers.

See [HTML.md](HTML.md) and [HTTP.md](HTTP.md) for the friendly tour.

## Testing And Concurrency

- `kvist:test` - test declarations, assertions, fixtures, and nested test
  context helpers. See [TESTING.md](TESTING.md).
- `kvist:parallel` - task start/result/detach and bounded parallel map/for
  helpers. See [PARALLEL.md](PARALLEL.md).

## Compile-Time And Runtime Support

- `kvist:soa` - struct-of-arrays compile-time helpers around Odin `#soa`
  storage.
- `kvist:reload` - checkpoint helper for resident reload hosts.
- `kvist:hot` - hot-reload module export macro.
- `kvist:live` - live module, command, and hook declaration macros.

Live and reload workflows are covered in [LIVE-DEVELOPMENT.md](LIVE-DEVELOPMENT.md).
