package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

@(test)
compile_typed_def_bindings_preserve_type_forms_during_macroexpand :: proc(t: ^testing.T) {
    source := `(package main)

(def xs: (slice i32) ([]i32 [1 2]))
(defvar ys: (slice i32) ([]i32 [3 4]))

(defn score [] -> int
  (+ (count xs) (count ys)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "xs: []i32 : []i32{1, 2}"), true)
    testing.expect_value(t, strings.contains(output, "ys: []i32 = []i32{3, 4}"), true)
}

@(test)
reject_macro_expanded_slash_package_access :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn inc [x: int] -> int
  (+ x 1))

(defmacro bad-map [f xs]
  (let [head (symbol "arr/map")]
    (quasiquote
      ((unquote head) (unquote f) (unquote xs)))))

(defn bad [] -> [dynamic]int
  (bad-map inc ([]int [1 2 3])))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "use `arr.map` for package access")
}

@(test)
reject_macro_expanded_slash_package_access_for_custom_alias :: proc(t: ^testing.T) {
    source := `(package main)
(import things "kvist:arr")

(defn inc [x: int] -> int
  (+ x 1))

(defmacro bad-map [f xs]
  (let [head (symbol "things/map")]
    (quasiquote
      ((unquote head) (unquote f) (unquote xs)))))

(defn bad [] -> [dynamic]int
  (bad-map inc ([]int [1 2 3])))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "use `things.map` for package access")
}

@(test)
reject_eval_macro_expanded_slash_package_access :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(def xs: []int ([]int [1 2 3]))

(defmacro bad-count [xs]
  (let [head (symbol "arr/count")]
    (quasiquote
      ((unquote head) (unquote xs)))))`

    _, err, ok := kvist.compile_eval_source_with_map(source, `(bad-count xs)`)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "use `arr.count` for package access")
}

@(test)
reject_eval_macro_expanded_slash_package_access_for_custom_alias :: proc(t: ^testing.T) {
    source := `(package main)
(import things "kvist:arr")

(def xs: []int ([]int [1 2 3]))

(defmacro bad-count [xs]
  (let [head (symbol "things/count")]
    (quasiquote
      ((unquote head) (unquote xs)))))`

    _, err, ok := kvist.compile_eval_source_with_map(source, `(bad-count xs)`)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "use `things.count` for package access")
}

@(test)
compile_macro_generated_data_literals_have_unique_names :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro as-data [form]
  (quasiquote (quote (unquote form))))

(defn main [] -> int
  (let [first (as-data [:name "Ada"])
        second (as-data [:name "Grace"])]
    (+ (count first) (count second))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, count_substring(output, "kvist_data_literal_1: Data"), 1)
    testing.expect_value(t, count_substring(output, "kvist_data_literal_2: Data"), 1)
}

@(test)
compile_doc_macro_uses_source_doc_expression :: proc(t: ^testing.T) {
    source := `(package main)

(defn greet
  "Say hello."
  []
  (println "hello"))

(defn main []
  (doc greet))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `fmt.println("Say hello.")`), true)
    testing.expect_value(t, strings.contains(output, "kvist-prim-doc"), false)
}

@(test)
compile_shipped_test_macro_package :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-test-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package tests)

(import t "kvist:test")

(t.deftest sample
  (t.is true))`

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

    testing.expect_value(t, strings.contains(output, "import t__testing \"core:testing\""), true)
    testing.expect_value(t, strings.contains(output, "@(test)"), true)
    testing.expect_value(t, strings.contains(output, "sample :: proc(t: ^t__testing.T) {"), true)
    testing.expect_value(t, strings.contains(output, "t____kvist_test_expect(t, true, \"\")"), true)
}

compiler_test_repo_root :: proc(loc := #caller_location) -> string {
    file_path := loc.file_path
    if !os.is_absolute_path(file_path) {
        absolute, err := os.get_absolute_path(file_path, context.temp_allocator)
        if err == nil {
            file_path = absolute
        }
    }
    tests_dir, _ := os.split_path(file_path)
    root, _ := os.split_path(tests_dir)
    return root
}

build_test_kvist_binary :: proc(t: ^testing.T, repo_root, dir: string) -> (path: string, ok: bool) {
    bin_name := "kvist-test-bin"
    when ODIN_OS == .Windows {
        bin_name = "kvist-test-bin.exe"
    }
    bin_path, join_err := os.join_path({dir, bin_name}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return "", false
    }

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {"odin", "build", "src/cli/kvist", fmt.tprintf("-out:%s", bin_path)},
            working_dir = repo_root,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil {
        delete(bin_path)
        return "", false
    }
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    if !state.exited || state.exit_code != 0 {
        delete(bin_path)
        return "", false
    }
    repo_source, repo_source_err := os.join_path({repo_root, "src", "kvist"}, context.allocator)
    testing.expect_value(t, repo_source_err == nil, true)
    if repo_source_err != nil {
        delete(bin_path)
        return "", false
    }
    defer delete(repo_source)

    install_source_parent, install_source_parent_err := os.join_path({dir, "src"}, context.allocator)
    testing.expect_value(t, install_source_parent_err == nil, true)
    if install_source_parent_err != nil {
        delete(bin_path)
        return "", false
    }
    defer delete(install_source_parent)

    install_source, install_source_err := os.join_path({install_source_parent, "kvist"}, context.allocator)
    testing.expect_value(t, install_source_err == nil, true)
    if install_source_err != nil {
        delete(bin_path)
        return "", false
    }
    defer delete(install_source)

    if os.exists(install_source_parent) {
        testing.expect_value(t, os.is_dir(install_source_parent), true)
        if !os.is_dir(install_source_parent) {
            delete(bin_path)
            return "", false
        }
    } else {
        mk_source_parent_err := os.make_directory_all(install_source_parent)
        testing.expect_value(t, mk_source_parent_err == nil, true)
        if mk_source_parent_err != nil {
            delete(bin_path)
            return "", false
        }
    }

    if !os.exists(install_source) {
        link_err := os.symlink(repo_source, install_source)
        testing.expect_value(t, link_err == nil, true)
        if link_err != nil {
            delete(bin_path)
            return "", false
        }
    }

    repo_odin, repo_odin_err := os.join_path({repo_root, "src", "odin"}, context.allocator)
    testing.expect_value(t, repo_odin_err == nil, true)
    if repo_odin_err != nil {
        delete(bin_path)
        return "", false
    }
    defer delete(repo_odin)

    install_odin, install_odin_err := os.join_path({install_source_parent, "odin"}, context.allocator)
    testing.expect_value(t, install_odin_err == nil, true)
    if install_odin_err != nil {
        delete(bin_path)
        return "", false
    }
    defer delete(install_odin)

    if !os.exists(install_odin) {
        link_err := os.symlink(repo_odin, install_odin)
        testing.expect_value(t, link_err == nil, true)
        if link_err != nil {
            delete(bin_path)
            return "", false
        }
    }
    return bin_path, true
}

test_env_slice_delete :: proc(values: ^[dynamic]string) {
    for value in values^ {
        delete(value)
    }
    delete(values^)
    values^ = nil
}

test_child_env_without_kvist_vars :: proc(extra: []string) -> ([dynamic]string, bool) {
    inherited_env, env_err := os.environ(context.allocator)
    if env_err != nil {
        return nil, false
    }
    defer delete(inherited_env)

    env_vars := make([dynamic]string, 0, len(inherited_env)+len(extra))
    for entry in extra {
        append(&env_vars, strings.clone(entry))
    }
    for entry in inherited_env {
        if strings.has_prefix(entry, "KVIST_ROOT=") ||
           strings.has_prefix(entry, "KVIST_CACHE_DIR=") ||
           strings.has_prefix(entry, "KVIST_NO_COMPILE_CACHE=") {
            delete(entry)
            continue
        }
        append(&env_vars, entry)
    }
    return env_vars, true
}

@(test)
compile_extended_shipped_test_macro_package :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-test-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "tests.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package tests)

(import t "kvist:test")

(defn each-fixture [t: ^testing.T, body: fn [t: ^testing.T]]
  (body t))

(t.use-fixtures :each each-fixture)

(t.deftest sample
  "Sample test."
  (t.testing "numbers"
    (t.testing "parity"
    (t.is (= 1 1))
    (t.is (not false))
    (t.is (= (+ 1 1) 2))
    (t.are [x expected]
      (= x expected)
      1 1
      2 2))))`

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

    testing.expect_value(t, strings.contains(output, "sample :: proc(t: ^t__testing.T) {"), true)
    testing.expect_value(t, strings.contains(output, "each_fixture("), true)
    testing.expect_value(t, strings.contains(output, "proc(t: ^t__testing.T) {"), true)
    testing.expect_value(t, strings.contains(output, "t____kvist_test_push_context(t, \"numbers\")"), true)
    testing.expect_value(t, strings.contains(output, "t____kvist_test_push_context(t, \"parity\")"), true)
    testing.expect_value(t, strings.contains(output, "defer t____kvist_test_pop_context(t)"), true)
    testing.expect_value(t, strings.contains(output, "t____kvist_test_expect_value(t, 1, 1)"), true)
    testing.expect_value(t, strings.contains(output, "t____kvist_test_expect(t, !(false), \"\")"), true)
    testing.expect_value(t, strings.contains(output, "t____kvist_test_expect_value(t, (1) + (1), 2)"), true)
    testing.expect_value(t, strings.contains(output, "t____kvist_test_expect_value(t, 2, 2)"), true)
}

@(test)
macroexpand_with_allocator_scope :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(with-allocator [allocator context.temp_allocator]
  (let [buffer (make [dynamic]int)]
    (defer (delete buffer))
    (arr.into! buffer ([]int [1 2]))))`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(do
  (let [allocator context.temp_allocator
        kvist-old-allocator-1 context.allocator]
    (set! context.allocator allocator)
    (defer (do
      (set! context.allocator kvist-old-allocator-1)))
    (let [buffer (make [dynamic]int)] (defer (delete buffer)) (arr.into! buffer ([]int [1 2])))))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_with_temp_allocator_scope :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(with-temp-allocator [allocator]
  (let [buffer (make [dynamic]int)]
    (defer (delete buffer))
    (arr.into! buffer ([]int [1 2]))))`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(do
  (let [kvist-temp-scope-1 (runtime.default-temp-allocator-temp-begin)
        allocator context.temp-allocator
        kvist-old-allocator-1 context.allocator]
    (set! context.allocator allocator)
    (defer (do
      (set! context.allocator kvist-old-allocator-1)
      (runtime.default-temp-allocator-temp-end kvist-temp-scope-1)))
    (let [buffer (make [dynamic]int)] (defer (delete buffer)) (arr.into! buffer ([]int [1 2])))))
`
    testing.expect_value(t, output, expected)
}

@(test)
macroexpand_bare_when_uses_source_macro :: proc(t: ^testing.T) {
    output, err, ok := kvist.macroexpand_source(`(when ready?
  (run))`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    expected := `(if ready? (run) (zero))
`
    testing.expect_value(t, output, expected)
}

@(test)
macro_boolean_helpers_use_bare_core_names :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro emit-flag []
  (if (and (not false)
                 (or false true))
    (quote (def bare-bool true))
    (quote (def bare-bool false))))

(emit-flag)`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "bare_bool :: true"), true)
}

@(test)
macro_transform_helpers_use_bare_core_names :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro source-length [acc form]
  (+ acc (count (source form))))

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

(defmacro source-total [items acc]
  (if (= (count items) 0)
    acc
    (source-total (rest items)
                  (source-length acc (first items)))))

(defmacro emit-transform-summary [items]
  (let [names (map source items)
        symbols (filter symbol? items)
        total (source-total items 0)]
    (forms
      (quasiquote
        (def macro-names-count (unquote (count names))))
      (quasiquote
        (def macro-symbols-count (unquote (count symbols))))
      (quasiquote
        (def macro-source-total (unquote total))))))

(emit-transform-summary [aa 7 bb])`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "macro_names_count :: 3"), true)
    testing.expect_value(t, strings.contains(output, "macro_symbols_count :: 2"), true)
    testing.expect_value(t, strings.contains(output, "macro_source_total :: 5"), true)
}

@(test)
macroexpand_recursive_macro_dsl_does_not_overflow_stack :: proc(t: ^testing.T) {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, `(package main)

(defmacro- map-id [items]
  (if (= (count items) 0)
    0
    (if (= (source (first items)) ":db/id")
      (nth items 1)
      (map-id (rest (rest items))))))

(defmacro- emit-map-attrs [e items]
  (if (= (count items) 0)
    (forms)
    (if (= (source (first items)) ":db/id")
      (emit-map-attrs e (rest (rest items)))
      (concat
        (forms
          (quasiquote (println (unquote e)
                               (unquote (source (first items)))
                               (unquote (count (nth items 1))))))
        (emit-map-attrs e (rest (rest items)))))))

(defmacro- emit-item [form]
  (emit-map-attrs (map-id form) form))

(defmacro- emit-items [forms]
  (if (= (count forms) 0)
    (forms)
    (concat
      (emit-item (first forms))
      (emit-items (rest forms)))))

(defmacro many-maps [& forms]
  (quasiquote
    (do
      (splice (emit-items forms)))))

(defn main []
  (many-maps
`)
    for i in 0 ..< 20 {
        fmt.sbprintf(&builder, "    %s:db/id %d :name \"n%d\" :aka [\"x\" \"y\"] :children [%d]%s\n", "{", i+1, i+1, i+10, "}")
    }
    strings.write_string(&builder, `  ))`)

    source := strings.clone(strings.to_string(builder))
    defer delete(source)
    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "fmt.println(1, \":name\", 1)"), true)
    testing.expect_value(t, strings.contains(output, "fmt.println(20, \":children\", 1)"), true)
}

@(test)
macroexpand_rejects_binding_macro_shapes :: proc(t: ^testing.T) {
    _, err_if_let, ok_if_let := kvist.macroexpand_source(`(if-let [[value found] (query)]
  value)`)
    testing.expect_value(t, ok_if_let, false)
    defer delete(err_if_let.message)
    testing.expect_value(t, err_if_let.message, "while expanding macro if-let: if-let expects [[value bool] expr], then, and else")

    _, err_when_let, ok_when_let := kvist.macroexpand_source(`(when-let [value 1 (query)]
  value)`)
    testing.expect_value(t, ok_when_let, false)
    defer delete(err_when_let.message)
    testing.expect_value(t, strings.contains(err_when_let.message, "when-let expects [value bool] expr binding pairs"), true)

    _, err_when_let_tuple, ok_when_let_tuple := kvist.macroexpand_source(`(when-let [[value 1] (query)]
  value)`)
    testing.expect_value(t, ok_when_let_tuple, false)
    defer delete(err_when_let_tuple.message)
    testing.expect_value(t, strings.contains(err_when_let_tuple.message, "while expanding macro tuple-binding-name: let binding macros expect [value bool] bindings"), true)

    _, err_when_ok, ok_when_ok := kvist.macroexpand_source(`(when-ok [data (read-text path)]
  data)`)
    testing.expect_value(t, ok_when_ok, false)
    defer delete(err_when_ok.message)
    testing.expect_value(t, strings.contains(err_when_ok.message, "while expanding macro tuple-binding-name: error binding macros expect [value err] bindings"), true)

    _, err_if_ok, ok_if_ok := kvist.macroexpand_source(`(if-ok [[data err] (read-text path)]
  data)`)
    testing.expect_value(t, ok_if_ok, false)
    defer delete(err_if_ok.message)
    testing.expect_value(t, err_if_ok.message, "while expanding macro if-ok: if-ok expects [[value err] expr], then, and else")
}

@(test)
macroexpand_reports_user_macro_error_context :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro fail-fast []
  (error "bad shape"))

(defmacro outer []
  (fail-fast))`

    _, err_direct, ok_direct := kvist.macroexpand_eval_source_with_map(source, `(fail-fast)`)
    testing.expect_value(t, ok_direct, false)
    defer delete(err_direct.message)
    testing.expect_value(t, err_direct.message, "while expanding macro fail-fast: bad shape")

    _, err_nested, ok_nested := kvist.macroexpand_eval_source_with_map(source, `(outer)`)
    testing.expect_value(t, ok_nested, false)
    defer delete(err_nested.message)
    testing.expect_value(t, err_nested.message, "while expanding macro outer: while expanding macro fail-fast: bad shape")
}

@(test)
macroexpand_gensym_creates_stable_symbol_within_expansion :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro with-temp-bool [value]
  (let [tmp (gensym "__tmp")]
    (quasiquote
      (let [(unquote tmp) (unquote value)]
        (when (unquote tmp)
          (println (unquote tmp)))))))`

    output, err, ok := kvist.macroexpand_eval_source_with_map(source, `(with-temp-bool true)`)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output.output)
    defer kvist.source_map_slice_delete(output.source_map)
    defer kvist.compile_warning_slice_delete(output.warnings)

    testing.expect_value(t, strings.contains(output.output, "(let [__tmp_"), true)
    testing.expect_value(t, strings.contains(output.output, "(if __tmp_"), true)
    testing.expect_value(t, strings.contains(output.output, "(fmt.println __tmp_"), true)
}

@(test)
macro_sequence_helpers_use_auto_referred_core_names :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro emit-counts [items]
  (forms
    (quasiquote
      (def macro-count: int (unquote (count items))))
    (quasiquote
      (def macro-count-again: int (unquote (count items))))))

(emit-counts [1 2 3])`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "macro_count: int : 3"), true)
    testing.expect_value(t, strings.contains(output, "macro_count_again: int : 3"), true)
}

@(test)
macro_contains_helper_uses_auto_referred_core_name :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro emit-contains [items]
  (forms
    (quasiquote
      (def macro-has-two: bool (unquote (contains? items 2))))
    (quasiquote
      (def macro-has-two-again: bool (unquote (contains? items 2))))))

(emit-contains [1 2 3])`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "macro_has_two: bool : true"), true)
    testing.expect_value(t, strings.contains(output, "macro_has_two_again: bool : true"), true)
}

@(test)
macro_qualified_kvist_helpers_are_ordinary_source_calls :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro emit-count [items]
  (quasiquote
    (def macro-count: int (unquote (kvist.count items)))))

(emit-count [1 2 3])`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "macro_count: int : 3"), false)
}

@(test)
compile_source_with_user_macro :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro unless [condition & body]
  (quasiquote
    (if (unquote condition)
      (do)
      (do (splice body)))))

(defn classify [n: int] -> string
  (unless (> n 0)
    (return "non-positive"))
  "positive")`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `classify :: proc(n: int) -> string`), true)
    testing.expect_value(t, strings.contains(output, `return "non-positive"`), true)
    testing.expect_value(t, strings.contains(output, `return "positive"`), true)
}

@(test)
compile_source_with_top_level_macro_dsl :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro defentity [name fields]
  (let [make-name (symbol (str "make-" (name name)))]
    (forms
      (quasiquote
        (defstruct (unquote name) (unquote fields)))
      (quasiquote
        (defn (unquote make-name) [] -> (unquote name)
          ((unquote name) []))))))

(defentity Point [x: float y: float])

(defn point-origin? [point: Point] -> bool
  (and (= point.x 0.0)
       (= point.y 0.0)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `Point :: struct {`), true)
    testing.expect_value(t, strings.contains(output, `make_Point :: proc() -> Point`), true)
    testing.expect_value(t, strings.contains(output, `return Point{}`), true)
    testing.expect_value(t, strings.contains(output, `point_origin_p :: proc(point: Point) -> bool`), true)
}

@(test)
compile_source_with_recursive_macro_dsl :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro emit-union-ctors [union-name variants]
  (if (= (count variants) 0)
    (forms)
    (let [tag (first variants)
          value-type (nth variants 1)
          ctor-name (symbol (str "make-" (name union-name) "-" (name tag)))
          field-key (keyword (name tag))]
      (forms
        (quasiquote
          (defn (unquote ctor-name) [value: (unquote value-type)] -> (unquote union-name)
            ((unquote union-name) (unquote field-key) value)))
        (emit-union-ctors union-name (rest (rest variants)))))))

(defmacro defunion+ctors [name variants]
  (forms
    (quasiquote
      (defunion (unquote name) (unquote variants)))
    (emit-union-ctors name variants)))

(defunion+ctors Value [
  i: int
  s: string
  ok: bool
])`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `Value :: union {`), true)
    testing.expect_value(t, strings.contains(output, `make_Value_i :: proc(value: int) -> Value`), true)
    testing.expect_value(t, strings.contains(output, `make_Value_s :: proc(value: string) -> Value`), true)
    testing.expect_value(t, strings.contains(output, `make_Value_ok :: proc(value: bool) -> Value`), true)
    testing.expect_value(t, strings.contains(output, `return Value(value)`), true)
}

@(test)
compile_source_with_message_family_macro :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro emit-message-structs [entries]
  (if (= (count entries) 0)
    (forms)
    (let [entry (first entries)
          struct-name (nth entry 0)
          fields (nth entry 1)]
      (forms
        (quasiquote
          (defstruct (unquote struct-name) (unquote fields)))
        (emit-message-structs (rest entries))))))

(defmacro emit-message-union-entries [entries]
  (if (= (count entries) 0)
    (forms)
    (let [entry (first entries)
          struct-name (nth entry 0)
          tag (symbol (str (name struct-name) ":"))]
      (forms
        tag
        struct-name
        (emit-message-union-entries (rest entries))))))

(defmacro emit-message-ctors [union-name entries]
  (if (= (count entries) 0)
    (forms)
    (let [entry (first entries)
          struct-name (nth entry 0)
          ctor-name (symbol (str "make-" (name union-name) "-" (name struct-name)))
          tag (symbol (str (name struct-name) ":"))
          field-key (keyword (name struct-name))]
      (forms
        (quasiquote
          (defn (unquote ctor-name) [value: (unquote struct-name)] -> (unquote union-name)
            ((unquote union-name) (unquote field-key) value)))
        (emit-message-ctors union-name (rest entries))))))

(defmacro defmessages [union-name entries]
  (forms
    (emit-message-structs entries)
    (quasiquote
      (defunion (unquote union-name) [
        (splice (emit-message-union-entries entries))
      ]))
    (emit-message-ctors union-name entries)))

(defmessages Event [
  [Connected [id: int]]
  [Disconnected [id: int reason: string]]
  [Data [id: int payload: string]]
])`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `Connected :: struct {`), true)
    testing.expect_value(t, strings.contains(output, `Disconnected :: struct {`), true)
    testing.expect_value(t, strings.contains(output, `Data :: struct {`), true)
    testing.expect_value(t, strings.contains(output, `Event :: union {`), true)
    testing.expect_value(t, strings.contains(output, `make_Event_Connected :: proc(value: Connected) -> Event`), true)
    testing.expect_value(t, strings.contains(output, `make_Event_Disconnected :: proc(value: Disconnected) -> Event`), true)
    testing.expect_value(t, strings.contains(output, `make_Event_Data :: proc(value: Data) -> Event`), true)
}

@(test)
compile_macro_generated_make_type_uses_type_context :: proc(t: ^testing.T) {
    source := `(package main)

(defmacro dynamic [elem-type]
  (quasiquote
    (not-a-type-constructor (unquote elem-type))))

(defmacro empty [elem-type]
  (quasiquote
    (make (dynamic (unquote elem-type)))))

(defn main []
  (let [xs (empty int)]
    (defer (delete xs))
    (return)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "xs := make([dynamic]int)"), true)
}

@(test)
compile_soa_convenience_macros :: proc(t: ^testing.T) {
    source := `(package main)
(import soa "kvist:soa")

(defstruct Particle [
  x: f32
  vx: f32
  mass: f32
])

(defn update-one [] -> f32
  (let [particles (soa.make Particle 2)]
    (defer (delete particles))
    (soa.push! (addr particles) (Particle :x 1 :vx 2 :mass 3))
    (soa.update! particles 0
      .vx (+ vx 10)
      .x (+ x vx))
    (+ particles.x[0] particles.vx[0])))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "particles := make(#soa[dynamic]Particle, 0, 2)"), true)
    testing.expect_value(t, strings.contains(output, "append_soa(&particles, Particle{x = 1, vx = 2, mass = 3})"), true)
    testing.expect_value(t, strings.contains(output, "vx := particles.vx[0]"), true)
    testing.expect_value(t, strings.contains(output, "x := particles.x[0]"), true)
    testing.expect_value(t, strings.contains(output, "particles.vx[0] = (vx) + (10)"), true)
    testing.expect_value(t, strings.contains(output, "particles.x[0] = (x) + (vx)"), true)
}
