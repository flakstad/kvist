package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

@(test)
compile_leaves_unimported_shipped_package_calls_unresolved :: proc(t: ^testing.T) {
    source := `(package main)

(defn inc [x: int] -> int
  (+ x 1))

(defn dot [xs: []int] -> [dynamic]int
  (arr.map inc xs))

(defn slash [xs: []int] -> [dynamic]int
  (arr/map inc xs))

(defn official [value: int]
  (html.render value))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "arr.map(inc, xs)"), true)
    testing.expect_value(t, strings.contains(output, "arr/map(inc, xs)"), true)
    testing.expect_value(t, strings.contains(output, "html.render(value)"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_impl"), false)
    testing.expect_value(t, strings.contains(output, "html/render"), false)
}

@(test)
compile_shipped_struct_source_package_uses_wrapper_resolution :: proc(t: ^testing.T) {
    source := `(package main)
(import soa "kvist:soa")

(defstruct Profile
  {name: string
   active?: bool})

(defn main []
  (println (soa.fields 'Profile) (soa.types 'Profile)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "fmt.println([]string{\"name\", \"active?\"}, map[string]string{"), true)
    testing.expect_value(t, strings.contains(output, "\"name\" = \"string\""), true)
    testing.expect_value(t, strings.contains(output, "\"active?\" = \"bool\""), true)
}

@(test)
compile_shipped_test_once_fixtures :: proc(t: ^testing.T) {
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

(defvar fixture-count: int 0)

(defn once-fixture []
  (set! fixture-count (+ fixture-count 1)))

(t.use-fixtures :once once-fixture)

(t.deftest first
  (t.is (= fixture-count 1)))

(t.deftest second
  (t.is (= fixture-count 1)))`

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

    testing.expect_value(t, strings.contains(output, "__kvist_test_once_guard"), true)
    testing.expect_value(t, strings.contains(output, "__kvist_test_ensure_once()"), true)
    testing.expect_value(t, strings.contains(output, "once_fixture()"), true)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "test", path},
            working_dir = repo_root,
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
}

@(test)
compile_shipped_test_generic_assertion_messages :: proc(t: ^testing.T) {
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
  (t.is true "ok")
  (t.is false "not ok"))`

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

    testing.expect_value(t, strings.contains(output, `__kvist_test_expect(t, true, "ok")`), true)
    testing.expect_value(t, strings.contains(output, `__kvist_test_expect(t, false, "not ok")`), true)
}

@(test)
compile_path_resolves_shipped_packages_from_configured_root :: proc(t: ^testing.T) {
    sync.lock(&test_env_mutex)
    defer sync.unlock(&test_env_mutex)

    dir, dir_err := os.make_directory_temp("", "kvist-home-src-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    source_root, source_root_err := os.join_path({dir, "src", "kvist"}, context.allocator)
    testing.expect_value(t, source_root_err == nil, true)
    if source_root_err != nil {
        return
    }
    defer delete(source_root)
    mk_source_root_err := os.make_directory_all(source_root)
    testing.expect_value(t, mk_source_root_err == nil, true)
    if mk_source_root_err != nil {
        return
    }

    core_dir, core_join_err := os.join_path({source_root, "core"}, context.allocator)
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
    core_write_err := os.write_entire_file_from_string(core_path, `(package core)`)
    testing.expect_value(t, core_write_err == nil, true)
    if core_write_err != nil {
        return
    }

    toy_dir, toy_join_err := os.join_path({source_root, "toy"}, context.allocator)
    testing.expect_value(t, toy_join_err == nil, true)
    if toy_join_err != nil {
        return
    }
    defer delete(toy_dir)
    mk_toy_err := os.make_directory_all(toy_dir)
    testing.expect_value(t, mk_toy_err == nil, true)
    if mk_toy_err != nil {
        return
    }

    toy_path, toy_path_err := os.join_path({toy_dir, "toy.kvist"}, context.allocator)
    testing.expect_value(t, toy_path_err == nil, true)
    if toy_path_err != nil {
        return
    }
    defer delete(toy_path)
    toy_write_err := os.write_entire_file_from_string(toy_path, `(package toy)

(defn id [x: int] -> int
  x)`)
    testing.expect_value(t, toy_write_err == nil, true)
    if toy_write_err != nil {
        return
    }

    main_path, main_path_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_path_err == nil, true)
    if main_path_err != nil {
        return
    }
    defer delete(main_path)
    main_write_err := os.write_entire_file_from_string(main_path, `(package main)
(import toy "kvist:toy")

(defn main [] -> int
  (toy.id 42))`)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    output_path, output_join_err := os.join_path({dir, "main.odin"}, context.allocator)
    testing.expect_value(t, output_join_err == nil, true)
    if output_join_err != nil {
        return
    }
    defer delete(output_path)

    root_env := fmt.tprintf("KVIST_ROOT=%s", source_root)
    child_env, child_env_ok := test_child_env_without_kvist_vars({root_env})
    testing.expect_value(t, child_env_ok, true)
    if !child_env_ok {
        return
    }
    defer test_env_slice_delete(&child_env)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "compile", main_path, "-o", output_path},
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
        return
    }

    output, read_err := os.read_entire_file_from_path(output_path, context.allocator)
    testing.expect_value(t, read_err == nil, true)
    if read_err != nil {
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(string(output), "toy__id :: proc(x: int) -> int"), true)
    testing.expect_value(t, strings.contains(string(output), "return toy__id(42)"), true)
}

@(test)
compile_source_with_shipped_reload_package_exposes_run_host_alias :: proc(t: ^testing.T) {
    tmp_dir, tmp_dir_err := os.make_directory_temp("", "kvist-reload-package-*", context.allocator)
    testing.expect_value(t, tmp_dir_err == nil, true)
    if tmp_dir_err != nil {
        return
    }
    defer os.remove_all(tmp_dir)
    defer delete(tmp_dir)

    path, join_err := os.join_path({tmp_dir, "kvist-reload-package-test.kvist"}, context.allocator)
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

(defn status-capability
  [ctx: rawptr input: string] -> [output: string, message: string, ok: bool]
  (values input "" true))

(defn run [state: ^Reload_State host: ^reload.Run_Host]
  (do
    (reload.register-console-capability!
      host
      "app/status"
      "proc(string)->string"
      (rawptr state)
      (rawptr status-capability))
    (when (reload.checkpoint! host)
      (return))))`
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

    testing.expect_value(t, strings.contains(output, "import runtime "), true)
    testing.expect_value(t, strings.contains(output, "reload__Run_Host :: runtime.Run_Host"), true)
    testing.expect_value(t, strings.contains(output, "reload__reload__Run_Host"), false)
    testing.expect_value(t, strings.contains(output, "run :: proc(state: ^Reload_State, host: ^reload__Run_Host)"), true)
    testing.expect_value(t, strings.contains(output, "runtime.console_register_capability_raw("), true)
}

@(test)
compile_source_with_shipped_reload_package_allows_any_import_alias :: proc(t: ^testing.T) {
    tmp_dir, tmp_dir_err := os.make_directory_temp("", "kvist-reload-alias-package-*", context.allocator)
    testing.expect_value(t, tmp_dir_err == nil, true)
    if tmp_dir_err != nil {
        return
    }
    defer os.remove_all(tmp_dir)
    defer delete(tmp_dir)

    path, join_err := os.join_path({tmp_dir, "kvist-reload-alias-test.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package main)
(import r "kvist:reload")

(defstruct App_State
  {requests: int})

(def Reload_State App_State)

(defn run [state: ^Reload_State host: ^r.Run_Host]
  (when (r.checkpoint! host)
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

    testing.expect_value(t, strings.contains(output, "r__Run_Host :: runtime.Run_Host"), true)
    testing.expect_value(t, strings.contains(output, "run :: proc(state: ^Reload_State, host: ^r__Run_Host)"), true)
    testing.expect_value(t, strings.contains(output, "r__checkpoint_bang(host)"), true)
}

@(test)
compile_shipped_str_source_package_uses_hybrid_resolution :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-str-hybrid-*", context.allocator)
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

    source := `(package main)
(import str "kvist:str")

(defn demo []
  (let [name "  Kvist  "
        trimmed (str.trim name)
        initial (str.get trimmed 0)
        tail (str.slice trimmed 1)
        starts? (str.starts-with? trimmed "K")
        lowered (str.lower trimmed)
        uppered (str.upper lowered)
        parts (str.split "a,b" ",")
        joined (str.join parts "-")
        replaced (str.replace joined "-" ":" 1)]
    (defer (delete parts))
    (defer (delete joined))
    (defer (delete replaced))
    (println (str.count trimmed) initial (str.count tail) starts? uppered joined replaced)))`

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

    testing.expect_value(t, strings.contains(output, "str__count :: #force_inline proc(s: string) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "return len(s)"), true)
    testing.expect_value(t, strings.contains(output, "initial := trimmed[0]"), true)
    testing.expect_value(t, strings.contains(output, "tail := (trimmed)[1:]"), true)
    testing.expect_value(t, strings.contains(output, "str__trim :: #force_inline proc(s: string) -> string {"), true)
    testing.expect_value(t, strings.contains(output, `import utf8 "core:unicode/utf8"`), true)
    testing.expect_value(t, strings.contains(output, "start := strings.index_proc(s, strings.is_space, false)"), true)
    testing.expect_value(t, strings.contains(output, "_, width := utf8.decode_rune_in_string((s)[last:])"), true)
    testing.expect_value(t, strings.contains(output, "return (s)[start:(last) + (width)]"), true)
    testing.expect_value(t, strings.contains(output, "#borrowed"), false)
    testing.expect_value(t, strings.contains(output, "str__starts_with_p :: #force_inline proc(s, prefix: string) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "return strings.has_prefix(s, prefix)"), true)
    testing.expect_value(t, strings.contains(output, "str__lower :: #force_inline proc(s: string) -> string {"), true)
    testing.expect_value(t, strings.contains(output, "return strings.to_lower(s)"), true)
    testing.expect_value(t, strings.contains(output, "str__upper :: #force_inline proc(s: string) -> string {"), true)
    testing.expect_value(t, strings.contains(output, "return strings.to_upper(s)"), true)
    testing.expect_value(t, strings.contains(output, "#owned"), false)
    testing.expect_value(t, strings.contains(output, "trimmed := str__trim(name)"), true)
    testing.expect_value(t, strings.contains(output, "starts_p := str__starts_with_p(trimmed, \"K\")"), true)
    testing.expect_value(t, strings.contains(output, "lowered := str__lower(trimmed)"), true)
    testing.expect_value(t, strings.contains(output, "uppered := str__upper(lowered)"), true)
    testing.expect_value(t, strings.contains(output, "parts := str__split(\"a,b\", \",\")"), true)
    testing.expect_value(t, strings.contains(output, "joined := str__join_impl((parts)[0:], \"-\")"), true)
    testing.expect_value(t, strings.contains(output, "replaced := str__replace_impl(joined, \"-\", \":\", 1)"), true)
    testing.expect_value(t, strings.contains(output, "fmt.println(str__count(trimmed), initial, str__count(tail), starts_p, uppered, joined, replaced)"), true)
}

@(test)
compile_shipped_str_source_package_rejects_private_members_without_fallback :: proc(t: ^testing.T) {
    source := `(package main)
(import str "kvist:str")

(defn demo [] -> string
  (str.join-impl [] ","))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, err.message, "source package member is private or undefined: str.join-impl")
}

@(test)
compile_shipped_set_source_package_uses_hybrid_resolution :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-set-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package main)
(import set "kvist:set")

(defn demo []
  (let [base (set.of int [1 2 3])
        extra (set.of int [3 4 5])
        merged (set.union base extra)
        overlap (set.intersection base extra)
        only-base (set.difference base extra)
        bigger (set.add base 9)
        smaller (set.remove bigger 2)
        subset? (set.subset? overlap merged)
        superset? (set.superset? merged overlap)
        disjoint? (set.disjoint? only-base extra)
        mutable (set.of int [1 2 3])]
    (defer (delete base))
    (defer (delete extra))
    (defer (delete merged))
    (defer (delete overlap))
    (defer (delete only-base))
    (defer (delete bigger))
    (defer (delete smaller))
    (defer (delete mutable))
    (set.add! mutable 4)
    (set.remove! mutable 1)
    (set.union! mutable extra)
    (println subset? superset? disjoint? (set.contains? mutable 4))))`

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

    testing.expect_value(t, strings.contains(output, "set__union :: #force_inline proc(lhs, rhs: map[$T]struct{}) -> map[T]struct{} {"), true)
    testing.expect_value(t, strings.contains(output, "set__intersection :: #force_inline proc(lhs, rhs: map[$T]struct{}) -> map[T]struct{} {"), true)
    testing.expect_value(t, strings.contains(output, "set__difference :: #force_inline proc(lhs, rhs: map[$T]struct{}) -> map[T]struct{} {"), true)
    testing.expect_value(t, strings.contains(output, "set__subset_p :: #force_inline proc(lhs, rhs: map[$T]struct{}) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "set__superset_p :: #force_inline proc(lhs, rhs: map[$T]struct{}) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "set__disjoint_p :: #force_inline proc(lhs, rhs: map[$T]struct{}) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "set__add :: #force_inline proc(s: map[$T]struct{}, value: T) -> map[T]struct{} {"), true)
    testing.expect_value(t, strings.contains(output, "set__remove :: #force_inline proc(s: map[$T]struct{}, value: T) -> map[T]struct{} {"), true)
    testing.expect_value(t, strings.contains(output, "out := make(map[T]struct{}, (len(lhs)) + (len(rhs)))"), true)
    testing.expect_value(t, strings.contains(output, "lhs_count := len(lhs)"), true)
    testing.expect_value(t, strings.contains(output, "rhs_count := len(rhs)"), true)
    testing.expect_value(t, strings.contains(output, "cap := lhs_count"), true)
    testing.expect_value(t, strings.contains(output, "if (cap) > (rhs_count) {"), true)
    testing.expect_value(t, strings.contains(output, "out := make(map[T]struct{}, cap)"), true)
    testing.expect_value(t, strings.contains(output, "if (len(lhs)) > (len(rhs)) {"), true)
    testing.expect_value(t, strings.contains(output, "out := make(map[T]struct{}, (len(s)) + (1))"), true)
    testing.expect_value(t, strings.contains(output, "merged := set__union(base, extra)"), true)
    testing.expect_value(t, strings.contains(output, "overlap := set__intersection(base, extra)"), true)
    testing.expect_value(t, strings.contains(output, "only_base := set__difference(base, extra)"), true)
    testing.expect_value(t, strings.contains(output, "bigger := set__add(base, 9)"), true)
    testing.expect_value(t, strings.contains(output, "smaller := set__remove(bigger, 2)"), true)
    testing.expect_value(t, strings.contains(output, "subset_p := set__subset_p(overlap, merged)"), true)
    testing.expect_value(t, strings.contains(output, "superset_p := set__superset_p(merged, overlap)"), true)
    testing.expect_value(t, strings.contains(output, "disjoint_p := set__disjoint_p(only_base, extra)"), true)
    testing.expect_value(t, strings.contains(output, "mutable[4] = struct{}{}"), true)
    testing.expect_value(t, strings.contains(output, "delete_key(&(mutable), 1)"), true)
    testing.expect_value(t, strings.contains(output, "for value, _ in extra {"), true)
    testing.expect_value(t, strings.contains(output, "mutable[value] = struct{}{}"), true)
    testing.expect_value(t, strings.contains(output, "kvist_set_union_in_place"), false)
    testing.expect_value(t, strings.contains(output, "fmt.println(subset_p, superset_p, disjoint_p, (map_get(&(mutable), 4, false)))"), false)
}

@(test)
compile_shipped_map_source_package_uses_hybrid_resolution :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-map-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package main)
(import core "kvist:core")
(import map "kvist:map")

(defn demo []
  (let [base (map.of string int {"a" 1 "b" 2})
        overrides (map.of string int {"b" 20 "c" 30})
        merged (map.merge base overrides)
        assoced (map.assoc merged "z" 99)
        trimmed (map.dissoc assoced "b")
        fresh (map.empty string int 4)
        mutable (map.of string int {"seed" 1})
        key-list (map.keys base)
        value-list (map.vals overrides)
        zipped (map.zip ["x" "y" "z"] [10 20])
        has-a? (map.contains? merged "a")
        read-a (map.get merged "a")]
    (defer (delete base))
    (defer (delete overrides))
    (defer (delete merged))
    (defer (delete assoced))
    (defer (delete trimmed))
    (defer (delete fresh))
    (defer (delete mutable))
    (defer (delete key-list))
    (defer (delete value-list))
    (defer (delete zipped))
    (map.assoc! mutable "extra" 7)
    (map.dissoc! mutable "seed")
    (map.merge! mutable overrides)
    (println has-a? read-a (count key-list) (count value-list) (map.get zipped "x" 0))))`

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

    testing.expect_value(t, strings.contains(output, "map__contains_p :: #force_inline proc(m: map[$K]$V, key: K) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "map__merge :: #force_inline proc(lhs, rhs: map[$K]$V) -> map[K]V {"), true)
    testing.expect_value(t, strings.contains(output, "out := make(map[K]V, (len(lhs)) + (len(rhs)))"), true)
    testing.expect_value(t, strings.contains(output, "map__keys :: #force_inline proc(m: map[$K]$V) -> [dynamic]K {"), true)
    testing.expect_value(t, strings.contains(output, "out := make([dynamic]K, 0, len(m))"), true)
    testing.expect_value(t, strings.contains(output, "map__vals :: #force_inline proc(m: map[$K]$V) -> [dynamic]V {"), true)
    testing.expect_value(t, strings.contains(output, "out := make([dynamic]V, 0, len(m))"), true)
    testing.expect_value(t, strings.contains(output, "map__zip :: #force_inline proc(ks: []$K, vs: []$V) -> map[K]V {"), true)
    testing.expect_value(t, strings.contains(output, "map__assoc :: #force_inline proc(m: map[$K]$V, key: K, value: V) -> map[K]V {"), true)
    testing.expect_value(t, strings.contains(output, "map__dissoc :: #force_inline proc(m: map[$K]$V, key: K) -> map[K]V {"), true)
    testing.expect_value(t, strings.contains(output, "value_count := len(vs)"), true)
    testing.expect_value(t, strings.contains(output, "cap := len(ks)"), true)
    testing.expect_value(t, strings.contains(output, "if (cap) > (value_count) {"), true)
    testing.expect_value(t, strings.contains(output, "out := make(map[K]V, cap)"), true)
    testing.expect_value(t, strings.contains(output, "if (i) < (value_count) {"), true)
    testing.expect_value(t, strings.contains(output, "merged := map__merge(base, overrides)"), true)
    testing.expect_value(t, strings.contains(output, "assoced := map__assoc(merged, \"z\", 99)"), true)
    testing.expect_value(t, strings.contains(output, "trimmed := map__dissoc(assoced, \"b\")"), true)
    testing.expect_value(t, strings.contains(output, "fresh := make(map[string]int, 4)"), true)
    testing.expect_value(t, strings.contains(output, "mutable := map[string]int{\"seed\" = 1}"), true)
    testing.expect_value(t, strings.contains(output, "key_list := map__keys(base)"), true)
    testing.expect_value(t, strings.contains(output, "value_list := map__vals(overrides)"), true)
    testing.expect_value(t, strings.contains(output, "zipped := map__zip("), true)
    testing.expect_value(t, strings.contains(output, "\"x\", \"y\", \"z\""), true)
    testing.expect_value(t, strings.contains(output, "has_a_p := map__contains_p(merged, \"a\")"), true)
    testing.expect_value(t, strings.contains(output, "read_a := merged[\"a\"]"), true)
    testing.expect_value(t, strings.contains(output, "mutable[\"extra\"] = 7"), true)
    testing.expect_value(t, strings.contains(output, "delete_key(&(mutable), \"seed\")"), true)
    testing.expect_value(t, strings.contains(output, "for key, value in overrides {"), true)
    testing.expect_value(t, strings.contains(output, "mutable[key] = value"), true)
    testing.expect_value(t, strings.contains(output, "kvist_merge_in_place(&(mutable), overrides)"), false)
    testing.expect_value(t, strings.contains(output, "fmt.println(has_a_p, read_a, len(key_list), len(value_list), kvist_get_or_default(zipped, \"x\", 0))"), true)
}

@(test)
compile_shipped_arr_source_package_uses_hybrid_resolution :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-arr-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    path, join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(path)

    source := `(package main)
(import core "kvist:core")
(import arr "kvist:arr")

(defn big? [x: int] -> bool
  (> x 15))

(defn next-value [] -> int
  7)

(defn double [x: int] -> int
  (* x 2))

(defn inc-value [x: int] -> int
  (+ x 1))

(defn add-index [i: int, x: int] -> int
  (+ i x))

(defn even-value? [x: int] -> bool
  (= (% x 2) 0))

(defn keep-even [x: int] -> [value: int, ok: bool]
  (if (even-value? x)
    (return x true)
    (return 0 false)))

(defn pair [x: int] -> []int
  ([]int [x x]))

(defn add-values [acc: int, x: int] -> int
  (+ acc x))

(defn pick-first [n: int] -> int
  0)

(defn demo []
  (let [numbers (arr.range 1 5)
        seed (arr.dynamic int [10 20 30 40])
        fixed (arr.fixed int [4 5 6])
        xs (slice seed 0)
        mutable ([dynamic]int [1 2 3])
        total (arr.count xs)
        first-by-get (arr.get xs 0)
        a (arr.first xs)
        b (arr.second xs)
        c (arr.nth 2 xs)
        z (arr.last xs)
        window (arr.slice xs 1 3)
        prefix (arr.take 2 xs)
        suffix (arr.drop 1 xs)
        without-tail (arr.drop-last 2 xs)
        sampled (arr.take-nth 2 xs)
        repeated (arr.repeat 3 9)
        generated (arr.repeatedly 2 next-value)
        powers (arr.iterate 4 double 1)
        cycled (arr.cycle 5 xs)
        mapped (arr.map inc-value xs)
        indexed (arr.map-indexed add-index xs)
        filtered (arr.filter even-value? xs)
        removed (arr.remove even-value? xs)
        kept (arr.keep keep-even xs)
        flattened (arr.mapcat pair xs)
        counted (arr.count-by even-value? xs)
        shuffled (arr.shuffle pick-first xs)
        sorted (arr.sort xs)
        threaded-flat-count (->> xs
                         (arr.mapcat pair)
                         (count))
        reduced (arr.reduce add-values 0 xs)
        small-prefix (arr.take-while big? xs)
        large-suffix (arr.drop-while big? xs)
        [first-big found-big?] (arr.find big? xs)
        any-big? (arr.some? big? xs)
        all-big? (arr.every? big? xs)
        tail (arr.rest xs)
        init (arr.butlast xs)]
    (defer (delete mutable))
    (defer (delete indexed))
    (defer (delete kept))
    (defer (delete flattened))
    (defer (delete counted))
    (defer (delete shuffled))
    (defer (delete sorted))
    (arr.push! mutable total)
    (arr.map! inc-value mutable)
    (arr.map-indexed! add-index mutable)
    (arr.fill! mutable 8)
    (arr.reverse! mutable)
    (arr.filter! even-value? mutable)
    (arr.remove! even-value? mutable)
    (arr.keep! keep-even mutable)
    (arr.shuffle! pick-first mutable)
    (arr.sort! mutable)
    (println (count fixed) total first-by-get a b c z
             first-big found-big? any-big? all-big?
             (count numbers) (count sampled) (count repeated) (count generated) (count powers) (count cycled)
             (count window) (count prefix) (count suffix) (count without-tail) (count tail) (count init)
             (count indexed) (count flattened) (count counted) (count shuffled) (count sorted) threaded-flat-count)))`

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

    testing.expect_value(t, strings.contains(output, "seed := [dynamic]int{10, 20, 30, 40}"), true)
    testing.expect_value(t, strings.contains(output, "fixed := [3]int{4, 5, 6}"), true)
    testing.expect_value(t, strings.contains(output, "xs := (seed)[0:]"), true)
    testing.expect_value(t, strings.contains(output, "arr__count :: #force_inline proc(xs: []$T) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "total := arr__count(xs)"), true)
    testing.expect_value(t, strings.contains(output, "arr__range_impl :: proc(start: int, end: int, step: int) -> arr__Range_Source {"), true)
    testing.expect_value(t, strings.contains(output, "numbers := (proc(kvist_source_arg_1: int, kvist_source_arg_2: int, kvist_source_arg_3: int) -> [dynamic]int {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_source := arr__range_impl(kvist_source_arg_1, kvist_source_arg_2, kvist_source_arg_3)"), true)
    testing.expect_value(t, strings.contains(output, "first_by_get := xs[0]"), true)
    testing.expect_value(t, strings.contains(output, "a := xs[0]"), true)
    testing.expect_value(t, strings.contains(output, "b := xs[1]"), true)
    testing.expect_value(t, strings.contains(output, "c := xs[2]"), true)
    testing.expect_value(t, strings.contains(output, "z := xs[(len(xs)) - (1)]"), true)
    testing.expect_value(t, strings.contains(output, "z := (xs)[len(xs)-1]"), false)
    testing.expect_value(t, strings.contains(output, "window := (xs)[1:3]"), true)
    testing.expect_value(t, strings.contains(output, "arr__take :: #force_inline proc(n: int, xs: []$T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "arr__drop :: #force_inline proc(n: int, xs: []$T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "#borrowed"), false)
    testing.expect_value(t, strings.contains(output, "arr__drop_last :: #force_inline proc(n: int, xs: []$T) -> []T"), true)
    testing.expect_value(t, strings.contains(output, "prefix := arr__take(2, xs)"), true)
    testing.expect_value(t, strings.contains(output, "suffix := arr__drop(1, xs)"), true)
    testing.expect_value(t, strings.contains(output, "without_tail := arr__drop_last(2, xs)"), true)
    testing.expect_value(t, strings.contains(output, "arr__Take_Nth_Source :: struct($T: typeid) {step: int, xs: []T, zero: T, index: int}"), true)
    testing.expect_value(t, strings.contains(output, "arr__take_nth_impl :: proc(n: int, xs: []$T) -> arr__Take_Nth_Source(T) {"), true)
    testing.expect_value(t, strings.contains(output, "sampled := (proc(kvist_source_arg_1: int, kvist_source_arg_2: []int) -> [dynamic]int {"), true)
    testing.expect_value(t, strings.contains(output, "arr__Repeat_Source :: struct($T: typeid) {value: T, index: int, count: int}"), true)
    testing.expect_value(t, strings.contains(output, "arr__repeat_impl :: proc(n: int, value: $T) -> arr__Repeat_Source(T) {"), true)
    testing.expect_value(t, strings.contains(output, "repeated := (proc(kvist_source_arg_1: int, kvist_source_arg_2: int) -> [dynamic]int {"), true)
    testing.expect_value(t, strings.contains(output, "arr__Repeatedly_Source :: struct($T: typeid) {f: proc() -> T, zero: T, index: int, count: int}"), true)
    testing.expect_value(t, strings.contains(output, "arr__repeatedly_impl :: proc(n: int, f: proc() -> $T) -> arr__Repeatedly_Source(T) {"), true)
    testing.expect_value(t, strings.contains(output, "generated := (proc(kvist_source_arg_1: int, kvist_source_arg_2: proc() -> int) -> [dynamic]int {"), true)
    testing.expect_value(t, strings.contains(output, "arr__Iterate_Source :: struct($T: typeid) {f: proc(x: T) -> T, current: T, index: int, count: int}"), true)
    testing.expect_value(t, strings.contains(output, "arr__iterate_impl :: proc(n: int, f: proc(x: $T) -> T, init: T) -> arr__Iterate_Source(T) {"), true)
    testing.expect_value(t, strings.contains(output, "powers := (proc(kvist_source_arg_1: int, kvist_source_arg_2: proc(x: int) -> int, kvist_source_arg_3: int) -> [dynamic]int {"), true)
    testing.expect_value(t, strings.contains(output, "arr__Cycle_Source :: struct($T: typeid) {xs: []T, zero: T, index: int, count: int, size: int}"), true)
    testing.expect_value(t, strings.contains(output, "arr__cycle_impl :: proc(n: int, xs: []$T) -> arr__Cycle_Source(T) {"), true)
    testing.expect_value(t, strings.contains(output, "cycled := (proc(kvist_source_arg_1: int, kvist_source_arg_2: []int) -> [dynamic]int {"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_impl :: #force_inline proc(f: proc(x: $T) -> $U, xs: []T) -> [dynamic]U {"), true)
    testing.expect_value(t, strings.contains(output, "mapped := arr__map_impl(inc_value, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_indexed :: #force_inline proc(f: proc(i: int, x: $T) -> $U, xs: []T) -> [dynamic]U {"), true)
    testing.expect_value(t, strings.contains(output, "indexed := arr__map_indexed(add_index, xs)"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_indexed_bang_impl :: #force_inline proc(f: proc(i: int, x: $T) -> T, xs: []T) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_indexed_bang_impl(add_index, (mutable)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__fill_bang_impl :: #force_inline proc(xs: []$T, value: T) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__fill_bang_impl((mutable)[0:], 8)"), true)
    testing.expect_value(t, strings.contains(output, "arr__reverse_bang_impl :: #force_inline proc(xs: []$T) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__reverse_bang_impl((mutable)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__filter_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "filtered := arr__filter_impl(even_value_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__remove_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "removed := arr__remove_impl(even_value_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__keep_impl :: #force_inline proc(f: proc(x: $T) -> (value: $U, ok: bool), xs: []T) -> [dynamic]U {"), true)
    testing.expect_value(t, strings.contains(output, "kept := arr__keep_impl(keep_even, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__mapcat_impl :: #force_inline proc(f: proc(x: $T) -> []$U, xs: []T) -> [dynamic]U {"), true)
    testing.expect_value(t, strings.contains(output, "flattened := arr__mapcat_impl(pair, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__count_by_impl :: #force_inline proc(f: proc(x: $T) -> $K, xs: []T) -> map[K]int {"), true)
    testing.expect_value(t, strings.contains(output, "counted := arr__count_by_impl(even_value_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__shuffle_impl :: #force_inline proc(pick: proc(n: int) -> int, xs: []$T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "shuffled := arr__shuffle_impl(pick_first, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__sort_impl :: #force_inline proc(xs: []$T) -> [dynamic]T {"), true)
    testing.expect_value(t, strings.contains(output, "kvist_slice.sort((out)[:])"), true)
    testing.expect_value(t, strings.contains(output, "import kvist_slice \"core:slice\""), true)
    testing.expect_value(t, strings.contains(output, "sorted := arr__sort_impl((xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "kvist_thread_1 := arr__mapcat_impl(pair, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(kvist_thread_1)"), true)
    testing.expect_value(t, strings.contains(output, "threaded_flat_count := len("), true)
    testing.expect_value(t, strings.contains(output, "arr__mapcat_impl(pair,"), true)
    testing.expect_value(t, strings.contains(output, "arr__reduce_impl :: #force_inline proc(f: proc(acc: $U, x: $T) -> U, init: U, xs: []T) -> U {"), true)
    testing.expect_value(t, strings.contains(output, "reduced := arr__reduce_impl(add_values, 0, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__take_while_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> []T {"), true)
    testing.expect_value(t, strings.contains(output, "arr__drop_while_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> []T {"), true)
    testing.expect_value(t, strings.contains(output, "small_prefix := arr__take_while_impl(big_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "large_suffix := arr__drop_while_impl(big_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__find_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> (value: T, ok: bool) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__some_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "arr__every_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: []T) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "first_big, found_big_p := arr__find_impl(big_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "any_big_p := arr__some_impl(big_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "all_big_p := arr__every_impl(big_p, (xs)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "append(&mutable, total)"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_bang_impl :: #force_inline proc(f: proc(x: $T) -> T, xs: []T) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__map_bang_impl(inc_value, (mutable)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__filter_bang_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: ^[dynamic]T) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__filter_bang_impl(even_value_p, &mutable)"), true)
    testing.expect_value(t, strings.contains(output, "arr__remove_bang_impl :: #force_inline proc(pred: proc(x: $T) -> bool, xs: ^[dynamic]T) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__remove_bang_impl(even_value_p, &mutable)"), true)
    testing.expect_value(t, strings.contains(output, "arr__keep_bang_impl :: #force_inline proc(f: proc(x: $T) -> (value: T, ok: bool), xs: ^[dynamic]T) {"), true)
    testing.expect_value(t, strings.contains(output, "arr__keep_bang_impl(keep_even, &mutable)"), true)
    testing.expect_value(t, strings.contains(output, "arr__shuffle_bang_impl(pick_first, (mutable)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "arr__sort_bang_impl((mutable)[0:])"), true)
    testing.expect_value(t, strings.contains(output, "tail := (xs)[1:]"), true)
    testing.expect_value(t, strings.contains(output, "init := arr__butlast(xs)"), true)
    testing.expect_value(t, strings.contains(output, "arr__take_nth_next(&kvist_source)"), true)
    testing.expect_value(t, strings.contains(output, "arr__cycle_next(&kvist_source)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_out := make([dynamic]int)"), true)
    testing.expect_value(t, strings.contains(output, "return (xs)[0:i]"), true)
    testing.expect_value(t, strings.contains(output, "return (xs)[i:]"), true)
    testing.expect_value(t, strings.contains(output, "fmt.println(len(fixed), total, first_by_get, a, b, c, z, first_big, found_big_p, any_big_p, all_big_p"), true)
    testing.expect_value(t, strings.contains(output, "kvist_range"), false)
    testing.expect_value(t, strings.contains(output, "kvist_map("), false)
    testing.expect_value(t, strings.contains(output, "kvist_map_indexed"), false)
    testing.expect_value(t, strings.contains(output, "kvist_filter("), false)
    testing.expect_value(t, strings.contains(output, "kvist_remove("), false)
    testing.expect_value(t, strings.contains(output, "kvist_keep("), false)
    testing.expect_value(t, strings.contains(output, "kvist_map_in_place("), false)
    testing.expect_value(t, strings.contains(output, "kvist_filter_in_place("), false)
    testing.expect_value(t, strings.contains(output, "kvist_remove_in_place("), false)
    testing.expect_value(t, strings.contains(output, "kvist_keep_in_place("), false)
    testing.expect_value(t, strings.contains(output, "kvist_count_by("), false)
    testing.expect_value(t, strings.contains(output, "kvist_shuffle("), false)
    testing.expect_value(t, strings.contains(output, "kvist_sort("), false)
    testing.expect_value(t, strings.contains(output, "kvist_mapcat"), false)
    testing.expect_value(t, strings.contains(output, "kvist_reduce("), false)
    testing.expect_value(t, strings.contains(output, "kvist_take_nth"), false)
    testing.expect_value(t, strings.contains(output, "kvist_repeat"), false)
    testing.expect_value(t, strings.contains(output, "kvist_repeatedly"), false)
    testing.expect_value(t, strings.contains(output, "kvist_iterate"), false)
    testing.expect_value(t, strings.contains(output, "kvist_cycle"), false)
    testing.expect_value(t, strings.contains(output, "kvist_take_while"), false)
    testing.expect_value(t, strings.contains(output, "kvist_drop_while"), false)
    testing.expect_value(t, strings.contains(output, "kvist_find"), false)
    testing.expect_value(t, strings.contains(output, "kvist_some_p"), false)
    testing.expect_value(t, strings.contains(output, "kvist_every_p"), false)
}
