package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

@(test)
compile_if_expression_in_let_binding :: proc(t: ^testing.T) {
    source := `(package main)

(defn pick [second?: bool] -> int
  (let [index (if second? 1 0)]
    index))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "index := (1 if second_p else 0)"), true)
}

@(test)
reject_if_expression_without_else :: proc(t: ^testing.T) {
    source := `(package main)

(defn pick [second?: bool] -> int
  (let [index (if second? 1)]
    index))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "if expression expects test, then, and else")
}

@(test)
compile_when_expression_in_let_binding :: proc(t: ^testing.T) {
    source := `(package main)

(defn pick [second?: bool] -> int
  (let [index (when second? 1)]
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
compile_when_expression_in_return_position :: proc(t: ^testing.T) {
    source := `(package main)

(defn pick [second?: bool] -> int
  (when second? 1))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "if second_p"), true)
    testing.expect_value(t, strings.contains(output, "return 1"), true)
    testing.expect_value(t, strings.contains(output, "return int{}"), true)
}

@(test)
compile_cond_expression_in_let_binding :: proc(t: ^testing.T) {
    source := `(package main)

(defn sign [n: int] -> int
  (let [value (cond
                (< n 0) -1
                (= n 0) 0
                :else 1)]
    value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "value := (-1 if (n) < (0) else (0 if (n) == (0) else 1))"), true)
}

@(test)
compile_case_expression_in_let_binding :: proc(t: ^testing.T) {
    source := `(package main)

(defn label [n: int] -> string
  (let [value (case n
                1 "one"
                2 "few"
                3 "few"
                "many")]
    value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, `if (kvist_case_`), true)
    testing.expect_value(t, strings.contains(output, `== (1)`), true)
    testing.expect_value(t, strings.contains(output, `== (2)`), true)
    testing.expect_value(t, strings.contains(output, `== (3)`), true)
    testing.expect_value(t, strings.contains(output, `value := `), true)
}

@(test)
reject_case_expression_without_default :: proc(t: ^testing.T) {
    source := `(package main)

(defn label [n: int] -> string
  (let [value (case n
                1 "one")]
    value))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "while expanding macro case: case expects subject, clause/body pairs, and default")
}

@(test)
compile_let_expression_with_expected_type :: proc(t: ^testing.T) {
    source := `(package main)

(defn id [x: int] -> int
  x)

(defn demo [] -> int
  (id (let [base 40]
        (+ base 2))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return id(\n        (proc() -> int {"), true)
    testing.expect_value(t, strings.contains(output, "base := 40"), true)
    testing.expect_value(t, strings.contains(output, "return (base) + (2)"), true)
}

@(test)
compile_final_let_expression_uses_proc_return_type :: proc(t: ^testing.T) {
    source := `(package main)

(defn demo [] -> int
  (let [base 40]
    (+ base 2)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return (base) + (2)"), true)
}

@(test)
compile_final_do_expression_uses_proc_return_type :: proc(t: ^testing.T) {
    source := `(package main)

(defn demo [] -> int
  (do
    (println "side")
    7))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `fmt.println("side")`), true)
    testing.expect_value(t, strings.contains(output, "return 7"), true)
}

@(test)
compile_final_block_expression_uses_proc_return_type :: proc(t: ^testing.T) {
    source := `(package main)

(defn demo [] -> int
  (block
    (def base 40)
    (+ base 2)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "base :: 40"), true)
    testing.expect_value(t, strings.contains(output, "return (base) + (2)"), true)
}

@(test)
compile_case_vector_clause_matches_vector_value :: proc(t: ^testing.T) {
    source := `(package main)

(defn score [xs: [2]int] -> int
  (let [value (case xs
                [1 2] 1
                0)]
    value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "== ([2]int{1, 2})"), true)
}

@(test)
reject_internal_lowering_call_names_in_source :: proc(t: ^testing.T) {
    source_prim := `(package main)

(defn bad [] -> int
  (kvist-prim-count [1 2 3]))`

    _, err_prim, ok_prim := kvist.compile_source(source_prim)
    testing.expect_value(t, ok_prim, false)
    if ok_prim {
        return
    }
    defer delete(err_prim.message)
    testing.expect_value(t, err_prim.message, "`kvist-prim-count` is an internal lowering name")

    source_underscore_prim := `(package main)

(defn bad [] -> int
  (kvist_prim_bit_or 1 2))`

    _, err_underscore_prim, ok_underscore_prim := kvist.compile_source(source_underscore_prim)
    testing.expect_value(t, ok_underscore_prim, false)
    if ok_underscore_prim {
        return
    }
    defer delete(err_underscore_prim.message)
    testing.expect_value(t, err_underscore_prim.message, "`kvist_prim_bit_or` is an internal lowering name")

    source_empty := `(package main)

(defn bad [] -> bool
  (kvist-prim-empty? [1 2 3]))`

    _, err_empty, ok_empty := kvist.compile_source(source_empty)
    testing.expect_value(t, ok_empty, false)
    if ok_empty {
        return
    }
    defer delete(err_empty.message)
    testing.expect_value(t, err_empty.message, "`kvist-prim-empty?` is an internal lowering name")

    source_contains := `(package main)

(defn bad [] -> bool
  (kvist-prim-contains? [1 2 3] 2))`

    _, err_contains, ok_contains := kvist.compile_source(source_contains)
    testing.expect_value(t, ok_contains, false)
    if ok_contains {
        return
    }
    defer delete(err_contains.message)
    testing.expect_value(t, err_contains.message, "`kvist-prim-contains?` is an internal lowering name")

    source_slice := `(package main)

(defn bad [] -> []int
  (kvist-prim-slice [1 2 3]))`

    _, err_slice, ok_slice := kvist.compile_source(source_slice)
    testing.expect_value(t, ok_slice, false)
    if ok_slice {
        return
    }
    defer delete(err_slice.message)
    testing.expect_value(t, err_slice.message, "`kvist-prim-slice` is an internal lowering name")

    source_get := `(package main)

(defn bad [] -> int
  (kvist-prim-get [1 2 3] 0))`

    _, err_get, ok_get := kvist.compile_source(source_get)
    testing.expect_value(t, ok_get, false)
    if ok_get {
        return
    }
    defer delete(err_get.message)
    testing.expect_value(t, err_get.message, "`kvist-prim-get` is an internal lowering name")

    source_or_else := `(package main)

(defn query [] -> [value: int, ok: bool] #optional_ok
  (return 1 true))

(defn bad [] -> int
  (kvist-prim-or-else (query) 0))`

    _, err_or_else, ok_or_else := kvist.compile_source(source_or_else)
    testing.expect_value(t, ok_or_else, false)
    if ok_or_else {
        return
    }
    defer delete(err_or_else.message)
    testing.expect_value(t, err_or_else.message, "`kvist-prim-or-else` is an internal lowering name")

    source_println := `(package main)

(defn bad []
  (kvist-prim-println "hello"))`

    _, err_println, ok_println := kvist.compile_source(source_println)
    testing.expect_value(t, ok_println, false)
    if ok_println {
        return
    }
    defer delete(err_println.message)
    testing.expect_value(t, err_println.message, "`kvist-prim-println` is an internal lowering name")

    source_tap := `(package main)

(defn bad [] -> int
  (kvist-prim-tap 1))`

    _, err_tap, ok_tap := kvist.compile_source(source_tap)
    testing.expect_value(t, ok_tap, false)
    if ok_tap {
        return
    }
    defer delete(err_tap.message)
    testing.expect_value(t, err_tap.message, "`kvist-prim-tap` is an internal lowering name")

    source_doc := `(package main)

(defn bad []
  (kvist-prim-doc 'println))`

    _, err_doc, ok_doc := kvist.compile_source(source_doc)
    testing.expect_value(t, ok_doc, false)
    if ok_doc {
        return
    }
    defer delete(err_doc.message)
    testing.expect_value(t, err_doc.message, "`kvist-prim-doc` is an internal lowering name")

    source_update_bang := `(package main)

(defn bad [xs: [dynamic]int]
  (kvist-prim-update! xs[0] + 1))`

    _, err_update_bang, ok_update_bang := kvist.compile_source(source_update_bang)
    testing.expect_value(t, ok_update_bang, false)
    if ok_update_bang {
        return
    }
    defer delete(err_update_bang.message)
    testing.expect_value(t, err_update_bang.message, "`kvist-prim-update!` is an internal lowering name")

    source_assoc := `(package main)

(defstruct Point {
  x: int
})

(defn bad [point: Point] -> Point
  (kvist-prim-assoc point .x 1))`

    _, err_assoc, ok_assoc := kvist.compile_source(source_assoc)
    testing.expect_value(t, ok_assoc, false)
    if ok_assoc {
        return
    }
    defer delete(err_assoc.message)
    testing.expect_value(t, err_assoc.message, "`kvist-prim-assoc` is an internal lowering name")

    source_update := `(package main)

(defstruct Point {
  x: int
})

(defn bad [point: Point] -> Point
  (kvist-prim-update point .x + 1))`

    _, err_update, ok_update := kvist.compile_source(source_update)
    testing.expect_value(t, ok_update, false)
    if ok_update {
        return
    }
    defer delete(err_update.message)
    testing.expect_value(t, err_update.message, "`kvist-prim-update` is an internal lowering name")

    source_case := `(package main)

(defn bad [n: int] -> int
  (kvist-prim-case n
    1 10
    0))`

    _, err_case, ok_case := kvist.compile_source(source_case)
    testing.expect_value(t, ok_case, false)
    if ok_case {
        return
    }
    defer delete(err_case.message)
    testing.expect_value(t, err_case.message, "`kvist-prim-case` is an internal lowering name")

    source_thread_first := `(package main)

(defn bad [x: int] -> int
  (kvist-prim-thread-first x (+ 1)))`

    _, err_thread_first, ok_thread_first := kvist.compile_source(source_thread_first)
    testing.expect_value(t, ok_thread_first, false)
    if ok_thread_first {
        return
    }
    defer delete(err_thread_first.message)
    testing.expect_value(t, err_thread_first.message, "`kvist-prim-thread-first` is an internal lowering name")

    source_thread_last := `(package main)

(defn bad [x: int] -> int
  (kvist-prim-thread-last x (+ 1)))`

    _, err_thread_last, ok_thread_last := kvist.compile_source(source_thread_last)
    testing.expect_value(t, ok_thread_last, false)
    if ok_thread_last {
        return
    }
    defer delete(err_thread_last.message)
    testing.expect_value(t, err_thread_last.message, "`kvist-prim-thread-last` is an internal lowering name")

    source_delete := `(package main)

(defn bad [lookup: map[string]int]
  (kvist-prim-delete! lookup "a"))`

    _, err_delete, ok_delete := kvist.compile_source(source_delete)
    testing.expect_value(t, ok_delete, false)
    if ok_delete {
        return
    }
    defer delete(err_delete.message)
    testing.expect_value(t, err_delete.message, "`kvist-prim-delete!` is an internal lowering name")

}

@(test)
reject_internal_lowering_call_names_in_eval_source :: proc(t: ^testing.T) {
    source := `(package main)

(def xs: []int ([]int [1 2 3]))`

    _, err_prim, ok_prim := kvist.compile_eval_source_with_map(source, `(kvist-prim-count xs)`)
    testing.expect_value(t, ok_prim, false)
    if ok_prim {
        return
    }
    defer delete(err_prim.message)
    testing.expect_value(t, err_prim.message, "`kvist-prim-count` is an internal lowering name")

    _, err_empty, ok_empty := kvist.compile_eval_source_with_map(source, `(kvist-prim-empty? xs)`)
    testing.expect_value(t, ok_empty, false)
    if ok_empty {
        return
    }
    defer delete(err_empty.message)
    testing.expect_value(t, err_empty.message, "`kvist-prim-empty?` is an internal lowering name")

    _, err_contains, ok_contains := kvist.compile_eval_source_with_map(source, `(kvist-prim-contains? xs 2)`)
    testing.expect_value(t, ok_contains, false)
    if ok_contains {
        return
    }
    defer delete(err_contains.message)
    testing.expect_value(t, err_contains.message, "`kvist-prim-contains?` is an internal lowering name")

    _, err_slice, ok_slice := kvist.compile_eval_source_with_map(source, `(kvist-prim-slice xs)`)
    testing.expect_value(t, ok_slice, false)
    if ok_slice {
        return
    }
    defer delete(err_slice.message)
    testing.expect_value(t, err_slice.message, "`kvist-prim-slice` is an internal lowering name")

    _, err_get, ok_get := kvist.compile_eval_source_with_map(source, `(kvist-prim-get xs 0)`)
    testing.expect_value(t, ok_get, false)
    if ok_get {
        return
    }
    defer delete(err_get.message)
    testing.expect_value(t, err_get.message, "`kvist-prim-get` is an internal lowering name")

    _, err_or_else, ok_or_else := kvist.compile_eval_source_with_map(source, `(kvist-prim-or-else (query) 0)`)
    testing.expect_value(t, ok_or_else, false)
    if ok_or_else {
        return
    }
    defer delete(err_or_else.message)
    testing.expect_value(t, err_or_else.message, "`kvist-prim-or-else` is an internal lowering name")

    _, err_println, ok_println := kvist.compile_eval_source_with_map(source, `(kvist-prim-println "hello")`)
    testing.expect_value(t, ok_println, false)
    if ok_println {
        return
    }
    defer delete(err_println.message)
    testing.expect_value(t, err_println.message, "`kvist-prim-println` is an internal lowering name")

    _, err_tap, ok_tap := kvist.compile_eval_source_with_map(source, `(kvist-prim-tap 1)`)
    testing.expect_value(t, ok_tap, false)
    if ok_tap {
        return
    }
    defer delete(err_tap.message)
    testing.expect_value(t, err_tap.message, "`kvist-prim-tap` is an internal lowering name")

    _, err_doc, ok_doc := kvist.compile_eval_source_with_map(source, `(kvist-prim-doc 'println)`)
    testing.expect_value(t, ok_doc, false)
    if ok_doc {
        return
    }
    defer delete(err_doc.message)
    testing.expect_value(t, err_doc.message, "`kvist-prim-doc` is an internal lowering name")

    _, err_update_bang, ok_update_bang := kvist.compile_eval_source_with_map(source, `(kvist-prim-update! xs[0] + 1)`)
    testing.expect_value(t, ok_update_bang, false)
    if ok_update_bang {
        return
    }
    defer delete(err_update_bang.message)
    testing.expect_value(t, err_update_bang.message, "`kvist-prim-update!` is an internal lowering name")

    _, err_assoc, ok_assoc := kvist.compile_eval_source_with_map(source, `(kvist-prim-assoc xs .x 1)`)
    testing.expect_value(t, ok_assoc, false)
    if ok_assoc {
        return
    }
    defer delete(err_assoc.message)
    testing.expect_value(t, err_assoc.message, "`kvist-prim-assoc` is an internal lowering name")

    _, err_update, ok_update := kvist.compile_eval_source_with_map(source, `(kvist-prim-update xs .x + 1)`)
    testing.expect_value(t, ok_update, false)
    if ok_update {
        return
    }
    defer delete(err_update.message)
    testing.expect_value(t, err_update.message, "`kvist-prim-update` is an internal lowering name")

    _, err_case, ok_case := kvist.compile_eval_source_with_map(source, `(kvist-prim-case 1 1 10 0)`)
    testing.expect_value(t, ok_case, false)
    if ok_case {
        return
    }
    defer delete(err_case.message)
    testing.expect_value(t, err_case.message, "`kvist-prim-case` is an internal lowering name")

    _, err_thread_first, ok_thread_first := kvist.compile_eval_source_with_map(source, `(kvist-prim-thread-first 1 (+ 1))`)
    testing.expect_value(t, ok_thread_first, false)
    if ok_thread_first {
        return
    }
    defer delete(err_thread_first.message)
    testing.expect_value(t, err_thread_first.message, "`kvist-prim-thread-first` is an internal lowering name")

    _, err_thread_last, ok_thread_last := kvist.compile_eval_source_with_map(source, `(kvist-prim-thread-last 1 (+ 1))`)
    testing.expect_value(t, ok_thread_last, false)
    if ok_thread_last {
        return
    }
    defer delete(err_thread_last.message)
    testing.expect_value(t, err_thread_last.message, "`kvist-prim-thread-last` is an internal lowering name")

    _, err_delete, ok_delete := kvist.compile_eval_source_with_map(source, `(kvist-prim-delete! xs 1)`)
    testing.expect_value(t, ok_delete, false)
    if ok_delete {
        return
    }
    defer delete(err_delete.message)
    testing.expect_value(t, err_delete.message, "`kvist-prim-delete!` is an internal lowering name")
}

@(test)
reject_mutation_of_runtime_initialized_def :: proc(t: ^testing.T) {
    source := `(package main)

(defn seed [] -> int 40)
(def answer (seed))

(defn change []
  (mut! answer += 2))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "cannot mutate immutable def answer; use defvar for mutable package state")
}

@(test)
compile_defn_clean_param_and_named_return_syntax :: proc(t: ^testing.T) {
    source := `(package main)

(defn query [path: string, limit: int] -> [value: int, ok: bool]
  (return limit true))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "query :: proc(path: string, limit: int) -> (value: int, ok: bool)"), true)
}

@(test)
compile_case_with_value_cases :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Method [
  Get
  Post
  Delete
])

(defn method-name [method: Method] -> string
  (case method
    .Get "GET"
    .Post "POST"
    "OTHER"))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "method_name :: proc(method: Method) -> string {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, "if (kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, "== (.Get)"), true)
    testing.expect_value(t, strings.contains(output, "else if (kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, "== (.Post)"), true)
    testing.expect_value(t, strings.contains(output, "return \"OTHER\""), true)
    testing.expect_value(t, strings.contains(output, "#partial switch method"), false)
}

@(test)
compile_case_with_repeated_value_cases :: proc(t: ^testing.T) {
    source := `(package main)

(defenum Method [
  Get
  Head
  Post
])

(defn read-method? [method: Method] -> bool
  (case method
    .Get true
    .Head true
    false))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "read_method_p :: proc(method: Method) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "if (kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, "== (.Get)"), true)
    testing.expect_value(t, strings.contains(output, "else if (kvist_case_"), true)
    testing.expect_value(t, strings.contains(output, "== (.Head)"), true)
    testing.expect_value(t, strings.contains(output, "return false"), true)
    testing.expect_value(t, strings.contains(output, "#partial switch method"), false)
}

@(test)
compile_operator_forms :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")
(import bit "kvist:bit")

(defn score [a: int, b: int, ok: bool] -> int
  (if (and ok (> a b))
    (+ a b)
    (if (not ok)
      (- b)
      (- b a))))

(defenum Status [OK Err])

(defn contains-key [lookup: map[string]int, key: string] -> bool
  (contains? lookup key))

(defn same? [a: int, b: int] -> bool
  (= a b))

(defn same3? [a: int, b: int, c: int] -> bool
  (= a b c))

(defn increasing? [a: int, b: int, c: int] -> bool
  (< a b c))

(defn bounded? [x: f32] -> bool
  (<= 0.0 x 1.0))

(defn status-ok-chain? [status: Status] -> bool
  (= status .OK .OK))

(defn missing-key [lookup: map[string]int, key: string] -> bool
  (not (contains? lookup key)))

(defn pack-version [major: u32, minor: u32, patch: u32] -> u32
  (bit.or
    (bit.shift-left major 22)
    (bit.shift-left minor 12)
    patch))

(defn unpack-major [version: u32] -> u32
  (bit.and (bit.shift-right version 22) 0x7F))

(defn toggle-bit [flags: u64, index: int] -> u64
  (bit.flip flags index))

(defn clear-bit [flags: u64, index: int] -> u64
  (bit.clear flags index))

(defn set-bit [flags: u64, index: int] -> u64
  (bit.set flags index))

(defn bit-set? [flags: u64, index: int] -> bool
  (bit.test flags index))

(defn remove-mask [flags: u32, mask: u32] -> u32
  (bit.and-not flags mask))

(defn invert-mask [mask: u32] -> u32
  (bit.not mask))

(defn xor-mask [a: u32, b: u32] -> u32
  (bit.xor a b))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "same_p :: proc(a, b: int) -> bool {\n    return (a) == (b)\n}"), true)
    testing.expect_value(t, strings.contains(output, "same3_p :: proc(a, b, c: int) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "increasing_p :: proc(a, b, c: int) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "bounded_p :: proc(x: f32) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "status_ok_chain_p :: proc(status: Status) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "proc() -> bool {"), true)
    testing.expect_value(t, strings.contains(output, ": f32 = 0.0"), true)
    testing.expect_value(t, strings.contains(output, ": f32 = 1.0"), true)
    testing.expect_value(t, strings.contains(output, ": Status = .OK"), true)
    testing.expect_value(t, strings.contains(output, "contains_key :: proc(lookup: map[string]int, key: string) -> bool {\n    return (key) in (lookup)\n}"), true)
    testing.expect_value(t, strings.contains(output, "missing_key :: proc(lookup: map[string]int, key: string) -> bool {\n    return !((key) in (lookup))\n}"), true)
    testing.expect_value(t, strings.contains(output, "return ((major) << (22)) | ((minor) << (12)) | (patch)"), true)
    testing.expect_value(t, strings.contains(output, "return ((version) >> (22)) & (0x7F)"), true)
    testing.expect_value(t, strings.contains(output, "return (flags) ~ ((1) << (uint(index)))"), true)
    testing.expect_value(t, strings.contains(output, "return (flags) & (~((1) << (uint(index))))"), true)
    testing.expect_value(t, strings.contains(output, "return (flags) | ((1) << (uint(index)))"), true)
    testing.expect_value(t, strings.contains(output, "return ((flags) & ((1) << (uint(index)))) != (0)"), true)
    testing.expect_value(t, strings.contains(output, "return (flags) & (~(mask))"), true)
    testing.expect_value(t, strings.contains(output, "return ~(mask)"), true)
    testing.expect_value(t, strings.contains(output, "return (a) ~ (b)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_prim_bit"), false)
}

@(test)
compile_cond_with_final_else :: proc(t: ^testing.T) {
    source := `(package main)

(defn classify [n: int] -> string
  (cond
    (< n 0) "negative"
    (= n 0) "zero"
    :else "positive"))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

classify :: proc(n: int) -> string {
    if (n) < (0) {
        return "negative"
    }
    else if (n) == (0) {
        return "zero"
    }
    else {
        return "positive"
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_cond_vector_clauses :: proc(t: ^testing.T) {
    source := `(package main)

(defn classify [n: int] -> string
  (cond
    [(< n 0) "negative"]
    [:else "non-negative"]))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "if (n) < (0) {"), true)
    testing.expect_value(t, strings.contains(output, "return \"negative\""), true)
    testing.expect_value(t, strings.contains(output, "else {"), true)
    testing.expect_value(t, strings.contains(output, "return \"non-negative\""), true)
}

@(test)
implicit_returns_only_apply_to_final_nested_blocks :: proc(t: ^testing.T) {
    source := `(package main)

(defn trace [x: int]
  (return))

(defn choose [flag: bool] -> int
  (let [x 1]
    (trace x))
  (if flag
    (trace 2)
    (trace 3))
  4)

(defn total [xs: []int] -> int
  (let [sum 0]
    (for [x xs]
      (set! sum (+ sum x))
      (trace sum))
    sum))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

trace :: proc(x: int) {
    return
}

choose :: proc(flag: bool) -> int {
    {
        x := 1
        trace(x)
    }
    if flag {
        trace(2)
    }
    else {
        trace(3)
    }
    return 4
}

total :: proc(xs: []int) -> int {
    sum := 0
    for x in xs {
        sum = (sum) + (x)
        trace(sum)
    }
    return sum
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_loop_form_is_removed :: proc(t: ^testing.T) {
    source := `(package main)

(defn spin []
  (loop true
    (break)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "`loop` has been removed; use `for` for collection iteration or `while` for condition loops")
}

@(test)
compile_flat_multi_return_binding :: proc(t: ^testing.T) {
    source := `(package main)

(defn query [] -> [value: int, ok: bool]
  (return 42 true))

(defn main []
  (let [[value ok] (query)
        [_, still-ok] (query)]
    (when (and ok still-ok)
      (return))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

query :: proc() -> (value: int, ok: bool) {
    return 42, true
}

main :: proc() {
    value, ok := query()
    _, still_ok := query()
    if (ok) && (still_ok) {
        return
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_flat_native_sequence_bindings :: proc(t: ^testing.T) {
    source := `(package main)

(defn fixed-total [xs: [3]int] -> int
  (let [[a b _] xs]
    (+ a b)))

(defn slice-total [xs: []int] -> int
  (let [[a b] xs]
    (+ a b)))

(defn dynamic-total [xs: [dynamic]int] -> int
  (let [[a b] xs]
    (+ a b)))

(defn temporary-total [] -> int
  (let [[a b] ([dynamic]int [10 20 30])]
    (+ a b)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, count_substring(output, " := xs"), 3)
    testing.expect_value(t, count_substring(output, "[0]"), 4)
    testing.expect_value(t, count_substring(output, "[1]"), 4)
    testing.expect_value(t, strings.contains(output, "_ = kvist_thread_1[2]"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_4)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_4 := [dynamic]int{10, 20, 30}"), true)
    testing.expect_value(t, count_substring(output, "native sequence pattern requires at least 2 elements"), 3)
}

@(test)
compile_native_data_element_binding_is_managed :: proc(t: ^testing.T) {
    source := `(package main)

(defn first-item [xs: []Data] -> Data
  (let [[item] xs]
    item))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "item := kvist_data_retain(kvist_thread_1[0])"), true)
    testing.expect_value(t, strings.contains(output, "defer kvist_data_release(item)"), true)
}

@(test)
reject_non_flat_native_sequence_binding_patterns :: proc(t: ^testing.T) {
    cases := []struct {
        source:    string,
        message:   string,
        highlight: string,
    }{
        {
            source = `(package main)
(defn bad [xs: []int]
  (let [[head & tail] xs]
    head))`,
            message = "native sequence destructuring does not yet support rest bindings (`&`)",
            highlight = "&",
        },
        {
            source = `(package main)
(defn bad [xs: [2][2]int]
  (let [[head [nested]] xs]
    head))`,
            message = "native sequence destructuring does not yet support nested patterns",
            highlight = "[nested]",
        },
        {
            source = `(package main)
(defn bad [xs: []int]
  (let [[first :as all] xs]
    first))`,
            message = "native sequence destructuring does not yet support `:as` bindings",
            highlight = ":as",
        },
        {
            source = `(package main)
(defn bad [xs: []int]
  (let [[] xs]
    (return)))`,
            message = "native sequence destructuring expects at least one binding",
            highlight = "[]",
        },
        {
            source = `(package main)
(defn bad [xs: [2]int]
  (let [[first second third] xs]
    first))`,
            message = "native sequence pattern requires 3 elements, but [2]int contains 2",
            highlight = "third",
        },
    }

    for test_case in cases {
        _, err, ok := kvist.compile_source(test_case.source)
        testing.expect_value(t, ok, false)
        if ok {
            continue
        }
        defer delete(err.message)
        testing.expect_value(t, err.message, test_case.message)
        testing.expect_value(t, test_case.source[err.span.start:err.span.end], test_case.highlight)
    }
}

@(test)
implicit_core_when_helper :: proc(t: ^testing.T) {
    source := `(package main)

(defn main [ok: bool]
  (when ok
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "if ok {"), true)
}

@(test)
implicit_core_cond_helper :: proc(t: ^testing.T) {
    source := `(package main)

(defn classify [n: int] -> string
  (cond
    (< n 0) "negative"
    :else "non-negative"))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "else {"), true)
}

@(test)
reject_when_let_expression_position :: proc(t: ^testing.T) {
    source := `(package main)

(defn query [] -> [value: int, found: bool]
  (return 42 true))

(defn demo [] -> int
  (let [value: int (when-let [[x found] (query)]
                     x)]
    value))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "if expression expects test, then, and else")
}

@(test)
compile_if_let_expression_with_expected_type :: proc(t: ^testing.T) {
    source := `(package main)

(defn query [] -> [value: int, found: bool]
  (return 42 true))

(defn demo [] -> int
  (let [value: int (if-let [[x found] (query)]
                     x
                     0)]
    value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "x, found := query()"), true)
    testing.expect_value(t, strings.contains(output, "value: int = (x if found else 0)"), true)
}

@(test)
compile_final_if_let_uses_proc_return_type :: proc(t: ^testing.T) {
    source := `(package main)

(defn query [] -> [value: int, found: bool]
  (return 42 true))

(defn demo [] -> int
  (if-let [[x found] (query)]
    x
    0))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "x, found := query()"), true)
    testing.expect_value(t, strings.contains(output, "if found {"), true)
    testing.expect_value(t, strings.contains(output, "return x"), true)
    testing.expect_value(t, strings.contains(output, "return 0"), true)
}

@(test)
compile_if_ok_expression_with_expected_type :: proc(t: ^testing.T) {
    source := `(package main)
(import os "core:os")

(defn read-count [] -> [value: int, err: os.Error]
  (return 42 nil))

(defn demo [] -> int
  (let [value: int (if-ok [[x err] (read-count)]
                     x
                     0)]
    value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "x, err := read_count()"), true)
    testing.expect_value(t, strings.contains(output, "value: int = (x if (err) == (os.Error{}) else 0)"), true)
}

@(test)
compile_chained_if_let_expression_with_expected_type :: proc(t: ^testing.T) {
    source := `(package main)

(defn query [n: int, found: bool] -> [value: int, ok: bool]
  (return n found))

(defn demo [] -> int
  (let [value: int (if-let [[x ok-x] (query 4 true)
                            [y ok-y] (query 5 false)]
                     (+ x y)
                     -1)]
    value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "proc(x: int) -> int"), true)
    testing.expect_value(t, strings.contains(output, "return (x) + (y)"), true)
}

@(test)
compile_final_if_ok_uses_proc_return_type :: proc(t: ^testing.T) {
    source := `(package main)
(import os "core:os")

(defn read-count [] -> [value: int, err: os.Error]
  (return 42 nil))

(defn demo [] -> int
  (if-ok [[x err] (read-count)]
    x
    0))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "x, err := read_count()"), true)
    testing.expect_value(t, strings.contains(output, "if (err) == (os.Error{}) {"), true)
    testing.expect_value(t, strings.contains(output, "return x"), true)
    testing.expect_value(t, strings.contains(output, "return 0"), true)
}

@(test)
reject_when_ok_expression_position :: proc(t: ^testing.T) {
    source := `(package main)
(import os "core:os")

(defn read-count [] -> [value: int, err: os.Error]
  (return 42 nil))

(defn demo [] -> int
  (let [value: int (when-ok [[x err] (read-count)]
                     x)]
    value))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "if expression expects test, then, and else")
}

@(test)
compile_let_discard_binding :: proc(t: ^testing.T) {
    source := `(package main)

(defn observe [x: int] -> int
  x)

(defn query [x: int] -> [value: int, ok: bool]
  (return x true))

(defn main [] -> int
  (let [_ (observe 1)
        _ (observe 2)
        _: int (observe 3)
        [_ ok] (query 4)
        [value _] (query 5)
        answer 42]
    (if ok
      (+ answer value)
      answer)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "_ = observe(1)"), true)
    testing.expect_value(t, strings.contains(output, "_ = observe(2)"), true)
    testing.expect_value(t, strings.contains(output, "_ = observe(3)"), true)
    testing.expect_value(t, strings.contains(output, "_ := observe"), false)
    testing.expect_value(t, strings.contains(output, "_, ok := query(4)"), true)
    testing.expect_value(t, strings.contains(output, "value, _ := query(5)"), true)
    testing.expect_value(t, strings.contains(output, "answer := 42"), true)
}

@(test)
compile_let_or_return_ok_binding :: proc(t: ^testing.T) {
    source := `(package main)

(defn next [] -> [value: int, ok: bool]
  (return 1 true))

(defn total [] -> [value: int, ok: bool]
  (let [[value ok] (next) :or-return]
    (return (+ value 1) true)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "value, ok = next()"), true)
    testing.expect_value(t, strings.contains(output, "return"), true)
}

@(test)
compile_body_only_while_loop :: proc(t: ^testing.T) {
    source := `(package main)

(defn run []
  (while true
    (do
      (println "tick")
      (break))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "for true {"), true)
    testing.expect_value(t, strings.contains(output, "fmt.println(\"tick\")"), true)
    testing.expect_value(t, strings.contains(output, "break"), true)
}

@(test)
reject_let_or_return_without_matching_named_returns :: proc(t: ^testing.T) {
    source := `(package main)

(defn next [] -> [value: int, ok: bool]
  (return 1 true))

(defn total [] -> int
  (let [[value ok] (next) :or-return]
    value))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, ":or-return currently requires proc named returns matching the binding names exactly")
}

@(test)
compile_let_or_break_and_or_continue_bindings :: proc(t: ^testing.T) {
    source := `(package main)

(defn next [] -> [value: int, ok: bool]
  (return 1 true))

(defn demo []
  (while true
    (let [[value ok] (next) :or-break]
      (println value))
    (let [[value ok] (next) :or-continue]
      (println value))
    (break)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "break"), true)
    testing.expect_value(t, strings.contains(output, "continue"), true)
}

@(test)
compile_defiter_call_materializes_in_expression_context :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct File_Source {
  items: []string
  index: int
})

(defn open-files [items: []string] -> File_Source
  (File_Source {items: items index: 0}))

(defn next-file [src: ^File_Source] -> [path: string ok: bool]
  (return "" false))

(defiter files [items: []string] -> File_Source :yield string
  :next next-file
  (open-files items))

(defn bad [items: []string] -> int
  (let [src (files items)]
    (count src)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "src := (proc(kvist_source_arg_1: []string) -> [dynamic]string {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_source := files(kvist_source_arg_1)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_item, kvist_source_ok := next_file(&kvist_source)"), true)
    testing.expect_value(t, strings.contains(output, "append(&kvist_out, kvist_item)"), true)
}

@(test)
reject_defiter_next_wrong_return_shape :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct File_Source {
  index: int
})

(defn open-files [] -> File_Source
  (File_Source {index: 0}))

(defn next-file [src: ^File_Source] -> [path: int ok: bool]
  (return 0 false))

(defiter files [] -> File_Source :yield string
  :next next-file
  (open-files))

(defn consume [] -> int
  (let [total 0]
    (for [path (files)]
      (set! total (+ total (count path))))
    total))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "defiter files :next must return [item: string ok: bool]")
}

@(test)
reject_defiter_dispose_return_value :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct File_Source {
  index: int
})

(defn open-files [] -> File_Source
  (File_Source {index: 0}))

(defn next-file [src: ^File_Source] -> [path: string ok: bool]
  (return "" false))

(defn dispose-files [src: ^File_Source] -> int
  0)

(defiter files [] -> File_Source :yield string
  :next next-file
  :dispose dispose-files
  (open-files))

(defn consume [] -> int
  (let [total 0]
    (for [path (files)]
      (set! total (+ total (count path))))
    total))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "defiter files :dispose must not return a value")
}

@(test)
reject_threaded_return_with_allocating_intermediate :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn inc [x: int] -> int
  (+ x 1))

(defn even? [x: int] -> bool
  (= (% x 2) 0))

(defn bad [xs: []int] -> []int
  (->> xs
       (arr.map inc)
       (arr.filter even?)
       (arr.take 1)))`

    _, err, ok := kvist.compile_source(source)
    defer delete(err.message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "cannot return a borrowed view that depends on an owned intermediate; bind the pipeline locally or return an owned result")
}

@(test)
compile_case_with_keyword_values :: proc(t: ^testing.T) {
    source := `(package main)

(defn score [mode: keyword] -> int
  (case mode
    :else 9
    :dev 1
    :prod 2
    0))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "score :: proc(mode: keyword) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "== (keyword(\":else\"))"), true)
    testing.expect_value(t, strings.contains(output, "== (keyword(\":dev\"))"), true)
    testing.expect_value(t, strings.contains(output, "== (keyword(\":prod\"))"), true)
    testing.expect_value(t, strings.contains(output, "switch mode"), false)
}

@(test)
compile_case_stmt_vector_clause_matches_vector_value :: proc(t: ^testing.T) {
    source := `(package main)

(defn score [xs: [2]int] -> int
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

    testing.expect_value(t, strings.contains(output, "== ([2]int{1, 2})"), true)
}

@(test)
compile_mut_bang_assignment_place_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point {
  x: int
  y: int
  active?: bool
})

  (defn mutate [total: ^int] -> int
  (let [xs ([dynamic]int [1 2 3])
        point (Point {x: 4 y: 5 active?: false})]
    (mut! point.y += 4)
    (mut! (get point .y) += 1)
    (mut! (get xs 1) -= 2)
    (mut! (deref total) *= 3)
    (inc! point.x)
    (dec! (get xs 2))
    (toggle! point.active_p)
    (negate! point.x)
    (+ point.x point.y (get xs 1) (get xs 2) (deref total))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `#+feature dynamic-literals
package main

Point :: struct {
    x: int,
    y: int,
    active_p: bool,
}

mutate :: proc(total: ^int) -> int {
    xs := [dynamic]int{1, 2, 3}
    point := Point{x = 4, y = 5, active_p = false}
    point.y += 4
    (point).y += 1
    xs[1] -= 2
    total^ *= 3
    point.x += 1
    xs[2] -= 1
    point.active_p = !(point.active_p)
    point.x = -(point.x)
    return (point.x) + (point.y) + (xs[1]) + (xs[2]) + (total^)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_mut_bang_assignment_rejects_non_place :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [x: int y: int]
  (mut! (+ x y) += 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "mut! expects an assignable place")
}

@(test)
compile_mut_bang_rejects_plain_assignment_operator :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [x: int]
  (mut! x = 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "mut! does not support =; use set! for plain assignment")
}

@(test)
compile_mut_bang_rejects_non_compound_operator :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [x: int]
  (mut! x + 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "mut! expects a compound assignment operator")
}

@(test)
compile_function_calls_support_positional_and_named_args :: proc(t: ^testing.T) {
    source := `(package main)

(defn foo [a: int, b: int, c: int] -> int
  (+ a b c))

(defn main [] -> int
  (let [first (foo 1 2 3)
        second (foo {a: 4 b: 5 c: 6})]
    (+ first second)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "first := foo(1, 2, 3)"), true)
    testing.expect_value(t, strings.contains(output, "second := foo(a = 4, b = 5, c = 6)"), true)
}

@(test)
reject_duplicate_named_call_arguments :: proc(t: ^testing.T) {
    source := `(package main)

(defn foo [a: int] -> int
  a)

(defn main [] -> int
  (foo {a: 1 a: 2}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "duplicate named argument a:"), true)
}

@(test)
compile_function_calls_fill_trailing_default_args_positionally :: proc(t: ^testing.T) {
    source := `(package main)

(defn greet [name: string, punctuation: string = "!"] -> string
  (+ name punctuation))

(defn main [] -> string
  (greet "Ada"))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "greet :: proc(name, punctuation: string) -> string"), true)
    testing.expect_value(t, strings.contains(output, "return greet(\"Ada\", \"!\")"), true)
}

@(test)
compile_named_function_calls_fill_missing_default_args :: proc(t: ^testing.T) {
    source := `(package main)

(defn greet [name: string, punctuation: string = "!"] -> string
  (+ name punctuation))

(defn main [] -> string
  (greet {name: "Ada"}))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return greet(name = \"Ada\", punctuation = \"!\")"), true)
}

@(test)
reject_named_function_calls_missing_required_args :: proc(t: ^testing.T) {
    source := `(package main)

(defn greet [name: string, punctuation: string = "!"] -> string
  (+ name punctuation))

(defn main [] -> string
  (greet {punctuation: "?"}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, strings.contains(err.message, "greet missing required argument name:"), true)
}

@(test)
compile_function_calls_support_mixed_positional_and_named_args :: proc(t: ^testing.T) {
    source := `(package main)

(defn place [name: string, x: int, y: int, label: string = "ok"] -> string
  label)

(defn main [] -> string
  (place "enemy" {x: 10 y: 20}))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return place(\"enemy\", x = 10, y = 20, label = \"ok\")"), true)
}

@(test)
reject_mixed_call_named_argument_overlapping_positional_argument :: proc(t: ^testing.T) {
    source := `(package main)

(defn place [name: string, x: int, y: int] -> int
  x)

(defn main [] -> int
  (place "enemy" {name: "boss" x: 10 y: 20}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "named argument name: overlaps positional argument 1"), true)
}

@(test)
compile_def_overload_proc_group :: proc(t: ^testing.T) {
    source := `(package main)
(import fmt "core:fmt")

(defstruct User {name: string})

(defn render-int [value: int] -> string
  (fmt.aprintf "int:%d" value))

(defn render-user [user: User] -> string
  (fmt.aprintf "user:%s" user.name))

(def render (overload render-int render-user))

(defn render-supported [value: $T] -> string
  (render value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "render :: proc{render_int, render_user}"), true)
    testing.expect_value(t, strings.contains(output, "return render(value)"), true)
}

@(test)
compile_local_def_overload_proc_group :: proc(t: ^testing.T) {
    source := `(package main)
(import fmt "core:fmt")

(defn render-int [value: int] -> string
  (fmt.aprintf "int:%d" value))

(defn render-string [value: string] -> string
  (fmt.aprintf "string:%s" value))

(defn main [] -> string
  (def render (overload render-int render-string))
  (render 1))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "    render :: proc{render_int, render_string}"), true)
    testing.expect_value(t, strings.contains(output, "return render(1)"), true)
}

@(test)
reject_empty_def_overload :: proc(t: ^testing.T) {
    source := `(package main)
(def render (overload))`

    _, err, ok := kvist.compile_source(source)
    defer delete(err.message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "overload expects at least one function name")
}

@(test)
compile_warns_for_use_after_known_owner_taking_call :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn demo []
  (let [dst (arr.empty [dynamic]int) :defer
        xs (arr.empty int)]
    (arr.push! dst xs)
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
compile_does_not_warn_for_valid_ownership_diagnostic_cases :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn local-view-use [] -> int
  (let [xs (arr.range 0 10) :defer]
    (count (arr.slice xs 0 3))))

(defn make-xs [] -> [dynamic]int
  (arr.range 0 10))

(defn explicit-delete []
  (let [xs (arr.range 0 10)]
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
ownership_audit_tracks_consumption_inside_ordinary_call_arguments :: proc(t: ^testing.T) {
    source := `(package main)

(defn make-values [] -> [dynamic]int
  (make [dynamic]int))

(defn consume [values: [dynamic]int] -> int
  (let [result (count values)]
    (delete values)
    result))

(defn demo []
  (let [values (make-values)]
    (println (consume values))))`

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
ordinary_native_storage_returns_with_odin_semantics :: proc(t: ^testing.T) {
    source := `(package main)

(defn values [] -> [out: [dynamic]int]
  (let [items (make [dynamic]int)]
    items))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "defer if kvist_owner_"), false)
    testing.expect_value(t, strings.contains(output, "return items"), true)
}
