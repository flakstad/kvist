package tests

import "base:runtime"
import "core:dynlib"
import fmt "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:testing"
import "core:thread"
import "core:time"
import kvist "../src/odin/kvist"
import kvist_repl "../src/odin/kvist_repl"
import repl_program "../src/odin/kvist_repl_program"
import olive_reload "../src/odin/olive_reload"

Console_Test_Client :: struct {
    endpoint: string,
    request:  olive_reload.Console_Request,
    response: olive_reload.Console_Response,
    message:  string,
    ok:       bool,
    allocator: runtime.Allocator,
}

Console_Cli_Client :: struct {
    binary:       string,
    endpoint:     string,
    context_file: string,
    repo_root:    string,
    request_file: ^os.File,
    stdout:       []u8,
    stderr:       []u8,
    state:        os.Process_State,
    exec_err:     os.Error,
    allocator:    runtime.Allocator,
}

console_test_submit :: proc(data: rawptr) {
    context = runtime.default_context()
    state := transmute(^Console_Test_Client)data
    context.allocator = state.allocator
    defer runtime.default_temp_allocator_destroy(
        auto_cast context.temp_allocator.data,
    )
    state.response, state.message, state.ok =
        olive_reload.console_submit(
            state.endpoint,
            state.request,
            2 * time.Second,
        )
}

console_cli_run :: proc(data: rawptr) {
    context = runtime.default_context()
    defer runtime.default_temp_allocator_destroy(
        auto_cast context.temp_allocator.data,
    )
    client := transmute(^Console_Cli_Client)data
    context.allocator = client.allocator
    command: [dynamic]string
    defer delete(command)
    append(&command, client.binary, "repl")
    if client.context_file != "" {
        append(&command, client.context_file)
    }
    append(&command, "--attach", client.endpoint, "--protocol", "jsonl")
    inherited_environment, environment_err := os.environ(client.allocator)
    if environment_err != nil {
        client.exec_err = environment_err
        return
    }
    defer {
        for entry in inherited_environment do delete(entry)
        delete(inherited_environment)
    }
    environment := make(
        [dynamic]string,
        0,
        len(inherited_environment)+1,
        client.allocator,
    )
    defer delete(environment)
    append(&environment, ..inherited_environment)
    package_root, package_root_err :=
        os.join_path(
            {client.repo_root, "src", "kvist"},
            client.allocator,
        )
    if package_root_err != nil {
        client.exec_err = package_root_err
        return
    }
    defer delete(package_root)
    kvist_root := fmt.aprintf("KVIST_ROOT=%s", package_root)
    defer delete(kvist_root)
    append(&environment, kvist_root)
    client.state,
    client.stdout,
    client.stderr,
    client.exec_err = os.process_exec(
        os.Process_Desc{
            command = command[:],
            working_dir = client.repo_root,
            env = environment[:],
            stdin = client.request_file,
        },
        client.allocator,
    )
}

repl_jsonl_event_line :: proc(output, id, kind: string) -> (string, bool) {
    needle := fmt.tprintf(`"id":"%s","kind":"%s"`, id, kind)
    offset := strings.index(output, needle)
    if offset < 0 {
        return "", false
    }
    start := offset
    for start > 0 && output[start-1] != '\n' {
        start -= 1
    }
    line := output[start:]
    if end := strings.index(line, "\n"); end >= 0 {
        line = line[:end]
    }
    return line, true
}

repl_jsonl_int_field :: proc(line, field: string) -> (int, bool) {
    needle := fmt.tprintf(`"%s":`, field)
    offset := strings.index(line, needle)
    if offset < 0 {
        return 0, false
    }
    start := offset+len(needle)
    end := start
    for end < len(line) && line[end] >= '0' && line[end] <= '9' {
        end += 1
    }
    if end == start {
        return 0, false
    }
    return strconv.parse_int(line[start:end])
}

console_test_handler :: proc(
    ctx: rawptr,
    input: string,
) -> (string, string, bool) {
    calls := transmute(^int)ctx
    calls^ += 1
    if input == "hello" {
        return "host:hello", "", true
    }
    return "host:unexpected", "", true
}

@(test)
compile_repl_emits_backend_neutral_incremental_procedures :: proc(
    t: ^testing.T,
) {
    incremental := kvist.Repl_Incremental_Program{}
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        `(defn square [x: int] -> int (* x x))
(defn score [x: int] -> int
  (if (> x 0) (+ (square x) 1) 0))`,
        repl_generation = true,
        repl_incremental_program = &incremental,
    )
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)
    defer kvist.repl_incremental_program_delete(&incremental)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    // Ordinary emission still runs first and remains the semantic oracle.
    testing.expect_value(t, result.output != "", true)
    testing.expect_value(t, incremental.encoded != "", true)
    decoded, decoded_ok := repl_program.program_decode(incremental.encoded)
    defer repl_program.program_delete(&decoded)
    testing.expect_value(t, decoded_ok, true)
    testing.expect_value(t, len(decoded.procedures), 2)
    if len(decoded.procedures) != 2 {
        return
    }
    testing.expect_value(t, decoded.procedures[0].name, "square")
    testing.expect_value(t, decoded.procedures[0].parameter_kinds[0], repl_program.Value_Kind.Int)
    testing.expect_value(t, decoded.procedures[1].name, "score")
    saw_program_call := false
    for expression in decoded.procedures[1].expressions {
        if expression.kind == .Program_Call &&
           expression.resolved_name == "square" {
            saw_program_call = true
        }
    }
    testing.expect_value(t, saw_program_call, true)
}

@(test)
compile_repl_incremental_managed_procedures_preserve_native_ownership :: proc(
    t: ^testing.T,
) {
    scalar_invokes := [?]kvist.Repl_Scalar_Invoke_Metadata{
        {
            name = "str__lower",
            signature = "proc(string:borrowed)->string:owned",
            result_abi = "value:string",
        },
        {
            name = "str__contains_p",
            signature =
                "proc(string:borrowed,string:borrowed)->bool",
            result_abi = "value:bool",
        },
        {
            name = "data__empty_map",
            signature = "proc()->Data:owned",
            result_abi = "value:Data",
        },
        {
            name = "data__count",
            signature = "proc(Data:borrowed)->int",
            result_abi = "value:int",
        },
    }
    session_source := `(import str "kvist:str")
(import data "kvist:data")`

    explicit := kvist.Repl_Incremental_Program{}
    explicit_result, explicit_err, explicit_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(defn normalized? [] -> bool
  (let [value (str.lower "KVIST") :defer]
    (str.contains? value "kvist")))`,
            repl_generation = true,
            repl_session_source = session_source,
            repl_incremental_program = &explicit,
            repl_scalar_invokes = scalar_invokes[:],
        )
    defer delete(explicit_result.output)
    defer kvist.source_map_slice_delete(explicit_result.source_map)
    defer kvist.compile_warning_slice_delete(explicit_result.warnings)
    defer kvist.repl_incremental_program_delete(&explicit)
    testing.expect_value(t, explicit_ok, true)
    if !explicit_ok {
        testing.expect_value(t, explicit_err.message, "")
    }
    explicit_program, explicit_decoded :=
        repl_program.program_decode(explicit.encoded)
    defer repl_program.program_delete(&explicit_program)
    testing.expect_value(t, explicit_decoded, true)
    testing.expect_value(t, len(explicit_program.procedures), 1)
    if len(explicit_program.procedures) == 1 {
        testing.expect_value(
            t,
            explicit_program.procedures[0].bindings[0].managed_cleanup,
            true,
        )
    }

    unmanaged := kvist.Repl_Incremental_Program{}
    unmanaged_result, unmanaged_err, unmanaged_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(defn normalized? [] -> bool
  (let [value (str.lower "KVIST")]
    (str.contains? value "kvist")))`,
            repl_generation = true,
            repl_session_source = session_source,
            repl_incremental_program = &unmanaged,
            repl_scalar_invokes = scalar_invokes[:],
        )
    defer delete(unmanaged_result.output)
    defer kvist.source_map_slice_delete(unmanaged_result.source_map)
    defer kvist.compile_warning_slice_delete(unmanaged_result.warnings)
    defer kvist.repl_incremental_program_delete(&unmanaged)
    testing.expect_value(t, unmanaged_ok, true)
    if !unmanaged_ok {
        testing.expect_value(t, unmanaged_err.message, "")
    }
    testing.expect_value(t, unmanaged.encoded, "")
    testing.expect_value(t, unmanaged_result.output != "", true)

    escaping := kvist.Repl_Incremental_Program{}
    escaping_result, escaping_err, escaping_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(defn escaped-managed-data-size [] -> int
  (data.count (let [value (data.empty-map)] value)))`,
            repl_generation = true,
            repl_session_source = session_source,
            repl_incremental_program = &escaping,
            repl_scalar_invokes = scalar_invokes[:],
        )
    defer delete(escaping_result.output)
    defer kvist.source_map_slice_delete(escaping_result.source_map)
    defer kvist.compile_warning_slice_delete(escaping_result.warnings)
    defer kvist.repl_incremental_program_delete(&escaping)
    testing.expect_value(t, escaping_ok, true)
    if !escaping_ok {
        testing.expect_value(t, escaping_err.message, "")
    }
    testing.expect_value(t, escaping.encoded, "")
    testing.expect_value(t, escaping_result.output != "", true)

    data_program := kvist.Repl_Incremental_Program{}
    data_result, data_err, data_ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        `(defn data-size [] -> int
  (let [value (data.empty-map)]
    (data.count value)))`,
        repl_generation = true,
        repl_session_source = session_source,
        repl_incremental_program = &data_program,
        repl_scalar_invokes = scalar_invokes[:],
    )
    defer delete(data_result.output)
    defer kvist.source_map_slice_delete(data_result.source_map)
    defer kvist.compile_warning_slice_delete(data_result.warnings)
    defer kvist.repl_incremental_program_delete(&data_program)
    testing.expect_value(t, data_ok, true)
    if !data_ok {
        testing.expect_value(t, data_err.message, "")
    }
    decoded_data, data_decoded :=
        repl_program.program_decode(data_program.encoded)
    defer repl_program.program_delete(&decoded_data)
    testing.expect_value(t, data_decoded, true)
    testing.expect_value(t, len(decoded_data.procedures), 1)
    if len(decoded_data.procedures) == 1 {
        testing.expect_value(
            t,
            decoded_data.procedures[0].bindings[0].managed_cleanup,
            true,
        )
    }
}

@(test)
compile_repl_incremental_program_falls_back_as_one_semantic_unit :: proc(
    t: ^testing.T,
) {
    incremental := kvist.Repl_Incremental_Program{}
    result, _, ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        `(defn fast [x: int] -> int (+ x 1))
(defn needs-native [x: int] -> int (do (println x) x))`,
        repl_generation = true,
        repl_incremental_program = &incremental,
    )
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)
    defer kvist.repl_incremental_program_delete(&incremental)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, incremental.encoded, "")
    testing.expect_value(t, result.output != "", true)
}

@(test)
compile_repl_incremental_program_models_structured_procedure_control :: proc(
    t: ^testing.T,
) {
    incremental := kvist.Repl_Incremental_Program{}
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        `(defn count-up [limit: int] -> int
  (defvar index: int 0)
  (while (< index limit)
    (inc! index))
  index)
(defn classify [x: int] -> int
  (if (< x 0) (return 40))
  (+ x 2))`,
        repl_generation = true,
        repl_incremental_program = &incremental,
    )
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)
    defer kvist.repl_incremental_program_delete(&incremental)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    decoded, decoded_ok := repl_program.program_decode(incremental.encoded)
    defer repl_program.program_delete(&decoded)
    testing.expect_value(t, decoded_ok, true)
    testing.expect_value(t, len(decoded.procedures), 2)
    saw_mutation := false
    saw_loop := false
    saw_return := false
    for procedure in decoded.procedures {
        for expression in procedure.expressions {
            #partial switch expression.kind {
            case .Set_Local: saw_mutation = true
            case .While:     saw_loop = true
            case .Return:    saw_return = true
            case:
            }
        }
    }
    testing.expect_value(t, saw_mutation, true)
    testing.expect_value(t, saw_loop, true)
    testing.expect_value(t, saw_return, true)
}

@(test)
compile_repl_semantic_plan_uses_expanded_and_typed_forms :: proc(
    t: ^testing.T,
) {
    cases := [?]struct {
        source:         string,
        session_source: string,
        result_abi:     string,
    }{
        {
            source = "(session-add 40)",
            session_source =
                "(defmacro session-add [x] (quasiquote (+ (unquote x) 2)))",
            result_abi = "value:int",
        },
        {
            source = "(let [x: f64 20] (+ x 22.0))",
            result_abi = "value:f64",
        },
        {
            source = "(+ 20 22.0)",
            result_abi = "value:f64",
        },
        {
            source = `(let [x: string "Kvist"] x)`,
            result_abi = "value:string",
        },
        {
            source = `(let [x: string "Kvist"] (= x "Kvist"))`,
            result_abi = "value:bool",
        },
        {
            source = "(if true 42 0)",
            result_abi = "value:int",
        },
    }
    for item in cases {
        plan := kvist.Repl_Execution_Plan{}
        result, err, ok := kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            item.source,
            repl_generation = true,
            repl_session_source = item.session_source,
            repl_context_cache_key = fmt.tprintf(
                "semantic-plan-context:%s",
                item.session_source,
            ),
            repl_execution_plan = &plan,
        )
        defer delete(result.output)
        defer kvist.source_map_slice_delete(result.source_map)
        defer kvist.compile_warning_slice_delete(result.warnings)
        testing.expect_value(t, ok, true)
        if !ok {
            testing.expect_value(t, err.message, "")
        }
        testing.expect_value(t, result.output, "")
        testing.expect_value(t, plan.encoded != "", true)
        testing.expect_value(t, plan.result_abi, item.result_abi)
        testing.expect_value(t, plan.recent_result_mask, u8(0))
        kvist.repl_execution_plan_delete(&plan)
    }

    recent_plan := kvist.Repl_Execution_Plan{}
    recent_result, recent_err, recent_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            "(let [value: int *1] (+ value 1))",
            repl_generation = true,
            repl_recent_result_types = []string{"int"},
            repl_execution_plan = &recent_plan,
        )
    defer delete(recent_result.output)
    defer kvist.source_map_slice_delete(recent_result.source_map)
    defer kvist.compile_warning_slice_delete(recent_result.warnings)
    defer kvist.repl_execution_plan_delete(&recent_plan)
    testing.expect_value(t, recent_ok, true)
    if !recent_ok {
        testing.expect_value(t, recent_err.message, "")
    }
    testing.expect_value(t, recent_result.output, "")
    testing.expect_value(t, recent_plan.recent_result_mask, u8(1))

    scalar_invokes := [?]kvist.Repl_Scalar_Invoke_Metadata{
        {
            name = "str__contains_p",
            signature = "proc(string:borrowed,string:borrowed)->bool",
            result_abi = "value:bool",
        },
        {
            name = "str__trim",
            signature = "proc(string:borrowed)->string:borrowed",
            result_abi = "value:string",
        },
        {
            name = "str__trim_prefix",
            signature =
                "proc(string:borrowed,string:borrowed)->string:borrowed",
            result_abi = "value:string",
        },
        {
            name = "str__lower",
            signature = "proc(string:borrowed)->string:owned",
            result_abi = "value:string",
        },
        {
            name = "data__empty_map",
            signature = "proc()->Data:owned",
            result_abi = "value:Data",
        },
        {
            name = "data__count",
            signature = "proc(Data:borrowed)->int",
            result_abi = "value:int",
        },
        {
            name = "data__first",
            signature = "proc(Data:borrowed)->Data:owned",
            result_abi = "value:Data",
        },
        {
            name = "profile_card",
            signature =
                "proc(string:borrowed,string:borrowed)->Data:owned",
            result_abi = "value:Data",
        },
    }
    adapter_plan := kvist.Repl_Execution_Plan{}
    adapter_result, adapter_err, adapter_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(and (str.contains? "Kvist REPL" "REPL") true)`,
            repl_generation = true,
            repl_session_source = `(import str "kvist:str")`,
            repl_context_cache_key = "semantic-plan-context:str",
            repl_execution_plan = &adapter_plan,
            repl_scalar_invokes = scalar_invokes[:],
        )
    defer delete(adapter_result.output)
    defer kvist.source_map_slice_delete(adapter_result.source_map)
    defer kvist.compile_warning_slice_delete(adapter_result.warnings)
    defer kvist.repl_execution_plan_delete(&adapter_plan)
    testing.expect_value(t, adapter_ok, true)
    if !adapter_ok {
        testing.expect_value(t, adapter_err.message, "")
    }
    testing.expect_value(t, adapter_result.output, "")
    testing.expect_value(
        t,
        strings.contains(adapter_plan.encoded, "|c2:"),
        true,
    )

    string_adapter_plan := kvist.Repl_Execution_Plan{}
    string_adapter_result, string_adapter_err, string_adapter_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(= (str.trim " Kvist ") "Kvist")`,
            repl_generation = true,
            repl_session_source = `(import str "kvist:str")`,
            repl_context_cache_key = "semantic-plan-context:str",
            repl_execution_plan = &string_adapter_plan,
            repl_scalar_invokes = scalar_invokes[:],
        )
    defer delete(string_adapter_result.output)
    defer kvist.source_map_slice_delete(string_adapter_result.source_map)
    defer kvist.compile_warning_slice_delete(string_adapter_result.warnings)
    defer kvist.repl_execution_plan_delete(&string_adapter_plan)
    testing.expect_value(t, string_adapter_ok, true)
    if !string_adapter_ok {
        testing.expect_value(t, string_adapter_err.message, "")
    }
    testing.expect_value(t, string_adapter_result.output, "")
    testing.expect_value(
        t,
        strings.contains(string_adapter_plan.encoded, "|c1:"),
        true,
    )

    nested_string_plan := kvist.Repl_Execution_Plan{}
    nested_string_result, nested_string_err, nested_string_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(= (str.trim-prefix (str.trim " Kvist ") "K") "vist")`,
            repl_generation = true,
            repl_session_source = `(import str "kvist:str")`,
            repl_execution_plan = &nested_string_plan,
            repl_scalar_invokes = scalar_invokes[:],
        )
    defer delete(nested_string_result.output)
    defer kvist.source_map_slice_delete(nested_string_result.source_map)
    defer kvist.compile_warning_slice_delete(nested_string_result.warnings)
    defer kvist.repl_execution_plan_delete(&nested_string_plan)
    testing.expect_value(t, nested_string_ok, true)
    if !nested_string_ok {
        testing.expect_value(t, nested_string_err.message, "")
    }
    testing.expect_value(t, nested_string_result.output, "")
    testing.expect_value(
        t,
        strings.contains(nested_string_plan.encoded, "|c1:") &&
        strings.contains(nested_string_plan.encoded, "|c2:"),
        true,
    )

    owned_string_plan := kvist.Repl_Execution_Plan{}
    owned_string_result, owned_string_err, owned_string_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(= (str.lower "KVIST") "kvist")`,
            repl_generation = true,
            repl_session_source = `(import str "kvist:str")`,
            repl_execution_plan = &owned_string_plan,
            repl_scalar_invokes = scalar_invokes[:],
        )
    defer delete(owned_string_result.output)
    defer kvist.source_map_slice_delete(owned_string_result.source_map)
    defer kvist.compile_warning_slice_delete(owned_string_result.warnings)
    defer kvist.repl_execution_plan_delete(&owned_string_plan)
    testing.expect_value(t, owned_string_ok, true)
    if !owned_string_ok {
        testing.expect_value(t, owned_string_err.message, "")
    }
    testing.expect_value(t, owned_string_result.output, "")
    testing.expect_value(
        t,
        strings.contains(owned_string_plan.encoded, "|c1:"),
        true,
    )

    owned_borrowed_plan := kvist.Repl_Execution_Plan{}
    owned_borrowed_result, owned_borrowed_err, owned_borrowed_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(= (str.trim (str.lower " KVIST ")) "kvist")`,
            repl_generation = true,
            repl_session_source = `(import str "kvist:str")`,
            repl_execution_plan = &owned_borrowed_plan,
            repl_scalar_invokes = scalar_invokes[:],
        )
    defer delete(owned_borrowed_result.output)
    defer kvist.source_map_slice_delete(owned_borrowed_result.source_map)
    defer kvist.compile_warning_slice_delete(owned_borrowed_result.warnings)
    defer kvist.repl_execution_plan_delete(&owned_borrowed_plan)
    testing.expect_value(t, owned_borrowed_ok, true)
    if !owned_borrowed_ok {
        testing.expect_value(t, owned_borrowed_err.message, "")
    }
    testing.expect_value(t, owned_borrowed_result.output, "")
    testing.expect_value(
        t,
        strings.count(owned_borrowed_plan.encoded, "|c1:"),
        2,
    )

    owned_local_plan := kvist.Repl_Execution_Plan{}
    owned_local_result, owned_local_err, owned_local_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(let [lowered (str.lower "KVIST")] (= lowered "kvist"))`,
            repl_generation = true,
            repl_session_source = `(import str "kvist:str")`,
            repl_execution_plan = &owned_local_plan,
            repl_scalar_invokes = scalar_invokes[:],
        )
    defer delete(owned_local_result.output)
    defer kvist.source_map_slice_delete(owned_local_result.source_map)
    defer kvist.compile_warning_slice_delete(owned_local_result.warnings)
    defer kvist.repl_execution_plan_delete(&owned_local_plan)
    testing.expect_value(t, owned_local_ok, true)
    if !owned_local_ok {
        testing.expect_value(t, owned_local_err.message, "")
    }
    testing.expect_value(t, owned_local_result.output, "")
    testing.expect_value(
        t,
        strings.count(owned_local_plan.encoded, "|c1:"),
        1,
    )

    data_plan := kvist.Repl_Execution_Plan{}
    data_result, data_err, data_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(data.count (data.empty-map))`,
            repl_generation = true,
            repl_session_source = `(import data "kvist:data")`,
            repl_execution_plan = &data_plan,
            repl_scalar_invokes = scalar_invokes[:],
        )
    defer delete(data_result.output)
    defer kvist.source_map_slice_delete(data_result.source_map)
    defer kvist.compile_warning_slice_delete(data_result.warnings)
    defer kvist.repl_execution_plan_delete(&data_plan)
    testing.expect_value(t, data_ok, true)
    if !data_ok {
        testing.expect_value(t, data_err.message, "")
    }
    testing.expect_value(t, data_result.output, "")
    testing.expect_value(
        t,
        strings.contains(data_plan.encoded, "|c0:") &&
        strings.contains(data_plan.encoded, "|c1:"),
        true,
    )

    recent_data_plan := kvist.Repl_Execution_Plan{}
    recent_data_result, recent_data_err, recent_data_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(data.count *1)`,
            repl_generation = true,
            repl_session_source = `(import data "kvist:data")`,
            repl_recent_result_types = []string{"Data"},
            repl_execution_plan = &recent_data_plan,
            repl_scalar_invokes = scalar_invokes[:],
        )
    defer delete(recent_data_result.output)
    defer kvist.source_map_slice_delete(recent_data_result.source_map)
    defer kvist.compile_warning_slice_delete(recent_data_result.warnings)
    defer kvist.repl_execution_plan_delete(&recent_data_plan)
    testing.expect_value(t, recent_data_ok, true)
    if !recent_data_ok {
        testing.expect_value(t, recent_data_err.message, "")
    }
    testing.expect_value(t, recent_data_result.output, "")
    testing.expect_value(
        t,
        strings.contains(recent_data_plan.encoded, "|r:0") &&
        strings.contains(recent_data_plan.encoded, "|c1:"),
        true,
    )

    final_data_plan := kvist.Repl_Execution_Plan{}
    final_data_result, final_data_err, final_data_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(data.empty-map)`,
            repl_generation = true,
            repl_session_source = `(import data "kvist:data")`,
            repl_execution_plan = &final_data_plan,
            repl_scalar_invokes = scalar_invokes[:],
        )
    defer delete(final_data_result.output)
    defer kvist.source_map_slice_delete(final_data_result.source_map)
    defer kvist.compile_warning_slice_delete(final_data_result.warnings)
    defer kvist.repl_execution_plan_delete(&final_data_plan)
    testing.expect_value(t, final_data_ok, true)
    if !final_data_ok {
        testing.expect_value(t, final_data_err.message, "")
    }
    testing.expect_value(t, final_data_result.output, "")
    testing.expect_value(
        t,
        strings.has_prefix(final_data_plan.encoded, "9|d|r|") &&
        strings.contains(final_data_plan.encoded, "|c0:"),
        true,
    )

    conditional_data_plan := kvist.Repl_Execution_Plan{}
    conditional_data_result, conditional_data_err, conditional_data_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(if true (data.empty-map) (data.empty-map))`,
            repl_generation = true,
            repl_session_source = `(import data "kvist:data")`,
            repl_execution_plan = &conditional_data_plan,
            repl_scalar_invokes = scalar_invokes[:],
        )
    defer delete(conditional_data_result.output)
    defer kvist.source_map_slice_delete(conditional_data_result.source_map)
    defer kvist.compile_warning_slice_delete(conditional_data_result.warnings)
    defer kvist.repl_execution_plan_delete(&conditional_data_plan)
    testing.expect_value(t, conditional_data_ok, true)
    if !conditional_data_ok {
        testing.expect_value(t, conditional_data_err.message, "")
    }
    testing.expect_value(t, conditional_data_result.output, "")
    testing.expect_value(
        t,
        strings.has_prefix(conditional_data_plan.encoded, "9|d|r|"),
        true,
    )

    unmanaged_data_plan := kvist.Repl_Execution_Plan{}
    unmanaged_data_result, unmanaged_data_err, unmanaged_data_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `*1`,
            repl_generation = true,
            repl_session_source = `(import data "kvist:data")`,
            repl_recent_result_types = []string{"Data"},
            repl_execution_plan = &unmanaged_data_plan,
            repl_scalar_invokes = scalar_invokes[:],
        )
    defer delete(unmanaged_data_result.output)
    defer kvist.source_map_slice_delete(unmanaged_data_result.source_map)
    defer kvist.compile_warning_slice_delete(unmanaged_data_result.warnings)
    defer kvist.repl_execution_plan_delete(&unmanaged_data_plan)
    testing.expect_value(t, unmanaged_data_ok, true)
    if !unmanaged_data_ok {
        testing.expect_value(t, unmanaged_data_err.message, "")
    }
    testing.expect_value(t, unmanaged_data_plan.encoded, "")
    testing.expect_value(t, unmanaged_data_result.output != "", true)

    session_data_plan := kvist.Repl_Execution_Plan{}
    session_data_result, session_data_err, session_data_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(data.first (profile-card "Ada Lovelace" "Mathematician"))`,
            repl_generation = true,
            repl_session_source = `(import data "kvist:data")
(defn profile-card [name: string, role: string] -> Data
  [:article {:class "profile"} [:h2 name] [:p role]])`,
            repl_execution_plan = &session_data_plan,
            repl_scalar_invokes = scalar_invokes[:],
        )
    defer delete(session_data_result.output)
    defer kvist.source_map_slice_delete(session_data_result.source_map)
    defer kvist.compile_warning_slice_delete(session_data_result.warnings)
    defer kvist.repl_execution_plan_delete(&session_data_plan)
    testing.expect_value(t, session_data_ok, true)
    if !session_data_ok {
        testing.expect_value(t, session_data_err.message, "")
    }
    testing.expect_value(t, session_data_result.output, "")
    testing.expect_value(
        t,
        strings.has_prefix(session_data_plan.encoded, "9|d|r|") &&
        strings.contains(session_data_plan.encoded, "|c2:") &&
        strings.contains(session_data_plan.encoded, "|c1:"),
        true,
    )

    stale_session_data_plan := kvist.Repl_Execution_Plan{}
    stale_session_data_result, stale_session_data_err,
    stale_session_data_ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        `(data.first (profile-card "Ada Lovelace" "Mathematician"))`,
        repl_generation = true,
        repl_session_source = `(import data "kvist:data")
(defn profile-card [name: string, role: string] -> Data
  [:article {:class "profile"} [:h2 name] [:p role]])`,
        repl_execution_plan = &stale_session_data_plan,
        repl_stale_proc_names = []string{"profile_card"},
        repl_scalar_invokes = scalar_invokes[:],
    )
    defer delete(stale_session_data_result.output)
    defer kvist.source_map_slice_delete(stale_session_data_result.source_map)
    defer kvist.compile_warning_slice_delete(
        stale_session_data_result.warnings,
    )
    defer kvist.repl_execution_plan_delete(&stale_session_data_plan)
    testing.expect_value(t, stale_session_data_ok, true)
    if !stale_session_data_ok {
        testing.expect_value(t, stale_session_data_err.message, "")
    }
    testing.expect_value(t, stale_session_data_plan.encoded, "")
    testing.expect_value(t, stale_session_data_result.output != "", true)

    fallback_plan := kvist.Repl_Execution_Plan{}
    fallback, fallback_err, fallback_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(str "semantic" " fallback")`,
            repl_generation = true,
            repl_execution_plan = &fallback_plan,
        )
    defer delete(fallback.output)
    defer kvist.source_map_slice_delete(fallback.source_map)
    defer kvist.compile_warning_slice_delete(fallback.warnings)
    defer kvist.repl_execution_plan_delete(&fallback_plan)
    testing.expect_value(t, fallback_ok, true)
    if !fallback_ok {
        testing.expect_value(t, fallback_err.message, "")
    }
    testing.expect_value(t, fallback_plan.encoded, "")
    testing.expect_value(t, fallback.output != "", true)

    native_only_sources := [?]string{
        "1e3",
        "(if true 7 (/ 1 0))",
        "(let [x: int 1.5] x)",
        "(let [x: f32 20] x)",
        "(return 42)",
        "(do (if true 1 2) 42)",
        "(let [value: int 0] (if true (set! value 42)) value)",
        "(do (if true (do (defvar hidden: int 42) " +
            "(discard hidden))) hidden)",
        "(do (defvar index: int 0) " +
            "(while (< index 1) (println index) " +
            "(set! index (+ index 1))) index)",
        "(do (defvar index: int 0) " +
            "(while (< index 1) (+ index 1)) index)",
        "(do (defvar index: int 0) " +
            "(while (< index 1) (defvar hidden: int 42) " +
            "(set! index (+ index 1))) hidden)",
        "(break)",
        "(continue)",
        "(do (defvar value: int 0) (break value) value)",
        "(let [value: int 0] (inc! value) value)",
        "(do (defvar value: bool false) (inc! value) value)",
        "(do (defvar value: int 0) (toggle! value) value)",
        "(do (defvar value: int 0) (mut! value += 1) value)",
        "(= 1 1 1)",
        "(+ 9999999999999999999999999999999999999999 0.5)",
    }
    for source in native_only_sources {
        native_plan := kvist.Repl_Execution_Plan{}
        native_result, native_err, _ := kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            source,
            repl_generation = true,
            repl_execution_plan = &native_plan,
        )
        defer delete(native_result.output)
        defer kvist.source_map_slice_delete(native_result.source_map)
        defer kvist.compile_warning_slice_delete(native_result.warnings)
        testing.expect_value(t, native_plan.encoded, "")
        kvist.repl_execution_plan_delete(&native_plan)
        kvist.compile_error_delete(&native_err)
    }

    history_plan := kvist.Repl_Execution_Plan{}
    history_result, _, _ := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        "(+ *1 0.5)",
        repl_generation = true,
        repl_recent_result_types = []string{"int"},
        repl_execution_plan = &history_plan,
    )
    defer delete(history_result.output)
    defer kvist.source_map_slice_delete(history_result.source_map)
    defer kvist.compile_warning_slice_delete(history_result.warnings)
    defer kvist.repl_execution_plan_delete(&history_plan)
    testing.expect_value(t, history_plan.encoded, "")

    unsafe_return_plan := kvist.Repl_Execution_Plan{}
    unsafe_return_result, unsafe_return_err, _ :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            "(/ 84 (maybe-zero -1))",
            repl_generation = true,
            repl_session_source =
                "(defn maybe-zero [x: int] -> int " +
                "(if (< x 0) (return 0)) 2)",
            repl_execution_plan = &unsafe_return_plan,
        )
    defer delete(unsafe_return_result.output)
    defer kvist.source_map_slice_delete(unsafe_return_result.source_map)
    defer kvist.compile_warning_slice_delete(unsafe_return_result.warnings)
    defer kvist.repl_execution_plan_delete(&unsafe_return_plan)
    defer kvist.compile_error_delete(&unsafe_return_err)
    testing.expect_value(t, unsafe_return_plan.encoded, "")
}

@(test)
compile_repl_generation_exports_native_batch_entry :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        "(println \"first\")\n(+ 10 20)",
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(t, strings.contains(result.output, "@(export)\nkvist_repl_api_version: u32 = 30"), true)
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_repl_stabilize_result :: proc "c"`,
        ),
        true,
    )
    testing.expect_value(t, strings.contains(result.output, "kvist_repl_run :: proc \"c\" (host: ^Kvist_Repl_Host_API) {"), true)
    testing.expect_value(t, strings.contains(result.output, "context = repl_runtime.default_context()"), true)
    testing.expect_value(t, strings.contains(result.output, "kvist_repl_host = host"), true)
    testing.expect_value(t, strings.contains(result.output, "allocator: repl_runtime.Allocator"), true)
    testing.expect_value(t, strings.contains(result.output, "context.allocator = host.allocator"), true)
    testing.expect_value(t, strings.contains(result.output, "transfer_result_allocation: Kvist_Repl_Transfer_Result_Allocation"), true)
    testing.expect_value(t, strings.contains(result.output, "retain_result_allocation: Kvist_Repl_Retain_Result_Allocation"), true)
    testing.expect_value(t, strings.contains(result.output, "transfer_binding_allocation: Kvist_Repl_Transfer_Binding_Allocation"), true)
    testing.expect_value(t, strings.contains(result.output, "retain_binding_allocation: Kvist_Repl_Retain_Binding_Allocation"), true)
    testing.expect_value(t, strings.contains(result.output, "debug_flags: Kvist_Repl_Debug_Flags"), true)
    testing.expect_value(t, strings.contains(result.output, "trace_point: Kvist_Repl_Trace_Point"), true)
    testing.expect_value(t, strings.contains(result.output, "trace_values: Kvist_Repl_Trace_Values"), true)
    testing.expect_value(t, strings.contains(result.output, "condition: Kvist_Repl_Condition"), true)
    testing.expect_value(t, strings.contains(result.output, "emit_output: Kvist_Repl_Emit_Output"), true)
    testing.expect_value(t, strings.contains(result.output, "render_scalar_result: Kvist_Repl_Render_Scalar_Result"), true)
    testing.expect_value(t, strings.contains(result.output, "register_scalar_invoke: Kvist_Repl_Register_Scalar_Invoke"), true)
    testing.expect_value(t, strings.contains(result.output, "emit_stream_output: Kvist_Repl_Emit_Output"), true)
    testing.expect_value(t, strings.contains(result.output, "enter_frame: Kvist_Repl_Enter_Frame"), true)
    testing.expect_value(t, strings.contains(result.output, "leave_frame: Kvist_Repl_Leave_Frame"), true)
    testing.expect_value(t, strings.contains(result.output, "kvist_repl_host.debug_flags(kvist_repl_host.ctx)"), true)
    testing.expect_value(t, strings.contains(result.output, "kvist_repl_host.trace_point(kvist_repl_host.ctx"), true)
    testing.expect_value(t, strings.contains(result.output, "kvist_repl_host.trace_values(kvist_repl_host.ctx"), true)
    testing.expect_value(t, strings.contains(result.output, `host.render_scalar_result(host.ctx, "int", transmute(rawptr)kvist_repl_result_impl)`), true)
    testing.expect_value(t, strings.contains(result.output, "kvist_repl_println(\"first\")"), true)
}

@(test)
compile_repl_data_result_emits_shared_allocation_adapter :: proc(
    t: ^testing.T,
) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        "(let [answer 1] (quasiquote {:answer (unquote answer)}))",
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_repl_retain_data_allocations :: proc(value: Data, visited: ^map[^Data_Node]bool)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "value.node == nil || value.node in visited^",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "retain_result_allocation(kvist_repl_host.ctx, rawptr(value.node))",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "retain_result_allocation(kvist_repl_host.ctx, rawptr(raw_data(value.node.entries)))",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_repl_data_visited := make(map[^Data_Node]bool)",
        ),
        true,
    )
}

@(test)
compile_repl_map_result_emits_backing_and_nested_adapters :: proc(
    t: ^testing.T,
) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        `(map[string]Data {"answer" (let [answer 1] (quasiquote {:value (unquote answer)}))})`,
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "rawptr(repl_runtime.map_data(transmute(repl_runtime.Raw_Map)value))",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "for kvist_transfer_key_",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_repl_retain_data_allocations(kvist_transfer_value_",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_repl_data_visited := make(map[^Data_Node]bool)",
        ),
        true,
    )
}

@(test)
compile_repl_binding_emits_generation_qualified_allocation_adapter :: proc(
    t: ^testing.T,
) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        `(def bound-values: map[string]Data (map[string]Data {"answer" (let [answer 1] (quasiquote {:value (unquote answer)}))}))`,
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `bound_values__repl_register_allocations :: proc(value: map[string]Data)`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `transfer_binding_allocation(kvist_repl_host.ctx, "bound_values"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `retain_binding_allocation(kvist_repl_host.ctx, "bound_values"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "bound_values__repl_register_allocations(bound_values__repl_storage)",
        ),
        true,
    )
}

@(test)
compile_repl_pointer_result_reports_unretained_lifecycle :: proc(
    t: ^testing.T,
) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        "(defn pointer-result [] -> rawptr nil)\n(pointer-result)",
        repl_generation = true,
    )
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
        testing.expect_value(
            t,
            result.warnings[0].code,
            kvist.Compile_Warning_Code.Repl_Unretained_Lifecycle,
        )
        testing.expect_value(
            t,
            strings.contains(
                result.warnings[0].message,
                "REPL result of type rawptr is evaluated for this submission but is not retained in *1",
            ),
            true,
        )
    }
    testing.expect_value(
        t,
        strings.contains(result.output, "host.register_result"),
        false,
    )
    testing.expect_value(
        t,
        kvist.compile_warning_code_text(
            kvist.Compile_Warning_Code.Repl_Unretained_Lifecycle,
        ),
        "KVR001",
    )

    _, inspect_err, inspect_ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        "(defn pointer-result [] -> rawptr nil)\n(pointer-result)",
        repl_generation = true,
        repl_inspect_only = true,
    )
    defer kvist.compile_error_delete(&inspect_err)
    testing.expect_value(t, inspect_ok, false)
    testing.expect_value(
        t,
        strings.contains(
            inspect_err.message,
            "native inspection cannot retain a pointer",
        ),
        true,
    )

    _, persistent_err, persistent_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            "(defvar pointer-owner: int 1)\n(def pointer-value: ^int (addr pointer-owner))",
            repl_generation = true,
        )
    defer kvist.compile_error_delete(&persistent_err)
    testing.expect_value(t, persistent_ok, false)
    testing.expect_value(
        t,
        strings.contains(
            persistent_err.message,
            "persistent REPL def with a pointer, foreign view, or opaque resource requires an owned copy until explicit lifecycle adapters are available",
        ),
        true,
    )

    _, opaque_err, opaque_ok :=
        kvist.compile_eval_path_with_map(
            "examples/language/pointers-and-raw.kvist",
            "(def handle: Handle (transmute Handle nil))",
            repl_generation = true,
        )
    defer kvist.compile_error_delete(&opaque_err)
    testing.expect_value(t, opaque_ok, false)
    testing.expect_value(
        t,
        strings.contains(
            opaque_err.message,
            "persistent REPL def with a pointer, foreign view, or opaque resource requires an owned copy until explicit lifecycle adapters are available",
        ),
        true,
    )
}

@(test)
compile_repl_nominal_definition_emits_layout_abi :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        "(defstruct Layout-Point [x: int label: string])",
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    abi := kvist.repl_registered_abi(result.output, "Layout-Point")
    defer delete(abi)
    testing.expect_value(
        t,
        abi,
        "type:Layout_Point|layout:Layout_Point=struct{x:int;label:string;}",
    )
}

@(test)
compile_repl_generation_emits_abort_operation_boundary :: proc(
    t: ^testing.T,
) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        `(defn abortable-operation [] -> int
  (do
    (kvist-intrinsic-condition-operation
      (kvist-intrinsic-signal-condition nil nil :operation/cancelled "cancelled" '{}))
    1))`,
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_debug_operation_",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `== "abort-operation"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `break kvist_debug_operation_`,
        ),
        true,
    )
}

@(test)
compile_repl_generation_emits_typed_conditions :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        `(defn keyword-condition [] -> int
  (do
    (kvist-intrinsic-signal-condition nil nil :io/not-found "missing" '{})
    1))
(defn string-condition [] -> int
  (do
    (kvist-intrinsic-signal-condition nil nil "validation/out-of-range" "invalid" '{})
    2))`,
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `: string = "io/not-found"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `: string = "validation/out-of-range"`,
        ),
        true,
    )

    _, invalid_err, invalid_ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        `(defn invalid-condition [] -> int
  (do
    (kvist-intrinsic-signal-condition nil nil 42 "invalid type" '{})
    0))`,
        repl_generation = true,
    )
    defer kvist.compile_error_delete(&invalid_err)
    testing.expect_value(t, invalid_ok, false)
    testing.expect_value(
        t,
        strings.contains(
            invalid_err.message,
            "type must be a keyword or string literal",
        ),
        true,
    )
}

@(test)
compile_repl_generation_emits_nested_debug_safe_point :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        "(defn paused-add [x: int] -> int (do (kvist-intrinsic-breakpoint) (+ x 1)))",
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `"__KVIST_DEBUG_PAUSE_E_37_65_L78:696e74:0:borrowed,__"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(result.output, `fmt.aprintf("%#v", x)`),
        true,
    )

    mutable_result, mutable_err, mutable_ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        "(defn paused-mutable [x: int] -> int (do (defvar y: int 2) (kvist-intrinsic-breakpoint) (+ x y)))",
        repl_generation = true,
    )
    testing.expect_value(t, mutable_ok, true)
    if !mutable_ok {
        testing.expect_value(t, mutable_err.message, "")
        return
    }
    defer delete(mutable_result.output)
    defer kvist.source_map_slice_delete(mutable_result.source_map)
    defer kvist.compile_warning_slice_delete(mutable_result.warnings)
    testing.expect_value(
        t,
        strings.contains(
            mutable_result.output,
            "_L78:696e74:0:borrowed,79:696e74:1:value,__",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(mutable_result.output, `fmt.aprintf("%#v", y)`),
        true,
    )

    struct_result, struct_err, struct_ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        `(defstruct DebugPair [left: int right: bool])
(defn paused-pair [pair: DebugPair] -> int (do (kvist-intrinsic-breakpoint) pair.left))`,
        repl_generation = true,
    )
    testing.expect_value(t, struct_ok, true)
    if !struct_ok {
        testing.expect_value(t, struct_err.message, "")
        return
    }
    defer delete(struct_result.output)
    defer kvist.source_map_slice_delete(struct_result.source_map)
    defer kvist.compile_warning_slice_delete(struct_result.warnings)
    testing.expect_value(
        t,
        strings.contains(
            struct_result.output,
            "_L70616972:446562756750616972:0:borrowed:6c656674=696e74;7269676874=626f6f6c;,__",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(struct_result.output, `[3]string{`),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(struct_result.output, `fmt.aprintf("%#v", pair.left)`),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(struct_result.output, `fmt.aprintf("%#v", pair.right)`),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            struct_result.output,
            `<not-captured type=DebugPair>`,
        ),
        true,
    )

    nested_result, nested_err, nested_ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        `(defstruct DebugPosition [line: int])
(defstruct DebugState [position: DebugPosition active: bool])
(defn paused-state [state: DebugState] -> int (do (kvist-intrinsic-breakpoint) state.position.line))`,
        repl_generation = true,
    )
    testing.expect_value(t, nested_ok, true)
    if !nested_ok {
        testing.expect_value(t, nested_err.message, "")
        return
    }
    defer delete(nested_result.output)
    defer kvist.source_map_slice_delete(nested_result.source_map)
    defer kvist.compile_warning_slice_delete(nested_result.warnings)
    testing.expect_value(
        t,
        strings.contains(
            nested_result.output,
            "706f736974696f6e2e6c696e65=696e74;",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(nested_result.output, `[4]string{`),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            nested_result.output,
            `fmt.aprintf("%#v", state.position.line)`,
        ),
        true,
    )

    array_result, array_err, array_ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        `(defn paused-array [values: [3]int] -> int
  (do (kvist-intrinsic-breakpoint) values[2]))`,
        repl_generation = true,
    )
    testing.expect_value(t, array_ok, true)
    if !array_ok {
        testing.expect_value(t, array_err.message, "")
        return
    }
    defer delete(array_result.output)
    defer kvist.source_map_slice_delete(array_result.source_map)
    defer kvist.compile_warning_slice_delete(array_result.warnings)
    testing.expect_value(
        t,
        strings.contains(array_result.output, "5b325d=696e74;"),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(array_result.output, `[4]string{`),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            array_result.output,
            `fmt.aprintf("%#v", values[2])`,
        ),
        true,
    )

    bounded_result, bounded_err, bounded_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(defn paused-large-array [values: [300]int] -> int
  (do (kvist-intrinsic-breakpoint) values[0]))`,
            repl_generation = true,
        )
    testing.expect_value(t, bounded_ok, true)
    if !bounded_ok {
        testing.expect_value(t, bounded_err.message, "")
        return
    }
    defer delete(bounded_result.output)
    defer kvist.source_map_slice_delete(bounded_result.source_map)
    defer kvist.compile_warning_slice_delete(bounded_result.warnings)
    testing.expect_value(
        t,
        strings.contains(bounded_result.output, `[257]string{`),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            bounded_result.output,
            `fmt.aprintf("%#v", values[255])`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            bounded_result.output,
            `fmt.aprintf("%#v", values[256])`,
        ),
        false,
    )

    dynamic_result, dynamic_err, dynamic_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(defn paused-dynamic [values: [dynamic]int] -> int
  (do (kvist-intrinsic-breakpoint) values[0]))`,
            repl_generation = true,
        )
    testing.expect_value(t, dynamic_ok, true)
    if !dynamic_ok {
        testing.expect_value(t, dynamic_err.message, "")
        return
    }
    defer delete(dynamic_result.output)
    defer kvist.source_map_slice_delete(dynamic_result.source_map)
    defer kvist.compile_warning_slice_delete(dynamic_result.warnings)
    testing.expect_value(
        t,
        strings.contains(
            dynamic_result.output,
            "_L76616c756573:5b64796e616d69635d696e74:0:borrowed::696e74,__",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            dynamic_result.output,
            "make([dynamic]string, 0, 1)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            dynamic_result.output,
            "0..<min(len(values), 64)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            dynamic_result.output,
            `<dynamic-array count=%d>`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            dynamic_result.output,
            `: string = "values"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            dynamic_result.output,
            `collection := transmute(^[dynamic]int)collection_ctx`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            dynamic_result.output,
            `return len(collection^)`,
        ),
        true,
    )

    dynamic_struct_result, dynamic_struct_err, dynamic_struct_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(defstruct DebugElement [line: int])
(defn paused-dynamic-struct [values: [dynamic]DebugElement] -> int
  (do (kvist-intrinsic-breakpoint) values[0].line))`,
            repl_generation = true,
        )
    testing.expect_value(t, dynamic_struct_ok, true)
    if !dynamic_struct_ok {
        testing.expect_value(t, dynamic_struct_err.message, "")
        return
    }
    defer delete(dynamic_struct_result.output)
    defer kvist.source_map_slice_delete(
        dynamic_struct_result.source_map,
    )
    defer kvist.compile_warning_slice_delete(
        dynamic_struct_result.warnings,
    )
    testing.expect_value(
        t,
        strings.contains(
            dynamic_struct_result.output,
            ":4465627567456c656d656e74:6c696e65=696e74;,__",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            dynamic_struct_result.output,
            "0..<min(len(values), 32)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            dynamic_struct_result.output,
            `fmt.aprintf("%#v", values[kvist_debug_index_`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            dynamic_struct_result.output,
            `].line)`,
        ),
        true,
    )

    map_result, map_err, map_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(defn paused-map [scores: map[string]int] -> int
  (do (kvist-intrinsic-breakpoint) scores["alice"]))`,
            repl_generation = true,
        )
    testing.expect_value(t, map_ok, true)
    if !map_ok {
        testing.expect_value(t, map_err.message, "")
        return
    }
    defer delete(map_result.output)
    defer kvist.source_map_slice_delete(map_result.source_map)
    defer kvist.compile_warning_slice_delete(map_result.warnings)
    testing.expect_value(
        t,
        strings.contains(
            map_result.output,
            ":0:borrowed::::737472696e67:696e74,__",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(map_result.output, `<map count=%d>`),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            map_result.output,
            "make([dynamic]string, 0, 64)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(map_result.output, "for kvist_debug_key_"),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            map_result.output,
            `fmt.aprintf("%#v", scores[kvist_debug_key_`,
        ),
        true,
    )

    map_struct_result, map_struct_err, map_struct_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(defstruct DebugMapValue [line: int])
(defn paused-map-struct [values: map[string]DebugMapValue] -> int
  (do (kvist-intrinsic-breakpoint) values["alice"].line))`,
            repl_generation = true,
        )
    testing.expect_value(t, map_struct_ok, true)
    if !map_struct_ok {
        testing.expect_value(t, map_struct_err.message, "")
        return
    }
    defer delete(map_struct_result.output)
    defer kvist.source_map_slice_delete(
        map_struct_result.source_map,
    )
    defer kvist.compile_warning_slice_delete(
        map_struct_result.warnings,
    )
    testing.expect_value(
        t,
        strings.contains(
            map_struct_result.output,
            ":737472696e67:44656275674d617056616c7565:6c696e65=696e74;,__",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            map_struct_result.output,
            "make([dynamic]string, 0, 32)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(map_struct_result.output, `].line)`),
        true,
    )

    nested_collection_result,
        nested_collection_err,
        nested_collection_ok :=
        kvist.compile_eval_path_with_map(
            "examples/collections/higher-order.kvist",
            `(defstruct DebugCollections [
  id: int
  history: [dynamic]int
  labels: map[string]int
  buckets: [2][dynamic]int
])
(defn paused-collections [state: DebugCollections] -> int
  (do (kvist-intrinsic-breakpoint) state.id))`,
            repl_generation = true,
        )
    testing.expect_value(t, nested_collection_ok, true)
    if !nested_collection_ok {
        testing.expect_value(t, nested_collection_err.message, "")
        return
    }
    defer delete(nested_collection_result.output)
    defer kvist.source_map_slice_delete(
        nested_collection_result.source_map,
    )
    defer kvist.compile_warning_slice_delete(
        nested_collection_result.warnings,
    )
    testing.expect_value(
        t,
        strings.contains(
            nested_collection_result.output,
            "686973746f7279=5b64796e616d69635d696e74;",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            nested_collection_result.output,
            "6c6162656c73=6d61705b737472696e675d696e74;",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            nested_collection_result.output,
            `<aggregate type=DebugCollections>`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            nested_collection_result.output,
            `<dynamic-array count=%d>`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            nested_collection_result.output,
            `<map count=%d>`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            nested_collection_result.output,
            `fmt.aprintf("%#v", state.history)`,
        ),
        false,
    )
    testing.expect_value(
        t,
        strings.contains(
            nested_collection_result.output,
            `fmt.aprintf("%#v", state.labels)`,
        ),
        false,
    )
    testing.expect_value(
        t,
        strings.contains(
            nested_collection_result.output,
            `kvist_debug_page_path_`,
        ) &&
            strings.contains(
                nested_collection_result.output,
                `: string = "state.history"`,
            ) &&
            strings.contains(
                nested_collection_result.output,
                `: string = "state.labels"`,
            ) &&
            strings.contains(
                nested_collection_result.output,
                `: string = "state.buckets[1]"`,
            ),
        true,
    )

    deleted_result, deleted_err, deleted_ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        "(defn paused-deleted [] (let [xs ([dynamic]int [1 2])] (delete xs) (kvist-intrinsic-breakpoint)))",
        repl_generation = true,
    )
    testing.expect_value(t, deleted_ok, true)
    if !deleted_ok {
        testing.expect_value(t, deleted_err.message, "")
        return
    }
    defer delete(deleted_result.output)
    defer kvist.source_map_slice_delete(deleted_result.source_map)
    defer kvist.compile_warning_slice_delete(deleted_result.warnings)
    testing.expect_value(
        t,
        strings.contains(
            deleted_result.output,
            `fmt.aprintf("<unavailable>")`,
        ),
        true,
    )
}

@(test)
compile_repl_generation_rejects_untyped_persistent_value :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/collections/higher-order.kvist",
        "(def answer 42)",
        repl_generation = true,
    )
    if ok {
        delete(result.output)
        kvist.source_map_slice_delete(result.source_map)
        kvist.compile_warning_slice_delete(result.warnings)
    }
    testing.expect_value(t, ok, false)
    defer delete(err.message)
    testing.expect_value(t, strings.contains(err.message, "requires an explicit retainable value type"), true)
}

@(test)
compile_repl_generation_accepts_compile_time_definitions :: proc(t: ^testing.T) {
    alias_result, alias_err, alias_ok := kvist.compile_eval_path_with_map(
        "examples/language/pointers-and-raw.kvist",
        "(def Handle (distinct rawptr))",
        repl_generation = true,
    )
    testing.expect_value(t, alias_ok, true)
    if !alias_ok {
        testing.expect_value(t, alias_err.message, "")
        return
    }
    defer delete(alias_result.output)
    defer kvist.source_map_slice_delete(alias_result.source_map)
    defer kvist.compile_warning_slice_delete(alias_result.warnings)
    testing.expect_value(
        t,
        strings.contains(alias_result.output, "Handle :: distinct rawptr"),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(alias_result.output, "Handle__repl_storage"),
        false,
    )
    alias_use_result, alias_use_err, alias_use_ok :=
        kvist.compile_eval_path_with_map(
            "examples/language/pointers-and-raw.kvist",
            "(defn same-handle [value: Handle] -> Handle value)",
            repl_generation = true,
            repl_session_source = "(def Handle (distinct rawptr))",
        )
    testing.expect_value(t, alias_use_ok, true)
    if !alias_use_ok {
        testing.expect_value(t, alias_use_err.message, "")
        return
    }
    defer delete(alias_use_result.output)
    defer kvist.source_map_slice_delete(alias_use_result.source_map)
    defer kvist.compile_warning_slice_delete(alias_use_result.warnings)

    overload_result, overload_err, overload_ok :=
        kvist.compile_eval_path_with_map(
            "examples/language/polymorphism.kvist",
            "(def render (overload render-int render-user))",
            repl_generation = true,
        )
    testing.expect_value(t, overload_ok, true)
    if !overload_ok {
        testing.expect_value(t, overload_err.message, "")
        return
    }
    defer delete(overload_result.output)
    defer kvist.source_map_slice_delete(overload_result.source_map)
    defer kvist.compile_warning_slice_delete(overload_result.warnings)
    testing.expect_value(
        t,
        strings.contains(
            overload_result.output,
            "render :: proc{render_int, render_user}",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(overload_result.output, "render__repl_storage"),
        false,
    )
    overload_use_result, overload_use_err, overload_use_ok :=
        kvist.compile_eval_path_with_map(
            "examples/language/polymorphism.kvist",
            "(render 7)",
            repl_generation = true,
            repl_session_source =
                "(def render (overload render-int render-user))",
        )
    testing.expect_value(t, overload_use_ok, true)
    if !overload_use_ok {
        testing.expect_value(t, overload_use_err.message, "")
        return
    }
    defer delete(overload_use_result.output)
    defer kvist.source_map_slice_delete(overload_use_result.source_map)
    defer kvist.compile_warning_slice_delete(overload_use_result.warnings)
}

@(test)
compile_repl_generation_accepts_explicit_odin_expression_escape :: proc(
    t: ^testing.T,
) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        `(odin "1 + 1")`,
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)
    testing.expect_value(
        t,
        strings.contains(result.output, "fmt.println(1 + 1)"),
        true,
    )
}

@(test)
compile_repl_generation_accepts_package_context_declaration :: proc(
    t: ^testing.T,
) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        `(package main)`,
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)
}

@(test)
compile_repl_generation_emits_persistent_proc_registration_and_adapter :: proc(t: ^testing.T) {
    definition := "(defn increment [x: int] -> int (+ x 1))"
    defined, err_defined, ok_defined := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        definition,
        repl_generation = true,
    )
    testing.expect_value(t, ok_defined, true)
    if !ok_defined {
        testing.expect_value(t, err_defined.message, "")
        return
    }
    defer delete(defined.output)
    defer kvist.source_map_slice_delete(defined.source_map)
    defer kvist.compile_warning_slice_delete(defined.warnings)
    testing.expect_value(t, strings.contains(defined.output, "increment :: proc(x: int) -> int"), true)
    testing.expect_value(
        t,
        strings.contains(
            defined.output,
            `host.register_proc(host.ctx, "increment", "proc(int:borrowed)->int", transmute(rawptr)increment)`,
        ),
        true,
    )

    called, err_called, ok_called := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        "(increment 41)",
        repl_generation = true,
        repl_session_source = definition,
    )
    testing.expect_value(t, ok_called, true)
    if !ok_called {
        testing.expect_value(t, err_called.message, "")
        return
    }
    defer delete(called.output)
    defer kvist.source_map_slice_delete(called.source_map)
    defer kvist.compile_warning_slice_delete(called.warnings)
    testing.expect_value(
        t,
        strings.contains(
            called.output,
            `target := transmute(proc(int) -> int) kvist_repl_host.lookup_proc(kvist_repl_host.ctx, "increment", "proc(int:borrowed)->int")`,
        ),
        true,
    )
    testing.expect_value(t, strings.contains(called.output, "kvist_repl_result_value := increment(41)"), true)
    testing.expect_value(t, strings.contains(called.output, "kvist_repl_result_storage = kvist_repl_result_value"), true)
    testing.expect_value(
        t,
        strings.contains(
            called.output,
            `host.register_result(host.ctx, "value:int", transmute(rawptr)kvist_repl_result_impl)`,
        ),
        true,
    )
}

@(test)
compile_repl_generation_retains_data_signature_support :: proc(
    t: ^testing.T,
) {
    definition := "(defn make-data [] -> Data {:answer 42})"
    called, err_called, ok_called := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        "(+ 1 2)",
        repl_generation = true,
        repl_session_source = definition,
    )
    testing.expect_value(t, ok_called, true)
    if !ok_called {
        testing.expect_value(t, err_called.message, "")
        return
    }
    defer delete(called.output)
    defer kvist.source_map_slice_delete(called.source_map)
    defer kvist.compile_warning_slice_delete(called.warnings)
    testing.expect_value(
        t,
        strings.contains(called.output, "make_data :: proc() -> Data"),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(called.output, "Data :: struct"),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            called.output,
            `kvist_repl_host.lookup_proc(kvist_repl_host.ctx, "make_data", "proc()->Data:owned")`,
        ),
        true,
    )
}

@(test)
compile_repl_generation_dispatches_calls_between_current_definitions :: proc(
    t: ^testing.T,
) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        `(defn square [x: int] -> int (* x x))
(defn score [x: int] -> int (+ (square x) 1))`,
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_repl_dispatch_square :: proc(x: int) -> int`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `lookup_proc(kvist_repl_host.ctx, "square", "proc(int:borrowed)->int")`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `(kvist_repl_dispatch_square(x)) + (1)`,
        ),
        true,
    )
}

@(test)
compile_repl_generation_reads_current_var_during_definition_initialization :: proc(
    t: ^testing.T,
) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        `(defvar init-count: int 0)
(def base: int (do (inc! init-count) 1))`,
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    register_at := strings.index(
        result.output,
        `host.register_proc(host.ctx, "init_count", "var:int"`,
    )
    base_init_at := strings.index(result.output, "base__repl_storage =")
    testing.expect_value(t, register_at >= 0, true)
    testing.expect_value(t, base_init_at >= 0, true)
    testing.expect_value(t, register_at < base_init_at, true)
}

@(test)
compile_repl_inspection_renders_without_registering_result :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        "(+ *1 1)",
        repl_generation = true,
        repl_recent_result_types = {"int"},
        repl_inspect_only = true,
        repl_inspection_result_slot = "kvist_repl_inspection_1",
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_repl_inspection_abi :: "value:int"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "host.emit_output(host.ctx, Kvist_Repl_Rendered_Value",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(result.output, "host.register_result("),
        false,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `host.register_proc(host.ctx, "kvist_repl_inspection_1", "value:int", transmute(rawptr)kvist_repl_result_impl)`,
        ),
        true,
    )
    inspection_abi := kvist.repl_inspection_result_abi(result.output)
    defer delete(inspection_abi)
    testing.expect_value(t, inspection_abi, "value:int")
}

@(test)
compile_repl_data_results_use_readable_data_rendering :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        "(quote {:answer 9})",
        repl_generation = true,
        repl_inspect_only = true,
        repl_inspection_result_slot = "kvist_repl_inspection_data",
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_data_write_repr :: proc(builder: ^strings.Builder, value: Data)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_repl_rendered_data := kvist_data_repr(kvist_repl_result_storage)",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `fmt.aprintf("KVIST_REPL_LAYOUT\t%d\t%d\n%s\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_repl_inspection_abi :: "value:Data"`,
        ),
        true,
    )
}

@(test)
compile_runtime_type_and_data_conversion_surface :: proc(t: ^testing.T) {
    cases := []struct {
        source: string,
        expected: string,
    }{
        {"(type 123)", `return keyword("int")`},
        {"(type {})", `return keyword("Map")`},
        {"(type (Data 123))", "kvist_data_type(kvist_type_value)"},
        {"(type Greeting)", `keyword("typeid")`},
        {"(type int)", `keyword("typeid")`},
        {`(type (Greeting "hello"))`, `return keyword("Greeting")`},
        {`(type (fn [x: int] -> int (+ x 1)))`, `return keyword("proc(int) -> int")`},
        {"(Data [])", "kvist_data_make_items"},
        {"(Data {:answer 9})", "kvist_data_make_map"},
    }

    for test_case in cases {
        result, err, ok := kvist.compile_eval_path_with_map(
            "examples/language/hello.kvist",
            test_case.source,
            repl_generation = true,
        )
        testing.expect_value(t, ok, true)
        if ok {
            testing.expect_value(
                t,
                strings.contains(result.output, test_case.expected),
                true,
            )
        } else {
            testing.expect_value(t, err.message, "")
        }
        delete(result.output)
        kvist.source_map_slice_delete(result.source_map)
        kvist.compile_warning_slice_delete(result.warnings)
        kvist.compile_error_delete(&err)
    }

    proc_source := `(package main)

(defn score [x: int] -> int
  (+ x 2))`
    proc_output, proc_err, proc_ok :=
        kvist.compile_eval_source(proc_source, "(type score)")
    testing.expect_value(t, proc_ok, true)
    if proc_ok {
        testing.expect_value(
            t,
            strings.contains(
                proc_output,
                `return keyword("proc(int) -> int")`,
            ),
            true,
        )
    } else {
        testing.expect_value(t, proc_err.message, "")
    }
    delete(proc_output)
    kvist.compile_error_delete(&proc_err)

    typeid_result, typeid_err, typeid_ok := kvist.compile_path_with_map(
        "examples/interop/core/matrix.kvist",
    )
    testing.expect_value(t, typeid_ok, true)
    if typeid_ok {
        testing.expect_value(
            t,
            strings.contains(
                typeid_result.output,
                "linalg.identity(matrix[2, 2]f32)",
            ),
            true,
        )
    } else {
        testing.expect_value(t, typeid_err.message, "")
    }
    delete(typeid_result.output)
    kvist.source_map_slice_delete(typeid_result.source_map)
    kvist.compile_warning_slice_delete(typeid_result.warnings)
    kvist.compile_error_delete(&typeid_err)
}

@(test)
compile_repl_inspection_reads_retained_typed_slot :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        "(+ kvist_repl_inspection_1 1)",
        repl_generation = true,
        repl_inspect_only = true,
        repl_inspection_source_slot = "kvist_repl_inspection_1",
        repl_inspection_source_type = "int",
        repl_inspection_result_slot = "kvist_repl_inspection_2",
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_repl_host.lookup_proc(kvist_repl_host.ctx, "kvist_repl_inspection_1", "value:int")`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(result.output, "kvist_repl_result_value :=") &&
        strings.contains(result.output, "kvist_repl_inspection_1()"),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `host.register_proc(host.ctx, "kvist_repl_inspection_2", "value:int", transmute(rawptr)kvist_repl_result_impl)`,
        ),
        true,
    )
}

@(test)
compile_repl_inspection_page_emits_bounded_native_batch :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        "kvist_repl_inspection_1",
        repl_generation = true,
        repl_inspect_only = true,
        repl_inspection_source_slot = "kvist_repl_inspection_1",
        repl_inspection_source_type = "[dynamic]int",
        repl_inspection_page_offset = 4,
        repl_inspection_page_limit = 8,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `fmt.sbprintf(&kvist_repl_page_output, "KVIST_REPL_PAGE_TOTAL\t%d\n", len(kvist_repl_result_storage))`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_repl_page_start := min(4, len(kvist_repl_result_storage))",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "kvist_repl_page_end := min(kvist_repl_page_start + 8, len(kvist_repl_result_storage))",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `fmt.sbprintf(&kvist_repl_page_output, "KVIST_REPL_PAGE_ITEM\t%d\t%#v\n", kvist_repl_page_index, kvist_repl_result_storage[kvist_repl_page_index])`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "host.emit_output(host.ctx, Kvist_Repl_Rendered_Value{data = raw_data(kvist_repl_page_text), length = len(kvist_repl_page_text)})",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(result.output, "fmt.println(kvist_repl_result_storage)"),
        false,
    )
}

@(test)
compile_repl_generation_emits_typed_recent_result_adapters :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        "(+ *1 1)",
        repl_generation = true,
        repl_recent_result_types = {"int", "string"},
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_repl_host.lookup_proc(kvist_repl_host.ctx, "kvist_repl_star_1", "value:int")`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_repl_host.lookup_proc(kvist_repl_host.ctx, "kvist_repl_star_2", "value:string")`,
        ),
        true,
    )
    testing.expect_value(t, strings.contains(result.output, "kvist_repl_star_1()"), true)
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `host.register_result(host.ctx, "value:int", transmute(rawptr)kvist_repl_result_impl)`,
        ),
        true,
    )
}

@(test)
repl_result_type_from_abi_strips_lifetime_metadata :: proc(t: ^testing.T) {
    owned := kvist.repl_result_type_from_abi("value:Data:owned")
    borrowed := kvist.repl_result_type_from_abi(
        "value:string:borrowed|layout:Alias=alias:string",
    )
    defer delete(owned)
    defer delete(borrowed)

    testing.expect_value(t, owned, "Data")
    testing.expect_value(t, borrowed, "string")
}

@(test)
compile_repl_generation_reads_recent_result_without_rotating_history :: proc(
    t: ^testing.T,
) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        "*2",
        repl_generation = true,
        repl_recent_result_types = {"int", "string", "f64"},
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_repl_star_2()`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(result.output, "host.register_result("),
        false,
    )
}

@(test)
compile_repl_generation_snapshots_borrowable_string_results :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        `"hello"`,
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_repl_snapshot_value :: proc(value: string) -> string { return strings.clone(value) }`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_repl_result_storage = kvist_repl_result_value`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `host.register_result(host.ctx, "value:string", transmute(rawptr)kvist_repl_result_impl)`,
        ),
        true,
    )
}

@(test)
compile_repl_generation_snapshots_deferred_dynamic_array_owner :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        `(let [owner ([dynamic]int [3 4]) :defer] owner)`,
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_repl_snapshot_value :: proc(value: [dynamic]int) -> [dynamic]int`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_repl_result_storage = kvist_repl_result_value`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `host.register_result(host.ctx, "value:[dynamic]int", transmute(rawptr)kvist_repl_result_impl)`,
        ),
        true,
    )
}

@(test)
compile_repl_generation_promotes_deferred_array_slice_result :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        `(let [owner ([dynamic]int [3 4 5]) :defer]
           (odin-slice owner 1))`,
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_repl_snapshot_value :: proc(value: []int) -> []int`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_out := make([dynamic]int, len(kvist_values)); copy(kvist_out[:], kvist_values); return kvist_out[:]`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `host.register_result(host.ctx, "value:[]int", transmute(rawptr)kvist_repl_result_impl)`,
        ),
        true,
    )
}

@(test)
compile_repl_generation_promotes_nested_borrowed_slice_result :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        `(defstruct Repl-Window [values: []int])
         (let [owner ([dynamic]int [3 4 5]) :defer]
           (Repl-Window :values (odin-slice owner 1)))`,
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_repl_snapshot_value :: proc(value: Repl_Window) -> Repl_Window`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_out.values = (proc(kvist_values: []int) -> []int`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `make([dynamic]int, len(kvist_values)); copy(kvist_out[:], kvist_values); return kvist_out[:]`,
        ),
        true,
    )
}

@(test)
compile_repl_generation_promotes_nested_borrowed_slice_definition :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        `(defstruct Retained-Window [values: []int])
         (def retained-window: Retained-Window
           (let [owner ([dynamic]int [6 7 8]) :defer]
             (Retained-Window :values (odin-slice owner 1))))`,
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `retained_window__repl_snapshot_value :: proc(value: Retained_Window) -> Retained_Window`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `retained_window__repl_snapshot_value(Retained_Window{`,
        ),
        true,
    )
}

@(test)
compile_repl_generation_clones_persistent_native_maps :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        `(defvar lookup: map[string]int (map[string]int {"one" 1}))`,
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `proc(kvist_values: map[string]int) -> map[string]int`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_out[strings.clone(kvist_key)] = kvist_value`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `host.register_proc(host.ctx, "lookup", "var:map[string]int"`,
        ),
        true,
    )
}

@(test)
compile_repl_generation_snapshots_native_map_results :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        `(map[string]int {"one" 1})`,
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_repl_snapshot_value :: proc(value: map[string]int) -> map[string]int`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `kvist_repl_result_value := kvist_repl_snapshot_value(`,
        ),
        true,
    )
}

@(test)
compile_repl_generation_loads_vars_and_state_editor_buffer :: proc(
    t: ^testing.T,
) {
    path := "examples/language/vars-and-state.kvist"
    source_bytes, read_err :=
        os.read_entire_file_from_path(path, context.allocator)
    testing.expect_value(t, read_err == nil, true)
    if read_err != nil {
        return
    }
    defer delete(source_bytes)
    source := string(source_bytes)

    forms, parse_err, parsed := kvist.read_top_forms(source, path)
    testing.expect_value(t, parsed, true)
    if !parsed {
        testing.expect_value(t, parse_err.message, "")
        return
    }
    defer kvist.delete_borrowed_cst_top_form_slice(&forms)

    editor_source := strings.builder_make()
    defer strings.builder_destroy(&editor_source)
    for top in forms {
        form := top.form
        if form.kind == .List && len(form.items) > 0 &&
           form.items[0].kind == .Symbol {
            head := form.items[0].text
            if head == "package" || head == "comment" {
                continue
            }
            if head == "defn" && len(form.items) > 1 &&
               form.items[1].kind == .Symbol &&
               form.items[1].text == "main" {
                continue
            }
        }
        strings.write_string(
            &editor_source,
            source[form.span.start:form.span.end],
        )
        strings.write_byte(&editor_source, '\n')
    }

    result, err, ok := kvist.compile_eval_path_with_map(
        path,
        strings.to_string(editor_source),
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)
    testing.expect_value(
        t,
        strings.contains(result.output, "request_count__repl_storage: int"),
        true,
    )
}

@(test)
compile_repl_generation_externalizes_package_runtime_state :: proc(t: ^testing.T) {
    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/vars-and-state.kvist",
        `(bump-request-count!)`,
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    testing.expect_value(
        t,
        strings.contains(result.output, "request_count__repl_storage: int"),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            `request_count__repl_initialize := host.lookup_proc(host.ctx, "request_count", "var:int") == nil`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "if request_count__repl_initialize { request_count__repl_storage = 0 }",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            result.output,
            "request_count()",
        ),
        true,
    )
}

@(test)
language_symbols_source_emits_operator_and_mutation_docs :: proc(t: ^testing.T) {
    output := kvist.language_symbols_source()
    defer delete(output)

    testing.expect_value(
        t,
        strings.contains(
            output,
            "kvist form\t+\t1\t1\t\t(+ x y ...)\tAdd two or more numeric operands eagerly.",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            "kvist form\tinc!\t1\t1\t\t(inc! place)\tIncrement a mutable numeric place by one.",
        ),
        true,
    )
}

@(test)
language_symbol_registry_has_complete_reference_docs :: proc(t: ^testing.T) {
    for entry in kvist.LANGUAGE_SOURCE_ENTRIES {
        signature := kvist.language_entry_signature(entry)
        doc := kvist.language_entry_doc(entry)
        testing.expect_value(t, signature != "", true)
        testing.expect_value(t, doc != "", true)
    }

    output := kvist.language_symbols_source()
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "\tpackage\t1\t1\t\t(package name)\tDeclare the Odin package"), true)
    testing.expect_value(t, strings.contains(output, "\timport\t1\t1\t\t(import \"path\" :as alias :refer [name ...])\tLoad a Kvist or Odin package"), true)
    testing.expect_value(t, strings.contains(output, "\tdefn\t1\t1\t\t(defn name docstring? [params ...] -> Return body ...)\tDefine a native"), true)
    testing.expect_value(t, strings.contains(output, "Example:"), true)
}

@(test)
shipped_package_public_symbols_have_documentation :: proc(t: ^testing.T) {
    packages := []string{"arr", "bit", "core", "data", "edn", "map", "parallel", "regex", "reload", "set", "soa", "str", "test"}
    for package_name in packages {
        import_path := fmt.tprintf("kvist:%s", package_name)
        output, ok := kvist.package_symbols_source(import_path, package_name)
        testing.expect_value(t, ok, true)
        if !ok {
            continue
        }
        lines := strings.split_lines(output, context.allocator)
        for line, index in lines {
            if index == 0 || line == "" {
                continue
            }
            fields, valid := kvist.symbols_split_record_fields(line)
            testing.expect_value(t, valid, true)
            if valid {
                testing.expect_value(t, fields[6] != "", true)
            }
            delete(fields)
        }
        delete(lines)
        delete(output)
    }
}

@(test)
package_symbols_hide_private_declarations_with_lifetime_metadata :: proc(t: ^testing.T) {
    edn_output, edn_ok := kvist.package_symbols_source("kvist:edn", "edn")
    testing.expect_value(t, edn_ok, true)
    if edn_ok {
        defer delete(edn_output)
        testing.expect_value(t, strings.contains(edn_output, "edn.read-error"), false)
        testing.expect_value(t, strings.contains(edn_output, "edn.release-items!"), false)
    }

    parallel_output, parallel_ok := kvist.package_symbols_source("kvist:parallel", "parallel")
    testing.expect_value(t, parallel_ok, true)
    if parallel_ok {
        defer delete(parallel_output)
        testing.expect_value(t, strings.contains(parallel_output, "parallel.map-impl"), false)
    }

    test_output, test_ok := kvist.package_symbols_source("kvist:test", "test")
    testing.expect_value(t, test_ok, true)
    if test_ok {
        defer delete(test_output)
        testing.expect_value(t, strings.contains(test_output, "__kvist_test_context"), false)
    }
}

@(test)
editor_symbols_and_calls_use_imported_data_package :: proc(t: ^testing.T) {
    source := `(package main)
(import data "kvist:data")

(defn values [] -> Data
  (data.from-int 123))

(defn empty [] -> Data
  (data.empty-map))

(defn kind [] -> Data
  (data.kind-keyword '{}))`

    path, ok_path := repo_temp_test_path(".tmp-data-editor-symbols.kvist")
    testing.expect_value(t, ok_path, true)
    if !ok_path {
        return
    }
    defer delete(path)

    symbols, symbols_err, symbols_ok :=
        kvist.editor_symbols_source(path, source)
    testing.expect_value(t, symbols_ok, true)
    if symbols_ok {
        testing.expect_value(
            t,
            strings.contains(symbols, "kvist package\tdata.from-int\t"),
            true,
        )
        testing.expect_value(
            t,
            strings.contains(symbols, "kvist package\tdata.from-string\t"),
            true,
        )
        testing.expect_value(
            t,
            strings.contains(symbols, "kvist package\tdata.empty-map\t"),
            true,
        )
        testing.expect_value(
            t,
            strings.contains(symbols, "kvist package\tdata.kind-keyword\t"),
            true,
        )
    } else {
        testing.expect_value(t, symbols_err.message, "")
    }
    delete(symbols)
    kvist.compile_error_delete(&symbols_err)

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if ok {
        testing.expect_value(t, strings.contains(output, "data__from_int(123)"), true)
        testing.expect_value(t, strings.contains(output, "data__empty_map()"), true)
        testing.expect_value(t, strings.contains(output, "data__kind_keyword("), true)
    } else {
        testing.expect_value(t, err.message, "")
    }
    delete(output)
    kvist.compile_error_delete(&err)
}

@(test)
compile_repl_generation_retains_canonical_package_import :: proc(
    t: ^testing.T,
) {
    import_source := `(import "kvist:data" :as data)`
    retained := kvist.repl_persistent_definitions_source(import_source)
    defer delete(retained)
    testing.expect_value(
        t,
        strings.contains(retained, import_source),
        true,
    )
    infos := kvist.repl_definition_infos(import_source)
    defer kvist.repl_definition_info_slice_delete(infos[:])
    testing.expect_value(t, len(infos), 0)

    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        "(data.from-int 123)",
        repl_generation = true,
        repl_session_source = retained,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)
    testing.expect_value(
        t,
        strings.contains(result.output, "data__from_int(123)"),
        true,
    )
}

@(test)
compile_repl_generation_retains_referred_package_import :: proc(
    t: ^testing.T,
) {
    import_source := `(import "kvist:data" :refer [empty-map])`
    retained := kvist.repl_persistent_definitions_source(import_source)
    defer delete(retained)
    testing.expect_value(
        t,
        strings.contains(retained, import_source),
        true,
    )

    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        "(empty-map)",
        repl_generation = true,
        repl_session_source = retained,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)
    testing.expect_value(
        t,
        strings.contains(result.output, "data__empty_map()"),
        true,
    )
}

@(test)
compile_repl_generation_retains_combined_as_and_refer_import :: proc(
    t: ^testing.T,
) {
    import_source :=
        `(import "kvist:data" :as d :refer [empty-map])`
    retained := kvist.repl_persistent_definitions_source(import_source)
    defer delete(retained)
    testing.expect_value(
        t,
        strings.contains(retained, import_source),
        true,
    )

    result, err, ok := kvist.compile_eval_path_with_map(
        "examples/language/hello.kvist",
        "(do (empty-map) (d.empty-map))",
        repl_generation = true,
        repl_session_source = retained,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)
    testing.expect_value(
        t,
        strings.contains(result.output, "d__empty_map()"),
        true,
    )
}

@(test)
compile_supports_combined_as_and_refer_kvist_package_imports :: proc(
    t: ^testing.T,
) {
    source := `(package main)
(import "kvist:arr" :as a :refer [empty push!])

(defn demo [] -> int
  (let [xs (empty int)]
    (push! xs 1 2 3)
    (a.count xs)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)
    testing.expect_value(t, strings.contains(output, "xs := make([dynamic]int)"), true)
    testing.expect_value(t, strings.contains(output, "append(&xs, 1, 2, 3)"), true)
    testing.expect_value(t, strings.contains(output, "return len(xs)"), true)
}

@(test)
compile_doc_macro_supports_language_forms :: proc(t: ^testing.T) {
    source := `(package main)

(defn main []
  (do
    (doc inc!)
    (doc +)
    (doc 'defn)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(
        t,
        strings.contains(
            output,
            `fmt.println("Increment a mutable numeric place by one.")`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `fmt.println("Add two or more numeric operands eagerly.")`,
        ),
        true,
    )
    testing.expect_value(t, strings.contains(output, "Define a native, eagerly compiled procedure."), true)
}

@(test)
compile_doc_macro_supports_imported_package_macros :: proc(t: ^testing.T) {
    source := `(package main)
(import arr "kvist:arr")

(defn main []
  (do
    (doc arr.range)
    (doc arr.count)))`

    output, err, ok := kvist.compile_source(source)
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(output)

    testing.expect_value(
        t,
        strings.contains(
            output,
            "Return a dynamic array of integers in arithmetic progression.",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            "Return the number of elements in an array-family value.",
        ),
        true,
    )
    testing.expect_value(t, strings.contains(output, "source-doc"), false)
}

generated_proc_body_contains :: proc(output, name, expected: string) -> bool {
    marker := fmt.tprintf("%s :: proc", name)
    start := strings.index(output, marker)
    if start < 0 {
        return false
    }
    tail := output[start:]
    end := strings.index(tail, "\n}\n")
    if end < 0 {
        return false
    }
    return strings.contains(tail[:end], expected)
}

@(test)
compile_repl_generation_uses_type_correct_zero_values :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp(
        "",
        "kvist-repl-zero-values-*",
        context.allocator,
    )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    source := `(package repl_zero_values)

(defstruct Entry [value: int])
(defunion Choice [entry: Entry number: int])
(def Entry-Pointer ^Entry)
(def Nested-Entry-Pointer Entry-Pointer)
(def Distinct-Entry-Pointer (distinct ^Entry))

(defn pointer-zero [] -> ^Entry (zero))
(defn pointer-alias-zero [] -> Nested-Entry-Pointer (zero))
(defn distinct-pointer-alias-zero [] -> Distinct-Entry-Pointer (zero))
(defn struct-zero [] -> Entry (zero))
(defn union-zero [] -> Choice (zero))
(defn array-zero [] -> [2]int (zero))
(defn int-zero [] -> int (zero))
(defn bool-zero [] -> bool (zero))
(defn string-zero [] -> string (zero))
(defn slice-zero [] -> []int (zero))
(defn dynamic-array-zero [] -> [dynamic]int (zero))
(defn map-zero [] -> map[string]int (zero))
(defn proc-zero [] -> (fn [] -> int) (zero))
(defn raw-pointer-zero [] -> rawptr (zero))
(defn c-string-zero [] -> cstring (zero))`
    source_path, join_err := os.join_path(
        {dir, "main.kvist"},
        context.allocator,
    )
    testing.expect_value(t, join_err == nil, true)
    if join_err != nil {
        return
    }
    defer delete(source_path)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(source_path, source) == nil,
        true,
    )

    result, err, ok := kvist.compile_eval_path_with_map(
        source_path,
        `(= (pointer-zero) nil)`,
        repl_generation = true,
    )
    testing.expect_value(t, ok, true)
    if !ok {
        testing.expect_value(t, err.message, "")
        return
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)
    output := result.output

    testing.expect_value(t, strings.contains(output, "return ^Entry{}"), false)
    testing.expect_value(t, strings.contains(output, "return Entry_Pointer{}"), false)
    testing.expect_value(t, strings.contains(output, "return Nested_Entry_Pointer{}"), false)
    testing.expect_value(t, strings.contains(output, "return Distinct_Entry_Pointer{}"), false)
    testing.expect_value(t, generated_proc_body_contains(output, "pointer_zero", "return nil"), true)
    testing.expect_value(t, generated_proc_body_contains(output, "pointer_alias_zero", "return nil"), true)
    testing.expect_value(t, generated_proc_body_contains(output, "distinct_pointer_alias_zero", "return nil"), true)
    testing.expect_value(t, generated_proc_body_contains(output, "struct_zero", "return Entry{}"), true)
    testing.expect_value(t, generated_proc_body_contains(output, "union_zero", "return Choice{}"), true)
    testing.expect_value(t, generated_proc_body_contains(output, "array_zero", "return [2]int{}"), true)
    testing.expect_value(t, generated_proc_body_contains(output, "int_zero", "return int{}"), true)
    testing.expect_value(t, generated_proc_body_contains(output, "bool_zero", "return bool{}"), true)
    testing.expect_value(t, generated_proc_body_contains(output, "string_zero", "return string{}"), true)
    testing.expect_value(t, generated_proc_body_contains(output, "slice_zero", "return nil"), true)
    testing.expect_value(t, generated_proc_body_contains(output, "dynamic_array_zero", "return nil"), true)
    testing.expect_value(t, generated_proc_body_contains(output, "map_zero", "return nil"), true)
    testing.expect_value(t, generated_proc_body_contains(output, "proc_zero", "return nil"), true)
    testing.expect_value(t, generated_proc_body_contains(output, "raw_pointer_zero", "return nil"), true)
    testing.expect_value(t, generated_proc_body_contains(output, "c_string_zero", "return nil"), true)
}

@(test)
cli_repl_accepts_pointer_returns_from_context_and_imported_packages :: proc(
    t: ^testing.T,
) {
    dir, dir_err := os.make_directory_temp(
        "",
        "kvist-repl-pointer-zero-*",
        context.allocator,
    )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    state_dir, _ := os.join_path({dir, "state"}, context.allocator)
    defer delete(state_dir)
    testing.expect_value(t, os.make_directory_all(state_dir) == nil, true)
    state_path, _ := os.join_path({state_dir, "state.kvist"}, context.allocator)
    defer delete(state_path)
    state_source := `(package state)
(import arr "kvist:arr")

(defstruct Imported-Entry [value: int])
(def Imported-Entry-Pointer ^Imported-Entry)
(defn imported-identity [entry: Imported-Entry-Pointer] -> Imported-Entry-Pointer entry)

(defn leaked-values []
  (let [xs (arr.empty int)]
    (println 1)))

(defn transferred-values []
  (let [xs (arr.empty int)]
    (delete xs)
    (println (count xs))))`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(state_path, state_source) == nil,
        true,
    )

    context_path, _ := os.join_path({dir, "main.kvist"}, context.allocator)
    defer delete(context_path)
    context_source := `(package repl_pointer_zero)
(import state "./state")
(defstruct Entry [value: int])
(defunion Choice [entry: Entry number: int])
(def Entry-Pointer ^Entry)
(def Nested-Entry-Pointer Entry-Pointer)
(def Distinct-Entry-Pointer (distinct ^Entry))
(defn missing [] -> ^Entry nil)
(defn identity-entry [entry: ^Entry] -> ^Entry entry)
(defn alias-identity [entry: Nested-Entry-Pointer] -> Nested-Entry-Pointer entry)
(defn distinct-alias-identity [entry: Distinct-Entry-Pointer] -> Distinct-Entry-Pointer entry)
(defn zero-int [] -> int (zero))
(defn zero-bool [] -> bool (zero))
(defn zero-string [] -> string (zero))
(defn zero-struct [] -> Entry (zero))
(defn zero-union [] -> Choice (zero))
(defn zero-array [] -> [2]int (zero))
(defn zero-slice [] -> []int (zero))
(defn zero-dynamic-array [] -> [dynamic]int (zero))
(defn zero-map [] -> map[string]int (zero))
(defn zero-proc [] -> (fn [] -> int) (zero))
(defn zero-rawptr [] -> rawptr (zero))
(defn zero-cstring [] -> cstring (zero))
(defn abort-pointer [] -> ^Entry
  (do (kvist-intrinsic-breakpoint) (missing)))
(defn imported-identity [entry: ^state.Imported-Entry] -> ^state.Imported-Entry
  (state.imported-identity entry))`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(context_path, context_source) == nil,
        true,
    )

    requests_path, _ := os.join_path({dir, "requests.jsonl"}, context.allocator)
    defer delete(requests_path)
    requests := `{"id":"probe","op":"eval","source":"(= (missing) nil)","source_path":"repl-probe.kvist","line":1,"column":1}
{"id":"abort-pointer","op":"eval","source":"(abort-pointer)"}
{"id":"abort-pointer-control","op":"debug-abort"}
{"id":"close","op":"close"}
`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(requests_path, requests) == nil,
        true,
    )
    request_file, open_err := os.open(requests_path)
    testing.expect_value(t, open_err == nil, true)
    if open_err != nil {
        return
    }
    defer os.close(request_file)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)
    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "repl", context_path, "--protocol", "jsonl"},
            working_dir = repo_root,
            stdin = request_file,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)
    testing.expect_value(t, exec_err == nil, true)
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    output := string(stdout)
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"probe","kind":"complete","success":true`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"abort-pointer-control","kind":"abort-requested","success":true`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"abort-pointer","kind":"aborted","success":true`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"abort-pointer","kind":"complete","success":false`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"code":"KVO002","confidence":"conservative","phase":"compile"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(output, `"line":9,"column":4,"end_line":9,"end_column":7`),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"code":"KVO003","confidence":"definite","phase":"compile"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(output, `"line":15,"column":21,"end_line":15,"end_column":23`),
        true,
    )
    testing.expect_value(t, strings.contains(output, "return ^Entry{}"), false)
    testing.expect_value(t, strings.contains(string(stderr), "Expected ';', got {"), false)
}

@(test)
cli_eval_uses_ephemeral_repl_session :: proc(t: ^testing.T) {
    dir, dir_err :=
        os.make_directory_temp(
            "",
            "kvist-eval-session-test-*",
            context.allocator,
        )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    context_path, context_err :=
        os.join_path({dir, "context.kvist"}, context.allocator)
    testing.expect_value(t, context_err == nil, true)
    if context_err != nil {
        return
    }
    defer delete(context_path)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(
            context_path,
            `(package eval_session_test)
(defn twice [value: int] -> int (* value 2))`,
        ) == nil,
        true,
    )

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    state, stdout, stderr, exec_err :=
        os.process_exec(
            os.Process_Desc{
                command = {
                    kvist_bin,
                    "eval",
                    context_path,
                    "(twice 21)",
                },
                working_dir = repo_root,
            },
            context.allocator,
        )
    defer delete(stdout)
    defer delete(stderr)
    testing.expect_value(t, exec_err == nil, true)
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    testing.expect_value(t, string(stdout), "42\n")
    testing.expect_value(t, string(stderr), "")

    silent_state, silent_stdout, silent_stderr, silent_err :=
        os.process_exec(
            os.Process_Desc{
                command = {
                    kvist_bin,
                    "eval",
                    context_path,
                    "(twice 22)",
                    "--no-print",
                },
                working_dir = repo_root,
            },
            context.allocator,
        )
    defer delete(silent_stdout)
    defer delete(silent_stderr)
    testing.expect_value(t, silent_err == nil, true)
    testing.expect_value(t, silent_state.exited, true)
    testing.expect_value(t, silent_state.exit_code, 0)
    testing.expect_value(t, string(silent_stdout), "")
    testing.expect_value(t, string(silent_stderr), "")
}

@(test)
cli_repl_evaluates_imported_package_source_in_application_session :: proc(
    t: ^testing.T,
) {
    dir, dir_err := os.make_directory_temp(
        "",
        "kvist-repl-package-source-*",
        context.allocator,
    )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    state_dir, _ := os.join_path({dir, "state"}, context.allocator)
    defer delete(state_dir)
    testing.expect_value(t, os.make_directory_all(state_dir) == nil, true)
    state_path, _ := os.join_path({state_dir, "state.kvist"}, context.allocator)
    defer delete(state_path)
    state_source := `(package state)
(defvar calls: int 0)
(def base: int 10)
(defn side []
  (println "state-side"))
(defn next
  "Advance the imported state counter."
  [] -> int
  (do (inc! calls) (+ base calls)))`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(state_path, state_source) == nil,
        true,
    )
    context_path, _ := os.join_path({dir, "main.kvist"}, context.allocator)
    defer delete(context_path)
    context_source := `(package app)
(import state "./state")
(defn next! [] -> int (state.next))`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(context_path, context_source) == nil,
        true,
    )
    requests_path, _ := os.join_path({dir, "requests.jsonl"}, context.allocator)
    defer delete(requests_path)
    requests := fmt.aprintf(
        `{{"id":"before","op":"eval","source":"(next!)"}}
{{"id":"replace","op":"eval","source":"(def base: int 20)","source_path":%q}}
{{"id":"inside-buffer","op":"eval","source":"(if true (side) (side))\n(+ base 1)\n(+ base 2)","source_path":%q}}
{{"id":"inside","op":"eval","source":"base","source_path":%q}}
{{"id":"after","op":"eval","source":"(next!)"}}
{{"id":"docs","op":"documentation","name":"next","source_path":%q}}
{{"id":"bindings","op":"bindings"}}
{{"id":"close","op":"close"}}
`,
        state_path,
        state_path,
        state_path,
        state_path,
    )
    defer delete(requests)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(requests_path, requests) == nil,
        true,
    )
    request_file, open_err := os.open(requests_path)
    testing.expect_value(t, open_err == nil, true)
    if open_err != nil {
        return
    }
    defer os.close(request_file)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)
    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "repl", context_path, "--protocol", "jsonl"},
            working_dir = repo_root,
            stdin = request_file,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)
    testing.expect_value(t, exec_err == nil, true)
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    output := string(stdout)
    testing.expect_value(
        t,
        strings.contains(output, `"id":"before","kind":"output","success":true`),
        true,
    )
    testing.expect_value(t, strings.contains(output, `"text":"11\n"`), true)
    testing.expect_value(
        t,
        strings.contains(output, `"id":"replace","kind":"complete","success":true`),
        true,
    )
    inside_buffer, found_inside_buffer :=
        repl_jsonl_event_line(output, "inside-buffer", "output")
    testing.expect_value(t, found_inside_buffer, true)
    testing.expect_value(
        t,
        strings.contains(inside_buffer, `"text":"22\n"`),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(output, `"id":"inside-buffer","kind":"stream-output","success":true`),
        true,
    )
    testing.expect_value(t, strings.contains(output, `"text":"state-side\n"`), true)
    testing.expect_value(
        t,
        strings.contains(output, `"id":"inside","kind":"output","success":true`),
        true,
    )
    testing.expect_value(t, strings.contains(output, `"text":"20\n"`), true)
    testing.expect_value(
        t,
        strings.contains(output, `"id":"after","kind":"output","success":true`),
        true,
    )
    testing.expect_value(t, strings.contains(output, `"text":"22\n"`), true)
    testing.expect_value(
        t,
        strings.contains(output, `"id":"docs","kind":"documentation","success":true`),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(output, `"doc":"Advance the imported state counter."`),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(output, fmt.tprintf(`"file":%q`, state_path)),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(output, `"name":"state__base","kind":"def"`),
        true,
    )
    testing.expect_value(t, string(stderr), "")
}

@(test)
cli_repl_caches_identical_frontend_generations :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp(
        "",
        "kvist-repl-frontend-cache-*",
        context.allocator,
    )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    context_path, _ := os.join_path({dir, "context.kvist"}, context.allocator)
    defer delete(context_path)
    context_source := `(package repl_frontend_cache)
(defvar count: int 0)
(defn bump [] -> int (do (inc! count) count))
(defn mix [label: string count: int ratio: f64 enabled: bool] -> string
  (str label ":" count ":" ratio ":" enabled))
(defn make-record [value: int] -> Data {:answer value})
(defn identity-record [value: Data] -> Data value)

;; A notebook-style form is evaluated explicitly by the editor, not while
;; loading the file as the REPL context.
(bump)`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(context_path, context_source) == nil,
        true,
    )

    requests_path, _ := os.join_path({dir, "requests.jsonl"}, context.allocator)
    defer delete(requests_path)
    requests := `{"id":"call-1","op":"eval","source":"(bump)"}
{"id":"call-2","op":"eval","source":"(bump)"}
{"id":"call-3","op":"eval","source":"(bump)"}
{"id":"call-4","op":"eval","source":"(bump)"}
{"id":"call-5","op":"eval","source":"(bump)"}
{"id":"call-6","op":"eval","source":"(bump)"}
{"id":"mixed","op":"eval","source":"(mix \"x\" 3 1.5 true)"}
{"id":"data","op":"eval","source":"(make-record 7)"}
{"id":"data-arg","op":"eval","source":"(identity-record *1)"}
{"id":"bulk","op":"eval","source":"(defn loaded-value [] -> int 42)","defer_debug_values":true}
{"id":"loaded-call","op":"eval","source":"(loaded-value)"}
{"id":"restore-loaded-debug-values","op":"eval","source":"(defn loaded-value [] -> int 42)"}
{"id":"restored-call","op":"eval","source":"(loaded-value)"}
{"id":"trace-loaded-definition","op":"eval","source":"(defn loaded-value [] -> int 42)","trace":true}
{"id":"relean-loaded","op":"eval","source":"(defn loaded-value [] -> int 42)","defer_debug_values":true}
{"id":"relean-call","op":"eval","source":"(loaded-value)"}
{"id":"def-live-data","op":"eval","source":"(defn live-data [value: int] -> Data {:value value})"}
{"id":"direct-live-data","op":"eval","source":"(live-data 9)"}
{"id":"compile-after-live-data","op":"eval","source":"(let [value *1] value)"}
{"id":"semantic-plan-1","op":"eval","source":"(+ 20 22.0)"}
{"id":"semantic-plan-2","op":"eval","source":"(+ 20 22.0)"}
{"id":"history-seed","op":"eval","source":"40"}
{"id":"history-plan-1","op":"eval","source":"(+ (bump) *1)"}
{"id":"history-string","op":"eval","source":"\"wrong\""}
{"id":"history-plan-mismatch","op":"eval","source":"(+ (bump) *1)"}
{"id":"history-restore","op":"eval","source":"40"}
{"id":"history-plan-2","op":"eval","source":"(+ (bump) *1)"}
{"id":"close","op":"close"}
`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(requests_path, requests) == nil,
        true,
    )
    request_file, open_err := os.open(requests_path)
    testing.expect_value(t, open_err == nil, true)
    if open_err != nil {
        return
    }
    defer os.close(request_file)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)
    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "repl", context_path, "--protocol", "jsonl"},
            working_dir = repo_root,
            stdin = request_file,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)
    testing.expect_value(t, exec_err == nil, true)
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    output := string(stdout)
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"call-1","kind":"output","success":true,"generation":1,"stream":"stdout","text":"1\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"call-6","kind":"output","success":true,"generation":6,"stream":"stdout","text":"6\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"call-6","kind":"complete","success":true,"generation":6`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(output, `"id":"mixed","kind":"output","success":true,"generation":7,"stream":"stdout","text":"x:3:1.5:true\n"`),
        true,
    )
    resident_timing, resident_found :=
        repl_jsonl_event_line(output, "call-2", "timings")
    testing.expect_value(t, resident_found, true)
    if resident_found {
        testing.expect_value(
            t,
            strings.contains(
                resident_timing,
                `"phase":"odin-build","elapsed_ns":0`,
            ),
            true,
        )
        testing.expect_value(
            t,
            strings.contains(
                resident_timing,
                `"execution_path":"resident-scalar"`,
            ),
            true,
        )
    }
    testing.expect_value(
        t,
        strings.contains(output, `"id":"data","kind":"output","success":true,"generation":8,"stream":"stdout","text":"{:answer 7}\n"`),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(output, `"id":"data-arg","kind":"output","success":true,"generation":9,"stream":"stdout","text":"{:answer 7}\n"`),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"bulk","kind":"complete","success":true,"generation":10`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"loaded-call","kind":"output","success":true,"generation":11,"stream":"stdout","text":"42\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"direct-live-data","kind":"output","success":true`,
        ) && strings.contains(
            output,
            `"id":"compile-after-live-data","kind":"output","success":true`,
        ),
        true,
    )
    semantic_plan_1_timing, semantic_plan_1_found :=
        repl_jsonl_event_line(output, "semantic-plan-1", "timings")
    semantic_plan_2_timing, semantic_plan_2_found :=
        repl_jsonl_event_line(output, "semantic-plan-2", "timings")
    history_plan_1_timing, history_plan_1_found :=
        repl_jsonl_event_line(output, "history-plan-1", "timings")
    history_mismatch_timing, history_mismatch_found :=
        repl_jsonl_event_line(output, "history-plan-mismatch", "timings")
    history_mismatch_complete, history_mismatch_complete_found :=
        repl_jsonl_event_line(output, "history-plan-mismatch", "complete")
    history_plan_2_timing, history_plan_2_found :=
        repl_jsonl_event_line(output, "history-plan-2", "timings")
    history_plan_2_output, history_plan_2_output_found :=
        repl_jsonl_event_line(output, "history-plan-2", "output")
    testing.expect_value(t, semantic_plan_1_found, true)
    testing.expect_value(t, semantic_plan_2_found, true)
    testing.expect_value(t, history_plan_1_found, true)
    testing.expect_value(t, history_mismatch_found, true)
    testing.expect_value(t, history_mismatch_complete_found, true)
    testing.expect_value(t, history_plan_2_found, true)
    testing.expect_value(t, history_plan_2_output_found, true)
    if semantic_plan_1_found && semantic_plan_2_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_plan_1_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(
                semantic_plan_2_timing,
                `"execution_path":"resident-cache"`,
            ) && strings.contains(
                semantic_plan_2_timing,
                `"frontend_cache_hit":true`,
            ),
            true,
        )
    }
    if history_plan_1_found && history_mismatch_found &&
       history_mismatch_complete_found && history_plan_2_found &&
       history_plan_2_output_found {
        testing.expect_value(
            t,
            strings.contains(
                history_plan_1_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && !strings.contains(
                history_mismatch_timing,
                `"execution_path":"resident-cache"`,
            ) && strings.contains(
                history_mismatch_complete,
                `"success":false`,
            ) && strings.contains(
                history_plan_2_timing,
                `"execution_path":"resident-cache"`,
            ) && strings.contains(
                history_plan_2_output,
                `"text":"48\n"`,
            ),
            true,
        )
    }
    loaded_timing_offset := strings.index(
        output,
        `"id":"loaded-call","kind":"timings"`,
    )
    testing.expect_value(t, loaded_timing_offset >= 0, true)
    if loaded_timing_offset >= 0 {
        loaded_timing_line := output[loaded_timing_offset:]
        if end := strings.index(loaded_timing_line, "\n"); end >= 0 {
            loaded_timing_line = loaded_timing_line[:end]
        }
        testing.expect_value(
            t,
            strings.contains(
                loaded_timing_line,
                `"phase":"odin-build","elapsed_ns":0`,
            ),
            true,
        )
        testing.expect_value(
            t,
            strings.contains(
                loaded_timing_line,
                `"execution_path":"resident-scalar"`,
            ),
            true,
        )
    }
    restore_timing, restore_found :=
        repl_jsonl_event_line(output, "restore-loaded-debug-values", "timings")
    restored_call_timing, restored_call_found :=
        repl_jsonl_event_line(output, "restored-call", "timings")
    trace_definition_timing, trace_definition_found :=
        repl_jsonl_event_line(output, "trace-loaded-definition", "timings")
    relean_timing, relean_found :=
        repl_jsonl_event_line(output, "relean-loaded", "timings")
    relean_call_timing, relean_call_found :=
        repl_jsonl_event_line(output, "relean-call", "timings")
    testing.expect_value(t, restore_found, true)
    testing.expect_value(t, restored_call_found, true)
    testing.expect_value(t, trace_definition_found, true)
    testing.expect_value(t, relean_found, true)
    testing.expect_value(t, relean_call_found, true)
    if restore_found {
        testing.expect_value(
            t,
            strings.contains(restore_timing, `"execution_path":"native-compile"`),
            true,
        )
    }
    if restored_call_found {
        testing.expect_value(
            t,
            strings.contains(
                restored_call_timing,
                `"execution_path":"resident-scalar"`,
            ),
            false,
        )
    }
    if trace_definition_found {
        testing.expect_value(
            t,
            strings.contains(
                trace_definition_timing,
                `"execution_path":"native-compile"`,
            ),
            true,
        )
    }
    if relean_found {
        testing.expect_value(
            t,
            strings.contains(relean_timing, `"kind":"timings"`),
            true,
        )
    }
    if relean_call_found {
        testing.expect_value(
            t,
            strings.contains(
                relean_call_timing,
                `"execution_path":"resident-scalar"`,
            ),
            true,
        )
    }
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"restored-call","kind":"output","success":true`,
        ) && strings.contains(
            output,
            `"id":"relean-call","kind":"output","success":true`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(output, `"phase":"odin-build","elapsed_ns":0`),
        true,
    )
    testing.expect_value(t, string(stderr), "")
}

@(test)
cli_repl_execution_modes_match_native_semantics :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp(
        "",
        "kvist-repl-execution-modes-*",
        context.allocator,
    )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    context_path, _ := os.join_path({dir, "context.kvist"}, context.allocator)
    defer delete(context_path)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(
            context_path,
            "(package repl_execution_modes)\n",
        ) == nil,
        true,
    )
    requests_path, _ := os.join_path({dir, "requests.jsonl"}, context.allocator)
    defer delete(requests_path)
    requests := `{"id":"define","op":"eval","source":"(defn session-inc [x: int] -> int (+ x 1))","defer_debug_values":true}
{"id":"helper","op":"eval","source":"(+ (session-inc 20) 21)"}
{"id":"float","op":"eval","source":"(let [value: f64 20.0] (+ value 22.5))"}
{"id":"branch","op":"eval","source":"(if (< 20 21) 42 0)"}
{"id":"string","op":"eval","source":"(= \"Kvist\" \"Kvist\")"}
{"id":"history-seed","op":"eval","source":"40"}
{"id":"history","op":"eval","source":"(+ *1 2)"}
{"id":"unsupported","op":"eval","source":"(str (session-inc 1))"}
{"id":"close","op":"close"}
`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(requests_path, requests) == nil,
        true,
    )

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    modes := [?]string{"resident", "native"}
    outputs: [2]string
    defer {
        for output in outputs do delete(output)
    }
    for mode, index in modes {
        request_file, open_err := os.open(requests_path)
        testing.expect_value(t, open_err == nil, true)
        if open_err != nil {
            return
        }
        state, stdout, stderr, exec_err := os.process_exec(
            os.Process_Desc{
                command = {
                    kvist_bin,
                    "repl",
                    context_path,
                    "--execution",
                    mode,
                    "--protocol",
                    "jsonl",
                },
                working_dir = repo_root,
                stdin = request_file,
            },
            context.allocator,
        )
        os.close(request_file)
        defer delete(stdout)
        defer delete(stderr)
        testing.expect_value(t, exec_err == nil, true)
        testing.expect_value(t, state.exited, true)
        testing.expect_value(t, state.exit_code, 0)
        testing.expect_value(t, string(stderr), "")
        outputs[index] = strings.clone(string(stdout))
        testing.expect_value(
            t,
            strings.contains(
                outputs[index],
                `"kind":"ready"`,
            ) && strings.contains(
                outputs[index],
                fmt.tprintf(`"execution_mode":"%s"`, mode),
            ),
            true,
        )
    }

    expression_ids := [?]string{
        "helper",
        "float",
        "branch",
        "string",
        "history-seed",
        "history",
    }
    for id in expression_ids {
        resident_output, resident_output_found :=
            repl_jsonl_event_line(outputs[0], id, "output")
        native_output, native_output_found :=
            repl_jsonl_event_line(outputs[1], id, "output")
        resident_timing, resident_timing_found :=
            repl_jsonl_event_line(outputs[0], id, "timings")
        native_timing, native_timing_found :=
            repl_jsonl_event_line(outputs[1], id, "timings")
        testing.expect_value(t, resident_output_found, true)
        testing.expect_value(t, native_output_found, true)
        testing.expect_value(t, resident_timing_found, true)
        testing.expect_value(t, native_timing_found, true)
        if resident_output_found && native_output_found &&
           resident_timing_found && native_timing_found {
            testing.expect_value(t, resident_output, native_output)
            testing.expect_value(
                t,
                strings.contains(
                    resident_timing,
                    `"execution_path":"resident`,
                ),
                true,
            )
            testing.expect_value(
                t,
                !strings.contains(native_timing, `"execution_path":"resident`) &&
                strings.contains(native_timing, `"execution_path":"native`),
                true,
            )
        }
    }

    resident_unsupported, resident_unsupported_found :=
        repl_jsonl_event_line(outputs[0], "unsupported", "complete")
    native_unsupported, native_unsupported_found :=
        repl_jsonl_event_line(outputs[1], "unsupported", "output")
    testing.expect_value(t, resident_unsupported_found, true)
    testing.expect_value(t, native_unsupported_found, true)
    if resident_unsupported_found && native_unsupported_found {
        testing.expect_value(
            t,
            strings.contains(resident_unsupported, `"success":false`) &&
            strings.contains(
                resident_unsupported,
                `"execution_path":"resident-unsupported"`,
            ),
            true,
        )
        testing.expect_value(
            t,
            strings.contains(native_unsupported, `"text":"2\n"`),
            true,
        )
    }
}

@(test)
cli_repl_acceleration_tiers_isolate_native_reuse_and_adapters :: proc(
    t: ^testing.T,
) {
    dir, dir_err := os.make_directory_temp(
        "",
        "kvist-repl-acceleration-tiers-*",
        context.allocator,
    )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    context_path, _ := os.join_path({dir, "context.kvist"}, context.allocator)
    defer delete(context_path)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(
            context_path,
            "(package repl_acceleration_tiers)\n",
        ) == nil,
        true,
    )
    requests_path, _ := os.join_path({dir, "requests.jsonl"}, context.allocator)
    defer delete(requests_path)
    requests := `{"id":"define","op":"eval","source":"(defn session-inc [x: int] -> int (+ x 1))","defer_debug_values":true}
{"id":"direct-first","op":"eval","source":"(session-inc 41)"}
{"id":"direct-repeat","op":"eval","source":"(session-inc 41)"}
{"id":"composed-first","op":"eval","source":"(+ (session-inc (+ 19 1)) 21)"}
{"id":"composed-repeat","op":"eval","source":"(+ (session-inc (+ 19 1)) 21)"}
{"id":"close","op":"close"}
`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(requests_path, requests) == nil,
        true,
    )

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)
    cache_off_env := "KVIST_NO_COMPILE_CACHE=1"
    child_env, child_env_ok :=
        test_child_env_without_kvist_vars({cache_off_env})
    testing.expect_value(t, child_env_ok, true)
    if !child_env_ok {
        return
    }
    defer test_env_slice_delete(&child_env)

    modes := [?]string{
        "auto",
        "native-adapter",
        "native-reuse",
        "native",
    }
    outputs: [len(modes)]string
    defer {
        for output in outputs do delete(output)
    }
    for mode, index in modes {
        request_file, open_err := os.open(requests_path)
        testing.expect_value(t, open_err == nil, true)
        if open_err != nil {
            return
        }
        state, stdout, stderr, exec_err := os.process_exec(
            os.Process_Desc{
                command = {
                    kvist_bin,
                    "repl",
                    context_path,
                    "--execution",
                    mode,
                    "--protocol",
                    "jsonl",
                },
                working_dir = repo_root,
                env = child_env[:],
                stdin = request_file,
            },
            context.allocator,
        )
        os.close(request_file)
        defer delete(stdout)
        defer delete(stderr)
        testing.expect_value(t, exec_err == nil, true)
        testing.expect_value(t, state.exited, true)
        testing.expect_value(t, state.exit_code, 0)
        testing.expect_value(t, string(stderr), "")
        outputs[index] = strings.clone(string(stdout))
    }

    ids := [?]string{
        "direct-first",
        "direct-repeat",
        "composed-first",
        "composed-repeat",
    }
    for id in ids {
        oracle_line, oracle_found :=
            repl_jsonl_event_line(outputs[3], id, "output")
        testing.expect_value(t, oracle_found, true)
        for output in outputs[:3] {
            line, found := repl_jsonl_event_line(output, id, "output")
            testing.expect_value(t, found, true)
            if found && oracle_found {
                testing.expect_value(t, line, oracle_line)
            }
        }
    }

    expected_paths := [?]struct {
        mode_index: int,
        id:         string,
        path:       string,
    }{
        {0, "direct-first", "resident-scalar"},
        {0, "direct-repeat", "resident-scalar"},
        {0, "composed-first", "resident-semantic-plan"},
        {0, "composed-repeat", "resident-cache"},
        {1, "direct-first", "resident-scalar"},
        {1, "direct-repeat", "resident-scalar"},
        {1, "composed-first", "native-compile"},
        {1, "composed-repeat", "native-loaded"},
        {2, "direct-first", "native-compile"},
        {2, "direct-repeat", "native-loaded"},
        {2, "composed-first", "native-compile"},
        {2, "composed-repeat", "native-loaded"},
        {3, "direct-first", "native-compile"},
        {3, "direct-repeat", "native-cache"},
        {3, "composed-first", "native-compile"},
        {3, "composed-repeat", "native-cache"},
    }
    for expected in expected_paths {
        line, found := repl_jsonl_event_line(
            outputs[expected.mode_index],
            expected.id,
            "timings",
        )
        testing.expect_value(t, found, true)
        if found {
            testing.expect_value(
                t,
                strings.contains(
                    line,
                    fmt.tprintf(
                        `"execution_path":"%s"`,
                        expected.path,
                    ),
                ),
                true,
            )
        }
    }
}

@(test)
cli_repl_incremental_native_and_compiled_generations_interoperate :: proc(
    t: ^testing.T,
) {
    if !kvist_repl.incremental_native_backend_supported() {
        // The incremental backend is an optional runtime capability. Its
        // lowering is covered independently; exercise process integration
        // wherever a compatible LLVM installation is available.
        return
    }
    dir, dir_err := os.make_directory_temp(
        "",
        "kvist-repl-incremental-native-*",
        context.allocator,
    )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    context_path, _ := os.join_path({dir, "context.kvist"}, context.allocator)
    defer delete(context_path)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(
            context_path,
            `(package repl_incremental_native)
(import data "kvist:data")
(defn context-text [value: string] -> string value)
(defn context-adjust [value: int] -> int (+ value 5))
(defn context-invert [value: bool] -> bool (not value))
(defn context-scale [value: f64] -> f64 (+ value 0.5))
(defn context-owned-text [value: string] -> string (str value "!"))
(defn context-string-size [value: string] -> int (len value))
(defn context-data [value: int] -> Data [:value value])
(defn context-data-size [value: Data] -> int (count value))
`,
        ) == nil,
        true,
    )
    requests_path, _ := os.join_path({dir, "requests.jsonl"}, context.allocator)
    defer delete(requests_path)
    requests := `{"id":"define-1","op":"eval","source":"(defn square [x: int] -> int (* x x))\n(defn score [x: int] -> int (+ (square x) 2))","no_print":true,"defer_debug_values":true}
{"id":"call-1","op":"eval","source":"(score 20)"}
{"id":"context-call","op":"eval","source":"(context-text \"native\")"}
{"id":"define-2","op":"eval","source":"(defn square [x: int] -> int (* x x))\n(defn score [x: int] -> int (+ (square x) 3))\n(defn project-score [x: int] -> int (+ (score x) (context-adjust x) (context-adjust (context-adjust x))))\n(defn project-float [value: f64 enabled: bool] -> f64 (if (context-invert enabled) (context-scale value) value))\n(defn project-string-size [] -> int (let [value (context-owned-text \"Kvist\") :defer] (context-string-size value)))\n(defn project-data-size [] -> int (let [value (context-data 42)] (context-data-size value)))","no_print":true,"defer_debug_values":true}
{"id":"call-2","op":"eval","source":"(score 20)"}
{"id":"external-call","op":"eval","source":"(project-score 20)"}
{"id":"external-scalar-call","op":"eval","source":"(project-float 2.5 false)"}
{"id":"external-string-call","op":"eval","source":"(project-string-size)"}
{"id":"external-data-call","op":"eval","source":"(project-data-size)"}
{"id":"control-define","op":"eval","source":"(defn bounded-odd-sum [limit: int stop: int] -> int\n  (defvar index: int 0)\n  (defvar total: int 0)\n  (while (< index limit)\n    (inc! index)\n    (if (= index stop) (break))\n    (if (= (% index 2) 0) (continue))\n    (set! total (+ total index)))\n  total)\n(defn contextual-sum [limit: int] -> int\n  (defvar index: int 0)\n  (defvar total: int 0)\n  (while (< index limit)\n    (inc! index)\n    (set! total (+ total (context-adjust index))))\n  total)\n(defn classify [x: int] -> int\n  (if (< x 0) (return 40))\n  (+ x 2))\n(defn mutate-scalars [value: f64 enabled: bool] -> f64\n  (defvar total: f64 value)\n  (defvar flag: bool enabled)\n  (inc! total)\n  (toggle! flag)\n  (if flag (negate! total))\n  total)","no_print":true,"defer_debug_values":true}
{"id":"loop-call","op":"eval","source":"(bounded-odd-sum 10 8)"}
{"id":"contextual-loop-call","op":"eval","source":"(contextual-sum 3)"}
{"id":"return-call","op":"eval","source":"(classify -1)"}
{"id":"scalar-mutation-call","op":"eval","source":"(mutate-scalars 2.5 false)"}
{"id":"close","op":"close"}
`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(requests_path, requests) == nil,
        true,
    )

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)
    child_env, child_env_ok := test_child_env_without_kvist_vars(
        {"KVIST_NO_COMPILE_CACHE=1"},
    )
    testing.expect_value(t, child_env_ok, true)
    if !child_env_ok {
        return
    }
    defer test_env_slice_delete(&child_env)
    request_file, open_err := os.open(requests_path)
    testing.expect_value(t, open_err == nil, true)
    if open_err != nil {
        return
    }
    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {
                kvist_bin,
                "repl",
                context_path,
                "--execution",
                "auto",
                "--protocol",
                "jsonl",
            },
            working_dir = repo_root,
            env = child_env[:],
            stdin = request_file,
        },
        context.allocator,
    )
    os.close(request_file)
    defer delete(stdout)
    defer delete(stderr)
    testing.expect_value(t, exec_err == nil, true)
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    testing.expect_value(t, string(stderr), "")
    output := string(stdout)
    expected := [?]struct {
        id:   string,
        kind: string,
        text: string,
    }{
        {"call-1", "output", `"text":"402\n"`},
        {"context-call", "output", `"text":"native\n"`},
        {"call-2", "output", `"text":"403\n"`},
        {"external-call", "output", `"text":"458\n"`},
        {"external-scalar-call", "output", `"text":"3\n"`},
        {"external-string-call", "output", `"text":"6\n"`},
        {"external-data-call", "output", `"text":"2\n"`},
        {"loop-call", "output", `"text":"16\n"`},
        {"contextual-loop-call", "output", `"text":"21\n"`},
        {"return-call", "output", `"text":"40\n"`},
        {"scalar-mutation-call", "output", `"text":"-3.5\n"`},
        {"define-1", "timings", `"execution_path":"incremental-native"`},
        {"context-call", "timings", `"execution_path":"native-compile"`},
        {"define-2", "timings", `"execution_path":"incremental-native"`},
        {"control-define", "timings", `"execution_path":"incremental-native"`},
    }
    for item in expected {
        line, found := repl_jsonl_event_line(output, item.id, item.kind)
        testing.expect_value(t, found, true)
        if found {
            testing.expect_value(t, strings.contains(line, item.text), true)
        }
    }

    native_request_file, native_open_err := os.open(requests_path)
    testing.expect_value(t, native_open_err == nil, true)
    if native_open_err != nil {
        return
    }
    native_state, native_stdout, native_stderr, native_exec_err :=
        os.process_exec(
            os.Process_Desc{
                command = {
                    kvist_bin,
                    "repl",
                    context_path,
                    "--execution",
                    "native",
                    "--protocol",
                    "jsonl",
                },
                working_dir = repo_root,
                env = child_env[:],
                stdin = native_request_file,
            },
            context.allocator,
        )
    os.close(native_request_file)
    defer delete(native_stdout)
    defer delete(native_stderr)
    testing.expect_value(t, native_exec_err == nil, true)
    testing.expect_value(t, native_state.exited, true)
    testing.expect_value(t, native_state.exit_code, 0)
    testing.expect_value(t, string(native_stderr), "")
    native_output := string(native_stdout)
    result_ids := [?]string{
        "call-1",
        "context-call",
        "call-2",
        "external-call",
        "external-scalar-call",
        "external-string-call",
        "external-data-call",
        "loop-call",
        "contextual-loop-call",
        "return-call",
        "scalar-mutation-call",
    }
    for id in result_ids {
        incremental_line, incremental_found :=
            repl_jsonl_event_line(output, id, "output")
        native_line, native_found :=
            repl_jsonl_event_line(native_output, id, "output")
        testing.expect_value(t, incremental_found, true)
        testing.expect_value(t, native_found, true)
        if incremental_found && native_found {
            testing.expect_value(t, incremental_line, native_line)
        }
    }
}

@(test)
cli_repl_reuses_verified_native_artifacts_across_sessions :: proc(
    t: ^testing.T,
) {
    dir, dir_err := os.make_directory_temp(
        "",
        "kvist-repl-native-artifact-cache-*",
        context.allocator,
    )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    context_path, _ := os.join_path({dir, "context.kvist"}, context.allocator)
    defer delete(context_path)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(
            context_path,
            "(package repl_native_artifact_cache)\n",
        ) == nil,
        true,
    )
    requests_path, _ := os.join_path({dir, "requests.jsonl"}, context.allocator)
    defer delete(requests_path)
    requests := `{"id":"value","op":"eval","source":"(+ 40 2)"}
{"id":"close","op":"close"}
`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(requests_path, requests) == nil,
        true,
    )

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)
    cache_dir, cache_dir_err := os.join_path(
        {dir, "cache"},
        context.allocator,
    )
    testing.expect_value(t, cache_dir_err == nil, true)
    if cache_dir_err != nil {
        return
    }
    defer delete(cache_dir)
    cache_env := fmt.tprintf("KVIST_CACHE_DIR=%s", cache_dir)
    child_env, child_env_ok := test_child_env_without_kvist_vars({cache_env})
    testing.expect_value(t, child_env_ok, true)
    if !child_env_ok {
        return
    }
    defer test_env_slice_delete(&child_env)

    outputs: [3]string
    defer {
        for output in outputs {
            delete(output)
        }
    }
    for session_index in 0..<len(outputs) {
        if session_index == 2 {
            native_cache_dir, native_cache_dir_err := os.join_path(
                {cache_dir, "repl-native"},
                context.allocator,
            )
            testing.expect_value(t, native_cache_dir_err == nil, true)
            if native_cache_dir_err != nil {
                return
            }
            defer delete(native_cache_dir)
            entries, entries_err := os.read_directory_by_path(
                native_cache_dir,
                -1,
                context.allocator,
            )
            testing.expect_value(t, entries_err == nil, true)
            if entries_err != nil {
                return
            }
            defer os.file_info_slice_delete(entries, context.allocator)
            testing.expect_value(t, len(entries), 1)
            if len(entries) != 1 {
                return
            }
            artifact_path, artifact_path_err := os.join_path(
                {
                    native_cache_dir,
                    entries[0].name,
                    "generation.dylib",
                },
                context.allocator,
            )
            testing.expect_value(t, artifact_path_err == nil, true)
            if artifact_path_err != nil {
                return
            }
            defer delete(artifact_path)
            testing.expect_value(
                t,
                os.write_entire_file_from_string(
                    artifact_path,
                    "corrupt native artifact",
                ) == nil,
                true,
            )
        }
        request_file, open_err := os.open(requests_path)
        testing.expect_value(t, open_err == nil, true)
        if open_err != nil {
            return
        }
        state, stdout, stderr, exec_err := os.process_exec(
            os.Process_Desc{
                command = {
                    kvist_bin,
                    "repl",
                    context_path,
                    "--execution",
                    "native-reuse",
                    "--protocol",
                    "jsonl",
                },
                working_dir = repo_root,
                env = child_env[:],
                stdin = request_file,
            },
            context.allocator,
        )
        os.close(request_file)
        defer delete(stdout)
        defer delete(stderr)
        testing.expect_value(t, exec_err == nil, true)
        testing.expect_value(t, state.exited, true)
        testing.expect_value(t, state.exit_code, 0)
        testing.expect_value(t, string(stderr), "")
        outputs[session_index] = strings.clone(string(stdout))
    }

    first_timing, first_timing_found :=
        repl_jsonl_event_line(outputs[0], "value", "timings")
    second_timing, second_timing_found :=
        repl_jsonl_event_line(outputs[1], "value", "timings")
    recovered_timing, recovered_timing_found :=
        repl_jsonl_event_line(outputs[2], "value", "timings")
    first_output, first_output_found :=
        repl_jsonl_event_line(outputs[0], "value", "output")
    second_output, second_output_found :=
        repl_jsonl_event_line(outputs[1], "value", "output")
    testing.expect_value(t, first_timing_found, true)
    testing.expect_value(t, second_timing_found, true)
    testing.expect_value(t, recovered_timing_found, true)
    testing.expect_value(t, first_output_found, true)
    testing.expect_value(t, second_output_found, true)
    if first_timing_found && second_timing_found {
        testing.expect_value(
            t,
            strings.contains(
                first_timing,
                `"execution_path":"native-compile"`,
            ),
            true,
        )
        testing.expect_value(
            t,
            strings.contains(
                second_timing,
                `"execution_path":"native-artifact-cache"`,
            ) && strings.contains(
                second_timing,
                `"phase":"odin-build","elapsed_ns":0`,
            ) && strings.contains(
                second_timing,
                `"native_cache_hit":true`,
            ),
            true,
        )
    }
    if recovered_timing_found {
        testing.expect_value(
            t,
            strings.contains(
                recovered_timing,
                `"execution_path":"native-compile"`,
            ) && strings.contains(
                recovered_timing,
                `"native_cache_hit":false`,
            ),
            true,
        )
    }
    if first_output_found && second_output_found {
        testing.expect_value(t, first_output, second_output)
        testing.expect_value(
            t,
            strings.contains(first_output, `"text":"42\n"`),
            true,
        )
    }
    testing.expect_value(
        t,
        strings.contains(outputs[1], `"native-artifact-cache"`),
        true,
    )
}

@(test)
cli_repl_reuses_loaded_native_expressions_across_intervening_evals :: proc(
    t: ^testing.T,
) {
    dir, dir_err := os.make_directory_temp(
        "",
        "kvist-repl-loaded-native-*",
        context.allocator,
    )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    context_path, _ := os.join_path({dir, "context.kvist"}, context.allocator)
    defer delete(context_path)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(
            context_path,
            "(package repl_loaded_native)\n",
        ) == nil,
        true,
    )
    requests_path, _ := os.join_path({dir, "requests.jsonl"}, context.allocator)
    defer delete(requests_path)
    requests := `{"id":"define","op":"eval","source":"(import data \"kvist:data\")\n(defvar reuse-count: int 0)\n(defvar reuse-data-count: i64 0)\n(defn reuse-bump [] -> int (do (inc! reuse-count) reuse-count))\n(defn reuse-data-bump [] -> i64 (do (inc! reuse-data-count) reuse-data-count))\n(defn reuse-native [x: int y: int :default 0] -> int (+ x y))","defer_debug_values":true}
{"id":"first","op":"eval","source":"(reuse-native (reuse-bump))"}
{"id":"repeat","op":"eval","source":"(reuse-native (reuse-bump))"}
{"id":"third","op":"eval","source":"(reuse-native (reuse-bump))"}
{"id":"intervening","op":"eval","source":"(reuse-native (+ (reuse-bump) 10))"}
{"id":"after-intervening","op":"eval","source":"(reuse-native (reuse-bump))"}
{"id":"final","op":"eval","source":"(reuse-native (reuse-bump))"}
{"id":"history","op":"eval","source":"*2"}
{"id":"data-first","op":"eval","source":"(data.from-int (reuse-data-bump))"}
{"id":"data-repeat","op":"eval","source":"(data.from-int (reuse-data-bump))"}
{"id":"data-third","op":"eval","source":"(data.from-int (reuse-data-bump))"}
{"id":"data-history","op":"eval","source":"*2"}
{"id":"close","op":"close"}
`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(requests_path, requests) == nil,
        true,
    )
    request_file, open_err := os.open(requests_path)
    testing.expect_value(t, open_err == nil, true)
    if open_err != nil {
        return
    }
    defer os.close(request_file)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)
    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {
                kvist_bin,
                "repl",
                context_path,
                "--execution",
                "auto",
                "--protocol",
                "jsonl",
            },
            working_dir = repo_root,
            stdin = request_file,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)
    testing.expect_value(t, exec_err == nil, true)
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    output := string(stdout)
    testing.expect_value(t, string(stderr), "")
    testing.expect_value(t, strings.contains(output, `"loaded-native-reuse"`), true)

    expected_outputs := [?]struct {
        id: string,
        text: string,
    }{
        {"first", `"text":"1\n"`},
        {"repeat", `"text":"2\n"`},
        {"third", `"text":"3\n"`},
        {"intervening", `"text":"14\n"`},
        {"after-intervening", `"text":"5\n"`},
        {"final", `"text":"6\n"`},
        {"history", `"text":"5\n"`},
        {"data-first", `"text":"1\n"`},
        {"data-repeat", `"text":"2\n"`},
        {"data-third", `"text":"3\n"`},
        {"data-history", `"text":"2\n"`},
    }
    for expected in expected_outputs {
        line, found := repl_jsonl_event_line(output, expected.id, "output")
        testing.expect_value(t, found, true)
        if found {
            testing.expect_value(
                t,
                strings.contains(line, expected.text),
                true,
            )
        }
    }

    path_expectations := [?]struct {
        id: string,
        path: string,
    }{
        {"first", "native-compile"},
        {"repeat", "native-loaded"},
        {"third", "native-loaded"},
        {"intervening", "native-compile"},
        {"after-intervening", "native-loaded"},
        {"final", "native-loaded"},
        {"data-first", "native-compile"},
        {"data-repeat", "native-loaded"},
        {"data-third", "native-loaded"},
    }
    for expected in path_expectations {
        line, found := repl_jsonl_event_line(output, expected.id, "timings")
        testing.expect_value(t, found, true)
        if found {
            testing.expect_value(
                t,
                strings.contains(
                    line,
                    fmt.tprintf(
                        `"execution_path":"%s"`,
                        expected.path,
                    ),
                ),
                true,
            )
            if expected.path == "native-loaded" {
                testing.expect_value(
                    t,
                    strings.contains(
                        line,
                        `"phase":"worker-load","elapsed_ns":0`,
                    ),
                    true,
                )
            }
        }
    }
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"repeat","kind":"generation-loaded"`,
        ),
        false,
    )

    native_request_file, native_open_err := os.open(requests_path)
    testing.expect_value(t, native_open_err == nil, true)
    if native_open_err != nil {
        return
    }
    native_state, native_stdout, native_stderr, native_exec_err :=
        os.process_exec(
            os.Process_Desc{
                command = {
                    kvist_bin,
                    "repl",
                    context_path,
                    "--execution",
                    "native",
                    "--protocol",
                    "jsonl",
                },
                working_dir = repo_root,
                stdin = native_request_file,
            },
            context.allocator,
        )
    os.close(native_request_file)
    defer delete(native_stdout)
    defer delete(native_stderr)
    testing.expect_value(t, native_exec_err == nil, true)
    testing.expect_value(t, native_state.exited, true)
    testing.expect_value(t, native_state.exit_code, 0)
    testing.expect_value(t, string(native_stderr), "")
    native_output := string(native_stdout)
    for expected in expected_outputs {
        auto_line, auto_found :=
            repl_jsonl_event_line(output, expected.id, "output")
        native_line, native_found :=
            repl_jsonl_event_line(native_output, expected.id, "output")
        testing.expect_value(t, auto_found, true)
        testing.expect_value(t, native_found, true)
        if auto_found && native_found {
            testing.expect_value(t, auto_line, native_line)
        }
    }
    forced_cache_ids := [?]string{
        "repeat",
        "third",
        "after-intervening",
        "final",
        "data-repeat",
        "data-third",
    }
    for id in forced_cache_ids {
        line, found := repl_jsonl_event_line(native_output, id, "timings")
        testing.expect_value(t, found, true)
        if found {
            testing.expect_value(
                t,
                strings.contains(line, `"execution_path":"native-cache"`),
                true,
            )
            testing.expect_value(
                t,
                strings.contains(line, `"execution_path":"native-loaded"`),
                false,
            )
        }
    }
}

@(test)
cli_repl_keeps_statement_blocks_native_and_composes_branch_adapters :: proc(
    t: ^testing.T,
) {
    dir, dir_err := os.make_directory_temp(
        "",
        "kvist-repl-statement-branches-*",
        context.allocator,
    )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    context_path, _ := os.join_path({dir, "context.kvist"}, context.allocator)
    defer delete(context_path)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(
            context_path,
            "(package repl_statement_branches)\n",
        ) == nil,
        true,
    )

    requests_path, _ := os.join_path({dir, "requests.jsonl"}, context.allocator)
    defer delete(requests_path)
    requests := `{"id":"define","op":"eval","source":"(defn branch-mutable [x: int] -> int\n  (defvar total: int 0)\n  (if (< x 0) (set! total 40) (set! total x))\n  total)\n(defn grouped-branch [x: int] -> int\n  (defvar total: int 0)\n  (if (< x 0)\n    (do (discard (+ total 1))\n        (set! total 20)\n        (if true (set! total (+ total 20))))\n    (set! total x))\n  total)\n(defn branch-return [x: int] -> int\n  (defvar total: int 0)\n  (if (< x 0) (return 40) (set! total x))\n  (+ total 2))\n(defn effectful-branch [x: int] -> int\n  (defvar total: int 0)\n  (if (< x 0)\n    (do (println \"branch-side\") (set! total 40))\n    (set! total x))\n  (+ total 2))","no_print":true,"defer_debug_values":true}
{"id":"statement-branch-block","op":"eval","source":"(do (defvar value: int 0) (if true (set! value 42) (set! value 0)) value)"}
{"id":"branch-taken","op":"eval","source":"(+ (branch-mutable -1) 2)"}
{"id":"branch-fallthrough","op":"eval","source":"(+ (branch-mutable 40) 2)"}
{"id":"grouped-branch","op":"eval","source":"(+ (grouped-branch -1) 2)"}
{"id":"branch-return","op":"eval","source":"(+ (branch-return -1) 2)"}
{"id":"effectful-branch","op":"eval","source":"(+ (effectful-branch -1) 0)"}
{"id":"close","op":"close"}
`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(requests_path, requests) == nil,
        true,
    )
    request_file, open_err := os.open(requests_path)
    testing.expect_value(t, open_err == nil, true)
    if open_err != nil {
        return
    }
    defer os.close(request_file)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)
    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "repl", context_path, "--protocol", "jsonl"},
            working_dir = repo_root,
            stdin = request_file,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)
    testing.expect_value(t, exec_err == nil, true)
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    output := string(stdout)

    statement_timing, statement_timing_found :=
        repl_jsonl_event_line(output, "statement-branch-block", "timings")
    statement_output, statement_output_found :=
        repl_jsonl_event_line(output, "statement-branch-block", "output")
    testing.expect_value(t, statement_timing_found, true)
    testing.expect_value(t, statement_output_found, true)
    if statement_timing_found && statement_output_found {
        testing.expect_value(
            t,
            strings.contains(
                statement_timing,
                `"execution_path":"native-compile"`,
            ) && strings.contains(statement_output, `"text":"42\n"`),
            true,
        )
    }

    composed_ids := [?]string{
        "branch-taken",
        "branch-fallthrough",
        "grouped-branch",
        "branch-return",
    }
    for id in composed_ids {
        timing, timing_found := repl_jsonl_event_line(output, id, "timings")
        result, result_found := repl_jsonl_event_line(output, id, "output")
        testing.expect_value(t, timing_found, true)
        testing.expect_value(t, result_found, true)
        if timing_found && result_found {
            testing.expect_value(
                t,
                strings.contains(
                    timing,
                    `"execution_path":"resident-semantic-plan"`,
                ) && strings.contains(result, `"text":"42\n"`),
                true,
            )
        }
    }

    effect_timing, effect_timing_found :=
        repl_jsonl_event_line(output, "effectful-branch", "timings")
    effect_output, effect_output_found :=
        repl_jsonl_event_line(output, "effectful-branch", "output")
    effect_stream, effect_stream_found :=
        repl_jsonl_event_line(output, "effectful-branch", "stream-output")
    testing.expect_value(t, effect_timing_found, true)
    testing.expect_value(t, effect_output_found, true)
    testing.expect_value(t, effect_stream_found, true)
    if effect_timing_found && effect_output_found && effect_stream_found {
        testing.expect_value(
            t,
            strings.contains(
                effect_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(
                effect_output,
                `"text":"42\n"`,
            ) && strings.contains(
                effect_stream,
                `"text":"branch-side\n"`,
            ),
            true,
        )
    }
    testing.expect_value(t, string(stderr), "")
}

@(test)
cli_repl_keeps_loops_native_and_composes_loop_adapters :: proc(
    t: ^testing.T,
) {
    dir, dir_err := os.make_directory_temp(
        "",
        "kvist-repl-while-loops-*",
        context.allocator,
    )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    context_path, _ := os.join_path({dir, "context.kvist"}, context.allocator)
    defer delete(context_path)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(
            context_path,
            "(package repl_while_loops)\n",
        ) == nil,
        true,
    )

    requests_path, _ := os.join_path({dir, "requests.jsonl"}, context.allocator)
    defer delete(requests_path)
    requests := `{"id":"define","op":"eval","source":"(defn count-up [limit: int] -> int\n  (defvar index: int 0)\n  (while (< index limit)\n    (set! index (+ index 1)))\n  index)\n(defn sum-until [limit: int] -> int\n  (defvar index: int 0)\n  (defvar total: int 0)\n  (while (< index limit)\n    (set! total (+ total index))\n    (set! index (+ index 1)))\n  total)\n(defn nested-loop [outer-limit: int inner-limit: int] -> int\n  (defvar outer: int 0)\n  (defvar total: int 0)\n  (while (< outer outer-limit)\n    (defvar inner: int 0)\n    (while (< inner inner-limit)\n      (set! total (+ total 1))\n      (set! inner (+ inner 1)))\n    (set! outer (+ outer 1)))\n  total)\n(defn find-loop [limit: int needle: int] -> int\n  (defvar index: int 0)\n  (while (< index limit)\n    (if (= index needle) (return index))\n    (set! index (+ index 1)))\n  -1)\n(defn break-loop [stop: int] -> int\n  (defvar index: int 0)\n  (while true\n    (when (= index stop) (break))\n    (inc! index))\n  index)\n(defn continue-loop [limit: int divisor: int] -> int\n  (defvar index: int 0)\n  (defvar total: int 0)\n  (while (< index limit)\n    (inc! index)\n    (when (= (% index divisor) 0) (continue))\n    (set! total (+ total index)))\n  total)\n(defn nested-break-loop [outer-limit: int inner-limit: int] -> int\n  (defvar outer: int 0)\n  (defvar total: int 0)\n  (while (< outer outer-limit)\n    (defvar inner: int 0)\n    (while true\n      (when (= inner inner-limit) (break))\n      (inc! total)\n      (inc! inner))\n    (inc! outer))\n  total)\n(defn nested-continue-loop [outer-limit: int inner-limit: int] -> int\n  (defvar outer: int 0)\n  (defvar total: int 0)\n  (while (< outer outer-limit)\n    (defvar inner: int 0)\n    (while (< inner inner-limit)\n      (inc! inner)\n      (when (= inner inner-limit) (continue))\n      (inc! total))\n    (inc! outer))\n  total)\n(defn effectful-loop [limit: int] -> int\n  (defvar index: int 0)\n  (while (< index limit)\n    (println \"loop-side\")\n    (set! index (+ index 1)))\n  index)\n(defn effectful-control [] -> int\n  (while true\n    (println \"control-side\")\n    (break))\n  42)","no_print":true,"defer_debug_values":true}
{"id":"statement-loop-block","op":"eval","source":"(do (defvar value: int 0) (while (< value 42) (set! value (+ value 1))) value)"}
{"id":"count-loop","op":"eval","source":"(+ (count-up (+ 39 1)) 2)"}
{"id":"sum-loop","op":"eval","source":"(* (sum-until (+ 5 2)) 2)"}
{"id":"nested-loop","op":"eval","source":"(+ (nested-loop (+ 5 1) 7) 0)"}
{"id":"return-loop","op":"eval","source":"(+ (find-loop 100 (+ 39 1)) 2)"}
{"id":"false-loop","op":"eval","source":"(+ (count-up 0) 42)"}
{"id":"increment-mutation","op":"eval","source":"(do (defvar value: int 40) (inc! value) (inc! value) value)"}
{"id":"decrement-mutation","op":"eval","source":"(do (defvar value: f64 43.0) (dec! value) value)"}
{"id":"toggle-mutation","op":"eval","source":"(do (defvar value: bool false) (toggle! value) (if value 42 0))"}
{"id":"negate-mutation","op":"eval","source":"(do (defvar value: int -42) (negate! value) value)"}
{"id":"break-loop","op":"eval","source":"(+ (break-loop (+ 39 1)) 2)"}
{"id":"continue-loop","op":"eval","source":"(+ (continue-loop 10 (+ 1 1)) 17)"}
{"id":"nested-break-loop","op":"eval","source":"(+ (nested-break-loop (+ 5 1) 7) 0)"}
{"id":"nested-continue-loop","op":"eval","source":"(+ (nested-continue-loop (+ 5 1) 8) 0)"}
{"id":"effectful-loop","op":"eval","source":"(+ (effectful-loop 1) 41)"}
{"id":"effectful-control","op":"eval","source":"(+ (effectful-control) 0)"}
{"id":"close","op":"close"}
`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(requests_path, requests) == nil,
        true,
    )
    request_file, open_err := os.open(requests_path)
    testing.expect_value(t, open_err == nil, true)
    if open_err != nil {
        return
    }
    defer os.close(request_file)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)
    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "repl", context_path, "--protocol", "jsonl"},
            working_dir = repo_root,
            stdin = request_file,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)
    testing.expect_value(t, exec_err == nil, true)
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    output := string(stdout)

    composed_ids := [?]string{
        "count-loop",
        "sum-loop",
        "nested-loop",
        "return-loop",
        "false-loop",
        "break-loop",
        "continue-loop",
        "nested-break-loop",
        "nested-continue-loop",
    }
    for id in composed_ids {
        timing, timing_found := repl_jsonl_event_line(output, id, "timings")
        result, result_found := repl_jsonl_event_line(output, id, "output")
        testing.expect_value(t, timing_found, true)
        testing.expect_value(t, result_found, true)
        if timing_found && result_found {
            testing.expect_value(
                t,
                strings.contains(
                    timing,
                    `"execution_path":"resident-semantic-plan"`,
                ) && strings.contains(result, `"text":"42\n"`),
                true,
            )
        }
    }

    native_statement_ids := [?]string{
        "statement-loop-block",
        "increment-mutation",
        "decrement-mutation",
        "toggle-mutation",
        "negate-mutation",
    }
    for id in native_statement_ids {
        timing, timing_found := repl_jsonl_event_line(output, id, "timings")
        result, result_found := repl_jsonl_event_line(output, id, "output")
        testing.expect_value(t, timing_found, true)
        testing.expect_value(t, result_found, true)
        if timing_found && result_found {
            testing.expect_value(
                t,
                strings.contains(timing, `"execution_path":"native-compile"`) &&
                    strings.contains(result, `"text":"42\n"`),
                true,
            )
        }
    }

    effect_timing, effect_timing_found :=
        repl_jsonl_event_line(output, "effectful-loop", "timings")
    effect_output, effect_output_found :=
        repl_jsonl_event_line(output, "effectful-loop", "output")
    effect_stream, effect_stream_found :=
        repl_jsonl_event_line(output, "effectful-loop", "stream-output")
    testing.expect_value(t, effect_timing_found, true)
    testing.expect_value(t, effect_output_found, true)
    testing.expect_value(t, effect_stream_found, true)
    if effect_timing_found && effect_output_found && effect_stream_found {
        testing.expect_value(
            t,
            strings.contains(
                effect_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) &&
            strings.contains(effect_output, `"text":"42\n"`) &&
            strings.contains(effect_stream, `"text":"loop-side\n"`),
            true,
        )
    }

    control_timing, control_timing_found :=
        repl_jsonl_event_line(output, "effectful-control", "timings")
    control_output, control_output_found :=
        repl_jsonl_event_line(output, "effectful-control", "output")
    control_stream, control_stream_found :=
        repl_jsonl_event_line(output, "effectful-control", "stream-output")
    testing.expect_value(t, control_timing_found, true)
    testing.expect_value(t, control_output_found, true)
    testing.expect_value(t, control_stream_found, true)
    if control_timing_found && control_output_found && control_stream_found {
        testing.expect_value(
            t,
            strings.contains(
                control_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(control_output, `"text":"42\n"`) &&
            strings.contains(control_stream, `"text":"control-side\n"`),
            true,
        )
    }

    testing.expect_value(t, string(stderr), "")
}

@(test)
cli_repl_prunes_loaded_source_packages_from_later_generations :: proc(
    t: ^testing.T,
) {
    dir, dir_err := os.make_directory_temp(
        "",
        "kvist-repl-source-package-pruning-*",
        context.allocator,
    )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    context_path, _ := os.join_path({dir, "context.kvist"}, context.allocator)
    defer delete(context_path)
    context_source := `(package repl_source_package_pruning)`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(context_path, context_source) == nil,
        true,
    )

    requests_path, _ := os.join_path({dir, "requests.jsonl"}, context.allocator)
    defer delete(requests_path)
    requests := `{"id":"load-data","op":"eval","source":"(import data \"kvist:data\")\n(defn profile-card [name: string, role: string] -> Data\n  [:article {:class \"profile\"}\n   [:h2 name]\n   [:p role]])\n(defn semantic-helper [x: int] -> int (+ x 1))\n(defn semantic-divisible? [x: int] -> bool (= (% x 4) 0))\n(defn semantic-sequence [x: int] -> int\n  (discard (+ x 100))\n  (+ x 2))\n(defn semantic-mutable [x: int] -> int\n  (defvar total: int x)\n  (set! total (+ total 2))\n  total)\n(defn semantic-early-return [x: int] -> int\n  (if (< x 0) (return 40))\n  (+ x 2))\n(defn semantic-tail-returns [x: int] -> int\n  (if (< x 0) (return 40) (return (+ x 2))))\n(defn semantic-return-inner [x: int] -> int\n  (if (< x 0) (return 5))\n  (+ x 1))\n(defn semantic-return-outer [x: int] -> int\n  (+ (semantic-return-inner x) 10))\n(defn semantic-effectful-return [x: int] -> int\n  (if (< x 0) (do (println \"return-side\") (return 40)))\n  (+ x 2))\n(def semantic-global-base: int 40)\n(defn semantic-global-reader [x: int] -> int (+ semantic-global-base x))\n(defn semantic-effectful-sequence [x: int] -> int\n  (println \"side\")\n  (+ x 1))\n(defn semantic-recursive [x: int] -> int\n  (if (= x 0) 0 (+ 1 (semantic-recursive (- x 1)))))\n(defn semantic-string-match? [match: string] -> bool\n  (or (= match \"focus\") (= match \"act\")))","source_path":"/virtual/source-package-pruning.kvist","line":3,"column":1,"no_print":true,"defer_debug_values":true}
{"id":"composite-1","op":"eval","source":"(get (profile-card \"Ada Lovelace\" \"Mathematician\") 0)"}
{"id":"rotate-history","op":"eval","source":"42"}
{"id":"plan-history","op":"eval","source":"(+ *1 1)"}
{"id":"read-retained-data","op":"eval","source":"(data.keyword *3)"}
{"id":"float-add","op":"eval","source":"(+ 20.5 21.5)"}
{"id":"float-history","op":"eval","source":"(< *1 50.0)"}
{"id":"let-scalars","op":"eval","source":"(let [x 20 y (+ x 1)] (+ x y 1))"}
{"id":"let-nested","op":"eval","source":"(let [x 20] (+ (let [y 1] y) x))"}
{"id":"semantic-typed-let","op":"eval","source":"(let [x: f64 20] (+ x 22.0))"}
{"id":"semantic-nested-let","op":"eval","source":"(let [x: f64 20] (+ (let [y: f64 1] y) x 21.0))"}
{"id":"semantic-control-flow","op":"eval","source":"(if (and (< 20 22.0) (not false)) (+ 20 22.0) 0.0)"}
{"id":"semantic-control-native","op":"eval","source":"(if (and (< 20 22.0) (not false)) (+ 20 22.0) 0.0)","native_debug_symbols":true}
{"id":"semantic-mixed-number","op":"eval","source":"(+ 20 22.0)"}
{"id":"semantic-mixed-repeat-a","op":"eval","source":"(+ 20 22.0)"}
{"id":"semantic-mixed-repeat-b","op":"eval","source":"(+ 20 22.0)"}
{"id":"semantic-mixed-cached","op":"eval","source":"(+ 20 22.0)"}
{"id":"semantic-direct-call","op":"eval","source":"(semantic-helper 41)"}
{"id":"semantic-composed-call","op":"eval","source":"(+ (semantic-helper (+ 19 1)) 21)"}
{"id":"semantic-safe-divisor-call","op":"eval","source":"(if (semantic-divisible? (+ 20 4)) 42 0)"}
{"id":"semantic-do-sequence","op":"eval","source":"(do (discard (+ 20 22)) 42)"}
{"id":"semantic-let-sequence","op":"eval","source":"(let [x: f64 20] (discard (+ x 1.0)) (+ x 22.0))"}
{"id":"semantic-composed-sequence","op":"eval","source":"(+ (semantic-sequence (+ 19 1)) 20)"}
{"id":"semantic-effectful-sequence","op":"eval","source":"(+ (semantic-effectful-sequence (+ 20 21)) 0)"}
{"id":"semantic-mutable-block","op":"eval","source":"(do (defvar value: int 20) (set! value (+ value 22)) value)"}
{"id":"semantic-composed-mutable","op":"eval","source":"(+ (semantic-mutable (+ 19 1)) 20)"}
{"id":"semantic-early-return-taken","op":"eval","source":"(+ (semantic-early-return -1) 2)"}
{"id":"semantic-early-return-fallthrough","op":"eval","source":"(+ (semantic-early-return 40) 0)"}
{"id":"semantic-tail-return","op":"eval","source":"(+ (semantic-tail-returns -1) 2)"}
{"id":"semantic-nested-return","op":"eval","source":"(+ (semantic-return-outer -1) 27)"}
{"id":"semantic-effectful-return","op":"eval","source":"(+ (semantic-effectful-return -1) 2)"}
{"id":"semantic-global-scope","op":"eval","source":"(let [semantic-global-base: int 1] (semantic-global-reader 2))"}
{"id":"semantic-captured-mutation","op":"eval","source":"(do (defvar value: int 0) (discard (if false (do (set! value 7) value) (do (set! value 42) value))) value)"}
{"id":"composite-2","op":"eval","source":"(get (profile-card \"Ada Lovelace\" \"Mathematician\") 0)"}
{"id":"data-managed-composition","op":"eval","source":"(data.count (data.empty-map))"}
{"id":"data-final-first","op":"eval","source":"(data.first (profile-card \"Ada Lovelace\" \"Mathematician\"))"}
{"id":"data-final-repeat","op":"eval","source":"(data.first (profile-card \"Ada Lovelace\" \"Mathematician\"))"}
{"id":"string-literal-plan","op":"eval","source":"\"focus\""}
{"id":"string-history-plan","op":"eval","source":"(= *1 \"focus\")"}
{"id":"semantic-string-match","op":"eval","source":"(if (semantic-string-match? \"focus\") 42 0)"}
{"id":"load-str","op":"eval","source":"(import str \"kvist:str\")","no_print":true,"defer_debug_values":true}
{"id":"str-first","op":"eval","source":"(str.contains? \"Kvist REPL\" \"REPL\")"}
{"id":"str-repeat","op":"eval","source":"(str.contains? \"Kvist REPL\" \"REPL\")"}
{"id":"semantic-string-adapter-call","op":"eval","source":"(and (str.contains? \"Kvist REPL\" \"REPL\") true)"}
{"id":"borrowed-string-result-first","op":"eval","source":"(str.trim \" Kvist \")"}
{"id":"borrowed-string-result-adapter","op":"eval","source":"(= (str.trim \" Kvist \") \"Kvist\")"}
{"id":"owned-string-result-first","op":"eval","source":"(str.lower \"KVIST\")"}
{"id":"owned-string-result-adapter","op":"eval","source":"(= (str.lower \"KVIST\") \"kvist\")"}
{"id":"owned-borrowed-string-result-adapter","op":"eval","source":"(= (str.trim (str.lower \" KVIST \")) \"kvist\")"}
{"id":"semantic-recursive-fallback","op":"eval","source":"(+ (semantic-recursive 2) 40)"}
{"id":"redefine-semantic-helper","op":"eval","source":"(defn semantic-helper [x: int] -> int (+ x 2))","no_print":true,"defer_debug_values":true}
{"id":"semantic-composed-redefined","op":"eval","source":"(+ (semantic-helper (+ 19 1)) 21)"}
{"id":"reject-unreachable-zero","op":"eval","source":"(if true 7 (/ 1 0))"}
{"id":"reject-out-of-range-plan","op":"eval","source":"9999999999999999999999999999999999999999"}
{"id":"shadow-plan-operator","op":"eval","source":"(defmacro + [x y] (quasiquote (- (unquote x) (unquote y))))","defer_debug_values":true}
{"id":"use-shadowed-operator","op":"eval","source":"(+ 10 3)"}
{"id":"close","op":"close"}
`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(requests_path, requests) == nil,
        true,
    )
    request_file, open_err := os.open(requests_path)
    testing.expect_value(t, open_err == nil, true)
    if open_err != nil {
        return
    }
    defer os.close(request_file)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)
    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "repl", context_path, "--protocol", "jsonl"},
            working_dir = repo_root,
            stdin = request_file,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)
    testing.expect_value(t, exec_err == nil, true)
    testing.expect_value(t, state.exited, true)
    testing.expect_value(t, state.exit_code, 0)
    output := string(stdout)
    testing.expect_value(
        t,
        strings.contains(output, `"reachable-native-generations"`),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"composite-1","kind":"output","success":true,"generation":2,"stream":"stdout","text":":article\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"rotate-history","kind":"output","success":true,"generation":3,"stream":"stdout","text":"42\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"plan-history","kind":"output","success":true,"generation":4,"stream":"stdout","text":"43\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"read-retained-data","kind":"output","success":true,"generation":5,"stream":"stdout","text":":article\n"`,
        ),
        true,
    )
    load_timing, load_found :=
        repl_jsonl_event_line(output, "load-data", "timings")
    primitive_timing, primitive_found :=
        repl_jsonl_event_line(output, "rotate-history", "timings")
    history_timing, history_found :=
        repl_jsonl_event_line(output, "plan-history", "timings")
    float_timing, float_found :=
        repl_jsonl_event_line(output, "float-add", "timings")
    float_history_timing, float_history_found :=
        repl_jsonl_event_line(output, "float-history", "timings")
    let_timing, let_found :=
        repl_jsonl_event_line(output, "let-scalars", "timings")
    nested_let_timing, nested_let_found :=
        repl_jsonl_event_line(output, "let-nested", "timings")
    semantic_typed_let_timing, semantic_typed_let_found :=
        repl_jsonl_event_line(output, "semantic-typed-let", "timings")
    semantic_nested_let_timing, semantic_nested_let_found :=
        repl_jsonl_event_line(output, "semantic-nested-let", "timings")
    semantic_control_timing, semantic_control_found :=
        repl_jsonl_event_line(output, "semantic-control-flow", "timings")
    semantic_control_native_timing, semantic_control_native_found :=
        repl_jsonl_event_line(output, "semantic-control-native", "timings")
    semantic_control_output, semantic_control_output_found :=
        repl_jsonl_event_line(output, "semantic-control-flow", "output")
    semantic_control_native_output, semantic_control_native_output_found :=
        repl_jsonl_event_line(output, "semantic-control-native", "output")
    semantic_mixed_timing, semantic_mixed_found :=
        repl_jsonl_event_line(output, "semantic-mixed-number", "timings")
    semantic_cached_timing, semantic_cached_found :=
        repl_jsonl_event_line(output, "semantic-mixed-cached", "timings")
    semantic_direct_call_timing, semantic_direct_call_found :=
        repl_jsonl_event_line(output, "semantic-direct-call", "timings")
    semantic_composed_call_timing, semantic_composed_call_found :=
        repl_jsonl_event_line(output, "semantic-composed-call", "timings")
    semantic_composed_call_output, semantic_composed_call_output_found :=
        repl_jsonl_event_line(output, "semantic-composed-call", "output")
    semantic_safe_divisor_timing, semantic_safe_divisor_found :=
        repl_jsonl_event_line(
            output,
            "semantic-safe-divisor-call",
            "timings",
        )
    semantic_safe_divisor_output, semantic_safe_divisor_output_found :=
        repl_jsonl_event_line(
            output,
            "semantic-safe-divisor-call",
            "output",
        )
    semantic_do_sequence_timing, semantic_do_sequence_found :=
        repl_jsonl_event_line(output, "semantic-do-sequence", "timings")
    semantic_do_sequence_output, semantic_do_sequence_output_found :=
        repl_jsonl_event_line(output, "semantic-do-sequence", "output")
    semantic_let_sequence_timing, semantic_let_sequence_found :=
        repl_jsonl_event_line(output, "semantic-let-sequence", "timings")
    semantic_let_sequence_output, semantic_let_sequence_output_found :=
        repl_jsonl_event_line(output, "semantic-let-sequence", "output")
    semantic_composed_sequence_timing, semantic_composed_sequence_found :=
        repl_jsonl_event_line(
            output,
            "semantic-composed-sequence",
            "timings",
        )
    semantic_composed_sequence_output, semantic_composed_sequence_output_found :=
        repl_jsonl_event_line(
            output,
            "semantic-composed-sequence",
            "output",
        )
    semantic_effectful_sequence_timing, semantic_effectful_sequence_found :=
        repl_jsonl_event_line(
            output,
            "semantic-effectful-sequence",
            "timings",
        )
    semantic_effectful_sequence_output, semantic_effectful_sequence_output_found :=
        repl_jsonl_event_line(
            output,
            "semantic-effectful-sequence",
            "output",
        )
    semantic_effectful_sequence_stream, semantic_effectful_sequence_stream_found :=
        repl_jsonl_event_line(
            output,
            "semantic-effectful-sequence",
            "stream-output",
        )
    semantic_mutable_block_timing, semantic_mutable_block_found :=
        repl_jsonl_event_line(output, "semantic-mutable-block", "timings")
    semantic_mutable_block_output, semantic_mutable_block_output_found :=
        repl_jsonl_event_line(output, "semantic-mutable-block", "output")
    semantic_composed_mutable_timing, semantic_composed_mutable_found :=
        repl_jsonl_event_line(output, "semantic-composed-mutable", "timings")
    semantic_composed_mutable_output, semantic_composed_mutable_output_found :=
        repl_jsonl_event_line(output, "semantic-composed-mutable", "output")
    semantic_early_return_taken_timing, semantic_early_return_taken_found :=
        repl_jsonl_event_line(output, "semantic-early-return-taken", "timings")
    semantic_early_return_taken_output, semantic_early_return_taken_output_found :=
        repl_jsonl_event_line(output, "semantic-early-return-taken", "output")
    semantic_early_return_fallthrough_timing, semantic_early_return_fallthrough_found :=
        repl_jsonl_event_line(
            output,
            "semantic-early-return-fallthrough",
            "timings",
        )
    semantic_early_return_fallthrough_output, semantic_early_return_fallthrough_output_found :=
        repl_jsonl_event_line(
            output,
            "semantic-early-return-fallthrough",
            "output",
        )
    semantic_tail_return_timing, semantic_tail_return_found :=
        repl_jsonl_event_line(output, "semantic-tail-return", "timings")
    semantic_tail_return_output, semantic_tail_return_output_found :=
        repl_jsonl_event_line(output, "semantic-tail-return", "output")
    semantic_nested_return_timing, semantic_nested_return_found :=
        repl_jsonl_event_line(output, "semantic-nested-return", "timings")
    semantic_nested_return_output, semantic_nested_return_output_found :=
        repl_jsonl_event_line(output, "semantic-nested-return", "output")
    semantic_effectful_return_timing, semantic_effectful_return_found :=
        repl_jsonl_event_line(output, "semantic-effectful-return", "timings")
    semantic_effectful_return_output, semantic_effectful_return_output_found :=
        repl_jsonl_event_line(output, "semantic-effectful-return", "output")
    semantic_effectful_return_stream, semantic_effectful_return_stream_found :=
        repl_jsonl_event_line(
            output,
            "semantic-effectful-return",
            "stream-output",
        )
    semantic_global_scope_timing, semantic_global_scope_found :=
        repl_jsonl_event_line(output, "semantic-global-scope", "timings")
    semantic_global_scope_output, semantic_global_scope_output_found :=
        repl_jsonl_event_line(output, "semantic-global-scope", "output")
    semantic_captured_mutation_timing, semantic_captured_mutation_found :=
        repl_jsonl_event_line(output, "semantic-captured-mutation", "timings")
    semantic_captured_mutation_complete, semantic_captured_mutation_complete_found :=
        repl_jsonl_event_line(output, "semantic-captured-mutation", "complete")
    semantic_recursive_timing, semantic_recursive_found :=
        repl_jsonl_event_line(
            output,
            "semantic-recursive-fallback",
            "timings",
        )
    semantic_recursive_output, semantic_recursive_output_found :=
        repl_jsonl_event_line(
            output,
            "semantic-recursive-fallback",
            "output",
        )
    semantic_redefined_timing, semantic_redefined_found :=
        repl_jsonl_event_line(
            output,
            "semantic-composed-redefined",
            "timings",
        )
    semantic_redefined_output, semantic_redefined_output_found :=
        repl_jsonl_event_line(
            output,
            "semantic-composed-redefined",
            "output",
        )
    let_output, let_output_found :=
        repl_jsonl_event_line(output, "let-scalars", "output")
    nested_let_output, nested_let_output_found :=
        repl_jsonl_event_line(output, "let-nested", "output")
    composite_timing, composite_found :=
        repl_jsonl_event_line(output, "composite-1", "timings")
    repeated_timing, repeated_found :=
        repl_jsonl_event_line(output, "composite-2", "timings")
    repeated_output, repeated_output_found :=
        repl_jsonl_event_line(output, "composite-2", "output")
    data_managed_timing, data_managed_found :=
        repl_jsonl_event_line(
            output,
            "data-managed-composition",
            "timings",
        )
    data_managed_output, data_managed_output_found :=
        repl_jsonl_event_line(
            output,
            "data-managed-composition",
            "output",
        )
    data_final_first_timing, data_final_first_found :=
        repl_jsonl_event_line(output, "data-final-first", "timings")
    data_final_repeat_timing, data_final_repeat_found :=
        repl_jsonl_event_line(output, "data-final-repeat", "timings")
    data_final_repeat_output, data_final_repeat_output_found :=
        repl_jsonl_event_line(output, "data-final-repeat", "output")
    str_first_timing, str_first_found :=
        repl_jsonl_event_line(output, "str-first", "timings")
    str_repeat_timing, str_repeat_found :=
        repl_jsonl_event_line(output, "str-repeat", "timings")
    semantic_string_timing, semantic_string_found :=
        repl_jsonl_event_line(
            output,
            "semantic-string-adapter-call",
            "timings",
        )
    semantic_string_output, semantic_string_output_found :=
        repl_jsonl_event_line(
            output,
            "semantic-string-adapter-call",
            "output",
        )
    string_result_first_timing, string_result_first_found :=
        repl_jsonl_event_line(
            output,
            "borrowed-string-result-first",
            "timings",
        )
    string_result_first_output, string_result_first_output_found :=
        repl_jsonl_event_line(
            output,
            "borrowed-string-result-first",
            "output",
        )
    string_result_timing, string_result_found :=
        repl_jsonl_event_line(
            output,
            "borrowed-string-result-adapter",
            "timings",
        )
    string_result_output, string_result_output_found :=
        repl_jsonl_event_line(
            output,
            "borrowed-string-result-adapter",
            "output",
        )
    owned_string_result_first_timing, owned_string_result_first_found :=
        repl_jsonl_event_line(
            output,
            "owned-string-result-first",
            "timings",
        )
    owned_string_result_first_output, owned_string_result_first_output_found :=
        repl_jsonl_event_line(
            output,
            "owned-string-result-first",
            "output",
        )
    owned_string_result_timing, owned_string_result_found :=
        repl_jsonl_event_line(
            output,
            "owned-string-result-adapter",
            "timings",
        )
    owned_string_result_output, owned_string_result_output_found :=
        repl_jsonl_event_line(
            output,
            "owned-string-result-adapter",
            "output",
        )
    owned_borrowed_result_timing, owned_borrowed_result_found :=
        repl_jsonl_event_line(
            output,
            "owned-borrowed-string-result-adapter",
            "timings",
        )
    owned_borrowed_result_output, owned_borrowed_result_output_found :=
        repl_jsonl_event_line(
            output,
            "owned-borrowed-string-result-adapter",
            "output",
        )
    string_literal_timing, string_literal_found :=
        repl_jsonl_event_line(output, "string-literal-plan", "timings")
    string_literal_output, string_literal_output_found :=
        repl_jsonl_event_line(output, "string-literal-plan", "output")
    string_history_timing, string_history_found :=
        repl_jsonl_event_line(output, "string-history-plan", "timings")
    string_history_output, string_history_output_found :=
        repl_jsonl_event_line(output, "string-history-plan", "output")
    semantic_string_match_timing, semantic_string_match_found :=
        repl_jsonl_event_line(output, "semantic-string-match", "timings")
    semantic_string_match_output, semantic_string_match_output_found :=
        repl_jsonl_event_line(output, "semantic-string-match", "output")
    testing.expect_value(t, load_found, true)
    testing.expect_value(t, primitive_found, true)
    testing.expect_value(t, history_found, true)
    testing.expect_value(t, float_found, true)
    testing.expect_value(t, float_history_found, true)
    testing.expect_value(t, let_found, true)
    testing.expect_value(t, nested_let_found, true)
    testing.expect_value(t, semantic_typed_let_found, true)
    testing.expect_value(t, semantic_nested_let_found, true)
    testing.expect_value(t, semantic_control_found, true)
    testing.expect_value(t, semantic_control_native_found, true)
    testing.expect_value(t, semantic_control_output_found, true)
    testing.expect_value(t, semantic_control_native_output_found, true)
    testing.expect_value(t, semantic_mixed_found, true)
    testing.expect_value(t, semantic_cached_found, true)
    testing.expect_value(t, semantic_direct_call_found, true)
    testing.expect_value(t, semantic_composed_call_found, true)
    testing.expect_value(t, semantic_composed_call_output_found, true)
    testing.expect_value(t, semantic_safe_divisor_found, true)
    testing.expect_value(t, semantic_safe_divisor_output_found, true)
    testing.expect_value(t, semantic_do_sequence_found, true)
    testing.expect_value(t, semantic_do_sequence_output_found, true)
    testing.expect_value(t, semantic_let_sequence_found, true)
    testing.expect_value(t, semantic_let_sequence_output_found, true)
    testing.expect_value(t, semantic_composed_sequence_found, true)
    testing.expect_value(t, semantic_composed_sequence_output_found, true)
    testing.expect_value(t, semantic_effectful_sequence_found, true)
    testing.expect_value(t, semantic_effectful_sequence_output_found, true)
    testing.expect_value(t, semantic_effectful_sequence_stream_found, true)
    testing.expect_value(t, semantic_mutable_block_found, true)
    testing.expect_value(t, semantic_mutable_block_output_found, true)
    testing.expect_value(t, semantic_composed_mutable_found, true)
    testing.expect_value(t, semantic_composed_mutable_output_found, true)
    testing.expect_value(t, semantic_early_return_taken_found, true)
    testing.expect_value(t, semantic_early_return_taken_output_found, true)
    testing.expect_value(t, semantic_early_return_fallthrough_found, true)
    testing.expect_value(t, semantic_early_return_fallthrough_output_found, true)
    testing.expect_value(t, semantic_tail_return_found, true)
    testing.expect_value(t, semantic_tail_return_output_found, true)
    testing.expect_value(t, semantic_nested_return_found, true)
    testing.expect_value(t, semantic_nested_return_output_found, true)
    testing.expect_value(t, semantic_effectful_return_found, true)
    testing.expect_value(t, semantic_effectful_return_output_found, true)
    testing.expect_value(t, semantic_effectful_return_stream_found, true)
    testing.expect_value(t, semantic_global_scope_found, true)
    testing.expect_value(t, semantic_global_scope_output_found, true)
    testing.expect_value(t, semantic_captured_mutation_found, true)
    testing.expect_value(t, semantic_captured_mutation_complete_found, true)
    testing.expect_value(t, semantic_recursive_found, true)
    testing.expect_value(t, semantic_recursive_output_found, true)
    testing.expect_value(t, semantic_redefined_found, true)
    testing.expect_value(t, semantic_redefined_output_found, true)
    testing.expect_value(t, let_output_found, true)
    testing.expect_value(t, nested_let_output_found, true)
    testing.expect_value(t, composite_found, true)
    testing.expect_value(t, repeated_found, true)
    testing.expect_value(t, repeated_output_found, true)
    testing.expect_value(t, data_managed_found, true)
    testing.expect_value(t, data_managed_output_found, true)
    testing.expect_value(t, data_final_first_found, true)
    testing.expect_value(t, data_final_repeat_found, true)
    testing.expect_value(t, data_final_repeat_output_found, true)
    testing.expect_value(t, str_first_found, true)
    testing.expect_value(t, str_repeat_found, true)
    testing.expect_value(t, semantic_string_found, true)
    testing.expect_value(t, semantic_string_output_found, true)
    testing.expect_value(t, string_result_first_found, true)
    testing.expect_value(t, string_result_first_output_found, true)
    testing.expect_value(t, string_result_found, true)
    testing.expect_value(t, string_result_output_found, true)
    testing.expect_value(t, owned_string_result_first_found, true)
    testing.expect_value(t, owned_string_result_first_output_found, true)
    testing.expect_value(t, owned_string_result_found, true)
    testing.expect_value(t, owned_string_result_output_found, true)
    testing.expect_value(t, owned_borrowed_result_found, true)
    testing.expect_value(t, owned_borrowed_result_output_found, true)
    testing.expect_value(t, string_literal_found, true)
    testing.expect_value(t, string_literal_output_found, true)
    testing.expect_value(t, string_history_found, true)
    testing.expect_value(t, string_history_output_found, true)
    testing.expect_value(t, semantic_string_match_found, true)
    testing.expect_value(t, semantic_string_match_output_found, true)
    if string_literal_found && string_literal_output_found {
        testing.expect_value(
            t,
            strings.contains(
                string_literal_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(string_literal_output, `"text":"focus\n"`),
            true,
        )
    }
    if string_history_found && string_history_output_found {
        testing.expect_value(
            t,
            strings.contains(
                string_history_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(string_history_output, `"text":"true\n"`),
            true,
        )
    }
    if semantic_string_match_found && semantic_string_match_output_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_string_match_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(
                semantic_string_match_output,
                `"text":"42\n"`,
            ),
            true,
        )
    }
    if primitive_found {
        testing.expect_value(
            t,
            strings.contains(
                primitive_timing,
                `"phase":"odin-build","elapsed_ns":0`,
            ),
            true,
        )
        testing.expect_value(
            t,
            strings.contains(
                primitive_timing,
                `"execution_path":"resident-semantic-plan"`,
            ),
            true,
        )
    }
    if history_found {
        testing.expect_value(
            t,
            strings.contains(
                history_timing,
                `"phase":"odin-build","elapsed_ns":0`,
            ) && strings.contains(
                history_timing,
                `"execution_path":"resident-semantic-plan"`,
            ),
            true,
        )
    }
    if float_found {
        testing.expect_value(
            t,
            strings.contains(
                float_timing,
                `"execution_path":"resident-semantic-plan"`,
            ),
            true,
        )
    }
    if float_history_found {
        testing.expect_value(
            t,
            strings.contains(
                float_history_timing,
                `"execution_path":"resident-semantic-plan"`,
            ),
            true,
        )
    }
    if let_found {
        testing.expect_value(
            t,
            strings.contains(
                let_timing,
                `"execution_path":"resident-semantic-plan"`,
            ),
            true,
        )
    }
    if nested_let_found {
        testing.expect_value(
            t,
            strings.contains(
                nested_let_timing,
                `"execution_path":"resident-semantic-plan"`,
            ),
            true,
        )
    }
    if semantic_typed_let_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_typed_let_timing,
                `"execution_path":"resident-semantic-plan"`,
            ),
            true,
        )
    }
    if semantic_nested_let_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_nested_let_timing,
                `"execution_path":"resident-semantic-plan"`,
            ),
            true,
        )
    }
    if semantic_control_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_control_timing,
                `"execution_path":"resident-semantic-plan"`,
            ),
            true,
        )
    }
    if semantic_control_native_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_control_native_timing,
                `"execution_path":"native-compile"`,
            ),
            true,
        )
    }
    if semantic_mixed_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_mixed_timing,
                `"execution_path":"resident-semantic-plan"`,
            ),
            true,
        )
    }
    if semantic_cached_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_cached_timing,
                `"execution_path":"resident-cache"`,
            ) && strings.contains(
                semantic_cached_timing,
                `"frontend_cache_hit":true`,
            ),
            true,
        )
    }
    if semantic_direct_call_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_direct_call_timing,
                `"execution_path":"resident-scalar"`,
            ),
            true,
        )
    }
    if semantic_composed_call_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_composed_call_timing,
                `"execution_path":"resident-semantic-plan"`,
            ),
            true,
        )
    }
    if semantic_safe_divisor_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_safe_divisor_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(
                semantic_safe_divisor_output,
                `"text":"42\n"`,
            ),
            true,
        )
    }
    if semantic_do_sequence_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_do_sequence_timing,
                `"execution_path":"native-compile"`,
            ) && strings.contains(
                semantic_do_sequence_output,
                `"text":"42\n"`,
            ),
            true,
        )
    }
    if semantic_let_sequence_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_let_sequence_timing,
                `"execution_path":"native-compile"`,
            ) && strings.contains(
                semantic_let_sequence_output,
                `"text":"42\n"`,
            ),
            true,
        )
    }
    if semantic_composed_sequence_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_composed_sequence_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(
                semantic_composed_sequence_output,
                `"text":"42\n"`,
            ),
            true,
        )
    }
    if semantic_effectful_sequence_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_effectful_sequence_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(
                semantic_effectful_sequence_output,
                `"text":"42\n"`,
            ) && strings.contains(
                semantic_effectful_sequence_stream,
                `"text":"side\n"`,
            ),
            true,
        )
    }
    if semantic_mutable_block_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_mutable_block_timing,
                `"execution_path":"native-compile"`,
            ) && strings.contains(
                semantic_mutable_block_output,
                `"text":"42\n"`,
            ),
            true,
        )
    }
    if semantic_composed_mutable_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_composed_mutable_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(
                semantic_composed_mutable_output,
                `"text":"42\n"`,
            ),
            true,
        )
    }
    if semantic_early_return_taken_found &&
       semantic_early_return_fallthrough_found &&
       semantic_tail_return_found && semantic_nested_return_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_early_return_taken_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(
                semantic_early_return_taken_output,
                `"text":"42\n"`,
            ),
            true,
        )
        testing.expect_value(
            t,
            strings.contains(
                semantic_early_return_fallthrough_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(
                semantic_early_return_fallthrough_output,
                `"text":"42\n"`,
            ),
            true,
        )
        testing.expect_value(
            t,
            strings.contains(
                semantic_tail_return_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(
                semantic_tail_return_output,
                `"text":"42\n"`,
            ),
            true,
        )
        testing.expect_value(
            t,
            strings.contains(
                semantic_nested_return_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(
                semantic_nested_return_output,
                `"text":"42\n"`,
            ),
            true,
        )
    }
    if semantic_effectful_return_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_effectful_return_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(
                semantic_effectful_return_output,
                `"text":"42\n"`,
            ) && strings.contains(
                semantic_effectful_return_stream,
                `"text":"return-side\n"`,
            ),
            true,
        )
    }
    if semantic_global_scope_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_global_scope_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(
                semantic_global_scope_output,
                `"text":"42\n"`,
            ),
            true,
        )
    }
    if semantic_captured_mutation_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_captured_mutation_timing,
                `"execution_path":"native-compile"`,
            ) && strings.contains(
                semantic_captured_mutation_complete,
                `"success":false`,
            ),
            true,
        )
    }
    if semantic_recursive_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_recursive_timing,
                `"execution_path":"resident-semantic-plan"`,
            ),
            true,
        )
    }
    if semantic_redefined_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_redefined_timing,
                `"execution_path":"resident-semantic-plan"`,
            ),
            true,
        )
    }
    if semantic_composed_call_output_found &&
       semantic_recursive_output_found &&
       semantic_redefined_output_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_composed_call_output,
                `"text":"42\n"`,
            ) && strings.contains(
                semantic_recursive_output,
                `"text":"42\n"`,
            ) && strings.contains(
                semantic_redefined_output,
                `"text":"43\n"`,
            ),
            true,
        )
    }
    if let_output_found {
        testing.expect_value(
            t,
            strings.contains(let_output, `"text":"42\n"`),
            true,
        )
    }
    if nested_let_output_found {
        testing.expect_value(
            t,
            strings.contains(nested_let_output, `"text":"21\n"`),
            true,
        )
    }
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"float-add","kind":"output","success":true`,
        ) && strings.contains(
            output,
            `"id":"float-history","kind":"output","success":true`,
        ) && strings.contains(
            output,
            `"id":"let-scalars","kind":"output","success":true`,
        ) && strings.contains(
            output,
            `"id":"let-nested","kind":"output","success":true`,
        ) && strings.contains(
            output,
            `"id":"semantic-typed-let","kind":"output","success":true`,
        ) && strings.contains(
            output,
            `"id":"semantic-nested-let","kind":"output","success":true`,
        ) && strings.contains(
            output,
            `"id":"semantic-control-flow","kind":"output","success":true`,
        ) && strings.contains(
            output,
            `"id":"semantic-control-native","kind":"output","success":true`,
        ) && strings.contains(
            output,
            `"id":"semantic-mixed-number","kind":"output","success":true`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(semantic_control_output, `"text":"42\n"`) &&
        strings.contains(semantic_control_native_output, `"text":"42\n"`),
        true,
    )
    if load_found && composite_found && repeated_found &&
       repeated_output_found {
        load_bytes, load_bytes_found :=
            repl_jsonl_int_field(load_timing, "generated_bytes")
        composite_bytes, composite_bytes_found :=
            repl_jsonl_int_field(composite_timing, "generated_bytes")
        repeated_bytes, repeated_bytes_found :=
            repl_jsonl_int_field(repeated_timing, "generated_bytes")
        testing.expect_value(t, load_bytes_found, true)
        testing.expect_value(t, composite_bytes_found, true)
        testing.expect_value(t, repeated_bytes_found, true)
        testing.expect_value(
            t,
            composite_bytes > 0 && composite_bytes*4 < load_bytes,
            true,
        )
        testing.expect_value(t, repeated_bytes, composite_bytes)
        testing.expect_value(
            t,
            strings.contains(
                repeated_timing,
                `"phase":"odin-build","elapsed_ns":0`,
            ),
            true,
        )
        testing.expect_value(
            t,
            strings.contains(repeated_timing, `"native_cache_hit":true`),
            true,
        )
        testing.expect_value(
            t,
            strings.contains(repeated_output, `"text":":article\n"`),
            true,
        )
    }
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"str-first","kind":"output","success":true`,
        ) && strings.contains(
            output,
            `"id":"str-repeat","kind":"output","success":true`,
        ),
        true,
    )
    if str_first_found && str_repeat_found {
        testing.expect_value(
            t,
            strings.contains(
                str_first_timing,
                `"phase":"odin-build","elapsed_ns":0`,
            ),
            false,
        )
        testing.expect_value(
            t,
            strings.contains(
                str_repeat_timing,
                `"phase":"odin-build","elapsed_ns":0`,
            ),
            true,
        )
        testing.expect_value(
            t,
            strings.contains(
                str_repeat_timing,
                `"execution_path":"resident-scalar"`,
            ),
            true,
        )
    }
    if semantic_string_found && semantic_string_output_found {
        testing.expect_value(
            t,
            strings.contains(
                semantic_string_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(
                semantic_string_output,
                `"text":"true\n"`,
            ),
            true,
        )
    }
    if string_result_first_found && string_result_first_output_found {
        testing.expect_value(
            t,
            strings.contains(
                string_result_first_timing,
                `"execution_path":"native-compile"`,
            ) && strings.contains(
                string_result_first_output,
                `"text":"Kvist\n"`,
            ),
            true,
        )
    }
    if string_result_found && string_result_output_found {
        testing.expect_value(
            t,
            strings.contains(
                string_result_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(
                string_result_output,
                `"text":"true\n"`,
            ),
            true,
        )
    }
    if owned_string_result_first_found &&
       owned_string_result_first_output_found {
        testing.expect_value(
            t,
            strings.contains(
                owned_string_result_first_timing,
                `"execution_path":"native-compile"`,
            ) && strings.contains(
                owned_string_result_first_output,
                `"text":"kvist\n"`,
            ),
            true,
        )
    }
    if owned_string_result_found && owned_string_result_output_found {
        testing.expect_value(
            t,
            strings.contains(
                owned_string_result_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(
                owned_string_result_output,
                `"text":"true\n"`,
            ),
            true,
        )
    }
    if owned_borrowed_result_found &&
       owned_borrowed_result_output_found {
        testing.expect_value(
            t,
            strings.contains(
                owned_borrowed_result_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(
                owned_borrowed_result_output,
                `"text":"true\n"`,
            ),
            true,
        )
    }
    if data_managed_found && data_managed_output_found {
        testing.expect_value(
            t,
            strings.contains(
                data_managed_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) && strings.contains(
                data_managed_output,
                `"text":"0\n"`,
            ),
            true,
        )
    }
    if data_final_first_found && data_final_repeat_found &&
       data_final_repeat_output_found {
        testing.expect_value(
            t,
            (strings.contains(
                data_final_first_timing,
                `"execution_path":"native-compile"`,
            ) || strings.contains(
                data_final_first_timing,
                `"execution_path":"resident-semantic-plan"`,
            )) && (strings.contains(
                data_final_repeat_timing,
                `"execution_path":"resident-semantic-plan"`,
            ) || strings.contains(
                data_final_repeat_timing,
                `"execution_path":"resident-cache"`,
            )) && strings.contains(
                data_final_repeat_output,
                `"text":":article\n"`,
            ),
            true,
        )
    }
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"reject-unreachable-zero","kind":"diagnostics","success":false`,
        ) && strings.contains(
            output,
            "Division by zero not allowed",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"reject-out-of-range-plan","kind":"diagnostics","success":false`,
        ) && strings.contains(
            output,
            "The maximum value that can be represented by 'int'",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"use-shadowed-operator","kind":"output","success":true`,
        ) && strings.contains(
            output,
            `"text":"7\n"`,
        ),
        true,
    )
    shadowed_timing, shadowed_found :=
        repl_jsonl_event_line(output, "use-shadowed-operator", "timings")
    testing.expect_value(t, shadowed_found, true)
    if shadowed_found {
        testing.expect_value(
            t,
            strings.contains(
                shadowed_timing,
                `"execution_path":"resident-semantic-plan"`,
            ),
            true,
        )
    }
    testing.expect_value(t, string(stderr), "")
}

@(test)
cli_repl_jsonl_executes_native_multi_form_generation :: proc(t: ^testing.T) {
    dir, dir_err := os.make_directory_temp("", "kvist-repl-cli-*", context.allocator)
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    state_dir, state_dir_err :=
        os.join_path({dir, "state"}, context.allocator)
    testing.expect_value(t, state_dir_err == nil, true)
    if state_dir_err != nil {
        return
    }
    defer delete(state_dir)
    testing.expect_value(t, os.make_directory_all(state_dir) == nil, true)
    state_path, state_path_err :=
        os.join_path({state_dir, "state.kvist"}, context.allocator)
    testing.expect_value(t, state_path_err == nil, true)
    if state_path_err != nil {
        return
    }
    defer delete(state_path)
    state_source := `(package state)

(defvar calls 0)
(defvar init-count 0)

(def base: int
  (do
    (inc! init-count)
    10))

(defn next [] -> int
  (do
    (inc! calls)
    (+ base (* init-count 1000) calls)))`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(state_path, state_source) == nil,
        true,
    )

    context_path, context_err := os.join_path({dir, "context.kvist"}, context.allocator)
    testing.expect_value(t, context_err == nil, true)
    if context_err != nil {
        return
    }
    defer delete(context_path)
    context_source := `(package repl_test)
(import state "./state")

(defvar package-counter 0)
(defvar package-init-count 0)

(def package-base: int
  (do
    (inc! package-init-count)
    40))

(defn twice [value: int] -> int
  (* value 2))

(defn package-state [] -> int
  (do
    (inc! package-counter)
    (+ package-base (* package-init-count 100) package-counter)))

(defn imported-state [] -> int
  (state.next))`
    testing.expect_value(t, os.write_entire_file_from_string(context_path, context_source) == nil, true)

    requests_path, requests_err := os.join_path({dir, "requests.jsonl"}, context.allocator)
    testing.expect_value(t, requests_err == nil, true)
    if requests_err != nil {
        return
    }
    defer delete(requests_path)
    requests := `{"id":"eval-1","op":"eval","source":"(println \"first\")\n(twice 15)","native_debug_symbols":true}
{"id":"def-foo-1","op":"eval","source":"(defn foo [x: int] -> int (+ x 1))","source_path":"/virtual/editor.kvist","line":40,"column":3}
{"id":"def-caller","op":"eval","source":"(defn caller [x: int] -> int (* (foo x) 2))"}
{"id":"tooling-lookup","op":"lookup","name":"foo"}
{"id":"tooling-complete","op":"complete","name":"fo"}
{"id":"tooling-documentation","op":"documentation","name":"foo"}
{"id":"tooling-xref","op":"xref","name":"foo"}
{"id":"tooling-overlay","op":"lookup","name":"overlay-only","source":"(package repl_protocol_test)\n(defn overlay-only [x: int] -> int x)"}
{"id":"call-1","op":"eval","source":"(caller 10)"}
{"id":"def-foo-2","op":"eval","source":"(defn foo [x: int] -> int (+ x 100))"}
{"id":"call-2","op":"eval","source":"(caller 10)"}
{"id":"def-foo-signature","op":"eval","source":"(defn foo [x: string] -> string x)"}
{"id":"call-new-signature","op":"eval","source":"(foo \"new\")"}
{"id":"call-old-signature","op":"eval","source":"(caller 10)"}
{"id":"versions-foo","op":"versions","name":"foo"}
{"id":"definition-foo-v1","op":"definition-location","name":"foo","version":1}
{"id":"definition-foo-current","op":"definition-location","name":"foo"}
{"id":"definition-foo-missing","op":"definition-location","name":"foo","version":99}
{"id":"panic-worker","op":"eval","source":"(panic \"boom\")","no_print":true}
{"id":"stale-after-crash","op":"eval","source":"(caller 10)"}
{"id":"recover-after-crash","op":"eval","source":"(+ 4 5)"}
{"id":"eval-buffer","op":"eval","source":"(defn buffered-add [x: int] -> int (+ x 1))\n(defn buffered-call [x: int] -> int (* (buffered-add x) 2))\n(buffered-call 10)","source_path":"/virtual/editor.kvist","line":40,"column":3}
{"id":"call-buffered","op":"eval","source":"(buffered-call 20)"}
{"id":"failed-buffer","op":"eval","source":"(defn ghost [x: int] -> int x)\n(unknown-buffer-call 1)"}
{"id":"ghost-not-committed","op":"eval","source":"(ghost 1)"}
{"id":"def-eager-value","op":"eval","source":"(def answer: int (do (println \"value-init\") 42))"}
{"id":"def-value-caller","op":"eval","source":"(defn value-caller [x: int] -> int (+ x answer))"}
{"id":"call-value-1","op":"eval","source":"(value-caller 1)"}
{"id":"redef-value-compatible","op":"eval","source":"(def answer: int 100)"}
{"id":"call-value-2","op":"eval","source":"(value-caller 1)"}
{"id":"redef-value-type","op":"eval","source":"(def answer: f64 3.5)"}
{"id":"call-new-value-type","op":"eval","source":"answer"}
{"id":"call-old-value-type","op":"eval","source":"(value-caller 1)"}
{"id":"def-mutable-buffer","op":"eval","source":"(defvar counter: int 1)\n(defn bump-counter [] -> int (do (inc! counter) counter))"}
{"id":"bump-counter-1","op":"eval","source":"(bump-counter)"}
{"id":"set-counter","op":"eval","source":"(set! counter 5)\ncounter"}
{"id":"bump-counter-2","op":"eval","source":"(bump-counter)"}
{"id":"redef-counter-compatible","op":"eval","source":"(defvar counter: int 10)"}
{"id":"bump-counter-3","op":"eval","source":"(bump-counter)"}
{"id":"redef-counter-type","op":"eval","source":"(defvar counter: f64 2.5)"}
{"id":"call-new-counter-type","op":"eval","source":"counter"}
{"id":"bump-old-counter-type","op":"eval","source":"(bump-counter)"}
{"id":"def-dynamic-string","op":"eval","source":"(def greeting: string (do (println \"string-init\") (str \"hello \" 42)))"}
{"id":"read-dynamic-string","op":"eval","source":"greeting"}
{"id":"def-mutable-string","op":"eval","source":"(defvar label: string \"one\")\n(defn read-label [] -> string label)"}
{"id":"mutate-string","op":"eval","source":"(set! label \"two\")\n(read-label)"}
{"id":"redef-mutable-string","op":"eval","source":"(defvar label: string \"three\")"}
{"id":"read-redefined-string","op":"eval","source":"(read-label)"}
{"id":"def-aggregate-buffer","op":"eval","source":"(defstruct Repl-Point [x: int y: int])\n(defvar repl-point: Repl-Point (Repl-Point :x 1 :y 2))\n(defn move-old-point [n: int] -> int (do (set! repl-point.x (+ repl-point.x n)) repl-point.x))"}
{"id":"mutate-old-layout","op":"eval","source":"(move-old-point 5)"}
{"id":"redef-aggregate-layout","op":"eval","source":"(defstruct Repl-Point [x: int y: int z: int])\n(defvar repl-point: Repl-Point (Repl-Point :x 10 :y 20 :z 30))"}
{"id":"read-new-layout","op":"eval","source":"repl-point.z"}
{"id":"mutate-retained-old-layout","op":"eval","source":"(move-old-point 1)"}
{"id":"read-new-layout-after-old-mutation","op":"eval","source":"repl-point.x"}
{"id":"def-session-transform","op":"eval","source":"(defn repl-increment [x: int] -> int (+ x 1))\n(defn repl-times-ten [x: int] -> int (* x 10))\n(deftransform repl-transform (map repl-increment))\n(defn collect-old-transform [xs: [2]int] -> [dynamic]int (into [dynamic]int repl-transform xs))"}
{"id":"call-session-transform","op":"eval","source":"(collect-old-transform ([2]int [1 2]))"}
{"id":"redef-session-transform","op":"eval","source":"(deftransform repl-transform (map repl-times-ten))\n(defn collect-new-transform [xs: [2]int] -> [dynamic]int (into [dynamic]int repl-transform xs))"}
{"id":"call-new-session-transform","op":"eval","source":"(collect-new-transform ([2]int [1 2]))"}
{"id":"call-retained-old-transform","op":"eval","source":"(collect-old-transform ([2]int [1 2]))"}
{"id":"def-session-iterator","op":"eval","source":"(defstruct Repl-Source [values: [2]int index: int])\n(defn repl-open-source [values: [2]int] -> Repl-Source (Repl-Source :values values :index 0))\n(defn repl-next-source [src: ^Repl-Source] -> [value: int ok: bool] (if (< src.index 2) (let [value src.values[src.index]] (inc! src.index) (return value true)) (return 0 false)))\n(defiter repl-items [values: [2]int] -> Repl-Source :yield int :next repl-next-source (repl-open-source values))"}
{"id":"def-session-iterator-user","op":"eval","source":"(defn sum-repl-items [values: [2]int] -> int (let [total 0] (for [value (repl-items values)] (set! total (+ total value))) total))"}
{"id":"call-session-iterator","op":"eval","source":"(sum-repl-items ([2]int [3 4]))"}
{"id":"def-dependency-pair","op":"eval","source":"(defn dep-foo [x: int] -> int (+ x 1))\n(defn dep-middle [x: int] -> int (int (dep-foo x)))\n(defn dep-caller [x: int] -> string (str (dep-middle x)))"}
{"id":"call-dependency-before","op":"eval","source":"(dep-caller 1)"}
{"id":"evolve-dependency-abi","op":"eval","source":"(defn dep-foo [x: int] -> i64 (i64 (+ x 10)))"}
{"id":"query-stale-dependents","op":"dependents","name":"dep-foo"}
{"id":"call-stale-dependent","op":"eval","source":"(dep-caller 1)"}
{"id":"refresh-stale-dependents","op":"refresh-dependents","name":"dep-foo"}
{"id":"call-refreshed-dependent","op":"eval","source":"(dep-caller 1)"}
{"id":"versions-refreshed-dependent","op":"versions","name":"dep-caller"}
{"id":"refresh-one-binding","op":"refresh","name":"dep-caller"}
{"id":"call-single-refreshed-binding","op":"eval","source":"(dep-caller 1)"}
{"id":"redefine-compatible-dependency","op":"eval","source":"(defn dep-foo [x: int] -> i64 (i64 (+ x 20)))"}
{"id":"query-compatible-dependents","op":"dependents","name":"dep-foo"}
{"id":"call-compatible-dependent","op":"eval","source":"(dep-caller 1)"}
{"id":"import-session-package","op":"eval","source":"(import arr \"kvist:arr\")\n(count (arr.fixed int [1 2 3]))"}
{"id":"use-session-import","op":"eval","source":"(arr.second (arr.fixed int [4 5 6]))"}
{"id":"def-session-macro","op":"eval","source":"(defmacro session-add [x] (quasiquote (+ (unquote x) 1)))\n(session-add 4)"}
{"id":"use-session-macro","op":"eval","source":"(session-add 9)"}
{"id":"def-session-macro-user","op":"eval","source":"(defn macro-user [x: int] -> int (session-add x))"}
{"id":"call-old-session-macro-user","op":"eval","source":"(macro-user 9)"}
{"id":"redef-session-macro","op":"eval","source":"(defmacro session-add [x] (quasiquote (+ (unquote x) 10)))"}
{"id":"query-stale-macro-user","op":"dependents","name":"session-add"}
{"id":"call-stale-macro-user","op":"eval","source":"(macro-user 9)"}
{"id":"refresh-macro-user","op":"refresh-dependents","name":"session-add"}
{"id":"call-refreshed-macro-user","op":"eval","source":"(macro-user 9)"}
{"id":"macroexpand-session","op":"macroexpand","source":"(session-add 5)"}
{"id":"expand-session","op":"expand","source":"(session-add 5)"}
{"id":"expand-session-unknown","op":"expand","source":"(missing-inspection-call 1)"}
{"id":"def-managed-session-values","op":"eval","source":"(def managed-payload: Data (quote {:answer 41}))\n(def managed-nums: [dynamic]int ([dynamic]int [1 2 3]))"}
{"id":"read-managed-data","op":"eval","source":"(data.int (get managed-payload :answer))"}
{"id":"copy-managed-array","op":"eval","source":"(let [copy managed-nums :defer] (set! copy[0] 10) (+ copy[0] managed-nums[0]))"}
{"id":"def-mutable-managed-data","op":"eval","source":"(defvar mutable-managed: Data 5)"}
{"id":"set-mutable-managed-data","op":"eval","source":"(set! mutable-managed 9)\n(data.int mutable-managed)"}
{"id":"drop-managed-array","op":"drop","name":"managed-nums"}
{"id":"dropped-array-is-hidden","op":"eval","source":"managed-nums"}
{"id":"drop-managed-data","op":"drop","name":"managed-payload"}
{"id":"def-mutable-dynamic-array","op":"eval","source":"(defvar mutable-numbers: [dynamic]int ([dynamic]int [1 2]))"}
{"id":"set-mutable-dynamic-array","op":"eval","source":"(set! mutable-numbers ([dynamic]int [5 6 7]))\n(+ mutable-numbers[0] mutable-numbers[2])"}
{"id":"def-mutable-data-array","op":"eval","source":"(defvar mutable-data-items: [dynamic]Data ([dynamic]Data [1 2]))"}
{"id":"set-mutable-data-array","op":"eval","source":"(set! mutable-data-items ([dynamic]Data [5 6 7]))\n(+ (data.int mutable-data-items[0]) (data.int mutable-data-items[2]))"}
{"id":"recent-int","op":"eval","source":"40"}
{"id":"recent-string","op":"eval","source":"\"hello\""}
{"id":"use-recent-mixed","op":"eval","source":"(+ (count *1) *2)"}
{"id":"recent-data","op":"eval","source":"(quote {:answer 9})"}
{"id":"use-recent-data","op":"eval","source":"(data.int (get *1 :answer))"}
{"id":"recent-array","op":"eval","source":"([dynamic]int [7 8])"}
{"id":"use-recent-array-copies","op":"eval","source":"(let [a *1 :defer b *1 :defer] (set! a[0] 20) (+ a[0] b[0]))"}
{"id":"results-1","op":"results"}
{"id":"silent-recent","op":"eval","source":"99","no_print":true}
{"id":"read-silent-recent","op":"eval","source":"*1"}
{"id":"recent-definition","op":"eval","source":"(defn recent-helper [x: int] -> int x)"}
{"id":"results-after-definition","op":"results"}
{"id":"def-borrow-owner","op":"eval","source":"(def borrow-owner: string (str \"  kept  \"))"}
{"id":"borrowed-result","op":"eval","source":"(import rstr \"kvist:str\")\n(rstr.trim borrow-owner)"}
{"id":"read-borrowed-result","op":"eval","source":"*1"}
{"id":"local-borrowed-result","op":"eval","source":"(let [owner (str \"  local  \") :defer] (rstr.trim owner))"}
{"id":"read-local-borrowed-result","op":"eval","source":"*1"}
{"id":"local-slice-owner","op":"eval","source":"(let [owner ([dynamic]int [3 4]) :defer] (odin-slice owner 1))"}
{"id":"results-after-local-slice","op":"results"}
{"id":"def-persistent-map","op":"eval","source":"(def persistent-map: map[string]int (map[string]int {\"a\" 1}))"}
{"id":"read-persistent-map","op":"eval","source":"persistent-map[\"a\"]"}
{"id":"def-mutable-map","op":"eval","source":"(defvar mutable-map: map[string]int (map[string]int {\"x\" 1}))"}
{"id":"mutate-map-entry","op":"eval","source":"(set! mutable-map[\"y\"] 5)\n(+ mutable-map[\"x\"] mutable-map[\"y\"])"}
{"id":"replace-mutable-map","op":"eval","source":"(set! mutable-map (map[string]int {\"z\" 9}))\nmutable-map[\"z\"]"}
{"id":"recent-map","op":"eval","source":"(map[string]int {\"k\" 7})"}
{"id":"use-recent-map-copies","op":"eval","source":"(let [copy *1 :defer] (set! copy[\"k\"] 20) (+ copy[\"k\"] *1[\"k\"]))"}
{"id":"results-after-map","op":"results"}
{"id":"inspect-recent","op":"inspect","source":"(do (inc! package-counter) repl-point)"}
{"id":"inspect-retained-field","op":"inspect","handle":"inspection-1","path":["x"]}
{"id":"inspect-array-shape","op":"inspect","source":"([dynamic]int [1 2])"}
{"id":"inspect-wrong-selector","op":"inspect","handle":"inspection-3","key_source":"\"a\""}
{"id":"inspect-retained-index","op":"inspect","handle":"inspection-3","index":1}
{"id":"inspect-map-shape","op":"inspect","source":"(map[string]int {\"a\" 1})"}
{"id":"inspect-retained-map-key","op":"inspect","handle":"inspection-5","key_source":"\"a\""}
{"id":"results-after-inspect","op":"results"}
{"id":"inspect-definition","op":"inspect","source":"(defn hidden-inspection [x: int] -> int x)"}
{"id":"package-state-1","op":"eval","source":"(package-state)"}
{"id":"package-state-2","op":"eval","source":"(package-state)"}
{"id":"imported-state-1","op":"eval","source":"(imported-state)"}
{"id":"imported-state-2","op":"eval","source":"(imported-state)"}
{"id":"bindings-1","op":"bindings"}
{"id":"inspect-array-page","op":"inspect-page","handle":"inspection-3","offset":0,"limit":1}
{"id":"inspect-map-page","op":"inspect-page","handle":"inspection-5","offset":0,"limit":1}
{"id":"inspect-page-too-large","op":"inspect-page","handle":"inspection-3","offset":0,"limit":101}
{"id":"loaded-generations","op":"generations"}
{"id":"debug-session-live","op":"debug-session"}
{"id":"breakpoint-foo","op":"breakpoint-locations","source_path":"/virtual/editor.kvist","line":40}
{"id":"def-nested-pause","op":"eval","source":"(defn paused-add [x: int] -> int (do (kvist-intrinsic-breakpoint) (+ x 1)))","source_path":"/virtual/editor.kvist","line":100,"column":3}
{"id":"call-nested-pause","op":"eval","source":"(paused-add 5)","source_path":"/virtual/editor.kvist","line":110,"column":1}
{"id":"eval-nested-local","op":"debug-eval","source":"x"}
{"id":"eval-nested-expression","op":"debug-eval","source":"(+ x 7)"}
{"id":"eval-nested-predicate","op":"debug-eval","source":"(and (> x 0) (< x 10))"}
{"id":"eval-nested-if","op":"debug-eval","source":"(if (= x 5) (* x 2) (/ 1 0))"}
{"id":"reject-nested-call","op":"debug-eval","source":"(paused-add x)"}
{"id":"reject-nested-types","op":"debug-eval","source":"(+ x true)"}
{"id":"reject-nested-zero","op":"debug-eval","source":"(/ x 0)"}
{"id":"reject-nested-overflow","op":"debug-eval","source":"(+ 9223372036854775807 1)"}
{"id":"reject-nested-branches","op":"debug-eval","source":"(if true 1 false)"}
{"id":"nested-frame","op":"debug-frame"}
{"id":"step-nested-pause","op":"debug-step"}
{"id":"stepped-frame","op":"debug-frame"}
{"id":"continue-nested-pause","op":"debug-continue"}
{"id":"def-struct-pause","op":"eval","source":"(defstruct DebugCursor [line: int])\n(defstruct DebugPair [left: int right: bool cursor: DebugCursor samples: [2]int])\n(defn paused-pair [pair: DebugPair values: [dynamic]int points: [dynamic]DebugCursor scores: map[string]int] -> int (do (kvist-intrinsic-breakpoint) pair.left))","source_path":"/virtual/editor.kvist","line":130,"column":1}
{"id":"call-struct-pause","op":"eval","source":"(paused-pair (DebugPair :left 7 :right true :cursor (DebugCursor :line 31) :samples [11 13]) ([dynamic]int [17 19 23 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64]) ([dynamic]DebugCursor [(DebugCursor :line 41) (DebugCursor :line 43) (DebugCursor :line 47)]) (map[string]int {\"zoe\" 9 \"alice\" 7 \"bob\" 8}))","source_path":"/virtual/editor.kvist","line":140,"column":1}
{"id":"eval-struct-field","op":"debug-eval","source":"pair.left"}
{"id":"eval-struct-bool","op":"debug-eval","source":"pair.right"}
{"id":"eval-struct-expression","op":"debug-eval","source":"(+ pair.left 8)"}
{"id":"eval-nested-struct-field","op":"debug-eval","source":"pair.cursor.line"}
{"id":"eval-nested-struct-expression","op":"debug-eval","source":"(+ pair.cursor.line pair.left)"}
{"id":"eval-fixed-array-path","op":"debug-eval","source":"pair.samples[1]"}
{"id":"eval-fixed-array-expression","op":"debug-eval","source":"(+ pair.samples[0] pair.samples[1])"}
{"id":"eval-dynamic-array-path","op":"debug-eval","source":"values[2]"}
{"id":"eval-dynamic-array-expression","op":"debug-eval","source":"(+ values[0] values[2])"}
{"id":"eval-dynamic-struct-path","op":"debug-eval","source":"points[1].line"}
{"id":"eval-dynamic-struct-expression","op":"debug-eval","source":"(+ points[1].line 1)"}
{"id":"eval-map-path","op":"debug-eval","source":"scores[\"alice\"]"}
{"id":"eval-map-expression","op":"debug-eval","source":"(+ scores[\"bob\"] 2)"}
{"id":"reject-debug-page-limit","op":"debug-page","source":"values","offset":0,"limit":101}
{"id":"page-dynamic-array-tail","op":"debug-page","source":"values","offset":64,"limit":1}
{"id":"page-map-tail","op":"debug-page","source":"scores","offset":1,"limit":2}
{"id":"reject-dynamic-array-truncated-index","op":"debug-eval","source":"values[64]"}
{"id":"reject-fixed-array-dynamic-index","op":"debug-eval","source":"pair.samples[pair.left]"}
{"id":"reject-fixed-array-uncaptured-index","op":"debug-eval","source":"pair.samples[9]"}
{"id":"struct-frame","op":"debug-frame"}
{"id":"continue-struct-pause","op":"debug-continue"}
{"id":"def-nested-collection-pause","op":"eval","source":"(defstruct NestedItem [events: [dynamic]int tags: map[string]int])\n(defstruct NestedState [id: int history: [dynamic]int labels: map[string]int buckets: [2][dynamic]int groups: [dynamic]NestedItem users: map[string]NestedItem])\n(defn paused-nested-collections [snapshot: NestedState] -> int (do (kvist-intrinsic-breakpoint) snapshot.id))","source_path":"/virtual/editor.kvist","line":160,"column":1}
{"id":"call-nested-collection-pause","op":"eval","source":"(paused-nested-collections (NestedState :id 4 :history ([dynamic]int [10 20 30 40]) :labels (map[string]int {\"z\" 9 \"a\" 1 \"m\" 5}) :buckets ([2][dynamic]int [([dynamic]int [1 2]) ([dynamic]int [7 8 9])]) :groups ([dynamic]NestedItem [(NestedItem :events ([dynamic]int [2 3]) :tags (map[string]int {\"first\" 1})) (NestedItem :events ([dynamic]int [11 12 13]) :tags (map[string]int {\"z\" 9 \"a\" 4}))]) :users (map[string]NestedItem {\"bob\" (NestedItem :events ([dynamic]int [5]) :tags (map[string]int {\"b\" 2})) \"alice\" (NestedItem :events ([dynamic]int [21 22 23]) :tags (map[string]int {\"z\" 8 \"a\" 6}))})))","source_path":"/virtual/editor.kvist","line":170,"column":1}
{"id":"page-nested-array","op":"debug-page","source":"snapshot.history","offset":2,"limit":2}
{"id":"page-nested-map","op":"debug-page","source":"snapshot.labels","offset":0,"limit":2}
{"id":"page-fixed-nested-array","op":"debug-page","source":"snapshot.buckets[1]","offset":1,"limit":2}
{"id":"page-runtime-nested-array","op":"debug-page","source":"snapshot.groups[1].events","offset":1,"limit":2}
{"id":"page-runtime-nested-map","op":"debug-page","source":"snapshot.groups[1].tags","offset":0,"limit":2}
{"id":"page-map-value-array","op":"debug-page","source":"snapshot.users[\"alice\"].events","offset":1,"limit":2}
{"id":"page-map-value-map","op":"debug-page","source":"snapshot.users[\"alice\"].tags","offset":0,"limit":2}
{"id":"nested-collection-frame","op":"debug-frame"}
{"id":"continue-nested-collection-pause","op":"debug-continue"}
{"id":"pause-eval","op":"eval","source":"(+ 20 22)","source_path":"/virtual/editor.kvist","line":75,"column":5,"pause_before":true}
{"id":"paused-bindings","op":"bindings"}
{"id":"continue-pause","op":"debug-continue"}
{"id":"ownership-history-before-reset","op":"ownership-history"}
{"id":"reset-after-bindings","op":"reset"}
{"id":"inspect-expired","op":"inspect","handle":"inspection-1","path":["x"]}
{"id":"results-empty","op":"results"}
{"id":"bindings-empty","op":"bindings"}
{"id":"generations-empty","op":"generations"}
{"id":"debug-session-reset","op":"debug-session"}
{"id":"def-default-proc","op":"eval","source":"(defn default-proc [x: int y: int :default 2] -> int (+ x y))"}
{"id":"def-default-caller","op":"eval","source":"(defn default-caller [] -> int (default-proc 5))"}
{"id":"call-default-v1","op":"eval","source":"(default-caller)"}
{"id":"redef-default-proc","op":"eval","source":"(defn default-proc [x: int y: int :default 20] -> int (+ x y))"}
{"id":"call-default-v2","op":"eval","source":"(default-proc 5)"}
{"id":"call-default-old-caller","op":"eval","source":"(default-caller)"}
{"id":"def-custom-abi","op":"eval","source":"(defn custom-abi :abi \"c\" [x: int] -> int (+ x 1))"}
{"id":"call-custom-abi","op":"eval","source":"(custom-abi 8)"}
{"id":"def-directed-proc","op":"eval","source":"(defn directed-proc [x: int] -> int #force_inline (+ x 2))"}
{"id":"call-directed-proc","op":"eval","source":"(directed-proc 8)"}
{"id":"def-generic-procs","op":"eval","source":"(import intrinsics \"base:intrinsics\")\n(defn generic-id [x: $T] -> T x)\n(defn generic-same? [value: $T expected: T] -> bool (where (intrinsics.type-is-comparable T)) (= value expected))"}
{"id":"call-generic-int","op":"eval","source":"(generic-id 11)"}
{"id":"call-generic-string","op":"eval","source":"(generic-id \"generic\")"}
{"id":"call-generic-constrained","op":"eval","source":"(generic-same? 7 7)"}
{"id":"nested-retained-view","op":"eval","source":"(defstruct Retained-Window [values: []int])\n(let [owner ([dynamic]int [3 4 5]) :defer] (Retained-Window :values (odin-slice owner 1)))"}
{"id":"read-nested-retained-view","op":"eval","source":"(let [window *1] window.values[0])"}
{"id":"define-nested-retained-view","op":"eval","source":"(def retained-window: Retained-Window (let [owner ([dynamic]int [6 7 8]) :defer] (Retained-Window :values (odin-slice owner 1))))"}
{"id":"read-defined-retained-view","op":"eval","source":"retained-window.values[0]"}
{"id":"interrupt-pause","op":"eval","source":"(do (kvist-intrinsic-breakpoint) 99)"}
{"id":"interrupt-active","op":"interrupt"}
{"id":"recover-interrupt","op":"eval","source":"(+ 1 2)"}
{"id":"invalid-timeout","op":"eval","source":"1","timeout_ms":0}
{"id":"deadline-eval","op":"eval","source":"(do (while true (discard 1)) 0)","timeout_ms":50}
{"id":"recover-deadline","op":"eval","source":"(+ 2 3)"}
{"id":"separate-stderr","op":"eval","source":"(import fmt \"core:fmt\")\n(fmt.eprintln \"native-stderr\")","no_print":true}
{"id":"unretained-pointer","op":"eval","source":"(defn pointer-result [] -> rawptr nil)\n(pointer-result)","source_path":"/virtual/pointer.kvist","line":7,"column":3}
{"id":"history-layout-v1","op":"eval","source":"(defstruct History-Point [x: int])","source_path":"/virtual/history-v1.kvist","line":10,"column":1,"no_print":true}
{"id":"inspect-history-v1","op":"inspect","source":"(History-Point :x 7)"}
{"id":"history-layout-v2","op":"eval","source":"(defstruct History-Point [x: int y: int])","source_path":"/virtual/history-v2.kvist","line":20,"column":1,"no_print":true}
{"id":"inspect-history-v1-cached","op":"inspect","handle":"inspection-1"}
{"id":"allocations-1","op":"allocations"}
{"id":"ownership-history-1","op":"ownership-history"}
{"id":"abort-definitions","op":"eval","source":"(defvar abort-probe: int 0)\n(defvar abort-cleanup: int 0)\n(defn record-abort-cleanup [] (inc! abort-cleanup))\n(defn abort-inside [] -> int (do (defer (record-abort-cleanup)) (set! abort-probe 8) (kvist-intrinsic-breakpoint) (set! abort-probe 9) 42))"}
{"id":"abort-call","op":"eval","source":"(abort-inside)"}
{"id":"abort-control","op":"debug-abort"}
{"id":"abort-state","op":"eval","source":"abort-probe"}
{"id":"abort-cleanup-state","op":"eval","source":"abort-cleanup"}
{"id":"condition-live-source","op":"eval","source":"(import condition \"kvist:condition\")\n(defn repl-condition-source [x: int] -> int (do (condition.signal :test/live \"live condition\" {:x x}) (+ x 1)))"}
{"id":"condition-live-handler","op":"eval","source":"(defn repl-condition-handler [problem: condition.Condition] -> condition.Decision (do (println \"live-handler\") (condition.continue)))"}
{"id":"condition-live-call","op":"eval","source":"(condition.with-handlers {:test/live repl-condition-handler} (repl-condition-source 8))"}
{"id":"dedupe-def-1","op":"eval","source":"(defn unchanged-definition [x: int] -> int (+ x 1))"}
{"id":"dedupe-def-2","op":"eval","source":"(defn unchanged-definition [x: int] -> int (+ x 1))"}
{"id":"dedupe-versions","op":"versions","name":"unchanged-definition"}
{"id":"iterator-v1","op":"eval","source":"(defstruct Live-Iterator-Source [values: [3]int index: int])\n(defn open-live-items [values: [3]int] -> Live-Iterator-Source (Live-Iterator-Source :values values :index 0))\n(defn next-live-item [source: ^Live-Iterator-Source] -> [value: int ok: bool] (if (< source.index 3) (let [value source.values[source.index]] (inc! source.index) (return value true)) (return 0 false)))\n(defiter live-items [values: [3]int] -> Live-Iterator-Source :yield int :next next-live-item (open-live-items values))\n(defn sum-live-items [values: [3]int] -> int (let [total 0] (for [value (live-items values)] (set! total (+ total value))) total))"}
{"id":"iterator-old-call","op":"eval","source":"(sum-live-items ([3]int [1 2 3]))"}
{"id":"iterator-v2","op":"eval","source":"(defstruct Live-Iterator-Source [values: [3]int index: int factor: int])\n(defn open-live-items [values: [3]int] -> Live-Iterator-Source (Live-Iterator-Source :values values :index 0 :factor 2))\n(defn next-live-item [source: ^Live-Iterator-Source] -> [value: int ok: bool] (if (< source.index 3) (let [value (* source.values[source.index] source.factor)] (inc! source.index) (return value true)) (return 0 false)))\n(defiter live-items [values: [3]int] -> Live-Iterator-Source :yield int :next next-live-item (open-live-items values))"}
{"id":"iterator-retained-call","op":"eval","source":"(sum-live-items ([3]int [1 2 3]))"}
{"id":"iterator-stale-dependents","op":"dependents","name":"live-items"}
{"id":"iterator-refresh","op":"refresh-dependents","name":"live-items"}
{"id":"iterator-refreshed-call","op":"eval","source":"(sum-live-items ([3]int [1 2 3]))"}
{"id":"native-cache-define","op":"eval","source":"(defvar native-cache-count: int 0)\n(defn native-cache-bump [] -> int (do (inc! native-cache-count) native-cache-count))"}
{"id":"native-cache-call-1","op":"eval","source":"(native-cache-bump)"}
{"id":"native-cache-call-2","op":"eval","source":"(native-cache-bump)"}
{"id":"native-cache-call-3","op":"eval","source":"(native-cache-bump)"}
{"id":"native-cache-call-4","op":"eval","source":"(native-cache-bump)"}
{"id":"native-cache-call-5","op":"eval","source":"(native-cache-bump)"}
{"id":"native-cache-call-6","op":"eval","source":"(native-cache-bump)"}
{"id":"close-1","op":"close"}
`
    testing.expect_value(t, os.write_entire_file_from_string(requests_path, requests) == nil, true)
    request_file, open_err := os.open(requests_path)
    testing.expect_value(t, open_err == nil, true)
    if open_err != nil {
        return
    }
    defer os.close(request_file)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)

    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "repl", context_path, "--protocol", "jsonl"},
            working_dir = repo_root,
            stdin = request_file,
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
    output := string(stdout)
    stale_macro_timing, stale_macro_timing_found :=
        repl_jsonl_event_line(output, "call-stale-macro-user", "timings")
    testing.expect_value(t, stale_macro_timing_found, true)
    if stale_macro_timing_found {
        testing.expect_value(
            t,
            strings.contains(
                stale_macro_timing,
                `"execution_path":"native-compile"`,
            ),
            true,
        )
    }
    testing.expect_value(t, strings.contains(output, `"kind":"ready"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-1","kind":"output"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-1","kind":"generation-loaded","success":true,"generation":1`), true)
    testing.expect_value(t, strings.contains(output, `"evaluation-phase-timings"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-1","kind":"timings","success":true,"generation":1`), true)
    testing.expect_value(t, strings.contains(output, `"phase":"frontend-total","elapsed_ns":`), true)
    testing.expect_value(t, strings.contains(output, `"phase":"odin-build","elapsed_ns":`), true)
    testing.expect_value(t, strings.contains(output, `"phase":"worker-roundtrip","elapsed_ns":`), true)
    testing.expect_value(t, strings.contains(output, `"phase":"worker-load","elapsed_ns":`), true)
    testing.expect_value(t, strings.contains(output, `"phase":"native-run","elapsed_ns":`), true)
    testing.expect_value(t, strings.contains(output, `"generated_bytes":`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-1","kind":"stream-output","success":true,"generation":1,"stream":"stdout","text":"first\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-1","kind":"complete","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-foo-1","kind":"complete","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-caller","kind":"complete","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"id":"tooling-lookup","kind":"lookup","success":true,"generation":3`), true)
    testing.expect_value(t, strings.contains(output, `"name":"foo"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"tooling-complete","kind":"completions","success":true,"generation":3`), true)
    testing.expect_value(t, strings.contains(output, `"id":"tooling-documentation","kind":"documentation","success":true,"generation":3`), true)
    testing.expect_value(t, strings.contains(output, `"id":"tooling-xref","kind":"xref","success":true,"generation":3`), true)
    testing.expect_value(t, strings.contains(output, `"id":"tooling-overlay","kind":"lookup","success":true,"generation":3`), true)
    testing.expect_value(t, strings.contains(output, `"name":"overlay-only"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-1","kind":"output","success":true,"generation":4,"stream":"stdout","text":"22\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-foo-2","kind":"complete","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-2","kind":"output","success":true,"generation":6,"stream":"stdout","text":"220\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-new-signature","kind":"output","success":true,"generation":8,"stream":"stdout","text":"new\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-old-signature","kind":"output","success":true,"generation":9,"stream":"stdout","text":"220\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"versions-foo","kind":"versions","success":true,"generation":9,"versions":[{"version":1,"generation":2,"kind":"defn","abi":"proc(int:borrowed)->int","source_path":"/virtual/editor.kvist","source_start_line":40,"source_start_column":3`), true)
    testing.expect_value(t, strings.contains(output, `{"version":2,"generation":5,"kind":"defn","abi":"proc(int:borrowed)->int","source_path":"`), true)
    testing.expect_value(t, strings.contains(output, `{"version":3,"generation":7,"kind":"defn","abi":"proc(string:borrowed)->string:borrowed","source_path":"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"definition-foo-v1","kind":"definition-location","success":true,"generation":9,"abi":"proc(int:borrowed)->int","source_path":"/virtual/editor.kvist","line":40,"column":3`), true)
    testing.expect_value(t, strings.contains(output, `"name":"foo","definition_kind":"defn","version":1,"definition_generation":2`), true)
    testing.expect_value(t, strings.contains(output, `"id":"definition-foo-current","kind":"definition-location","success":true,"generation":9,"abi":"proc(string:borrowed)->string:borrowed"`), true)
    testing.expect_value(t, strings.contains(output, `"name":"foo","definition_kind":"defn","version":3,"definition_generation":7`), true)
    testing.expect_value(t, strings.contains(output, `"id":"definition-foo-missing","kind":"complete","success":false,"generation":9,"message":"unknown REPL binding version: foo 99"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"panic-worker","kind":"complete","success":false,"generation":10`), true)
    testing.expect_value(t, strings.contains(output, `"id":"panic-worker","kind":"native-crash","success":false,"generation":10`), true)
    testing.expect_value(t, strings.contains(output, `"failure_kind":"unexpected-worker-exit","exit_code":`), true)
    testing.expect_value(t, strings.contains(output, `"id":"stale-after-crash","kind":"worker-replaced","success":true,"generation":11`), true)
    testing.expect_value(t, strings.contains(output, `"id":"stale-after-crash","kind":"complete","success":false,"generation":11`), true)
    testing.expect_value(t, strings.contains(output, "Undeclared name: caller"), true)
    testing.expect_value(t, strings.contains(output, `"id":"recover-after-crash","kind":"output","success":true,"generation":12,"stream":"stdout","text":"9\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-buffer","kind":"output","success":true,"generation":13,"stream":"stdout","text":"22\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-buffered","kind":"output","success":true,"generation":14,"stream":"stdout","text":"42\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"failed-buffer","kind":"complete","success":false,"generation":15`), true)
    testing.expect_value(t, strings.contains(output, `"id":"failed-buffer","kind":"diagnostics","success":false,"generation":15`), true)
    testing.expect_value(t, strings.contains(output, `"severity":"error","phase":"odin"`), true)
    testing.expect_value(t, strings.contains(output, "Undeclared name: unknown_buffer_call"), true)
    testing.expect_value(t, strings.contains(output, `"id":"ghost-not-committed","kind":"complete","success":false,"generation":16`), true)
    testing.expect_value(t, strings.contains(output, "Undeclared name: ghost"), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-eager-value","kind":"stream-output","success":true,"generation":17,"stream":"stdout","text":"value-init\n"`), true)
    testing.expect_value(t, count_substring(output, "value-init"), 1)
    testing.expect_value(t, strings.contains(output, `"id":"call-value-1","kind":"output","success":true,"generation":19,"stream":"stdout","text":"43\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-value-2","kind":"output","success":true,"generation":21,"stream":"stdout","text":"101\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-new-value-type","kind":"output","success":true,"generation":23,"stream":"stdout","text":"3.5\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-old-value-type","kind":"output","success":true,"generation":24,"stream":"stdout","text":"101\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"bump-counter-1","kind":"output","success":true,"generation":26,"stream":"stdout","text":"2\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"set-counter","kind":"output","success":true,"generation":27,"stream":"stdout","text":"5\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"bump-counter-2","kind":"output","success":true,"generation":28,"stream":"stdout","text":"6\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"bump-counter-3","kind":"output","success":true,"generation":30,"stream":"stdout","text":"11\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-new-counter-type","kind":"output","success":true,"generation":32,"stream":"stdout","text":"2.5\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"bump-old-counter-type","kind":"output","success":true,"generation":33,"stream":"stdout","text":"12\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-dynamic-string","kind":"stream-output","success":true,"generation":34,"stream":"stdout","text":"string-init\n"`), true)
    testing.expect_value(t, count_substring(output, "string-init"), 1)
    testing.expect_value(t, strings.contains(output, `"id":"read-dynamic-string","kind":"output","success":true,"generation":35,"stream":"stdout","text":"hello 42\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"mutate-string","kind":"output","success":true,"generation":37,"stream":"stdout","text":"two\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"read-redefined-string","kind":"output","success":true,"generation":39,"stream":"stdout","text":"three\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"mutate-old-layout","kind":"output","success":true,"generation":41,"stream":"stdout","text":"6\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"read-new-layout","kind":"output","success":true,"generation":43,"stream":"stdout","text":"30\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"mutate-retained-old-layout","kind":"output","success":true,"generation":44,"stream":"stdout","text":"7\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"read-new-layout-after-old-mutation","kind":"output","success":true,"generation":45,"stream":"stdout","text":"10\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-session-transform","kind":"complete","success":true,"generation":46`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-session-transform","kind":"output","success":true,"generation":47,"stream":"stdout","text":"[2, 3]\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"redef-session-transform","kind":"complete","success":true,"generation":48`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-new-session-transform","kind":"output","success":true,"generation":49,"stream":"stdout","text":"[10, 20]\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-retained-old-transform","kind":"output","success":true,"generation":50,"stream":"stdout","text":"[2, 3]\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-session-iterator","kind":"complete","success":true,"generation":51`), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-session-iterator-user","kind":"complete","success":true,"generation":52`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-session-iterator","kind":"output","success":true,"generation":53,"stream":"stdout","text":"7\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-dependency-before","kind":"output","success":true,"generation":55,"stream":"stdout","text":"2\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"query-stale-dependents","kind":"dependents","success":true,"generation":56`), true)
    testing.expect_value(t, strings.contains(output, `{"name":"dep-middle","kind":"defn","version":1,"generation":54,"abi":"proc(int:borrowed)->int","dependencies":["dep-foo"],"stale":true}`), true)
    testing.expect_value(t, strings.contains(output, `{"name":"dep-caller","kind":"defn","version":1,"generation":54,"abi":"proc(int:borrowed)->string:owned","dependencies":["dep-middle"],"stale":true}`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-stale-dependent","kind":"output","success":true,"generation":57,"stream":"stdout","text":"2\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"refresh-stale-dependents","kind":"complete","success":true,"generation":58`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-refreshed-dependent","kind":"output","success":true,"generation":59,"stream":"stdout","text":"11\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"versions-refreshed-dependent","kind":"versions","success":true,"generation":59`), true)
    testing.expect_value(t, strings.contains(output, `{"version":1,"generation":54,"kind":"defn","abi":"proc(int:borrowed)->string:owned","dependencies":["dep-middle"],"source_path":"`), true)
    testing.expect_value(t, strings.contains(output, `{"version":2,"generation":58,"kind":"defn","abi":"proc(int:borrowed)->string:owned","dependencies":["dep-middle"],"source_path":"`), true)
    testing.expect_value(t, count_substring(output, `"source_start_line":3,"source_start_column":1`), 2)
    testing.expect_value(t, strings.contains(output, `"id":"refresh-one-binding","kind":"complete","success":true,"generation":60`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-single-refreshed-binding","kind":"output","success":true,"generation":61,"stream":"stdout","text":"11\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"query-compatible-dependents","kind":"dependents","success":true,"generation":62`), true)
    testing.expect_value(t, strings.contains(output, `{"name":"dep-middle","kind":"defn","version":2,"generation":58,"abi":"proc(int:borrowed)->int","dependencies":["dep-foo"],"stale":false}`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-compatible-dependent","kind":"output","success":true,"generation":63,"stream":"stdout","text":"21\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"import-session-package","kind":"output","success":true,"generation":64,"stream":"stdout","text":"3\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"use-session-import","kind":"output","success":true,"generation":65,"stream":"stdout","text":"5\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-session-macro","kind":"output","success":true,"generation":66,"stream":"stdout","text":"5\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"use-session-macro","kind":"output","success":true,"generation":67,"stream":"stdout","text":"10\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-old-session-macro-user","kind":"output","success":true,"generation":69,"stream":"stdout","text":"10\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"query-stale-macro-user","kind":"dependents","success":true,"generation":70`), true)
    testing.expect_value(t, strings.contains(output, `{"name":"macro-user","kind":"defn","version":1,"generation":68,"abi":"proc(int:borrowed)->int","dependencies":["session-add"],"stale":true}`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-stale-macro-user","kind":"output","success":true,"generation":71,"stream":"stdout","text":"10\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"refresh-macro-user","kind":"complete","success":true,"generation":72`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-refreshed-macro-user","kind":"output","success":true,"generation":73,"stream":"stdout","text":"19\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"macroexpand-session","kind":"expansion","success":true,"generation":73`), true)
    testing.expect_value(t, strings.contains(output, `(+ 5 10)\n`), true)
    testing.expect_value(t, strings.contains(output, `"id":"expand-session","kind":"expansion","success":true,"generation":73`), true)
    testing.expect_value(t, strings.contains(output, `kvist_repl_result_value := (5) + (10)`), true)
    testing.expect_value(t, strings.contains(output, `"id":"expand-session-unknown","kind":"expansion","success":true,"generation":73`), true)
    testing.expect_value(t, strings.contains(output, "missing_inspection_call(1)"), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-managed-session-values","kind":"complete","success":true,"generation":74`), true)
    testing.expect_value(t, strings.contains(output, `"id":"read-managed-data","kind":"output","success":true,"generation":75,"stream":"stdout","text":"41\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"copy-managed-array","kind":"output","success":true,"generation":76,"stream":"stdout","text":"11\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"set-mutable-managed-data","kind":"output","success":true,"generation":78,"stream":"stdout","text":"9\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"drop-managed-array","kind":"drop","success":true,"generation":78`), true)
    testing.expect_value(t, strings.contains(output, `"id":"dropped-array-is-hidden","kind":"complete","success":false,"generation":79`), true)
    testing.expect_value(t, strings.contains(output, "Undeclared name: managed_nums"), true)
    testing.expect_value(t, strings.contains(output, `"id":"drop-managed-data","kind":"drop","success":true,"generation":79`), true)
    testing.expect_value(t, strings.contains(output, `"id":"set-mutable-dynamic-array","kind":"output","success":true,"generation":81,"stream":"stdout","text":"12\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"set-mutable-data-array","kind":"output","success":true,"generation":83,"stream":"stdout","text":"12\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"recent-int","kind":"output","success":true,"generation":84,"stream":"stdout","text":"40\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"recent-string","kind":"output","success":true,"generation":85,"stream":"stdout","text":"hello\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"use-recent-mixed","kind":"output","success":true,"generation":86,"stream":"stdout","text":"45\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"recent-data","kind":"output","success":true,"generation":87,"stream":"stdout","text":"{:answer 9}\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"use-recent-data","kind":"output","success":true,"generation":88,"stream":"stdout","text":"9\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"recent-array","kind":"output","success":true,"generation":89,"stream":"stdout","text":"[7, 8]\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"use-recent-array-copies","kind":"output","success":true,"generation":90,"stream":"stdout","text":"27\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"results-1","kind":"results","success":true,"generation":90`), true)
    testing.expect_value(t, strings.contains(output, `{"slot":1,"name":"*1","type":"int","abi":"value:int","generation":90,`), true)
    testing.expect_value(t, strings.contains(output, `{"slot":2,"name":"*2","type":"[dynamic]int","abi":"value:[dynamic]int","generation":89,"lifecycle":{"ownership":"owned","storage":"worker","clone":"snapshot","destroy":"deferred","checkpoint":"snapshot","render":"native"}`), true)
    testing.expect_value(t, strings.contains(output, `{"slot":3,"name":"*3","type":"i64","abi":"value:i64","generation":88,`), true)
    testing.expect_value(t, strings.contains(output, `"id":"silent-recent","kind":"output"`), false)
    testing.expect_value(t, strings.contains(output, `"id":"silent-recent","kind":"complete","success":true,"generation":91`), true)
    testing.expect_value(t, strings.contains(output, `"id":"read-silent-recent","kind":"output","success":true,"generation":92,"stream":"stdout","text":"99\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"recent-definition","kind":"complete","success":true,"generation":93`), true)
    testing.expect_value(t, strings.contains(output, `"id":"results-after-definition","kind":"results","success":true,"generation":93`), true)
    testing.expect_value(t, strings.contains(output, `{"slot":1,"name":"*1","type":"int","abi":"value:int","generation":91,`), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-borrow-owner","kind":"complete","success":true,"generation":94`), true)
    testing.expect_value(t, strings.contains(output, `"id":"borrowed-result","kind":"output","success":true,"generation":95,"stream":"stdout","text":"kept\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"read-borrowed-result","kind":"output","success":true,"generation":96,"stream":"stdout","text":"kept\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"local-borrowed-result","kind":"output","success":true,"generation":97,"stream":"stdout","text":"local\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"read-local-borrowed-result","kind":"output","success":true,"generation":98,"stream":"stdout","text":"local\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"local-slice-owner","kind":"output","success":true,"generation":99,"stream":"stdout","text":"[4]\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"local-slice-owner","kind":"complete","success":true,"generation":99`), true)
    testing.expect_value(t, strings.contains(output, `"id":"results-after-local-slice","kind":"results","success":true,"generation":99`), true)
    testing.expect_value(t, strings.contains(output, `{"slot":1,"name":"*1","type":"[]int","abi":"value:[]int","generation":99,"lifecycle":{"ownership":"retained-view","storage":"worker-backed","clone":"promote","destroy":"worker-exit","checkpoint":"snapshot","render":"native"}`), true)
    testing.expect_value(t, strings.contains(output, `"owner_id":"repl-worker","allocation_id":"result:g99"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-persistent-map","kind":"complete","success":true,"generation":100`), true)
    testing.expect_value(t, strings.contains(output, `"id":"read-persistent-map","kind":"output","success":true,"generation":101,"stream":"stdout","text":"1\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-mutable-map","kind":"complete","success":true,"generation":102`), true)
    testing.expect_value(t, strings.contains(output, `"id":"mutate-map-entry","kind":"output","success":true,"generation":103,"stream":"stdout","text":"6\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"replace-mutable-map","kind":"output","success":true,"generation":104,"stream":"stdout","text":"9\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"recent-map","kind":"output","success":true,"generation":105,"stream":"stdout","text":"map[k=7]\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"use-recent-map-copies","kind":"output","success":true,"generation":106,"stream":"stdout","text":"27\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"results-after-map","kind":"results","success":true,"generation":106`), true)
    testing.expect_value(t, strings.contains(output, `{"slot":1,"name":"*1","type":"int","abi":"value:int","generation":106,`), true)
    testing.expect_value(t, strings.contains(output, `{"slot":2,"name":"*2","type":"map[string]int","abi":"value:map[string]int","generation":105,"lifecycle":{"ownership":"owned","storage":"worker","clone":"snapshot","destroy":"deferred","checkpoint":"snapshot","render":"native"}`), true)
    testing.expect_value(t, strings.contains(output, `"id":"inspect-recent","kind":"inspection","success":true,"generation":107,"text":"Repl_Point{x = 10, y = 20, z = 30}\n","type":"Repl_Point","abi":"value:Repl_Point|layout:Repl_Point=struct{x:int;y:int;z:int;}","handle":"inspection-1","shape":"struct","members":[{"name":"x","type":"int"},{"name":"y","type":"int"},{"name":"z","type":"int"}]`), true)
    testing.expect_value(t, strings.contains(output, `"name":"Repl-Point","definition_kind":"defstruct","version":2`), true)
    testing.expect_value(t, strings.contains(output, `"allocation_id":"inspection-1","retained_owner_chain":["repl-worker"],"size":24,"alignment":8`), true)
    testing.expect_value(t, strings.contains(output, `"id":"inspect-retained-field","kind":"inspection","success":true,"generation":108,"text":"10\n","type":"int","abi":"value:int","handle":"inspection-2","path":["x"],"shape":"scalar"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"inspect-array-shape","kind":"inspection","success":true,"generation":109,"type":"[dynamic]int","abi":"value:[dynamic]int","handle":"inspection-3","shape":"dynamic-array","element_type":"int","offset":0,"limit":20,"total":2,"entries":[{"index":0,"value":"1"},{"index":1,"value":"2"}]`), true)
    testing.expect_value(t, strings.contains(output, `"allocation_id":"inspection-3","retained_owner_chain":["repl-worker"]`), true)
    testing.expect_value(t, strings.contains(output, `"id":"inspect-wrong-selector","kind":"complete","success":false,"generation":109,"message":"invalid inspection child path"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"inspect-retained-index","kind":"inspection","success":true,"generation":110,"text":"2\n","type":"int","abi":"value:int","handle":"inspection-4","index":1,"shape":"scalar"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"inspect-map-shape","kind":"inspection","success":true,"generation":111,"type":"map[string]int","abi":"value:map[string]int","handle":"inspection-5","shape":"map","key_type":"string","value_type":"int","offset":0,"limit":20,"total":1,"entries":[{"key":"a","value":"1"}]`), true)
    testing.expect_value(t, strings.contains(output, `"id":"inspect-retained-map-key","kind":"inspection","success":true,"generation":112,"text":"1\n","type":"int","abi":"value:int","handle":"inspection-6","key_source":"\"a\"","shape":"scalar"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"results-after-inspect","kind":"results","success":true,"generation":112,"results":[{"slot":1,"name":"*1","type":"int","abi":"value:int","generation":106,`), true)
    testing.expect_value(t, strings.contains(output, `"id":"results-after-inspect","kind":"complete","success":true,"generation":112`), true)
    testing.expect_value(t, strings.contains(output, `"id":"inspect-definition","kind":"complete","success":false,"generation":112,"message":"inspect accepts an expression, not persistent definitions"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"package-state-1","kind":"output","success":true,"generation":113,"stream":"stdout","text":"142\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"package-state-2","kind":"output","success":true,"generation":114,"stream":"stdout","text":"143\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"imported-state-1","kind":"output","success":true,"generation":115,"stream":"stdout","text":"1011\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"imported-state-2","kind":"output","success":true,"generation":116,"stream":"stdout","text":"1012\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"bindings-1","kind":"bindings","success":true,"generation":116`), true)
    testing.expect_value(t, strings.contains(output, `{"name":"Repl-Point","kind":"defstruct","version":2,`), true)
    testing.expect_value(t, strings.contains(output, `{"name":"repl-point","kind":"defvar","version":2,`), true)
    testing.expect_value(t, strings.contains(output, `{"name":"repl-transform","kind":"deftransform","version":2,`), true)
    testing.expect_value(t, strings.contains(output, `{"name":"repl-items","kind":"defiter","version":1,`), true)
    testing.expect_value(t, strings.contains(output, `{"name":"dep-caller","kind":"defn","version":3,"generation":60,"abi":"proc(int:borrowed)->string:owned","dependencies":["dep-middle"],"stale":false}`), true)
    testing.expect_value(t, strings.contains(output, `{"name":"session-add","kind":"defmacro","version":2,"generation":70,"stale":false}`), true)
    testing.expect_value(t, strings.contains(output, `{"name":"macro-user","kind":"defn","version":2,"generation":72,"abi":"proc(int:borrowed)->int","dependencies":["session-add"],"stale":false}`), true)
    testing.expect_value(t, strings.contains(output, `{"name":"mutable-managed","kind":"defvar","version":1,"generation":77,"abi":"var:Data","stale":false,"type":"Data","lifecycle":{"ownership":"owned"`), true)
    testing.expect_value(t, strings.contains(output, `{"name":"mutable-numbers","kind":"defvar","version":1,"generation":80,"abi":"var:[dynamic]int","stale":false,"type":"[dynamic]int","lifecycle":{"ownership":"owned"`), true)
    testing.expect_value(t, strings.contains(output, `{"name":"mutable-data-items","kind":"defvar","version":1,"generation":82,"abi":"var:[dynamic]Data","stale":false,"type":"[dynamic]Data","lifecycle":{"ownership":"owned"`), true)
    testing.expect_value(t, strings.contains(output, `{"name":"persistent-map","kind":"def","version":1,"generation":100,"abi":"value:map[string]int","stale":false,"type":"map[string]int","lifecycle":{"ownership":"owned"`), true)
    testing.expect_value(t, strings.contains(output, `{"name":"mutable-map","kind":"defvar","version":1,"generation":102,"abi":"var:map[string]int","stale":false,"type":"map[string]int","lifecycle":{"ownership":"owned"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"inspect-array-page","kind":"inspection-page","success":true,"generation":117,"type":"[dynamic]int","abi":"value:[dynamic]int","handle":"inspection-3","shape":"dynamic-array","element_type":"int","offset":0,"limit":1,"total":2,"entries":[{"index":0,"value":"1"}]`), true)
    testing.expect_value(t, strings.contains(output, `"id":"inspect-map-page","kind":"inspection-page","success":true,"generation":118,"type":"map[string]int","abi":"value:map[string]int","handle":"inspection-5","shape":"map","key_type":"string","value_type":"int","offset":0,"limit":1,"total":1,"entries":[{"key":"a","value":"1"}]`), true)
    testing.expect_value(t, strings.contains(output, `"id":"inspect-page-too-large","kind":"complete","success":false,"generation":118,"message":"invalid inspection page request"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"loaded-generations","kind":"generations","success":true,"generation":118`), true)
    testing.expect_value(t, strings.contains(output, `generation_0118.odin`), true)
    testing.expect_value(t, strings.contains(output, `generation_0118.map`), true)
    testing.expect_value(t, strings.contains(output, fmt.tprintf("generation_0118.%s", dynlib.LIBRARY_FILE_EXTENSION)), true)
    testing.expect_value(t, strings.contains(output, `"debug_symbols":true`), true)
    testing.expect_value(t, strings.contains(output, `"debug_symbols":false`), true)
    testing.expect_value(t, strings.contains(output, `"id":"loaded-generations","kind":"complete","success":true,"generation":118`), true)
    testing.expect_value(t, strings.contains(output, `"id":"debug-session-live","kind":"debug-session","success":true,"generation":118`), true)
    testing.expect_value(t, strings.contains(output, `"worker_epoch":2,"capabilities":[`), true)
    testing.expect_value(t, strings.contains(output, `"session-completion"`), true)
    testing.expect_value(t, strings.contains(output, `"session-lookup"`), true)
    testing.expect_value(t, strings.contains(output, `"session-documentation"`), true)
    testing.expect_value(t, strings.contains(output, `"session-xref"`), true)
    testing.expect_value(t, strings.contains(output, `"lifecycle-metadata"`), true)
    testing.expect_value(t, strings.contains(output, `"nested-retained-views"`), true)
    testing.expect_value(t, strings.contains(output, `"native-crash-events"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"debug-session-live","kind":"complete","success":true,"generation":118`), true)
    testing.expect_value(t, strings.contains(output, `"id":"breakpoint-foo","kind":"breakpoint-locations","success":true,"generation":118`), true)
    testing.expect_value(t, strings.contains(output, `"generation":13,"source_path":"/virtual/editor.kvist","source_start_line":40,"source_start_column":3`), true)
    testing.expect_value(t, strings.contains(output, `"generated_path":"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-nested-pause","kind":"complete","success":true,"generation":119`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-nested-pause","kind":"paused","success":true,"generation":120,"pause_id":"pause-119-37-65","source_path":"/virtual/editor.kvist","line":100,"column":40`), true)
    testing.expect_value(t, strings.contains(output, `"frame_id":"frame-pause-119-37-65","pause_id":"pause-119-37-65","generation":119,"definition_name":"paused-add","definition_version":1,"source_path":"/virtual/editor.kvist","line":100,"column":40,"phase":"before-form"`), true)
    testing.expect_value(t, strings.contains(output, `"locals":[{"name":"x","type":"int","mutable":false,"ownership":"borrowed","value":"5"`), true)
    testing.expect_value(t, strings.contains(output, `"lifecycle":{"ownership":"borrowed","storage":"frame","clone":"promote","destroy":"frame-exit","checkpoint":"snapshot","render":"native"}`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-nested-local","kind":"debug-value","success":true,"generation":120,"text":"5","type":"int","pause_id":"pause-119-37-65"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-nested-local","kind":"complete","success":true,"generation":120`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-nested-expression","kind":"debug-value","success":true,"generation":120,"text":"12","type":"int","pause_id":"pause-119-37-65"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-nested-predicate","kind":"debug-value","success":true,"generation":120,"text":"true","type":"bool","pause_id":"pause-119-37-65"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-nested-if","kind":"debug-value","success":true,"generation":120,"text":"10","type":"int","pause_id":"pause-119-37-65"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"reject-nested-call","kind":"complete","success":false,"generation":120,"message":"unsupported operator in paused evaluation: paused-add"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"reject-nested-types","kind":"complete","success":false,"generation":120,"message":"+ expects int operands in paused evaluation"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"reject-nested-zero","kind":"complete","success":false,"generation":120,"message":"division by zero in paused evaluation"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"reject-nested-overflow","kind":"complete","success":false,"generation":120,"message":"integer overflow in paused evaluation"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"reject-nested-branches","kind":"complete","success":false,"generation":120,"message":"paused if branches must have the same type"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"nested-frame","kind":"debug-frame","success":true,"generation":120,"pause_id":"pause-119-37-65"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"step-nested-pause","kind":"stepping","success":true,"generation":120,"pause_id":"pause-119-37-65"`), true)
    testing.expect_value(t, strings.contains(output, `"pause_id":"pause-119-66-73"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"stepped-frame","kind":"debug-frame","success":true,"generation":120,"pause_id":"pause-119-66-73"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"continue-nested-pause","kind":"resumed","success":true,"generation":120,"pause_id":"pause-119-66-73"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-nested-pause","kind":"output","success":true,"generation":120,"stream":"stdout","text":"6\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-struct-pause","kind":"complete","success":true,"generation":121`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-struct-pause","kind":"paused","success":true,"generation":122,"pause_id":"pause-121-238-266","source_path":"/virtual/editor.kvist","line":132,"column":121`), true)
    testing.expect_value(t, strings.contains(output, `"paths":[{"path":"left","type":"int","value":"7"},{"path":"right","type":"bool","value":"true"},`), true)
    testing.expect_value(t, strings.contains(output, `{"path":"cursor.line","type":"int","value":"31"}`), true)
    testing.expect_value(t, strings.contains(output, `{"path":"samples[0]","type":"int","value":"11"},{"path":"samples[1]","type":"int","value":"13"}`), true)
    testing.expect_value(t, strings.contains(output, `"element_type":"int","capture_limit":64,"total":65,"truncated":true`), true)
    testing.expect_value(t, strings.contains(output, `"value":"<dynamic-array count=65>"`), true)
    testing.expect_value(t, strings.contains(output, `{"path":"[0]","type":"int","value":"17"},{"path":"[1]","type":"int","value":"19"},{"path":"[2]","type":"int","value":"23"}`), true)
    testing.expect_value(t, strings.contains(output, `{"path":"[63]","type":"int","value":"63"}`), true)
    testing.expect_value(t, strings.contains(output, `"element_type":"DebugCursor","capture_limit":32,"total":3,"truncated":false`), true)
    testing.expect_value(t, strings.contains(output, `{"path":"[1].line","type":"int","value":"43"}`), true)
    testing.expect_value(t, strings.contains(output, `"value":"<map count=3>"`), true)
    testing.expect_value(t, strings.contains(output, `{"path":"[\"alice\"]","type":"int","value":"7"},{"path":"[\"bob\"]","type":"int","value":"8"},{"path":"[\"zoe\"]","type":"int","value":"9"}],"key_type":"string","value_type":"int","capture_limit":64,"total":3,"truncated":false`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-struct-field","kind":"debug-value","success":true,"generation":122,"text":"7","type":"int","pause_id":"pause-121-238-266"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-struct-bool","kind":"debug-value","success":true,"generation":122,"text":"true","type":"bool","pause_id":"pause-121-238-266"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-struct-expression","kind":"debug-value","success":true,"generation":122,"text":"15","type":"int","pause_id":"pause-121-238-266"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-nested-struct-field","kind":"debug-value","success":true,"generation":122,"text":"31","type":"int","pause_id":"pause-121-238-266"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-nested-struct-expression","kind":"debug-value","success":true,"generation":122,"text":"38","type":"int","pause_id":"pause-121-238-266"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-fixed-array-path","kind":"debug-value","success":true,"generation":122,"text":"13","type":"int","pause_id":"pause-121-238-266"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-fixed-array-expression","kind":"debug-value","success":true,"generation":122,"text":"24","type":"int","pause_id":"pause-121-238-266"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-dynamic-array-path","kind":"debug-value","success":true,"generation":122,"text":"23","type":"int","pause_id":"pause-121-238-266"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-dynamic-array-expression","kind":"debug-value","success":true,"generation":122,"text":"40","type":"int","pause_id":"pause-121-238-266"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-dynamic-struct-path","kind":"debug-value","success":true,"generation":122,"text":"43","type":"int","pause_id":"pause-121-238-266"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-dynamic-struct-expression","kind":"debug-value","success":true,"generation":122,"text":"44","type":"int","pause_id":"pause-121-238-266"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-map-path","kind":"debug-value","success":true,"generation":122,"text":"7","type":"int","pause_id":"pause-121-238-266"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"eval-map-expression","kind":"debug-value","success":true,"generation":122,"text":"10","type":"int","pause_id":"pause-121-238-266"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"reject-debug-page-limit","kind":"complete","success":false,"generation":122,"message":"invalid paused collection page request"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"page-dynamic-array-tail","kind":"debug-page","success":true,"generation":122,"shape":"dynamic-array","element_type":"int","offset":64,"limit":1,"total":65,"entries":[{"index":64,"value":"64"}],"pause_id":"pause-121-238-266","collection_path":"values"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"page-map-tail","kind":"debug-page","success":true,"generation":122,"shape":"map","key_type":"string","value_type":"int","offset":1,"limit":2,"total":3,"entries":[{"index":1,"key":"bob","value":"8"},{"index":2,"key":"zoe","value":"9"}],"pause_id":"pause-121-238-266","collection_path":"scores"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"reject-dynamic-array-truncated-index","kind":"complete","success":false,"generation":122,"message":"aggregate path is not captured in the active frame: values[64]"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"reject-fixed-array-dynamic-index","kind":"complete","success":false,"generation":122,"message":"paused aggregate access requires a literal index or map key"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"reject-fixed-array-uncaptured-index","kind":"complete","success":false,"generation":122,"message":"aggregate path is not captured in the active frame: pair.samples[9]"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"struct-frame","kind":"debug-frame","success":true,"generation":122,"pause_id":"pause-121-238-266"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"continue-struct-pause","kind":"resumed","success":true,"generation":122,"pause_id":"pause-121-238-266"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-struct-pause","kind":"output","success":true,"generation":122,"stream":"stdout","text":"7\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-nested-collection-pause","kind":"complete","success":true,"generation":123`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-nested-collection-pause","kind":"paused","success":true,"generation":124`), true)
    testing.expect_value(t, strings.contains(output, `"id":"page-nested-array","kind":"debug-page","success":true,"generation":124,"shape":"dynamic-array","element_type":"int","offset":2,"limit":2,"total":4,"entries":[{"index":2,"value":"30"},{"index":3,"value":"40"}]`), true)
    testing.expect_value(t, strings.contains(output, `"id":"page-nested-map","kind":"debug-page","success":true,"generation":124,"shape":"map","key_type":"string","value_type":"int","offset":0,"limit":2,"total":3,"entries":[{"index":0,"key":"a","value":"1"},{"index":1,"key":"m","value":"5"}]`), true)
    testing.expect_value(t, strings.contains(output, `"id":"page-fixed-nested-array","kind":"debug-page","success":true,"generation":124,"shape":"dynamic-array","element_type":"int","offset":1,"limit":2,"total":3,"entries":[{"index":1,"value":"8"},{"index":2,"value":"9"}]`), true)
    testing.expect_value(t, strings.contains(output, `"id":"page-runtime-nested-array","kind":"debug-page","success":true,"generation":124,"shape":"dynamic-array","element_type":"int","offset":1,"limit":2,"total":3,"entries":[{"index":1,"value":"12"},{"index":2,"value":"13"}]`), true)
    testing.expect_value(t, strings.contains(output, `"id":"page-runtime-nested-map","kind":"debug-page","success":true,"generation":124,"shape":"map","key_type":"string","value_type":"int","offset":0,"limit":2,"total":2,"entries":[{"index":0,"key":"a","value":"4"},{"index":1,"key":"z","value":"9"}]`), true)
    testing.expect_value(t, strings.contains(output, `"id":"page-map-value-array","kind":"debug-page","success":true,"generation":124,"shape":"dynamic-array","element_type":"int","offset":1,"limit":2,"total":3,"entries":[{"index":1,"value":"22"},{"index":2,"value":"23"}]`), true)
    testing.expect_value(t, strings.contains(output, `"id":"page-map-value-map","kind":"debug-page","success":true,"generation":124,"shape":"map","key_type":"string","value_type":"int","offset":0,"limit":2,"total":2,"entries":[{"index":0,"key":"a","value":"6"},{"index":1,"key":"z","value":"8"}]`), true)
    testing.expect_value(t, strings.contains(output, `"id":"nested-collection-frame","kind":"debug-frame","success":true,"generation":124`), true)
    testing.expect_value(t, strings.contains(output, `"collections":[{"path":"snapshot.history","shape":"dynamic-array","element_type":"int"},{"path":"snapshot.labels","shape":"map","key_type":"string","value_type":"int"},{"path":"snapshot.buckets[0]","shape":"dynamic-array","element_type":"int"},{"path":"snapshot.buckets[1]","shape":"dynamic-array","element_type":"int"},{"path":"snapshot.groups","shape":"dynamic-array","element_type":"NestedItem"},{"path":"snapshot.groups[0].events","shape":"dynamic-array","element_type":"int"},{"path":"snapshot.groups[0].tags","shape":"map","key_type":"string","value_type":"int"},{"path":"snapshot.groups[1].events","shape":"dynamic-array","element_type":"int"},{"path":"snapshot.groups[1].tags","shape":"map","key_type":"string","value_type":"int"},{"path":"snapshot.users","shape":"map","key_type":"string","value_type":"NestedItem"},{"path":"snapshot.users[\"alice\"].events","shape":"dynamic-array","element_type":"int"},{"path":"snapshot.users[\"alice\"].tags","shape":"map","key_type":"string","value_type":"int"},{"path":"snapshot.users[\"bob\"].events","shape":"dynamic-array","element_type":"int"},{"path":"snapshot.users[\"bob\"].tags","shape":"map","key_type":"string","value_type":"int"}]`), true)
    testing.expect_value(t, strings.contains(output, `"id":"continue-nested-collection-pause","kind":"resumed","success":true,"generation":124`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-nested-collection-pause","kind":"output","success":true,"generation":124,"stream":"stdout","text":"4\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"pause-eval","kind":"paused","success":true,"generation":125,"pause_id":"pause-125","source_path":"/virtual/editor.kvist","line":75,"column":5`), true)
    testing.expect_value(t, strings.contains(output, `"id":"paused-bindings","kind":"complete","success":false,"generation":125,"message":"REPL is paused; send debug-frame, debug-page, debug-eval, debug-eval-native, debug-restart, debug-step, debug-step-over, debug-step-out, debug-continue, debug-abort, or interrupt with the active pause_id"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"continue-pause","kind":"resumed","success":true,"generation":125,"pause_id":"pause-125"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"continue-pause","kind":"complete","success":true,"generation":125`), true)
    testing.expect_value(t, strings.contains(output, `"id":"pause-eval","kind":"output","success":true,"generation":125,"stream":"stdout","text":"42\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"pause-eval","kind":"complete","success":true,"generation":125`), true)
    testing.expect_value(t, strings.contains(output, `"id":"ownership-history-before-reset","kind":"ownership-history","success":true,"generation":125`), true)
    testing.expect_value(t, strings.contains(output, `"allocation_id":"binding:managed-nums:v1","action":"dropped","generation":78,"name":"managed-nums","type":"[dynamic]int","owner_from":"repl-worker","reason":"binding explicitly dropped"`), true)
    testing.expect_value(t, strings.contains(output, `"action":"evicted"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"reset-after-bindings","kind":"reset","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"id":"inspect-expired","kind":"complete","success":false,"generation":0,"message":"unknown or expired inspection handle"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"results-empty","kind":"results","success":true,"generation":0`), true)
    testing.expect_value(t, strings.contains(output, `"id":"bindings-empty","kind":"bindings","success":true,"generation":0`), true)
    testing.expect_value(t, strings.contains(output, `"id":"generations-empty","kind":"generations","success":true,"generation":0`), true)
    testing.expect_value(t, strings.contains(output, `"id":"generations-empty","kind":"complete","success":true,"generation":0`), true)
    testing.expect_value(t, strings.contains(output, `"id":"debug-session-reset","kind":"debug-session","success":true,"generation":0`), true)
    testing.expect_value(t, strings.contains(output, `"worker_epoch":3`), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-default-proc","kind":"complete","success":true,"generation":1`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-default-v1","kind":"output","success":true,"generation":3,"stream":"stdout","text":"7\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"redef-default-proc","kind":"complete","success":true,"generation":4`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-default-v2","kind":"output","success":true,"generation":5,"stream":"stdout","text":"25\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-default-old-caller","kind":"output","success":true,"generation":6,"stream":"stdout","text":"7\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-custom-abi","kind":"complete","success":true,"generation":7`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-custom-abi","kind":"output","success":true,"generation":8,"stream":"stdout","text":"9\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-directed-proc","kind":"complete","success":true,"generation":9`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-directed-proc","kind":"output","success":true,"generation":10,"stream":"stdout","text":"10\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"def-generic-procs","kind":"complete","success":true,"generation":11`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-generic-int","kind":"output","success":true,"generation":12,"stream":"stdout","text":"11\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-generic-string","kind":"output","success":true,"generation":13,"stream":"stdout","text":"generic\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"call-generic-constrained","kind":"output","success":true,"generation":14,"stream":"stdout","text":"true\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"nested-retained-view","kind":"output","success":true,"generation":15,"stream":"stdout","text":"Retained_Window{values = [4, 5]}\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"read-nested-retained-view","kind":"output","success":true,"generation":16,"stream":"stdout","text":"4\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"define-nested-retained-view","kind":"complete","success":true,"generation":17`), true)
    testing.expect_value(t, strings.contains(output, `"id":"read-defined-retained-view","kind":"output","success":true,"generation":18,"stream":"stdout","text":"7\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"interrupt-active","kind":"interrupted","success":true,"generation":19`), true)
    testing.expect_value(t, strings.contains(output, `"id":"interrupt-pause","kind":"complete","success":false,"generation":19`), true)
    testing.expect_value(t, strings.contains(output, `"id":"recover-interrupt","kind":"worker-replaced","success":true,"generation":20`), true)
    testing.expect_value(t, strings.contains(output, `"id":"recover-interrupt","kind":"output","success":true,"generation":20,"stream":"stdout","text":"3\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"invalid-timeout","kind":"complete","success":false,"generation":20,"message":"timeout_ms must be between 1 and 3600000"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"deadline-eval","kind":"deadline-exceeded","success":false,"generation":21,"message":"evaluation deadline exceeded after 50 ms"`), true)
    testing.expect_value(t, strings.contains(output, `"timeout_ms":50`), true)
    testing.expect_value(t, strings.contains(output, `"id":"recover-deadline","kind":"worker-replaced","success":true,"generation":22`), true)
    testing.expect_value(t, strings.contains(output, `"id":"recover-deadline","kind":"output","success":true,"generation":22,"stream":"stdout","text":"5\n"`), true)
    testing.expect_value(t, strings.contains(output, `"separate-worker-streams"`), true)
    testing.expect_value(t, strings.contains(output, `"unretained-lifecycle-diagnostics"`), true)
    testing.expect_value(t, strings.contains(output, `"native-layout-metadata"`), true)
    testing.expect_value(t, strings.contains(output, `"inspection-definition-versions"`), true)
    testing.expect_value(t, strings.contains(output, `"cached-inspection-snapshots"`), true)
    testing.expect_value(t, strings.contains(output, `"logical-allocation-inventory"`), true)
    testing.expect_value(t, strings.contains(output, `"ownership-lifecycle-history"`), true)
    testing.expect_value(t, strings.contains(output, `"runtime-checkpoint-allocation-stats"`), true)
    testing.expect_value(t, strings.contains(output, `"generation-managed-allocation-stats"`), true)
    testing.expect_value(t, strings.contains(output, `"physical-allocation-inventory"`), true)
    testing.expect_value(t, strings.contains(output, `"physical-result-ownership-transfers"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"separate-stderr","kind":"output","success":true,"generation":23,"stream":"stderr","text":"native-stderr\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"unretained-pointer","kind":"diagnostics","success":true,"generation":24`), true)
    testing.expect_value(t, strings.contains(output, `"diagnostics":[{"severity":"warning","code":"KVR001","confidence":"definite","phase":"compile"`), true)
    testing.expect_value(t, strings.contains(output, `"source_path":"/virtual/pointer.kvist","line":8,"column":1`), true)
    testing.expect_value(t, strings.contains(output, `"id":"unretained-pointer","kind":"complete","success":true,"generation":24`), true)
    testing.expect_value(t, strings.contains(output, `"id":"inspect-history-v1","kind":"inspection","success":true,"generation":26`), true)
    testing.expect_value(t, strings.contains(output, `"type":"History_Point","abi":"value:History_Point|layout:History_Point=struct{x:int;}"`), true)
    testing.expect_value(t, strings.contains(output, `"source_path":"/virtual/history-v1.kvist","line":10,"column":1`), true)
    testing.expect_value(t, strings.contains(output, `"name":"History-Point","definition_kind":"defstruct","version":1,"definition_generation":25`), true)
    testing.expect_value(t, strings.contains(output, `"id":"inspect-history-v1-cached","kind":"inspection","success":true,"generation":27`), true)
    testing.expect_value(t, strings.contains(output, `"generation":27,"text":"History_Point{x = 7}\n","type":"History_Point","abi":"value:History_Point|layout:History_Point=struct{x:int;}"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"inspect-history-v1-cached","kind":"complete","success":true,"generation":27`), true)
    testing.expect_value(t, strings.contains(output, `"id":"allocations-1","kind":"allocations","success":true,"generation":27`), true)
    testing.expect_value(t, strings.contains(output, `"allocation_id":"inspection-1","owner_id":"repl-worker","kind":"inspection","name":"inspection-1","type":"History_Point","abi":"value:History_Point|layout:History_Point=struct{x:int;}"`), true)
    testing.expect_value(t, strings.contains(output, `"known_allocation_bytes":8,"known_allocation_count":1`), true)
    testing.expect_value(t, strings.contains(output, `"id":"ownership-history-1","kind":"ownership-history","success":true,"generation":27`), true)
    testing.expect_value(t, strings.contains(output, `"allocation_id":"inspection-1","action":"retained","generation":26,"name":"inspection-1","type":"History_Point","owner_to":"repl-worker","reason":"inspection snapshot retained"`), true)
    testing.expect_value(t, strings.contains(output, `"instrumented-debug-abort"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"abort-control","kind":"abort-requested","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"id":"abort-call","kind":"aborted","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"id":"abort-call","kind":"complete","success":false`), true)
    testing.expect_value(t, strings.contains(output, `"id":"abort-state","kind":"output","success":true,"generation":30,"stream":"stdout","text":"8\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"abort-cleanup-state","kind":"output","success":true,"generation":31,"stream":"stdout","text":"1\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"condition-live-source","kind":"complete","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"id":"condition-live-handler","kind":"complete","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"id":"condition-live-call","kind":"stream-output","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"text":"live-handler\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"condition-live-call","kind":"output","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"text":"9\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"dedupe-def-1","kind":"generation-loaded"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"dedupe-def-2","kind":"generation-loaded"`), false)
    testing.expect_value(t, count_substring(output, `"id":"dedupe-def-2"`), 1)
    testing.expect_value(t, strings.contains(output, `"id":"dedupe-versions","kind":"versions","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"id":"iterator-old-call","kind":"output","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"id":"iterator-old-call","kind":"output","success":true,"generation":`), true)
    testing.expect_value(t, strings.contains(output, `"id":"iterator-retained-call","kind":"output","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"id":"iterator-stale-dependents","kind":"dependents","success":true`), true)
    testing.expect_value(t, strings.contains(output, `{"name":"sum-live-items","kind":"defn"`), true)
    testing.expect_value(t, strings.contains(output, `"abi":"proc([3]int:borrowed)->int","dependencies":["live-items"],"stale":true`), true)
    testing.expect_value(t, strings.contains(output, `"id":"iterator-refresh","kind":"complete","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"id":"iterator-refreshed-call","kind":"output","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"text":"12\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"native-cache-call-6","kind":"output","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"text":"6\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"native-cache-call-6","kind":"timings","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"id":"native-cache-call-6","kind":"complete","success":true`), true)
    testing.expect_value(t, strings.contains(output, `"native_cache_hit":true`), true)
    testing.expect_value(t, string(stderr), "")
}

@(test)
cli_repl_steps_over_and_out_of_nested_calls :: proc(t: ^testing.T) {
    dir, dir_err :=
        os.make_directory_temp(
            "",
            "kvist-repl-depth-step-*",
            context.allocator,
        )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    context_path, context_err :=
        os.join_path({dir, "context.kvist"}, context.allocator)
    testing.expect_value(t, context_err == nil, true)
    if context_err != nil {
        return
    }
    defer delete(context_path)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(
            context_path,
            "(package depth_step_test)\n",
        ) == nil,
        true,
    )

    requests_path, requests_err :=
        os.join_path({dir, "requests.jsonl"}, context.allocator)
    testing.expect_value(t, requests_err == nil, true)
    if requests_err != nil {
        return
    }
    defer delete(requests_path)
    requests :=
`{"id":"define","op":"eval","source":"(defn depth-leaf [x: int] -> int\n  (do\n    (discard (+ x 1))\n    (+ x 2)))\n(defn depth-middle [x: int] -> int\n  (do\n    (discard (depth-leaf x))\n    (+ x 10)))\n(defn depth-outer [x: int] -> int\n  (do\n    (kvist-intrinsic-breakpoint)\n    (discard (depth-middle x))\n    (+ x 100)))\n(defn condition-value [x: int] -> int\n  (do\n    (kvist-intrinsic-signal-condition nil nil :kvist/condition \"inspect x\" '{})\n    (+ x 1)))\n(defn repair-int [x: int] -> int\n  (do\n    (defvar value: int x)\n    (kvist-intrinsic-use-value-restart nil nil value \"replace value\")\n    value))\n(defn repair-bool [x: bool] -> bool\n  (do\n    (defvar value: bool x)\n    (kvist-intrinsic-use-value-restart nil nil value \"replace flag\")\n    value))\n(defn retry-region [] -> int\n  (do\n    (defvar attempts: int 0)\n    (kvist-intrinsic-restart-case\n      (do\n        (inc! attempts)\n        (kvist-intrinsic-signal-condition nil nil :kvist/condition \"retry region\" '{})\n        (inc! attempts)))\n    attempts))\n(defn repair-f32 [x: f32] -> f32\n  (do\n    (defvar value: f32 x)\n    (kvist-intrinsic-use-value-restart nil nil value \"replace f32\")\n    value))\n(defn repair-f64 [x: f64] -> f64\n  (do\n    (defvar value: f64 x)\n    (kvist-intrinsic-use-value-restart nil nil value \"replace f64\")\n    value))\n(defn repair-string [x: string] -> string\n  (do\n    (defvar value: string x)\n    (kvist-intrinsic-use-value-restart nil nil value \"replace string\")\n    value))\n(defn repair-string-length [x: string] -> int\n  (do\n    (defvar value: string x)\n    (kvist-intrinsic-use-value-restart nil nil value \"replace string with empty\")\n    (len value)))","source_path":"/virtual/depth-step.kvist"}
{"id":"call-over","op":"eval","source":"(depth-outer 5)"}
{"id":"over-to-call","op":"debug-step"}
{"id":"over-call","op":"debug-step-over"}
{"id":"over-frame","op":"debug-frame"}
{"id":"continue-over","op":"debug-continue"}
{"id":"call-out","op":"eval","source":"(depth-outer 5)"}
{"id":"out-to-call","op":"debug-step"}
{"id":"out-to-middle-entry","op":"debug-step"}
{"id":"out-to-middle-call","op":"debug-step"}
{"id":"out-to-leaf-entry","op":"debug-step"}
{"id":"out-leaf","op":"debug-step-out"}
{"id":"middle-frame","op":"debug-frame"}
{"id":"out-middle","op":"debug-step-out"}
{"id":"outer-frame","op":"debug-frame"}
{"id":"continue-out","op":"debug-continue"}
{"id":"trace-call","op":"eval","source":"(depth-middle 5)","trace":true,"trace_limit":100,"trace_values":true,"trace_value_limit":2}
{"id":"bounded-trace","op":"eval","source":"(depth-middle 5)","trace":true,"trace_limit":2}
{"id":"condition-call","op":"eval","source":"(condition-value 5)"}
{"id":"condition-frame","op":"debug-frame"}
{"id":"condition-restart","op":"debug-restart","name":"continue"}
{"id":"use-value-call","op":"eval","source":"(repair-int 5)"}
{"id":"invalid-use-value","op":"debug-restart","name":"use-value","source":"nope"}
{"id":"use-value-restart","op":"debug-restart","name":"use-value","source":"42"}
{"id":"continue-value-call","op":"eval","source":"(repair-int 7)"}
{"id":"continue-value-restart","op":"debug-restart","name":"continue"}
{"id":"bool-value-call","op":"eval","source":"(repair-bool false)"}
{"id":"bool-value-restart","op":"debug-restart","name":"use-value","source":"true"}
{"id":"retry-case-call","op":"eval","source":"(retry-region)"}
{"id":"retry-case-restart","op":"debug-restart","name":"retry"}
{"id":"retry-case-continue","op":"debug-restart","name":"continue"}
{"id":"skip-case-call","op":"eval","source":"(retry-region)"}
{"id":"skip-case-restart","op":"debug-restart","name":"skip"}
{"id":"f32-value-call","op":"eval","source":"(repair-f32 1.0)"}
{"id":"invalid-f32-value","op":"debug-restart","name":"use-value","source":"not-a-float"}
{"id":"f32-value-restart","op":"debug-restart","name":"use-value","source":"3.25"}
{"id":"f64-value-call","op":"eval","source":"(repair-f64 1.0)"}
{"id":"f64-value-restart","op":"debug-restart","name":"use-value","source":"2.5"}
{"id":"string-value-call","op":"eval","source":"(repair-string \"old\")"}
{"id":"string-value-restart","op":"debug-restart","name":"use-value","source":"hello restart"}
{"id":"empty-string-value-call","op":"eval","source":"(repair-string-length \"old\")"}
{"id":"empty-string-value-restart","op":"debug-restart","name":"use-value","source":""}
{"id":"live-define","op":"eval","source":"(defn live-helper [x: int] -> int (+ x 1))\n(defn live-pauser [] -> int (do (kvist-intrinsic-breakpoint) 77))\n(defn live-outer [] -> int (do (kvist-intrinsic-breakpoint) (live-helper 5)))"}
{"id":"live-outer-call","op":"eval","source":"(live-outer)"}
{"id":"live-probe-before","op":"debug-eval-native","source":"(live-helper 20)"}
{"id":"live-redefine","op":"debug-eval-native","source":"(defn live-helper [x: int] -> int (+ x 100))","no_print":true}
{"id":"live-probe-after","op":"debug-eval-native","source":"(live-helper 20)"}
{"id":"live-nested-pause","op":"debug-eval-native","source":"(live-pauser)"}
{"id":"continue-live-nested","op":"debug-continue"}
{"id":"continue-live-outer","op":"debug-continue"}
{"id":"live-outer-again","op":"eval","source":"(live-outer)"}
{"id":"continue-live-outer-again","op":"debug-continue"}
{"id":"live-helper-after","op":"eval","source":"(live-helper 5)"}
{"id":"live-bindings","op":"bindings"}
{"id":"live-generations","op":"generations"}
{"id":"typed-condition-define","op":"eval","source":"(defn typed-condition [x: int] -> int (do (kvist-intrinsic-signal-condition nil nil :validation/out-of-range \"typed condition\" '{}) (+ x 1)))"}
{"id":"typed-condition-call","op":"eval","source":"(typed-condition 7)"}
{"id":"typed-condition-probe","op":"debug-eval-native","source":"(live-helper 1)"}
{"id":"typed-condition-continue","op":"debug-restart","name":"continue"}
{"id":"abort-operation-define","op":"eval","source":"(defvar operation-cleanup: int 0)\n(defn mark-operation-cleanup [] (inc! operation-cleanup))\n(defn abortable-operation [] -> int (do (set! operation-cleanup 0) (defvar progress: int 0) (kvist-intrinsic-condition-operation (do (defer (mark-operation-cleanup)) (inc! progress) (kvist-intrinsic-signal-condition nil nil :operation/cancelled \"abort operation\" '{}) (inc! progress))) (+ progress operation-cleanup 10)))"}
{"id":"abort-operation-call","op":"eval","source":"(abortable-operation)"}
{"id":"abort-operation-restart","op":"debug-restart","name":"abort-operation"}
{"id":"close","op":"close"}
`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(requests_path, requests) == nil,
        true,
    )
    request_file, open_err := os.open(requests_path)
    testing.expect_value(t, open_err == nil, true)
    if open_err != nil {
        return
    }
    defer os.close(request_file)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)
    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {
                kvist_bin,
                "repl",
                context_path,
                "--protocol",
                "jsonl",
            },
            working_dir = repo_root,
            stdin = request_file,
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
    output := string(stdout)
    testing.expect_value(
        t,
        count_substring(
            output,
            `"id":"call-over","kind":"paused"`,
        ),
        3,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"over-call","kind":"stepping","success":true`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"invalid-f32-value","kind":"complete","success":false,"generation":12,"message":"use-value expects a valid f32 value"`,
        ) && strings.contains(
            output,
            `{"name":"use-value","label":"Replace the mutable local and continue","requires_value":true,"value_type":"f32"}`,
        ) && strings.contains(
            output,
            `"id":"f32-value-call","kind":"output","success":true,"generation":12,"stream":"stdout","text":"3.25\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"f64-value-call","kind":"output","success":true,"generation":13,"stream":"stdout","text":"2.5\n"`,
        ) && strings.contains(
            output,
            `"id":"string-value-call","kind":"output","success":true,"generation":14,"stream":"stdout","text":"hello restart\n"`,
        ) && strings.contains(
            output,
            `"id":"empty-string-value-call","kind":"output","success":true,"generation":15,"stream":"stdout","text":"0\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"retry-case-call","kind":"condition","success":true,"generation":10,"message":"retry region"`,
        ) && strings.contains(
            output,
            `{"name":"retry","label":"Retry the enclosing restart case","requires_value":false},{"name":"skip","label":"Skip the rest of the enclosing restart case","requires_value":false}`,
        ) && strings.contains(
            output,
            `"id":"retry-case-restart","kind":"restart-invoked","success":true,"generation":10`,
        ) && strings.contains(
            output,
            `"id":"retry-case-call","kind":"output","success":true,"generation":10,"stream":"stdout","text":"3\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"skip-case-restart","kind":"restart-invoked","success":true,"generation":11`,
        ) && strings.contains(
            output,
            `"id":"skip-case-call","kind":"output","success":true,"generation":11,"stream":"stdout","text":"1\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"over-frame","kind":"debug-frame","success":true`,
        ) && strings.contains(
            output,
            `"source_path":"/virtual/depth-step.kvist","line":13`,
        ),
        true,
    )
    testing.expect_value(
        t,
        count_substring(
            output,
            `"id":"call-out","kind":"paused"`,
        ),
        7,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"out-leaf","kind":"stepping","success":true`,
        ) && strings.contains(
            output,
            `"id":"middle-frame","kind":"debug-frame","success":true`,
        ) && strings.contains(
            output,
            `"source_path":"/virtual/depth-step.kvist","line":8`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"out-middle","kind":"stepping","success":true`,
        ) && strings.contains(
            output,
            `"id":"outer-frame","kind":"debug-frame","success":true`,
        ),
        true,
    )
    testing.expect_value(
        t,
        count_substring(output, `"stream":"stdout","text":"105\n"`),
        5,
    )
    testing.expect_value(
        t,
        count_substring(
            output,
            `"id":"trace-call","kind":"trace"`,
        ),
        6,
    )
    testing.expect_value(
        t,
        count_substring(output, `"elapsed_ns":`) >= 8,
        true,
    )
    testing.expect_value(
        t,
        count_substring(output, `"delta_ns":`),
        8,
    )
    testing.expect_value(
        t,
        !strings.contains(output, `"elapsed_ns":-`) &&
        !strings.contains(output, `"delta_ns":-`),
        true,
    )
    testing.expect_value(
        t,
        count_substring(output, `"kind":"trace-summary"`),
        2,
    )
    testing.expect_value(
        t,
        count_substring(
            output,
            `"id":"trace-call","kind":"trace-values"`,
        ),
        2,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"trace_values":[{"name":"x","type":"int","mutable":false,"ownership":"borrowed","value":"5"}]`,
        ) && strings.contains(
            output,
            `"id":"trace-call","kind":"trace-values-limit","success":true`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"trace-call","kind":"trace-summary","success":true,"generation":4`,
        ) && strings.contains(
            output,
            `"trace_points":6,"trace_total_ns":`,
        ) && strings.contains(
            output,
            `"trace_unattributed_ns":`,
        ) && strings.contains(
            output,
            `"hotspots":[`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"bounded-trace","kind":"trace-summary","success":true,"generation":5`,
        ) && strings.contains(
            output,
            `"trace_points":2,"trace_total_ns":`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"trace-call","kind":"trace","success":true,"generation":4`,
        ) && strings.contains(
            output,
            `"source_path":"/virtual/depth-step.kvist","line":2`,
        ) && strings.contains(
            output,
            `"depth":2`,
        ),
        true,
    )
    testing.expect_value(
        t,
        count_substring(
            output,
            `"id":"bounded-trace","kind":"trace"`,
        ),
        2,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"bounded-trace","kind":"trace-limit","success":true`,
        ),
        true,
    )
    testing.expect_value(
        t,
        count_substring(output, `"stream":"stdout","text":"15\n"`),
        2,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"condition-call","kind":"condition","success":true,"generation":6,"message":"inspect x"`,
        ) && strings.contains(
            output,
            `"condition_type":"kvist/condition","condition_data":"{}","restarts":[{"name":"continue","label":"Continue from this safe point","requires_value":false}]`,
        ) && strings.contains(
            output,
            `"locals":[{"name":"x","type":"int","mutable":false,"ownership":"borrowed","value":"5"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"condition-frame","kind":"debug-frame","success":true,"generation":6`,
        ) && strings.contains(
            output,
            `"id":"condition-restart","kind":"restart-invoked","success":true,"generation":6`,
        ) && strings.contains(
            output,
            `"restart":"continue"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"use-value-call","kind":"condition","success":true,"generation":7,"message":"replace value"`,
        ) && strings.contains(
            output,
            `{"name":"use-value","label":"Replace the mutable local and continue","requires_value":true,"value_type":"int"}`,
        ) && strings.contains(
            output,
            `"name":"value","type":"int","mutable":true,"ownership":"value","value":"5"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"invalid-use-value","kind":"complete","success":false,"generation":7,"message":"use-value expects a valid int value"`,
        ) && strings.contains(
            output,
            `"id":"use-value-restart","kind":"restart-invoked","success":true,"generation":7`,
        ) && strings.contains(
            output,
            `"id":"use-value-call","kind":"output","success":true,"generation":7,"stream":"stdout","text":"42\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"continue-value-call","kind":"output","success":true,"generation":8,"stream":"stdout","text":"7\n"`,
        ) && strings.contains(
            output,
            `"id":"bool-value-call","kind":"output","success":true,"generation":9,"stream":"stdout","text":"true\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"condition-call","kind":"output","success":true,"generation":6,"stream":"stdout","text":"6\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"live-outer-call","kind":"paused","success":true,"generation":17`,
        ) && strings.contains(
            output,
            `"id":"live-probe-before","kind":"output","success":true,"generation":18,"stream":"stdout","text":"21\n"`,
        ) && strings.contains(
            output,
            `"id":"live-redefine","kind":"complete","success":true,"generation":19`,
        ) && strings.contains(
            output,
            `"id":"live-probe-after","kind":"output","success":true,"generation":20,"stream":"stdout","text":"120\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"live-nested-pause","kind":"paused","success":true,"generation":21`,
        ) && strings.contains(
            output,
            `"id":"continue-live-nested","kind":"resumed","success":true,"generation":21`,
        ) && strings.contains(
            output,
            `"id":"live-nested-pause","kind":"output","success":true,"generation":21,"stream":"stdout","text":"77\n"`,
        ) && count_substring(
            output,
            `"id":"live-outer-call","kind":"paused","success":true,"generation":17`,
        ) == 5,
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"continue-live-outer","kind":"resumed","success":true,"generation":17`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"live-outer-call","kind":"output","success":true,"generation":17,"stream":"stdout","text":"105\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"name":"live-helper","kind":"defn","version":2,"generation":19`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"live-outer-again","kind":"output","success":true,"generation":22,"stream":"stdout","text":"105\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"live-helper-after","kind":"output","success":true,"generation":23,"stream":"stdout","text":"105\n"`,
        ) && strings.contains(
            output,
            `"id":"live-generations","kind":"generations","success":true,"generation":23`,
        ),
        true,
    )
    testing.expect_value(
        t,
        count_substring(
            output,
            `"id":"typed-condition-call","kind":"condition","success":true,"generation":25,"message":"typed condition"`,
        ),
        2,
    )
    testing.expect_value(
        t,
        count_substring(
            output,
            `"condition_type":"validation/out-of-range"`,
        ) >= 2,
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"typed-condition-probe","kind":"output","success":true,"generation":26,"stream":"stdout","text":"101\n"`,
        ) && strings.contains(
            output,
            `"id":"typed-condition-continue","kind":"restart-invoked","success":true,"generation":25`,
        ) && strings.contains(
            output,
            `"id":"typed-condition-call","kind":"output","success":true,"generation":25,"stream":"stdout","text":"8\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"abort-operation-call","kind":"condition","success":true,"generation":28,"message":"abort operation"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"condition_type":"operation/cancelled","condition_data":"{}","restarts":[{"name":"continue","label":"Continue from this safe point","requires_value":false},{"name":"abort-operation","label":"Abort the enclosing debug operation","requires_value":false}]`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"abort-operation-restart","kind":"restart-invoked","success":true,"generation":28`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"abort-operation-call","kind":"output","success":true,"generation":28,"stream":"stdout","text":"12\n"`,
        ),
        true,
    )
    testing.expect_value(t, string(stderr), "")
}

@(test)
cli_repl_pages_into_collections_beyond_eager_frame_window :: proc(
    t: ^testing.T,
) {
    dir, dir_err :=
        os.make_directory_temp(
            "",
            "kvist-repl-deep-page-*",
            context.allocator,
        )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil {
        return
    }
    defer os.remove_all(dir)
    defer delete(dir)

    context_path, context_err :=
        os.join_path({dir, "context.kvist"}, context.allocator)
    testing.expect_value(t, context_err == nil, true)
    if context_err != nil {
        return
    }
    defer delete(context_path)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(
            context_path,
            "(package deep_page_test)\n",
        ) == nil,
        true,
    )

    requests_path, requests_err :=
        os.join_path({dir, "requests.jsonl"}, context.allocator)
    testing.expect_value(t, requests_err == nil, true)
    if requests_err != nil {
        return
    }
    defer delete(requests_path)
    requests := strings.builder_make()
    defer strings.builder_destroy(&requests)
    strings.write_string(
        &requests,
        "{\"id\":\"def\",\"op\":\"eval\",\"source\":\"(defstruct DeepItem [id: int events: [dynamic]int labels: map[string]int]) (defn pause-deep [items: [dynamic]DeepItem] -> int (do (kvist-intrinsic-breakpoint) items[0].id)) (defn pause-deep-map [mapped: map[string]DeepItem] -> int (do (kvist-intrinsic-breakpoint) mapped[\\\"k00\\\"].id))\"}\n",
    )
    strings.write_string(
        &requests,
        "{\"id\":\"call\",\"op\":\"eval\",\"source\":\"(pause-deep ([dynamic]DeepItem [",
    )
    for i in 0..<24 {
        fmt.sbprintf(
            &requests,
            "(DeepItem :id %d :events ([dynamic]int [%d %d]) :labels (map[string]int %c\\\"a\\\" %d \\\"z\\\" %d%c)) ",
            i,
            i,
            i+100,
            '{',
            i,
            i+300,
            '}',
        )
    }
    strings.write_string(&requests, "]))\"}\n")
    strings.write_string(
        &requests,
        "{\"id\":\"parent\",\"op\":\"debug-page\",\"source\":\"items\",\"offset\":23,\"limit\":1}\n",
    )
    strings.write_string(
        &requests,
        "{\"id\":\"child\",\"op\":\"debug-page\",\"source\":\"items[23].events\",\"offset\":0,\"limit\":2}\n",
    )
    strings.write_string(
        &requests,
        "{\"id\":\"array-map-child\",\"op\":\"debug-page\",\"source\":\"items[23].labels\",\"offset\":0,\"limit\":2}\n",
    )
    strings.write_string(
        &requests,
        "{\"id\":\"frame\",\"op\":\"debug-frame\"}\n",
    )
    strings.write_string(
        &requests,
        "{\"id\":\"continue\",\"op\":\"debug-continue\"}\n",
    )
    strings.write_string(
        &requests,
        "{\"id\":\"map-call\",\"op\":\"eval\",\"source\":\"(pause-deep-map (map[string]DeepItem {",
    )
    for i in 0..<24 {
        fmt.sbprintf(
            &requests,
            "\\\"k%02d\\\" (DeepItem :id %d :events ([dynamic]int [%d %d]) :labels (map[string]int %c\\\"a\\\" %d \\\"z\\\" %d%c)) ",
            i,
            i,
            i,
            i+200,
            '{',
            i,
            i+400,
            '}',
        )
    }
    strings.write_string(&requests, "}))\"}\n")
    strings.write_string(
        &requests,
        "{\"id\":\"map-parent\",\"op\":\"debug-page\",\"source\":\"mapped\",\"offset\":23,\"limit\":1}\n",
    )
    strings.write_string(
        &requests,
        "{\"id\":\"map-child\",\"op\":\"debug-page\",\"source\":\"mapped[\\\"k23\\\"].events\",\"offset\":0,\"limit\":2}\n",
    )
    strings.write_string(
        &requests,
        "{\"id\":\"map-map-child\",\"op\":\"debug-page\",\"source\":\"mapped[\\\"k23\\\"].labels\",\"offset\":0,\"limit\":2}\n",
    )
    strings.write_string(
        &requests,
        "{\"id\":\"map-continue\",\"op\":\"debug-continue\"}\n",
    )
    strings.write_string(&requests, "{\"id\":\"close\",\"op\":\"close\"}\n")
    testing.expect_value(
        t,
        os.write_entire_file_from_string(
            requests_path,
            strings.to_string(requests),
        ) == nil,
        true,
    )
    request_file, open_err := os.open(requests_path)
    testing.expect_value(t, open_err == nil, true)
    if open_err != nil {
        return
    }
    defer os.close(request_file)

    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok {
        return
    }
    defer delete(kvist_bin)
    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {
                kvist_bin,
                "repl",
                context_path,
                "--protocol",
                "jsonl",
            },
            working_dir = repo_root,
            stdin = request_file,
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
    output := string(stdout)
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"parent","kind":"debug-page","success":true`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"path":"items[23].events","shape":"dynamic-array","element_type":"int"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"path":"items[23].labels","shape":"map","key_type":"string","value_type":"int"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"child","kind":"debug-page","success":true`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"array-map-child","kind":"debug-page","success":true`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"entries":[{"index":0,"value":"23"},{"index":1,"value":"123"}]`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"path":"items[23].events","shape":"dynamic-array","element_type":"int"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"map-parent","kind":"debug-page","success":true`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"path":"mapped[\"k23\"].events","shape":"dynamic-array","element_type":"int"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"path":"mapped[\"k23\"].labels","shape":"map","key_type":"string","value_type":"int"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"map-child","kind":"debug-page","success":true`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"map-map-child","kind":"debug-page","success":true`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"entries":[{"index":0,"value":"23"},{"index":1,"value":"223"}]`,
        ),
        true,
    )
    testing.expect_value(t, string(stderr), "")
}

@(test)
repl_session_state_checkpoints :: proc(t: ^testing.T) {
    dir, dir_err :=
        os.make_directory_temp(
            "",
            "kvist-repl-checkpoints-*",
            context.allocator,
        )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil do return
    defer os.remove_all(dir)
    defer delete(dir)

    context_path, context_err := os.join_path({dir, "context.kvist"}, context.allocator)
    testing.expect_value(t, context_err == nil, true)
    if context_err != nil do return
    defer delete(context_path)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(context_path, "(package checkpoint_test)\n") == nil,
        true,
    )
    requests_path, requests_err := os.join_path({dir, "requests.jsonl"}, context.allocator)
    testing.expect_value(t, requests_err == nil, true)
    if requests_err != nil do return
    defer delete(requests_path)
    requests :=
`{"id":"define","op":"eval","source":"(defvar counter: int 1)\n(defvar label: string \"before\")\n(defvar nums: [dynamic]int ([dynamic]int [1 2]))","no_print":true}
{"id":"runtime-before-save","op":"runtime-allocations"}
{"id":"physical-after-define","op":"physical-allocations"}
{"id":"save","op":"checkpoint","name":"baseline"}
{"id":"runtime-after-save","op":"runtime-allocations"}
{"id":"inventory","op":"checkpoints"}
{"id":"mutate","op":"eval","source":"(do (set! counter 9) (set! label \"after\") (set! nums[0] 42))","no_print":true}
{"id":"restore","op":"checkpoint-restore","name":"baseline"}
{"id":"probe","op":"eval","source":"(do (println counter) (println label) (println nums[0]))","no_print":true}
{"id":"retype","op":"eval","source":"(defvar counter: f64 2.5)","no_print":true}
{"id":"reject","op":"checkpoint-restore","name":"baseline"}
{"id":"probe-after-reject","op":"eval","source":"(do (println counter) (println label) (println nums[0]))","no_print":true}
{"id":"drop","op":"checkpoint-drop","name":"baseline"}
{"id":"runtime-after-drop","op":"runtime-allocations"}
{"id":"inventory-empty","op":"checkpoints"}
{"id":"missing","op":"checkpoint-restore","name":"baseline"}
{"id":"managed-result","op":"eval","source":"([dynamic]int [7 8])","no_print":true}
{"id":"physical-after-result","op":"physical-allocations"}
{"id":"nested-managed-result","op":"eval","source":"(defstruct ManagedBox [label: string values: [dynamic]int])\n(ManagedBox :label \"nested\" :values ([dynamic]int [4 5]))","no_print":true}
{"id":"physical-after-nested","op":"physical-allocations"}
{"id":"nested-managed-array-result","op":"eval","source":"([dynamic]ManagedBox [(ManagedBox :label \"inside\" :values ([dynamic]int [8 9]))])","no_print":true}
{"id":"physical-after-nested-array","op":"physical-allocations"}
{"id":"shared-data-result","op":"eval","source":"(let [answer 1] (quasiquote {:answer (unquote answer) :label \"shared\"}))","no_print":true}
{"id":"physical-after-data","op":"physical-allocations"}
{"id":"managed-map-result","op":"eval","source":"(map[string]Data {\"value\" (let [answer 3] (quasiquote {:answer (unquote answer)}))})","no_print":true}
{"id":"physical-after-map","op":"physical-allocations"}
{"id":"managed-bindings","op":"eval","source":"(def bound-data: Data (let [answer 11] (quasiquote {:answer (unquote answer)})))\n(def bound-map: map[string]int (map[string]int {\"value\" 11}))","no_print":true}
{"id":"physical-after-bindings","op":"physical-allocations"}
{"id":"redefine-managed-binding","op":"eval","source":"(def bound-map: map[string]int (map[string]int {\"value\" 12}))","no_print":true}
{"id":"physical-after-binding-redefinition","op":"physical-allocations"}
{"id":"close","op":"close"}
`
    testing.expect_value(
        t,
        os.write_entire_file_from_string(requests_path, requests) == nil,
        true,
    )
    request_file, open_err := os.open(requests_path)
    testing.expect_value(t, open_err == nil, true)
    if open_err != nil do return
    defer os.close(request_file)
    repo_root := compiler_test_repo_root()
    kvist_bin, bin_ok := build_test_kvist_binary(t, repo_root, dir)
    if !bin_ok do return
    defer delete(kvist_bin)
    state, stdout, stderr, exec_err := os.process_exec(
        os.Process_Desc{
            command = {kvist_bin, "repl", context_path, "--protocol", "jsonl"},
            working_dir = repo_root,
            stdin = request_file,
        },
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)
    testing.expect_value(t, exec_err == nil, true)
    if exec_err != nil do return
    testing.expect_value(t, state.exited && state.exit_code == 0, true)
    output := string(stdout)
    testing.expect_value(t, strings.contains(output, `"id":"runtime-before-save","kind":"runtime-allocations","success":true,"generation":1,"attached":false,"reload_requested":false,"runtime_live_allocations":0,"runtime_live_bytes":0,"runtime_total_allocations":0,"runtime_total_allocated_bytes":0,"runtime_total_frees":0,"runtime_total_freed_bytes":0,"managed_live_allocations":1,"managed_live_bytes":16,"managed_peak_bytes":16,"managed_total_allocations":1,"managed_total_allocated_bytes":16,"managed_total_frees":0,"managed_total_freed_bytes":0`), true)
    testing.expect_value(t, strings.contains(output, `"id":"physical-after-define","kind":"physical-allocations","success":true,"generation":1,"attached":false,"reload_requested":false,"physical_allocations":[{"allocation_id":"managed:1","owner_id":"binding:nums:g1","kind":"managed","size":16,"alignment":8,"generation":1,"retained_owner_chain":["binding:nums:g1"]}],"physical_allocation_count":1`), true)
    testing.expect_value(t, strings.contains(output, `"owner_from":"generation:1","owner_to":"binding:nums:g1","generation":1,"action":"transferred","reason":"exclusive binding allocation transferred"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"save","kind":"checkpoint-saved","success":true,"generation":1,"checkpoint":"baseline","checkpoint_bindings":3`), true)
    testing.expect_value(t, strings.contains(output, `"id":"runtime-after-save","kind":"runtime-allocations","success":true,"generation":1,"attached":false,"reload_requested":false,"runtime_live_allocations":3,"runtime_live_bytes":64,"runtime_total_allocations":3,"runtime_total_allocated_bytes":64,"runtime_total_frees":0,"runtime_total_freed_bytes":0`), true)
    testing.expect_value(t, strings.contains(output, `"id":"inventory","kind":"checkpoints","success":true,"generation":1,"checkpoints":[{"name":"baseline","bindings":3}]`), true)
    testing.expect_value(t, strings.contains(output, `"id":"restore","kind":"checkpoint-restored","success":true,"generation":2,"checkpoint":"baseline","checkpoint_bindings":3`), true)
    testing.expect_value(t, count_substring(output, `"id":"probe","kind":"stream-output","success":true,"generation":3,"stream":"stdout"`) == 3, true)
    testing.expect_value(t, strings.contains(output, `"id":"probe","kind":"stream-output","success":true,"generation":3,"stream":"stdout","text":"before\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"reject","kind":"checkpoint-restored","success":false,"generation":4,"message":"checkpoint binding \"counter\" changed type or layout"`), true)
    testing.expect_value(t, count_substring(output, `"id":"probe-after-reject","kind":"stream-output","success":true,"generation":5,"stream":"stdout"`) == 3, true)
    testing.expect_value(t, strings.contains(output, `"id":"probe-after-reject","kind":"stream-output","success":true,"generation":5,"stream":"stdout","text":"2.5\n"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"drop","kind":"checkpoint-dropped","success":true,"generation":5,"checkpoint":"baseline"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"runtime-after-drop","kind":"runtime-allocations","success":true,"generation":5,"attached":false,"reload_requested":false,"runtime_live_allocations":0,"runtime_live_bytes":0,"runtime_total_allocations":3,"runtime_total_allocated_bytes":64,"runtime_total_frees":3,"runtime_total_freed_bytes":64,"managed_live_allocations":1,"managed_live_bytes":16,"managed_peak_bytes":24,"managed_total_allocations":7,"managed_total_allocated_bytes":64,"managed_total_frees":6,"managed_total_freed_bytes":48`), true)
    testing.expect_value(t, strings.contains(output, `"id":"inventory-empty","kind":"checkpoints","success":true,"generation":5`), true)
    testing.expect_value(t, strings.contains(output, `"id":"missing","kind":"checkpoint-restored","success":false,"generation":5,"message":"unknown checkpoint \"baseline\""`), true)
    testing.expect_value(t, strings.contains(output, `"id":"physical-after-result","kind":"physical-allocations","success":true,"generation":6`), true)
    testing.expect_value(t, strings.contains(output, `"owner_id":"result:g6","kind":"managed","size":16,"alignment":8,"generation":6,"retained_owner_chain":["result:g6"]`), true)
    testing.expect_value(t, strings.contains(output, `"owner_from":"generation:6","owner_to":"result:g6","generation":6,"action":"transferred","reason":"exclusive result allocation transferred"`), true)
    testing.expect_value(t, strings.contains(output, `"physical_transfer_count":1`), true)
    testing.expect_value(t, strings.contains(output, `"id":"physical-after-nested","kind":"physical-allocations","success":true,"generation":7`), true)
    testing.expect_value(t, strings.contains(output, `"owner_from":"generation:7","owner_to":"result:g7","generation":7,"action":"transferred","reason":"exclusive result allocation transferred"`), true)
    testing.expect_value(t, strings.contains(output, `"physical_transfer_count":4`), true)
    testing.expect_value(t, strings.contains(output, `"id":"physical-after-nested-array","kind":"physical-allocations","success":true,"generation":8`), true)
    testing.expect_value(t, strings.contains(output, `"owner_from":"generation:8","owner_to":"result:g8","generation":8,"action":"transferred","reason":"exclusive result allocation transferred"`), true)
    testing.expect_value(t, strings.contains(output, `"physical_transfer_count":7`), true)
    testing.expect_value(t, strings.contains(output, `"id":"physical-after-data","kind":"physical-allocations","success":true,"generation":9`), true)
    testing.expect_value(t, strings.contains(output, `"retained_owner_chain":["generation:9","result:g9"]`), true)
    testing.expect_value(t, strings.contains(output, `"owner_from":"generation:9","owner_to":"result:g9","generation":9,"action":"retained","reason":"shared Data result retained"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"physical-after-map","kind":"physical-allocations","success":true,"generation":10`), true)
    testing.expect_value(t, strings.contains(output, `"owner_id":"result:g10","kind":"managed"`), true)
    testing.expect_value(t, strings.contains(output, `"owner_from":"generation:10","owner_to":"result:g10","generation":10,"action":"transferred","reason":"exclusive result allocation transferred"`), true)
    testing.expect_value(t, strings.contains(output, `"owner_from":"generation:10","owner_to":"result:g10","generation":10,"action":"retained","reason":"shared Data result retained"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"physical-after-bindings","kind":"physical-allocations","success":true,"generation":11`), true)
    testing.expect_value(t, strings.contains(output, `"owner_id":"binding:bound_map:g11","kind":"managed"`), true)
    testing.expect_value(t, strings.contains(output, `"owner_from":"generation:11","owner_to":"binding:bound_map:g11","generation":11,"action":"transferred","reason":"exclusive binding allocation transferred"`), true)
    testing.expect_value(t, strings.contains(output, `"retained_owner_chain":["generation:11","binding:bound_data:g11"]`), true)
    testing.expect_value(t, strings.contains(output, `"owner_from":"generation:11","owner_to":"binding:bound_data:g11","generation":11,"action":"retained","reason":"shared binding allocation retained"`), true)
    testing.expect_value(t, strings.contains(output, `"id":"physical-after-binding-redefinition","kind":"physical-allocations","success":true,"generation":12`), true)
    testing.expect_value(t, strings.contains(output, `"owner_id":"binding:bound_map:g11","kind":"managed"`), true)
    testing.expect_value(t, strings.contains(output, `"owner_id":"binding:bound_map:g12","kind":"managed"`), true)
    testing.expect_value(t, strings.contains(output, `"owner_from":"generation:12","owner_to":"binding:bound_map:g12","generation":12,"action":"transferred","reason":"exclusive binding allocation transferred"`), true)
}

@(test)
olive_attached_console_hardens_mailbox_identity :: proc(t: ^testing.T) {
    endpoint, endpoint_err :=
        os.make_directory_temp(
            "",
            "kvist-attached-hardening-*",
            context.allocator,
        )
    testing.expect_value(t, endpoint_err == nil, true)
    if endpoint_err != nil do return
    defer os.remove_all(endpoint)
    defer delete(endpoint)

    stale_request, _ :=
        os.join_path({endpoint, "request-stale.json"}, context.allocator)
    stale_response, _ :=
        os.join_path({endpoint, "response-stale.json"}, context.allocator)
    stale_temp, _ :=
        os.join_path({endpoint, ".request-stale.tmp"}, context.allocator)
    unrelated, _ :=
        os.join_path({endpoint, "keep.txt"}, context.allocator)
    defer delete(stale_request)
    defer delete(stale_response)
    defer delete(stale_temp)
    defer delete(unrelated)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(stale_request, "{}") == nil &&
        os.write_entire_file_from_string(stale_response, "{}") == nil &&
        os.write_entire_file_from_string(stale_temp, "{}") == nil &&
        os.write_entire_file_from_string(unrelated, "keep") == nil,
        true,
    )

    session := olive_reload.Session{generation = 1}
    host := olive_reload.Run_Host{session = rawptr(&session)}
    defer olive_reload.console_host_delete(&host)
    testing.expect_value(
        t,
        olive_reload.console_enable(&host, endpoint),
        true,
    )
    testing.expect_value(
        t,
        !os.exists(stale_request) &&
        !os.exists(stale_response) &&
        !os.exists(stale_temp) &&
        os.exists(unrelated),
        true,
    )

    invalid_response, invalid_message, invalid_ok :=
        olive_reload.console_submit(
            endpoint,
            olive_reload.Console_Request{
                protocol_version =
                    olive_reload.CONSOLE_PROTOCOL_VERSION,
                id = "../escape",
                op = "handshake",
            },
            time.Millisecond,
        )
    testing.expect_value(t, invalid_ok, false)
    testing.expect_value(t, invalid_message, "invalid attached console request")
    olive_reload.console_response_delete(&invalid_response)
    delete(invalid_message)

    mismatched_request, _ :=
        os.join_path({endpoint, "request-safe.json"}, context.allocator)
    mismatched_response, _ :=
        os.join_path({endpoint, "response-other.json"}, context.allocator)
    defer delete(mismatched_request)
    defer delete(mismatched_response)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(
            mismatched_request,
            `{"protocol_version":1,"id":"other","op":"reload"}`,
        ) == nil,
        true,
    )
    testing.expect_value(t, olive_reload.console_poll(&host), 0)
    testing.expect_value(
        t,
        !host.console_reload_requested &&
        !os.exists(mismatched_request) &&
        !os.exists(mismatched_response),
        true,
    )

    collision_response, _ :=
        os.join_path(
            {endpoint, "response-collision.json"},
            context.allocator,
        )
    collision_request, _ :=
        os.join_path(
            {endpoint, "request-collision.json"},
            context.allocator,
        )
    defer delete(collision_response)
    defer delete(collision_request)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(collision_response, "{}") == nil,
        true,
    )
    testing.expect_value(
        t,
        olive_reload.console_enable(&host, endpoint),
        true,
    )
    testing.expect_value(t, os.exists(collision_response), true)
    collision, collision_message, collision_ok :=
        olive_reload.console_submit(
            endpoint,
            olive_reload.Console_Request{
                protocol_version =
                    olive_reload.CONSOLE_PROTOCOL_VERSION,
                id = "collision",
                op = "handshake",
            },
            time.Millisecond,
        )
    testing.expect_value(t, collision_ok, false)
    testing.expect_value(
        t,
        collision_message,
        "attached console request id is already in use",
    )
    testing.expect_value(t, os.exists(collision_request), false)
    olive_reload.console_response_delete(&collision)
    delete(collision_message)
}

@(test)
olive_attached_console_schedules_typed_capabilities :: proc(t: ^testing.T) {
    endpoint, endpoint_err :=
        os.make_directory_temp(
            "",
            "kvist-attached-console-*",
            context.allocator,
        )
    testing.expect_value(t, endpoint_err == nil, true)
    if endpoint_err != nil do return
    defer os.remove_all(endpoint)
    defer delete(endpoint)

    session := olive_reload.Session{generation = 7}
    calls := 0
    host := olive_reload.Run_Host{
        session = rawptr(&session),
    }
    defer olive_reload.console_host_delete(&host)
    testing.expect_value(
        t,
        olive_reload.console_enable(&host, endpoint),
        true,
    )
    registered := olive_reload.console_register_capability(
        &host,
        "app/echo",
        "proc(string)->string",
        rawptr(&calls),
        console_test_handler,
    )
    testing.expect_value(t, registered, true)

    handshake := Console_Test_Client{
        endpoint = endpoint,
        request = olive_reload.Console_Request{
            protocol_version = olive_reload.CONSOLE_PROTOCOL_VERSION,
            id = "handshake-1",
            op = "handshake",
        },
        allocator = context.allocator,
    }
    handshake_thread :=
        thread.create_and_start_with_data(
            rawptr(&handshake),
            console_test_submit,
        )
    for _ in 0..<200 {
        if olive_reload.console_poll(&host) > 0 do break
        time.sleep(5 * time.Millisecond)
    }
    thread.join(handshake_thread)
    thread.destroy(handshake_thread)
    testing.expect_value(t, handshake.ok, true)
    testing.expect_value(t, handshake.response.success, true)
    testing.expect_value(t, handshake.response.generation, 7)
    testing.expect_value(t, len(handshake.response.capabilities), 1)
    if len(handshake.response.capabilities) == 1 {
        testing.expect_value(
            t,
            handshake.response.capabilities[0].name,
            "app/echo",
        )
        testing.expect_value(
            t,
            handshake.response.capabilities[0].signature,
            "proc(string)->string",
        )
    }
    olive_reload.console_response_delete(&handshake.response)
    if handshake.message != "" do delete(handshake.message)

    invoke := Console_Test_Client{
        endpoint = endpoint,
        request = olive_reload.Console_Request{
            protocol_version = olive_reload.CONSOLE_PROTOCOL_VERSION,
            id = "invoke-1",
            op = "invoke",
            name = "app/echo",
            signature = "proc(string)->string",
            input = "hello",
        },
        allocator = context.allocator,
    }
    invoke_thread :=
        thread.create_and_start_with_data(
            rawptr(&invoke),
            console_test_submit,
        )
    for _ in 0..<200 {
        if olive_reload.console_poll(&host) > 0 do break
        time.sleep(5 * time.Millisecond)
    }
    thread.join(invoke_thread)
    thread.destroy(invoke_thread)
    testing.expect_value(t, invoke.ok && invoke.response.success, true)
    testing.expect_value(t, invoke.response.output, "host:hello")
    testing.expect_value(t, calls, 1)
    olive_reload.console_response_delete(&invoke.response)
    if invoke.message != "" do delete(invoke.message)
}

@(test)
cli_repl_attach_proxies_olive_capabilities :: proc(t: ^testing.T) {
    dir, dir_err :=
        os.make_directory_temp(
            "",
            "kvist-cli-attach-*",
            context.allocator,
        )
    testing.expect_value(t, dir_err == nil, true)
    if dir_err != nil do return
    defer os.remove_all(dir)
    defer delete(dir)
    endpoint, endpoint_err :=
        os.join_path({dir, "endpoint"}, context.allocator)
    testing.expect_value(t, endpoint_err == nil, true)
    if endpoint_err != nil do return
    defer delete(endpoint)
    testing.expect_value(t, os.make_directory_all(endpoint) == nil, true)

    context_path, context_err :=
        os.join_path({dir, "context.kvist"}, context.allocator)
    testing.expect_value(t, context_err == nil, true)
    if context_err != nil do return
    defer delete(context_path)
    testing.expect_value(
        t,
        os.write_entire_file_from_string(
            context_path,
            "(package attached_eval_test)\n",
        ) == nil,
        true,
    )

    requests_path, requests_err :=
        os.join_path({dir, "requests.jsonl"}, context.allocator)
    testing.expect_value(t, requests_err == nil, true)
    if requests_err != nil do return
    defer delete(requests_path)
    requests := strings.builder_make()
    defer strings.builder_destroy(&requests)
    strings.write_string(
        &requests,
`{"id":"session","op":"attached-session"}
{"id":"define","op":"eval","source":"(defn attached-add [x: int] -> int (+ x 2))\n(defn attached-output [x: int] -> int (do (println \"first\") (println x) (+ x 1)))\n(defn attached-paused [x: int] -> int (do (kvist-intrinsic-breakpoint) (+ x 3)))\n(defn attached-collection-pause [values: [dynamic]int scores: map[string]int] -> int (do (kvist-intrinsic-breakpoint) (+ values[0] scores[\"a\"])))\n(defn attached-repair [x: int] -> int (do (defvar value: int x) (kvist-intrinsic-use-value-restart nil nil value \"replace attached value\") value))\n(defn attached-condition [x: int] -> int (do (kvist-intrinsic-signal-condition nil nil :attached/invalid \"attached condition\" '{}) (+ x 1)))\n(defstruct AttachedPair [left: int right: string])\n(defn attached-traced [x: int] -> int (do (discard (+ x 1)) (+ x 2)))\n(defstruct AttachedDeepItem [id: int events: [dynamic]int labels: map[string]int])\n(defn attached-deep [items: [dynamic]AttachedDeepItem] -> int (do (kvist-intrinsic-breakpoint) items[0].id))\n(defn attached-deep-map [mapped: map[string]AttachedDeepItem] -> int (do (kvist-intrinsic-breakpoint) mapped[\"k00\"].id))\n(defvar attached-counter: int 10)","source_path":"/virtual/attached-defs.kvist","line":10,"column":1,"no_print":true}
{"id":"call","op":"eval","source":"(def attached-bound-map: map[string]int (map[string]int {\"value\" 3}))\n(def attached-bound-data: Data (let [answer 3] (quasiquote {:answer (unquote answer)})))\n(map[string]Data {\"value\" (let [answer 3] (quasiquote {:answer (unquote answer)}))})","no_print":true}
{"id":"result","op":"eval","source":"(attached-add 4)"}
{"id":"inspect-scalar","op":"inspect","source":"(attached-add 8)"}
{"id":"inspect-struct","op":"inspect","source":"(AttachedPair :left 1 :right \"two\")"}
{"id":"inspect-struct-cached","op":"inspect","handle":"inspection-2"}
{"id":"allocations-attached","op":"allocations"}
{"id":"ownership-history-attached","op":"ownership-history"}
{"id":"inspect-struct-field","op":"inspect","handle":"inspection-2","path":["left"]}
{"id":"inspect-array","op":"inspect","source":"([dynamic]int [4 5])"}
{"id":"inspect-array-index","op":"inspect","handle":"inspection-4","index":1}
{"id":"inspect-array-page","op":"inspect-page","handle":"inspection-4","offset":1,"limit":1}
{"id":"inspect-map","op":"inspect","source":"(map[string]int {\"a\" 1 \"b\" 2})"}
{"id":"inspect-map-key","op":"inspect","handle":"inspection-6","key_source":"\"b\""}
{"id":"inspect-map-page","op":"inspect-page","handle":"inspection-6","offset":1,"limit":1}
{"id":"paused-eval","op":"eval","source":"(attached-add 18)","source_path":"/virtual/attached.kvist","line":40,"column":3,"pause_before":true}
{"id":"paused-frame","op":"debug-frame","pause_id":"pause-13"}
{"id":"paused-continue","op":"debug-continue","pause_id":"pause-13"}
{"id":"nested-eval","op":"eval","source":"(attached-paused 7)","source_path":"/virtual/attached.kvist","line":50,"column":1}
{"id":"nested-frame","op":"debug-frame"}
{"id":"nested-step","op":"debug-step"}
{"id":"stepped-frame","op":"debug-frame"}
{"id":"nested-continue","op":"debug-continue"}
{"id":"collection-eval","op":"eval","source":"(attached-collection-pause ([dynamic]int [3 4]) (map[string]int {\"a\" 5 \"b\" 6}))","source_path":"/virtual/attached.kvist","line":60,"column":1}
{"id":"collection-frame","op":"debug-frame"}
{"id":"collection-array-page","op":"debug-page","source":"values","offset":0,"limit":2}
{"id":"collection-map-page","op":"debug-page","source":"scores","offset":0,"limit":2}
{"id":"collection-continue","op":"debug-continue"}
{"id":"repair-eval","op":"eval","source":"(attached-repair 5)"}
{"id":"repair-invalid","op":"debug-restart","name":"use-value","source":"nope"}
{"id":"repair-restart","op":"debug-restart","name":"use-value","source":"42"}
{"id":"condition-eval","op":"eval","source":"(attached-condition 9)"}
{"id":"condition-restart","op":"debug-restart","name":"continue"}
`,
    )
    strings.write_string(
        &requests,
        `{"id":"nested-page-eval","op":"eval","source":"(attached-deep ([dynamic]AttachedDeepItem [`,
    )
    for i in 0..<24 {
        fmt.sbprintf(
            &requests,
            "(AttachedDeepItem :id %d :events ([dynamic]int [%d %d]) :labels (map[string]int %c\\\"a\\\" %d \\\"z\\\" %d%c)) ",
            i,
            i,
            i+100,
            '{',
            i,
            i+300,
            '}',
        )
    }
    strings.write_string(
        &requests,
        `]))"}
{"id":"nested-parent-page","op":"debug-page","source":"items","offset":23,"limit":1}
{"id":"nested-child-page","op":"debug-page","source":"items[23].events","offset":0,"limit":2}
{"id":"nested-map-page","op":"debug-page","source":"items[23].labels","offset":0,"limit":2}
{"id":"nested-page-frame","op":"debug-frame"}
{"id":"nested-page-continue","op":"debug-continue"}
`,
    )
    strings.write_string(
        &requests,
        `{"id":"nested-map-eval","op":"eval","source":"(attached-deep-map (map[string]AttachedDeepItem {`,
    )
    for i in 0..<24 {
        fmt.sbprintf(
            &requests,
            "\\\"k%02d\\\" (AttachedDeepItem :id %d :events ([dynamic]int [%d %d]) :labels (map[string]int %c\\\"a\\\" %d \\\"z\\\" %d%c)) ",
            i,
            i,
            i,
            i+200,
            '{',
            i,
            i+400,
            '}',
        )
    }
    strings.write_string(
        &requests,
        `}))"}
{"id":"nested-map-parent","op":"debug-page","source":"mapped","offset":23,"limit":1}
{"id":"nested-map-child","op":"debug-page","source":"mapped[\"k23\"].events","offset":0,"limit":2}
{"id":"nested-map-map","op":"debug-page","source":"mapped[\"k23\"].labels","offset":0,"limit":2}
{"id":"nested-map-frame","op":"debug-frame"}
{"id":"nested-map-continue","op":"debug-continue"}
{"id":"trace-eval","op":"eval","source":"(attached-traced 4)","trace":true,"trace_limit":2,"trace_values":true,"trace_value_limit":1}
{"id":"runtime-before-checkpoint","op":"runtime-allocations"}
{"id":"physical-attached","op":"physical-allocations"}
{"id":"checkpoint-save","op":"checkpoint","name":"attached-baseline"}
{"id":"runtime-checkpoint-live","op":"runtime-allocations"}
{"id":"checkpoint-inventory","op":"checkpoints"}
{"id":"checkpoint-mutate","op":"eval","source":"(set! attached-counter 99)","no_print":true}
{"id":"checkpoint-restore","op":"checkpoint-restore","name":"attached-baseline"}
{"id":"checkpoint-probe","op":"eval","source":"attached-counter"}
{"id":"checkpoint-drop","op":"checkpoint-drop","name":"attached-baseline"}
{"id":"runtime-checkpoint-freed","op":"runtime-allocations"}
{"id":"checkpoint-empty","op":"checkpoints"}
{"id":"checkpoint-missing","op":"checkpoint-restore","name":"attached-baseline"}
{"id":"generations","op":"generations"}
{"id":"bindings","op":"bindings"}
{"id":"versions","op":"versions","name":"attached-add"}
{"id":"definition-location","op":"definition-location","name":"attached-add","version":1}
{"id":"results","op":"results"}
{"id":"output-order","op":"eval","source":"(attached-output 7)"}
{"id":"reset","op":"reset"}
{"id":"generations-reset","op":"generations"}
{"id":"checkpoints-reset","op":"checkpoints"}
{"id":"stale-call","op":"eval","source":"(attached-add 5)"}
{"id":"fresh-result","op":"eval","source":"(+ 1 1)"}
{"id":"invoke","op":"invoke-capability","name":"app/echo","abi":"proc(string)->string","source":"hello"}
{"id":"reload","op":"reload"}
{"id":"attached-timeout","op":"eval","source":"1","timeout_ms":50}
{"id":"attached-abort-definitions","op":"eval","source":"(defvar attached-abort-probe: int 0)\n(defvar attached-abort-cleanup: int 0)\n(defn attached-record-abort-cleanup [] (inc! attached-abort-cleanup))\n(defn attached-abort-inside [] -> int (do (defer (attached-record-abort-cleanup)) (set! attached-abort-probe 8) (kvist-intrinsic-breakpoint) (set! attached-abort-probe 9) 42))"}
{"id":"attached-abort-call","op":"eval","source":"(attached-abort-inside)"}
{"id":"attached-abort-control","op":"debug-abort"}
{"id":"attached-abort-state","op":"eval","source":"attached-abort-probe"}
{"id":"attached-abort-cleanup-state","op":"eval","source":"attached-abort-cleanup"}
{"id":"close","op":"close"}
`,
    )
    testing.expect_value(
        t,
        os.write_entire_file_from_string(
            requests_path,
            strings.to_string(requests),
        ) == nil,
        true,
    )
    request_file, open_err := os.open(requests_path)
    testing.expect_value(t, open_err == nil, true)
    if open_err != nil do return
    defer os.close(request_file)

    session := olive_reload.Session{generation = 7}
    calls := 0
    host := olive_reload.Run_Host{
        session = rawptr(&session),
    }
    defer olive_reload.console_host_delete(&host)
    testing.expect_value(
        t,
        olive_reload.console_enable(&host, endpoint),
        true,
    )
    testing.expect_value(
        t,
        olive_reload.console_register_capability(
            &host,
            "app/echo",
            "proc(string)->string",
            rawptr(&calls),
            console_test_handler,
        ),
        true,
    )
    repo_root := compiler_test_repo_root()
    binary, binary_ok := build_test_kvist_binary(t, repo_root, dir)
    if !binary_ok do return
    defer delete(binary)
    client := Console_Cli_Client{
        binary = binary,
        endpoint = endpoint,
        context_file = context_path,
        repo_root = repo_root,
        request_file = request_file,
        allocator = context.allocator,
    }
    client_thread :=
        thread.create_and_start_with_data(
            rawptr(&client),
            console_cli_run,
        )
    replacement_started := false
    // The client may issue many sequential attached requests. Keep polling
    // beyond the 30-second per-request console timeout under a slow CI load.
    for _ in 0..<12000 {
        _ = olive_reload.console_poll(&host)
        if host.console_reload_requested && !replacement_started {
            replacement_started = true
            host.console_reload_requested = false
            olive_reload.console_clear_capabilities(&host)
            session.generation = 8
            testing.expect_value(
                t,
                olive_reload.console_register_capability(
                    &host,
                    "app/echo",
                    "proc(string)->string",
                    rawptr(&calls),
                    console_test_handler,
                ),
                true,
            )
        }
        if thread.is_done(client_thread) do break
        time.sleep(5 * time.Millisecond)
    }
    thread.join(client_thread)
    thread.destroy(client_thread)
    defer delete(client.stdout)
    defer delete(client.stderr)
    testing.expect_value(t, client.exec_err == nil, true)
    testing.expect_value(t, string(client.stderr), "")
    testing.expect_value(
        t,
        client.state.exited && client.state.exit_code == 0,
        true,
    )
    output := string(client.stdout)
    output_first :=
        strings.index(
            output,
            `"id":"output-order","kind":"output","success":true,"generation":23,"stream":"stdout","text":"first\n"`,
        )
    output_value :=
        strings.index(
            output,
            `"id":"output-order","kind":"output","success":true,"generation":23,"stream":"stdout","text":"7\n"`,
        )
    output_result :=
        strings.index(
            output,
            `"id":"output-order","kind":"output","success":true,"generation":23,"stream":"stdout","text":"8\n"`,
        )
    testing.expect_value(
        t,
        output_first >= 0 &&
        output_first < output_value &&
        output_value < output_result,
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"retained_owner_chain":["generation:2","result:g2"]`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"owner_from":"generation:2","owner_to":"result:g2","generation":2,"action":"retained","reason":"shared Data result retained"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"owner_from":"generation:2","owner_to":"result:g2","generation":2,"action":"transferred","reason":"exclusive result allocation transferred"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"owner_from":"generation:2","owner_to":"binding:attached_bound_map:g2","generation":2,"action":"transferred","reason":"exclusive binding allocation transferred"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"owner_from":"generation:2","owner_to":"binding:attached_bound_data:g2","generation":2,"action":"retained","reason":"shared binding allocation retained"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"runtime-before-checkpoint","kind":"runtime-allocations","success":true,"generation":20,"attached":true,"reload_requested":false,"application_generation":7,"attached_generation":20,"runtime_live_allocations":0,"runtime_live_bytes":0,"runtime_total_allocations":0,"runtime_total_allocated_bytes":0,"runtime_total_frees":0,"runtime_total_freed_bytes":0`,
        ) && strings.contains(
            output,
            `"id":"physical-attached","kind":"physical-allocations","success":true,"generation":20`,
        ) && strings.contains(
            output,
            `"id":"checkpoint-save","kind":"checkpoint-saved","success":true,"generation":20,"checkpoint":"attached-baseline","checkpoint_bindings":1`,
        ) && strings.contains(
            output,
            `"id":"runtime-checkpoint-live","kind":"runtime-allocations","success":true,"generation":20,"attached":true,"reload_requested":false,"application_generation":7,"attached_generation":20,"runtime_live_allocations":1,"runtime_live_bytes":8,"runtime_total_allocations":1,"runtime_total_allocated_bytes":8,"runtime_total_frees":0,"runtime_total_freed_bytes":0`,
        ) && strings.contains(
            output,
            `"id":"checkpoint-inventory","kind":"checkpoints","success":true,"generation":20,"checkpoints":[{"name":"attached-baseline","bindings":1}]`,
        ) && strings.contains(
            output,
            `"id":"checkpoint-restore","kind":"checkpoint-restored","success":true,"generation":21,"checkpoint":"attached-baseline","checkpoint_bindings":1`,
        ) && strings.contains(
            output,
            `"id":"checkpoint-probe","kind":"output","success":true,"generation":22,"stream":"stdout","text":"10\n"`,
        ) && strings.contains(
            output,
            `"id":"checkpoint-drop","kind":"checkpoint-dropped","success":true,"generation":22,"checkpoint":"attached-baseline"`,
        ) && strings.contains(
            output,
            `"id":"runtime-checkpoint-freed","kind":"runtime-allocations","success":true,"generation":22,"attached":true,"reload_requested":false,"application_generation":7,"attached_generation":22,"runtime_live_allocations":0,"runtime_live_bytes":0,"runtime_total_allocations":1,"runtime_total_allocated_bytes":8,"runtime_total_frees":1,"runtime_total_freed_bytes":8`,
        ) && strings.contains(
            output,
            `"id":"checkpoint-empty","kind":"checkpoints","success":true,"generation":22`,
        ) && strings.contains(
            output,
            `"id":"checkpoint-missing","kind":"checkpoint-restored","success":false,"generation":22,"message":"unknown checkpoint \"attached-baseline\""`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"nested-map-parent","kind":"debug-page","success":true,"generation":19`,
        ) && strings.contains(
            output,
            `"path":"mapped[\"k23\"].events","shape":"dynamic-array","element_type":"int"`,
        ) && strings.contains(
            output,
            `"path":"mapped[\"k23\"].labels","shape":"map","key_type":"string","value_type":"int"`,
        ) && strings.contains(
            output,
            `"id":"nested-map-child","kind":"debug-page","success":true,"generation":19`,
        ) && strings.contains(
            output,
            `"entries":[{"index":0,"value":"23"},{"index":1,"value":"223"}]`,
        ) && strings.contains(
            output,
            `"id":"nested-map-map","kind":"debug-page","success":true,"generation":19`,
        ) && strings.contains(
            output,
            `"entries":[{"index":0,"key":"a","value":"23"},{"index":1,"key":"z","value":"423"}]`,
        ) && strings.contains(
            output,
            `"id":"nested-map-frame","kind":"debug-frame","success":true,"generation":19`,
        ) && strings.contains(
            output,
            `"id":"nested-map-continue","kind":"resumed","success":true,"generation":19`,
        ) && strings.contains(
            output,
            `"id":"nested-map-eval","kind":"output","success":true,"generation":19,"stream":"stdout","text":"0\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"nested-parent-page","kind":"debug-page","success":true,"generation":18`,
        ) && strings.contains(
            output,
            `"path":"items[23].events","shape":"dynamic-array","element_type":"int"`,
        ) && strings.contains(
            output,
            `"path":"items[23].labels","shape":"map","key_type":"string","value_type":"int"`,
        ) && strings.contains(
            output,
            `"id":"nested-child-page","kind":"debug-page","success":true,"generation":18`,
        ) && strings.contains(
            output,
            `"entries":[{"index":0,"value":"23"},{"index":1,"value":"123"}]`,
        ) && strings.contains(
            output,
            `"id":"nested-map-page","kind":"debug-page","success":true,"generation":18`,
        ) && strings.contains(
            output,
            `"entries":[{"index":0,"key":"a","value":"23"},{"index":1,"key":"z","value":"323"}]`,
        ) && strings.contains(
            output,
            `"id":"nested-page-frame","kind":"debug-frame","success":true,"generation":18`,
        ) && strings.contains(
            output,
            `"id":"nested-page-continue","kind":"resumed","success":true,"generation":18`,
        ) && strings.contains(
            output,
            `"id":"nested-page-eval","kind":"output","success":true,"generation":18,"stream":"stdout","text":"0\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"inspect-scalar","kind":"inspection","success":true,"generation":4,"text":"10\n","type":"int","abi":"value:int","handle":"inspection-1","shape":"scalar"`,
        ) && strings.contains(
            output,
            `"id":"inspect-struct","kind":"inspection","success":true,"generation":5`,
        ) && strings.contains(
            output,
            `"type":"AttachedPair","abi":"value:AttachedPair|layout:AttachedPair=struct{left:int;right:string;}","handle":"inspection-2","shape":"struct","members":[{"name":"left","type":"int"},{"name":"right","type":"string"}]`,
        ) && strings.contains(
            output,
            `"id":"inspect-struct-cached","kind":"inspection","success":true,"generation":5,"text":"AttachedPair{left = 1, right = \"two\"}\n"`,
        ) && strings.contains(
            output,
            `"id":"inspect-struct-cached","kind":"complete","success":true,"generation":5`,
        ) && strings.contains(
            output,
            `"id":"allocations-attached","kind":"allocations","success":true,"generation":5`,
        ) && strings.contains(
            output,
            `"allocation_id":"inspection-2","owner_id":"attached-program","kind":"inspection","name":"inspection-2","type":"AttachedPair"`,
        ) && strings.contains(
            output,
            `"known_allocation_bytes":32,"known_allocation_count":2`,
        ) && strings.contains(
            output,
            `"id":"ownership-history-attached","kind":"ownership-history","success":true,"generation":5`,
        ) && strings.contains(
            output,
            `"allocation_id":"inspection-2","action":"retained","generation":5,"name":"inspection-2","type":"AttachedPair","owner_to":"attached-program","reason":"inspection snapshot retained"`,
        ) && strings.contains(
            output,
            `"retained_owner_chain":["attached-program"],"size":8,"alignment":8`,
        ) && strings.contains(
            output,
            `"attached-native-layout-metadata"`,
        ) && strings.contains(
            output,
            `"attached-inspection-definition-versions"`,
        ) && strings.contains(
            output,
            `"attached-cached-inspection-snapshots"`,
        ) && strings.contains(
            output,
            `"attached-logical-allocation-inventory"`,
        ) && strings.contains(
            output,
            `"attached-ownership-lifecycle-history"`,
        ) && strings.contains(
            output,
            `"attached-runtime-checkpoint-allocation-stats"`,
        ) && strings.contains(
            output,
            `"attached-generation-managed-allocation-stats"`,
        ) && strings.contains(
            output,
            `"attached-physical-allocation-inventory"`,
        ) && strings.contains(
            output,
            `"attached-physical-result-ownership-transfers"`,
        ) && strings.contains(
            output,
            `"definition_kind":"defstruct","version":1`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"trace-eval","kind":"trace","success":true,"generation":20`,
        ) && strings.contains(
            output,
            `"source_path":"/virtual/attached-defs.kvist"`,
        ) && strings.contains(
            output,
            `"id":"trace-eval","kind":"trace-limit","success":true,"generation":20`,
        ) && strings.contains(
            output,
            `"id":"trace-eval","kind":"trace-values","success":true,"generation":20`,
        ) && strings.contains(
            output,
            `"name":"x","type":"int","mutable":false,"ownership":"borrowed","value":"4"`,
        ) && strings.contains(
            output,
            `"id":"trace-eval","kind":"trace-values-limit","success":true,"generation":20`,
        ) && strings.contains(
            output,
            `"id":"trace-eval","kind":"trace-summary","success":true,"generation":20`,
        ) && strings.contains(
            output,
            `"trace_points":`,
        ) && strings.contains(
            output,
            `"hotspots":[`,
        ) && strings.contains(
            output,
            `"id":"trace-eval","kind":"output","success":true,"generation":20,"stream":"stdout","text":"6\n"`,
        ) && !strings.contains(
            output,
            "KVIST_REPL_TRACE",
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"inspect-struct-field","kind":"inspection","success":true,"generation":6,"text":"1\n","type":"int","abi":"value:int","handle":"inspection-3","path":["left"],"shape":"scalar"`,
        ) && strings.contains(
            output,
            `"id":"inspect-array","kind":"inspection","success":true,"generation":7,"type":"[dynamic]int","abi":"value:[dynamic]int","handle":"inspection-4","shape":"dynamic-array","element_type":"int","offset":0,"limit":20,"total":2,"entries":[{"index":0,"value":"4"},{"index":1,"value":"5"}]`,
        ) && strings.contains(
            output,
            `"id":"inspect-array-index","kind":"inspection","success":true,"generation":8,"text":"5\n","type":"int","abi":"value:int","handle":"inspection-5","index":1,"shape":"scalar"`,
        ) && strings.contains(
            output,
            `"id":"inspect-array-page","kind":"inspection-page","success":true,"generation":9,"type":"[dynamic]int","abi":"value:[dynamic]int","handle":"inspection-4","shape":"dynamic-array","element_type":"int","offset":1,"limit":1,"total":2,"entries":[{"index":1,"value":"5"}]`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"inspect-map","kind":"inspection","success":true,"generation":10,"type":"map[string]int","abi":"value:map[string]int","handle":"inspection-6","shape":"map","key_type":"string","value_type":"int","offset":0,"limit":20,"total":2,"entries":[{"key":"a","value":"1"},{"key":"b","value":"2"}]`,
        ) && strings.contains(
            output,
            `"id":"inspect-map-key","kind":"inspection","success":true,"generation":11,"text":"2\n","type":"int","abi":"value:int","handle":"inspection-7","key_source":"\"b\"","shape":"scalar"`,
        ) && strings.contains(
            output,
            `"id":"inspect-map-page","kind":"inspection-page","success":true,"generation":12,"type":"map[string]int","abi":"value:map[string]int","handle":"inspection-6","shape":"map","key_type":"string","value_type":"int","offset":1,"limit":1,"total":2,"entries":[{"key":"b","value":"2"}]`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"paused-eval","kind":"paused","success":true,"generation":13,"pause_id":"pause-13","frames":[{"frame_id":"frame-pause-13","pause_id":"pause-13","generation":13,"source_path":"/virtual/attached.kvist","line":40,"column":3,"phase":"before-eval","locals":[]}]`,
        ) && strings.contains(
            output,
            `"id":"paused-frame","kind":"debug-frame","success":true,"generation":13,"pause_id":"pause-13","frames":[`,
        ) && strings.contains(
            output,
            `"id":"paused-continue","kind":"resumed","success":true,"generation":13,"pause_id":"pause-13"`,
        ) && strings.contains(
            output,
            `"id":"paused-eval","kind":"output","success":true,"generation":13,"stream":"stdout","text":"20\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"nested-eval","kind":"paused","success":true,"generation":14,"pause_id":"pause-1-`,
        ) && strings.contains(
            output,
            `"generation":1,"definition_name":"attached-paused","definition_version":1,"source_path":"/virtual/attached-defs.kvist","line":12`,
        ) && strings.contains(
            output,
            `"phase":"before-form","locals":[{"name":"x","type":"int","mutable":false,"ownership":"borrowed","value":"7"`,
        ) && strings.contains(
            output,
            `"id":"nested-frame","kind":"debug-frame","success":true,"generation":14`,
        ) && strings.contains(
            output,
            `"id":"nested-step","kind":"stepping","success":true,"generation":14`,
        ) && strings.contains(
            output,
            `"id":"stepped-frame","kind":"debug-frame","success":true,"generation":14`,
        ) && strings.contains(
            output,
            `"id":"nested-continue","kind":"resumed","success":true,"generation":14`,
        ) && strings.contains(
            output,
            `"id":"nested-eval","kind":"output","success":true,"generation":14,"stream":"stdout","text":"10\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"collection-eval","kind":"paused","success":true,"generation":15`,
        ) && strings.contains(
            output,
            `"path":"values","shape":"dynamic-array","element_type":"int"`,
        ) && strings.contains(
            output,
            `"path":"scores","shape":"map","key_type":"string","value_type":"int"`,
        ) && strings.contains(
            output,
            `"id":"collection-frame","kind":"debug-frame","success":true,"generation":15`,
        ) && strings.contains(
            output,
            `"id":"collection-array-page","kind":"debug-page","success":true,"generation":15,"shape":"dynamic-array","element_type":"int","offset":0,"limit":2,"total":2,"entries":[{"index":0,"value":"3"},{"index":1,"value":"4"}]`,
        ) && strings.contains(
            output,
            `"id":"collection-map-page","kind":"debug-page","success":true,"generation":15,"shape":"map","key_type":"string","value_type":"int","offset":0,"limit":2,"total":2,"entries":[{"index":0,"key":"a","value":"5"},{"index":1,"key":"b","value":"6"}]`,
        ) && strings.contains(
            output,
            `"id":"collection-eval","kind":"output","success":true,"generation":15,"stream":"stdout","text":"8\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"repair-eval","kind":"condition","success":true,"generation":16,"message":"replace attached value","pause_id":`,
        ) && strings.contains(
            output,
            `"condition_type":"kvist/condition","restarts":[`,
        ) && strings.contains(
            output,
            `{"name":"use-value","label":"Replace the mutable local and continue","requires_value":true,"value_type":"int"}`,
        ) && strings.contains(
            output,
            `"id":"repair-invalid","kind":"complete","success":false,"generation":16`,
        ) && strings.contains(
            output,
            `"message":"use-value expects a valid int value"`,
        ) && strings.contains(
            output,
            `"id":"repair-restart","kind":"restart-invoked","success":true,"generation":16`,
        ) && strings.contains(
            output,
            `"restart":"use-value"`,
        ) && strings.contains(
            output,
            `"id":"repair-eval","kind":"output","success":true,"generation":16,"stream":"stdout","text":"42\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"condition-eval","kind":"condition","success":true,"generation":17,"message":"attached condition","pause_id":`,
        ) && strings.contains(
            output,
            `"condition_type":"attached/invalid","condition_data":"{}","restarts":[{"name":"continue","label":"Continue from this safe point","requires_value":false}]`,
        ) && strings.contains(
            output,
            `"id":"condition-restart","kind":"restart-invoked","success":true,"generation":17`,
        ) && strings.contains(
            output,
            `"restart":"continue"`,
        ) && strings.contains(
            output,
            `"id":"condition-eval","kind":"output","success":true,"generation":17,"stream":"stdout","text":"10\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"kind":"ready","success":true,"generation":7`,
        ) && strings.contains(
            output,
            `"attached":true`,
        ) && strings.contains(
            output,
            `{"name":"app/echo","signature":"proc(string)->string"}`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"generations","kind":"generations","success":true,"generation":22,"generations":[`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"bindings","kind":"bindings","success":true,"generation":22,"bindings":[{"name":"attached-add","kind":"defn","version":1,"generation":1`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"versions","kind":"versions","success":true,"generation":22,"versions":[{"version":1,"generation":1,"kind":"defn"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"source_path":"/virtual/attached-defs.kvist","source_start_line":10,"source_start_column":1`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"definition-location","kind":"definition-location","success":true,"generation":22`,
        ) && strings.contains(
            output,
            `"name":"attached-add","definition_kind":"defn","version":1,"definition_generation":1`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"results","kind":"results","success":true,"generation":22,"results":[{"slot":1,"name":"*1","type":"int","abi":"value:int","generation":22,`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"attached-timeout","kind":"complete","success":false,"generation":8,"message":"timeout_ms is unavailable for attached applications; use cooperative restarts"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"reset","kind":"attached-reset","success":true,"generation":7`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"generations-reset","kind":"generations","success":true,"generation":0`,
        ) && strings.contains(
            output,
            `"id":"checkpoints-reset","kind":"checkpoints","success":true,"generation":0`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"stale-call","kind":"complete","success":false`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"fresh-result","kind":"output","success":true,"generation":1,"stream":"stdout","text":"2\n"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"define","kind":"generation-loaded","success":true,"generation":1`,
        ) && strings.contains(
            output,
            `"id":"call","kind":"generation-loaded","success":true,"generation":2`,
        ) && strings.contains(
            output,
            `"id":"result","kind":"output","success":true,"generation":3,"stream":"stdout","text":"6\n"`,
        ) && strings.contains(
            output,
            `"application_generation":7,"attached_generation":3`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"invoke","kind":"capability-result","success":true,"generation":7`,
        ) && strings.contains(
            output,
            `"text":"host:hello"`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"reload","kind":"reload-requested","success":true,"generation":7`,
        ) && strings.contains(
            output,
            `"reload_requested":true`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"reload","kind":"reload-complete","success":true,"generation":8`,
        ) && strings.contains(
            output,
            `{"name":"app/echo","signature":"proc(string)->string"}`,
        ),
        true,
    )
    testing.expect_value(
        t,
        strings.contains(
            output,
            `"id":"attached-abort-control","kind":"abort-requested","success":true`,
        ) && strings.contains(
            output,
            `"id":"attached-abort-call","kind":"aborted","success":true`,
        ) && strings.contains(
            output,
            `"id":"attached-abort-call","kind":"complete","success":false`,
        ) && strings.contains(
            output,
            `"id":"attached-abort-state","kind":"output","success":true`,
        ) && strings.contains(
            output,
            `"stream":"stdout","text":"8\n"`,
        ) && strings.contains(
            output,
            `"id":"attached-abort-cleanup-state","kind":"output","success":true`,
        ) && strings.contains(
            output,
            `"stream":"stdout","text":"1\n"`,
        ),
        true,
    )
    testing.expect_value(t, calls, 1)
    testing.expect_value(t, replacement_started, true)
    testing.expect_value(t, host.console_reload_requested, false)
}
