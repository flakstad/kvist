# OdinL Tooling Plan

Tooling comes after the compiler reaches the language draft's core target. The
editor story should feel close to Clojure editing while keeping Odin as the
execution model.

## References

- `../cluck/emacs`: useful model for a light Clojure-like major mode derived
  from `clojure-mode`, with inline eval overlays and a small command set.
- `../odineval`: useful model for Odin eval by generating temporary Odin,
  invoking `odin run` / `odin check`, showing generated code, and integrating
  with Emacs result buffers.

Do not merge OdinL into `odineval` prematurely. Reuse the execution ideas and
possibly code structure, but keep OdinL parsing/lowering/source mapping in this
repo.

## Major Mode

The first Emacs target should be `odinl-mode` for `*.odinl` files.

It should be very close to `clojure-mode`:

- derive from `clojure-mode`
- use structural editing packages such as paredit or smartparens
- keep Lisp navigation commands working
- use Clojure-like indentation with 2 spaces in `.odinl`
- font-lock OdinL special forms, keywords, Odin directive symbols, and raw
  `(odin "...")` escape hatches
- provide indentation overrides for OdinL forms such as `proc`, `struct`,
  `enum`, `union`, `let`, `switch`, `cond`, `for`, and `each`

The compiler's Odin source remains 4-space indented. The OdinL source format is
separate and should read like Clojure.

## Eval Tooling

OdinL eval must remain source generation plus Odin execution, not an
interpreter.

Initial commands should mirror the useful `odineval` and `cluck` workflows:

- eval form at point inline
- eval selected region inline
- eval current top-level form
- check form at point without running
- run/check current generated buffer
- expand form at point into generated Odin for debugging
- clear inline results
- switch to result buffer

The eval path should be:

1. collect file context from the current `.odinl` buffer
2. lower OdinL to temporary Odin
3. inject a scratch `main` or scratch package runner when evaluating an
   expression/form
4. run `odin run` or `odin check` from the `odinl` CLI
5. map diagnostics back through OdinL source spans where possible
6. display results inline and in a result buffer

## Compiler Support Needed First

Before building the major mode deeply, the compiler should expose stable
tooling entry points:

- compile file to generated Odin
- compile with declaration source map
- check or run generated Odin with `odinl check` / `odinl run`
- evaluate a selected expression/form with surrounding file context using
  `odinl eval`
- inspect the generated scratch Odin for a selected form with `odinl expand`
- optionally write generated Odin for editor inspection with `--generated`

The current `--map` output is line-oriented. Declarations are still the fallback
mapping, but emitted body forms, binding assignments, conditions, loop
collections, return values, and assignment values carry narrower source spans
where the generated line has a clear OdinL origin. Internally, diagnostic
remapping also uses generated columns when Odin reports them. Eval forms carry
an origin marker, so compiler errors in selected eval text can be reported
against `file:<eval>:line:column` instead of the surrounding file.

The Emacs result buffer should treat remapped OdinL diagnostics as
`compilation-mode` output. That keeps errors clickable and lets ordinary Emacs
commands such as `next-error` / `M-g n` navigate back into `.odinl` source.

## Near-Term Language Tooling

After the core compiler is solid, the next language-level tooling target is the
macro system. Macros should be a frontend feature over OdinL forms, not a
runtime facility:

- expansion happens before ordinary lowering to Odin;
- macro expansion output must still be inspectable OdinL/Odin-shaped code;
- editor tooling should provide `macroexpand` for the form at point;
- `odinl macroexpand` is the frontend expansion view; it currently handles
  built-in macro-like forms such as `with-allocator` and
  `with-temp-allocator` and cleanup forms such as `with-delete`, while
  `odinl expand` remains the generated-Odin lowering preview;
- `odinl macroexpand file.odinl FORM --map output.map` writes a simple
  line-oriented expansion map so generated macroexpand lines can be related
  back to the original macro call, binding values, and body forms;
- diagnostics should keep enough source information to point through expansion
  where practical;
- macros must not introduce a hidden stateful REPL or dynamic runtime world.

The current implementation has a small compiler-defined macro registry rather
than user-defined macros. The registry is shared by `odinl macroexpand` and the
normal emitter so supported macro-like forms have one explicit classification
point. For now, normal compilation still lowers these forms directly where that
keeps ownership checks precise; a later expansion phase can move more of that
lowering into frontend form rewriting once diagnostics and ownership rules stay
equally clear. `odinl macroexpand` expands nested compiler-defined macro forms
inside ordinary wrapper forms and `with-*` bodies, so resource-scope previews
show the shape of stacked cleanup/resource helpers. Formatting of recursive
macroexpand output is still a preview format, not the final source formatter.

Good first macro candidates are resource-scope and repetition helpers that
clearly expand to existing forms, such as allocator setup/teardown,
`with-*`-style cleanup, and repetitive check/error propagation. `when-ok` is
the first explicit multi-return convenience macro: it expands `[value ok expr]`
to a destructuring `let` plus `when ok`.

## Data-Oriented Iteration

OdinL should support REPL-driven development without pretending to have a
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
(tap> :label value)
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
     (filter active?)
     (tap> :active)
     (map :name))
```

The step is ownership-transparent. A tapped owned final value remains owned by
the binding or caller. A tapped owned intermediate is still cleaned up by the
threaded `let` lowering before later steps run.

A richer tap sink can come later as an explicit CLI/editor option or ordinary
Odin value, not as ambient language state.

### Watches

Clojure atom watches are useful because they make changes visible. OdinL should
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

1. write a proc that downloads, parses, or computes data;
2. run it once from the editor;
3. save the result to disk;
4. load that saved value in later eval calls without repeating the expensive
   operation.

Initial support should stay boring:

```clojure
(spit "tmp/users.json" text)
(let [[data err] (slurp "tmp/users.json")]
  (if (!= err nil)
    0
    (do
      (defer (delete data))
      (len data))))
```

These forms are now intentionally thin wrappers over `core:os`; source files
must import it explicitly with `(import os "core:os")`. `(spit path data)`
lowers to `os.write_entire_file(path, data)` and returns `os.Error`. `(slurp
path)` lowers to `os.read_entire_file(path, context.allocator)` and returns
owned `[]byte` plus `os.Error`; callers delete the bytes or return them to
transfer ownership.

`odinl eval` runs generated scratch code from the source file's directory, so
relative dev paths such as `tmp/users.json` are stable across separate eval
processes. Odin's file-writing calls do not create parent directories; examples
that write under `tmp` should create that directory explicitly and treat the
returned error as ordinary program data.

Saving JSON can also stay boring:

```clojure
(import json "core:encoding/json")
(import os "core:os")

(let [[data marshal-err] (json.marshal user)]
  (if (!= marshal-err nil)
    false
    (do
      (defer (delete data))
      (== (spit "tmp/users.json" data) nil))))

(let [[data read-err] (slurp "tmp/users.json")]
  (if (!= read-err nil)
    false
    (do
      (defer (delete data))
      (let [user (User {})
            unmarshal-err (json.unmarshal data (& user))]
        (== unmarshal-err nil)))))
```

For structured data, continue to require explicit format and type decisions
rather than inventing a universal printer/reader. JSON is ordinary host
interop: source files import `core:encoding/json` and call `json.marshal` /
`json.unmarshal` explicitly. Odin's JSON unmarshal can allocate strings,
slices, dynamic arrays, and maps inside the destination value according to that
destination type, so callers still own any allocations inside a successfully
decoded value. For allocation-heavy decoded values, keep cleanup explicit in the
calling code.

These helpers should lean on Odin's existing core libraries:

- `core:os` for `os.read_entire_file` and `os.write_entire_file`;
- `core:encoding/json` for `json.marshal`, `json.unmarshal`, and JSON struct
  tags;
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
and edit it. CBOR is a reasonable later option for larger caches. Odin's custom
marshalers/unmarshalers should remain available for special types rather than
OdinL inventing a parallel serialization protocol.

### CLI Cache

The CLI has a small text cache for eval output:

```sh
odinl eval file.odinl FORM --save NAME
odinl cache path NAME
odinl cache list
odinl cache rm NAME
```

The default cache directory is project-local `.odinl-cache`, which is gitignored.
Set `ODINL_CACHE_DIR` when editor tooling or tests need an isolated cache. Cache
names are simple file names: letters, digits, `_`, `-`, and `.` only. `--save`
writes the exact stdout from a successful eval run to the named cache file and
still prints stdout normally.

This is intentionally text-oriented. For structured values, prefer explicit
`spit`, `slurp`, `json.marshal`, and `json.unmarshal` in OdinL source so
ownership and format choices stay visible.

The Emacs tooling exposes this through ordinary CLI calls:

- `odinl-save-form-result` (`C-c C-w`) evals a form and saves stdout with
  `odinl eval --save`;
- `odinl-cache-list` (`C-c C-l`) lists saved cache names;
- `odinl-cache-open` (`C-c C-o`) opens a saved cache file;
- `odinl-cache-rm` (`C-c C-d`) removes a saved cache file.

Useful future `odinl` commands or flags:

- `odinl eval file.odinl FORM --tap`
- `odinl watch file.odinl FORM`

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
  small OdinL library, and how to keep it explicit rather than part of compiler
  semantics.
- Disk cache layout: default cache directory, naming, invalidation, cleanup,
  file extensions, and whether cache metadata records source file, form, type,
  and timestamp.
- Formatter and indentation: Clojure-like 2-space `.odinl` formatting, separate
  from 4-space generated Odin.
- Source maps and diagnostics: expression-level spans, generated helper spans,
  macro expansion spans, and editor navigation from Odin errors back to OdinL.
- Package/workspace discovery: how `odinl eval`, `check`, `run`, and future
  watch commands find the right Odin package root and import context.
- Tooling protocol: whether Emacs calls CLI commands only, or whether a small
  long-lived helper process is useful for speed while still avoiding stateful
  language semantics.
- Example and ownership coverage: every new helper should have examples showing
  allocation, cleanup, and eval-friendly comment forms.
