# Ownership Rules

OdinL should teach ordinary Odin ownership. It should not hide allocation or
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

## Delete These

These forms return owned values in normal OdinL code:

```clojure
(make [dynamic]int)
(make map[string]int)

(new [dynamic]int [1 2 3])
(new map[string]int {"one" 1 "two" 2})

(map f xs)
(filter pred xs)
(remove pred xs)
(map-indexed f xs)
(keep f xs)
(concat xs ys)
(reverse xs)
(partition n xs)
(partition-all n xs)
(partition-by f xs)
(partition-by :field xs)
(zipmap keys vals)
(index-by f xs)
(index-by :field xs)
(frequencies xs)
(range end)
(range start end)
(range start end step)
(repeat n x)
(repeatedly n f)
(iterate n f x)
```

Use `defer delete` for local owned values:

```clojure
(let [active-users (filter active? users)
      names (map :name active-users)]
  (defer (delete active-users))
  (defer (delete names))
  ...)
```

For `partition`, `partition-all`, and `partition-by`, delete the outer dynamic
array. The chunks inside are borrowed slices and must not be deleted:

```clojure
(let [chunks (partition 2 xs)]
  (defer (delete chunks))
  (first (get chunks 0)))
```

## Do Not Delete These

These are scalar values, plain values, or borrowed views:

```clojure
(User {:name "Ada" :age 36})
(new []int [1 2 3])
(new [3]int [1 2 3])

(first xs)
(second xs)
(last xs)
(nth xs n)
(rest xs)
(take n xs)
(drop n xs)
(take-while pred xs)
(drop-while pred xs)
(split-at n xs)
(find pred xs)
(some? pred xs)
(every? pred xs)
(reduce f init xs)
(empty? xs)
```

`split-at` returns two borrowed slices:

```clojure
(let [[front back] (split-at 2 xs)]
  ...)
```

Do not delete `front` or `back`.

## Returning Owned Values

If a proc returns an owned value, do not delete it locally:

```clojure
(proc active-users [users: []User] -> [dynamic]User
  (filter active? users))
```

The caller owns the result:

```clojure
(let [active (active-users users)]
  (defer (delete active))
  ...)
```

The same rule applies to owned maps:

```clojure
(proc ages-by-name [names: []string, ages: []int] -> map[string]int
  (zipmap names ages))
```

The caller deletes the returned map.

## Do Not Hide Owned Intermediates

Owned helper results should be visible as a binding or a return value:

```clojure
(let [names (map :name users)]
  (defer (delete names))
  (first names))
```

This is rejected because the intermediate dynamic array has no visible owner:

```clojure
(first (map :name users))
```

Return the owned result directly when ownership should pass to the caller:

```clojure
(proc user-names [users: []User] -> [dynamic]string
  (map :name users))
```

## Borrowed Views Must Not Escape Their Backing Storage

Slice views borrow from another value. This is fine locally:

```clojure
(let [xs (new []int [1 2 3 4])
      tail (drop 1 xs)]
  (first tail))
```

But do not return a slice view into data that dies with the proc:

```clojure
;; Wrong direction: returns a view into a local literal.
(proc bad [] -> []int
  (let [xs (new []int [1 2 3])]
    (drop 1 xs)))
```

Odin itself rejects some unsafe literal escapes. OdinL should also reject more
of these cases over time as ownership analysis improves.

## Threading Pipelines

Threading pipelines in `let` bindings are cleanup-aware. If an intermediate
step allocates, OdinL lowers it to a generated temporary and emits
`defer delete(...)` for that generated value.

```clojure
(let [total (->> xs
                 (map inc)
                 (filter even?)
                 (reduce add 0))]
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
