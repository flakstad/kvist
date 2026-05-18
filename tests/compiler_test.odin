package tests

import "base:runtime"
import "core:strings"
import "core:testing"
import odinl "../src/odinl"

@(test)
compile_hello_program :: proc(t: ^testing.T) {
    source := `(package main)
(import "core:fmt")

// Greets from OdinL.
(struct Greeting {
  :message string
})

(proc main []
  (let [g (Greeting {
            :message "hello from odinl"
          })]
    (fmt.println (:message g))))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import "core:fmt"

// Greets from OdinL.
Greeting :: struct {
    message: string,
}

main :: proc() {
    g := Greeting{message = "hello from odinl"}
    fmt.println(g.message)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_all_examples :: proc(t: ^testing.T) {
    examples := [?]string{
        "examples/control-flow.odinl",
        "examples/data-literals.odinl",
        "examples/declarations.odinl",
        "examples/hello.odinl",
        "examples/higher-order.odinl",
        "examples/interop-directives.odinl",
        "examples/pointers-and-raw.odinl",
        "examples/proc-values.odinl",
        "examples/sequence-helpers.odinl",
        "examples/sequences.odinl",
        "examples/unions.odinl",
    }

    for path in examples {
        result, err, ok := odinl.compile_path_with_map(path)
        testing.expect_value(t, ok, true)
        if !ok {
            testing.expect_value(t, err.message, "")
            continue
        }
        testing.expect_value(t, len(result.output) > 0, true)
        testing.expect_value(t, len(result.source_map) > 0, true)
        delete(result.output)
        delete(result.source_map)
    }
}

@(test)
compile_eval_source_generates_scratch_main :: proc(t: ^testing.T) {
    source := `(package app)
(import "core:fmt")

(proc add [a: int, b: int] -> int
  (+ a b))

(proc main []
  (fmt.println "ordinary main"))`

    output, err, ok := odinl.compile_eval_source(source, "(add 20 22)")
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import "core:fmt"

add :: proc(a: int, b: int) -> int {
    return (a) + (b)
}

main :: proc() {
    fmt.println(add(20, 22))
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_eval_source_can_emit_statement_runner :: proc(t: ^testing.T) {
    source := `(package main)
(import "core:fmt")

(proc add [a: int, b: int] -> int
  (+ a b))`

    output, err, ok := odinl.compile_eval_source(source, "(fmt.println (add 1 2))", true)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import "core:fmt"

add :: proc(a: int, b: int) -> int {
    return (a) + (b)
}

main :: proc() {
    fmt.println(add(1, 2))
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_eval_source_can_load_declaration_form :: proc(t: ^testing.T) {
    source := `(package main)

(struct Greeting {
  :message string
})`

    output, err, ok := odinl.compile_eval_source(source, `(struct Greeting {
  :message string
})`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Greeting :: struct {
    message: string,
}

main :: proc() {
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_eval_source_deduplicates_import_declaration_form :: proc(t: ^testing.T) {
    source := `(package main)
(import "core:fmt")

(proc main []
  (fmt.println "hello"))`

    output, err, ok := odinl.compile_eval_source(source, `(import "core:fmt")`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import "core:fmt"

main :: proc() {
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_eval_source_can_load_main_proc_declaration_form :: proc(t: ^testing.T) {
    source := `(package main)
(import "core:fmt")

(proc main []
  (fmt.println "hello"))`

    output, err, ok := odinl.compile_eval_source(source, `(proc main []
  (fmt.println "hello"))`)
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
    testing.expect_value(t, output, expected)
}

@(test)
compile_eval_source_reports_eval_origin :: proc(t: ^testing.T) {
    source := `(package main)

(proc add [a: int, b: int] -> int
  (+ a b))`

    _, err, ok := odinl.compile_eval_source(source, "(not 1 2)")
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.span.source, odinl.Source_Kind.Eval)

    formatted := odinl.format_eval_compile_error("app.odinl", source, "(not 1 2)", err)
    defer delete(formatted)
    expected := `app.odinl:<eval>:1:1: not expects one argument
  (not 1 2)
  ^
`
    testing.expect_value(t, formatted, expected)
}

@(test)
compile_eval_source_map_marks_eval_runner :: proc(t: ^testing.T) {
    source := `(package main)

(proc add [a: int, b: int] -> int
  (+ a b))`

    result, err, ok := odinl.compile_eval_source_with_map(source, "(add 1 2)")
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)

    found_eval_entry := false
    for entry in result.source_map {
        if entry.source_span.source == .Eval {
            found_eval_entry = true
            break
        }
    }
    testing.expect_value(t, found_eval_entry, true)
}

@(test)
reader_supports_hash_underscore_and_comment_form :: proc(t: ^testing.T) {
    source := `(package main)
#_(struct Ignored {
  :field string
})
(comment
  (proc old []
    (fmt.println "old")))
(proc main []
  (return))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    expected := `package main

main :: proc() {
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
reader_preserves_top_form_source_text :: proc(t: ^testing.T) {
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    source := `// Doc.
(package main)

(const answer 42)`

    forms, err, ok := odinl.read_top_forms(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }

    testing.expect_value(t, len(forms), 2)
    testing.expect_value(t, forms[0].source, "(package main)")
    testing.expect_value(t, len(forms[0].doc_lines), 1)
    testing.expect_value(t, forms[0].doc_lines[0], "// Doc.")
    testing.expect_value(t, forms[1].source, "(const answer 42)")
}

@(test)
reader_converts_semicolon_doc_comments :: proc(t: ^testing.T) {
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    source := `; Lisp doc.
(const answer 42)`

    forms, err, ok := odinl.read_top_forms(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }

    testing.expect_value(t, len(forms), 1)
    testing.expect_value(t, len(forms[0].doc_lines), 1)
    testing.expect_value(t, forms[0].doc_lines[0], "// Lisp doc.")
}

@(test)
reader_classifies_core_literals :: proc(t: ^testing.T) {
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    source := `(const answer 42)
(const negative -1)
(const ok true)
(const none nil)`

    forms, err, ok := odinl.read_top_forms(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }

    testing.expect_value(t, forms[0].form.items[2].kind, odinl.CST_Form_Kind.Number)
    testing.expect_value(t, forms[1].form.items[2].kind, odinl.CST_Form_Kind.Number)
    testing.expect_value(t, forms[2].form.items[2].kind, odinl.CST_Form_Kind.Bool)
    testing.expect_value(t, forms[3].form.items[2].kind, odinl.CST_Form_Kind.Nil)
}

@(test)
compile_source_with_declaration_source_map :: proc(t: ^testing.T) {
    source := `(package main)

(const answer 42)

(proc main []
  (return))`

    result, err, ok := odinl.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)

    expected := `package main

answer :: 42

main :: proc() {
    return
}
`
    testing.expect_value(t, result.output, expected)
    testing.expect_value(t, len(result.source_map), 3)
    testing.expect_value(t, result.source_map[0].generated_start_line, 1)
    testing.expect_value(t, result.source_map[0].generated_end_line, 1)
    testing.expect_value(t, result.source_map[1].generated_start_line, 3)
    testing.expect_value(t, result.source_map[1].generated_end_line, 3)
    testing.expect_value(t, result.source_map[2].generated_start_line, 5)
    testing.expect_value(t, result.source_map[2].generated_end_line, 7)
    testing.expect_value(t, result.source_map[1].source_span.start > result.source_map[0].source_span.start, true)
}

@(test)
compile_source_map_accounts_for_feature_line_and_multiline_raw :: proc(t: ^testing.T) {
    source := `(package main)

(odin "Foreign_Handle :: distinct rawptr\nOther_Handle :: distinct rawptr")

(proc main []
  (let [lookup (new map[string]int {"one" 1})]
    (return)))`

    result, err, ok := odinl.compile_source_with_map(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer delete(result.source_map)

    testing.expect_value(t, len(result.source_map), 3)
    testing.expect_value(t, result.source_map[0].generated_start_line, 2)
    testing.expect_value(t, result.source_map[0].generated_end_line, 2)
    testing.expect_value(t, result.source_map[1].generated_start_line, 4)
    testing.expect_value(t, result.source_map[1].generated_end_line, 5)
    testing.expect_value(t, result.source_map[2].generated_start_line, 7)
    testing.expect_value(t, result.source_map[2].generated_end_line, 10)
}

@(test)
format_declaration_source_map :: proc(t: ^testing.T) {
    entries := [?]odinl.Source_Map_Entry{
        {
            generated_start_line = 1,
            generated_end_line = 3,
            source_span = odinl.Span{start = 10, end = 20},
        },
    }

    formatted := odinl.format_source_map(entries[:])
    defer delete(formatted)

    expected := `generated_start generated_end source_start source_end
1 3 10 20
`
    testing.expect_value(t, formatted, expected)

    entry, found := odinl.source_map_entry_for_generated_line(entries[:], 2)
    testing.expect_value(t, found, true)
    testing.expect_value(t, entry.source_span.start, 10)

    _, missing := odinl.source_map_entry_for_generated_line(entries[:], 4)
    testing.expect_value(t, missing, false)
}

@(test)
compile_const_and_enum_forms :: proc(t: ^testing.T) {
    source := `(package main)

// Default answer for bootstrapping.
(const answer 42)
; Maximum configured size.
(const max-size int 1024)

(enum Method [
  Get
  Post
  Delete
])

(enum Http-Status {
  :OK 200
  :Not-Found 404
  :Unprocessable-Content 422
})`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

// Default answer for bootstrapping.
answer :: 42

// Maximum configured size.
max_size: int : 1024

Method :: enum {
    Get,
    Post,
    Delete,
}

Http_Status :: enum {
    OK = 200,
    Not_Found = 404,
    Unprocessable_Content = 422,
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_switch_with_implicit_branch_returns :: proc(t: ^testing.T) {
    source := `(package main)

(enum Method [
  Get
  Post
  Delete
])

(proc method-name [method: Method] -> string
  (switch method
    .Get "GET"
    .Post "POST"
    :else "OTHER"))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Method :: enum {
    Get,
    Post,
    Delete,
}

method_name :: proc(method: Method) -> string {
    #partial switch method {
    case .Get:
        return "GET"
    case .Post:
        return "POST"
    case:
        return "OTHER"
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_switch_with_grouped_value_cases :: proc(t: ^testing.T) {
    source := `(package main)

(enum Method [
  Get
  Head
  Post
])

(proc read-method? [method: Method] -> bool
  (switch method
    [.Get .Head] true
    :else false))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Method :: enum {
    Get,
    Head,
    Post,
}

read_method_p :: proc(method: Method) -> bool {
    #partial switch method {
    case .Get, .Head:
        return true
    case:
        return false
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_explicit_partial_switch :: proc(t: ^testing.T) {
    source := `(package main)

(enum Method [
  Get
  Post
])

(proc maybe-print [method: Method]
  (#partial switch method
    .Get (return)))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Method :: enum {
    Get,
    Post,
}

maybe_print :: proc(method: Method) {
    #partial switch method {
    case .Get:
        return
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_union_decl_and_constructor :: proc(t: ^testing.T) {
    source := `(package main)

// Tagged sum for testing constructors.
(union Value {
  :i int
  :s string
})

(proc wrap-int [n: int] -> Value
  (Value {:i n}))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

// Tagged sum for testing constructors.
Value :: union {
    int,
    string,
}

wrap_int :: proc(n: int) -> Value {
    return Value(n)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_operator_forms :: proc(t: ^testing.T) {
    source := `(package main)

(proc score [a: int, b: int, ok: bool] -> int
  (if (and ok (> a b))
    (+ a b)
    (if (not ok)
      (- b)
      (- b a))))

(proc has-key [lookup: map[string]int, key: string] -> bool
  (in? lookup key))

(proc contains-key [lookup: map[string]int, key: string] -> bool
  (contains? lookup key))

(proc missing-key [lookup: map[string]int, key: string] -> bool
  (not (in? lookup key)))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

score :: proc(a: int, b: int, ok: bool) -> int {
    if (ok) && ((a) > (b)) {
        return (a) + (b)
    }
    else {
        if !(ok) {
            return -(b)
        }
        else {
            return (b) - (a)
        }
    }
}

has_key :: proc(lookup: map[string]int, key: string) -> bool {
    return (key) in (lookup)
}

contains_key :: proc(lookup: map[string]int, key: string) -> bool {
    return (key) in (lookup)
}

missing_key :: proc(lookup: map[string]int, key: string) -> bool {
    return !((key) in (lookup))
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_union_type_switch :: proc(t: ^testing.T) {
    source := `(package main)

(union Value {
  :i int
  :s string
})

(proc describe [value: Value] -> string
  (switch [v value]
    int "int"
    string v
    :else "nil"))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Value :: union {
    int,
    string,
}

describe :: proc(value: Value) -> string {
    switch v in value {
    case int:
        return "int"
    case string:
        return v
    case:
        return "nil"
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_cond_with_final_else :: proc(t: ^testing.T) {
    source := `(package main)

(proc classify [n: int] -> string
  (cond
    (< n 0) "negative"
    (== n 0) "zero"
    :else "positive"))`

    output, err, ok := odinl.compile_source(source)
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
implicit_returns_only_apply_to_final_nested_blocks :: proc(t: ^testing.T) {
    source := `(package main)

(proc trace [x: int]
  (return))

(proc choose [flag: bool] -> int
  (let [x 1]
    (trace x))
  (if flag
    (trace 2)
    (trace 3))
  4)

(proc total [xs: []int] -> int
  (let [sum 0]
    (each [x xs]
      (set! sum (+ sum x))
      (trace sum))
    sum))`

    output, err, ok := odinl.compile_source(source)
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
compile_break_and_continue_forms :: proc(t: ^testing.T) {
    source := `(package main)

(proc first-positive [xs: []int] -> int
  (let [result 0]
    (each [x xs]
      (when (< x 0)
        (continue))
      (when (> x 0)
        (set! result x)
        (break)))
    result))`

    output, err, ok := odinl.compile_source(source)
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
compile_defer_forms :: proc(t: ^testing.T) {
    source := `(package main)
(import "core:fmt")

(proc main []
  (let [x 1]
    (defer (fmt.println x))
    (defer
      (fmt.println "done")
      (fmt.println x))
    (return)))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

import "core:fmt"

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
compile_flat_multi_return_destructuring :: proc(t: ^testing.T) {
    source := `(package main)

(proc query [] -> [value: int, ok: bool]
  (return 42 true))

(proc main []
  (let [[value ok] (query)
        [_, still-ok] (query)]
    (when (and ok still-ok)
      (return))))`

    output, err, ok := odinl.compile_source(source)
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
compile_proc_types_and_literals :: proc(t: ^testing.T) {
    source := `(package main)

(proc apply [f: (proc [x: int] -> int), x: int] -> int
  (f x))

(proc main []
  (let [out (apply (proc [x: int] -> int
                     (+ x 1))
                   41)]
    (return)))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

apply :: proc(f: proc(x: int) -> int, x: int) -> int {
    return f(x)
}

main :: proc() {
    out := apply(
        proc(x: int) -> int {
            return (x) + (1)
        },
        41
    )
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_core_higher_order_helpers_and_slice_exprs :: proc(t: ^testing.T) {
    source := `(package main)

(proc inc [x: int] -> int
  (+ x 1))

(proc even? [x: int] -> bool
  (== (% x 2) 0))

(proc add [acc: int, x: int] -> int
  (+ acc x))

(proc main []
  (let [xs (new []int [1 2 3 4])
        mapped (map inc xs)
        tail (slice mapped 1)
        evens (filter even? mapped)
        total (->> xs
                   (map inc)
                   (filter even?)
                   (reduce add 0))
        middle (slice mapped 0 1)]
    (defer (delete mapped))
    (defer (delete evens))
    (return)))`

    output, err, ok := odinl.compile_source(source)
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

even_p :: proc(x: int) -> bool {
    return ((x) % (2)) == (0)
}

add :: proc(acc: int, x: int) -> int {
    return (acc) + (x)
}

main :: proc() {
    xs := []int{1, 2, 3, 4}
    mapped := odinl_map(inc, (xs)[:])
    tail := (mapped)[1:]
    evens := odinl_filter(even_p, (mapped)[:])
    odinl_thread_1 := odinl_map(inc, (xs)[:])
    defer delete(odinl_thread_1)
    odinl_thread_2 := odinl_filter(even_p, (odinl_thread_1)[:])
    defer delete(odinl_thread_2)
    total := odinl_reduce(add, 0, (odinl_thread_2)[:])
    middle := (mapped)[0:1]
    defer delete(mapped)
    defer delete(evens)
    return
}

odinl_map :: proc(f: proc(x: $T) -> $U, xs: []T) -> [dynamic]U {
    out := make([dynamic]U)
    for x in xs {
        append(&out, f(x))
    }
    return out
}

odinl_filter :: proc(pred: proc(x: $T) -> bool, xs: []T) -> [dynamic]T {
    out := make([dynamic]T)
    for x in xs {
        if pred(x) {
            append(&out, x)
        }
    }
    return out
}

odinl_reduce :: proc(f: proc(acc: $U, x: $T) -> U, init: U, xs: []T) -> U {
    acc := init
    for x in xs {
        acc = f(acc, x)
    }
    return acc
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_sequence_trim_helpers_as_slice_views :: proc(t: ^testing.T) {
    source := `(package main)

(proc keep? [x: int] -> bool
  (< x 4))

(proc main []
  (let [xs (new []int [1 2 3 4])
        prefix (take 2 xs)
        suffix (drop 1 xs)
        small-prefix (take-while keep? xs)
        large-suffix (drop-while keep? xs)]
    (return)))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "prefix := odinl_take(2, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "suffix := odinl_drop(1, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "small_prefix := odinl_take_while(keep_p, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "large_suffix := odinl_drop_while(keep_p, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "odinl_take :: proc(n: int, xs: []$T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return xs[:limit]"), true)
    testing.expect_value(t, strings.contains(output, "odinl_drop :: proc(n: int, xs: []$T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return xs[start:]"), true)
    testing.expect_value(t, strings.contains(output, "odinl_take_while :: proc(pred: proc(x: $T) -> bool, xs: []T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return xs[:i]"), true)
    testing.expect_value(t, strings.contains(output, "odinl_drop_while :: proc(pred: proc(x: $T) -> bool, xs: []T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "return xs[i:]"), true)
}

@(test)
compile_threaded_let_binding_keeps_owned_intermediates_alive :: proc(t: ^testing.T) {
    source := `(package main)

(struct User {
  :name string
  :active bool
})

(proc main []
  (let [users (new []User [(User {:name "Ada" :active true})
                           (User {:name "Lin" :active false})
                           (User {:name "Grace" :active true})])
        active-names (->> users
                          (filter :active)
                          (map :name)
                          (take 1))]
    (return)))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "odinl_thread_1 := odinl_filter_field_active((users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(odinl_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "odinl_thread_2 := odinl_map_field_name(type_of(((odinl_thread_1)[:])[0].name), (odinl_thread_1)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(odinl_thread_2)"), true)
    testing.expect_value(t, strings.contains(output, "active_names := odinl_take(1, (odinl_thread_2)[:])"), true)
}

@(test)
reject_threaded_return_with_allocating_intermediate :: proc(t: ^testing.T) {
    source := `(package main)

(proc inc [x: int] -> int
  (+ x 1))

(proc even? [x: int] -> bool
  (== (% x 2) 0))

(proc bad [xs: []int] -> []int
  (->> xs
       (map inc)
       (filter even?)
       (take 1)))`

    _, err, ok := odinl.compile_source(source)
    defer delete(err.message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "threaded return has an allocating intermediate; bind the pipeline with let so OdinL can emit cleanup")
}

@(test)
reject_returning_threaded_view_of_owned_intermediate :: proc(t: ^testing.T) {
    source := `(package main)

(struct User {
  :name string
  :active bool
})

(proc bad [users: []User] -> []string
  (let [active-names (->> users
                          (filter :active)
                          (map :name)
                          (take 1))]
    active-names))`

    _, err, ok := odinl.compile_source(source)
    defer delete(err.message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "cannot return a threaded slice view that borrows from an owned intermediate; return an owned result or keep the pipeline local")
}

@(test)
compile_additional_sequence_helpers :: proc(t: ^testing.T) {
    source := `(package main)

(proc even? [x: int] -> bool
  (== (% x 2) 0))

(proc add-index [i: int, x: int] -> int
  (+ i x))

(proc keep-even [x: int] -> [value: int, ok: bool]
  (if (even? x)
    (return x true)
    (return 0 false)))

(proc pair [x: int] -> []int
  (new []int [x (+ x 10)]))

(proc neg [x: int] -> int
  (- x))

(proc main []
  (let [xs (new []int [1 2 3])
        mutable (new [dynamic]int [1 2 3])
        ys (new []int [4 5])
        without-evens (remove even? xs)
        indexed (map-indexed add-index xs)
        kept (keep keep-even xs)
        flattened (mapcat pair xs)
        joined (concat without-evens ys)
        reversed (reverse joined)
        sorted (sort joined)
        descending (sort-by neg joined)
        threaded-flat (->> xs
                           (mapcat pair)
                           (filter even?))
        threaded-sorted (->> xs
                             (sort)
                             (filter even?))
        tail-last (last joined)
        no-items? (empty? (drop 3 xs))]
    (defer (delete mutable))
    (defer (delete without-evens))
    (defer (delete indexed))
    (defer (delete kept))
    (defer (delete flattened))
    (defer (delete joined))
    (defer (delete reversed))
    (defer (delete sorted))
    (defer (delete descending))
    (defer (delete threaded-flat))
    (defer (delete threaded-sorted))
    (reverse! xs)
    (sort! xs)
    (sort-by! neg xs)
    (map! neg mutable)
    (map-indexed! add-index mutable)
    (filter! even? mutable)
    (remove! even? mutable)
    (keep! keep-even mutable)
    (into! mutable ys)
    (return)))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "without_evens := odinl_remove(even_p, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "indexed := odinl_map_indexed(add_index, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "kept := odinl_keep(keep_even, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "flattened := odinl_mapcat(pair, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "joined := odinl_concat((without_evens)[:], (ys)[:])"), true)
    testing.expect_value(t, strings.contains(output, "reversed := odinl_reverse((joined)[:])"), true)
    testing.expect_value(t, strings.contains(output, "sorted := odinl_sort((joined)[:])"), true)
    testing.expect_value(t, strings.contains(output, "descending := odinl_sort_by(neg, (joined)[:])"), true)
    testing.expect_value(t, strings.contains(output, "odinl_thread_1 := odinl_mapcat(pair, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(odinl_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "threaded_flat := odinl_filter(even_p, (odinl_thread_1)[:])"), true)
    testing.expect_value(t, strings.contains(output, "odinl_thread_2 := odinl_sort((xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(odinl_thread_2)"), true)
    testing.expect_value(t, strings.contains(output, "threaded_sorted := odinl_filter(even_p, (odinl_thread_2)[:])"), true)
    testing.expect_value(t, strings.contains(output, "odinl_reverse_in_place((xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "odinl_sort_in_place((xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "odinl_sort_by_in_place(neg, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "odinl_map_in_place(neg, (mutable)[:])"), true)
    testing.expect_value(t, strings.contains(output, "odinl_map_indexed_in_place(add_index, (mutable)[:])"), true)
    testing.expect_value(t, strings.contains(output, "odinl_filter_in_place(even_p, &(mutable))"), true)
    testing.expect_value(t, strings.contains(output, "odinl_remove_in_place(even_p, &(mutable))"), true)
    testing.expect_value(t, strings.contains(output, "odinl_keep_in_place(keep_even, &(mutable))"), true)
    testing.expect_value(t, strings.contains(output, "append(&(mutable), ..(ys)[:])"), true)
    testing.expect_value(t, strings.contains(output, "tail_last := ((joined)[:])[len((joined)[:])-1]"), true)
    testing.expect_value(t, strings.contains(output, "no_items_p := len((odinl_drop(3, (xs)[:]))[:]) == 0"), true)
    testing.expect_value(t, strings.contains(output, "odinl_remove :: proc(pred: proc(x: $T) -> bool, xs: []T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_map_indexed :: proc(f: proc(i: int, x: $T) -> $U, xs: []T) -> [dynamic]U"), true)
    testing.expect_value(t, strings.contains(output, "odinl_keep :: proc(f: proc(x: $T) -> ($U, bool), xs: []T) -> [dynamic]U"), true)
    testing.expect_value(t, strings.contains(output, "odinl_mapcat :: proc(f: proc(x: $T) -> []$U, xs: []T) -> [dynamic]U"), true)
    testing.expect_value(t, strings.contains(output, "odinl_sort :: proc(xs: []$T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_sort_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_reverse_in_place :: proc(xs: []$T)"), true)
    testing.expect_value(t, strings.contains(output, "odinl_sort_in_place :: proc(xs: []$T)"), true)
    testing.expect_value(t, strings.contains(output, "odinl_sort_by_in_place :: proc(f: proc(x: $T) -> $K, xs: []T)"), true)
    testing.expect_value(t, strings.contains(output, "odinl_map_in_place :: proc(f: proc(x: $T) -> T, xs: []T)"), true)
    testing.expect_value(t, strings.contains(output, "odinl_map_indexed_in_place :: proc(f: proc(i: int, x: $T) -> T, xs: []T)"), true)
    testing.expect_value(t, strings.contains(output, "odinl_filter_in_place :: proc(pred: proc(x: $T) -> bool, xs: ^[dynamic]T)"), true)
    testing.expect_value(t, strings.contains(output, "odinl_remove_in_place :: proc(pred: proc(x: $T) -> bool, xs: ^[dynamic]T)"), true)
    testing.expect_value(t, strings.contains(output, "odinl_keep_in_place :: proc(f: proc(x: $T) -> (T, bool), xs: ^[dynamic]T)"), true)
}

@(test)
compile_chunking_and_zipmap_sequence_helpers :: proc(t: ^testing.T) {
    source := `(package main)

(proc even? [x: int] -> bool
  (== (% x 2) 0))

(proc identity [x: int] -> int
  x)

(proc parity [x: int] -> int
  (% x 2))

(proc main []
  (let [xs (new []int [1 2 2 3 3 3])
        names (new []string ["Ada" "Lin"])
        ages (new []int [36 17])
        [front back] (split-at 2 xs)
        chunks (partition 2 xs)
        chunks-all (partition-all 3 xs)
        by-run (partition-by identity xs)
        by-name (zipmap names ages)
        by-parity (group-by parity xs)
        unique (distinct xs)
        distinct-parity (distinct-by parity xs)
        threaded (->> xs
                      (remove even?)
                      (distinct)
                      (partition-by identity))]
    (defer (delete chunks))
    (defer (delete chunks-all))
    (defer (delete by-run))
    (defer (delete by-name))
    (defer
      (each [_ group by-parity]
        (delete group))
      (delete by-parity))
    (defer (delete unique))
    (defer (delete distinct-parity))
    (defer (delete threaded))
    (return)))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "front, back := odinl_split_at(2, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "chunks := odinl_partition(2, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "chunks_all := odinl_partition_all(3, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "by_run := odinl_partition_by(identity, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "by_name := odinl_zipmap((names)[:], (ages)[:])"), true)
    testing.expect_value(t, strings.contains(output, "by_parity := odinl_group_by(parity, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "unique := odinl_distinct((xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "distinct_parity := odinl_distinct_by(parity, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "for _, group in by_parity {"), true)
    testing.expect_value(t, strings.contains(output, "delete(group)"), true)
    testing.expect_value(t, strings.contains(output, "odinl_thread_1 := odinl_remove(even_p, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(odinl_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "odinl_thread_2 := odinl_distinct((odinl_thread_1)[:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(odinl_thread_2)"), true)
    testing.expect_value(t, strings.contains(output, "threaded := odinl_partition_by(identity, (odinl_thread_2)[:])"), true)
    testing.expect_value(t, strings.contains(output, "odinl_split_at :: proc(n: int, xs: []$T) -> (left: []T, right: []T)"), true)
    testing.expect_value(t, strings.contains(output, "odinl_partition :: proc(n: int, xs: []$T) -> [dynamic][]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_partition_all :: proc(n: int, xs: []$T) -> [dynamic][]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_partition_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> [dynamic][]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_zipmap :: proc(keys: []$K, values: []$V) -> map[K]V"), true)
    testing.expect_value(t, strings.contains(output, "odinl_group_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> map[K][dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_distinct :: proc(xs: []$T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_distinct_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> [dynamic]T"), true)
}

@(test)
compile_map_constructing_sequence_helpers :: proc(t: ^testing.T) {
    source := `(package main)

(proc identity [x: int] -> int
  x)

(proc main []
  (let [xs (new []int [1 2 2 3])
        by-value (index-by identity xs)
        by-group (group-by identity xs)
        threaded (->> xs
                      (group-by identity))
        counts (frequencies xs)]
    (defer (delete by-value))
    (defer
      (each [_ group by-group]
        (delete group))
      (delete by-group))
    (defer
      (each [_ group threaded]
        (delete group))
      (delete threaded))
    (defer (delete counts))
    (return)))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "by_value := odinl_index_by(identity, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "by_group := odinl_group_by(identity, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "threaded := odinl_group_by(identity, (xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "counts := odinl_frequencies((xs)[:])"), true)
    testing.expect_value(t, strings.contains(output, "odinl_index_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> map[K]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_group_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> map[K][dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_frequencies :: proc(xs: []$T) -> map[T]int"), true)
}

@(test)
compile_bounded_sequence_producers :: proc(t: ^testing.T) {
    source := `(package main)

(proc next [] -> int
  42)

(proc double [x: int] -> int
  (* x 2))

(proc main []
  (let [xs (range 1 5)
        ys (repeat 3 "x")
        zs (repeatedly 2 next)
        powers (iterate 4 double 1)
        cycled (cycle 5 (new []int [1 2]))]
    (defer (delete xs))
    (defer (delete ys))
    (defer (delete zs))
    (defer (delete powers))
    (defer (delete cycled))
    (return)))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "xs := odinl_range(1, 5, 1)"), true)
    testing.expect_value(t, strings.contains(output, "ys := odinl_repeat(3, \"x\")"), true)
    testing.expect_value(t, strings.contains(output, "zs := odinl_repeatedly(2, next)"), true)
    testing.expect_value(t, strings.contains(output, "powers := odinl_iterate(4, double, 1)"), true)
    testing.expect_value(t, strings.contains(output, "cycled := odinl_cycle(5, []int{1, 2})"), true)
    testing.expect_value(t, strings.contains(output, "odinl_range :: proc(start, end, step: int) -> [dynamic]int"), true)
    testing.expect_value(t, strings.contains(output, "odinl_repeat :: proc(n: int, value: $T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_repeatedly :: proc(n: int, f: proc() -> $T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_iterate :: proc(n: int, f: proc(x: $T) -> T, init: T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_cycle :: proc(n: int, xs: []$T) -> [dynamic]T"), true)
}

@(test)
compile_keyword_callbacks_for_sequence_helpers :: proc(t: ^testing.T) {
    source := `(package main)

(struct User {
  :name string
  :verified bool
})

(proc main []
  (let [users (new []User [(User {:name "Ada" :verified true})
                           (User {:name "Lin" :verified false})])
        names (map :name users)
        by-name (index-by :name users)
        by-verified (group-by :verified users)
        groups (partition-by :verified users)
        distinct-names (distinct-by :name users)
        sorted (sort-by :name users)
        mutated (new [dynamic]User [(User {:name "Ada" :verified true})
                                    (User {:name "Lin" :verified false})])
        verified (filter :verified users)
        unverified (remove :verified users)
        [first ok] (find :verified users)
        any? (some? :verified users)
        all? (every? :verified verified)]
    (defer
      (each [_ group by-verified]
        (delete group))
      (delete by-verified))
    (sort-by! :name mutated)
    (filter! :verified mutated)
    (remove! :verified mutated)
    (return)))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "names := odinl_map_field_name(type_of(((users)[:])[0].name), (users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "by_name := odinl_index_by_field_name(type_of(((users)[:])[0].name), (users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "by_verified := odinl_group_by_field_verified(type_of(((users)[:])[0].verified), (users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "groups := odinl_partition_by_field_verified(type_of(((users)[:])[0].verified), (users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "distinct_names := odinl_distinct_by_field_name(type_of(((users)[:])[0].name), (users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "sorted := odinl_sort_by_field_name(type_of(((users)[:])[0].name), (users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "odinl_sort_by_in_place_field_name((mutated)[:])"), true)
    testing.expect_value(t, strings.contains(output, "odinl_filter_in_place_field_verified(&(mutated))"), true)
    testing.expect_value(t, strings.contains(output, "odinl_remove_in_place_field_verified(&(mutated))"), true)
    testing.expect_value(t, strings.contains(output, "verified := odinl_filter_field_verified((users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "unverified := odinl_remove_field_verified((users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "first, ok := odinl_find_field_verified((users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "any_p := odinl_some_p_field_verified((users)[:])"), true)
    testing.expect_value(t, strings.contains(output, "all_p := odinl_every_p_field_verified((verified)[:])"), true)
    testing.expect_value(t, strings.contains(output, "odinl_map_field_name :: proc($Field_Type: typeid, xs: []$T) -> [dynamic]Field_Type"), true)
    testing.expect_value(t, strings.contains(output, "odinl_index_by_field_name :: proc($Key: typeid, xs: []$T) -> map[Key]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_group_by_field_verified :: proc($Key: typeid, xs: []$T) -> map[Key][dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_partition_by_field_verified :: proc($Key: typeid, xs: []$T) -> [dynamic][]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_distinct_by_field_name :: proc($Key: typeid, xs: []$T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_sort_by_field_name :: proc($Key: typeid, xs: []$T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_sort_by_in_place_field_name :: proc(xs: []$T)"), true)
    testing.expect_value(t, strings.contains(output, "odinl_filter_in_place_field_verified :: proc(xs: ^[dynamic]$T)"), true)
    testing.expect_value(t, strings.contains(output, "odinl_remove_in_place_field_verified :: proc(xs: ^[dynamic]$T)"), true)
    testing.expect_value(t, strings.contains(output, "odinl_filter_field_verified :: proc(xs: []$T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_remove_field_verified :: proc(xs: []$T) -> [dynamic]T"), true)
    testing.expect_value(t, strings.contains(output, "odinl_find_field_verified :: proc(xs: []$T) -> (value: T, ok: bool)"), true)
    testing.expect_value(t, strings.contains(output, "odinl_some_p_field_verified :: proc(xs: []$T) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "odinl_every_p_field_verified :: proc(xs: []$T) -> bool"), true)
}

@(test)
compile_sequence_indexing_helpers :: proc(t: ^testing.T) {
    source := `(package main)

(proc main []
  (let [xs (new []int [10 20 30])
        a (first xs)
        b (second xs)
        c (nth xs 2)
        n (count xs)
        tail (rest xs)
        threaded (->> xs
                      (rest)
                      (count))]
    (return)))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

main :: proc() {
    xs := []int{10, 20, 30}
    a := ((xs)[:])[0]
    b := ((xs)[:])[1]
    c := ((xs)[:])[2]
    n := len((xs)[:])
    tail := ((xs)[:])[1:]
    threaded := len((((xs)[:])[1:])[:])
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
allow_returning_owned_sequence_result :: proc(t: ^testing.T) {
    source := `(package main)

(proc inc [x: int] -> int
  (+ x 1))

(proc owned [xs: []int] -> [dynamic]int
  (map inc xs))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "return odinl_map(inc, (xs)[:])"), true)
}

@(test)
reject_discarded_owned_sequence_result :: proc(t: ^testing.T) {
    source := `(package main)

(proc inc [x: int] -> int
  (+ x 1))

(proc main []
  (let [xs (new []int [1 2 3])]
    (map inc xs)
    (return)))`

    _, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "owned sequence result must be bound or returned; nested owned results would leak")
}

@(test)
reject_nested_owned_sequence_result :: proc(t: ^testing.T) {
    source := `(package main)

(proc inc [x: int] -> int
  (+ x 1))

(proc bad [xs: []int] -> int
  (first (map inc xs)))`

    _, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "owned sequence result must be bound or returned; nested owned results would leak")
}

@(test)
compile_collection_type_forms_and_make_new :: proc(t: ^testing.T) {
    source := `(package main)

(struct State {
  :values (slice int)
  :buffer (dynamic int)
  :lookup (map string int)
  :next (ptr State)
})

(proc main []
  (let [values (new (slice int) [1 2 3])
        buffer (make (dynamic int))
        lookup (make (map string int))]
    (return)))`

    output, err, ok := odinl.compile_source(source)
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
compile_array_map_literals_and_typed_let_type_forms :: proc(t: ^testing.T) {
    source := `(package main)

(struct Config {
  :ports (array 3 int)
  :lookup (map string int)
})

(proc main []
  (let [ports: (array 3 int) (new (array 3 int) [80 443 8080])
        lookup: (map string int) (new (map string int) {"http" 80 "https" 443})]
    (return)))`

    output, err, ok := odinl.compile_source(source)
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
compile_multiline_composite_literals :: proc(t: ^testing.T) {
    source := `(package main)

(struct Handler {
  :run (proc [] -> int)
})

(proc main []
  (let [handler (Handler {:run (proc [] -> int
                                  42)})
        handlers (new (slice Handler)
                   [(Handler {:run (proc [] -> int
                                      7)})])]
    (return)))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Handler :: struct {
    run: proc() -> int,
}

main :: proc() {
    handler := Handler{
        run = proc() -> int {
            return 42
        },
    }
    handlers := []Handler{
        Handler{
            run = proc() -> int {
                return 7
            },
        },
    }
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_thread_first_forms :: proc(t: ^testing.T) {
    source := `(package main)

(enum Method [
  Get
  Post
])

(struct Request {
  :method Method
  :path string
})

(proc method-name [method: Method] -> string
  (switch method
    .Get "GET"
    :else "OTHER"))

(proc describe [req: Request] -> string
  (-> req :method method-name))

(proc clone-path [req: Request, allocator: rawptr] -> string
  (-> req :path (clone-string allocator)))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Method :: enum {
    Get,
    Post,
}

Request :: struct {
    method: Method,
    path: string,
}

method_name :: proc(method: Method) -> string {
    #partial switch method {
    case .Get:
        return "GET"
    case:
        return "OTHER"
    }
}

describe :: proc(req: Request) -> string {
    return method_name(req.method)
}

clone_path :: proc(req: Request, allocator: rawptr) -> string {
    return clone_string(req.path, allocator)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_pointer_deref_and_address_of :: proc(t: ^testing.T) {
    source := `(package main)

(struct Person {
  :name string
})

(proc ptr-value [x: ^int] -> int
  (^ x))

(proc bump [x: ^int]
  (set! (^ x) (+ (^ x) 1)))

(proc borrow-name [p: ^Person] -> ^string
  (& (:name (^ p))))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

Person :: struct {
    name: string,
}

ptr_value :: proc(x: ^int) -> int {
    return (x)^
}

bump :: proc(x: ^int) {
    (x)^ = ((x)^) + (1)
}

borrow_name :: proc(p: ^Person) -> ^string {
    return &((p)^.name)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_nil_predicate :: proc(t: ^testing.T) {
    source := `(package main)

(struct User {
  :name string
})

(proc has-user [p: ^User] -> bool
  (not (nil? p)))

(proc print-user [p: ^User]
  (when (nil? p)
    (return)))`

    output, err, ok := odinl.compile_source(source)
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
    return !((p) == nil)
}

print_user :: proc(p: ^User) {
    if (p) == nil {
        return
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_lisp_predicate_and_bang_identifier_names :: proc(t: ^testing.T) {
    source := `(package main)

(proc greater-than? [threshold: int, x: int] -> bool
  (> x threshold))

(proc bump! [x: ^int]
  (set! (^ x) (+ (^ x) 1)))

(proc main []
  (let [x 1]
    (greater-than? 0 x)))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

greater_than_p :: proc(threshold: int, x: int) -> bool {
    return (x) > (threshold)
}

bump_bang :: proc(x: ^int) {
    (x)^ = ((x)^) + (1)
}

main :: proc() {
    x := 1
    greater_than_p(0, x)
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_odin_shaped_type_spellings :: proc(t: ^testing.T) {
    source := `(package main)

(struct Raw-Types {
  :values []int
  :fixed [3]int
  :buffer [dynamic]int
  :lookup map[string]int
  :next ^Raw-Types
})

(proc values [state: ^Raw-Types] -> []int
  (:values (^ state)))

(proc main []
  (let [values (new []int [1 2 3])
        lookup (new map[string]int {"one" 1})
        buffer-literal (new [dynamic]int [1 2])
        buffer (make [dynamic]int)]
    (return)))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `#+feature dynamic-literals
package main

Raw_Types :: struct {
    values: []int,
    fixed: [3]int,
    buffer: [dynamic]int,
    lookup: map[string]int,
    next: ^Raw_Types,
}

values :: proc(state: ^Raw_Types) -> []int {
    return (state)^.values
}

main :: proc() {
    values := []int{1, 2, 3}
    lookup := map[string]int{"one" = 1}
    buffer_literal := [dynamic]int{1, 2}
    buffer := make([dynamic]int)
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_compact_type_spellings_inside_vectors :: proc(t: ^testing.T) {
    source := `(package main)

(proc first [xs: []int, lookup: map[string]int] -> int
  (let [buffer: [dynamic]int (make [dynamic]int)
        fixed: [3]int (new [3]int [1 2 3])]
    (get xs 0)))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

first :: proc(xs: []int, lookup: map[string]int) -> int {
    buffer: [dynamic]int = make([dynamic]int)
    fixed: [3]int = [3]int{1, 2, 3}
    return xs[0]
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_map_literals_with_non_string_keys :: proc(t: ^testing.T) {
    source := `(package main)

(proc main []
  (let [by-code (new map[int]string {1 "one" 2 "two"})
        by-flag (new map[bool]int {true 1 false 0})]
    (return)))`

    output, err, ok := odinl.compile_source(source)
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
compile_unparenthesized_proc_type_spelling :: proc(t: ^testing.T) {
    source := `(package main)

(const default-pred proc [x: int] -> bool
  (proc [x: int] -> bool
    true))

(struct Runner {
  :run proc [x: int] -> bool
})

(union Callback {
  :pred proc [x: int] -> bool
})

(proc apply-pred [pred: proc [x: int] -> bool, x: int] -> bool
  (pred x))

(proc always [] -> proc [x: int] -> bool
  (proc [x: int] -> bool
    true))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

default_pred: proc(x: int) -> bool : proc(x: int) -> bool {
    return true
}

Runner :: struct {
    run: proc(x: int) -> bool,
}

Callback :: union {
    proc(x: int) -> bool,
}

apply_pred :: proc(pred: proc(x: int) -> bool, x: int) -> bool {
    return pred(x)
}

always :: proc() -> proc(x: int) -> bool {
    return proc(x: int) -> bool {
        return true
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_typed_let_with_proc_type_spelling :: proc(t: ^testing.T) {
    source := `(package main)

(proc main []
  (let [pred: proc [x: int] -> bool (proc [x: int] -> bool
                                        true)]
    (pred 1)
    (return)))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

main :: proc() {
    pred: proc(x: int) -> bool = proc(x: int) -> bool {
        return true
    }
    pred(1)
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_proc_directives_and_declaration_attributes :: proc(t: ^testing.T) {
    source := `(package main)

(odin "@(private)")
(odin "#force_inline")
(proc hidden [] -> int
  1)

(proc query [] -> [value: int, ok: bool] #optional_ok
  (return 42 true))`

    output, err, ok := odinl.compile_source(source)
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
compile_directive_expression_wrappers :: proc(t: ^testing.T) {
    source := `(package main)

(proc inc [x: int] -> int
  (+ x 1))

(proc main []
  (let [x (#force_inline inc 41)
        y (#force_inline (inc x))]
    (return)))`

    output, err, ok := odinl.compile_source(source)
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
reject_proc_directive_before_non_proc_declaration :: proc(t: ^testing.T) {
    source := `(package main)

(odin "#force_inline")
(const answer 42)`

    _, err, ok := odinl.compile_source(source)
    defer delete(err.message)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, err.message, "procedure directive must be followed by a proc declaration")
}

@(test)
compile_parenthesized_nested_proc_type_spelling :: proc(t: ^testing.T) {
    source := `(package main)

(proc identity-factory [f: (proc [x: int] -> proc [y: int] -> bool)] -> (proc [x: int] -> proc [y: int] -> bool)
  f)`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

identity_factory :: proc(f: proc(x: int) -> proc(y: int) -> bool) -> proc(x: int) -> proc(y: int) -> bool {
    return f
}
`
    testing.expect_value(t, output, expected)
}

@(test)
format_compile_errors_with_line_column_and_context :: proc(t: ^testing.T) {
    source := `(package main)
(unknown thing)`

    _, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    formatted := odinl.format_compile_error("bad.odinl", source, err)
    defer delete(formatted)

    expected := `bad.odinl:2:2: unsupported top-level form: unknown
  (unknown thing)
   ^
`
    testing.expect_value(t, formatted, expected)
}

@(test)
lower_rejects_missing_package :: proc(t: ^testing.T) {
    source := `(proc main []
  (return))`

    _, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    formatted := odinl.format_compile_error("bad.odinl", source, err)
    defer delete(formatted)
    expected := `bad.odinl:1:1: missing package declaration
  (proc main []
  ^
`
    testing.expect_value(t, formatted, expected)
}

@(test)
lower_rejects_duplicate_package :: proc(t: ^testing.T) {
    source := `(package main)
(package other)
(proc main []
  (return))`

    _, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    formatted := odinl.format_compile_error("bad.odinl", source, err)
    defer delete(formatted)
    expected := `bad.odinl:2:1: package declaration must appear exactly once
  (package other)
  ^
`
    testing.expect_value(t, formatted, expected)
}

@(test)
lower_rejects_import_after_declarations :: proc(t: ^testing.T) {
    source := `(package main)
(const answer 42)
(import "core:fmt")`

    _, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    formatted := odinl.format_compile_error("bad.odinl", source, err)
    defer delete(formatted)
    expected := `bad.odinl:3:1: import declarations must appear before other declarations
  (import "core:fmt")
  ^
`
    testing.expect_value(t, formatted, expected)
}

@(test)
compile_top_level_odin_escape :: proc(t: ^testing.T) {
    source := `(package main)

// Foreign handle alias.
(odin "Foreign_Handle :: distinct rawptr")
(odin "foreign import sqlite \"system:sqlite3\"")

(proc main []
  (odin "context.user_ptr = nil")
  (return))`

    output, err, ok := odinl.compile_source(source)
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

main :: proc() {
    context.user_ptr = nil
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_multiline_statement_odin_escape :: proc(t: ^testing.T) {
    source := `(package main)

(proc main []
  (odin "x := 1\n_ = x")
  (return))`

    output, err, ok := odinl.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

main :: proc() {
    x := 1
    _ = x
    return
}
`
    testing.expect_value(t, output, expected)
}
