package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

@(test)
compile_malli_types_and_empty_collection_constructors :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")
(import arr "kvist:arr")
(import map "kvist:map")
(import set "kvist:set")

(defn score [xs: [dynamic]int, tags: (map string (struct []))] -> int
    (let [out (arr.empty int 4)
        lookup (map.empty string int)
        seen (set.empty string 8)]
    (arr.push! out (arr.count xs))
    (set! (get lookup "count") (arr.count xs))
    (set.add! seen "ok")
    (+ (arr.get out 0) (map.get lookup "count" 0))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "score :: proc(xs: [dynamic]int, tags: map[string]struct{}) -> int"), true)
    testing.expect_value(t, strings.contains(output, "out := make([dynamic]int, 0, 4)"), true)
    testing.expect_value(t, strings.contains(output, "lookup := make(map[string]int)"), true)
    testing.expect_value(t, strings.contains(output, "seen := make(map[string]struct{}, 8)"), true)
}

@(test)
reject_public_soa_struct_introspection_as_compiler_form :: proc(t: ^testing.T) {
    fields_source := `(package main)
(import soa "kvist:soa")

(defstruct Profile
  [name: string])

(defn main []
  (println (soa/fields 'Profile)))`

    _, err_fields, ok_fields := kvist.compile_source(fields_source)
    testing.expect_value(t, ok_fields, false)
    defer delete(err_fields.message)
    testing.expect_value(t, err_fields.message, "use `soa.fields` for package access")

    types_source := `(package main)
(import soa "kvist:soa")

(defstruct Profile
  [name: string])

(defn main []
  (println (soa/types 'Profile)))`

    _, err_types, ok_types := kvist.compile_source(types_source)
    testing.expect_value(t, ok_types, false)
    defer delete(err_types.message)
    testing.expect_value(t, err_types.message, "use `soa.types` for package access")
}

@(test)
compile_parenthesizes_native_slice_literal_used_as_loop_collection :: proc(t: ^testing.T) {
    source := `(package main)

(defn count-names [] -> int
  (let [count 0]
    (for [name ([]string ["Ada"])]
      (set! count (+ count 1)))
    count))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `for name in ([]string{"Ada"}) {`), true)
}

@(test)
compile_sequence_trim_helpers_as_slice_views :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn keep? [x: int] -> bool
  (< x 4))

(defn main []
  (let [xs ([]int [1 2 3 4])
        prefix (arr.take 2 xs)
        suffix (arr.drop 1 xs)
        without-last (arr.butlast xs)
        without-two (arr.drop-last 2 xs)
        small-prefix (arr.take-while keep? xs)
        large-suffix (arr.drop-while keep? xs)
        threaded-count (->> xs
                            (arr.drop-last 1)
                            (count))]
    (return)))`

    dir, dir_err := os.make_directory_temp("", "kvist-trim-source-package-*", context.allocator)
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

    write_err := os.write_entire_file(path, transmute([]byte)source)
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

    testing.expect_value(t, strings.contains(output, "prefix := arr__take(2, xs)"), true)
    testing.expect_value(t, strings.contains(output, "suffix := arr__drop(1, xs)"), true)
    testing.expect_value(t, strings.contains(output, "without_last := arr__butlast(xs)"), true)
    testing.expect_value(t, strings.contains(output, "without_two := arr__drop_last(2, xs)"), true)
    testing.expect_value(t, strings.contains(output, "small_prefix := arr__take_while_impl(keep_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "large_suffix := arr__drop_while_impl(keep_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "threaded_count := len(arr__drop_last(1, xs))"), true)
    testing.expect_value(t, strings.contains(output, "arr__take :: #force_inline proc(n: int, xs: []$T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return (xs)[0:limit]"), true)
    testing.expect_value(t, strings.contains(output, "#borrowed"), false)
    testing.expect_value(t, strings.contains(output, "arr__drop :: #force_inline proc(n: int, xs: []$T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return (xs)[start:]"), true)
    testing.expect_value(t, strings.contains(output, "arr__drop_last :: #force_inline proc(n: int, xs: []$T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return (xs)[0:end]"), true)
    testing.expect_value(t, strings.contains(output, "arr__take_while_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return (xs)[0:i]"), true)
    testing.expect_value(t, strings.contains(output, "arr__drop_while_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return (xs)[i:]"), true)
    testing.expect_value(t, strings.contains(output, "kvist_take :: proc(n: int, xs: []$T) -> []T"), false)
    testing.expect_value(t, strings.contains(output, "kvist_drop :: proc(n: int, xs: []$T) -> []T"), false)
    testing.expect_value(t, strings.contains(output, "kvist_drop_last :: proc(n: int, xs: []$T) -> []T"), false)
}

@(test)
compile_additional_sequence_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn even? [x: int] -> bool
  (= (% x 2) 0))

(defn add-index [i: int, x: int] -> int
  (+ i x))

(defn keep-even [x: int] -> [value: int, ok: bool]
  (if (even? x)
    (return x true)
    (return 0 false)))

(defn pair [x: int] -> []int
  ([]int [x (+ x 10)]))

(defn main []
  (let [xs ([]int [1 2 3])
        ys ([]int [4 5])
        without-evens (arr.remove even? xs)
        kept (arr.keep keep-even xs)
        joined (arr.concat without-evens ys)
        threaded-sorted (->> xs
                             (arr.remove even?)
                             (arr.keep keep-even))]
    (defer (delete without-evens))
    (defer (delete kept))
    (defer (delete joined))
    (defer (delete threaded-sorted))
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "without_evens := arr__remove_impl(even_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "kept := arr__keep_impl(keep_even, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "joined := arr__concat((without_evens)[:], ys)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_1 := arr__remove_impl(even_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "threaded_sorted := arr__keep_impl(keep_even,"), true)
    testing.expect_value(t, strings.contains(output, "arr__concat :: #force_inline proc(xs: []$T, ys: []T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "arr__remove_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "arr__keep_impl :: #force_inline proc(f: proc(x: $T) -> (value: $U, ok: bool), xs: []T) -> [dynamic]U"), true)
    testing.expect_value(t, strings.contains(output, "kvist_concat :: proc"), false)
    testing.expect_value(t, strings.contains(output, "kvist_sort :: proc(xs: []$T) -> [dynamic]T"), false)
    testing.expect_value(t, strings.contains(output, "kvist_sort_in_place :: proc(xs: []$T)"), false)
}

@(test)
compile_chunking_and_zipmap_sequence_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")
(import map "kvist:map")

(defn even? [x: int] -> bool
  (= (% x 2) 0))

(defn identity [x: int] -> int
  x)

(defn parity [x: int] -> int
  (% x 2))

(defn main []
  (let [xs ([]int [1 2 2 3 3 3])
        names ([]string ["Ada" "Lin"])
        ages ([]int [36 17])
        [front back] (arr.split-at 2 xs)
        chunks (arr.partition 2 xs)
        chunks-all (arr.partition-all 3 xs)
        by-run (arr.partition-by identity xs)
        by-name (map.zip names ages)
        by-parity (arr.group-by parity xs)
        unique (arr.distinct xs)
        distinct-parity (arr.distinct-by parity xs)
        threaded (->> xs
                      (arr.remove even?)
                      (arr.distinct)
                      (arr.partition-by identity))]
    (defer (delete chunks))
    (defer (delete chunks-all))
    (defer (delete by-run))
    (defer (delete by-name))
    (defer
      (for [_ group by-parity]
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

    testing.expect_value(t, strings.contains(output, "front, back := arr__split_at(2, xs)"), true)
    testing.expect_value(t, strings.contains(output, "chunks := arr__partition(2, xs)"), true)
    testing.expect_value(t, strings.contains(output, "chunks_all := arr__partition_all(3, xs)"), true)
    testing.expect_value(t, strings.contains(output, "by_run := arr__partition_by_impl(identity, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "by_name := map__zip(names, ages)"), true)
    testing.expect_value(t, strings.contains(output, "by_parity := arr__group_by_impl(parity, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "unique := arr__distinct_impl((xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "distinct_parity := arr__distinct_by_impl(parity, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "for _, group in by_parity {"), true)
    testing.expect_value(t, strings.contains(output, "delete(group)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_1 := arr__remove_impl(even_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "arr__distinct_impl("), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_"), true)
    testing.expect_value(t, strings.contains(output, "threaded := arr__partition_by_impl(identity,"), true)
    testing.expect_value(t, strings.contains(output, "arr__split_at :: #force_inline proc(n: int, xs: []$T) -> (left: []T, right: []T) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__partition :: #force_inline proc(n: int, xs: []$T) -> [dynamic][]T {"), true)
    testing.expect_value(t, strings.contains(output, "arr__partition_all :: #force_inline proc(n: int, xs: []$T) -> [dynamic][]T {"), true)
    testing.expect_value(t, strings.contains(output, "arr__partition_by_impl :: #force_inline proc(f: proc(x: $T) -> $K, xs: []T) -> [dynamic][]T {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_partition_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> [dynamic][]T"), false)
    testing.expect_value(t, strings.contains(output, "map__zip :: #force_inline proc(ks: []$K, vs: []$V) -> map[K]V {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_zipmap :: proc(keys: []$K, values: []$V) -> map[K]V"), false)
    testing.expect_value(t, strings.contains(output, "kvist_partition :: proc(n: int, xs: []$T) -> [dynamic][]T"), false)
    testing.expect_value(t, strings.contains(output, "kvist_partition_all :: proc(n: int, xs: []$T) -> [dynamic][]T"), false)
    testing.expect_value(t, strings.contains(output, "map__arr__group_by_impl :: #force_inline proc(f: proc(x: $T) -> $K, xs: []T) -> map[K][dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_group_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> map[K][dynamic]T"), false)
    testing.expect_value(t, strings.contains(output, "map__arr__distinct_impl :: #force_inline proc(xs: []$T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_distinct :: proc(xs: []$T) -> [dynamic]T"), false)
    testing.expect_value(t, strings.contains(output, "map__arr__distinct_by_impl :: #force_inline proc(f: proc(x: $T) -> $K, xs: []T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_distinct_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> [dynamic]T"), false)
    testing.expect_value(t, strings.contains(output, "kvist_split_at"), false)
}

@(test)
compile_map_constructing_sequence_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")
(import map "kvist:map")

(defn identity [x: int] -> int
  x)

(defn amount [x: int] -> int
  x)

(defn main []
  (let [xs ([]int [1 2 2 3])
        by-value (arr.index-by identity xs)
        by-group (arr.group-by identity xs)
        by-sum (arr.sum-by identity amount xs)
        counts (arr.frequencies xs)
        base (map[string]int {"a" 1 "b" 2})
        overrides (map[string]int {"b" 20 "c" 30})
        merged (map.merge base overrides)
        key-list (map.keys base)
        value-list (map.vals overrides)
        key-count (->> merged
                       (map.keys)
                       (count))]
    (defer (delete by-value))
    (defer
      (for [_ group by-group]
        (delete group))
      (delete by-group))
    (defer (delete by-sum))
    (defer (delete counts))
    (defer (delete base))
    (defer (delete overrides))
    (defer (delete merged))
    (defer (delete key-list))
    (defer (delete value-list))
    (when (= key-count 0)
      (return))
    (map.merge! base overrides)
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "by_value := arr__index_by_impl(identity, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "by_group := arr__group_by_impl(identity, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "by_sum := arr__sum_by_impl(identity, amount,"), true)
    testing.expect_value(t, strings.contains(output, "counts := arr__frequencies_impl((xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "map__merge :: #force_inline proc(lhs, rhs: map[$K]$V) -> map[K]V {"), true)
    testing.expect_value(t, strings.contains(output, "map__keys :: #force_inline proc(m: map[$K]$V) -> [dynamic]K {"), true)
    testing.expect_value(t, strings.contains(output, "map__vals :: #force_inline proc(m: map[$K]$V) -> [dynamic]V {"), true)
    testing.expect_value(t, strings.contains(output, "merged := map__merge(base, overrides)"), true)
    testing.expect_value(t, strings.contains(output, "key_list := map__keys(base)"), true)
    testing.expect_value(t, strings.contains(output, "value_list := map__vals(overrides)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_1 := map__keys(merged)"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "key_count := len("), true)
    testing.expect_value(t, strings.contains(output, "map__keys(merged)"), true)
    testing.expect_value(t, strings.contains(output, "for key, value in overrides {"), true)
    testing.expect_value(t, strings.contains(output, "base[key] = value"), true)
    testing.expect_value(t, strings.contains(output, "map__arr__index_by_impl :: #force_inline proc(f: proc(x: $T) -> $K, xs: []T) -> map[K]T {"), true)
    testing.expect_value(t, strings.contains(output, "map__arr__group_by_impl :: #force_inline proc(f: proc(x: $T) -> $K, xs: []T) -> map[K][dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_group_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> map[K][dynamic]T"), false)
    testing.expect_value(t, strings.contains(output, "kvist_count_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> map[K]int"), false)
    testing.expect_value(t, strings.contains(output, "kvist_index_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> map[K]T"), false)
    testing.expect_value(t, strings.contains(output, "map__arr__sum_by_impl :: #force_inline proc(key_f: proc(x: $T) -> $K, value_f: proc(x: T) -> $V, xs: []T) -> map[K]V {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sum_by :: proc(key_f: proc(x: $T) -> $K, value_f: proc(x: T) -> $V, xs: []T) -> map[K]V"), false)
    testing.expect_value(t, strings.contains(output, "map__arr__frequencies_impl :: #force_inline proc(xs: []$T) -> map[T]int {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_frequencies :: proc(xs: []$T) -> map[T]int"), false)
    testing.expect_value(t, strings.contains(output, "kvist_merge :: proc(lhs, rhs: map[$K]$V) -> map[K]V"), false)
    testing.expect_value(t, strings.contains(output, "kvist_merge_in_place"), false)
    testing.expect_value(t, strings.contains(output, "kvist_keys :: proc(m: map[$K]$V) -> [dynamic]K"), false)
    testing.expect_value(t, strings.contains(output, "kvist_vals :: proc(m: map[$K]$V) -> [dynamic]V"), false)
}

@(test)
compile_bounded_sequence_producers :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn next [] -> int
  42)

(defn double [x: int] -> int
  (* x 2))

(defn main []
  (let [xs (arr.range 1 5)
        ys (arr.repeat 3 "x")
        zs (arr.repeatedly 2 next)
        powers (arr.iterate 4 double 1)
        cycled (arr.cycle 5 ([]int [1 2]))]
    (defer (delete xs))
    (defer (delete ys))
    (defer (delete zs))
    (defer (delete powers))
    (defer (delete cycled))
    (return)))`

    dir, dir_err := os.make_directory_temp("", "kvist-bounded-producers-*", context.allocator)
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

    write_err := os.write_entire_file(path, transmute([]byte)source)
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

    testing.expect_value(t, strings.contains(output, "xs := (proc(kvist_source_arg_1: int, kvist_source_arg_2: int, kvist_source_arg_3: int) -> [dynamic]int {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_source := arr__range_impl(kvist_source_arg_1, kvist_source_arg_2, kvist_source_arg_3)"), true)
    testing.expect_value(t, strings.contains(output, "arr__range_next(&kvist_source)"), true)
    testing.expect_value(t, strings.contains(output, "append(&kvist_out, kvist_item)"), true)
    testing.expect_value(t, strings.contains(output, "ys := (proc(kvist_source_arg_1: int, kvist_source_arg_2: string) -> [dynamic]string {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_source := arr__repeat_impl(kvist_source_arg_1, kvist_source_arg_2)"), true)
    testing.expect_value(t, strings.contains(output, "arr__repeat_next(&kvist_source)"), true)
    testing.expect_value(t, strings.contains(output, "zs := (proc(kvist_source_arg_1: int, kvist_source_arg_2: proc() -> int) -> [dynamic]int {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_source := arr__repeatedly_impl(kvist_source_arg_1, kvist_source_arg_2)"), true)
    testing.expect_value(t, strings.contains(output, "arr__repeatedly_next(&kvist_source)"), true)
    testing.expect_value(t, strings.contains(output, "powers := (proc(kvist_source_arg_1: int, kvist_source_arg_2: proc(x: int) -> int, kvist_source_arg_3: int) -> [dynamic]int {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_source := arr__iterate_impl(kvist_source_arg_1, kvist_source_arg_2, kvist_source_arg_3)"), true)
    testing.expect_value(t, strings.contains(output, "arr__iterate_next(&kvist_source)"), true)
    testing.expect_value(t, strings.contains(output, "cycled := (proc(kvist_source_arg_1: int, kvist_source_arg_2: []int) -> [dynamic]int {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_source := arr__cycle_impl(kvist_source_arg_1, kvist_source_arg_2)"), true)
    testing.expect_value(t, strings.contains(output, "arr__cycle_next(&kvist_source)"), true)
    testing.expect_value(t, strings.contains(output, "arr__range_impl :: proc(start: int, end: int, step: int) -> arr__Range_Source {"), true)
    testing.expect_value(t, strings.contains(output, "arr__Repeat_Source :: struct($T: typeid) {value: T, index: int, count: int}"), true)
    testing.expect_value(t, strings.contains(output, "arr__repeat_impl :: proc(n: int, value: $T) -> arr__Repeat_Source(T) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__Repeatedly_Source :: struct($T: typeid) {f: proc() -> T, zero: T, index: int, count: int}"), true)
    testing.expect_value(t, strings.contains(output, "arr__repeatedly_impl :: proc(n: int, f: proc() -> $T) -> arr__Repeatedly_Source(T) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__Iterate_Source :: struct($T: typeid) {f: proc(x: T) -> T, current: T, index: int, count: int}"), true)
    testing.expect_value(t, strings.contains(output, "arr__iterate_impl :: proc(n: int, f: proc(x: $T) -> T, init: T) -> arr__Iterate_Source(T) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__Cycle_Source :: struct($T: typeid) {xs: []T, zero: T, index: int, count: int, size: int}"), true)
    testing.expect_value(t, strings.contains(output, "arr__cycle_impl :: proc(n: int, xs: []$T) -> arr__Cycle_Source(T) {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_range"), false)
    testing.expect_value(t, strings.contains(output, "kvist_repeat"), false)
    testing.expect_value(t, strings.contains(output, "kvist_repeatedly"), false)
    testing.expect_value(t, strings.contains(output, "kvist_iterate"), false)
    testing.expect_value(t, strings.contains(output, "kvist_cycle"), false)
}

@(test)
compile_field_selector_callbacks_for_sequence_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defstruct User [
  name: string
  amount: int
  verified: bool
])

(defn main []
  (let [users ([]User [(User :name "Ada" :amount 10 :verified true)
                           (User :name "Lin" :amount 20 :verified false)])
        names (arr.map .name users)
        by-name (arr.index-by .name users)
        by-verified (arr.group-by .verified users)
        count-by-verified (arr.count-by .verified users)
        sum-by-verified (arr.sum-by .verified .amount users)
        groups (arr.partition-by .verified users)
        distinct-names (arr.distinct-by .name users)
        sorted (arr.sort-by .name users)
        mutated ([dynamic]User [(User :name "Ada" :amount 10 :verified true)
                                    (User :name "Lin" :amount 20 :verified false)])
        verified (arr.filter .verified users)
        unverified (arr.remove .verified users)
        [first ok] (arr.find .verified users)
        any? (arr.some? .verified users)
        all? (arr.every? .verified verified)
        prefix (arr.take-while .verified users)
        suffix (arr.drop-while .verified users)]
    (defer
      (for [_ group by-verified]
        (delete group))
      (delete by-verified))
    (arr.sort-by! .name mutated)
    (arr.filter! .verified mutated)
    (arr.remove! .verified mutated)
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "names := arr__map_impl__kvist_field_0_name(type_of(((users)[0:])[0]), type_of(((users)[0:])[0].name), (users)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "by_name := arr__index_by_impl__kvist_field_0_name(type_of(((users)[0:])[0]), type_of(((users)[0:])[0].name), (users)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "by_verified := arr__group_by_impl__kvist_field_0_verified(type_of(((users)[0:])[0]), type_of(((users)[0:])[0].verified), (users)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "count_by_verified := arr__count_by_impl__kvist_field_0_verified(type_of(((users)[0:])[0]), type_of(((users)[0:])[0].verified), (users)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "sum_by_verified := arr__sum_by_impl__kvist_field_0_verified__kvist_field_1_amount(type_of(((users)[0:])[0]), type_of(((users)[0:])[0].verified), type_of(((users)[0:])[0].amount), (users)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "groups := arr__partition_by_impl__kvist_field_0_verified(type_of(((users)[0:])[0]), type_of(((users)[0:])[0].verified), (users)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "distinct_names := arr__distinct_by_impl__kvist_field_0_name(type_of(((users)[0:])[0]), type_of(((users)[0:])[0].name), (users)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "sorted := arr__sort_by_impl__kvist_field_0_name(type_of(((users)[0:])[0]), type_of(((users)[0:])[0].name), (users)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__sort_by_bang_impl__kvist_field_0_name(type_of(((mutated)[0:])[0]), type_of(((mutated)[0:])[0].name), (mutated)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__filter_bang_impl__kvist_field_0_verified(type_of(((&mutated)^)[0]), &mutated)"), true)
    testing.expect_value(t, strings.contains(output, "arr__remove_bang_impl__kvist_field_0_verified(type_of(((&mutated)^)[0]), &mutated)"), true)
    testing.expect_value(t, strings.contains(output, "verified := arr__filter_impl__kvist_field_0_verified(type_of(((users)[0:])[0]), (users)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "unverified := arr__remove_impl__kvist_field_0_verified(type_of(((users)[0:])[0]), (users)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "first, ok := arr__find_impl__kvist_field_0_verified(type_of(((users)[0:])[0]), (users)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "any_p := arr__some_impl__kvist_field_0_verified(type_of(((users)[0:])[0]), (users)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "all_p := arr__every_impl__kvist_field_0_verified(type_of(((verified)[0:])[0]), (verified)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "prefix := arr__take_while_impl__kvist_field_0_verified(type_of(((users)[0:])[0]), (users)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "suffix := arr__drop_while_impl__kvist_field_0_verified(type_of(((users)[0:])[0]), (users)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_impl__kvist_field_0_name :: proc($T: typeid, $U: typeid, xs: []T) -> [dynamic]U"), true)
    testing.expect_value(t, strings.contains(output, "arr__index_by_impl__kvist_field_0_name :: proc($T: typeid, $K: typeid, xs: []T) -> map[K]T"), true)
    testing.expect_value(t, strings.contains(output, "arr__group_by_impl__kvist_field_0_verified :: proc($T: typeid, $K: typeid, xs: []T) -> map[K][dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "arr__count_by_impl__kvist_field_0_verified :: proc($T: typeid, $K: typeid, xs: []T) -> map[K]int"), true)
    testing.expect_value(t, strings.contains(output, "arr__sum_by_impl__kvist_field_0_verified__kvist_field_1_amount :: proc($T: typeid, $K: typeid, $V: typeid, xs: []T) -> map[K]V"), true)
    testing.expect_value(t, strings.contains(output, "arr__partition_by_impl__kvist_field_0_verified :: proc($T: typeid, $K: typeid, xs: []T) -> [dynamic][]T"), true)
    testing.expect_value(t, strings.contains(output, "arr__distinct_by_impl__kvist_field_0_name :: proc($T: typeid, $K: typeid, xs: []T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "arr__sort_by_impl__kvist_field_0_name :: proc($T: typeid, $K: typeid, xs: []T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "arr__sort_by_bang_impl__kvist_field_0_name :: proc($T: typeid, $K: typeid, xs: []T)"), true)
    testing.expect_value(t, strings.contains(output, "arr__sort_by_items_bang :: proc(items: []arr__Sort_By_Item($K, $T))"), true)
    testing.expect_value(t, strings.contains(output, "kvist_slice.sort_by(items, proc(a, b: arr__Sort_By_Item(K, T)) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "append(&items, arr__Sort_By_Item(K, T){key = x.name, value = x})"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sort_by_field_name"), false)
    testing.expect_value(t, strings.contains(output, "kvist_sort_by_in_place_field_name"), false)
    testing.expect_value(t, strings.contains(output, "arr__filter_bang_impl__kvist_field_0_verified :: proc($T: typeid, xs: ^[dynamic]T)"), true)
    testing.expect_value(t, strings.contains(output, "arr__remove_bang_impl__kvist_field_0_verified :: proc($T: typeid, xs: ^[dynamic]T)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_filter_in_place_field_verified"), false)
    testing.expect_value(t, strings.contains(output, "kvist_remove_in_place_field_verified"), false)
    testing.expect_value(t, strings.contains(output, "arr__filter_impl__kvist_field_0_verified :: proc($T: typeid, xs: []T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "arr__remove_impl__kvist_field_0_verified :: proc($T: typeid, xs: []T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_map_field_name"), false)
    testing.expect_value(t, strings.contains(output, "kvist_filter_field_verified"), false)
    testing.expect_value(t, strings.contains(output, "kvist_remove_field_verified"), false)
    testing.expect_value(t, strings.contains(output, "arr__find_impl__kvist_field_0_verified :: proc($T: typeid, xs: []T) -> (value: T, ok: bool)"), true)
    testing.expect_value(t, strings.contains(output, "arr__some_impl__kvist_field_0_verified :: proc($T: typeid, xs: []T) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "arr__every_impl__kvist_field_0_verified :: proc($T: typeid, xs: []T) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "arr__take_while_impl__kvist_field_0_verified :: proc($T: typeid, xs: []T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "arr__drop_while_impl__kvist_field_0_verified :: proc($T: typeid, xs: []T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "kvist_find_field_verified"), false)
    testing.expect_value(t, strings.contains(output, "kvist_some_p_field_verified"), false)
    testing.expect_value(t, strings.contains(output, "kvist_every_p_field_verified"), false)
    testing.expect_value(t, strings.contains(output, "kvist_take_while_field_verified"), false)
    testing.expect_value(t, strings.contains(output, "kvist_drop_while_field_verified"), false)
    testing.expect_value(t, strings.contains(output, "kvist_index_by_field_name"), false)
    testing.expect_value(t, strings.contains(output, "kvist_group_by_field_verified"), false)
    testing.expect_value(t, strings.contains(output, "kvist_count_by_field_verified"), false)
    testing.expect_value(t, strings.contains(output, "kvist_partition_by_field_verified"), false)
    testing.expect_value(t, strings.contains(output, "kvist_distinct_by_field_name"), false)
    testing.expect_value(t, strings.contains(output, "kvist_sum_by_fields_verified_amount"), false)
}

@(test)
compile_sequence_indexing_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")
(import arr "kvist:arr")

(defn main []
  (let [xs ([]int [10 20 30])
        a (arr.first xs)
        b (arr.second xs)
        c (arr.nth 2 xs)
        n (count xs)
        tail (arr.rest xs)
        threaded-first (->> xs
                            (arr.first))
        threaded-second (->> xs
                             (arr.second))
        threaded-nth (->> xs
                         (arr.nth 2))
        threaded-last (->> xs
                           (arr.last))
        threaded (->> xs
                      (arr.rest)
                      (count))]
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "a := xs[0]"), true)
    testing.expect_value(t, strings.contains(output, "b := xs[1]"), true)
    testing.expect_value(t, strings.contains(output, "c := xs[2]"), true)
    testing.expect_value(t, strings.contains(output, "n := len(xs)"), true)
    testing.expect_value(t, strings.contains(output, "tail := (xs)[1:]"), true)
    testing.expect_value(t, strings.contains(output, "threaded_first := xs[0]"), true)
    testing.expect_value(t, strings.contains(output, "threaded_second := xs[1]"), true)
    testing.expect_value(t, strings.contains(output, "threaded_nth := xs[2]"), true)
    testing.expect_value(t, strings.contains(output, "threaded_last := xs[(len(xs)) - (1)]"), true)
    testing.expect_value(t, strings.contains(output, "threaded := len((xs)[1:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__rest(xs)"), false)
}

@(test)
compile_does_not_infer_third_party_dynamic_array_when_input_may_be_returned :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-owned-return-package-negative-*", context.allocator)
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

(defn keep-or-new [xs: [dynamic]int, allocate?: bool] -> [dynamic]int #force_inline
  (if allocate?
    (make [dynamic]int)
    xs))`
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
  (let [xs (make [dynamic]int)]
    (defer (delete xs))
    (support.keep-or-new xs false)
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

    testing.expect_value(t, strings.contains(result.output, "support__keep_or_new :: #force_inline proc("), true)
    testing.expect_value(t, strings.contains(result.output, ") -> [dynamic]int"), true)
    testing.expect_value(t, strings.contains(result.output, "#owned"), false)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
report_namespaced_sequence_helper_errors_with_surface_name :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn inc [x: int] -> int
  (+ x 1))

(defn main [xs: []int]
  (let [mapped (arr.map inc)]
    (return mapped)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "arr.map expects 2 arguments")
}

@(test)
compile_collection_type_forms_and_make :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct State [
  values: (slice int)
  buffer: (dynamic int)
  lookup: (map string int)
  next: (ptr State)
])

(defn main []
  (let [values ((slice int) [1 2 3])
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
compile_soa_type_call_column_access_and_push :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")
(import arr "kvist:arr")
(import soa "kvist:soa")

(defstruct Particle [
  mass: f32
  id: int
])

(defn fixed-first [] -> f32
  (let [particles (#soa[2]Particle
                    [(Particle :mass 1 :id 10)
                     (Particle :mass 2 :id 20)])]
    (arr.get particles.mass 0)))

(defn add-particle! [particles: ^#soa[dynamic]Particle
                     particle: Particle]
  (append_soa particles particle)
  (return))

(defn dynamic-score [] -> f32
  (let [particles (#soa[dynamic]Particle
                    [(Particle :mass 1 :id 10)])]
    (defer (delete particles))
    (soa.push! (addr particles) (Particle :mass 2 :id 20))
    (set! particles.mass[0] 12)
    (+ (arr.get particles.mass 0)
       (arr.get particles 1).mass)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "fixed_first :: proc() -> f32"), true)
    testing.expect_value(t, strings.contains(output, "particles := #soa[2]Particle{"), true)
    testing.expect_value(t, strings.contains(output, "return particles.mass[0]"), true)
    testing.expect_value(t, strings.contains(output, "add_particle_bang :: proc(particles: ^#soa[dynamic]Particle, particle: Particle)"), true)
    testing.expect_value(t, strings.contains(output, "append_soa(particles, particle)"), true)
    testing.expect_value(t, strings.contains(output, "dynamic_score :: proc() -> f32"), true)
    testing.expect_value(t, strings.contains(output, "particles := (proc() -> #soa[dynamic]Particle {"), true)
    testing.expect_value(t, strings.contains(output, "out := make(#soa[dynamic]Particle)"), true)
    testing.expect_value(t, strings.contains(output, "append_soa(&out, Particle{"), true)
    testing.expect_value(t, strings.contains(output, "append_soa(&particles, Particle{"), true)
    testing.expect_value(t, strings.contains(output, "(particles.mass)[0] = 12"), true)
    testing.expect_value(t, strings.contains(output, "return (particles.mass[0]) + (particles[1].mass)"), true)
}

@(test)
reject_soa_make_raw_as_compiler_form :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Particle [
  x: f32
])

(defn main []
  (soa-make-raw #soa[dynamic]Particle 7))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "soa_make_raw(#soa[dynamic]Particle, 7)"), true)
    testing.expect_value(t, strings.contains(output, "make(#soa[dynamic]Particle, 0, 7)"), false)
}

@(test)
compile_soa_column_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import soa "kvist:soa")

(defstruct Particle [
  x: f32
  vx: f32
])

(defn update-columns [] -> f32
  (let [particles (soa.make Particle 2)]
    (defer (delete particles))
    (soa.push! (addr particles) (Particle :x 1 :vx 2))
    (soa.push! (addr particles) (Particle :x 3 :vx 4))
    (soa.axpy! particles .x 0.5 .vx)
    (soa.clamp! particles .x 0.0 4.0)
    (let [total: f32 0]
      (soa.sum-into! total particles .x)
      (soa.dot-into! total particles .vx .vx)
      total)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "particles.x[i] += (0.5) * (particles.vx[i])"), true)
    testing.expect_value(t, strings.contains(output, "if (particles.x[i]) < (0.0)"), true)
    testing.expect_value(t, strings.contains(output, "total += particles.x[i]"), true)
    testing.expect_value(t, strings.contains(output, "total += (particles.vx[i]) * (particles.vx[i])"), true)
}

@(test)
compile_bit_set_and_simd_surface_type_constructors :: proc(t: ^testing.T) {
    source := `(package main)
(import intrinsics "base:intrinsics")

(defenum Permission [
  Read
  Write
  Execute
])

(defn permissions [] -> bit_set[Permission; u8]
  (bit_set[Permission; u8] [.Read .Execute]))

(defn simd-score [] -> f32
  (let [v (#simd[4]f32 [1.0 2.0 3.0 4.0])
        doubled (intrinsics.simd_add v v)]
    (intrinsics.simd_reduce_add_ordered doubled)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "permissions :: proc() -> bit_set[Permission; u8]"), true)
    testing.expect_value(t, strings.contains(output, "return bit_set[Permission; u8]{.Read, .Execute}"), true)
    testing.expect_value(t, strings.contains(output, "v := #simd[4]f32{1.0, 2.0, 3.0, 4.0}"), true)
    testing.expect_value(t, strings.contains(output, "doubled := intrinsics.simd_add(v, v)"), true)
    testing.expect_value(t, strings.contains(output, "return intrinsics.simd_reduce_add_ordered(doubled)"), true)
}

@(test)
compile_array_map_literals_and_typed_let_type_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Config [
  ports: (array 3 int)
  lookup: (map string int)
])

(defn main []
  (let [ports: (array 3 int) ((array 3 int) [80 443 8080])
        lookup: (map string int) ((map string int) {"http" 80 "https" 443})]
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
compile_typed_map_literal_passes_value_type_to_let_values :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Entry [
  attrs: [dynamic]string
])

(defn entries [] -> map[string]Entry
  (map[string]Entry
    {"one" (let [attrs ([dynamic]string ["name" "email"])]
             (Entry :attrs attrs))}))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return map[string]Entry{"), true)
    testing.expect_value(t, strings.contains(output, "\"one\" = (proc() -> Entry {"), true)
    testing.expect_value(t, strings.contains(output, "attrs := [dynamic]string{\"name\", \"email\"}"), true)
}

@(test)
compile_typed_set_literal_passes_element_type_to_let_items :: proc(t: ^testing.T) {
    source := `(package main)

(defn tags [] -> (map string (struct []))
  ((map string (struct [])) #{(let [tag "name"] tag)}))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "tags :: proc() -> map[string]struct{}"), true)
    testing.expect_value(t, strings.contains(output, "(proc() -> string {"), true)
    testing.expect_value(t, strings.contains(output, "tag := \"name\""), true)
}

@(test)
compile_keyword_key_map_literal :: proc(t: ^testing.T) {
    source := `(package main)

(defn states [] -> map[keyword]int
  {:job/ready 1
   :job/done 2})`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `#+feature dynamic-literals
package main

states :: proc() -> map[keyword]int {
    return map[keyword]int{keyword(":job/ready") = 1, keyword(":job/done") = 2}
}

keyword :: distinct string
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_keyword_set_literal :: proc(t: ^testing.T) {
    source := `(package main)

(defn modes [] -> (map keyword (struct []))
  #{:env/dev :env/prod})`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `#+feature dynamic-literals
package main

modes :: proc() -> map[keyword]struct{} {
    return map[keyword]struct{}{keyword(":env/dev") = {}, keyword(":env/prod") = {}}
}

keyword :: distinct string
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_pointer_suffix_deref_and_set_bang_locals :: proc(t: ^testing.T) {
    source := `(package main)

(defvar counter: int 0)

(defn bump [total: ^int] -> int
  (set! total^ (+ total^ 1))
  total^)

(defn main [] -> int
  (let [local 2]
    (set! local (+ local 1))
    (set! counter local)
    (bump &counter)))`

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
compile_set_bang_rejects_non_place :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [x: int y: int]
  (set! (+ x y) 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "set! expects an assignable place")
}

@(test)
compile_map_literals_with_non_string_keys :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (let [by-code (map[int]string {1 "one" 2 "two"})
        by-flag (map[bool]int {true 1 false 0})]
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
(import core "kvist:core")
(import arr "kvist:arr")

(defn score [] -> int
  (let [xs [1 2 3] :defer
        lookup {"one" 1 "two" 2} :defer
        tags #{"math" "lisp"} :defer]
    (println tags)
    (+ (arr.count xs)
       (get lookup "one"))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "#+feature dynamic-literals"), true)
    testing.expect_value(t, strings.contains(output, "arr__count :: #force_inline proc(xs: []$T) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "xs := [dynamic]int{1, 2, 3}"), true)
    testing.expect_value(t, strings.contains(output, "lookup := map[string]int{\"one\" = 1, \"two\" = 2}"), true)
    testing.expect_value(t, strings.contains(output, "tags := map[string]struct{}{\"math\" = {}, \"lisp\" = {}}"), true)
    testing.expect_value(t, strings.contains(output, "return (arr__count((xs)[:])) + (lookup[\"one\"])"), true)
}

@(test)
compile_typed_empty_inline_collection_literals :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn score [] -> int
  (let [xs: [dynamic]int [] :defer
        lookup: map[string]int {} :defer
        tags: (map string (struct [])) #{} :defer]
    (println lookup tags)
    (arr.count xs)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "#+feature dynamic-literals"), true)
    testing.expect_value(t, strings.contains(output, "arr__count :: #force_inline proc(xs: []$T) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "xs: [dynamic]int = [dynamic]int{}"), true)
    testing.expect_value(t, strings.contains(output, "lookup: map[string]int = map[string]int{}"), true)
    testing.expect_value(t, strings.contains(output, "tags: map[string]struct{} = map[string]struct{}{}"), true)
    testing.expect_value(t, strings.contains(output, "return arr__count((xs)[:])"), true)
}

@(test)
compile_inline_map_literal_rejects_mixed_values :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (let [profile {"name" "Ada" "age" 36}]
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
compile_map_supports_single_captured_local_in_fn_literal :: proc(t: ^testing.T) {
    source := "(package main)\n(import arr \"kvist:arr\")\n\n(defn demo [xs: []int] -> [dynamic]int\n  (let [offset 10]\n    (arr.map (fn [x: int] -> int\n               (+ x offset))\n             xs)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "return arr__map_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "proc(offset: int, x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "return (x) + (offset)"), true)
    testing.expect_value(t, strings.contains(output, "offset,"), true)
    testing.expect_value(t, strings.contains(output, "xs)"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_impl__kvist_capture_0_1 :: proc(f: proc(c1: $C1, x: $T) -> $U, kvist_capture_1: C1, xs: []T) -> [dynamic]U {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_map_1"), false)
}

@(test)
compile_map_bang_supports_single_captured_local_in_fn_literal :: proc(t: ^testing.T) {
    source := "(package main)\n(import arr \"kvist:arr\")\n\n(defn demo [xs: [dynamic]int] -> [dynamic]int\n  (let [offset 10]\n    (arr.map! (fn [x: int] -> int\n                (+ x offset))\n              xs)\n    xs))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "arr__map_bang_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "proc(offset: int, x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "return (x) + (offset)"), true)
    testing.expect_value(t, strings.contains(output, "offset,"), true)
    testing.expect_value(t, strings.contains(output, "xs)"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_bang_impl__kvist_capture_0_1 :: proc(f: proc(c1: $C1, x: $T) -> T, kvist_capture_1: C1, xs: []T) {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_map_in_place_1"), false)
}

@(test)
compile_map_supports_multiple_captured_locals_in_fn_literal :: proc(t: ^testing.T) {
    source := "(package main)\n(import arr \"kvist:arr\")\n\n(defn demo [xs: []int] -> [dynamic]int\n  (let [offset 10\n        scale 2]\n    (arr.map (fn [x: int] -> int\n               (+ (* x scale) offset))\n             xs)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "return arr__map_impl__kvist_capture_0_2("), true)
    testing.expect_value(t, strings.contains(output, "proc(scale: int, offset: int, x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "scale,"), true)
    testing.expect_value(t, strings.contains(output, "offset,"), true)
    testing.expect_value(t, strings.contains(output, "xs)"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_impl__kvist_capture_0_2 :: proc(f: proc(c1: $C1, c2: $C2, x: $T) -> $U, kvist_capture_1: C1, kvist_capture_2: C2, xs: []T) -> [dynamic]U {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_map_2"), false)
}

@(test)
compile_filter_supports_single_captured_local_in_fn_literal :: proc(t: ^testing.T) {
    source := "(package main)\n(import arr \"kvist:arr\")\n\n(defn demo [xs: [dynamic]int] -> [dynamic]int\n  (let [limit 10]\n    (arr.filter (fn [x: int] -> bool\n                  (> x limit))\n                xs)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "arr__filter_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "proc(limit: int, x: int) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "return (x) > (limit)"), true)
    testing.expect_value(t, strings.contains(output, "arr__filter_impl__kvist_capture_0_1 :: proc(pred: proc(c1: $C1, x: $T) -> bool, kvist_capture_1: C1, xs: []T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_filter_1"), false)
}

@(test)
compile_filter_supports_multiple_captured_locals_in_fn_literal :: proc(t: ^testing.T) {
    source := "(package main)\n(import arr \"kvist:arr\")\n\n(defn demo [xs: [dynamic]int] -> [dynamic]int\n  (let [lo 3\n        hi 10]\n    (arr.filter (fn [x: int] -> bool\n                  (and (> x lo) (< x hi)))\n                xs)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "arr__filter_impl__kvist_capture_0_2("), true)
    testing.expect_value(t, strings.contains(output, "proc(lo: int, hi: int, x: int) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "lo,"), true)
    testing.expect_value(t, strings.contains(output, "hi,"), true)
    testing.expect_value(t, strings.contains(output, "xs)"), true)
    testing.expect_value(t, strings.contains(output, "arr__filter_impl__kvist_capture_0_2 :: proc(pred: proc(c1: $C1, c2: $C2, x: $T) -> bool, kvist_capture_1: C1, kvist_capture_2: C2, xs: []T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_filter_2"), false)
}

@(test)
compile_arr_sort_by_supports_captured_callbacks :: proc(t: ^testing.T) {
    source := "(package main)\n(import arr \"kvist:arr\")\n\n(defn demo [xs: []int] -> int\n  (let [offset 10\n        sorted (arr.sort-by (fn [x: int] -> int (+ x offset)) xs) :defer]\n    (arr.last sorted)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "sorted := arr__sort_by_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "proc(offset: int, x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "return (x) + (offset)"), true)
    testing.expect_value(t, strings.contains(output, "arr__sort_by_impl__kvist_capture_0_1 :: proc(f: proc(c1: $C1, x: $T) -> $K, kvist_capture_1: C1, xs: []T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "append(&items, arr__Sort_By_Item(K, T){key = f(kvist_capture_1, x), value = x})"), true)
    testing.expect_value(t, strings.contains(output, "arr__sort_by_items_bang((items)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "append(&out, item.value)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sort_by_1"), false)
}

@(test)
compile_arr_sort_by_bang_supports_captured_callbacks :: proc(t: ^testing.T) {
    source := "(package main)\n(import arr \"kvist:arr\")\n\n(defn demo [xs: [dynamic]int] -> int\n  (let [offset 10]\n    (arr.sort-by! (fn [x: int] -> int (+ x offset)) xs)\n    (arr.last xs)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "arr__sort_by_bang_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "proc(offset: int, x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "arr__sort_by_bang_impl__kvist_capture_0_1 :: proc(f: proc(c1: $C1, x: $T) -> $K, kvist_capture_1: C1, xs: []T) {"), true)
    testing.expect_value(t, strings.contains(output, "append(&items, arr__Sort_By_Item(K, T){key = f(kvist_capture_1, x), value = x})"), true)
    testing.expect_value(t, strings.contains(output, "arr__sort_by_items_bang((items)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "xs[i] = item.value"), true)
    testing.expect_value(t, strings.contains(output, "kvist_sort_by_in_place_1"), false)
}

@(test)
compile_filter_bang_supports_single_captured_local_in_fn_literal :: proc(t: ^testing.T) {
    source := "(package main)\n(import arr \"kvist:arr\")\n\n(defn demo [xs: [dynamic]int] -> [dynamic]int\n  (let [limit 10]\n    (arr.filter! (fn [x: int] -> bool\n                   (> x limit))\n                 xs)\n    xs))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "arr__filter_bang_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "proc(limit: int, x: int) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "arr__filter_bang_impl__kvist_capture_0_1 :: proc(pred: proc(c1: $C1, x: $T) -> bool, kvist_capture_1: C1, xs: ^[dynamic]T) {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_filter_in_place_1"), false)
}

@(test)
compile_warns_for_typed_dynamic_array_let_local :: proc(t: ^testing.T) {
    source := `(package main)

(defn demo []
  (let [xs: [dynamic]int []]
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
    }
}

@(test)
compile_odin_append_accepts_pointer_to_dynamic_array :: proc(t: ^testing.T) {
    source := `(package main)
(defn add-byte! [buf: (ptr (dynamic byte)) b: byte]
  (append buf b))

(defn main []
  (let [buf ([dynamic]byte [])]
    (defer (delete buf))
    (add-byte! (addr buf) 42)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "add_byte_bang :: proc(buf: ^[dynamic]byte, b: byte)"), true)
    testing.expect_value(t, strings.contains(output, "append(buf, b)"), true)
    testing.expect_value(t, strings.contains(output, "append(&(buf), b)"), false)
}

@(test)
compile_pointer_to_set_type_constructors :: proc(t: ^testing.T) {
    source := `(package main)

(defn count-caret [seen: (ptr (map string (struct [])))] -> int
  (count (deref seen)))

(defn count-list [seen: (ptr (map string (struct [])))] -> int
  (count (deref seen)))

(defn count-map [seen: ^map[string]int] -> int
  (count (deref seen)))

(defn count-bit-set [flags: ^bit_set[int; u8]] -> int
  0)

(defn count-matrix [m: ^matrix[2, 2]f32] -> int
  0)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "count_caret :: proc(seen: ^map[string]struct{}) -> int"), true)
    testing.expect_value(t, strings.contains(output, "count_list :: proc(seen: ^map[string]struct{}) -> int"), true)
    testing.expect_value(t, strings.contains(output, "count_map :: proc(seen: ^map[string]int) -> int"), true)
    testing.expect_value(t, strings.contains(output, "count_bit_set :: proc(flags: ^bit_set[int; u8]) -> int"), true)
    testing.expect_value(t, strings.contains(output, "count_matrix :: proc(m: ^matrix[2, 2]f32) -> int"), true)
    testing.expect_value(t, strings.contains(output, "return len(seen^)"), true)
}

@(test)
compile_pointer_to_map_and_set_mutation_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import map "kvist:map")
(import set "kvist:set")

(defn mark-seen! [seen: (ptr (map string (struct []))), lookup: ^map[string]int] -> bool
  (set.add! seen "a")
  (set.remove! seen "b")
  (map.assoc! lookup "a" 1)
  (map.dissoc! lookup "z")
  (contains? seen "a"))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "mark_seen_bang :: proc(seen: ^map[string]struct{}, lookup: ^map[string]int) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "seen^[\"a\"] = struct{}{}"), true)
    testing.expect_value(t, strings.contains(output, "delete_key(seen, \"b\")"), true)
    testing.expect_value(t, strings.contains(output, "lookup^[\"a\"] = 1"), true)
    testing.expect_value(t, strings.contains(output, "delete_key(lookup, \"z\")"), true)
    testing.expect_value(t, strings.contains(output, "return (\"a\") in (seen^)"), true)
    testing.expect_value(t, strings.contains(output, "delete_key(&(seen)"), false)
    testing.expect_value(t, strings.contains(output, "lookup[\"a\"] = 1"), false)
}

@(test)
foreign_call_keeps_contextual_native_array_literal_inline :: proc(t: ^testing.T) {
    source := `(package main)
(import rl "vendor:raylib")

(defn draw [panel: rl.Rectangle]
  (rl.DrawRectangleRounded panel 0.08 8 [0 0 0 195]))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "rl.DrawRectangleRounded(panel, 0.08, 8, rl.Color{0, 0, 0, 195})"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_"), false)
}
