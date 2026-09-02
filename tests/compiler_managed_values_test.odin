package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

@(test)
managed_struct_results_move_through_ordinary_control_flow :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Box [
  value: Data
])

(defn make-box [value: Data] -> Box
  (let [present true]
    (if present
      (Box :value value)
      (Box :value nil))))

(defn use [value: Data]
  (let [box (make-box value)]
    (discard box)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "box := make_box(value)"), true)
    testing.expect_value(t, strings.contains(output, "box := kvist_managed_clone_Box(make_box(value))"), false)
    testing.expect_value(t, strings.contains(output, "defer (proc(kvist_place: ^Box, kvist_owner: ^bool)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_managed_destroy_Box(kvist_place^)"), true)
}

@(test)
compile_rejects_copy_update_of_managed_struct_field :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Box [
  value: Data
])

(defn update-value [box: Box, f: (fn [value: Data] -> Data)] -> Box
  (copy-update box .value f))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    delete(output)
    defer delete(err.message)
    testing.expect_value(
        t,
        err.message,
        "update of a managed field is not yet supported; compute the new value first and use assoc",
    )
}

@(test)
compile_manages_owned_string_fields_in_native_structs :: proc(t: ^testing.T) {
    source := `(package main)
(import data "kvist:data")

(defstruct Person [
  name: string
])

(defn decode-person [value: Data] -> [person: Person, err: data.Decode-Error, ok: bool]
  (data.decode Person value))

(defn make-person [name: string] -> Person
  (Person :name name))

(defn rename [person: Person, name: string] -> Person
  (assoc person .name name))

(defn overwrite [person: Person, name: string]
  (let [copy person]
    (set! copy.name name)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return Person{name = strings.clone(name)}"), true)
    testing.expect_value(t, strings.contains(output, "out.name = strings.clone(value.name)"), true)
    testing.expect_value(t, strings.contains(output, "delete(value.name)"), true)
    testing.expect_value(
        t,
        strings.contains(output, ".name = strings.clone(kvist_value)"),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(output, "delete(kvist_update_"),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            "kvist_replacement := strings.clone(kvist_value); kvist_previous := kvist_place^",
        ),
        true,
    )
}

@(test)
compile_manages_owned_dynamic_array_fields_in_native_structs :: proc(t: ^testing.T) {
    source := `(package main)
(import data "kvist:data")

(defstruct Batch [
  values: [dynamic]i64
])

(defn decode-batch [value: Data] -> [batch: Batch, err: data.Decode-Error, ok: bool]
  (data.decode Batch value))

(defn wrap [values: [dynamic]i64] -> Batch
  (Batch :values values))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return Batch{values = values}"), true)
    testing.expect_value(
        t,
        strings.contains(
            output,
            "out.values = (proc(kvist_values: [dynamic]i64) -> [dynamic]i64",
        ),
        true,
    )
    testing.expect_value(t, strings.contains(output, "delete(value.values)"), true)
}

@(test)
consuming_overload_parameters_transfer_managed_arguments :: proc(t: ^testing.T) {
    source := `(package main)
(import data "kvist:data")

(defn consume-int [kind: int, value: Data] -> int
  (data.release value)
  kind)

(defn consume-string [kind: string, value: Data] -> int
  (data.release value)
  (count kind))

(def consume (overload consume-int consume-string))

(defn use [] -> int
  (consume 42 (data.from-string "temporary")))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, "return consume(42, kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, "data__from_string(\"temporary\")\n    defer"), false)
}

@(test)
warn_discarded_inferred_owned_string_proc_result :: proc(t: ^testing.T) {
    source := `(package main)
(import strings "core:strings")

(defn clone-owned [s: string] -> string
  (let [[out err] (strings.clone s)]
    out))

(defn main [s: string]
  (clone-owned s)
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
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from clone-owned is discarded; bind it, delete it, or return it")
    }
}

@(test)
warn_discarded_inferred_owned_string_proc_with_owned_early_return :: proc(t: ^testing.T) {
    source := `(package main)
(import strings "core:strings")

(defn lower-or-upper [s: string flag: bool] -> string
  (when flag
    (return (strings.to_lower s)))
  (strings.to_upper s))

(defn main [s: string]
  (lower-or-upper s true)
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
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from lower-or-upper is discarded; bind it, delete it, or return it")
    }
}

@(test)
warn_discarded_third_party_inferred_owned_string_proc_result :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-owned-string-*", context.allocator)
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

(defn join-two [a: string, b: string] -> string #force_inline
  (let [builder (strings.builder_make)]
    (defer (strings.builder_destroy (addr builder)))
    (strings.write_string (addr builder) a)
    (strings.write_string (addr builder) b)
    (let [[out err] (strings.clone (strings.to_string builder))]
      (if (!= err nil)
        ""
        out))))`
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
  (support.join-two "a" "b")
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

    testing.expect_value(t, strings.contains(result.output, "support__join_two :: #force_inline proc(a, b: string) -> string {"), true)
    testing.expect_value(t, strings.contains(result.output, "out, err := strings.clone(strings.to_string(builder))"), true)
    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from support.join-two is discarded; bind it, delete it, or return it")
    }
}

@(test)
warn_discarded_third_party_owned_string_wrapper_result :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-owned-string-wrapper-*", context.allocator)
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

(defn clone-base [s: string] -> string #force_inline
  (let [[out err] (strings.clone s)]
    out))

(defn clone-wrapper [s: string] -> string #force_inline
  (clone-base s))`
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
  (support.clone-wrapper s)
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

    testing.expect_value(t, strings.contains(result.output, "support__clone_base :: #force_inline proc(s: string) -> string"), true)
    testing.expect_value(t, strings.contains(result.output, "support__clone_wrapper :: #force_inline proc(s: string) -> string"), true)
    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from support.clone-wrapper is discarded; bind it, delete it, or return it")
    }
}

@(test)
warn_discarded_third_party_named_return_assignment_owned_string :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-owned-named-set-*", context.allocator)
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

(defn lower-named [s: string] -> [out: string, ok: bool] #force_inline
  (set! out (strings.to_lower s))
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
  (support.lower-named s)
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

    testing.expect_value(t, strings.contains(result.output, "support__lower_named :: #force_inline proc(s: string) -> (out: string, ok: bool)"), true)
    testing.expect_value(t, strings.contains(result.output, "out = strings.to_lower(s)"), true)
    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from support.lower-named is discarded; bind it, delete it, or return it")
    }
}

@(test)
warn_discarded_third_party_conditional_assignment_owned_string :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-owned-branch-set-*", context.allocator)
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

(defn normalize [s: string upper?: bool] -> string #force_inline
  (let [out ""]
    (if upper?
      (set! out (strings.to_upper s))
      (set! out (strings.to_lower s)))
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
  (support.normalize s true)
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

    testing.expect_value(t, strings.contains(result.output, "support__normalize :: #force_inline proc(s: string, upper_p: bool) -> string"), true)
    testing.expect_value(t, strings.contains(result.output, "out = strings.to_upper(s)"), true)
    testing.expect_value(t, strings.contains(result.output, "out = strings.to_lower(s)"), true)
    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from support.normalize is discarded; bind it, delete it, or return it")
    }
}

@(test)
warn_discarded_third_party_type_case_assignment_owned_string :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-owned-type-case-set-*", context.allocator)
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

(defstruct Upper [
  value: string
])

(defstruct Lower [
  value: string
])

(defunion Mode [
  upper: Upper
  lower: Lower
])

(defn normalize-mode [mode: Mode s: string] -> string #force_inline
  (let [out ""]
    (case mode
      (Upper _) (set! out (strings.to_upper s))
      (Lower _) (set! out (strings.to_lower s))
      (set! out (strings.to_lower s)))
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

(defn main [mode: support.Mode s: string]
  (support.normalize-mode mode s)
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

    testing.expect_value(t, strings.contains(result.output, "support__normalize_mode :: #force_inline proc(mode: support__Mode, s: string) -> string"), true)
    testing.expect_value(t, strings.contains(result.output, "out = strings.to_upper(s)"), true)
    testing.expect_value(t, strings.contains(result.output, "out = strings.to_lower(s)"), true)
    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from support.normalize-mode is discarded; bind it, delete it, or return it")
    }
}

@(test)
compile_does_not_infer_owned_string_when_alloc_or_input_parameter_returned :: proc(t: ^testing.T) {
    source := `(package main)
(import strings "core:strings")

(defn replace-or-original [s: string, old: string, new: string] -> string
  (let [[updated allocated?] (strings.replace s old new -1)]
    (if allocated?
      updated
      s)))

(defn main [s: string]
  (replace-or-original s "x" "y")
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
compile_does_not_infer_third_party_owned_string_when_only_one_if_branch_allocates :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-mixed-owned-if-package-*", context.allocator)
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

(defn lower-or-default [s: string allocate?: bool] -> string #force_inline
  (if allocate?
    (strings.to_lower s)
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

(defn main [s: string]
  (support.lower-or-default s false)
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

    testing.expect_value(t, strings.contains(result.output, "support__lower_or_default :: #force_inline proc"), true)
    testing.expect_value(t, strings.contains(result.output, "return strings.to_lower(s)"), true)
    testing.expect_value(t, strings.contains(result.output, "return \"default\""), true)
    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_does_not_infer_owned_string_when_early_return_uses_input_parameter :: proc(t: ^testing.T) {
    source := `(package main)
(import strings "core:strings")

(defn lower-or-original-early [s: string flag: bool] -> string
  (when flag
    (return s))
  (strings.to_lower s))

(defn main [s: string]
  (lower-or-original-early s true)
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
compile_does_not_infer_owned_string_after_named_return_overwrite :: proc(t: ^testing.T) {
    source := `(package main)
(import strings "core:strings")

(defn lower-or-original [s: string flag: bool] -> [out: string, ok: bool]
  (set! out (strings.to_lower s))
  (when flag
    (set! out s))
  (set! ok true)
  (return out ok))

(defn main [s: string]
  (lower-or-original s true)
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
