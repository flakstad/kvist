// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

@(test)
reject_defer_owned_let_branch_case_return :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Step-Kind [One Two])

(defstruct Step {
  kind: Step-Kind
})

(defn owned-from-case [step: Step] -> [dynamic]int
  (case step.kind
    .One
      (let [out (make [dynamic]int) :defer]
        (arr.push! out 1)
        out)
    (make [dynamic]int)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "defer-marked binding cannot be returned; remove defer or transfer ownership explicitly")
}

@(test)
compile_defer_with_resource_passed_to_owned_data_result :: proc(t: ^testing.T) {
    source := `(package main)

(defn close-handle [_handle: rawptr]
  (discard _handle))

(defn load-data [_handle: rawptr] -> Data
  [:status :ready])

(defn demo [] -> Data
  (let [handle (rawptr nil) :defer-with close-handle]
    (load-data handle)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        defer delete(err.message)
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "defer close_handle(handle)"), true)
}

@(test)
compile_defer_forms :: proc(t: ^testing.T) {
    source := `(package main)
(import fmt "core:fmt")

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

import fmt "core:fmt"

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
warn_defer_direct_odin_slice_view :: proc(t: ^testing.T) {
    source := `(package main)

(defn demo [xs: []int, s: string]
  (let [window (odin-slice xs) :defer
        suffix (odin-slice s 1) :defer]
    (println (count window) (count suffix))))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, strings.contains(result.output, "window := (xs)[:]"), true)
    testing.expect_value(t, strings.contains(result.output, "suffix := (s)[1:]"), true)
    testing.expect_value(t, len(result.warnings), 2)
    if len(result.warnings) == 2 {
        testing.expect_value(t, strings.contains(result.warnings[0].message, "borrowed view"), true)
        testing.expect_value(t, strings.contains(result.warnings[1].message, "borrowed view"), true)
    }
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
  (let [mapped (arr.map inc xs) :defer
        filtered (arr.filter even? mapped) :defer]
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
compile_let_or_break_err_binding_with_defer :: proc(t: ^testing.T) {
    source := `(package main)

(defn read-text [path: string] -> [data: [dynamic]byte, err: rawptr]
  (return ([dynamic]byte [1 2]) nil))

(defn load [path: string]
  (while true
    (let [[data err] (read-text path) :or-break :defer]
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
compile_let_binding_with_defer_with_cleanup :: proc(t: ^testing.T) {
    source := `(package main)

(defn close-buffer [data: [dynamic]byte]
  (delete data))

(defn load []
  (let [data ([dynamic]byte [1 2]) :defer-with close-buffer]
    (println (count data))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "defer close_buffer(data)"), true)
}

@(test)
compile_result_binding_with_defer_with_cleanup :: proc(t: ^testing.T) {
    source := `(package main)

(defn read-text [path: string] -> [data: [dynamic]byte, err: rawptr]
  (return ([dynamic]byte [1 2]) nil))

(defn close-buffer [data: [dynamic]byte]
  (delete data))

(defn load [path: string]
  (while true
    (let [[data err] (read-text path) :or-break :defer-with close-buffer]
      (println (count data)))
    (break)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "data, err := read_text(path)"), true)
    testing.expect_value(t, strings.contains(output, "defer close_buffer(data)"), true)
}

@(test)
compile_let_or_return_err_binding_with_errdefer :: proc(t: ^testing.T) {
    source := `(package main)

(defn read-text [path: string] -> [data: [dynamic]byte, err: rawptr]
  (return ([dynamic]byte [1 2]) nil))

(defvar fake-error-token: int 1)

(defn fake-error [] -> rawptr
  (transmute rawptr (addr fake-error-token)))

(defn load [path: string, fail: bool] -> [data: [dynamic]byte, err: rawptr]
  (let [[data err] (read-text path) :or-return :errdefer]
    (if fail
      (do
        (set! err (fake-error))
        (return)))
    (return data err)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "data, err = read_text(path)"), true)
    testing.expect_value(t, strings.contains(output, "defer {"), true)
    testing.expect_value(t, strings.contains(output, "if err != nil {"), true)
    testing.expect_value(t, strings.contains(output, "delete(data)"), true)
}

@(test)
reject_let_errdefer_without_or_return_err_binding :: proc(t: ^testing.T) {
    source := `(package main)

(defn next [] -> [value: int, ok: bool]
  (return 1 true))

(defn total [] -> [value: int, ok: bool]
  (let [[value ok] (next) :or-return :errdefer]
    (return value ok)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, ":errdefer is only supported on [value err] :or-return bindings")
}

@(test)
reject_let_errdefer_with_defer :: proc(t: ^testing.T) {
    source := `(package main)

(defn read-text [] -> [data: [dynamic]byte, err: rawptr]
  (return ([dynamic]byte [1 2]) nil))

(defn load [] -> [data: [dynamic]byte, err: rawptr]
  (let [[data err] (read-text) :or-return :defer :errdefer]
    (return data err)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "use only one cleanup marker: :defer, :errdefer, or :defer-with")
}

@(test)
reject_let_defer_with_without_cleanup :: proc(t: ^testing.T) {
    source := `(package main)

(defn load []
  (let [data ([dynamic]byte [1 2]) :defer-with]
    (println data)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, ":defer-with expects a cleanup function")
}

@(test)
reject_let_errdefer_outside_tail_position :: proc(t: ^testing.T) {
    source := `(package main)

(defn read-text [] -> [data: [dynamic]byte, err: rawptr]
  (return ([dynamic]byte [1 2]) nil))

(defn load [] -> [data: [dynamic]byte, err: rawptr]
  (let [[data err] (read-text) :or-return :errdefer]
    (println (count data)))
  (return data err))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, ":errdefer is only supported in tail-position let forms")
}

@(test)
compile_let_defer_final_if_scalar_use :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn total [flag: bool] -> int
  (let [xs ([dynamic]int [1 2]) :defer]
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
    testing.expect_value(t, strings.contains(output, "return len(xs)"), true)
}

@(test)
compile_let_defer_final_cond_scalar_use :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn total [n: int] -> int
  (let [xs ([dynamic]int [1 2]) :defer]
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
    testing.expect_value(t, strings.contains(output, "return len(xs)"), true)
}

@(test)
compile_let_defer_final_case_scalar_use :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn total [mode: int] -> int
  (let [xs ([dynamic]int [1 2]) :defer]
    (case mode
      0 0
      1 (count xs)
      2)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "defer delete(xs)"), true)
    testing.expect_value(t, strings.contains(output, "return len(xs)"), true)
}

@(test)
compile_let_defer_binding :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (let [xs ([dynamic]int [1 2]) :defer
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
  (let [xs ([dynamic]int [1 2]) :defer]
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
  (let [xs ([dynamic]int [1 2]) :defer]
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
  (let [xs ([dynamic]int [1 2]) :defer]
    (pass-through xs)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "defer-marked binding cannot be returned; remove defer or transfer ownership explicitly")
}

@(test)
compile_defer_binding_passed_as_borrowed_slice_to_copied_result :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defstruct Query {
  xs: [dynamic]int
})

(defstruct Result {
  query: Query
})

(defn copy-query [xs: []int] -> Query
  (let [out (make [dynamic]int)]
    (arr.into! out xs)
    (Query {xs: out})))

(defn ok [] -> Result
  (let [xs ([dynamic]int [1 2]) :defer]
    (Result {query: (copy-query (slice xs 0))})))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "defer delete(xs)"), true)
    testing.expect_value(t, strings.contains(output, "copy_query((xs)[0:])"), true)
}

@(test)
reject_returning_defer_binding_through_local_wrapper :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Box {
  xs: [dynamic]int
})

(defn owned [] -> Box
  (let [xs ([dynamic]int [1 2]) :defer
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
  (let [xs ([dynamic]int [1 2]) :defer
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
  (let [xs ([dynamic]int [1 2]) :defer
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
warn_defer_inside_loop_runs_at_surrounding_scope_exit :: proc(t: ^testing.T) {
    source := `(package main)

(defn main [xs: []int]
  (for [x xs]
    (defer (println x)))
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

    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "defer inside loop runs when the surrounding scope exits, not after each iteration; wrap the iteration body in block or clean up explicitly")
    }
}

@(test)
allow_defer_inside_loop_block_scope :: proc(t: ^testing.T) {
    source := `(package main)

(defn main [xs: []int]
  (for [x xs]
    (block
      (defer (println x))))
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
warn_defer_marked_borrowed_string_view :: proc(t: ^testing.T) {
    source := `(package main)
(import str "kvist:str")

(defn main [s: string]
  (let [trimmed (str.trim s) :defer]
    (println trimmed)))`

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
        testing.expect_value(t, result.warnings[0].message, "str.trim returns a borrowed view; do not delete it, delete the owner instead")
    }
}

@(test)
warn_defer_inferred_borrowed_odin_string_view_result :: proc(t: ^testing.T) {
    source := `(package main)
(import strings "core:strings")

(defn trim-view [s: string] -> string
  (strings.trim_space s))

(defn trim-cutset-view [s: string] -> string
  (strings.trim s " \t"))

(defn trim-prefix-view [s: string] -> string
  (strings.trim_prefix s "kvist."))

(defn trim-suffix-view [s: string] -> string
  (strings.trim_suffix s ".txt"))

(defn main [s: string]
  (let [trimmed (trim-view s) :defer
        trimmed-cutset (trim-cutset-view s) :defer
        without-prefix (trim-prefix-view s) :defer
        without-suffix (trim-suffix-view s) :defer]
    (println trimmed trimmed-cutset without-prefix without-suffix)))`

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
    testing.expect_value(t, len(result.warnings), 4)
    if len(result.warnings) == 4 {
        testing.expect_value(t, result.warnings[0].message, "trim-view returns a borrowed view; do not delete it, delete the owner instead")
        testing.expect_value(t, result.warnings[1].message, "trim-cutset-view returns a borrowed view; do not delete it, delete the owner instead")
        testing.expect_value(t, result.warnings[2].message, "trim-prefix-view returns a borrowed view; do not delete it, delete the owner instead")
        testing.expect_value(t, result.warnings[3].message, "trim-suffix-view returns a borrowed view; do not delete it, delete the owner instead")
    }
}

@(test)
warn_defer_third_party_borrowed_view_returned_through_local :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-borrowed-local-*", context.allocator)
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

(defn trim-local [s: string] -> string #force_inline
  (let [view (strings.trim_space s)]
    view))`
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
  (let [trimmed (support.trim-local s) :defer]
    (println trimmed)))`
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

    testing.expect_value(t, strings.contains(result.output, "support__trim_local :: #force_inline proc(s: string) -> string"), true)
    testing.expect_value(t, strings.contains(result.output, "view := strings.trim_space(s)"), true)
    testing.expect_value(t, strings.contains(result.output, "#borrowed"), false)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "support.trim-local returns a borrowed view; do not delete it, delete the owner instead")
    }
}

@(test)
warn_defer_third_party_borrowed_helper_returned_through_local :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-borrowed-helper-local-*", context.allocator)
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

(defn base-view [s: string] -> string #force_inline
  (strings.trim_space s))

(defn wrapper-view [s: string] -> string #force_inline
  (let [view (base-view s)]
    view))`
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
  (let [trimmed (support.wrapper-view s) :defer]
    (println trimmed)))`
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

    testing.expect_value(t, strings.contains(result.output, "support__base_view :: #force_inline proc(s: string) -> string"), true)
    testing.expect_value(t, strings.contains(result.output, "support__wrapper_view :: #force_inline proc(s: string) -> string"), true)
    testing.expect_value(t, strings.contains(result.output, "#borrowed"), false)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "support.wrapper-view returns a borrowed view; do not delete it, delete the owner instead")
    }
}

@(test)
warn_defer_third_party_named_return_assignment_borrowed_view :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-borrowed-named-set-*", context.allocator)
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

(defn named-view [s: string] -> [out: string, ok: bool] #force_inline
  (set! out (strings.trim_space s))
  (set! ok true)
  (return out ok))`
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
  (delete (support.named-view s)))`
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

    testing.expect_value(t, strings.contains(result.output, "support__named_view :: #force_inline proc(s: string) -> (out: string, ok: bool)"), true)
    testing.expect_value(t, strings.contains(result.output, "out = strings.trim_space(s)"), true)
    testing.expect_value(t, strings.contains(result.output, "#borrowed"), false)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "support.named-view returns a borrowed view; do not delete it, delete the owner instead")
    }
}

@(test)
warn_defer_third_party_conditional_assignment_borrowed_view :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-borrowed-branch-set-*", context.allocator)
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

(defn trim-choice [s: string prefix?: bool] -> string #force_inline
  (let [view ""]
    (if prefix?
      (set! view (strings.trim_prefix s "kvist."))
      (set! view (strings.trim_suffix s ".txt")))
    view))`
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
  (let [trimmed (support.trim-choice s true) :defer]
    (println trimmed)))`
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

    testing.expect_value(t, strings.contains(result.output, "support__trim_choice :: #force_inline proc(s: string, prefix_p: bool) -> string"), true)
    testing.expect_value(t, strings.contains(result.output, "view = strings.trim_prefix(s, \"kvist.\")"), true)
    testing.expect_value(t, strings.contains(result.output, "view = strings.trim_suffix(s, \".txt\")"), true)
    testing.expect_value(t, strings.contains(result.output, "#borrowed"), false)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "support.trim-choice returns a borrowed view; do not delete it, delete the owner instead")
    }
}

@(test)
warn_defer_third_party_type_case_assignment_borrowed_view :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-borrowed-type-case-set-*", context.allocator)
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

(defstruct Prefix {
  marker: string
})

(defstruct Suffix {
  marker: string
})

(defunion TrimMode {
  prefix: Prefix
  suffix: Suffix
})

(defn trim-mode [mode: TrimMode s: string] -> string #force_inline
  (let [view ""]
    (case mode
      (Prefix _) (set! view (strings.trim_prefix s "kvist."))
      (Suffix _) (set! view (strings.trim_suffix s ".txt"))
      (set! view (strings.trim_space s)))
    view))`
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

(defn main [mode: support.TrimMode s: string]
  (let [trimmed (support.trim-mode mode s) :defer]
    (println trimmed)))`
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

    testing.expect_value(t, strings.contains(result.output, "support__trim_mode :: #force_inline proc(mode: support__TrimMode, s: string) -> string"), true)
    testing.expect_value(t, strings.contains(result.output, "view = strings.trim_prefix(s, \"kvist.\")"), true)
    testing.expect_value(t, strings.contains(result.output, "view = strings.trim_suffix(s, \".txt\")"), true)
    testing.expect_value(t, strings.contains(result.output, "view = strings.trim_space(s)"), true)
    testing.expect_value(t, strings.contains(result.output, "#borrowed"), false)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "support.trim-mode returns a borrowed view; do not delete it, delete the owner instead")
    }
}

@(test)
warn_defer_third_party_destructured_borrowed_wrapper_result :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-borrowed-destructured-wrapper-*", context.allocator)
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

(defn trim-pair [s: string] -> [view: string, ok: bool] #force_inline
  (return (strings.trim_space s) true))

(defn trim-wrapper [s: string] -> string #force_inline
  (let [[view ok] (trim-pair s)]
    view))`
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
  (let [trimmed (support.trim-wrapper s) :defer]
    (println trimmed)))`
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

    testing.expect_value(t, strings.contains(result.output, "support__trim_pair :: #force_inline proc(s: string) -> (view: string, ok: bool)"), true)
    testing.expect_value(t, strings.contains(result.output, "support__trim_wrapper :: #force_inline proc(s: string) -> string"), true)
    testing.expect_value(t, strings.contains(result.output, "#borrowed"), false)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "support.trim-wrapper returns a borrowed view; do not delete it, delete the owner instead")
    }
}

@(test)
warn_defer_inferred_borrowed_slice_result :: proc(t: ^testing.T) {
    source := `(package main)

(defn take-one [xs: []int] -> []int
  (slice xs 0 1))

(defn take-one-wrapper [xs: []int] -> []int
  (take-one xs))

(defn split-one [xs: []int] -> [left: []int, right: []int]
  (return (slice xs 0 1) (slice xs 1)))

(defn prefix-until-zero [xs: []int] -> []int
  (for [x i xs]
    (when (= x 0)
      (return (slice xs 0 i))))
  xs)

(defn drop-first-byte [s: string] -> string
  (if (> (count s) 0)
    (slice s 1)
    s))

(defn main [xs: []int]
  (let [prefix (take-one xs) :defer
        wrapped (take-one-wrapper xs) :defer
        scanned (prefix-until-zero xs) :defer
        suffix (drop-first-byte "abc") :defer]
    (delete (split-one xs))
    (println (count prefix) (count wrapped) (count scanned) suffix)))`

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
    testing.expect_value(t, len(result.warnings), 5)
    if len(result.warnings) == 5 {
        testing.expect_value(t, result.warnings[0].message, "take-one returns a borrowed view; do not delete it, delete the owner instead")
        testing.expect_value(t, result.warnings[1].message, "take-one-wrapper returns a borrowed view; do not delete it, delete the owner instead")
        testing.expect_value(t, result.warnings[2].message, "prefix-until-zero returns a borrowed view; do not delete it, delete the owner instead")
        testing.expect_value(t, result.warnings[3].message, "drop-first-byte returns a borrowed view; do not delete it, delete the owner instead")
        testing.expect_value(t, result.warnings[4].message, "split-one returns a borrowed view; do not delete it, delete the owner instead")
    }
}

@(test)
warn_defer_third_party_conditional_borrowed_view_with_zero_fallback :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-borrowed-zero-branch-*", context.allocator)
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

(defn maybe-tail [xs: []int, take?: bool] -> []int #force_inline
  (if take?
    (slice xs 1)
    nil))

(defn maybe-trim [s: string, trim?: bool] -> string #force_inline
  (if trim?
    (strings.trim_space s)
    ""))

(defn maybe-split [s: string, split?: bool] -> []string #force_inline
  (if split?
    (strings.split s " ")
    nil))

(defn trim-or-label [s: string, trim?: bool] -> string #force_inline
  (if trim?
    (strings.trim_space s)
    "default"))`
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

(defn main [xs: []int, s: string, choose?: bool]
  (support.maybe-split s choose?)
  (let [tail (support.maybe-tail xs choose?) :defer
        trimmed (support.maybe-trim s choose?) :defer]
    (delete (support.trim-or-label s choose?))
    (println (count tail) trimmed)))`
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

    testing.expect_value(t, strings.contains(result.output, "support__maybe_tail :: #force_inline proc(xs: []int, take_p: bool) -> []int"), true)
    testing.expect_value(t, strings.contains(result.output, "support__maybe_trim :: #force_inline proc(s: string, trim_p: bool) -> string"), true)
    testing.expect_value(t, strings.contains(result.output, "support__maybe_split :: #force_inline proc(s: string, split_p: bool) -> []string"), true)
    testing.expect_value(t, strings.contains(result.output, "support__trim_or_label :: #force_inline proc(s: string, trim_p: bool) -> string"), true)
    testing.expect_value(t, strings.contains(result.output, "#borrowed"), false)
    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, len(result.warnings), 3)
    if len(result.warnings) == 3 {
        testing.expect_value(t, result.warnings[0].message, "owned result from support.maybe-split is discarded; bind it, delete it, or return it")
        testing.expect_value(t, result.warnings[1].message, "support.maybe-tail returns a borrowed view; do not delete it, delete the owner instead")
        testing.expect_value(t, result.warnings[2].message, "support.maybe-trim returns a borrowed view; do not delete it, delete the owner instead")
    }
}

@(test)
compile_recognizes_explicit_custom_deferred_cleanup :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn destroy-items! [items: [dynamic]int]
  (delete items))

(defn demo []
  (let [items (arr.empty int)]
    (defer (destroy-items! items))
    (println (count items))))`

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
managed_cleanup_reads_the_final_value_after_reassignment :: proc(t: ^testing.T) {
    source := `(package main)
(import data "kvist:data")

(def input-data '[1 2 3])

(defn build [] -> int
  (let [out: Data []]
    (set! out (data.into out input-data))
    (set! out (data.into out input-data))
    (data.count out)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(
        t,
        strings.contains(
            output,
            "defer (proc(kvist_place: ^Data, kvist_owner: ^bool)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(output, "kvist_data_release(kvist_place^)"),
        true,
    )
    testing.expect_value(
        t,
        strings.count(output, "kvist_data_move_assign(&(out)") == 2,
        true,
    )
}

@(test)
explicit_branch_cleanup_suppresses_generated_scope_cleanup :: proc(t: ^testing.T) {
    source := `(package main)

(defn choose [fail?: bool] -> [dynamic]int
  (let [values (make [dynamic]int)]
    (when fail?
      (delete values)
      (return (make [dynamic]int)))
    values))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "defer if "), false)
    testing.expect_value(t, strings.contains(output, "delete(values)"), true)
}
