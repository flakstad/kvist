# Parallel Package

This note tracks the `kvist:parallel` package. The package is thread-shaped: it
wraps common `core:thread` plus `core:sync/chan` boilerplate without
introducing an async runtime, coroutine scheduler, or hidden work pool.

## Current Surface

```clojure
(import p "kvist:parallel")

(let [task (p.start worker input)]
  (p.result task))
```

`p.start` starts `worker` on another OS thread and returns a one-result task
handle. `p.result` blocks for the result and cleans up all task-owned
resources.

```clojure
(let [pricing (p.start fetch-pricing product-id)
      stock   (p.start fetch-stock product-id)]
  (Product_View {
    price: (p.result pricing)
    stock: (p.result stock)}))
```

`p.start` supports named workers with any fixed arity:

```clojure
(p.start load-config)
(p.start fetch-user user-id)
(p.start score-user user rules now)
```

It also supports inline `fn` workers:

```clojure
(let [task (p.start (fn [user: User] -> Score
                      (score-user rules user))
                    user)]
  (p.result task))
```

Inline start workers may capture local values. Captures are copied into the
generated task data.

Detached fire-and-forget work uses a separate form:

```clojure
(p.detach send-email user)
(p.detach (fn [user: User]
            (send-email-with-template template user))
          user)
```

`p.detach` returns no handle and generates a self-cleaning thread. Detached
workers are for side effects and must not return a value. Inline detach workers
may capture local values; captures are copied into the generated task data.

Ordered parallel map uses a bounded worker count:

```clojure
(let [scores (p.map score-user users)]
  (defer (delete scores))
  ...)
```

`p.map` currently accepts a known named one-argument worker or an inline `fn`
literal, plus a slice, fixed array, or dynamic array source. It preserves input
order and returns an owned `[dynamic]Out`. The generated helper defaults to:

```clojure
min(len(xs), max(1, os.get_processor_core_count() - 1), 16)
```

That keeps one core free by default, caps the automatic worker count at `16`,
and never starts more workers than input items.

Use `p.map-with` when the caller should choose the worker count:

```clojure
(let [scores (p.map-with {workers: 4} score-user users)]
  (defer (delete scores))
  ...)
```

Explicit worker counts are clamped to at least `1` and at most `len(xs)`, but
they are not capped by the default `16` worker limit.

Inline `p.map` workers may capture local values. Captures are copied into the
generated thread data for each worker:

```clojure
(let [rules (load-rules)
      scores (p.map (fn [user: User] -> Score
                      (score-user rules user))
                    users)]
  (defer (delete scores))
  ...)
```

Side-effecting parallel iteration uses `p.for`:

```clojure
(p.for send-email users)
(p.for-with {workers: 4}
  (fn [user: User]
    (send-email-with-template template user))
  users)
```

`p.for` and `p.for-with` use the same worker-count policy and inline-capture
lowering as `p.map`, but workers must not return a value. They are for
side-effecting work where allocating and discarding a result array would be the
wrong shape.

The current implementation is intentionally narrow:

- `p.start` workers must be known named workers or inline `fn` literals;
- `p.map` workers must be known named one-argument functions or inline
  one-argument `fn` literals;
- `p.for` workers must be known named or inline one-argument workers with no
  return value;
- `p.start` workers must return exactly one value;
- `p.detach` workers must be known named workers or inline `fn` literals with
  no return value;
- `p.result` is blocking and consumes the task handle;
- no cancellation or explicit worker-pool surface exists yet.

## Relationship To Odin Channels

Odin channels are the result transport for this abstraction:

1. `p.start` creates a buffered `chan.Chan(T)` with capacity `1`.
2. It generates a typed task-data struct for the worker and argument types.
3. It starts an OS thread with `thread.create_and_start_with_poly_data`.
4. The worker computes `(f x)` and sends the value to the channel.
5. `p.result` receives the value, joins/destroys the thread, frees task data,
   and destroys the channel.

The channel should not be hidden behind a fake runtime. It is the blocking
result transport. The task handle wraps it with the thread handle and allocated
task data so callers do not repeat cleanup boilerplate.

The raw Odin shape is:

```odin
result, err := chan.create(chan.Chan(int), 1, context.allocator)
task_thread := thread.create_and_start_with_poly_data(data, parallel_start_worker_square_int_int)
value, ok := chan.recv(result)
thread.join(task_thread)
thread.destroy(task_thread)
free(task.data)
chan.destroy(result)
```

The Kvist package should remove the repeated channel/thread cleanup shape:

```clojure
(let [task (p.start square 12)]
  (p.result task))
```

## Not Async/Await

`kvist:parallel` is not an async I/O surface:

- no event loop;
- no coroutine suspension points;
- no compiler-generated state machines;
- no function coloring;
- no cancellation propagation yet.

`start`, `result`, and `detach` are OS-thread-backed operations. `result` is
blocking.

## Measurements

`examples/packages/parallel-measure.kvist` is a small runnable measurement
harness for the current public surface:

```sh
odin run cmd/kvist -- run examples/packages/parallel-measure.kvist
```

It compares four CPU-bound calls run sequentially with the same four calls run
through `p.start` / `p.result`, `p.map`, and `p.for`, then measures tiny task
start/result overhead and detached launch overhead. The numbers are
machine-dependent and should be treated as smoke measurements, not as a formal
benchmark.

Sample output on a 10-core machine, using `Work-Rounds = 3000000`:

```text
cores 10
work_rounds 3000000
sequential_us 62599 checksum 1463214
parallel_us 15973.000000000002 checksum 1463214
speedup_x 3.9190508983910344
parallel_map_us 15952.999999999998 checksum 1463214
map_speedup_x 3.9239641446749833
parallel_for_us 15926 checksum 1463214
for_speedup_x 3.9306166017832473
joined_task_us 5305 tasks 200 avg_us 26.524999999999999 checksum 19900
detach_launch_us 2617 tasks 200 avg_us 13.085 count 200
```

The same run immediately before that produced a 3.74x CPU-bound speedup, about
28 us per tiny `start`/`result`, and about 14 us per detached launch. The useful
takeaway is the shape: `p.start` and `p.map` are worthwhile for coarse CPU work,
while tiny tasks are dominated by OS-thread launch and cleanup overhead. That is
why `p.map` is bounded and does not create one OS thread per item.

## Map Contract

`p.map` and `p.map-with` share the same generated helper shape. The important
contract is:

- preserve input order;
- return owned `[dynamic]Out`;
- clean up all task handles and channels;
- keep worker count bounded, with explicit control available through
  `{workers: n}`;
- keep future fallible-worker support aligned with ordinary Kvist/Odin
  multi-return values.

## Implementation Notes

A direct generic package prototype tried to implement:

```clojure
(p.start worker input)
(p.result task)
```

as ordinary Kvist polymorphic functions. The direct version attempted to pass
the worker proc value through thread task data. A raw Odin experiment with
heap-allocated task data and a stored proc field compiled but crashed, so
storing arbitrary proc values in cross-thread task data is not a safe first
design.

The implemented approach is compiler specialization:

- `p.start` expands to an internal `parallel-start` form;
- the compiler resolves the named worker function or inline `fn` literal;
- it generates a typed task-data struct and worker trampoline per worker shape;
- `p.result` expands to an internal `parallel-result` form that emits the common
  blocking receive and cleanup helper.
- `p.detach` expands to an internal `parallel-detach` form that emits a
  self-cleaning thread helper with no result channel. Inline `fn` workers emit a
  private callback proc, and captured values are copied into the generated task
  data.
- `p.map` expands to an internal `parallel-map` form that emits a bounded
  ordered map helper for the worker/input/output type. Inline `fn` workers emit
  a private callback proc, and captured values are copied into the generated
  worker thread data.
- `p.map-with` expands to an internal `parallel-map-with` form that passes an
  explicit worker count to the same helper.
- `p.for` expands to an internal `parallel-for` form that emits the same
  bounded thread-striding shape without an output array.
- `p.for-with` expands to an internal `parallel-for-with` form that passes an
  explicit worker count to the same `for` helper.

The important implementation choice is that `p.map` is not implemented as
one `p.start` per item. It generates a bounded helper directly so tiny per-item
work does not accidentally create thousands of OS threads.
