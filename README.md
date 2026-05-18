# odinl

An experiment in writing Odin with a small Clojure/Lisp-shaped syntax: Odin in
parens, not Clojure on Odin.

The current language draft is [LANGUAGE.md](LANGUAGE.md).

This is intentionally a source-to-source translator, not a new runtime or a
new semantic layer. The goal is:

- keep Odin semantics
- write paren-shaped source for editing comfort
- emit boring, readable `.odin`
- use `odin check` as the real validator

## Plan

The first milestone is a small Odin compiler/transpiler that is pleasant enough
for small pure `.odinl` files:

- one `.odinl` file emits one `.odin` file
- `.odinl` files use OdinL forms rather than mixed raw Odin top-level text
- forms map mechanically to Odin constructs
- generated Odin stays readable and debuggable
- Odin remains responsible for type checking, semantics, and diagnostics
- raw `(odin "...")` escape hatches are available when explicit interop is
  clearer than a dedicated surface form

The non-goals are just as important:

- no Clojure data model
- no persistent collections
- no seq abstraction
- no runtime library unless Odin interop absolutely needs a helper
- no semantic gap between source and generated Odin

If this grows, it should grow by covering more Odin syntax directly where the
lowering remains obvious: structs, enums, unions, pointers, slices, arrays,
`defer`, `when`, procedures, packages, and imports. It should not grow by
inventing a new language on top of Odin.

## Example

```odin
(package main)
(import "core:fmt")

(proc add [a: int, b: int] -> int
  (+ a b))

(proc main []
  (fmt.println (add 20 22)))
```

emits:

```odin
package main

import "core:fmt"

add :: proc(a: int, b: int) -> int {
    return a + b
}

main :: proc() {
    fmt.println(add(20, 22))
}
```

## Usage

```sh
odin build cmd/odinl
./odinl examples/hello.odinl -o /tmp/hello.odin
odin check /tmp/hello.odin -file
```

If `-o` is omitted, generated Odin is written to stdout.
Pass `--map /tmp/hello.map` to also write a declaration-level source map:

```sh
./odinl examples/hello.odinl -o /tmp/hello.odin --map /tmp/hello.map
```

Run the executable examples through OdinL and then `odin check` with:

```sh
./scripts/check_examples.sh
```

Run CLI and Emacs-tooling integration checks with:

```sh
./scripts/test_tooling.sh
```

Generate a scratch runner for one selected form with:

```sh
./odinl eval examples/higher-order.odinl '(reduce add 0 (new []int [1 2 3]))'
```

The CLI can also invoke Odin for generated files directly:

```sh
./odinl check examples/hello.odinl
./odinl run examples/hello.odinl
```

The examples cover control flow, collection literals, procedure values,
map/filter/reduce-style higher-order helpers, pointer/raw interop,
source-level procedure directives, named returns, and flat multi-return
destructuring.

The compiler implementation is in Odin under `src/odinl`; the CLI entry point
is `cmd/odinl/main.odin`.

Tooling notes for the post-compiler Emacs/eval work are in
[docs/TOOLING.md](docs/TOOLING.md).
Emacs support is in [emacs/odinl-mode.el](emacs/odinl-mode.el) and
[emacs/odinl-eval.el](emacs/odinl-eval.el).

## File Model

The intended source extension is `.odinl`.

Normal `.odin` files should remain ordinary Odin and should not require this
translator. For v0.1, `.odinl` files are pure OdinL source. Raw Odin is
available through explicit `(odin "...")` escape hatches rather than implicit
passthrough.

Example:

```odin
(package main)
(import "core:fmt")

(struct Point {
  :x int
  :y int
})

(proc add [a: int, b: int] -> int
  (+ a b))

(proc main []
  (fmt.println (add 1 2)))
```

The Odin compiler should only see generated `.odin` files. That keeps normal
Odin tooling honest while OdinL remains a source-to-source layer.

## Syntax Shape

The syntax should earn its keep. Merely moving parens around is not enough.
Forms should make editing more Lisp-like where that has real value.

`let` should be Clojure-like: a scoped expression with bindings, not just a
renamed Odin declaration.

```clojure
(let [x 20
      y 22]
  (+ x y))
```

Inside a proc with a return type, the final expression should return
implicitly:

```clojure
(proc answer [] -> int
  (let [x 20
        y 22]
    (+ x y)))
```

emits:

```odin
answer :: proc() -> int {
    x := 20
    y := 22
    return x + y
}
```

## REPL-Like Development

Odin does not have a Lisp-style stateful REPL, but `odinl` can still aim for
a useful eval-selection workflow.

The idea is to make editor tooling that takes one selected form, generates a
temporary Odin file around it, runs `odin run`, and prints the result. This is
not an interpreter and not a persistent runtime. It is source generation plus
Odin's normal compiler.

Possible levels:

- expression eval: wrap one expression in a generated `main` and print it
- file-context eval: include package imports, constants, types, and procedures
  from the current file before running the selected form
- package eval: compile the current package plus a generated scratch entry point
- watch/eval loop: keep the temp-file generation and `odin run` invocation fast
  enough to feel interactive from Emacs

The constraint is important: eval should preserve Odin semantics exactly. If a
form only works because `odinl` invented a hidden dynamic environment, that
is the wrong direction.

## Relationship to odineval

`odineval` can be a useful base for OdinL tooling, but not for the OdinL
language layer itself.

The parts that should transfer well are execution and editor workflow:

- package and project detection
- temporary workspace generation
- internal package eval by copying a package and injecting a scratch runner
- Emacs result display, inline overlays, popup buffers, and build/check/test
  commands
- generated-code inspection and compiler failure handling

The parts that should remain OdinL-specific are:

- `.odinl` parsing
- OdinL-to-Odin lowering
- source mapping from `.odinl` locations to generated `.odin` locations
- syntax decisions around `let`, literals, proc forms, implicit returns, and
  raw Odin escape hatches

The likely architecture, if this project moves forward, is:

```text
odinl
  parser/lowering: .odinl -> .odin
  basic execution: compile/check/run/eval generated Odin

odineval
  reference implementation and inspiration for richer Odin eval workflows

shared later
  package discovery, temp workspace, command runner, Emacs result display
```

The current `odinl` CLI already owns the basic eval/check/run loop so editor
tooling can call one tool. `odineval` remains useful as a design reference for
larger package-aware workflows and polished editor interaction.

Do not merge the projects prematurely. `odineval` is useful because it makes
ordinary Odin more interactive. OdinL is a syntax experiment. Keeping them
separate avoids contaminating a practical tool with speculative syntax work.

## Data Literals

Inline data literals are valuable for editing comfort, but they should lower to
Odin literals rather than introduce a Clojure data model.

Useful targets:

- vector/list-looking syntax for Odin array or slice literals
- map-looking syntax for Odin map literals when key/value types are explicit
- map-looking syntax for Odin struct literals when a struct type is explicit

Examples of the intended shape:

```clojure
(new []int [1 2 3])
(new map[string]int {"a" 1 "b" 2})
(Person {:name "Andreas" :age 42})
```

These should lower to ordinary Odin constructs such as:

```odin
[]int{1, 2, 3}
map[string]int{"a" = 1, "b" = 2}
Person{name = "Andreas", age = 42}
```

The rule is: `[]` and `{}` are syntax for Odin literals, not universal
Clojure-style collections. Prefer explicit type ascription over guessing.

Do not use Clojure-style `^type` hints for this. In Odin, `^` already means
pointer, so using it for type hints would make the surface language harder to
read.

Use named constructors for nominal types and `new` for anonymous typed
composite literals.

## Odin Feature Sketches

These examples are design sketches. They are here to make the proposed surface
syntax concrete before the implementation commits too hard.

Common top-level Odin should usually stay raw because Odin's syntax is already
compact and readable:

```odin
package http

import "base:runtime"
import "core:net"
import http "../odin-http/"

Requestline_Error :: enum {
    None,
    Method_Not_Implemented,
    Not_Enough_Fields,
    Invalid_Version_Format,
}

Requestline :: struct {
    method: Method,
    target: union {
        string,
        URL,
    },
    version: Version,
}
```

The Lisp layer should focus first on procedure bodies and expression-heavy code.

Struct literals:

```clojure
Person :: struct {
    name: string,
    age: int,
}

(proc make-person [] -> Person
  (as Person {:name "Andreas"
              :age 42}))
```

Maps, dynamic arrays, compound literals, and calls:

```clojure
(proc route-get [(router ^Router) (pattern string) (handler Handler)]
  (route-add
    router
    .Get
    (as Route {:handler handler
               :pattern (strings.concatenate
                          (as []string ["^" pattern "$"])
                          router.allocator)})))
```

emits Odin-shaped code like:

```odin
route_get :: proc(router: ^Router, pattern: string, handler: Handler) {
    route_add(
        router,
        .Get,
        Route{handler = handler, pattern = strings.concatenate([]string{"^", pattern, "$"}, router.allocator)},
    )
}
```

Slices, loops, and mutation:

```clojure
(proc sum [(xs []int)] -> int
  (let [total 0]
    (for-in x xs
      (set! total (+ total x)))
    total))
```

Named and multi-value returns:

```clojure
(proc query-get [(url URL) (key string)] -> (val string, ok bool) #optional_ok
  (let [q url.query]
    (for-in entry (#force_inline query-iter (& q))
      (when (== entry.key key)
        (return entry.value true)))))
```

This is one place where explicit `return` remains useful. Implicit final return
is for the common final-expression case, not a ban on early returns.

`or_return` should probably stay as an Odin postfix operator:

```clojure
(proc decoded [(url URL) (key string) (allocator runtime.Allocator)] -> (val string, ok bool)
  (let [s (or-return (query-get url key))]
    (net.percent-decode s allocator)))
```

or, if postfix forms prove clearer:

```clojure
(let [s (query-get url key or-return)]
  ...)
```

This syntax is unsettled. The important point is that `or_return` is a core Odin
control-flow feature and should not be hidden behind a fake exception/result
abstraction.

Pointers should keep Odin's spelling:

```clojure
(proc bump [(x ^int)]
  (set! (^ x) (+ (^ x) 1)))
```

Address-of also needs a readable spelling:

```clojure
(headers-init (& r.headers) allocator)
```

Switch:

```clojure
(proc method-string [(m Method)] -> string #no_bounds_check
  (switch m
    .Get "GET"
    .Post "POST"
    .Delete "DELETE"
    :else ""))
```

Type switches and partial switches need to preserve Odin's syntax closely:

```clojure
(switch-in t rline.target
  string (io.write-string w t)
  URL    (request-path-write w t))

(#partial switch mode
  .Flush
  (do
    (assert (not rw.ended))
    (write-chunk b (slice rw.buf))))
```

Anonymous procs and callbacks:

```clojure
(http.route-get
  (& router)
  "/users/(%w+)/comments/(%d+)"
  (http.handler
    (proc [(req ^http.Request) (res ^http.Response)]
      (http.respond-plain
        res
        (fmt.tprintf "user %s, comment: %s"
                     (get req.url_params 0)
                     (get req.url_params 1))))))
```

Generated Odin should remain a normal anonymous proc passed to `http.handler`.

Attributes and directives should attach to the following form without forcing
everything into parens:

```clojure
@(private)
(proc route-add [(router ^Router) (method Method) (route Route)]
  (when (not (in? router.routes method))
    (set! (get router.routes method)
          (make [dynamic]Route router.allocator)))
  (append (& (get router.routes method)) route))

(proc headers-count [(h Headers)] -> int #force_inline
  (len h._kv))

(let [entry (#force_inline query-iter (& q))]
  ...)
```

Some attributes/directives may be better left as raw Odin until the syntax is
obvious.

`defer` and conditional defer:

```clojure
(proc header-parse [(headers ^Headers) (line string) (allocator runtime.Allocator)] -> (key string, ok bool)
  (let [value (strings.trim-space (slice line (+ colon 1)))
        key   (sanitize-key (^ headers) (slice line 0 colon))]
    (defer
      (when (not ok)
        (delete key allocator)
        (set! key "")))
    ...))
```

Conditionals as expressions when useful:

```clojure
(proc classify [(n int)] -> string
  (if (< n 0)
    "negative"
    (if (== n 0)
      "zero"
      "positive")))
```

Raw Odin should remain available directly in `.odinl`:

```odin
Foreign_Handle :: distinct rawptr

@(link_name = "foreign_call")
foreign_call :: proc(handle: Foreign_Handle) ---

(proc call [(handle Foreign_Handle)]
  (foreign_call handle))
```

## Target Forms

- `(package name)`, `(import "path")`, `(import alias "path")`
- `(const name expr)` -> `name :: expr`
- `(const name type expr)` -> `name: type : expr`
- `(struct Name {:field Type ...})`
- `(enum Name [A B C])` and `(enum Name {:A 1 :B 2})`
- `(union Name {:variant Type ...})`
- `(proc name [arg: type, ...] -> return-type body...)`
- top-level and statement `(odin "...")` raw escape hatches
- `(let [binding value ...] body...)` scoped expression/block
- `(set! place expr)` -> `place = expr`
- final expression in a non-void proc emits `return <expr>`
- `(if test then else)`
- `(when test body...)`
- `(for test body...)`
- `(each [name collection] body...)`
- `(do body...)`
- `(new Type literal)` typed composite literals
- `(make Type args...)` runtime/allocator-backed construction
- `(map f xs)`, `(filter pred xs)`, and `(reduce f init xs)` core eager helpers
- `(:field value)`, `(get value key)`, `(-> value steps...)`, and `(->> value steps...)`
- `(^ ptr)` and `(& place)`
- numbers, booleans, `nil`, and `(nil? value)`
- calls: `(foo a b)` -> `foo(a, b)`
- operators: `(+ a b)`, `(<= i 10)`, `(and a b)`, etc. emit infix

Current pragmatic Odin conveniences beyond the original core target include
`(in? collection key)`, `(break)`, `(continue)`, and directive expression
wrappers like `(#force_inline call arg)`.

This is deliberately incomplete. Add only forms that map cleanly to Odin.

## Design Rules

- Prefer transparent lowering over clever abstraction.
- Keep generated Odin idiomatic enough to read and edit.
- Use Odin syntax and names for types.
- Add forms only when their Odin output is obvious.
- Prefer an explicit raw Odin escape hatch over guessing.
- Treat `odin check` as the source of truth.
