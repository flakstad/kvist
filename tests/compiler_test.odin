package tests

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import kvist "../src/kvist"

repo_temp_test_path :: proc(name: string) -> (string, bool) {
    root, ok_root := kvist.repo_root_for_path(".")
    if !ok_root {
        return "", false
    }
    defer delete(root)
    path, join_err := os.join_path({root, name}, context.allocator)
    if join_err != nil {
        return "", false
    }
    return path, true
}

count_substring :: proc(text, needle: string) -> int {
    if len(needle) == 0 {
        return 0
    }
    count := 0
    offset := 0
    for offset < len(text) {
        idx := strings.index(text[offset:], needle)
        if idx < 0 {
            break
        }
        count += 1
        offset += idx + len(needle)
    }
    return count
}

@(test)
compile_hello_program :: proc(t: ^testing.T) {
    source := `(package main)
(import "core:fmt")

// Greets from Kvist.
(defstruct Greeting {
  message: string
})

(defn main []
  (let [g (Greeting {
            message: "hello from kvist"
          })]
    (fmt.println g.message)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import "core:fmt"

// Greets from Kvist.
Greeting :: struct {
    message: string,
}

main :: proc() {
    g := Greeting{message = "hello from kvist"}
    fmt.println(g.message)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_top_level_defn_decl_head :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (println "hello"))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import "core:fmt"

main :: proc() {
    fmt.println("hello")
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_defstruct_program :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Profile
  "Profile data."
  {name: string
   age: int
   active?: bool
   tags: set[string]
   scores: [dynamic]int
   home: Point})

(defstruct Point
  {x: float
   y: float})`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

// Profile data.
Profile :: struct {
    name: string,
    age: int,
    active_p: bool,
    tags: map[string]struct{},
    scores: [dynamic]int,
    home: Point,
}

Point :: struct {
    x: f64,
    y: f64,
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_all_examples :: proc(t: ^testing.T) {
    examples := [?]string{
        "examples/language/cluck-port-arrays.kvist",
        "examples/language/cluck-port-docs.kvist",
        "examples/language/cluck-port-maps-sets.kvist",
        "examples/language/cluck-port-multi-return.kvist",
        "examples/language/cluck-port-packages.kvist",
        "examples/language/cluck-port-records.kvist",
        "examples/language/cluck-port-loops.kvist",
        "examples/language/cluck-port-strings.kvist",
        "examples/language/cluck-port-struct-defaults.kvist",
        "examples/language/cluck-port-struct-introspection.kvist",
        "examples/language/cluck-port-struct-types.kvist",
        "examples/language/closures.kvist",
        "examples/language/control-flow.kvist",
        "examples/interop/core/core-concurrency.kvist",
        "examples/interop/core/core-container-queue.kvist",
        "examples/interop/core/core-encoding-formats.kvist",
        "examples/interop/core/core-math-linalg.kvist",
        "examples/interop/core/core-os-paths.kvist",
        "examples/interop/core/core-paths.kvist",
        "examples/interop/core/core-text-encoding.kvist",
        "examples/interop/core/core-time-slice.kvist",
        "examples/visual/constraint-cloth.kvist",
        "examples/language/data-literals.kvist",
        "examples/language/declarations.kvist",
        "examples/interop/core/dev-io.kvist",
        "examples/language/defstructs.kvist",
        "examples/interop/core/error-handling.kvist",
        "examples/visual/flocking-sim.kvist",
        "examples/web/http-client.kvist",
        "examples/web/http-server.kvist",
        "examples/web/http-session.kvist",
        "examples/web/http-sse.kvist",
        "examples/web/http-sse-live.kvist",
        "examples/web/http-datastar.kvist",
        "examples/web/http-datastar-live.kvist",
        "examples/language/hello.kvist",
        "examples/collections/higher-order.kvist",
        "examples/web/html-demo.kvist",
        "examples/web/html-interpolation.kvist",
        "examples/web/html-render.kvist",
        "examples/web/html-values.kvist",
        "examples/language/inline-literals.kvist",
        "examples/interop/interop-directives.kvist",
        "examples/language/local-declarations.kvist",
        "examples/language/multi-return-bindings.kvist",
        "examples/interop/core/matrix.kvist",
        "examples/visual/matrix-kinematics.kvist",
        "examples/interop/core/odin-types.kvist",
        "examples/language/pointers-and-raw.kvist",
        "examples/language/function-values.kvist",
        "examples/visual/reaction-diffusion.kvist",
        "examples/collections/sequence-helpers.kvist",
        "examples/collections/sequences.kvist",
        "examples/collections/sources.kvist",
        "examples/visual/spatial-hash-collisions.kvist",
        "examples/collections/tap.kvist",
        "examples/packages/testing.kvist",
        "examples/language/unions.kvist",
        "examples/collections/update.kvist",
        "examples/visual/wave-ripples.kvist",
        "examples/interop/vendor/vendor-raylib.kvist",
        "examples/interop/vendor/vendor-stb-easy-font.kvist",
    }

    for path in examples {
        result, err, ok := kvist.compile_path_with_map(path)
        testing.expect_value(t, ok, true)
        if !ok {
            testing.expect_value(t, err.message, "")
            continue
        }
        testing.expect_value(t, len(result.output) > 0, true)
        testing.expect_value(t, len(result.source_map) > 0, true)
        delete(result.output)
        delete(result.source_map)
        kvist.compile_warning_slice_delete(result.warnings)
    }
}

@(test)
compile_eval_path_rewrites_source_package_aliases :: proc(t: ^testing.T) {
    output, err, ok := kvist.compile_eval_path("examples/language/cluck-port-packages.kvist", "(math.sum-range 0 5)")
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "math__sum_range(0, 5)"), true)
}

@(test)
compile_eval_source_generates_scratch_main :: proc(t: ^testing.T) {
    source := `(package app)
(import "core:fmt")

(defn add [a: int, b: int] -> int
  (+ a b))

(defn main []
  (fmt.println "ordinary main"))`

    output, err, ok := kvist.compile_eval_source(source, "(add 20 22)")
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import "core:fmt"

add :: proc(a, b: int) -> int {
    return (a) + (b)
}

main :: proc() {
    fmt.println(add(20, 22))
}
`
    testing.expect_value(t, output, expected)
}

@(test)
symbols_source_indexes_top_level_forms :: proc(t: ^testing.T) {
    source := `(package main)
(import strings "core:strings")

/*
 * A user record.
 * Owned by caller.
 */
(defstruct User {
  name: string
  active: bool
})

(defenum Status [
  Active
  Archived
])

(defunion Value {
  i: int
  s: string
})

(def max-age: int 120)

// Returns true for active users.
// Used by sequence examples.
(defn active? [user: User] -> bool
  user.active)

(defsource active-users [users: []User] -> User
  (open-users users)
  :next next-user)`

    output, err, ok := kvist.symbols_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\n"), true)
    testing.expect_value(t, strings.contains(output, "import\tstrings\t2\t9\tcore:strings\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "struct\tUser\t8\t12\t\t(User {name: string active: bool})\tA user record.\\nOwned by caller.\n"), true)
    testing.expect_value(t, strings.contains(output, "field\tUser.name\t9\t3\tUser\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "enum\tStatus\t13\t10\t\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "variant\tStatus.Active\t14\t3\tStatus\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "union\tValue\t18\t11\t\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "variant\tValue.i\t19\t3\tValue\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "const\tmax-age\t23\t6\t\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "source\tactive-users\t30\t12\t\t(active-users [users: []User] -> User)\t\n"), true)
    testing.expect_value(t, strings.contains(output, "proc\tactive?\t27\t7\t\t(active? [user: User] -> bool)\tReturns true for active users.\\nUsed by sequence examples.\n"), true)
}

@(test)
symbols_source_indexes_defstruct_docstring :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Person
  "Primary profile."
  {name: string
   age: int})`

    output, err, ok := kvist.symbols_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "struct\tPerson\t3\t12\t\t(Person {name: string age: int})\tPrimary profile.\n"), true)
    testing.expect_value(t, strings.contains(output, "field\tPerson.name\t5\t4\tPerson\t\t\n"), true)
}

@(test)
symbols_source_indexes_defstate_as_struct :: proc(t: ^testing.T) {
    source := `(package main)

(defstate App_State
  {steps: int
   message: string}
  {run: run})`

    output, err, ok := kvist.symbols_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "struct\tApp_State\t3\t11\tstate\t(App_State {steps: int message: string})\t\n"), true)
    testing.expect_value(t, strings.contains(output, "field\tApp_State.steps\t4\t4\tApp_State\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "field\tApp_State.message\t5\t4\tApp_State\t\t\n"), true)
}

@(test)
symbols_source_indexes_defunion_and_defenum :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Status [
  Active
  Archived
])

(defunion Value {
  i: int
  s: string
})`

    output, err, ok := kvist.symbols_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "enum\tStatus\t3\t10\t\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "variant\tStatus.Active\t4\t3\tStatus\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "union\tValue\t8\t11\t\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "variant\tValue.i\t9\t3\tValue\t\t\n"), true)
}

@(test)
symbols_source_includes_proc_default_values_in_signatures :: proc(t: ^testing.T) {
    source := `(package main)

(defn greet [name: string, punctuation: string = "!", count: int = (+ 1 2)] -> string
  name)`

    output, err, ok := kvist.symbols_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "proc\tgreet\t3\t7\t\t(greet [name: string, punctuation: string = \"!\", count: int = (+ 1 2)] -> string)\t\n"), true)
}

@(test)
symbols_source_includes_dot_access_param_signatures :: proc(t: ^testing.T) {
    source := `(package main)

(import "core:fmt")

(defstruct Point {
  x: int
  y: int
})

(defn draw [point: Point] -> int
  (+ point.x point.y))`

    output, err, ok := kvist.symbols_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "(draw [point: Point] -> int)"), true)
}

@(test)
builtin_symbols_source_emits_signatures_and_docs :: proc(t: ^testing.T) {
    output := kvist.builtin_symbols_source()
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\n"), true)
    testing.expect_value(t, strings.contains(output, "\tprintln\t"), false)
    testing.expect_value(t, strings.contains(output, "\tdoc\t"), false)
    testing.expect_value(t, strings.contains(output, "\tor-else\t"), false)
    testing.expect_value(t, strings.contains(output, "\tupdate!\t"), false)
    testing.expect_value(t, strings.contains(output, "\twhen-let\t"), false)
    testing.expect_value(t, strings.contains(output, "\tif-let\t"), false)
    testing.expect_value(t, strings.contains(output, "\twhen-ok\t"), false)
    testing.expect_value(t, strings.contains(output, "\tif-ok\t"), false)
}

@(test)
package_symbols_source_supports_shipped_test_package :: proc(t: ^testing.T) {
    output, ok := kvist.package_symbols_source("kvist:test", "t")
    testing.expect_value(t, ok, true)
    if !ok {
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "macro\tt.deftest\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tt.is\t"), true)
}

@(test)
package_symbols_source_emits_core_update_bang_helper :: proc(t: ^testing.T) {
    output, ok := kvist.package_symbols_source("kvist:core", "core")
    testing.expect_value(t, ok, true)
    if !ok {
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "macro\tcore.update!\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.update\t"), false)
    testing.expect_value(t, strings.contains(output, "macro\tcore.assoc\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.when\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.cond\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.comment\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.case\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.switch\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.->\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.->>\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.or-else\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.doc\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.nil?\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.tap>\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.println\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.in\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.not-in\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.when-let\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.if-let\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.when-ok\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tcore.if-ok\t"), true)
}

@(test)
imported_symbols_source_indexes_odin_imports :: proc(t: ^testing.T) {
    source := `(package main)
(import fmt "core:fmt")`

    output, err, ok := kvist.imported_symbols_source("/tmp/imported-symbols-test.kvist", source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile\n"), true)
    testing.expect_value(t, strings.contains(output, "fmt.println"), true)
    testing.expect_value(t, strings.contains(output, "\tcore:fmt\t"), true)
}

@(test)
odin_symbol_visible_to_tooling_filters_internal_noise :: proc(t: ^testing.T) {
    testing.expect_value(t, kvist.odin_symbol_visible_to_tooling("/tmp/fmt/fmt_os.odin", "println"), true)
    testing.expect_value(t, kvist.odin_symbol_visible_to_tooling("/tmp/fmt/fmt.odin", "fmt_arg"), false)
    testing.expect_value(t, kvist.odin_symbol_visible_to_tooling("/tmp/fmt/example.odin", "SomeType"), false)
    testing.expect_value(t, kvist.odin_symbol_visible_to_tooling("/tmp/fmt/fmt_js.odin", "stderr"), false)
    testing.expect_value(t, kvist.odin_symbol_visible_to_tooling("/tmp/fmt/fmt_os.odin", "main"), false)
}

@(test)
editor_symbols_source_merges_context_surfaces :: proc(t: ^testing.T) {
    source := `(package main)
(import fmt "core:fmt")

(defstruct Greeting {message: string})

(defn main []
  (let [g (Greeting {message: "hi"})]
    (println g.message)))`

    output, err, ok := kvist.editor_symbols_source("/tmp/editor-symbols-test.kvist", source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile\n"), true)
    testing.expect_value(t, strings.contains(output, "struct\tGreeting\t"), true)
    testing.expect_value(t, strings.contains(output, "proc\tmain\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tarr.push!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tcore.println\t"), true)
    testing.expect_value(t, strings.contains(output, "odin\tfmt.println\t"), true)
}

@(test)
editor_symbols_source_indexes_local_defvar_struct_fields :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Animation {
  texture: int
  num-frames: int
  name: string
})

(defn main []
  (defvar player-idle (Animation {texture: 1 num-frames: 3 name: "idle"}))
  (defvar current-anim player-idle))`

    output, err, ok := kvist.editor_symbols_source("/tmp/editor-local-fields-test.kvist", source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "local\tplayer-idle\t10\t11\tAnimation\t\t\t/tmp/editor-local-fields-test.kvist\n"), true)
    testing.expect_value(t, strings.contains(output, "field\tplayer-idle.texture\t10\t11\tAnimation\t\t\t/tmp/editor-local-fields-test.kvist\n"), true)
    testing.expect_value(t, strings.contains(output, "field\tplayer-idle.num-frames\t10\t11\tAnimation\t\t\t/tmp/editor-local-fields-test.kvist\n"), true)
    testing.expect_value(t, strings.contains(output, "field\tcurrent-anim.name\t11\t11\tAnimation\t\t\t/tmp/editor-local-fields-test.kvist\n"), true)
}

@(test)
editor_symbols_source_includes_language_forms_and_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn main []
  (let [x 1]
    (if true
      (arr.map inc [1 2 3])
      (println x))))`

    path, ok_path := repo_temp_test_path(".tmp-editor-symbols-test.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)

    output, err, ok := kvist.editor_symbols_source(path, source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist form\tlet\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tif\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tdefsource\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\twhen\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tcond\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tcase\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tswitch\t"), false)
    testing.expect_value(t, strings.contains(output, "compatibility syntax\tswitch\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\twhile\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\teach\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tdiscard\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tupdate!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tget\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tslice\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\taddr\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tderef\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tloop\t"), false)
    testing.expect_value(t, strings.contains(output, "kvist helper\tprintln\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist helper\tupdate!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist helper\tslice\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist helper\twhen-let\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist helper\tswitch\t"), false)
    testing.expect_value(t, strings.contains(output, "kvist package\tcore.println\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tarr.map\t"), true)
}

@(test)
editor_symbols_source_includes_proc_default_values_in_signatures :: proc(t: ^testing.T) {
    source := `(package main)

(defn greet [name: string, punctuation: string = "!", count: int = (+ 1 2)] -> string
  name)`

    output, err, ok := kvist.editor_symbols_source("/tmp/editor-default-signature-test.kvist", source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "proc\tgreet\t3\t7\t\t(greet [name: string, punctuation: string = \"!\", count: int = (+ 1 2)] -> string)\t\t/tmp/editor-default-signature-test.kvist\n"), true)
}

@(test)
editor_symbols_source_includes_dot_access_param_signatures :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point {
  x: int
  y: int
})

(defn draw [point: Point] -> int
  (+ point.x point.y))`

    output, err, ok := kvist.editor_symbols_source("/tmp/editor-dot-signature-test.kvist", source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "(draw [point: Point] -> int)"), true)
}

@(test)
editor_symbols_source_includes_expanded_str_and_set_packages :: proc(t: ^testing.T) {
    source := `(package main)
(import str "kvist:str")
(import set "kvist:set")

(defn main []
  (let [parts (str.split "a,b" ",")
        seen (set.empty string)]
    (defer (delete parts))
    (defer (delete seen))
    (set.union! seen (set.of string ["a"]))
    (println (str.trim " ok "))))`

    path, ok_path := repo_temp_test_path(".tmp-str-set-editor-symbols.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)

    output, err, ok := kvist.editor_symbols_source(path, source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist package\tstr.split\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tstr.replace\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tset.union!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tset.difference!\t"), true)
}

@(test)
editor_symbols_source_includes_core_package_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn main []
  (let [xs [1 2 3]]
    (println (count xs) (empty? xs) (contains? xs 2))))`

    path, ok_path := repo_temp_test_path(".tmp-core-editor-symbols.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)

    output, err, ok := kvist.editor_symbols_source(path, source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist package\tcore.count\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tcore.empty?\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tcore.contains?\t"), true)
}

@(test)
editor_symbols_source_includes_arr_and_map_mutation_packages :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")
(import map "kvist:map")

(defn main []
  (let [xs ([dynamic]int [1 2 3])
        lookup (map.of string int {"seed" 1})]
    (defer (delete xs))
    (defer (delete lookup))
    (arr.map! inc xs)
    (map.assoc! lookup "next" 2)
    (map.dissoc! lookup "seed")
    (println xs lookup)))`

    path, ok_path := repo_temp_test_path(".tmp-arr-map-mutation-editor-symbols.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)

    output, err, ok := kvist.editor_symbols_source(path, source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist package\tarr.map!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tarr.dynamic\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tarr.push!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tarr.sort-by!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tmap.assoc!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tmap.dissoc!\t"), true)
}

@(test)
editor_symbols_source_includes_soa_package_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import soa "kvist:soa")

(defstruct Profile
  {name: string
   active?: bool})

(defn main []
  (let [profiles (soa.make Profile 4)]
    (defer (delete profiles))
    (println (soa.fields 'Profile) (soa.types 'Profile) (len profiles))))`

    path, ok_path := repo_temp_test_path(".tmp-soa-editor-symbols.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)

    output, err, ok := kvist.editor_symbols_source(path, source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist package\tsoa.fields\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tsoa.types\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tsoa.make\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tsoa.push!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tsoa.update!\t"), true)
}

@(test)
editor_symbols_source_includes_cli_package_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import cli "kvist:cli")

(defn main []
  (let [args ([]string ["tool" "serve" "--port" "8080"])]
    (cli.println (cli.flag args "--debug")
                 (cli.option args "--port" "3000")
                 (cli.int-option args "--port" 3000)
                 (or-else (cli.command args) "none"))))`

    path, ok_path := repo_temp_test_path(".tmp-cli-editor-symbols.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)

    output, err, ok := kvist.editor_symbols_source(path, source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist package\tcli.flag\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tcli.option\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tcli.int-option\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tcli.command\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist package\tcli.println\t"), true)
}

@(test)
editor_symbols_source_includes_source_package_imports :: proc(t: ^testing.T) {
    source := `(package main)
(import html "kvist:html")

(defn main []
  (html.render [:div "ok"]))`

    path, ok_path := repo_temp_test_path(".tmp-html-editor-symbols.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)

    write_err := os.write_entire_file(path, transmute([]byte)source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }
    defer os.remove(path)

    output, err, ok := kvist.editor_symbols_source(path, source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "macro\thtml.render\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\thtml.render-file\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\thtml.for\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\thtml.html\t"), false)
    testing.expect_value(t, strings.contains(output, "struct\thtml.Element\t"), false)
    testing.expect_value(t, strings.contains(output, "union\thtml.Node\t"), false)
    testing.expect_value(t, strings.contains(output, "packages/html/html.kvist"), true)
    testing.expect_value(t, strings.contains(output, "html.emit-node"), false)
    testing.expect_value(t, strings.contains(output, "html.render-node-into"), false)
}

@(test)
editor_symbols_source_includes_multi_file_root_package_symbols :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-editor-root-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package demo)

(defn main [] -> int
  (helper-value 5))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    helpers_path, helpers_join_err := os.join_path({dir, "helpers.kvist"}, context.allocator)
    testing.expect_value(t, helpers_join_err == nil, true)
    if helpers_join_err != nil {
        return
    }
    defer delete(helpers_path)
    helpers_source := `(package demo)

(defn- secret-bonus [] -> int
  2)

(defn helper-value [n: int] -> int
  (+ n (secret-bonus)))`
    helpers_write_err := os.write_entire_file_from_string(helpers_path, helpers_source)
    testing.expect_value(t, helpers_write_err == nil, true)
    if helpers_write_err != nil {
        return
    }

    output, err, ok := kvist.editor_symbols_source(main_path, main_source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "proc\tmain\t"), true)
}

@(test)
editor_symbols_source_includes_multi_file_root_package_symbols_from_non_anchor_file :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-editor-root-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package demo)

(defstruct App_State
  {count: int})

(defn main [] -> int
  (helper-value 5))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    app_path, app_join_err := os.join_path({dir, "app.kvist"}, context.allocator)
    testing.expect_value(t, app_join_err == nil, true)
    if app_join_err != nil {
        return
    }
    defer delete(app_path)
    app_source := `(package demo)

(defn helper-value [n: int] -> int
  (+ n 1))`
    app_write_err := os.write_entire_file_from_string(app_path, app_source)
    testing.expect_value(t, app_write_err == nil, true)
    if app_write_err != nil {
        return
    }

    output, err, ok := kvist.editor_symbols_source(app_path, app_source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "proc\tmain\t"), true)
    testing.expect_value(t, strings.contains(output, "struct\tApp_State\t"), true)
    testing.expect_value(t, strings.contains(output, main_path), true)
}

@(test)
editor_symbols_source_includes_relative_source_package_imports :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-editor-source-import-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package demo)
(import "support/math")

(defn main [] -> int
  (math.sum-range 0 5))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    support_dir, support_dir_err := os.join_path({dir, "support", "math"}, context.allocator)
    testing.expect_value(t, support_dir_err == nil, true)
    if support_dir_err != nil {
        return
    }
    defer delete(support_dir)
    mk_support_err := os.make_directory_all(support_dir)
    testing.expect_value(t, mk_support_err == nil, true)
    if mk_support_err != nil {
        return
    }

    support_path, support_path_err := os.join_path({support_dir, "math.kvist"}, context.allocator)
    testing.expect_value(t, support_path_err == nil, true)
    if support_path_err != nil {
        return
    }
    defer delete(support_path)
    support_source := `(package math)

(defn sum-range [start: int, end: int] -> int
  (+ start end))`
    support_write_err := os.write_entire_file_from_string(support_path, support_source)
    testing.expect_value(t, support_write_err == nil, true)
    if support_write_err != nil {
        return
    }

    output, err, ok := kvist.editor_symbols_source(main_path, main_source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "source import\tmath\t1\t1\tsupport/math\t(import math \"support/math\")"), true)
    testing.expect_value(t, strings.contains(output, "proc\tmath.sum-range\t"), true)
    testing.expect_value(t, strings.contains(output, support_path), true)
}

@(test)
compile_path_supports_html_expression_interpolation :: proc(t: ^testing.T) {
    path, ok_path := repo_temp_test_path(".tmp-html-interpolation-test.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)
    defer os.remove(path)

    source := `(import arr "kvist:arr")
(import html "kvist:html")

(defn status-label [enabled?: bool] -> string
  (if enabled?
    "Ready"
    "Hidden"))

(defn demo [title: string, count: int, ratio: float, enabled?: bool] -> string
  (let [archived? false
        ids (arr.range 1 4) defer]
    (html.render
      [:section {data-count: count
                 data-ratio: ratio
                 hidden: enabled?
                 data-state: (if enabled? "ready" "hidden")
                 data-archived: (when archived? "true")}
       [:h1 title]
       [:<>
        [:h2 title]
        [:p (+ count 10)]]
       [:p (status-label enabled?)]
       [:p (+ count 1)]
       (when archived?
         [:p "Archived"])
       nil
       [:ul
        (html.for [id ids]
          [:li id])]
       (if enabled?
         "Visible"
         "Hidden")])))`

    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `ids := arr__range_impl(1, 4, 1)`), true)
    testing.expect_value(t, strings.contains(output, `html__render_attr_into(&__html_render_builder`), true)
    testing.expect_value(t, strings.contains(output, `value = html__Attr_Value(count)`), true)
    testing.expect_value(t, strings.contains(output, `value = html__Attr_Value(ratio)`), true)
    testing.expect_value(t, strings.contains(output, `value = html__Attr_Value(enabled_p)`), true)
    testing.expect_value(t, strings.contains(output, `if enabled_p`), true)
    testing.expect_value(t, strings.contains(output, `for id in ids`), true)
    testing.expect_value(t, strings.contains(output, `html__render_node_into(&__html_render_builder`), true)
    testing.expect_value(t, strings.contains(output, `html__Node(html__Element{tag = "section"`), false)
    testing.expect_value(t, strings.contains(output, `children = []html__Node`), false)
}

@(test)
compile_path_direct_html_render_emits_builder_writes :: proc(t: ^testing.T) {
    path, ok_path := repo_temp_test_path(".tmp-html-direct-render-test.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)
    defer os.remove(path)

    source := `(import html "kvist:html")

(defn demo [title: string, enabled?: bool] -> string
  (html.render
    [:section {class: "panel"
               hidden: enabled?
               data-state: (if enabled? "on" "off")}
     [:h1 title]
     (when enabled?
       [:span "Ready & <ok>"])]))`

    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `strings.write_string(&__html_render_builder`), true)
    testing.expect_value(t, strings.contains(output, `"<section"`), true)
    testing.expect_value(t, strings.contains(output, `html__write_attr_string(&__html_render_builder`), true)
    testing.expect_value(t, strings.contains(output, `html__render_attr_into(&__html_render_builder`), true)
    testing.expect_value(t, strings.contains(output, `if enabled_p`), true)
    testing.expect_value(t, strings.contains(output, `html__Node(html__Element{tag = "section"`), false)
    testing.expect_value(t, strings.contains(output, `children = []html__Node`), false)
}

@(test)
compile_path_html_render_supports_template_bindings :: proc(t: ^testing.T) {
    path, ok_path := repo_temp_test_path(".tmp-html-template-render-test.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)
    defer os.remove(path)

    source := `(import html "kvist:html")

(defn demo [name: string] -> string
  (html.render "<h1>{{name}}</h1>" {name: name}))`

    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `__html_template`), true)
    testing.expect_value(t, strings.contains(output, `html__clone_string("<h1>{{name}}</h1>")`), true)
    testing.expect_value(t, strings.contains(output, `html__replace_owned(__html_template`), true)
    testing.expect_value(t, strings.contains(output, `"{{name}}"`), true)
    testing.expect_value(t, strings.contains(output, `return __html_template`), true)
}

@(test)
compile_path_html_render_file_embeds_template_at_compile_time :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-html-render-file-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    template_path, template_join_err := os.join_path({dir, "home.html"}, context.allocator)
    testing.expect_value(t, template_join_err == nil, true)
    if template_join_err != nil {
        return
    }
    defer delete(template_path)
    template_write_err := os.write_entire_file_from_string(template_path, "<main>{{name}}</main>")
    testing.expect_value(t, template_write_err == nil, true)
    if template_write_err != nil {
        return
    }

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)

    source := `(package main)
(import html "kvist:html")

(defn demo [name: string] -> string
  (html.render-file "home.html" {name: name}))`

    source_write_err := os.write_entire_file_from_string(main_path, source)
    testing.expect_value(t, source_write_err == nil, true)
    if source_write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `html__clone_string("<main>{{name}}</main>")`), true)
    testing.expect_value(t, strings.contains(output, `"home.html"`), false)
    testing.expect_value(t, strings.contains(output, `os.read_entire_file`), false)
}

@(test)
compile_eval_source_can_emit_statement_runner :: proc(t: ^testing.T) {
    source := `(package main)
(import "core:fmt")

(defn add [a: int, b: int] -> int
  (+ a b))`

    output, err, ok := kvist.compile_eval_source(source, "(fmt.println (add 1 2))", true)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import "core:fmt"

add :: proc(a, b: int) -> int {
    return (a) + (b)
}

main :: proc() {
    fmt.println(add(1, 2))
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_eval_source_prints_block_forms_as_statements :: proc(t: ^testing.T) {
    source := `(package main)
(import io "kvist:io")
(import os "core:os")

(defn load-note [path: string] -> [data: []byte, err: os.Error]
  (io.read path))`

    output, err, ok := kvist.compile_eval_source(source, `(let [[data err] (load-note "tmp/kvist-note.txt")]
  (if (!= err nil)
    0
    (do
      (defer (delete data))
      (len data))))`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `import os "core:os"`), true)
    testing.expect_value(t, strings.contains(output, "io__read :: #force_inline proc(path: string) -> (data: []byte, err: os.Error)"), true)
    testing.expect_value(t, strings.contains(output, "return os.read_entire_file(path, context.allocator)"), true)
    testing.expect_value(t, strings.contains(output, "load_note :: proc(path: string) -> (data: []byte, err: os.Error)"), true)
    testing.expect_value(t, strings.contains(output, "return io__read(path)"), true)
    testing.expect_value(t, strings.contains(output, `data, err := load_note("tmp/kvist-note.txt")`), true)
    testing.expect_value(t, strings.contains(output, "fmt.println(len(data))"), true)
}

@(test)
compile_eval_source_can_load_declaration_form :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Greeting {
  message: string
})`

    output, err, ok := kvist.compile_eval_source(source, `(defstruct Greeting {
  message: string
})`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Greeting :: struct {
    message: string,
}

main :: proc() {
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_eval_source_can_load_defstruct_declaration_form :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Greeting
  "Greeting text."
  {message: string})`

    output, err, ok := kvist.compile_eval_source(source, `(defstruct Greeting
  "Greeting text."
  {message: string})`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

// Greeting text.
Greeting :: struct {
    message: string,
}

main :: proc() {
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_defstruct_rejects_duplicate_fields :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Broken
  {name: string
   name: int})`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "duplicate defstruct field name:"), true)
}

@(test)
compile_defstruct_rejects_bad_metadata :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Broken
  {tags: [set]
   scores: [fixed-arr int]})`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "expects one element type") || strings.contains(err.message, "expects a numeric length"), true)
}

@(test)
compile_struct_constructor_rejects_unknown_field :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Person
  {name: string
   age: int})

(defn bad [] -> Person
  (Person {name: "Ada" extra: 1}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "unknown struct constructor field extra:"), true)
}

@(test)
compile_struct_constructor_rejects_duplicate_field :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Person
  {name: string
   age: int})

(defn bad [] -> Person
  (Person {name: "Ada" name: "Grace"}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "duplicate struct constructor field name:"), true)
}

@(test)
compile_struct_constructor_rejects_literal_type_mismatch :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Person
  {name: string
   age: int})

(defn bad [] -> Person
  (Person {name: 42 age: "old"}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "struct constructor literal type mismatch for name:") || strings.contains(err.message, "struct constructor literal type mismatch for age:"), true)
}

@(test)
compile_label_fields_for_struct_union_and_enum :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point {
  x: f32
  y: f32
})

(defunion Value {
  i: int
  label: string
})

(defenum Http-Status {
  OK: 200
  Not-Found: 404
})

(defn point [] -> Point
  (Point {x: 1.0 y: 2.0}))

(defn value [] -> Value
  (Value {i: 42}))

(defn status [] -> Http-Status
  .OK)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "Point :: struct {"), true)
    testing.expect_value(t, strings.contains(output, "x: f32,"), true)
    testing.expect_value(t, strings.contains(output, "y: f32,"), true)
    testing.expect_value(t, strings.contains(output, "Value :: union {"), true)
    testing.expect_value(t, strings.contains(output, "    int,\n"), true)
    testing.expect_value(t, strings.contains(output, "    string,\n"), true)
    testing.expect_value(t, strings.contains(output, "Http_Status :: enum {"), true)
    testing.expect_value(t, strings.contains(output, "OK = 200,"), true)
    testing.expect_value(t, strings.contains(output, "Not_Found = 404,"), true)
    testing.expect_value(t, strings.contains(output, "return Point{x = 1.0, y = 2.0}"), true)
    testing.expect_value(t, strings.contains(output, "return Value(int(42))"), true)
    testing.expect_value(t, strings.contains(output, "return .OK"), true)
}

@(test)
compile_type_call_position_supports_scalar_conversions :: proc(t: ^testing.T) {
    source := `(package main)

(defn as-f32 [x: int] -> f32
  (f32 x))

(defn as-i32 [x: f64] -> i32
  (i32 x))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return f32(x)"), true)
    testing.expect_value(t, strings.contains(output, "return i32(x)"), true)
}

@(test)
compile_type_call_position_supports_complex_type_heads :: proc(t: ^testing.T) {
    source := `(package main)

(defn ptr-cast [x: rawptr] -> ^f32
  ((ptr f32) x))

(defn slice-cast [xs: []i32] -> (slice i32)
  ((slice i32) xs))

(defn fixed-literal [] -> [3]i32
  ((array 3 i32) [1 2 3]))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return (^f32)(x)"), true)
    testing.expect_value(t, strings.contains(output, "return ([]i32)(xs)"), true)
    testing.expect_value(t, strings.contains(output, "return [3]i32{1, 2, 3}"), true)
}

@(test)
reject_old_core_slice_type_constructor :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [xs: []i32] -> (core.slice i32)
  xs)`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "unsupported type form")
}

@(test)
compile_typed_def_bindings_preserve_type_forms_during_macroexpand :: proc(t: ^testing.T) {
    source := `(package main)

(def xs: (slice i32) ([]i32 [1 2]))
(defvar ys: (slice i32) ([]i32 [3 4]))

(defn score [] -> int
  (+ (count xs) (count ys)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "xs: []i32 : []i32{1, 2}"), true)
    testing.expect_value(t, strings.contains(output, "ys: []i32 = []i32{3, 4}"), true)
}

@(test)
compile_type_call_position_supports_complex_symbol_heads :: proc(t: ^testing.T) {
    source := `(package main)

(defn ptr-cast [x: rawptr] -> ^f32
  (^f32 x))

(defn slice-cast [xs: []f32] -> []f32
  ([]f32 xs))

(defn fixed-literal [] -> [3]i32
  ([3]i32 [1 2 3]))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return (^f32)(x)"), true)
    testing.expect_value(t, strings.contains(output, "return ([]f32)(xs)"), true)
    testing.expect_value(t, strings.contains(output, "return [3]i32{1, 2, 3}"), true)
}

@(test)
compile_as_form_is_removed :: proc(t: ^testing.T) {
    source := `(package main)

(defn main [] -> f32
  (as f32 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, strings.contains(err.message, "`as` has been removed"), true)
}

@(test)
compile_new_form_is_removed :: proc(t: ^testing.T) {
    source := `(package main)

(defn main [] -> []int
  (new []int [1 2 3]))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, strings.contains(err.message, "`new` has been removed"), true)
}

@(test)
compile_update_bang_stmt :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct Point
  {x: int
   y: int})

(defn score [] -> int
    (let [xs ([dynamic]int [1 2 3])
        lookup (map[string]int {"a" 1})
        point (Point {x: 4 y: 5})]
    (set! xs[1] 42)
    (set! (get lookup "a") 7)
    (set! (get point .x) 8)
    (set! point.y 9)
    (+ (+ (get xs 1) (get lookup "a"))
       (+ (get point .x) (get point .y)))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "(xs)[1] = 42"), true)
    testing.expect_value(t, strings.contains(output, "lookup[\"a\"] = 7"), true)
    testing.expect_value(t, strings.contains(output, "(point).x = 8"), true)
    testing.expect_value(t, strings.contains(output, "point.y = 9"), true)
    testing.expect_value(t, strings.contains(output, "((point).x) + ((point).y)"), true)
}

@(test)
compile_canonical_bare_core_helpers :: proc(t: ^testing.T) {
    source := `(package main)

(defn score [needle: int] -> int
  (let [xs ([dynamic]int [1 2 3])
        lookup (map[string]int {"a" 4})
        tail (slice xs 1)
        total (count xs)]
    (update! xs[0] + 10)
    (delete! lookup "a")
    (if (contains? xs needle)
      (if (in "a" lookup)
        (if (not-in "b" lookup)
          (if (empty? (slice tail))
            0
            (+ total (get xs 0)))
          0)
        0)
      0)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "(xs)[1:]"), true)
    testing.expect_value(t, strings.contains(output, "total := len((xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "(xs)[0] += (10)"), true)
    testing.expect_value(t, strings.contains(output, "delete_key(&(lookup), \"a\")"), true)
    testing.expect_value(t, strings.contains(output, "kvist_contains_value((xs)[:]"), true)
    testing.expect_value(t, strings.contains(output, "(\"a\") in (lookup)"), true)
    testing.expect_value(t, strings.contains(output, "!((\"b\") in (lookup))"), true)
    testing.expect_value(t, strings.contains(output, "len(((tail)[:])[:]) == 0"), true)
    testing.expect_value(t, strings.contains(output, "(total) + (xs[0])"), true)
}

@(test)
reject_slash_package_access_in_source :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [] -> [dynamic]int
  (arr/map inc [1 2 3]))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "use `arr.map` for package access")
}

@(test)
reject_internal_lowering_call_names_in_source :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn inc [x: int] -> int
  (+ x 1))

(defn bad-core [] -> int
  (core-count [1 2 3]))

(defn bad-arr [] -> [dynamic]int
  (arr-map inc [1 2 3]))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "`core-count` is an internal lowering name; use `count`")

    source_arr := `(package main)
(import arr "kvist:arr")

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [] -> [dynamic]int
  (arr-map inc [1 2 3]))`

    _, err_arr, ok_arr := kvist.compile_source(source_arr)
    testing.expect_value(t, ok_arr, false)
    if ok_arr {
        return
    }
    defer delete(err_arr.message)
    testing.expect_value(t, err_arr.message, "`arr-map` is an internal lowering name; use `arr.map`")
}

@(test)
reject_package_dash_call_names_in_source :: proc(t: ^testing.T) {
    cases := []struct {
        source:   string,
        expected: string,
    }{
        {`(package main)

(defn bad [xs: []int] -> [dynamic]int
  (arr-interpose 0 xs))`, "`arr-interpose` is an internal lowering name; use `arr.interpose`"},
        {`(package main)

(defn bad [m: map[string]int] -> [dynamic]string
  (map-keys m))`, "`map-keys` is an internal lowering name; use `map.keys`"},
        {`(package main)

(defn bad [a: set[int] b: set[int]] -> set[int]
  (set-union a b))`, "`set-union` is an internal lowering name; use `set.union`"},
        {`(package main)

(defn bad [s: string] -> string
  (str-lower s))`, "`str-lower` is an internal lowering name; use `str.lower`"},
        {`(package main)

(defn bad [path: string]
  (io-read path))`, "`io-read` is an internal lowering name; use `io.read`"},
        {`(package main)

(defn bad [value: int]
  (json-write value))`, "`json-write` is an internal lowering name; use `json.write`"},
        {`(package main)

(defn bad [args: []string] -> bool
  (cli-flag args "--verbose"))`, "`cli-flag` is an internal lowering name; use `cli.flag`"},
    }

    for test_case in cases {
        _, err, ok := kvist.compile_source(test_case.source)
        testing.expect_value(t, ok, false)
        if ok {
            continue
        }
        testing.expect_value(t, err.message, test_case.expected)
        delete(err.message)
    }
}

@(test)
reject_internal_lowering_call_names_in_eval_source :: proc(t: ^testing.T) {
    source := `(package main)

(def xs: []int ([]int [1 2 3]))`

    _, err, ok := kvist.compile_eval_source_with_map(source, `(core-count xs)`)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "`core-count` is an internal lowering name; use `count`")
}

@(test)
reject_slash_package_access_in_eval_source :: proc(t: ^testing.T) {
    source := `(package main)

(def xs: []int ([]int [1 2 3]))`

    _, err, ok := kvist.compile_eval_source_with_map(source, `(arr/count xs)`)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "use `arr.count` for package access")
}

@(test)
reject_macro_expanded_slash_package_access :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defmacro bad-map [f xs]
  (let [head (symbol "arr/map")]
    (quasiquote
      ((unquote head) (unquote f) (unquote xs)))))

(defn bad [] -> [dynamic]int
  (bad-map inc ([]int [1 2 3])))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "use `arr.map` for package access")
}

@(test)
reject_macro_expanded_slash_package_access_for_custom_alias :: proc(t: ^testing.T) {
    source := `(package main)
(import things "kvist:arr")

(defn inc [x: int] -> int
  (+ x 1))

(defmacro bad-map [f xs]
  (let [head (symbol "things/map")]
    (quasiquote
      ((unquote head) (unquote f) (unquote xs)))))

(defn bad [] -> [dynamic]int
  (bad-map inc ([]int [1 2 3])))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "use `things.map` for package access")
}

@(test)
reject_eval_macro_expanded_slash_package_access :: proc(t: ^testing.T) {
    source := `(package main)

(def xs: []int ([]int [1 2 3]))

(defmacro bad-count [xs]
  (let [head (symbol "arr/count")]
    (quasiquote
      ((unquote head) (unquote xs)))))`

    _, err, ok := kvist.compile_eval_source_with_map(source, `(bad-count xs)`)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "use `arr.count` for package access")
}

@(test)
reject_eval_macro_expanded_slash_package_access_for_custom_alias :: proc(t: ^testing.T) {
    source := `(package main)
(import things "kvist:arr")

(def xs: []int ([]int [1 2 3]))

(defmacro bad-count [xs]
  (let [head (symbol "things/count")]
    (quasiquote
      ((unquote head) (unquote xs)))))`

    _, err, ok := kvist.compile_eval_source_with_map(source, `(bad-count xs)`)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "use `things.count` for package access")
}

@(test)
compile_get_field_selector_and_enum_key :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point {
  x: int
})

(defenum Status [Active Inactive])

(defn score [] -> int
  (let [point (Point {x: 4})
        counts (map[Status]int {.Active 7})]
    (+ (get point .x)
       (get counts .Active))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return ((point).x) + (counts[.Active])"), true)
}

@(test)
compile_eval_source_deduplicates_import_declaration_form :: proc(t: ^testing.T) {
    source := `(package main)
(import "core:fmt")

(defn main []
  (fmt.println "hello"))`

    output, err, ok := kvist.compile_eval_source(source, `(import "core:fmt")`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import "core:fmt"

main :: proc() {
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_eval_source_can_load_foreign_import_declaration_form :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (return))`

    output, err, ok := kvist.compile_eval_source(source, `(foreign-import libc "system:c")`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

foreign import libc "system:c"

main :: proc() {
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_eval_source_can_load_main_defn_declaration_form :: proc(t: ^testing.T) {
    source := `(package main)
(import "core:fmt")

(defn main []
  (fmt.println "hello"))`

    output, err, ok := kvist.compile_eval_source(source, `(defn main []
  (fmt.println "hello"))`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import "core:fmt"

main :: proc() {
    fmt.println("hello")
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_eval_source_reports_eval_origin :: proc(t: ^testing.T) {
    source := `(package main)

(defn add [a: int, b: int] -> int
  (+ a b))`

    _, err, ok := kvist.compile_eval_source(source, "(not 1 2)")
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.span.source, kvist.Source_Kind.Eval)

    formatted := kvist.format_eval_compile_error("app.kvist", source, "(not 1 2)", err)
    defer delete(formatted)
    expected := `app.kvist:<eval>:1:1: not expects one argument
  (not 1 2)
  ^
`
    testing.expect_value(t, formatted, expected)
}

@(test)
compile_eval_source_map_marks_eval_runner :: proc(t: ^testing.T) {
    source := `(package main)

(defn add [a: int, b: int] -> int
  (+ a b))`

    result, err, ok := kvist.compile_eval_source_with_map(source, "(add 1 2)")
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    found_eval_entry := false
    for entry in result.source_map {
        if entry.source_span.source == .Eval {
            found_eval_entry = true
            break
        }
    }
    testing.expect_value(t, found_eval_entry, true)
}

@(test)
reader_supports_hash_underscore_and_comment_form :: proc(t: ^testing.T) {
    source := `(package main)
#_(defstruct Ignored {
  field: string
})
(comment
  (defn old []
    (fmt.println "old")))
(defn main []
  (return))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    expected := `package main

main :: proc() {
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
reader_preserves_top_form_source_text :: proc(t: ^testing.T) {
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    source := `// Doc.
(package main)

(def answer 42)`

    forms, err, ok := kvist.read_top_forms(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }

    testing.expect_value(t, len(forms), 2)
    testing.expect_value(t, forms[0].source, "(package main)")
    testing.expect_value(t, len(forms[0].doc_lines), 1)
    testing.expect_value(t, forms[0].doc_lines[0], "// Doc.")
    testing.expect_value(t, forms[1].source, "(def answer 42)")
}

@(test)
reader_converts_semicolon_doc_comments :: proc(t: ^testing.T) {
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    source := `; Lisp doc.
(def answer 42)`

    forms, err, ok := kvist.read_top_forms(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }

    testing.expect_value(t, len(forms), 1)
    testing.expect_value(t, len(forms[0].doc_lines), 1)
    testing.expect_value(t, forms[0].doc_lines[0], "// Lisp doc.")
}

@(test)
reader_converts_block_doc_comments :: proc(t: ^testing.T) {
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    source := `/*
 * Block doc.
 * Second line.
 */
(def answer 42)`

    forms, err, ok := kvist.read_top_forms(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }

    testing.expect_value(t, len(forms), 1)
    testing.expect_value(t, len(forms[0].doc_lines), 1)
    testing.expect_value(t, forms[0].doc_lines[0], "Block doc.\nSecond line.")
}

@(test)
reader_classifies_core_literals :: proc(t: ^testing.T) {
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    source := `(def answer 42)
(def negative -1)
(def ok true)
(def none nil)`

    forms, err, ok := kvist.read_top_forms(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }

    testing.expect_value(t, forms[0].form.items[2].kind, kvist.CST_Form_Kind.Number)
    testing.expect_value(t, forms[1].form.items[2].kind, kvist.CST_Form_Kind.Number)
    testing.expect_value(t, forms[2].form.items[2].kind, kvist.CST_Form_Kind.Bool)
    testing.expect_value(t, forms[3].form.items[2].kind, kvist.CST_Form_Kind.Nil)
}

@(test)
reader_classifies_inline_collection_literals :: proc(t: ^testing.T) {
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    source := `(def xs [1 2 3])
(def lookup {one: "1" two: "2"})
(def tags #{math: lisp:})`

    forms, err, ok := kvist.read_top_forms(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }

    testing.expect_value(t, forms[0].form.items[2].kind, kvist.CST_Form_Kind.Vector)
    testing.expect_value(t, forms[1].form.items[2].kind, kvist.CST_Form_Kind.Brace)
    testing.expect_value(t, forms[2].form.items[2].kind, kvist.CST_Form_Kind.Set)
}

@(test)
compile_source_with_declaration_source_map :: proc(t: ^testing.T) {
    source := `(package main)

(def answer 42)

(defn main []
  (return))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    expected := `package main

answer :: 42

main :: proc() {
    return
}
`
    testing.expect_value(t, result.output, expected)
    testing.expect_value(t, len(result.source_map) >= 4, true)
    package_entry, found_package := kvist.source_map_entry_for_generated_line(result.source_map[:], 1)
    testing.expect_value(t, found_package, true)
    testing.expect_value(t, package_entry.source_span.start, 0)

    const_entry, found_const := kvist.source_map_entry_for_generated_line(result.source_map[:], 3)
    testing.expect_value(t, found_const, true)
    testing.expect_value(t, const_entry.source_span.start > package_entry.source_span.start, true)

    proc_entry, found_proc := kvist.source_map_entry_for_generated_line(result.source_map[:], 5)
    testing.expect_value(t, found_proc, true)
    proc_line, _, _, _ := kvist.source_position(source, proc_entry.source_span.start)
    testing.expect_value(t, proc_line, 5)

    return_entry, found_return := kvist.source_map_entry_for_generated_line(result.source_map[:], 6)
    testing.expect_value(t, found_return, true)
    return_line, return_column, _, _ := kvist.source_position(source, return_entry.source_span.start)
    testing.expect_value(t, return_line, 6)
    testing.expect_value(t, return_column, 3)
}

@(test)
compile_source_map_accounts_for_feature_line_and_multiline_raw :: proc(t: ^testing.T) {
    source := `(package main)

(odin "Foreign_Handle :: distinct rawptr\nOther_Handle :: distinct rawptr")

(defn main []
  (let [lookup (map[string]int {"one" 1})]
    (return)))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.source_map) >= 5, true)
    package_entry, found_package := kvist.source_map_entry_for_generated_line(result.source_map[:], 2)
    testing.expect_value(t, found_package, true)
    testing.expect_value(t, package_entry.source_span.start, 0)

    raw_entry, found_raw := kvist.source_map_entry_for_generated_line(result.source_map[:], 4)
    testing.expect_value(t, found_raw, true)
    raw_line, _, _, _ := kvist.source_position(source, raw_entry.source_span.start)
    testing.expect_value(t, raw_line, 3)

    proc_entry, found_proc := kvist.source_map_entry_for_generated_line(result.source_map[:], 7)
    testing.expect_value(t, found_proc, true)
    proc_line, _, _, _ := kvist.source_position(source, proc_entry.source_span.start)
    testing.expect_value(t, proc_line, 5)

    binding_entry, found_binding := kvist.source_map_entry_for_generated_line(result.source_map[:], 8)
    testing.expect_value(t, found_binding, true)
    binding_line, binding_column, _, _ := kvist.source_position(source, binding_entry.source_span.start)
    testing.expect_value(t, binding_line, 6)
    testing.expect_value(t, binding_column > 0, true)
}

@(test)
format_declaration_source_map :: proc(t: ^testing.T) {
    entries := [?]kvist.Source_Map_Entry{
        {
            generated_start_line = 1,
            generated_end_line = 3,
            source_span = kvist.Span{start = 10, end = 20},
        },
        {
            generated_start_line = 2,
            generated_end_line = 2,
            source_span = kvist.Span{start = 30, end = 35},
        },
        {
            generated_start_line = 2,
            generated_end_line = 2,
            generated_start_column = 8,
            generated_end_column = 12,
            source_span = kvist.Span{start = 40, end = 45},
        },
    }

    formatted := kvist.format_source_map(entries[:])
    defer delete(formatted)

    expected := `generated_start generated_end source_start source_end
1 3 10 20
2 2 30 35
2 2 40 45
`
    testing.expect_value(t, formatted, expected)

    entry, found := kvist.source_map_entry_for_generated_line(entries[:], 2)
    testing.expect_value(t, found, true)
    testing.expect_value(t, entry.source_span.start, 30)

    column_entry, column_found := kvist.source_map_entry_for_generated_location(entries[:], 2, 9)
    testing.expect_value(t, column_found, true)
    testing.expect_value(t, column_entry.source_span.start, 40)

    fallback_entry, fallback_found := kvist.source_map_entry_for_generated_location(entries[:], 2, 2)
    testing.expect_value(t, fallback_found, true)
    testing.expect_value(t, fallback_entry.source_span.start, 30)

    _, missing := kvist.source_map_entry_for_generated_line(entries[:], 4)
    testing.expect_value(t, missing, false)
}

@(test)
compile_const_and_enum_forms :: proc(t: ^testing.T) {
    source := `(package main)

// Default answer for bootstrapping.
(def answer 42)
; Maximum configured size.
(def max-size: int 1024)

(defenum Method [
  Get
  Post
  Delete
])

(defenum Http-Status {
  OK: 200
  Not-Found: 404
  Unprocessable-Content: 422
})`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

// Default answer for bootstrapping.
answer :: 42

// Maximum configured size.
max_size: int : 1024

Method :: enum {
    Get,
    Post,
    Delete,
}

Http_Status :: enum {
    OK = 200,
    Not_Found = 404,
    Unprocessable_Content = 422,
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_def_and_defvar_forms :: proc(t: ^testing.T) {
    source := `(package main)
(import "core:sync")

(def answer 42)
(def max-size: int 1024)
(defvar lock: sync.Mutex)
(defvar table: map[int]string)
(defvar live-port: int 8080)
(defvar retries 3)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "answer :: 42"), true)
    testing.expect_value(t, strings.contains(output, "max_size: int : 1024"), true)
    testing.expect_value(t, strings.contains(output, "lock: sync.Mutex"), true)
    testing.expect_value(t, strings.contains(output, "table: map[int]string"), true)
    testing.expect_value(t, strings.contains(output, "live_port: int = 8080"), true)
    testing.expect_value(t, strings.contains(output, "retries := 3"), true)
}

@(test)
compile_local_typed_defvar_without_initializer :: proc(t: ^testing.T) {
    source := `(package main)

(defn demo [] -> int
  (defvar count: int)
  (set! count 41)
  (+ count 1))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "count: int"), true)
    testing.expect_value(t, strings.contains(output, "count = 41"), true)
    testing.expect_value(t, strings.contains(output, "return (count) + (1)"), true)
}

@(test)
compile_def_type_alias_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Order {
  id: int
})

(def Handle (distinct rawptr))
(def Order-Groups map[int][dynamic]Order)
(def Byte-Slice []byte)
(def Lane #simd[4]f32)

(defn group-count [groups: Order-Groups] -> int
  (count groups))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "Handle :: distinct rawptr"), true)
    testing.expect_value(t, strings.contains(output, "Order_Groups :: map[int][dynamic]Order"), true)
    testing.expect_value(t, strings.contains(output, "Byte_Slice :: []byte"), true)
    testing.expect_value(t, strings.contains(output, "Lane :: #simd[4]f32"), true)
    testing.expect_value(t, strings.contains(output, "group_count :: proc(groups: Order_Groups) -> int"), true)
}

@(test)
compile_rejects_old_typed_def_and_defvar_spelling :: proc(t: ^testing.T) {
    const_source := `(package main)

(def max-size int 1024)`

    output, err, ok := kvist.compile_source(const_source)
    testing.expect_value(t, ok, false)
    if ok {
        delete(output)
    }
    testing.expect_value(t, strings.contains(err.message, "typed def expects a name ending in ':'"), true)
    delete(err.message)

    var_source := `(package main)

(defvar live-port int 8080)`

    output, err, ok = kvist.compile_source(var_source)
    testing.expect_value(t, ok, false)
    if ok {
        delete(output)
    }
    testing.expect_value(t, strings.contains(err.message, "typed defvar expects a name ending in ':'"), true)
    delete(err.message)
}

@(test)
compile_rejects_removed_defconst_form :: proc(t: ^testing.T) {
    source := `(package main)

(defconst answer 42)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        delete(output)
    }
    testing.expect_value(t, strings.contains(err.message, "unsupported top-level form: defconst"), true)
    delete(err.message)
}

@(test)
compile_local_declaration_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defn classify [code: int] -> int
  (def max-code: int 10)
  (defenum Status [OK Err])
  (defstruct Payload {code: int status: Status})
  (defunion Value {payload: Payload raw: int})
  (let [payload (Payload {code: code status: .OK})
        value (Value {payload: payload})]
    (if (> payload.code max-code)
      1
      0)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

classify :: proc(code: int) -> int {
    max_code: int : 10
    Status :: enum {
        OK,
        Err,
    }
    Payload :: struct {
        code: int,
        status: Status,
    }
    Value :: union {
        Payload,
        int,
    }
    payload := Payload{code = code, status = .OK}
    value := Value(payload)
    if (payload.code) > (max_code) {
        return 1
    }
    else {
        return 0
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_local_struct_validates_constructors :: proc(t: ^testing.T) {
    source := `(package main)

(defn broken [] -> int
  (defstruct Local {x: int})
  (let [value (Local {y: 1})]
    0))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "unknown struct constructor field y:"), true)
}

@(test)
compile_type_call_struct_constructor_uses_field_type_context :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Level {platforms: [dynamic]int})

(defn main []
  (let [level (Level {platforms: []})]
    level))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "level := Level{platforms = [dynamic]int{}}"), true)
}

@(test)
compile_local_declarations_do_not_escape_block_scope :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Local {name: string})

(defn broken [] -> int
  (do
    (defstruct Local {x: int}))
  (let [value (Local {x: 1})]
    0))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "unknown struct constructor field x:"), true)
}

@(test)
compile_local_struct_shadows_package_struct_metadata :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Local {name: string})

(defn local-x [] -> int
  (defstruct Local {x: int})
  (let [value (Local {x: 1})]
    value.x))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "Local :: struct {\n    name: string,\n}"), true)
    testing.expect_value(t, strings.contains(output, "    Local :: struct {\n        x: int,\n    }"), true)
    testing.expect_value(t, strings.contains(output, "value := Local{x = 1}"), true)
    testing.expect_value(t, strings.contains(output, "return value.x"), true)
}

@(test)
compile_malli_types_and_empty_collection_constructors :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")
(import arr "kvist:arr")
(import map "kvist:map")
(import set "kvist:set")

(defn score [xs: [dynamic]int, tags: set[string]] -> int
    (let [out (arr.empty int 4)
        lookup (map.empty string int)
        seen (set.empty string 8)]
    (arr.push! out (arr.count xs))
    (set! (get lookup "count") (arr.count xs))
    (set.add! seen "ok")
    (+ (arr.get out 0) (map.get lookup "count" 0))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "score :: proc(xs: [dynamic]int, tags: map[string]struct{}) -> int"), true)
    testing.expect_value(t, strings.contains(output, "out := make([dynamic]int, 0, 4)"), true)
    testing.expect_value(t, strings.contains(output, "lookup := make(map[string]int)"), true)
    testing.expect_value(t, strings.contains(output, "seen := make(map[string]struct{}, 8)"), true)
}

@(test)
compile_supports_aliased_kvist_package_imports :: proc(t: ^testing.T) {
    source := `(package main)
(import a "kvist:arr")

(defn demo [] -> int
  (let [xs (a.empty int)]
    (a.push! xs 1 2 3)
    (a.count xs)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "xs := make([dynamic]int)"), true)
    testing.expect_value(t, strings.contains(output, "append(&(xs), 1, 2, 3)"), true)
    testing.expect_value(t, strings.contains(output, "return len((xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist:arr"), false)
}

@(test)
compile_rejects_unknown_kvist_package_import :: proc(t: ^testing.T) {
    source := `(package main)
(import missing "kvist:not-a-package")

(defn demo [] -> int
  1)`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "could not resolve shipped source import: kvist:not-a-package"), true)
}

@(test)
compile_defn_clean_param_and_named_return_syntax :: proc(t: ^testing.T) {
    source := `(package main)

(defn query [path: string, limit: int] -> [value: int, ok: bool]
  (return limit true))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "query :: proc(path: string, limit: int) -> (value: int, ok: bool)"), true)
}

@(test)
compile_defenum_and_defunion_aliases :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Method
  "HTTP method."
  [Get Post])

(defunion Value
  "Tagged value."
  {i: int
   s: string})`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "// HTTP method."), true)
    testing.expect_value(t, strings.contains(output, "Method :: enum {"), true)
    testing.expect_value(t, strings.contains(output, "// Tagged value."), true)
    testing.expect_value(t, strings.contains(output, "Value :: union {"), true)
}

@(test)
compile_struct_types_reports_source_surface :: proc(t: ^testing.T) {
    source := `(package main)
(import soa "kvist:soa")

(defstruct Profile
  {name: string
   active?: bool
   favorite-key: string
   tags: set[string]
   scores: [dynamic]int
   window: []float})

(defn type-map [] -> map[string]string
  (soa.types 'Profile))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "\"tags\" = \"set[string]\""), true)
    testing.expect_value(t, strings.contains(output, "\"scores\" = \"[dynamic]int\""), true)
    testing.expect_value(t, strings.contains(output, "\"window\" = \"[]float\""), true)
    testing.expect_value(t, strings.contains(output, "\"active?\" = \"bool\""), true)
    testing.expect_value(t, strings.contains(output, "\"favorite-key\" = \"string\""), true)
}

@(test)
compile_shipped_struct_source_package_uses_wrapper_resolution :: proc(t: ^testing.T) {
    source := `(package main)
(import soa "kvist:soa")

(defstruct Profile
  {name: string
   active?: bool})

(defn main []
  (println (soa.fields 'Profile) (soa.types 'Profile)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "fmt.println([]string{\"name\", \"active?\"}, map[string]string{"), true)
    testing.expect_value(t, strings.contains(output, "\"name\" = \"string\""), true)
    testing.expect_value(t, strings.contains(output, "\"active?\" = \"bool\""), true)
}

@(test)
compile_switch_with_implicit_branch_returns :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Method [
  Get
  Post
  Delete
])

(defn method-name [method: Method] -> string
  (switch method
    .Get "GET"
    .Post "POST"
    :else "OTHER"))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Method :: enum {
    Get,
    Post,
    Delete,
}

method_name :: proc(method: Method) -> string {
    #partial switch method {
    case .Get:
        return "GET"
    case .Post:
        return "POST"
    case:
        return "OTHER"
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_switch_with_grouped_value_cases :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Method [
  Get
  Head
  Post
])

(defn read-method? [method: Method] -> bool
  (switch method
    [.Get .Head] true
    :else false))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Method :: enum {
    Get,
    Head,
    Post,
}

read_method_p :: proc(method: Method) -> bool {
    #partial switch method {
    case .Get, .Head:
        return true
    case:
        return false
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_case_with_value_cases :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Method [
  Get
  Post
  Delete
])

(defn method-name [method: Method] -> string
  (case method
    .Get "GET"
    .Post "POST"
    :else "OTHER"))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Method :: enum {
    Get,
    Post,
    Delete,
}

method_name :: proc(method: Method) -> string {
    #partial switch method {
    case .Get:
        return "GET"
    case .Post:
        return "POST"
    case:
        return "OTHER"
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_case_with_grouped_value_cases :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Method [
  Get
  Head
  Post
])

(defn read-method? [method: Method] -> bool
  (case method
    [.Get .Head] true
    :else false))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Method :: enum {
    Get,
    Head,
    Post,
}

read_method_p :: proc(method: Method) -> bool {
    #partial switch method {
    case .Get, .Head:
        return true
    case:
        return false
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_explicit_partial_switch :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Method [
  Get
  Post
])

(defn maybe-print [method: Method]
  (#partial switch method
    .Get (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Method :: enum {
    Get,
    Post,
}

maybe_print :: proc(method: Method) {
    #partial switch method {
    case .Get:
        return
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_union_decl_and_constructor :: proc(t: ^testing.T) {
    source := `(package main)

// Tagged sum for testing constructors.
(defunion Value {
  i: int
  s: string
})

(defn wrap-int [n: int] -> Value
  (Value {i: n}))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

// Tagged sum for testing constructors.
Value :: union {
    int,
    string,
}

wrap_int :: proc(n: int) -> Value {
    return Value(n)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_operator_forms :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn score [a: int, b: int, ok: bool] -> int
  (if (and ok (> a b))
    (+ a b)
    (if (not ok)
      (- b)
      (- b a))))

(defenum Status [OK Err])

(defn has-key [lookup: map[string]int, key: string] -> bool
  (in key lookup))

(defn contains-key [lookup: map[string]int, key: string] -> bool
  (contains? lookup key))

(defn same? [a: int, b: int] -> bool
  (= a b))

(defn same3? [a: int, b: int, c: int] -> bool
  (= a b c))

(defn increasing? [a: int, b: int, c: int] -> bool
  (< a b c))

(defn bounded? [x: f32] -> bool
  (<= 0.0 x 1.0))

(defn status-ok-chain? [status: Status] -> bool
  (= status .OK .OK))

(defn missing-key [lookup: map[string]int, key: string] -> bool
  (not-in key lookup))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "same_p :: proc(a, b: int) -> bool {\n    return (a) == (b)\n}"), true)
    testing.expect_value(t, strings.contains(output, "same3_p :: proc(a, b, c: int) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "increasing_p :: proc(a, b, c: int) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "bounded_p :: proc(x: f32) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "status_ok_chain_p :: proc(status: Status) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "proc() -> bool {"), true)
    testing.expect_value(t, strings.contains(output, ": f32 = 0.0"), true)
    testing.expect_value(t, strings.contains(output, ": f32 = 1.0"), true)
    testing.expect_value(t, strings.contains(output, ": Status = .OK"), true)
    testing.expect_value(t, strings.contains(output, "has_key :: proc(lookup: map[string]int, key: string) -> bool {\n    return (key) in (lookup)\n}"), true)
    testing.expect_value(t, strings.contains(output, "contains_key :: proc(lookup: map[string]int, key: string) -> bool {\n    return (key) in (lookup)\n}"), true)
    testing.expect_value(t, strings.contains(output, "missing_key :: proc(lookup: map[string]int, key: string) -> bool {\n    return !((key) in (lookup))\n}"), true)
}

@(test)
reject_nary_not_equal :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [a: int, b: int, c: int] -> bool
  (!= a b c))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "!= expects exactly two arguments")
}

@(test)
reject_removed_in_question_with_canonical_message :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [lookup: map[string]int, key: string] -> bool
  (in? key lookup))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "`in?` has been removed; use `contains?`")
}

@(test)
reject_contains_question_string_needle_with_canonical_message :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [] -> bool
  (contains? "abc" 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "contains? on strings expects a string needle")
}

@(test)
compile_explicit_core_package_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn main []
  (let [xs [1 2 3]
        lookup {"one" 1}]
    (println (count xs)
             (empty? xs)
             (contains? xs 2)
             (contains? lookup "one"))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_contains_value((xs)[:], 2)"), true)
    testing.expect_value(t, strings.contains(output, "(\"one\") in (lookup)"), true)
}

@(test)
compile_union_type_switch :: proc(t: ^testing.T) {
    source := `(package main)

(defunion Value {
  i: int
  s: string
})

(defn describe [value: Value] -> string
  (switch [v value]
    int "int"
    string v
    :else "nil"))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Value :: union {
    int,
    string,
}

describe :: proc(value: Value) -> string {
    switch v in value {
    case int:
        return "int"
    case string:
        return v
    case:
        return "nil"
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_case_with_union_payload_patterns :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Connected {
  id: int
})

(defstruct Disconnected {
  id: int
  reason: string
})

(defstruct Data {
  id: int
  payload: string
})

(defunion Event {
  connected: Connected
  disconnected: Disconnected
  data: Data
})

(defn event-score [event: Event] -> int
  (case event
    (Connected conn) conn.id
    (Disconnected disc) (len disc.reason)
    (Data data) (len data.payload)
    :else 0))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "switch kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, " in event {"), true)
    testing.expect_value(t, strings.contains(output, "case Connected:"), true)
    testing.expect_value(t, strings.contains(output, "conn := kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, "return conn.id"), true)
    testing.expect_value(t, strings.contains(output, "case Disconnected:"), true)
    testing.expect_value(t, strings.contains(output, "disc := kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, "return len(disc.reason)"), true)
    testing.expect_value(t, strings.contains(output, "case Data:"), true)
    testing.expect_value(t, strings.contains(output, "data := kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, "return len(data.payload)"), true)
    testing.expect_value(t, strings.contains(output, "case:\n        return 0"), true)
}

@(test)
compile_case_with_ignored_union_payload :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Connected {
  id: int
})

(defstruct Data {
  payload: string
})

(defunion Event {
  connected: Connected
  data: Data
})

(defn event-score [event: Event] -> int
  (case event
    (Connected _) 1
    (Data data) (len data.payload)
    :else 0))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "case Connected:\n        return 1"), true)
    testing.expect_value(t, strings.contains(output, "_ := kvist_case_"), false)
    testing.expect_value(t, strings.contains(output, "data := kvist_case_"), true)
}

@(test)
compile_case_flat_union_payload_arm_with_do_body :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct Connected {
  id: int
})

(defstruct Disconnected {
  reason: string
})

(defunion Event {
  connected: Connected
  disconnected: Disconnected
})

(defn event-score [event: Event] -> int
  (case event
    (Connected conn) conn.id
    (Disconnected disc) (do
                          (println disc.reason)
                          0)
    :else -1))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "case Connected:"), true)
    testing.expect_value(t, strings.contains(output, "conn := kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, "return conn.id"), true)
    testing.expect_value(t, strings.contains(output, "case Disconnected:"), true)
    testing.expect_value(t, strings.contains(output, "disc := kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, "fmt.println(disc.reason)"), true)
    testing.expect_value(t, strings.contains(output, "return 0"), true)
    testing.expect_value(t, strings.contains(output, "case:\n        return -1"), true)
}

@(test)
reject_case_mixing_value_and_type_patterns :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Connected {
  id: int
})

(defunion Event {
  connected: Connected
})

(defn event-score [event: Event] -> int
  (case event
    (Connected conn) conn.id
    .Other 0
    :else -1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "type case expects (Type binding)")
}

@(test)
reject_case_type_pattern_shape :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Connected {
  id: int
})

(defunion Event {
  connected: Connected
})

(defn event-score [event: Event] -> int
  (case event
    (Connected) 1
    :else 0))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "type case expects (Type binding)")
}

@(test)
compile_cond_with_final_else :: proc(t: ^testing.T) {
    source := `(package main)

(defn classify [n: int] -> string
  (cond
    (< n 0) "negative"
    (= n 0) "zero"
    :else "positive"))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

classify :: proc(n: int) -> string {
    if (n) < (0) {
        return "negative"
    }
    else if (n) == (0) {
        return "zero"
    }
    else {
        return "positive"
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_cond_vector_clauses :: proc(t: ^testing.T) {
    source := `(package main)

(defn classify [n: int] -> string
  (cond
    [(< n 0) "negative"]
    [:else "non-negative"]))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "if (n) < (0) {"), true)
    testing.expect_value(t, strings.contains(output, "return \"negative\""), true)
    testing.expect_value(t, strings.contains(output, "else {"), true)
    testing.expect_value(t, strings.contains(output, "return \"non-negative\""), true)
}

@(test)
implicit_returns_only_apply_to_final_nested_blocks :: proc(t: ^testing.T) {
    source := `(package main)

(defn trace [x: int]
  (return))

(defn choose [flag: bool] -> int
  (let [x 1]
    (trace x))
  (if flag
    (trace 2)
    (trace 3))
  4)

(defn total [xs: []int] -> int
  (let [sum 0]
    (each [x xs]
      (set! sum (+ sum x))
      (trace sum))
    sum))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

trace :: proc(x: int) {
    return
}

choose :: proc(flag: bool) -> int {
    {
        x := 1
        trace(x)
    }
    if flag {
        trace(2)
    }
    else {
        trace(3)
    }
    return 4
}

total :: proc(xs: []int) -> int {
    sum := 0
    for x in xs {
        sum = (sum) + (x)
        trace(sum)
    }
    return sum
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_break_and_continue_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defn first-positive [xs: []int] -> int
  (let [result 0]
    (each [x xs]
      (when (< x 0)
        (continue))
      (when (> x 0)
        (set! result x)
        (break)))
    result))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

first_positive :: proc(xs: []int) -> int {
    result := 0
    for x in xs {
        if (x) < (0) {
            continue
        }
        if (x) > (0) {
            result = x
            break
        }
    }
    return result
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_for_statement_loop_form_is_removed :: proc(t: ^testing.T) {
    source := `(package main)

(defn total [xs: []int] -> int
  (let [sum 0]
    (for [x xs]
      (set! sum (+ sum x)))
    sum))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "`for` is a comprehension; use `each` for collection loops or `while` for condition loops")
}

@(test)
compile_each_iteration_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defn score-array [xs: [dynamic]int] -> int
  (let [total 0]
    (each [i x xs]
      (set! total (+ total i x)))
    total))

(defn score-map [counts: map[string]int] -> int
  (let [total 0]
    (each [key value counts]
      (set! total (+ total value)))
    total))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "for i, x in xs {"), true)
    testing.expect_value(t, strings.contains(output, "for key, value in counts {"), true)
}

@(test)
compile_each_collection_and_while_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defn score [xs: []int] -> int
  (let [total 0]
    (each [x xs]
      (mut! total += x))
    total))

(defn spin []
  (while true
    (break)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

score :: proc(xs: []int) -> int {
    total := 0
    for x in xs {
        total += x
    }
    return total
}

spin :: proc() {
    for true {
        break
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_for_comprehension_infers_bound_value_output :: proc(t: ^testing.T) {
    source := `(package main)

(defn copy [xs: []int] -> [dynamic]int
  (for [x xs]
    x))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return (proc(xs: []int) -> [dynamic]int {"), true)
    testing.expect_value(t, strings.contains(output, "out := make([dynamic]int)"), true)
    testing.expect_value(t, strings.contains(output, "for x in xs {"), true)
    testing.expect_value(t, strings.contains(output, "append(&out, x)"), true)
    testing.expect_value(t, strings.contains(output, "return out"), true)
}

@(test)
compile_for_comprehension_supports_when_and_explicit_output_type :: proc(t: ^testing.T) {
    source := `(package main)

(defn next-even-values [xs: []int] -> [dynamic]int
  (for [x xs
        :when (= (% x 2) 0)]
    :into [dynamic]int
    (+ x 1)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "if !("), true)
    testing.expect_value(t, strings.contains(output, "continue"), true)
    testing.expect_value(t, strings.contains(output, "append(&out, (x) + (1))"), true)
}

@(test)
compile_for_comprehension_requires_output_type_when_it_cannot_infer :: proc(t: ^testing.T) {
    source := `(package main)

(defn next-values [xs: []int] -> [dynamic]int
  (for [x xs]
    (+ x 1)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, strings.contains(err.message, "add :into [dynamic]T"), true)
}

@(test)
compile_for_comprehension_supports_let_and_while :: proc(t: ^testing.T) {
    source := `(package main)

(defn prefix-squares [xs: []int, limit: int] -> [dynamic]int
  (for [x xs :while (< x limit) :let [square (* x x)]]
    :into [dynamic]int
    square))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "for x in xs {"), true)
    testing.expect_value(t, strings.contains(output, "if !((x) < (limit)) {"), true)
    testing.expect_value(t, strings.contains(output, "break"), true)
    testing.expect_value(t, strings.contains(output, "square := (x) * (x)"), true)
    testing.expect_value(t, strings.contains(output, "append(&out, square)"), true)
}

@(test)
compile_for_comprehension_supports_map_output :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User {
  name: string
  age: int
})

(defn users-by-name [users: []User] -> map[string]User
  (for [user users :when (> user.age 10)]
    :into map[string]User
    [user.name user]))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return (proc(users: []User) -> map[string]User {"), true)
    testing.expect_value(t, strings.contains(output, "out := make(map[string]User)"), true)
    testing.expect_value(t, strings.contains(output, "if !((user.age) > (10)) {"), true)
    testing.expect_value(t, strings.contains(output, "out[user.name] = user"), true)
}

@(test)
compile_for_comprehension_supports_set_output :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User {
  id: string
  active: bool
})

(defn active-ids [users: []User] -> set[string]
  (for [user users :when user.active]
    :into set[string]
    user.id))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return (proc(users: []User) -> map[string]struct{} {"), true)
    testing.expect_value(t, strings.contains(output, "out := make(map[string]struct{})"), true)
    testing.expect_value(t, strings.contains(output, "if !(user.active) {"), true)
    testing.expect_value(t, strings.contains(output, "out[user.id] = {}"), true)
}

@(test)
compile_for_comprehension_rejects_map_output_without_pair_yield :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [xs: []int] -> map[int]int
  (for [x xs]
    :into map[int]int
    x))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "for comprehension map output expects yielded [key value]")
}

@(test)
compile_indexed_symbol_expr_and_places :: proc(t: ^testing.T) {
    source := `(package main)

(defn read-at [xs: []int, i: int] -> int
  xs[i])

(defn write-at [xs: [dynamic]int, i: int]
  (set! xs[i] 10)
  (mut! xs[i] += 2))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return (xs)[i]"), true)
    testing.expect_value(t, strings.contains(output, "(xs)[i] = 10"), true)
    testing.expect_value(t, strings.contains(output, "(xs)[i] += 2"), true)
}

@(test)
compile_indexed_field_symbol_places :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Columns {x: [dynamic]f32})

(defn step [cols: Columns, i: int, dx: f32] -> f32
  (mut! cols.x[i] += dx)
  cols.x[i])`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "(cols.x)[i] += dx"), true)
    testing.expect_value(t, strings.contains(output, "return (cols.x)[i]"), true)
}

@(test)
compile_expression_index_places :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct State {cells: [dynamic]int})

(defstruct User {name: string})

(defstruct User-State {users: [dynamic]User})

(defn idx [x: int, y: int] -> int
  (+ x (* y 10)))

(defn touch [state: State, x: int, y: int] -> int
  (set! state.cells[(idx x y)] 10)
  (mut! state.cells[(idx x y)] += 2)
  state.cells[(idx x y)])

(defn pick-name [state: User-State, x: int, y: int] -> string
  state.users[(idx x y)].name)

(defn read-matrix [matrix: [][]int, row: int, col: int] -> int
  matrix[row][col])

(defn slice-views [xs: []int, start: int, end: int] -> int
  (let [all xs[:]
        tail xs[start:]
        head xs[:end]
        mid xs[start:end]
        next xs[(+ start 1):(+ end 1)]]
    (+ (count all)
       (count tail)
       (count head)
       (count mid)
       (count next))))

(defn write-matrix [matrix: [dynamic][dynamic]int, row: int, col: int]
  (set! matrix[row][col] 42)
  (mut! matrix[row][col] += 1))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "(state.cells)[idx(x, y)] = 10"), true)
    testing.expect_value(t, strings.contains(output, "(state.cells)[idx(x, y)] += 2"), true)
    testing.expect_value(t, strings.contains(output, "return (state.cells)[idx(x, y)]"), true)
    testing.expect_value(t, strings.contains(output, "return (state.users)[idx(x, y)].name"), true)
    testing.expect_value(t, strings.contains(output, "return ((matrix)[row])[col]"), true)
    testing.expect_value(t, strings.contains(output, "all := (xs)[:]"), true)
    testing.expect_value(t, strings.contains(output, "tail := (xs)[start:]"), true)
    testing.expect_value(t, strings.contains(output, "head := (xs)[:end]"), true)
    testing.expect_value(t, strings.contains(output, "mid := (xs)[start:end]"), true)
    testing.expect_value(t, strings.contains(output, "next := (xs)[(start) + (1):(end) + (1)]"), true)
    testing.expect_value(t, strings.contains(output, "((matrix)[row])[col] = 42"), true)
    testing.expect_value(t, strings.contains(output, "((matrix)[row])[col] += 1"), true)
}

@(test)
compile_loop_form_is_removed :: proc(t: ^testing.T) {
    source := `(package main)

(defn spin []
  (loop true
    (break)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "`loop` has been removed; use `each` for collection iteration or `while` for condition loops")
}

@(test)
compile_defer_forms :: proc(t: ^testing.T) {
    source := `(package main)
(import "core:fmt")

(defn main []
  (let [x 1]
    (defer (fmt.println x))
    (defer
      (fmt.println "done")
      (fmt.println x))
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import "core:fmt"

main :: proc() {
    x := 1
    defer fmt.println(x)
    defer {
        fmt.println("done")
        fmt.println(x)
    }
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_flat_multi_return_binding :: proc(t: ^testing.T) {
    source := `(package main)

(defn query [] -> [value: int, ok: bool]
  (return 42 true))

(defn main []
  (let [[value ok] (query)
        [_, still-ok] (query)]
    (when (and ok still-ok)
      (return))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

query :: proc() -> (value: int, ok: bool) {
    return 42, true
}

main :: proc() {
    value, ok := query()
    _, still_ok := query()
    if (ok) && (still_ok) {
        return
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
implicit_core_when_helper :: proc(t: ^testing.T) {
    source := `(package main)

(defn main [ok: bool]
  (when ok
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "if ok {"), true)
}

@(test)
implicit_core_cond_helper :: proc(t: ^testing.T) {
    source := `(package main)

(defn classify [n: int] -> string
  (cond
    (< n 0) "negative"
    :else "non-negative"))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "else {"), true)
}

@(test)
implicit_core_comment_helper :: proc(t: ^testing.T) {
    source := `(package main)
(comment
  (fmt.println "ignored"))

(defn main []
  (return))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "main :: proc()"), true)
}

@(test)
implicit_core_switch_helper :: proc(t: ^testing.T) {
    source := `(package main)

(defn classify [n: int] -> string
  (switch n
    0 "zero"
    :else "other"))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "#partial switch n"), true)
}

@(test)
compile_switch_emits_compatibility_warning :: proc(t: ^testing.T) {
    source := `(package main)

(defn classify [n: int] -> string
  (switch n
    0 "zero"
    :else "other"))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "`switch` is compatibility syntax; use `case` for subject dispatch or `cond` for predicate branches")
    }
}

@(test)
compile_case_does_not_emit_switch_warning :: proc(t: ^testing.T) {
    source := `(package main)

(defn classify [n: int] -> string
  (case n
    0 "zero"
    :else "other"))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_when_let_macro :: proc(t: ^testing.T) {
    source := `(package main)

(defn query [] -> [value: int, found: bool]
  (return 42 true))

(defn main []
  (when-let [value found (query)]
    (when (> value 40)
      (return))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

query :: proc() -> (value: int, found: bool) {
    return 42, true
}

main :: proc() {
    value, found := query()
    if found {
        if (value) > (40) {
            return
        }
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_if_let_macro :: proc(t: ^testing.T) {
    source := `(package main)

(defn query [] -> [value: int, found: bool]
  (return 42 true))

(defn main [] -> int
  (if-let [value found (query)]
    value
    0))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

query :: proc() -> (value: int, found: bool) {
    return 42, true
}

main :: proc() -> int {
    value, found := query()
    if found {
        return value
    }
    else {
        return 0
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_if_ok_macro :: proc(t: ^testing.T) {
    source := `(package main)
(import os "core:os")

(defn read-count [] -> [value: int, err: os.Error]
  (return 42 nil))

(defn main [] -> int
  (if-ok [value err (read-count)]
    value
    0))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "value, err := read_count()"), true)
    testing.expect_value(t, strings.contains(output, "if (err) == ({})"), true)
    testing.expect_value(t, strings.contains(output, "return value"), true)
    testing.expect_value(t, strings.contains(output, "return 0"), true)
}

@(test)
compile_when_ok_macro :: proc(t: ^testing.T) {
    source := `(package main)
(import os "core:os")

(defn read-count [] -> [value: int, err: os.Error]
  (return 42 nil))

(defn main [] -> int
  (let [total 0]
    (when-ok [value err (read-count)]
      (set! total value))
    total))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "value, err := read_count()"), true)
    testing.expect_value(t, strings.contains(output, "if (err) == ({})"), true)
    testing.expect_value(t, strings.contains(output, "total = value"), true)
    testing.expect_value(t, strings.contains(output, "return total"), true)
}

@(test)
compile_file_dev_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import io "kvist:io")
(import os "core:os")

(defn read-file [path: string] -> [data: []byte, err: os.Error]
  (io.read path))

(defn write-text [path: string, text: string] -> os.Error
  (io.write path text))

(defn read-count [path: string] -> int
  (let [[data err] (io.read path)]
    (if (!= err nil)
      0
      (do
        (defer (delete data))
        (len data)))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "read_file :: proc(path: string) -> (data: []byte, err: os.Error)"), true)
    testing.expect_value(t, strings.contains(output, "io__read :: #force_inline proc(path: string) -> (data: []byte, err: os.Error)"), true)
    testing.expect_value(t, strings.contains(output, "io__write :: #force_inline proc(path: string, data: $T) -> os.Error"), true)
    testing.expect_value(t, strings.contains(output, "return io__read(path)"), true)
    testing.expect_value(t, strings.contains(output, "return io__write(path, text)"), true)
    testing.expect_value(t, strings.contains(output, "data, err := io__read(path)"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(data)"), true)
}

@(test)
compile_json_interop_is_explicit :: proc(t: ^testing.T) {
    source := `(package main)
(import json "kvist:json")

(defstruct User {
  name: string
  age: int
})

(defn save-user [path: string, user: User] -> bool
  (let [[marshal-err write-err] (json.write path user)]
    (and (= marshal-err nil)
         (= write-err nil))))

(defn load-user [path: string] -> bool
  (let [[user read-err unmarshal-err] (json.read-as User path)]
    (and (= read-err nil)
         (= unmarshal-err nil))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "json__write :: #force_inline proc"), true)
    testing.expect_value(t, strings.contains(output, "json__read_as :: #force_inline proc"), true)
    testing.expect_value(t, strings.contains(output, "marshal_err, write_err := json__write(path, user)"), true)
    testing.expect_value(t, strings.contains(output, "user, read_err, unmarshal_err := json__read_as(User, path)"), true)
}

@(test)
compile_http_server_surface_is_explicit :: proc(t: ^testing.T) {
    output, err, ok := kvist.compile_path("examples/web/http-server.kvist")
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "vendor/odin-http"), true)
    testing.expect_value(t, strings.contains(output, "http__new_router :: proc() -> h.Router"), true)
    testing.expect_value(t, strings.contains(output, "http__new_server :: proc() -> h.Server"), true)
    testing.expect_value(t, strings.contains(output, "router := http__new_router()"), true)
    testing.expect_value(t, strings.contains(output, "server := http__new_server()"), true)
    testing.expect_value(t, strings.contains(output, "defer h.router_destroy(&router)"), true)
    testing.expect_value(t, strings.contains(output, "h.router_init(&router)"), true)
    testing.expect_value(t, strings.contains(output, "h.route_get("), true)
    testing.expect_value(t, strings.contains(output, "\"/ping\""), true)
    testing.expect_value(t, strings.contains(output, "h.respond_plain(res, \"pong\")"), true)
    testing.expect_value(t, strings.contains(output, "h.respond_json(res, Greeting{message = fmt.tprintf(\"hello %s\", (params)[0])})"), true)
    testing.expect_value(t, strings.contains(output, "h.server_shutdown_on_interrupt(&server)"), true)
    testing.expect_value(t, strings.contains(output, "h.listen_and_serve(&server, h.router_handler(&router), net.Endpoint{address = net.IP4_Loopback, port = 6969})"), true)
}

@(test)
compile_http_client_surface_is_explicit :: proc(t: ^testing.T) {
    output, err, ok := kvist.compile_path("examples/web/http-client.kvist")
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "vendor/odin-http/client"), true)
    testing.expect_value(t, strings.contains(output, "httpc__new_request :: proc(method: h.Method) -> hc.Request"), true)
    testing.expect_value(t, strings.contains(output, "res, err := hc.get(\"http://127.0.0.1:6969/ping\")"), true)
    testing.expect_value(t, strings.contains(output, "defer hc.response_destroy(&res)"), true)
    testing.expect_value(t, strings.contains(output, "req := httpc__new_request(.Post)"), true)
    testing.expect_value(t, strings.contains(output, "defer hc.request_destroy(&req)"), true)
    testing.expect_value(t, strings.contains(output, "h.headers_set_unsafe(&(req.headers), \"x-api-key\", \"demo\")"), true)
    testing.expect_value(t, strings.contains(output, "append(&(req.cookies), h.Cookie{name = \"session\", value = \"abc123\"})"), true)
    testing.expect_value(t, strings.contains(output, "json_err := hc.with_json(&req, Greeting{message = \"hello\"})"), true)
    testing.expect_value(t, strings.contains(output, "res, err := hc.request(&req, \"http://127.0.0.1:6969/hello\")"), true)
}

@(test)
compile_http_handler_surface_is_explicit :: proc(t: ^testing.T) {
    path, ok_path := repo_temp_test_path(".tmp-http-handler-test.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)
    defer os.remove(path)

    source := `(package main)
(import http "kvist:http")

(defn main []
  (let [router (http.new-router)
        server (http.new-server)]
    (defer (http.router-destroy! router))
    (http.get! router "/ping" [req res]
      (http.respond-plain res "pong"))
    (let [app (http.router-handler router)]
      (http.server-shutdown-on-interrupt! server)
      (http.listen! server 6969)
      (http.serve-handler! server app))))`

    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "app := h.router_handler(&router)"), true)
    testing.expect_value(t, strings.contains(output, "h.listen(&server, net.Endpoint{address = net.IP4_Loopback, port = 6969})"), true)
    testing.expect_value(t, strings.contains(output, "h.serve(&server, app)"), true)
}

@(test)
compile_http_rate_limit_surface_is_explicit :: proc(t: ^testing.T) {
    path, ok_path := repo_temp_test_path(".tmp-http-rate-limit-test.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)
    defer os.remove(path)

    source := `(package main)
(import http "kvist:http")
(import time "core:time")

(defn main []
  (let [router (http.new-router)
        server (http.new-server)
        opts (http.new-rate-limit-opts (* 60 time.Second) 100)
        data (http.new-rate-limit-data)]
    (defer (http.router-destroy! router))
    (defer (http.rate-limit-destroy! data))
    (http.get! router "/ping" [req res]
      (http.respond-plain res "pong"))
    (let [base (http.router-handler router)
          app (http.rate-limit data base opts)]
      (http.server-shutdown-on-interrupt! server)
      (http.listen! server 6969)
      (http.serve-handler! server app))))`

    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "http__new_rate_limit_opts :: proc(window: time.Duration, max: int) -> h.Rate_Limit_Opts"), true)
    testing.expect_value(t, strings.contains(output, "http__new_rate_limit_data :: proc() -> h.Rate_Limit_Data"), true)
    testing.expect_value(t, strings.contains(output, "opts := http__new_rate_limit_opts((60) * (time.Second), 100)"), true)
    testing.expect_value(t, strings.contains(output, "data := http__new_rate_limit_data()"), true)
    testing.expect_value(t, strings.contains(output, "defer h.rate_limit_destroy(&data)"), true)
    testing.expect_value(t, strings.contains(output, "base := h.router_handler(&router)"), true)
    testing.expect_value(t, strings.contains(output, "app := h.rate_limit(&data, &base, &opts)"), true)
    testing.expect_value(t, strings.contains(output, "h.serve(&server, app)"), true)
}

@(test)
compile_http_session_surface_is_explicit :: proc(t: ^testing.T) {
    output, err, ok := kvist.compile_path("examples/web/http-session.kvist")
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "session__request_method_line :: proc(req: ^h.Request) -> h.Method"), true)
    testing.expect_value(t, strings.contains(output, "line := (req.line).(h.Requestline)"), true)
    testing.expect_value(t, strings.contains(output, "opts := session__new_opts(\"sid\", \"csrf\", new_sid, csrf_for, request_csrf)"), true)
    testing.expect_value(t, strings.contains(output, "request_csrf :: proc(req: ^h.Request) -> string"), true)
    testing.expect_value(t, strings.contains(output, "plan := session__plan(req, opts)"), true)
    testing.expect_value(t, strings.contains(output, "if (plan.action) != (.Reject)"), true)
    testing.expect_value(t, strings.contains(output, "append(&(res^.cookies)"), true)
}

@(test)
compile_http_sse_surface_is_explicit :: proc(t: ^testing.T) {
    output, err, ok := kvist.compile_path("examples/web/http-sse.kvist")
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "sse____kvist_http_sse_new_started :: proc(res: ^h.Response) -> ^h.Sse"), true)
    testing.expect_value(t, strings.contains(output, "stream := sse____kvist_http_sse_new_started(res)"), true)
    testing.expect_value(t, strings.contains(output, "h.sse_event(stream, h.Sse_Event{comment = \"connected\"})"), true)
    testing.expect_value(t, strings.contains(output, "h.sse_event(stream, h.Sse_Event{retry = 1000})"), true)
    testing.expect_value(t, strings.contains(output, "h.sse_event(stream, h.Sse_Event{event = \"welcome\", data = \"ready\"})"), true)
    testing.expect_value(t, strings.contains(output, "h.sse_end(stream)"), true)
}

@(test)
compile_http_datastar_surface_is_explicit :: proc(t: ^testing.T) {
    output, err, ok := kvist.compile_path("examples/web/http-datastar.kvist")
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "import strings \"core:strings\""), true)
    testing.expect_value(t, strings.contains(output, "event = \"datastar-patch-elements\""), true)
    testing.expect_value(t, strings.contains(output, "event = \"datastar-patch-signals\""), true)
    testing.expect_value(t, strings.contains(output, "dstar__patch_elements_helper(stream, "), true)
    testing.expect_value(t, strings.contains(output, "dstar__patch_signals_helper(stream, "), true)
    testing.expect_value(t, strings.contains(output, "dstar__execute_script_helper(stream, "), true)
    testing.expect_value(t, strings.contains(output, "\"body\", \"append\""), true)
    testing.expect_value(t, strings.contains(output, "window.location = '"), true)
}

@(test)
compile_tap_helper :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")
(import "core:fmt")

(defn main []
  (let [answer (tap> "answer" 42)
        owned (tap> "owned" ([dynamic]int [1 2 3]))]
    (defer (delete owned))
    (fmt.println answer)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "answer := kvist_tap_labeled(\"answer\", 42)"), true)
    testing.expect_value(t, strings.contains(output, "owned := kvist_tap_labeled(\"owned\", [dynamic]int{1, 2, 3})"), true)
    testing.expect_value(t, strings.contains(output, "kvist_tap :: proc(value: $T) -> T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_tap_labeled :: proc(label: string, value: $T) -> T"), true)
    testing.expect_value(t, strings.contains(output, "fmt.print(label)"), true)
    testing.expect_value(t, strings.contains(output, "fmt.println(value)"), true)
}

@(test)
reject_tap_label_with_canonical_message :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [] -> int
  (tap> 1 2))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "tap> label must be a string literal")
}

@(test)
compile_tap_thread_steps :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")
(import "core:fmt")

(defn inc [x: int] -> int
  (+ x 1))

(defn even? [x: int] -> bool
  (= (% x 2) 0))

(defn add [acc: int, x: int] -> int
  (+ acc x))

(defn main []
  (let [xs ([]int [1 2 3 4])
        answer (-> 41
                   inc
                   (tap> "answer"))
        mapped (->> xs
                    (arr.map inc)
                    (tap> "mapped"))
        total (->> xs
                   (arr.map inc)
                   (tap> "mapped")
                   (arr.filter even?)
                   (arr.reduce add 0))]
    (defer (delete mapped))
    (fmt.println answer total)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "answer := kvist_tap_labeled(\"answer\", inc(41))"), true)
    testing.expect_value(t, strings.contains(output, "mapped := kvist_tap_labeled(\"mapped\", kvist_map(inc, (xs)[:]))"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_1 := kvist_map(inc, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_2 := kvist_filter(even_p, (kvist_tap_labeled(\"mapped\", kvist_thread_1))[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_2)"), true)
    testing.expect_value(t, strings.contains(output, "total := kvist_reduce(add, 0, (kvist_thread_2)[:])"), true)
}

@(test)
compile_let_rejects_field_destructuring :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User {
  name: string
  age: int
})

(defn main []
  (let [user (User {name: "Ada" age: 36})
        {name: user-name age: user-age} user
        user-name user.name
        user-age user.age]
    (return)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "field destructuring has been removed"), true)
}

@(test)
compile_field_access_on_call_result :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User {
  name: string
  age: int
})

(defn make-user [] -> User
  (User {name: "Ada" age: 36}))

(defn main [] -> string
  (make-user).name)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return make_user().name"), true)
}

@(test)
compile_proc_params_reject_field_destructuring :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point {
  x: int
  y: int
})

(defn draw [{keys: [x y] as: point}: Point] -> int
  (+ x y))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "field destructuring parameters have been removed"), true)
}

@(test)
compile_with_allocator_scope :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (with-allocator [allocator context.temp_allocator]
    (let [buffer (make [dynamic]int)]
      (defer (delete buffer))
      (arr.into! buffer ([]int [1 2]))
      (return))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

main :: proc() {
    {
        allocator := context.temp_allocator
        kvist_old_allocator_1 := context.allocator
        context.allocator = allocator
        defer context.allocator = kvist_old_allocator_1
        buffer := make([dynamic]int)
        defer delete(buffer)
        append(&(buffer), ..[]int{1, 2})
        return
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_with_temp_allocator_scope :: proc(t: ^testing.T) {
    source := `(package main)
(import runtime "base:runtime")

(defn main []
  (with-temp-allocator [allocator]
    (let [buffer (make [dynamic]int)]
      (defer (delete buffer))
      (arr.into! buffer ([]int [1 2]))
      (return))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import runtime "base:runtime"

main :: proc() {
    {
        kvist_temp_scope_1 := runtime.default_temp_allocator_temp_begin()
        defer runtime.default_temp_allocator_temp_end(kvist_temp_scope_1)
        allocator := context.temp_allocator
        kvist_old_allocator_2 := context.allocator
        context.allocator = allocator
        defer context.allocator = kvist_old_allocator_2
        buffer := make([dynamic]int)
        defer delete(buffer)
        append(&(buffer), ..[]int{1, 2})
        return
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_let_defer_scope :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn inc [x: int] -> int
  (+ x 1))

(defn even? [x: int] -> bool
  (= (% x 2) 0))

(defn add [acc: int, x: int] -> int
  (+ acc x))

(defn total [xs: []int] -> int
  (let [mapped (arr.map inc xs) defer
        filtered (arr.filter even? mapped) defer]
    (arr.reduce add 0 filtered)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "mapped := arr__map_impl(inc, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(mapped)"), true)
    testing.expect_value(t, strings.contains(output, "filtered := arr__filter_impl(even_p, (mapped)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(filtered)"), true)
    testing.expect_value(t, strings.contains(output, "return arr__reduce_impl(add, 0, (filtered)[0:])"), true)
}

@(test)
compile_with_temp_allocator_final_scalar_use :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")
(import runtime "base:runtime")

(defn total [] -> int
  (with-temp-allocator [allocator]
    (let [xs ([dynamic]int [1 2]) ]
      (defer (delete xs))
      (count xs))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "runtime.default_temp_allocator_temp_begin"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(xs)"), true)
    testing.expect_value(t, strings.contains(output, "return len((xs)[:])"), true)
}

@(test)
compile_let_or_return_ok_binding :: proc(t: ^testing.T) {
    source := `(package main)

(defn next [] -> [value: int, ok: bool]
  (return 1 true))

(defn total [] -> [value: int, ok: bool]
  (let [[value ok] (next) or-return]
    (return (+ value 1) true)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "value, ok = next()"), true)
    testing.expect_value(t, strings.contains(output, "return"), true)
}

@(test)
compile_let_or_break_err_binding_with_defer :: proc(t: ^testing.T) {
    source := `(package main)

(defn read-text [path: string] -> [data: [dynamic]byte, err: rawptr]
  (return ([dynamic]byte [1 2]) nil))

(defn load [path: string]
  (while true
    (let [[data err] (read-text path) or-break defer]
      (println data))
    (break)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "data, err := read_text(path)"), true)
    testing.expect_value(t, strings.contains(output, "err != nil"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(data)"), true)
}

@(test)
compile_body_only_while_loop :: proc(t: ^testing.T) {
    source := `(package main)

(defn run []
  (while true
    (do
      (println "tick")
      (break))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "for true {"), true)
    testing.expect_value(t, strings.contains(output, "fmt.println(\"tick\")"), true)
    testing.expect_value(t, strings.contains(output, "break"), true)
}

@(test)
reject_let_or_return_without_matching_named_returns :: proc(t: ^testing.T) {
    source := `(package main)

(defn next [] -> [value: int, ok: bool]
  (return 1 true))

(defn total [] -> int
  (let [[value ok] (next) or-return]
    value))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "or-return currently requires proc named returns matching the binding names exactly")
}

@(test)
compile_let_or_break_and_or_continue_bindings :: proc(t: ^testing.T) {
    source := `(package main)

(defn next [] -> [value: int, ok: bool]
  (return 1 true))

(defn demo []
  (while true
    (let [[value ok] (next) or-break]
      (println value))
    (let [[value ok] (next) or-continue]
      (println value))
    (break)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "break"), true)
    testing.expect_value(t, strings.contains(output, "continue"), true)
}

@(test)
compile_or_else_optional_ok_expression :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn query [] -> [value: int, ok: bool] #optional_ok
  (return 42 true))

(defn total [] -> int
  (or-else (query) 7))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return query() or_else 7"), true)
}

@(test)
compile_shipped_test_macro_package :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-test-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package tests)

(import t "kvist:test")

(t.deftest sample
  (t.is true))`

    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "import \"core:testing\""), true)
    testing.expect_value(t, strings.contains(output, "@(test)"), true)
    testing.expect_value(t, strings.contains(output, "sample :: proc(t: ^testing.T) {"), true)
    testing.expect_value(t, strings.contains(output, "t____kvist_test_expect(t, true, \"\")"), true)
}

compiler_test_repo_root :: proc(loc := #caller_location) -> string {
    file_path := loc.file_path
    if !os.is_absolute_path(file_path) {
        absolute, err := os.get_absolute_path(file_path, context.temp_allocator)
        if err == nil {
            file_path = absolute
        }
    }
    tests_dir, _ := os.split_path(file_path)
    root, _ := os.split_path(tests_dir)
    return root
}

build_test_kvist_binary :: proc(t: ^testing.T, repo_root, dir: string) -> (path: string, ok: bool) {
    bin_path, join_err := os.join_path({dir, "kvist-test-bin"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return "", false
    }

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {"odin", "build", "cmd/kvist", fmt.tprintf("-out:%s", bin_path)},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        delete(bin_path)
        return "", false
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    if !state.exited || state.exit_code != 0 {
        delete(bin_path)
        return "", false
    }
    return bin_path, true
}

@(test)
compile_extended_shipped_test_macro_package :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-test-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package tests)

(import t "kvist:test")

(defn each-fixture [t: ^testing.T, body: fn [t: ^testing.T]]
  (body t))

(t.use-fixtures each: each-fixture)

(t.deftest sample
  "Sample test."
  (t.testing "numbers"
    (t.testing "parity"
    (t.is (= 1 1))
    (t.is (not false))
    (t.is (= (+ 1 1) 2))
    (t.are [x expected]
      (= x expected)
      1 1
      2 2))))`

    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "sample :: proc(t: ^testing.T) {"), true)
    testing.expect_value(t, strings.contains(output, "each_fixture("), true)
    testing.expect_value(t, strings.contains(output, "proc(t: ^testing.T) {"), true)
    testing.expect_value(t, strings.contains(output, "t____kvist_test_push_context(t, \"numbers\")"), true)
    testing.expect_value(t, strings.contains(output, "t____kvist_test_push_context(t, \"parity\")"), true)
    testing.expect_value(t, strings.contains(output, "defer t____kvist_test_pop_context(t)"), true)
    testing.expect_value(t, strings.contains(output, "t____kvist_test_expect_value(t, 1, 1)"), true)
    testing.expect_value(t, strings.contains(output, "t____kvist_test_expect(t, !(false), \"\")"), true)
    testing.expect_value(t, strings.contains(output, "t____kvist_test_expect_value(t, (1) + (1), 2)"), true)
    testing.expect_value(t, strings.contains(output, "t____kvist_test_expect_value(t, 2, 2)"), true)
}

@(test)
compile_shipped_test_once_fixtures :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-test-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package tests)

(import t "kvist:test")

(defvar fixture-count: int 0)

(defn once-fixture []
  (set! fixture-count (+ fixture-count 1)))

(t.use-fixtures once: once-fixture)

(t.deftest first
  (t.is (= fixture-count 1)))

(t.deftest second
  (t.is (= fixture-count 1)))`

    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "__kvist_test_once_guard"), true)
    testing.expect_value(t, strings.contains(output, "__kvist_test_ensure_once()"), true)
    testing.expect_value(t, strings.contains(output, "once_fixture()"), true)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "test", path},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
}

@(test)
compile_shipped_test_generic_assertion_messages :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-test-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package tests)

(import t "kvist:test")

(t.deftest sample
  (t.is true "ok")
  (t.is false "not ok"))`

    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `__kvist_test_expect(t, true, "ok")`), true)
    testing.expect_value(t, strings.contains(output, `__kvist_test_expect(t, false, "not ok")`), true)
}

@(test)
cli_test_command_runs_filtered_kvist_tests :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-test-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    generated, generated_err := os.join_path({dir, "generated.odin"}, context.allocator)
    testing.expect_value(t, generated_err == nil, true)
    if generated_err != nil {
        return
    }
    defer delete(generated)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    source := `(package tests)

(import t "kvist:test")

(t.deftest passing
  (t.is true))

(t.deftest failing
  (t.is false))`

    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "test", path, "--generated", generated, "--names", "passing"},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    testing.expect_value(t, os.exists(generated), true)
}

@(test)
cli_test_command_reports_testing_context :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-test-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package tests)

(import t "kvist:test")

(t.deftest failing
  (t.testing "numbers"
    (t.testing "parity"
      (t.is false "not ok"))))`

    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "test", path, "--names", "failing"},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 1)
    testing.expect_value(t, strings.contains(string(stdout), "numbers > parity: not ok") || strings.contains(string(stderr), "numbers > parity: not ok"), true)
}

@(test)
reject_or_else_wrong_arity :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn query [] -> [value: int, ok: bool] #optional_ok
  (return 42 true))

(defn total [] -> int
  (or-else (query)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "or-else expects 2 arguments")
}

@(test)
cli_reload_command_discovers_sibling_reload_adapter :: proc(t: ^testing.T) {
    repo_root := compiler_test_repo_root()
    dir, dir_err := os.make_directory_temp(repo_root, "kvist-reload-discovery-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package demo_app)

(defstruct App_State
  {ticks: int})

(defn init [state: ^App_State]
  (set! state^.ticks 0))

(defn tick [state: ^App_State]
  (mut! state^.ticks += 1))

(defn main []
  (let [state (App_State {})]
    (init &state)
    (tick &state)))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    reload_path, reload_join_err := os.join_path({dir, "reload.kvist"}, context.allocator)
    testing.expect_value(t, reload_join_err == nil, true)
    if reload_join_err != nil {
        return
    }
    defer delete(reload_path)
    reload_source := `(package demo_reload)
(import app "main")
(import reload "kvist:reload")

(defstate app.App_State
  {run: run
   init: app.init})

(defn run [state: ^app.App_State host: ^reload.Run_Host]
  (app.tick state)
  (when (reload.checkpoint! host)
    (return)))`
    reload_write_err := os.write_entire_file_from_string(reload_path, reload_source)
    testing.expect_value(t, reload_write_err == nil, true)
    if reload_write_err != nil {
        return
    }

    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "dev", "--reload", main_path, "--print-paths", "--json"},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    testing.expect_value(t, strings.contains(string(stdout), fmt.tprintf(`"input": "%s"`, reload_path)), true)
    testing.expect_value(t, strings.contains(string(stdout), "reload.kvist"), true)
}

@(test)
cli_test_command_runs_builtin_package_suite :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-builtin-package-suite-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    path, join_err := os.join_path({repo_root, "examples", "packages", "builtin-package-tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "test", path},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
}

@(test)
cli_test_command_runs_http_and_html_package_suite :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-http-html-package-suite-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    path, join_err := os.join_path({repo_root, "examples", "packages", "http-and-html-package-tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "test", path},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
}

@(test)
cli_test_command_runs_test_package_suite :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-test-package-suite-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    path, join_err := os.join_path({repo_root, "examples", "packages", "test-package-tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "test", path},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
}

@(test)
cli_test_command_runs_arr_package_suite :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-arr-package-suite-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    path, join_err := os.join_path({repo_root, "examples", "packages", "arr-package-tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "test", path},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
}

@(test)
cli_test_command_runs_package_edge_suite :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-package-edge-suite-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    path, join_err := os.join_path({repo_root, "examples", "packages", "package-edge-tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "test", path},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        return
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
}

@(test)
compile_let_defer_final_if_scalar_use :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn total [flag: bool] -> int
  (let [xs ([dynamic]int [1 2]) defer]
    (if flag
      (count xs)
      0)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "defer delete(xs)"), true)
    testing.expect_value(t, strings.contains(output, "return len((xs)[:])"), true)
}

@(test)
compile_let_defer_final_cond_scalar_use :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn total [n: int] -> int
  (let [xs ([dynamic]int [1 2]) defer]
    (cond
      (> n 0) (count xs)
      :else 0)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "defer delete(xs)"), true)
    testing.expect_value(t, strings.contains(output, "return len((xs)[:])"), true)
}

@(test)
compile_let_defer_final_switch_scalar_use :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn total [mode: int] -> int
  (let [xs ([dynamic]int [1 2]) defer]
    (switch mode
      0 0
      1 (count xs)
      :else 2)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "defer delete(xs)"), true)
    testing.expect_value(t, strings.contains(output, "return len((xs)[:])"), true)
}

@(test)
compile_let_defer_binding :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (let [xs ([dynamic]int [1 2]) defer
        answer 42]
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "xs := [dynamic]int{1, 2}"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(xs)"), true)
    testing.expect_value(t, strings.contains(output, "answer := 42"), true)
}

@(test)
reject_returning_defer_binding :: proc(t: ^testing.T) {
    source := `(package main)

(defn owned [] -> [dynamic]int
  (let [xs ([dynamic]int [1 2]) defer]
    xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "defer-marked binding cannot be returned; remove defer or transfer ownership explicitly")
}

@(test)
reject_returning_defer_binding_inside_struct_literal :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Box {
  xs: [dynamic]int
})

(defn owned [] -> Box
  (let [xs ([dynamic]int [1 2]) defer]
    (Box {xs: xs})))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "defer-marked binding cannot be returned; remove defer or transfer ownership explicitly")
}

@(test)
reject_returning_defer_binding_inside_call :: proc(t: ^testing.T) {
    source := `(package main)

(defn pass-through [xs: [dynamic]int] -> [dynamic]int
  xs)

(defn owned [] -> [dynamic]int
  (let [xs ([dynamic]int [1 2]) defer]
    (pass-through xs)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "defer-marked binding cannot be returned; remove defer or transfer ownership explicitly")
}

@(test)
reject_returning_defer_binding_through_local_wrapper :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Box {
  xs: [dynamic]int
})

(defn owned [] -> Box
  (let [xs ([dynamic]int [1 2]) defer
        box (Box {xs: xs})]
    box))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "defer-marked binding cannot be returned; remove defer or transfer ownership explicitly")
}

@(test)
reject_returning_defer_binding_through_set_bang_wrapper :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Box {
  xs: [dynamic]int
})

(defn owned [] -> Box
  (let [xs ([dynamic]int [1 2]) defer
        box (Box {xs: ([dynamic]int [])})]
    (set! box (Box {xs: xs}))
    box))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "defer-marked binding cannot be returned; remove defer or transfer ownership explicitly")
}

@(test)
reject_returning_defer_binding_in_final_if_points_to_alias_branch :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Box {
  xs: [dynamic]int
})

(defn owned [flag: bool] -> Box
  (let [xs ([dynamic]int [1 2]) defer
        box (Box {xs: xs})]
    (if flag
      box
      (Box {xs: ([dynamic]int [])}))))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "defer-marked binding cannot be returned; remove defer or transfer ownership explicitly")
    testing.expect_value(t, source[err.span.start:err.span.end], "box")
}

@(test)
reject_returning_owned_result_from_with_temp_allocator :: proc(t: ^testing.T) {
    source := `(package main)
(import runtime "base:runtime")

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [xs: []int] -> [dynamic]int
  (with-temp-allocator [allocator]
    (arr.map inc xs)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "owned value cannot escape with-temp-allocator; allocate it outside the temp scope or copy it before returning")
}

@(test)
reject_returning_owned_result_from_with_temp_allocator_through_local_wrapper :: proc(t: ^testing.T) {
    source := `(package main)
(import runtime "base:runtime")

(defstruct Box {
  xs: [dynamic]int
})

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [xs: []int] -> Box
  (with-temp-allocator [allocator]
    (let [box (Box {xs: (map inc xs)})]
      box)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "owned value cannot escape with-temp-allocator; allocate it outside the temp scope or copy it before returning")
}

@(test)
reject_returning_owned_result_from_with_temp_allocator_through_set_bang_wrapper :: proc(t: ^testing.T) {
    source := `(package main)
(import runtime "base:runtime")

(defstruct Box {
  xs: [dynamic]int
})

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [xs: []int] -> Box
  (with-temp-allocator [allocator]
    (let [box (Box {xs: ([dynamic]int [])})]
      (set! box (Box {xs: (map inc xs)}))
      box)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "owned value cannot escape with-temp-allocator; allocate it outside the temp scope or copy it before returning")
}

@(test)
reject_returning_owned_result_from_with_temp_allocator_in_final_if_points_to_alias_branch :: proc(t: ^testing.T) {
    source := `(package main)
(import runtime "base:runtime")

(defstruct Box {
  xs: [dynamic]int
})

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [xs: []int flag: bool] -> Box
  (with-temp-allocator [allocator]
    (let [box (Box {xs: (map inc xs)})]
      (if flag
        box
        (Box {xs: ([dynamic]int [])})))))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "owned value cannot escape with-temp-allocator; allocate it outside the temp scope or copy it before returning")
    testing.expect_value(t, source[err.span.start:err.span.end], "box")
}

@(test)
reject_returning_slurp_result_from_with_temp_allocator :: proc(t: ^testing.T) {
    source := `(package main)
(import io "kvist:io")
(import os "core:os")
(import runtime "base:runtime")

(defn bad [path: string] -> [data: []byte, err: os.Error]
  (with-temp-allocator [allocator]
    (io.read path)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "owned value cannot escape with-temp-allocator; allocate it outside the temp scope or copy it before returning")
}

@(test)
reject_returning_wrapped_owned_result_from_with_temp_allocator :: proc(t: ^testing.T) {
    source := `(package main)
(import runtime "base:runtime")

(defstruct Box {
  xs: [dynamic]int
})

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [xs: []int] -> Box
  (with-temp-allocator [allocator]
    (Box {xs: (arr.map inc xs)})))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "owned value cannot escape with-temp-allocator; allocate it outside the temp scope or copy it before returning")
}

@(test)
reject_returning_owned_arg_call_from_with_temp_allocator :: proc(t: ^testing.T) {
    source := `(package main)
(import runtime "base:runtime")

(defn pass-through [xs: [dynamic]int] -> [dynamic]int
  xs)

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [xs: []int] -> [dynamic]int
  (with-temp-allocator [allocator]
    (pass-through (arr.map inc xs))))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "owned value cannot escape with-temp-allocator; allocate it outside the temp scope or copy it before returning")
}

@(test)
macroexpand_with_allocator_scope :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(with-allocator [allocator context.temp_allocator]
  (let [buffer (make [dynamic]int)]
    (defer (delete buffer))
    (arr.into! buffer ([]int [1 2]))))`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(do
  (let [allocator context.temp_allocator
        kvist-old-allocator-1 context.allocator]
    (set! context.allocator allocator)
    (defer (do
      (set! context.allocator kvist-old-allocator-1)))
    (let [buffer (make [dynamic]int)] (defer (delete buffer)) (arr.into! buffer ([]int [1 2])))))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_with_temp_allocator_scope :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(with-temp-allocator [allocator]
  (let [buffer (make [dynamic]int)]
    (defer (delete buffer))
    (arr.into! buffer ([]int [1 2]))))`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(do
  (let [kvist-temp-scope-1 (runtime.default-temp-allocator-temp-begin)
        allocator context.temp-allocator
        kvist-old-allocator-1 context.allocator]
    (set! context.allocator allocator)
    (defer (do
      (set! context.allocator kvist-old-allocator-1)
      (runtime.default-temp-allocator-temp-end kvist-temp-scope-1)))
    (let [buffer (make [dynamic]int)] (defer (delete buffer)) (arr.into! buffer ([]int [1 2])))))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_when_let :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(when-let [value found (query)]
  (fmt.println value))`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(let [[value found] (query)] (if found (fmt.println value)))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_if_let :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(if-let [value found (query)]
  value
  0)`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(let [[value found] (query)] (if found value 0))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_when_ok :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(when-ok [data err (read-text path)]
  (use data))`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(let [[data err] (read-text path)] (if (= err {}) (use data)))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_if_ok :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(if-ok [data err (read-text path)]
  (len data)
  0)`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(let [[data err] (read-text path)] (if (= err {}) (len data) 0))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_thread_first :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(-> req .method method-name)`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(method-name req.method)
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_thread_last :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(->> xs (arr.filter even?) (arr.map inc) (count))`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(core-count (arr.map inc (arr.filter even? xs)))
`
    testing.expect_value(t, output, expected)
}

@(test)
reject_legacy_thread_helpers :: proc(t: ^testing.T) {
    source := `(package main)

(defn main [xs: []int] -> int
  (->> xs
       (arr.rest)
       (count)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    source = `(package main)

(defstruct Request {
  path: string
})

(defn main [req: Request] -> int
  (-> req .path len))`

    {
        output_thread_first, err_thread_first, ok_thread_first := kvist.compile_source(source)
        testing.expect_value(t, ok_thread_first, true)
        if !ok_thread_first {
            testing.expect_value(t, err_thread_first.message, "")
            return
        }
        defer delete(output_thread_first)
    }
}

@(test)
macroexpand_rejects_binding_macro_shapes :: proc(t: ^testing.T) {
    _, err_if_let, ok_if_let := kvist.macroexpand_source(`(if-let [value found (query)]
  value)`)
    testing.expect_value(t, ok_if_let, false)
    defer delete(err_if_let.message)
    testing.expect_value(t, err_if_let.message, "if-let expects [value bool expr], then, and else")

    _, err_when_let, ok_when_let := kvist.macroexpand_source(`(when-let [value 1 (query)]
  value)`)
    testing.expect_value(t, ok_when_let, false)
    defer delete(err_when_let.message)
    testing.expect_value(t, err_when_let.message, "when-let expects [value bool expr] binding")

    _, err_when_ok, ok_when_ok := kvist.macroexpand_source(`(when-ok [data (read-text path)]
  data)`)
    testing.expect_value(t, ok_when_ok, false)
    defer delete(err_when_ok.message)
    testing.expect_value(t, err_when_ok.message, "when-ok expects [value err expr] binding")

    _, err_if_ok, ok_if_ok := kvist.macroexpand_source(`(if-ok [data err (read-text path)]
  data)`)
    testing.expect_value(t, ok_if_ok, false)
    defer delete(err_if_ok.message)
    testing.expect_value(t, err_if_ok.message, "if-ok expects [value err expr], then, and else")
}

@(test)
macroexpand_source_map_marks_generated_lines :: proc(t: ^testing.T) {
    source := `(with-temp-allocator [allocator]
  (let [xs (arr.map inc users)]
    (count xs)))`
    result, err, ok := kvist.macroexpand_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.source_map), 9)

    body_start := strings.index(source, "(let [xs (arr.map inc users)]")

    body_entry, body_found := kvist.source_map_entry_for_generated_line(result.source_map[:], 9)
    testing.expect_value(t, body_found, true)
    testing.expect_value(t, body_entry.source_span.start, body_start)
}

@(test)
macroexpand_user_macro_in_file_context :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro unless [condition & body]
  (quasiquote
    (if (unquote condition)
      (do)
      (do (splice body)))))

(defn answer [] -> int
  42)`

    output, err, ok := kvist.macroexpand_eval_source_with_map(source, `(unless (> n 0)
  (return 0))`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output.output)
    defer delete(output.source_map)
    defer kvist.compile_warning_slice_delete(output.warnings)

    expected := `(if (> n 0) (do) (do (return 0)))
`
    testing.expect_value(t, output.output, expected)
}

@(test)
macroexpand_gensym_creates_stable_symbol_within_expansion :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro with-temp-bool [value]
  (let [tmp (gensym "__tmp")]
    (quasiquote
      (let [(unquote tmp) (unquote value)]
        (when (unquote tmp)
          (println (unquote tmp)))))))`

    output, err, ok := kvist.macroexpand_eval_source_with_map(source, `(with-temp-bool true)`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output.output)
    defer delete(output.source_map)
    defer kvist.compile_warning_slice_delete(output.warnings)

    testing.expect_value(t, strings.contains(output.output, "(let [__tmp_"), true)
    testing.expect_value(t, strings.contains(output.output, "(if __tmp_"), true)
    testing.expect_value(t, strings.contains(output.output, "(core-println __tmp_"), true)
}

@(test)
compile_path_macro_io_read_uses_source_relative_file_at_compile_time :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-macro-io-read-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    template_path, template_join_err := os.join_path({dir, "template.html"}, context.allocator)
    testing.expect_value(t, template_join_err == nil, true)
    if template_join_err != nil {
        return
    }
    defer delete(template_path)

    template_write_err := os.write_entire_file_from_string(template_path, "<h1>Compile-time</h1>\n")
    testing.expect_value(t, template_write_err == nil, true)
    if template_write_err != nil {
        return
    }

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)

    source := `(package main)
(import io "kvist:io")

(defmacro def-template []
  (let [text (io.read "template.html")]
    (quasiquote
      (def template: string (unquote text)))))

(def-template)

(defn main [] -> string
  template)`

    source_write_err := os.write_entire_file_from_string(main_path, source)
    testing.expect_value(t, source_write_err == nil, true)
    if source_write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `template: string : "<h1>Compile-time</h1>\n"`), true)
    testing.expect_value(t, strings.contains(output, `return template`), true)
}

@(test)
compile_path_macro_io_read_reports_missing_compile_time_file :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-macro-io-read-missing-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)

    source := `(package main)
(import io "kvist:io")

(defmacro def-template []
  (let [text (io.read "missing.html")]
    (quasiquote
      (def template: string (unquote text)))))

(def-template)`

    source_write_err := os.write_entire_file_from_string(main_path, source)
    testing.expect_value(t, source_write_err == nil, true)
    if source_write_err != nil {
        return
    }

    _, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "compile-time io.read could not read file:"), true)
    testing.expect_value(t, strings.contains(err.message, "missing.html"), true)
}

@(test)
compile_source_with_user_macro :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro unless [condition & body]
  (quasiquote
    (if (unquote condition)
      (do)
      (do (splice body)))))

(defn classify [n: int] -> string
  (unless (> n 0)
    (return "non-positive"))
  "positive")`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `classify :: proc(n: int) -> string`), true)
    testing.expect_value(t, strings.contains(output, `return "non-positive"`), true)
    testing.expect_value(t, strings.contains(output, `return "positive"`), true)
}

@(test)
compile_source_with_top_level_macro_dsl :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro defentity [name fields]
  (let [make-name (symbol (str "make-" (name name)))]
    (forms
      (quasiquote
        (defstruct (unquote name) (unquote fields)))
      (quasiquote
        (defn (unquote make-name) [] -> (unquote name)
          ((unquote name) {}))))))

(defentity Point {x: float y: float})

(defn point-origin? [point: Point] -> bool
  (and (= point.x 0.0)
       (= point.y 0.0)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `Point :: struct {`), true)
    testing.expect_value(t, strings.contains(output, `make_Point :: proc() -> Point`), true)
    testing.expect_value(t, strings.contains(output, `return Point{}`), true)
    testing.expect_value(t, strings.contains(output, `point_origin_p :: proc(point: Point) -> bool`), true)
}

@(test)
compile_source_with_recursive_macro_dsl :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro emit-union-ctors [union-name variants]
  (if (= (count variants) 0)
    (forms)
    (let [tag (arr.first variants)
          value-type (arr.nth variants 1)
          ctor-name (symbol (str "make-" (name union-name) "-" (name tag)))]
      (forms
        (quasiquote
          (defn (unquote ctor-name) [value: (unquote value-type)] -> (unquote union-name)
            ((unquote union-name) {(unquote tag) value})))
        (emit-union-ctors union-name (arr.rest (arr.rest variants)))))))

(defmacro defunion+ctors [name variants]
  (forms
    (quasiquote
      (defunion (unquote name) (unquote variants)))
    (emit-union-ctors name variants)))

(defunion+ctors Value {
  i: int
  s: string
  ok: bool
})`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `Value :: union {`), true)
    testing.expect_value(t, strings.contains(output, `make_Value_i :: proc(value: int) -> Value`), true)
    testing.expect_value(t, strings.contains(output, `make_Value_s :: proc(value: string) -> Value`), true)
    testing.expect_value(t, strings.contains(output, `make_Value_ok :: proc(value: bool) -> Value`), true)
    testing.expect_value(t, strings.contains(output, `return Value(value)`), true)
}

@(test)
compile_source_with_message_family_macro :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro emit-message-structs [entries]
  (if (= (count entries) 0)
    (forms)
    (let [entry (arr.first entries)
          struct-name (arr.nth entry 0)
          fields (arr.nth entry 1)]
      (forms
        (quasiquote
          (defstruct (unquote struct-name) (unquote fields)))
        (emit-message-structs (arr.rest entries))))))

(defmacro emit-message-union-entries [entries]
  (if (= (count entries) 0)
    (forms)
    (let [entry (arr.first entries)
          struct-name (arr.nth entry 0)
          tag (symbol (str (name struct-name) ":"))]
      (forms
        tag
        struct-name
        (emit-message-union-entries (arr.rest entries))))))

(defmacro emit-message-ctors [union-name entries]
  (if (= (count entries) 0)
    (forms)
    (let [entry (arr.first entries)
          struct-name (arr.nth entry 0)
          ctor-name (symbol (str "make-" (name union-name) "-" (name struct-name)))
          tag (symbol (str (name struct-name) ":"))]
      (forms
        (quasiquote
          (defn (unquote ctor-name) [value: (unquote struct-name)] -> (unquote union-name)
            ((unquote union-name) {(unquote tag) value})))
        (emit-message-ctors union-name (arr.rest entries))))))

(defmacro defmessages [union-name entries]
  (forms
    (emit-message-structs entries)
    (quasiquote
      (defunion (unquote union-name) {
        (splice (emit-message-union-entries entries))
      }))
    (emit-message-ctors union-name entries)))

(defmessages Event [
  [Connected {id: int}]
  [Disconnected {id: int reason: string}]
  [Data {id: int payload: string}]
])`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `Connected :: struct {`), true)
    testing.expect_value(t, strings.contains(output, `Disconnected :: struct {`), true)
    testing.expect_value(t, strings.contains(output, `Data :: struct {`), true)
    testing.expect_value(t, strings.contains(output, `Event :: union {`), true)
    testing.expect_value(t, strings.contains(output, `make_Event_Connected :: proc(value: Connected) -> Event`), true)
    testing.expect_value(t, strings.contains(output, `make_Event_Disconnected :: proc(value: Disconnected) -> Event`), true)
    testing.expect_value(t, strings.contains(output, `make_Event_Data :: proc(value: Data) -> Event`), true)
}

@(test)
compile_fn_types_and_literals :: proc(t: ^testing.T) {
    source := `(package main)

(defn apply [f: (fn [x: int] -> int), x: int] -> int
  (f x))

(defn main []
  (let [out (apply (fn [x: int] -> int
                     (+ x 1))
                   41)]
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

apply :: proc(f: proc(x: int) -> int, x: int) -> int {
    return f(x)
}

main :: proc() {
    out := apply(
        proc(x: int) -> int {
            return (x) + (1)
        },
        41
    )
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_core_higher_order_helpers_and_slice_exprs :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn inc [x: int] -> int
  (+ x 1))

(defn even? [x: int] -> bool
  (= (% x 2) 0))

(defn add [acc: int, x: int] -> int
  (+ acc x))

(defn main []
  (let [xs ([]int [1 2 3 4])
        mapped (arr.map inc xs)
        tail (slice mapped 1)
        evens (arr.filter even? mapped)
        total (->> xs
                   (arr.map inc)
                   (arr.filter even?)
                   (arr.reduce add 0))
        middle (slice mapped 0 1)]
    (defer (delete mapped))
    (defer (delete evens))
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

inc :: proc(x: int) -> int {
    return (x) + (1)
}

even_p :: proc(x: int) -> bool {
    return ((x) % (2)) == (0)
}

add :: proc(acc, x: int) -> int {
    return (acc) + (x)
}

main :: proc() {
    xs := []int{1, 2, 3, 4}
    mapped := kvist_map(inc, (xs)[:])
    tail := (mapped)[1:]
    evens := kvist_filter(even_p, (mapped)[:])
    kvist_thread_1 := kvist_map(inc, (xs)[:])
    defer delete(kvist_thread_1)
    kvist_thread_2 := kvist_filter(even_p, (kvist_thread_1)[:])
    defer delete(kvist_thread_2)
    total := kvist_reduce(add, 0, (kvist_thread_2)[:])
    middle := (mapped)[0:1]
    defer delete(mapped)
    defer delete(evens)
    return
}

kvist_map :: proc(f: proc(x: $T) -> $U, xs: []T) -> [dynamic]U {
    out := make([dynamic]U, 0, len(xs))
    for x in xs {
        append(&out, f(x))
    }
    return out
}

kvist_filter :: proc(pred: proc(x: $T) -> bool, xs: []T) -> [dynamic]T {
    out := make([dynamic]T, 0, len(xs))
    for x in xs {
        if pred(x) {
            append(&out, x)
        }
    }
    return out
}

kvist_reduce :: proc(f: proc(acc: $U, x: $T) -> U, init: U, xs: []T) -> U {
    acc := init
    for x in xs {
        acc = f(acc, x)
    }
    return acc
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_sequence_trim_helpers_as_slice_views :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn keep? [x: int] -> bool
  (< x 4))

(defn main []
  (let [xs ([]int [1 2 3 4])
        prefix (arr.take 2 xs)
        suffix (arr.drop 1 xs)
        without-last (arr.butlast xs)
        without-two (arr.drop-last 2 xs)
        small-prefix (arr.take-while keep? xs)
        large-suffix (arr.drop-while keep? xs)
        threaded-count (->> xs
                            (arr.drop-last 1)
                            (count))]
    (return)))`

    dir, dir_err := os.make_directory_temp("", "kvist-trim-source-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    write_err := os.write_entire_file(path, transmute([]byte)source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "prefix := arr__take(2, xs)"), true)
    testing.expect_value(t, strings.contains(output, "suffix := arr__drop(1, xs)"), true)
    testing.expect_value(t, strings.contains(output, "without_last := arr__butlast(xs)"), true)
    testing.expect_value(t, strings.contains(output, "without_two := arr__drop_last(2, xs)"), true)
    testing.expect_value(t, strings.contains(output, "small_prefix := arr__take_while_impl(keep_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "large_suffix := arr__drop_while_impl(keep_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "threaded_count := len((arr__drop_last(1, xs))[:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__take :: #force_inline proc(n: int, xs: []$T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return (xs)[0:limit]"), true)
    testing.expect_value(t, strings.contains(output, "arr__drop :: #force_inline proc(n: int, xs: []$T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return (xs)[start:]"), true)
    testing.expect_value(t, strings.contains(output, "arr__drop_last :: #force_inline proc(n: int, xs: []$T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return (xs)[0:end]"), true)
    testing.expect_value(t, strings.contains(output, "arr__take_while_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return (xs)[0:i]"), true)
    testing.expect_value(t, strings.contains(output, "arr__drop_while_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return (xs)[i:]"), true)
    testing.expect_value(t, strings.contains(output, "kvist_take :: proc(n: int, xs: []$T) -> []T"), false)
    testing.expect_value(t, strings.contains(output, "kvist_drop :: proc(n: int, xs: []$T) -> []T"), false)
    testing.expect_value(t, strings.contains(output, "kvist_drop_last :: proc(n: int, xs: []$T) -> []T"), false)
}

@(test)
compile_named_functional_transform_into_and_transduce :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Order {
  status: int
  amount: int
  discount: int
})

(defn paid? [order: Order] -> bool
  (= order.status 2))

(defn order-total [order: Order] -> int
  (- order.amount order.discount))

(defn positive? [x: int] -> bool
  (> x 0))

(deftransform paid-order-totals
  (comp
    (filter paid?)
    (map order-total)
    (filter positive?)))

(defn collect [orders: []Order] -> [dynamic]int
  (into [dynamic]int paid-order-totals orders))

(defn total [orders: []Order] -> int
  (transduce paid-order-totals + 0 orders))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "for kvist_item in kvist_source {"), true)
    testing.expect_value(t, strings.contains(output, "if paid_p(kvist_item) {"), true)
    testing.expect_value(t, strings.contains(output, " := order_total(kvist_item)"), true)
    testing.expect_value(t, strings.contains(output, "if positive_p(kvist_xform_"), true)
    testing.expect_value(t, strings.contains(output, "append(&kvist_out, kvist_xform_"), true)
    testing.expect_value(t, strings.contains(output, "kvist_acc += kvist_xform_"), true)
    testing.expect_value(t, strings.contains(output, "paid_order_totals ::"), false)
}

@(test)
compile_inline_functional_transform_into :: proc(t: ^testing.T) {
    source := `(package main)

(defn even? [x: int] -> bool
  (= (% x 2) 0))

(defn inc [x: int] -> int
  (+ x 1))

(defn values [xs: []int] -> [dynamic]int
  (into [dynamic]int
    (comp
      (filter even?)
      (map inc))
    xs))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "if even_p(kvist_item) {"), true)
    testing.expect_value(t, strings.contains(output, " := inc(kvist_item)"), true)
    testing.expect_value(t, strings.contains(output, "append(&kvist_out, kvist_xform_"), true)
}

@(test)
compile_defsource_each_and_into_consumers :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct File_Source {
  items: []string
  index: int
})

(defn open-files [items: []string] -> File_Source
  (File_Source {items: items index: 0}))

(defn next-file [src: ^File_Source] -> [path: string ok: bool]
  (if (< src.index (len src.items))
    (let [path src.items[src.index]]
      (set! src.index (+ src.index 1))
      (return path true))
    (return "" false)))

(defn dispose-files [src: ^File_Source]
  (set! src.index 0))

(defn long-path? [path: string] -> bool
  (> (len path) 5))

(defn path-length [path: string] -> int
  (len path))

(defsource files [items: []string] -> string
  (open-files items)
  :next next-file
  :dispose dispose-files)

(defn total-name-length [items: []string] -> int
  (let [total 0]
    (each [path (files items)]
      (set! total (+ total (len path))))
    total))

(defn long-paths [items: []string] -> [dynamic]string
  (into [dynamic]string
    (comp
      (filter long-path?))
    (files items)))

(defn total-long-path-length [items: []string] -> int
  (transduce
    (comp
      (filter long-path?)
      (map path-length))
    + 0
    (files items)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "files :: proc(items: []string) -> File_Source {"), true)
    testing.expect_value(t, strings.contains(output, "return open_files(items)"), true)
    testing.expect_value(t, strings.contains(output, "defer dispose_files(&kvist_source_"), true)
    testing.expect_value(t, strings.contains(output, "path, kvist_source_ok_"), true)
    testing.expect_value(t, strings.contains(output, " := next_file(&kvist_source_"), true)
    testing.expect_value(t, strings.contains(output, "if !kvist_source_ok_"), true)
    testing.expect_value(t, strings.contains(output, "(proc(kvist_source_arg_1: []string) -> [dynamic]string {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_source := files(kvist_source_arg_1)"), true)
    testing.expect_value(t, strings.contains(output, "defer dispose_files(&kvist_source)\n        kvist_out := make([dynamic]string)"), true)
    testing.expect_value(t, strings.contains(output, "if long_path_p(kvist_item) {"), true)
    testing.expect_value(t, strings.contains(output, "append(&kvist_out, kvist_item)"), true)
    testing.expect_value(t, strings.contains(output, "(proc(kvist_source_arg_1: []string, kvist_init: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "defer dispose_files(&kvist_source)\n        kvist_acc := kvist_init"), true)
    testing.expect_value(t, strings.contains(output, "kvist_acc := kvist_init"), true)
    testing.expect_value(t, strings.contains(output, " := path_length(kvist_item)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_acc += kvist_xform_"), true)
}

@(test)
reject_source_call_outside_source_consumer :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct File_Source {
  items: []string
  index: int
})

(defn open-files [items: []string] -> File_Source
  (File_Source {items: items index: 0}))

(defn next-file [src: ^File_Source] -> [path: string ok: bool]
  (return "" false))

(defsource files [items: []string] -> string
  (open-files items)
  :next next-file)

(defn bad [items: []string] -> int
  (let [src (files items)]
    0))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "source files can currently only be consumed by each, into, or transduce")
}

@(test)
reject_defsource_next_wrong_state_parameter :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct File_Source {
  index: int
})

(defstruct Other_Source {
  index: int
})

(defn open-files [] -> File_Source
  (File_Source {index: 0}))

(defn next-file [src: ^Other_Source] -> [path: string ok: bool]
  (return "" false))

(defsource files [] -> string
  (open-files)
  :next next-file)

(defn consume [] -> int
  (let [total 0]
    (each [path (files)]
      (set! total (+ total (len path))))
    total))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "defsource files :next must take ^File_Source")
}

@(test)
reject_defsource_next_wrong_return_shape :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct File_Source {
  index: int
})

(defn open-files [] -> File_Source
  (File_Source {index: 0}))

(defn next-file [src: ^File_Source] -> [path: int ok: bool]
  (return 0 false))

(defsource files [] -> string
  (open-files)
  :next next-file)

(defn consume [] -> int
  (let [total 0]
    (each [path (files)]
      (set! total (+ total (len path))))
    total))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "defsource files :next must return [item: string ok: bool]")
}

@(test)
reject_defsource_dispose_return_value :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct File_Source {
  index: int
})

(defn open-files [] -> File_Source
  (File_Source {index: 0}))

(defn next-file [src: ^File_Source] -> [path: string ok: bool]
  (return "" false))

(defn dispose-files [src: ^File_Source] -> int
  0)

(defsource files [] -> string
  (open-files)
  :next next-file
  :dispose dispose-files)

(defn consume [] -> int
  (let [total 0]
    (each [path (files)]
      (set! total (+ total (len path))))
    total))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "defsource files :dispose must not return a value")
}

@(test)
compile_parallel_start_result_and_detach :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn zero [] -> int
  5)

(defn combine [a: int, b: int, c: int] -> int
  (+ a b c))

(defn notify [user-id: int]
  (println user-id))

(defn demo [] -> int
  (let [zero-task (p.start zero)
        combine-task (p.start combine 1 2 3)]
    (p.detach notify 99)
    (+ (p.result zero-task) (p.result combine-task))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "import chan \"core:sync/chan\""), true)
    testing.expect_value(t, strings.contains(output, "import thread \"core:thread\""), true)
    testing.expect_value(t, strings.contains(output, "zero_task := parallel_start_zero_void_int()"), true)
    testing.expect_value(t, strings.contains(output, "combine_task := parallel_start_combine_int_int_int_int(1, 2, 3)"), true)
    testing.expect_value(t, strings.contains(output, "parallel_detach_notify_int(99)"), true)
    testing.expect_value(t, strings.contains(output, "return (parallel_result(zero_task)) + (parallel_result(combine_task))"), true)
    testing.expect_value(t, strings.contains(output, "parallel_Task :: struct($T: typeid)"), true)
    testing.expect_value(t, strings.contains(output, "result: chan.Chan(T),"), true)
    testing.expect_value(t, strings.contains(output, "thread: ^thread.Thread,"), true)
    testing.expect_value(t, strings.contains(output, "parallel_Start_Data_zero_void_int :: struct"), true)
    testing.expect_value(t, strings.contains(output, "chan.send(data.result, zero())"), true)
    testing.expect_value(t, strings.contains(output, "parallel_start_zero_void_int :: proc() -> parallel_Task(int)"), true)
    testing.expect_value(t, strings.contains(output, "parallel_Start_Data_combine_int_int_int_int :: struct"), true)
    testing.expect_value(t, strings.contains(output, "a: int,"), true)
    testing.expect_value(t, strings.contains(output, "b: int,"), true)
    testing.expect_value(t, strings.contains(output, "c: int,"), true)
    testing.expect_value(t, strings.contains(output, "chan.send(data.result, combine(data.a, data.b, data.c))"), true)
    testing.expect_value(t, strings.contains(output, "parallel_start_combine_int_int_int_int :: proc(a: int, b: int, c: int) -> parallel_Task(int)"), true)
    testing.expect_value(t, strings.contains(output, "thread.create_and_start_with_poly_data(data, parallel_start_worker_combine_int_int_int_int)"), true)
    testing.expect_value(t, strings.contains(output, "parallel_result :: proc(task: parallel_Task($T)) -> T"), true)
    testing.expect_value(t, strings.contains(output, "thread.join(task.thread)"), true)
    testing.expect_value(t, strings.contains(output, "thread.destroy(task.thread)"), true)
    testing.expect_value(t, strings.contains(output, "free(task.data)"), true)
    testing.expect_value(t, strings.contains(output, "chan.destroy(task.result)"), true)
    testing.expect_value(t, strings.contains(output, "parallel_Detach_Data_notify_int :: struct"), true)
    testing.expect_value(t, strings.contains(output, "parallel_detach_worker_notify_int :: proc(data: ^parallel_Detach_Data_notify_int)"), true)
    testing.expect_value(t, strings.contains(output, "notify(data.user_id)"), true)
    testing.expect_value(t, strings.contains(output, "parallel_detach_notify_int :: proc(user_id: int)"), true)
    testing.expect_value(t, strings.contains(output, "thread.create_and_start_with_poly_data(data, parallel_detach_worker_notify_int, nil, .Normal, true)"), true)
    testing.expect_value(t, strings.contains(output, "assert(false, \"parallel.detach could not start worker thread\")"), true)
}

@(test)
compile_parallel_repeated_start_reuses_helper :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn square [x: int] -> int
  (* x x))

(defn demo [] -> int
  (let [a (p.start square 1)
        b (p.start square 2)
        c (p.start square 3)]
    (+ (p.result a) (p.result b) (p.result c))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "a := parallel_start_square_int_int(1)"), true)
    testing.expect_value(t, strings.contains(output, "b := parallel_start_square_int_int(2)"), true)
    testing.expect_value(t, strings.contains(output, "c := parallel_start_square_int_int(3)"), true)
    testing.expect_value(t, count_substring(output, "parallel_start_square_int_int :: proc(x: int) -> parallel_Task(int)"), 1)
    testing.expect_value(t, count_substring(output, "parallel_start_worker_square_int_int :: proc(data: ^parallel_Start_Data_square_int_int)"), 1)
}

@(test)
compile_parallel_map_named_worker :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn square [x: int] -> int
  (* x x))

(defn demo [xs: []int] -> [dynamic]int
  (p.map square xs))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "import os \"core:os\""), true)
    testing.expect_value(t, strings.contains(output, "return parallel_map_square_int_int((xs)[:], 0)"), true)
    testing.expect_value(t, strings.contains(output, "parallel_Map_Data_square_int_int :: struct"), true)
    testing.expect_value(t, strings.contains(output, "xs: []int,"), true)
    testing.expect_value(t, strings.contains(output, "out: [dynamic]int,"), true)
    testing.expect_value(t, strings.contains(output, "parallel_map_worker_square_int_int :: proc(data: ^parallel_Map_Data_square_int_int)"), true)
    testing.expect_value(t, strings.contains(output, "data.out[i] = square(data.xs[i])"), true)
    testing.expect_value(t, strings.contains(output, "parallel_map_square_int_int :: proc(xs: []int, requested_worker_count: int) -> [dynamic]int"), true)
    testing.expect_value(t, strings.contains(output, "out := make([dynamic]int, len(xs))"), true)
    testing.expect_value(t, strings.contains(output, "worker_count := requested_worker_count"), true)
    testing.expect_value(t, strings.contains(output, "worker_count = os.get_processor_core_count() - 1"), true)
    testing.expect_value(t, strings.contains(output, "if worker_count > 16"), true)
    testing.expect_value(t, strings.contains(output, "if worker_count > len(xs)"), true)
    testing.expect_value(t, strings.contains(output, "thread.create_and_start_with_poly_data(data, parallel_map_worker_square_int_int)"), true)
    testing.expect_value(t, strings.contains(output, "thread.join(task_thread)"), true)
    testing.expect_value(t, strings.contains(output, "thread.destroy(task_thread)"), true)
    testing.expect_value(t, strings.contains(output, "free(data)"), true)
    testing.expect_value(t, strings.contains(output, "return out"), true)
}

@(test)
compile_parallel_map_reuses_helper :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn square [x: int] -> int
  (* x x))

(defn demo [xs: []int] -> int
  (let [a (p.map square xs)
        b (p.map square xs)]
    (defer (delete a))
    (defer (delete b))
    (+ (count a) (count b))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, count_substring(output, "parallel_map_square_int_int :: proc(xs: []int, requested_worker_count: int) -> [dynamic]int"), 1)
    testing.expect_value(t, count_substring(output, "parallel_map_worker_square_int_int :: proc(data: ^parallel_Map_Data_square_int_int)"), 1)
}

@(test)
compile_parallel_map_with_worker_count :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn square [x: int] -> int
  (* x x))

(defn demo [xs: []int] -> [dynamic]int
  (p.map-with {workers: 4} square xs))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return parallel_map_square_int_int((xs)[:], 4)"), true)
    testing.expect_value(t, strings.contains(output, "parallel_map_square_int_int :: proc(xs: []int, requested_worker_count: int) -> [dynamic]int"), true)
}

@(test)
compile_parallel_map_and_map_with_reuse_helper :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn square [x: int] -> int
  (* x x))

(defn demo [xs: []int] -> int
  (let [a (p.map square xs)
        b (p.map-with {workers: 2} square xs)]
    (defer (delete a))
    (defer (delete b))
    (+ (count a) (count b))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "a := parallel_map_square_int_int((xs)[:], 0)"), true)
    testing.expect_value(t, strings.contains(output, "b := parallel_map_square_int_int((xs)[:], 2)"), true)
    testing.expect_value(t, count_substring(output, "parallel_map_square_int_int :: proc(xs: []int, requested_worker_count: int) -> [dynamic]int"), 1)
    testing.expect_value(t, count_substring(output, "parallel_map_worker_square_int_int :: proc(data: ^parallel_Map_Data_square_int_int)"), 1)
}

@(test)
reject_parallel_start_wrong_arity :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn combine [a: int, b: int] -> int
  (+ a b))

(defn demo [] -> int
  (p.result (p.start combine 1)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "parallel.start worker combine expects 2 arguments, got 1")
}

@(test)
compile_parallel_start_inline_worker :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn demo [] -> int
  (p.result (p.start (fn [x: int] -> int
                       (+ x 1))
                     1)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return parallel_result(parallel_start_inline_"), true)
    testing.expect_value(t, strings.contains(output, "(1))"), true)
    testing.expect_value(t, strings.contains(output, "parallel_start_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, " :: proc(x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "parallel_Start_Data_inline_"), true)
    testing.expect_value(t, strings.contains(output, "x: int,"), true)
    testing.expect_value(t, strings.contains(output, "chan.send(data.result, parallel_start_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, "(data.x))"), true)
    testing.expect_value(t, strings.contains(output, "parallel_start_inline_"), true)
    testing.expect_value(t, strings.contains(output, " :: proc(x: int) -> parallel_Task(int)"), true)
}

@(test)
compile_parallel_start_with_captured_inline_worker :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn demo [] -> int
  (let [offset 10
        task (p.start (fn [x: int] -> int
                        (+ x offset))
                      5)]
    (p.result task)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "task := parallel_start_inline_"), true)
    testing.expect_value(t, strings.contains(output, "(offset, 5)"), true)
    testing.expect_value(t, strings.contains(output, "parallel_start_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, " :: proc(offset: int, x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "offset: int,"), true)
    testing.expect_value(t, strings.contains(output, "x: int,"), true)
    testing.expect_value(t, strings.contains(output, "data.offset = offset"), true)
    testing.expect_value(t, strings.contains(output, "data.x = x"), true)
    testing.expect_value(t, strings.contains(output, "chan.send(data.result, parallel_start_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, "(data.offset, data.x))"), true)
    testing.expect_value(t, strings.contains(output, "parallel_start_inline_"), true)
    testing.expect_value(t, strings.contains(output, " :: proc(offset: int, x: int) -> parallel_Task(int)"), true)
}

@(test)
reject_parallel_start_inline_without_return_value :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn demo [] -> int
  (p.result (p.start (fn []
                       (println 1)))))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "parallel.start inline worker must return exactly one value")
}

@(test)
reject_parallel_detach_return_value :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn compute [x: int] -> int
  x)

(defn demo []
  (p.detach compute 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "parallel.detach worker must not return a value")
}

@(test)
compile_parallel_detach_inline_worker :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn demo []
  (p.detach (fn []
              (println 42))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "parallel_detach_inline_"), true)
    testing.expect_value(t, strings.contains(output, "()"), true)
    testing.expect_value(t, strings.contains(output, "parallel_detach_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, " :: proc() {"), true)
    testing.expect_value(t, strings.contains(output, "parallel_Detach_Data_inline_"), true)
    testing.expect_value(t, strings.contains(output, "parallel_detach_worker_inline_"), true)
    testing.expect_value(t, strings.contains(output, "parallel_detach_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, "thread.create_and_start_with_poly_data(data, parallel_detach_worker_inline_"), true)
}

@(test)
compile_parallel_detach_with_captured_inline_worker :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn observe [x: int]
  (println x))

(defn demo []
  (let [offset 10]
    (p.detach (fn [x: int]
                (observe (+ x offset)))
              5)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "parallel_detach_inline_"), true)
    testing.expect_value(t, strings.contains(output, "(offset, 5)"), true)
    testing.expect_value(t, strings.contains(output, "parallel_detach_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, " :: proc(offset: int, x: int) {"), true)
    testing.expect_value(t, strings.contains(output, "offset: int,"), true)
    testing.expect_value(t, strings.contains(output, "x: int,"), true)
    testing.expect_value(t, strings.contains(output, "data.offset = offset"), true)
    testing.expect_value(t, strings.contains(output, "data.x = x"), true)
    testing.expect_value(t, strings.contains(output, "parallel_detach_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, "(data.offset, data.x)"), true)
}

@(test)
reject_parallel_detach_inline_return_value :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn demo []
  (p.detach (fn [] -> int
              1)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "parallel.detach inline worker must not return a value")
}

@(test)
compile_parallel_map_inline_worker :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn demo [xs: []int] -> [dynamic]int
  (p.map (fn [x: int] -> int
           (+ x 1))
         xs))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return parallel_map_inline_"), true)
    testing.expect_value(t, strings.contains(output, "((xs)[:], 0)"), true)
    testing.expect_value(t, strings.contains(output, "parallel_map_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, " :: proc(x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "data.out[i] = parallel_map_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, "(data.xs[i])"), true)
}

@(test)
compile_parallel_map_with_captured_inline_worker :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn demo [xs: []int] -> [dynamic]int
  (let [offset 10]
    (p.map-with {workers: 2}
      (fn [x: int] -> int
        (+ x offset))
      xs)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "parallel_map_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, " :: proc(offset: int, x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "offset: int,"), true)
    testing.expect_value(t, strings.contains(output, "data.offset = offset"), true)
    testing.expect_value(t, strings.contains(output, "data.out[i] = parallel_map_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, "(data.offset, data.xs[i])"), true)
    testing.expect_value(t, strings.contains(output, "((xs)[:], 2, offset)"), true)
}

@(test)
reject_parallel_map_multi_arg_worker :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn add [a: int, b: int] -> int
  (+ a b))

(defn demo [xs: []int] -> [dynamic]int
  (p.map add xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "parallel.map worker must take exactly one argument")
}

@(test)
reject_parallel_map_inline_multi_arg_worker :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn demo [xs: []int] -> [dynamic]int
  (p.map (fn [a: int, b: int] -> int
           (+ a b))
         xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "parallel.map inline worker must take exactly one argument")
}

@(test)
reject_parallel_map_source_type_mismatch :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn square [x: int] -> int
  (* x x))

(defn demo [xs: []f64] -> [dynamic]int
  (p.map square xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "parallel.map worker expects int but source has f64")
}

@(test)
reject_parallel_map_with_non_brace_options :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn square [x: int] -> int
  (* x x))

(defn demo [xs: []int] -> [dynamic]int
  (p.map-with 4 square xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "parallel.map-with expects options like {workers: n}")
}

@(test)
reject_parallel_map_with_missing_workers :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn square [x: int] -> int
  (* x x))

(defn demo [xs: []int] -> [dynamic]int
  (p.map-with {} square xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "parallel.map-with expects {workers: n}")
}

@(test)
reject_parallel_map_with_unknown_option :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn square [x: int] -> int
  (* x x))

(defn demo [xs: []int] -> [dynamic]int
  (p.map-with {threads: 4} square xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "parallel.map-with unknown option: threads")
}

@(test)
compile_parallel_each_named_worker :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn record [x: int]
  (println x))

(defn demo [xs: []int]
  (p.each record xs))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "parallel_each_record_int((xs)[:], 0)"), true)
    testing.expect_value(t, strings.contains(output, "parallel_Each_Data_record_int :: struct"), true)
    testing.expect_value(t, strings.contains(output, "xs: []int,"), true)
    testing.expect_value(t, strings.contains(output, "parallel_each_worker_record_int :: proc(data: ^parallel_Each_Data_record_int)"), true)
    testing.expect_value(t, strings.contains(output, "record(data.xs[i])"), true)
    testing.expect_value(t, strings.contains(output, "parallel_each_record_int :: proc(xs: []int, requested_worker_count: int)"), true)
    testing.expect_value(t, strings.contains(output, "worker_count = os.get_processor_core_count() - 1"), true)
    testing.expect_value(t, strings.contains(output, "if worker_count > 16"), true)
    testing.expect_value(t, strings.contains(output, "thread.create_and_start_with_poly_data(data, parallel_each_worker_record_int)"), true)
    testing.expect_value(t, strings.contains(output, "thread.join(task_thread)"), true)
    testing.expect_value(t, strings.contains(output, "free(data)"), true)
}

@(test)
compile_parallel_each_with_captured_inline_worker :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn demo [xs: []int]
  (let [offset 10]
    (p.each-with {workers: 2}
      (fn [x: int]
        (println (+ x offset)))
      xs)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "parallel_each_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, " :: proc(offset: int, x: int) {"), true)
    testing.expect_value(t, strings.contains(output, "offset: int,"), true)
    testing.expect_value(t, strings.contains(output, "data.offset = offset"), true)
    testing.expect_value(t, strings.contains(output, "parallel_each_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, "(data.offset, data.xs[i])"), true)
    testing.expect_value(t, strings.contains(output, "parallel_each_inline_"), true)
    testing.expect_value(t, strings.contains(output, "((xs)[:], 2, offset)"), true)
}

@(test)
reject_parallel_each_return_value :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn square [x: int] -> int
  (* x x))

(defn demo [xs: []int]
  (p.each square xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "parallel.each worker must not return a value")
}

@(test)
reject_parallel_each_inline_return_value :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn demo [xs: []int]
  (p.each (fn [x: int] -> int
            x)
          xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "parallel.each inline worker must not return a value")
}

@(test)
reject_parallel_each_with_unknown_option :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn record [x: int]
  (println x))

(defn demo [xs: []int]
  (p.each-with {threads: 4} record xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "parallel.each-with unknown option: threads")
}

@(test)
compile_functional_transform_field_selectors :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User {
  age: int
  active?: bool
})

(deftransform active-ages
  (comp
    (filter .active?)
    (map .age)))

(defn values [users: []User] -> [dynamic]int
  (into [dynamic]int active-ages users))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "if kvist_item.active_p {"), true)
    testing.expect_value(t, strings.contains(output, " := kvist_item.age"), true)
    testing.expect_value(t, strings.contains(output, "append(&kvist_out, kvist_xform_"), true)
}

@(test)
reject_functional_transform_bad_named_spec_early :: proc(t: ^testing.T) {
    source := `(package main)

(deftransform bad-transform
  (map inc))

(defn inc [x: int] -> int
  (+ x 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "deftransform expects (comp ...)")
}

@(test)
reject_functional_transform_unknown_step :: proc(t: ^testing.T) {
    source := `(package main)

(defn values [xs: []int] -> [dynamic]int
  (into [dynamic]int
    (comp
      (take 2))
    xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "transform steps currently support map and filter")
}

@(test)
reject_named_functional_transform_unknown_step_early :: proc(t: ^testing.T) {
    source := `(package main)

(deftransform bad-transform
  (comp
    (take 2)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "transform steps currently support map and filter")
}

@(test)
reject_functional_transform_unknown_named_transform :: proc(t: ^testing.T) {
    source := `(package main)

(defn values [xs: []int] -> [dynamic]int
  (into [dynamic]int missing-transform xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "unknown transform: missing-transform")
}

@(test)
reject_functional_transform_callback_arity :: proc(t: ^testing.T) {
    source := `(package main)

(defn between? [x: int y: int] -> bool
  (and (> x 0) (< x y)))

(defn values [xs: []int] -> [dynamic]int
  (into [dynamic]int
    (comp
      (filter between?))
    xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "transform callback currently expects a one-argument function")
}

@(test)
reject_functional_transform_callback_type_mismatch :: proc(t: ^testing.T) {
    source := `(package main)

(defn positive? [x: int] -> bool
  (> x 0))

(defn values [xs: []string] -> [dynamic]string
  (into [dynamic]string
    (comp
      (filter positive?))
    xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "transform callback expects int but pipeline has string")
}

@(test)
reject_functional_transform_filter_non_bool :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn values [xs: []int] -> [dynamic]int
  (into [dynamic]int
    (comp
      (filter inc))
    xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "filter transform expects bool callback result, got int")
}

@(test)
reject_functional_transform_unsupported_transduce_reducer :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn total [xs: []int] -> int
  (transduce
    (comp
      (map inc))
    * 1 xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "transduce currently supports + as reducer")
}

@(test)
reject_functional_transform_output_type_mismatch :: proc(t: ^testing.T) {
    source := `(package main)

(defn even? [x: int] -> bool
  (= (% x 2) 0))

(defn label [x: int] -> string
  "x")

(defn values [xs: []int] -> [dynamic]int
  (into [dynamic]int
    (comp
      (filter even?)
      (map label))
    xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "into transform output element type is int, but pipeline produces string")
}

@(test)
compile_threaded_let_binding_keeps_owned_intermediates_alive :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User {
  name: string
  active: bool
})

(defn main []
  (let [users ([]User [(User {name: "Ada" active: true})
                           (User {name: "Lin" active: false})
                           (User {name: "Grace" active: true})])
        active-names (->> users
                          (arr.filter .active)
                          (arr.map .name)
                          (arr.take 1))]
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_thread_1 := kvist_filter_field_active((users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_2 := kvist_map_field_name(type_of(((kvist_thread_1)[:])[0].name), (kvist_thread_1)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_2)"), true)
    testing.expect_value(t, strings.contains(output, "active_names := arr__take(1, (kvist_thread_2)[:])"), true)
}

@(test)
compile_imported_arr_reduce_thread_step :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn inc [x: int] -> int
  (+ x 1))

(defn add [acc: int, x: int] -> int
  (+ acc x))

(defn total [xs: []int] -> int
  (let [total (->> xs
                   (arr.map inc)
                   (arr.reduce add 0))]
    total))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_thread_1 := kvist_map(inc, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "total := kvist_reduce(add, 0, (kvist_thread_1)[:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__reduce(add"), false)
}

@(test)
reject_threaded_return_with_allocating_intermediate :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn even? [x: int] -> bool
  (= (% x 2) 0))

(defn bad [xs: []int] -> []int
  (->> xs
       (arr.map inc)
       (arr.filter even?)
       (arr.take 1)))`

    _, err, ok := kvist.compile_source(source)
    defer delete(err.message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "threaded return has an allocating intermediate; bind the pipeline with let so Kvist can emit cleanup")
}

@(test)
reject_returning_threaded_view_of_owned_intermediate :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User {
  name: string
  active: bool
})

(defn bad [users: []User] -> []string
  (let [active-names (->> users
                          (arr.filter .active)
                          (arr.map .name)
                          (arr.take 1))]
    active-names))`

    _, err, ok := kvist.compile_source(source)
    defer delete(err.message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "cannot return a threaded slice view that borrows from an owned intermediate; return an owned result or keep the pipeline local")
}

@(test)
compile_additional_sequence_helpers :: proc(t: ^testing.T) {
    source := `(package main)

(defn even? [x: int] -> bool
  (= (% x 2) 0))

(defn add-index [i: int, x: int] -> int
  (+ i x))

(defn keep-even [x: int] -> [value: int, ok: bool]
  (if (even? x)
    (return x true)
    (return 0 false)))

(defn pair [x: int] -> []int
  ([]int [x (+ x 10)]))

(defn neg [x: int] -> int
  (- x))

(defn pick-first [n: int] -> int
  0)

(defn main []
  (let [xs ([]int [1 2 3])
        mutable ([dynamic]int [1 2 3])
        ys ([]int [4 5])
        without-evens (arr.remove even? xs)
        kept (arr.keep keep-even xs)
        joined (concat without-evens ys)
        copied (arr.into [dynamic]int xs)
        descending (arr.sort-by neg joined)
        threaded-sorted (->> xs
                             (arr.remove even?)
                             (arr.keep keep-even))
        tail-last (arr.last joined)]
    (defer (delete mutable))
    (defer (delete without-evens))
    (defer (delete kept))
    (defer (delete joined))
    (defer (delete copied))
    (defer (delete descending))
    (defer (delete threaded-sorted))
    (arr.sort-by! neg xs)
    (arr.map! neg mutable)
    (arr.filter! even? mutable)
    (arr.remove! even? mutable)
    (arr.keep! keep-even mutable)
    (arr.into! mutable ys)
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "without_evens := kvist_remove(even_p, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kept := kvist_keep(keep_even, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "joined := kvist_concat((without_evens)[:], (ys)[:])"), true)
    testing.expect_value(t, strings.contains(output, "copied := kvist_into([dynamic]int, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "descending := kvist_sort_by_callback_neg((joined)[:])"), true)
    testing.expect_value(t, strings.contains(output, "import kvist_slice \"core:slice\""), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_1 := kvist_remove(even_p, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "threaded_sorted := kvist_keep(keep_even, (kvist_thread_1)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sort_by_in_place_callback_neg((xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_map_in_place(neg, (mutable)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_filter_in_place(even_p, &(mutable))"), true)
    testing.expect_value(t, strings.contains(output, "kvist_remove_in_place(even_p, &(mutable))"), true)
    testing.expect_value(t, strings.contains(output, "kvist_keep_in_place(keep_even, &(mutable))"), true)
    testing.expect_value(t, strings.contains(output, "append(&(mutable), ..(ys)[:])"), true)
    testing.expect_value(t, strings.contains(output, "tail_last := ((joined)[:])[len((joined)[:])-1]"), true)
    testing.expect_value(t, strings.contains(output, "kvist_remove :: proc(pred: proc(x: $T) -> bool, xs: []T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_keep :: proc(f: proc(x: $T) -> ($U, bool), xs: []T) -> [dynamic]U"), true)
    testing.expect_value(t, strings.contains(output, "kvist_into :: proc($Out: typeid, xs: []$T) -> Out"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sort :: proc(xs: []$T) -> [dynamic]T"), false)
    testing.expect_value(t, strings.contains(output, "kvist_sort_by_callback_neg :: proc(xs: []$T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "return neg(a) < neg(b)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sort_in_place :: proc(xs: []$T)"), false)
    testing.expect_value(t, strings.contains(output, "kvist_sort_by_in_place_callback_neg :: proc(xs: []$T)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_map_in_place :: proc(f: proc(x: $T) -> T, xs: []T)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_filter_in_place :: proc(pred: proc(x: $T) -> bool, xs: ^[dynamic]T)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_remove_in_place :: proc(pred: proc(x: $T) -> bool, xs: ^[dynamic]T)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_keep_in_place :: proc(f: proc(x: $T) -> (T, bool), xs: ^[dynamic]T)"), true)
}

@(test)
compile_chunking_and_zipmap_sequence_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")
(import map "kvist:map")

(defn even? [x: int] -> bool
  (= (% x 2) 0))

(defn identity [x: int] -> int
  x)

(defn parity [x: int] -> int
  (% x 2))

(defn main []
  (let [xs ([]int [1 2 2 3 3 3])
        names ([]string ["Ada" "Lin"])
        ages ([]int [36 17])
        [front back] (arr.split-at 2 xs)
        chunks (arr.partition 2 xs)
        chunks-all (arr.partition-all 3 xs)
        by-run (arr.partition-by identity xs)
        by-name (map.zip names ages)
        by-parity (arr.group-by parity xs)
        unique (arr.distinct xs)
        distinct-parity (arr.distinct-by parity xs)
        threaded (->> xs
                      (arr.remove even?)
                      (arr.distinct)
                      (arr.partition-by identity))]
    (defer (delete chunks))
    (defer (delete chunks-all))
    (defer (delete by-run))
    (defer (delete by-name))
    (defer
      (each [_ group by-parity]
        (delete group))
      (delete by-parity))
    (defer (delete unique))
    (defer (delete distinct-parity))
    (defer (delete threaded))
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "front, back := arr__split_at(2, xs)"), true)
    testing.expect_value(t, strings.contains(output, "chunks := arr__partition(2, xs)"), true)
    testing.expect_value(t, strings.contains(output, "chunks_all := arr__partition_all(3, xs)"), true)
    testing.expect_value(t, strings.contains(output, "by_run := arr__partition_by_impl(identity, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "by_name := map__zip(names, ages)"), true)
    testing.expect_value(t, strings.contains(output, "by_parity := arr__group_by_impl(parity, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "unique := arr__distinct_impl((xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "distinct_parity := arr__distinct_by_impl(parity, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "for _, group in by_parity {"), true)
    testing.expect_value(t, strings.contains(output, "delete(group)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_1 := kvist_remove(even_p, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_2 := arr__distinct_impl((kvist_thread_1)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_2)"), true)
    testing.expect_value(t, strings.contains(output, "threaded := arr__partition_by_impl(identity,"), true)
    testing.expect_value(t, strings.contains(output, "arr__split_at :: #force_inline proc(n: int, xs: []$T) -> (left: []T, right: []T) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__partition :: #force_inline proc(n: int, xs: []$T) -> [dynamic][]T {"), true)
    testing.expect_value(t, strings.contains(output, "arr__partition_all :: #force_inline proc(n: int, xs: []$T) -> [dynamic][]T {"), true)
    testing.expect_value(t, strings.contains(output, "arr__partition_by_impl :: #force_inline proc(f: proc(x: $T) -> $K, xs: []T) -> [dynamic][]T {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_partition_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> [dynamic][]T"), false)
    testing.expect_value(t, strings.contains(output, "map__zip :: #force_inline proc(ks: []$K, vs: []$V) -> map[K]V {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_zipmap :: proc(keys: []$K, values: []$V) -> map[K]V"), false)
    testing.expect_value(t, strings.contains(output, "kvist_partition :: proc(n: int, xs: []$T) -> [dynamic][]T"), false)
    testing.expect_value(t, strings.contains(output, "kvist_partition_all :: proc(n: int, xs: []$T) -> [dynamic][]T"), false)
    testing.expect_value(t, strings.contains(output, "map__arr__group_by_impl :: #force_inline proc(f: proc(x: $T) -> $K, xs: []T) -> map[K][dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_group_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> map[K][dynamic]T"), false)
    testing.expect_value(t, strings.contains(output, "map__arr__distinct_impl :: #force_inline proc(xs: []$T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_distinct :: proc(xs: []$T) -> [dynamic]T"), false)
    testing.expect_value(t, strings.contains(output, "map__arr__distinct_by_impl :: #force_inline proc(f: proc(x: $T) -> $K, xs: []T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_distinct_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> [dynamic]T"), false)
    testing.expect_value(t, strings.contains(output, "kvist_split_at"), false)
}

@(test)
compile_map_constructing_sequence_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")
(import map "kvist:map")

(defn identity [x: int] -> int
  x)

(defn amount [x: int] -> int
  x)

(defn main []
  (let [xs ([]int [1 2 2 3])
        by-value (arr.index-by identity xs)
        by-group (arr.group-by identity xs)
        by-sum (arr.sum-by identity amount xs)
        counts (arr.frequencies xs)
        base (map[string]int {"a" 1 "b" 2})
        overrides (map[string]int {"b" 20 "c" 30})
        merged (map.merge base overrides)
        key-list (map.keys base)
        value-list (map.vals overrides)
        key-count (->> merged
                       (map.keys)
                       (count))]
    (defer (delete by-value))
    (defer
      (each [_ group by-group]
        (delete group))
      (delete by-group))
    (defer (delete by-sum))
    (defer (delete counts))
    (defer (delete base))
    (defer (delete overrides))
    (defer (delete merged))
    (defer (delete key-list))
    (defer (delete value-list))
    (when (= key-count 0)
      (return))
    (map.merge! base overrides)
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "by_value := arr__index_by_impl(identity, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "by_group := arr__group_by_impl(identity, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "by_sum := arr__sum_by_impl(identity, amount,"), true)
    testing.expect_value(t, strings.contains(output, "counts := arr__frequencies_impl((xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "map__merge :: #force_inline proc(lhs, rhs: map[$K]$V) -> map[K]V {"), true)
    testing.expect_value(t, strings.contains(output, "map__keys :: #force_inline proc(m: map[$K]$V) -> [dynamic]K {"), true)
    testing.expect_value(t, strings.contains(output, "map__vals :: #force_inline proc(m: map[$K]$V) -> [dynamic]V {"), true)
    testing.expect_value(t, strings.contains(output, "merged := map__merge(base, overrides)"), true)
    testing.expect_value(t, strings.contains(output, "key_list := map__keys(base)"), true)
    testing.expect_value(t, strings.contains(output, "value_list := map__vals(overrides)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_1 := map__keys(merged)"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "key_count := len((kvist_thread_1)[:])"), true)
    testing.expect_value(t, strings.contains(output, "for key, value in overrides {"), true)
    testing.expect_value(t, strings.contains(output, "base[key] = value"), true)
    testing.expect_value(t, strings.contains(output, "map__arr__index_by_impl :: #force_inline proc(f: proc(x: $T) -> $K, xs: []T) -> map[K]T {"), true)
    testing.expect_value(t, strings.contains(output, "map__arr__group_by_impl :: #force_inline proc(f: proc(x: $T) -> $K, xs: []T) -> map[K][dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_group_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> map[K][dynamic]T"), false)
    testing.expect_value(t, strings.contains(output, "kvist_count_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> map[K]int"), false)
    testing.expect_value(t, strings.contains(output, "kvist_index_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> map[K]T"), false)
    testing.expect_value(t, strings.contains(output, "map__arr__sum_by_impl :: #force_inline proc(key_f: proc(x: $T) -> $K, value_f: proc(x: T) -> $V, xs: []T) -> map[K]V {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sum_by :: proc(key_f: proc(x: $T) -> $K, value_f: proc(x: T) -> $V, xs: []T) -> map[K]V"), false)
    testing.expect_value(t, strings.contains(output, "map__arr__frequencies_impl :: #force_inline proc(xs: []$T) -> map[T]int {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_frequencies :: proc(xs: []$T) -> map[T]int"), false)
    testing.expect_value(t, strings.contains(output, "kvist_merge :: proc(lhs, rhs: map[$K]$V) -> map[K]V"), false)
    testing.expect_value(t, strings.contains(output, "kvist_merge_in_place"), false)
    testing.expect_value(t, strings.contains(output, "kvist_keys :: proc(m: map[$K]$V) -> [dynamic]K"), false)
    testing.expect_value(t, strings.contains(output, "kvist_vals :: proc(m: map[$K]$V) -> [dynamic]V"), false)
}

@(test)
compile_bounded_sequence_producers :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn next [] -> int
  42)

(defn double [x: int] -> int
  (* x 2))

(defn main []
  (let [xs (arr.range 1 5)
        ys (arr.repeat 3 "x")
        zs (arr.repeatedly 2 next)
        powers (arr.iterate 4 double 1)
        cycled (arr.cycle 5 ([]int [1 2]))]
    (defer (delete xs))
    (defer (delete ys))
    (defer (delete zs))
    (defer (delete powers))
    (defer (delete cycled))
    (return)))`

    dir, dir_err := os.make_directory_temp("", "kvist-bounded-producers-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    write_err := os.write_entire_file(path, transmute([]byte)source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "xs := arr__range_impl(1, 5, 1)"), true)
    testing.expect_value(t, strings.contains(output, "ys := arr__repeat(3, \"x\")"), true)
    testing.expect_value(t, strings.contains(output, "zs := arr__repeatedly(2, next)"), true)
    testing.expect_value(t, strings.contains(output, "powers := arr__iterate(4, double, 1)"), true)
    testing.expect_value(t, strings.contains(output, "cycled := arr__cycle(5, []int{1, 2})"), true)
    testing.expect_value(t, strings.contains(output, "arr__range_impl :: #force_inline proc(start, end, step: int) -> [dynamic]int {"), true)
    testing.expect_value(t, strings.contains(output, "arr__repeat :: #force_inline proc(n: int, value: $T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "arr__repeatedly :: #force_inline proc(n: int, f: proc() -> $T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "arr__iterate :: #force_inline proc(n: int, f: proc(x: $T) -> T, init: T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "arr__cycle :: #force_inline proc(n: int, xs: []$T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_range"), false)
    testing.expect_value(t, strings.contains(output, "kvist_repeat"), false)
    testing.expect_value(t, strings.contains(output, "kvist_repeatedly"), false)
    testing.expect_value(t, strings.contains(output, "kvist_iterate"), false)
    testing.expect_value(t, strings.contains(output, "kvist_cycle"), false)
}

@(test)
compile_field_selector_callbacks_for_sequence_helpers :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User {
  name: string
  amount: int
  verified: bool
})

(defn main []
  (let [users ([]User [(User {name: "Ada" amount: 10 verified: true})
                           (User {name: "Lin" amount: 20 verified: false})])
        names (arr.map .name users)
        by-name (arr.index-by .name users)
        by-verified (arr.group-by .verified users)
        count-by-verified (arr.count-by .verified users)
        sum-by-verified (arr.sum-by .verified .amount users)
        groups (arr.partition-by .verified users)
        distinct-names (arr.distinct-by .name users)
        sorted (arr.sort-by .name users)
        mutated ([dynamic]User [(User {name: "Ada" amount: 10 verified: true})
                                    (User {name: "Lin" amount: 20 verified: false})])
        verified (arr.filter .verified users)
        unverified (arr.remove .verified users)
        [first ok] (arr.find .verified users)
        any? (arr.some? .verified users)
        all? (arr.every? .verified verified)]
    (defer
      (each [_ group by-verified]
        (delete group))
      (delete by-verified))
    (arr.sort-by! .name mutated)
    (arr.filter! .verified mutated)
    (arr.remove! .verified mutated)
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "names := kvist_map_field_name(type_of(((users)[:])[0].name), (users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "by_name := kvist_index_by_field_name(type_of(((users)[:])[0].name), (users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "by_verified := kvist_group_by_field_verified(type_of(((users)[:])[0].verified), (users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "count_by_verified := kvist_count_by_field_verified(type_of(((users)[:])[0].verified), (users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "sum_by_verified := kvist_sum_by_fields_verified_amount(type_of(((users)[:])[0].verified), type_of(((users)[:])[0].amount), (users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "groups := kvist_partition_by_field_verified(type_of(((users)[:])[0].verified), (users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "distinct_names := kvist_distinct_by_field_name(type_of(((users)[:])[0].name), (users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "sorted := kvist_sort_by_field_name(type_of(((users)[:])[0].name), (users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sort_by_in_place_field_name((mutated)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_filter_in_place_field_verified(&(mutated))"), true)
    testing.expect_value(t, strings.contains(output, "kvist_remove_in_place_field_verified(&(mutated))"), true)
    testing.expect_value(t, strings.contains(output, "verified := kvist_filter_field_verified((users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "unverified := kvist_remove_field_verified((users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "first, ok := kvist_find_field_verified((users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "any_p := kvist_some_p_field_verified((users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "all_p := kvist_every_p_field_verified((verified)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_map_field_name :: proc($Field_Type: typeid, xs: []$T) -> [dynamic]Field_Type"), true)
    testing.expect_value(t, strings.contains(output, "kvist_index_by_field_name :: proc($Key: typeid, xs: []$T) -> map[Key]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_group_by_field_verified :: proc($Key: typeid, xs: []$T) -> map[Key][dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_count_by_field_verified :: proc($Key: typeid, xs: []$T) -> map[Key]int"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sum_by_fields_verified_amount :: proc($Key: typeid, $Value: typeid, xs: []$T) -> map[Key]Value"), true)
    testing.expect_value(t, strings.contains(output, "kvist_partition_by_field_verified :: proc($Key: typeid, xs: []$T) -> [dynamic][]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_distinct_by_field_name :: proc($Key: typeid, xs: []$T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sort_by_field_name :: proc($Key: typeid, xs: []$T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_slice.sort_by(out[:], proc(a, b: T) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sort_by_in_place_field_name :: proc(xs: []$T)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_slice.sort_by(xs, proc(a, b: T) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "kvist_filter_in_place_field_verified :: proc(xs: ^[dynamic]$T)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_remove_in_place_field_verified :: proc(xs: ^[dynamic]$T)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_filter_field_verified :: proc(xs: []$T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_remove_field_verified :: proc(xs: []$T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_find_field_verified :: proc(xs: []$T) -> (value: T, ok: bool)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_some_p_field_verified :: proc(xs: []$T) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "kvist_every_p_field_verified :: proc(xs: []$T) -> bool"), true)
}

@(test)
compile_sequence_indexing_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")
(import arr "kvist:arr")

(defn main []
  (let [xs ([]int [10 20 30])
        a (arr.first xs)
        b (arr.second xs)
        c (arr.nth xs 2)
        n (count xs)
        tail (arr.rest xs)
        threaded (->> xs
                      (arr.rest)
                      (count))]
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "a := xs[0]"), true)
    testing.expect_value(t, strings.contains(output, "b := xs[1]"), true)
    testing.expect_value(t, strings.contains(output, "c := xs[2]"), true)
    testing.expect_value(t, strings.contains(output, "n := len((xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "tail := (xs)[1:]"), true)
    testing.expect_value(t, strings.contains(output, "threaded := len((((xs)[:])[1:])[:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__rest(xs)"), false)
}

@(test)
allow_returning_owned_sequence_result :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn owned [xs: []int] -> [dynamic]int
  (arr.map inc xs))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return kvist_map(inc, (xs)[:])"), true)
}

@(test)
warn_discarded_owned_sequence_result :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn main []
  (let [xs ([]int [1 2 3])]
    (arr.map inc xs)
    (return)))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from arr.map is discarded; bind it, delete it, or return it")
    }
}

@(test)
reject_legacy_unqualified_sequence_helpers :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn main []
  (let [xs ([]int [1 2 3])
        ys (map inc xs)
        first-y (->> xs
                     (map inc)
                     (first))]
    (defer (delete ys))
    (println first-y)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "`map` is no longer a core helper; use `arr.map`")
    delete(err.message)

    source = `(package main)

(defn even? [x: int] -> bool
  (= (% x 2) 0))

(defn main [xs: []int]
  (arr.filter even? xs)
  (filter even? xs)
  (return))`

    _, err, ok = kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "`filter` is no longer a core helper; use `arr.filter`")
    delete(err.message)

    source = `(package main)

(defn main []
  (let [xs (range 5)]
    (defer (delete xs))
    (return)))`

    _, err, ok = kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "`range` is no longer a core helper; use `arr.range`")
    delete(err.message)

    source = `(package main)

(defn main [xs: []int]
  (first xs))`

    _, err, ok = kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "`first` is no longer a core helper; use `arr.first`")
    delete(err.message)

    source = `(package main)

(defn main [xs: []int]
  (rest xs))`

    _, err, ok = kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "`rest` is no longer a core helper; use `arr.rest`")
    delete(err.message)

    source = `(package main)

(defn main [keys: []string, vals: []int]
  (zipmap keys vals))`

    _, err, ok = kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "`zipmap` is no longer a core helper; use `map.zip`")
    delete(err.message)

    source = `(package main)

(defn main [lhs: map[string]int, rhs: map[string]int]
  (merge lhs rhs))`

    _, err, ok = kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "`merge` is no longer a core helper; use `map.merge`")
    delete(err.message)

    source = `(package main)

(defn main [target: map[string]int, source: map[string]int]
  (merge! target source)
  (return))`

    _, err, ok = kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "`merge!` is no longer a core helper; use `map.merge!`")
    delete(err.message)

    source = `(package main)

(defn main [xs: []int]
  (into! xs xs)
  (return))`

    _, err, ok = kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "`into!` is no longer a core helper; use `arr.into!`")
    delete(err.message)

    source = `(package main)

(defn main [path: string]
  (slurp path))`

    _, err, ok = kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "`slurp` is no longer a core helper; use `io.read`")
    delete(err.message)

    source = `(package main)
(import io "kvist:io")

(defn main [path: string, text: string]
  (io.write path text)
  (spit path text)
  (return))`

    _, err, ok = kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "`spit` is no longer a core helper; use `io.write`")
    delete(err.message)
}

@(test)
report_namespaced_sequence_helper_errors_with_surface_name :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn main [xs: []int]
  (let [mapped (arr.map inc)]
    (return mapped)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "arr.map expects function and collection")
}

@(test)
report_namespaced_thread_helper_errors_with_surface_name :: proc(t: ^testing.T) {
    source := `(package main)

(defn main [xs: []int]
  (->> xs
       (map.zip))
  (return))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "map.zip thread step expects one key collection argument")
}

@(test)
reject_nested_owned_sequence_result :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [xs: []int] -> int
  (arr.first (arr.map inc xs)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "arr.map returns an owned result; bind it so it can be deleted, or return it to transfer ownership")
}

@(test)
reject_nested_tapped_owned_sequence_result :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [xs: []int] -> int
  (arr.first (tap> "mapped" (arr.map inc xs))))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "arr.map returns an owned result; bind it so it can be deleted, or return it to transfer ownership")
}

@(test)
warn_discarded_slurp_result :: proc(t: ^testing.T) {
    source := `(package main)
(import io "kvist:io")

(defn main []
  (io.read "cache.json")
  (return))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from io.read is discarded; bind it, delete it, or return it")
    }
}

@(test)
compile_collection_type_forms_and_make :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct State {
  values: (slice int)
  buffer: (dynamic int)
  lookup: (map string int)
  next: (ptr State)
})

(defn main []
  (let [values ((slice int) [1 2 3])
        buffer (make (dynamic int))
        lookup (make (map string int))]
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

State :: struct {
    values: []int,
    buffer: [dynamic]int,
    lookup: map[string]int,
    next: ^State,
}

main :: proc() {
    values := []int{1, 2, 3}
    buffer := make([dynamic]int)
    lookup := make(map[string]int)
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_soa_type_call_column_access_and_push :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")
(import arr "kvist:arr")

(defstruct Particle {
  mass: f32
  id: int
})

(defn fixed-first [] -> f32
  (let [particles (#soa[2]Particle
                    [(Particle {mass: 1 id: 10})
                     (Particle {mass: 2 id: 20})])]
    (arr.get particles.mass 0)))

(defn add-particle! [particles: ^#soa[dynamic]Particle
                     particle: Particle]
  (arr.push! particles particle)
  (return))

(defn dynamic-score [] -> f32
  (let [particles (#soa[dynamic]Particle
                    [(Particle {mass: 1 id: 10})])]
    (defer (delete particles))
    (arr.push! particles (Particle {mass: 2 id: 20}))
    (set! particles.mass[0] 12)
    (+ (arr.get particles.mass 0)
       (arr.get particles 1).mass)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "fixed_first :: proc() -> f32"), true)
    testing.expect_value(t, strings.contains(output, "particles := #soa[2]Particle{"), true)
    testing.expect_value(t, strings.contains(output, "return particles.mass[0]"), true)
    testing.expect_value(t, strings.contains(output, "add_particle_bang :: proc(particles: ^#soa[dynamic]Particle, particle: Particle)"), true)
    testing.expect_value(t, strings.contains(output, "append_soa(particles, particle)"), true)
    testing.expect_value(t, strings.contains(output, "dynamic_score :: proc() -> f32"), true)
    testing.expect_value(t, strings.contains(output, "particles := (proc() -> #soa[dynamic]Particle {"), true)
    testing.expect_value(t, strings.contains(output, "out := make(#soa[dynamic]Particle)"), true)
    testing.expect_value(t, strings.contains(output, "append_soa(&out, Particle{"), true)
    testing.expect_value(t, strings.contains(output, "append_soa(&(particles), Particle{"), true)
    testing.expect_value(t, strings.contains(output, "(particles.mass)[0] = 12"), true)
    testing.expect_value(t, strings.contains(output, "return (particles.mass[0]) + (particles[1].mass)"), true)
}

@(test)
compile_soa_convenience_macros :: proc(t: ^testing.T) {
    source := `(package main)
(import soa "kvist:soa")

(defstruct Particle {
  x: f32
  vx: f32
  mass: f32
})

(defn update-one [] -> f32
  (let [particles (soa.make Particle 2)]
    (defer (delete particles))
    (soa.push! particles (Particle {x: 1 vx: 2 mass: 3}))
    (soa.update! particles 0
      .vx (+ vx 10)
      .x (+ x vx))
    (+ particles.x[0] particles.vx[0])))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "particles := make(#soa[dynamic]Particle, 0, 2)"), true)
    testing.expect_value(t, strings.contains(output, "append(&(particles), Particle{x = 1, vx = 2, mass = 3})"), true)
    testing.expect_value(t, strings.contains(output, "vx := particles.vx[0]"), true)
    testing.expect_value(t, strings.contains(output, "x := particles.x[0]"), true)
    testing.expect_value(t, strings.contains(output, "particles.vx[0] = (vx) + (10)"), true)
    testing.expect_value(t, strings.contains(output, "particles.x[0] = (x) + (vx)"), true)
}

@(test)
compile_soa_column_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import soa "kvist:soa")

(defstruct Particle {
  x: f32
  vx: f32
})

(defn update-columns [] -> f32
  (let [particles (soa.make Particle 2)]
    (defer (delete particles))
    (soa.push! particles (Particle {x: 1 vx: 2}))
    (soa.push! particles (Particle {x: 3 vx: 4}))
    (soa.axpy! particles .x 0.5 .vx)
    (soa.clamp! particles .x 0.0 4.0)
    (let [total: f32 0]
      (soa.sum-into! total particles .x)
      (soa.dot-into! total particles .vx .vx)
      total)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "particles.x[i] += (0.5) * (particles.vx[i])"), true)
    testing.expect_value(t, strings.contains(output, "if (particles.x[i]) < (0.0)"), true)
    testing.expect_value(t, strings.contains(output, "total += particles.x[i]"), true)
    testing.expect_value(t, strings.contains(output, "total += (particles.vx[i]) * (particles.vx[i])"), true)
}

@(test)
compile_matrix_surface_type_constructor :: proc(t: ^testing.T) {
    source := `(package main)
(import linalg "core:math/linalg")

(defn score [] -> f32
  (let [m (matrix[2 2]f32 [1.0 2.0 3.0 4.0])
        ident (linalg.identity (type matrix[2 2]f32))
        product (linalg.mul m ident)
        flat (linalg.matrix_flatten product)]
    (+ (get flat 0) (get flat 3))))

(defn quat-score [] -> f64
  (let [q (quaternion [0.0 0.0 0.0 1.0])
        q2 (quaternion 0.0 0.0 0.0 1.0)
        unit (linalg.normalize q)]
    (+ (linalg.dot q unit)
       (linalg.dot q2 q2))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "m := matrix[2, 2]f32{1.0, 2.0, 3.0, 4.0}"), true)
    testing.expect_value(t, strings.contains(output, "ident := linalg.identity(matrix[2, 2]f32)"), true)
    testing.expect_value(t, strings.contains(output, "product := linalg.mul(m, ident)"), true)
    testing.expect_value(t, strings.contains(output, "flat := linalg.matrix_flatten(product)"), true)
    testing.expect_value(t, strings.contains(output, "q := quaternion(x=0.0, y=0.0, z=0.0, w=1.0)"), true)
    testing.expect_value(t, strings.contains(output, "q2 := quaternion(x=0.0, y=0.0, z=0.0, w=1.0)"), true)
    testing.expect_value(t, strings.contains(output, "unit := linalg.normalize(q)"), true)
    testing.expect_value(t, strings.contains(output, "return (linalg.dot(q, unit)) + (linalg.dot(q2, q2))"), true)
}

@(test)
compile_bit_set_and_simd_surface_type_constructors :: proc(t: ^testing.T) {
    source := `(package main)
(import intrinsics "base:intrinsics")

(defenum Permission [
  Read
  Write
  Execute
])

(defn permissions [] -> bit_set[Permission; u8]
  (bit_set[Permission; u8] [.Read .Execute]))

(defn simd-score [] -> f32
  (let [v (#simd[4]f32 [1.0 2.0 3.0 4.0])
        doubled (intrinsics.simd_add v v)]
    (intrinsics.simd_reduce_add_ordered doubled)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "permissions :: proc() -> bit_set[Permission; u8]"), true)
    testing.expect_value(t, strings.contains(output, "return bit_set[Permission; u8]{.Read, .Execute}"), true)
    testing.expect_value(t, strings.contains(output, "v := #simd[4]f32{1.0, 2.0, 3.0, 4.0}"), true)
    testing.expect_value(t, strings.contains(output, "doubled := intrinsics.simd_add(v, v)"), true)
    testing.expect_value(t, strings.contains(output, "return intrinsics.simd_reduce_add_ordered(doubled)"), true)
}

@(test)
compile_polymorphic_type_form :: proc(t: ^testing.T) {
    source := `(package main)
(import chan "core:sync/chan")

(defstruct Queue {
  jobs: (type chan.Chan int)
})

(defn recv-job [jobs: (type chan.Chan int)] -> int
  (let [[value ok] (chan.recv jobs)]
    (if ok value 0)))

(defn main []
  (let [[jobs err] (chan.create (type chan.Chan int) context.allocator)]
    (defer (chan.destroy jobs))
    (if (= err .None)
      (return)
      (return))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import chan "core:sync/chan"

Queue :: struct {
    jobs: chan.Chan(int),
}

recv_job :: proc(jobs: chan.Chan(int)) -> int {
    value, ok := chan.recv(jobs)
    if ok {
        return value
    }
    else {
        return 0
    }
}

main :: proc() {
    jobs, err := chan.create(chan.Chan(int), context.allocator)
    defer chan.destroy(jobs)
    if (err) == (.None) {
        return
    }
    else {
        return
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_array_map_literals_and_typed_let_type_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Config {
  ports: (array 3 int)
  lookup: (map string int)
})

(defn main []
  (let [ports: (array 3 int) ((array 3 int) [80 443 8080])
        lookup: (map string int) ((map string int) {"http" 80 "https" 443})]
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `#+feature dynamic-literals
package main

Config :: struct {
    ports: [3]int,
    lookup: map[string]int,
}

main :: proc() {
    ports: [3]int = [3]int{80, 443, 8080}
    lookup: map[string]int = map[string]int{"http" = 80, "https" = 443}
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_type_call_expression_for_positional_odin_aggregates :: proc(t: ^testing.T) {
    source := `(package main)
(import rl "vendor:raylib")

(defn main []
  (rl.SetWindowState (rl.ConfigFlags [.WINDOW_RESIZABLE]))
  (rl.ClearBackground (rl.Color [110 184 168 255])))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import rl "vendor:raylib"

main :: proc() {
    rl.SetWindowState(rl.ConfigFlags{.WINDOW_RESIZABLE})
    rl.ClearBackground(rl.Color{110, 184, 168, 255})
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_imported_odin_proc_calls_infer_aggregate_arg_types :: proc(t: ^testing.T) {
    source := `(package main)
(import rl "vendor:raylib")

(defn main []
  (rl.SetConfigFlags [.WINDOW_RESIZABLE])
  (rl.ClearBackground [110 184 168 255]))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import rl "vendor:raylib"

main :: proc() {
    rl.SetConfigFlags(rl.ConfigFlags{.WINDOW_RESIZABLE})
    rl.ClearBackground(rl.Color{110, 184, 168, 255})
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_typed_odin_aggregate_keyword_labels :: proc(t: ^testing.T) {
    source := `(package main)
(import rl "vendor:raylib")

(defn rect [frame: int width: f32 frames: int height: f32] -> rl.Rectangle
  (rl.Rectangle {x: (/ (* (f32 frame) width) (f32 frames))
                 y: 0
                 width: (/ width (f32 frames))
                 height: height}))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import rl "vendor:raylib"

rect :: proc(frame: int, width: f32, frames: int, height: f32) -> rl.Rectangle {
    return rl.Rectangle{x = ((f32(frame)) * (width)) / (f32(frames)), y = 0, width = (width) / (f32(frames)), height = height}
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_typed_odin_aggregate_positional_vector_literal :: proc(t: ^testing.T) {
    source := `(package main)
(import rl "vendor:raylib")

(defn platform-collider [pos: rl.Vector2] -> rl.Rectangle
  (rl.Rectangle [pos.x pos.y 96 16]))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import rl "vendor:raylib"

platform_collider :: proc(pos: rl.Vector2) -> rl.Rectangle {
    return rl.Rectangle{pos.x, pos.y, 96, 16}
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_imported_odin_struct_constructor_uses_field_type_context :: proc(t: ^testing.T) {
    source := `(package main)
(import rl "vendor:raylib")

(defn make-camera [player-pos: rl.Vector2] -> rl.Camera2D
  (rl.Camera2D {zoom: (f32 1)
                offset: [(f32 2) (f32 3)]
                target: player-pos}))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return rl.Camera2D{zoom = f32(1), offset = rl.Vector2{f32(2), f32(3)}, target = player_pos}"), true)
}

@(test)
compile_local_var_block_and_mut_bang_forms :: proc(t: ^testing.T) {
    source := `(package main)
(import rl "vendor:raylib")

(defn main []
  (defvar player-pos (rl.Vector2 [0 0]))
  (defvar player-vel: rl.Vector2 [1 2])
  (block
    (defvar dt 0.5)
    (mut! player-vel.y += dt)
    (set! player-pos.x 10)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import rl "vendor:raylib"

main :: proc() {
    player_pos := rl.Vector2{0, 0}
    player_vel: rl.Vector2 = rl.Vector2{1, 2}
    {
        dt := 0.5
        player_vel.y += dt
        player_pos.x = 10
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_rejects_positional_brace_aggregate_literals :: proc(t: ^testing.T) {
    source := `(package main)
(import rl "vendor:raylib")

(defn bad [] -> rl.Vector2
  (rl.Vector2 {0 0}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "positional aggregate literals use vector syntax"), true)
}

@(test)
compile_accepts_trailing_colon_field_labels :: proc(t: ^testing.T) {
    source := `(package main)
(import rl "vendor:raylib")

(defn rect [] -> rl.Rectangle
  (rl.Rectangle {x: 0 y: 0 width: 1 height: 1}))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return rl.Rectangle{x = 0, y = 0, width = 1, height = 1}"), true)
}

@(test)
compile_multiline_composite_literals :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Handler {
  run: (fn [] -> int)
})

(defn main []
  (let [handler (Handler {run: (fn [] -> int
                                  42)})
        handlers ((slice Handler)
                   [(Handler {run: (fn [] -> int
                                      7)})])]
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Handler :: struct {
    run: proc() -> int,
}

main :: proc() {
    handler := Handler{
        run = proc() -> int {
            return 42
        },
    }
    handlers := []Handler{
        Handler{
            run = proc() -> int {
                return 7
            },
        },
    }
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_thread_first_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Method [
  Get
  Post
])

(defstruct Request {
  method: Method
  path: string
})

(defn method-name [method: Method] -> string
  (switch method
    .Get "GET"
    :else "OTHER"))

(defn describe [req: Request] -> string
  (-> req .method method-name))

(defn clone-path [req: Request, allocator: rawptr] -> string
  (-> req .path (clone-string allocator)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Method :: enum {
    Get,
    Post,
}

Request :: struct {
    method: Method,
    path: string,
}

method_name :: proc(method: Method) -> string {
    #partial switch method {
    case .Get:
        return "GET"
    case:
        return "OTHER"
    }
}

describe :: proc(req: Request) -> string {
    return method_name(req.method)
}

clone_path :: proc(req: Request, allocator: rawptr) -> string {
    return clone_string(req.path, allocator)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_pointer_deref_and_address_of :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Person {
  name: string
})

(defn ptr-value [x: ^int] -> int
  (deref x))

(defn bump [x: ^int]
  (set! (deref x) (+ (deref x) 1)))

(defn borrow-name [p: ^Person] -> ^string
  &p^.name)

(defn borrow-name-form [p: ^Person] -> ^string
  (addr p^.name))

(defn first-name [people: ^[]Person] -> string
  (deref people)[0].name)

(defn borrow-first-name [people: ^[]Person] -> ^string
  (addr (deref people)[0].name))

(defn borrow-cell [xs: [dynamic]int, i: int] -> ^int
  (addr xs[i]))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Person :: struct {
    name: string,
}

ptr_value :: proc(x: ^int) -> int {
    return x^
}

bump :: proc(x: ^int) {
    x^ = (x^) + (1)
}

borrow_name :: proc(p: ^Person) -> ^string {
    return &(p^.name)
}

borrow_name_form :: proc(p: ^Person) -> ^string {
    return &(p^.name)
}

first_name :: proc(people: ^[]Person) -> string {
    return (people^)[0].name
}

borrow_first_name :: proc(people: ^[]Person) -> ^string {
    return &((people^)[0].name)
}

borrow_cell :: proc(xs: [dynamic]int, i: int) -> ^int {
    return &((xs)[i])
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_pointer_suffix_deref_and_set_bang_locals :: proc(t: ^testing.T) {
    source := `(package main)

(defvar counter: int 0)

(defn bump [total: ^int] -> int
  (set! total^ (+ total^ 1))
  total^)

(defn main [] -> int
  (let [local 2]
    (set! local (+ local 1))
    (set! counter local)
    (bump &counter)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

expected := `package main

counter: int = 0

bump :: proc(total: ^int) -> int {
    total^ = (total^) + (1)
    return total^
}

main :: proc() -> int {
    local := 2
    local = (local) + (1)
    counter = local
    return bump(&counter)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_function_style_update_bang :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct Point {
  x: int
  y: int
})

(defn score [] -> int
  (let [xs ([dynamic]int [1 2 3])
        lookup (map[string]int {"a" 1})
        point (Point {x: 4 y: 5})]
    (update! xs[1] + 40)
    (update! xs[2] + 3)
    (update! (get lookup "a") + 6)
    (update! point.y + 4)
    (update! point.y inc)
    (+ (get xs 1) (get lookup "a") point.y)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `#+feature dynamic-literals
package main

Point :: struct {
    x: int,
    y: int,
}

score :: proc() -> int {
    xs := [dynamic]int{1, 2, 3}
    lookup := map[string]int{"a" = 1}
    point := Point{x = 4, y = 5}
    (xs)[1] += (40)
    (xs)[2] += (3)
    lookup["a"] += (6)
    point.y += (4)
    point.y += 1
    return (xs[1]) + (lookup["a"]) + (point.y)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_place_style_update_bang :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point {
  x: int
  name: string
})

(defn add-scaled [x: int scale: int delta: int] -> int
  (+ x (* scale delta)))

(defn trim-demo [s: string] -> string
  s)

(defn score [] -> int
  (let [point (Point {x: 4 name: "Ada"})
        total 10]
    (update! point.x add-scaled 2 3)
    (update! point.name trim-demo)
    (update! total + 5)
    (+ point.x total)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "point.x = add_scaled(point.x, 2, 3)"), true)
    testing.expect_value(t, strings.contains(output, "point.name = trim_demo(point.name)"), true)
    testing.expect_value(t, strings.contains(output, "total += (5)"), true)
}

@(test)
compile_update_bang_rejects_target_key_form :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn bad [] -> int
  (let [xs ([dynamic]int [1 2 3])]
    (update! xs 1 + 40)
    (get xs 1)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "update! expects updater function or operator")
}

@(test)
compile_mut_bang_assignment_place_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point {
  x: int
  y: int
  active?: bool
})

  (defn mutate [total: ^int] -> int
  (let [xs ([dynamic]int [1 2 3])
        point (Point {x: 4 y: 5 active?: false})]
    (mut! point.y += 4)
    (mut! (get point .y) += 1)
    (mut! (get xs 1) -= 2)
    (mut! (deref total) *= 3)
    (inc! point.x)
    (dec! (get xs 2))
    (toggle! point.active_p)
    (negate! point.x)
    (+ point.x point.y (get xs 1) (get xs 2) (deref total))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `#+feature dynamic-literals
package main

Point :: struct {
    x: int,
    y: int,
    active_p: bool,
}

mutate :: proc(total: ^int) -> int {
    xs := [dynamic]int{1, 2, 3}
    point := Point{x = 4, y = 5, active_p = false}
    point.y += 4
    (point).y += 1
    xs[1] -= 2
    total^ *= 3
    point.x += 1
    xs[2] -= 1
    point.active_p = !(point.active_p)
    point.x = -(point.x)
    return (point.x) + (point.y) + (xs[1]) + (xs[2]) + (total^)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_mut_bang_assignment_rejects_non_place :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [x: int y: int]
  (mut! (+ x y) += 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "mut! expects an assignable place")
}

@(test)
compile_set_bang_rejects_non_place :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [x: int y: int]
  (set! (+ x y) 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "set! expects an assignable place")
}

@(test)
compile_mut_bang_rejects_plain_assignment_operator :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [x: int]
  (mut! x = 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "mut! does not support =; use set! for plain assignment")
}

@(test)
compile_mut_bang_rejects_non_compound_operator :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [x: int]
  (mut! x + 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "mut! expects a compound assignment operator")
}

@(test)
compile_update_bang_rejects_non_place :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [x: int y: int]
  (update! (+ x y) + 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "update! expects an assignable place")
}

@(test)
compile_shallow_struct_assoc_exprs :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct Point {
  x: int
  y: int
  name: string
})

(defn inc [x: int] -> int
  (+ x 1))

(defn add-scaled [x: int, scale: int, offset: int] -> int
  (+ (* x scale) offset))

(defn score [] -> int
  (let [point (Point {x: 4 y: 5 name: "old"})
        older (assoc point.name "new")
        legacy (assoc older .name "legacy")]
    (+ point.y older.y (len older.name) (len legacy.name))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "older := (proc(kvist_target: Point, kvist_value: string) -> Point {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_1 := kvist_target"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_1.name = kvist_value"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_update_1"), true)
    testing.expect_value(t, strings.contains(output, "})(point, \"new\")"), true)
    testing.expect_value(t, strings.contains(output, "legacy := (proc(kvist_target: Point, kvist_value: string) -> Point {"), true)
    testing.expect_value(t, strings.contains(output, "})(older, \"legacy\")"), true)
}

@(test)
compile_nested_struct_assoc_exprs :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Profile {
  name: string
  age: int
})

(defstruct User {
  profile: Profile
  active?: bool
})

(defn inc [x: int] -> int
  (+ x 1))

(defn score [user: User] -> int
  (let [renamed (assoc user.profile.name "Ada")
        active (assoc renamed .active? true)]
    (+ active.profile.age (len renamed.profile.name))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "renamed := (proc(kvist_target: User, kvist_value: string) -> User {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_1 := kvist_target"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_1.profile.name = kvist_value"), true)
    testing.expect_value(t, strings.contains(output, "})(user, \"Ada\")"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_2.active_p = kvist_value"), true)
}

@(test)
compile_threaded_shallow_struct_assoc_exprs :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct User {
  name: string
  age: int
  active?: bool
})

(defn score [user: User] -> int
  (let [updated (-> user
                  (assoc .active? false)
                  (assoc .name "Ada"))]
    (+ updated.age (len updated.name))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_update_1 := kvist_target"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_1.active_p = kvist_value"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_2.name = kvist_value"), true)
}

@(test)
compile_threaded_nested_struct_assoc_exprs :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct Profile {
  name: string
  age: int
})

(defstruct User {
  profile: Profile
  active?: bool
})

(defn score [user: User] -> int
  (let [updated (-> user
                  (assoc .profile.name "Ada")
                  (assoc .active? true))]
    (+ updated.profile.age (len updated.profile.name))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_update_1.profile.name = kvist_value"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_2.active_p = kvist_value"), true)
}

@(test)
compile_threaded_shallow_struct_assoc_from_proc_return :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct User {
  name: string
  age: int
})

(defn inc [x: int] -> int
  (+ x 1))

(defn make-user [] -> User
  (User {name: "Ada" age: 41}))

(defn score [] -> int
  (let [updated (-> (make-user)
                  (assoc .age 42))]
    updated.age))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_update_1.age = kvist_value"), true)
    testing.expect_value(t, strings.contains(output, "})(make_user(), 42)"), true)
}

@(test)
reject_threaded_update_is_removed :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct User {
  age: int
})

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [user: User] -> User
  (-> user
    (update .age inc)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "`update` has been removed; bind a copy and use `assoc`, or mutate a place with `update!`")
}

@(test)
reject_threaded_shallow_struct_assoc_unknown_field :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct User {
  age: int
})

(defn bad [user: User] -> User
  (-> user
    (assoc .missing 1)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "assoc could not find field .missing on User")
}

@(test)
reject_shallow_struct_update_non_field_selector :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point {
  x: int
})

(defn bad [point: Point] -> Point
  (assoc point 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "assoc expects a field place such as user.name or user.address.city")
}

@(test)
reject_update_is_removed :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point {
  x: int
})

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [point: Point] -> Point
  (update point.x inc))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "`update` has been removed; bind a copy and use `assoc`, or mutate a place with `update!`")
}

@(test)
reject_core_update_package_access_is_removed :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct Profile {
  age: int
})

(defstruct User {
  profile: Profile
})

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [user: User] -> User
  (core.update user.profile.age inc))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "`update` has been removed; bind a copy and use `assoc`, or mutate a place with `update!`")
}

@(test)
compile_update_bang_unary_inc :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct Point {
  y: int
})

(defn inc [x: int] -> int
  (+ x 1))

(defn score [] -> int
  (let [point (Point {y: 5})]
    (update! point.y inc)
    point.y))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "point.y += 1"), true)
}

@(test)
compile_nil_predicate :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct User {
  name: string
})

(defn has-user [p: ^User] -> bool
  (not (nil? p)))

(defn print-user [p: ^User]
  (when (nil? p)
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

User :: struct {
    name: string,
}

has_user :: proc(p: ^User) -> bool {
    return !((p) == (nil))
}

print_user :: proc(p: ^User) {
    if (p) == (nil) {
        return
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_lisp_predicate_and_bang_identifier_names :: proc(t: ^testing.T) {
    source := `(package main)

(defn greater-than? [threshold: int, x: int] -> bool
  (> x threshold))

(defn bump! [x: ^int]
  (set! (deref x) (+ (deref x) 1)))

(defn main []
  (let [x 1]
    (greater-than? 0 x)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

greater_than_p :: proc(threshold, x: int) -> bool {
    return (x) > (threshold)
}

bump_bang :: proc(x: ^int) {
    x^ = (x^) + (1)
}

main :: proc() {
    x := 1
    greater_than_p(0, x)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_odin_shaped_type_spellings :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Raw-Types {
  values: []int
  fixed: [3]int
  buffer: [dynamic]int
  lookup: map[string]int
  next: ^Raw-Types
})

(defn values [state: ^Raw-Types] -> []int
  state^.values)

(defn main []
  (let [values ([]int [1 2 3])
        lookup (map[string]int {"one" 1})
        buffer-literal ([dynamic]int [1 2])
        buffer (make [dynamic]int)]
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `#+feature dynamic-literals
package main

Raw_Types :: struct {
    values: []int,
    fixed: [3]int,
    buffer: [dynamic]int,
    lookup: map[string]int,
    next: ^Raw_Types,
}

values :: proc(state: ^Raw_Types) -> []int {
    return state^.values
}

main :: proc() {
    values := []int{1, 2, 3}
    lookup := map[string]int{"one" = 1}
    buffer_literal := [dynamic]int{1, 2}
    buffer := make([dynamic]int)
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_compact_type_spellings_inside_vectors :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn first [xs: []int, lookup: map[string]int] -> int
  (let [buffer: [dynamic]int (make [dynamic]int)
        fixed: [3]int ([3]int [1 2 3])
        from-map (get lookup "missing" -1)]
    (+ (get xs 0) from-map)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

first :: proc(xs: []int, lookup: map[string]int) -> int {
    buffer: [dynamic]int = make([dynamic]int)
    fixed: [3]int = [3]int{1, 2, 3}
    from_map := kvist_get_or_default(lookup, "missing", -1)
    return (xs[0]) + (from_map)
}

kvist_get_or_default :: proc(m: map[$K]$V, key: K, default: V) -> V {
    value, ok := m[key]
    if ok {
        return value
    }
    return default
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_map_literals_with_non_string_keys :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (let [by-code (map[int]string {1 "one" 2 "two"})
        by-flag (map[bool]int {true 1 false 0})]
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `#+feature dynamic-literals
package main

main :: proc() {
    by_code := map[int]string{1 = "one", 2 = "two"}
    by_flag := map[bool]int{true = 1, false = 0}
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_inline_collection_literals :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn score [] -> int
  (let [xs [1 2 3] defer
        lookup {"one" 1 "two" 2} defer
        tags #{"math" "lisp"} defer]
    (println tags)
    (+ (arr.count xs)
       (get lookup "one"))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `#+feature dynamic-literals
package main

import "core:fmt"

score :: proc() -> int {
    xs := [dynamic]int{1, 2, 3}
    defer delete(xs)
    lookup := map[string]int{"one" = 1, "two" = 2}
    defer delete(lookup)
    tags := map[string]struct{}{"math" = {}, "lisp" = {}}
    defer delete(tags)
    fmt.println(tags)
    return (len(xs)) + (lookup["one"])
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_typed_empty_inline_collection_literals :: proc(t: ^testing.T) {
    source := `(package main)

(defn score [] -> int
  (let [xs: [dynamic]int [] defer
        lookup: map[string]int {} defer
        tags: set[string] #{} defer]
    (println lookup tags)
    (arr.count xs)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `#+feature dynamic-literals
package main

import "core:fmt"

score :: proc() -> int {
    xs: [dynamic]int = [dynamic]int{}
    defer delete(xs)
    lookup: map[string]int = map[string]int{}
    defer delete(lookup)
    tags: map[string]struct{} = map[string]struct{}{}
    defer delete(tags)
    fmt.println(lookup, tags)
    return len(xs)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_inline_map_literal_rejects_mixed_values :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (let [profile {"name" "Ada" "age" 36}]
    (return)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "map literal values must be homogeneous"), true)
}

@(test)
compile_function_calls_support_positional_and_named_args :: proc(t: ^testing.T) {
    source := `(package main)

(defn foo [a: int, b: int, c: int] -> int
  (+ a b c))

(defn main [] -> int
  (let [first (foo 1 2 3)
        second (foo {a: 4 b: 5 c: 6})]
    (+ first second)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "first := foo(1, 2, 3)"), true)
    testing.expect_value(t, strings.contains(output, "second := foo(a = 4, b = 5, c = 6)"), true)
}

@(test)
reject_duplicate_named_call_arguments :: proc(t: ^testing.T) {
    source := `(package main)

(defn foo [a: int] -> int
  a)

(defn main [] -> int
  (foo {a: 1 a: 2}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "duplicate named argument a:"), true)
}

@(test)
compile_function_calls_fill_trailing_default_args_positionally :: proc(t: ^testing.T) {
    source := `(package main)

(defn greet [name: string, punctuation: string = "!"] -> string
  (+ name punctuation))

(defn main [] -> string
  (greet "Ada"))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "greet :: proc(name, punctuation: string) -> string"), true)
    testing.expect_value(t, strings.contains(output, "return greet(\"Ada\", \"!\")"), true)
}

@(test)
compile_named_function_calls_fill_missing_default_args :: proc(t: ^testing.T) {
    source := `(package main)

(defn greet [name: string, punctuation: string = "!"] -> string
  (+ name punctuation))

(defn main [] -> string
  (greet {name: "Ada"}))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return greet(name = \"Ada\", punctuation = \"!\")"), true)
}

@(test)
reject_missing_required_named_argument_without_default :: proc(t: ^testing.T) {
    source := `(package main)

(defn greet [name: string, punctuation: string = "!"] -> string
  (+ name punctuation))

(defn main [] -> string
  (greet {punctuation: "?"}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "missing required named arguments: name:"), true)
    testing.expect_value(t, strings.contains(err.message, "valid named args: name:, punctuation:"), true)
}

@(test)
reject_unknown_named_argument :: proc(t: ^testing.T) {
    source := `(package main)

(defn greet [name: string, punctuation: string = "!"] -> string
  (+ name punctuation))

(defn main [] -> string
  (greet {name: "Ada" tone: "warm"}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "unknown named argument tone:"), true)
    testing.expect_value(t, strings.contains(err.message, "valid named args: name:, punctuation:"), true)
}

@(test)
reject_unknown_named_argument_with_typo_suggestion :: proc(t: ^testing.T) {
    source := `(package main)

(defn greet [name: string, punctuation: string = "!"] -> string
  (+ name punctuation))

(defn main [] -> string
  (greet {name: "Ada" punctuaton: "?"}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "unknown named argument punctuaton:"), true)
    testing.expect_value(t, strings.contains(err.message, "did you mean punctuation:"), true)
}

@(test)
reject_required_parameter_after_default_parameter :: proc(t: ^testing.T) {
    source := `(package main)

(defn greet [name: string = "Ada", punctuation: string] -> string
  (+ name punctuation))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "parameters with defaults must trail required parameters"), true)
}

@(test)
compile_function_calls_support_mixed_positional_and_named_args :: proc(t: ^testing.T) {
    source := `(package main)

(defn place [name: string, x: int, y: int, label: string = "ok"] -> string
  label)

(defn main [] -> string
  (place "enemy" {x: 10 y: 20}))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return place(\"enemy\", x = 10, y = 20, label = \"ok\")"), true)
}

@(test)
compile_mixed_calls_fill_named_and_default_tail_args :: proc(t: ^testing.T) {
    source := `(package main)

(defn draw [target: int, x: int, y: int, color: int = 7, scale: int = 1] -> int
  color)

(defn main [] -> int
  (draw 99 {y: 20 x: 10 scale: 3}))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return draw(99, x = 10, y = 20, color = 7, scale = 3)"), true)
}

@(test)
compile_general_calls_support_trailing_named_args :: proc(t: ^testing.T) {
    source := `(package main)
(import strings "core:strings")

(defn clone-temp [s: string] -> string
  (let [[out err] (strings.clone s {allocator: context.temp_allocator})]
    out))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "strings.clone(s, allocator = context.temp_allocator)"), true)
}

@(test)
compile_general_dotted_calls_support_pure_named_args :: proc(t: ^testing.T) {
    source := `(package main)
(import fmt "core:fmt")

(defn demo []
  (fmt.println {value: 1 label: "ok"}))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "fmt.println(value = 1, label = \"ok\")"), true)
}

@(test)
reject_mixed_call_named_argument_overlapping_positional_argument :: proc(t: ^testing.T) {
    source := `(package main)

(defn place [name: string, x: int, y: int] -> int
  x)

(defn main [] -> int
  (place "enemy" {name: "boss" x: 10 y: 20}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "named argument name: overlaps positional argument 1"), true)
}

@(test)
reject_mixed_call_missing_required_named_tail_argument :: proc(t: ^testing.T) {
    source := `(package main)

(defn place [name: string, x: int, y: int, label: string = "ok"] -> string
  label)

(defn main [] -> string
  (place "enemy" {x: 10}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "missing required arguments after positional prefix: y:"), true)
    testing.expect_value(t, strings.contains(err.message, "valid named args: name:, x:, y:, label:"), true)
}

@(test)
compile_unparenthesized_fn_type_spelling :: proc(t: ^testing.T) {
    source := `(package main)

(def default-pred: fn [x: int] -> bool
  (fn [x: int] -> bool
    true))

(defstruct Runner {
  run: fn [x: int] -> bool
})

(defunion Callback {
  pred: fn [x: int] -> bool
})

(defn apply-pred [pred: fn [x: int] -> bool, x: int] -> bool
  (pred x))

(defn always [] -> fn [x: int] -> bool
  (fn [x: int] -> bool
    true))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

default_pred: proc(x: int) -> bool : proc(x: int) -> bool {
    return true
}

Runner :: struct {
    run: proc(x: int) -> bool,
}

Callback :: union {
    proc(x: int) -> bool,
}

apply_pred :: proc(pred: proc(x: int) -> bool, x: int) -> bool {
    return pred(x)
}

always :: proc() -> proc(x: int) -> bool {
    return proc(x: int) -> bool {
        return true
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_typed_let_with_fn_type_spelling :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (let [pred: fn [x: int] -> bool (fn [x: int] -> bool
                                        true)]
    (pred 1)
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

main :: proc() {
    pred: proc(x: int) -> bool = proc(x: int) -> bool {
        return true
    }
    pred(1)
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_proc_directives_and_declaration_attributes :: proc(t: ^testing.T) {
    source := `(package main)

(attr private)
(defn hidden [] -> int #force_inline
  1)

(defn query [] -> [value: int, ok: bool] #optional_ok
  (return 42 true))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

expected := `package main

@(private)
hidden :: #force_inline proc() -> int {
    return 1
}

query :: proc() -> (value: int, ok: bool) #optional_ok {
    return 42, true
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_proc_where_constraints :: proc(t: ^testing.T) {
    source := `(package main)
(import "base:intrinsics")

(defn same? [value: $T, expected: T] -> bool
  (where (intrinsics.type-is-comparable T))
  (= value expected))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "same_p :: proc(value: $T, expected: T) -> bool where intrinsics.type_is_comparable(T) {"), true)
}

@(test)
reject_attr_without_items :: proc(t: ^testing.T) {
    source := `(package main)

(attr)
(def answer 42)`

    _, err, ok := kvist.compile_source(source)
    defer delete(err.message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "attr expects at least one attribute item")
}

@(test)
compile_map_supports_single_captured_local_in_fn_literal :: proc(t: ^testing.T) {
    source := "(package main)\n\n(defn demo [xs: []int] -> [dynamic]int\n  (let [offset 10]\n    (arr.map (fn [x: int] -> int\n               (+ x offset))\n             xs)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "return kvist_map_1("), true)
    testing.expect_value(t, strings.contains(output, "proc(offset: int, x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "return (x) + (offset)"), true)
    testing.expect_value(t, strings.contains(output, "offset,"), true)
    testing.expect_value(t, strings.contains(output, "(xs)[:]"), true)
    testing.expect_value(t, strings.contains(output, "kvist_map_1 :: proc(f: proc(c1: $C1, x: $T) -> $U, c1: C1, xs: []T) -> [dynamic]U {"), true)
}

@(test)
compile_map_bang_supports_single_captured_local_in_fn_literal :: proc(t: ^testing.T) {
    source := "(package main)\n\n(defn demo [xs: [dynamic]int] -> [dynamic]int\n  (let [offset 10]\n    (arr.map! (fn [x: int] -> int\n                (+ x offset))\n              xs)\n    xs))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "kvist_map_in_place_1("), true)
    testing.expect_value(t, strings.contains(output, "proc(offset: int, x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "return (x) + (offset)"), true)
    testing.expect_value(t, strings.contains(output, "offset,"), true)
    testing.expect_value(t, strings.contains(output, "(xs)[:]"), true)
    testing.expect_value(t, strings.contains(output, "kvist_map_in_place_1 :: proc(f: proc(c1: $C1, x: $T) -> T, c1: C1, xs: []T) {"), true)
}

@(test)
compile_map_supports_multiple_captured_locals_in_fn_literal :: proc(t: ^testing.T) {
    source := "(package main)\n\n(defn demo [xs: []int] -> [dynamic]int\n  (let [offset 10\n        scale 2]\n    (arr.map (fn [x: int] -> int\n               (+ (* x scale) offset))\n             xs)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "return kvist_map_2("), true)
    testing.expect_value(t, strings.contains(output, "proc(scale: int, offset: int, x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "scale,"), true)
    testing.expect_value(t, strings.contains(output, "offset,"), true)
    testing.expect_value(t, strings.contains(output, "(xs)[:]"), true)
    testing.expect_value(t, strings.contains(output, "kvist_map_2 :: proc(f: proc(c1: $C1, c2: $C2, x: $T) -> $U, c1: C1, c2: C2, xs: []T) -> [dynamic]U {"), true)
}

@(test)
compile_filter_supports_single_captured_local_in_fn_literal :: proc(t: ^testing.T) {
    source := "(package main)\n\n(defn demo [xs: [dynamic]int] -> [dynamic]int\n  (let [limit 10]\n    (arr.filter (fn [x: int] -> bool\n                  (> x limit))\n                xs)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "kvist_filter_1("), true)
    testing.expect_value(t, strings.contains(output, "proc(limit: int, x: int) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "return (x) > (limit)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_filter_1 :: proc(f: proc(c1: $C1, x: $T) -> bool, c1: C1, xs: []T) -> [dynamic]T {"), true)
}

@(test)
compile_filter_supports_multiple_captured_locals_in_fn_literal :: proc(t: ^testing.T) {
    source := "(package main)\n\n(defn demo [xs: [dynamic]int] -> [dynamic]int\n  (let [lo 3\n        hi 10]\n    (arr.filter (fn [x: int] -> bool\n                  (and (> x lo) (< x hi)))\n                xs)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "kvist_filter_2("), true)
    testing.expect_value(t, strings.contains(output, "proc(lo: int, hi: int, x: int) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "lo,"), true)
    testing.expect_value(t, strings.contains(output, "hi,"), true)
    testing.expect_value(t, strings.contains(output, "(xs)[:]"), true)
    testing.expect_value(t, strings.contains(output, "kvist_filter_2 :: proc(f: proc(c1: $C1, c2: $C2, x: $T) -> bool, c1: C1, c2: C2, xs: []T) -> [dynamic]T {"), true)
}

@(test)
compile_user_proc_supports_captured_callback_literal :: proc(t: ^testing.T) {
    source := "(package main)\n\n(defn apply-one [f: (fn [x: int] -> int), x: int] -> int\n  (f x))\n\n(defn demo [] -> int\n  (let [offset 10]\n    (apply-one (fn [x: int] -> int (+ x offset)) 5)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "apply_one__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "proc(offset: int, x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "apply_one__kvist_capture_0_1 :: proc(f: proc(c1: $C1, x: int) -> int, kvist_capture_1: C1, x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "return f(kvist_capture_1, x)"), true)
}

@(test)
compile_user_proc_forwards_captured_callback_context :: proc(t: ^testing.T) {
    source := "(package main)\n\n(defn apply-one [f: (fn [x: int] -> int), x: int] -> int\n  (f x))\n\n(defn apply-twice [f: (fn [x: int] -> int), x: int] -> int\n  (+ (apply-one f x) (apply-one f x)))\n\n(defn demo [] -> int\n  (let [offset 10]\n    (apply-twice (fn [x: int] -> int (+ x offset)) 5)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "apply_twice__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "return (apply_one__kvist_capture_0_1(f, kvist_capture_1, x)) + (apply_one__kvist_capture_0_1(f, kvist_capture_1, x))"), true)
    testing.expect_value(t, strings.contains(output, "apply_one__kvist_capture_0_1 :: proc(f: proc(c1: $C1, x: int) -> int, kvist_capture_1: C1, x: int) -> int {"), true)
}

@(test)
compile_user_proc_rejects_escaping_captured_callback :: proc(t: ^testing.T) {
    source := "(package main)\n\n(defn escape [f: (fn [x: int] -> int), x: int] -> int\n  (let [g f]\n    (g x)))\n\n(defn demo [] -> int\n  (let [offset 10]\n    (escape (fn [x: int] -> int (+ x offset)) 5)))"

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "captured callback cannot be passed to escape because callback parameter f may escape"), true)
}

@(test)
compile_arr_package_indexed_and_reduce_helpers_support_captured_callbacks :: proc(t: ^testing.T) {
    source := "(package main)\n(import arr \"kvist:arr\")\n\n(defn demo [xs: []int] -> int\n  (let [offset 10\n        mapped (arr.map-indexed (fn [i: int, x: int] -> int (+ x i offset)) xs) defer\n        total (arr.reduce (fn [acc: int, x: int] -> int (+ acc x offset)) 0 xs)\n        indexed-total (arr.reduce-indexed (fn [acc: int, i: int, x: int] -> int (+ acc x i offset)) 0 xs)]\n    (+ (arr.last mapped) total indexed-total)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "arr__map_indexed__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "arr__reduce_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "arr__reduce_indexed_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "proc(c1: $C1, i: int, x: $T) -> $U"), true)
    testing.expect_value(t, strings.contains(output, "proc(c1: $C1, acc: $U, x: $T) -> U"), true)
    testing.expect_value(t, strings.contains(output, "proc(c1: $C1, acc: $U, i: int, x: $T) -> U"), true)
}

@(test)
compile_arr_package_scan_helpers_support_captured_callbacks :: proc(t: ^testing.T) {
    source := "(package main)\n(import arr \"kvist:arr\")\n\n(defn demo [xs: []int] -> bool\n  (let [limit 3\n        [found found?] (arr.find (fn [x: int] -> bool (> x limit)) xs)\n        [index indexed-value indexed?] (arr.find-indexed (fn [i: int, x: int] -> bool (and (> x limit) (>= i 0))) xs)\n        [smallest smallest?] (arr.min-by (fn [x: int] -> int (+ x limit)) xs)\n        [largest largest?] (arr.max-by (fn [x: int] -> int (+ x limit)) xs)]\n    (and (= (count (arr.take-while (fn [x: int] -> bool (< x limit)) xs)) 2)\n         (= (count (arr.drop-while (fn [x: int] -> bool (< x limit)) xs)) 2)\n         found? indexed? smallest? largest?\n         (= found 4)\n         (= indexed-value 4)\n         (= smallest 1)\n         (= largest 4)\n         (arr.some? (fn [x: int] -> bool (> x limit)) xs)\n         (not (arr.every? (fn [x: int] -> bool (> x limit)) xs)))))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "arr__take_while_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "arr__drop_while_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "arr__find_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "arr__find_indexed_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "arr__min_by_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "arr__max_by_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "arr__some_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "arr__every_impl__kvist_capture_0_1("), true)
}

@(test)
compile_filter_bang_supports_single_captured_local_in_fn_literal :: proc(t: ^testing.T) {
    source := "(package main)\n\n(defn demo [xs: [dynamic]int] -> [dynamic]int\n  (let [limit 10]\n    (arr.filter! (fn [x: int] -> bool\n                   (> x limit))\n                 xs)\n    xs))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "kvist_filter_in_place_1("), true)
    testing.expect_value(t, strings.contains(output, "proc(limit: int, x: int) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_filter_in_place_1 :: proc(f: proc(c1: $C1, x: $T) -> bool, c1: C1, xs: ^[dynamic]T) {"), true)
}

@(test)
compile_remove_supports_single_captured_local_in_fn_literal :: proc(t: ^testing.T) {
    source := "(package main)\n\n(defn demo [xs: [dynamic]int] -> [dynamic]int\n  (let [limit 10]\n    (arr.remove (fn [x: int] -> bool\n                  (> x limit))\n                xs)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "kvist_remove_1("), true)
    testing.expect_value(t, strings.contains(output, "proc(limit: int, x: int) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_remove_1 :: proc(f: proc(c1: $C1, x: $T) -> bool, c1: C1, xs: []T) -> [dynamic]T {"), true)
}

@(test)
compile_keep_supports_single_captured_local_in_fn_literal :: proc(t: ^testing.T) {
    source := "(package main)\n\n(defn demo [xs: [dynamic]int] -> [dynamic]int\n  (let [limit 10]\n    (arr.keep (fn [x: int] -> [value: int, ok: bool]\n                (if (> x limit)\n                  (return x true)\n                  (return 0 false)))\n              xs)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "kvist_keep_1("), true)
    testing.expect_value(t, strings.contains(output, "proc(limit: int, x: int) -> (value: int, ok: bool) {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_keep_1 :: proc(f: proc(c1: $C1, x: $T) -> ($U, bool), c1: C1, xs: []T) -> [dynamic]U {"), true)
}

@(test)
compile_directive_expression_wrappers :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn main []
  (let [x (#force_inline inc 41)
        y (#force_inline (inc x))]
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

inc :: proc(x: int) -> int {
    return (x) + (1)
}

main :: proc() {
    x := #force_inline inc(41)
    y := #force_inline inc(x)
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_caller_intrinsic_expressions :: proc(t: ^testing.T) {
    source := `(package main)
(import rt "base:runtime")

(defn location [loc: rt.Source_Code_Location = #caller_location] -> rt.Source_Code_Location
  loc)

(defn expression [x: bool, expr: string = (#caller_expression x)] -> string
  expr)

(defn demo [] -> string
  (discard (location))
  (expression true))

(defn named-demo [] -> string
  (expression {x: false}))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "loc: rt.Source_Code_Location = #caller_location"), true)
    testing.expect_value(t, strings.contains(output, "expr: string = #caller_expression(x)"), true)
    testing.expect_value(t, strings.contains(output, "_ = location()"), true)
    testing.expect_value(t, strings.contains(output, "return expression(true)"), true)
    testing.expect_value(t, strings.contains(output, "return expression(x = false)"), true)
}

@(test)
reject_proc_directive_before_non_proc_declaration :: proc(t: ^testing.T) {
    source := `(package main)

(odin "#force_inline")
(def answer 42)`

    _, err, ok := kvist.compile_source(source)
    defer delete(err.message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "procedure directive must be followed by a proc declaration")
}

@(test)
compile_parenthesized_nested_fn_type_spelling :: proc(t: ^testing.T) {
    source := `(package main)

(defn identity-factory [f: (fn [x: int] -> fn [y: int] -> bool)] -> (fn [x: int] -> fn [y: int] -> bool)
  f)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

identity_factory :: proc(f: proc(x: int) -> proc(y: int) -> bool) -> proc(x: int) -> proc(y: int) -> bool {
    return f
}
`
    testing.expect_value(t, output, expected)
}

@(test)
format_compile_errors_with_line_column_and_context :: proc(t: ^testing.T) {
    source := `(package main)
(unknown thing)`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    formatted := kvist.format_compile_error("bad.kvist", source, err)
    defer delete(formatted)

    expected := `bad.kvist:2:2: unsupported top-level form: unknown
  (unknown thing)
   ^
`
    testing.expect_value(t, formatted, expected)
}

@(test)
lower_rejects_missing_package :: proc(t: ^testing.T) {
    source := `(defn main []
  (return))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    formatted := kvist.format_compile_error("bad.kvist", source, err)
    defer delete(formatted)
    expected := `bad.kvist:1:1: missing package declaration
  (defn main []
  ^
`
    testing.expect_value(t, formatted, expected)
}

@(test)
compile_path_defaults_missing_package_to_main :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-test-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(defn main []
  (println "hello"))`
    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "package main"), true)
    testing.expect_value(t, strings.contains(output, "main :: proc()"), true)
}

@(test)
compile_path_supports_multi_file_source_package_directory :: proc(t: ^testing.T) {
    output, err, ok := kvist.compile_path("examples/language/cluck-port-packages.kvist")
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "math__sum_range"), true)
    testing.expect_value(t, strings.contains(output, "math__evens_under"), true)
    testing.expect_value(t, strings.contains(output, "math__default_limit"), true)
    testing.expect_value(t, strings.contains(output, "math__even_step_p"), true)
}

@(test)
compile_source_package_preserves_type_forms_in_proc_signatures :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-package-type-forms-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    pkg_dir, join_pkg_err := os.join_path({dir, "support", "groups"}, context.allocator)
    testing.expect_value(t, join_pkg_err == nil, true)
    if join_pkg_err != nil {
        return
    }
    defer delete(pkg_dir)
    mk_pkg_err := os.make_directory_all(pkg_dir)
    testing.expect_value(t, mk_pkg_err == nil, true)
    if mk_pkg_err != nil {
        return
    }

    pkg_file, pkg_join_err := os.join_path({pkg_dir, "groups.kvist"}, context.allocator)
    testing.expect_value(t, pkg_join_err == nil, true)
    if pkg_join_err != nil {
        return
    }
    defer delete(pkg_file)
    pkg_source := `(package groups)

(defn make-groups [] -> (map string (dynamic int))
  (let [out (make map[string][dynamic]int)
        group (make [dynamic]int 0 2)]
    (append (addr group) 1)
    (set! out["a"] group)
    out))`
    pkg_write_err := os.write_entire_file_from_string(pkg_file, pkg_source)
    testing.expect_value(t, pkg_write_err == nil, true)
    if pkg_write_err != nil {
        return
    }

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(import groups "support/groups")

(defn main [] -> int
  (let [groups (groups.make-groups)]
    (count groups)))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "groups__make_groups :: proc() -> map[string][dynamic]int"), true)
    testing.expect_value(t, strings.contains(output, "out := make(map[string][dynamic]int)"), true)
    testing.expect_value(t, strings.contains(output, "group := make([dynamic]int, 0, 2)"), true)
    testing.expect_value(t, strings.contains(output, "groups__dynamic"), false)
}

@(test)
compile_source_package_rewrites_typed_decl_names :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-package-typed-decls-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    pkg_dir, join_pkg_err := os.join_path({dir, "support"}, context.allocator)
    testing.expect_value(t, join_pkg_err == nil, true)
    if join_pkg_err != nil {
        return
    }
    defer delete(pkg_dir)
    mk_pkg_err := os.make_directory_all(pkg_dir)
    testing.expect_value(t, mk_pkg_err == nil, true)
    if mk_pkg_err != nil {
        return
    }

    pkg_file, pkg_join_err := os.join_path({pkg_dir, "support.kvist"}, context.allocator)
    testing.expect_value(t, pkg_join_err == nil, true)
    if pkg_join_err != nil {
        return
    }
    defer delete(pkg_file)
    pkg_source := `(package support)

(defvar state: int)

(defn set-state [value: int]
  (set! state value))

(defn get-state [] -> int
  state)`
    pkg_write_err := os.write_entire_file_from_string(pkg_file, pkg_source)
    testing.expect_value(t, pkg_write_err == nil, true)
    if pkg_write_err != nil {
        return
    }

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package main)
(import support "support")

(defn main [] -> int
  (support.set-state 42)
  (support.get-state))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "support__state: int"), true)
    testing.expect_value(t, strings.contains(output, "support__state = value"), true)
    testing.expect_value(t, strings.contains(output, "return support__state"), true)
}

@(test)
compile_path_supports_multi_file_root_package_directory :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-root-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package demo)

(defn main [] -> int
  (helper-value 5))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    helpers_path, helpers_join_err := os.join_path({dir, "helpers.kvist"}, context.allocator)
    testing.expect_value(t, helpers_join_err == nil, true)
    if helpers_join_err != nil {
        return
    }
    defer delete(helpers_path)
    helpers_source := `(package demo)
(import arr "kvist:arr")

(defn helper-value [n: int] -> int
  (let [xs (arr.dynamic int [n (+ n 1)])]
    (+ (arr.count xs) n)))`
    helpers_write_err := os.write_entire_file_from_string(helpers_path, helpers_source)
    testing.expect_value(t, helpers_write_err == nil, true)
    if helpers_write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "helper_value :: proc"), true)
    testing.expect_value(t, strings.contains(output, "main :: proc() -> int"), true)

    eval_result, eval_err, ok_eval := kvist.compile_eval_path(main_path, "(main)")
    testing.expect_value(t, ok_eval, true)
    if !ok_eval {
        testing.expect_value(t, eval_err.message, "")
        return
    }
    defer delete(eval_result)
    testing.expect_value(t, strings.contains(eval_result, "helper_value"), true)
}

@(test)
compile_path_root_package_ignores_unrelated_malformed_package_files :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-root-package-siblings-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package main)

(defn main [] -> int
  (+ 20 22))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    draft_path, draft_join_err := os.join_path({dir, "draft.kvist"}, context.allocator)
    testing.expect_value(t, draft_join_err == nil, true)
    if draft_join_err != nil {
        return
    }
    defer delete(draft_path)
    draft_source := `(package draft)

(defn broken []
  (let [x 1]
    x)`
    draft_write_err := os.write_entire_file_from_string(draft_path, draft_source)
    testing.expect_value(t, draft_write_err == nil, true)
    if draft_write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "main :: proc() -> int"), true)
}

@(test)
compile_path_rejects_private_source_package_member_access :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-private-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    pkg_dir, join_pkg_err := os.join_path({dir, "support", "secret"}, context.allocator)
    testing.expect_value(t, join_pkg_err == nil, true)
    if join_pkg_err != nil {
        return
    }
    defer delete(pkg_dir)
    mk_pkg_err := os.make_directory_all(pkg_dir)
    testing.expect_value(t, mk_pkg_err == nil, true)
    if mk_pkg_err != nil {
        return
    }

    pkg_file, pkg_join_err := os.join_path({pkg_dir, "secret.kvist"}, context.allocator)
    testing.expect_value(t, pkg_join_err == nil, true)
    if pkg_join_err != nil {
        return
    }
    defer delete(pkg_file)
    pkg_source := `(package secret)

(def- hidden-value 42)

(defn- hidden [] -> int
  42)

(defn visible [] -> int
  7)`
    pkg_write_err := os.write_entire_file_from_string(pkg_file, pkg_source)
    testing.expect_value(t, pkg_write_err == nil, true)
    if pkg_write_err != nil {
        return
    }

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(import secret "support/secret")

(defn main []
  (println secret.hidden-value))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    _, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "source package member is private or undefined: secret.hidden-value"), true)
}

@(test)
compile_path_rejects_cyclic_source_package_imports :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-cycle-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    support_dir, support_join_err := os.join_path({dir, "support"}, context.allocator)
    testing.expect_value(t, support_join_err == nil, true)
    if support_join_err != nil {
        return
    }
    defer delete(support_dir)

    alpha_dir, alpha_join_err := os.join_path({support_dir, "alpha"}, context.allocator)
    testing.expect_value(t, alpha_join_err == nil, true)
    if alpha_join_err != nil {
        return
    }
    defer delete(alpha_dir)
    beta_dir, beta_join_err := os.join_path({support_dir, "beta"}, context.allocator)
    testing.expect_value(t, beta_join_err == nil, true)
    if beta_join_err != nil {
        return
    }
    defer delete(beta_dir)

    alpha_mk_err := os.make_directory_all(alpha_dir)
    testing.expect_value(t, alpha_mk_err == nil, true)
    if alpha_mk_err != nil {
        return
    }
    beta_mk_err := os.make_directory_all(beta_dir)
    testing.expect_value(t, beta_mk_err == nil, true)
    if beta_mk_err != nil {
        return
    }

    alpha_file, alpha_file_err := os.join_path({alpha_dir, "alpha.kvist"}, context.allocator)
    testing.expect_value(t, alpha_file_err == nil, true)
    if alpha_file_err != nil {
        return
    }
    defer delete(alpha_file)
    alpha_source := `(package alpha)
(import beta "../beta")

(defn alpha-value [] -> int
  (beta/beta-value))`
    alpha_write_err := os.write_entire_file_from_string(alpha_file, alpha_source)
    testing.expect_value(t, alpha_write_err == nil, true)
    if alpha_write_err != nil {
        return
    }

    beta_file, beta_file_err := os.join_path({beta_dir, "beta.kvist"}, context.allocator)
    testing.expect_value(t, beta_file_err == nil, true)
    if beta_file_err != nil {
        return
    }
    defer delete(beta_file)
    beta_source := `(package beta)
(import alpha "../alpha")

(defn beta-value [] -> int
  (alpha/alpha-value))`
    beta_write_err := os.write_entire_file_from_string(beta_file, beta_source)
    testing.expect_value(t, beta_write_err == nil, true)
    if beta_write_err != nil {
        return
    }

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(import alpha "support/alpha")

(defn main []
  (alpha/alpha-value))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    _, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "cyclic source import:"), true)
    testing.expect_value(t, strings.contains(err.message, "support/alpha"), true)
    testing.expect_value(t, strings.contains(err.message, "support/beta"), true)
}

@(test)
compile_path_rejects_mismatched_package_names_in_directory :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-mismatch-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    pkg_dir, pkg_join_err := os.join_path({dir, "support", "mixed"}, context.allocator)
    testing.expect_value(t, pkg_join_err == nil, true)
    if pkg_join_err != nil {
        return
    }
    defer delete(pkg_dir)
    mk_pkg_err := os.make_directory_all(pkg_dir)
    testing.expect_value(t, mk_pkg_err == nil, true)
    if mk_pkg_err != nil {
        return
    }

    one_file, one_join_err := os.join_path({pkg_dir, "one.kvist"}, context.allocator)
    testing.expect_value(t, one_join_err == nil, true)
    if one_join_err != nil {
        return
    }
    defer delete(one_file)
    one_write_err := os.write_entire_file_from_string(one_file, `(package mixed)

(defn one [] -> int
  1)`)
    testing.expect_value(t, one_write_err == nil, true)
    if one_write_err != nil {
        return
    }

    two_file, two_join_err := os.join_path({pkg_dir, "two.kvist"}, context.allocator)
    testing.expect_value(t, two_join_err == nil, true)
    if two_join_err != nil {
        return
    }
    defer delete(two_file)
    two_write_err := os.write_entire_file_from_string(two_file, `(package other)

(defn two [] -> int
  2)`)
    testing.expect_value(t, two_write_err == nil, true)
    if two_write_err != nil {
        return
    }

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(import mixed "support/mixed")

(defn main []
  (mixed/one))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    _, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "source package files must declare the same package"), true)
}

@(test)
lower_rejects_duplicate_package :: proc(t: ^testing.T) {
    source := `(package main)
(package other)
(defn main []
  (return))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    formatted := kvist.format_compile_error("bad.kvist", source, err)
    defer delete(formatted)
    expected := `bad.kvist:2:1: package declaration must appear exactly once
  (package other)
  ^
`
    testing.expect_value(t, formatted, expected)
}

@(test)
lower_rejects_import_after_declarations :: proc(t: ^testing.T) {
    source := `(package main)
(def answer 42)
(import "core:fmt")`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    formatted := kvist.format_compile_error("bad.kvist", source, err)
    defer delete(formatted)
    expected := `bad.kvist:3:1: import declarations must appear before other declarations
  (import "core:fmt")
  ^
`
    testing.expect_value(t, formatted, expected)
}

@(test)
compile_plain_odin_import_paths :: proc(t: ^testing.T) {
    source := `(package main)
(import kvist_live "../../../src/kvist_live")
(import "core:fmt")

(defn main []
  (return))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import kvist_live "../../../src/kvist_live"

import "core:fmt"

main :: proc() {
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_path_imports_local_odin_package_without_marker :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-local-odin-import-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    support_dir, support_dir_err := os.join_path({dir, "support"}, context.allocator)
    testing.expect_value(t, support_dir_err == nil, true)
    if support_dir_err != nil {
        return
    }
    defer delete(support_dir)
    mk_err := os.make_directory_all(support_dir)
    testing.expect_value(t, mk_err == nil, true)
    if mk_err != nil {
        return
    }

    odin_path, odin_path_err := os.join_path({support_dir, "support.odin"}, context.allocator)
    testing.expect_value(t, odin_path_err == nil, true)
    if odin_path_err != nil {
        return
    }
    defer delete(odin_path)
    odin_source := `package support

raw_value :: proc() -> int {
    return 42
}
`
    odin_write_err := os.write_entire_file_from_string(odin_path, odin_source)
    testing.expect_value(t, odin_write_err == nil, true)
    if odin_write_err != nil {
        return
    }

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)
    source := `(package main)
(import support "support")

(defn main [] -> int
  (support.raw-value))`
    write_err := os.write_entire_file_from_string(main_path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `import support "support"`), true)
    testing.expect_value(t, strings.contains(output, "support.raw_value()"), true)
}

@(test)
compile_source_package_rebases_local_odin_import_without_marker :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-package-raw-import-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    raw_dir, raw_dir_err := os.join_path({dir, "support", "raw"}, context.allocator)
    testing.expect_value(t, raw_dir_err == nil, true)
    if raw_dir_err != nil {
        return
    }
    defer delete(raw_dir)
    wrap_dir, wrap_dir_err := os.join_path({dir, "support", "wrap"}, context.allocator)
    testing.expect_value(t, wrap_dir_err == nil, true)
    if wrap_dir_err != nil {
        return
    }
    defer delete(wrap_dir)
    mk_raw_err := os.make_directory_all(raw_dir)
    mk_wrap_err := os.make_directory_all(wrap_dir)
    testing.expect_value(t, mk_raw_err == nil, true)
    testing.expect_value(t, mk_wrap_err == nil, true)
    if mk_raw_err != nil || mk_wrap_err != nil {
        return
    }

    raw_path, raw_path_err := os.join_path({raw_dir, "raw.odin"}, context.allocator)
    testing.expect_value(t, raw_path_err == nil, true)
    if raw_path_err != nil {
        return
    }
    defer delete(raw_path)
    raw_source := `package raw

raw_value :: proc() -> int {
    return 11
}
`
    raw_write_err := os.write_entire_file_from_string(raw_path, raw_source)
    testing.expect_value(t, raw_write_err == nil, true)
    if raw_write_err != nil {
        return
    }

    wrap_path, wrap_path_err := os.join_path({wrap_dir, "wrap.kvist"}, context.allocator)
    testing.expect_value(t, wrap_path_err == nil, true)
    if wrap_path_err != nil {
        return
    }
    defer delete(wrap_path)
    wrap_source := `(package wrap)
(import raw "../raw")

(defn value [] -> int
  (raw.raw-value))`
    wrap_write_err := os.write_entire_file_from_string(wrap_path, wrap_source)
    testing.expect_value(t, wrap_write_err == nil, true)
    if wrap_write_err != nil {
        return
    }

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)
    source := `(package main)
(import wrap "support/wrap")

(defn main [] -> int
  (wrap.value))`
    write_err := os.write_entire_file_from_string(main_path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "import raw "), true)
    testing.expect_value(t, strings.contains(output, "/support/raw\""), true)
    testing.expect_value(t, strings.contains(output, "raw.raw_value()"), true)
    testing.expect_value(t, strings.contains(output, "wrap__value()"), true)
}

@(test)
compile_source_package_keeps_foreign_import_declaration :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-package-foreign-import-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    support_dir, support_dir_err := os.join_path({dir, "support"}, context.allocator)
    testing.expect_value(t, support_dir_err == nil, true)
    if support_dir_err != nil {
        return
    }
    defer delete(support_dir)
    mk_err := os.make_directory_all(support_dir)
    testing.expect_value(t, mk_err == nil, true)
    if mk_err != nil {
        return
    }

    support_path, support_path_err := os.join_path({support_dir, "support.kvist"}, context.allocator)
    testing.expect_value(t, support_path_err == nil, true)
    if support_path_err != nil {
        return
    }
    defer delete(support_path)
    support_source := `(package support)
(foreign-import libc "system:c")

(defn value [] -> int
  7)`
    support_write_err := os.write_entire_file_from_string(support_path, support_source)
    testing.expect_value(t, support_write_err == nil, true)
    if support_write_err != nil {
        return
    }

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)
    source := `(package main)
(import support "support")

(defn main [] -> int
  (support.value))`
    write_err := os.write_entire_file_from_string(main_path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `foreign import libc "system:c"`), true)
    testing.expect_value(t, strings.contains(output, "support__value :: proc() -> int"), true)
    testing.expect_value(t, strings.contains(output, "return support__value()"), true)
}

@(test)
compile_source_package_imports_mixed_kvist_and_odin_directory :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-mixed-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    support_dir, support_dir_err := os.join_path({dir, "support"}, context.allocator)
    testing.expect_value(t, support_dir_err == nil, true)
    if support_dir_err != nil {
        return
    }
    defer delete(support_dir)
    mk_err := os.make_directory_all(support_dir)
    testing.expect_value(t, mk_err == nil, true)
    if mk_err != nil {
        return
    }

    kvist_path, kvist_path_err := os.join_path({support_dir, "support.kvist"}, context.allocator)
    testing.expect_value(t, kvist_path_err == nil, true)
    if kvist_path_err != nil {
        return
    }
    defer delete(kvist_path)
    kvist_source := `(package support)

(defn kvist-value [] -> int
  7)`
    kvist_write_err := os.write_entire_file_from_string(kvist_path, kvist_source)
    testing.expect_value(t, kvist_write_err == nil, true)
    if kvist_write_err != nil {
        return
    }

    odin_path, odin_path_err := os.join_path({support_dir, "raw.odin"}, context.allocator)
    testing.expect_value(t, odin_path_err == nil, true)
    if odin_path_err != nil {
        return
    }
    defer delete(odin_path)
    odin_source := `package support

raw_value :: proc() -> int {
    return 35
}
`
    odin_write_err := os.write_entire_file_from_string(odin_path, odin_source)
    testing.expect_value(t, odin_write_err == nil, true)
    if odin_write_err != nil {
        return
    }

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)
    source := `(package main)
(import support "support")

(defn main [] -> int
  (+ (support.kvist-value)
     (support.raw-value)))`
    write_err := os.write_entire_file_from_string(main_path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "import support "), true)
    testing.expect_value(t, strings.contains(output, "/support\""), true)
    testing.expect_value(t, strings.contains(output, "support__kvist_value()"), true)
    testing.expect_value(t, strings.contains(output, "support.raw_value()"), true)
}

@(test)
compile_exported_c_abi_proc_and_var :: proc(t: ^testing.T) {
    source := `(package main)

(export)
(defvar hot_api_version: u32 1)

(export)
(defn hot_tick :abi "c" [state: rawptr] -> int
  42)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

@(export)
hot_api_version: u32 = 1

@(export)
hot_tick :: proc "c" (state: rawptr) -> int {
    return 42
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_defstate_program :: proc(t: ^testing.T) {
    source := `(package main)

(defstate App_State
  {steps: int}
  {run: run
   init: init
   on-load: on-load
   on-unload: on-unload
   version: "v1"})

(defn run [state: ^App_State host: ^reload__Run_Host]
  (mut! state^.steps += 1))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "App_State :: struct"), true)
    testing.expect_value(t, strings.contains(output, "run :: proc"), true)
    testing.expect_value(t, strings.contains(output, ":run"), false)
}

@(test)
compile_defstate_program_with_run_metadata :: proc(t: ^testing.T) {
    source := `(package main)

(defstate App_State
  {requests: int}
  {run: run
   version: "v1"})

(defn run [state: ^App_State host: ^reload__Run_Host]
  (mut! state^.requests += 1))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "App_State :: struct"), true)
    testing.expect_value(t, strings.contains(output, "run :: proc"), true)
    testing.expect_value(t, strings.contains(output, ":run"), false)
}

@(test)
compile_source_with_shipped_reload_package_exposes_run_host_alias :: proc(t: ^testing.T) {
    tmp_dir, tmp_dir_err := os.make_directory_temp("", "kvist-reload-package-*", context.allocator)
    testing.expect_value(t, tmp_dir_err == nil, true)
    if tmp_dir_err != nil {
        return
    }
    defer os.remove_all(tmp_dir)
    defer delete(tmp_dir)

    path, join_err := os.join_path({tmp_dir, "kvist-reload-package-test.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package main)
(import reload "kvist:reload")

(defstate App_State
  {requests: int}
  {run: run})

(defn run [state: ^App_State host: ^reload.Run_Host]
  (when (reload.checkpoint! host)
    (return)))`
    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "import runtime "), true)
    testing.expect_value(t, strings.contains(output, "reload__Run_Host :: runtime.Run_Host"), true)
    testing.expect_value(t, strings.contains(output, "reload__reload__Run_Host"), false)
    testing.expect_value(t, strings.contains(output, "run :: proc(state: ^App_State, host: ^reload__Run_Host)"), true)
}

@(test)
compile_reload_adapter_defstate_can_reference_imported_state :: proc(t: ^testing.T) {
    tmp_dir, tmp_dir_err := os.make_directory_temp("", "kvist-reload-adapter-*", context.allocator)
    testing.expect_value(t, tmp_dir_err == nil, true)
    if tmp_dir_err != nil {
        return
    }
    defer os.remove_all(tmp_dir)
    defer delete(tmp_dir)

    app_dir, app_dir_err := os.join_path({tmp_dir, "app"}, context.allocator)
    testing.expect_value(t, app_dir_err == nil, true)
    if app_dir_err != nil {
        return
    }
    defer delete(app_dir)
    make_app_err := os.make_directory_all(app_dir)
    testing.expect_value(t, make_app_err == nil, true)
    if make_app_err != nil {
        return
    }

    app_path, app_path_err := os.join_path({app_dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, app_path_err == nil, true)
    if app_path_err != nil {
        return
    }
    defer delete(app_path)
    app_source := `(package adapter_app)

(defstruct App_State
  {ticks: int})

(defn init [state: ^App_State]
  (set! state^.ticks 0))

(defn tick [state: ^App_State]
  (mut! state^.ticks += 1))`
    app_write_err := os.write_entire_file_from_string(app_path, app_source)
    testing.expect_value(t, app_write_err == nil, true)
    if app_write_err != nil {
        return
    }

    reload_path, reload_path_err := os.join_path({tmp_dir, "reload.kvist"}, context.allocator)
    testing.expect_value(t, reload_path_err == nil, true)
    if reload_path_err != nil {
        return
    }
    defer delete(reload_path)
    reload_source := `(package adapter_reload)
(import app "app")
(import reload "kvist:reload")

(defstate app.App_State
  {run: run
   init: app.init})

(defn run [state: ^app.App_State host: ^reload.Run_Host]
  (app.tick state)
  (when (reload.checkpoint! host)
    (return)))`
    reload_write_err := os.write_entire_file_from_string(reload_path, reload_source)
    testing.expect_value(t, reload_write_err == nil, true)
    if reload_write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(reload_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "app__App_State :: struct"), true)
    testing.expect_value(t, strings.contains(output, "run :: proc(state: ^app__App_State, host: ^reload__Run_Host)"), true)
    testing.expect_value(t, strings.contains(output, "defstate"), false)
}

@(test)
compile_output_rebases_absolute_odin_imports_for_output_path :: proc(t: ^testing.T) {
    tmp_dir, tmp_dir_err := os.make_directory_temp("", "kvist-reload-package-rebase-*", context.allocator)
    testing.expect_value(t, tmp_dir_err == nil, true)
    if tmp_dir_err != nil {
        return
    }
    defer os.remove_all(tmp_dir)
    defer delete(tmp_dir)

    output_dir, output_dir_err := os.join_path({tmp_dir, "generated"}, context.allocator)
    testing.expect_value(t, output_dir_err == nil, true)
    if output_dir_err != nil {
        return
    }
    defer delete(output_dir)

    output_path, output_path_err := os.join_path({output_dir, "main.odin"}, context.allocator)
    testing.expect_value(t, output_path_err == nil, true)
    if output_path_err != nil {
        return
    }
    defer delete(output_path)

    path, join_err := os.join_path({tmp_dir, "kvist-reload-package-rebase-test.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package main)
(import reload "kvist:reload")

(defstate App_State
  {requests: int}
  {run: run})

(defn run [state: ^App_State host: ^reload.Run_Host]
  (when (reload.checkpoint! host)
    (return)))`
    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    rebased, rebase_err, rebase_ok := kvist.rebase_emitted_odin_imports_for_output_path(output, output_path)
    testing.expect_value(t, rebase_ok, true)
    if !rebase_ok {
        testing.expect_value(t, rebase_err.message, "")
        return
    }
    defer delete(rebased)

    testing.expect_value(t, strings.contains(rebased, "import runtime "), true)
    testing.expect_value(t, strings.contains(rebased, "import runtime \"/"), false)
}

@(test)
compile_output_rebased_for_tmp_path_uses_canonical_relative_import :: proc(t: ^testing.T) {
    tmp_dir, tmp_dir_err := os.make_directory_temp("", "kvist-reload-package-tmp-*", context.allocator)
    testing.expect_value(t, tmp_dir_err == nil, true)
    if tmp_dir_err != nil {
        return
    }
    defer os.remove_all(tmp_dir)
    defer delete(tmp_dir)

    path, join_err := os.join_path({tmp_dir, "kvist-reload-package-tmp-check.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    output_path, output_path_err := os.join_path({tmp_dir, "kvist-reload-package-tmp-check.odin"}, context.allocator)
    testing.expect_value(t, output_path_err == nil, true)
    if output_path_err != nil {
        return
    }
    defer delete(output_path)

    source := `(package main)
(import reload "kvist:reload")

(defstate App_State
  {requests: int}
  {run: run})

(defn run [state: ^App_State host: ^reload.Run_Host]
  (when (reload.checkpoint! host)
    (return)))`
    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    rebased, rebase_err, rebase_ok := kvist.rebase_emitted_odin_imports_for_output_path(output, output_path)
    testing.expect_value(t, rebase_ok, true)
    if !rebase_ok {
        testing.expect_value(t, rebase_err.message, "")
        return
    }
    defer delete(rebased)

    repo_root_value, repo_ok := kvist.repo_root_for_path(".")
    testing.expect_value(t, repo_ok, true)
    if !repo_ok {
        return
    }
    repo_root := repo_root_value
    defer delete(repo_root)

    runtime_path, runtime_path_err := os.join_path({repo_root, "src", "olive_reload"}, context.allocator)
    testing.expect_value(t, runtime_path_err == nil, true)
    if runtime_path_err != nil {
        return
    }
    defer delete(runtime_path)

    canonical_tmp_dir, canonical_tmp_dir_err := os.get_absolute_path(tmp_dir, context.allocator)
    testing.expect_value(t, canonical_tmp_dir_err == nil, true)
    if canonical_tmp_dir_err != nil {
        return
    }
    defer delete(canonical_tmp_dir)

    canonical_runtime_path, canonical_runtime_path_err := os.get_absolute_path(runtime_path, context.allocator)
    testing.expect_value(t, canonical_runtime_path_err == nil, true)
    if canonical_runtime_path_err != nil {
        return
    }
    defer delete(canonical_runtime_path)

    expected_import_path, expected_import_path_err := os.get_relative_path(canonical_tmp_dir, canonical_runtime_path, context.allocator)
    testing.expect_value(t, expected_import_path_err == nil, true)
    if expected_import_path_err != nil {
        return
    }
    defer delete(expected_import_path)

    expected_import_line := fmt.tprintf("import runtime %q", expected_import_path)
    testing.expect_value(t, strings.contains(rebased, expected_import_line), true)
}

@(test)
compile_source_package_exports_raw_odin_names :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-package-exports-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    support_dir, support_dir_err := os.join_path({dir, "support"}, context.allocator)
    testing.expect_value(t, support_dir_err == nil, true)
    if support_dir_err != nil {
        return
    }
    defer delete(support_dir)

    make_support_err := os.make_directory_all(support_dir)
    testing.expect_value(t, make_support_err == nil, true)
    if make_support_err != nil {
        return
    }

    support_path, support_path_err := os.join_path({support_dir, "support.kvist"}, context.allocator)
    testing.expect_value(t, support_path_err == nil, true)
    if support_path_err != nil {
        return
    }
    defer delete(support_path)

    support_source := `(package support)
(import fmt "core:fmt")
(exports [Raw_Handle])
(odin "Raw_Handle :: distinct rawptr")

(defn describe [handle: Raw_Handle]
  (fmt.printf "%v\n" handle))`
    support_write_err := os.write_entire_file_from_string(support_path, support_source)
    testing.expect_value(t, support_write_err == nil, true)
    if support_write_err != nil {
        return
    }

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)

    source := `(package main)
(import support "support")

(defn use-handle [handle: support.Raw_Handle]
  (support.describe handle))`
    write_err := os.write_entire_file_from_string(main_path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "Raw_Handle :: distinct rawptr"), true)
    testing.expect_value(t, strings.contains(output, "use_handle :: proc(handle: ^support__Raw_Handle)"), false)
    testing.expect_value(t, strings.contains(output, "use_handle :: proc(handle: support__Raw_Handle)"), true)
}

@(test)
compile_source_with_shipped_hot_macro_package :: proc(t: ^testing.T) {
    tmp_dir, tmp_dir_err := os.make_directory_temp("", "kvist-hot-macro-*", context.allocator)
    testing.expect_value(t, tmp_dir_err == nil, true)
    if tmp_dir_err != nil {
        return
    }
    defer os.remove_all(tmp_dir)
    defer delete(tmp_dir)
    path, join_err := os.join_path({tmp_dir, "kvist-hot-macro-test.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package main)
(import hot "kvist:hot")
(import kvist_hot "../../../src/kvist_hot")
(import shared "../shared")

(def version: string "module v1")

(hot.defmodule shared.State
                demo-message
                demo-tick
                version
                "module v1 loaded")`

    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `import kvist_hot "../../../src/kvist_hot"`), true)
    testing.expect_value(t, strings.contains(output, `kvist_hot_api_version: u32 = 1`), true)
    testing.expect_value(t, strings.contains(output, `demo_message :: proc "c" () -> cstring`), true)
    testing.expect_value(t, strings.contains(output, `demo_tick :: proc "c" (state: rawptr)`), true)
    testing.expect_value(t, strings.contains(output, `kvist_hot.On_Load(shared.State, state, is_reload, "module v1 loaded")`), true)
}

@(test)
compile_canonical_foreign_import_and_transmute_forms :: proc(t: ^testing.T) {
    source := `(package main)

// Foreign handle alias.
(def Foreign-Handle (distinct rawptr))
(foreign-import sqlite "system:sqlite3")

(defn bytes [text: string] -> []byte
  (transmute []byte text))

(defn next-handler [handle: Foreign-Handle] -> ^Foreign-Handle
  (type-assert handle ^Foreign-Handle))

(defn empty-flags [] -> bit_set[int; u8]
  (zero bit_set[int; u8]))

(defn allocate-handle [] -> ^Foreign-Handle
  (alloc Foreign-Handle context.temp_allocator))

(defn main [handle: Foreign-Handle]
  (set! context.user_ptr nil)
  (return))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

// Foreign handle alias.
Foreign_Handle :: distinct rawptr

foreign import sqlite "system:sqlite3"

bytes :: proc(text: string) -> []byte {
    return transmute([]byte)text
}

next_handler :: proc(handle: Foreign_Handle) -> ^Foreign_Handle {
    return (handle).(^Foreign_Handle)
}

empty_flags :: proc() -> bit_set[int; u8] {
    return bit_set[int; u8]{}
}

allocate_handle :: proc() -> ^Foreign_Handle {
    return new(Foreign_Handle, context.temp_allocator)
}

main :: proc(handle: Foreign_Handle) {
    context.user_ptr = nil
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
reject_foreign_import_in_expression_position :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad []
  (foreign-import sqlite "system:sqlite3"))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        delete(output)
        return
    }
    testing.expect_value(t, strings.contains(err.message, "foreign-import is a top-level declaration form"), true)
    delete(err.message)
}

@(test)
compile_multiline_statement_odin_escape :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (odin "x := 1\n_ = x")
  (return))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

main :: proc() {
    x := 1
    _ = x
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_discard_statement :: proc(t: ^testing.T) {
    source := `(package main)

(defn observe [x: int, y: int]
  (discard x y)
  (return))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

observe :: proc(x, y: int) {
    _ = x
    _ = y
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_warns_for_discarded_owned_result_inside_discard :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn demo []
  (discard (arr.range 3)))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from arr.range is discarded; bind it, delete it, or return it")
    }
}

@(test)
compile_warns_for_leaked_owned_let_local :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn demo []
  (let [xs (arr.empty int)]
    (println 1)))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned local xs is never deleted or returned; add (defer (delete xs)) or return it")
    }
}

@(test)
compile_does_not_warn_for_typed_non_owned_aggregate_let_local :: proc(t: ^testing.T) {
    source := `(package main)
(import rl "vendor:raylib")

(defn demo []
  (let [player-pos: rl.Vector2 [0 0]
        player-vel: rl.Vector2 [0 0]
        player-grounded? false
        player-flip? false]
    (discard player-pos player-vel player-grounded? player-flip?)))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_warns_for_typed_dynamic_array_let_local :: proc(t: ^testing.T) {
    source := `(package main)

(defn demo []
  (let [xs: [dynamic]int []]
    (println 1)))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned local xs is never deleted or returned; add (defer (delete xs)) or return it")
    }
}

@(test)
compile_does_not_warn_for_owned_local_deleted_in_all_if_branches :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn demo [flag: bool]
  (let [xs (arr.empty int)]
    (if flag
      (delete xs)
      (delete xs))
    (println 1)))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_warns_for_owned_local_leaking_in_if_branch :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn demo [flag: bool]
  (let [xs (arr.empty int)]
    (if flag
      (delete xs)
      (println 1))
    (println 2)))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned local xs is never deleted or returned; add (defer (delete xs)) or return it")
    }
}

@(test)
compile_warns_for_overwritten_owned_local :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn demo []
  (let [xs (arr.empty int)]
    (set! xs (arr.empty int))
    (defer (delete xs))
    (println 1)))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned local xs is overwritten before cleanup; delete it or return it before set!")
    }
}

@(test)
compile_warns_for_discarded_owned_result :: proc(t: ^testing.T) {
    source := `(package main)

(defn demo []
  (arr.range 3)
  (println 1))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from arr.range is discarded; bind it, delete it, or return it")
    }
}

@(test)
compile_string_package_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import str "kvist:str")

(defn demo []
  (let [name "  Kvist Core  "
        parts (str.split "a,b,c" ",")
        joined (str.join parts "-")
        trimmed (str.trim name)
        without-prefix (str.trim-prefix "kvist.core" "kvist.")
        without-suffix (str.trim-suffix "kvist.txt" ".txt")
        starts? (str.starts-with? without-prefix "co")
        ends? (str.ends-with? without-suffix "st")
        first-dash (str.index-of joined "-")
        last-dash (str.last-index-of joined "-")
        replaced-all (str.replace joined "-" "_")
        replaced-one (str.replace joined "-" "_" 1)
        lowered (str.lower replaced-all)
        uppered (str.upper lowered)]
    (defer (delete parts))
    (defer (delete joined))
    (defer (delete replaced-all))
    (defer (delete replaced-one))
    (defer (delete lowered))
    (defer (delete uppered))
    (println trimmed without-prefix without-suffix starts? ends? first-dash last-dash uppered)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "import strings \"core:strings\""), true)
    testing.expect_value(t, strings.contains(output, "str__split :: #force_inline proc(s, separator: string) -> []string {"), true)
    testing.expect_value(t, strings.contains(output, "return strings.split(s, separator)"), true)
    testing.expect_value(t, strings.contains(output, "str__join_impl :: #force_inline proc(parts: []string, separator: string) -> string {"), true)
    testing.expect_value(t, strings.contains(output, "out, _ := strings.join(parts, separator)"), true)
    testing.expect_value(t, strings.contains(output, "parts := str__split(\"a,b,c\", \",\")"), true)
    testing.expect_value(t, strings.contains(output, "joined := str__join_impl((parts)[0:], \"-\")"), true)
    testing.expect_value(t, strings.contains(output, "str__trim :: #force_inline proc(s: string) -> string {"), true)
    testing.expect_value(t, strings.contains(output, "return strings.trim_space(s)"), true)
    testing.expect_value(t, strings.contains(output, "str__starts_with_p :: #force_inline proc(s, prefix: string) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "return strings.has_prefix(s, prefix)"), true)
    testing.expect_value(t, strings.contains(output, "trimmed := str__trim(name)"), true)
    testing.expect_value(t, strings.contains(output, "without_prefix := str__trim_prefix(\"kvist.core\", \"kvist.\")"), true)
    testing.expect_value(t, strings.contains(output, "without_suffix := str__trim_suffix(\"kvist.txt\", \".txt\")"), true)
    testing.expect_value(t, strings.contains(output, "starts_p := str__starts_with_p(without_prefix, \"co\")"), true)
    testing.expect_value(t, strings.contains(output, "ends_p := str__ends_with_p(without_suffix, \"st\")"), true)
    testing.expect_value(t, strings.contains(output, "first_dash := str__index_of(joined, \"-\")"), true)
    testing.expect_value(t, strings.contains(output, "last_dash := str__last_index_of(joined, \"-\")"), true)
    testing.expect_value(t, strings.contains(output, "str__replace_impl :: #force_inline proc(s, old, new: string, n: int) -> string {"), true)
    testing.expect_value(t, strings.contains(output, "out, _ := strings.replace(s, old, new, n)"), true)
    testing.expect_value(t, strings.contains(output, "replaced_all := str__replace_impl(joined, \"-\", \"_\", -1)"), true)
    testing.expect_value(t, strings.contains(output, "replaced_one := str__replace_impl(joined, \"-\", \"_\", 1)"), true)
    testing.expect_value(t, strings.contains(output, "str__lower :: #force_inline proc(s: string) -> string {"), true)
    testing.expect_value(t, strings.contains(output, "return strings.to_lower(s)"), true)
    testing.expect_value(t, strings.contains(output, "lowered := str__lower(replaced_all)"), true)
    testing.expect_value(t, strings.contains(output, "uppered := str__upper(lowered)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_str_replace :: proc(s, old, new: string, n: int) -> string"), false)
}

@(test)
compile_shipped_str_source_package_uses_hybrid_resolution :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-str-hybrid-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package main)
(import str "kvist:str")

(defn demo []
  (let [name "  Kvist  "
        trimmed (str.trim name)
        initial (str.get trimmed 0)
        tail (str.slice trimmed 1)
        starts? (str.starts-with? trimmed "K")
        lowered (str.lower trimmed)
        uppered (str.upper lowered)
        parts (str.split "a,b" ",")
        joined (str.join parts "-")
        replaced (str.replace joined "-" ":" 1)]
    (defer (delete parts))
    (defer (delete joined))
    (defer (delete replaced))
    (println (str.count trimmed) initial (str.count tail) starts? uppered joined replaced)))`

    write_err := os.write_entire_file(path, transmute([]byte)source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "str__count :: #force_inline proc(s: string) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "return len(s)"), true)
    testing.expect_value(t, strings.contains(output, "initial := trimmed[0]"), true)
    testing.expect_value(t, strings.contains(output, "tail := (trimmed)[1:]"), true)
    testing.expect_value(t, strings.contains(output, "str__trim :: #force_inline proc(s: string) -> string {"), true)
    testing.expect_value(t, strings.contains(output, "return strings.trim_space(s)"), true)
    testing.expect_value(t, strings.contains(output, "str__starts_with_p :: #force_inline proc(s, prefix: string) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "return strings.has_prefix(s, prefix)"), true)
    testing.expect_value(t, strings.contains(output, "str__lower :: #force_inline proc(s: string) -> string {"), true)
    testing.expect_value(t, strings.contains(output, "return strings.to_lower(s)"), true)
    testing.expect_value(t, strings.contains(output, "str__upper :: #force_inline proc(s: string) -> string {"), true)
    testing.expect_value(t, strings.contains(output, "return strings.to_upper(s)"), true)
    testing.expect_value(t, strings.contains(output, "trimmed := str__trim(name)"), true)
    testing.expect_value(t, strings.contains(output, "starts_p := str__starts_with_p(trimmed, \"K\")"), true)
    testing.expect_value(t, strings.contains(output, "lowered := str__lower(trimmed)"), true)
    testing.expect_value(t, strings.contains(output, "uppered := str__upper(lowered)"), true)
    testing.expect_value(t, strings.contains(output, "parts := str__split(\"a,b\", \",\")"), true)
    testing.expect_value(t, strings.contains(output, "joined := str__join_impl((parts)[0:], \"-\")"), true)
    testing.expect_value(t, strings.contains(output, "replaced := str__replace_impl(joined, \"-\", \":\", 1)"), true)
    testing.expect_value(t, strings.contains(output, "fmt.println(str__count(trimmed), initial, str__count(tail), starts_p, uppered, joined, replaced)"), true)
}

@(test)
compile_shipped_str_source_package_rejects_private_members_without_fallback :: proc(t: ^testing.T) {
    source := `(package main)
(import str "kvist:str")

(defn demo [] -> string
  (str.join-impl [] ","))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "source package member is private or undefined: str.join-impl")
}

@(test)
compile_shipped_set_source_package_uses_hybrid_resolution :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-set-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package main)
(import set "kvist:set")

(defn demo []
  (let [base (set.of int [1 2 3])
        extra (set.of int [3 4 5])
        merged (set.union base extra)
        overlap (set.intersection base extra)
        only-base (set.difference base extra)
        bigger (set.add base 9)
        smaller (set.remove bigger 2)
        subset? (set.subset? overlap merged)
        superset? (set.superset? merged overlap)
        disjoint? (set.disjoint? only-base extra)
        mutable (set.of int [1 2 3])]
    (defer (delete base))
    (defer (delete extra))
    (defer (delete merged))
    (defer (delete overlap))
    (defer (delete only-base))
    (defer (delete bigger))
    (defer (delete smaller))
    (defer (delete mutable))
    (set.add! mutable 4)
    (set.remove! mutable 1)
    (set.union! mutable extra)
    (println subset? superset? disjoint? (set.contains? mutable 4))))`

    write_err := os.write_entire_file(path, transmute([]byte)source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "set__union :: #force_inline proc(lhs, rhs: map[$T]struct{}) -> map[T]struct{} {"), true)
    testing.expect_value(t, strings.contains(output, "set__intersection :: #force_inline proc(lhs, rhs: map[$T]struct{}) -> map[T]struct{} {"), true)
    testing.expect_value(t, strings.contains(output, "set__difference :: #force_inline proc(lhs, rhs: map[$T]struct{}) -> map[T]struct{} {"), true)
    testing.expect_value(t, strings.contains(output, "set__subset_p :: #force_inline proc(lhs, rhs: map[$T]struct{}) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "set__superset_p :: #force_inline proc(lhs, rhs: map[$T]struct{}) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "set__disjoint_p :: #force_inline proc(lhs, rhs: map[$T]struct{}) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "set__add :: #force_inline proc(s: map[$T]struct{}, value: T) -> map[T]struct{} {"), true)
    testing.expect_value(t, strings.contains(output, "set__remove :: #force_inline proc(s: map[$T]struct{}, value: T) -> map[T]struct{} {"), true)
    testing.expect_value(t, strings.contains(output, "out := make(map[T]struct{}, (len(lhs)) + (len(rhs)))"), true)
    testing.expect_value(t, strings.contains(output, "lhs_count := len(lhs)"), true)
    testing.expect_value(t, strings.contains(output, "rhs_count := len(rhs)"), true)
    testing.expect_value(t, strings.contains(output, "cap := lhs_count"), true)
    testing.expect_value(t, strings.contains(output, "if (cap) > (rhs_count) {"), true)
    testing.expect_value(t, strings.contains(output, "out := make(map[T]struct{}, cap)"), true)
    testing.expect_value(t, strings.contains(output, "if (len(lhs)) > (len(rhs)) {"), true)
    testing.expect_value(t, strings.contains(output, "out := make(map[T]struct{}, (len(s)) + (1))"), true)
    testing.expect_value(t, strings.contains(output, "merged := set__union(base, extra)"), true)
    testing.expect_value(t, strings.contains(output, "overlap := set__intersection(base, extra)"), true)
    testing.expect_value(t, strings.contains(output, "only_base := set__difference(base, extra)"), true)
    testing.expect_value(t, strings.contains(output, "bigger := set__add(base, 9)"), true)
    testing.expect_value(t, strings.contains(output, "smaller := set__remove(bigger, 2)"), true)
    testing.expect_value(t, strings.contains(output, "subset_p := set__subset_p(overlap, merged)"), true)
    testing.expect_value(t, strings.contains(output, "superset_p := set__superset_p(merged, overlap)"), true)
    testing.expect_value(t, strings.contains(output, "disjoint_p := set__disjoint_p(only_base, extra)"), true)
    testing.expect_value(t, strings.contains(output, "mutable[4] = struct{}{}"), true)
    testing.expect_value(t, strings.contains(output, "delete_key(&(mutable), 1)"), true)
    testing.expect_value(t, strings.contains(output, "for value, _ in extra {"), true)
    testing.expect_value(t, strings.contains(output, "mutable[value] = struct{}{}"), true)
    testing.expect_value(t, strings.contains(output, "kvist_set_union_in_place"), false)
    testing.expect_value(t, strings.contains(output, "fmt.println(subset_p, superset_p, disjoint_p, (map_get(&(mutable), 4, false)))"), false)
}

@(test)
compile_shipped_map_source_package_uses_hybrid_resolution :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-map-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package main)
(import core "kvist:core")
(import map "kvist:map")

(defn demo []
  (let [base (map.of string int {"a" 1 "b" 2})
        overrides (map.of string int {"b" 20 "c" 30})
        merged (map.merge base overrides)
        assoced (map.assoc merged "z" 99)
        trimmed (map.dissoc assoced "b")
        fresh (map.empty string int 4)
        mutable (map.of string int {"seed" 1})
        key-list (map.keys base)
        value-list (map.vals overrides)
        zipped (map.zip ["x" "y" "z"] [10 20])
        has-a? (map.contains? merged "a")
        read-a (map.get merged "a")]
    (defer (delete base))
    (defer (delete overrides))
    (defer (delete merged))
    (defer (delete assoced))
    (defer (delete trimmed))
    (defer (delete fresh))
    (defer (delete mutable))
    (defer (delete key-list))
    (defer (delete value-list))
    (defer (delete zipped))
    (map.assoc! mutable "extra" 7)
    (map.dissoc! mutable "seed")
    (map.merge! mutable overrides)
    (println has-a? read-a (count key-list) (count value-list) (map.get zipped "x" 0))))`

    write_err := os.write_entire_file(path, transmute([]byte)source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "map__contains_p :: #force_inline proc(m: map[$K]$V, key: K) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "map__merge :: #force_inline proc(lhs, rhs: map[$K]$V) -> map[K]V {"), true)
    testing.expect_value(t, strings.contains(output, "out := make(map[K]V, (len(lhs)) + (len(rhs)))"), true)
    testing.expect_value(t, strings.contains(output, "map__keys :: #force_inline proc(m: map[$K]$V) -> [dynamic]K {"), true)
    testing.expect_value(t, strings.contains(output, "out := make([dynamic]K, 0, len(m))"), true)
    testing.expect_value(t, strings.contains(output, "map__vals :: #force_inline proc(m: map[$K]$V) -> [dynamic]V {"), true)
    testing.expect_value(t, strings.contains(output, "out := make([dynamic]V, 0, len(m))"), true)
    testing.expect_value(t, strings.contains(output, "map__zip :: #force_inline proc(ks: []$K, vs: []$V) -> map[K]V {"), true)
    testing.expect_value(t, strings.contains(output, "map__assoc :: #force_inline proc(m: map[$K]$V, key: K, value: V) -> map[K]V {"), true)
    testing.expect_value(t, strings.contains(output, "map__dissoc :: #force_inline proc(m: map[$K]$V, key: K) -> map[K]V {"), true)
    testing.expect_value(t, strings.contains(output, "value_count := len((vs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "cap := len((ks)[:])"), true)
    testing.expect_value(t, strings.contains(output, "if (cap) > (value_count) {"), true)
    testing.expect_value(t, strings.contains(output, "out := make(map[K]V, cap)"), true)
    testing.expect_value(t, strings.contains(output, "if (i) < (value_count) {"), true)
    testing.expect_value(t, strings.contains(output, "merged := map__merge(base, overrides)"), true)
    testing.expect_value(t, strings.contains(output, "assoced := map__assoc(merged, \"z\", 99)"), true)
    testing.expect_value(t, strings.contains(output, "trimmed := map__dissoc(assoced, \"b\")"), true)
    testing.expect_value(t, strings.contains(output, "fresh := make(map[string]int, 4)"), true)
    testing.expect_value(t, strings.contains(output, "mutable := map[string]int{\"seed\" = 1}"), true)
    testing.expect_value(t, strings.contains(output, "key_list := map__keys(base)"), true)
    testing.expect_value(t, strings.contains(output, "value_list := map__vals(overrides)"), true)
    testing.expect_value(t, strings.contains(output, "zipped := map__zip([dynamic]string{\"x\", \"y\", \"z\"}, [dynamic]int{10, 20})"), true)
    testing.expect_value(t, strings.contains(output, "has_a_p := map__contains_p(merged, \"a\")"), true)
    testing.expect_value(t, strings.contains(output, "read_a := merged[\"a\"]"), true)
    testing.expect_value(t, strings.contains(output, "mutable[\"extra\"] = 7"), true)
    testing.expect_value(t, strings.contains(output, "delete_key(&(mutable), \"seed\")"), true)
    testing.expect_value(t, strings.contains(output, "for key, value in overrides {"), true)
    testing.expect_value(t, strings.contains(output, "mutable[key] = value"), true)
    testing.expect_value(t, strings.contains(output, "kvist_merge_in_place(&(mutable), overrides)"), false)
    testing.expect_value(t, strings.contains(output, "fmt.println(has_a_p, read_a, len((key_list)[:]), len((value_list)[:]), kvist_get_or_default(zipped, \"x\", 0))"), true)
}

@(test)
compile_shipped_arr_source_package_uses_hybrid_resolution :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-arr-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package main)
(import core "kvist:core")
(import arr "kvist:arr")

(defn big? [x: int] -> bool
  (> x 15))

(defn next-value [] -> int
  7)

(defn double [x: int] -> int
  (* x 2))

(defn inc-value [x: int] -> int
  (+ x 1))

(defn add-index [i: int, x: int] -> int
  (+ i x))

(defn even-value? [x: int] -> bool
  (= (% x 2) 0))

(defn keep-even [x: int] -> [value: int, ok: bool]
  (if (even-value? x)
    (return x true)
    (return 0 false)))

(defn pair [x: int] -> []int
  ([]int [x x]))

(defn add-values [acc: int, x: int] -> int
  (+ acc x))

(defn pick-first [n: int] -> int
  0)

(defn demo []
  (let [numbers (arr.range 1 5)
        seed (arr.dynamic int [10 20 30 40])
        fixed (arr.fixed int [4 5 6])
        xs (slice seed 0)
        mutable ([dynamic]int [1 2 3])
        total (arr.count xs)
        first-by-get (arr.get xs 0)
        a (arr.first xs)
        b (arr.second xs)
        c (arr.nth xs 2)
        z (arr.last xs)
        window (arr.slice xs 1 3)
        prefix (arr.take 2 xs)
        suffix (arr.drop 1 xs)
        without-tail (arr.drop-last 2 xs)
        sampled (arr.take-nth 2 xs)
        repeated (arr.repeat 3 9)
        generated (arr.repeatedly 2 next-value)
        powers (arr.iterate 4 double 1)
        cycled (arr.cycle 5 xs)
        mapped (arr.map inc-value xs)
        indexed (arr.map-indexed add-index xs)
        filtered (arr.filter even-value? xs)
        removed (arr.remove even-value? xs)
        kept (arr.keep keep-even xs)
        flattened (arr.mapcat pair xs)
        counted (arr.count-by even-value? xs)
        shuffled (arr.shuffle pick-first xs)
        sorted (arr.sort xs)
        threaded-flat-count (->> xs
                         (arr.mapcat pair)
                         (count))
        reduced (arr.reduce add-values 0 xs)
        small-prefix (arr.take-while big? xs)
        large-suffix (arr.drop-while big? xs)
        [first-big found-big?] (arr.find big? xs)
        any-big? (arr.some? big? xs)
        all-big? (arr.every? big? xs)
        tail (arr.rest xs)
        init (arr.butlast xs)]
    (defer (delete mutable))
    (defer (delete indexed))
    (defer (delete kept))
    (defer (delete flattened))
    (defer (delete counted))
    (defer (delete shuffled))
    (defer (delete sorted))
    (arr.push! mutable total)
    (arr.map! inc-value mutable)
    (arr.map-indexed! add-index mutable)
    (arr.reverse! mutable)
    (arr.filter! even-value? mutable)
    (arr.remove! even-value? mutable)
    (arr.keep! keep-even mutable)
    (arr.shuffle! pick-first mutable)
    (arr.sort! mutable)
    (println (count fixed) total first-by-get a b c z
             first-big found-big? any-big? all-big?
             (count numbers) (count sampled) (count repeated) (count generated) (count powers) (count cycled)
             (count window) (count prefix) (count suffix) (count without-tail) (count tail) (count init)
             (count indexed) (count flattened) (count counted) (count shuffled) (count sorted) threaded-flat-count)))`

    write_err := os.write_entire_file(path, transmute([]byte)source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "seed := [dynamic]int{10, 20, 30, 40}"), true)
    testing.expect_value(t, strings.contains(output, "fixed := [3]int{4, 5, 6}"), true)
    testing.expect_value(t, strings.contains(output, "xs := (seed)[0:]"), true)
    testing.expect_value(t, strings.contains(output, "total := len((xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__range_impl :: #force_inline proc(start, end, step: int) -> [dynamic]int {"), true)
    testing.expect_value(t, strings.contains(output, "numbers := arr__range_impl(1, 5, 1)"), true)
    testing.expect_value(t, strings.contains(output, "first_by_get := xs[0]"), true)
    testing.expect_value(t, strings.contains(output, "a := xs[0]"), true)
    testing.expect_value(t, strings.contains(output, "b := xs[1]"), true)
    testing.expect_value(t, strings.contains(output, "c := xs[2]"), true)
    testing.expect_value(t, strings.contains(output, "z := xs[(len((xs)[:])) - (1)]"), true)
    testing.expect_value(t, strings.contains(output, "window := (xs)[1:3]"), true)
    testing.expect_value(t, strings.contains(output, "arr__take :: #force_inline proc(n: int, xs: []$T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "arr__drop :: #force_inline proc(n: int, xs: []$T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "arr__drop_last :: #force_inline proc(n: int, xs: []$T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "prefix := arr__take(2, xs)"), true)
    testing.expect_value(t, strings.contains(output, "suffix := arr__drop(1, xs)"), true)
    testing.expect_value(t, strings.contains(output, "without_tail := arr__drop_last(2, xs)"), true)
    testing.expect_value(t, strings.contains(output, "arr__take_nth :: #force_inline proc(n: int, xs: []$T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "sampled := arr__take_nth(2, xs)"), true)
    testing.expect_value(t, strings.contains(output, "arr__repeat :: #force_inline proc(n: int, value: $T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "repeated := arr__repeat(3, 9)"), true)
    testing.expect_value(t, strings.contains(output, "arr__repeatedly :: #force_inline proc(n: int, f: proc() -> $T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "generated := arr__repeatedly(2, next_value)"), true)
    testing.expect_value(t, strings.contains(output, "arr__iterate :: #force_inline proc(n: int, f: proc(x: $T) -> T, init: T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "powers := arr__iterate(4, double, 1)"), true)
    testing.expect_value(t, strings.contains(output, "arr__cycle :: #force_inline proc(n: int, xs: []$T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "cycled := arr__cycle(5, xs)"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_impl :: #force_inline proc(f: proc(x: $T) -> $U, xs: []T) -> [dynamic]U {"), true)
    testing.expect_value(t, strings.contains(output, "mapped := arr__map_impl(inc_value, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_indexed :: #force_inline proc(f: proc(i: int, x: $T) -> $U, xs: []T) -> [dynamic]U {"), true)
    testing.expect_value(t, strings.contains(output, "indexed := arr__map_indexed(add_index, xs)"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_indexed_bang_impl :: #force_inline proc(f: proc(i: int, x: $T) -> T, xs: []T) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_indexed_bang_impl(add_index, (mutable)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__reverse_bang_impl :: #force_inline proc(xs: []$T) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__reverse_bang_impl((mutable)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__filter_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "filtered := arr__filter_impl(even_value_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__remove_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "removed := arr__remove_impl(even_value_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__keep_impl :: #force_inline proc(f: proc(x: $T) -> (value: $U, ok: bool), xs: []T) -> [dynamic]U {"), true)
    testing.expect_value(t, strings.contains(output, "kept := arr__keep_impl(keep_even, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__mapcat_impl :: #force_inline proc(f: proc(x: $T) -> []$U, xs: []T) -> [dynamic]U {"), true)
    testing.expect_value(t, strings.contains(output, "flattened := arr__mapcat_impl(pair, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__count_by_impl :: #force_inline proc(f: proc(x: $T) -> $K, xs: []T) -> map[K]int {"), true)
    testing.expect_value(t, strings.contains(output, "counted := arr__count_by_impl(even_value_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__shuffle_impl :: #force_inline proc(pick: proc(n: int) -> int, xs: []$T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "shuffled := arr__shuffle_impl(pick_first, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__sort_impl :: #force_inline proc(xs: []$T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_slice.sort((out)[:])"), true)
    testing.expect_value(t, strings.contains(output, "sorted := arr__sort_impl((xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_1 := arr__mapcat_impl(pair, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "threaded_flat_count := len((kvist_thread_1)[:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__reduce_impl :: #force_inline proc(f: proc(acc: $U, x: $T) -> U, init: U, xs: []T) -> U {"), true)
    testing.expect_value(t, strings.contains(output, "reduced := arr__reduce_impl(add_values, 0, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__take_while_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> []T {"), true)
    testing.expect_value(t, strings.contains(output, "arr__drop_while_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> []T {"), true)
    testing.expect_value(t, strings.contains(output, "small_prefix := arr__take_while_impl(big_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "large_suffix := arr__drop_while_impl(big_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__find_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> (value: T, ok: bool) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__some_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "arr__every_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "first_big, found_big_p := arr__find_impl(big_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "any_big_p := arr__some_impl(big_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "all_big_p := arr__every_impl(big_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "append(&(mutable), total)"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_bang_impl :: #force_inline proc(f: proc(x: $T) -> T, xs: []T) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_bang_impl(inc_value, (mutable)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__filter_bang_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: ^[dynamic]T) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__filter_bang_impl(even_value_p, &mutable)"), true)
    testing.expect_value(t, strings.contains(output, "arr__remove_bang_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: ^[dynamic]T) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__remove_bang_impl(even_value_p, &mutable)"), true)
    testing.expect_value(t, strings.contains(output, "arr__keep_bang_impl :: #force_inline proc(f: proc(x: $T) -> (value: T, ok: bool), xs: ^[dynamic]T) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__keep_bang_impl(keep_even, &mutable)"), true)
    testing.expect_value(t, strings.contains(output, "arr__shuffle_bang_impl(pick_first, (mutable)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__sort_bang_impl((mutable)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "tail := (xs)[1:]"), true)
    testing.expect_value(t, strings.contains(output, "init := arr__butlast(xs)"), true)
    testing.expect_value(t, strings.contains(output, "out := make([dynamic]T, 0, ((len((xs)[:])) + ((n) - (1))) / (n))"), true)
    testing.expect_value(t, strings.contains(output, "out := make([dynamic]T, 0, n)"), true)
    testing.expect_value(t, strings.contains(output, "out := make([dynamic]int, 0, arr__count)"), true)
    testing.expect_value(t, strings.contains(output, "return (xs)[0:i]"), true)
    testing.expect_value(t, strings.contains(output, "return (xs)[i:]"), true)
    testing.expect_value(t, strings.contains(output, "fmt.println(len((fixed)[:]), total, first_by_get, a, b, c, z, first_big, found_big_p, any_big_p, all_big_p"), true)
    testing.expect_value(t, strings.contains(output, "kvist_range"), false)
    testing.expect_value(t, strings.contains(output, "kvist_map("), false)
    testing.expect_value(t, strings.contains(output, "kvist_map_indexed"), false)
    testing.expect_value(t, strings.contains(output, "kvist_filter("), false)
    testing.expect_value(t, strings.contains(output, "kvist_remove("), false)
    testing.expect_value(t, strings.contains(output, "kvist_keep("), false)
    testing.expect_value(t, strings.contains(output, "kvist_map_in_place("), false)
    testing.expect_value(t, strings.contains(output, "kvist_filter_in_place("), false)
    testing.expect_value(t, strings.contains(output, "kvist_remove_in_place("), false)
    testing.expect_value(t, strings.contains(output, "kvist_keep_in_place("), false)
    testing.expect_value(t, strings.contains(output, "kvist_count_by("), false)
    testing.expect_value(t, strings.contains(output, "kvist_shuffle("), false)
    testing.expect_value(t, strings.contains(output, "kvist_sort("), false)
    testing.expect_value(t, strings.contains(output, "kvist_mapcat"), false)
    testing.expect_value(t, strings.contains(output, "kvist_reduce("), false)
    testing.expect_value(t, strings.contains(output, "kvist_take_nth"), false)
    testing.expect_value(t, strings.contains(output, "kvist_repeat"), false)
    testing.expect_value(t, strings.contains(output, "kvist_repeatedly"), false)
    testing.expect_value(t, strings.contains(output, "kvist_iterate"), false)
    testing.expect_value(t, strings.contains(output, "kvist_cycle"), false)
    testing.expect_value(t, strings.contains(output, "kvist_take_while"), false)
    testing.expect_value(t, strings.contains(output, "kvist_drop_while"), false)
    testing.expect_value(t, strings.contains(output, "kvist_find"), false)
    testing.expect_value(t, strings.contains(output, "kvist_some_p"), false)
    testing.expect_value(t, strings.contains(output, "kvist_every_p"), false)
}

@(test)
compile_set_package_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import set "kvist:set")

(defn demo []
  (let [base (set.of int [1 2 3])
        extra (set.of int [3 4])
        merged (set.union base extra)
        overlap (set.intersection base extra)
        only-base (set.difference base extra)
        bigger (set.add base 9)
        smaller (set.remove bigger 2)
        subset? (set.subset? overlap merged)
        superset? (set.superset? merged overlap)
        disjoint? (set.disjoint? only-base extra)
        mutable (set.of int [1 2 3])]
    (defer (delete base))
    (defer (delete extra))
    (defer (delete merged))
    (defer (delete overlap))
    (defer (delete only-base))
    (defer (delete bigger))
    (defer (delete smaller))
    (defer (delete mutable))
    (set.add! mutable 4)
    (set.remove! mutable 1)
    (println subset? superset? disjoint?)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "set__union :: #force_inline proc(lhs, rhs: map[$T]struct{}) -> map[T]struct{} {"), true)
    testing.expect_value(t, strings.contains(output, "set__intersection :: #force_inline proc(lhs, rhs: map[$T]struct{}) -> map[T]struct{} {"), true)
    testing.expect_value(t, strings.contains(output, "set__difference :: #force_inline proc(lhs, rhs: map[$T]struct{}) -> map[T]struct{} {"), true)
    testing.expect_value(t, strings.contains(output, "set__subset_p :: #force_inline proc(lhs, rhs: map[$T]struct{}) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "set__superset_p :: #force_inline proc(lhs, rhs: map[$T]struct{}) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "set__disjoint_p :: #force_inline proc(lhs, rhs: map[$T]struct{}) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "set__add :: #force_inline proc(s: map[$T]struct{}, value: T) -> map[T]struct{} {"), true)
    testing.expect_value(t, strings.contains(output, "set__remove :: #force_inline proc(s: map[$T]struct{}, value: T) -> map[T]struct{} {"), true)
    testing.expect_value(t, strings.contains(output, "out := make(map[T]struct{}, (len(lhs)) + (len(rhs)))"), true)
    testing.expect_value(t, strings.contains(output, "out := make(map[T]struct{}, cap)"), true)
    testing.expect_value(t, strings.contains(output, "merged := set__union(base, extra)"), true)
    testing.expect_value(t, strings.contains(output, "overlap := set__intersection(base, extra)"), true)
    testing.expect_value(t, strings.contains(output, "only_base := set__difference(base, extra)"), true)
    testing.expect_value(t, strings.contains(output, "bigger := set__add(base, 9)"), true)
    testing.expect_value(t, strings.contains(output, "smaller := set__remove(bigger, 2)"), true)
    testing.expect_value(t, strings.contains(output, "subset_p := set__subset_p(overlap, merged)"), true)
    testing.expect_value(t, strings.contains(output, "superset_p := set__superset_p(merged, overlap)"), true)
    testing.expect_value(t, strings.contains(output, "disjoint_p := set__disjoint_p(only_base, extra)"), true)
    testing.expect_value(t, strings.contains(output, "mutable[4] = struct{}{}"), true)
    testing.expect_value(t, strings.contains(output, "delete_key(&(mutable), 1)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_set_union :: proc(lhs, rhs: map[$T]struct{}) -> map[T]struct{}"), false)
    testing.expect_value(t, strings.contains(output, "kvist_set_add :: proc(s: map[$T]struct{}, value: T) -> map[T]struct{}"), false)
}

@(test)
compile_set_package_bang_algebra_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import set "kvist:set")

(defn demo []
  (let [target (set.of int [1 2 3]) defer
        rhs (set.of int [3 4 5]) defer]
    (set.union! target rhs)
    (set.intersection! target rhs)
    (set.difference! target rhs)
    (println (set.contains? target 4))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "for value, _ in rhs {"), true)
    testing.expect_value(t, strings.contains(output, "target[value] = struct{}{}"), true)
    testing.expect_value(t, strings.contains(output, "for value, _ in target {"), true)
    testing.expect_value(t, strings.contains(output, "delete_key(&(target), value)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_set_union_in_place"), false)
    testing.expect_value(t, strings.contains(output, "kvist_set_intersection_in_place"), false)
    testing.expect_value(t, strings.contains(output, "kvist_set_difference_in_place"), false)
}
