package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

@(test)
proc_resolution_does_not_guess_transitive_generated_names :: proc(t: ^testing.T) {
    decls := []kvist.IR_Decl{
        {
            kind = .Proc,
            proc_decl = kvist.Proc_Decl{name = "outer__support__work"},
        },
    }
    emitter := kvist.Emitter{decls = decls}

    call_name, _, ok := kvist.resolve_proc_call_decl(&emitter, "support/work")
    defer delete(call_name)
    testing.expect_value(t, ok, false)
}

@(test)
compile_hello_program :: proc(t: ^testing.T) {
    source := `(package main)
(import fmt "core:fmt")

;; Greets from Kvist.
(defstruct Greeting {
  message: string
})

(defn main []
  (let [g (Greeting {
            message: "hello from kvist"
          })]
    (fmt.println g.message)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import fmt "core:fmt"

// Greets from Kvist.
Greeting :: struct {
    message: string,
}

main :: proc() {
    g := Greeting{message = "hello from kvist"}
    fmt.println(g.message)
}
`
    testing.expect_value(t, strings.trim_space(output), strings.trim_space(expected))
}

@(test)
compile_top_level_defn_decl_head :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (println "hello"))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import "core:fmt"

main :: proc() {
    fmt.println("hello")
}
`
    testing.expect_value(t, strings.trim_space(output), strings.trim_space(expected))
}

@(test)
compile_min_max_expressions :: proc(t: ^testing.T) {
    source := `(package main)

(defn clampish [x: int lo: int hi: int] -> int
  (max lo (min x hi)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return max(lo, min(x, hi))"), true)
}

@(test)
compile_do_expression_with_expected_type :: proc(t: ^testing.T) {
    source := `(package main)

(defn demo [] -> int
  (let [value: int (do
                    (println "side")
                    7)]
    value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "value: int = (proc() -> int {"), true)
    testing.expect_value(t, strings.contains(output, `fmt.println("side")`), true)
    testing.expect_value(t, strings.contains(output, "return 7"), true)
}

@(test)
compile_block_expression_captures_scalar_conversion_local :: proc(t: ^testing.T) {
    source := `(package main)

(defn demo [mode: string] -> i64
  (let [wake-at (i64 42)
        result (cond
                 (= mode "set")
                   (let [kind "action"]
                     (if (= kind "action") wake-at (i64 0)))
                 :else (i64 0))]
    result))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "wake_at: i64"), true)
    testing.expect_value(t, strings.contains(output, "wake_at)"), true)
}

@(test)
reject_statement_only_form_in_expression_position :: proc(t: ^testing.T) {
    source := `(package main)

(defn demo [] -> int
  (let [value: int (while true
                    (return 1))]
    value))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "while is a statement and cannot be used as an expression")
}

@(test)
compile_all_examples :: proc(t: ^testing.T) {
    when ODIN_OS == .Windows {
        // ponytail: too slow for Windows CI; smoke tests cover representative CLI paths there.
        return
    }

    examples := [?]string{
        "examples/coverage/cluck-port/cluck-port-arrays.kvist",
        "examples/coverage/cluck-port/cluck-port-docs.kvist",
        "examples/coverage/cluck-port/cluck-port-maps-sets.kvist",
        "examples/coverage/cluck-port/cluck-port-multi-return.kvist",
        "examples/coverage/cluck-port/cluck-port-packages.kvist",
        "examples/coverage/cluck-port/cluck-port-records.kvist",
        "examples/coverage/cluck-port/cluck-port-loops.kvist",
        "examples/coverage/cluck-port/cluck-port-strings.kvist",
        "examples/coverage/cluck-port/cluck-port-struct-defaults.kvist",
        "examples/coverage/cluck-port/cluck-port-struct-introspection.kvist",
        "examples/coverage/cluck-port/cluck-port-struct-types.kvist",
        "examples/language/closures.kvist",
        "examples/language/control-flow.kvist",
        "examples/data/core-updates.kvist",
        "examples/data/edn-write.kvist",
        "examples/data/typed-decode.kvist",
        "examples/data/typed-struct-decode.kvist",
        "examples/interop/core/core-concurrency.kvist",
        "examples/interop/core/core-container-queue.kvist",
        "examples/interop/core/core-encoding-formats.kvist",
        "examples/interop/core/core-math-linalg.kvist",
        "examples/interop/core/core-os-paths.kvist",
        "examples/interop/core/core-paths.kvist",
        "examples/interop/core/core-text-encoding.kvist",
        "examples/interop/core/core-time-slice.kvist",
        "examples/visual/constraint-cloth.kvist",
        "examples/language/data-literals.kvist",
        "examples/language/declarations.kvist",
        "examples/language/defstructs.kvist",
        "examples/visual/flocking-sim.kvist",
        "examples/language/hello.kvist",
        "examples/collections/functional-pipelines.kvist",
        "examples/collections/higher-order.kvist",
        "examples/language/inline-literals.kvist",
        "examples/interop/interop-directives.kvist",
        "examples/language/let-discard-bindings.kvist",
        "examples/language/local-declarations.kvist",
        "examples/language/macro-authoring.kvist",
        "examples/language/macro-dsl.kvist",
        "examples/language/macro-messages.kvist",
        "examples/language/macro-union-helpers.kvist",
        "examples/language/managed-data-structs.kvist",
        "examples/language/multiline-strings.kvist",
        "examples/language/multi-return-bindings.kvist",
        "examples/interop/core/matrix.kvist",
        "examples/visual/matrix-kinematics.kvist",
        "examples/interop/core/odin-types.kvist",
        "examples/language/pointers-and-raw.kvist",
        "examples/language/function-values.kvist",
        "examples/visual/reaction-diffusion.kvist",
        "examples/collections/sequence-helpers.kvist",
        "examples/collections/sequences.kvist",
        "examples/collections/package-tour.kvist",
        "examples/collections/sources.kvist",
        "examples/visual/spatial-hash-collisions.kvist",
        "examples/collections/tap.kvist",
        "examples/packages/testing.kvist",
        "examples/language/unions.kvist",
        "examples/collections/update.kvist",
        "examples/visual/wave-ripples.kvist",
        "examples/interop/vendor/vendor-raylib.kvist",
        "examples/interop/vendor/vendor-stb-easy-font.kvist",
    }

    for path in examples {
        result, err, ok := kvist.compile_path_with_map(path)
        testing.expect_value(t, ok, true)
        if !ok {
            testing.expect_value(t, err.message, "")
            continue
        }
        testing.expect_value(t, len(result.output) > 0, true)
        testing.expect_value(t, len(result.source_map) > 0, true)
        delete(result.output)
        kvist.source_map_slice_delete(result.source_map)
        kvist.compile_warning_slice_delete(result.warnings)
    }
}

@(test)
compile_as_form_is_removed :: proc(t: ^testing.T) {
    source := `(package main)

(defn main [] -> f32
  (as f32 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, strings.contains(err.message, "`as` has been removed"), true)
}

@(test)
compile_new_form_is_removed :: proc(t: ^testing.T) {
    source := `(package main)

(defn main [] -> []int
  (new []int [1 2 3]))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, strings.contains(err.message, "`new` has been removed"), true)
}

@(test)
compile_update_bang_stmt :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct Point
  {x: int
   y: int})

(defn score [] -> int
    (let [xs ([dynamic]int [1 2 3])
        lookup (map[string]int {"a" 1})
        point (Point {x: 4 y: 5})]
    (set! xs[1] 42)
    (set! (get lookup "a") 7)
    (set! (get point .x) 8)
    (set! point.y 9)
    (+ (+ (get xs 1) (get lookup "a"))
       (+ (get point .x) (get point .y)))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "(xs)[1] = 42"), true)
    testing.expect_value(t, strings.contains(output, "lookup[\"a\"] = 7"), true)
    testing.expect_value(t, strings.contains(output, "(point).x = 8"), true)
    testing.expect_value(t, strings.contains(output, "point.y = 9"), true)
    testing.expect_value(t, strings.contains(output, "((point).x) + ((point).y)"), true)
}

@(test)
compile_canonical_bare_core_helpers :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point {
  x: int
})

(defn score [needle: int] -> int
  (let [xs ([dynamic]int [1 2 3])
        lookup (map[string]int {"a" 4})
        tail (slice xs 1)
        total (count xs)
        point (Point {x: 1})
        associated (assoc point.x total)
        updated (update associated.x + 1)]
    (update! xs[0] + 10)
    (delete! lookup "a")
    (if (contains? xs needle)
      (if (contains? lookup "a")
        (if (not (contains? lookup "b"))
          (if (empty? (slice tail))
            0
            (+ total (get xs 0) (get updated .x)))
          0)
        0)
      0)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "(xs)[1:]"), true)
    testing.expect_value(t, strings.contains(output, "total := len(xs)"), true)
    testing.expect_value(t, strings.contains(output, "(xs)[0] += 10"), true)
    testing.expect_value(t, strings.contains(output, "delete_key(&(lookup), \"a\")"), true)
    testing.expect_value(t, strings.contains(output, "kvist_contains_value((xs)[:]"), true)
    testing.expect_value(t, strings.contains(output, "(\"a\") in (lookup)"), true)
    testing.expect_value(t, strings.contains(output, "!((\"b\") in (lookup))"), true)
    testing.expect_value(t, strings.contains(output, "(len((tail)[:])) == (0)"), true)
    testing.expect_value(t, strings.contains(output, "associated := (proc(kvist_target: Point, kvist_value: int) -> Point {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_1.x = kvist_value"), true)
    testing.expect_value(t, strings.contains(output, "updated := (proc(kvist_target: Point, kvist_arg_0: int) -> Point {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_update_2.x = (kvist_target.x) + (kvist_arg_0)"), true)
    testing.expect_value(t, strings.contains(output, "(total) + (xs[0]) + ((updated).x)"), true)
}

@(test)
compile_runtime_initialized_immutable_defs :: proc(t: ^testing.T) {
    source := `(package main)
(import edn "kvist:edn")

(def config (edn.read "{:port 8080}"))

(defn port [] -> i64
  (data.int (get config :port)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "config: Data\n"), true)
    testing.expect_value(t, strings.contains(output, "@(init)\n__kvist_runtime_defs_init :: proc \"contextless\" ()"), true)
    testing.expect_value(t, strings.contains(output, "config = edn__read(\"{:port 8080}\")"), true)
    testing.expect_value(t, strings.contains(output, "@(fini)\n__kvist_runtime_defs_fini :: proc \"contextless\" ()"), true)
    testing.expect_value(t, strings.contains(output, "kvist_data_release(config)"), true)

    eval_output, eval_err, eval_ok := kvist.compile_eval_source(source, "(data.int (get config :port))", true)
    testing.expect_value(t, eval_ok, true)
    if !eval_ok {
        testing.expect_value(t, eval_err.message, "")
        return
    }
    defer delete(eval_output)
    testing.expect_value(t, strings.contains(eval_output, "config = edn__read(\"{:port 8080}\")"), true)
}

@(test)
compile_runtime_defs_initialize_in_declaration_order :: proc(t: ^testing.T) {
    source := `(package main)

(defn seed [] -> int 40)
(defn add-two [value: int] -> int (+ value 2))

(def first (seed))
(def second (add-two first))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    first_at := strings.index(output, "first = seed()")
    second_at := strings.index(output, "second = add_two(first)")
    testing.expect_value(t, first_at >= 0, true)
    testing.expect_value(t, second_at > first_at, true)
}

@(test)
compile_def_and_defvar_forms :: proc(t: ^testing.T) {
    source := `(package main)
(import sync "core:sync")

(def answer 42)
(def max-size: int 1024)
(defvar lock: sync.Mutex)
(defvar table: map[int]string)
(defvar live-port: int 8080)
(defvar retries 3)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "answer :: 42"), true)
    testing.expect_value(t, strings.contains(output, "max_size: int : 1024"), true)
    testing.expect_value(t, strings.contains(output, "lock: sync.Mutex"), true)
    testing.expect_value(t, strings.contains(output, "table: map[int]string"), true)
    testing.expect_value(t, strings.contains(output, "live_port: int = 8080"), true)
    testing.expect_value(t, strings.contains(output, "retries := 3"), true)
}

@(test)
compile_rejects_removed_defconst_form :: proc(t: ^testing.T) {
    source := `(package main)

(defconst answer 42)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        delete(output)
    }
    testing.expect_value(t, strings.contains(err.message, "unsupported top-level form: defconst"), true)
    delete(err.message)
}

@(test)
compile_local_declaration_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defn classify [code: int] -> int
  (def max-code: int 10)
  (defenum Status [OK Err])
  (defstruct Payload {code: int status: Status})
  (defunion Value {payload: Payload raw: int})
  (let [payload (Payload {code: code status: .OK})
        value (Value {payload: payload})]
    (if (> payload.code max-code)
      1
      0)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

classify :: proc(code: int) -> int {
    max_code: int : 10
    Status :: enum {
        OK,
        Err,
    }
    Payload :: struct {
        code: int,
        status: Status,
    }
    Value :: union {
        Payload,
        int,
    }
    payload := Payload{code = code, status = .OK}
    value := Value(payload)
    if (payload.code) > (max_code) {
        return 1
    }
    else {
        return 0
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
reject_nary_not_equal :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [a: int, b: int, c: int] -> bool
  (!= a b c))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "!= expects exactly two arguments")
}

@(test)
reject_removed_in_forms_with_canonical_messages :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [lookup: map[string]int, key: string] -> bool
  (in key lookup))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "`in` has been removed; use `contains?`")
}

@(test)
reject_removed_not_in_form_with_canonical_message :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [lookup: map[string]int, key: string] -> bool
  (not-in key lookup))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "`not-in` has been removed; use `(not (contains? collection value))`")
}

@(test)
reject_contains_question_string_needle_with_canonical_message :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [] -> bool
  (contains? "abc" 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "contains? on strings expects a string needle")
}

@(test)
compile_break_and_continue_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defn first-positive [xs: []int] -> int
  (let [result 0]
    (for [x xs]
      (when (< x 0)
        (continue))
      (when (> x 0)
        (set! result x)
        (break)))
    result))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

first_positive :: proc(xs: []int) -> int {
    result := 0
    for x in xs {
        if (x) < (0) {
            continue
        }
        if (x) > (0) {
            result = x
            break
        }
    }
    return result
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_indexed_symbol_expr_and_places :: proc(t: ^testing.T) {
    source := `(package main)

(defn read-at [xs: []int, i: int] -> int
  xs[i])

(defn write-at [xs: [dynamic]int, i: int]
  (set! xs[i] 10)
  (mut! xs[i] += 2))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return (xs)[i]"), true)
    testing.expect_value(t, strings.contains(output, "(xs)[i] = 10"), true)
    testing.expect_value(t, strings.contains(output, "(xs)[i] += 2"), true)
}

@(test)
compile_expression_index_places :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct State {cells: [dynamic]int})

(defstruct User {name: string})

(defstruct User-State {users: [dynamic]User})

(defn idx [x: int, y: int] -> int
  (+ x (* y 10)))

(defn touch [state: State, x: int, y: int] -> int
  (set! state.cells[(idx x y)] 10)
  (mut! state.cells[(idx x y)] += 2)
  state.cells[(idx x y)])

(defn pick-name [state: User-State, x: int, y: int] -> string
  state.users[(idx x y)].name)

(defn read-matrix [matrix: [][]int, row: int, col: int] -> int
  matrix[row][col])

(defn slice-views [xs: []int, start: int, end: int] -> int
  (let [all xs[:]
        tail xs[start:]
        head xs[:end]
        mid xs[start:end]
        next xs[(+ start 1):(+ end 1)]]
    (+ (count all)
       (count tail)
       (count head)
       (count mid)
       (count next))))

(defn write-matrix [matrix: [dynamic][dynamic]int, row: int, col: int]
  (set! matrix[row][col] 42)
  (mut! matrix[row][col] += 1))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "(state.cells)[idx(x, y)] = 10"), true)
    testing.expect_value(t, strings.contains(output, "(state.cells)[idx(x, y)] += 2"), true)
    testing.expect_value(t, strings.contains(output, "return (state.cells)[idx(x, y)]"), true)
    testing.expect_value(t, strings.contains(output, "return (state.users)[idx(x, y)].name"), true)
    testing.expect_value(t, strings.contains(output, "return ((matrix)[row])[col]"), true)
    testing.expect_value(t, strings.contains(output, "all := (xs)[:]"), true)
    testing.expect_value(t, strings.contains(output, "tail := (xs)[start:]"), true)
    testing.expect_value(t, strings.contains(output, "head := (xs)[:end]"), true)
    testing.expect_value(t, strings.contains(output, "mid := (xs)[start:end]"), true)
    testing.expect_value(t, strings.contains(output, "next := (xs)[(start) + (1):(end) + (1)]"), true)
    testing.expect_value(t, strings.contains(output, "((matrix)[row])[col] = 42"), true)
    testing.expect_value(t, strings.contains(output, "((matrix)[row])[col] += 1"), true)
}

@(test)
compile_each_form_is_removed :: proc(t: ^testing.T) {
    source := `(package main)

(defn total [xs: []int] -> int
  (let [sum 0]
    (each [x xs]
      (set! sum (+ sum x)))
    sum))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "`each` has been removed; use `for` for collection iteration")
}

@(test)
implicit_core_comment_helper :: proc(t: ^testing.T) {
    source := `(package main)
(comment
  (fmt.println "ignored"))

(defn main []
  (return))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "main :: proc()"), true)
}

@(test)
implicit_core_comment_helper_inside_function :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (comment
    (missing.package "ignored"))
  (return))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "missing"), false)
}

compile_case_does_not_emit_switch_warning :: proc(t: ^testing.T) {
    source := `(package main)

(defn classify [n: int] -> string
  (case n
    0 "zero"
    "other"))`

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
    testing.expect_value(
        t,
        strings.contains(result.output, "xs = replacement"),
        true,
    )
}

@(test)
compile_tap_helper :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")
(import fmt "core:fmt")

(defn main []
  (let [answer (tap> "answer" 42)
        owned (tap> "owned" ([dynamic]int [1 2 3]))]
    (defer (delete owned))
    (fmt.println answer)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "fmt.print(\"answer\")"), true)
    testing.expect_value(t, strings.contains(output, "fmt.print(\"owned\")"), true)
    testing.expect_value(t, strings.contains(output, "fmt.print(\": \")"), true)
    testing.expect_value(t, strings.contains(output, "fmt.println(kvist_tap"), true)
    testing.expect_value(t, strings.contains(output, "answer := kvist_tap"), true)
    testing.expect_value(t, strings.contains(output, "owned := kvist_tap"), true)
    testing.expect_value(t, strings.contains(output, "tap_impl"), false)
    testing.expect_value(t, strings.contains(output, "tap_labeled_impl"), false)
}

@(test)
reject_tap_label_with_canonical_message :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [] -> int
  (tap> 1 2))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "while expanding macro tap>: tap> label must be a string literal")
}

@(test)
compile_or_else_optional_ok_expression :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn query [] -> [value: int, ok: bool] #optional_ok
  (return 42 true))

(defn total [] -> int
  (or-else (query) 7))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return (query()) or_else (7)"), true)
}

@(test)
reject_or_else_wrong_arity :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn query [] -> [value: int, ok: bool] #optional_ok
  (return 42 true))

(defn total [] -> int
  (or-else (query)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "or-else expects 2 arguments")
}

@(test)
compile_core_higher_order_helpers_and_slice_exprs :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")
(import core "kvist:core")

(defn inc [x: int] -> int
  (+ x 1))

(defn even? [x: int] -> bool
  (= (% x 2) 0))

(defn add [acc: int, x: int] -> int
  (+ acc x))

(defn main []
  (let [xs ([]int [1 2 3 4])
        mapped (arr.map inc xs)
        tail (slice mapped 1)
        evens (arr.filter even? mapped)
        total (count evens)
        middle (slice mapped 0 1)]
    (defer (delete mapped))
    (defer (delete evens))
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "mapped := arr__map_impl(inc, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "evens := arr__filter_impl(even_p, (mapped)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "total := len(evens)"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(mapped)"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(evens)"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_impl :: #force_inline proc"), true)
    testing.expect_value(t, strings.contains(output, "arr__filter_impl :: #force_inline proc"), true)
}

@(test)
reject_defiter_next_wrong_state_parameter :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct File_Source {
  index: int
})

(defstruct Other_Source {
  index: int
})

(defn open-files [] -> File_Source
  (File_Source {index: 0}))

(defn next-file [src: ^Other_Source] -> [path: string ok: bool]
  (return "" false))

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
    testing.expect_value(t, err.message, "defiter files :next must take ^File_Source")
}

@(test)
compile_leaves_legacy_unqualified_helpers_as_plain_calls :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn main [xs: []int, path: string]
  (map inc xs)
  (filter inc xs)
  (range 5)
  (zipmap xs xs)
  (slurp path)
  (return))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "map(inc, xs)"), true)
    testing.expect_value(t, strings.contains(output, "filter(inc, xs)"), true)
    testing.expect_value(t, strings.contains(output, "range(5)"), true)
    testing.expect_value(t, strings.contains(output, "zipmap(xs, xs)"), true)
    testing.expect_value(t, strings.contains(output, "slurp(path)"), true)
    testing.expect_value(t, strings.contains(output, "arr/"), false)
    testing.expect_value(t, strings.contains(output, "map/zip"), false)
    testing.expect_value(t, strings.contains(output, "io/read"), false)
}

@(test)
compile_local_var_block_and_mut_bang_forms :: proc(t: ^testing.T) {
    source := `(package main)
(import rl "vendor:raylib")

(defn main []
  (defvar player-pos (rl.Vector2 [0 0]))
  (defvar player-vel: rl.Vector2 [1 2])
  (block
    (defvar dt 0.5)
    (mut! player-vel.y += dt)
    (set! player-pos.x 10)))`

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
    player_pos := rl.Vector2{0, 0}
    player_vel: rl.Vector2 = rl.Vector2{1, 2}
    {
        dt := 0.5
        player_vel.y += dt
        player_pos.x = 10
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_rejects_list_form_address_of :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Person {
  name: string
})

(defn borrow-name [p: ^Person] -> ^string
  (& p^.name))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "address-of list form is not supported; use &value or (addr value)")
}

@(test)
compile_function_style_update_bang :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct Point {
  x: int
  y: int
})

(defn score [] -> int
  (let [xs ([dynamic]int [1 2 3])
        lookup (map[string]int {"a" 1})
        point (Point {x: 4 y: 5})]
    (update! xs[1] + 40)
    (update! xs[2] + 3)
    (update! (get lookup "a") + 6)
    (update! point.y + 4)
    (update! point.y inc)
    (+ (get xs 1) (get lookup "a") point.y)))`

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
}

score :: proc() -> int {
    xs := [dynamic]int{1, 2, 3}
    lookup := map[string]int{"a" = 1}
    point := Point{x = 4, y = 5}
    (xs)[1] += 40
    (xs)[2] += 3
    lookup["a"] += 6
    point.y += 4
    point.y += 1
    return (xs[1]) + (lookup["a"]) + (point.y)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_place_style_update_bang :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct Point {
  x: int
  name: string
})

(defn add-scaled [x: int scale: int delta: int] -> int
  (+ x (* scale delta)))

(defn trim-demo [s: string] -> string
  s)

(defn score [] -> int
  (let [point (Point {x: 4 name: "Ada"})
        total 10]
    (update! point.x add-scaled 2 3)
    (update! point.name trim-demo)
    (update! total + 5)
    (+ point.x total)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "point.x = add_scaled(point.x, 2, 3)"), true)
    testing.expect_value(t, strings.contains(output, "point.name = trim_demo(point.name)"), true)
    testing.expect_value(t, strings.contains(output, "total += 5"), true)
}

@(test)
compile_update_bang_rejects_target_key_form :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn bad [] -> int
  (let [xs ([dynamic]int [1 2 3])]
    (update! xs 1 + 40)
    (get xs 1)))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, err.message, "while expanding macro update!: update! expects updater function or operator")
}

@(test)
compile_update_bang_rejects_non_place :: proc(t: ^testing.T) {
    source := `(package main)

(defn bad [x: int y: int]
  (update! (+ x y) + 1))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "mut! expects an assignable place")
}

@(test)
compile_update_bang_unary_inc :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct Point {
  y: int
})

(defn inc [x: int] -> int
  (+ x 1))

(defn score [] -> int
  (let [point (Point {y: 5})]
    (update! point.y inc)
    point.y))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "point.y += 1"), true)
}

@(test)
compile_nil_predicate :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defstruct User {
  name: string
})

(defn has-user [p: ^User] -> bool
  (not (nil? p)))

(defn has-user-qualified [p: ^User] -> bool
  (not (core.nil? p)))

(defn print-user [p: ^User]
  (when (nil? p)
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

User :: struct {
    name: string,
}

has_user :: proc(p: ^User) -> bool {
    return !((p) == (nil))
}

has_user_qualified :: proc(p: ^User) -> bool {
    return !((p) == (nil))
}

print_user :: proc(p: ^User) {
    if (p) == (nil) {
        return
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_lisp_predicate_and_bang_identifier_names :: proc(t: ^testing.T) {
    source := `(package main)

(defn greater-than? [threshold: int, x: int] -> bool
  (> x threshold))

(defn bump! [x: ^int]
  (set! (deref x) (+ (deref x) 1)))

(defn main []
  (let [x 1]
    (greater-than? 0 x)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

greater_than_p :: proc(threshold, x: int) -> bool {
    return (x) > (threshold)
}

bump_bang :: proc(x: ^int) {
    x^ = (x^) + (1)
}

main :: proc() {
    x := 1
    greater_than_p(0, x)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
reject_unknown_named_argument :: proc(t: ^testing.T) {
    source := `(package main)

(defn greet [name: string, punctuation: string = "!"] -> string
  (+ name punctuation))

(defn main [] -> string
  (greet {name: "Ada" tone: "warm"}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "unknown named argument tone:"), true)
    testing.expect_value(t, strings.contains(err.message, "valid named args: name:, punctuation:"), true)
}

@(test)
reject_unknown_named_argument_with_typo_suggestion :: proc(t: ^testing.T) {
    source := `(package main)

(defn greet [name: string, punctuation: string = "!"] -> string
  (+ name punctuation))

(defn main [] -> string
  (greet {name: "Ada" punctuaton: "?"}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "unknown named argument punctuaton:"), true)
    testing.expect_value(t, strings.contains(err.message, "did you mean punctuation:"), true)
}

@(test)
reject_required_parameter_after_default_parameter :: proc(t: ^testing.T) {
    source := `(package main)

(defn greet [name: string = "Ada", punctuation: string] -> string
  (+ name punctuation))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "parameters with defaults must trail required parameters"), true)
}

@(test)
compile_mixed_calls_fill_named_and_default_tail_args :: proc(t: ^testing.T) {
    source := `(package main)

(defn draw [target: int, x: int, y: int, color: int = 7, scale: int = 1] -> int
  color)

(defn main [] -> int
  (draw 99 {y: 20 x: 10 scale: 3}))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return draw(99, x = 10, y = 20, color = 7, scale = 3)"), true)
}

@(test)
compile_general_calls_support_trailing_named_args :: proc(t: ^testing.T) {
    source := `(package main)
(import strings "core:strings")

(defn clone-temp [s: string] -> string
  (let [[out err] (strings.clone s {allocator: context.temp_allocator})]
    out))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "strings.clone(s, allocator = context.temp_allocator)"), true)
}

@(test)
compile_general_dotted_calls_support_pure_named_args :: proc(t: ^testing.T) {
    source := `(package main)
(import fmt "core:fmt")

(defn demo []
  (fmt.println {value: 1 label: "ok"}))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "fmt.println(value = 1, label = \"ok\")"), true)
}

@(test)
reject_mixed_calls_missing_required_tail_args :: proc(t: ^testing.T) {
    source := `(package main)

(defn place [name: string, x: int, y: int, label: string = "ok"] -> string
  label)

(defn main [] -> string
  (place "enemy" {x: 10}))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    testing.expect_value(t, strings.contains(err.message, "place missing required argument y:"), true)
}

@(test)
compile_proc_directives_and_declaration_attributes :: proc(t: ^testing.T) {
    source := `(package main)

@private
(defn hidden [] -> int #force_inline
  1)

(defn query [] -> [value: int, ok: bool] #optional_ok
  (return 42 true))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

expected := `package main

@(private)
hidden :: #force_inline proc() -> int {
    return 1
}

query :: proc() -> (value: int, ok: bool) #optional_ok {
    return 42, true
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_proc_where_constraints :: proc(t: ^testing.T) {
    source := `(package main)
(import intrinsics "base:intrinsics")

(defn same? [value: $T, expected: T] -> bool
  (where (intrinsics.type-is-comparable T))
  (= value expected))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "same_p :: proc(value: $T, expected: T) -> bool where intrinsics.type_is_comparable(T) {"), true)
}

@(test)
reject_old_attr_form :: proc(t: ^testing.T) {
    source := `(package main)

(attr)
(def answer 42)`

    _, err, ok := kvist.compile_source(source)
    defer delete(err.message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "`(attr name)` has been removed; use `@name`")
}

@(test)
reject_old_export_form :: proc(t: ^testing.T) {
    source := `(package main)

(export)
(def answer 42)`

    _, err, ok := kvist.compile_source(source)
    defer delete(err.message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "`(export)` has been removed; use `@export`")
}

@(test)
reject_old_exports_form :: proc(t: ^testing.T) {
    source := `(package main)

(exports [Raw_Handle])
(odin "Raw_Handle :: distinct rawptr")`

    _, err, ok := kvist.compile_source(source)
    defer delete(err.message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "`(exports [Name])` has been removed; use `@exports [Name]`")
}

@(test)
compile_user_proc_forwards_captured_callback_context :: proc(t: ^testing.T) {
    source := "(package main)\n\n(defn apply-one [f: (fn [x: int] -> int), x: int] -> int\n  (f x))\n\n(defn apply-twice [f: (fn [x: int] -> int), x: int] -> int\n  (+ (apply-one f x) (apply-one f x)))\n\n(defn demo [] -> int\n  (let [offset 10]\n    (apply-twice (fn [x: int] -> int (+ x offset)) 5)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "apply_twice__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "return (apply_one__kvist_capture_0_1(f, kvist_capture_1, x)) + (apply_one__kvist_capture_0_1(f, kvist_capture_1, x))"), true)
    testing.expect_value(t, strings.contains(output, "apply_one__kvist_capture_0_1 :: proc(f: proc(c1: $C1, x: int) -> int, kvist_capture_1: C1, x: int) -> int {"), true)
}

@(test)
compile_user_proc_rejects_escaping_captured_callback :: proc(t: ^testing.T) {
    source := "(package main)\n\n(defn escape [f: (fn [x: int] -> int), x: int] -> int\n  (let [g f]\n    (g x)))\n\n(defn demo [] -> int\n  (let [offset 10]\n    (escape (fn [x: int] -> int (+ x offset)) 5)))"

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "captured callback cannot be passed to escape because callback parameter f may escape"), true)
}

@(test)
compile_directive_expression_wrappers :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn main []
  (let [x (inc 41 #force_inline)
        y (inc x #force_inline)]
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

inc :: proc(x: int) -> int {
    return (x) + (1)
}

main :: proc() {
    x := #force_inline inc(41)
    y := #force_inline inc(x)
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_caller_intrinsic_expressions :: proc(t: ^testing.T) {
    source := `(package main)
(import rt "base:runtime")

(defn location [loc: rt.Source_Code_Location = #caller_location] -> rt.Source_Code_Location
  loc)

(defn expression [x: bool, expr: string = (#caller_expression x)] -> string
  expr)

(defn demo [] -> string
  (discard (location))
  (expression true))

(defn named-demo [] -> string
  (expression {x: false}))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "loc: rt.Source_Code_Location = #caller_location"), true)
    testing.expect_value(t, strings.contains(output, "expr: string = #caller_expression(x)"), true)
    testing.expect_value(t, strings.contains(output, "_ = location()"), true)
    testing.expect_value(t, strings.contains(output, "return expression(true)"), true)
    testing.expect_value(t, strings.contains(output, "return expression(x = false)"), true)
}

@(test)
reject_proc_directive_before_non_proc_declaration :: proc(t: ^testing.T) {
    source := `(package main)

(odin "#force_inline")
(def answer 42)`

    _, err, ok := kvist.compile_source(source)
    defer delete(err.message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "procedure directive must be followed by a proc declaration")
}

@(test)
compile_exported_c_abi_proc_and_var :: proc(t: ^testing.T) {
    source := `(package main)

@export
(defvar hot_api_version: u32 1)

@export
(defn hot_tick :abi "c" [state: rawptr] -> int
  42)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

@(export)
hot_api_version: u32 = 1

@(export)
hot_tick :: proc "c" (state: rawptr) -> int {
    return 42
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_reload_state_alias_program :: proc(t: ^testing.T) {
    source := `(package main)

(defstruct App_State
  {steps: int})

(def Reload_State App_State)
(def Reload_Version "v1")

(defn run [state: ^Reload_State host: ^reload__Run_Host]
  (mut! state^.steps += 1))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "App_State :: struct"), true)
    testing.expect_value(t, strings.contains(output, "Reload_State :: App_State"), true)
    testing.expect_value(t, strings.contains(output, "run :: proc"), true)
}

@(test)
compile_defstate_is_not_supported :: proc(t: ^testing.T) {
    source := `(package main)

(defstate App_State
  {requests: int}
  {run: run
   version: "v1"})

(defn run [state: ^App_State host: ^reload__Run_Host]
  (mut! state^.requests += 1))`

    _, err, ok := kvist.compile_source(source)
    if err.message != "" {
        delete(err.message)
    }
    testing.expect_value(t, ok, false)
}

@(test)
compile_discard_statement :: proc(t: ^testing.T) {
    source := `(package main)

(defn observe [x: int, y: int]
  (discard x y)
  (return))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

observe :: proc(x, y: int) {
    _ = x
    _ = y
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
reject_removed_ownership_syntax :: proc(t: ^testing.T) {
    source := `(package main)
(defn invalid [value: (owned Data)] -> Data
  value)`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "ownership-qualified types have been removed"), true)
}

@(test)
reject_removed_ownership_directives :: proc(t: ^testing.T) {
    source := `(package main)
(defn invalid [value: Data] -> Data #owned
  value)`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "#owned has been removed"), true)
}
