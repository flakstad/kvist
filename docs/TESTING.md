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
checked as truthy-or-not, which is exactly as dramatic as it needs to be.

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

Current `:once` fixtures are setup-only. They do not receive a teardown
continuation.

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

The test package keeps assertion plumbing tidy; it does not hide ownership or
allocator rules. No confetti cannon of implicit cleanup here.

## Examples

- [examples/packages/testing.kvist](../examples/packages/testing.kvist) - small
  package tour
- [examples/coverage/packages/test-package-tests.kvist](../examples/coverage/packages/test-package-tests.kvist) -
  fixtures, contexts, and table assertions
- [examples/coverage/packages/builtin-package-tests.kvist](../examples/coverage/packages/builtin-package-tests.kvist) -
  broader package tests using `kvist:test`
