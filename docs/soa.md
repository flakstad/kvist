# Struct Of Arrays

Kvist exposes Odin's struct-of-arrays layout through `#soa` types and the
`kvist:soa` package. Each struct field is stored as a separate column.

```clojure
(import soa "kvist:soa")

(defstruct Particle {
  x: f32
  y: f32
  mass: f32
})

(let [particles (soa.make Particle 1024)]
  (defer (delete particles))
  (soa.push! (addr particles) (Particle {x: 1 y: 2 mass: 3}))
  (println particles.x[0]))
```

Use `#soa[N]T` for fixed storage and `#soa[dynamic]T` for dynamic storage.
`soa.make` creates the dynamic form with optional initial capacity.

## Storage

Dynamic buffers support:

```clojure
(soa.push! (addr particles) particle)
(soa.reserve! particles capacity)
(soa.resize! particles count)
(soa.clear! particles)
(soa.remove-ordered-at! particles index)
(soa.remove-unordered-at! particles index)
```

`soa.zip` creates a struct-of-arrays view over columns. `soa.unzip` returns its
columns.

## Column Operations

Columns are ordinary indexed arrays:

```clojure
(set! particles.mass[i] 10)
(soa.fill! particles .mass 1.0)
(soa.scale! particles .mass 0.5)
```

`soa.update!` updates several fields at one index. Each selected field is
available by name inside its update expression:

```clojure
(soa.update! particles i
  .x (+ x 1)
  .y (+ y 1))
```

The package also provides direct column loops:

```clojure
(soa.copy! particles .x .y)
(soa.add! particles .x .y)
(soa.sub! particles .x .y)
(soa.mul! particles .x .y)
(soa.axpy! particles .x factor .y)
(soa.clamp! particles .mass 0.0 10.0)
(soa.sum-into! total particles .mass)
(soa.dot-into! total particles .x .y)
(soa.norm2-into! total particles .x)
```

These macros expand to direct loops over the columns.

`soa.fields` and `soa.types` expose compile-time struct metadata for macros and
generated code.

See the [package example](../examples/packages/soa.kvist) and the
[visual simulations](../examples/visual/) for larger uses.
