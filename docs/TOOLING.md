# Kvist Tooling

Kvist tooling is built around source generation plus Odin execution. The CLI
lowers `.kvist` source to Odin, invokes Odin when requested, and maps diagnostics
back to Kvist source spans where the compiler has source-map information. The
loop is intentionally direct: write Kvist, ask Odin to check or run it, and use
the remapped diagnostics to get back to the source quickly.

## CLI Commands

Common commands:

```sh
kvist compile file.kvist -o file.odin
kvist build file.kvist
kvist check file.kvist
kvist run file.kvist
kvist test file-or-dir.kvist
kvist test file.kvist --names test_one,test_two
kvist eval file.kvist '(form)'
kvist expand file.kvist '(form)'
kvist macroexpand file.kvist '(form)'
kvist doc file.kvist symbol
kvist lookup file.kvist symbol
kvist symbols file.kvist
kvist editor-symbols file.kvist identifier
kvist complete file.kvist prefix
kvist xref file.kvist symbol
kvist builtin-symbols
kvist imported-symbols file.kvist
kvist package-symbols kvist:arr arr
```

`kvist eval` and `kvist expand` generate scratch Odin with the surrounding file
context. `eval` runs the scratch program; `expand` prints the generated Odin.
`macroexpand` shows frontend macro expansion before Odin lowering. See
[MACROS.md](MACROS.md) for the macro authoring surface. See
[LIVE-DEVELOPMENT.md](LIVE-DEVELOPMENT.md) for how scratch evaluation fits into
the broader live-development workflow alongside resident reload sessions.

`kvist test --names ...` runs selected tests from a file. Use it when you want a
tighter feedback loop than the full test file.

## Source Maps And Diagnostics

`compile --map path` writes a line-oriented source map. Declaration mappings are
always available, and many body forms also carry narrower spans for bindings,
conditions, returns, assignment values, generated macro expansion, and eval
forms.

The CLI prints remapped diagnostics in a format suitable for editor
`compilation-mode` integration. Eval forms use an eval-origin marker so errors
in selected text can point at `file:<eval>:line:column`.

## Emacs Commands

The Emacs integration shells out to the `kvist` CLI. It provides:

- eval form / region / top-level form
- check form or current buffer
- expand selected form to generated Odin
- macroexpand selected form
- show documentation, lookup, completion, xref, and symbol output
- list builtin, imported, and package symbols
- save eval stdout to the Kvist cache
- list, open, and remove cached eval outputs

Kvist source uses Clojure-like 2-space indentation. Generated Odin remains
ordinary Odin with the repository's Odin formatting style.

## Tap And Cache

`tap>` is the expression-friendly inspection helper:

```clojure
(tap> value)
(tap> "label" value)
```

It prints through generated Odin and returns the original value. In threaded
pipelines it is ownership-transparent; owned intermediate cleanup still follows
the normal threaded `let` lowering rules.

The eval cache is text-oriented:

```sh
kvist eval file.kvist FORM --save NAME
kvist cache path NAME
kvist cache list
kvist cache rm NAME
```

The default cache directory is project-local `.kvist-cache`. Set
`KVIST_CACHE_DIR` for an isolated cache. Cache names may contain letters,
digits, `_`, `-`, and `.`.

For structured development data, use explicit source-level helpers such as
`io.write`, `io.read`, `json.write`, and `json.read-as` so format and ownership
stay visible in Kvist code.
