# Kvist Tooling Plan

Tooling comes after the compiler reaches the language draft's core target. The
editor story should feel close to Clojure editing while keeping Odin as the
execution model.

## References

- `../cluck/emacs`: useful model for a light Clojure-like major mode derived
  from `clojure-mode`, with inline eval overlays and a small command set.
- `../probe`: useful model for Odin eval by generating temporary Odin,
  invoking `odin run` / `odin check`, showing generated code, and integrating
  with Emacs result buffers.

Do not merge Kvist into `probe` prematurely. Reuse the execution ideas and
possibly code structure, but keep Kvist parsing/lowering/source mapping in this
repo.

## Major Mode

The first Emacs target should be `kvist-mode` for `*.kvist` files.

It should be very close to `clojure-mode`:

- derive from `clojure-mode`
- use structural editing packages such as paredit or smartparens
- keep Lisp navigation commands working
- use Clojure-like indentation with 2 spaces in `.kvist`
- font-lock Kvist special forms, keywords, Odin directive symbols, and raw
  `(odin "...")` escape hatches
- provide indentation overrides for Kvist forms such as `defn`, `defstruct`,
  `defenum`, `defunion`, `fn`, `let`, `defvar`, `block`, `switch`,
  `cond`, and `for`

The compiler's Odin source remains 4-space indented. The Kvist source format is
separate and should read like Clojure.

## Eval Tooling

Kvist eval must remain source generation plus Odin execution, not an
interpreter.

Initial commands should mirror the useful `probe` and `cluck` workflows:

- eval form at point inline
- eval selected region inline
- eval current top-level form
- check form at point without running
- run/check current generated buffer
- expand form at point into generated Odin for debugging
- clear inline results
- switch to result buffer

The eval path should be:

1. collect file context from the current `.kvist` buffer
2. lower Kvist to temporary Odin
3. inject a scratch `main` or scratch package runner when evaluating an
   expression/form
4. run `odin run` or `odin check` from the `kvist` CLI
5. map diagnostics back through Kvist source spans where possible
6. display results inline and in a result buffer

## Compiler Support Needed First

Before building the major mode deeply, the compiler should expose stable
tooling entry points:

- compile file to generated Odin
- compile with declaration source map
- check or run generated Odin with `kvist check` / `kvist run`
- evaluate a selected expression/form with surrounding file context using
  `kvist eval`
- inspect the generated scratch Odin for a selected form with `kvist expand`
- optionally write generated Odin for editor inspection with `--generated`

The current `--map` output is line-oriented. Declarations are still the fallback
mapping, but emitted body forms, binding assignments, conditions, for
collections, return values, and assignment values carry narrower source spans
where the generated line has a clear Kvist origin. Internally, diagnostic
remapping also uses generated columns when Odin reports them. Eval forms carry
an origin marker, so compiler errors in selected eval text can be reported
against `file:<eval>:line:column` instead of the surrounding file.

The Emacs result buffer should treat remapped Kvist diagnostics as
`compilation-mode` output. That keeps errors clickable and lets ordinary Emacs
commands such as `next-error` / `M-g n` navigate back into `.kvist` source.

## Near-Term Language Tooling

After the core compiler is solid, the next language-level tooling target is the
macro system. Macros should be a frontend feature over Kvist forms, not a
runtime facility:

- expansion happens before ordinary lowering to Odin;
- macro expansion output must still be inspectable Kvist/Odin-shaped code;
- editor tooling should provide `macroexpand` for the form at point;
- `kvist macroexpand` is the frontend expansion view; it currently handles
  built-in macro-like forms such as `with-allocator` and
  `with-temp-allocator`, while
  `kvist expand` remains the generated-Odin lowering preview;
- `kvist macroexpand file.kvist FORM --map output.map` writes a simple
  line-oriented expansion map so generated macroexpand lines can be related
  back to the original macro call, binding values, and body forms;
- diagnostics should keep enough source information to point through expansion
  where practical;
- macros must not introduce a hidden stateful REPL or dynamic runtime world.

The current implementation has a small compiler-defined macro registry rather
than user-defined macros. The registry is shared by `kvist macroexpand` and the
normal emitter so supported macro-like forms have one explicit classification
point. For now, normal compilation still lowers these forms directly where that
keeps ownership checks precise; a later expansion phase can move more of that
lowering into frontend form rewriting once diagnostics and ownership rules stay
equally clear. `kvist macroexpand` expands nested compiler-defined macro forms
inside ordinary wrapper forms and `with-*` bodies, so resource-scope previews
show the shape of stacked cleanup/resource helpers. Formatting of recursive
macroexpand output is still a preview format, not the final source formatter.

Good first macro candidates are resource-scope and repetition helpers that
clearly expand to existing forms, such as allocator setup/teardown,
`with-*`-style cleanup, and repetitive check/error propagation. The initial
multi-return convenience macros are:

- `when-let` and `if-let` for `[value bool expr]`, expanding to multi-return
  `let` plus a direct boolean condition;
- `when-ok` and `if-ok` for `[value err expr]`, expanding to multi-return
  `let` plus `(= err {})`.

The bool/error distinction is intentional. Odin procs commonly report success
with either an explicit bool or a zero-valued error object, and Kvist keeps that
choice visible instead of inventing a general truthiness rule.

## Data-Oriented Iteration

Kvist should support REPL-driven development without pretending to have a
stateful Lisp REPL. The model is still: generate scratch Odin, run/check it, and
keep the useful artifacts.

Useful workflows to design:

- tap-style inspection, similar in spirit to Clojure `tap>`;
- watches for rerunning forms or files when inputs change;
- explicit save/load of dev data between eval calls;
- simple file helpers for text and bytes;
- editor commands to open the last generated Odin, stdout/stderr, saved value,
  or tapped value.

### Tap

A tap system should help inspect values during eval and normal runs without
changing program semantics. The initial spelling is:

```clojure
(tap> value)
(tap> "label" value)
```

This currently lowers through tiny generated helpers that print to stdout with
`fmt` and return the tapped value. Source files must import `core:fmt`
explicitly. That is intentionally modest: it works in normal runs and editor
evals, it is visible in the generated Odin, and it does not depend on a hidden
global tap registry.

In practice, `tap>` is the expression-friendly version of adding a temporary
print line: wrap a value, see it, and keep passing the same value onward. It is
especially useful inside a threaded pipeline or nested expression where adding a
separate statement would force a local binding just for inspection.

`tap>` also works as a `->` / `->>` thread step:

```clojure
(->> users
     (arr.filter active?)
     (tap> "active")
     (arr.map .name))
```

The step is ownership-transparent. A tapped owned final value remains owned by
the binding or caller. A tapped owned intermediate is still cleaned up by the
threaded `let` lowering before later steps run.

A richer tap sink can come later as an explicit CLI/editor option or ordinary
Odin value, not as ambient language state.

### Watches

Clojure atom watches are useful because they make changes visible. Kvist should
not copy atoms or dynamic vars, but the tooling can provide similar feedback:

- watch a source file or package and rerun a selected eval form;
- watch a saved data file and rerun a downstream form;
- optionally diff or replace inline results when output changes.

This is an editor/CLI workflow, not a hidden language runtime. A watch should be
described as "rerun this form when these files change", not "maintain live
mutable REPL state".

A future watch command should be explicit about what it reruns. It can be useful
for repeatedly checking a form, rerunning a saved-data transformation, or
refreshing inline eval output while editing. It should not silently manage a web
server lifecycle by default; explicit run/restart commands are clearer for that
kind of process.

### Disk-Backed Dev Values

The important iterative workflow is:

1. write a function that downloads, parses, or computes data;
2. run it once from the editor;
3. save the result to disk;
4. load that saved value in later eval calls without repeating the expensive
   operation.

Initial support should stay boring:

```clojure
(import io "kvist:io")

(io.write "tmp/users.json" text)
(let [[data err] (io.read "tmp/users.json")]
  (if (!= err nil)
    0
    (do
      (defer (delete data))
      (len data))))
```

These helpers are intentionally thin wrappers over `core:os`; source files
must import them explicitly with `(import io "kvist:io")`. `(io.write path
data)` lowers through `os.write_entire_file(path, data)` and returns
`os.Error`. `(io.read path)` lowers through
`os.read_entire_file(path, context.allocator)` and returns owned `[]byte` plus
`os.Error`; callers delete the bytes or return them to transfer ownership.

`kvist eval` runs generated scratch code from the source file's directory, so
relative dev paths such as `tmp/users.json` are stable across separate eval
processes. Odin's file-writing calls do not create parent directories; examples
that write under `tmp` should create that directory explicitly and treat the
returned error as ordinary program data.

Saving JSON can also stay boring:

```clojure
(import io "kvist:io")
(import json "kvist:json")

(let [[marshal-err write-err] (json.write "tmp/users.json" user)]
  (and (= marshal-err nil)
       (= write-err nil)))

(let [[user read-err unmarshal-err] (json.read-as User "tmp/users.json")]
  (and (= read-err nil)
       (= unmarshal-err nil)))
```

For structured data, continue to require explicit format and type decisions
rather than inventing a universal printer/reader. The shipped `kvist:json`
package keeps the surface narrow: `json.write` and `json.read-as`. Odin's JSON
unmarshal can allocate strings, slices, dynamic arrays, and maps inside the
destination value according to that destination type, so callers still own any
allocations inside a successfully decoded value. For allocation-heavy decoded
values, keep cleanup explicit in the calling code.

These helpers should lean on Odin's existing core libraries:

- `core:os` for `os.read_entire_file` and `os.write_entire_file`;
- `core:encoding/json` under the shipped `kvist:json` package;
- `core:encoding/cbor` as a later binary cache option when inspectability is
  less important than speed or size.

The intended lowering is ordinary Odin. A JSON save can marshal a value and
write the resulting bytes:

```odin
data, err := json.marshal(value)
defer delete(data)
if err == nil {
    err = os.write_entire_file(path, data)
}
```

A JSON load reads bytes and unmarshals into an explicitly requested type:

```odin
data, err := os.read_entire_file(path, context.allocator)
defer delete(data)

value: T
if err == nil {
    err = json.unmarshal(data, &value)
}
```

The design constraint is the important part: serialization should be explicit,
file-backed, and reproducible from a fresh process. The editor can make the
workflow feel REPL-like by remembering recent paths and commands, but the
compiled Odin should remain ordinary.

JSON should be the first supported structured format because users can inspect
and edit it. CBOR is a reasonable later option for larger caches. Raw Odin
marshalers/unmarshalers should remain available for special types rather than
Kvist inventing a parallel serialization protocol.

### CLI Cache

The CLI has a small text cache for eval output:

```sh
kvist eval file.kvist FORM --save NAME
kvist cache path NAME
kvist cache list
kvist cache rm NAME
```

The default cache directory is project-local `.kvist-cache`, which is gitignored.
Set `KVIST_CACHE_DIR` when editor tooling or tests need an isolated cache. Cache
names are simple file names: letters, digits, `_`, `-`, and `.` only. `--save`
writes the exact stdout from a successful eval run to the named cache file and
still prints stdout normally.

This is intentionally text-oriented. For structured values, prefer explicit
`io.write`, `io.read`, `json.write`, and `json.read-as` in Kvist source so
ownership and format choices stay visible.

The Emacs tooling exposes this through ordinary CLI calls:

- `kvist-save-form-result` (`C-c C-w`) evals a form and saves stdout with
  `kvist eval --save`;
- `kvist-cache-list` (`C-c C-l`) lists saved cache names;
- `kvist-cache-open` (`C-c C-o`) opens a saved cache file;
- `kvist-cache-rm` (`C-c C-d`) removes a saved cache file.

Useful future `kvist` commands or flags:

- `kvist eval file.kvist FORM --tap`
- `kvist watch file.kvist FORM`

The exact CLI can change, but it should keep the source of truth on disk so a
fresh process can reproduce the same development state.

## Planning Areas

These areas are worth planning explicitly before implementation becomes too
large:

- Macro expansion phase: CST vs AST input, hygiene expectations, macroexpand
  output, source spans, and error reporting through expansion.
- Tap registry: whether taps are configured through an explicit value, context,
  environment variables, or CLI/editor flags; supported sinks such as stdout,
  files, editor buffers, and sockets.
- Runtime reactive utilities: whether watch/cell/signal behavior belongs in a
  small Kvist library, and how to keep it explicit rather than part of compiler
  semantics.
- Disk cache layout: default cache directory, naming, invalidation, cleanup,
  file extensions, and whether cache metadata records source file, form, type,
  and timestamp.
- Formatter and indentation: Clojure-like 2-space `.kvist` formatting, separate
  from 4-space generated Odin.
- Source maps and diagnostics: expression-level spans, generated helper spans,
  macro expansion spans, and editor navigation from Odin errors back to Kvist.
- Package/workspace discovery: how `kvist eval`, `check`, `run`, and future
  watch commands find the right Odin package root and import context.
- Tooling protocol: whether Emacs calls CLI commands only, or whether a small
  long-lived helper process is useful for speed while still avoiding stateful
  language semantics.
- Example and ownership coverage: every new helper should have examples showing
  allocation, cleanup, and eval-friendly comment forms.
