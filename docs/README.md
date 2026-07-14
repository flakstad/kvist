# Kvist Docs

These docs map the current Kvist surface: the language, the shipped packages,
the tooling, and the ownership rules that matter in real programs.

Start here:

- [FALSE-FRIENDS.md](FALSE-FRIENDS.md) - Clojure/Lisp-looking forms whose
  Kvist semantics stay Odin-shaped
- [LANGUAGE.md](LANGUAGE.md) - core language reference
- [FUNCTIONAL-TRANSFORMS.md](FUNCTIONAL-TRANSFORMS.md) - fused data transforms with `into`, `transduce`, and `for`
- [TOOLING.md](TOOLING.md) - CLI and editor-facing tooling
- [SEQUENCES.md](SEQUENCES.md) - collection helpers and their ownership model
- [DATA.md](DATA.md) - first-class quoted data and managed runtime value design
- [PACKAGES.md](PACKAGES.md) - shipped `kvist:*` package index
- [TESTING.md](TESTING.md) - tests, assertions, fixtures, and table checks
- [MACROS.md](MACROS.md) - macro authoring
- [ARCHITECTURE.md](ARCHITECTURE.md) - compiler kernel and package boundary for contributors

Focused references:

- [PARALLEL.md](PARALLEL.md) - `kvist:parallel`
- [LIVE-DEVELOPMENT.md](LIVE-DEVELOPMENT.md) - resident reload and scratch eval workflows

Experimental notes live under `docs/experimental/`.

- [experimental/LISP-NATIVE.md](experimental/LISP-NATIVE.md) - staged plan for
  Data, EDN, runtime bindings, Syntax, REPL, and resident-console work

Optional official packages and their documentation are linked from
[PACKAGES.md](PACKAGES.md).
