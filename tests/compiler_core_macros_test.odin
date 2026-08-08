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
compile_when_let_macro :: proc(t: ^testing.T) {
    source := `(package main)

(defn query [] -> [value: int, found: bool]
  (return 42 true))

(defn main []
  (when-let [[value found] (query)]
    (when (> value 40)
      (return))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

query :: proc() -> (value: int, found: bool) {
    return 42, true
}

main :: proc() {
    value, found := query()
    if found {
        if (value) > (40) {
            return
        }
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_if_let_macro :: proc(t: ^testing.T) {
    source := `(package main)

(defn query [] -> [value: int, found: bool]
  (return 42 true))

(defn main [] -> int
  (if-let [[value found] (query)]
    value
    0))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `package main

query :: proc() -> (value: int, found: bool) {
    return 42, true
}

main :: proc() -> int {
    value, found := query()
    if found {
        return value
    }
    else {
        return 0
    }
}
`
    testing.expect_value(t, output, expected)
}

@(test)
compile_chained_if_let_macro :: proc(t: ^testing.T) {
    source := `(package main)

(defn query [n: int] -> [value: int, found: bool]
  (if (> n 0)
    (return n true)
    (return 0 false)))

(defn main [] -> int
  (if-let [[a ok] (query 1)
           [b ok] (query a)]
    (+ a b)
    0))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "a, ok := query(1)"), true)
    testing.expect_value(t, strings.contains(output, "if ok {\n        b, ok := query(a)"), true)
    testing.expect_value(t, strings.contains(output, "return (a) + (b)"), true)
    testing.expect_value(t, strings.contains(output, "return 0"), true)
}

@(test)
compile_if_ok_macro :: proc(t: ^testing.T) {
    source := `(package main)
(import os "core:os")

(defn read-count [] -> [value: int, err: os.Error]
  (return 42 nil))

(defn main [] -> int
  (if-ok [[value err] (read-count)]
    value
    0))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "value, err := read_count()"), true)
    testing.expect_value(t, strings.contains(output, "if (err) == (os.Error{})"), true)
    testing.expect_value(t, strings.contains(output, "return value"), true)
    testing.expect_value(t, strings.contains(output, "return 0"), true)
}

@(test)
compile_chained_if_ok_macro :: proc(t: ^testing.T) {
    source := `(package main)
(import os "core:os")

(defn read-count [n: int] -> [value: int, err: os.Error]
  (return n nil))

(defn main [] -> int
  (if-ok [[a err] (read-count 1)
          [b err] (read-count a)]
    (+ a b)
    0))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "a, err := read_count(1)"), true)
    testing.expect_value(t, strings.contains(output, "if (err) == (os.Error{}) {\n        b, err := read_count(a)"), true)
    testing.expect_value(t, strings.contains(output, "return (a) + (b)"), true)
    testing.expect_value(t, strings.contains(output, "return 0"), true)
}

@(test)
compile_when_ok_macro :: proc(t: ^testing.T) {
    source := `(package main)
(import os "core:os")

(defn read-count [] -> [value: int, err: os.Error]
  (return 42 nil))

(defn main [] -> int
  (let [total 0]
    (when-ok [[value err] (read-count)]
      (set! total value))
    total))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "value, err := read_count()"), true)
    testing.expect_value(t, strings.contains(output, "if (err) == (os.Error{})"), true)
    testing.expect_value(t, strings.contains(output, "total = value"), true)
    testing.expect_value(t, strings.contains(output, "return total"), true)
}

@(test)
macroexpand_when_let :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(when-let [[value found] (query)]
  (fmt.println value))`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(let [[value found] (query)] (if found (fmt.println value)))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_if_let :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(if-let [[value found] (query)]
  value
  0)`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(let [[value found] (query)] (if found value 0))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_chained_if_let :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(if-let [[a ok] (query 1)
         [b ok] (query a)]
  (+ a b)
  0)`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(let [[a ok] (query 1)] (if ok (let [[b ok] (query a)] (if ok (+ a b) 0)) 0))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_when_ok :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(when-ok [[data err] (read-text path)]
  (use data))`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(let [[data err] (read-text path)] (if (= err {}) (use data)))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_if_ok :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(if-ok [[data err] (read-text path)]
  (count data)
  0)`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(let [[data err] (read-text path)] (if (= err {}) (odin-call "len" data) 0))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_chained_if_ok :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(if-ok [[data err] (read-text path)
        [cfg err] (parse data)]
  (use cfg)
  0)`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(let [[data err] (read-text path)] (if (= err {}) (let [[cfg err] (parse data)] (if (= err {}) (use cfg) 0)) 0))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_thread_first :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(-> req .method method-name)`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(method-name (odin-get req .method))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_thread_last :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(->> xs (arr.filter even?) (arr.map inc) (count))`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(odin-call "len" (arr.map inc (arr.filter even? xs)))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_doto_threads_target_through_setup_calls :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(doto req (set-header! "x-api-key" key) (enable-retry!))`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "(let [kvist_doto_"), true)
    testing.expect_value(t, strings.contains(output, "(set-header! kvist_doto_"), true)
    testing.expect_value(t, strings.contains(output, "(enable-retry! kvist_doto_"), true)
}

@(test)
compile_relative_core_directory_does_not_shadow_installed_core_macros :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-core-relative-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    core_dir, core_join_err := os.join_path({dir, "packages", "core"}, context.allocator)
    testing.expect_value(t, core_join_err == nil, true)
    if core_join_err != nil {
        return
    }
    defer delete(core_dir)

    mk_core_err := os.make_directory_all(core_dir)
    testing.expect_value(t, mk_core_err == nil, true)
    if mk_core_err != nil {
        return
    }

    core_path, core_path_err := os.join_path({core_dir, "core.kvist"}, context.allocator)
    testing.expect_value(t, core_path_err == nil, true)
    if core_path_err != nil {
        return
    }
    defer delete(core_path)
    core_write_err := os.write_entire_file_from_string(core_path, `(package core)

(defmacro when [test & body]
  (quasiquote 123))`)
    testing.expect_value(t, core_write_err == nil, true)
    if core_write_err != nil {
        return
    }

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)
    main_write_err := os.write_entire_file_from_string(main_path, `(package main)

(defn main [] -> int
  (when true 7))`)
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

    testing.expect_value(t, strings.contains(output, "return 123"), false)
    testing.expect_value(t, strings.contains(output, "return 7"), true)
}
