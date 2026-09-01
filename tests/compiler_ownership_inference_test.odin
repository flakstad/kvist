package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

@(test)
core_str_participates_in_owned_result_diagnostics :: proc(t: ^testing.T) {
    source := `(package main)

(defn main [name: string]
  (str "hello " name)
  (let [message (str "goodbye " name) :defer]
    (println message)))`

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
        testing.expect_value(t, result.warnings[0].message, "owned result from fmt.aprintf is discarded; bind it, delete it, or return it")
    }
    testing.expect_value(t, strings.contains(result.output, "defer delete(message)"), true)
}

@(test)
compile_nested_owned_argument_transfer_does_not_delete_temporary :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defstruct Node
  {values: [dynamic]int})

(defn inc [value: int] -> int
  (+ value 1))

(defn node [values: [dynamic]int] -> Node
  (Node {values: values}))

(defn add-node! [node-value: Node] -> int
  1)

(defn map-and-add! [values: []int] -> int
  (let [result (add-node! (node (arr.map inc values)))]
    result))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_"), false)
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
    defer kvist.compile_error_delete(&err)
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
    defer kvist.compile_error_delete(&err)
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
reject_returning_conditionally_assigned_third_party_owned_result_from_with_temp_allocator :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-temp-owned-conditional-source-*", context.allocator)
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

(defn copy [xs: []int] -> [dynamic]int #force_inline
  (let [out (make [dynamic]int)]
    (for [x xs]
      (append (addr out) x))
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
(import runtime "base:runtime")
(import support "support")

(defn bad [xs: []int fallback: [dynamic]int flag: bool] -> [dynamic]int
  (with-temp-allocator [allocator]
    (let [out fallback]
      (if flag
        (set! out (support.copy xs)))
      out)))`
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
compile_transfers_owned_result_into_composite_literal :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defstruct Batch {
  values: [dynamic]int
})

(defn inc [x: int] -> int
  (+ x 1))

(defn make-batch [xs: []int] -> Batch
  (Batch {values: (arr.map inc xs)}))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    delete(output)
}

@(test)
compile_transfers_owned_result_through_composite_wrapper :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defstruct Batch {
  values: [dynamic]int
})

(defn inc [x: int] -> int
  (+ x 1))

(defn wrap [values: [dynamic]int] -> Batch
  (Batch {values: values}))

(defn make-batch [xs: []int] -> Batch
  (wrap (arr.map inc xs)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    delete(output)
}

@(test)
compile_binds_owned_result_from_both_if_branches :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn inc [x: int] -> int
  (+ x 1))

(defn choose-map [xs: []int, choose?: bool] -> [dynamic]int
  (let [values (if choose?
                 (arr.map inc xs)
                 (arr.map inc xs))]
    values))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    delete(output)
}

@(test)
warn_discarded_regex_owned_results_from_alloc_shape :: proc(t: ^testing.T) {
    source := `(package main)
(import re "kvist:regex")

(defn bad-compile []
  (re.compile #"^a+$")
  (return))

(defn bad-match [compiled: re.Regex]
  (re.match compiled "aaa")
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

    testing.expect_value(t, strings.contains(result.output, "re__compile :: #force_inline proc(pattern: re__Pattern) -> (value: re__Regex, err: re__Error)"), true)
    testing.expect_value(t, strings.contains(result.output, "re__match :: #force_inline proc(compiled: re__Regex, s: string) -> (capture: re__Capture, ok: bool)"), true)
    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, len(result.warnings), 2)
    if len(result.warnings) == 2 {
        testing.expect_value(t, result.warnings[0].message, "owned result from re.compile is discarded; bind it, delete it, or return it")
        testing.expect_value(t, result.warnings[1].message, "owned result from re.match is discarded; bind it, delete it, or return it")
    }
}

@(test)
warn_discarded_third_party_regex_owned_result_from_alloc_shape :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-owned-regex-package-*", context.allocator)
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
(import r "core:text/regex")

(def Regex r.Regular_Expression)
(def Error r.Error)

(defn compile [pattern: string] -> [value: Regex, err: Error] #force_inline
  (r.create pattern))`
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

(defn main []
  (support.compile #"^a+$")
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

    testing.expect_value(t, strings.contains(result.output, "support__compile :: #force_inline proc(pattern: string) -> (value: support__Regex, err: support__Error)"), true)
    testing.expect_value(t, strings.contains(result.output, "return r.create(pattern)"), true)
    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from support.compile is discarded; bind it, delete it, or return it")
    }
}

@(test)
compile_warns_for_discarded_owned_result_inside_discard :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn make-values [] -> [dynamic]int
  (make [dynamic]int))

(defn demo []
  (discard (make-values)))`

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
        testing.expect_value(t, result.warnings[0].message, "owned result from make-values is discarded; bind it, delete it, or return it")
        testing.expect_value(t, result.warnings[0].code, kvist.Compile_Warning_Code.Ownership_Discarded_Result)
        testing.expect_value(t, result.warnings[0].confidence, kvist.Compile_Warning_Confidence.Definite)
    }
}

@(test)
compile_does_not_warn_for_owned_local_transferred_into_final_composite :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defstruct Box {
  xs: [dynamic]int
})

(defn demo [] -> Box
  (let [xs (arr.empty int)]
    (Box {xs: xs})))`

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
compile_does_not_warn_for_owned_local_transferred_into_later_composite_binding :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defstruct Box {
  xs: [dynamic]int
})

(defn demo [] -> int
  (let [xs (arr.empty int)
        box (Box {xs: xs})]
    (defer (delete box.xs))
    (count box.xs)))

(defn managed-alias [] -> int
  (let [xs (arr.empty int) :defer
        box (Box {xs: xs})]
    (arr.push! xs 1)
    (count box.xs)))`

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
compile_does_not_warn_for_owned_local_transferred_into_returned_composite :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defstruct Box {
  xs: [dynamic]int
})

(defn demo [] -> Box
  (let [xs (arr.empty int)]
    (return (Box {xs: xs}))))`

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
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_warns_for_owned_local_used_after_deleted_in_all_if_branches :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn demo [flag: bool]
  (let [xs (arr.empty int)]
    (if flag
      (delete xs)
      (delete xs))
    (println (count xs))))`

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
        testing.expect_value(t, result.warnings[0].message, "owned local xs is used after ownership transfer")
        testing.expect_value(t, result.warnings[0].code, kvist.Compile_Warning_Code.Ownership_Use_After_Transfer)
        testing.expect_value(t, result.warnings[0].confidence, kvist.Compile_Warning_Confidence.Conservative)
    }
}

@(test)
compile_warns_for_owned_local_used_after_deleted_in_all_type_case_branches :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

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

(defn demo [event: Event]
  (let [xs (arr.empty int)]
    (case event
      (Connected _) (delete xs)
      (Disconnected _) (delete xs)
      (delete xs))
    (println (count xs))))`

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
        testing.expect_value(t, result.warnings[0].message, "owned local xs is used after ownership transfer")
        testing.expect_value(t, result.warnings[0].code, kvist.Compile_Warning_Code.Ownership_Use_After_Transfer)
        testing.expect_value(t, result.warnings[0].confidence, kvist.Compile_Warning_Confidence.Conservative)
    }
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
    defer kvist.source_map_slice_delete(result.source_map)
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
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned local xs is overwritten before cleanup; delete it or return it before set!")
    }
}

@(test)
compile_warns_for_use_after_ownership_transfer :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn demo []
  (let [xs (arr.empty int)]
    (delete xs)
    (println (count xs))))`

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
        testing.expect_value(t, result.warnings[0].message, "owned local xs is used after ownership transfer")
        testing.expect_value(t, result.warnings[0].code, kvist.Compile_Warning_Code.Ownership_Use_After_Transfer)
        testing.expect_value(t, result.warnings[0].confidence, kvist.Compile_Warning_Confidence.Definite)
    }
}

@(test)
compile_warns_for_use_after_transfer_inside_branch :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn demo [flag: bool]
  (let [xs (arr.empty int) :defer]
    (if flag
      (do
        (delete xs)
        (println (count xs)))
      (println 1))))`

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
        testing.expect_value(t, result.warnings[0].message, "owned local xs is used after ownership transfer")
    }
}

@(test)
compile_warns_for_direct_append_ownership_transfer :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn demo []
  (let [dst (arr.empty [dynamic]int) :defer
        xs (arr.empty int)]
    (append (addr dst) xs)
    (println (count xs))))`

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
        testing.expect_value(t, result.warnings[0].message, "owned local xs is used after ownership transfer")
    }
}

@(test)
compile_does_not_treat_generated_append_names_as_ownership_transfer :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(foreign-import support "support")

(defn demo []
  (let [dst (arr.empty [dynamic]int) :defer
        xs (arr.empty int)]
    (support__append (addr dst) xs)
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
compile_warns_for_discarded_owned_result :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn make-values [] -> [dynamic]int
  (make [dynamic]int))

(defn demo []
  (make-values)
  (println 1))`

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
        testing.expect_value(t, result.warnings[0].message, "owned result from make-values is discarded; bind it, delete it, or return it")
    }
}
