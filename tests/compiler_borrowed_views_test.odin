package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

@(test)
compile_direct_dynamic_array_expr_borrows_as_slice_argument :: proc(t: ^testing.T) {
    source := `(package main)

(defn total [xs: []int] -> int
  (count xs))

(defn demo [] -> int
  (total ([dynamic]int [1 2 3])))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_thread_1 := [dynamic]int{1, 2, 3}"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "return total(kvist_thread_1)"), true)
}

@(test)
compile_dynamic_array_local_borrows_as_slice_argument :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Order {
  amount: int
})

(defn total [orders: []Order] -> int
  (let [sum 0]
    (for [order orders]
      (mut! sum += order.amount))
    sum))

(defn main []
  (let [orders [(Order {amount: 120})
                (Order {amount: 80})] :defer]
    (println (total orders))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "orders := [dynamic]Order{Order{amount = 120}, Order{amount = 80}}"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(orders)"), true)
    testing.expect_value(t, strings.contains(output, "fmt.println(total((orders)[:]))"), true)
}

@(test)
reject_returning_threaded_view_of_owned_intermediate :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

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
    testing.expect_value(t, err.message, "cannot return a borrowed view that depends on an owned intermediate; return an owned result or keep the pipeline local")
}

@(test)
warn_third_party_odin_string_alias_owned_and_borrowed_results :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-odin-string-alias-*", context.allocator)
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
(import s "core:strings")

(defn lower-copy [value: string] -> string #force_inline
  (s.to_lower value))

(defn trim-view [value: string] -> string #force_inline
  (s.trim_space value))`
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

(defn main [value: string]
  (support.lower-copy value)
  (let [view (support.trim-view value) :defer]
    (println view))
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

    testing.expect_value(t, strings.contains(result.output, "support__lower_copy :: #force_inline proc(value: string) -> string"), true)
    testing.expect_value(t, strings.contains(result.output, "return s.to_lower(value)"), true)
    testing.expect_value(t, strings.contains(result.output, "support__trim_view :: #force_inline proc(value: string) -> string"), true)
    testing.expect_value(t, strings.contains(result.output, "return s.trim_space(value)"), true)
    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, strings.contains(result.output, "#borrowed"), false)
    testing.expect_value(t, len(result.warnings), 2)
    if len(result.warnings) == 2 {
        testing.expect_value(t, result.warnings[0].message, "owned result from support.lower-copy is discarded; bind it, delete it, or return it")
        testing.expect_value(t, result.warnings[1].message, "support.trim-view returns a borrowed view; do not delete it, delete the owner instead")
    }
}

@(test)
compile_does_not_keep_borrowed_local_after_owned_reassignment :: proc(t: ^testing.T) {
    source := `(package main)
(import strings "core:strings")

(defn lower-after-view [s: string] -> string
  (let [view (strings.trim_space s)]
    (set! view (strings.to_lower view))
    view))

(defn main [s: string]
  (let [owned (lower-after-view s) :defer]
    (println owned)))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, strings.contains(result.output, "#borrowed"), false)
    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_warns_for_borrowed_value_escaping_owner :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn bad-view [] -> []int
  (let [xs (arr.range 0 10) :defer]
    (arr.slice xs 0 3)))`

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
        testing.expect_value(t, result.warnings[0].message, "borrowed value escapes owner xs")
    }
}

@(test)
compile_warns_for_bound_borrowed_value_escaping_owner :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn bad-view [] -> []int
  (let [xs (arr.range 0 10) :defer
        view (arr.slice xs 0 3)]
    view))`

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
        testing.expect_value(t, result.warnings[0].message, "borrowed value escapes owner xs")
    }
}

@(test)
compile_warns_for_borrowed_value_escaping_in_returned_composite :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defstruct ViewBox {
  view: []int
})

(defn bad-view [] -> ViewBox
  (let [xs (arr.range 0 10) :defer
        view (arr.slice xs 0 3)]
    (ViewBox {view: view})))`

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
        testing.expect_value(t, result.warnings[0].message, "borrowed value escapes owner xs")
    }
}

@(test)
compile_warns_for_third_party_conditional_borrowed_assignment_escaping_owner :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-borrowed-escape-branch-set-*", context.allocator)
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

(defn left [xs: []int] -> []int #force_inline
  (slice xs 0 2))

(defn right [xs: []int] -> []int #force_inline
  (slice xs 1 3))`
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
(import arr "kvist:arr")
(import support "support")

(defn bad-view [flag?: bool] -> []int
  (let [xs (arr.range 0 10) :defer
        view: []int ([]int [])]
    (if flag?
      (set! view (support.left xs))
      (set! view (support.right xs)))
    view))`
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

    testing.expect_value(t, strings.contains(result.output, "support__left :: #force_inline proc(xs: []int) -> []int"), true)
    testing.expect_value(t, strings.contains(result.output, "support__right :: #force_inline proc(xs: []int) -> []int"), true)
    testing.expect_value(t, strings.contains(result.output, "#borrowed"), false)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "borrowed value escapes owner xs")
    }
}

@(test)
compile_warns_for_third_party_type_case_borrowed_assignment_escaping_owner :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-borrowed-escape-type-case-set-*", context.allocator)
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

(defn left [xs: []int] -> []int #force_inline
  (slice xs 0 2))

(defn right [xs: []int] -> []int #force_inline
  (slice xs 1 3))`
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
(import arr "kvist:arr")
(import support "support")

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

(defn bad-view [event: Event] -> []int
  (let [xs (arr.range 0 10) :defer
        view: []int ([]int [])]
    (case event
      (Connected _) (set! view (support.left xs))
      (Disconnected _) (set! view (support.right xs))
      (set! view (support.left xs)))
    view))`
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

    testing.expect_value(t, strings.contains(result.output, "support__left :: #force_inline proc(xs: []int) -> []int"), true)
    testing.expect_value(t, strings.contains(result.output, "support__right :: #force_inline proc(xs: []int) -> []int"), true)
    testing.expect_value(t, strings.contains(result.output, "#borrowed"), false)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "borrowed value escapes owner xs")
    }
}

@(test)
compile_does_not_infer_owned_slice_for_borrowed_slice_return :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn tail [xs: []int] -> []int
  (core.slice xs 1))

(defn main [xs: []int]
  (tail xs)
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

    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
infer_owned_result_consuming_parameter_and_borrowed_result :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")
(import data "kvist:data")

(defn make-values [] -> [dynamic]int
  (arr.range 0 3))

(defn consume [values: [dynamic]int] -> int
  (let [result (count values)]
    (delete values)
    result))

(defn view [value: Data] -> Data
  value)

(defn demo [value: Data]
  (let [values (make-values)]
    (consume values)
    (view value)))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, strings.contains(result.output, "make_values :: proc() -> [dynamic]int"), true)
    testing.expect_value(t, strings.contains(result.output, "consume :: proc(values: [dynamic]int)"), true)
    testing.expect_value(t, strings.contains(result.output, "delete(values)"), true)
    testing.expect_value(t, len(result.warnings), 0)

    symbols, symbols_err, symbols_ok := kvist.symbols_source(source)
    testing.expect_value(t, symbols_ok, true)
    if symbols_ok {
        defer delete(symbols)
        testing.expect_value(t, strings.contains(symbols, "make-values\t"), true)
        testing.expect_value(t, strings.contains(symbols, "consumes=0"), true)
        testing.expect_value(t, strings.contains(symbols, "lifetime=result-borrowed"), true)
        testing.expect_value(t, strings.contains(symbols, "(owned "), false)
        testing.expect_value(t, strings.contains(symbols, "(borrowed "), false)
    } else {
        defer delete(symbols_err.message)
        testing.expect_value(t, symbols_err.message, "")
    }
}
