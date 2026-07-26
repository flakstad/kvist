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
kvist frontend-check file.kvist
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

`kvist frontend-check` runs dependency loading, macro expansion, parsing,
lowering, ownership/known-type analysis, emission, warnings, and source-map
construction without invoking Odin. It uses the same content-addressed frontend
result cache as `check`; `check` remains the authoritative Odin-backed gate.

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

`build`, `check`, `run`, and `test` emit a small root Odin unit plus one
generated Odin package per reachable Kvist source package. The shared runtime
helpers are emitted once in a generated support package. When `--generated`
names `build/app.odin`, the package tree is written below
`build/app.odin.packages/`.

`kvist compile app.kvist -o build/app.odin --packages` exposes the same layout
for inspection without invoking Odin. With `--map build/app.map`, the root map
is written to that path and package maps are written below
`build/app.map.packages/`. Without `--packages`, `compile` retains its
single-file/stdout behavior.

The complete generated package graph is cached in the `compile-packages/`
subdirectory. Entries are content-addressed by the Kvist compiler binary and
every reachable `.kvist` or package-sidecar `.odin` source file, so editing a
direct or transitive dependency creates a new entry automatically. Each package
entry retains its Odin, source map, coded warnings, and generated-package
dependencies, so a warm command reports and remaps diagnostics exactly like a
cold command. Each entry is a bounded directory containing a compact metadata
manifest and plain root/artifact Odin files; the 64 least-recently-used graph
entries are retained.

Package frontend artifacts are retained separately below `package-frontend/`.
On a graph-cache miss, Kvist reuses an artifact when its local sources and the
inferred interfaces of its recorded direct dependencies are unchanged. A
body-only edit therefore re-emits the changed package while preserving stable
dependency packages. Interface changes invalidate the changed package's actual
dependants without evicting unrelated package artifacts. The four most recently
used compiler namespaces are retained, with up to 512 entries in each.

Dependency fingerprints are retained separately in `fingerprints/`. A manifest
records the resolved graph, per-file content hashes, and file/package-directory
metadata. When source metadata is unchanged, Kvist verifies those inputs
without rereading their contents. The compiler binary itself is always checked
by content: size and modification time are not a sufficient identity for a
rebuilt executable. Package frontend namespaces use that same compiler-content
identity. A changed file, added or removed package file, changed sidecar, or
changed compiler invalidates the corresponding cache entry. The 256 most
recently used fingerprint manifests are retained.

Use the cache transparency commands when investigating a build:

```sh
kvist check app.kvist --explain-cache
kvist cache inspect
kvist cache clear app.kvist
kvist cache clear
```

`--explain-cache` prints the key, entry, selected input, transitive inputs, and
hit or miss reason. `cache clear INPUT` removes the current content-addressed
entry for that input; bare `cache clear` removes compile entries and dependency
fingerprint manifests. Set
`KVIST_NO_COMPILE_CACHE=1` to force a fresh translation. The `compile` command
itself remains uncached because it writes user-selected Odin and map outputs.

## Phase Timings

Use `--timings` with `compile`, `build`, `check`, `run`, `test`, or `eval` to
print an opt-in timing summary to stderr. Use `--timings-json PATH` for a stable,
versioned machine-readable report without changing normal stdout:

```sh
kvist check app.kvist --timings
kvist build app.kvist --timings-json build/timings.json
kvist run app.kvist --timings --timings-json build/run-timings.json
```

Reports include dependency discovery, cache fingerprint and I/O, generated
output preparation, the Odin process, normalized Odin parse/type-check/codegen/
link phases when the installed Odin exports them, and executable runtime for
`run`. Fingerprint reports also identify manifest hits and the number of files
whose hashes were reused or recomputed. Cache-hit reports omit frontend detail
because no frontend work ran.

The frontend categories follow boundaries that exist in the compiler today:
reading/resolution, macro expansion, post-expansion resolution, AST parsing,
lowering, analysis, Odin emission, and source-map construction. Timing reports
are also written for failed frontend or Odin commands. Reload/watch commands do
not accept timing flags because they require repeated event reports rather than
one command summary.

For structured development data, use explicit source-level helpers such as
`io.write`, `io.read`, `json.write`, and `json.read-as` so format and ownership
stay visible in Kvist code.
