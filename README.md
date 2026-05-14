# odinl

An experiment in writing Odin with a small Clojure/Lisp-shaped syntax: Odin in
parens, not Clojure on Odin.

This is intentionally a source-to-source translator, not a new runtime or a
new semantic layer. The goal is:

- keep Odin semantics
- write paren-shaped source for editing comfort
- emit boring, readable `.odin`
- use `odin check` as the real validator

## Plan

The first milestone is a tiny translator that is pleasant enough for small
files:

- one `.odinl` file emits one `.odin` file
- `.odinl` files may mix raw Odin and marked Lisp-Odin islands
- forms map mechanically to Odin constructs
- generated Odin stays readable and debuggable
- Odin remains responsible for type checking, semantics, and diagnostics
- raw `(odin "...")` escape hatches are available from the start

The non-goals are just as important:

- no Clojure data model
- no persistent collections
- no seq abstraction
- no runtime library unless Odin interop absolutely needs a helper
- no semantic gap between source and generated Odin

If this grows, it should grow by covering more Odin syntax directly: structs,
enums, unions, pointers, slices, arrays, `defer`, `using`, `when`, `or_return`,
allocators, attributes, procedures, packages, and imports. It should not grow
by inventing a new language on top of Odin.

## Example

```odin
package main

import "core:fmt"

#odinl
(proc main []
  (fmt.println "hello from odin-clj")
  (let x int 41)
  (fmt.println (+ x 1)))
#end
```

emits:

```odin
package main

import "core:fmt"

main :: proc() {
    fmt.println("hello from odin-clj")
    x: int = 41
    fmt.println(x + 1)
}
```

## Usage

```sh
python3 -m src.odin_clj examples/hello.odinl -o /tmp/hello.odin
odin check /tmp/hello.odin -file
```

If `-o` is omitted, generated Odin is written to stdout.

The current prototype still translates pure Lisp-Odin input. Mixed raw-Odin
plus `#odinl` islands, Odin-style `->` proc return syntax, and implicit final
returns are the intended next syntax step.

## File Model

The intended source extension is `.odinl`.

Normal `.odin` files should remain ordinary Odin and should not require this
translator. `.odinl` files are mixed files: raw Odin is copied through, while
Lisp-Odin islands are translated.

Example:

```odin
package main

import "core:fmt"

Point :: struct {
    x: int,
    y: int,
}

#odinl
(proc add [(a int) (b int)] -> int
  (+ a b))
#end

main :: proc() {
    fmt.println(add(1, 2))
}
```

The Odin compiler should only see generated `.odin` files. That keeps normal
Odin tooling honest while still allowing mixed source in `.odinl`.

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
form only works because `odin-clj` invented a hidden dynamic environment, that
is the wrong direction.

## Data Literals

Inline data literals are valuable for editing comfort, but they should lower to
Odin literals rather than introduce a Clojure data model.

Useful targets:

- vector/list-looking syntax for Odin array or slice literals
- map-looking syntax for Odin map literals when key/value types are explicit
- map-looking syntax for Odin struct literals when a struct type is explicit

Examples of the intended shape:

```clojure
^[]int [1 2 3]
^map[string]int {"a" 1 "b" 2}
^Person {:name "Andreas" :age 42}
```

These should lower to ordinary Odin constructs such as:

```odin
[]int{1, 2, 3}
map[string]int{"a" = 1, "b" = 2}
Person{name = "Andreas", age = 42}
```

The rule is: `[]` and `{}` are syntax for Odin literals, not universal
Clojure-style collections. Prefer explicit type hints over guessing.

The `^type` syntax is compile-time lowering guidance for `odinl`; it is not
Clojure metadata. It says "emit this literal as this Odin type".

## Target Forms

- raw Odin outside `#odinl` / `#end` islands
- `(proc name [(arg type) ...] -> return-type body...)`
- `(proc name [(arg type) ...] body...)`
- `(let name type expr)` -> `name: type = expr`
- `(let name expr)` -> `name := expr`
- `(const name type expr)` -> `name: type : expr`
- `(const name expr)` -> `name :: expr`
- `(set! place expr)` -> `place = expr`
- final expression in a non-void proc emits `return <expr>`
- `(if test then else)`
- `(when test body...)`
- `(for [init test post] body...)`
- `(for-in name collection body...)`
- `(block body...)`
- `(odin "...")` raw Odin escape hatch
- `^Type form` type hint for typed literal lowering
- calls: `(foo a b)` -> `foo(a, b)`
- operators: `(+ a b)`, `(<= i 10)`, `(and a b)`, etc. emit infix

This is deliberately incomplete. Add only forms that map cleanly to Odin.

The current implementation also accepts the original pure Lisp-Odin bootstrap
forms such as `(package main)`, `(import "core:fmt")`, and
`(proc main [] void ...)` while the `.odinl` file model is being built.

## Design Rules

- Prefer transparent lowering over clever abstraction.
- Keep generated Odin idiomatic enough to read and edit.
- Use Odin syntax and names for types.
- Add forms only when their Odin output is obvious.
- Prefer an explicit raw Odin escape hatch over guessing.
- Treat `odin check` as the source of truth.
