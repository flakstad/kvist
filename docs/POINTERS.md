# Pointers And Values

Kvist keeps Odin's execution model. There is no borrow checker and no hidden
ownership runtime for pointers. The current rule is simple:

- pass small values by value
- pass large or shared mutable values by pointer
- use slices for shared contiguous read/write data
- use address-of and dereference only when identity or mutation through a
  reference is actually required

Source style:

```clojure
^Order
(addr order)
total^
```

Supported alternate forms:

```clojure
(ptr Order)
(& order)
(deref total)
```

Pointer types can be written as `^T` or `(ptr T)`. Prefer `^T` when it reads
cleanly in a type position; use `(ptr T)` when a call-shaped type is clearer.

Address-of can be written as `(addr place)` or `(& place)`. Prefer `addr` in
ordinary code because it is easy to search for and does not visually collide
with variadic parameter syntax.

Use `x^` for the simple pointer-symbol case. Keep `(deref ...)` for compound
pointer expressions where suffix syntax would be hard to read, such as
`(deref ptrs[i])`.

Writable places:

```clojure
(set! total^ (+ total^ 1))
(set! order^.amount 42)
(set! xs[i] 9)
```

That keeps `set!` uniform: write to the place you spelled in source.

## What Kvist Helps With Today

- pointer syntax is explicit in source
- ownership warnings catch a small set of obvious dynamic-allocation mistakes
- examples show the intended pointer/value split in ordinary code

## Current Limits

- no compile-time pointer-vs-value recommendation
- no warning for large structs repeatedly copied by value
- no warning for a pointer parameter that never needs to be a pointer
- no borrow/lifetime analysis

The pointer model is explicit craft and discipline. Kvist does not add hidden
borrow checking or ownership magic around pointers.
