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
kvist build file.kvist --out dist/app
kvist check file.kvist
kvist run file.kvist
kvist test file-or-dir.kvist
kvist test file.kvist --names test_one,test_two
kvist test file.kvist --track-memory
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

`kvist build` invokes Odin and writes the final executable when `--out` is
provided. The generated Odin file stays temporary unless `--generated` is used
for inspection.

## Package Resolution

`kvist:*` imports resolve shipped packages independently of the current working
directory. Lookup order is:

- `KVIST_ROOT`, when explicitly set to a root containing `core/core.kvist`.
- the parent of an installed `bin/kvist`, with packages directly under that
  root.
- `src/kvist` beside a compiler binary built at the source checkout root.

`kvist root` prints the selected root. Resolution does not probe the current
directory or importing repository.

This lets an installed `kvist` binary work from application repositories without
being launched from the Kvist source tree.
`macroexpand` shows frontend macro expansion before Odin lowering. See
[MACROS.md](MACROS.md) for the macro authoring surface. See
[LIVE-DEVELOPMENT.md](LIVE-DEVELOPMENT.md) for how scratch evaluation fits into
the broader live-development workflow alongside resident reload sessions.

`kvist test --names ...` runs selected tests from a file. Use it when you want a
tighter feedback loop than the full test file.

`kvist test --track-memory` enables Odin's test allocator accounting. It is
off by default because third-party libraries and process-lifetime caches can
otherwise turn ordinary package tests into ownership audits.

## Symbol And Editor Queries

Symbol commands print tab-separated rows so editors and shell tools can consume
the same output:

```sh
kvist lookup examples/collections/log-source.kvist log-lines
kvist complete examples/collections/log-source.kvist log
kvist xref examples/collections/log-source.kvist log-lines
```

The first two commands include the shared header plus matching symbol rows, for
example:

```text
kind	name	line	column	detail	signature	doc	file
iterator	log-lines	23	10		(log-lines [lines: []string] -> Log_Source :yield string)		examples/collections/log-source.kvist
```

`doc` renders the same data for humans:

```sh
kvist doc examples/collections/log-source.kvist log-lines
```

```text
iterator log-lines
(log-lines [lines: []string] -> Log_Source :yield string)
examples/collections/log-source.kvist:23
```

Package queries use the same row shape:

```sh
kvist imported-symbols examples/collections/sequences.kvist
kvist package-symbols kvist:arr arr
```

Use `imported-symbols` for the packages visible from one file and
`package-symbols` when an editor wants to inspect a package before it is
imported.

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

`build`, `check`, `run`, and `test` also keep emitted Odin in the
`compile/` subdirectory. Entries are content-addressed by the Kvist compiler
binary and every reachable `.kvist` or package-sidecar `.odin` source file, so
editing a direct or transitive dependency creates a new entry automatically.
Each entry includes emitted Odin, source maps, and coded warnings, so a warm
command reports and remaps diagnostics exactly like a cold command.

Use the cache transparency commands when investigating a build:

```sh
kvist check app.kvist --explain-cache
kvist cache inspect
kvist cache clear app.kvist
kvist cache clear
```

`--explain-cache` prints the key, entry, selected input, transitive inputs, and
hit or miss reason. `cache clear INPUT` removes the current content-addressed
entry for that input; bare `cache clear` removes the compile cache. Set
`KVIST_NO_COMPILE_CACHE=1` to force a fresh translation. The `compile` command
itself remains uncached because it writes user-selected Odin and map outputs.

For structured development data, use explicit source-level helpers such as
`io.write`, `io.read`, `json.write`, and `json.read-as` so format and ownership
stay visible in Kvist code.
