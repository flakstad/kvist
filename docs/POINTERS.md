# Pointers And Values

Kvist keeps Odin's execution model. There is no borrow checker and no hidden
ownership runtime for pointers. The current rule is simple:

- pass small values by value
- pass large or shared mutable values by pointer
- use slices for shared contiguous read/write data
- use `addr` and `deref` only when identity or mutation through a reference
  is actually required

Source style:

```clojure
^Order
(addr order)
total^
(set! total^ (+ total^ 1))
```

Use `x^` for the simple symbol case. Keep `(deref ...)` for more complex
expressions such as `(deref (get ptrs i))`.

Writable places:

```clojure
(set! total^ (+ total^ 1))
(set! order^.amount 42)
(set! (get xs i) 9)
```

That keeps `set!` uniform: write to the place you spelled in source.

## What Kvist Helps With Today

- pointer syntax is explicit in source
- ownership warnings catch a small set of obvious dynamic-allocation mistakes
- examples show the intended pointer/value split in ordinary code

## What Kvist Does Not Help With Yet

- no compile-time pointer-vs-value recommendation
- no warning for large structs repeatedly copied by value
- no warning for a pointer parameter that never needs to be a pointer
- no borrow/lifetime analysis

So today the model is still mostly craft and discipline. The language should
help more over time, but only conservatively.

## Likely Future Diagnostics

These are good candidates for future warnings:

- taking the address of a temporary
- passing a large struct by value repeatedly
- pointer parameters that are never dereferenced
- local mutation on a copied value where shared mutation was likely intended

These should stay warnings first, not become hidden language magic.
