package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

@(test)
compile_multiline_string_literal :: proc(t: ^testing.T) {
    source := `(package main)

(def Query: string "[:find ?name
 :in [?email ...]
 :where [?e :user/email ?email]
        [?e :user/name \"Ada\"]]")

(defn query [] -> string
  Query)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `Query: string : "[:find ?name\n :in [?email ...]\n :where [?e :user/email ?email]\n        [?e :user/name \"Ada\"]]"`), true)
    testing.expect_value(t, strings.contains(output, "Query: string : \"[:find ?name\n"), false)
}

@(test)
reader_supports_hash_underscore_and_comment_form :: proc(t: ^testing.T) {
    source := `(package main)
#_(defstruct Ignored [
  field: string
])
(comment
  (defn old []
    (fmt.println "old")))
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

main :: proc() {
    return
}
`
    testing.expect_value(t, output, expected)
}

@(test)
reader_reports_expected_missing_closing_delimiter :: proc(t: ^testing.T) {
    _, err, ok := kvist.compile_source(`(package main)

(defn demo []
  (println "unterminated"`)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "missing closing delimiter `)` for `(` opened here")
}

@(test)
reader_reports_actual_unexpected_closing_delimiter :: proc(t: ^testing.T) {
    _, err, ok := kvist.compile_source(`(package main)

(defn demo []
  (println "extra")) )`)
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, err.message, "unexpected closing delimiter `)`")
}

@(test)
reader_preserves_top_form_source_text :: proc(t: ^testing.T) {
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    source := `;; Doc.
(package main)

(def answer 42)`

    forms, err, ok := kvist.read_top_forms(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }

    testing.expect_value(t, len(forms), 2)
    testing.expect_value(t, forms[0].source, "(package main)")
    testing.expect_value(t, len(forms[0].doc_lines), 1)
    testing.expect_value(t, forms[0].doc_lines[0], "// Doc.")
    testing.expect_value(t, forms[1].source, "(def answer 42)")
}

@(test)
reader_expands_quote_syntax_to_core_forms :: proc(t: ^testing.T) {
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    source := "'answer\n`(def ~name ~@body)"

    forms, err, ok := kvist.read_top_forms(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }

    testing.expect_value(t, len(forms), 2)
    testing.expect_value(t, forms[0].form.kind, kvist.CST_Form_Kind.List)
    testing.expect_value(t, len(forms[0].form.items), 2)
    testing.expect_value(t, forms[0].form.items[0].text, "quote")
    testing.expect_value(t, forms[0].form.items[1].text, "answer")
    testing.expect_value(t, forms[0].source, "'answer")

    qq := forms[1].form
    testing.expect_value(t, qq.kind, kvist.CST_Form_Kind.List)
    testing.expect_value(t, len(qq.items), 2)
    testing.expect_value(t, qq.items[0].text, "quasiquote")
    template := qq.items[1]
    testing.expect_value(t, template.kind, kvist.CST_Form_Kind.List)
    testing.expect_value(t, template.items[0].text, "def")
    testing.expect_value(t, template.items[1].items[0].text, "unquote")
    testing.expect_value(t, template.items[1].items[1].text, "name")
    testing.expect_value(t, template.items[2].items[0].text, "splice")
    testing.expect_value(t, template.items[2].items[1].text, "body")
    testing.expect_value(t, forms[1].source, "`(def ~name ~@body)")
}

@(test)
reader_converts_semicolon_doc_comments :: proc(t: ^testing.T) {
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    source := `; Lisp doc.
(def answer 42)`

    forms, err, ok := kvist.read_top_forms(source)
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

    source := `(def answer 42)
(def negative -1)
(def ok true)
(def none nil)`

    forms, err, ok := kvist.read_top_forms(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }

    testing.expect_value(t, forms[0].form.items[2].kind, kvist.CST_Form_Kind.Number)
    testing.expect_value(t, forms[1].form.items[2].kind, kvist.CST_Form_Kind.Number)
    testing.expect_value(t, forms[2].form.items[2].kind, kvist.CST_Form_Kind.Bool)
    testing.expect_value(t, forms[3].form.items[2].kind, kvist.CST_Form_Kind.Nil)
}

@(test)
reader_classifies_inline_collection_literals :: proc(t: ^testing.T) {
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    source := `(def xs [1 2 3])
(def lookup {:one "1" :two "2"})
(def tags #{:math :lisp})`

    forms, err, ok := kvist.read_top_forms(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }

    testing.expect_value(t, forms[0].form.items[2].kind, kvist.CST_Form_Kind.Vector)
    testing.expect_value(t, forms[1].form.items[2].kind, kvist.CST_Form_Kind.Brace)
    testing.expect_value(t, forms[2].form.items[2].kind, kvist.CST_Form_Kind.Set)
}

@(test)
reader_classifies_inline_regex_literals :: proc(t: ^testing.T) {
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    source := `(def digits #"\d+")
(def quoted #"a\"b")`

    forms, err, ok := kvist.read_top_forms(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }

    testing.expect_value(t, forms[0].form.items[2].kind, kvist.CST_Form_Kind.Regex)
    testing.expect_value(t, forms[0].form.items[2].text, `#"\d+"`)
    digits := kvist.unquote_regex_literal(forms[0].form.items[2].text)
    defer delete(digits)
    testing.expect_value(t, digits, `\d+`)

    testing.expect_value(t, forms[1].form.items[2].kind, kvist.CST_Form_Kind.Regex)
    quoted := kvist.unquote_regex_literal(forms[1].form.items[2].text)
    defer delete(quoted)
    testing.expect_value(t, quoted, `a"b`)
}

@(test)
compile_inline_regex_literal_emits_pattern_string :: proc(t: ^testing.T) {
    source := `(package main)

(defn pattern [] -> string
  #"\d+")`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `return "\\d+"`), true)
}

@(test)
macroexpand_accepts_quote_reader_syntax :: proc(t: ^testing.T) {
    source := "(package main)\n\n" +
              "(defmacro my-when [condition & body]\n" +
              "  `(if ~condition\n" +
              "     (do ~@body)))\n\n" +
              "(defn demo [ok?: bool] -> int\n" +
              "  (my-when ok?\n" +
              "    (return 42))\n" +
              "  0)\n\n" +
              "(defmacro emit-answer []\n" +
              "  '(def Answer 7))\n\n" +
              "(emit-answer)"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "if ok_p {"), true)
    testing.expect_value(t, strings.contains(output, "return 42"), true)
    testing.expect_value(t, strings.contains(output, "Answer :: 7"), true)
}
