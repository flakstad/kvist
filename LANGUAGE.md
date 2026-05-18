# OdinL Language Draft

This document captures the current design direction for OdinL as a
Clojure-smelling Lisp that compiles to Odin.

This is a draft, not a stability promise. The goal is to make the design
explicit early enough that implementation follows a coherent language model
instead of accumulating parser hacks.

## Direction

OdinL is no longer framed as "Odin in parens". The stronger direction is:

- a small Lisp-shaped source language
- Clojure-flavored syntax and editing feel
- Odin as the code generation target
- Odin as the execution model
- readable generated `.odin`
- no hidden interpreter runtime

The language should smell like Clojure in surface syntax while remaining honest
about Odin's operational model: explicit layout, explicit mutation, explicit
allocation, and ordinary Odin interop.

## Non-Goals

These are explicit non-goals for the first language design:

- no Clojure seq abstraction
- no laziness by default
- no persistent collection semantics unless intentionally added later
- no dynamic vars or hidden runtime environment
- no "better Odin through magic"
- no opaque generated code that must not be read
- no attempt to use Odin as a compiler IR for arbitrarily high-level features

## Relationship to `odineval`

`odineval` remains the right execution harness for REPL-like workflows:

- generate scratch Odin packages
- support internal and external eval
- run `odin run` / `odin check`
- show generated Odin during debugging
- support editor integration

OdinL should reuse that execution model rather than invent an interpreter.

The architectural split should be:

```text
odinl
  reader
  expander
  resolver
  lowering
  Odin emitter

odineval
  scratch package generation
  internal/external eval
  odin run/check/build/test
  editor UX
```

## Implementation Direction

The old Python prototype should be treated as superseded rather than gradually
evolved into the new language.

The serious OdinL compiler/transpiler should be implemented in Odin itself.

Reasons:

- the project is now a real language frontend, not a throwaway syntax sketch
- implementing it in Odin keeps the toolchain aligned with the host language
- the emitted-code model, type vocabulary, and interop concerns stay close to
  the environment OdinL targets
- long-term maintenance is cleaner if the compiler lives in the same ecosystem

This implies a clean break:

- do not keep stretching the old Python translator
- do not preserve compatibility with the old mixed-file experiment
- build the real compiler as a fresh Odin implementation

## Surface Syntax

The surface grammar uses three primary container shapes:

- `(...)` for forms and invocation
- `[...]` for signatures and ordered binding lists
- `{...}` for named fields and keyed literals

`.odinl` source should be formatted like Clojure-family code, with 2-space
indentation. This is separate from generated `.odin` and compiler `.odin`
source, which use ordinary Odin 4-space indentation.

The language keeps Odin-style top-level package and import forms:

```clojure
(package main)
(import "core:fmt")
(import strings "core:strings")
(import runtime "base:runtime")
```

Qualified Odin names such as `fmt.println`, `strings.clone`, and
`runtime.Allocator` remain ordinary symbols.

## File Model

For v0.1, `.odinl` files should be pure OdinL source.

That means:

- no mixed raw Odin passthrough
- no top-level autodetection between Odin and Lisp syntax
- no partial "copy this chunk through unchanged" file model
- raw Odin only through explicit escape hatches such as `(odin "...")`

Ordinary `.odin` files remain ordinary Odin and should not require OdinL.

This keeps the compiler architecture much cleaner:

- one reader
- one AST
- one lowering path
- simpler source mapping
- clearer macro story later

## Reader Surface

The reader should be small and unsurprising. It needs to support the language's
core syntax, not become a second meta-language.

### Core reader forms

The reader should support:

- lists: `(...)`
- vectors: `[...]`
- brace forms: `{...}`
- symbols
- keywords
- strings
- numeric literals
- booleans
- `nil`
- comments
- `(comment ...)`

### Symbols

Symbols should allow ordinary Lisp identifiers plus Odin-oriented qualified and
tag-like spellings that matter for interop:

- ordinary names: `answer`, `route-add`, `parse-request`
- qualified names: `fmt.println`, `runtime.Allocator`
- enum tags/constants where useful: `.Get`

The exact symbol grammar can stay conservative at first, but it should be broad
enough that common Odin names do not require escaping.

## Name Mapping

OdinL source names and emitted Odin identifiers do not need to use exactly the
same spelling, but the mapping should be simple and predictable.

The conservative default is:

- preserve case
- preserve underscores that already exist
- map hyphens to underscores
- map a predicate suffix `?` to `_p`
- map a mutation/side-effect suffix `!` to `_bang`
- do not invent camelization or other clever rewrites

Examples:

```clojure
route-add     ;; => route_add
query-get     ;; => query_get
http-only     ;; => http_only
greater-than? ;; => greater_than_p
bump!         ;; => bump_bang
Request       ;; => Request
HTTPServer    ;; => HTTPServer
runtime.Allocator ;; => runtime.Allocator
```

This strikes a workable balance:

- Lisp-friendly source names remain pleasant to write
- generated Odin names remain boring and readable
- users can predict the emitted identifier without consulting the compiler

### Fields and keywords

Keyword names should follow the same mapping rules when lowered to Odin field
names.

Examples:

```clojure
:path        ;; => path
:http-only   ;; => http_only
:created-at  ;; => created_at
```

So:

```clojure
(struct Cookie {
  :http-only bool
  :created-at string
})
```

lowers conceptually to:

```odin
Cookie :: struct {
    http_only: bool,
    created_at: string,
}
```

### Enum and union variant names

Enum members and named union variants should follow the same predictable rule:
hyphens become underscores, case is otherwise preserved.

Examples:

```clojure
(enum Http-Status [
  OK
  Not-Found
  Unprocessable-Content
])
```

Conceptual Odin lowering:

```odin
Http_Status :: enum {
    OK,
    Not_Found,
    Unprocessable_Content,
}
```

Likewise, enum tag references should map the same way:

```clojure
.Not-Found   ;; => .Not_Found
```

### Qualified names

Qualified names should map component-wise when they refer to OdinL-defined
identifiers, while existing imported Odin names should remain as written.

This means the compiler should resolve names first and emit them second, rather
than trying to rewrite raw text blindly.

### Deliberate non-goal

The language should not try to be clever about identifier style conversion.
Avoid:

- automatic camelCase generation
- automatic PascalCase generation
- special punctuation-based naming conventions beyond simple lowering rules
- separate source and emitted names unless explicitly added later

### Keywords

Keywords are part of the reader surface because they are used for:

- struct field declarations
- struct and union construction
- field access
- keyed literal forms

Examples:

```clojure
:path
:method
:http-only
```

Keyword access remains expression syntax, not reader magic:

```clojure
(:path req)
```

### Brace forms

Brace forms are reader-level syntax. Their meaning is determined by context.

Examples:

```clojure
(struct Request {
  :method Method
  :path string
})

(Request {
  :method .Get
  :path "/ping"
})
```

The reader should preserve the order of brace entries exactly as written.

### Booleans and `nil`

The language should surface ordinary boolean literals and `nil` directly:

```clojure
true
false
nil
```

These should lower to the obvious Odin values where valid.

The reader classifies these as literal forms rather than generic symbols so
later diagnostics and macro expansion can distinguish values from names.

### Comments

The comment story should stay simple in v0.1.

At minimum, line comments should be supported.

Odin-style `//` comments are worth supporting directly:

```clojure
// this is a comment
```

Lisp-style `;` comments are also acceptable:

```clojure
; this is a comment
```

Block comments can be added later if needed, but there is no need to overdesign
the reader before real usage justifies it.

### `(comment ...)`

`(comment ...)` should be supported as a structured reader/parsing form that
ignores everything within it.

Examples:

```clojure
(comment
  (proc old-version [x: int] -> int
    (+ x 1)))

(comment
  (fmt.println "debug")
  (dangerous-call))
```

This is useful for experimentation and temporarily disabling forms without
leaving the expression language.

## Top-Level Forms

The planned v0.1 top-level forms are:

- `package`
- `import`
- `const`
- `struct`
- `enum`
- `union`
- `proc`
- `odin`

### `const`

```clojure
(const answer 42)
(const max-size int 1024)
```

### `struct`

Structs use brace syntax with keyword field names.

```clojure
(struct Request {
  :method Method
  :path string
  :query string
  :params []string
})
```

Important: although brace syntax resembles a map, struct field order is
preserved exactly as written because Odin struct layout depends on field order.

### `enum`

Enums are ordered by default and should use sequence syntax when values are
implicit.

```clojure
(enum Method [
  Get
  Post
  Delete
])
```

For explicit values, keyed brace syntax is allowed:

```clojure
(enum Http-Status {
  :OK 200
  :Not-Found 404
  :Unprocessable-Content 422
})
```

### `union`

`union` denotes a tagged union in the Odin sense, not a C raw union.

```clojure
(union Value {
  :i int
  :s string
  :ok bool
})
```

Use `union` when exactly one variant is valid at a time and the choice may
carry data. This is appropriate for AST nodes, tagged results, events, tokens,
or variant-bearing entities.

Raw overlapping-memory unions for C interop are a separate concern and should
not be conflated with `union`.

The v0.1 union story should stay deliberately narrow:

- declaration support: yes
- construction support: yes
- rich inspection/destructuring support: later
- full ergonomic use should wait for a future `match` design

### `proc`

Functions use a typed signature vector:

```clojure
(proc add [a: int, b: int] -> int
  (+ a b))

(proc query-get [url: URL, key: string] -> [val: string, ok: bool]
  ...)
```

Commas are optional and exist for readability:

```clojure
(proc add [a: int
           b: int] -> int
  (+ a b))
```

An empty return annotation means the function is `void`:

```clojure
(proc main []
  (fmt.println "hello"))
```

### `odin`

`odin` is the raw escape hatch.

```clojure
(odin "foreign import sqlite \"system:sqlite3\"")
```

This should remain explicit and slightly awkward on purpose.

## Expressions

The planned core expression forms are:

- `let`
- `do`
- `if`
- `when`
- `cond`
- `switch`
- `set!`
- `get`
- keyword field access: `(:field expr)`
- threading: `->` and `->>`
- `return`
- `defer`
- `for`
- `each`
- higher-order procedures
- raw `odin`

## Special Forms and Calls

The language should keep the set of privileged forms small and fixed.

### Core special forms

The parser should recognize these as special forms rather than ordinary calls:

- `package`
- `import`
- `const`
- `struct`
- `enum`
- `union`
- `proc`
- `odin`
- `let`
- `do`
- `if`
- `when`
- `cond`
- `switch`
- `set!`
- `return`
- `defer`
- `for`
- `each`
- `comment`

Everything else should be treated as an ordinary call unless another reader
rule applies.

This is an important design constraint: avoid growing the special-form set
casually.

### Ordinary calls

Any list whose head is not a special form and not a dedicated syntactic head
such as a keyword should parse as a normal call expression.

Examples:

```clojure
(fmt.println "hello")
(strings.clone raw allocator)
(make [dynamic]Route allocator)
(new []int [1 2 3])
```

Qualified Odin names remain normal callable heads:

```clojure
(fmt.tprintf "%s" name)
```

### Keyword-headed forms

Keyword-headed lists should not be treated as ordinary function calls.

The primary v0.1 case is field access:

```clojure
(:path req)
(:http-only cookie)
```

These should parse into a dedicated field-access form, not into a generic call
whose callee happens to be a keyword.

This keeps field access semantically distinct from function invocation and
avoids pretending keywords are first-class callable lookup functions in the
Clojure sense.

### `proc` by shape

`proc` is intentionally allowed in more than one position, but only in a
controlled way.

Top-level declaration shape:

```clojure
(proc add [a: int, b: int] -> int
  (+ a b))
```

Expression literal shape:

```clojure
(proc [x: int] -> int
  (+ x 1))
```

The parser should distinguish these by shape:

- `(proc name [args...] ...)` => declaration form
- `(proc [args...] ...)` => procedure literal form

There is no need to make `proc` a generic callable head with more ad hoc
variants in v0.1.

### Future macro expansion boundary

Macro expansion should happen after parsing special forms and ordinary calls
into structured syntax, not over raw token streams.

That means the parser should first answer:

- what is a declaration?
- what is a control form?
- what is a call?
- what is field access?

and only then hand structured forms to a later macro phase.

### `let`

`let` is a scoped binding expression, not just declaration sugar.

```clojure
(let [x 20
      y 22]
  (+ x y))
```

Typed local bindings are allowed:

```clojure
(let [x: int 20
      y: int 22]
  (+ x y))
```

Flat multi-return destructuring is worth supporting because it matches ordinary
Odin usage and keeps explicit control flow readable:

```clojure
(let [[req ok] (parse-request s)]
  (when (not ok)
    (return "" false))
  (:path req))
```

The intended v0.1 scope is deliberately small:

- flat vector destructuring for multi-return bindings
- `_` allowed for ignored positions
- flat struct-field destructuring in `let`
- no generalized nested destructuring yet
- no protocol-driven binding sugar in the core language

Examples:

```clojure
(let [[val ok] (query-get url key)]
  ...)

(let [[_, ok] (delete key allocator)]
  ...)
```

This keeps the core language explicit while leaving room for later macro-based
binding abstractions such as `when-bind`.

Struct field destructuring lowers to obvious Odin assignments:

```clojure
(let [{:name name
       :age age} user]
  ...)
```

should lower as if written:

```odin
name := user.name
age := user.age
```

Shorthand such as `{:name :age}` expands to same-named locals. The compiler may
introduce a temporary so the source expression is evaluated once before fields
are pulled out.

Map destructuring is a separate question because Odin map lookup has presence
semantics, not Clojure nil-as-missing semantics. It should not be added until
the generated code can stay explicit about whether lookup failure is allowed.

### `do`

```clojure
(do
  (fmt.println "side effect")
  (+ 1 2))
```

### `if`, `when`, `cond`

```clojure
(if (< n 0)
  "negative"
  "positive")

(when debug?
  (fmt.println "debug"))

(cond
  (< n 0) "negative"
  (== n 0) "zero"
  :else "positive")
```

## Operators

The operator surface should stay simple and predictable.

### Arithmetic and comparison

Use symbolic operators for arithmetic and comparison:

- `+`
- `-`
- `*`
- `/`
- `%`
- `==`
- `!=`
- `<`
- `<=`
- `>`
- `>=`

Examples:

```clojure
(+ a b)
(- x 1)
(== status .OK)
(<= i 10)
```

These should lower directly to the obvious Odin operators.

### Boolean logic

Use Lisp-friendly word forms for boolean logic:

- `and`
- `or`
- `not`

Examples:

```clojure
(when (and ok (not done))
  ...)

(if (or debug force)
  ...
  ...)
```

These should lower directly to Odin boolean operators such as `&&`, `||`, and
`!`.

### No bare `=` equality form

The language should not introduce bare `=` as an equality operator in v0.1.

Reasons:

- `==` already maps directly to Odin equality
- bare `=` risks confusion with binding or assignment-oriented syntax traditions
- avoiding extra equality spellings keeps parsing and examples simpler

If a more Clojure-like generic equality layer ever appears, it should be a
deliberate later addition rather than an accidental alias.

### `switch`

`switch` is the v0.1 value-dispatch form. It is intended for Odin-like
branching over enums and other ordinary values without introducing a full
pattern language.

```clojure
(switch method
  .Get "GET"
  .Post "POST"
  .Delete "DELETE"
  :else "")
```

`switch` should be expression-valued when every arm produces a value, and should
lower directly to ordinary Odin `switch` or an equivalent obvious lowering.

It is the preferred v0.1 form for enum dispatch. Union destructuring and
pattern-oriented branching are intentionally deferred until a later `match`
design exists.

### `set!`

Mutation remains explicit.

```clojure
(set! total (+ total x))
(set! (:status res) 200)
```

### `get`

`get` is for indexed or keyed lookup, not struct field access.

```clojure
(get xs 0)
(get table key)
(get table key default-value)
```

The three-argument form is map-oriented and lowers to a tiny helper using Odin's
ordinary comma-ok map lookup. It returns `default-value` when the key is absent.

### Keyword field access

Keyword access is the primary field access form:

```clojure
(:path req)
(:name person)
(set! (:status res) 200)
```

This should compile to ordinary Odin field access such as `req.path`.

Important semantic note: keyword field access is not map lookup. It denotes
static named field selection and should be a compile-time error when used
against a type that does not support that field.

### Threading

Field-heavy code should compose naturally with `->`:

```clojure
(-> req :path)
(-> req :method method-name)
```

This expands in the usual Clojure style:

```clojure
(-> req :method method-name)
;; => (method-name (:method req))
```

### Control flow

Loops and cleanup remain explicit statements/forms:

```clojure
(for (< i 10)
  (fmt.println i))

(each [x xs]
  (fmt.println x))

(defer (free thing))
```

The current direction is:

- `for` for condition-controlled loops
- `each` for iteration over collections/ranges

Counted loops should be written explicitly with surrounding bindings and
mutation:

```clojure
(let [i 0]
  (for (< i 10)
    (fmt.println i)
    (set! i (+ i 1))))
```

### Higher-order procedures

Higher-order procedures are supported because Odin procedure values are
first-class. OdinL should expose that directly, but honestly:

- anonymous procedures are non-capturing
- any callback that needs runtime context must receive that context explicitly

The intended surface style can still be familiar:

```clojure
(map job-to-be-done xs)
(filter useful? xs)
(remove archived? xs)
(reduce combine init xs)
(map-indexed attach-index xs)
(keep maybe-useful xs)
(concat xs ys)
(merge defaults overrides)
(reverse xs)
(shuffle pick xs)
(shuffle! pick xs)
(split-at 2 xs)
(partition 2 xs)
(partition-all 3 xs)
(zipmap names ages)
(index-by key-fn xs)
(frequencies xs)
(keys m)
(vals m)
(range 10)
(repeat 3 "odin")
(repeatedly 3 make-value)
(iterate 4 step initial)
(take 10 xs)
(drop 2 xs)
(first xs)
(second xs)
(last xs)
(nth xs 2)
(rest xs)
(empty? xs)
(find ready? xs)
(some? archived? xs)
(every? valid? xs)
(->> users
     (filter :verified)
     (map :name))
```

These are now core eager helpers that lower to generated generic Odin
procedures in the same output file. Keywords used as callbacks in these helpers
lower to generated field-specific helper procedures; they are shorthand for
field access, not a general callable keyword/map-lookup abstraction. The broader
collection-processing model is still intentionally not locked down yet. In
particular, OdinL should not prematurely commit to:

- `*-into` helper families
- seq semantics
- lazy semantics
- transducer semantics without a dedicated design pass

For now, explicit `for` / `each` loops remain the baseline collection
processing model, and higher-order procedures are supported as a capability
rather than a frozen standard library design.

Anonymous procedures use `proc` as an expression form:

```clojure
(map (proc [x: int] -> int
       (+ x 1))
     xs
     allocator)
```

Because Odin only has non-capturing lambda procedures, OdinL should not pretend
to support Clojure-style closure capture unless it later grows a deliberate
closure-lowering model.

This means the following should not be assumed to work implicitly:

```clojure
(let [threshold 10]
  (filter (proc [x: int] -> bool
            (> x threshold))
          xs
          allocator))
```

Instead, callbacks that need extra state should use explicit context arguments:

```clojure
(proc greater-than? [threshold: int, x: int] -> bool
  (> x threshold))

(filter-with greater-than? threshold xs allocator)
```

This keeps the source language close to Clojure in feel while staying honest
about Odin's no-capturing-closures model.

`into`, transducers, and collection-building conventions are better treated as a
separate future design project once the core language, procedure types, and
allocation model are more settled.

See `docs/SEQUENCES.md` for the current sequence helper roadmap. The short
version is: helpers should be eager, Odin-shaped, and explicit about whether
they return slice views or owned dynamic arrays.

### File-backed development values

OdinL supports the first small piece of a disk-backed iterative workflow with
thin `core:os` forms:

```clojure
(import os "core:os")

(spit "tmp/users.json" text)
(let [[data err] (slurp "tmp/users.json")]
  (if (!= err nil)
    0
    (do
      (defer (delete data))
      (len data))))
```

`spit` lowers to `os.write_entire_file(path, data)` and returns `os.Error`.
`slurp` lowers to `os.read_entire_file(path, context.allocator)` and returns
owned `[]byte` plus `os.Error`. The caller must delete the bytes when keeping
the value local, or return them to transfer ownership.

## Literals and Construction

The current direction is:

- numbers, strings, booleans, and `nil` where Odin allows them
- vectors for ordered literal data
- braces with keywords for named field initialization
- constructor-style typed struct creation

### Struct construction

Prefer constructor syntax over `(as Type ...)`:

```clojure
(Request {
  :method .Get
  :path "/users"
  :query ""
  :params ["42"]
})
```

This lowers naturally to an Odin struct literal.

The same constructor style should apply to named union values:

```clojure
(Value {:i 123})
(Value {:s "hello"})
```

Exactly one variant should be supplied for tagged-union construction.

This should remain the only blessed union-construction surface in v0.1.

Shorthand alternatives such as:

```clojure
(Value :i 123)
```

should not be added yet. Keeping union and struct construction on one brace-form
rule is simpler and more predictable.

### General typed construction

The language still needs a generic way to construct typed composite values that
do not have a named nominal constructor shape.

Current draft direction:

- named nominal types can be constructed directly: `(Request {...})`
- anonymous composite types should use an explicit constructor form such as
  `(new []int [1 2 3])`

Examples:

```clojure
(new []int [1 2 3])
(new [4]int [1 2 3 4])
(new map[string]int {"a" 1 "b" 2})
(new []string [])
(new map[string]int {})
```

This keeps construction explicit without forcing every typed literal through a
general `(as Type ...)` form. It also avoids requiring arbitrary type syntax to
act as the head of an invocation form in v0.1.

`make` should remain available for Odin runtime/allocator-backed construction
rather than being replaced by surface sugar:

```clojure
(make [dynamic]Route allocator)
(make map[string]int allocator)
```

The intended split is:

- named nominal constructor call for structs/unions
- `new` for typed literal construction
- `make` for Odin runtime/allocator-backed construction

### Composite literal discipline

Composite literals should remain typed or type-directed. The language should not
pretend that vectors and maps denote universal runtime collection types in the
Clojure sense.

Examples:

```clojure
(Request {
  :method .Get
  :path "/ping"
  :query ""
  :params []
})
```

Support for slice, array, map, and union construction syntax is still open and
should be designed with Odin lowering in mind, not by blindly importing
Clojure's collection semantics.

Bare collection literals should not be relied upon without explicit type context
in v0.1. In particular, empty literals should stay typed:

```clojure
(new []int [])
(new map[string]int {})
```

## Union Use in v0.1

Although `union` declarations and construction are part of the core language,
their ergonomic use remains intentionally limited in v0.1.

The recommended stance is:

- allow union declaration
- allow union construction
- defer pleasant payload inspection/destructuring to future `match`
- use raw Odin escape hatches where union-heavy logic would otherwise force
  premature syntax design

Example construction:

```clojure
(union Value {
  :i int
  :s string
})

(let [a (Value {:i 123})
      b (Value {:s "hello"})]
  ...)
```

For code that needs richer variant handling before `match` exists, explicit
escape hatches are acceptable:

```clojure
(odin "/* union-heavy handling here until match exists */")
```

This is intentionally conservative. A partial extraction API is more likely to
be regretted than missed.

## Type Syntax

Types should stay visually close to Odin:

- `int`
- `string`
- `bool`
- `^Person`
- `[]int`
- `[4]int`
- `[dynamic]Route`
- `map[string]int`
- qualified types such as `runtime.Allocator`

The guiding rule is that type syntax should be readable in a Lisp file without
trying to redesign Odin's type model.

Procedure types themselves are part of the core language because higher-order
procedures depend on them.

### Procedure types

The current draft is to use `proc` in type position too:

```clojure
proc [x: int] -> bool
proc [x: int, y: int] -> int
proc [url: URL, key: string] -> [val: string, ok: bool]
```

That means higher-order procedures can look like:

```clojure
(proc find-index [xs: []int, pred: proc [x: int] -> bool] -> int
  ...)
```

This keeps procedure type syntax close to Odin while still fitting naturally
inside parameter annotations.

The anonymous procedure literal form stays:

```clojure
(proc [x: int] -> int
  (+ x 1))
```

This reuses the same signature shape in expression and type position, which is
useful for readability and parser simplicity.

### Deferred type features

These stay deferred until the core language is stable:

- polymorphism and parametric types beyond what lowers trivially
- richer inline type expressions
- procedure calling-convention annotations in source syntax
- implicit coercion rules beyond what Odin already makes obvious

## Planned Supported Subset

OdinL should not attempt to support all of Odin. The language should only cover
the parts that are common, mechanically lowerable, and worth having in Lisp
surface syntax.

### Expected core support

- `package`, `import`, `const`, `struct`, `enum`, `union`, `proc`
- local bindings with `let`
- `do`, `if`, `when`, `cond`
- `set!`, `return`, `defer`
- `for`, `each`
- field access, keyed lookup, threading
- named type construction and generic `new`
- procedure values and higher-order procedures
- raw `odin` escape hatch

### Implemented direct Odin conveniences

The compiler also currently supports a few mechanically lowered forms that were
not part of the original expected-core list:

- `(in? collection key)`, composed with `(not ...)` for absence checks
- `(break)` and `(continue)`
- directive expression wrappers such as `(#force_inline query-iter (& q))`

These are intentionally small Odin conveniences, not new semantic layers.

### Likely later support

- a language-level `match`
- `or_*`-style propagation sugar, likely as macros first
- a minimal surface for common attributes/directives if one proves obviously better than raw escape hatches
- variadic procedures
- procedure groups
- richer map/slice/array literal conveniences

### Probably escape-hatch only for a while

- foreign blocks and complicated linkage forms
- exotic calling conventions
- compile-time metaprogramming details
- less common Odin directives
- raw-union/C-layout-specialized declarations

The general rule should be:

- if the lowering is obvious and boring, add syntax
- if the feature is niche or semantically awkward, use `(odin "...")`
- if the feature implies a new semantic layer, defer it

`using` is currently outside the design target and should not receive dedicated
surface syntax.

## Attributes and Directives

Attributes and directives occur in real Odin code, but they do not yet justify a
rich OdinL surface.

Examples of the kind of thing this covers:

- `@(private)`
- `@(test)`
- `#optional_ok`
- `#force_inline`
- `#no_bounds_check`

The current design stance is:

- do not design a separate metadata language for v0.1
- keep the common cases in mind
- prefer the raw escape hatch until a truly obvious surface emerges

That means code like this remains acceptable for now:

```clojure
(odin "@(private)")
(proc route-add [router: ^Router, method: Method, route: Route]
  ...)

(odin "#force_inline")
(proc headers-count [h: Headers] -> int
  (len (:kv h)))

(let [entry (#force_inline query-iter (& q))]
  ...)
```

This is intentionally conservative. Attributes and directives are exactly the
kind of area where premature syntax design tends to create a second language.

If a minimal dedicated surface is added later, it should likely be limited to:

- declaration-leading attributes
- procedure-level directives
- common testing/visibility/inlining cases

and should lower transparently to ordinary Odin spellings.

## Documentation Comments

Odin's documentation tooling works from ordinary preceding comments, not from a
special runtime docstring construct. OdinL should align with that model.

That means the v0.1 documentation story should be simple:

- write ordinary comments directly above declarations
- lower them to ordinary Odin comments
- let Odin's existing documentation tooling consume the generated result

For now, this is the preferred style:

```clojure
// Adds two numbers.
(proc add [a: int, b: int] -> int
  (+ a b))
```

Likewise for types:

```clojure
// Incoming HTTP request.
(struct Request {
  :method Method
  :path string
})
```

This is intentionally boring and matches Odin's own documentation conventions
well.

### Deferred docs ideas

There are richer documentation ideas worth preserving for later exploration:

- inline declaration docstrings for short prose
- `doc-from`-style macros that read documentation from external files
- macro-assisted expansion of richer docs into ordinary Odin comments

Examples of the kind of thing worth considering later:

```clojure
(proc add
  "Adds two numbers."
  [a: int, b: int] -> int
  (+ a b))
```

```clojure
(proc complicated-thing
  (doc-from "docs/complicated-thing.md")
  [req: Request, allocator: runtime.Allocator] -> [res: Response, ok: bool]
  ...)
```

The `doc-from` idea is especially attractive for long-form documentation,
because it keeps source compact while still allowing the compiler or macro layer
to emit ordinary Odin comments for documentation tools.

These richer approaches should stay out of the v0.1 core until the macro model
and tooling story are more settled.

## Function Body Semantics

The current draft semantics are:

- non-void `proc` implicitly returns the final expression of the body
- `void` functions do not synthesize a return value
- explicit `return` remains available for early exits
- explicit `return` is always valid at the final site too
- multi-value return sites should remain explicit with `(return ...)`

Example:

```clojure
(proc answer [] -> int
  (let [x 20
        y 22]
    (+ x y)))
```

Conceptual Odin lowering:

```odin
answer :: proc() -> int {
    x := 20
    y := 22
    return x + y
}
```

This means all of the following are valid:

```clojure
(proc add [a: int, b: int] -> int
  (+ a b))

(proc add-explicit [a: int, b: int] -> int
  (return (+ a b)))
```

Early exits still require explicit `return`:

```clojure
(proc query-get [url: URL, key: string] -> [val: string, ok: bool]
  (when (== key "")
    (return "" false))
  (when ...
    (return value true))
  (return "" false))
```

Implicit final return is most natural for single-value expression results.
Multi-value return sites should prefer explicit `(return ...)` rather than
inventing tuple-packing surface syntax.

## Nil and Optional Conventions

OdinL should expose `nil` where Odin itself already has nil-capable values, but
`nil` should not become the language's universal success/failure convention.

The preferred core style is Odin-first explicit multi-return:

```clojure
(proc route-for [router: Router, method: Method] -> [route: Route, ok: bool]
  (let [[route ok] (get (:routes router) method)]
    (when (not ok)
      (return {} false))
    route))
```

Likewise for parsing:

```clojure
(proc request-path [s: string] -> [path: string, ok: bool]
  (let [[req ok] (parse-request s)]
    (when (not ok)
      (return "" false))
    (:path req)))
```

Direct `nil` checks remain appropriate where the underlying Odin value is
actually nil-capable:

```clojure
(proc print-user [p: ^User]
  (when (nil? p)
    (return))
  (fmt.println (:name (^ p))))
```

`nil?` lowers mechanically to an Odin nil comparison.

The intended stance is:

- `nil` exists where Odin already supports it
- `nil` is not the universal absence/failure protocol
- lookup and parse-style operations should prefer explicit multi-return
- OdinL should not invent a language-level Maybe/Result abstraction in v0.1

## Odin Interop

Interop should stay direct and boring.

Example source:

```clojure
(package demo)

(import "core:fmt")
(import strings "core:strings")
(import runtime "base:runtime")

(struct Person {
  :name string
  :age int
})

(proc birthday-message [p: Person, allocator: runtime.Allocator] -> string
  (strings.clone
    (fmt.tprintf "%s is now %d" (:name p) (+ (:age p) 1))
    allocator))

(proc print-person [p: Person]
  (fmt.println (fmt.tprintf "name=%s age=%d" (:name p) (:age p))))

(proc main []
  (let [p (Person {
            :name "Andreas"
            :age 42
          })]
    (print-person p)
    (fmt.println (birthday-message p (odin "context.allocator")))))
```

This should lower to ordinary Odin with:

- ordinary package/import declarations
- ordinary `proc` declarations
- ordinary field access
- direct calls into Odin libraries

## Evaluation Model

OdinL should support REPL-like development, but not a real interpreter.

The intended workflow is:

1. select one or more OdinL forms
2. lower them to scratch Odin
3. generate a temp runner package
4. invoke `odin run` or `odin check`
5. show result and optionally the generated Odin

Useful editor commands later:

- eval form at point
- eval top-level form
- eval buffer/package context
- macroexpand form
- show lowered Odin

The current CLI supports both inspection levels. `odinl macroexpand file.odinl
FORM` shows frontend expansion for macro-like forms such as `with-allocator`.
`odinl expand file.odinl FORM` emits the generated scratch Odin for the selected
form without running it.

The development model should become richer without becoming stateful. Tooling
may support tap-style inspection, rerun watches, and disk-backed saved values,
but those features should be explicit editor/CLI workflows around generated
Odin. A fresh process should be able to reproduce the same result from source
files and saved data files.

See `docs/TOOLING.md` for the current plan around tap-style inspection,
file-backed dev values, watches, and Emacs integration.

## Macros

Because OdinL is a Lisp, macros are likely an important later feature. But they
should arrive only after the core surface language is stable. They are now one
of the next major design areas after the direct compiler surface and eager
sequence library are in good shape.

The intended macro direction is:

- compile-time only
- source-to-source over OdinL forms and AST, not runtime metaprogramming
- no hidden interpreter world
- no requirement for a persistent dynamic environment
- expansion results should still lower to ordinary readable Odin

This means macros should be designed as a language frontend feature, not as a
runtime facility.

### `with-*` forms

Allocator-oriented `with-*` forms should behave like macro-expanded resource
scopes over ordinary Odin. `with-allocator` and `with-temp-allocator` are
supported directly and are inspectable through `odinl macroexpand` while the
general macro system is still pending.

The implemented shape is:

```clojure
(with-allocator [allocator some-allocator-expr]
  ...)
```

It lowers to the moral equivalent of:

```odin
{
    allocator := some_allocator_expr
    old_allocator := context.allocator
    context.allocator = allocator
    defer context.allocator = old_allocator
    ...
}
```

This is intentionally simple: the allocator value is visible, the old allocator
is restored by `defer`, and ordinary `delete` calls in the body run before the
allocator is restored.

For Odin's temporary allocator, use:

```clojure
(import runtime "base:runtime")

(with-temp-allocator [allocator]
  ...)
```

It lowers to the moral equivalent of:

```odin
{
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    allocator := context.temp_allocator
    old_allocator := context.allocator
    context.allocator = allocator
    defer context.allocator = old_allocator
    ...
}
```

The explicit `base:runtime` import is intentional for now. The generated Odin
uses Odin's normal temp allocator API directly instead of hiding it behind an
OdinL runtime. Owned values allocated in this scope must not escape it; the
compiler rejects obvious direct returns of owned helper results from
`with-temp-allocator`.

Other `with-*` forms are still attractive because they can expand into
combinations of existing core forms such as:

- `let`
- `defer`
- local `proc` calls
- explicit cleanup

That is a good sign: when a construct can be explained as macro-generated
surface sugar over a small explicit core, it does not need to be primitive.

The important constraint is that `with-*` forms should not smuggle in a hidden
runtime or fake dynamic binding model. If they exist, they should expand into
ordinary explicit Odin-shaped control flow.

For example, allocator helpers should keep ownership visible:

```clojure
(with-allocator [allocator context.temp_allocator]
  (let [buffer (make [dynamic]int)]
    (defer (delete buffer))
    ...))

(with-temp-allocator [allocator]
  (let [buffer (make [dynamic]int)]
    (defer (delete buffer))
    ...))

(with-arena [arena (make-arena allocator)]
  (work (:allocator arena)))
```

An arena helper should expand to the moral equivalent of:

```clojure
(let [arena (make-arena allocator)]
  (defer (destroy-arena arena))
  (work (:allocator arena)))
```

The exact Odin allocator API names should come from real Odin practice when the
macro is designed. The language rule is simpler: expansion may save typing, but
it must not hide allocation, cleanup, or which allocator is being passed.

Possible macro-friendly targets include:

- allocator setup and teardown
- temporary resource scopes
- repetitive check/cleanup patterns
- local contextual convenience over explicit arguments

## Deferred Features

These are intentionally deferred:

- macros as a user-facing feature
- pattern matching syntax over unions/enums beyond `switch`
- persistent collection semantics
- transducers and the final collection-processing abstraction
- protocols or multimethods
- laziness
- async
- ownership/borrow systems
- hidden runtime services
- generalized inference-heavy struct literal elision
- capturing closures

## Open Questions

The following design questions remain open and should be settled before too much
implementation accumulates:

1. Union construction syntax
2. Union handling beyond value-level `switch`
3. Whether `nil` is surfaced directly or only where required by Odin lowering
4. Slice/array/map literal syntax beyond struct construction
5. How much compile-time type inference is allowed for composite literals
6. Exact macro model and expansion phase boundaries
7. Surface spelling for `or_*` forms

## Immediate Implementation Consequences

The compiler should stay a small Odin-based source-to-source compiler. The
implementation should be staged where staging makes the compiler clearer, but
it should not build a deep compiler architecture merely to satisfy an abstract
model.

The intended pipeline is:

1. reader/token stream
2. CST forms with spans, comments, and reader metadata
3. parsed declaration-level AST
4. lightweight validation/lowering to Odin-shaped declarations
5. readable Odin emission

Future macro expansion and richer source mapping should fit into this pipeline,
but they do not require every expression to become a large typed node hierarchy
up front.

### Recommended Internal Representation Split

The implementation should keep the conceptual layers distinct:

- CST: close to source structure
- AST: declarations and any semantic expression nodes that have earned their
  keep
- IR: Odin-shaped lowered declarations and any lowered expression/block nodes
  that simplify emission or diagnostics

The split is pragmatic. It is fine for expression bodies to remain CST forms
while their lowering is simple and mechanical.

#### CST

The CST should preserve:

- exact form boundaries
- source spans
- comment locations
- ignored forms such as `#_`
- enough shape information to produce useful parse errors

The CST does not need to be clever. It should answer questions like:

- was this a list, vector, brace form, keyword, symbol, or literal?
- where did it come from in the source file?
- what comments preceded it?

That is enough to support docs, diagnostics, and later macro expansion without
committing too early to semantic interpretation.

#### AST

The AST should model OdinL constructs directly when doing so improves the
compiler. Declaration-level AST nodes are worth having immediately:

- `PackageDecl`
- `ImportDecl`
- `ConstDecl`
- `StructDecl`
- `EnumDecl`
- `UnionDecl`
- `ProcDecl`

Expression-level nodes should be introduced incrementally. Good candidates are
forms with real validation or lowering complexity:

- `LetExpr` / binding groups
- `SwitchExpr` / case clauses
- `ProcLiteral`
- composite literal pairs
- `ForStmt` and `EachStmt`

Generic calls, operators, simple field access, `get`, `new`, `make`, and raw
Odin snippets may continue to lower directly from CST while that keeps the code
simpler.

This is the layer where the compiler rejects malformed uses of otherwise valid
reader forms, but it should reject them with the lightest representation that
does the job.

#### IR

The IR should be Odin-shaped and intentionally boring.

It is not a generic optimizer IR. It exists only where it makes emission simple,
keeps diagnostics precise, or makes the boundary between OdinL semantics and
Odin output explicit.

Likely IR nodes that may earn their place over time:

- declarations
- blocks
- variable bindings
- assignments
- explicit returns
- explicit switches
- loops
- raw emitted snippets only where deliberately allowed

The key discipline is that when code reaches IR, any represented OdinL sugar
should already be gone. But trivial expression sugar does not need an IR node
until having one improves the compiler.

### Source spans and comments

Source spans should be carried from CST into AST and, where useful, into IR.

Minimum expectation:

- every significant parsed/lowered node has a span
- declarations keep attached leading doc comments
- parse/lower errors point back to `.odinl` locations, not just generated Odin

Comments themselves should not be preserved indiscriminately forever, but the
compiler should preserve enough information to:

- emit declaration docs into Odin comments
- support good diagnostics
- support future macro/source inspection tools

The CLI can emit a declaration-level source map with `--map`. The current map is
line-oriented and intentionally simple: generated start/end lines paired with
the original OdinL byte span. Finer-grained expression mapping can be layered on
later where editor tooling or diagnostics need it; it should not force a
wholesale expression IR first.

Implementation status: the compiler now names these stages explicitly. The
reader produces `CST_Form` / `CST_Top_Form`, parsing produces `AST_Program` and
`AST_Decl`, lowering produces `IR_Program` and `IR_Decl`, and emission consumes
IR. Expression bodies are intentionally still represented as CST forms inside
AST/IR declarations until a specific form benefits from a typed helper or node.

### First-pass Odin package layout

A reasonable initial Odin codebase layout would be:

```text
src/
  main.odin             ; CLI entry
  cli/
  reader/
  cst/
  ast/
  parse/
  expand/
  resolve/
  lower/
  ir/
  emit/
  diagnostics/
  support/
```

Or, if preferred, a flatter package layout with one package and many files. The
important separation is conceptual, not aesthetic.

Suggested responsibilities:

- `reader`: tokenization, comments, `#_`, raw textual spans
- `cst`: raw form data structures
- `parse`: CST to AST parsing/validation
- `ast`: declaration and earned semantic node definitions
- `expand`: future macro expansion and syntactic rewrites
- `resolve`: name and scope resolution, identifier lowering decisions
- `lower`: AST/CST-backed constructs to Odin-shaped IR where useful
- `ir`: lowered node definitions that simplify emission
- `emit`: readable Odin generation
- `diagnostics`: spans, error messages, source snippets

### Why keep CST in the pipeline?

The reader-level CST should remain a first-class representation because it buys
several practical things:

- easier handling of comments and docs
- better parse errors
- better macro expansion inputs later
- easier support for reader features like `#_`
- less pressure to prematurely interpret simple mechanical forms

The CST can stay small. It does not need to become a full syntax tree with
format-preserving ambitions.

The first implementation milestone should remain modest:

1. parse pure `.odinl`
2. support comments, `#_`, keywords, symbols, vectors, and brace forms
3. build a clean declaration AST
4. lower a small locked subset to readable Odin

That locked subset should start with:

- `package`, `import`, `const`, `struct`, `enum`, `union`, `proc`
- `let`, `do`, `if`, `when`, `cond`, `switch`
- `set!`, `return`, `defer`, `each`
- field access, `get`, threading
- named constructors, `new`, `make`
- flat multi-return destructuring
- raw `odin` escape hatch

Macros should be accounted for architecturally, but not implemented first.

### Bootstrapping

Building the compiler in Odin does not require a mystical bootstrap story.

The practical approach is:

- use ordinary Odin tooling to build the compiler binary
- keep test fixtures in `.odinl` plus expected `.odin`
- use `odineval` later for interactive workflows around the compiler's output

The important point is that OdinL should compile to Odin, while the OdinL
compiler itself is just an ordinary Odin program.
