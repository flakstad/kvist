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
third_party_macro_can_use_expected_zero :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro default-if [test value]
  (quasiquote
    (if (unquote test)
      (unquote value)
      (zero))))

(defn pick [second?: bool] -> int
  (let [index (default-if second? 1)]
    index))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "index := (1 if second_p else int{})"), true)
}

@(test)
compile_source_package_can_use_inline_tap_style_macro :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-inline-tap-package-*", context.allocator)
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
(import fmt "core:fmt")

(defmacro peek [label value]
  (cond
   (string? label)
    (let [target (gensym "support_peek")]
      (quasiquote
        (let [(unquote target) (unquote value)]
          (fmt.print (unquote label))
          (fmt.print ": ")
          (println (unquote target))
          (unquote target))))
   true
    (error "support.peek label must be a string literal")))`
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
(import arr "kvist:arr")

(defn demo [] -> int
  (let [xs (support.peek "xs" (arr.range 3)) :defer]
    (count xs)))`
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

    testing.expect_value(t, strings.contains(result.output, "fmt.print(\"xs\")"), true)
    testing.expect_value(t, strings.contains(result.output, "fmt.print(\": \")"), true)
    testing.expect_value(t, strings.contains(result.output, "fmt.println(support_peek"), true)
    testing.expect_value(t, strings.contains(result.output, "support_peek_"), true)
    testing.expect_value(t, strings.contains(result.output, "xs := support_peek"), true)
    testing.expect_value(t, strings.contains(result.output, "defer delete(xs)"), true)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_source_package_can_use_source_doc_macro :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-doc-package-*", context.allocator)
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

(defmacro show-doc [name]
  (quasiquote
    (println (source-doc (unquote name)))))`
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

(defn target
  "Package macro can read this doc."
  []
  (return))

(defn main []
  (support.show-doc 'target))`
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

    testing.expect_value(t, strings.contains(output, `fmt.println("Package macro can read this doc.")`), true)
    testing.expect_value(t, strings.contains(output, "kvist-prim-doc"), false)
}

@(test)
compile_source_package_can_use_odin_call_macro :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-odin-call-package-*", context.allocator)
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

(defmacro size [value]
  (quasiquote
    (odin-call "len" (unquote value))))`
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

(defn demo [xs: []int] -> int
  (support.size xs))`
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

    testing.expect_value(t, strings.contains(result.output, "return len(xs)"), true)
    testing.expect_value(t, strings.contains(result.output, "kvist_prim_count"), false)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_source_package_can_use_neutral_macro_time_helpers :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-macro-helpers-package-*", context.allocator)
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

(defmacro pick-known [items]
  (if (and (= (count items) 3)
           (contains? items "green")
           (not (contains? (slice items 1) "red")))
    (quasiquote "ok")
    (quasiquote "bad")))`
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

(defn demo [] -> string
  (support.pick-known ["red" "green" "blue"]))`
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

    testing.expect_value(t, strings.contains(result.output, `return "ok"`), true)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_source_package_macro_name_uses_source_member_name :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-macro-source-name-package-*", context.allocator)
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

(defmacro marker []
  (quote true))

(defmacro expect-marker-head [form]
  (if (= (name (first form)) "marker")
    (quote (def matched true))
    (quote (def missed true))))`
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

(support.expect-marker-head (support.marker))

(defn demo [] -> bool
  matched)`
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

    testing.expect_value(t, strings.contains(result.output, "matched :: true"), true)
    testing.expect_value(t, strings.contains(result.output, "missed :: true"), false)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_source_package_can_use_odin_contains_macro :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-odin-contains-package-*", context.allocator)
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

(defmacro has? [collection key]
  (quasiquote
    (odin-contains (unquote collection) (unquote key))))`
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

(defn scan [xs: []int, needle: int] -> bool
  (support.has? xs needle))

(defn lookup [m: map[string]int, key: string] -> bool
  (support.has? m key))

(defn lookup-ptr [m: ^map[string]int, key: string] -> bool
  (support.has? m key))

(defn text [s: string, needle: string] -> bool
  (support.has? s needle))`
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

    testing.expect_value(t, strings.contains(result.output, "return kvist_contains_value((xs)[:], needle)"), true)
    testing.expect_value(t, strings.contains(result.output, "return (key) in (m)"), true)
    testing.expect_value(t, strings.contains(result.output, "return (key) in (m^)"), true)
    testing.expect_value(t, strings.contains(result.output, "return strings.contains(s, needle)"), true)
    testing.expect_value(t, strings.contains(result.output, "kvist_prim_contains"), false)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_source_package_can_use_odin_get_macro :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-odin-get-package-*", context.allocator)
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

(defmacro at [target key]
  (quasiquote
    (odin-get (unquote target) (unquote key))))

(defmacro at-or [target key fallback]
  (quasiquote
    (odin-get (unquote target) (unquote key) (unquote fallback))))`
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

(defstruct User {
  name: string
  score: int
})

(defn score [xs: []int, m: map[string]int, user: User] -> int
  (+ (support.at xs 1)
     (support.at-or m "missing" 40)
     (support.at user .score)))`
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

    testing.expect_value(t, strings.contains(result.output, "return (xs[1]) + (kvist_get_or_default(m, \"missing\", 40)) + ((user).score)"), true)
    testing.expect_value(t, strings.contains(result.output, "kvist_prim_get"), false)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_source_package_can_use_odin_slice_macro :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-odin-slice-package-*", context.allocator)
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

(defmacro view [target]
  (quasiquote
    (odin-slice (unquote target))))

(defmacro suffix [target start]
  (quasiquote
    (odin-slice (unquote target) (unquote start))))

(defmacro window [target start end]
  (quasiquote
    (odin-slice (unquote target) (unquote start) (unquote end))))`
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

(defn all [xs: [dynamic]int] -> []int
  (support.view xs))

(defn rest [xs: []int] -> []int
  (support.suffix xs 1))

(defn middle [xs: []int] -> []int
  (support.window xs 1 3))`
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

    testing.expect_value(t, strings.contains(result.output, "return (xs)[:]"), true)
    testing.expect_value(t, strings.contains(result.output, "return (xs)[1:]"), true)
    testing.expect_value(t, strings.contains(result.output, "return (xs)[1:3]"), true)
    testing.expect_value(t, strings.contains(result.output, "kvist_prim_slice"), false)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_source_package_can_use_source_update_macro :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-update-package-*", context.allocator)
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

(defmacro update-ish! [place updater & rest]
  (let [op (name updater)]
    (cond
      (and (= op "+") (= (count rest) 1))
      (quasiquote
        (mut! (unquote place) += (unquote (first rest))))
      :else
      (quasiquote
        (set! (unquote place) ((unquote updater) (unquote place)))))))`
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

(defn inc [x: int] -> int
  (+ x 1))

(defn demo [] -> int
  (let [xs ([dynamic]int [1 2 3])
        total 4]
    (defer (delete xs))
    (support.update-ish! xs[1] + 10)
    (support.update-ish! total inc)
    (+ (get xs 1) total)))`
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

    testing.expect_value(t, strings.contains(result.output, "(xs)[1] += 10"), true)
    testing.expect_value(t, strings.contains(result.output, "total = inc(total)"), true)
    testing.expect_value(t, strings.contains(result.output, "kvist_prim_update"), false)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_source_package_can_use_copy_with_macro :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-copy-with-package-*", context.allocator)
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

(defmacro- first-dot-index-loop [text index]
  (if (= index (count text))
    -1
    (if (= (slice text index (+ index 1)) ".")
      index
      (first-dot-index-loop text (+ index 1)))))

(defmacro- first-dot-index [text]
  (first-dot-index-loop text 0))

(defmacro- field-target [place]
  (let [text (source place)
        dot (first-dot-index text)]
    (if (> dot 0)
      (symbol (slice text 0 dot))
      (error "field place helper expects a field place such as user.name or user.address.city"))))

(defmacro- field-selector [place]
  (let [text (source place)
        dot (first-dot-index text)]
    (if (> dot 0)
      (symbol (slice text dot))
      (error "field place helper expects a field place such as user.name or user.address.city"))))

(defmacro replacing [place value]
  (let [target (field-target place)
        selector (field-selector place)]
    (quasiquote
      (copy-with (unquote target) (unquote selector) (unquote value)))))

(defmacro replacing-on [target selector value]
  (quasiquote
    (copy-with (unquote target) (unquote selector) (unquote value))))`
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

(defstruct Profile {
  name: string
})

(defstruct User {
  profile: Profile
  active?: bool
})

(defn rename [user: User] -> User
  (let [renamed (support.replacing user.profile.name "Ada")]
    (support.replacing-on renamed .active? true)))`
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

    testing.expect_value(t, strings.contains(result.output, "kvist_update_1.profile.name = kvist_value"), true)
    testing.expect_value(t, strings.contains(result.output, "kvist_update_2.active_p = kvist_value"), true)
    testing.expect_value(t, strings.contains(result.output, "kvist_prim_assoc"), false)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_source_package_can_use_copy_update_macro :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-copy-update-package-*", context.allocator)
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

(defmacro- first-dot-index-loop [text index]
  (if (= index (count text))
    -1
    (if (= (slice text index (+ index 1)) ".")
      index
      (first-dot-index-loop text (+ index 1)))))

(defmacro- first-dot-index [text]
  (first-dot-index-loop text 0))

(defmacro- field-target [place]
  (let [text (source place)
        dot (first-dot-index text)]
    (if (> dot 0)
      (symbol (slice text 0 dot))
      (error "field place helper expects a field place such as user.name or user.address.city"))))

(defmacro- field-selector [place]
  (let [text (source place)
        dot (first-dot-index text)]
    (if (> dot 0)
      (symbol (slice text dot))
      (error "field place helper expects a field place such as user.name or user.address.city"))))

(defmacro changing [place f & args]
  (let [target (field-target place)
        selector (field-selector place)]
    (quasiquote
      (copy-update (unquote target) (unquote selector) (unquote f) (splice args)))))

(defmacro changing-on [target selector f & args]
  (quasiquote
    (copy-update (unquote target) (unquote selector) (unquote f) (splice args))))`
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

(defstruct Profile {
  visits: int
})

(defstruct User {
  profile: Profile
  score: int
})

(defn add [x: int delta: int] -> int
  (+ x delta))

(defn bump [user: User] -> User
  (let [visited (support.changing user.profile.visits inc)]
    (support.changing-on visited .score add 10)))`
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

    testing.expect_value(t, strings.contains(result.output, "kvist_update_1.profile.visits = (kvist_target.profile.visits) + 1"), true)
    testing.expect_value(t, strings.contains(result.output, "kvist_update_2.score = add(kvist_target.score, kvist_arg_0)"), true)
    testing.expect_value(t, strings.contains(result.output, "kvist_prim_update"), false)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_imported_macro_package_can_define_source_sequence_helpers :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-macro-seq-package-*", context.allocator)
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

    support_path, support_path_err := os.join_path({pkg_dir, "support.kvist"}, context.allocator)
    testing.expect_value(t, support_path_err == nil, true)
    if support_path_err != nil {
        return
    }
    defer delete(support_path)
    support_source := `(package support)

(defmacro map [f #form values]
  (if (= (count values) 0)
    (forms)
    (concat
      (forms (f (first values)))
      (map f (rest values)))))

(defmacro filter [pred #form values]
  (if (= (count values) 0)
    (forms)
    (let [head (first values)
          tail (filter pred (rest values))]
      (if (pred head)
        (concat (forms head) tail)
        tail))))

(defmacro emit-summary [items]
  (let [names (map source items)
        symbols (filter symbol? items)]
    (forms
      (quasiquote
        (def imported-names-count (unquote (count names))))
      (quasiquote
        (def imported-symbols-count (unquote (count symbols)))))))`
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
    main_source := `(package main)
(import support "support")

(support.emit-summary [aa 7 bb])`
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

    testing.expect_value(t, strings.contains(output, "imported_names_count :: 3"), true)
    testing.expect_value(t, strings.contains(output, "imported_symbols_count :: 2"), true)
}

@(test)
compile_imported_macro_package_can_define_private_set_predicate_helper :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-macro-set-p-helper-*", context.allocator)
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

    support_path, support_path_err := os.join_path({pkg_dir, "support.kvist"}, context.allocator)
    testing.expect_value(t, support_path_err == nil, true)
    if support_path_err != nil {
        return
    }
    defer delete(support_path)
    support_source := `(package support)

(defmacro- set? [form]
  (= (count form) 2))

(defmacro emit-helper-result [items]
  (if (set? items)
    (quasiquote
      (def helper-result true))
    (quasiquote
      (def helper-result false))))`
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
    main_source := `(package main)
(import support "support")

(support.emit-helper-result [aa bb])`
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

    testing.expect_value(t, strings.contains(output, "helper_result :: true"), true)
}

@(test)
compile_imported_macro_package_can_shadow_core_macro_helper_with_private_macro :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-macro-shadow-helper-*", context.allocator)
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

    support_path, support_path_err := os.join_path({pkg_dir, "support.kvist"}, context.allocator)
    testing.expect_value(t, support_path_err == nil, true)
    if support_path_err != nil {
        return
    }
    defer delete(support_path)
    support_source := `(package support)

(defmacro- count [form]
  (if (= (source form) "marked")
    7
    0))

(defmacro emit-helper-result [marker]
  (quasiquote
    (def helper-result: int (unquote (count marker)))))`
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
    main_source := `(package main)
(import support "support")

(support.emit-helper-result marked)`
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

    testing.expect_value(t, strings.contains(output, "helper_result: int : 7"), true)
}

@(test)
compile_source_package_macro_can_expand_to_private_defiter :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-defiter-package-*", context.allocator)
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

(defstruct- Num-Source {
  current: int
  end: int
})

(defn- next-num [src: ^Num-Source] -> [value: int ok: bool]
  (if (< src.current src.end)
    (let [value src.current]
      (set! src.current (+ src.current 1))
      (return value true))
    (return 0 false)))

(defiter- nums-impl [end: int] -> Num-Source :yield int
  :next next-num
  (Num-Source {current: 0 end: end}))

(defmacro nums [end]
  (quasiquote
    (support__nums_impl (unquote end))))`
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

(defn inc [x: int] -> int
  (+ x 1))

(defn demo [n: int] -> int
  (transduce
    (map inc)
    + 0
    (support.nums n)))`
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

    testing.expect_value(t, strings.contains(output, "support__nums_impl :: proc(end: int) -> support__Num_Source {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_source := support__nums_impl(kvist_source_arg_1)"), true)
    testing.expect_value(t, strings.contains(output, "support__next_num(&kvist_source)"), true)
}

@(test)
warn_discarded_third_party_macro_impl_result_from_actual_decl :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-owned-impl-package-*", context.allocator)
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

(defn- join-impl [xs: []$T, ys: []T] -> [dynamic]T #force_inline
  (let [out (make [dynamic]T 0 (+ (core.count xs) (core.count ys)))]
    (for [x xs]
      (append (addr out) x))
    (for [y ys]
      (append (addr out) y))
    out))

(defmacro join [xs ys]
  (quasiquote
    (join-impl (unquote xs) (unquote ys))))`
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

    testing.expect_value(t, strings.contains(result.output, "support__join_impl :: #force_inline proc(xs: []$T, ys: []T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, strings.contains(result.output, "support__join_impl(xs, ys)"), true)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from support.join is discarded; bind it, delete it, or return it")
    }
}

@(test)
third_party_source_package_macro_uses_bare_when_dsl :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-third-party-bare-when-dsl-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    pkg_dir, pkg_join_err := os.join_path({dir, "support"}, context.allocator)
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

    pkg_file, pkg_file_err := os.join_path({pkg_dir, "support.kvist"}, context.allocator)
    testing.expect_value(t, pkg_file_err == nil, true)
    if pkg_file_err != nil {
        return
    }
    defer delete(pkg_file)
    pkg_source := `(package support)

(defmacro- when-form? [form]
  (if (list? form)
    (if (= (count form) 3)
      (if (symbol? (first form))
        (= (name (first form)) "when")
        false)
      false)
    false))

(defmacro emit [form]
  (if (when-form? form)
    (quasiquote
      (if (unquote (nth form 1))
        (unquote (nth form 2))
        "skip"))
    form))`
    pkg_write_err := os.write_entire_file_from_string(pkg_file, pkg_source)
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

(defn demo [ready?: bool] -> string
  (support.emit
    (when ready? "ready")))`
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

    testing.expect_value(t, strings.contains(output, "if ready_p"), true)
    testing.expect_value(t, strings.contains(output, "return \"ready\""), true)
    testing.expect_value(t, strings.contains(output, "return \"skip\""), true)
    testing.expect_value(t, strings.contains(output, "support__when"), false)
}

@(test)
compile_path_source_package_macro_can_preserve_keyword_source :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-package-macro-source-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    pkg_dir, pkg_join_err := os.join_path({dir, "support", "tx"}, context.allocator)
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

    pkg_file, pkg_file_err := os.join_path({pkg_dir, "tx.kvist"}, context.allocator)
    testing.expect_value(t, pkg_file_err == nil, true)
    if pkg_file_err != nil {
        return
    }
    defer delete(pkg_file)
    pkg_source := `(package tx)

(defmacro- emit-op [form]
  (if (vector? form)
    (quasiquote (unquote (source (nth form 0))))
    (error "tx-data expects vector forms")))

(defmacro- emit-ops [forms]
  (if (= (count forms) 0)
    (forms)
    (forms
      (emit-op (first forms))
      (emit-ops (rest forms)))))

(defmacro tx-data [& forms]
  (quasiquote ([]string [(splice (emit-ops forms))])))`
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
    main_source := `(import tx "support/tx")

(defn tx-count [] -> int
  (let [ops (tx.tx-data [:db/add 1 :user/name "Ada"]
                        [:db/retract 1 :user/name "Ada"])]
    (count ops)))`
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

    testing.expect_value(t, strings.contains(output, `"[:db/add, 1, :user/name, \"Ada\"]"`), false)
    testing.expect_value(t, strings.contains(output, `"db/add"`), false)
    testing.expect_value(t, strings.contains(output, `":db/add"`), true)
    testing.expect_value(t, strings.contains(output, `":db/retract"`), true)
}

@(test)
compile_nested_source_package_qualified_macro :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-nested-source-macro-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    macros_dir, _ := os.join_path({dir, "macros"}, context.allocator)
    middle_dir, _ := os.join_path({dir, "middle"}, context.allocator)
    defer delete(macros_dir)
    defer delete(middle_dir)
    testing.expect_value(t, os.make_directory_all(macros_dir) == nil, true)
    testing.expect_value(t, os.make_directory_all(middle_dir) == nil, true)

    macros_path, _ := os.join_path({macros_dir, "macros.kvist"}, context.allocator)
    middle_path, _ := os.join_path({middle_dir, "middle.kvist"}, context.allocator)
    middle_use_path, _ := os.join_path({middle_dir, "use.kvist"}, context.allocator)
    root_path, _ := os.join_path({dir, "main.kvist"}, context.allocator)
    defer delete(macros_path)
    defer delete(middle_path)
    defer delete(middle_use_path)
    defer delete(root_path)
    testing.expect_value(t, os.write_entire_file_from_string(macros_path, `(package macros)
(defmacro forty-two [] (quasiquote 42))`) == nil, true)
    testing.expect_value(t, os.write_entire_file_from_string(middle_path, `(package middle)
(import macros "../macros")`) == nil, true)
    testing.expect_value(t, os.write_entire_file_from_string(middle_use_path, `(package middle)
(def value (macros.forty-two))`) == nil, true)
    testing.expect_value(t, os.write_entire_file_from_string(root_path, `(package main)
(import middle "middle")
(def answer middle.value)`) == nil, true)

    output, err, ok := kvist.compile_path(root_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "42"), true)
    testing.expect_value(t, strings.contains(output, "forty_two"), false)
}
