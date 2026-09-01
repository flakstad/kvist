// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist_repl

import "base:runtime"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import repl_plan "../kvist_repl_plan"
import repl_program "../kvist_repl_program"

worker_execution_plan_test_mutex: sync.Mutex
worker_test_owned_string_calls: int
worker_test_owned_string_allocator: runtime.Allocator
worker_test_data_allocator: runtime.Allocator
worker_test_data_releases: int
worker_test_data_commits: int
worker_test_data_renders: int
worker_test_abort_worker: ^Worker
Worker_Test_Loaded_Result :: struct {
    number: int,
    values: [2]f64,
}

worker_test_loaded_result: Worker_Test_Loaded_Result
worker_test_loaded_snapshots: [3]Worker_Test_Loaded_Result

@(test)
incremental_llvm_discovers_embedded_toolchain_library_names :: proc(
    t: ^testing.T,
) {
    fixture := "ignored LLVM API text\x00" +
        "/toolchain/lib/libLLVM.dylib\x00" +
        "libLLVM.so.22.1\x00" +
        "C:\\Odin\\LLVM-C.dll\x00"
    candidates := incremental_llvm_embedded_library_candidates(
        transmute([]byte)fixture,
    )
    defer incremental_llvm_text_slice_delete(&candidates)
    expected := [?]string{
        "libLLVM.dylib",
        "/toolchain/lib/libLLVM.dylib",
        "libLLVM.so.22.1",
        "LLVM-C.dll",
        "C:\\Odin\\LLVM-C.dll",
    }
    for value in expected {
        found := false
        for candidate in candidates {
            if candidate == value {
                found = true
                break
            }
        }
        testing.expect_value(t, found, true)
    }
}

@(test)
incremental_llvm_uses_the_installed_odin_toolchain :: proc(
    t: ^testing.T,
) {
    state, stdout, stderr, process_err := os.process_exec(
        os.Process_Desc{command = {"odin", "report"}},
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)
    testing.expect_value(t, process_err == nil, true)
    testing.expect_value(t, state.exited && state.exit_code == 0, true)
    if process_err != nil || !state.exited || state.exit_code != 0 ||
       !strings.contains(string(stdout), "Backend: LLVM") {
        return
    }
    names := incremental_llvm_candidate_names()
    defer incremental_llvm_candidate_names_delete(&names)
    library := incremental_llvm_odin_toolchain_library(names[:])
    defer delete(library)
    require_integration := os.get_env(
        "KVIST_TEST_REQUIRE_ODIN_LLVM",
        context.temp_allocator,
    ) == "1"
    if require_integration {
        testing.expect_value(t, library != "", true)
    }
}

worker_test_loaded_result_impl :: proc() -> Worker_Test_Loaded_Result {
    return worker_test_loaded_result
}

worker_test_loaded_snapshot_0 :: proc() -> Worker_Test_Loaded_Result {
    return worker_test_loaded_snapshots[0]
}

worker_test_loaded_snapshot_1 :: proc() -> Worker_Test_Loaded_Result {
    return worker_test_loaded_snapshots[1]
}

worker_test_loaded_snapshot_2 :: proc() -> Worker_Test_Loaded_Result {
    return worker_test_loaded_snapshots[2]
}

worker_test_stabilize_loaded_result :: proc "c" (
    occupied: [^]rawptr,
    occupied_count: int,
) -> rawptr {
    addresses := [3]rawptr{
        transmute(rawptr)worker_test_loaded_snapshot_0,
        transmute(rawptr)worker_test_loaded_snapshot_1,
        transmute(rawptr)worker_test_loaded_snapshot_2,
    }
    for address, snapshot_index in addresses {
        used := false
        for occupied_index in 0..<occupied_count {
            if occupied[occupied_index] == address {
                used = true
                break
            }
        }
        if !used {
            worker_test_loaded_snapshots[snapshot_index] =
                worker_test_loaded_result
            return address
        }
    }
    return nil
}

Worker_Test_Data_Handle :: struct {
    value:    int,
    rendered: string,
}

worker_test_data_result :: proc() -> int {
    return 42
}

worker_test_data_release :: proc "c" (context_ptr: rawptr) {
    if context_ptr == nil {
        return
    }
    context = runtime.default_context()
    context.allocator = worker_test_data_allocator
    handle := transmute(^Worker_Test_Data_Handle)context_ptr
    delete(handle.rendered)
    free(handle)
    worker_test_data_releases += 1
}

worker_test_data_commit :: proc "c" (context_ptr: rawptr) -> rawptr {
    if context_ptr == nil {
        return nil
    }
    worker_test_data_commits += 1
    return transmute(rawptr)worker_test_data_result
}

worker_test_data_render :: proc "c" (
    context_ptr: rawptr,
    rendered: ^Rendered_Value,
) -> bool {
    if context_ptr == nil || rendered == nil {
        return false
    }
    context = runtime.default_context()
    context.allocator = worker_test_data_allocator
    handle := transmute(^Worker_Test_Data_Handle)context_ptr
    if handle.rendered == "" {
        handle.rendered = strings.clone("{:value 42}")
    }
    rendered^ = Rendered_Value{
        data = raw_data(handle.rendered),
        length = len(handle.rendered),
    }
    worker_test_data_renders += 1
    return true
}

worker_test_make_data_scalar :: proc "c" (
    args: [^]Scalar_Value,
    arg_count: int,
    result: ^Scalar_Value,
) -> bool {
    context = runtime.default_context()
    context.allocator = worker_test_data_allocator
    if arg_count != 0 {
        return false
    }
    handle := new(Worker_Test_Data_Handle)
    handle.value = 42
    result^ = Scalar_Value{
        kind = .Data,
        owned = true,
        source_value = rawptr(&handle.value),
        managed_context = rawptr(handle),
        managed_release = worker_test_data_release,
        managed_commit = worker_test_data_commit,
        managed_render = worker_test_data_render,
    }
    return true
}

worker_test_read_data_scalar :: proc "c" (
    args: [^]Scalar_Value,
    arg_count: int,
    result: ^Scalar_Value,
) -> bool {
    if arg_count != 1 || args[0].kind != .Data ||
       args[0].source_value == nil {
        return false
    }
    value := (transmute(^int)args[0].source_value)^
    result^ = Scalar_Value{kind = .Int, int_value = i64(value)}
    return true
}

worker_test_data_release_count_scalar :: proc "c" (
    args: [^]Scalar_Value,
    arg_count: int,
    result: ^Scalar_Value,
) -> bool {
    if arg_count != 0 {
        return false
    }
    result^ = {
        kind = .Int,
        int_value = i64(worker_test_data_releases),
    }
    return true
}

worker_test_contains_scalar :: proc "c" (
    args: [^]Scalar_Value,
    arg_count: int,
    result: ^Scalar_Value,
) -> bool {
    context = runtime.default_context()
    if arg_count != 2 || args[0].kind != .String ||
       args[1].kind != .String {
        return false
    }
    text := string(args[0].string_data[:args[0].string_length])
    needle := string(args[1].string_data[:args[1].string_length])
    result^ = Scalar_Value{
        kind = .Bool,
        int_value = 1 if strings.contains(text, needle) else 0,
    }
    return true
}

worker_test_trim_scalar :: proc "c" (
    args: [^]Scalar_Value,
    arg_count: int,
    result: ^Scalar_Value,
) -> bool {
    context = runtime.default_context()
    if arg_count != 1 || args[0].kind != .String {
        return false
    }
    text := string(args[0].string_data[:args[0].string_length])
    trimmed := strings.trim_space(text)
    result^ = Scalar_Value{
        kind = .String,
        string_data = raw_data(trimmed),
        string_length = len(trimmed),
    }
    return true
}

worker_test_owned_string_scalar :: proc "c" (
    args: [^]Scalar_Value,
    arg_count: int,
    result: ^Scalar_Value,
) -> bool {
    context = runtime.default_context()
    context.allocator = worker_test_owned_string_allocator
    worker_test_owned_string_calls += 1
    if arg_count != 1 || args[0].kind != .String {
        return false
    }
    text := string(args[0].string_data[:args[0].string_length])
    owned := strings.clone(text)
    data := raw_data(owned)
    for byte, index in owned {
        if byte >= 'A' && byte <= 'Z' {
            data[index] = u8(byte+32)
        }
    }
    result^ = Scalar_Value{
        kind = .String,
        owned = true,
        string_data = data,
        string_length = len(owned),
    }
    return true
}

worker_test_abort_scalar :: proc "c" (
    args: [^]Scalar_Value,
    arg_count: int,
    result: ^Scalar_Value,
) -> bool {
    if arg_count != 0 || worker_test_abort_worker == nil {
        return false
    }
    worker_test_abort_worker.abort_requested = true
    result^ = Scalar_Value{kind = .Int, int_value = 42}
    return true
}

worker_test_increment_scalar :: proc "c" (
    args: [^]Scalar_Value,
    arg_count: int,
    result: ^Scalar_Value,
) -> bool {
    if arg_count != 1 || args[0].kind != .Int {
        return false
    }
    result^ = {kind = .Int, int_value = args[0].int_value+1}
    return true
}

worker_test_add_ten_scalar :: proc "c" (
    args: [^]Scalar_Value,
    arg_count: int,
    result: ^Scalar_Value,
) -> bool {
    if arg_count != 1 || args[0].kind != .Int {
        return false
    }
    result^ = {kind = .Int, int_value = args[0].int_value+10}
    return true
}

worker_test_scalar_target :: proc(name, signature: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, name)
    strings.write_byte(&builder, 0)
    strings.write_string(&builder, signature)
    return strings.clone(strings.to_string(builder))
}

@(test)
worker_loaded_native_results_preserve_typed_history :: proc(t: ^testing.T) {
    sync.lock(&worker_execution_plan_test_mutex)
    defer sync.unlock(&worker_execution_plan_test_mutex)
    worker := Worker{allocator = context.allocator}
    defer worker_delete(&worker)
    current_address := transmute(rawptr)worker_test_loaded_result_impl
    generation := Generation_Symbols{
        stabilize_result = worker_test_stabilize_loaded_result,
        result_address = current_address,
    }
    result_proc := proc(address: rawptr) -> Worker_Test_Loaded_Result {
        return (transmute(proc() -> Worker_Test_Loaded_Result)address)()
    }

    worker_test_loaded_result = {number = 10, values = {10.5, 10.75}}
    worker.result_slots[0] = {
        name = strings.clone("kvist_repl_star_1"),
        signature = strings.clone("value:Worker_Test_Loaded_Result"),
        address = current_address,
    }
    testing.expect_value(
        t,
        worker_stabilize_loaded_result(&worker, &generation),
        true,
    )
    worker_test_loaded_result = {number = 20, values = {20.5, 20.75}}
    testing.expect_value(
        t,
        result_proc(worker.result_slots[0].address),
        Worker_Test_Loaded_Result{number = 10, values = {10.5, 10.75}},
    )
    worker_register_result(
        rawptr(&worker),
        cstring("value:Worker_Test_Loaded_Result"),
        current_address,
    )
    testing.expect_value(
        t,
        worker_stabilize_loaded_result(&worker, &generation),
        true,
    )
    worker_test_loaded_result = {number = 30, values = {30.5, 30.75}}
    testing.expect_value(
        t,
        result_proc(worker.result_slots[0].address),
        Worker_Test_Loaded_Result{number = 20, values = {20.5, 20.75}},
    )
    testing.expect_value(
        t,
        result_proc(worker.result_slots[1].address),
        Worker_Test_Loaded_Result{number = 10, values = {10.5, 10.75}},
    )
    worker_register_result(
        rawptr(&worker),
        cstring("value:Worker_Test_Loaded_Result"),
        current_address,
    )
    testing.expect_value(
        t,
        worker_stabilize_loaded_result(&worker, &generation),
        true,
    )
    worker_test_loaded_result = {number = 40, values = {40.5, 40.75}}
    testing.expect_value(
        t,
        result_proc(worker.result_slots[0].address),
        Worker_Test_Loaded_Result{number = 30, values = {30.5, 30.75}},
    )
    testing.expect_value(
        t,
        result_proc(worker.result_slots[1].address),
        Worker_Test_Loaded_Result{number = 20, values = {20.5, 20.75}},
    )
    testing.expect_value(
        t,
        result_proc(worker.result_slots[2].address),
        Worker_Test_Loaded_Result{number = 10, values = {10.5, 10.75}},
    )
    worker_register_result(
        rawptr(&worker),
        cstring("value:Worker_Test_Loaded_Result"),
        current_address,
    )
    testing.expect_value(
        t,
        worker_stabilize_loaded_result(&worker, &generation),
        true,
    )
    worker_test_loaded_result = {number = 50, values = {50.5, 50.75}}
    testing.expect_value(
        t,
        result_proc(worker.result_slots[0].address),
        Worker_Test_Loaded_Result{number = 40, values = {40.5, 40.75}},
    )
    testing.expect_value(
        t,
        result_proc(worker.result_slots[1].address),
        Worker_Test_Loaded_Result{number = 30, values = {30.5, 30.75}},
    )
    testing.expect_value(
        t,
        result_proc(worker.result_slots[2].address),
        Worker_Test_Loaded_Result{number = 20, values = {20.5, 20.75}},
    )
}

@(test)
worker_execution_plans_preserve_typed_result_history :: proc(t: ^testing.T) {
    sync.lock(&worker_execution_plan_test_mutex)
    defer sync.unlock(&worker_execution_plan_test_mutex)
    worker := Worker{}
    defer worker_delete(&worker)

    message, ok := worker_execute_plan(
        &worker,
        "9|i|r|i:20|i:22|add:2",
    )
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "42\n")

    message, ok = worker_execute_plan(
        &worker,
        "9|i|p|r:0",
    )
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "42\n")
    testing.expect_value(t, worker.result_slots[1].address, nil)

    message, ok = worker_execute_plan(
        &worker,
        "9|i|r|r:0|i:1|add:2",
    )
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "43\n")
    testing.expect_value(t, worker.result_slots[0].signature, "value:int")
    testing.expect_value(t, worker.result_slots[1].signature, "value:int")
    testing.expect_value(t, worker.direct_int_results[1], 43)
    testing.expect_value(t, worker.direct_int_results[0], 42)
}

@(test)
worker_execution_plans_preserve_borrowed_string_history :: proc(
    t: ^testing.T,
) {
    sync.lock(&worker_execution_plan_test_mutex)
    defer sync.unlock(&worker_execution_plan_test_mutex)
    worker := Worker{}
    defer worker_delete(&worker)

    message, ok := worker_execute_plan(
        &worker,
        "9|s|r|s:68656c6c6f",
    )
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "hello\n")
    testing.expect_value(t, worker.result_slots[0].signature, "value:string")

    message, ok = worker_execute_plan(&worker, "9|s|p|r:0")
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "hello\n")

    // Rotate enough strings that loading *3 reuses its backing ring cell.
    message, ok = worker_execute_plan(&worker, "9|s|r|s:616c706861")
    testing.expect_value(t, ok, true)
    message, ok = worker_execute_plan(&worker, "9|s|r|s:62657461")
    testing.expect_value(t, ok, true)
    message, ok = worker_execute_plan(&worker, "9|s|r|r:2")
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "hello\n")

    message, ok = worker_execute_plan(
        &worker,
        "9|b|r|s:68656c6c6f|r:0|eq",
    )
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "true\n")
}

@(test)
worker_execution_plans_invoke_loaded_scalar_adapters :: proc(
    t: ^testing.T,
) {
    sync.lock(&worker_execution_plan_test_mutex)
    defer sync.unlock(&worker_execution_plan_test_mutex)
    worker := Worker{allocator = context.allocator}
    defer worker_delete(&worker)
    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.contains"),
        cstring("proc(string,string)->bool"),
        cstring("value:bool"),
        worker_test_contains_scalar,
    )

    target := worker_test_scalar_target(
        "test.contains",
        "proc(string,string)->bool",
    )
    defer delete(target)
    plan := repl_plan.Execution_Plan{
        result_kind = .Bool,
        result_action = .Rotate_History,
    }
    append(
        &plan.instructions,
        repl_plan.Instruction{
            opcode = .Push_String,
            text_operand = strings.clone("Kvist REPL"),
        },
        repl_plan.Instruction{
            opcode = .Push_String,
            text_operand = strings.clone("REPL"),
        },
        repl_plan.Instruction{
            opcode = .Invoke_Scalar_2,
            text_operand = strings.clone(target),
        },
    )
    defer repl_plan.execution_plan_delete(&plan)
    encoded, encoded_ok := repl_plan.execution_plan_encode(plan)
    testing.expect_value(t, encoded_ok, true)
    defer delete(encoded)

    message, ok := worker_execute_plan(&worker, encoded)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "true\n")

    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.trim"),
        cstring("proc(string:borrowed)->string:borrowed"),
        cstring("value:string"),
        worker_test_trim_scalar,
    )
    trim_target := worker_test_scalar_target(
        "test.trim",
        "proc(string:borrowed)->string:borrowed",
    )
    defer delete(trim_target)
    trim_plan := repl_plan.Execution_Plan{
        result_kind = .String,
        result_action = .Rotate_History,
    }
    append(
        &trim_plan.instructions,
        repl_plan.Instruction{
            opcode = .Push_String,
            text_operand = strings.clone(" Kvist "),
        },
        repl_plan.Instruction{
            opcode = .Invoke_Scalar_1,
            text_operand = strings.clone(trim_target),
        },
    )
    defer repl_plan.execution_plan_delete(&trim_plan)
    trim_encoded, trim_encoded_ok :=
        repl_plan.execution_plan_encode(trim_plan)
    testing.expect_value(t, trim_encoded_ok, true)
    defer delete(trim_encoded)

    message, ok = worker_execute_plan(&worker, trim_encoded)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "Kvist\n")
    message, ok = worker_execute_plan(&worker, "9|s|p|r:0")
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "Kvist\n")

    worker_test_owned_string_calls = 0
    worker_test_owned_string_allocator = worker.allocator
    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.lower"),
        cstring("proc(string:borrowed)->string:owned"),
        cstring("value:string"),
        worker_test_owned_string_scalar,
    )
    owned_target := worker_test_scalar_target(
        "test.lower",
        "proc(string:borrowed)->string:owned",
    )
    defer delete(owned_target)
    owned_plan := repl_plan.Execution_Plan{
        result_kind = .String,
        result_action = .Rotate_History,
    }
    append(
        &owned_plan.instructions,
        repl_plan.Instruction{
            opcode = .Push_String,
            text_operand = strings.clone("KVIST"),
        },
        repl_plan.Instruction{
            opcode = .Invoke_Scalar_1,
            text_operand = strings.clone(owned_target),
        },
    )
    defer repl_plan.execution_plan_delete(&owned_plan)
    owned_encoded, owned_encoded_ok :=
        repl_plan.execution_plan_encode(owned_plan)
    testing.expect_value(t, owned_encoded_ok, true)
    defer delete(owned_encoded)

    message, ok = worker_execute_plan(&worker, owned_encoded)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "kvist\n")
    testing.expect_value(t, worker_test_owned_string_calls, 1)

    nested_owned_plan := repl_plan.Execution_Plan{
        result_kind = .Bool,
        result_action = .Rotate_History,
    }
    append(
        &nested_owned_plan.instructions,
        repl_plan.Instruction{
            opcode = .Push_String,
            text_operand = strings.clone(" KVIST "),
        },
        repl_plan.Instruction{
            opcode = .Invoke_Scalar_1,
            text_operand = strings.clone(owned_target),
        },
        repl_plan.Instruction{
            opcode = .Invoke_Scalar_1,
            text_operand = strings.clone(trim_target),
        },
        repl_plan.Instruction{
            opcode = .Push_String,
            text_operand = strings.clone("kvist"),
        },
        repl_plan.Instruction{opcode = .Equal},
    )
    defer repl_plan.execution_plan_delete(&nested_owned_plan)
    nested_owned_encoded, nested_owned_encoded_ok :=
        repl_plan.execution_plan_encode(nested_owned_plan)
    testing.expect_value(t, nested_owned_encoded_ok, true)
    defer delete(nested_owned_encoded)

    message, ok = worker_execute_plan(&worker, nested_owned_encoded)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "true\n")
    testing.expect_value(t, worker_test_owned_string_calls, 2)
}

@(test)
worker_execution_plans_propagate_loaded_adapter_abort :: proc(
    t: ^testing.T,
) {
    sync.lock(&worker_execution_plan_test_mutex)
    defer sync.unlock(&worker_execution_plan_test_mutex)
    worker := Worker{allocator = context.allocator}
    defer worker_delete(&worker)
    worker_test_abort_worker = &worker
    defer worker_test_abort_worker = nil
    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.abort"),
        cstring("proc()->int"),
        cstring("value:int"),
        worker_test_abort_scalar,
    )
    target := worker_test_scalar_target("test.abort", "proc()->int")
    defer delete(target)
    plan := repl_plan.Execution_Plan{
        result_kind = .Int,
        result_action = .Rotate_History,
    }
    append(
        &plan.instructions,
        repl_plan.Instruction{
            opcode = .Invoke_Scalar_0,
            text_operand = strings.clone(target),
        },
    )
    defer repl_plan.execution_plan_delete(&plan)
    encoded, encoded_ok := repl_plan.execution_plan_encode(plan)
    testing.expect_value(t, encoded_ok, true)
    defer delete(encoded)

    message, ok := worker_execute_plan(&worker, encoded)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.last_run_aborted, true)
    testing.expect_value(t, worker.output, "")

    message, ok = worker_execute_plan(&worker, "9|i|r|i:42")
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.last_run_aborted, false)
    testing.expect_value(t, worker.output, "42\n")
}

@(test)
worker_execution_plans_manage_owned_string_lifetimes :: proc(
    t: ^testing.T,
) {
    sync.lock(&worker_execution_plan_test_mutex)
    defer sync.unlock(&worker_execution_plan_test_mutex)
    worker := Worker{allocator = context.allocator}
    defer worker_delete(&worker)
    worker_test_owned_string_allocator = worker.allocator
    worker_test_owned_string_calls = 0
    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.lower"),
        cstring("proc(string:borrowed)->string:owned"),
        cstring("value:string"),
        worker_test_owned_string_scalar,
    )
    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.trim"),
        cstring("proc(string:borrowed)->string:borrowed"),
        cstring("value:string"),
        worker_test_trim_scalar,
    )
    owned_target := worker_test_scalar_target(
        "test.lower",
        "proc(string:borrowed)->string:owned",
    )
    defer delete(owned_target)
    trim_target := worker_test_scalar_target(
        "test.trim",
        "proc(string:borrowed)->string:borrowed",
    )
    defer delete(trim_target)

    alias_plan := repl_plan.Execution_Plan{
        result_kind = .Bool,
        result_action = .Rotate_History,
    }
    append(
        &alias_plan.instructions,
        repl_plan.Instruction{
            opcode = .Push_String,
            text_operand = strings.clone(" KVIST "),
        },
        repl_plan.Instruction{
            opcode = .Invoke_Scalar_1,
            text_operand = strings.clone(owned_target),
        },
        repl_plan.Instruction{opcode = .Store_Local, operand = 0},
        repl_plan.Instruction{opcode = .Load_Local, operand = 0},
        repl_plan.Instruction{
            opcode = .Invoke_Scalar_1,
            text_operand = strings.clone(trim_target),
        },
        repl_plan.Instruction{opcode = .Store_Local, operand = 1},
        repl_plan.Instruction{opcode = .Load_Local, operand = 1},
        repl_plan.Instruction{
            opcode = .Push_String,
            text_operand = strings.clone("kvist"),
        },
        repl_plan.Instruction{opcode = .Equal},
    )
    defer repl_plan.execution_plan_delete(&alias_plan)
    alias_encoded, alias_encoded_ok :=
        repl_plan.execution_plan_encode(alias_plan)
    testing.expect_value(t, alias_encoded_ok, true)
    defer delete(alias_encoded)

    message, ok := worker_execute_plan(&worker, alias_encoded)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "true\n")

    error_plan := repl_plan.Execution_Plan{
        result_kind = .Bool,
        result_action = .Rotate_History,
    }
    append(
        &error_plan.instructions,
        repl_plan.Instruction{
            opcode = .Push_String,
            text_operand = strings.clone("KVIST"),
        },
        repl_plan.Instruction{
            opcode = .Invoke_Scalar_1,
            text_operand = strings.clone(owned_target),
        },
        repl_plan.Instruction{opcode = .Push_Int, operand = 1},
        repl_plan.Instruction{opcode = .Equal},
    )
    defer repl_plan.execution_plan_delete(&error_plan)
    error_encoded, error_encoded_ok :=
        repl_plan.execution_plan_encode(error_plan)
    testing.expect_value(t, error_encoded_ok, true)
    defer delete(error_encoded)

    message, ok = worker_execute_plan(&worker, error_encoded)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, message, "invalid resident comparison operands")
    delete(message)


}

@(test)
worker_owned_scalar_results_use_managed_allocator :: proc(t: ^testing.T) {
    sync.lock(&worker_execution_plan_test_mutex)
    defer sync.unlock(&worker_execution_plan_test_mutex)
    worker := Worker{allocator = context.allocator}
    defer worker_delete(&worker)
    mem.tracking_allocator_init(
        &worker.generation_allocator,
        worker.allocator,
        worker.allocator,
    )
    worker.managed_allocations = make(
        map[rawptr]Worker_Managed_Allocation,
        worker.allocator,
    )
    worker.generation_allocator_initialized = true
    worker_ensure_host_api(&worker)
    worker_test_owned_string_allocator = worker.host_api.allocator
    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.lower"),
        cstring("proc(string:borrowed)->string:owned"),
        cstring("value:string"),
        worker_test_owned_string_scalar,
    )
    input := "KVIST"
    invoked := worker_invoke_scalar(
        &worker,
        "test.lower",
        "proc(string:borrowed)->string:owned",
        []Scalar_Value{{
            kind = .String,
            string_data = raw_data(input),
            string_length = len(input),
        }},
    )
    testing.expect_value(t, invoked, true)
    testing.expect_value(t, worker.output, "kvist\n")
    testing.expect_value(t, len(worker.managed_allocations), 0)
}

@(test)
worker_execution_plans_manage_opaque_data_temporaries :: proc(
    t: ^testing.T,
) {
    sync.lock(&worker_execution_plan_test_mutex)
    defer sync.unlock(&worker_execution_plan_test_mutex)
    worker := Worker{allocator = context.allocator}
    defer worker_delete(&worker)
    worker_test_data_allocator = worker.allocator
    worker_test_data_releases = 0
    worker_test_data_commits = 0
    worker_test_data_renders = 0
    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.make-data"),
        cstring("proc()->Data:owned"),
        cstring("value:Data"),
        worker_test_make_data_scalar,
    )
    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.read-data"),
        cstring("proc(Data:borrowed)->int"),
        cstring("value:int"),
        worker_test_read_data_scalar,
    )
    make_target := worker_test_scalar_target(
        "test.make-data",
        "proc()->Data:owned",
    )
    defer delete(make_target)
    read_target := worker_test_scalar_target(
        "test.read-data",
        "proc(Data:borrowed)->int",
    )
    defer delete(read_target)

    nested_plan := repl_plan.Execution_Plan{
        result_kind = .Int,
        result_action = .Rotate_History,
    }
    append(
        &nested_plan.instructions,
        repl_plan.Instruction{
            opcode = .Invoke_Scalar_0,
            text_operand = strings.clone(make_target),
        },
        repl_plan.Instruction{
            opcode = .Invoke_Scalar_1,
            text_operand = strings.clone(read_target),
        },
    )
    defer repl_plan.execution_plan_delete(&nested_plan)
    nested_encoded, nested_encoded_ok :=
        repl_plan.execution_plan_encode(nested_plan)
    testing.expect_value(t, nested_encoded_ok, true)
    defer delete(nested_encoded)

    message, ok := worker_execute_plan(&worker, nested_encoded)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "42\n")
    testing.expect_value(t, worker_test_data_releases, 1)
    testing.expect_value(t, worker_test_data_commits, 0)
    testing.expect_value(t, worker_test_data_renders, 0)

    live_plan := repl_plan.Execution_Plan{
        result_kind = .Int,
        result_action = .Rotate_History,
    }
    for slot in 0..<4 {
        append(
            &live_plan.instructions,
            repl_plan.Instruction{
                opcode = .Invoke_Scalar_0,
                text_operand = strings.clone(make_target),
            },
            repl_plan.Instruction{opcode = .Store_Local, operand = slot},
        )
    }
    for slot in 0..<4 {
        append(
            &live_plan.instructions,
            repl_plan.Instruction{opcode = .Load_Local, operand = slot},
            repl_plan.Instruction{
                opcode = .Invoke_Scalar_1,
                text_operand = strings.clone(read_target),
            },
        )
    }
    append(
        &live_plan.instructions,
        repl_plan.Instruction{opcode = .Add, operand = 4},
    )
    defer repl_plan.execution_plan_delete(&live_plan)
    live_encoded, live_encoded_ok :=
        repl_plan.execution_plan_encode(live_plan)
    testing.expect_value(t, live_encoded_ok, true)
    defer delete(live_encoded)

    releases_before := worker_test_data_releases
    message, ok = worker_execute_plan(&worker, live_encoded)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "168\n")
    testing.expect_value(
        t,
        worker_test_data_releases-releases_before,
        4,
    )

    error_plan := repl_plan.Execution_Plan{
        result_kind = .Bool,
        result_action = .Rotate_History,
    }
    append(
        &error_plan.instructions,
        repl_plan.Instruction{
            opcode = .Invoke_Scalar_0,
            text_operand = strings.clone(make_target),
        },
        repl_plan.Instruction{opcode = .Push_Int, operand = 42},
        repl_plan.Instruction{opcode = .Equal},
    )
    defer repl_plan.execution_plan_delete(&error_plan)
    error_encoded, error_encoded_ok :=
        repl_plan.execution_plan_encode(error_plan)
    testing.expect_value(t, error_encoded_ok, true)
    defer delete(error_encoded)

    releases_before = worker_test_data_releases
    message, ok = worker_execute_plan(&worker, error_encoded)
    testing.expect_value(t, ok, false)
    testing.expect_value(t, message, "invalid resident comparison operands")
    testing.expect_value(
        t,
        worker_test_data_releases-releases_before,
        1,
    )
    delete(message)


    final_plan := repl_plan.Execution_Plan{
        result_kind = .Data,
        result_action = .Rotate_History,
    }
    append(
        &final_plan.instructions,
        repl_plan.Instruction{
            opcode = .Invoke_Scalar_0,
            text_operand = strings.clone(make_target),
        },
    )
    defer repl_plan.execution_plan_delete(&final_plan)
    final_encoded, final_encoded_ok :=
        repl_plan.execution_plan_encode(final_plan)
    testing.expect_value(t, final_encoded_ok, true)
    defer delete(final_encoded)

    releases_before = worker_test_data_releases
    committed_before := worker_test_data_commits
    renders_before := worker_test_data_renders
    message, ok = worker_execute_plan(&worker, final_encoded)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "{:value 42}\n")
    testing.expect_value(t, worker.result_slots[0].signature, "value:Data")
    testing.expect_value(
        t,
        worker_test_data_releases-releases_before,
        1,
    )
    testing.expect_value(
        t,
        worker_test_data_commits-committed_before,
        1,
    )
    testing.expect_value(
        t,
        worker_test_data_renders-renders_before,
        1,
    )

    message, ok = worker_execute_plan(&worker, "9|d|p|r:0")
    testing.expect_value(t, ok, false)
    testing.expect_value(
        t,
        message,
        "invalid resident execution result action",
    )
    delete(message)

    releases_before = worker_test_data_releases
    committed_before = worker_test_data_commits
    renders_before = worker_test_data_renders
    invoked := worker_invoke_scalar(
        &worker,
        "test.make-data",
        "proc()->Data:owned",
        nil,
    )
    testing.expect_value(t, invoked, true)
    testing.expect_value(t, worker.output, "{:value 42}\n")
    testing.expect_value(
        t,
        worker_test_data_releases-releases_before,
        1,
    )
    testing.expect_value(
        t,
        worker_test_data_commits-committed_before,
        1,
    )
    testing.expect_value(
        t,
        worker_test_data_renders-renders_before,
        1,
    )
}

@(test)
worker_execution_plans_run_typed_control_flow :: proc(t: ^testing.T) {
    sync.lock(&worker_execution_plan_test_mutex)
    defer sync.unlock(&worker_execution_plan_test_mutex)
    worker := Worker{}
    defer worker_delete(&worker)

    message, ok := worker_execute_plan(
        &worker,
        "9|i|r|b:1|jf:4|i:7|jmp:5|i:9",
    )
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "7\n")

    message, ok = worker_execute_plan(
        &worker,
        "9|b|r|b:0|sf:4|b:1|not",
    )
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "false\n")
}

@(test)
worker_execution_plans_reject_type_mismatches :: proc(t: ^testing.T) {
    sync.lock(&worker_execution_plan_test_mutex)
    defer sync.unlock(&worker_execution_plan_test_mutex)
    worker := Worker{}
    defer worker_delete(&worker)
    message, ok := worker_execute_plan(
        &worker,
        "9|i|r|b:1|i:2|add:2",
    )
    testing.expect_value(t, ok, false)
    testing.expect_value(t, message, "resident arithmetic expects numeric operands")
    delete(message)
}

@(test)
worker_execution_plans_preserve_f64_history :: proc(t: ^testing.T) {
    sync.lock(&worker_execution_plan_test_mutex)
    defer sync.unlock(&worker_execution_plan_test_mutex)
    worker := Worker{}
    defer worker_delete(&worker)

    message, ok := worker_execute_plan(
        &worker,
        "9|f|r|f:4609434218613702656|f:4612248968380809216|add:2",
    )
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "3.75\n")
    testing.expect_value(t, worker.result_slots[0].signature, "value:f64")
    testing.expect_value(t, worker.direct_f64_results[0], 3.75)

    message, ok = worker_execute_plan(
        &worker,
        "9|f|p|r:0",
    )
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "3.75\n")

    message, ok = worker_execute_plan(
        &worker,
        "9|b|r|r:0|f:4616189618054758400|lt",
    )
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "true\n")
}

@(test)
worker_execution_plans_run_typed_locals :: proc(t: ^testing.T) {
    sync.lock(&worker_execution_plan_test_mutex)
    defer sync.unlock(&worker_execution_plan_test_mutex)
    worker := Worker{}
    defer worker_delete(&worker)

    message, ok := worker_execute_plan(
        &worker,
        "9|i|r|i:20|sl:0|ll:0|i:1|add:2|sl:1|ll:0|ll:1|i:1|add:3",
    )
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    testing.expect_value(t, worker.output, "42\n")

    message, ok = worker_execute_plan(&worker, "9|i|r|ll:0")
    testing.expect_value(t, ok, false)
    testing.expect_value(
        t,
        message,
        "resident execution plan local is unavailable",
    )
    delete(message)
}

worker_test_incremental_scale_program :: proc(
    multiplier: int,
) -> repl_program.Program {
    expressions := [?]repl_program.Expression{
        {kind = .Local, value_kind = .Int, operand = 0},
        {
            kind = .Int_Literal,
            value_kind = .Int,
            int_value = multiplier,
        },
        {
            kind = .Multiply,
            value_kind = .Int,
            children_count = 2,
        },
    }
    procedure := repl_program.Procedure{
        name = strings.clone("scale"),
        signature = strings.clone("proc(int:borrowed)->int"),
        result_kind = .Int,
        local_count = 1,
        result_expr = 2,
    }
    append(&procedure.parameter_kinds, repl_program.Value_Kind.Int)
    append(&procedure.local_kinds, repl_program.Value_Kind.Int)
    append(&procedure.expressions, ..expressions[:])
    append(&procedure.child_indices, 0, 1)
    program := repl_program.Program{}
    append(&program.procedures, procedure)
    return program
}

worker_test_incremental_loaded_call_program :: proc(
    procedure_name,
    target_name,
    signature: string,
    takes_argument: bool,
) -> repl_program.Program {
    procedure := repl_program.Procedure{
        name = strings.clone(procedure_name),
        signature = strings.clone(
            "proc(int:borrowed)->int" if takes_argument else "proc()->int",
        ),
        result_kind = .Int,
        local_count = 1 if takes_argument else 0,
        result_expr = 1 if takes_argument else 0,
    }
    if takes_argument {
        append(&procedure.parameter_kinds, repl_program.Value_Kind.Int)
        append(&procedure.local_kinds, repl_program.Value_Kind.Int)
        append(&procedure.expressions, repl_program.Expression{
            kind = .Local,
            value_kind = .Int,
            operand = 0,
        })
    }
    append(&procedure.expressions, repl_program.Expression{
        kind = .Native_Call,
        value_kind = .Int,
        children_count = 1 if takes_argument else 0,
        resolved_name = strings.clone(target_name),
        scalar_signature = strings.clone(signature),
    })
    if takes_argument {
        append(&procedure.child_indices, 0)
    }
    program := repl_program.Program{}
    append(&program.procedures, procedure)
    return program
}

worker_test_incremental_managed_program :: proc() -> repl_program.Program {
    string_proc := repl_program.Procedure{
        name = strings.clone("managed-string-chain"),
        signature = strings.clone("proc()->bool"),
        result_kind = .Bool,
        local_count = 1,
        result_expr = 6,
    }
    append(&string_proc.local_kinds, repl_program.Value_Kind.String)
    append(
        &string_proc.expressions,
        repl_program.Expression{
            kind = .String_Literal,
            value_kind = .String,
            string_value = strings.clone(" KVIST "),
        },
        repl_program.Expression{
            kind = .Native_Call,
            value_kind = .String,
            children_start = 0,
            children_count = 1,
            resolved_name = strings.clone("test.lower"),
            scalar_signature = strings.clone(
                "proc(string:borrowed)->string:owned",
            ),
        },
        repl_program.Expression{
            kind = .Local,
            value_kind = .String,
            operand = 0,
        },
        repl_program.Expression{
            kind = .Native_Call,
            value_kind = .String,
            children_start = 1,
            children_count = 1,
            resolved_name = strings.clone("test.trim"),
            scalar_signature = strings.clone(
                "proc(string:borrowed)->string:borrowed",
            ),
        },
        repl_program.Expression{
            kind = .String_Literal,
            value_kind = .String,
            string_value = strings.clone("kvist"),
        },
        repl_program.Expression{
            kind = .Native_Call,
            value_kind = .Bool,
            children_start = 2,
            children_count = 2,
            resolved_name = strings.clone("test.contains"),
            scalar_signature = strings.clone(
                "proc(string,string)->bool",
            ),
        },
        repl_program.Expression{
            kind = .Let,
            value_kind = .Bool,
            bindings_start = 0,
            bindings_count = 1,
            body = 5,
        },
    )
    append(&string_proc.child_indices, 0, 2, 3, 4)
    append(&string_proc.bindings, repl_program.Binding{
        slot = 0,
        value_expr = 1,
        value_kind = .String,
        managed_cleanup = true,
    })

    data_proc := repl_program.Procedure{
        name = strings.clone("managed-data-chain"),
        signature = strings.clone("proc()->int"),
        result_kind = .Int,
        local_count = 1,
        result_expr = 3,
    }
    append(&data_proc.local_kinds, repl_program.Value_Kind.Data)
    append(
        &data_proc.expressions,
        repl_program.Expression{
            kind = .Native_Call,
            value_kind = .Data,
            resolved_name = strings.clone("test.make-data"),
            scalar_signature = strings.clone("proc()->Data:owned"),
        },
        repl_program.Expression{
            kind = .Local,
            value_kind = .Data,
            operand = 0,
        },
        repl_program.Expression{
            kind = .Native_Call,
            value_kind = .Int,
            children_count = 1,
            resolved_name = strings.clone("test.read-data"),
            scalar_signature = strings.clone(
                "proc(Data:borrowed)->int",
            ),
        },
        repl_program.Expression{
            kind = .Let,
            value_kind = .Int,
            bindings_count = 1,
            body = 2,
        },
    )
    append(&data_proc.child_indices, 1)
    append(&data_proc.bindings, repl_program.Binding{
        slot = 0,
        value_expr = 0,
        value_kind = .Data,
        managed_cleanup = true,
    })

    loop_proc := repl_program.Procedure{
        name = strings.clone("managed-data-loop"),
        signature = strings.clone("proc()->int"),
        result_kind = .Int,
        local_count = 2,
        result_expr = 17,
    }
    append(
        &loop_proc.local_kinds,
        repl_program.Value_Kind.Int,
        repl_program.Value_Kind.Data,
    )
    append(
        &loop_proc.expressions,
        repl_program.Expression{
            kind = .Int_Literal,
            value_kind = .Int,
        },
        repl_program.Expression{
            kind = .Local,
            value_kind = .Int,
            operand = 0,
        },
        repl_program.Expression{
            kind = .Int_Literal,
            value_kind = .Int,
            int_value = 3,
        },
        repl_program.Expression{
            kind = .Less,
            value_kind = .Bool,
            children_count = 2,
        },
        repl_program.Expression{
            kind = .Native_Call,
            value_kind = .Data,
            resolved_name = strings.clone("test.make-data"),
            scalar_signature = strings.clone("proc()->Data:owned"),
        },
        repl_program.Expression{
            kind = .Local,
            value_kind = .Data,
            operand = 1,
        },
        repl_program.Expression{
            kind = .Native_Call,
            value_kind = .Int,
            children_start = 2,
            children_count = 1,
            resolved_name = strings.clone("test.read-data"),
            scalar_signature = strings.clone(
                "proc(Data:borrowed)->int",
            ),
        },
        repl_program.Expression{
            kind = .Discard,
            value_kind = .Void,
            children_start = 3,
            children_count = 1,
        },
        repl_program.Expression{
            kind = .Local,
            value_kind = .Int,
            operand = 0,
        },
        repl_program.Expression{
            kind = .Int_Literal,
            value_kind = .Int,
            int_value = 1,
        },
        repl_program.Expression{
            kind = .Add,
            value_kind = .Int,
            children_start = 4,
            children_count = 2,
        },
        repl_program.Expression{
            kind = .Set_Local,
            value_kind = .Void,
            operand = 0,
            children_start = 6,
            children_count = 1,
        },
        repl_program.Expression{
            kind = .Sequence,
            value_kind = .Void,
            children_start = 7,
            children_count = 2,
        },
        repl_program.Expression{
            kind = .Let,
            value_kind = .Void,
            bindings_start = 1,
            bindings_count = 1,
            body = 12,
        },
        repl_program.Expression{
            kind = .While,
            value_kind = .Void,
            children_start = 9,
            children_count = 2,
        },
        repl_program.Expression{
            kind = .Native_Call,
            value_kind = .Int,
            resolved_name = strings.clone("test.data-release-count"),
            scalar_signature = strings.clone("proc()->int"),
        },
        repl_program.Expression{
            kind = .Sequence,
            value_kind = .Int,
            children_start = 11,
            children_count = 2,
        },
        repl_program.Expression{
            kind = .Let,
            value_kind = .Int,
            bindings_count = 1,
            body = 16,
        },
    )
    append(
        &loop_proc.child_indices,
        1, 2,
        5,
        6,
        8, 9,
        10,
        7, 11,
        3, 13,
        14, 15,
    )
    append(
        &loop_proc.bindings,
        repl_program.Binding{
            slot = 0,
            value_expr = 0,
            value_kind = .Int,
        },
        repl_program.Binding{
            slot = 1,
            value_expr = 4,
            value_kind = .Data,
            managed_cleanup = true,
        },
    )

    abort_proc := repl_program.Procedure{
        name = strings.clone("managed-data-abort"),
        signature = strings.clone("proc()->int"),
        result_kind = .Int,
        local_count = 1,
        result_expr = 2,
    }
    append(&abort_proc.local_kinds, repl_program.Value_Kind.Data)
    append(
        &abort_proc.expressions,
        repl_program.Expression{
            kind = .Native_Call,
            value_kind = .Data,
            resolved_name = strings.clone("test.make-data"),
            scalar_signature = strings.clone("proc()->Data:owned"),
        },
        repl_program.Expression{
            kind = .Native_Call,
            value_kind = .Int,
            resolved_name = strings.clone("test.abort"),
            scalar_signature = strings.clone("proc()->int"),
        },
        repl_program.Expression{
            kind = .Let,
            value_kind = .Int,
            bindings_count = 1,
            body = 1,
        },
    )
    append(&abort_proc.bindings, repl_program.Binding{
        slot = 0,
        value_expr = 0,
        value_kind = .Data,
        managed_cleanup = true,
    })

    program := repl_program.Program{}
    append(
        &program.procedures,
        string_proc,
        data_proc,
        loop_proc,
        abort_proc,
    )
    return program
}

@(test)
worker_incremental_native_calls_manage_string_and_data_temporaries :: proc(
    t: ^testing.T,
) {
    if !incremental_native_backend_supported() {
        return
    }
    sync.lock(&worker_execution_plan_test_mutex)
    defer sync.unlock(&worker_execution_plan_test_mutex)
    worker := Worker{allocator = context.allocator}
    defer worker_delete(&worker)
    worker_test_owned_string_allocator = worker.allocator
    worker_test_owned_string_calls = 0
    worker_test_data_allocator = worker.allocator
    worker_test_data_releases = 0
    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.lower"),
        cstring("proc(string:borrowed)->string:owned"),
        cstring("value:string"),
        worker_test_owned_string_scalar,
    )
    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.trim"),
        cstring("proc(string:borrowed)->string:borrowed"),
        cstring("value:string"),
        worker_test_trim_scalar,
    )
    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.contains"),
        cstring("proc(string,string)->bool"),
        cstring("value:bool"),
        worker_test_contains_scalar,
    )
    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.make-data"),
        cstring("proc()->Data:owned"),
        cstring("value:Data"),
        worker_test_make_data_scalar,
    )
    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.read-data"),
        cstring("proc(Data:borrowed)->int"),
        cstring("value:int"),
        worker_test_read_data_scalar,
    )
    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.data-release-count"),
        cstring("proc()->int"),
        cstring("value:int"),
        worker_test_data_release_count_scalar,
    )
    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.abort"),
        cstring("proc()->int"),
        cstring("value:int"),
        worker_test_abort_scalar,
    )
    program := worker_test_incremental_managed_program()
    encoded, encoded_ok := repl_program.program_encode(program)
    repl_program.program_delete(&program)
    testing.expect_value(t, encoded_ok, true)
    defer delete(encoded)
    message, ok := worker_execute_incremental_program(&worker, encoded)
    defer delete(message)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")

    string_invoke := worker_find_scalar_invoke(
        &worker,
        "managed-string-chain",
        "proc()->bool",
    )
    string_result, string_aborted, string_called :=
        worker_call_scalar_invoke(&worker, string_invoke, nil)
    testing.expect_value(t, string_called, true)
    testing.expect_value(t, string_aborted, false)
    testing.expect_value(t, string_result.kind, Scalar_Value_Kind.Bool)
    testing.expect_value(t, string_result.int_value, i64(1))
    testing.expect_value(t, worker_test_owned_string_calls, 1)

    releases_before := worker_test_data_releases
    data_invoke := worker_find_scalar_invoke(
        &worker,
        "managed-data-chain",
        "proc()->int",
    )
    data_result, data_aborted, data_called := worker_call_scalar_invoke(
        &worker,
        data_invoke,
        nil,
    )
    testing.expect_value(t, data_called, true)
    testing.expect_value(t, data_aborted, false)
    testing.expect_value(t, data_result.kind, Scalar_Value_Kind.Int)
    testing.expect_value(t, data_result.int_value, i64(42))
    testing.expect_value(
        t,
        worker_test_data_releases-releases_before,
        1,
    )

    releases_before = worker_test_data_releases
    loop_invoke := worker_find_scalar_invoke(
        &worker,
        "managed-data-loop",
        "proc()->int",
    )
    loop_result, loop_aborted, loop_called := worker_call_scalar_invoke(
        &worker,
        loop_invoke,
        nil,
    )
    testing.expect_value(t, loop_called, true)
    testing.expect_value(t, loop_aborted, false)
    testing.expect_value(t, loop_result.kind, Scalar_Value_Kind.Int)
    testing.expect_value(
        t,
        loop_result.int_value,
        i64(releases_before+3),
    )
    testing.expect_value(
        t,
        worker_test_data_releases-releases_before,
        3,
    )

    releases_before = worker_test_data_releases
    worker_test_abort_worker = &worker
    abort_invoke := worker_find_scalar_invoke(
        &worker,
        "managed-data-abort",
        "proc()->int",
    )
    _, abort_aborted, abort_called := worker_call_scalar_invoke(
        &worker,
        abort_invoke,
        nil,
    )
    worker_test_abort_worker = nil
    testing.expect_value(t, abort_called, true)
    testing.expect_value(t, abort_aborted, true)
    testing.expect_value(
        t,
        worker_test_data_releases-releases_before,
        1,
    )
}

@(test)
worker_incremental_native_calls_follow_loaded_adapter_slots :: proc(
    t: ^testing.T,
) {
    if !incremental_native_backend_supported() {
        return
    }
    sync.lock(&worker_execution_plan_test_mutex)
    defer sync.unlock(&worker_execution_plan_test_mutex)
    worker := Worker{allocator = context.allocator}
    defer worker_delete(&worker)
    program := worker_test_incremental_loaded_call_program(
        "use-loaded",
        "test.offset",
        "proc(int:borrowed)->int",
        true,
    )
    encoded, encoded_ok := repl_program.program_encode(program)
    repl_program.program_delete(&program)
    testing.expect_value(t, encoded_ok, true)
    defer delete(encoded)
    missing_message, missing_ok := worker_execute_incremental_program(
        &worker,
        encoded,
    )
    testing.expect_value(t, missing_ok, false)
    testing.expect_value(
        t,
        missing_message,
        "incremental native scalar dependency is unavailable",
    )
    delete(missing_message)
    testing.expect_value(
        t,
        worker_find_scalar_invoke(
            &worker,
            "use-loaded",
            "proc(int:borrowed)->int",
        ) == nil,
        true,
    )

    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.offset"),
        cstring("proc(int:borrowed)->int"),
        cstring("value:int"),
        worker_test_increment_scalar,
    )
    message, ok := worker_execute_incremental_program(&worker, encoded)
    defer delete(message)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    invoke := worker_find_scalar_invoke(
        &worker,
        "use-loaded",
        "proc(int:borrowed)->int",
    )
    args := []Scalar_Value{{kind = .Int, int_value = 41}}
    result, aborted, called := worker_call_scalar_invoke(
        &worker,
        invoke,
        args,
    )
    testing.expect_value(t, called, true)
    testing.expect_value(t, aborted, false)
    testing.expect_value(t, result.int_value, i64(42))

    // A compatible native redefinition updates the existing worker slot. The
    // already-compiled caller follows the slot instead of pinning an address.
    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.offset"),
        cstring("proc(int:borrowed)->int"),
        cstring("value:int"),
        worker_test_add_ten_scalar,
    )
    result, aborted, called = worker_call_scalar_invoke(
        &worker,
        invoke,
        args,
    )
    testing.expect_value(t, called, true)
    testing.expect_value(t, aborted, false)
    testing.expect_value(t, result.int_value, i64(51))

    worker_test_abort_worker = &worker
    defer worker_test_abort_worker = nil
    worker_register_scalar_invoke(
        rawptr(&worker),
        cstring("test.abort"),
        cstring("proc()->int"),
        cstring("value:int"),
        worker_test_abort_scalar,
    )
    abort_program := worker_test_incremental_loaded_call_program(
        "use-abort",
        "test.abort",
        "proc()->int",
        false,
    )
    transitive_abort := repl_program.Procedure{
        name = strings.clone("use-transitive-abort"),
        signature = strings.clone("proc()->int"),
        result_kind = .Int,
        result_expr = 0,
    }
    append(&transitive_abort.expressions, repl_program.Expression{
        kind = .Program_Call,
        value_kind = .Int,
        resolved_name = strings.clone("use-abort"),
        scalar_signature = strings.clone("proc()->int"),
    })
    append(&abort_program.procedures, transitive_abort)
    abort_encoded, abort_encoded_ok :=
        repl_program.program_encode(abort_program)
    repl_program.program_delete(&abort_program)
    testing.expect_value(t, abort_encoded_ok, true)
    defer delete(abort_encoded)
    abort_message, abort_ok := worker_execute_incremental_program(
        &worker,
        abort_encoded,
    )
    defer delete(abort_message)
    testing.expect_value(t, abort_ok, true)
    abort_invoke := worker_find_scalar_invoke(
        &worker,
        "use-abort",
        "proc()->int",
    )
    _, abort_propagated, abort_called := worker_call_scalar_invoke(
        &worker,
        abort_invoke,
        nil,
    )
    testing.expect_value(t, abort_called, true)
    testing.expect_value(t, abort_propagated, true)
    transitive_invoke := worker_find_scalar_invoke(
        &worker,
        "use-transitive-abort",
        "proc()->int",
    )
    _, transitive_aborted, transitive_called := worker_call_scalar_invoke(
        &worker,
        transitive_invoke,
        nil,
    )
    testing.expect_value(t, transitive_called, true)
    testing.expect_value(t, transitive_aborted, true)
}

@(test)
worker_incremental_native_program_redefines_a_typed_proc :: proc(
    t: ^testing.T,
) {
    if !incremental_native_backend_supported() {
        // The backend is optional for ordinary Kvist builds. Cross-platform
        // CI exercises this test whenever LLVM's C API is discoverable.
        return
    }
    sync.lock(&worker_execution_plan_test_mutex)
    defer sync.unlock(&worker_execution_plan_test_mutex)
    worker := Worker{}
    defer worker_delete(&worker)

    first := worker_test_incremental_scale_program(2)
    first_encoded, first_encoded_ok := repl_program.program_encode(first)
    repl_program.program_delete(&first)
    testing.expect_value(t, first_encoded_ok, true)
    defer delete(first_encoded)
    message, ok := worker_execute_incremental_program(&worker, first_encoded)
    defer delete(message)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, message, "")
    first_slot := worker_find_scalar_invoke(
        &worker,
        "scale",
        "proc(int:borrowed)->int",
    )
    testing.expect_value(t, first_slot != nil, true)
    args := []Scalar_Value{{kind = .Int, int_value = 21}}
    first_result, _, first_called := worker_call_scalar_invoke(
        &worker,
        first_slot,
        args,
    )
    testing.expect_value(t, first_called, true)
    testing.expect_value(t, first_result.kind, Scalar_Value_Kind.Int)
    testing.expect_value(t, first_result.int_value, i64(42))

    second := worker_test_incremental_scale_program(3)
    second_encoded, second_encoded_ok := repl_program.program_encode(second)
    repl_program.program_delete(&second)
    testing.expect_value(t, second_encoded_ok, true)
    defer delete(second_encoded)
    second_message, second_ok := worker_execute_incremental_program(
        &worker,
        second_encoded,
    )
    defer delete(second_message)
    testing.expect_value(t, second_ok, true)
    testing.expect_value(t, second_message, "")
    second_slot := worker_find_scalar_invoke(
        &worker,
        "scale",
        "proc(int:borrowed)->int",
    )
    second_result, _, second_called := worker_call_scalar_invoke(
        &worker,
        second_slot,
        args,
    )
    testing.expect_value(t, second_called, true)
    testing.expect_value(t, second_result.int_value, i64(63))

    native_address: rawptr
    for slot in worker.proc_slots {
        if slot.name == "scale" &&
           slot.signature == "proc(int:borrowed)->int" {
            native_address = slot.address
        }
    }
    testing.expect_value(t, native_address != nil, true)
    native_scale := transmute(proc(int) -> int)native_address
    testing.expect_value(t, native_scale(14), 42)
}
