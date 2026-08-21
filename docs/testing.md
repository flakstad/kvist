# Testing

Kvist's test package is a small layer over Odin's `core:testing`. It gives you
Lisp-shaped test declarations, assertion context, table checks, and fixtures
while still using Odin's ordinary test runner underneath.

Import it as:

```clojure
(import t "kvist:test")
```

Run test files with:

```sh
./kvist test path/to/file.kvist
```

## A Small Test

```clojure
(package tests)

(import t "kvist:test")

(t.deftest arithmetic
  (t.is (= (+ 2 2) 4)))
```

`t.deftest` lowers to an Odin `@(test)` proc. Inside the test body, `t` is the
current `^testing.T`.

A string immediately after the test name becomes the generated proc docstring:

```clojure
(t.deftest parses-empty-input
  "Empty input is valid."
  (t.is true))
```

## Assertions

Use `t.is` for assertions:

```clojure
(t.is true)
(t.is (> score 10) "score should clear the bar")
(t.is (= (+ 2 3) 5))
(t.is (not failed?))
```

`t.is` records failures through Odin's testing package and returns the boolean
result from the underlying assertion helper.

Equality forms of shape `(= actual expected)` use value-aware reporting when
possible, so failures can show both sides. Ordinary boolean expressions are
checked as true or false.

## Context

Use `t.testing` to add a message around a group of assertions:

```clojure
(t.deftest user-score
  (t.testing "new users"
    (t.is (= 0 initial-score))
    (t.testing "after bonus"
      (t.is (= 10 final-score)))))
```

Nested contexts are joined in failure output. The context is scoped with
`defer`, so it is popped even if the body returns early.

## Table Checks

`t.are` repeats one assertion shape over rows of values:

```clojure
(t.deftest squares
  (t.are [x expected]
    (= (* x x) expected)
    1 1
    2 4
    3 9))
```

The binding vector must be non-empty. The remaining values are consumed in rows
the same size as the binding vector; if the row is incomplete, Kvist reports a
macro expansion error.

## Fixtures

Fixtures affect tests defined later in the same package file.

Use `:once` for setup that should run before the first wrapped test body:

```clojure
(defvar once-ran 0)

(defn once-fixture []
  (set! once-ran (+ once-ran 1)))

(t.use-fixtures :once once-fixture)
```

`:once` fixtures are setup-only. They do not receive a teardown continuation.

Use `:each` for wrappers around every later test:

```clojure
(defn each-fixture [t: ^testing.T, body: fn [t: ^testing.T]]
  ;; Put setup here.
  (body t))

(t.use-fixtures :each each-fixture)
```

Each `:each` fixture receives the current `^testing.T` and a body proc. Call
`(body t)` to run the test body. If the fixture allocates resources, use
ordinary Kvist cleanup patterns such as `defer`.

## Ownership In Tests

Test code is still normal Kvist code. If a helper returns owned memory, clean it
up, usually with `:defer` or `defer`:

```clojure
(import arr "kvist:arr")

(t.deftest generated-values
  (let [xs (arr.range 0 4) :defer]
    (t.is (= (count xs) 4))))
```

The test package does not hide ownership or allocator rules.

## Property-Based Tests

The property-based suite is a separate Odin runner under `tests/pbt`. It uses
the [`pbt`](https://github.com/flakstad/pbt) package as a test-only dependency;
neither the Kvist compiler nor programs built with Kvist depend on it.

For local development, place the `pbt` repository next to Kvist as `../pbt`
and run:

```sh
./scripts/test_pbt.sh --text
```

Point `KVIST_PBT_ROOT` at another checkout when needed:

```sh
KVIST_PBT_ROOT=/path/to/pbt ./scripts/test_pbt.sh --text
```

The script caches the Kvist compiler, compiled targets, and PBT runner under
the ignored `tmp/pbt-cache` directory. Cache entries are separated by workspace,
Odin version, and PBT checkout, and each artifact is rebuilt when a source file
or source directory is newer. Set `KVIST_PBT_CACHE_DIR` to move the cache or
`KVIST_PBT_REBUILD=1` to force a complete rebuild. Explicit target environment
variables still bypass the corresponding cached target.

The runner accepts PBT options such as `--property`, `--tag`, `--num-tests`,
`--seed`, `--replay-seed`, and `--replay-choices`. CI checks out an exact PBT
commit under `.tooling/pbt` so the test dependency is reproducible.

The reader properties generate recursive forms, escaped string and regex
literals, reader sugar, and discarded forms. The same generated model is also
rendered both compactly and with varied whitespace, commas, and comments; both
renderings must produce the same normalized CST. Targeted corruptions exercise
missing, mismatched, and extra delimiters as well as unterminated string and
regex literals, and require bounded reader diagnostics.

The EDN property compiles a small Kvist target and sends generated EDN values
to it over stdin. The target requires structural `read(write(value))` equality
and idempotent canonical output, and the runner checks that a second process
roundtrip produces the same bytes. `scripts/test_pbt.sh` builds this target
automatically; set `KVIST_PBT_EDN_TARGET` to reuse an existing binary.

The stateful Data map property generates shrinkable command sequences over a
small independent Odin model. After every `assoc`, `dissoc`, or `lookup`, a
compiled Kvist target reports all modeled key slots. The property checks the
complete resulting state, input immutability, and an internal EDN roundtrip.
The script builds this target automatically; set `KVIST_PBT_DATA_MAP_TARGET`
to reuse an existing binary.

A second stateful Data property models two-level maps and checks sequences of
`assoc-in`, `update-in`, `get-in`, and `dissoc-in`. It covers both existing and
missing paths, including creation of intermediate maps, preservation of empty
parent maps, and sibling retention after deletion. It checks parent shape, the
queried value, the complete nested state, and input immutability after every
command. Set
`KVIST_PBT_DATA_NESTED_TARGET` to reuse its compiled target.

The stateful sequence property switches between vector and list Data while
checking `conj`, `append`, indexed `assoc`, `pop`, `nth`, `peek`, `list`, and `vec`
against an independent bounded sequence model. It covers valid vector updates,
out-of-range reads, empty peeks, and the different list/vector stack ends. Set
`KVIST_PBT_DATA_SEQUENCE_TARGET` to reuse its compiled target.

The native set property generates duplicate-rich integer inputs and compares
`kvist:set` with a finite-domain bitmask model. It checks pure and mutating
union, intersection, difference, add, and remove operations, plus subset,
superset, disjointness, membership, cardinality, and input immutability. Set
`KVIST_PBT_SET_TARGET` to reuse its compiled target.

The Data transform property compares eager sequence helpers with an independent
bounded model. It checks mapping, indexed mapping, filtering, take/drop,
remove/keep, indexed keep, mapcat, split-at, reverse, interleave, rest/butlast,
distinct and distinct-by, membership, interpose, take-nth, and concat. It also
checks `into` ordering for vectors and lists, duplicate elimination for sets,
and the identities `concat(split-at(n, xs)) = xs` and
`reverse(reverse(xs)) = xs`. Generated counts cover negative and oversized
values, while callback keys exercise collisions and negative remainders. Set
`KVIST_PBT_DATA_TRANSFORM_TARGET` to reuse its compiled target.

The native map property compares `kvist:map` with a finite-domain reference
model. It checks pure and mutating assoc, dissoc, and merge operations, lookup
and defaults, membership, keys and value projections, zip truncation, duplicate
keys, cardinality, and input immutability. Map iteration order is deliberately
excluded from the model. Set `KVIST_PBT_MAP_TARGET` to reuse its compiled
target.

The Data aggregate property checks left-to-right reduction, frequencies,
count-by, group-by, index-by, and reduce-kv against an independent model.
Generated modulo keys include negative values; groups must preserve input
order, index-by must retain the last item, and frequency maps must reduce back
to the original count and sum. Set `KVIST_PBT_DATA_AGGREGATE_TARGET` to reuse
its compiled target.

The Data scan property checks first-match search, indexed search, min/max by
key, boolean scans, take/drop-while, stable sorting, fixed partitions,
partition-all, and partition-by against an independent model. Generated inputs
include observable equal sort keys, missing searches, non-positive partition
sizes, and incomplete trailing partitions. Set `KVIST_PBT_DATA_SCAN_TARGET` to
reuse its compiled target.

The Data map transform property checks select-keys, merge and merge-with,
key/value/entry callbacks, entry filtering, and into against a finite-domain
model. Generated inputs force transformed-key and source-entry collisions. It
also reconstructs maps through both entries and paired key/value projections.
Set `KVIST_PBT_DATA_MAP_TRANSFORM_TARGET` to reuse its compiled target.

The stateful Data set property checks `conj`, `append`, membership, cardinality,
and set-to-vector/list-to-set conversions against a finite-domain bitmask
model. Every command also verifies input immutability and an EDN roundtrip;
duplicate insertions must leave the set unchanged. Set
`KVIST_PBT_DATA_SET_TARGET` to reuse its compiled target.

The Data accessor property generates every runtime Data kind with shallow,
shrinkable payloads. It checks the one-hot type predicates, kind keywords,
primitive accessor roundtrips, describe metadata, collection boundary
accessors, map entry access, tagged payloads, and success/error metadata from
the primitive decoders. Set `KVIST_PBT_DATA_ACCESS_TARGET` to reuse its
compiled target.

The typed decode property generates valid nested configuration documents and
targeted single corruptions across required fields, enums, nested structs, and
typed dynamic arrays. `data.decode` and `data.validate` must agree, failures
must report the modeled path/kinds/enum metadata, and successful native values
must match independent summaries of the generated input. Set
`KVIST_PBT_TYPED_DECODE_TARGET` to reuse its compiled target.

Compiler-semantics properties live in a separate slow runner because every
case invokes the Kvist compiler and Odin toolchain. Run its default 25 cases per
property with:

```sh
./scripts/test_pbt_compiler.sh --text
```

The generators build bounded integer, floating-point, boolean, escaped-string,
native-array, map, set, struct, enum, and tagged-union expressions containing
arithmetic, comparisons, logical operators, string transforms, literals,
selectors, casts, indexing, lookup, membership, slicing, destructuring, field
access, type-payload cases, value updates, mutation, `if`, typed-result `let`,
function calls, anonymous functions and captures, pointers and aliasing,
multi-return bindings and guards, `cond`, `case`, `for`, `while`, `break`,
`continue`, `defer`, structural Data patterns and destructuring, and `->`.
The core-macro cases additionally cover `->>`, `cond->`, `as->`, `doto`,
`when-let`, `if-let`, `when-ok`, and `if-ok`, including single evaluation and
short-circuiting across chained value/boolean and value/error bindings.
Call-resolution cases combine positional, reordered named, mixed, and defaulted
arguments with generic specialization and global, generic, and local overload
selection.
Dedicated cases verify that `and` and `or` short-circuit before an unsafe
division. Each program is compiled and executed, and its output is compared
with an independent Odin model. The runner supports the same replay and count
options as the main suite; set `KVIST_PBT_COMPILER` or
`KVIST_PBT_COMPILER_EXPRESSION_SOURCE` to override
its cached compiler or integer/boolean source fixture. Set
`KVIST_PBT_COMPILER_STRING_SOURCE` to override the separate string fixture;
this keeps the `kvist:str` package cost out of non-string compiler cases.
The script retries the known transient Odin `Queue($T=string)` type-check
assertion for at most 32 total attempts. Other compiler failures are not
retried, and the assertion remains an error if all 32 attempts fail. Compiler
cases have a 120-second outer process timeout so the bounded retry sequence can
finish before PBT classifies it as a timeout.

The compiler runner also generates invalid expressions directly against the
frontend library. It covers invalid arities, missing `case` defaults, mismatched
branch types, non-assignable mutation targets, removed forms, and statements in
expression position. Every rejection must retain its diagnostic category and
an in-bounds span attributed to the generated eval source.

## Examples

- [examples/packages/testing.kvist](../examples/packages/testing.kvist) - small
  package tour
- [examples/coverage/packages/test-package-tests.kvist](../examples/coverage/packages/test-package-tests.kvist) -
  fixtures, contexts, and table assertions
- [examples/coverage/packages/builtin-package-tests.kvist](../examples/coverage/packages/builtin-package-tests.kvist) -
  broader package tests using `kvist:test`
