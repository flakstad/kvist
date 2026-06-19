# Shipped Packages

Kvist ships source packages under `packages/`. Import them with `kvist:*`
paths:

```clojure
(import arr "kvist:arr")
(import http "kvist:http")
```

This is an index, not a full API reference. For exact signatures, read the
package source and runnable examples.

## Core

- `kvist:core` - auto-exposed core macros and helpers such as `when`, `cond`,
  `case`, threading, `count`, `get`, `slice`, `contains?`, guards, value update,
  `doc`, `nil?`, `tap>`, and `println`.

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
  size, TTY checks, exit, and print helpers.

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
