package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

@(test)
compile_vector_case_expression_clause_uses_source_equality :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Method [Get Head Post])

(defn cost [method: Method] -> int
  (let [value (case method
                [.Get .Head] 1
                .Post 2
                3)]
    value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, ".Get"), true)
    testing.expect_value(t, strings.contains(output, ".Head"), true)
}

@(test)
compile_eval_source_generates_scratch_main :: proc(t: ^testing.T) {
    source := `(package app)
(import fmt "core:fmt")

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

import fmt "core:fmt"

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
compile_eval_source_can_emit_statement_runner :: proc(t: ^testing.T) {
    source := `(package main)
(import fmt "core:fmt")

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

import fmt "core:fmt"

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
(import os "core:os")

(defn load-note [path: string] -> [data: []byte, err: os.Error]
  (os.read_entire_file path context.allocator))`

    output, err, ok := kvist.compile_eval_source(source, `(let [[data err] (load-note "tmp/kvist-note.txt")]
  (if (!= err nil)
    0
    (do
      (defer (delete data))
      (count data))))`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `import os "core:os"`), true)
    testing.expect_value(t, strings.contains(output, "return os.read_entire_file(path, context.allocator)"), true)
    testing.expect_value(t, strings.contains(output, "load_note :: proc(path: string) -> (data: []byte, err: os.Error)"), true)
    testing.expect_value(t, strings.contains(output, `data, err := load_note("tmp/kvist-note.txt")`), true)
    testing.expect_value(t, strings.contains(output, "fmt.println(len(data))"), true)
}

@(test)
compile_eval_source_can_load_declaration_form :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Greeting [
  message: string
])`

    output, err, ok := kvist.compile_eval_source(source, `(defstruct Greeting [
  message: string
])`)
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
  [message: string])`

    output, err, ok := kvist.compile_eval_source(source, `(defstruct Greeting
  "Greeting text."
  [message: string])`)
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
compile_eval_source_can_load_main_defn_declaration_form :: proc(t: ^testing.T) {
    source := `(package main)
(import fmt "core:fmt")

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

import fmt "core:fmt"

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
compile_core_helpers_and_source_refer_collisions_resolve_by_core_surface :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-core-refer-collision-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    shadow_path, shadow_join_err := os.join_path({dir, "shadow.kvist"}, context.allocator)
    testing.expect_value(t, shadow_join_err == nil, true)
    if shadow_join_err != nil {
        return
    }
    defer delete(shadow_path)
    shadow_source := `(package shadow)

(defmacro len [x]
  (quasiquote 999))

(defmacro cond-> [x & forms]
  (quasiquote 999))`
    shadow_write_err := os.write_entire_file_from_string(shadow_path, shadow_source)
    testing.expect_value(t, shadow_write_err == nil, true)
    if shadow_write_err != nil {
        return
    }

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package main)
(import "./shadow" :refer [len cond->])

(defn demo [] -> int
  (let [xs ([]int [1 2 3])]
    (+ (count xs)
       (len xs)
       (cond-> 1
         true (+ 1)))))`
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

    testing.expect_value(t, strings.contains(output, "len(xs)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_cond_thread"), true)
    testing.expect_value(t, strings.contains(output, "999"), true)
}

@(test)
compile_struct_types_reports_source_surface :: proc(t: ^testing.T) {
    source := `(package main)
(import soa "kvist:soa")

(defstruct Profile
  [name: string
   active?: bool
   favorite-key: string
   tags: (map string (struct []))
   scores: [dynamic]int
   window: []float])

(defn type-map [] -> map[string]string
  (soa.types 'Profile))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "\"tags\" = \"map[string]struct{}\""), true)
    testing.expect_value(t, strings.contains(output, "\"scores\" = \"[dynamic]int\""), true)
    testing.expect_value(t, strings.contains(output, "\"window\" = \"[]float\""), true)
    testing.expect_value(t, strings.contains(output, "\"active?\" = \"bool\""), true)
    testing.expect_value(t, strings.contains(output, "\"favorite-key\" = \"string\""), true)
}

@(test)
compile_vector_case_statement_clause_uses_source_equality :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Method [
  Get
  Head
  Post
])

(defn read-method? [method: Method] -> bool
  (case method
    [.Get .Head] true
    false))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, ".Get"), true)
    testing.expect_value(t, strings.contains(output, ".Head"), true)
}

@(test)
reject_partial_source_form :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Method [
  Get
  Post
])

(defn maybe-print [method: Method]
  (#partial switch method
    .Get (return)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "#partial is not Kvist syntax; use case or cond")
}

@(test)
reject_switch_source_form :: proc(t: ^testing.T) {
    source := `(package main)

(defn classify [n: int] -> string
  (switch n
    0 "zero"
    :else "other"))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "`switch` has been removed; use `case` for subject dispatch or `cond` for predicate branches")
}

@(test)
compile_tap_thread_steps :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")
(import arr "kvist:arr")
(import fmt "core:fmt")

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

    testing.expect_value(t, strings.contains(output, "fmt.print(\"answer\")"), true)
    testing.expect_value(t, strings.contains(output, "fmt.print(\"mapped\")"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_impl(inc, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "fmt.println(kvist_tap"), true)
    testing.expect_value(t, strings.contains(output, "proc(xs: []int) -> [dynamic]int"), true)
    testing.expect_value(t, strings.contains(output, "tap_labeled_impl"), false)
    testing.expect_value(t, strings.contains(output, "arr__filter_impl("), true)
    testing.expect_value(t, strings.contains(output, "even_p,"), true)
    testing.expect_value(t, strings.contains(output, "total := arr__reduce_impl(add, 0,"), true)
}

@(test)
reject_returning_destructured_source_owned_result_from_with_temp_allocator :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-temp-owned-destructured-source-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    pkg_dir, pkg_dir_err := os.join_path({dir, "support"}, context.allocator)
    testing.expect_value(t, pkg_dir_err == nil, true)
    if pkg_dir_err != nil {
        return
    }
    defer delete(pkg_dir)
    mk_pkg_err := os.make_directory_all(pkg_dir)
    testing.expect_value(t, mk_pkg_err == nil, true)
    if mk_pkg_err != nil {
        return
    }

    pkg_path, pkg_path_err := os.join_path({pkg_dir, "support.kvist"}, context.allocator)
    testing.expect_value(t, pkg_path_err == nil, true)
    if pkg_path_err != nil {
        return
    }
    defer delete(pkg_path)
    pkg_source := `(package support)
(import os "core:os")

(defn read-base [path: string] -> [data: []byte, err: os.Error] #force_inline
  (os.read_entire_file path context.allocator))`
    pkg_write_err := os.write_entire_file_from_string(pkg_path, pkg_source)
    testing.expect_value(t, pkg_write_err == nil, true)
    if pkg_write_err != nil {
        return
    }

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package main)
(import runtime "base:runtime")
(import support "support")

(defn bad [path: string] -> []byte
  (with-temp-allocator [allocator]
    (let [[data err] (support.read-base path)]
      data)))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    _, err, ok := kvist.compile_path_with_map(main_path)
    testing.expect_value(t, ok, false)
    defer kvist.compile_error_delete(&err)
    testing.expect_value(t, err.message, "owned value cannot escape with-temp-allocator; allocate it outside the temp scope or copy it before returning")
}

@(test)
reject_legacy_thread_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

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

(defstruct Request [
  path: string
])

(defn main [req: Request] -> int
  (-> req .path count))`

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
compile_named_functional_transform_into_and_transduce :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defstruct Order [
  status: int
  amount: int
  discount: int
])

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

(defn append [out: [dynamic]int, orders: []Order]
  (arr.into! out paid-order-totals orders))

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
    testing.expect_value(t, strings.contains(output, "(proc(kvist_out: ^[dynamic]int, kvist_source: []Order) {"), true)
    testing.expect_value(t, strings.contains(output, "append(kvist_out, kvist_xform_"), true)
    testing.expect_value(t, strings.contains(output, "kvist_acc += kvist_xform_"), true)
    testing.expect_value(t, strings.contains(output, "paid_order_totals ::"), false)
    testing.expect_value(t, strings.contains(output, "kvist-prim-dynamic-array-into"), false)
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
compile_defiter_each_into_and_transduce_consumers :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defstruct File_Source [
  items: []string
  index: int
])

(defn open-files [items: []string] -> File_Source
  (File_Source :items items :index 0))

(defn next-file [src: ^File_Source] -> [path: string ok: bool]
  (if (< src.index (count src.items))
    (let [path src.items[src.index]]
      (set! src.index (+ src.index 1))
      (return path true))
    (return "" false)))

(defn dispose-files [src: ^File_Source]
  (set! src.index 0))

(defn long-path? [path: string] -> bool
  (> (count path) 5))

(defn path-length [path: string] -> int
  (count path))

(defiter files [items: []string] -> File_Source :yield string
  :next next-file
  :dispose dispose-files
  (open-files items))

(defn total-name-length [items: []string] -> int
  (let [total 0]
    (for [path (files items)]
      (set! total (+ total (count path))))
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
    (files items)))

(defn total-long-path-length-for [items: []string] -> int
  (let [total 0]
    (for [length (files items) :transform (comp
                                            (filter long-path?)
                                            (map path-length))]
      (set! total (+ total length)))
    total))

(defn named-total-long-path-length-for [items: []string] -> int
  (let [total 0]
    (for [length (files items) :transform long-path-lengths]
      (set! total (+ total length)))
    total))

(defn indexed-total-long-path-length-for [items: []string] -> int
  (let [total 0]
    (for [idx length (files items) :transform long-path-lengths]
      (set! total (+ total idx length)))
    total))

(defn append-long-path-lengths [out: [dynamic]int, items: []string]
  (arr.into! out long-path-lengths (files items)))

(deftransform long-path-lengths
  (filter long-path?)
  (map path-length))

(defn total-long-path-length-named [items: []string] -> int
  (transduce
    long-path-lengths
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
    testing.expect_value(t, strings.contains(output, "length := kvist_xform_"), true)
    testing.expect_value(t, strings.contains(output, "total = (total) + (length)"), true)
    testing.expect_value(t, strings.contains(output, "idx := 0"), true)
    testing.expect_value(t, strings.contains(output, "total = (total) + (idx) + (length)"), true)
    testing.expect_value(t, strings.contains(output, "idx += 1"), true)
    testing.expect_value(t, strings.contains(output, "(proc(kvist_out: ^[dynamic]int, kvist_source_arg_1: []string) {"), true)
    testing.expect_value(t, strings.contains(output, "append(kvist_out, kvist_xform_"), true)
}

@(test)
compile_thread_start_result_and_detach :: proc(t: ^testing.T) {
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
    testing.expect_value(t, strings.contains(output, "zero_task := thread_start_zero_void_int()"), true)
    testing.expect_value(t, strings.contains(output, "combine_task := thread_start_combine_int_int_int_int(1, 2, 3)"), true)
    testing.expect_value(t, strings.contains(output, "thread_detach_notify_int(99)"), true)
    testing.expect_value(t, strings.contains(output, "return (p__result_impl(zero_task)) + (p__result_impl(combine_task))"), true)
    testing.expect_value(t, strings.contains(output, "parallel_Task :: struct($T: typeid)"), true)
    testing.expect_value(t, strings.contains(output, "result: chan.Chan(T),"), true)
    testing.expect_value(t, strings.contains(output, "thread: ^thread.Thread,"), true)
    testing.expect_value(t, strings.contains(output, "thread_Start_Data_zero_void_int :: struct"), true)
    testing.expect_value(t, strings.contains(output, "chan.send(data.result, zero())"), true)
    testing.expect_value(t, strings.contains(output, "thread_start_zero_void_int :: proc() -> parallel_Task(int)"), true)
    testing.expect_value(t, strings.contains(output, "thread_Start_Data_combine_int_int_int_int :: struct"), true)
    testing.expect_value(t, strings.contains(output, "a: int,"), true)
    testing.expect_value(t, strings.contains(output, "b: int,"), true)
    testing.expect_value(t, strings.contains(output, "c: int,"), true)
    testing.expect_value(t, strings.contains(output, "chan.send(data.result, combine(data.a, data.b, data.c))"), true)
    testing.expect_value(t, strings.contains(output, "thread_start_combine_int_int_int_int :: proc(a: int, b: int, c: int) -> parallel_Task(int)"), true)
    testing.expect_value(t, strings.contains(output, "thread.create_and_start_with_poly_data(data, thread_start_worker_combine_int_int_int_int)"), true)
    testing.expect_value(t, strings.contains(output, "p__result_impl :: #force_inline proc(task: parallel_Task($T)) -> T"), true)
    testing.expect_value(t, strings.contains(output, "parallel_result :: proc"), false)
    testing.expect_value(t, strings.contains(output, "thread.join(task.thread)"), true)
    testing.expect_value(t, strings.contains(output, "thread.destroy(task.thread)"), true)
    testing.expect_value(t, strings.contains(output, "free(task.data)"), true)
    testing.expect_value(t, strings.contains(output, "chan.destroy(task.result)"), true)
    testing.expect_value(t, strings.contains(output, "thread_Detach_Data_notify_int :: struct"), true)
    testing.expect_value(t, strings.contains(output, "thread_detach_worker_notify_int :: proc(data: ^thread_Detach_Data_notify_int)"), true)
    testing.expect_value(t, strings.contains(output, "notify(data.user_id)"), true)
    testing.expect_value(t, strings.contains(output, "thread_detach_notify_int :: proc(user_id: int)"), true)
    testing.expect_value(t, strings.contains(output, "thread.create_and_start_with_poly_data(data, thread_detach_worker_notify_int, nil, .Normal, true)"), true)
    testing.expect_value(t, strings.contains(output, "assert(false, \"thread-detach could not start worker thread\")"), true)
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

    testing.expect_value(t, strings.contains(output, "a := thread_start_square_int_int(1)"), true)
    testing.expect_value(t, strings.contains(output, "b := thread_start_square_int_int(2)"), true)
    testing.expect_value(t, strings.contains(output, "c := thread_start_square_int_int(3)"), true)
    testing.expect_value(t, count_substring(output, "thread_start_square_int_int :: proc(x: int) -> parallel_Task(int)"), 1)
    testing.expect_value(t, count_substring(output, "thread_start_worker_square_int_int :: proc(data: ^thread_Start_Data_square_int_int)"), 1)
}

@(test)
compile_thread_map_named_worker :: proc(t: ^testing.T) {
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
    testing.expect_value(t, strings.contains(output, "return p__map_impl(square, xs, 0)"), true)
    testing.expect_value(t, strings.contains(output, "p__map_impl :: #force_inline proc(f: proc(x: $T) -> $U, xs: []T, requested_worker_count: int) -> [dynamic]U"), true)
    testing.expect_value(t, strings.contains(output, "p__map_worker :: proc(f: proc(x: $T) -> $U, xs: []T, out: ^[dynamic]U, start, step: int) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "(out^)[i] = f((xs)[i])"), true)
    testing.expect_value(t, strings.contains(output, "out := make([dynamic]U, len(xs))"), true)
    testing.expect_value(t, strings.contains(output, "worker_count := requested_worker_count"), true)
    testing.expect_value(t, strings.contains(output, "worker_count = (os.get_processor_core_count()) - (1)"), true)
    testing.expect_value(t, strings.contains(output, "if (worker_count) > (16)"), true)
    testing.expect_value(t, strings.contains(output, "if (worker_count) > (source_count)"), true)
    testing.expect_value(t, strings.contains(output, "append(&tasks, thread_start_p__map_worker_"), true)
    testing.expect_value(t, strings.contains(output, "chan.send(data.result, p__map_worker(data.f, data.xs, data.out, data.start, data.step))"), true)
    testing.expect_value(t, strings.contains(output, "_ = p__result_impl((tasks)[i])"), true)
    testing.expect_value(t, strings.contains(output, "thread.join(task.thread)"), true)
    testing.expect_value(t, strings.contains(output, "thread.destroy(task.thread)"), true)
    testing.expect_value(t, strings.contains(output, "free(task.data)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_owner^ = false; return kvist_value"), false)
    testing.expect_value(t, strings.contains(output, "thread_map_square_int_int"), false)
}

@(test)
compile_thread_map_reuses_helper :: proc(t: ^testing.T) {
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

    testing.expect_value(t, count_substring(output, "p__map_impl :: #force_inline proc(f: proc(x: $T) -> $U, xs: []T, requested_worker_count: int) -> [dynamic]U"), 1)
    testing.expect_value(t, count_substring(output, "p__map_worker :: proc(f: proc(x: $T) -> $U, xs: []T, out: ^[dynamic]U, start, step: int) -> bool"), 1)
    testing.expect_value(t, strings.contains(output, "thread_start_worker_p__map_worker_"), true)
    testing.expect_value(t, strings.contains(output, "thread_map_square_int_int"), false)
}

@(test)
compile_thread_map_with_worker_count :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn square [x: int] -> int
  (* x x))

(defn demo [xs: []int] -> [dynamic]int
  (p.map-with {:workers 4} square xs))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return p__map_impl(square, xs, 4)"), true)
    testing.expect_value(t, strings.contains(output, "p__map_impl :: #force_inline proc(f: proc(x: $T) -> $U, xs: []T, requested_worker_count: int) -> [dynamic]U"), true)
    testing.expect_value(t, strings.contains(output, "thread_map_square_int_int"), false)
}

@(test)
compile_thread_map_and_map_with_reuse_helper :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn square [x: int] -> int
  (* x x))

(defn demo [xs: []int] -> int
  (let [a (p.map square xs)
        b (p.map-with {:workers 2} square xs)]
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

    testing.expect_value(t, strings.contains(output, "a := p__map_impl(square, xs, 0)"), true)
    testing.expect_value(t, strings.contains(output, "b := p__map_impl(square, xs, 2)"), true)
    testing.expect_value(t, count_substring(output, "p__map_impl :: #force_inline proc(f: proc(x: $T) -> $U, xs: []T, requested_worker_count: int) -> [dynamic]U"), 1)
    testing.expect_value(t, count_substring(output, "p__map_worker :: proc(f: proc(x: $T) -> $U, xs: []T, out: ^[dynamic]U, start, step: int) -> bool"), 1)
    testing.expect_value(t, strings.contains(output, "thread_map_square_int_int"), false)
}

@(test)
reject_thread_start_wrong_arity :: proc(t: ^testing.T) {
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
    testing.expect_value(t, err.message, "thread-start worker combine expects 2 arguments, got 1")
}

@(test)
compile_thread_start_inline_worker :: proc(t: ^testing.T) {
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

    testing.expect_value(t, strings.contains(output, "return p__result_impl(thread_start_inline_"), true)
    testing.expect_value(t, strings.contains(output, "(1))"), true)
    testing.expect_value(t, strings.contains(output, "thread_start_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, " :: proc(x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "thread_Start_Data_inline_"), true)
    testing.expect_value(t, strings.contains(output, "x: int,"), true)
    testing.expect_value(t, strings.contains(output, "chan.send(data.result, thread_start_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, "(data.x))"), true)
    testing.expect_value(t, strings.contains(output, "thread_start_inline_"), true)
    testing.expect_value(t, strings.contains(output, " :: proc(x: int) -> parallel_Task(int)"), true)
}

@(test)
compile_thread_start_with_captured_inline_worker :: proc(t: ^testing.T) {
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

    testing.expect_value(t, strings.contains(output, "task := thread_start_inline_"), true)
    testing.expect_value(t, strings.contains(output, "(offset, 5)"), true)
    testing.expect_value(t, strings.contains(output, "thread_start_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, " :: proc(offset: int, x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "offset: int,"), true)
    testing.expect_value(t, strings.contains(output, "x: int,"), true)
    testing.expect_value(t, strings.contains(output, "data.offset = offset"), true)
    testing.expect_value(t, strings.contains(output, "data.x = x"), true)
    testing.expect_value(t, strings.contains(output, "chan.send(data.result, thread_start_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, "(data.offset, data.x))"), true)
    testing.expect_value(t, strings.contains(output, "thread_start_inline_"), true)
    testing.expect_value(t, strings.contains(output, " :: proc(offset: int, x: int) -> parallel_Task(int)"), true)
}

@(test)
reject_thread_start_inline_without_return_value :: proc(t: ^testing.T) {
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
    testing.expect_value(t, err.message, "thread-start inline worker must return exactly one value")
}

@(test)
reject_thread_detach_return_value :: proc(t: ^testing.T) {
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
    testing.expect_value(t, err.message, "thread-detach worker must not return a value")
}

@(test)
compile_thread_detach_inline_worker :: proc(t: ^testing.T) {
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

    testing.expect_value(t, strings.contains(output, "thread_detach_inline_"), true)
    testing.expect_value(t, strings.contains(output, "()"), true)
    testing.expect_value(t, strings.contains(output, "thread_detach_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, " :: proc() {"), true)
    testing.expect_value(t, strings.contains(output, "thread_Detach_Data_inline_"), true)
    testing.expect_value(t, strings.contains(output, "thread_detach_worker_inline_"), true)
    testing.expect_value(t, strings.contains(output, "thread_detach_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, "thread.create_and_start_with_poly_data(data, thread_detach_worker_inline_"), true)
}

@(test)
compile_thread_detach_with_captured_inline_worker :: proc(t: ^testing.T) {
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

    testing.expect_value(t, strings.contains(output, "thread_detach_inline_"), true)
    testing.expect_value(t, strings.contains(output, "(offset, 5)"), true)
    testing.expect_value(t, strings.contains(output, "thread_detach_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, " :: proc(offset: int, x: int) {"), true)
    testing.expect_value(t, strings.contains(output, "offset: int,"), true)
    testing.expect_value(t, strings.contains(output, "x: int,"), true)
    testing.expect_value(t, strings.contains(output, "data.offset = offset"), true)
    testing.expect_value(t, strings.contains(output, "data.x = x"), true)
    testing.expect_value(t, strings.contains(output, "thread_detach_callback_inline_"), true)
    testing.expect_value(t, strings.contains(output, "(data.offset, data.x)"), true)
}

@(test)
reject_thread_detach_inline_return_value :: proc(t: ^testing.T) {
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
    testing.expect_value(t, err.message, "thread-detach inline worker must not return a value")
}

@(test)
compile_thread_map_inline_worker :: proc(t: ^testing.T) {
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

    testing.expect_value(t, strings.contains(output, "return p__map_impl("), true)
    testing.expect_value(t, strings.contains(output, "proc(x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "append(&tasks, thread_start_p__map_worker"), true)
    testing.expect_value(t, strings.contains(output, "chan.send(data.result, p__map_worker(data.f, data.xs, data.out, data.start, data.step))"), true)
    testing.expect_value(t, strings.contains(output, "thread_map_"), false)
}

@(test)
compile_thread_map_with_captured_inline_worker :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn demo [xs: []int] -> [dynamic]int
  (let [offset 10]
    (p.map-with {:workers 2}
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

    testing.expect_value(t, strings.contains(output, "p__map_impl__kvist_capture_0_1"), true)
    testing.expect_value(t, strings.contains(output, "proc(offset: int, x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "p__map_worker__kvist_capture_0_1"), true)
    testing.expect_value(t, strings.contains(output, "data.kvist_capture_1 = kvist_capture_1"), true)
    testing.expect_value(t, strings.contains(output, "p__map_worker__kvist_capture_0_1(data.f, data.kvist_capture_1, data.xs, data.out, data.start, data.step)"), true)
    testing.expect_value(t, strings.contains(output, "f(kvist_capture_1, (xs)[i])"), true)
    testing.expect_value(t, strings.contains(output, "thread_map_"), false)
}

@(test)
reject_thread_map_multi_arg_worker :: proc(t: ^testing.T) {
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
    testing.expect_value(t, err.message, "expected proc(x: int) -> int callback, got proc(int, int) -> int")
}

@(test)
reject_thread_map_inline_multi_arg_worker :: proc(t: ^testing.T) {
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
    testing.expect_value(t, err.message, "expected proc(x: int) -> int callback, got proc(int, int) -> int")
}

@(test)
reject_thread_map_source_type_mismatch :: proc(t: ^testing.T) {
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
    testing.expect_value(t, err.message, "expected proc(x: f64) -> int callback, got proc(int) -> int")
}

@(test)
reject_thread_map_with_non_brace_options :: proc(t: ^testing.T) {
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
    testing.expect_value(t, err.message, "while expanding macro p__map-with: parallel.map-with expects options like {:workers n}")
}

@(test)
reject_thread_map_with_missing_workers :: proc(t: ^testing.T) {
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
    testing.expect_value(t, err.message, "while expanding macro p__map-with: parallel.map-with expects {:workers n}")
}

@(test)
reject_thread_map_with_unknown_option :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn square [x: int] -> int
  (* x x))

(defn demo [xs: []int] -> [dynamic]int
  (p.map-with {:threads 4} square xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "while expanding macro p__map-with: parallel.map-with unknown option: threads")
}

@(test)
compile_thread_for_named_worker :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn record [x: int]
  (println x))

(defn demo [xs: []int]
  (p.for record xs))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "p__for_impl(record, xs, 0)"), true)
    testing.expect_value(t, strings.contains(output, "p__for_impl :: #force_inline proc(f: proc(x: $T), xs: []T, requested_worker_count: int)"), true)
    testing.expect_value(t, strings.contains(output, "p__for_worker :: proc(f: proc(x: $T), xs: []T, start, step: int) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "f((xs)[i])"), true)
    testing.expect_value(t, strings.contains(output, "worker_count = (os.get_processor_core_count()) - (1)"), true)
    testing.expect_value(t, strings.contains(output, "if (worker_count) > (16)"), true)
    testing.expect_value(t, strings.contains(output, "append(&tasks, thread_start_p__for_worker_"), true)
    testing.expect_value(t, strings.contains(output, "chan.send(data.result, p__for_worker(data.f, data.xs, data.start, data.step))"), true)
    testing.expect_value(t, strings.contains(output, "thread.join(task.thread)"), true)
    testing.expect_value(t, strings.contains(output, "free(task.data)"), true)
    testing.expect_value(t, strings.contains(output, "thread_for_record_int"), false)
}

@(test)
compile_thread_for_with_captured_inline_worker :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn demo [xs: []int]
  (let [offset 10]
    (p.for-with {:workers 2}
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

    testing.expect_value(t, strings.contains(output, "p__for_impl__kvist_capture_0_1"), true)
    testing.expect_value(t, strings.contains(output, "proc(offset: int, x: int) {"), true)
    testing.expect_value(t, strings.contains(output, "p__for_worker__kvist_capture_0_1"), true)
    testing.expect_value(t, strings.contains(output, "data.kvist_capture_1 = kvist_capture_1"), true)
    testing.expect_value(t, strings.contains(output, "p__for_worker__kvist_capture_0_1(data.f, data.kvist_capture_1, data.xs, data.start, data.step)"), true)
    testing.expect_value(t, strings.contains(output, "f(kvist_capture_1, (xs)[i])"), true)
    testing.expect_value(t, strings.contains(output, "thread_for_"), false)
}

@(test)
reject_thread_for_return_value :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn square [x: int] -> int
  (* x x))

(defn demo [xs: []int]
  (p.for square xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "expected proc(x: int) callback, got proc(int) -> int")
}

@(test)
reject_thread_for_inline_return_value :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn demo [xs: []int]
  (p.for (fn [x: int] -> int
            x)
          xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "expected proc(x: int) callback, got proc(int) -> int")
}

@(test)
reject_thread_for_with_unknown_option :: proc(t: ^testing.T) {
    source := `(package main)
(import p "kvist:parallel")

(defn record [x: int]
  (println x))

(defn demo [xs: []int]
  (p.for-with {:threads 4} record xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "while expanding macro p__for-with: parallel.for-with unknown option: threads")
}

@(test)
compile_functional_transform_field_selectors :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct User [
  age: int
  active?: bool
])

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
compile_functional_transform_map_indexed :: proc(t: ^testing.T) {
    source := `(package main)

(defn add-index [i: int x: int] -> int
  (+ i x))

(deftransform indexed
  (filter even?)
  (map-indexed add-index))

(defn even? [x: int] -> bool
  (= (% x 2) 0))

(defn total [xs: []int] -> int
  (transduce indexed + 0 xs))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, " := 0"), true)
    testing.expect_value(t, strings.contains(output, "add_index(kvist_xform_"), true)
    testing.expect_value(t, strings.contains(output, " += 1"), true)
    testing.expect_value(t, strings.contains(output, "kvist_acc +="), true)
}

@(test)
compile_functional_transform_inline_fn_callbacks :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn keep-large [x: int] -> [value: int, ok: bool]
  (if (> x 10)
    (return x true)
    (return 0 false)))

(defn collect [xs: []int] -> [dynamic]int
  (let [limit 2
        offset 1]
    (into [dynamic]int
      (comp
        (filter (fn [x: int] -> bool (> x limit)))
        (map (fn [x: int] -> int (+ x offset))))
      xs)))

(defn append [out: [dynamic]int, xs: []int]
  (let [limit 2]
    (arr.into! out
      (filter (fn [x: int] -> bool (> x limit)))
      xs)))

(defn total [xs: []int] -> int
  (let [limit 2
        offset 1]
    (transduce
      (comp
        (filter (fn [x: int] -> bool (> x limit)))
        (map (fn [x: int] -> int (+ x offset))))
      + 0 xs)))

(defn weighted-total [xs: []int] -> int
  (let [scale 3]
    (transduce
      (filter (fn [x: int] -> bool (> x 1)))
      (fn [acc: int, x: int] -> int (+ acc (* x scale)))
      0 xs)))

(defn indexed-total [xs: []int] -> int
  (let [offset 10]
    (transduce
      (map-indexed (fn [i: int, x: int] -> int (+ i x offset)))
      + 0 xs)))

(defn kept [xs: []int] -> [dynamic]int
  (into [dynamic]int
    (keep (fn [x: int] -> [value: int, ok: bool]
            (if (> x 10)
              (return x true)
              (return 0 false))))
    xs))

(defn loop-total [xs: []int] -> int
  (let [limit 2
        total 0]
    (for [x xs :transform (filter (fn [x: int] -> bool (> x limit)))]
      (set! total (+ total x)))
    total))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

	testing.expect_value(t, strings.contains(output, "proc(limit: int, x: int) -> bool"), true)
	testing.expect_value(t, strings.contains(output, "proc(offset: int, x: int) -> int"), true)
	testing.expect_value(t, strings.contains(output, "proc(scale: int, acc: int, x: int) -> int"), true)
	testing.expect_value(t, strings.contains(output, "proc(offset: int, i: int, x: int) -> int"), true)
    testing.expect_value(t, strings.contains(output, "-> (value: int, ok: bool)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_acc +="), true)
    testing.expect_value(t, strings.contains(output, "append(kvist_out, kvist_item)"), true)
    testing.expect_value(t, strings.contains(output, "append(&kvist_out, kvist_xform_"), true)
}

@(test)
compile_defiter_transform_inline_fn_callbacks :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Num_Source [
  xs: []int
  idx: int
])

(defn next-num [src: ^Num_Source] -> [value: int ok: bool]
  (if (< src.idx (count src.xs))
    (let [value src.xs[src.idx]]
      (set! src.idx (+ src.idx 1))
      (return value true))
    (return 0 false)))

(defiter nums [xs: []int] -> Num_Source :yield int
  :next next-num
  (Num_Source :xs xs :idx 0))

(defn total [xs: []int] -> int
  (let [limit 2
        offset 1]
    (transduce
      (comp
        (filter (fn [x: int] -> bool (> x limit)))
        (map (fn [x: int] -> int (+ x offset))))
      + 0
      (nums xs))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "(proc(limit: int, offset: int, kvist_source_arg_1: []int, kvist_init: int) -> int"), true)
    testing.expect_value(t, strings.contains(output, "proc(limit: int, x: int) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "proc(offset: int, x: int) -> int"), true)
    testing.expect_value(t, strings.contains(output, "next_num(&kvist_source)"), true)
}

@(test)
compile_functional_transform_map_value_sources :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn positive? [x: int] -> bool
  (> x 0))

(defn inc [x: int] -> int
  (+ x 1))

(deftransform positive-increments
  (filter positive?)
  (map inc))

(defn collect [lookup: map[string]int] -> [dynamic]int
  (into [dynamic]int positive-increments lookup))

(defn append-values [out: [dynamic]int, lookup: map[string]int]
  (arr.into! out positive-increments lookup))

(defn total [lookup: map[string]int] -> int
  (transduce positive-increments + 0 lookup))

(defn loop-total [lookup: map[string]int] -> int
  (let [total 0]
    (for [value lookup :transform positive-increments]
      (set! total (+ total value)))
    total))

(defn loop-key-total [lookup: map[string]int] -> int
  (let [total 0]
    (for [key value lookup :transform positive-increments]
      (set! total (+ total (count key)))
      (set! total (+ total value)))
    total))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "for _, kvist_item in kvist_source {"), true)
    testing.expect_value(t, strings.contains(output, "for _, kvist_item in lookup {"), true)
    testing.expect_value(t, strings.contains(output, "for key, kvist_item in lookup {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_acc +="), true)
    testing.expect_value(t, strings.contains(output, "append(&kvist_out,"), true)
    testing.expect_value(t, strings.contains(output, "append(kvist_out,"), true)
}

@(test)
compile_functional_transform_map_entry_sources :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")
(import map "kvist:map")

(defn entry-score [entry: (map.entry string int)] -> int
  (+ (count entry.key) entry.value))

(defn keep-positive-entry? [entry: (map.entry string int)] -> bool
  (> entry.value 0))

(deftransform entry-scores
  (filter keep-positive-entry?)
  (map entry-score))

(defn collect [lookup: map[string]int] -> [dynamic]int
  (into [dynamic]int entry-scores (map.entries lookup)))

(defn bump-entry [entry: (map.entry string int)] -> (map.entry string int)
  ((map.entry string int) :key entry.key :value (+ entry.value 1)))

(defn collect-map [lookup: map[string]int] -> map[string]int
  (into map[string]int
    (comp
      (filter keep-positive-entry?)
      (map bump-entry))
    (map.entries lookup)))

(defn collect-map-inline [lookup: map[string]int] -> map[string]int
  (into map[string]int
    (map (fn [entry: (map.entry string int)] -> (map.entry string int)
           ((map.entry string int) :key entry.key :value (+ entry.value 1))))
    (map.entries lookup)))

(defn collect-inferred-empty [] -> map[string]int
  (let [lookup (map.empty string int)]
    (defer (delete lookup))
    (map.assoc! lookup "a" 1)
    (into map[string]int (map bump-entry) (map.entries lookup))))

(defn collect-inferred-of [] -> map[string]int
  (let [lookup (map.of string int {"a" 1})]
    (defer (delete lookup))
    (into map[string]int (map bump-entry) (map.entries lookup))))

(defn append-values [out: [dynamic]int, lookup: map[string]int]
  (arr.into! out entry-scores (map.entries lookup)))

(defn total [lookup: map[string]int] -> int
  (transduce entry-scores + 0 (map.entries lookup)))

(defn loop-total [lookup: map[string]int] -> int
  (let [total 0]
    (for [entry (map.entries lookup) :transform entry-scores]
      (set! total (+ total entry)))
    total))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "import map__raw "), true)
    testing.expect_value(t, strings.contains(output, "entry_score :: proc(entry: map__raw.entry(string, int)) -> int"), true)
    testing.expect_value(t, strings.contains(output, "for key, value in kvist_source {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_item := map__raw.entry(string, int){key = key, value = value}"), true)
    testing.expect_value(t, strings.contains(output, "append(&kvist_out,"), true)
    testing.expect_value(t, strings.contains(output, "kvist_out[(kvist_xform_"), true)
    testing.expect_value(t, strings.contains(output, ").key] = (kvist_xform_"), true)
    testing.expect_value(t, strings.contains(output, ").value"), true)
    testing.expect_value(t, strings.contains(output, "kvist_out := make(map[string]int, len(kvist_source))"), true)
    testing.expect_value(t, strings.contains(output, "append(kvist_out,"), true)
    testing.expect_value(t, strings.contains(output, "kvist_acc +="), true)
    testing.expect_value(t, strings.contains(output, "kvist-prim-map-entries"), false)
}

@(test)
compile_functional_transform_min_max_reducers :: proc(t: ^testing.T) {
    source := `(package main)

(defn smallest [xs: []int] -> int
  (transduce (filter (fn [x: int] -> bool (> x 0))) min 999 xs))

(defn largest [xs: []int] -> int
  (transduce (filter (fn [x: int] -> bool (> x 0))) max 0 xs))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "if kvist_item < kvist_acc { kvist_acc = kvist_item }"), true)
    testing.expect_value(t, strings.contains(output, "if kvist_item > kvist_acc { kvist_acc = kvist_item }"), true)
}

@(test)
compile_functional_transform_reduced_reducer :: proc(t: ^testing.T) {
    source := `(package main)

(defn stop-at [xs: []int] -> int
  (transduce (filter (fn [x: int] -> bool (> x 0)))
    (fn [sum: int, x: int] -> int
      (if (> (+ sum x) 10)
        (reduced (+ sum x))
        (+ sum x)))
    0 xs))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "sum := kvist_acc"), true)
    testing.expect_value(t, strings.contains(output, "x := kvist_item"), true)
    testing.expect_value(t, strings.contains(output, "if ((sum) + (x)) > (10) { kvist_acc = (sum) + (x); break } else { kvist_acc = (sum) + (x) }"), true)
}

@(test)
compile_functional_transform_reduced_reducer_let :: proc(t: ^testing.T) {
    source := `(package main)

(defn stop-at [xs: []int] -> int
  (transduce (filter (fn [x: int] -> bool (> x 0)))
    (fn [sum: int, x: int] -> int
      (let [next (+ sum x)]
        (if (> next 10)
          (reduced next)
          next)))
    0 xs))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "next := (sum) + (x)"), true)
    testing.expect_value(t, strings.contains(output, "if (next) > (10) { kvist_acc = next; break } else { kvist_acc = next }"), true)
}

@(test)
compile_functional_transform_into_set :: proc(t: ^testing.T) {
    source := `(package main)

(defn even? [x: int] -> bool
  (= (% x 2) 0))

(defn collect [xs: []int] -> (map int (struct []))
  (into (map int (struct [])) (filter even?) xs))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "collect :: proc(xs: []int) -> map[int]struct{} {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_out := make(map[int]struct{}, len(kvist_source))"), true)
    testing.expect_value(t, strings.contains(output, "kvist_out[kvist_item] = struct{}{}"), true)
}

@(test)
compile_functional_transform_arr_range_sources :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn even? [x: int] -> bool
  (= (% x 2) 0))

(defn inc [x: int] -> int
  (+ x 1))

(deftransform even-increments
  (filter even?)
  (map inc))

(defn collect [] -> [dynamic]int
  (into [dynamic]int even-increments (arr.range 0 6)))

(defn append-values [out: [dynamic]int]
  (arr.into! out even-increments (arr.range 0 6 2)))

(defn total [] -> int
  (transduce even-increments + 0 (arr.range 6)))

(defn loop-total [] -> int
  (let [total 0]
    (for [value (arr.range 5 -1 -2) :transform even-increments]
      (set! total (+ total value)))
    total))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "arr__range_impl"), true)
    testing.expect_value(t, strings.contains(output, "arr__range_impl(0, 6, 1)"), false)
    testing.expect_value(t, strings.contains(output, "arr__range_next(&kvist_source"), true)
    testing.expect_value(t, strings.contains(output, "kvist_acc +="), true)
}

@(test)
compile_for_over_arr_range_uses_source_defined_iterator :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn total [n: int] -> int
  (let [sum 0]
    (for [i (arr.range 0 n)]
      (set! sum (+ sum i)))
    sum))

(defn indexed-total [] -> int
  (let [sum 0]
    (for [value idx (arr.range 2 8 2)]
      (set! sum (+ sum idx value)))
    (for [_ (arr.range 0 2)]
      (set! sum (+ sum 1)))
    (for [_ (arr.range 0 2)]
      (set! sum (+ sum 1)))
    sum))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "defer delete(kvist_loop_"), false)
    testing.expect_value(t, strings.contains(output, "arr__range_impl(0, n, 1)"), true)
    testing.expect_value(t, strings.contains(output, "arr__range_next(&kvist_source_"), true)
    testing.expect_value(t, strings.contains(output, "value, kvist_source_ok_"), true)
    testing.expect_value(t, strings.contains(output, "kvist_loop_source_index_"), true)
    testing.expect_value(t, strings.contains(output, "idx := kvist_loop_source_index_"), true)
    testing.expect_value(t, strings.contains(output, "_ = _"), false)
    testing.expect_value(t, strings.contains(output, "_ := "), false)
    testing.expect_value(t, strings.contains(output, "kvist_loop_source_index_"), true)
}

@(test)
compile_for_over_arr_repeat_uses_source_defined_iterator :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn total [] -> int
  (let [sum 0]
    (for [value (arr.repeat 3 4)]
      (set! sum (+ sum value)))
    sum))

(defn indexed-total [] -> int
  (let [sum 0]
    (for [value idx (arr.repeat 2 5)]
      (set! sum (+ sum idx value)))
    sum))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "arr__repeat_impl(3, 4)"), true)
    testing.expect_value(t, strings.contains(output, "arr__repeat_impl(2, 5)"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_loop_"), false)
    testing.expect_value(t, strings.contains(output, "arr__repeat_next(&kvist_source_"), true)
    testing.expect_value(t, strings.contains(output, "value, kvist_source_ok_"), true)
    testing.expect_value(t, strings.contains(output, "idx := kvist_loop_source_index_"), true)
    testing.expect_value(t, strings.contains(output, "kvist_loop_source_index_"), true)
}

@(test)
compile_for_over_arr_repeatedly_uses_source_defined_iterator :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn next-value [] -> int
  7)

(defn total [] -> int
  (let [sum 0]
    (for [value (arr.repeatedly 3 next-value)]
      (set! sum (+ sum value)))
    sum))

(defn indexed-total [] -> int
  (let [sum 0]
    (for [value idx (arr.repeatedly 2 next-value)]
      (set! sum (+ sum idx value)))
    sum))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "arr__repeatedly(3, next_value)"), false)
    testing.expect_value(t, strings.contains(output, "arr__repeatedly(2, next_value)"), false)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_loop_"), false)
    testing.expect_value(t, strings.contains(output, "arr__repeatedly_impl(3, next_value)"), true)
    testing.expect_value(t, strings.contains(output, "arr__repeatedly_impl(2, next_value)"), true)
    testing.expect_value(t, strings.contains(output, "arr__repeatedly_next(&kvist_source_"), true)
    testing.expect_value(t, strings.contains(output, "value, kvist_source_ok_"), true)
    testing.expect_value(t, strings.contains(output, "idx := kvist_loop_source_index_"), true)
}

@(test)
compile_for_over_arr_iterate_uses_source_defined_iterator :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn double [x: int] -> int
  (* x 2))

(defn total [] -> int
  (let [sum 0]
    (for [value (arr.iterate 4 double 1)]
      (set! sum (+ sum value)))
    sum))

(defn indexed-total [] -> int
  (let [sum 0]
    (for [value idx (arr.iterate 3 double 1)]
      (set! sum (+ sum idx value)))
    sum))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "arr__iterate(4, double, 1)"), false)
    testing.expect_value(t, strings.contains(output, "arr__iterate(3, double, 1)"), false)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_loop_"), false)
    testing.expect_value(t, strings.contains(output, "arr__iterate_impl(4, double, 1)"), true)
    testing.expect_value(t, strings.contains(output, "arr__iterate_impl(3, double, 1)"), true)
    testing.expect_value(t, strings.contains(output, "arr__iterate_next(&kvist_source_"), true)
    testing.expect_value(t, strings.contains(output, "value, kvist_source_ok_"), true)
    testing.expect_value(t, strings.contains(output, "idx := kvist_loop_source_index_"), true)
}

@(test)
compile_for_over_arr_cycle_uses_source_defined_iterator :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn total [] -> int
  (let [sum 0
        xs ([]int [1 2])]
    (for [value (arr.cycle 5 xs)]
      (set! sum (+ sum value)))
    sum))

(defn indexed-total [] -> int
  (let [sum 0
        xs ([]int [3 4])]
    (for [value idx (arr.cycle 3 xs)]
      (set! sum (+ sum idx value)))
    sum))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "arr__cycle(5, xs)"), false)
    testing.expect_value(t, strings.contains(output, "arr__cycle(3, xs)"), false)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_loop_"), false)
    testing.expect_value(t, strings.contains(output, "arr__cycle_impl(5, xs)"), true)
    testing.expect_value(t, strings.contains(output, "arr__cycle_impl(3, xs)"), true)
    testing.expect_value(t, strings.contains(output, "arr__cycle_next(&kvist_source_"), true)
    testing.expect_value(t, strings.contains(output, "value, kvist_source_ok_"), true)
    testing.expect_value(t, strings.contains(output, "idx := kvist_loop_source_index_"), true)
}

@(test)
compile_for_over_arr_take_nth_uses_source_defined_iterator :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn total [xs: []int] -> int
  (let [sum 0]
    (for [value (arr.take-nth 2 xs)]
      (set! sum (+ sum value)))
    sum))

(defn indexed-total [xs: []int] -> int
  (let [sum 0]
    (for [value idx (arr.take-nth 3 xs)]
      (set! sum (+ sum idx value)))
    sum))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "arr__take_nth(2, xs)"), false)
    testing.expect_value(t, strings.contains(output, "arr__take_nth(3, xs)"), false)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_loop_"), false)
    testing.expect_value(t, strings.contains(output, "arr__take_nth_impl(2, xs)"), true)
    testing.expect_value(t, strings.contains(output, "arr__take_nth_impl(3, xs)"), true)
    testing.expect_value(t, strings.contains(output, "arr__take_nth_next(&kvist_source_"), true)
    testing.expect_value(t, strings.contains(output, "value, kvist_source_ok_"), true)
    testing.expect_value(t, strings.contains(output, "idx := kvist_loop_source_index_"), true)
}

@(test)
compile_functional_transform_arr_repeat_sources :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn positive? [x: int] -> bool
  (> x 0))

(defn inc [x: int] -> int
  (+ x 1))

(deftransform positive-increments
  (filter positive?)
  (map inc))

(defn collect [] -> [dynamic]int
  (into [dynamic]int positive-increments (arr.repeat 3 4)))

(defn append-values [out: [dynamic]int]
  (arr.into! out positive-increments (arr.repeat 2 4)))

(defn total [] -> int
  (transduce positive-increments + 0 (arr.repeat 3 4)))

(defn loop-total [] -> int
  (let [total 0]
    (for [value (arr.repeat 3 4) :transform positive-increments]
      (set! total (+ total value)))
    total))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "arr__repeat_impl"), true)
    testing.expect_value(t, strings.contains(output, "arr__repeat_next(&kvist_source"), true)
    testing.expect_value(t, strings.contains(output, "kvist_source_arg_2: $T"), false)
    testing.expect_value(t, strings.contains(output, "(proc(kvist_source_arg_1: int, kvist_source_arg_2: int, kvist_init: int) -> int"), true)
    testing.expect_value(t, strings.contains(output, "kvist_out := make([dynamic]int)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_acc +="), true)
}

@(test)
compile_functional_transform_mapcat :: proc(t: ^testing.T) {
    source := `(package main)

(defn pair [x: int] -> [2]int
  ([2]int [x (+ x 1)]))

(deftransform pairs
  (mapcat pair))

(defn total [xs: []int] -> int
  (transduce pairs + 0 xs))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "pair(kvist_item)"), true)
    testing.expect_value(t, strings.contains(output, "for kvist_xform_"), true)
    testing.expect_value(t, strings.contains(output, "kvist_acc +="), true)
}

@(test)
compile_for_functional_transform :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn even? [x: int] -> bool
  (= (% x 2) 0))

(deftransform inc-evens
  (map inc)
  (filter even?))

(defn total [xs: []int] -> int
  (let [sum 0]
    (for [value xs :transform inc-evens]
      (set! sum (+ sum value)))
    (for [idx value xs :transform inc-evens]
      (set! sum (+ sum idx value)))
    sum))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "for kvist_item in xs {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_xform_"), true)
    testing.expect_value(t, strings.contains(output, "value := kvist_xform_"), true)
    testing.expect_value(t, strings.contains(output, "sum = (sum) + (value)"), true)
    testing.expect_value(t, strings.contains(output, "idx := 0"), true)
    testing.expect_value(t, strings.contains(output, "sum = (sum) + (idx) + (value)"), true)
    testing.expect_value(t, strings.contains(output, "idx += 1"), true)
}

@(test)
compile_functional_transform_single_step_named_spec :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(deftransform increments
  (map inc))

(defn values [xs: []int] -> [dynamic]int
  (into [dynamic]int increments xs))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_xform_"), true)
    testing.expect_value(t, strings.contains(output, "append(&kvist_out"), true)
}

@(test)
compile_contextual_single_step_transforms :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn inc [x: int] -> int
  (+ x 1))

(defn even? [x: int] -> bool
  (= (% x 2) 0))

(defn collect [xs: []int] -> [dynamic]int
  (into [dynamic]int (map inc) xs))

(defn append [out: [dynamic]int, xs: []int]
  (arr.into! out (filter even?) xs))

(defn total [xs: []int] -> int
  (transduce (map inc) + 0 xs))

(defn loop-total [xs: []int] -> int
  (let [sum 0]
    (for [value xs :transform (filter even?)]
      (set! sum (+ sum value)))
    sum))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "append(&kvist_out, kvist_xform_"), true)
    testing.expect_value(t, strings.contains(output, "append(kvist_out, kvist_item)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_acc +="), true)
    testing.expect_value(t, strings.contains(output, "if even_p(kvist_item) {"), true)
    testing.expect_value(t, strings.contains(output, "map ::"), false)
    testing.expect_value(t, strings.contains(output, "filter ::"), false)
}

@(test)
reject_transform_step_as_runtime_value :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn bad []
  (let [xf (map inc)]
    (return)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, strings.contains(err.message, "map"), true)
}

@(test)
reject_functional_transform_unknown_step :: proc(t: ^testing.T) {
    source := `(package main)

(defn values [xs: []int] -> [dynamic]int
  (into [dynamic]int
    (comp
      (partition 2))
    xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "transform steps currently support map, map-indexed, mapcat, filter, remove, keep, take, take-while, drop, drop-while, distinct, and distinct-by")
}

@(test)
reject_named_functional_transform_unknown_step_when_used :: proc(t: ^testing.T) {
    declaration_only_source := `(package main)

(deftransform bad-transform
  (comp
    (partition 2)))`

    declaration_output, declaration_err, declaration_ok := kvist.compile_source(declaration_only_source)
    testing.expect_value(t, declaration_ok, true)
    if !declaration_ok {
        testing.expect_value(t, declaration_err.message, "")
        return
    }
    defer delete(declaration_output)

    source := `(package main)

(deftransform bad-transform
  (comp
    (partition 2)))

(defn values [xs: []int] -> [dynamic]int
  (into [dynamic]int bad-transform xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "transform steps currently support map, map-indexed, mapcat, filter, remove, keep, take, take-while, drop, drop-while, distinct, and distinct-by")
}

@(test)
reject_generated_shaped_functional_transform_step :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn values [xs: []int] -> [dynamic]int
  (into [dynamic]int
    (comp
      (arr__map inc))
    xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "transform steps currently support map, map-indexed, mapcat, filter, remove, keep, take, take-while, drop, drop-while, distinct, and distinct-by")
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

    testing.expect_value(t, err.message, "transduce reducer must be +, a known two-argument function, or a fn literal: *")
}

@(test)
reject_functional_transform_inline_fn_missing_return :: proc(t: ^testing.T) {
    source := `(package main)

(defn values [xs: []int] -> [dynamic]int
  (into [dynamic]int
    (filter (fn [x: int] (> x 0)))
    xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "transform fn callback requires an explicit single return type")
}

@(test)
reject_functional_transform_inline_map_indexed_arity :: proc(t: ^testing.T) {
    source := `(package main)

(defn total [xs: []int] -> int
  (transduce
    (map-indexed (fn [x: int] -> int x))
    + 0 xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "map-indexed transform fn callback expects 2 parameters")
}

@(test)
reject_functional_transform_inline_reducer_arity :: proc(t: ^testing.T) {
    source := `(package main)

(defn total [xs: []int] -> int
  (transduce
    (map (fn [x: int] -> int x))
    (fn [x: int] -> int x)
    0 xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "transduce fn reducer expects 2 parameters")
}

@(test)
reject_functional_transform_inline_reducer_missing_return :: proc(t: ^testing.T) {
    source := `(package main)

(defn total [xs: []int] -> int
  (transduce
    (map (fn [x: int] -> int x))
    (fn [acc: int, x: int] (+ acc x))
    0 xs))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "transduce fn reducer requires an explicit single return type")
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

    testing.expect_value(t, err.message, "into transform output value type is int, but pipeline produces string")
}

@(test)
warn_discarded_transform_into_result_from_output_type :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(deftransform increments
  (map inc))

(defn main [xs: []int]
  (into [dynamic]int increments xs)
  (return))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, strings.contains(result.output, "append(&kvist_out"), true)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from into is discarded; bind it, delete it, or return it")
    }
}

@(test)
compile_case_stmt_with_keyword_subject_uses_source_conditionals :: proc(t: ^testing.T) {
    source := `(package main)

(defn rank [state: keyword] -> int
  (case state
    :queued 0
    :done 1
    -1))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "rank :: proc(state: keyword) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "== (keyword(\":queued\"))"), true)
    testing.expect_value(t, strings.contains(output, "== (keyword(\":done\"))"), true)
    testing.expect_value(t, strings.contains(output, "return -1"), true)
    testing.expect_value(t, strings.contains(output, "switch state"), false)
}

@(test)
compile_case_stmt_with_int_subject_uses_source_conditionals :: proc(t: ^testing.T) {
    source := `(package main)

(defn slot-value [slot: int] -> int
  (case slot
    0 10
    1 20
    0))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "slot_value :: proc(slot: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "== (0)"), true)
    testing.expect_value(t, strings.contains(output, "== (1)"), true)
    testing.expect_value(t, strings.contains(output, "return 0"), true)
    testing.expect_value(t, strings.contains(output, "switch slot"), false)
}

@(test)
compile_case_vector_clause_with_dynamic_array_subject_uses_source_equality :: proc(t: ^testing.T) {
    source := `(package main)

(defn score [xs: [dynamic]int] -> int
  (case xs
    [1 2] 1
    0))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "== ([dynamic]int{1, 2})"), true)
}

@(test)
compile_thread_first_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Method [
  Get
  Post
])

(defstruct Request [
  method: Method
  path: string
])

(defn method-name [method: Method] -> string
  (case method
    .Get "GET"
    "OTHER"))

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

    testing.expect_value(t, strings.contains(output, "Method :: enum {"), true)
    testing.expect_value(t, strings.contains(output, "Request :: struct {"), true)
    testing.expect_value(t, strings.contains(output, "method_name :: proc(method: Method) -> string {"), true)
    testing.expect_value(t, strings.contains(output, "== (.Get)"), true)
    testing.expect_value(t, strings.contains(output, "return \"OTHER\""), true)
    testing.expect_value(t, strings.contains(output, "describe :: proc(req: Request) -> string {"), true)
    testing.expect_value(t, strings.contains(output, "return method_name((req).method)"), true)
    testing.expect_value(t, strings.contains(output, "return clone_string((req).path, allocator)"), true)
    testing.expect_value(t, strings.contains(output, "#partial switch method"), false)
}

@(test)
compile_cond_thread_exprs :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Request [
  content-type: keyword
  authenticated?: bool
  trace-id: int
])

(defn add-trace [req: Request, trace-id: int] -> Request
  (assoc req.trace-id trace-id))

(defn refine [req: Request, json?: bool, auth?: bool, trace?: bool] -> Request
  (cond-> req
    json? (assoc .content-type :json)
    auth? (assoc .authenticated? true)
    trace? (update .trace-id + 10)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "refine :: proc(req: Request, json_p, auth_p, trace_p: bool) -> Request"), true)
    testing.expect_value(t, strings.contains(output, "kvist_cond_thread_"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_cond_thread_"), true)
    testing.expect_value(t, strings.contains(output, "if json_p"), true)
    testing.expect_value(t, strings.contains(output, "content_type = kvist_value"), true)
    testing.expect_value(t, strings.contains(output, "authenticated_p = kvist_value"), true)
    testing.expect_value(t, strings.contains(output, "trace_id = (kvist_target.trace_id) + (kvist_arg_0)"), true)
}

@(test)
compile_as_thread_exprs :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Profile [
  visits: int
])

(defstruct User [
  profile: Profile
  age: int
])

(defn visit [user: User] -> User
  (update user.profile.visits + 1))

(defn attach-bonus [bonus: int, user: User] -> User
  (update user.age + bonus))

(defn score [user: User, bonus: int] -> int
  (as-> user x
    (visit x)
    (attach-bonus bonus x)
    (+ x.age x.profile.visits)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "score :: proc(user: User, bonus: int) -> int"), true)
    testing.expect_value(t, strings.contains(output, "(proc(user: User, bonus: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, "visit(kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, "attach_bonus(bonus, kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, ".age) + (kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, "return kvist_thread_"), true)
}

@(test)
reject_distinct_transform_for_native_items :: proc(t: ^testing.T) {
    source := `(package main)

(defn collect [values: []int] -> [dynamic]int
  (into [dynamic]int (distinct) values))`

    _, err, ok := kvist.compile_source(source)
    defer delete(err.message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "distinct transform currently expects Data items, got int")
}

@(test)
reject_distinct_transform_argument :: proc(t: ^testing.T) {
    source := `(package main)

(deftransform invalid
  (distinct identity))`

    _, err, ok := kvist.compile_source(source)
    defer delete(err.message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "distinct transform step expects no arguments")
}

@(test)
compile_arr_sort_by_named_callbacks_are_source_owned :: proc(t: ^testing.T) {
    source := "(package main)\n(import arr \"kvist:arr\")\n\n(defn identity [x: int] -> int x)\n\n(defn demo [xs: [dynamic]int] -> int\n  (let [sorted (arr.sort-by identity xs) :defer]\n    (arr.sort-by! identity xs)\n    (+ (arr.last sorted) (arr.last xs))))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "sorted := arr__sort_by_impl(identity,"), true)
    testing.expect_value(t, strings.contains(output, "arr__sort_by_bang_impl(identity,"), true)
    testing.expect_value(t, strings.contains(output, "arr__Sort_By_Item :: struct($K: typeid, $T: typeid) {key: K, value: T}"), true)
    testing.expect_value(t, strings.contains(output, "arr__sort_by_items_bang((items)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sort_by_callback_identity"), false)
    testing.expect_value(t, strings.contains(output, "kvist_sort_by_in_place_callback_identity"), false)
    testing.expect_value(t, strings.contains(output, "kvist_sort_by :: proc"), false)
    testing.expect_value(t, strings.contains(output, "kvist_sort_by_in_place :: proc"), false)
}
