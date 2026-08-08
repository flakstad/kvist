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
macroexpand_evaluates_and_or_in_macro_predicates :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro emit-flag []
  (if (and (symbol? (quote if))
           (or (= (name (quote if)) "when")
               (= (name (quote if)) "if")))
    (quote (def matched true))
    (quote (def missed true))))

(emit-flag)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "matched :: true"), true)
    testing.expect_value(t, strings.contains(output, "missed"), false)
}

@(test)
macroexpand_evaluates_cond_in_macro_predicates :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro emit-kind [head]
  (let [kind (cond
               (= (name head) "if") "branch"
               (= (name head) "when") "branch"
               :else "other")]
    (cond
      (= kind "branch") (quote (def branch-kind true))
      (= kind "other") (quote (def other-kind true))
      (= kind "unknown") (quote (def other-kind true))
      :else (quote (def missed-kind true)))))

(emit-kind if)
(emit-kind let)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "branch_kind :: true"), true)
    testing.expect_value(t, strings.contains(output, "other_kind :: true"), true)
    testing.expect_value(t, strings.contains(output, "missed_kind"), false)
}

@(test)
macroexpand_user_macros_can_define_case_like_dispatch_with_cond :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro emit-kind []
  (let [kind "other"]
    (cond
      (= kind "known") (quote (def known-match true))
      (= kind "other") (quote (def other-match true))
      :else (quote (def default-match true)))))

(emit-kind)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "other_match :: true"), true)
    testing.expect_value(t, strings.contains(output, "default_match"), false)
}

@(test)
macroexpand_user_macros_can_define_literal_classifiers :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro literal-int? [form #form]
  (and (number? form)
       (not (contains? (source form) "."))
       (not (contains? (source form) "e"))
       (not (contains? (source form) "E"))))

(defmacro literal-float? [form #form]
  (and (number? form)
       (not (literal-int? form))))

(defmacro literal-bool? [form #form]
  (let [text (source form)]
    (or (= text "true")
        (= text "false"))))

(defmacro emit-classifiers []
  (if (and (literal-int? 12)
           (literal-float? 1.5)
           (literal-float? 1e2)
           (literal-bool? true)
           (literal-bool? false)
           (not (literal-int? 1.5))
           (not (literal-bool? maybe)))
    (quote (def literal-classifiers-ok true))
    (quote (def literal-classifiers-bad true))))

(emit-classifiers)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "literal_classifiers_ok :: true"), true)
    testing.expect_value(t, strings.contains(output, "literal_classifiers_bad"), false)
}

@(test)
macroexpand_user_macros_can_define_field_selector_predicate :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro field-selector-form? [form]
  (and (symbol? form)
       (> (count (source form)) 1)
       (= (slice (source form) 0 1) ".")))

(defmacro emit-field-selector-check [field plain keyword]
  (let [items (quote (user.name .title))]
    (if (and (field-selector-form? field)
           (field-selector-form? (nth items 1))
           (not (field-selector-form? plain))
           (not (field-selector-form? keyword)))
      (quote (def field-selector-ok true))
      (quote (def field-selector-bad true)))))

(emit-field-selector-check .name name :name)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "field_selector_ok :: true"), true)
    testing.expect_value(t, strings.contains(output, "field_selector_bad"), false)
}

@(test)
macroexpand_evaluates_guard_style_cond_with_not :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro aggregate-find? [form]
  (cond
    (not (list? form)) false
    (not (or (= (count form) 2)
                         (= (count form) 3))) false
    (not (symbol? (first form))) false
    :else true))

(defmacro emit-aggregate [form]
  (if (aggregate-find? form)
    (forms (quote (def aggregate-ok true)))
    (forms)))

(emit-aggregate (count ?x))
(emit-aggregate 42)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "aggregate_ok :: true"), true)
}

@(test)
macroexpand_evaluates_contains_in_macro_predicates :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro emit-aggregate-op [op]
  (if (contains? ["count" "count-distinct" "min" "max" "sum" "avg"] (name op))
    (forms (quote (def aggregate-op true)))
    (forms)))

(emit-aggregate-op sum)
(emit-aggregate-op median)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "aggregate_op :: true"), true)
    testing.expect_value(t, strings.contains(output, "median"), false)
}

@(test)
macroexpand_evaluates_numeric_comparisons_in_macro_predicates :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro emit-small-form [form]
  (cond
    (<= (count form) 1) (quote (def one-or-less true))
    (< (count form) 4) (quote (def small-form true))
    :else (quote (def large-form true))))

(emit-small-form (a b))
(emit-small-form (a b c d))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "small_form :: true"), true)
    testing.expect_value(t, strings.contains(output, "large_form :: true"), true)
    testing.expect_value(t, strings.contains(output, "one_or_less"), false)
}

@(test)
macroexpand_evaluates_string_helpers_in_macro_predicates :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro source-starts-with? [text prefix]
  (if (> (count prefix) (count text))
    false
    (= (slice text 0 (count prefix)) prefix)))

(defmacro source-ends-with? [text suffix]
  (let [text-len (count text)
        suffix-len (count suffix)]
    (if (> suffix-len text-len)
      false
      (= (slice text (- text-len suffix-len)) suffix))))

(defmacro reverse-attr? [form]
  (and (keyword? form)
             (source-starts-with? (source form) ":_")
             (source-ends-with? (slice (source form) 1) "friend")
             (= (count (source form)) 13)))

(defmacro emit-reverse [form]
  (if (and (reverse-attr? form)
                 (contains? (source form) "user"))
    (quote (def reverse-attr true))
    (quote (def normal-attr true))))

(emit-reverse :_user/friend)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "reverse_attr :: true"), true)
    testing.expect_value(t, strings.contains(output, "normal_attr"), false)
}

@(test)
macroexpand_user_macros_can_define_decimal_parser :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro digit-value [s]
  (cond
    (= s "0") 0
    (= s "1") 1
    (= s "2") 2
    (= s "3") 3
    (= s "4") 4
    (= s "5") 5
    (= s "6") 6
    (= s "7") 7
    (= s "8") 8
    (= s "9") 9
    :else nil))

(defmacro times-ten [n]
  (+ n n n n n n n n n n))

(defmacro parse-decimal-loop [text index acc]
  (if (= index (count text))
    acc
    (let [digit (digit-value (slice text index (+ index 1)))]
      (if digit
        (parse-decimal-loop text (+ index 1) (+ (times-ten acc) digit))
        nil))))

(defmacro parse-decimal [text]
  (if (= (count text) 0)
    nil
    (parse-decimal-loop text 0 0)))

(defmacro emit-parsed [form]
  (let [n (parse-decimal (source form))]
    (if n
      (quasiquote (def parsed (unquote n)))
      (quote (def parsed-failed true)))))

(defmacro emit-zero [form]
  (let [n (parse-decimal (source form))]
    (if n
      (quasiquote (def parsed-zero (unquote n)))
      (quote (def parsed-zero-failed true)))))

(defmacro emit-invalid [form]
  (if (parse-decimal (source form))
    (quote (def invalid-parsed true))
    (quote (def invalid-rejected true))))

(defmacro decimal-digit? [form]
  (let [s (source form)]
    (and (= (count s) 1)
               (contains? "0123456789" s))))

(defmacro source-every? [predicate #form values]
  (if (= (count values) 0)
    true
    (if (predicate (first values))
      (source-every? predicate (rest values))
      false)))

(defmacro emit-digits [form]
  (if (and (decimal-digit? form)
                 (source-every? decimal-digit? [1 2 3]))
    (quote (def digits-ok true))
    (quote (def digits-bad true))))

(emit-parsed 42)
(emit-zero 0)
(emit-invalid nope)
(emit-digits 7)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "parsed :: 42"), true)
    testing.expect_value(t, strings.contains(output, "parsed_zero :: 0"), true)
    testing.expect_value(t, strings.contains(output, "invalid_rejected :: true"), true)
    testing.expect_value(t, strings.contains(output, "digits_ok :: true"), true)
    testing.expect_value(t, strings.contains(output, "parsed_failed"), false)
    testing.expect_value(t, strings.contains(output, "parsed_zero_failed"), false)
    testing.expect_value(t, strings.contains(output, "invalid_parsed"), false)
    testing.expect_value(t, strings.contains(output, "digits_bad"), false)
}

@(test)
macroexpand_user_macros_can_define_form_substitution :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro- subst-symbol [form names values]
  (if (= (count names) 0)
    form
    (if (= (source form) (source (first names)))
      (first values)
      (subst-symbol form (rest names) (rest values)))))

(defmacro- subst-items [items names values]
  (if (= (count items) 0)
    (forms)
    (concat
      (forms (subst-form (first items) names values))
      (subst-items (rest items) names values))))

(defmacro- subst-form [form names values]
  (if (= (count names) (count values))
    (if (symbol? form)
      (subst-symbol form names values)
      (if (list? form)
        (list (subst-items form names values))
        (if (vector? form)
          (vector (subst-items form names values))
          (if (brace? form)
            (brace (subst-items form names values))
            form))))
    (error "subst-form expects the same number of names and values")))

(defmacro emit-answer []
  (subst-form '(defn answer [] -> int (+ x 1))
              (vector 'x)
              (vector 41)))

(emit-answer)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "answer :: proc() -> int"), true)
    testing.expect_value(t, strings.contains(output, "return (41) + (1)"), true)
}

@(test)
macroexpand_user_macros_can_define_nil_predicate :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro local-nil? [form]
  (if (= form nil)
    true
    (if (form? form)
      (= (text form) "nil")
      false)))

(defmacro emit-nil-flag [form]
  (if (local-nil? form)
    (quote (def saw-nil true))
    (quote (def saw-value true))))

(emit-nil-flag nil)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "saw_nil :: true"), true)
    testing.expect_value(t, strings.contains(output, "saw_value"), false)
}

@(test)
macroexpand_evaluates_sequence_helpers :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro query-var? [form]
  (let [text (source form)]
    (and (symbol? form)
               (> (count text) 0)
               (= (slice text 0 1) "?"))))

(defmacro literal-nil? [form]
  (= form nil))

(defmacro emit-vars [vars]
  (if (every? query-var? vars)
    (let [names (map source vars)
          kept (filter query-var? vars)
          nils (filter literal-nil? [1 nil 2])]
      (if (and (some? string? names)
                     (= (count kept) 2)
                     (= (count nils) 1))
        (quote (def vars-ok true))
        (quote (def vars-bad true))))
    (quote (def vars-bad true))))

(emit-vars [?x ?y])`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "vars_ok :: true"), true)
    testing.expect_value(t, strings.contains(output, "vars_bad"), false)
}

@(test)
macroexpand_user_macros_can_define_recursive_fold :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro digit-value [s]
  (cond
    (= s "0") 0
    (= s "1") 1
    (= s "2") 2
    (= s "3") 3
    (= s "4") 4
    (= s "5") 5
    (= s "6") 6
    (= s "7") 7
    (= s "8") 8
    (= s "9") 9
    :else nil))

(defmacro times-ten [n]
  (+ n n n n n n n n n n))

(defmacro parse-decimal-loop [text index acc]
  (if (= index (count text))
    acc
    (let [digit (digit-value (slice text index (+ index 1)))]
      (if digit
        (parse-decimal-loop text (+ index 1) (+ (times-ten acc) digit))
        nil))))

(defmacro parse-decimal [text]
  (if (= (count text) 0)
    nil
    (parse-decimal-loop text 0 0)))

(defmacro add-source-int [acc form]
  (let [n (parse-decimal (source form))]
    (if n
      (+ acc n)
      (error (str "expected integer literal: " (source form))))))

(defmacro sum-source-ints [forms acc]
  (if (= (count forms) 0)
    acc
    (sum-source-ints (rest forms)
                     (add-source-int acc (first forms)))))

(defmacro emit-sum [forms]
  (let [total (sum-source-ints forms 0)]
    (quasiquote
      (def folded-total (unquote total)))))

(emit-sum [10 20 12])`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "folded_total :: 42"), true)
}

@(test)
macroexpand_user_macro_in_file_context :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro unless [condition & body]
  (quasiquote
    (if (unquote condition)
      (do)
      (do (splice body)))))

(defn answer [] -> int
  42)`

    output, err, ok := kvist.macroexpand_eval_source_with_map(source, `(unless (> n 0)
  (return 0))`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output.output)
    defer kvist.source_map_slice_delete(output.source_map)
    defer kvist.compile_warning_slice_delete(output.warnings)

    expected := `(if (> n 0) (do) (do (return 0)))
`
    testing.expect_value(t, output.output, expected)
}

@(test)
compile_path_macro_read_file_uses_source_relative_file_at_compile_time :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-macro-read-file-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    template_path, template_join_err := os.join_path({dir, "template.html"}, context.allocator)
    testing.expect_value(t, template_join_err == nil, true)
    if template_join_err != nil {
        return
    }
    defer delete(template_path)

    template_write_err := os.write_entire_file_from_string(template_path, "<h1>Compile-time</h1>\n")
    testing.expect_value(t, template_write_err == nil, true)
    if template_write_err != nil {
        return
    }

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)

    source := `(package main)

(defmacro def-template []
  (let [text (read-file "template.html")]
    (quasiquote
      (def template: string (unquote text)))))

(def-template)

(defn main [] -> string
  template)`

    source_write_err := os.write_entire_file_from_string(main_path, source)
    testing.expect_value(t, source_write_err == nil, true)
    if source_write_err != nil {
        return
    }

    output, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `template: string : "<h1>Compile-time</h1>\n"`), true)
    testing.expect_value(t, strings.contains(output, `return template`), true)
}

@(test)
compile_path_macro_read_file_reports_missing_compile_time_file :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-macro-read-file-missing-*", context.allocator)
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

    source := `(package main)

(defmacro def-template []
  (let [text (read-file "missing.html")]
    (quasiquote
      (def template: string (unquote text)))))

(def-template)`

    source_write_err := os.write_entire_file_from_string(main_path, source)
    testing.expect_value(t, source_write_err == nil, true)
    if source_write_err != nil {
        return
    }

    _, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer kvist.compile_error_delete(&err)
    testing.expect_value(t, strings.contains(err.message, "compile-time read-file could not read file:"), true)
    testing.expect_value(t, strings.contains(err.message, "missing.html"), true)
}

@(test)
macro_kvist_read_file_alias_is_not_macro_helper :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro def-template []
  (let [text (kvist.read-file "template.html")]
    (quasiquote
      (def template: string (unquote text)))))

(def-template)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "template.html"), true)
    testing.expect_value(t, strings.contains(output, "Compile-time"), false)
}
