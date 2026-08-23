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
compile_eval_path_rewrites_source_package_aliases :: proc(t: ^testing.T) {
    output, err, ok := kvist.compile_eval_path("examples/coverage/cluck-port/cluck-port-packages.kvist", "(math.sum-range 0 5)")
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "math__sum_range(0, 5)"), true)
}

@(test)
third_party_source_package_can_alias_core_escape :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-core-alias-escape-*", context.allocator)
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
(import k "kvist:core")

(defn count [xs: []int] -> int
  (k.count xs))

(defn tail [xs: []int] -> []int
  (k.slice xs 1))

(defn first [xs: []int] -> int
  (k.get xs 0))`
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
(import s "support")

(defn main [] -> int
  (let [xs ([]int [1 2 3])]
    (+ (s.count xs) (s.first (s.tail xs)))))`
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

    testing.expect_value(t, strings.contains(output, "s__count :: proc(xs: []int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "return len(xs)"), true)
    testing.expect_value(t, strings.contains(output, "return (xs)[1:]"), true)
    testing.expect_value(t, strings.contains(output, "return xs[0]"), true)
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
reject_internal_lowering_call_names_in_imported_source_package :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-imported-internal-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    bad_dir, bad_dir_err := os.join_path({dir, "packages", "bad"}, context.allocator)
    testing.expect_value(t, bad_dir_err == nil, true)
    if bad_dir_err != nil {
        return
    }
    defer delete(bad_dir)

    mk_err := os.make_directory_all(bad_dir)
    testing.expect_value(t, mk_err == nil, true)
    if mk_err != nil {
        return
    }

    bad_path, bad_path_err := os.join_path({bad_dir, "bad.kvist"}, context.allocator)
    testing.expect_value(t, bad_path_err == nil, true)
    if bad_path_err != nil {
        return
    }
    defer delete(bad_path)

    bad_write_err := os.write_entire_file_from_string(bad_path, `(package bad)

(defn count [xs: []int] -> int
  (kvist-prim-count xs))`)
    testing.expect_value(t, bad_write_err == nil, true)
    if bad_write_err != nil {
        return
    }

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)

    main_write_err := os.write_entire_file_from_string(main_path, `(package main)
(import bad "packages/bad")

(defn main [xs: []int] -> int
  (bad.count xs))`)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    _, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer kvist.compile_error_delete(&err)
    testing.expect_value(t, err.message, "`kvist-prim-count` is an internal lowering name")
}

@(test)
compile_leaves_package_dash_call_names_as_plain_calls :: proc(t: ^testing.T) {
    cases := []struct {
        source:   string,
        expected: string,
    }{
        {`(package main)

(defn bad [xs: []int] -> [dynamic]int
  (arr-interpose 0 xs))`, "arr_interpose(0, xs)"},
        {`(package main)

(defn bad [m: map[string]int] -> [dynamic]string
  (map-keys m))`, "map_keys(m)"},
        {`(package main)

(defn bad [a: (map int (struct {})) b: (map int (struct {}))] -> (map int (struct {}))
  (set-union a b))`, "set_union(a, b)"},
        {`(package main)

(defn bad [s: string] -> string
  (str-lower s))`, "str_lower(s)"},
        {`(package main)

(defn bad [path: string]
  (io-read path))`, "io_read(path)"},
        {`(package main)

(defn bad [value: int]
  (json-write value))`, "json_write(value)"},
        {`(package main)

(defn bad [args: []string] -> bool
  (cli-flag args "--verbose"))`, "cli_flag(args, \"--verbose\")"},
    }

    for test_case in cases {
        output, err, ok := kvist.compile_source(test_case.source)
        testing.expect_value(t, ok, true)
        if !ok {
            testing.expect_value(t, err.message, "")
            continue
        }
        testing.expect_value(t, strings.contains(output, test_case.expected), true)
        delete(output)
    }
}

@(test)
reject_slash_package_access_in_eval_source :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

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
compile_eval_source_deduplicates_import_declaration_form :: proc(t: ^testing.T) {
    source := `(package main)
(import fmt "core:fmt")

(defn main []
  (fmt.println "hello"))`

    output, err, ok := kvist.compile_eval_source(source, `(import fmt "core:fmt")`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import fmt "core:fmt"

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
    testing.expect_value(t, strings.contains(output, "append(&xs, 1, 2, 3)"), true)
    testing.expect_value(t, strings.contains(output, "return len(xs)"), true)
    testing.expect_value(t, strings.contains(output, "kvist:arr"), false)
}

@(test)
compile_supports_as_kvist_package_imports :: proc(t: ^testing.T) {
    source := `(package main)
(import "kvist:arr" :as a)

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
    testing.expect_value(t, strings.contains(output, "append(&xs, 1, 2, 3)"), true)
    testing.expect_value(t, strings.contains(output, "return len(xs)"), true)
    testing.expect_value(t, strings.contains(output, "kvist:arr"), false)
}

@(test)
compile_supports_explicit_refer_kvist_package_imports :: proc(t: ^testing.T) {
    source := `(package main)
(import "kvist:arr" :refer [empty push! count])

(defn demo [] -> int
  (let [xs (empty int)]
    (push! xs 1 2 3)
    (+ (count xs) (arr.count xs))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "xs := make([dynamic]int)"), true)
    testing.expect_value(t, strings.contains(output, "append(&xs, 1, 2, 3)"), true)
    testing.expect_value(t, strings.contains(output, "arr__count :: #force_inline proc(xs: []$T) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "len("), true)
    testing.expect_value(t, strings.contains(output, "arr__count((xs)[:])"), true)
}

@(test)
reject_path_only_imports :: proc(t: ^testing.T) {
    source := `(package main)
(import "kvist:arr")

(defn demo [] -> int
  1)`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "import expects alias plus string path, string path plus :as alias, or string path plus :refer vector"), true)
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
    testing.expect_value(t, strings.contains(err.message, "could not resolve source package import: kvist:not-a-package"), true)
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

    testing.expect_value(t, strings.contains(output, "kvist_thread_1 := arr__map_impl(inc, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "total := arr__reduce_impl(add, 0,"), true)
}

@(test)
compile_threaded_map_zip_requires_imported_map_package :: proc(t: ^testing.T) {
    source := `(package main)
(import map "kvist:map")

(defn main [vals: []int] -> map[string]int
  (let [out (->> vals
                 (map.zip ([]string ["a" "b"])))]
    out))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "out := map__zip("), true)
    testing.expect_value(t, strings.contains(output, "return out"), true)
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
compile_leaves_unimported_arr_count_and_constructors_unresolved :: proc(t: ^testing.T) {
    cases := []struct {
        source:   string,
        expected: string,
    }{
        {`(package main)

(defn score [xs: []int] -> int
  (arr.count xs))`, "arr.count(xs)"},
        {`(package main)

(defn score [xs: []int] -> int
  (arr.get xs 0))`, "arr.get(xs, 0)"},
        {`(package main)

(defn score [xs: []int] -> []int
  (arr.slice xs 1))`, "arr.slice(xs, 1)"},
        {`(package main)

(defn score [] -> int
  (let [xs (arr.empty int)]
    (count xs)))`, "arr.empty(int)"},
        {`(package main)

(defn score [] -> int
  (let [xs (arr.dynamic int [1 2])]
    (count xs)))`, "xs := arr.dynamic(int, kvist_thread_1)"},
        {`(package main)

(defn score [] -> int
  (let [xs (arr.fixed int [1 2])]
    (count xs)))`, "xs := arr.fixed(int, kvist_thread_1)"},
    }

    for test_case in cases {
        output, err, ok := kvist.compile_source(test_case.source)
        testing.expect_value(t, ok, true)
        if !ok {
            testing.expect_value(t, err.message, "")
            continue
        }
        testing.expect_value(t, strings.contains(output, test_case.expected), true)
        delete(output)
    }
}

@(test)
compile_leaves_unimported_direct_arr_sequence_helpers_unresolved :: proc(t: ^testing.T) {
    cases := []struct {
        source:   string,
        expected: string,
    }{
        {`(package main)

(defn score [xs: []int] -> []int
  (arr.take 2 xs))`, "arr.take(2, xs)"},
        {`(package main)

(defn score [xs: []int] -> []int
  (arr.drop 1 xs))`, "arr.drop(1, xs)"},
        {`(package main)

(defn score [xs: []int] -> []int
  (arr.drop-last 1 xs))`, "arr.drop_last(1, xs)"},
        {`(package main)

(defn score [xs: []int] -> []int
  (arr.butlast xs))`, "arr.butlast(xs)"},
        {`(package main)

(defn score [xs: []int] -> int
  (arr.first xs))`, "arr.first"},
        {`(package main)

(defn score [xs: []int] -> int
  (arr.second xs))`, "arr.second"},
        {`(package main)

(defn score [xs: []int] -> int
  (arr.last xs))`, "arr.last"},
        {`(package main)

(defn score [xs: []int] -> int
  (arr.nth 2 xs))`, "arr.nth"},
        {`(package main)

(defn score [xs: []int] -> []int
  (arr.rest xs))`, "arr.rest"},
        {`(package main)

(defn add-index [i: int, x: int] -> int
  (+ i x))

(defn score [xs: []int] -> [dynamic]int
  (arr.map-indexed add-index xs))`, "arr.map_indexed(add_index, xs)"},
        {`(package main)

(defn pair [x: int] -> []int
  ([]int [x x]))

(defn score [xs: []int] -> [dynamic]int
  (arr.mapcat pair xs))`, "arr.mapcat(pair, xs)"},
        {`(package main)

(defn score [xs: []int] -> [left: []int, right: []int]
  (arr.split-at 1 xs))`, "arr.split_at(1, xs)"},
        {`(package main)

(defn score [xs: []int] -> [dynamic][]int
  (arr.partition 2 xs))`, "arr.partition(2, xs)"},
        {`(package main)

(defn score [xs: []int] -> [dynamic][]int
  (arr.partition-all 2 xs))`, "arr.partition_all(2, xs)"},
        {`(package main)

(defn score [xs: []int] -> [dynamic]int
  (arr.take-nth 2 xs))`, "arr.take_nth(2, xs)"},
        {`(package main)

(defn score [] -> [dynamic]int
  (arr.range 3))`, "arr.range(3)"},
        {`(package main)

(defn score [] -> [dynamic]int
  (arr.repeat 2 9))`, "arr.repeat(2, 9)"},
        {`(package main)

(defn next [] -> int
  1)

(defn score [] -> [dynamic]int
  (arr.repeatedly 2 next))`, "arr.repeatedly(2, next)"},
        {`(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn score [] -> [dynamic]int
  (arr.iterate 2 inc 0))`, "arr.iterate(2, inc, 0)"},
        {`(package main)

(defn score [xs: []int] -> [dynamic]int
  (arr.cycle 2 xs))`, "arr.cycle(2, xs)"},
        {`(package main)

(defn score [xs: []int] -> map[int]int
  (arr.frequencies xs))`, "arr.frequencies(xs)"},
        {`(package main)

(defn score [xs: []int] -> [dynamic]int
  (arr.distinct xs))`, "arr.distinct(xs)"},
        {`(package main)

(defn score [xs: []int] -> [dynamic]int
  (arr.reverse xs))`, "arr.reverse(xs)"},
        {`(package main)

(defn score [xs: [dynamic]int]
  (arr.reverse! xs))`, "arr.reverse_bang(xs)"},
        {`(package main)

(defn pick-first [n: int] -> int
  0)

(defn score [xs: []int] -> [dynamic]int
  (arr.shuffle pick-first xs))`, "arr.shuffle(pick_first, xs)"},
        {`(package main)

(defn pick-first [n: int] -> int
  0)

(defn score [xs: [dynamic]int]
  (arr.shuffle! pick-first xs))`, "arr.shuffle_bang(pick_first, xs)"},
        {`(package main)

(defn score [xs: []int] -> [dynamic]int
  (arr.sort xs))`, "arr.sort(xs)"},
        {`(package main)

(defn score [xs: [dynamic]int]
  (arr.sort! xs))`, "arr.sort_bang(xs)"},
    }

    for test_case in cases {
        output, err, ok := kvist.compile_source(test_case.source)
        testing.expect_value(t, ok, true)
        if !ok {
            testing.expect_value(t, err.message, "")
            continue
        }
        testing.expect_value(t, strings.contains(output, test_case.expected), true)
        delete(output)
    }
}

@(test)
compile_does_not_classify_unimported_arr_view_helper_as_borrowed :: proc(t: ^testing.T) {
    source := `(package main)

(defn score [xs: []int] -> int
  (let [prefix (arr.take 2 xs) :defer]
    (count prefix)))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, strings.contains(result.output, "arr.take(2, xs)"), true)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_leaves_unimported_for_arr_sequence_source_unresolved :: proc(t: ^testing.T) {
    source := `(package main)

(defn score [] -> int
  (let [total 0]
    (for [value (arr.repeat 2 9)]
      (set! total (+ total value)))
    total))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "arr.repeat(2, 9)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_loop_repeat_index_"), false)
}

@(test)
compile_leaves_unimported_direct_arr_callback_helpers_unresolved :: proc(t: ^testing.T) {
    cases := []struct {
        source:   string,
        expected: string,
    }{
        {`(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn score [xs: []int] -> [dynamic]int
  (arr.map inc xs))`, "arr.map(inc, xs)"},
        {`(package main)

(defn positive? [x: int] -> bool
  (> x 0))

(defn score [xs: []int] -> [dynamic]int
  (arr.filter positive? xs))`, "arr.filter(positive_p, xs)"},
        {`(package main)

(defn positive? [x: int] -> bool
  (> x 0))

(defn score [xs: []int] -> [dynamic]int
  (arr.remove positive? xs))`, "arr.remove(positive_p, xs)"},
        {`(package main)

(defn keep-positive [x: int] -> [value: int, ok: bool]
  (return x (> x 0)))

(defn score [xs: []int] -> [dynamic]int
  (arr.keep keep-positive xs))`, "arr.keep(keep_positive, xs)"},
        {`(package main)

(defn add [acc: int, x: int] -> int
  (+ acc x))

(defn score [xs: []int] -> int
  (arr.reduce add 0 xs))`, "arr.reduce(add, 0, xs)"},
        {`(package main)

(defn identity [x: int] -> int
  x)

(defn score [xs: []int] -> [dynamic]int
  (arr.sort-by identity xs))`, "arr.sort_by(identity, xs)"},
        {`(package main)

(defn identity [x: int] -> int
  x)

(defn score [xs: [dynamic]int]
  (arr.sort-by! identity xs))`, "arr.sort_by_bang(identity, xs)"},
        {`(package main)

(defn identity [x: int] -> int
  x)

(defn score [xs: []int] -> [dynamic][]int
  (arr.partition-by identity xs))`, "arr.partition_by(identity, xs)"},
        {`(package main)

(defn identity [x: int] -> int
  x)

(defn score [xs: []int] -> map[int]int
  (arr.index-by identity xs))`, "arr.index_by(identity, xs)"},
        {`(package main)

(defn identity [x: int] -> int
  x)

(defn score [xs: []int] -> map[int][dynamic]int
  (arr.group-by identity xs))`, "arr.group_by(identity, xs)"},
        {`(package main)

(defn identity [x: int] -> int
  x)

(defn score [xs: []int] -> map[int]int
  (arr.count-by identity xs))`, "arr.count_by(identity, xs)"},
        {`(package main)

(defn identity [x: int] -> int
  x)

(defn score [xs: []int] -> map[int]int
  (arr.sum-by identity identity xs))`, "arr.sum_by(identity, identity, xs)"},
        {`(package main)

(defn identity [x: int] -> int
  x)

(defn score [xs: []int] -> [dynamic]int
  (arr.distinct-by identity xs))`, "arr.distinct_by(identity, xs)"},
        {`(package main)

(defn positive? [x: int] -> bool
  (> x 0))

(defn score [xs: []int] -> []int
  (arr.take-while positive? xs))`, "arr.take_while(positive_p, xs)"},
        {`(package main)

(defn positive? [x: int] -> bool
  (> x 0))

(defn score [xs: []int] -> []int
  (arr.drop-while positive? xs))`, "arr.drop_while(positive_p, xs)"},
        {`(package main)

(defn positive? [x: int] -> bool
  (> x 0))

(defn score [xs: []int] -> [value: int, ok: bool]
  (arr.find positive? xs))`, "arr.find(positive_p, xs)"},
        {`(package main)

(defn positive? [x: int] -> bool
  (> x 0))

(defn score [xs: []int] -> bool
  (arr.some? positive? xs))`, "arr.some_p(positive_p, xs)"},
        {`(package main)

(defn positive? [x: int] -> bool
  (> x 0))

(defn score [xs: []int] -> bool
  (arr.every? positive? xs))`, "arr.every_p(positive_p, xs)"},
        {`(package main)

(defn positive? [i: int, x: int] -> bool
  (> x i))

(defn score [xs: []int] -> [index: int, value: int, ok: bool]
  (arr.find-indexed positive? xs))`, "arr.find_indexed(positive_p, xs)"},
        {`(package main)

(defn identity [x: int] -> int
  x)

(defn score [xs: []int] -> [value: int, ok: bool]
  (arr.min-by identity xs))`, "arr.min_by(identity, xs)"},
        {`(package main)

(defn identity [x: int] -> int
  x)

(defn score [xs: []int] -> [value: int, ok: bool]
  (arr.max-by identity xs))`, "arr.max_by(identity, xs)"},
        {`(package main)

(defn score [xs: [dynamic]int]
  (arr.push! xs 1))`, "arr.push_bang(xs, 1)"},
        {`(package main)

(defn inc [x: int] -> int
  x)

(defn score [xs: [dynamic]int]
  (arr.map! inc xs))`, "arr.map_bang(inc, xs)"},
        {`(package main)

(defn positive? [x: int] -> bool
  true)

(defn score [xs: [dynamic]int]
  (arr.filter! positive? xs))`, "arr.filter_bang(positive_p, xs)"},
        {`(package main)

(defn positive? [x: int] -> bool
  true)

(defn score [xs: [dynamic]int]
  (arr.remove! positive? xs))`, "arr.remove_bang(positive_p, xs)"},
        {`(package main)

(defn keep-one [x: int] -> [value: int, ok: bool]
  (return x true))

(defn score [xs: [dynamic]int]
  (arr.keep! keep-one xs))`, "arr.keep_bang(keep_one, xs)"},
        {`(package main)

(defn score [xs: []int] -> [dynamic]int
  (arr.into [dynamic]int xs))`, "arr.into([dynamic]int, xs)"},
        {`(package main)

(defn score [xs: [dynamic]int]
  (arr.into! xs ([]int [1 2])))`, "arr.into_bang(xs, []int{1, 2})"},
    }

    for test_case in cases {
        output, err, ok := kvist.compile_source(test_case.source)
        testing.expect_value(t, ok, true)
        if !ok {
            testing.expect_value(t, err.message, "")
            continue
        }
        testing.expect_value(t, strings.contains(output, test_case.expected), true)
        delete(output)
    }
}

@(test)
compile_leaves_unimported_threaded_package_get_and_slice_unresolved :: proc(t: ^testing.T) {
    cases := []struct {
        source:   string,
        expected: string,
    }{
        {`(package main)

(defn score [xs: []int] -> int
  (->> xs
       (arr.first)))`, "arr.first"},
        {`(package main)

(defn score [xs: []int] -> int
  (->> xs
       (arr.second)))`, "arr.second"},
        {`(package main)

(defn score [xs: []int] -> int
  (->> xs
       (arr.last)))`, "arr.last"},
        {`(package main)

(defn score [xs: []int] -> int
  (->> xs
       (arr.nth 2)))`, "arr.nth"},
        {`(package main)

(defn score [xs: []int] -> []int
  (->> xs
       (arr.rest)))`, "arr.rest"},
    }

    for test_case in cases {
        output, err, ok := kvist.compile_source(test_case.source)
        testing.expect_value(t, ok, true)
        if !ok {
            testing.expect_value(t, err.message, "")
            continue
        }
        testing.expect_value(t, strings.contains(output, test_case.expected), true)
        delete(output)
    }
}

@(test)
compile_leaves_unimported_threaded_package_sequence_helpers_unresolved :: proc(t: ^testing.T) {
    cases := []struct {
        source:   string,
        expected: string,
    }{
        {`(package main)

(defn pair [x: int] -> []int
  ([]int [x x]))

(defn score [xs: []int] -> [dynamic]int
  (let [out (->> xs
                 (arr.mapcat pair))]
    out))`, "arr.mapcat(pair, xs)"},
        {`(package main)

(defn score [keys: []string, vals: []int] -> map[string]int
  (let [out (->> vals
                 (map.zip keys))]
    out))`, "map.zip(keys, vals)"},
        {`(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn score [xs: []int] -> [dynamic]int
  (let [out (->> xs
                 (arr.map inc))]
    out))`, "arr.map(inc, xs)"},
        {`(package main)

(defn positive? [x: int] -> bool
  (> x 0))

(defn score [xs: []int] -> [dynamic]int
  (let [out (->> xs
                 (arr.filter positive?))]
    out))`, "arr.filter(positive_p, xs)"},
        {`(package main)

(defn positive? [x: int] -> bool
  (> x 0))

(defn score [xs: []int] -> [dynamic]int
  (let [out (->> xs
                 (arr.remove positive?))]
    out))`, "arr.remove(positive_p, xs)"},
        {`(package main)

(defn keep-positive [x: int] -> [value: int, ok: bool]
  (return x (> x 0)))

(defn score [xs: []int] -> [dynamic]int
  (let [out (->> xs
                 (arr.keep keep-positive))]
    out))`, "arr.keep(keep_positive, xs)"},
        {`(package main)

(defn positive? [x: int] -> bool
  (> x 0))

(defn score [xs: []int] -> []int
  (->> xs
       (arr.take-while positive?)))`, "arr.take_while(positive_p, xs)"},
    }

    for test_case in cases {
        output, err, ok := kvist.compile_source(test_case.source)
        testing.expect_value(t, ok, true)
        if !ok {
            testing.expect_value(t, err.message, "")
            continue
        }
        testing.expect_value(t, strings.contains(output, test_case.expected), true)
        delete(output)
    }
}

@(test)
compile_leaves_unimported_set_helpers_unresolved :: proc(t: ^testing.T) {
    cases := []struct {
        source:   string,
        expected: string,
    }{
        {`(package main)

(defn score [s: (map int (struct {}))] -> bool
  (set.contains? s 1))`, "set.contains_p(s, 1)"},
        {`(package main)

(defn score [lhs: (map int (struct {})), rhs: (map int (struct {}))] -> (map int (struct {}))
  (set.union lhs rhs))`, "set.union(lhs, rhs)"},
        {`(package main)

(defn score [lhs: (map int (struct {})), rhs: (map int (struct {}))] -> (map int (struct {}))
  (set.intersection lhs rhs))`, "set.intersection(lhs, rhs)"},
        {`(package main)

(defn score [lhs: (map int (struct {})), rhs: (map int (struct {}))] -> (map int (struct {}))
  (set.difference lhs rhs))`, "set.difference(lhs, rhs)"},
        {`(package main)

(defn score [s: (map int (struct {}))] -> (map int (struct {}))
  (set.add s 1))`, "set.add(s, 1)"},
        {`(package main)

(defn score [s: (map int (struct {}))] -> (map int (struct {}))
  (set.remove s 1))`, "set.remove(s, 1)"},
        {`(package main)

(defn score [lhs: (map int (struct {})), rhs: (map int (struct {}))] -> bool
  (set.subset? lhs rhs))`, "set.subset_p(lhs, rhs)"},
        {`(package main)

(defn score [lhs: (map int (struct {})), rhs: (map int (struct {}))] -> bool
  (set.superset? lhs rhs))`, "set.superset_p(lhs, rhs)"},
        {`(package main)

(defn score [lhs: (map int (struct {})), rhs: (map int (struct {}))] -> bool
  (set.disjoint? lhs rhs))`, "set.disjoint_p(lhs, rhs)"},
        {`(package main)

(defn score [] -> int
  (let [s (set.empty int)]
    (count s)))`, "set.empty(int)"},
        {`(package main)

(defn score [] -> int
  (let [s (set.of int [1 2])]
    (count s)))`, "s := set.of(int, kvist_thread_1)"},
        {`(package main)

(defn score [s: (map int (struct {}))]
  (set.add! s 1))`, "set.add_bang(s, 1)"},
        {`(package main)

(defn score [s: (map int (struct {}))]
  (set.remove! s 1))`, "set.remove_bang(s, 1)"},
        {`(package main)

(defn score [target: (map int (struct {})), source: (map int (struct {}))]
  (set.union! target source))`, "set.union_bang(target, source)"},
        {`(package main)

(defn score [target: (map int (struct {})), source: (map int (struct {}))]
  (set.intersection! target source))`, "set.intersection_bang(target, source)"},
        {`(package main)

(defn score [target: (map int (struct {})), source: (map int (struct {}))]
  (set.difference! target source))`, "set.difference_bang(target, source)"},
    }

    for test_case in cases {
        output, err, ok := kvist.compile_source(test_case.source)
        testing.expect_value(t, ok, true)
        if !ok {
            testing.expect_value(t, err.message, "")
            continue
        }
        testing.expect_value(t, strings.contains(output, test_case.expected), true)
        delete(output)
    }
}

@(test)
third_party_source_package_uses_auto_referred_core_helpers :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-third-party-bare-core-*", context.allocator)
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

(defn summarize [xs: []int] -> int
  (let [lookup (make (map int int))
        total 0
        i 0]
    (for [x xs]
      (set! (get lookup x) x))
    (delete! lookup 0)
    (while (< i (count xs))
      (let [x (get xs i)]
        (when (contains? lookup x)
          (set! total (+ total x))))
      (inc! i))
    total))`
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

(defn main [] -> int
  (support.summarize ([]int [0 1 2])))`
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

    testing.expect_value(t, strings.contains(output, "support__summarize :: proc(xs: []int) -> int"), true)
    testing.expect_value(t, strings.contains(output, "len(xs)"), true)
    testing.expect_value(t, strings.contains(output, "delete_key(&(lookup), 0)"), true)
    testing.expect_value(t, strings.contains(output, "support__count"), false)
    testing.expect_value(t, strings.contains(output, "support__get"), false)
    testing.expect_value(t, strings.contains(output, "support__when"), false)
    testing.expect_value(t, strings.contains(output, "support__delete"), false)
}

@(test)
compile_source_package_preserves_nested_imports_and_raw_prefixes :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-nested-source-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    inner_dir, inner_dir_err := os.join_path({dir, "inner"}, context.allocator)
    testing.expect_value(t, inner_dir_err == nil, true)
    if inner_dir_err != nil {
        return
    }
    defer delete(inner_dir)
    facade_dir, facade_dir_err := os.join_path({dir, "facade"}, context.allocator)
    testing.expect_value(t, facade_dir_err == nil, true)
    if facade_dir_err != nil {
        return
    }
    defer delete(facade_dir)
    testing.expect_value(t, os.make_directory_all(inner_dir) == nil, true)
    testing.expect_value(t, os.make_directory_all(facade_dir) == nil, true)

    inner_path, inner_path_err := os.join_path({inner_dir, "inner.kvist"}, context.allocator)
    testing.expect_value(t, inner_path_err == nil, true)
    if inner_path_err != nil {
        return
    }
    defer delete(inner_path)
    inner_source := `(package inner)
(import fmt "core:fmt")

(defn answer [] -> int
  42)

(defn rendered [] -> string
  (fmt.tprintf "%d" (answer)))

(odin "inner__Raw_Box :: struct { value: int }")

(defn raw-box-value [box: inner__Raw_Box] -> int
  box.value)

(odin "inner__raw_answer :: proc() -> int { return inner__answer() }")`
    testing.expect_value(t, os.write_entire_file_from_string(inner_path, inner_source) == nil, true)

    facade_path, facade_path_err := os.join_path({facade_dir, "facade.kvist"}, context.allocator)
    testing.expect_value(t, facade_path_err == nil, true)
    if facade_path_err != nil {
        return
    }
    defer delete(facade_path)
    facade_source := `(package facade)
(import inner "../inner")

(defn rendered [] -> string
  (inner.rendered))`
    testing.expect_value(t, os.write_entire_file_from_string(facade_path, facade_source) == nil, true)

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package main)
(import api "facade")

(defn main [] -> string
  (api.rendered))`
    testing.expect_value(t, os.write_entire_file_from_string(main_path, main_source) == nil, true)

    output, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `import fmt "core:fmt"`), true)
    testing.expect_value(t, strings.contains(output, "api__inner__raw_answer :: proc"), true)
    testing.expect_value(t, strings.contains(output, "box: api__inner__Raw_Box"), true)
    testing.expect_value(t, strings.contains(output, "return api__inner__answer()"), true)
    testing.expect_value(t, strings.contains(output, "return api__inner__rendered()"), true)
}

@(test)
compile_path_rejects_same_import_alias_for_different_paths :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-package-import-conflict-*", context.allocator)
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
(import shared "core:fmt")
(defn main [] -> int 0)`) == nil, true)
    testing.expect_value(t, os.write_entire_file_from_string(helper_path, `(package demo)
(import shared "core:strings")
(defn helper [] -> int 1)`) == nil, true)

    _, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "import alias refers to different paths in package: shared"), true)
}

@(test)
compile_path_keeps_parameter_field_access_when_parameter_shadows_package_alias :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-package-param-shadow-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    helper_dir, helper_dir_err := os.join_path({dir, "helper"}, context.allocator)
    testing.expect_value(t, helper_dir_err == nil, true)
    if helper_dir_err != nil {
        return
    }
    defer delete(helper_dir)
    sample_dir, sample_dir_err := os.join_path({dir, "sample"}, context.allocator)
    testing.expect_value(t, sample_dir_err == nil, true)
    if sample_dir_err != nil {
        return
    }
    defer delete(sample_dir)
    testing.expect_value(t, os.make_directory_all(helper_dir) == nil, true)
    testing.expect_value(t, os.make_directory_all(sample_dir) == nil, true)

    helper_path, helper_path_err := os.join_path({helper_dir, "helper.kvist"}, context.allocator)
    testing.expect_value(t, helper_path_err == nil, true)
    if helper_path_err != nil {
        return
    }
    defer delete(helper_path)
    testing.expect_value(t, os.write_entire_file_from_string(helper_path, `(package helper)

(defn visible [] -> bool true)` ) == nil, true)

    sample_path, sample_path_err := os.join_path({sample_dir, "sample.kvist"}, context.allocator)
    testing.expect_value(t, sample_path_err == nil, true)
    if sample_path_err != nil {
        return
    }
    defer delete(sample_path)
    testing.expect_value(t, os.write_entire_file_from_string(sample_path, `(package sample)

(import data "../helper")

(defstruct Record {has-tempid: bool})

(defn has-tempid? [data: Record] -> bool
  data.has-tempid)

(defn local-has-tempid? [record: Record] -> bool
  (let [data record
        copied data.has-tempid]
    copied))

(defn count-tempids [records: []Record] -> int
  (let [total 0]
    (for [data records]
      (when data.has-tempid
        (inc! total)))
    total))` ) == nil, true)

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)
    testing.expect_value(t, os.write_entire_file_from_string(main_path, `(package main)

(import sample "./sample")

(defn main [] -> bool
  (sample.has-tempid? (sample.Record {has-tempid: true})))` ) == nil, true)

    output, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "return data.has_tempid"), true)
    testing.expect_value(t, strings.contains(output, "data__has_tempid"), false)
}

@(test)
lower_rejects_import_after_declarations :: proc(t: ^testing.T) {
    source := `(package main)
(def answer 42)
(import fmt "core:fmt")`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    formatted := kvist.format_compile_error("bad.kvist", source, err)
    defer delete(formatted)
    expected := `bad.kvist:3:1: import declarations must appear before other declarations
  (import fmt "core:fmt")
  ^
`
    testing.expect_value(t, formatted, expected)
}

@(test)
compile_plain_odin_import_paths :: proc(t: ^testing.T) {
    source := `(package main)
(import native_support "../../../src/odin/native_support")
(import fmt "core:fmt")

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

import native_support "../../../src/odin/native_support"

import fmt "core:fmt"

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
compile_imported_enum_case_stmt_uses_source_conditionals :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-imported-enum-case-*", context.allocator)
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

Kind :: enum {
    One,
    Two,
    Three,
}

Value :: struct {
    kind: Kind,
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

(defn label [value: support.Value] -> string
  (case value.kind
    .One "one"
    .Two "two"
    "other"))`
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

    testing.expect_value(t, strings.contains(output, "kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, "== (.One)"), true)
    testing.expect_value(t, strings.contains(output, "== (.Two)"), true)
    testing.expect_value(t, strings.contains(output, "return \"other\""), true)
    testing.expect_value(t, strings.contains(output, "#partial switch value.kind"), false)
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

(defn main []
  (println (wrap.value)))`
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
    testing.expect_value(t, strings.contains(output, "\"support/raw\""), true)
    testing.expect_value(t, strings.contains(output, "raw.raw_value()"), true)
    testing.expect_value(t, strings.contains(output, "wrap__value()"), true)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)
    child_env, child_env_ok := test_child_env_without_kvist_vars(nil)
    testing.expect_value(t, child_env_ok, true)
    if !child_env_ok {
        return
    }
    defer test_env_slice_delete(&child_env)
    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "check", "main.kvist"},
            working_dir = dir,
            env = child_env[:],
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
    if !state.exited || state.exit_code != 0 {
        testing.expect_value(t, string(stderr), "")
    }
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

(defn main []
  (let [value (+ (support.kvist-value)
                 (support.raw-value))]
    (discard value)))`
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

    testing.expect_value(t, strings.contains(output, "import support__raw "), true)
    testing.expect_value(t, strings.contains(output, "\"support\""), true)
    testing.expect_value(t, strings.contains(output, "support__kvist_value()"), true)
    testing.expect_value(t, strings.contains(output, "support__raw.raw_value()"), true)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    cache_dir, cache_dir_err := os.join_path({dir, "cold-cache"}, context.allocator)
    testing.expect_value(t, cache_dir_err == nil, true)
    if cache_dir_err != nil {
        return
    }
    defer delete(cache_dir)
    cache_env := fmt.tprintf("KVIST_CACHE_DIR=%s", cache_dir)
    child_env, child_env_ok := test_child_env_without_kvist_vars({cache_env})
    testing.expect_value(t, child_env_ok, true)
    if !child_env_ok {
        return
    }
    defer test_env_slice_delete(&child_env)

    generated_path, generated_path_err := os.join_path({dir, "generated", "main.odin"}, context.allocator)
    testing.expect_value(t, generated_path_err == nil, true)
    if generated_path_err != nil {
        return
    }
    defer delete(generated_path)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "check", "main.kvist", "--generated", generated_path},
            working_dir = dir,
            env = child_env[:],
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
    if !state.exited || state.exit_code != 0 {
        testing.expect_value(t, string(stderr), "")
    }
}

@(test)
compile_reload_adapter_state_alias_can_reference_imported_state :: proc(t: ^testing.T) {
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

(def Reload_State app.App_State)

(defn init [state: ^Reload_State]
  (app.init state))

(defn run [state: ^Reload_State host: ^reload.Run_Host]
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

    testing.expect_value(t, strings.contains(output, "Reload_State :: app__App_State"), true)
    testing.expect_value(t, strings.contains(output, "run :: proc(state: ^Reload_State, host: ^reload__Run_Host)"), true)
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

(defstruct App_State
  {requests: int})

(def Reload_State App_State)

(defn run [state: ^Reload_State host: ^reload.Run_Host]
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
    import_prefix := `import runtime "`
    import_start := strings.index(rebased, import_prefix)
    testing.expect_value(t, import_start >= 0, true)
    if import_start >= 0 {
        path_start := import_start + len(import_prefix)
        path_end_offset := strings.index(rebased[path_start:], `"`)
        testing.expect_value(t, path_end_offset >= 0, true)
        if path_end_offset >= 0 {
            testing.expect_value(t, os.is_absolute_path(rebased[path_start:path_start+path_end_offset]), false)
        }
    }
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

(defstruct App_State
  {requests: int})

(def Reload_State App_State)

(defn run [state: ^Reload_State host: ^reload.Run_Host]
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

    repo_root := compiler_test_repo_root()

    runtime_path, runtime_path_err := os.join_path({repo_root, "src", "odin", "olive_reload"}, context.allocator)
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

    rebased_forward, _ := strings.replace_all(rebased, "\\", "/", context.temp_allocator)
    testing.expect_value(t, strings.contains(rebased_forward, "import runtime "), true)
    testing.expect_value(t, strings.contains(rebased_forward, "olive_reload"), true)
    testing.expect_value(t, strings.contains(rebased, "\\src\\odin\\olive_reload"), false)
}

@(test)
compile_absolute_source_package_import :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-absolute-source-import-*", context.allocator)
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
    testing.expect_value(t, os.make_directory_all(support_dir) == nil, true)

    support_path, support_path_err := os.join_path({support_dir, "support.kvist"}, context.allocator)
    testing.expect_value(t, support_path_err == nil, true)
    if support_path_err != nil {
        return
    }
    defer delete(support_path)
    testing.expect_value(t, os.write_entire_file_from_string(support_path, `(package support)
(defn answer [] -> int 42)`) == nil, true)

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)
    main_source := fmt.tprintf("(package main)\n(import support %q)\n(def value (support.answer))", support_dir)
    testing.expect_value(t, os.write_entire_file_from_string(main_path, main_source) == nil, true)

    output, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "support__answer"), true)
    testing.expect_value(t, strings.contains(output, fmt.tprintf("import support %q", support_dir)), false)

    dependencies, dependency_err, dependencies_ok := kvist.source_dependency_paths(main_path)
    testing.expect_value(t, dependencies_ok, true)
    if !dependencies_ok {
        testing.expect_value(t, dependency_err.message, "")
        return
    }
    defer kvist.delete_string_slice(&dependencies)
    main_absolute, main_absolute_err := os.get_absolute_path(main_path, context.allocator)
    support_absolute, support_absolute_err := os.get_absolute_path(support_path, context.allocator)
    testing.expect_value(t, main_absolute_err == nil, true)
    testing.expect_value(t, support_absolute_err == nil, true)
    if main_absolute_err == nil && support_absolute_err == nil {
        defer delete(main_absolute)
        defer delete(support_absolute)
        found_main := false
        found_support := false
        for dependency in dependencies {
            found_main = found_main || dependency == main_absolute
            found_support = found_support || dependency == support_absolute
        }
        testing.expect_value(t, found_main, true)
        testing.expect_value(t, found_support, true)
    }
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
@exports [Raw_Handle]
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
compile_canonical_foreign_import_and_transmute_forms :: proc(t: ^testing.T) {
    source := `(package main)

;; Foreign handle alias.
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
compile_leaves_unimported_direct_str_helpers_unresolved :: proc(t: ^testing.T) {
    cases := []struct {
        name:    string,
        expr:    string,
        expected: string,
    }{
        {"count", `(str.count s)`, `str.count(s)`},
        {"contains", `(str.contains? s "x")`, `str.contains_p`},
        {"split", `(str.split s ",")`, `str.split(s, ",")`},
        {"join", `(str.join parts ",")`, `str.join(parts, ",")`},
        {"trim", `(str.trim s)`, `str.trim(s)`},
        {"trim-prefix", `(str.trim-prefix s "x")`, `str.trim_prefix(s, "x")`},
        {"trim-suffix", `(str.trim-suffix s "x")`, `str.trim_suffix(s, "x")`},
        {"starts-with", `(str.starts-with? s "x")`, `str.starts_with_p(s, "x")`},
        {"ends-with", `(str.ends-with? s "x")`, `str.ends_with_p(s, "x")`},
        {"index-of", `(str.index-of s "x")`, `str.index_of(s, "x")`},
        {"last-index-of", `(str.last-index-of s "x")`, `str.last_index_of(s, "x")`},
        {"replace", `(str.replace s "x" "y")`, `str.replace(s, "x", "y")`},
        {"lower", `(str.lower s)`, `str.lower(s)`},
        {"upper", `(str.upper s)`, `str.upper(s)`},
        {"builder", `(str.builder)`, `str.builder()`},
        {"write", `(str.write! b "x")`, `str.write_bang`},
        {"finish", `(str.finish b)`, `str.finish(b)`},
        {"destroy", `(str.destroy! b)`, `str.destroy_bang(b)`},
        {"unescape", `(str.unescape s)`, `str.unescape(s)`},
        {"get", `(str.get s 0)`, `str.get(s, 0)`},
        {"slice", `(str.slice s 1)`, `str.slice(s, 1)`},
    }

    for c in cases {
        source := fmt.tprintf(`(package main)

(defn demo [s: string parts: []string b: rawptr]
  %s)`, c.expr)

        output, err, ok := kvist.compile_source(source)
        testing.expect_value(t, ok, true)
        if !ok {
            testing.expect_value(t, err.message, c.name)
            continue
        }
        testing.expect_value(t, strings.contains(output, c.expected), true)
        testing.expect_value(t, strings.contains(output, "core:strings"), false)
        delete(output)
    }
}

@(test)
compile_does_not_classify_unimported_str_owned_helper_as_owned :: proc(t: ^testing.T) {
    source := `(package main)

(defn demo [s: string]
  (discard (str.split s ",")))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, strings.contains(result.output, "str.split(s, \",\")"), true)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
warn_discarded_imported_str_split_owned_result :: proc(t: ^testing.T) {
    source := `(package main)
(import str "kvist:str")

(defn demo [s: string]
  (discard (str.split s ",")))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, strings.contains(result.output, "str__split(s, \",\")"), true)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from str.split is discarded; bind it, delete it, or return it")
    }
}

@(test)
warn_discarded_imported_str_finish_owned_result :: proc(t: ^testing.T) {
    source := `(package main)
(import str "kvist:str")

(defn demo []
  (let [builder (str.builder)]
    (defer (str.destroy! (addr builder)))
    (discard (str.finish (addr builder)))))`

    result, err, ok := kvist.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, strings.contains(result.output, "str__finish(&builder)"), true)
    testing.expect_value(t, len(result.warnings), 1)
    if len(result.warnings) == 1 {
        testing.expect_value(t, result.warnings[0].message, "owned result from str.finish is discarded; bind it, delete it, or return it")
    }
}

@(test)
compile_leaves_unimported_direct_map_helpers_unresolved :: proc(t: ^testing.T) {
    cases := []struct {
        source:   string,
        expected: string,
    }{
        {`(package main)

(defn score [m: map[string]int] -> int
  (map.get m "x" 0))`, `map.get(m, "x", 0)`},
        {`(package main)

(defn score [m: map[string]int] -> bool
  (map.contains? m "x"))`, `map.contains_p(m, "x")`},
        {`(package main)

(defn score [m: map[string]int] -> map[string]int
  (map.assoc m "x" 1))`, `map.assoc(m, "x", 1)`},
        {`(package main)

(defn score [m: map[string]int] -> map[string]int
  (map.dissoc m "x"))`, `map.dissoc(m, "x")`},
        {`(package main)

(defn score [m: map[string]int, n: map[string]int] -> map[string]int
  (map.merge m n))`, `map.merge(m, n)`},
        {`(package main)

(defn score [m: map[string]int] -> [dynamic]string
  (map.keys m))`, `map.keys(m)`},
        {`(package main)

(defn score [m: map[string]int] -> [dynamic]int
  (map.vals m))`, `map.vals(m)`},
        {`(package main)

(defn score [keys: []string, vals: []int] -> map[string]int
  (map.zip keys vals))`, "map.zip(keys, vals)"},
        {`(package main)

(defn score [] -> int
  (let [m (map.empty string int)]
    (count m)))`, "map.empty(string, int)"},
        {`(package main)

(defn score [] -> int
  (let [m (map.of string int {"a" 1})]
    (count m)))`, `m := map.of(string, int, kvist_thread_1)`},
        {`(package main)

(defn score [m: map[string]int]
  (map.assoc! m "x" 1))`, `map.assoc_bang(m, "x", 1)`},
        {`(package main)

(defn score [m: map[string]int, n: map[string]int]
  (map.merge! m n))`, "map.merge_bang(m, n)"},
        {`(package main)

(defn score [m: map[string]int]
  (map.dissoc! m "x"))`, `map.dissoc_bang(m, "x")`},
    }

    for test_case in cases {
        output, err, ok := kvist.compile_source(test_case.source)
        testing.expect_value(t, ok, true)
        if !ok {
            testing.expect_value(t, err.message, "")
            continue
        }
        testing.expect_value(t, strings.contains(output, test_case.expected), true)
        delete(output)
    }
}

@(test)
compile_leaves_unimported_threaded_core_package_helpers_unresolved :: proc(t: ^testing.T) {
    cases := []struct {
        source:   string,
        expected: string,
    }{
        {`(package main)

(defn demo [s: string]
  (-> s (str.trim)))`, "str.trim"},
        {`(package main)

(defn demo [s: string] -> bool
  (-> s (str.contains? "x")))`, `str.contains_p`},
        {`(package main)

(defn demo [s: string] -> string
  (-> s (str.unescape)))`, "str.unescape"},
        {`(package main)

(defn demo [b: rawptr]
  (-> b (str.write! "x")))`, `str.write_bang`},
        {`(package main)

(defn demo [b: rawptr] -> string
  (-> b (str.finish)))`, "str.finish"},
        {`(package main)

(defn score [m: map[string]int] -> int
  (let [ks (->> m
                (map.keys))]
    (count ks)))`, "map.keys"},
        {`(package main)

(defn score [m: map[string]int] -> int
  (let [vs (->> m
                (map.vals))]
    (count vs)))`, "map.vals"},
        {`(package main)

(defn score [xs: []int] -> int
  (let [ys (->> xs
                (arr.take 2))]
    (count ys)))`, "arr.take"},
        {`(package main)

(defn score [xs: []int] -> int
  (let [ys (->> xs
                (arr.drop 1))]
    (count ys)))`, "arr.drop"},
        {`(package main)

(defn score [xs: []int] -> int
  (let [ys (->> xs
                (arr.drop-last 1))]
    (count ys)))`, "arr.drop_last"},
        {`(package main)

(defn score [xs: []int] -> int
  (let [ys (->> xs
                (arr.butlast))]
    (count ys)))`, "arr.butlast"},
        {`(package main)

(defn score [xs: []int] -> int
  (let [ys (->> xs
                (arr.partition 2))]
    (count ys)))`, "arr.partition"},
        {`(package main)

(defn score [xs: []int] -> int
  (let [ys (->> xs
                (arr.partition-all 2))]
    (count ys)))`, "arr.partition_all"},
        {`(package main)

(defn score [xs: []int] -> int
  (let [ys (->> xs
                (arr.distinct))]
    (count ys)))`, "arr.distinct"},
        {`(package main)

(defn score [xs: []int] -> int
  (let [ys (->> xs
                (arr.sort))]
    (count ys)))`, "arr.sort"},
    }

    for c in cases {
        output, err, ok := kvist.compile_source(c.source)
        testing.expect_value(t, ok, true)
        if !ok {
            testing.expect_value(t, err.message, "")
            continue
        }
        testing.expect_value(t, strings.contains(output, c.expected), true)
        delete(output)
    }
}

@(test)
compile_leaves_unimported_official_package_helpers_unresolved :: proc(t: ^testing.T) {
    cases := []struct {
        source:   string,
        expected: string,
    }{
        {`(package main)
(import os "core:os")

(defn write-file [path: string, data: []byte] -> os.Error
  (io.write path data))`, "io.write(path, data)"},
        {`(package main)

(defstruct User {
  name: string
})

(defn save-user [path: string, user: User]
  (let [[marshal-err write-err] (json.write path user)]
    (return)))`, "json.write(path, user)"},
        {`(package main)

(defn debug? [args: []string] -> bool
  (cli.flag args "--debug"))`, `cli.flag(args, "--debug")`},
        {`(package main)

(defn demo [] -> string
  (html.render [div "ok"]))`, "html.render{div, \"ok\"}"},
        {`(package main)

(defn demo [] -> string
  (html.render-file "home.html"))`, "html.render_file"},
        {`(package main)
(import os "core:os")

(defn write-file [path: string, data: []byte] -> os.Error
  (-> path
      (io.write data)))`, "io.write(path, data)"},
    }

    for test_case in cases {
        output, err, ok := kvist.compile_source(test_case.source)
        testing.expect_value(t, ok, true)
        if !ok {
            testing.expect_value(t, err.message, "")
            continue
        }
        testing.expect_value(t, strings.contains(output, test_case.expected), true)
        delete(output)
    }
}

@(test)
compile_imported_inferred_lifetime_boundaries :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-owned-boundary-*", context.allocator)
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
    testing.expect_value(t, os.make_directory_all(support_dir) == nil, true)

    support_path, support_path_err := os.join_path({support_dir, "support.kvist"}, context.allocator)
    testing.expect_value(t, support_path_err == nil, true)
    if support_path_err != nil {
        return
    }
    defer delete(support_path)
    support_source := `(package support)
(import arr "kvist:arr")

(defn make-values [] -> [dynamic]int
  (arr.range 0 3))

(defn consume [values: [dynamic]int]
  (delete values))

(defn view [values: []int] -> []int
  values)`
    testing.expect_value(t, os.write_entire_file_from_string(support_path, support_source) == nil, true)

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package main)
(import arr "kvist:arr")
(import support "support")

(defn demo []
  (let [values (support.make-values)]
    (support.consume values)))`
    testing.expect_value(t, os.write_entire_file_from_string(main_path, main_source) == nil, true)

    result, err, ok := kvist.compile_path_with_map(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, strings.contains(result.output, "support__make_values :: proc() -> [dynamic]int"), true)
    testing.expect_value(t, strings.contains(result.output, "support__view :: proc(values: []int) -> []int"), true)
    testing.expect_value(t, strings.contains(result.output, "kvist_owner^ = false"), false)
    testing.expect_value(t, len(result.warnings), 0)
}
