# Kvist Macros

Kvist macros run before ordinary parsing and Odin emission. They transform
Kvist forms into Kvist forms. They do not run at program runtime, and they do
not introduce a dynamic runtime object model.

Use macros when the shape of the source is the important part:

- declaring several related forms from one compact declaration
- validating a small DSL before normal lowering
- generating repetitive, predictable Odin-shaped code
- adapting field selectors such as `.name` into specialized helpers
- reading small compile-time resources into generated declarations

Prefer ordinary functions when runtime values are enough.

Macros are excellent when syntax is the problem; prefer a function when runtime
values are enough.

## Basic Form

```clojure
(defmacro unless [condition & body]
  (quasiquote
    (if (unquote condition)
      (do)
      (do (splice body)))))
```

Macro parameters receive source forms. A rest parameter is written as `& name`
at the end of the parameter vector and receives zero or more forms.

Use `defmacro-` for package-private macros.

For a small runnable version of this shape, see
[examples/language/macros.kvist](../examples/language/macros.kvist).

## Quoting

`quote` returns one form without evaluating it in the macro evaluator.

`quasiquote` builds a form while allowing selected parts to be evaluated:

```clojure
(quasiquote
  (defn (unquote fn-name) [] -> int
    (unquote value)))
```

`unquote` inserts one evaluated macro value. `splice` inserts zero or more
forms into a quasiquoted list, vector, or brace literal.

```clojure
(quasiquote
  (do (splice body)))
```

## Returning Forms

Most expression macros return one form. Top-level DSL macros often return
multiple forms with `forms`:

```clojure
(defmacro defentity [name fields]
  (let [make-name (symbol (str "make-" (name name)))]
    (forms
      (quasiquote
        (defstruct (unquote name) (unquote fields)))
      (quasiquote
        (defn (unquote make-name) [] -> (unquote name)
          ((unquote name) {}))))))
```

`concat` also returns a sequence of forms by concatenating evaluated form
sequences.

## Form Inspection

The macro evaluator provides predicates for source shapes:

```clojure
(form? x)
(list? x)
(vector? x)
(brace? x)
(symbol? x)
(keyword? x)
(field-selector? x)
(string? x)
(number? x)
(int? x)
(float? x)
(bool? x)
(nil? x)
```

Sequence helpers for form collections:

```clojure
(first xs)
(rest xs)
(nth xs i)
(count xs)
(slice xs start)
(slice xs start end)
```

Constructors and text helpers:

```clojure
(list a b c)
(vector a b c)
(brace key value)
(symbol "make-Point")
(keyword "else")
(name .field)       ;; "field"
(name :else)        ;; "else"
(text form-or-value)
(str "prefix-" (name sym))
(gensym "tmp")
```

Use `error` for macro validation failures:

```clojure
(if (field-selector? field)
  ...
  (error "expected a field selector such as .name"))
```

Errors raised while expanding macros include the macro expansion context.

## Compile-Time IO

`io.read` is available to macros and resolves relative paths against the source
file being compiled:

```clojure
(defmacro def-template []
  (let [text (io.read "template.html")]
    (quasiquote
      (def template: string (unquote text)))))
```

Use this for small source assets or generated constants. Runtime file work
belongs in ordinary Kvist code.

## Hygiene

Kvist macros are explicit source rewriting, not a hygienic macro system. Use
`gensym` for generated locals that must not collide with user code:

```clojure
(defmacro once [expr]
  (let [tmp (gensym "value")]
    (quasiquote
      (let [(unquote tmp) (unquote expr)]
        (unquote tmp)))))
```

Package-qualified symbols and generated symbols are emitted exactly as source
forms, then go through normal Kvist package and name lowering.

When generating typed declarations, the `:` belongs to the generated name
symbol:

```clojure
(let [typed-name (symbol (str (name const-name) ":"))]
  (quasiquote
    (def (unquote typed-name) string "value")))
```

This expands to a normal typed declaration such as:

```clojure
(def Label: string "value")
```

## Inspecting Expansions

Use the CLI to inspect macro output before Odin lowering:

```sh
kvist macroexpand file.kvist '(some-macro arg)'
```

Use `kvist expand` to inspect the generated Odin after macro expansion and
ordinary lowering:

```sh
kvist expand file.kvist '(some-expression)'
```

Macro code should produce clear Kvist forms first; readable Odin follows from
that.

## Examples

- [examples/language/macros.kvist](../examples/language/macros.kvist) - small
  expression macro
- [examples/language/macro-dsl.kvist](../examples/language/macro-dsl.kvist) -
  macro that emits several top-level forms
- [examples/language/macro-messages.kvist](../examples/language/macro-messages.kvist) -
  declaration DSL with generated structs, union entries, and constructors
- [packages/html/html.kvist](../packages/html/html.kvist) - real shipped macro
  package with form inspection, validation, and generated rendering code
