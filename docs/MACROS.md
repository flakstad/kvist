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
  `(if ~condition
     (do)
     (do ~@body)))
```

Macro parameters receive source forms. A rest parameter is written as `& name`
at the end of the parameter vector and receives zero or more forms.

Use `defmacro-` for package-private macros.

Macros see source keywords such as `:else` and `:db/add` as source forms. That
is separate from ordinary runtime `keyword` values in Kvist code. Macro-time
`keyword?`, `keyword`, `name`, and `source` work on the source
representation; after expansion, ordinary lowering turns keyword literals in
emitted code into runtime `keyword` values.

For a small runnable version of this shape, see
[examples/language/macros.kvist](../examples/language/macros.kvist).

## Quoting

`'form` is reader syntax for `(quote form)`: it returns one form without
evaluating it in the macro evaluator.

Backtick is reader syntax for `quasiquote`. It builds a form while allowing
selected parts to be evaluated:

```clojure
`(defn ~fn-name [] -> int
   ~value)
```

`~` is reader syntax for `unquote` and inserts one evaluated macro value.
`~@` is reader syntax for `splice` and inserts zero or more forms into a
quasiquoted list, vector, or brace literal.

```clojure
`(do ~@body)
```

The long forms `quote`, `quasiquote`, `unquote`, and `splice` remain valid.
The reader syntax is the preferred spelling for macro code.
Kvist backtick is simple quasiquote sugar; it does not auto-qualify symbols or
create Clojure-style auto-gensyms.

## Returning Forms

Most expression macros return one form. Top-level DSL macros often return
multiple forms with `forms`:

```clojure
(defmacro defentity [name fields]
  (let [make-name (symbol (str "make-" (name name)))]
    (forms
      `(defstruct ~name ~fields)
      `(defn ~make-name [] -> ~name
         (~name {})))))
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
(set? x)
(symbol? x)
(keyword? x)
(string? x)
(number? x)
```

`keyword?` here means "is this source form spelled like `:name`?", not "does
this runtime expression have type `keyword`?".

More specific literal classifiers, such as integer, float, boolean, or nil
checks, should be local macro helpers over `source`, `number?`, `symbol?`, and
ordinary string predicates.
Field selector predicates should use the same local-helper style:

```clojure
(defmacro- field-selector? [form]
  (and (symbol? form)
       (> (count (source form)) 1)
       (= (slice (source form) 0 1) ".")))
```

Field-place decomposition should also be local macro source. For example,
`assoc`-style macros can split `user.profile.name` into target `user` and
selector `.profile.name` with private helpers over `source`, `count`, `slice`,
and `symbol`; this is ordinary source code, not evaluator knowledge.

Sequence helpers for form collections:

```clojure
(first xs)
(rest xs)
(nth xs i)
(count xs)
(contains? xs value)
(slice xs start)
(slice xs start end)
(concat xs ys ...)
(not value)
(and a b ...)
(or a b ...)
(parse-int text) ;; int or nil
```

Small form-sequence transforms can be written as ordinary recursive macros when
macro code needs to inspect or rewrite source lists:

```clojure
(defmacro source-map [f #form values]
  (if (= (count values) 0)
    (forms)
    (concat
      (forms (f (first values)))
      (source-map f (rest values)))))

(defmacro source-filter [pred #form values]
  (if (= (count values) 0)
    (forms)
    (let [head (first values)
          tail (source-filter pred (rest values))]
      (if (pred head)
        (concat (forms head) tail)
        tail))))
```

These are macro-time operations over source forms, not runtime `kvist:arr`
helpers. `pred` and `f` are unary macro-time function names such as `symbol?`,
`keyword?`, `source`, `name`, `text`, or a unary user macro. The evaluator
supports calling a macro-time symbol parameter in head position, so `(pred x)`
resolves to the symbol passed for `pred`. Write folds the same way, as ordinary
recursive macros over `first`, `rest`, and `count`; the evaluator does not
provide separate `map`, `filter`, or `reduce` helpers.

Constructors and text helpers:

```clojure
(list a b c)
(vector a b c)
(brace key value)
(symbol "make-Point")
(keyword "else")
(name .field)       ;; "field"
(name :else)        ;; "else"
(name pkg.member)   ;; "member" for rewritten source-package symbols
(text form-or-value)
(source :db/add)    ;; ":db/add"
(str "prefix-" (name sym))
(gensym "tmp")
(subst template names values)
```

Use `source` when the original token spelling is data, such as EDN-style
keywords in DSLs. `name` and `text` normalize symbols and keywords. When a
macro receives a source form whose package-qualified symbol was rewritten for
emission, `name` reports the original member name rather than the generated
implementation symbol, so package DSLs do not need generated-name checks.
`parse-int` returns an integer on success and `nil` on failure, so `0`
remains a valid truthy parsed result in macro conditionals.

Use `subst` for template-style source replacement. `names` and `values`
are source-form lists of the same length.

Use `keyword` when a macro needs to emit a keyword literal back into
ordinary Kvist code:

```clojure
(defmacro else-branch []
  (keyword "else"))
```

Macro-time helpers intentionally cover only source forms and simple scalar
values. If a helper operates on runtime arrays, maps, sets, or owned strings,
use the ordinary package helper in runtime Kvist code instead.

Use `error` for macro validation failures:

```clojure
(if (field-selector? field)
  field
  (error "expected a field selector such as .name"))
```

Errors raised while expanding macros include the macro expansion context.

## Compile-Time Files

`kvist.read-file` is available to macros and resolves relative paths against the
source file being compiled:

```clojure
(defmacro def-template []
  (let [text (kvist.read-file "template.html")]
    `(def template: string ~text)))
```

Use this for small source assets or generated constants. Runtime file work
belongs in ordinary Kvist code such as `io.read`.

## Hygiene

Kvist macros are explicit source rewriting, not a hygienic macro system. Use
`gensym` for generated locals that must not collide with user code:

```clojure
(defmacro once [expr]
  (let [tmp (gensym "value")]
    `(let [~tmp ~expr]
       ~tmp)))
```

Package-qualified symbols and generated symbols are emitted exactly as source
forms, then go through normal Kvist package and name lowering.

When generating typed declarations, the `:` belongs to the generated name
symbol:

```clojure
(let [typed-name (symbol (str (name const-name) ":"))]
  `(def ~typed-name string "value"))
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
- [kvist-lang/html](https://github.com/kvist-lang/html/blob/main/html.kvist) - an external package built from public macro facilities
  package with form inspection, validation, and generated rendering code
