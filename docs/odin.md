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

## Interactive Odin Development

The Kvist REPL can act as a typed development surface over Odin. Start it with
a normal Kvist context file:

```sh
./kvist repl examples/interop/repl-odin.kvist
```

For a small amount of Odin, place it inside a typed Kvist definition:

```clojure
(defn odin-sum-squares [limit: int] -> int
  (odin "
    total := 0
    for i in 0..<limit {
        total += i * i
    }
    return total
  "))
```

The Kvist signature is the durable boundary: the definition persists, can be
redefined, and can be called and inspected normally. The Odin body may also
call typed Kvist procedures by their generated Odin names.

For a program containing substantial Odin, keep it as ordinary source:

```text
project/
  dev/user.kvist
  native/
    engine.odin
    storage.odin
    types.odin
```

The development context imports the package directory and optionally adds thin
typed helpers:

```clojure
(package dev)
(import native "../native")

(defn run-engine [iterations: int] -> int
  (native.run iterations))
```

This allows the application to remain mostly Odin while Kvist supplies the
interactive development layer. A raw `(odin "...")` submitted by itself is a
single experiment; it does not add persistent top-level Odin declarations to
the session. Reusable declarations belong in a typed Kvist definition or an
`.odin` file, and a clean build remains the final program.

See the runnable [REPL/Odin example](../examples/interop/repl-odin.kvist),
including its [Odin-only support package](../examples/interop/repl-odin-support/support.odin).

## Mixed Packages

Kvist and Odin files can live in the same package directory and refer to each
other. Use ordinary imports for other Odin packages. Use `foreign-import` for
native libraries and `(odin "...")` only when raw Odin syntax is necessary.

## Examples

The [interop examples](../examples/interop/) cover:

- interactive typed boundaries around embedded and imported Odin;
- files, paths, time, strings, parsing, and encodings;
- queues, slices, matrices, SIMD, threads, channels, and synchronization;
- cryptography;
- raylib and stb vendor packages;
- foreign imports and Odin directives.
