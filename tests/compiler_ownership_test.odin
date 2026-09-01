package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

@(test)
reject_shadowed_cleanup_for_outer_owned_let_binding :: proc(t: ^testing.T) {
    source := `(package main)
(import fmt "core:fmt")

(defn broken [] -> int
  (+ 1
     (let [label (fmt.aprintf "outer")]
       (let [label (fmt.aprintf "inner")]
         (delete label))
       2)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    delete(output)
    defer delete(err.message)
    testing.expect_value(
        t,
        err.message,
        "fmt.aprintf returns an owned result; bind it so it can be deleted, or return it to transfer ownership",
    )
}

@(test)
compile_outer_owned_let_cleanup_after_shadowed_scope :: proc(t: ^testing.T) {
    source := `(package main)
(import fmt "core:fmt")

(defn valid [] -> int
  (+ 1
     (let [label (fmt.aprintf "outer")]
       (discard
         (let [label (fmt.aprintf "inner") :defer]
           (count label)))
       (delete label)
       2)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.count(output, "delete(label)") >= 2, true)
}

@(test)
compile_owned_let_branch_case_in_return_position :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defenum Step-Kind [One Two])

(defstruct Step {
  kind: Step-Kind
})

(defn owned-from-case [step: Step] -> [dynamic]int
  (case step.kind
    .One
      (let [out (make [dynamic]int)]
        (arr.push! out 1)
        out)
    (let [out (make [dynamic]int)]
      (arr.push! out 2)
      out)))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings), 0)
    testing.expect_value(t, strings.contains(result.output, "kvist_owner^ = false; return kvist_value"), false)
}

@(test)
compile_owned_let_branch_mixed_with_owned_call_case :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defenum Step-Kind [One Two])

(defstruct Step {
  kind: Step-Kind
})

(defn make-one [] -> [dynamic]int
  (let [out (make [dynamic]int)]
    (arr.push! out 1)
    out))

(defn owned-from-mixed-case [step: Step] -> [dynamic]int
  (case step.kind
    .One
      (let [out (make [dynamic]int)]
        (arr.push! out 10)
        out)
    (make-one)))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings), 0)
    testing.expect_value(t, strings.contains(result.output, "kvist_owner^ = false; return kvist_value"), false)
    testing.expect_value(t, strings.contains(result.output, "return make_one()"), true)
}

@(test)
compile_rejects_removed_owned_struct_field_syntax :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Values {
  items: (owned []int)
})`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    delete(output)
    defer delete(err.message)
    testing.expect_value(
        t,
        err.message,
        "owned struct field types have been removed; field lifetimes are inferred from construction and decoding",
    )
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
compile_core_str_constructs_one_owned_formatted_string :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point {x: int y: int})

(defn render [path: string, point: Point] -> string
  (str "@get('" path "', {open: 100%}) " true " " 42 " " :ready " " point))

(defn empty [] -> string
  (str))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, strings.contains(result.output, `fmt.aprintf("%v%v%v%v%v%v%v%v%v%v"`), true)
    testing.expect_value(t, strings.contains(result.output, `"@get('"`), true)
    testing.expect_value(t, strings.contains(result.output, `"', {open: 100%}) "`), true)
    testing.expect_value(t, strings.contains(result.output, `fmt.aprintf("")`), true)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_with_allocator_scope :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (with-allocator [allocator context.temp_allocator]
    (let [buffer (make [dynamic]int)]
      (defer (delete buffer))
      (odin "append(&(buffer), ..[]int{1, 2})")
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
      (odin "append(&(buffer), ..[]int{1, 2})")
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
compile_with_allocator_expression_with_expected_type :: proc(t: ^testing.T) {
    source := `(package main)

(defn id [x: int] -> int
  x)

(defn demo [] -> int
  (let [value: int (with-allocator [allocator context.temp_allocator]
                     (id 42))]
    value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "value: int = (proc() -> int {"), true)
    testing.expect_value(t, strings.contains(output, "context.allocator = allocator"), true)
    testing.expect_value(t, strings.contains(output, "return id(42)"), true)
}

@(test)
compile_with_temp_allocator_expression_with_expected_type :: proc(t: ^testing.T) {
    source := `(package main)
(import runtime "base:runtime")

(defn id [x: int] -> int
  x)

(defn demo [] -> int
  (let [value: int (with-temp-allocator [allocator]
                     (id 42))]
    value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "value: int = (proc() -> int {"), true)
    testing.expect_value(t, strings.contains(output, "runtime.default_temp_allocator_temp_begin()"), true)
    testing.expect_value(t, strings.contains(output, "return id(42)"), true)
}

@(test)
reject_untyped_with_allocator_expression :: proc(t: ^testing.T) {
    source := `(package main)

(defn demo []
  (let [value (with-allocator [allocator context.temp_allocator]
                42)]
    value))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "with-allocator expression needs an expected type; add a let binding type or use it where the type is known")
}

@(test)
compile_final_with_allocator_uses_proc_return_type :: proc(t: ^testing.T) {
    source := `(package main)

(defn id [x: int] -> int
  x)

(defn demo [] -> int
  (with-allocator [allocator context.temp_allocator]
    (id 42)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "context.allocator = allocator"), true)
    testing.expect_value(t, strings.contains(output, "return id(42)"), true)
}

@(test)
compile_final_with_temp_allocator_uses_proc_return_type :: proc(t: ^testing.T) {
    source := `(package main)
(import runtime "base:runtime")

(defn id [x: int] -> int
  x)

(defn demo [] -> int
  (with-temp-allocator [allocator]
    (id 42)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "runtime.default_temp_allocator_temp_begin()"), true)
    testing.expect_value(t, strings.contains(output, "return id(42)"), true)
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
    testing.expect_value(t, strings.contains(output, "return len(xs)"), true)
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
compile_threaded_let_binding_keeps_owned_intermediates_alive :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

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

    testing.expect_value(t, strings.contains(output, "kvist_thread_1 := arr__filter_impl__kvist_field_0_active(type_of(((users)[0:])[0]), (users)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_2 := (kvist_thread_1)[0:]"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_3 := arr__map_impl__kvist_field_0_name(type_of((kvist_thread_2)[0]), type_of((kvist_thread_2)[0].name), kvist_thread_2)"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_3)"), true)
    testing.expect_value(t, strings.contains(output, "active_names := arr__take(1,"), true)
    testing.expect_value(t, strings.contains(output, "kvist_filter_field_active"), false)
    testing.expect_value(t, strings.contains(output, "kvist_map_field_name"), false)
}

@(test)
allow_returning_owned_sequence_result :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

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

    testing.expect_value(t, strings.contains(output, "return arr__map_impl(inc, (xs)[0:])"), true)
}

@(test)
warn_discarded_owned_sequence_result :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

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
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from arr.map is discarded; bind it, delete it, or return it")
    }
}

@(test)
warn_discarded_third_party_dynamic_array_result_from_alloc_shape :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-owned-return-package-*", context.allocator)
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
(import core "kvist:core")

(defn join [xs: []$T, ys: []T] -> [dynamic]T #force_inline
  (let [out (make [dynamic]T 0 (+ (core.count xs) (core.count ys)))]
    (for [x xs]
      (append (addr out) x))
    (for [y ys]
      (append (addr out) y))
    out))`
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
(import support "support")

(defn demo []
  (let [xs ([]int [1])
        ys ([]int [2])]
    (support.join xs ys)
    (return)))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    result, err, ok := kvist.compile_path_with_map(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, strings.contains(result.output, "support__join :: #force_inline proc(xs: []$T, ys: []T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, strings.contains(result.output, "support__join(xs, ys)"), true)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from support.join is discarded; bind it, delete it, or return it")
    }
}

@(test)
warn_discarded_third_party_named_owned_bytes_from_alloc_shape :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-owned-named-bytes-package-*", context.allocator)
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
(import ops "core:os")

(defn read-bytes [path: string] -> [data: []byte, err: ops.Error] #force_inline
  (ops.read_entire_file path context.allocator))`
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
(import support "support")

(defn main [path: string]
  (support.read-bytes path)
  (return))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    result, err, ok := kvist.compile_path_with_map(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, strings.contains(result.output, "support__read_bytes :: #force_inline proc(path: string) -> (data: []byte, err: ops.Error)"), true)
    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, strings.contains(result.output, "return ops.read_entire_file(path, context.allocator)"), true)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from support.read-bytes is discarded; bind it, delete it, or return it")
    }
}

@(test)
warn_discarded_third_party_destructured_owned_wrapper_result :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-owned-destructured-wrapper-*", context.allocator)
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
  (os.read_entire_file path context.allocator))

(defn read-wrapper [path: string] -> []byte #force_inline
  (let [[data err] (read-base path)]
    data))`
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
(import support "support")

(defn main [path: string]
  (support.read-wrapper path)
  (return))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    result, err, ok := kvist.compile_path_with_map(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, strings.contains(result.output, "support__read_base :: #force_inline proc(path: string) -> (data: []byte, err: os.Error)"), true)
    testing.expect_value(t, strings.contains(result.output, "support__read_wrapper :: #force_inline proc(path: string) -> []byte"), true)
    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from support.read-wrapper is discarded; bind it, delete it, or return it")
    }
}

@(test)
compile_direct_core_strings_result_without_owned_warning :: proc(t: ^testing.T) {
    source := `(package main)
(import strings "core:strings")

(defn main [s: string]
  (strings.clone s)
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

    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
warn_discarded_third_party_replaced_string_from_alloc_shape :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-owned-replace-*", context.allocator)
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
(import strings "core:strings")

(defn replace-all [s: string, old: string, new: string] -> string #force_inline
  (let [[out _] (strings.replace s old new -1)]
    out))`
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
(import support "support")

(defn main [s: string]
  (support.replace-all s "x" "y")
  (return))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    result, err, ok := kvist.compile_path_with_map(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, strings.contains(result.output, "support__replace_all :: #force_inline proc(s, old, new: string) -> string"), true)
    testing.expect_value(t, strings.contains(result.output, "out, _ := strings.replace(s, old, new, -1)"), true)
    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from support.replace-all is discarded; bind it, delete it, or return it")
    }
}

@(test)
reject_nested_owned_sequence_result :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

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
(import arr "kvist:arr")

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
  (let [xs (arr.empty int)]
    (println 1)))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned local xs is never deleted or returned; add (defer (delete xs)) or return it")
        testing.expect_value(t, result.warnings[0].code, kvist.Compile_Warning_Code.Ownership_Unreleased_Local)
        testing.expect_value(t, result.warnings[0].confidence, kvist.Compile_Warning_Confidence.Conservative)
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
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_tracks_owned_replacement_after_delete_and_set :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn demo []
  (let [xs (arr.empty int)
        replacement (arr.empty int)]
    (delete xs)
    (set! xs replacement)
    (println (count xs))
    (delete xs)))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
warn_discarded_third_party_split_slice_from_alloc_shape :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-owned-split-*", context.allocator)
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
(import strings "core:strings")

(defn split-words [s: string] -> []string #force_inline
  (strings.split s " "))`
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
(import support "support")

(defn main [s: string]
  (support.split-words s)
  (return))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    result, err, ok := kvist.compile_path_with_map(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, strings.contains(result.output, "support__split_words :: #force_inline proc(s: string) -> []string"), true)
    testing.expect_value(t, strings.contains(result.output, "return strings.split(s, \" \")"), true)
    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from support.split-words is discarded; bind it, delete it, or return it")
    }
}
