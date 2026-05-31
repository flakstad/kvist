package tests

import "base:runtime"
import "core:os"
import "core:strings"
import "core:testing"
import kvist "../src/kvist"

@(test)
compile_hello_program :: proc(t: ^testing.T) {
    source := `(package main)
(import "core:fmt")

// Greets from Kvist.
(defstruct Greeting {
  :message string
})

(defn main []
  (let [g (Greeting {
            :message "hello from kvist"
          })]
    (fmt.println (:message g))))`

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
reject_legacy_top_level_proc_decl_head :: proc(t: ^testing.T) {
    source := `(package main)

(proc main []
  (println "hello"))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "unsupported top-level form: proc")
}

@(test)
compile_defstruct_program :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Profile
  "Profile data."
  {:name string
   :age int
   :active? bool
   :tags set[string]
   :scores [dynamic]int
   :home Point})

(defstruct Point
  {:x float
   :y float})`

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
    tags: map[string]bool,
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
        "examples/cluck-port-arrays.kvist",
        "examples/cluck-port-docs.kvist",
        "examples/cluck-port-maps-sets.kvist",
        "examples/cluck-port-multi-return.kvist",
        "examples/cluck-port-packages.kvist",
        "examples/cluck-port-records.kvist",
        "examples/cluck-port-loops.kvist",
        "examples/cluck-port-strings.kvist",
        "examples/cluck-port-struct-defaults.kvist",
        "examples/cluck-port-struct-introspection.kvist",
        "examples/cluck-port-struct-types.kvist",
        "examples/closures.kvist",
        "examples/control-flow.kvist",
        "examples/core-concurrency.kvist",
        "examples/core-container-queue.kvist",
        "examples/core-encoding-formats.kvist",
        "examples/core-math-linalg.kvist",
        "examples/core-os-paths.kvist",
        "examples/core-paths.kvist",
        "examples/core-text-encoding.kvist",
        "examples/core-time-slice.kvist",
        "examples/data-literals.kvist",
        "examples/declarations.kvist",
        "examples/dev-io.kvist",
        "examples/defstructs.kvist",
        "examples/error-handling.kvist",
        "examples/hello.kvist",
        "examples/higher-order.kvist",
        "examples/hiccup-demo.kvist",
        "examples/hiccup-interpolation.kvist",
        "examples/hiccup-render.kvist",
        "examples/hiccup-values.kvist",
        "examples/inline-literals.kvist",
        "examples/interop-directives.kvist",
        "examples/pointers-and-raw.kvist",
        "examples/proc-values.kvist",
        "examples/sequence-helpers.kvist",
        "examples/sequences.kvist",
        "examples/tap.kvist",
        "examples/testing.kvist",
        "examples/unions.kvist",
        "examples/update.kvist",
        "examples/vendor-raylib.kvist",
        "examples/vendor-stb-easy-font.kvist",
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
    output, err, ok := kvist.compile_eval_path("examples/cluck-port-packages.kvist", "(math/sum-range 0 5)")
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

add :: proc(a: int, b: int) -> int {
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
  :name string
  :active bool
})

(defenum Status [
  Active
  Archived
])

(defunion Value {
  :i int
  :s string
})

(defconst max-age int 120)

// Returns true for active users.
// Used by sequence examples.
(defn active? [user: User] -> bool
  (:active user))`

    output, err, ok := kvist.symbols_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\n"), true)
    testing.expect_value(t, strings.contains(output, "import\tstrings\t2\t9\tcore:strings\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "struct\tUser\t8\t9\t\t(User {:name string :active bool})\tA user record.\\nOwned by caller.\n"), true)
    testing.expect_value(t, strings.contains(output, "field\tUser.name\t9\t3\tUser\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "enum\tStatus\t13\t7\t\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "variant\tStatus.Active\t14\t3\tStatus\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "union\tValue\t18\t8\t\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "variant\tValue.i\t19\t3\tValue\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "const\tmax-age\t23\t8\t\t\t\n"), true)
    testing.expect_value(t, strings.contains(output, "proc\tactive?\t27\t7\t\t(active? [user: User] -> bool)\tReturns true for active users.\\nUsed by sequence examples.\n"), true)
}

@(test)
symbols_source_indexes_defstruct_docstring :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Person
  "Primary profile."
  {:name string
   :age int})`

    output, err, ok := kvist.symbols_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "struct\tPerson\t3\t12\t\t(Person {:name string :age int})\tPrimary profile.\n"), true)
    testing.expect_value(t, strings.contains(output, "field\tPerson.name\t5\t4\tPerson\t\t\n"), true)
}

@(test)
symbols_source_indexes_defunion_and_defenum :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Status [
  Active
  Archived
])

(defunion Value {
  :i int
  :s string
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
builtin_symbols_source_emits_signatures_and_docs :: proc(t: ^testing.T) {
    output := kvist.builtin_symbols_source()
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\n"), true)
    testing.expect_value(t, strings.contains(output, "kvist core\tprintln\t1\t1\t\t(println value...)\tPrint one or more values. Kvist lowers this to fmt output and auto-imports core:fmt when needed.\n"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tor-else\t1\t1\t\t(or-else expr fallback)\tEvaluate an Odin optional-ok expression and return its value when ok is true, otherwise return the fallback value.\n"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tupdate!\t1\t1\t\t(update! target key-or-field value-or-updater ...)\tMutate a struct field, array/slice slot, or map key in place. Supports replacement and updater forms such as inc or +.\n"), true)
    testing.expect_value(t, strings.contains(output, "kvist macro\twhen-let\t1\t1\t\t(when-let [value bool expr] body...)\tBind a value and explicit boolean result from a multi-return expression. Run the body only when the boolean is true. Expands to a destructuring let plus when.\n"), true)
}

@(test)
package_symbols_source_supports_shipped_test_package :: proc(t: ^testing.T) {
    output, ok := kvist.package_symbols_source("kvist:test", "t")
    testing.expect_value(t, ok, true)
    if !ok {
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "macro\tt/deftest\t"), true)
    testing.expect_value(t, strings.contains(output, "macro\tt/is\t"), true)
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

(defstruct Greeting {:message string})

(defn main []
  (println (:message (Greeting {:message "hi"}))))`

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
    testing.expect_value(t, strings.contains(output, "kvist package\tarr/push!\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist core\tprintln\t"), true)
    testing.expect_value(t, strings.contains(output, "odin\tfmt.println\t"), true)
}

@(test)
editor_symbols_source_includes_language_forms_and_helpers :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (let [x 1]
    (if true
      (map inc [1 2 3])
      (println x))))`

    output, err, ok := kvist.editor_symbols_source("/Users/andreas/Projects/kvist/.tmp-editor-symbols-test.kvist", source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist form\tlet\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist form\tif\t"), true)
    testing.expect_value(t, strings.contains(output, "kvist helper\tmap\t"), true)
}

@(test)
editor_symbols_source_includes_source_package_imports :: proc(t: ^testing.T) {
    source := `(package main)
(import hiccup "kvist:hiccup")

(defn main []
  (hiccup/render (hiccup/html [:div "ok"])))`

    path := "/Users/andreas/Projects/kvist/.tmp-hiccup-editor-symbols.kvist"
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

    testing.expect_value(t, strings.contains(output, "macro\thiccup/html\t"), true)
    testing.expect_value(t, strings.contains(output, "proc\thiccup/render\t"), true)
    testing.expect_value(t, strings.contains(output, "struct\thiccup/Element\t"), true)
    testing.expect_value(t, strings.contains(output, "union\thiccup/Node\t"), true)
    testing.expect_value(t, strings.contains(output, "packages/hiccup/package.kvist"), true)
    testing.expect_value(t, strings.contains(output, "hiccup/emit-node"), false)
    testing.expect_value(t, strings.contains(output, "hiccup/render-node-into"), false)
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

    testing.expect_value(t, strings.contains(output, "proc\thelper-value\t"), true)
    testing.expect_value(t, strings.contains(output, "proc\tsecret-bonus\t"), true)
    testing.expect_value(t, strings.contains(output, helpers_path), true)
}

@(test)
compile_path_supports_hiccup_expression_interpolation :: proc(t: ^testing.T) {
    path := "/Users/andreas/Projects/kvist/.tmp-hiccup-interpolation-test.kvist"
    defer os.remove(path)

    source := `(import hiccup "kvist:hiccup")

(defn status-label [enabled?: bool] -> string
  (if enabled?
    "Ready"
    "Hidden"))

(defn demo [title: string, count: int, ratio: float, enabled?: bool] -> hiccup/Node
  (let [archived? false]
    (hiccup/html
      [:section {:data-count count
                 :data-ratio ratio
                 :hidden enabled?
                 :data-state (if enabled? "ready" "hidden")
                 :data-archived (when archived? "true")}
       [:h1 title]
       [:<>
        [:h2 title]
        [:p (+ count 10)]]
       [:p (status-label enabled?)]
       [:p (+ count 1)]
       (when archived?
         [:p "Archived"])
       nil
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

    testing.expect_value(t, strings.contains(output, `value = hiccup__Attr_Value(count)`), true)
    testing.expect_value(t, strings.contains(output, `value = hiccup__Attr_Value(ratio)`), true)
    testing.expect_value(t, strings.contains(output, `value = hiccup__Attr_Value(enabled_p)`), true)
    testing.expect_value(t, strings.contains(output, `value = hiccup__if_attr_value(enabled_p, hiccup__Attr_Value("ready"), hiccup__Attr_Value("hidden"))`), true)
    testing.expect_value(t, strings.contains(output, `value = hiccup__if_attr_value(archived_p, hiccup__Attr_Value("true"), hiccup__Attr_Value(hiccup__Nothing{}))`), true)
    testing.expect_value(t, strings.contains(output, `children = []hiccup__Node{hiccup__Node(title)}`), true)
    testing.expect_value(t, strings.contains(output, `hiccup__Node(hiccup__Fragment{children = []hiccup__Node{hiccup__Node(hiccup__Element{tag = "h2"`), true)
    testing.expect_value(t, strings.contains(output, `hiccup__Node((count) + (10))`), true)
    testing.expect_value(t, strings.contains(output, `hiccup__Node(status_label(enabled_p))`), true)
    testing.expect_value(t, strings.contains(output, `hiccup__Node((count) + (1))`), true)
    testing.expect_value(t, strings.contains(output, `hiccup__if_node(archived_p, hiccup__Node(hiccup__Element{tag = "p"`), true)
    testing.expect_value(t, strings.contains(output, `hiccup__Node(hiccup__Nothing{})`), true)
    testing.expect_value(t, strings.contains(output, `hiccup__if_node(enabled_p, hiccup__Node("Visible"), hiccup__Node("Hidden"))`), true)
    testing.expect_value(t, strings.contains(output, `hiccup__Attr_Value("count")`), false)
    testing.expect_value(t, strings.contains(output, `hiccup__Node("title")`), false)
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

add :: proc(a: int, b: int) -> int {
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
(import os "core:os")

(defn load-note [path: string] -> [data: []byte, err: os.Error]
  (slurp path))`

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

    expected := `package main

import fmt "core:fmt"

import os "core:os"

load_note :: proc(path: string) -> (data: []byte, err: os.Error) {
    return os.read_entire_file(path, context.allocator)
}

main :: proc() {
    {
        data, err := load_note("tmp/kvist-note.txt")
        if (err) != (nil) {
            fmt.println(0)
        }
        else {
            {
                defer delete(data)
                fmt.println(len(data))
            }
        }
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_eval_source_can_load_declaration_form :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Greeting {
  :message string
})`

    output, err, ok := kvist.compile_eval_source(source, `(struct Greeting {
  :message string
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
  {:message string})`

    output, err, ok := kvist.compile_eval_source(source, `(defstruct Greeting
  "Greeting text."
  {:message string})`)
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
  {:name string
   :name int})`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    testing.expect_value(t, strings.contains(err.message, "duplicate defstruct field :name"), true)
}

@(test)
compile_defstruct_rejects_bad_metadata :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Broken
  {:tags [set]
   :scores [fixed-arr int]})`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    testing.expect_value(t, strings.contains(err.message, "expects one element type") || strings.contains(err.message, "expects a numeric length"), true)
}

@(test)
compile_struct_constructor_rejects_unknown_field :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Person
  {:name string
   :age int})

(defn bad [] -> Person
  (Person {:name "Ada" :extra 1}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    testing.expect_value(t, strings.contains(err.message, "unknown struct constructor field :extra"), true)
}

@(test)
compile_struct_constructor_rejects_duplicate_field :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Person
  {:name string
   :age int})

(defn bad [] -> Person
  (Person {:name "Ada" :name "Grace"}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    testing.expect_value(t, strings.contains(err.message, "duplicate struct constructor field :name"), true)
}

@(test)
compile_struct_constructor_rejects_literal_type_mismatch :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Person
  {:name string
   :age int})

(defn bad [] -> Person
  (Person {:name 42 :age "old"}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    testing.expect_value(t, strings.contains(err.message, "struct constructor literal type mismatch for :name") || strings.contains(err.message, "struct constructor literal type mismatch for :age"), true)
}

@(test)
compile_update_bang_stmt :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point
  {:x int
   :y int})

(defn score [] -> int
  (let [xs (new [dynamic]int [1 2 3])
        lookup (new map[string]int {"a" 1})
        point (Point {:x 4 :y 5})]
    (update! xs 1 42)
    (update! lookup "a" 7)
    (update! point :y 9)
    (+ (+ (get xs 1) (get lookup "a"))
       (:y point))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "(xs)[1] = 42"), true)
    testing.expect_value(t, strings.contains(output, "(lookup)[\"a\"] = 7"), true)
    testing.expect_value(t, strings.contains(output, "(point).y = 9"), true)
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
compile_eval_source_can_load_main_proc_declaration_form :: proc(t: ^testing.T) {
    source := `(package main)
(import "core:fmt")

(defn main []
  (fmt.println "hello"))`

    output, err, ok := kvist.compile_eval_source(source, `(proc main []
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
#_(struct Ignored {
  :field string
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

(defconst answer 42)`

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
    testing.expect_value(t, forms[1].source, "(const answer 42)")
}

@(test)
reader_converts_semicolon_doc_comments :: proc(t: ^testing.T) {
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    source := `; Lisp doc.
(defconst answer 42)`

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
(defconst answer 42)`

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

    source := `(const answer 42)
(defconst negative -1)
(defconst ok true)
(defconst none nil)`

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

    source := `(defconst xs [1 2 3])
(defconst lookup {:one "1" :two "2"})
(defconst tags #{:math :lisp})`

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

(defconst answer 42)

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
  (let [lookup (new map[string]int {"one" 1})]
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
(defconst answer 42)
; Maximum configured size.
(defconst max-size int 1024)

(defenum Method [
  Get
  Post
  Delete
])

(defenum Http-Status {
  :OK 200
  :Not-Found 404
  :Unprocessable-Content 422
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
compile_defconst_and_defvar_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defconst answer 42)
(defvar live-port int 8080)
(defvar retries 3)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "answer :: 42"), true)
    testing.expect_value(t, strings.contains(output, "live_port: int = 8080"), true)
    testing.expect_value(t, strings.contains(output, "retries := 3"), true)
}

@(test)
compile_malli_types_and_empty_collection_constructors :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")
(import map "kvist:map")
(import set "kvist:set")

(defn score [xs: [dynamic]int, tags: set[string]] -> int
  (let [out (arr/empty int 4)
        lookup (map/empty string int)
        seen (set/empty string 8)]
    (arr/push! out (arr/count xs))
    (update! lookup "count" (arr/count xs))
    (set/add! seen "ok")
    (+ (arr/get out 0) (map/get lookup "count" 0))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "score :: proc(xs: [dynamic]int, tags: map[string]bool) -> int"), true)
    testing.expect_value(t, strings.contains(output, "out := make([dynamic]int, 0, 4)"), true)
    testing.expect_value(t, strings.contains(output, "lookup := make(map[string]int)"), true)
    testing.expect_value(t, strings.contains(output, "seen := make(map[string]bool, 8)"), true)
}

@(test)
compile_supports_aliased_kvist_package_imports :: proc(t: ^testing.T) {
    source := `(package main)
(import a "kvist:arr")

(defn demo [] -> int
  (let [xs (a/empty int)]
    (a/push! xs 1 2 3)
    (a/count xs)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "xs := make([dynamic]int)"), true)
    testing.expect_value(t, strings.contains(output, "append(&(xs), 1, 2, 3)"), true)
    testing.expect_value(t, strings.contains(output, "return len(xs)"), true)
    testing.expect_value(t, strings.contains(output, "kvist:arr"), false)
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
  {:i int
   :s string})`

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
(import struct "kvist:struct")

(defstruct Profile
  {:name string
   :active? bool
   :favorite-key keyword
   :tags set[string]
   :scores [dynamic]int
   :window []float})

(defn type-map [] -> map[string]string
  (struct/types 'Profile))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "\":tags\" = \"set[string]\""), true)
    testing.expect_value(t, strings.contains(output, "\":scores\" = \"[dynamic]int\""), true)
    testing.expect_value(t, strings.contains(output, "\":window\" = \"[]float\""), true)
    testing.expect_value(t, strings.contains(output, "\":active?\" = \"bool\""), true)
    testing.expect_value(t, strings.contains(output, "\":favorite-key\" = \"string\""), true)
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
  :i int
  :s string
})

(defn wrap-int [n: int] -> Value
  (Value {:i n}))`

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

(defn score [a: int, b: int, ok: bool] -> int
  (if (and ok (> a b))
    (+ a b)
    (if (not ok)
      (- b)
      (- b a))))

(defn has-key [lookup: map[string]int, key: string] -> bool
  (in? lookup key))

(defn contains-key [lookup: map[string]int, key: string] -> bool
  (contains? lookup key))

(defn missing-key [lookup: map[string]int, key: string] -> bool
  (not (in? lookup key)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

score :: proc(a: int, b: int, ok: bool) -> int {
    if (ok) && ((a) > (b)) {
        return (a) + (b)
    }
    else {
        if !(ok) {
            return -(b)
        }
        else {
            return (b) - (a)
        }
    }
}

has_key :: proc(lookup: map[string]int, key: string) -> bool {
    return (key) in (lookup)
}

contains_key :: proc(lookup: map[string]int, key: string) -> bool {
    return (key) in (lookup)
}

missing_key :: proc(lookup: map[string]int, key: string) -> bool {
    return !((key) in (lookup))
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_union_type_switch :: proc(t: ^testing.T) {
    source := `(package main)

(defunion Value {
  :i int
  :s string
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
compile_cond_with_final_else :: proc(t: ^testing.T) {
    source := `(package main)

(defn classify [n: int] -> string
  (cond
    (< n 0) "negative"
    (== n 0) "zero"
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
compile_for_iteration_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defn score-array [xs: [dynamic]int] -> int
  (let [total 0]
    (for [i x xs]
      (set! total (+ total i x)))
    total))

(defn score-map [counts: map[string]int] -> int
  (let [total 0]
    (for [key value counts]
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
compile_flat_multi_return_destructuring :: proc(t: ^testing.T) {
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
        {
            if (value) > (40) {
                return
            }
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
(import os "core:os")

(defn read-file [path: string] -> [data: []byte, err: os.Error]
  (slurp path))

(defn write-text [path: string, text: string] -> os.Error
  (spit path text))

(defn read-count [path: string] -> int
  (let [[data err] (slurp path)]
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

    testing.expect_value(t, strings.contains(output, `import os "core:os"`), true)
    testing.expect_value(t, strings.contains(output, "read_file :: proc(path: string) -> (data: []byte, err: os.Error)"), true)
    testing.expect_value(t, strings.contains(output, "return os.read_entire_file(path, context.allocator)"), true)
    testing.expect_value(t, strings.contains(output, "return os.write_entire_file(path, text)"), true)
    testing.expect_value(t, strings.contains(output, "data, err := os.read_entire_file(path, context.allocator)"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(data)"), true)
}

@(test)
compile_json_interop_is_explicit :: proc(t: ^testing.T) {
    source := `(package main)
(import json "core:encoding/json")
(import os "core:os")

(defstruct User {
  :name string
  :age int
})

(defn save-user [path: string, user: User] -> bool
  (let [[data marshal-err] (json.marshal user)]
    (if (!= marshal-err nil)
      false
      (do
        (defer (delete data))
        (== (spit path data) nil)))))

(defn load-user [path: string] -> [user: User, ok: bool]
  (let [[data read-err] (slurp path)]
    (if (!= read-err nil)
      (return user false)
      (do
        (defer (delete data))
        (let [unmarshal-err (json.unmarshal data (& user))]
          (return user (== unmarshal-err nil)))))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `import json "core:encoding/json"`), true)
    testing.expect_value(t, strings.contains(output, `import os "core:os"`), true)
    testing.expect_value(t, strings.contains(output, "data, marshal_err := json.marshal(user)"), true)
    testing.expect_value(t, strings.contains(output, "return (os.write_entire_file(path, data)) == (nil)"), true)
    testing.expect_value(t, strings.contains(output, "data, read_err := os.read_entire_file(path, context.allocator)"), true)
    testing.expect_value(t, strings.contains(output, "unmarshal_err := json.unmarshal(data, &user)"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(data)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_save_json"), false)
    testing.expect_value(t, strings.contains(output, "kvist_load_json"), false)
}

@(test)
compile_tap_helper :: proc(t: ^testing.T) {
    source := `(package main)
(import "core:fmt")

(defn main []
  (let [answer (tap> :answer 42)
        owned (tap> "owned" (new [dynamic]int [1 2 3]))]
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
compile_tap_thread_steps :: proc(t: ^testing.T) {
    source := `(package main)
(import "core:fmt")

(defn inc [x: int] -> int
  (+ x 1))

(defn even? [x: int] -> bool
  (== (% x 2) 0))

(defn add [acc: int, x: int] -> int
  (+ acc x))

(defn main []
  (let [xs (new []int [1 2 3 4])
        answer (-> 41
                   inc
                   (tap> :answer))
        mapped (->> xs
                    (map inc)
                    (tap> :mapped))
        total (->> xs
                   (map inc)
                   (tap> "mapped")
                   (filter even?)
                   (reduce add 0))]
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
compile_struct_field_destructuring :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User {
  :name string
  :age int
})

(defn main []
  (let [user (User {:name "Ada" :age 36})
        {:name user-name :age user-age} user
        {:age} user]
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
    age: int,
}

main :: proc() {
    user := User{name = "Ada", age = 36}
    kvist_destructure_1 := user
    user_name := kvist_destructure_1.name
    user_age := kvist_destructure_1.age
    kvist_destructure_2 := user
    age := kvist_destructure_2.age
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_with_allocator_scope :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (with-allocator [allocator context.temp_allocator]
    (let [buffer (make [dynamic]int)]
      (defer (delete buffer))
      (into! buffer (new []int [1 2]))
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
      (into! buffer (new []int [1 2]))
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

(defn inc [x: int] -> int
  (+ x 1))

(defn even? [x: int] -> bool
  (== (% x 2) 0))

(defn add [acc: int, x: int] -> int
  (+ acc x))

(defn total [xs: []int] -> int
  (let [mapped (map inc xs) defer
        filtered (filter even? mapped) defer]
    (reduce add 0 filtered)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "mapped := kvist_map(inc, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(mapped)"), true)
    testing.expect_value(t, strings.contains(output, "filtered := kvist_filter(even_p, (mapped)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(filtered)"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_reduce(add, 0, (filtered)[:])"), true)
}

@(test)
compile_with_temp_allocator_final_scalar_use :: proc(t: ^testing.T) {
    source := `(package main)
(import runtime "base:runtime")

(defn total [] -> int
  (with-temp-allocator [allocator]
    (let [xs (new [dynamic]int [1 2]) ]
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
  (return (new [dynamic]byte [1 2]) nil))

(defn load [path: string]
  (for true
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
  (for true
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

    path, join_err := os.join_path({dir, "package.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package tests)

(import t "kvist:test")

(t/deftest sample
  (t/is true))`

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
    testing.expect_value(t, strings.contains(output, "testing.expect(t, true)"), true)
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

    path, join_err := os.join_path({dir, "package.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package tests)

(import t "kvist:test")

(defn each-fixture [t: ^testing.T, body: proc [t: ^testing.T]]
  (body t))

(t/use-fixtures :each each-fixture)

(t/deftest sample
  "Sample test."
  (t/testing "numbers"
    (t/is (= 1 1))
    (t/is (not false))
    (t/is (= (+ 1 1) 2))
    (t/are [x expected]
      (= x expected)
      1 1
      2 2)))`

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
    testing.expect_value(t, strings.contains(output, "testing.expect_value(t, 1, 1)"), true)
    testing.expect_value(t, strings.contains(output, "testing.expect(t, !(false))"), true)
    testing.expect_value(t, strings.contains(output, "testing.expect_value(t, (1) + (1), 2)"), true)
    testing.expect_value(t, strings.contains(output, "testing.expect_value(t, 2, 2)"), true)
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

    path, join_err := os.join_path({dir, "package.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package tests)

(import t "kvist:test")

(t/deftest sample
  (t/is true "ok")
  (t/is false "not ok"))`

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

    testing.expect_value(t, strings.contains(output, `testing.expect(t, true, "ok")`), true)
    testing.expect_value(t, strings.contains(output, `testing.expect(t, false, "not ok")`), true)
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

    path, join_err := os.join_path({dir, "package.kvist"}, context.allocator)
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

    source := `(package tests)

(import t "kvist:test")

(t/deftest passing
  (t/is true))

(t/deftest failing
  (t/is false))`

    write_err := os.write_entire_file_from_string(path, source)
    testing.expect_value(t, write_err == nil, true)
    if write_err != nil {
        return
    }

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {"odin", "run", "cmd/kvist", "--", "test", path, "--generated", generated, "--names", "passing"},
            working_dir = ".",
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
reject_or_else_wrong_arity :: proc(t: ^testing.T) {
    source := `(package main)

(defn query [] -> [value: int, ok: bool] #optional_ok
  (return 42 true))

(defn total [] -> int
  (or-else (query)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "or-else expects optional-ok expression and fallback")
}

@(test)
compile_let_defer_final_if_scalar_use :: proc(t: ^testing.T) {
    source := `(package main)

(defn total [flag: bool] -> int
  (let [xs (new [dynamic]int [1 2]) defer]
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

(defn total [n: int] -> int
  (let [xs (new [dynamic]int [1 2]) defer]
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

(defn total [mode: int] -> int
  (let [xs (new [dynamic]int [1 2]) defer]
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
  (let [xs (new [dynamic]int [1 2]) defer
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
  (let [xs (new [dynamic]int [1 2]) defer]
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
  :xs [dynamic]int
})

(defn owned [] -> Box
  (let [xs (new [dynamic]int [1 2]) defer]
    (Box {:xs xs})))`

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
  (let [xs (new [dynamic]int [1 2]) defer]
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
  :xs [dynamic]int
})

(defn owned [] -> Box
  (let [xs (new [dynamic]int [1 2]) defer
        box (Box {:xs xs})]
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
  :xs [dynamic]int
})

(defn owned [] -> Box
  (let [xs (new [dynamic]int [1 2]) defer
        box (Box {:xs (new [dynamic]int [])})]
    (set! box (Box {:xs xs}))
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
  :xs [dynamic]int
})

(defn owned [flag: bool] -> Box
  (let [xs (new [dynamic]int [1 2]) defer
        box (Box {:xs xs})]
    (if flag
      box
      (Box {:xs (new [dynamic]int [])}))))`

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
    (map inc xs)))`

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
  :xs [dynamic]int
})

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [xs: []int] -> Box
  (with-temp-allocator [allocator]
    (let [box (Box {:xs (map inc xs)})]
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
  :xs [dynamic]int
})

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [xs: []int] -> Box
  (with-temp-allocator [allocator]
    (let [box (Box {:xs (new [dynamic]int [])})]
      (set! box (Box {:xs (map inc xs)}))
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
  :xs [dynamic]int
})

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [xs: []int flag: bool] -> Box
  (with-temp-allocator [allocator]
    (let [box (Box {:xs (map inc xs)})]
      (if flag
        box
        (Box {:xs (new [dynamic]int [])})))))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "owned value cannot escape with-temp-allocator; allocate it outside the temp scope or copy it before returning")
    testing.expect_value(t, source[err.span.start:err.span.end], "box")
}

@(test)
reject_returning_slurp_result_from_with_temp_allocator :: proc(t: ^testing.T) {
    source := `(package main)
(import os "core:os")
(import runtime "base:runtime")

(defn bad [path: string] -> [data: []byte, err: os.Error]
  (with-temp-allocator [allocator]
    (slurp path)))`

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
  :xs [dynamic]int
})

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [xs: []int] -> Box
  (with-temp-allocator [allocator]
    (Box {:xs (map inc xs)})))`

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
    (pass-through (map inc xs))))`

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
    (into! buffer (new []int [1 2]))))`)
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
    (let [buffer (make [dynamic]int)] (defer (delete buffer)) (into! buffer (new []int [1 2])))))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_with_temp_allocator_scope :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(with-temp-allocator [allocator]
  (let [buffer (make [dynamic]int)]
    (defer (delete buffer))
    (into! buffer (new []int [1 2]))))`)
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
    (let [buffer (make [dynamic]int)] (defer (delete buffer)) (into! buffer (new []int [1 2])))))
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

    expected := `(let [[value found] (query)] (when found (fmt.println value)))
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

    expected := `(let [[data err] (read-text path)] (when (== err {}) (use data)))
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

    expected := `(let [[data err] (read-text path)] (if (== err {}) (len data) 0))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_thread_first :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(-> req :method method-name)`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(method-name (:method req))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_thread_last :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(->> xs (filter even?) (map inc) (count))`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(count (map inc (filter even? xs)))
`
    testing.expect_value(t, output, expected)
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
  (let [xs (map inc users)]
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

    body_start := strings.index(source, "(let [xs (map inc users)]")

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

(defentity Point {:x float :y float})

(defn point-origin? [point: Point] -> bool
  (and (== (:x point) 0.0)
       (== (:y point) 0.0)))`

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
    (let [tag (first variants)
          value-type (nth variants 1)
          ctor-name (symbol (str "make-" (name union-name) "-" (name tag)))]
      (forms
        (quasiquote
          (defn (unquote ctor-name) [value: (unquote value-type)] -> (unquote union-name)
            ((unquote union-name) {(unquote tag) value})))
        (emit-union-ctors union-name (rest (rest variants)))))))

(defmacro defunion+ctors [name variants]
  (forms
    (quasiquote
      (defunion (unquote name) (unquote variants)))
    (emit-union-ctors name variants)))

(defunion+ctors Value {
  :i int
  :s string
  :ok bool
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
    (let [entry (first entries)
          struct-name (nth entry 0)
          fields (nth entry 1)]
      (forms
        (quasiquote
          (defstruct (unquote struct-name) (unquote fields)))
        (emit-message-structs (rest entries))))))

(defmacro emit-message-union-entries [entries]
  (if (= (count entries) 0)
    (forms)
    (let [entry (first entries)
          struct-name (nth entry 0)
          tag (keyword (name struct-name))]
      (forms
        tag
        struct-name
        (emit-message-union-entries (rest entries))))))

(defmacro emit-message-ctors [union-name entries]
  (if (= (count entries) 0)
    (forms)
    (let [entry (first entries)
          struct-name (nth entry 0)
          ctor-name (symbol (str "make-" (name union-name) "-" (name struct-name)))
          tag (keyword (name struct-name))]
      (forms
        (quasiquote
          (defn (unquote ctor-name) [value: (unquote struct-name)] -> (unquote union-name)
            ((unquote union-name) {(unquote tag) value})))
        (emit-message-ctors union-name (rest entries))))))

(defmacro defmessages [union-name entries]
  (forms
    (emit-message-structs entries)
    (quasiquote
      (defunion (unquote union-name) {
        (splice (emit-message-union-entries entries))
      }))
    (emit-message-ctors union-name entries)))

(defmessages Event [
  [Connected {:id int}]
  [Disconnected {:id int :reason string}]
  [Data {:id int :payload string}]
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
compile_proc_types_and_literals :: proc(t: ^testing.T) {
    source := `(package main)

(defn apply [f: (proc [x: int] -> int), x: int] -> int
  (f x))

(defn main []
  (let [out (apply (proc [x: int] -> int
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

(defn inc [x: int] -> int
  (+ x 1))

(defn even? [x: int] -> bool
  (== (% x 2) 0))

(defn add [acc: int, x: int] -> int
  (+ acc x))

(defn main []
  (let [xs (new []int [1 2 3 4])
        mapped (map inc xs)
        tail (slice mapped 1)
        evens (filter even? mapped)
        total (->> xs
                   (map inc)
                   (filter even?)
                   (reduce add 0))
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

add :: proc(acc: int, x: int) -> int {
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

(defn keep? [x: int] -> bool
  (< x 4))

(defn main []
  (let [xs (new []int [1 2 3 4])
        prefix (take 2 xs)
        suffix (drop 1 xs)
        without-last (butlast xs)
        without-two (drop-last 2 xs)
        small-prefix (take-while keep? xs)
        large-suffix (drop-while keep? xs)
        threaded-count (->> xs
                            (drop-last 1)
                            (count))]
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "prefix := kvist_take(2, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "suffix := kvist_drop(1, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "without_last := kvist_drop_last(1, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "without_two := kvist_drop_last(2, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "small_prefix := kvist_take_while(keep_p, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "large_suffix := kvist_drop_while(keep_p, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "threaded_count := len((kvist_drop_last(1, (xs)[:]))[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_take :: proc(n: int, xs: []$T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return xs[:limit]"), true)
    testing.expect_value(t, strings.contains(output, "kvist_drop :: proc(n: int, xs: []$T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return xs[start:]"), true)
    testing.expect_value(t, strings.contains(output, "kvist_drop_last :: proc(n: int, xs: []$T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return xs[:end]"), true)
    testing.expect_value(t, strings.contains(output, "kvist_take_while :: proc(pred: proc(x: $T) -> bool, xs: []T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return xs[:i]"), true)
    testing.expect_value(t, strings.contains(output, "kvist_drop_while :: proc(pred: proc(x: $T) -> bool, xs: []T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return xs[i:]"), true)
}

@(test)
compile_threaded_let_binding_keeps_owned_intermediates_alive :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User {
  :name string
  :active bool
})

(defn main []
  (let [users (new []User [(User {:name "Ada" :active true})
                           (User {:name "Lin" :active false})
                           (User {:name "Grace" :active true})])
        active-names (->> users
                          (filter :active)
                          (map :name)
                          (take 1))]
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
    testing.expect_value(t, strings.contains(output, "active_names := kvist_take(1, (kvist_thread_2)[:])"), true)
}

@(test)
reject_threaded_return_with_allocating_intermediate :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn even? [x: int] -> bool
  (== (% x 2) 0))

(defn bad [xs: []int] -> []int
  (->> xs
       (map inc)
       (filter even?)
       (take 1)))`

    _, err, ok := kvist.compile_source(source)
    defer delete(err.message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "threaded return has an allocating intermediate; bind the pipeline with let so Kvist can emit cleanup")
}

@(test)
reject_returning_threaded_view_of_owned_intermediate :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User {
  :name string
  :active bool
})

(defn bad [users: []User] -> []string
  (let [active-names (->> users
                          (filter :active)
                          (map :name)
                          (take 1))]
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
  (== (% x 2) 0))

(defn add-index [i: int, x: int] -> int
  (+ i x))

(defn keep-even [x: int] -> [value: int, ok: bool]
  (if (even? x)
    (return x true)
    (return 0 false)))

(defn pair [x: int] -> []int
  (new []int [x (+ x 10)]))

(defn neg [x: int] -> int
  (- x))

(defn pick-first [n: int] -> int
  0)

(defn main []
  (let [xs (new []int [1 2 3])
        mutable (new [dynamic]int [1 2 3])
        ys (new []int [4 5])
        without-evens (remove even? xs)
        indexed (map-indexed add-index xs)
        kept (keep keep-even xs)
        flattened (mapcat pair xs)
        joined (concat without-evens ys)
        copied (into [dynamic]int xs)
        interposed (interpose 0 xs)
        interleaved (interleave xs ys)
        reversed (reverse joined)
        shuffled (shuffle pick-first joined)
        sorted (sort joined)
        descending (sort-by neg joined)
        sampled (take-nth 2 joined)
        threaded-flat (->> xs
                           (mapcat pair)
                           (filter even?))
        threaded-sorted (->> xs
                             (sort)
                             (filter even?))
        threaded-sample (->> xs
                             (take-nth 2)
                             (map neg))
        tail-last (last joined)
        no-items? (empty? (drop 3 xs))]
    (defer (delete mutable))
    (defer (delete without-evens))
    (defer (delete indexed))
    (defer (delete kept))
    (defer (delete flattened))
    (defer (delete joined))
    (defer (delete copied))
    (defer (delete interposed))
    (defer (delete interleaved))
    (defer (delete reversed))
    (defer (delete shuffled))
    (defer (delete sorted))
    (defer (delete descending))
    (defer (delete sampled))
    (defer (delete threaded-flat))
    (defer (delete threaded-sorted))
    (defer (delete threaded-sample))
    (reverse! xs)
    (sort! xs)
    (sort-by! neg xs)
    (shuffle! pick-first xs)
    (map! neg mutable)
    (map-indexed! add-index mutable)
    (filter! even? mutable)
    (remove! even? mutable)
    (keep! keep-even mutable)
    (into! mutable ys)
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "without_evens := kvist_remove(even_p, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "indexed := kvist_map_indexed(add_index, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kept := kvist_keep(keep_even, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "flattened := kvist_mapcat(pair, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "joined := kvist_concat((without_evens)[:], (ys)[:])"), true)
    testing.expect_value(t, strings.contains(output, "copied := kvist_into([dynamic]int, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "interposed := kvist_interpose(0, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "interleaved := kvist_interleave((xs)[:], (ys)[:])"), true)
    testing.expect_value(t, strings.contains(output, "reversed := kvist_reverse((joined)[:])"), true)
    testing.expect_value(t, strings.contains(output, "shuffled := kvist_shuffle(pick_first, (joined)[:])"), true)
    testing.expect_value(t, strings.contains(output, "sorted := kvist_sort((joined)[:])"), true)
    testing.expect_value(t, strings.contains(output, "descending := kvist_sort_by_callback_neg((joined)[:])"), true)
    testing.expect_value(t, strings.contains(output, "import kvist_slice \"core:slice\""), true)
    testing.expect_value(t, strings.contains(output, "sampled := kvist_take_nth(2, (joined)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_1 := kvist_mapcat(pair, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "threaded_flat := kvist_filter(even_p, (kvist_thread_1)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_2 := kvist_sort((xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_2)"), true)
    testing.expect_value(t, strings.contains(output, "threaded_sorted := kvist_filter(even_p, (kvist_thread_2)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_3 := kvist_take_nth(2, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_3)"), true)
    testing.expect_value(t, strings.contains(output, "threaded_sample := kvist_map(neg, (kvist_thread_3)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_reverse_in_place((xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sort_in_place((xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sort_by_in_place_callback_neg((xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_shuffle_in_place(pick_first, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_map_in_place(neg, (mutable)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_map_indexed_in_place(add_index, (mutable)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_filter_in_place(even_p, &(mutable))"), true)
    testing.expect_value(t, strings.contains(output, "kvist_remove_in_place(even_p, &(mutable))"), true)
    testing.expect_value(t, strings.contains(output, "kvist_keep_in_place(keep_even, &(mutable))"), true)
    testing.expect_value(t, strings.contains(output, "append(&(mutable), ..(ys)[:])"), true)
    testing.expect_value(t, strings.contains(output, "tail_last := ((joined)[:])[len((joined)[:])-1]"), true)
    testing.expect_value(t, strings.contains(output, "no_items_p := len((kvist_drop(3, (xs)[:]))[:]) == 0"), true)
    testing.expect_value(t, strings.contains(output, "kvist_remove :: proc(pred: proc(x: $T) -> bool, xs: []T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_map_indexed :: proc(f: proc(i: int, x: $T) -> $U, xs: []T) -> [dynamic]U"), true)
    testing.expect_value(t, strings.contains(output, "kvist_keep :: proc(f: proc(x: $T) -> ($U, bool), xs: []T) -> [dynamic]U"), true)
    testing.expect_value(t, strings.contains(output, "kvist_mapcat :: proc(f: proc(x: $T) -> []$U, xs: []T) -> [dynamic]U"), true)
    testing.expect_value(t, strings.contains(output, "kvist_into :: proc($Out: typeid, xs: []$T) -> Out"), true)
    testing.expect_value(t, strings.contains(output, "kvist_interpose :: proc(sep: $T, xs: []T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_interleave :: proc(xs, ys: []$T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_shuffle :: proc(pick: proc(n: int) -> int, xs: []$T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sort :: proc(xs: []$T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_slice.sort(out[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sort_by_callback_neg :: proc(xs: []$T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "return neg(a) < neg(b)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_take_nth :: proc(n: int, xs: []$T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_reverse_in_place :: proc(xs: []$T)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_shuffle_in_place :: proc(pick: proc(n: int) -> int, xs: []$T)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sort_in_place :: proc(xs: []$T)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_slice.sort(xs)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sort_by_in_place_callback_neg :: proc(xs: []$T)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_map_in_place :: proc(f: proc(x: $T) -> T, xs: []T)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_map_indexed_in_place :: proc(f: proc(i: int, x: $T) -> T, xs: []T)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_filter_in_place :: proc(pred: proc(x: $T) -> bool, xs: ^[dynamic]T)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_remove_in_place :: proc(pred: proc(x: $T) -> bool, xs: ^[dynamic]T)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_keep_in_place :: proc(f: proc(x: $T) -> (T, bool), xs: ^[dynamic]T)"), true)
}

@(test)
compile_chunking_and_zipmap_sequence_helpers :: proc(t: ^testing.T) {
    source := `(package main)

(defn even? [x: int] -> bool
  (== (% x 2) 0))

(defn identity [x: int] -> int
  x)

(defn parity [x: int] -> int
  (% x 2))

(defn main []
  (let [xs (new []int [1 2 2 3 3 3])
        names (new []string ["Ada" "Lin"])
        ages (new []int [36 17])
        [front back] (split-at 2 xs)
        chunks (partition 2 xs)
        chunks-all (partition-all 3 xs)
        by-run (partition-by identity xs)
        by-name (zipmap names ages)
        by-parity (group-by parity xs)
        unique (distinct xs)
        distinct-parity (distinct-by parity xs)
        threaded (->> xs
                      (remove even?)
                      (distinct)
                      (partition-by identity))]
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

    testing.expect_value(t, strings.contains(output, "front, back := kvist_split_at(2, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "chunks := kvist_partition(2, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "chunks_all := kvist_partition_all(3, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "by_run := kvist_partition_by(identity, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "by_name := kvist_zipmap((names)[:], (ages)[:])"), true)
    testing.expect_value(t, strings.contains(output, "by_parity := kvist_group_by(parity, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "unique := kvist_distinct((xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "distinct_parity := kvist_distinct_by(parity, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "for _, group in by_parity {"), true)
    testing.expect_value(t, strings.contains(output, "delete(group)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_1 := kvist_remove(even_p, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_2 := kvist_distinct((kvist_thread_1)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_2)"), true)
    testing.expect_value(t, strings.contains(output, "threaded := kvist_partition_by(identity, (kvist_thread_2)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_split_at :: proc(n: int, xs: []$T) -> (left: []T, right: []T)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_partition :: proc(n: int, xs: []$T) -> [dynamic][]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_partition_all :: proc(n: int, xs: []$T) -> [dynamic][]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_partition_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> [dynamic][]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_zipmap :: proc(keys: []$K, values: []$V) -> map[K]V"), true)
    testing.expect_value(t, strings.contains(output, "kvist_group_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> map[K][dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_distinct :: proc(xs: []$T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_distinct_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> [dynamic]T"), true)
}

@(test)
compile_map_constructing_sequence_helpers :: proc(t: ^testing.T) {
    source := `(package main)

(defn identity [x: int] -> int
  x)

(defn amount [x: int] -> int
  x)

(defn main []
  (let [xs (new []int [1 2 2 3])
        by-value (index-by identity xs)
        by-group (group-by identity xs)
        by-count (count-by identity xs)
        by-sum (sum-by identity amount xs)
        threaded (->> xs
                      (count-by identity))
        counts (frequencies xs)
        base (new map[string]int {"a" 1 "b" 2})
        overrides (new map[string]int {"b" 20 "c" 30})
        merged (merge base overrides)
        key-list (keys base)
        value-list (vals overrides)
        key-count (->> merged
                       (keys)
                       (count))]
    (defer (delete by-value))
    (defer
      (each [_ group by-group]
        (delete group))
      (delete by-group))
    (defer (delete by-count))
    (defer (delete by-sum))
    (defer (delete threaded))
    (defer (delete counts))
    (defer (delete base))
    (defer (delete overrides))
    (defer (delete merged))
    (defer (delete key-list))
    (defer (delete value-list))
    (when (== key-count 0)
      (return))
    (merge! base overrides)
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "by_value := kvist_index_by(identity, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "by_group := kvist_group_by(identity, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "by_count := kvist_count_by(identity, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "by_sum := kvist_sum_by(identity, amount, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "threaded := kvist_count_by(identity, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "counts := kvist_frequencies((xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "merged := kvist_merge(base, overrides)"), true)
    testing.expect_value(t, strings.contains(output, "key_list := kvist_keys(base)"), true)
    testing.expect_value(t, strings.contains(output, "value_list := kvist_vals(overrides)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_1 := kvist_keys(merged)"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "key_count := len((kvist_thread_1)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_merge_in_place(&(base), overrides)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_index_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> map[K]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_group_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> map[K][dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_count_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> map[K]int"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sum_by :: proc(key_f: proc(x: $T) -> $K, value_f: proc(x: T) -> $V, xs: []T) -> map[K]V"), true)
    testing.expect_value(t, strings.contains(output, "kvist_frequencies :: proc(xs: []$T) -> map[T]int"), true)
    testing.expect_value(t, strings.contains(output, "kvist_merge :: proc(lhs, rhs: map[$K]$V) -> map[K]V"), true)
    testing.expect_value(t, strings.contains(output, "kvist_merge_in_place :: proc(target: ^map[$K]$V, source: map[K]V)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_keys :: proc(m: map[$K]$V) -> [dynamic]K"), true)
    testing.expect_value(t, strings.contains(output, "kvist_vals :: proc(m: map[$K]$V) -> [dynamic]V"), true)
}

@(test)
compile_bounded_sequence_producers :: proc(t: ^testing.T) {
    source := `(package main)

(defn next [] -> int
  42)

(defn double [x: int] -> int
  (* x 2))

(defn main []
  (let [xs (range 1 5)
        ys (repeat 3 "x")
        zs (repeatedly 2 next)
        powers (iterate 4 double 1)
        cycled (cycle 5 (new []int [1 2]))]
    (defer (delete xs))
    (defer (delete ys))
    (defer (delete zs))
    (defer (delete powers))
    (defer (delete cycled))
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "xs := kvist_range(1, 5, 1)"), true)
    testing.expect_value(t, strings.contains(output, "ys := kvist_repeat(3, \"x\")"), true)
    testing.expect_value(t, strings.contains(output, "zs := kvist_repeatedly(2, next)"), true)
    testing.expect_value(t, strings.contains(output, "powers := kvist_iterate(4, double, 1)"), true)
    testing.expect_value(t, strings.contains(output, "cycled := kvist_cycle(5, []int{1, 2})"), true)
    testing.expect_value(t, strings.contains(output, "kvist_range :: proc(start, end, step: int) -> [dynamic]int"), true)
    testing.expect_value(t, strings.contains(output, "kvist_repeat :: proc(n: int, value: $T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_repeatedly :: proc(n: int, f: proc() -> $T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_iterate :: proc(n: int, f: proc(x: $T) -> T, init: T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_cycle :: proc(n: int, xs: []$T) -> [dynamic]T"), true)
}

@(test)
compile_keyword_callbacks_for_sequence_helpers :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User {
  :name string
  :amount int
  :verified bool
})

(defn main []
  (let [users (new []User [(User {:name "Ada" :amount 10 :verified true})
                           (User {:name "Lin" :amount 20 :verified false})])
        names (map :name users)
        by-name (index-by :name users)
        by-verified (group-by :verified users)
        count-by-verified (count-by :verified users)
        sum-by-verified (sum-by :verified :amount users)
        groups (partition-by :verified users)
        distinct-names (distinct-by :name users)
        sorted (sort-by :name users)
        mutated (new [dynamic]User [(User {:name "Ada" :amount 10 :verified true})
                                    (User {:name "Lin" :amount 20 :verified false})])
        verified (filter :verified users)
        unverified (remove :verified users)
        [first ok] (find :verified users)
        any? (some? :verified users)
        all? (every? :verified verified)]
    (defer
      (each [_ group by-verified]
        (delete group))
      (delete by-verified))
    (sort-by! :name mutated)
    (filter! :verified mutated)
    (remove! :verified mutated)
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

(defn main []
  (let [xs (new []int [10 20 30])
        a (first xs)
        b (second xs)
        c (nth xs 2)
        n (count xs)
        tail (rest xs)
        threaded (->> xs
                      (rest)
                      (count))]
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
    xs := []int{10, 20, 30}
    a := ((xs)[:])[0]
    b := ((xs)[:])[1]
    c := ((xs)[:])[2]
    n := len((xs)[:])
    tail := ((xs)[:])[1:]
    threaded := len((((xs)[:])[1:])[:])
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
allow_returning_owned_sequence_result :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn owned [xs: []int] -> [dynamic]int
  (map inc xs))`

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
  (let [xs (new []int [1 2 3])]
    (map inc xs)
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
        testing.expect_value(t, result.warnings[0].message, "owned result from map is discarded; bind it, delete it, or return it")
    }
}

@(test)
reject_nested_owned_sequence_result :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn bad [xs: []int] -> int
  (first (map inc xs)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "owned result must be bound or returned; nested owned results would leak")
}

@(test)
warn_discarded_slurp_result :: proc(t: ^testing.T) {
    source := `(package main)
(import os "core:os")

(defn main []
  (slurp "cache.json")
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
        testing.expect_value(t, result.warnings[0].message, "owned result from slurp is discarded; bind it, delete it, or return it")
    }
}

@(test)
compile_collection_type_forms_and_make_new :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct State {
  :values (slice int)
  :buffer (dynamic int)
  :lookup (map string int)
  :next (ptr State)
})

(defn main []
  (let [values (new (slice int) [1 2 3])
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
compile_polymorphic_type_form :: proc(t: ^testing.T) {
    source := `(package main)
(import chan "core:sync/chan")

(defstruct Queue {
  :jobs (type chan.Chan int)
})

(defn recv-job [jobs: (type chan.Chan int)] -> int
  (let [[value ok] (chan.recv jobs)]
    (if ok value 0)))

(defn main []
  (let [[jobs err] (chan.create (type chan.Chan int) context.allocator)]
    (defer (chan.destroy jobs))
    (if (== err .None)
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
  :ports (array 3 int)
  :lookup (map string int)
})

(defn main []
  (let [ports: (array 3 int) (new (array 3 int) [80 443 8080])
        lookup: (map string int) (new (map string int) {"http" 80 "https" 443})]
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
compile_multiline_composite_literals :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Handler {
  :run (proc [] -> int)
})

(defn main []
  (let [handler (Handler {:run (proc [] -> int
                                  42)})
        handlers (new (slice Handler)
                   [(Handler {:run (proc [] -> int
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
  :method Method
  :path string
})

(defn method-name [method: Method] -> string
  (switch method
    .Get "GET"
    :else "OTHER"))

(defn describe [req: Request] -> string
  (-> req :method method-name))

(defn clone-path [req: Request, allocator: rawptr] -> string
  (-> req :path (clone-string allocator)))`

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
  :name string
})

(defn ptr-value [x: ^int] -> int
  (deref x))

(defn bump [x: ^int]
  (set! (deref x) (+ (deref x) 1)))

(defn borrow-name [p: ^Person] -> ^string
  (addr (:name (deref p))))`

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
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_pointer_suffix_deref_and_set_bang_locals :: proc(t: ^testing.T) {
    source := `(package main)

(defvar counter int 0)

(defn bump [total: ^int] -> int
  (set! total^ (+ total^ 1))
  total^)

(defn main [] -> int
  (let [local 2]
    (set! local (+ local 1))
    (set! counter local)
    (bump (addr counter))))`

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

(defstruct Point {
  :x int
  :y int
})

(defn score [] -> int
  (let [xs (new [dynamic]int [1 2 3])
        lookup (new map[string]int {"a" 1})
        point (Point {:x 4 :y 5})]
    (update! xs 1 + 40)
    (update! lookup "a" + 6)
    (update! point :y + 4)
    (+ (get xs 1) (get lookup "a") (:y point))))`

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
    (lookup)["a"] += (6)
    (point).y += (4)
    return (xs[1]) + (lookup["a"]) + (point.y)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_update_expr_struct_field :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point {
  :x int
  :y int
})

(defn inc [x: int] -> int
  (+ x 1))

(defn score [] -> int
  (let [point (Point {:x 4 :y 5})
        newer (update point :y inc)]
    (+ (:y point) (:y newer))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Point :: struct {
    x: int,
    y: int,
}

inc :: proc(x: int) -> int {
    return (x) + (1)
}

score :: proc() -> int {
    point := Point{x = 4, y = 5}
    newer := proc(value: Point) -> Point {
        kvist_eval_1 := value
        (kvist_eval_1).y = inc((kvist_eval_1).y)
        return kvist_eval_1
    }(point)
    return (point.y) + (newer.y)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_update_bang_unary_inc :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point {
  :y int
})

(defn inc [x: int] -> int
  (+ x 1))

(defn score [] -> int
  (let [point (Point {:y 5})]
    (update! point :y inc)
    (:y point)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "(point).y += 1"), true)
}

@(test)
compile_nil_predicate :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User {
  :name string
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
    return !((p) == nil)
}

print_user :: proc(p: ^User) {
    if (p) == nil {
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

greater_than_p :: proc(threshold: int, x: int) -> bool {
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
  :values []int
  :fixed [3]int
  :buffer [dynamic]int
  :lookup map[string]int
  :next ^Raw-Types
})

(defn values [state: ^Raw-Types] -> []int
  (:values (deref state)))

(defn main []
  (let [values (new []int [1 2 3])
        lookup (new map[string]int {"one" 1})
        buffer-literal (new [dynamic]int [1 2])
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

(defn first [xs: []int, lookup: map[string]int] -> int
  (let [buffer: [dynamic]int (make [dynamic]int)
        fixed: [3]int (new [3]int [1 2 3])
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
  (let [by-code (new map[int]string {1 "one" 2 "two"})
        by-flag (new map[bool]int {true 1 false 0})]
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

(defn score [] -> int
  (let [xs [1 2 3] defer
        lookup {:one 1 :two 2} defer
        tags #{:math :lisp} defer]
    (println tags)
    (+ (arr/count xs)
       (get lookup :one))))`

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
    lookup := map[string]int{":one" = 1, ":two" = 2}
    defer delete(lookup)
    tags := map[string]bool{":math" = true, ":lisp" = true}
    defer delete(tags)
    fmt.println(tags)
    return (len(xs)) + (lookup[":one"])
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
    (arr/count xs)))`

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
    tags: map[string]bool = map[string]bool{}
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
  (let [profile {:name "Ada" :age 36}]
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
compile_unparenthesized_proc_type_spelling :: proc(t: ^testing.T) {
    source := `(package main)

(defconst default-pred proc [x: int] -> bool
  (proc [x: int] -> bool
    true))

(defstruct Runner {
  :run proc [x: int] -> bool
})

(defunion Callback {
  :pred proc [x: int] -> bool
})

(defn apply-pred [pred: proc [x: int] -> bool, x: int] -> bool
  (pred x))

(defn always [] -> proc [x: int] -> bool
  (proc [x: int] -> bool
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
compile_typed_let_with_proc_type_spelling :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (let [pred: proc [x: int] -> bool (proc [x: int] -> bool
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

(odin "@(private)")
(odin "#force_inline")
(defn hidden [] -> int
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
reject_proc_directive_before_non_proc_declaration :: proc(t: ^testing.T) {
    source := `(package main)

(odin "#force_inline")
(defconst answer 42)`

    _, err, ok := kvist.compile_source(source)
    defer delete(err.message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "procedure directive must be followed by a proc declaration")
}

@(test)
compile_parenthesized_nested_proc_type_spelling :: proc(t: ^testing.T) {
    source := `(package main)

(defn identity-factory [f: (proc [x: int] -> proc [y: int] -> bool)] -> (proc [x: int] -> proc [y: int] -> bool)
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
    source := `(proc main []
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
    output, err, ok := kvist.compile_path("examples/cluck-port-packages.kvist")
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
  (let [xs (arr/dynamic int [n (+ n 1)])]
    (+ (arr/count xs) n)))`
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

    pkg_file, pkg_join_err := os.join_path({pkg_dir, "package.kvist"}, context.allocator)
    testing.expect_value(t, pkg_join_err == nil, true)
    if pkg_join_err != nil {
        return
    }
    defer delete(pkg_file)
    pkg_source := `(package secret)

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
  (println (secret/hidden)))`
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
    testing.expect_value(t, strings.contains(err.message, "source package member is private or undefined: secret/hidden"), true)
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

    alpha_file, alpha_file_err := os.join_path({alpha_dir, "package.kvist"}, context.allocator)
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

    beta_file, beta_file_err := os.join_path({beta_dir, "package.kvist"}, context.allocator)
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
(defconst answer 42)
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
compile_top_level_odin_escape :: proc(t: ^testing.T) {
    source := `(package main)

// Foreign handle alias.
(odin "Foreign_Handle :: distinct rawptr")
(odin "foreign import sqlite \"system:sqlite3\"")

(defn main []
  (odin "context.user_ptr = nil")
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

main :: proc() {
    context.user_ptr = nil
    return
}
`
    testing.expect_value(t, output, expected)
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
compile_warns_for_leaked_owned_let_local :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn demo []
  (let [xs (arr/empty int)]
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
  (let [xs (arr/empty int)]
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
  (let [xs (arr/empty int)]
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
  (let [xs (arr/empty int)]
    (set! xs (arr/empty int))
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
  (range 3)
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
        testing.expect_value(t, result.warnings[0].message, "owned result from range is discarded; bind it, delete it, or return it")
    }
}
