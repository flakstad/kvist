# Sequences

Kvist uses native arrays, slices, maps, sets, and strings. Sequence helpers are
eager and have explicit ownership. There is no lazy sequence runtime.

```clojure
(import arr "kvist:arr")
(import map "kvist:map")
(import set "kvist:set")
(import str "kvist:str")
```

Core operations such as `count`, `empty?`, `get`, `slice`, `contains?`,
`assoc`, and `update` dispatch from the native type. Other operations remain
package-qualified.

## Arrays And Slices

Constructors:

```clojure
(arr.empty int)
(arr.empty int 64)
(arr.dynamic int [1 2 3])
(arr.fixed int [1 2 3])
```

`arr.empty` and `arr.dynamic` return owned dynamic arrays. `arr.fixed` returns a
fixed array value.

Accessors and views:

```clojure
(arr.first xs)
(arr.second xs)
(arr.last xs)
(arr.nth xs 4)
(arr.take 10 xs)
(arr.drop 10 xs)
(arr.rest xs)
(arr.split-at 10 xs)
```

`take`, `drop`, `rest`, `take-while`, `drop-while`, `butlast`, `drop-last`, and
the chunks returned by partition helpers are borrowed slice views. Their input
must outlive them.

Eager builders:

```clojure
(arr.map label xs)
(arr.filter active? xs)
(arr.remove archived? xs)
(arr.keep parse xs)
(arr.mapcat children xs)
(arr.reverse xs)
(arr.sort xs)
(arr.sort-by .name xs)
(arr.distinct xs)
(arr.partition 20 xs)
(arr.group-by .owner xs)
```

These return owned collections. They do not mutate the input.
Partition helpers own the outer dynamic array; their inner chunks are borrowed
slices.

Scans do not allocate output collections:

```clojure
(arr.reduce + 0 xs)
(arr.find urgent? xs)
(arr.some? urgent? xs)
(arr.every? valid? xs)
(arr.min-by .score xs)
(arr.max-by .score xs)
```

Bounded producers return owned arrays in ordinary expression position:

```clojure
(arr.range 0 10)
(arr.repeat 4 value)
(arr.repeatedly 4 make-value)
(arr.iterate 4 next-value initial)
(arr.cycle 10 xs)
(arr.take-nth 2 xs)
```

They stream without building an array when used directly by `for`, `into`, or
`transduce`.

## Mutation

Names ending in `!` mutate existing storage:

```clojure
(arr.push! xs value)
(arr.map! normalize xs)
(arr.filter! keep? xs)
(arr.reverse! xs)
(arr.sort-by! .name xs)
(arr.into! xs more)
```

Helpers that can resize an array require an owned dynamic array binding.

Use direct place operations for local mutation:

```clojure
(set! user.name "Ada")
(mut! total += amount)
(update! user.score + bonus)
(delete! lookup key)
```

`assoc` and `update` return changed struct copies:

```clojure
(-> user
    (assoc .name "Ada")
    (update .score + 10))
```

## Maps And Sets

Map constructors and persistent-style helpers return owned maps:

```clojure
(map.empty string int)
(map.of string int {"a" 1 "b" 2})
(map.assoc scores "Ada" 42)
(map.dissoc scores "Ada")
(map.merge defaults overrides)
```

Bang variants mutate an existing map:

```clojure
(map.assoc! scores "Ada" 42)
(map.dissoc! scores "Ada")
(map.merge! scores updates)
```

`map.keys` and `map.vals` return owned dynamic arrays.

Sets use an Odin map-backed representation:

```clojure
(set.of keyword [:open :closed])
(set.union lhs rhs)
(set.intersection lhs rhs)
(set.difference lhs rhs)
(set.add! values :open)
(set.remove! values :closed)
```

Non-bang set operations return owned sets. Bang operations mutate the target.

## Strings

String views borrow from their input:

```clojure
(str.slice text 0 4)
(str.trim text)
(str.trim-prefix text "prefix-")
```

String builders and transformations return owned values:

```clojure
(str.join parts ", ")
(str.replace text "old" "new")
(str.lower text)
(str.upper text)
```

`str.split` returns an owned slice of borrowed string views.

## Ownership

The common rules are:

- view helpers borrow;
- eager builders return owned collections;
- bang helpers mutate and return no replacement collection;
- scans return scalars or small tuples;
- owned results must be returned, deleted, or bound with cleanup;
- native containers holding managed `Data` values need an explicit ownership
  contract.

```clojure
(let [active (arr.filter active? users) :defer
      names (arr.map .name active) :defer]
  (println names))
```

Each eager step above allocates. Use a fused [transform](transforms.md), a
mutating helper, or a direct `for` loop when intermediate collections are not
useful values.

See [the package tour](../examples/collections/package-tour.kvist) and
[the sequence examples](../examples/collections/sequences.kvist).
