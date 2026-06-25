# False Friends

Kvist deliberately uses Lisp-shaped source for Odin-shaped programs. Some forms
therefore look familiar if you know Clojure or other Lisps, but they keep
Kvist's native execution model: concrete values, explicit allocation, explicit
mutation, and no hidden sequence runtime.

Use this page as a quick mental-model check when reading examples.

## Common Traps

| Form | Looks Like | Kvist Meaning |
| --- | --- | --- |
| `for` | Clojure sequence comprehension | An Odin-style loop for side effects. It does not build a sequence. |
| `[1 2 3]` | Persistent vector data | In common expression contexts, an owned dynamic array that must be deleted, deferred, returned, or transferred. |
| `{k v}` / `#{v}` | Persistent map/set data | Owned map/set storage when constructed locally. Clean it up like other owned values. |
| `arr.map`, `arr.filter` | Lazy sequence operations | Eager helpers. Builders return owned dynamic arrays. |
| `deftransform` | Runtime pipeline value | Compile-time fused transform structure accepted only in transform positions. |
| `.field` | First-class accessor function | Contextual selector syntax accepted by specific helpers and macros. |
| `fn` with captures | Heap closure | Non-capturing proc value, or a non-escaping captured callback lowered with explicit extra parameters. |
| `let` binding | Immutable local | Ordinary local storage. It can be assigned with `set!` when the binding is a valid place. |
| `when` expression | False returns `nil` | False returns the expected type's zero value when used as an expression. |
| `or` / `and` | Return one input value | Boolean operators only. Arbitrary values are not conditions. |
| `:dev`, `:else`, `:defer` | One keyword model | Runtime keyword literals and syntactic marker keywords share spelling but are interpreted by position. |

## Ownership In Pipelines

Threading makes eager data flow readable, but it does not make eager helpers
free. This pipeline allocates for the filtering step and again for the mapping
step:

```clojure
(->> users
     (arr.filter active?)
     (arr.map .name)
     (arr.take 10))
```

When such a pipeline is bound in `let`, Kvist can emit named temporaries and
matching cleanup for owned intermediates. The allocation and copy costs still
exist. For hot paths, prefer one of these shapes:

- a fused transform with `into`, `arr.into!`, `transduce`, or `for :transform`
- bang helpers over a working buffer you own
- an explicit `for` loop when the state update is clearer by hand

## Transform Syntax Is Contextual

Transform steps such as `(map f)`, `(filter pred)`, and `(comp ...)` are not
runtime values. They are compile-time syntax accepted by `deftransform`, `into`,
`arr.into!`, `transduce`, and `for :transform`.

Ordinary collection helpers are different:

```clojure
(arr.map f xs)                  ; eager helper, returns an owned dynamic array
(into [dynamic]int (map f) xs)  ; fused transform position
```

## Map Sources

Map sources feed values through transforms by default:

```clojure
(transduce (filter positive?) + 0 lookup)
```

Use `map.entries` when the transform needs keys:

```clojure
(transduce
  (map (fn [entry: (map.entry string int)] -> int
         (+ (count entry.key) entry.value)))
  + 0
  (map.entries lookup))
```

## Prefer Explicit Package Helpers In Intro Code

Kvist can expose package helpers as bare names for unaliased imports, but
introductory code usually reads better with explicit package names:

```clojure
(import arr "kvist:arr")

(let [active (arr.filter active? users) :defer]
  (arr.map .name active))
```

That spelling keeps the eager, array-specific ownership model visible.
