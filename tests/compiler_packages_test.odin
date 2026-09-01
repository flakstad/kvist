package tests

import "base:runtime"
import fmt "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import kvist "../src/odin/kvist"

@(test)
compiler_entry_type_parts_are_package_neutral :: proc(t: ^testing.T) {
    key_ty, value_ty, ok := kvist.entry_type_parts("third_party.entry(string, map[int]string)")
    testing.expect_value(t, ok, true)
    testing.expect_value(t, key_ty, "string")
    testing.expect_value(t, value_ty, "map[int]string")

    _, _, ok = kvist.entry_type_parts("map__raw.pair(string, int)")
    testing.expect_value(t, ok, false)
}

@(test)
compile_explicit_core_package_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import core "kvist:core")

(defn main []
    (let [xs [1 2 3]
        lookup {"one" 1}]
    (println (count xs)
             (empty? xs)
             (contains? xs 2)
             (contains? lookup "one"))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "len(xs)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_contains_value((xs)[:], 2)"), true)
    testing.expect_value(t, strings.contains(output, "(\"one\") in (lookup)"), true)
}

@(test)
compile_source_package_can_use_mutating_odin_target :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-mut-target-package-*", context.allocator)
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

(defmacro drop-key! [target key]
  (quasiquote
    (delete_key (mut (unquote target)) (unquote key))))`
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

(defn local! []
  (let [lookup (map[string]int {"a" 1}) :defer]
    (support.drop-key! lookup "a")))

(defn borrowed! [lookup: ^map[string]int]
  (support.drop-key! lookup "b"))`
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

    testing.expect_value(t, strings.contains(result.output, "delete_key(&(lookup), \"a\")"), true)
    testing.expect_value(t, strings.contains(result.output, "delete_key(lookup, \"b\")"), true)
    testing.expect_value(t, strings.contains(result.output, "kvist_prim_delete"), false)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_source_package_can_use_odin_infix_or_else :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-or-else-package-*", context.allocator)
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

(defmacro fallback [expr value]
  (quasiquote
    (odin-infix "or_else" (unquote expr) (unquote value))))`
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

(defn query [] -> [value: int, ok: bool] #optional_ok
  (return 42 true))

(defn total [] -> int
  (support.fallback (query) 7))`
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

    testing.expect_value(t, strings.contains(result.output, "return (query()) or_else (7)"), true)
    testing.expect_value(t, strings.contains(result.output, "kvist_prim_or_else"), false)
    testing.expect_value(t, len(result.warnings), 0)
}

@(test)
compile_source_package_can_use_thread_start :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-thread-start-package-*", context.allocator)
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

(odin "support_Task :: struct($T: typeid) {
    result: chan.Chan(T),
    thread: ^thread.Thread,
    data: rawptr,
}")

(defmacro start
  [worker & args]
  (quasiquote
    (thread-start support_Task (unquote worker) (splice args))))

(defn result
  [task: (support_Task $T)] -> T #force_inline
  (let [[value ok] (chan.recv task.result)]
    (thread.join task.thread)
    (thread.destroy task.thread)
    (free task.data)
    (chan.destroy task.result)
    (assert ok "task ended without a result")
    value))`
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

(defn square [x: int] -> int
  (* x x))

(defn demo [] -> int
  (support.result (support.start square 6)))`
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

    testing.expect_value(t, strings.contains(output, "import chan \"core:sync/chan\""), true)
    testing.expect_value(t, strings.contains(output, "import thread \"core:thread\""), true)
    testing.expect_value(t, strings.contains(output, "support_Task :: struct($T: typeid)"), true)
    testing.expect_value(t, strings.contains(output, "return support__result(thread_start_square_int_int(6))"), true)
    testing.expect_value(t, strings.contains(output, "thread_Start_Data_square_int_int :: struct"), true)
    testing.expect_value(t, strings.contains(output, "thread_start_square_int_int :: proc(x: int) -> support_Task(int)"), true)
    testing.expect_value(t, strings.contains(output, "return support_Task(int){result = result, thread = task_thread, data = data}"), true)
    testing.expect_value(t, strings.contains(output, "parallel_Task"), false)
    testing.expect_value(t, strings.contains(output, "kvist:parallel"), false)
}

@(test)
compile_source_package_can_use_thread_detach :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-thread-detach-package-*", context.allocator)
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

(defmacro later
  [worker & args]
  (quasiquote
    (thread-detach (unquote worker) (splice args))))`
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

(defn notify [user-id: int]
  (println user-id))

(defn demo []
  (support.later notify 42))`
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

    testing.expect_value(t, strings.contains(output, "import thread \"core:thread\""), true)
    testing.expect_value(t, strings.contains(output, "thread_detach_notify_int(42)"), true)
    testing.expect_value(t, strings.contains(output, "thread_Detach_Data_notify_int :: struct"), true)
    testing.expect_value(t, strings.contains(output, "thread.create_and_start_with_poly_data(data, thread_detach_worker_notify_int, nil, .Normal, true)"), true)
    testing.expect_value(t, strings.contains(output, "parallel_detach"), false)
    testing.expect_value(t, strings.contains(output, "kvist:parallel"), false)
}

@(test)
compile_source_package_thread_start_specializes_generic_proc_argument :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-thread-start-generic-package-*", context.allocator)
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
(import chan "core:sync/chan")
(import thread "core:thread")

(odin "support_Task :: struct($T: typeid) {
    result: chan.Chan(T),
    thread: ^thread.Thread,
    data: rawptr,
}")

(defn result [task: (support_Task $T)] -> T #force_inline
  (let [[value ok] (chan.recv task.result)]
    (thread.join task.thread)
    (thread.destroy task.thread)
    (free task.data)
    (chan.destroy task.result)
    (assert ok "support task ended without result")
    value))

(defn worker [f: (fn [x: $T] -> $U), x: T] -> U
  (f x))

(defmacro run-one [f x]
  (quasiquote
    (result (thread-start support_Task worker (unquote f) (unquote x)))))`
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

(defn inc-one [x: int] -> int
  (+ x 1))

(defn demo [x: int] -> int
  (support.run-one inc-one x))

(defn main []
  (println (demo 4)))`
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

    testing.expect_value(t, strings.contains(output, "f: proc(x: int) -> int,"), true)
    testing.expect_value(t, strings.contains(output, "result: chan.Chan(int),"), true)
    testing.expect_value(t, strings.contains(output, "x: int,"), true)
    testing.expect_value(t, strings.contains(output, "$int"), false)

    odin_dir, odin_dir_err := os.join_path({dir, "generated"}, context.allocator)
    testing.expect_value(t, odin_dir_err == nil, true)
    if odin_dir_err != nil {
        return
    }
    defer delete(odin_dir)
    mk_odin_err := os.make_directory_all(odin_dir)
    testing.expect_value(t, mk_odin_err == nil, true)
    if mk_odin_err != nil {
        return
    }
    odin_path, odin_path_err := os.join_path({odin_dir, "main.odin"}, context.allocator)
    testing.expect_value(t, odin_path_err == nil, true)
    if odin_path_err != nil {
        return
    }
    defer delete(odin_path)
    odin_write_err := os.write_entire_file_from_string(odin_path, output)
    testing.expect_value(t, odin_write_err == nil, true)
    if odin_write_err != nil {
        return
    }

    repo_root := compiler_test_repo_root()
    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command     = {"odin", "check", odin_dir},
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
compile_source_package_can_build_parallel_collection_helpers_with_thread_start :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-thread-collection-package-*", context.allocator)
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
(import chan "core:sync/chan")
(import os "core:os")
(import thread "core:thread")

(odin "support_Task :: struct($T: typeid) {
    result: chan.Chan(T),
    thread: ^thread.Thread,
    data: rawptr,
}")

(defn- result
  [task: (support_Task $T)] -> T #force_inline
  (let [[value ok] (chan.recv task.result)]
    (thread.join task.thread)
    (thread.destroy task.thread)
    (free task.data)
    (chan.destroy task.result)
    (assert ok "support task ended without result")
    value))

(defn- worker-count
  [requested: int, n: int] -> int #force_inline
  (let [worker-count requested]
    (when (<= worker-count 0)
      (set! worker-count (- (os.get_processor_core_count) 1)))
    (when (> worker-count n)
      (set! worker-count n))
    (when (< worker-count 1)
      (set! worker-count 1))
    worker-count))

(defn- map-worker
  [f: (fn [x: $T] -> $U), xs: []T, out: (ptr (dynamic U)), start: int, step: int] -> bool
  (let [i start]
    (while (< i (count xs))
      (set! (deref out)[i] (f xs[i]))
      (set! i (+ i step)))
    true))

(defn- map-impl
  [f: (fn [x: $T] -> $U), xs: []T, requested-workers: int] -> [dynamic]U #force_inline
  (let [out (make [dynamic]U (count xs))]
    (when (= (count xs) 0)
      (return out))
    (let [workers (worker-count requested-workers (count xs))
          tasks (make (dynamic (support_Task bool)) 0 workers) :defer
          i 0]
      (while (< i workers)
        (append (addr tasks) (thread-start support_Task map-worker f xs (addr out) i workers))
        (set! i (+ i 1)))
      (set! i 0)
      (while (< i (count tasks))
        (discard (result tasks[i]))
        (set! i (+ i 1))))
    out))

(defn- for-worker
  [f: (fn [x: $T]), xs: []T, start: int, step: int] -> bool
  (let [i start]
    (while (< i (count xs))
      (f xs[i])
      (set! i (+ i step)))
    true))

(defn- for-impl
  [f: (fn [x: $T]), xs: []T, requested-workers: int] #force_inline
  (when (= (count xs) 0)
    (return))
  (let [workers (worker-count requested-workers (count xs))
        tasks (make (dynamic (support_Task bool)) 0 workers) :defer
        i 0]
    (while (< i workers)
      (append (addr tasks) (thread-start support_Task for-worker f xs i workers))
      (set! i (+ i 1)))
    (set! i 0)
    (while (< i (count tasks))
      (discard (result tasks[i]))
      (set! i (+ i 1)))))

(defmacro map-workers
  [worker xs]
  (quasiquote
    (map-impl (unquote worker) (unquote xs) 0)))

(defmacro for-workers
  [worker xs]
  (quasiquote
    (for-impl (unquote worker) (unquote xs) 0)))`
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

(defn observe [x: int]
  (println x))

(defn mapped [xs: []int] -> [dynamic]int
  (let [offset 10]
    (support.map-workers
      (fn [x: int] -> int
        (+ x offset))
      xs)))

(defn observe-all [xs: []int]
  (support.for-workers observe xs))

(defn main []
  (let [xs ([dynamic]int [1 2 3]) :defer
        ys (mapped xs) :defer]
    (observe-all xs)
    (println (count ys))))`
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

    testing.expect_value(t, strings.contains(output, "import os \"core:os\""), true)
    testing.expect_value(t, strings.contains(output, "support_Task :: struct($T: typeid)"), true)
    testing.expect_value(t, strings.contains(output, "import thread \"core:thread\""), true)
    testing.expect_value(t, strings.contains(output, "support__map_impl__kvist_capture_0_1"), true)
    testing.expect_value(t, strings.contains(output, "support__map_worker__kvist_capture_0_1"), true)
    testing.expect_value(t, strings.contains(output, "proc(offset: int, x: int) -> int {"), true)
    testing.expect_value(t, strings.contains(output, "support__map_worker__kvist_capture_0_1(data.f, data.kvist_capture_1, data.xs, data.out, data.start, data.step)"), true)
    testing.expect_value(t, strings.contains(output, "f(kvist_capture_1, (xs)[i])"), true)
    testing.expect_value(t, strings.contains(output, "support__for_impl(observe, xs, 0)"), true)
    testing.expect_value(t, strings.contains(output, "support__map_impl :: #force_inline proc(f: proc(x: $T) -> $U, xs: []T, requested_workers: int) -> [dynamic]U"), true)
    testing.expect_value(t, strings.contains(output, "support__for_impl :: #force_inline proc(f: proc(x: $T), xs: []T, requested_workers: int)"), true)
    testing.expect_value(t, strings.contains(output, "append(&tasks, thread_start_support__map_worker_"), true)
    testing.expect_value(t, strings.contains(output, "append(&tasks, thread_start_support__for_worker_"), true)
    testing.expect_value(t, strings.contains(output, "kvist:parallel"), false)
    testing.expect_value(t, strings.contains(output, "thread_map_square_int_int"), false)
    testing.expect_value(t, strings.contains(output, "thread_for_observe_int"), false)

    odin_dir, odin_dir_err := os.join_path({dir, "generated"}, context.allocator)
    testing.expect_value(t, odin_dir_err == nil, true)
    if odin_dir_err != nil {
        return
    }
    defer delete(odin_dir)
    mk_odin_err := os.make_directory_all(odin_dir)
    testing.expect_value(t, mk_odin_err == nil, true)
    if mk_odin_err != nil {
        return
    }
    odin_path, odin_path_err := os.join_path({odin_dir, "main.odin"}, context.allocator)
    testing.expect_value(t, odin_path_err == nil, true)
    if odin_path_err != nil {
        return
    }
    defer delete(odin_path)
    odin_write_err := os.write_entire_file_from_string(odin_path, output)
    testing.expect_value(t, odin_write_err == nil, true)
    if odin_write_err != nil {
        return
    }

    repo_root := compiler_test_repo_root()
    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command     = {"odin", "check", odin_dir},
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
compile_arr_package_indexed_and_reduce_helpers_support_captured_callbacks :: proc(t: ^testing.T) {
    source := "(package main)\n(import arr \"kvist:arr\")\n\n(defn demo [xs: []int] -> int\n  (let [offset 10\n        mapped (arr.map-indexed (fn [i: int, x: int] -> int (+ x i offset)) xs) :defer\n        total (arr.reduce (fn [acc: int, x: int] -> int (+ acc x offset)) 0 xs)\n        indexed-total (arr.reduce-indexed (fn [acc: int, i: int, x: int] -> int (+ acc x i offset)) 0 xs)]\n    (+ (arr.last mapped) total indexed-total)))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "arr__map_indexed__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "arr__reduce_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "arr__reduce_indexed_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "proc(c1: $C1, i: int, x: $T) -> $U"), true)
    testing.expect_value(t, strings.contains(output, "proc(c1: $C1, acc: $U, x: $T) -> U"), true)
    testing.expect_value(t, strings.contains(output, "proc(c1: $C1, acc: $U, i: int, x: $T) -> U"), true)
}

@(test)
compile_arr_package_scan_helpers_support_captured_callbacks :: proc(t: ^testing.T) {
    source := "(package main)\n(import arr \"kvist:arr\")\n\n(defn demo [xs: []int] -> bool\n  (let [limit 3\n        [found found?] (arr.find (fn [x: int] -> bool (> x limit)) xs)\n        [index indexed-value indexed?] (arr.find-indexed (fn [i: int, x: int] -> bool (and (> x limit) (>= i 0))) xs)\n        [smallest smallest?] (arr.min-by (fn [x: int] -> int (+ x limit)) xs)\n        [largest largest?] (arr.max-by (fn [x: int] -> int (+ x limit)) xs)]\n    (and (= (count (arr.take-while (fn [x: int] -> bool (< x limit)) xs)) 2)\n         (= (count (arr.drop-while (fn [x: int] -> bool (< x limit)) xs)) 2)\n         found? indexed? smallest? largest?\n         (= found 4)\n         (= indexed-value 4)\n         (= smallest 1)\n         (= largest 4)\n         (arr.some? (fn [x: int] -> bool (> x limit)) xs)\n         (not (arr.every? (fn [x: int] -> bool (> x limit)) xs)))))"

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "arr__take_while_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "arr__drop_while_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "arr__find_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "arr__find_indexed_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "arr__min_by_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "arr__max_by_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "arr__some_impl__kvist_capture_0_1("), true)
    testing.expect_value(t, strings.contains(output, "arr__every_impl__kvist_capture_0_1("), true)
}

@(test)
lower_rejects_missing_package :: proc(t: ^testing.T) {
    source := `(defn main []
  (return))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    formatted := kvist.format_compile_error("bad.kvist", source, err)
    defer delete(formatted)
    expected := `bad.kvist:1:1: missing package declaration
  (defn main []
  ^
`
    testing.expect_value(t, formatted, expected)
}

@(test)
compile_path_defaults_missing_package_to_main :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-test-*", context.allocator)
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

    source := `(defn main []
  (println "hello"))`
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

    testing.expect_value(t, strings.contains(output, "package main"), true)
    testing.expect_value(t, strings.contains(output, "main :: proc()"), true)
}

@(test)
compile_source_package_preserves_type_forms_in_proc_signatures :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-package-type-forms-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    pkg_dir, join_pkg_err := os.join_path({dir, "support", "groups"}, context.allocator)
    testing.expect_value(t, join_pkg_err == nil, true)
    if join_pkg_err != nil {
        return
    }
    defer delete(pkg_dir)
    mk_pkg_err := os.make_directory_all(pkg_dir)
    testing.expect_value(t, mk_pkg_err == nil, true)
    if mk_pkg_err != nil {
        return
    }

    pkg_file, pkg_join_err := os.join_path({pkg_dir, "groups.kvist"}, context.allocator)
    testing.expect_value(t, pkg_join_err == nil, true)
    if pkg_join_err != nil {
        return
    }
    defer delete(pkg_file)
    pkg_source := `(package groups)

(defn make-groups [] -> (map string (dynamic int))
  (let [out (make map[string][dynamic]int)
        group (make [dynamic]int 0 2)]
    (append (addr group) 1)
    (set! out["a"] group)
    out))`
    pkg_write_err := os.write_entire_file_from_string(pkg_file, pkg_source)
    testing.expect_value(t, pkg_write_err == nil, true)
    if pkg_write_err != nil {
        return
    }

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(import groups "support/groups")

(defn main [] -> int
  (let [groups (groups.make-groups)]
    (count groups)))`
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

    testing.expect_value(t, strings.contains(output, "groups__make_groups :: proc() -> map[string][dynamic]int"), true)
    testing.expect_value(t, strings.contains(output, "out := make(map[string][dynamic]int)"), true)
    testing.expect_value(t, strings.contains(output, "group := make([dynamic]int, 0, 2)"), true)
    testing.expect_value(t, strings.contains(output, "groups__dynamic"), false)
}

@(test)
compile_source_package_function_names_do_not_shadow_builtin_signature_types :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-package-builtin-type-shadow-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    pkg_dir, join_pkg_err := os.join_path({dir, "data"}, context.allocator)
    testing.expect_value(t, join_pkg_err == nil, true)
    if join_pkg_err != nil {
        return
    }
    defer delete(pkg_dir)
    mk_pkg_err := os.make_directory_all(pkg_dir)
    testing.expect_value(t, mk_pkg_err == nil, true)
    if mk_pkg_err != nil {
        return
    }

    pkg_file, pkg_join_err := os.join_path({pkg_dir, "data.kvist"}, context.allocator)
    testing.expect_value(t, pkg_join_err == nil, true)
    if pkg_join_err != nil {
        return
    }
    defer delete(pkg_file)
    pkg_source := `(package data)

(defn int [value: Data] -> i64
  42)

(defn bool [value: Data] -> bool
  true)

(defn string [value: Data] -> string
  "data")`
    pkg_write_err := os.write_entire_file_from_string(pkg_file, pkg_source)
    testing.expect_value(t, pkg_write_err == nil, true)
    if pkg_write_err != nil {
        return
    }

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package main)
(import data "data")

(def value '42)

(defn main [] -> bool
  (and (= (data.int value) 42)
       (data.bool value)
       (= (data.string value) "data")))`
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

    testing.expect_value(t, strings.contains(output, "data__int :: proc(value: Data) -> i64"), true)
    testing.expect_value(t, strings.contains(output, "data__bool :: proc(value: Data) -> bool"), true)
    testing.expect_value(t, strings.contains(output, "data__string :: proc(value: Data) -> string"), true)
    testing.expect_value(t, strings.contains(output, "-> data__bool"), false)
    testing.expect_value(t, strings.contains(output, "-> data__string"), false)
}

@(test)
compile_source_package_can_define_set_type_name :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-package-set-type-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    pkg_dir, join_pkg_err := os.join_path({dir, "support"}, context.allocator)
    testing.expect_value(t, join_pkg_err == nil, true)
    if join_pkg_err != nil {
        return
    }
    defer delete(pkg_dir)
    mk_pkg_err := os.make_directory_all(pkg_dir)
    testing.expect_value(t, mk_pkg_err == nil, true)
    if mk_pkg_err != nil {
        return
    }

    pkg_file, pkg_join_err := os.join_path({pkg_dir, "support.kvist"}, context.allocator)
    testing.expect_value(t, pkg_join_err == nil, true)
    if pkg_join_err != nil {
        return
    }
    defer delete(pkg_file)
    pkg_source := `(package support)

(def set (distinct int))

(defn wrap [value: int] -> set
  (set value))`
    pkg_write_err := os.write_entire_file_from_string(pkg_file, pkg_source)
    testing.expect_value(t, pkg_write_err == nil, true)
    if pkg_write_err != nil {
        return
    }

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package main)
(import support "support")

(defn main [] -> int
  (int (support.wrap 42)))`
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

    testing.expect_value(t, strings.contains(output, "support__set :: distinct int"), true)
    testing.expect_value(t, strings.contains(output, "support__wrap :: proc(value: int) -> support__set"), true)
    testing.expect_value(t, strings.contains(output, "return support__set(value)"), true)
    testing.expect_value(t, strings.contains(output, "-> set"), false)
}

@(test)
compile_source_package_rewrites_overload_members :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-package-overload-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    pkg_dir, join_pkg_err := os.join_path({dir, "support"}, context.allocator)
    testing.expect_value(t, join_pkg_err == nil, true)
    if join_pkg_err != nil {
        return
    }
    defer delete(pkg_dir)
    mk_pkg_err := os.make_directory_all(pkg_dir)
    testing.expect_value(t, mk_pkg_err == nil, true)
    if mk_pkg_err != nil {
        return
    }

    pkg_file, pkg_join_err := os.join_path({pkg_dir, "support.kvist"}, context.allocator)
    testing.expect_value(t, pkg_join_err == nil, true)
    if pkg_join_err != nil {
        return
    }
    defer delete(pkg_file)
    pkg_source := `(package support)
(import fmt "core:fmt")

(defn render-int [value: int] -> string
  (fmt.aprintf "int:%d" value))

(defn render-string [value: string] -> string
  (fmt.aprintf "string:%s" value))

(def render (overload render-int render-string))

(defn render-supported [value: $T] -> string
  (render value))`
    pkg_write_err := os.write_entire_file_from_string(pkg_file, pkg_source)
    testing.expect_value(t, pkg_write_err == nil, true)
    if pkg_write_err != nil {
        return
    }

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package main)
(import support "support")

(defn main [] -> string
  (support.render-supported 42))`
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

    testing.expect_value(t, strings.contains(output, "support__render :: proc{support__render_int, support__render_string}"), true)
    testing.expect_value(t, strings.contains(output, "return support__render(value)"), true)
}

@(test)
compile_source_package_rewrites_typed_decl_names :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-package-typed-decls-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    pkg_dir, join_pkg_err := os.join_path({dir, "support"}, context.allocator)
    testing.expect_value(t, join_pkg_err == nil, true)
    if join_pkg_err != nil {
        return
    }
    defer delete(pkg_dir)
    mk_pkg_err := os.make_directory_all(pkg_dir)
    testing.expect_value(t, mk_pkg_err == nil, true)
    if mk_pkg_err != nil {
        return
    }

    pkg_file, pkg_join_err := os.join_path({pkg_dir, "support.kvist"}, context.allocator)
    testing.expect_value(t, pkg_join_err == nil, true)
    if pkg_join_err != nil {
        return
    }
    defer delete(pkg_file)
    pkg_source := `(package support)

(defvar state: int)

(defn set-state [value: int]
  (set! state value))

(defn get-state [] -> int
  state)`
    pkg_write_err := os.write_entire_file_from_string(pkg_file, pkg_source)
    testing.expect_value(t, pkg_write_err == nil, true)
    if pkg_write_err != nil {
        return
    }

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package main)
(import support "support")

(defn main [] -> int
  (support.set-state 42)
  (support.get-state))`
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

    testing.expect_value(t, strings.contains(output, "support__state: int"), true)
    testing.expect_value(t, strings.contains(output, "support__state = value"), true)
    testing.expect_value(t, strings.contains(output, "return support__state"), true)
}

@(test)
compile_source_package_rewrites_compact_types_and_keeps_enum_variants :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-source-package-compact-types-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    pkg_dir, join_pkg_err := os.join_path({dir, "model"}, context.allocator)
    testing.expect_value(t, join_pkg_err == nil, true)
    if join_pkg_err != nil {
        return
    }
    defer delete(pkg_dir)
    mk_pkg_err := os.make_directory_all(pkg_dir)
    testing.expect_value(t, mk_pkg_err == nil, true)
    if mk_pkg_err != nil {
        return
    }

    pkg_file, pkg_join_err := os.join_path({pkg_dir, "model.kvist"}, context.allocator)
    testing.expect_value(t, pkg_join_err == nil, true)
    if pkg_join_err != nil {
        return
    }
    defer delete(pkg_file)
    pkg_source := `(package model)

(defenum Term-Kind [Value Var])

(defstruct Value {
  text: string
})

(defstruct Item {
  value: Value
})

(defstruct Box {
  items: [dynamic]Item
  kind: Term-Kind
})

(defn make-box [] -> Box
  (Box {items: (make [dynamic]Item)
        kind: .Value}))

(defn count-items [box: Box, items: []Item] -> int
  (+ (count box.items) (count items)))`
    pkg_write_err := os.write_entire_file_from_string(pkg_file, pkg_source)
    testing.expect_value(t, pkg_write_err == nil, true)
    if pkg_write_err != nil {
        return
    }

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(package main)
(import m "model")

(defn main [] -> int
  (let [box (m.make-box)
        items ([]m.Item [])]
    (m.count-items box items)))`
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

    testing.expect_value(t, strings.contains(output, "items: [dynamic]m__Item"), true)
    testing.expect_value(t, strings.contains(output, "count_items :: proc(box: m__Box, items: []m__Item) -> int"), true)
    testing.expect_value(t, strings.contains(output, "items := []m__Item{}"), true)
    testing.expect_value(t, strings.contains(output, "m__Term_Kind :: enum {\n    Value,\n    Var,"), true)
    testing.expect_value(t, strings.contains(output, "kind = .Value"), true)
}

@(test)
compile_path_rejects_private_source_package_member_access :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-private-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    pkg_dir, join_pkg_err := os.join_path({dir, "support", "secret"}, context.allocator)
    testing.expect_value(t, join_pkg_err == nil, true)
    if join_pkg_err != nil {
        return
    }
    defer delete(pkg_dir)
    mk_pkg_err := os.make_directory_all(pkg_dir)
    testing.expect_value(t, mk_pkg_err == nil, true)
    if mk_pkg_err != nil {
        return
    }

    pkg_file, pkg_join_err := os.join_path({pkg_dir, "secret.kvist"}, context.allocator)
    testing.expect_value(t, pkg_join_err == nil, true)
    if pkg_join_err != nil {
        return
    }
    defer delete(pkg_file)
    pkg_source := `(package secret)

(def- hidden-value 42)

(defn- hidden [] -> int
  42)

(defn visible [] -> int
  7)`
    pkg_write_err := os.write_entire_file_from_string(pkg_file, pkg_source)
    testing.expect_value(t, pkg_write_err == nil, true)
    if pkg_write_err != nil {
        return
    }

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(import secret "support/secret")

(defn main []
  (println secret.hidden-value))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    _, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "source package member is private or undefined: secret.hidden-value"), true)
}

@(test)
compile_path_rejects_mismatched_package_names_in_directory :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-mismatch-package-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    pkg_dir, pkg_join_err := os.join_path({dir, "support", "mixed"}, context.allocator)
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

    one_file, one_join_err := os.join_path({pkg_dir, "one.kvist"}, context.allocator)
    testing.expect_value(t, one_join_err == nil, true)
    if one_join_err != nil {
        return
    }
    defer delete(one_file)
    one_write_err := os.write_entire_file_from_string(one_file, `(package mixed)

(defn one [] -> int
  1)`)
    testing.expect_value(t, one_write_err == nil, true)
    if one_write_err != nil {
        return
    }

    two_file, two_join_err := os.join_path({pkg_dir, "two.kvist"}, context.allocator)
    testing.expect_value(t, two_join_err == nil, true)
    if two_join_err != nil {
        return
    }
    defer delete(two_file)
    two_write_err := os.write_entire_file_from_string(two_file, `(package other)

(defn two [] -> int
  2)`)
    testing.expect_value(t, two_write_err == nil, true)
    if two_write_err != nil {
        return
    }

    main_path, main_join_err := os.join_path({dir, "main.kvist"}, context.allocator)
    testing.expect_value(t, main_join_err == nil, true)
    if main_join_err != nil {
        return
    }
    defer delete(main_path)
    main_source := `(import mixed "support/mixed")

(defn main []
  (mixed/one))`
    main_write_err := os.write_entire_file_from_string(main_path, main_source)
    testing.expect_value(t, main_write_err == nil, true)
    if main_write_err != nil {
        return
    }

    _, err, ok := kvist.compile_path(main_path)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "source package files must declare the same package"), true)
}

@(test)
lower_rejects_duplicate_package :: proc(t: ^testing.T) {
    source := `(package main)
(package other)
(defn main []
  (return))`

    _, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, false)
    if ok {
        return
    }
    defer delete(err.message)

    formatted := kvist.format_compile_error("bad.kvist", source, err)
    defer delete(formatted)
    expected := `bad.kvist:2:1: package declaration must appear exactly once
  (package other)
  ^
`
    testing.expect_value(t, formatted, expected)
}

@(test)
compile_string_package_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import str "kvist:str")

(defn demo []
  (let [name "  Kvist Core  "
        parts (str.split "a,b,c" ",")
        joined (str.join parts "-")
        trimmed (str.trim name)
        without-prefix (str.trim-prefix "kvist.core" "kvist.")
        without-suffix (str.trim-suffix "kvist.txt" ".txt")
        starts? (str.starts-with? without-prefix "co")
        ends? (str.ends-with? without-suffix "st")
        first-dash (str.index-of joined "-")
        last-dash (str.last-index-of joined "-")
        replaced-all (str.replace joined "-" "_")
        replaced-one (str.replace joined "-" "_" 1)
        lowered (str.lower replaced-all)
        uppered (str.upper lowered)
        builder (str.builder)
        unescaped (str.unescape "a\\nb")]
    (defer (delete parts))
    (defer (delete joined))
    (defer (delete replaced-all))
    (defer (delete replaced-one))
    (defer (delete lowered))
    (defer (delete uppered))
    (defer (delete unescaped))
    (defer (str.destroy! (addr builder)))
    (str.write! (addr builder) "hi")
    (str.write! (addr builder) "!")
    (let [built (str.finish (addr builder))]
      (defer (delete built))
      (println trimmed without-prefix without-suffix starts? ends? first-dash last-dash uppered built unescaped))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "import strings \"core:strings\""), true)
    testing.expect_value(t, strings.contains(output, "str__split :: #force_inline proc(s, separator: string) -> []string {"), true)
    testing.expect_value(t, strings.contains(output, "return strings.split(s, separator)"), true)
    testing.expect_value(t, strings.contains(output, "str__join_impl :: #force_inline proc(parts: []string, separator: string) -> string {"), true)
    testing.expect_value(t, strings.contains(output, "str__builder := strings.builder_make()"), true)
    testing.expect_value(t, strings.contains(output, "defer strings.builder_destroy(&str__builder)"), true)
    testing.expect_value(t, strings.contains(output, "strings.write_string(&str__builder, separator)"), true)
    testing.expect_value(t, strings.contains(output, "strings.write_string(&str__builder, parts[i])"), true)
    testing.expect_value(t, strings.contains(output, "out, err := strings.clone(strings.to_string(str__builder))"), true)
    testing.expect_value(t, strings.contains(output, "#owned"), false)
    testing.expect_value(t, strings.contains(output, "parts := str__split(\"a,b,c\", \",\")"), true)
    testing.expect_value(t, strings.contains(output, "joined := str__join_impl((parts)[0:], \"-\")"), true)
    testing.expect_value(t, strings.contains(output, "str__trim :: #force_inline proc(s: string) -> string {"), true)
    testing.expect_value(t, strings.contains(output, "start := strings.index_proc(s, strings.is_space, false)"), true)
    testing.expect_value(t, strings.contains(output, "_, width := utf8.decode_rune_in_string((s)[last:])"), true)
    testing.expect_value(t, strings.contains(output, "return (s)[start:(last) + (width)]"), true)
    testing.expect_value(t, strings.contains(output, "#borrowed"), false)
    testing.expect_value(t, strings.contains(output, "str__starts_with_p :: #force_inline proc(s, prefix: string) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, "return strings.has_prefix(s, prefix)"), true)
    testing.expect_value(t, strings.contains(output, "trimmed := str__trim(name)"), true)
    testing.expect_value(t, strings.contains(output, "without_prefix := str__trim_prefix(\"kvist.core\", \"kvist.\")"), true)
    testing.expect_value(t, strings.contains(output, "without_suffix := str__trim_suffix(\"kvist.txt\", \".txt\")"), true)
    testing.expect_value(t, strings.contains(output, "starts_p := str__starts_with_p(without_prefix, \"co\")"), true)
    testing.expect_value(t, strings.contains(output, "ends_p := str__ends_with_p(without_suffix, \"st\")"), true)
    testing.expect_value(t, strings.contains(output, "first_dash := str__index_of(joined, \"-\")"), true)
    testing.expect_value(t, strings.contains(output, "last_dash := str__last_index_of(joined, \"-\")"), true)
    testing.expect_value(t, strings.contains(output, "str__replace_impl :: #force_inline proc(s, old, new: string, n: int) -> string {"), true)
	testing.expect_value(t, strings.contains(output, "out, allocated := strings.replace(s, old, new, n)"), true)
	testing.expect_value(t, strings.contains(output, "if allocated {"), true)
	testing.expect_value(t, strings.contains(output, "owned, err := strings.clone(out)"), true)
    testing.expect_value(t, strings.contains(output, "replaced_all := str__replace_impl(joined, \"-\", \"_\", -1)"), true)
    testing.expect_value(t, strings.contains(output, "replaced_one := str__replace_impl(joined, \"-\", \"_\", 1)"), true)
    testing.expect_value(t, strings.contains(output, "str__lower :: #force_inline proc(s: string) -> string {"), true)
    testing.expect_value(t, strings.contains(output, "return strings.to_lower(s)"), true)
    testing.expect_value(t, strings.contains(output, "#owned"), false)
    testing.expect_value(t, strings.contains(output, "lowered := str__lower(replaced_all)"), true)
    testing.expect_value(t, strings.contains(output, "uppered := str__upper(lowered)"), true)
    testing.expect_value(t, strings.contains(output, "str__builder :: #force_inline proc() -> strings.Builder {"), true)
    testing.expect_value(t, strings.contains(output, "return strings.builder_make()"), true)
    testing.expect_value(t, strings.contains(output, "str__write_bang :: #force_inline proc(builder: ^strings.Builder, value: string) {"), true)
    testing.expect_value(t, strings.contains(output, "strings.write_string(builder, value)"), true)
    testing.expect_value(t, strings.contains(output, "str__finish :: #force_inline proc(builder: ^strings.Builder) -> string {"), true)
    testing.expect_value(t, strings.contains(output, "out, err := strings.clone(strings.to_string(builder^))"), true)
    testing.expect_value(t, strings.contains(output, "str__destroy_bang :: #force_inline proc(builder: ^strings.Builder) {"), true)
    testing.expect_value(t, strings.contains(output, "strings.builder_destroy(builder)"), true)
    testing.expect_value(t, strings.contains(output, "builder := str__builder()"), true)
    testing.expect_value(t, strings.contains(output, "str__write_bang(&builder, \"hi\")"), true)
    testing.expect_value(t, strings.contains(output, "built := str__finish(&builder)"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(built)"), true)
    testing.expect_value(t, strings.contains(output, "defer str__destroy_bang(&builder)"), true)
    testing.expect_value(t, strings.contains(output, "str__unescape :: #force_inline proc(s: string) -> string {"), true)
    testing.expect_value(t, strings.contains(output, "str__builder := strings.builder_make()"), true)
    testing.expect_value(t, strings.contains(output, "defer strings.builder_destroy(&str__builder)"), true)
    testing.expect_value(t, strings.contains(output, "if ((s[i]) == (byte(92))) && (((i) + (1)) < (len(s))) {"), true)
    testing.expect_value(t, strings.contains(output, "strings.write_byte(&str__builder, byte(10))"), true)
    testing.expect_value(t, strings.contains(output, "strings.write_byte(&str__builder, s[i])"), true)
    testing.expect_value(t, strings.contains(output, "out, err := strings.clone(strings.to_string(str__builder))"), true)
    testing.expect_value(t, strings.contains(output, "unescaped := str__unescape(\"a\\\\nb\")"), true)
    testing.expect_value(t, strings.contains(output, "defer delete(unescaped)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_str_unescape"), false)
    testing.expect_value(t, strings.contains(output, "kvist_str_replace :: proc(s, old, new: string, n: int) -> string"), false)
}

@(test)
compile_regex_package_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import re "kvist:regex")

(defn demo [] -> bool
  (and (re.matches? #"\d+" "abc123")
       (not (re.matches? #"^\d+$" "abc123"))))

(defn compiled-demo [] -> bool
  (let [[compiled err] (re.compile #"^a+$")]
    (if (!= err nil)
      false
      (do
        (let [owned-compiled compiled :defer-with re.destroy!]
          (re.matches-compiled? owned-compiled "aaa"))))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, `import rx "core:text/regex"`), true)
    testing.expect_value(t, strings.contains(output, "re__Pattern :: string"), true)
    testing.expect_value(t, strings.contains(output, "re__Regex :: rx.Regular_Expression"), true)
    testing.expect_value(t, strings.contains(output, "re__compile :: #force_inline proc(pattern: re__Pattern) -> (value: re__Regex, err: re__Error) {"), true)
    testing.expect_value(t, strings.contains(output, "return rx.create(pattern)"), true)
    testing.expect_value(t, strings.contains(output, "re__matches_p :: #force_inline proc(pattern: re__Pattern, s: string) -> bool {"), true)
    testing.expect_value(t, strings.contains(output, `re__matches_p("\\d+", "abc123")`), true)
    testing.expect_value(t, strings.contains(output, `re__matches_p("^\\d+$", "abc123")`), true)
    testing.expect_value(t, strings.contains(output, `compiled, err := re__compile("^a+$")`), true)
    testing.expect_value(t, strings.contains(output, "owned_compiled := compiled"), true)
    testing.expect_value(t, strings.contains(output, "defer re__destroy_bang(owned_compiled)"), true)
    testing.expect_value(t, strings.contains(output, `re__matches_compiled_p(owned_compiled, "aaa")`), true)
    testing.expect_value(t, strings.contains(output, "#owned"), false)
}

@(test)
compile_set_package_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import set "kvist:set")

(defn demo []
  (let [base (set.of int [1 2 3])
        extra (set.of int [3 4])
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
    (println subset? superset? disjoint?)))`

    output, err, ok := kvist.compile_source(source)
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
    testing.expect_value(t, strings.contains(output, "out := make(map[T]struct{}, cap)"), true)
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
    testing.expect_value(t, strings.contains(output, "kvist_set_union :: proc(lhs, rhs: map[$T]struct{}) -> map[T]struct{}"), false)
    testing.expect_value(t, strings.contains(output, "kvist_set_add :: proc(s: map[$T]struct{}, value: T) -> map[T]struct{}"), false)
}

@(test)
compile_set_package_bang_algebra_helpers :: proc(t: ^testing.T) {
    source := `(package main)
(import set "kvist:set")

(defn demo []
  (let [target (set.of int [1 2 3]) :defer
        rhs (set.of int [3 4 5]) :defer]
    (set.union! target rhs)
    (set.intersection! target rhs)
    (set.difference! target rhs)
    (println (set.contains? target 4))))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(t, strings.contains(output, "for value, _ in rhs {"), true)
    testing.expect_value(t, strings.contains(output, "target[value] = struct{}{}"), true)
    testing.expect_value(t, strings.contains(output, "for value, _ in target {"), true)
    testing.expect_value(t, strings.contains(output, "delete_key(&(target), value)"), true)
    testing.expect_value(t, strings.contains(output, "kvist_set_union_in_place"), false)
    testing.expect_value(t, strings.contains(output, "kvist_set_intersection_in_place"), false)
    testing.expect_value(t, strings.contains(output, "kvist_set_difference_in_place"), false)
}
