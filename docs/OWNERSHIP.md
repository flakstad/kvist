# Ownership Rules

Kvist should teach ordinary Odin ownership. It should not hide allocation or
pretend that Odin has garbage collection.

The practical rule is:

- If a value owns dynamic storage, delete it when the current scope is done with
  it.
- If a proc returns an owned value, ownership transfers to the caller and the
  callee must not delete it before returning.
- If a value is a borrowed slice/view, do not delete it. Keep its backing value
  alive for as long as the view is used.
- Plain structs, enums, numbers, booleans, strings, fixed arrays, and ordinary
  slice views do not need deletion.

Kvist should not rely on hidden cleanup to make this work. The ownership model
stays explicit. The compiler may help with diagnostics, but user code should be
written as if ownership is the programmer's responsibility.

`tap>` prints and returns its value. It does not allocate an owned result by
itself, but ownership passes through it: `(tap> (arr/map f xs))` is still an owned
result and must be bound or returned. The same is true in threaded code:
`(->> xs (arr/map f) (tap> :mapped))` still returns an owned dynamic array.

## Delete These

These forms return owned values in normal Kvist code:

```clojure
(make [dynamic]int)
(make map[string]int)

(new [dynamic]int [1 2 3])
(new map[string]int {"one" 1 "two" 2})

(arr/map f xs)
(arr/filter pred xs)
(arr/remove pred xs)
(arr/take-nth n xs)
(arr/map-indexed f xs)
(arr/keep f xs)
(arr/mapcat f xs)
(concat xs ys)
(arr/into [dynamic]int xs)
(arr/interpose sep xs)
(arr/interleave xs ys)
(arr/reverse xs)
(arr/shuffle pick xs)
(arr/sort xs)
(arr/sort-by f xs)
(arr/sort-by :field xs)
(arr/partition n xs)
(arr/partition-all n xs)
(arr/partition-by f xs)
(arr/partition-by :field xs)
(map/zip keys vals)
(arr/index-by f xs)
(arr/index-by :field xs)
(arr/group-by f xs)
(arr/group-by :field xs)
(arr/count-by f xs)
(arr/count-by :field xs)
(arr/sum-by key-f value-f xs)
(arr/sum-by :key-field :value-field xs)
(arr/frequencies xs)
(map/keys m)
(map/vals m)
(arr/range end)
(arr/range start end)
(arr/range start end step)
(arr/repeat n x)
(arr/repeatedly n f)
(arr/iterate n f x)
(arr/cycle n xs)
(io/read path)
```

Use `defer delete` for local owned values:

```clojure
(let [active-users (arr/filter active? users)
      names (arr/map :name active-users)]
  (defer (delete active-users))
  (defer (delete names))
  ...)
```

For ordinary local scopes, Kvist also supports a binding-level `defer` marker:

```clojure
(let [active-users (arr/filter active? users) defer
      names (arr/map :name active-users) defer]
  ...)
```

This lowers to the same explicit `defer delete(...)` pattern. It is only a
local binding convenience; it does not create a hidden runtime cleanup model.
Defer-marked bindings cannot escape through the return boundary, including
direct return, wrapping them in returned structs, or passing them into returned
calls.

For `arr/partition`, `arr/partition-all`, and `arr/partition-by`, delete the outer dynamic
array. The chunks inside are borrowed slices and must not be deleted:

```clojure
(let [chunks (arr/partition 2 xs)]
  (defer (delete chunks))
  (arr/first (get chunks 0)))
```

`io/read` lowers to `os.read_entire_file(path, context.allocator)`. It returns
owned bytes plus an `os.Error`, so delete the bytes once the successful read is
no longer needed:

```clojure
(let [[data err] (io/read path)]
  (if (!= err nil)
    0
    (do
      (defer (delete data))
      (len data))))
```

If a proc returns the bytes from `io/read`, ownership transfers to the caller and
the callee must not delete them.

Data marshalling is explicit host interop, not Kvist core. For JSON, the shipped
`kvist:json` package provides `json/write` and `json/read-as`. `json/write`
marshals to owned bytes internally and deletes them after writing. `json/read-as`
may allocate strings, slices, dynamic arrays, or maps inside the destination
value; the caller owns those decoded allocations and must clean them up according
to the decoded type.

## Compiler Ownership Knowledge

The compiler should keep an internal list of **known owned producers**. This is
the source of truth for future diagnostics and examples. The list should stay
small and explicit rather than trying to infer ownership from arbitrary user
procedures.

That knowledge is for warnings first, not hidden cleanup behavior.

Near-term diagnostics should stay conservative:

- warn when a known owned result is produced and discarded;
- warn when a known owned result is bound locally and then clearly never
  deleted, returned, or transferred;
- warn when a local known-owned binding is overwritten before cleanup.

Current compiler warnings implement the first conservative slice of this:

- discarded owned constructor/allocation results such as `arr/empty`, `arr/dynamic`,
  `map/empty`, `map/of`, `set/empty`, `set/of`, owned `str/*` builders such as
  `str/join`, `str/replace`, `str/lower`, `str/upper`, and owned `set/*`
  builders such as `set/union`, `set/intersection`, `set/difference`,
  `set/add`, and `set/remove`;
- owned `let` locals that are never deleted or returned;
- owned locals overwritten with `set!` before cleanup.

These warnings should be specific enough to point at the producing form and
suggest the obvious next step, such as adding `(defer (delete xs))`, returning
the value directly, or cleaning up before `set!`.

The warning pass should also stay conservative around branches: if every `if`,
`cond`, or `switch` branch clearly deletes or returns the owned local, the
compiler should not warn. If one branch leaks, it should.

These warnings should avoid cases where ownership is ambiguous, especially:

- values stored inside structs or other aggregates;
- values passed through unknown user procedures;
- branch-heavy flows where escape/transfer is not obvious;
- nested ownership inside structs, maps, or arrays.

Warnings are the right first step. A stricter mode can be considered later, but
the initial goal is to help users catch obvious mistakes without pretending the
compiler has a full ownership system.

## Do Not Delete These

These are scalar values, plain values, or borrowed views:

```clojure
(User {:name "Ada" :age 36})
(new []int [1 2 3])
(new [3]int [1 2 3])

(arr/first xs)
(arr/second xs)
(arr/last xs)
(arr/nth xs n)
(arr/rest xs)
(arr/take n xs)
(arr/drop n xs)
(arr/butlast xs)
(arr/drop-last n xs)
(arr/take-while pred xs)
(arr/drop-while pred xs)
(arr/split-at n xs)
(arr/find pred xs)
(some? pred xs)
(every? pred xs)
(arr/reduce f init xs)
(empty? xs)
(count xs)
(contains? collection key)
(io/write path data)
(tap> value)
(tap> :label value)
```

Only the small cross-family kernel remains bare here: `slice`, `get`,
`empty?`, `count`, and `contains?`. Other collection helpers should use their
explicit package names.

`io/write` lowers to `os.write_entire_file(path, data)` and returns `os.Error`.
It does not allocate an owned result.

`arr/split-at` returns two borrowed slices:

```clojure
(let [[front back] (arr/split-at 2 xs)]
  ...)
```

Do not delete `front` or `back`.

`arr/distinct` and `arr/distinct-by` return owned dynamic arrays. They use temporary
maps internally and clean those maps inside the helper, but the returned dynamic
array belongs to the caller:

```clojure
(let [users (arr/distinct-by :id rows)]
  (defer (delete users))
  ...)
```

## Mutating Helpers

Bang helpers mutate existing storage and do not create owned results:

```clojure
(arr/reverse! xs)
(arr/shuffle! pick xs)
(arr/sort! xs)
(arr/sort-by! f xs)
(arr/sort-by! :field xs)
(arr/map! f xs)
(arr/map-indexed! f xs)
(arr/filter! pred xs)
(arr/filter! :field xs)
(arr/remove! pred xs)
(arr/remove! :field xs)
(arr/keep! f xs)
(arr/into! target xs)
(map/merge! target source)
```

Use them when mutation is the right Odin choice. They do not need `delete`
because they do not allocate a result, but the value they mutate may still need
deletion if it is an owned dynamic array. Length-changing helpers require a
dynamic array because they compact and resize the existing storage:

```clojure
(let [xs (new [dynamic]int [3 1 2])]
  (defer (delete xs))
  (arr/sort! xs)
  (arr/first xs))

(let [xs (new [dynamic]int [1 2 3 4])]
  (defer (delete xs))
  (arr/filter! even? xs)
  (len xs))

(let [xs (new [dynamic]int [1 2])
      more (new []int [3 4])]
  (defer (delete xs))
  (arr/into! xs more)
  (len xs))
```

## Allocator Scopes

`with-allocator` temporarily changes `context.allocator` for a lexical block:

```clojure
(with-allocator [allocator context.temp_allocator]
  (let [xs (make [dynamic]int)]
    (defer (delete xs))
    ...))
```

The generated Odin stores the old allocator, assigns the requested allocator,
and restores the old allocator with `defer`. Defers created inside the body run
before the restore defer, so local `delete` calls still use the scoped
allocator. Values returned from the block transfer ownership to the caller, so
the caller must delete them with the matching allocator discipline.

`with-temp-allocator` additionally starts and ends Odin's default temp allocator
scope:

```clojure
(import runtime "base:runtime")

(with-temp-allocator [allocator]
  (let [xs (make [dynamic]int)]
    (defer (delete xs))
    ...))
```

This form still emits ordinary Odin calls to `runtime.default_temp_allocator_*`.
The runtime import is explicit, and any owned values that escape the block must
not borrow storage from the ended temp scope. Kvist rejects obvious direct
escapes such as returning `(arr/map f xs)` from a `with-temp-allocator` body, or
hiding an owned temp-allocated result inside a returned call or struct literal.

For ordinary local owned values, prefer `let` bindings marked with trailing
`defer`:

```clojure
(let [active (arr/filter active? users) defer]
  (count active))

(let [active (arr/filter active? users) defer
      names (arr/map :name active) defer]
  (count names))
```

This lowers to local bindings with matching `defer delete(...)` calls. Use it
when the owned values are local to the body. Do not return a defer-marked value
from the body; if ownership should pass to the caller, return the owned
expression directly without the `defer` marker. That also applies to wrapping
the binding inside a returned struct or passing it into a returned call.

## Returning Owned Values

If a proc returns an owned value, do not delete it locally:

```clojure
(defn active-users [users: []User] -> [dynamic]User
  (arr/filter active? users))
```

The caller owns the result:

```clojure
(let [active (active-users users)]
  (defer (delete active))
  ...)
```

The same rule applies to owned maps:

```clojure
(defn ages-by-name [names: []string, ages: []int] -> map[string]int
  (map/zip names ages))
```

The caller deletes the returned map. `(map/merge left right)` follows the same rule:
it returns a new owned map, while `(map/merge! target source)` mutates an existing
map and does not create an owned result.

Aggregate helpers such as `count-by` and `sum-by` also return owned maps:

```clojure
(let [totals (arr/sum-by :region :amount orders)]
  (defer (delete totals))
  ...)
```

`arr/group-by` returns an owned map with owned dynamic-array values. Clean up both
levels:

```clojure
(let [groups (arr/group-by :status users)]
  (defer
    (each [_ group groups]
      (delete group))
    (delete groups))
  ...)
```

## Do Not Hide Owned Intermediates

Owned helper results should be visible as a binding or a return value:

```clojure
(let [names (arr/map :name users)]
  (defer (delete names))
  (arr/first names))
```

This is rejected because the intermediate dynamic array has no visible owner:

```clojure
(arr/first (arr/map :name users))
```

Return the owned result directly when ownership should pass to the caller:

```clojure
(defn user-names [users: []User] -> [dynamic]string
  (arr/map :name users))
```

## Borrowed Views Must Not Escape Their Backing Storage

Slice views borrow from another value. This is fine locally:

```clojure
(let [xs (new []int [1 2 3 4])
      tail (arr/drop 1 xs)]
  (arr/first tail))
```

But do not return a slice view into data that dies with the proc:

```clojure
;; Wrong direction: returns a view into a local literal.
(defn bad [] -> []int
  (let [xs (new []int [1 2 3])]
    (arr/drop 1 xs)))
```

Odin itself rejects some unsafe literal escapes. Kvist should also reject more
of these cases over time as ownership analysis improves.

## Threading Pipelines

Threading pipelines in `let` bindings are cleanup-aware. If an intermediate
step allocates, Kvist lowers it to a generated temporary and emits
`defer delete(...)` for that generated value.

```clojure
(let [total (->> xs
                 (arr/map inc)
                 (arr/filter even?)
                 (arr/reduce add 0))]
  total)
```

This emits ordinary Odin with named temporaries and cleanup for the allocating
`map` and `filter` results.

Returning a threaded expression with allocating intermediates is rejected for
now. Bind it in `let`, return the final owned value directly, or rewrite the
proc so ownership is explicit.

## Example Standard

Examples should be production-style:

- Every local owned dynamic array or map should have a nearby `defer delete`.
- Do not delete borrowed views.
- Do not delete values that are returned to transfer ownership.
- Prefer small named procs plus `(comment ...)` eval examples over large `main`
  procedures that only print everything.
