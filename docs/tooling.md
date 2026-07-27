# Tooling

The `kvist` CLI compiles Kvist source to Odin and maps Odin diagnostics back to
Kvist source where source-map information is available.

## Commands

```sh
kvist compile file.kvist -o file.odin
kvist build file.kvist --out dist/app
kvist check file.kvist
kvist frontend-check file.kvist
kvist run file.kvist
kvist test file.kvist
```

`compile` writes generated Odin. `build`, `check`, `run`, and `test` invoke
Odin. `frontend-check` stops before Odin and is useful for compiler diagnostics;
`check` is the authoritative validation command.

Test selection and memory tracking are optional:

```sh
kvist test file.kvist --names test_one,test_two
kvist test file.kvist --track-memory
```

## Evaluation And Expansion

These commands use the imports and declarations from a source file:

```sh
kvist eval file.kvist '(form)'
kvist expand file.kvist '(form)'
kvist macroexpand file.kvist '(form)'
```

`eval` compiles and runs the form. `expand` prints generated Odin.
`macroexpand` prints Kvist after macro expansion.

## Symbols

Human-readable documentation:

```sh
kvist doc file.kvist symbol
```

Editor-oriented queries:

```sh
kvist lookup file.kvist symbol
kvist complete file.kvist prefix
kvist xref file.kvist symbol
kvist symbols file.kvist
kvist imported-symbols file.kvist
kvist package-symbols kvist:arr arr
kvist builtin-symbols
```

Machine-oriented symbol commands print tab-separated rows with declaration
kind, name, location, signature, documentation, and source file.

## Packages

`kvist:*` imports resolve from:

1. `KVIST_ROOT`, when set;
2. the package root beside an installed `bin/kvist`;
3. `src/kvist` beside a compiler built in this repository.

```sh
kvist root
```

The compiler does not search the current application repository for shipped
packages.

## Generated Files And Source Maps

Use `--generated` to keep generated Odin from `build`, `check`, `run`, or
`test`. `compile --map path` writes a source map.

```sh
kvist compile app.kvist -o build/app.odin --packages
kvist compile app.kvist -o build/app.odin --map build/app.map
```

`--packages` writes the generated package tree as well as the root unit.

## Cache

The default cache is `.kvist-cache`. Set `KVIST_CACHE_DIR` to use another
location.

```sh
kvist check app.kvist --explain-cache
kvist cache inspect
kvist cache clear app.kvist
kvist cache clear
```

Set `KVIST_NO_COMPILE_CACHE=1` to force fresh translation.

Evaluation output can be saved separately:

```sh
kvist eval file.kvist FORM --save NAME
kvist cache list
kvist cache path NAME
kvist cache rm NAME
```

## Timings

```sh
kvist check app.kvist --timings
kvist build app.kvist --timings-json build/timings.json
```

Timing reports cover Kvist compilation, cache work, Odin phases, and program
runtime where applicable.

## Emacs

The Emacs mode provides evaluation, checking, expansion, documentation,
completion, and xref through the CLI. See [the Emacs guide](../emacs/README.md).
