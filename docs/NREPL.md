# nREPL Editor Adapter

Kvist provides an experimental nREPL compatibility layer for Calva, CIDER,
Conjure, and other clients that already speak nREPL. It exposes the native
Kvist REPL; it does not turn Kvist into Clojure or start a JVM.

## Start with the Right Context

The source argument is required and must describe the code you intend to work
on:

```sh
kvist nrepl path/to/app.kvist
```

The context file anchors the package graph, imports, compiler options, source
mapping, and symbol index used by every editor request. Do not start the server
with an unrelated example or empty file and then connect an editor to another
application. In particular, loading a real source file outside the active
package graph is rejected.

For an application, use its normal entry file or an ordinary development file
such as `dev/user.kvist` that imports the application graph. The latter can
also contain development-only helpers and fixtures. It is a convention, not a
special manifest format.

The adapter listens only on `127.0.0.1`, selects an available port, and writes
it to `.nrepl-port` in the current directory. The defaults can be changed with
`--port PORT`, `--port-file PATH`, or `--no-port-file`.

## Protocol Surface

The adapter supports the nREPL transport, bencode framing, request IDs,
UUID-shaped logical sessions, streaming output, and these operations:

- Session and discovery: `describe`, `clone`, `close`, and `ls-sessions`.
- Evaluation: `eval`, `load-file`, and `interrupt`.
- Tooling: `ns-list`, `completions`, `lookup`, `complete`, and `info`.
- CIDER aliases: `cider/complete` and `cider/info`.

`user` is a virtual namespace used to satisfy generic clients. Kvist has no
Clojure namespaces, and changing this value does not change evaluation.
Logical nREPL sessions share one native Kvist runtime, so definitions remain
visible when an editor creates separate evaluation and tooling sessions.

`load-file` ignores file-only `package`, `comment`, and `main` forms while
preserving source positions. A load from an absolute, existing path must be in
the package graph rooted at the server's context file.

Interrupt terminates arbitrary code in the active native worker. This is a
real interrupt, but it replaces the worker: definitions, retained values,
mutable REPL state, and `*1`/`*2`/`*3` history are cleared for every logical
nREPL session. The next evaluation starts in a fresh worker using the same
context file.

The adapter currently accepts one TCP client connection at a time. It does not
implement stdin, classpath or dependency operations, Clojure namespaces, test
middleware, macroexpansion middleware, refactoring middleware, debugging
middleware, or the complete `cider-nrepl` operation set. Unsupported
Clojure-specific editor commands therefore remain unsupported even though
connect, evaluation, completion, lookup, and interrupt work.

## Calva

Until Calva can activate its nREPL features for a separate Kvist language ID,
associate Kvist files with Clojure in the workspace settings:

```json
{
  "files.associations": {
    "*.kvist": "clojure"
  }
}
```

Start `kvist nrepl` from the project directory, then run **Calva: Connect to a
Running REPL Server in your Project** and choose **Generic**. Calva reads the
generated `.nrepl-port` file.

The unmodified Calva extension has been exercised in a real VS Code Extension
Host for connection, ordinary top-level and selection evaluation, complete
unsaved-buffer loading, completion, hover documentation, signature help,
definition lookup, last-result copying, diagnostics, and interrupt with
recovery. The relevant commands are **Calva: Evaluate Top Level Form
(defun)**, **Calva: Evaluate Current Form (or selection, if any)**, and
**Calva: Load/Evaluate Current File and its Requires/Dependencies**.

The file association is a transitional compatibility setting. Calva's
Clojure parser still controls structural editing, selection, and syntax-aware
commands, so Kvist constructs outside the shared Lisp subset can be parsed
incorrectly.

## CIDER

CIDER can connect with `M-x cider-connect-clj`; the adapter is classified as a
generic nREPL runtime. The repository's `kvist-mode` already owns `*.kvist`
files and derives from `clojure-mode`, so CIDER's minor mode can be enabled for
an experimental source workflow:

```elisp
(require 'kvist-mode)
(add-hook 'kvist-mode-hook #'cider-mode)
```

The pinned CIDER integration test covers a real connection, evaluation,
ordinary top-level form and region evaluation through CIDER's source commands,
complete unsaved-buffer loading, completion, info lookup, interrupt, and
evaluation after interrupt.

If `kvist-eval.el` is also loaded, its native keymap deliberately owns several
of the same keys. In particular, `C-c C-x` is
`kvist-eval-comment-form` and only operates inside `(comment ...)`; it is not a
CIDER nREPL command. Use `C-x C-e` or `M-x cider-eval-last-sexp` for CIDER
evaluation, and `M-x cider-load-buffer` for a CIDER whole-buffer load. Toggling
`M-x kvist-eval-mode` off exposes CIDER's conflicting standard bindings,
including `C-c C-k` for `cider-load-buffer`.

Many CIDER commands depend on unimplemented Clojure or `cider-nrepl`
middleware. The native [Kvist Emacs client](../emacs/README.md) remains the
complete Emacs integration for Kvist-specific debugging, live conditions,
inspection, generations, and attached applications. It uses its own native
REPL session; those features do not become CIDER features merely because both
minor modes are loaded.

## Conjure

Conjure can retain a real `kvist` filetype while routing its evaluations to
the Clojure nREPL transport client:

```lua
vim.filetype.add({ extension = { kvist = "kvist" } })
-- Add "kvist" to any other Conjure filetypes you use.
vim.g["conjure#filetypes"] = { "kvist" }
vim.g["conjure#filetype#kvist"] = "conjure.client.clojure.nrepl"
```

The pinned Conjure integration test covers its connection setup and preamble,
evaluation, file loading, completion, info lookup, interrupt, and evaluation
after interrupt.

## Language Mode Direction

`*.kvist` should not be permanently presented as Clojure. The long-term VS
Code design is a distinct `kvist` language ID with a Kvist grammar, brackets,
comments, indentation, and language tooling. Calva would then need a small
extension point or explicit Kvist document selector so its nREPL commands can
operate on that language ID.

A dedicated mode should use Kvist's own compiler frontend and tooling results
for semantic operations rather than fork a Clojure parser. Reusing Lisp
parenthesis navigation and indentation is still reasonable, just as the
current Emacs `kvist-mode` derives from `clojure-mode`. The staged direction is
therefore:

1. Keep the VS Code file association as an explicitly temporary way to use
   unmodified Calva.
2. Register a real `kvist` language mode for accurate syntax highlighting and
   file identity.
3. Let Calva opt into `kvist` documents for nREPL commands, while Kvist's own
   tooling supplies completion, documentation, definitions, and diagnostics
   where Clojure assumptions diverge.

Conjure already demonstrates the desired separation: a `kvist` language mode
can select its existing nREPL transport without claiming that the source is
Clojure.

## Reproducible Tests

```sh
./scripts/test_nrepl.sh
./scripts/test_calva_nrepl.sh
./scripts/test_cider_nrepl.sh
./scripts/test_conjure_nrepl.sh
```

The on-demand nREPL workflow runs the codec/helper and protocol tests on Linux
and Windows. The on-demand editor workflow runs Calva, CIDER, and Conjure as
separate Linux jobs against pinned client revisions; the Calva test uses a
pinned VS Code Extension Host. Local runs require the respective editor
toolchains and network access.
