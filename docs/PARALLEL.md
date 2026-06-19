# Parallel Package

`kvist:parallel` wraps common `core:thread` and channel cleanup without adding
an async runtime, coroutine scheduler, or hidden worker system. It is a small
thread-backed helper package for explicit parallel work.

## Current Surface

```clojure
(import p "kvist:parallel")

(let [task (p.start worker input)]
  (p.result task))
```

`p.start` starts `worker` on another OS thread and returns a one-result task
handle. `p.result` blocks for the result and cleans up task-owned resources.

`p.start` supports:

- known named workers with fixed arity
- inline `fn` workers
- copied local captures for inline workers
- exactly one return value

Detached fire-and-forget work uses `p.detach`:

```clojure
(p.detach send-email user)
```

Detached workers must not return a value.

## Ordered Parallel Collection Helpers

`p.map` runs a one-argument worker across a collection, preserves input order,
and returns an owned `[dynamic]Out`:

```clojure
(let [scores (p.map score-user users)]
  (defer (delete scores))
  ...)
```

`p.for` uses the same bounded-worker shape for side-effecting work and returns
no collection:

```clojure
(p.for send-email users)
```

Use `p.map-with` or `p.for-with` to choose a worker count explicitly:

```clojure
(p.map-with {workers: 4} score-user users)
(p.for-with {workers: 4} send-email users)
```

The option must be a map literal with a `workers:` label. Other option names,
duplicate `workers:` labels, or a bare number are rejected during lowering.

## Worker Count

The default worker count is bounded. The helper keeps one core free by default,
caps automatic worker count at `16`, and never starts more workers than input
items.

Explicit worker counts are clamped to at least `1` and at most `len(xs)`.

## Current Limits

- `p.start` workers must be known named workers or inline `fn` literals
- `p.start` workers must return exactly one value
- `p.detach` workers must not return a value
- `p.map` currently accepts a known named one-argument worker or inline
  one-argument `fn`
- `p.map-with` accepts only `{workers: n}` options
- `p.for` currently accepts a known named one-argument worker or inline
  one-argument `fn` with no return value
- `p.for-with` accepts only `{workers: n}` options
- `p.result` is blocking and consumes the task handle
- there is no cancellation surface

## Runtime Model

This package is thread-backed, not async:

- work runs on OS threads
- result transport uses channels underneath
- `p.result` blocks
- `p.map` uses bounded helpers rather than one thread per item

Use it for coarse CPU work or for explicit thread-shaped concurrency where the
cleanup boilerplate would otherwise be repetitive.

## Examples

- [examples/packages/parallel.kvist](../examples/packages/parallel.kvist) -
  runnable package tour
- [examples/packages/parallel-measure.kvist](../examples/packages/parallel-measure.kvist) -
  small measurement harness for task overhead and CPU-bound work
