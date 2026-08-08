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
compile_path_supports_multi_file_source_package_directory :: proc(t: ^testing.T) {
    output, err, ok := kvist.compile_path("examples/coverage/cluck-port/cluck-port-packages.kvist")
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
compile_path_deduplicates_identical_imports_across_package_files :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-package-imports-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    main_path, main_err := os.join_path({dir, "main.kvist"}, context.allocator)
    helper_path, helper_err := os.join_path({dir, "helper.kvist"}, context.allocator)
    testing.expect_value(t, main_err == nil && helper_err == nil, true)
    if main_err != nil || helper_err != nil {
        return
    }
    defer delete(main_path)
    defer delete(helper_path)

    main_source := `(package demo)
(import fmt "core:fmt")

(defn main []
  (fmt.println (helper-value)))`
    helper_source := `(package demo)
(import fmt "core:fmt")

(defn helper-value [] -> int
  (do
    (fmt.println "helper")
    42))`
    testing.expect_value(t, os.write_entire_file_from_string(main_path, main_source) == nil, true)
    testing.expect_value(t, os.write_entire_file_from_string(helper_path, helper_source) == nil, true)

    output, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, count_substring(output, `import fmt "core:fmt"`), 1)
}

@(test)
compile_path_warnings_report_the_imported_package_file :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-warning-origin-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    main_path, main_err := os.join_path({dir, "main.kvist"}, context.allocator)
    helper_path, helper_err := os.join_path({dir, "helper.kvist"}, context.allocator)
    testing.expect_value(t, main_err == nil && helper_err == nil, true)
    if main_err != nil || helper_err != nil {
        return
    }
    defer delete(main_path)
    defer delete(helper_path)

    testing.expect_value(t, os.write_entire_file_from_string(main_path, `(package demo)
(defn main [] (helper))`) == nil, true)
    helper_source := `(package demo)
(import arr "kvist:arr")
(defn helper []
  (let [forgotten (make [dynamic]int)]
    (println (count forgotten))))`
    testing.expect_value(t, os.write_entire_file_from_string(helper_path, helper_source) == nil, true)

    result, err, ok := kvist.compile_path_with_map(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, len(result.warnings) > 0, true)
    if len(result.warnings) == 0 {
        return
    }
    warning := result.warnings[0]
    testing.expect_value(t, warning.source_path, helper_path)
    testing.expect_value(t, warning.line, 4)
    testing.expect_value(t, warning.column > 0, true)

    formatted := kvist.format_compile_warning(main_path, "", warning)
    defer delete(formatted)
    testing.expect_value(t, strings.has_prefix(formatted, fmt.tprintf("%s:4:", helper_path)), true)

    found_helper_map := false
    for entry in result.source_map {
        if entry.source_path == helper_path {
            found_helper_map = true
            break
        }
    }
    testing.expect_value(t, found_helper_map, true)
}

@(test)
compile_path_errors_report_the_imported_package_file :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-error-origin-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    support_dir, support_dir_err := os.join_path({dir, "support"}, context.allocator)
    main_path, main_err := os.join_path({dir, "main.kvist"}, context.allocator)
    helper_path, helper_err := os.join_path({support_dir, "support.kvist"}, context.allocator)
    testing.expect_value(t, support_dir_err == nil && main_err == nil && helper_err == nil, true)
    if support_dir_err != nil || main_err != nil || helper_err != nil {
        return
    }
    defer delete(support_dir)
    defer delete(main_path)
    defer delete(helper_path)
    testing.expect_value(t, os.make_directory_all(support_dir) == nil, true)

    testing.expect_value(t, os.write_entire_file_from_string(main_path, `(package main)
(import support "support")
(defn main [] (println support.answer))`) == nil, true)
    helper_source := `(package support)
(def answer [1 2)`
    testing.expect_value(t, os.write_entire_file_from_string(helper_path, helper_source) == nil, true)

    _, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer kvist.compile_error_delete(&err)
    testing.expect_value(t, err.source_path, helper_path)

    formatted := kvist.format_compile_error(main_path, "", err)
    defer delete(formatted)
    testing.expect_value(t, strings.has_prefix(formatted, fmt.tprintf("%s:2:", helper_path)), true)
    testing.expect_value(t, strings.contains(formatted, "(def answer [1 2)"), true)
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
compile_path_package_files_are_order_independent :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-package-file-order-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    pkg_dir, pkg_dir_err := os.join_path({dir, "order-independent"}, context.allocator)
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

    types_path, types_path_err := os.join_path({pkg_dir, "a_types.kvist"}, context.allocator)
    testing.expect_value(t, types_path_err == nil, true)
    if types_path_err != nil {
        return
    }
    defer delete(types_path)
    types_source := `(package order-independent)

(defstruct Box {value: int})`
    types_write_err := os.write_entire_file_from_string(types_path, types_source)
    testing.expect_value(t, types_write_err == nil, true)
    if types_write_err != nil {
        return
    }

    macros_path, macros_path_err := os.join_path({pkg_dir, "m_macros.kvist"}, context.allocator)
    testing.expect_value(t, macros_path_err == nil, true)
    if macros_path_err != nil {
        return
    }
    defer delete(macros_path)
    macros_source := `(package order-independent)

(defmacro- emit-box [n]
  (quasiquote (Box {value: (unquote n)})))

(defmacro make-box [n]
  (emit-box n))`
    macros_write_err := os.write_entire_file_from_string(macros_path, macros_source)
    testing.expect_value(t, macros_write_err == nil, true)
    if macros_write_err != nil {
        return
    }

    runtime_path, runtime_path_err := os.join_path({pkg_dir, "z_runtime.kvist"}, context.allocator)
    testing.expect_value(t, runtime_path_err == nil, true)
    if runtime_path_err != nil {
        return
    }
    defer delete(runtime_path)
    runtime_source := `(package order-independent)

(defn read-box [] -> int
  (let [box (make-box 42)]
    box.value))`
    runtime_write_err := os.write_entire_file_from_string(runtime_path, runtime_source)
    testing.expect_value(t, runtime_write_err == nil, true)
    if runtime_write_err != nil {
        return
    }

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package tests)

(import p "./order-independent")

(defn main [] -> int
  (p.read-box))`
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

    testing.expect_value(t, strings.contains(output, "Box :: struct"), true)
    testing.expect_value(t, strings.contains(output, "read_box :: proc() -> int"), true)

    eval_result, eval_err, ok_eval := kvist.compile_eval_path(main_path, "(main)")
    testing.expect_value(t, ok_eval, true)
    if !ok_eval {
        testing.expect_value(t, eval_err.message, "")
        return
    }
    defer delete(eval_result)

    testing.expect_value(t, strings.contains(eval_result, "p__read_box :: proc() -> int"), true)
    testing.expect_value(t, strings.contains(eval_result, "box := p__Box{value = 42}"), true)
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
