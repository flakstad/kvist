# HTML

`kvist:html` is a small HTML renderer for building markup directly from Kvist
code or simple templates. It gives you two main paths:

- Hiccup-style vectors for pages built in Kvist code.
- Template strings or files with `{{name}}` placeholders.

Both return owned strings. If you bind the result locally, delete it when you
are done.

## Hiccup-Style Rendering

Import the package and pass a vector tree to `html.render`:

```clojure
(import html "kvist:html")

(let [page (html.render
             [div {class "panel"}
              [h1 "Status"]
              [p "Ready <ok>"]]) :defer]
  (println page))
```

String text and string attributes are HTML-escaped. Integers, floats, and bools
render as text values. Boolean attributes render as a bare attribute when true
and disappear when false:

```clojure
(html.render
  [section {hidden false data-count 3}
   [p true]
   [p 42]])
```

Use `[<> ...]` for a fragment with no wrapper element:

```clojure
(html.render
  [div
   [<> [h2 "One"] [h2 "Two"]]])
```

## Expressions

Attributes and children can use ordinary Kvist expressions:

```clojure
(let [title "Dashboard"
      ready? true]
  (html.render
    [section {data-state (if ready? "ready" "waiting")}
     [h1 title]
     (if ready? "Live" "Paused")]))
```

`nil` omits a child or attribute. `when` can be used for conditional output:

```clojure
(html.render
  [div {data-archived (when archived? "true")}
   (when archived?
     [p "Archived"])])
```

Use strings for HTML attribute and child text. Keywords are rejected here; they
are syntax markers in Kvist, not HTML values.

## Loops

Use `html.for` inside render trees when the page needs repeated children:

```clojure
(import arr "kvist:arr")
(import html "kvist:html")

(let [ids (arr.range 1 4) :defer
      page (html.render
             [ul
              (html.for [id ids]
                [li id])]) :defer]
  (println page))
```

`html.for` is compile-time rendering structure. It emits ordinary looping code
into the renderer; it is not a lazy sequence.

## Templates

For boring string templates, use `html.render` with a template string and a
brace literal of replacements:

```clojure
(html.render "<p>{{name}}</p>" {name "Ada"})
```

`html.render-file` reads the template file at macro expansion time and embeds
the template contents:

```clojure
(html.render-file "html-template.html" {name "Bob"})
```

This is handy for small static templates. It is not a runtime file watcher; if
the file changes, rebuild.

## Ownership

`html.render` and `html.render-file` return owned strings:

```clojure
(let [page (html.render [p "hello"]) :defer]
  (println page))
```

If the rendered string is returned to the caller, ownership follows the normal
Kvist rules.

## Examples

- [`examples/web/html-demo.kvist`](../examples/web/html-demo.kvist) - vector
  rendering and `html.for`.
- [`examples/web/html-interpolation.kvist`](../examples/web/html-interpolation.kvist) -
  expressions, `if`, `when`, fragments, and `nil`.
- [`examples/web/html-values.kvist`](../examples/web/html-values.kvist) -
  typed scalar values.
- [`examples/web/html-render-file.kvist`](../examples/web/html-render-file.kvist) -
  compile-time template file rendering.
