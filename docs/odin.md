# Odin Interoperability

Kvist can use Odin packages directly. There is no wrapper layer:

```clojure
(import os "core:os")
(import time "core:time")
(import sha2 "core:crypto/sha2")
(import raylib "vendor:raylib")
```

Procedures, types, constants, enums, multiple return values, allocators, and
errors keep their Odin semantics. Kvist only changes the source syntax.

## Core Packages

Odin's `core` library gives Kvist programs a broad standard library:

- `core:os`, `core:path/filepath`, and `core:time` for files, processes, paths,
  and time;
- `core:strings`, `core:strconv`, `core:text/*`, and `core:unicode` for text;
- `core:encoding/*` for JSON, CSV, INI, XML, Base64, hex, UUIDs, and more;
- `core:container/*`, `core:slice`, and `core:sort` for concrete collections;
- `core:math`, `core:math/linalg`, and `core:math/rand` for numeric work;
- `core:thread`, `core:sync`, and `core:sync/chan` for concurrency;
- `core:crypto/*`, `core:compress/*`, and `core:image/*` for common formats and
  algorithms;
- `core:io`, `core:net`, `core:mem`, `core:reflect`, and `core:testing` for
  lower-level application work.

Browse the complete [Odin core library](https://pkg.odin-lang.org/core/).

## Vendor Packages

Odin also ships maintained bindings and libraries under `vendor:*`, including
raylib, SDL, GLFW, OpenGL, Vulkan, WebGPU, Box2D, miniaudio, curl, Lua, stb,
and CommonMark.

Browse the complete [Odin vendor library](https://pkg.odin-lang.org/vendor/).

## Calling Odin

Call imported procedures normally:

```clojure
(let [[data err] (os.read_entire_file path context.allocator)]
  (if (= err nil)
    (do
      (defer (delete data))
      (count data))
    0))
```

Use `(type ...)` for polymorphic Odin types when needed:

```clojure
(import queue "core:container/queue")

(let [q: (type queue.Queue int) {}]
  (let [err (queue.init (addr q))]
    (if (= err nil)
      (do
        (defer (queue.destroy (addr q)))
        (queue.push-back (addr q) 42)))))
```

Odin APIs keep their ownership contracts. Delete owned strings, slices, maps,
and containers; free owned pointers; do not delete borrowed views.

## Mixed Packages

Kvist and Odin files can live in the same package directory and refer to each
other. Use ordinary imports for other Odin packages. Use `foreign-import` for
native libraries and `(odin "...")` only when raw Odin syntax is necessary.

## Examples

The [interop examples](../examples/interop/) cover:

- files, paths, time, strings, parsing, and encodings;
- queues, slices, matrices, SIMD, threads, channels, and synchronization;
- cryptography;
- raylib and stb vendor packages;
- foreign imports and Odin directives.
