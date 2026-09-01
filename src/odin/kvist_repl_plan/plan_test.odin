package kvist_repl_plan

import "core:strings"
import "core:testing"

@(test)
execution_plan_round_trips_versioned_instructions :: proc(t: ^testing.T) {
    instructions := [?]Instruction{
        {opcode = .Push_Bool, operand = 1},
        {opcode = .Branch_False, operand = 5},
        {opcode = .Push_Int, operand = 40},
        {opcode = .Push_Int, operand = 2},
        {opcode = .Add, operand = 2},
        {opcode = .Jump, operand = 6},
    }
    source := Execution_Plan{
        result_kind = .Int,
        result_action = .Rotate_History,
    }
    append(&source.instructions, ..instructions[:])
    defer execution_plan_delete(&source)
    encoded, encoded_ok := execution_plan_encode(source)
    testing.expect_value(t, encoded_ok, true)
    decoded, decoded_ok := execution_plan_decode(encoded)
    testing.expect_value(t, decoded_ok, true)
    if decoded_ok {
        testing.expect_value(t, decoded.result_kind, Value_Kind.Int)
        testing.expect_value(
            t,
            decoded.result_action,
            Result_Action.Rotate_History,
        )
        testing.expect_value(t, len(decoded.instructions), 6)
        testing.expect_value(
            t,
            decoded.instructions[4],
            Instruction{opcode = .Add, operand = 2},
        )
    }
    execution_plan_delete(&decoded)
    delete(encoded)

    float_source := Execution_Plan{
        result_kind = .F64,
        result_action = .Rotate_History,
    }
    append(
        &float_source.instructions,
        Instruction{
            opcode = .Push_F64,
            operand = 4609434218613702656,
        },
        Instruction{opcode = .Store_Local, operand = 0},
        Instruction{opcode = .Load_Local, operand = 0},
    )
    defer execution_plan_delete(&float_source)
    float_encoded, float_encoded_ok := execution_plan_encode(float_source)
    testing.expect_value(t, float_encoded_ok, true)
    float_decoded, float_decoded_ok := execution_plan_decode(float_encoded)
    testing.expect_value(t, float_decoded_ok, true)
    if float_decoded_ok {
        testing.expect_value(t, float_decoded.result_kind, Value_Kind.F64)
        testing.expect_value(
            t,
            float_decoded.instructions[0],
            Instruction{
                opcode = .Push_F64,
                operand = 4609434218613702656,
            },
        )
        testing.expect_value(
            t,
            float_decoded.instructions[2],
            Instruction{opcode = .Load_Local, operand = 0},
        )
    }
    execution_plan_delete(&float_decoded)
    delete(float_encoded)

    text_source := Execution_Plan{
        result_kind = .String,
        result_action = .Rotate_History,
    }
    append(
        &text_source.instructions,
        Instruction{
            opcode = .Push_String,
            text_operand = strings.clone("a|b:\nKvist"),
        },
    )
    defer execution_plan_delete(&text_source)
    text_encoded, text_encoded_ok := execution_plan_encode(text_source)
    testing.expect_value(t, text_encoded_ok, true)
    testing.expect_value(
        t,
        text_encoded,
        "9|s|r|s:617c623a0a4b76697374",
    )
    text_decoded, text_decoded_ok := execution_plan_decode(text_encoded)
    testing.expect_value(t, text_decoded_ok, true)
    if text_decoded_ok {
        testing.expect_value(t, text_decoded.result_kind, Value_Kind.String)
        testing.expect_value(
            t,
            text_decoded.instructions[0].text_operand,
            "a|b:\nKvist",
        )
    }
    execution_plan_delete(&text_decoded)
    delete(text_encoded)

    data_target_builder := strings.builder_make()
    strings.write_string(&data_target_builder, "data__empty_map")
    strings.write_byte(&data_target_builder, 0)
    strings.write_string(&data_target_builder, "proc()->Data:owned")
    data_source := Execution_Plan{
        result_kind = .Data,
        result_action = .Rotate_History,
    }
    append(
        &data_source.instructions,
        Instruction{
            opcode = .Invoke_Scalar_0,
            text_operand = strings.clone(
                strings.to_string(data_target_builder),
            ),
        },
    )
    strings.builder_destroy(&data_target_builder)
    defer execution_plan_delete(&data_source)
    data_encoded, data_encoded_ok := execution_plan_encode(data_source)
    testing.expect_value(t, data_encoded_ok, true)
    testing.expect_value(t, strings.has_prefix(data_encoded, "9|d|r|c0:"), true)
    data_decoded, data_decoded_ok := execution_plan_decode(data_encoded)
    testing.expect_value(t, data_decoded_ok, true)
    if data_decoded_ok {
        testing.expect_value(t, data_decoded.result_kind, Value_Kind.Data)
        testing.expect_value(
            t,
            data_decoded.instructions[0].text_operand,
            data_source.instructions[0].text_operand,
        )
    }
    execution_plan_delete(&data_decoded)
    delete(data_encoded)

    call_target_builder := strings.builder_make()
    strings.write_string(&call_target_builder, "contains")
    strings.write_byte(&call_target_builder, 0)
    strings.write_string(
        &call_target_builder,
        "proc(string,string)->bool",
    )
    call_source := Execution_Plan{
        result_kind = .Bool,
        result_action = .Rotate_History,
    }
    append(
        &call_source.instructions,
        Instruction{
            opcode = .Invoke_Scalar_2,
            text_operand = strings.clone(
                strings.to_string(call_target_builder),
            ),
        },
    )
    strings.builder_destroy(&call_target_builder)
    defer execution_plan_delete(&call_source)
    call_encoded, call_encoded_ok := execution_plan_encode(call_source)
    testing.expect_value(t, call_encoded_ok, true)
    call_decoded, call_decoded_ok := execution_plan_decode(call_encoded)
    testing.expect_value(t, call_decoded_ok, true)
    if call_decoded_ok {
        testing.expect_value(
            t,
            call_decoded.instructions[0].opcode,
            Opcode.Invoke_Scalar_2,
        )
        testing.expect_value(
            t,
            call_decoded.instructions[0].text_operand,
            call_source.instructions[0].text_operand,
        )
    }
    execution_plan_delete(&call_decoded)
    delete(call_encoded)
}

@(test)
execution_plan_rejects_unknown_and_out_of_range_encodings :: proc(
    t: ^testing.T,
) {
    invalid := [?]string{
        "",
        "6|i|r|i:1",
        "7|i|r|i:1",
        "8|i|r|i:1",
        "9|x|r|i:1",
        "9|i|x|i:1",
        "9|i|r|wat",
        "9|i|r|b:2",
        "9|i|r|r:3",
        "9|i|r|add:1",
        "9|i|r|jmp:2",
        "9|i|r|i:1|jmp:0",
        "9|i|r|loop:0",
        "9|i|r|i:1|loop:1",
        "9|i|r|not:1",
        "9|i|r|drop:1",
        "9|i|r|sl:-1",
        "9|i|r|ll:4096",
        "9|s|r|s",
        "9|s|r|s:0",
        "9|s|r|s:zz",
        "9|i|r|i:",
        "9|b|r|c2:",
        "9|b|r|c2:6e616d65",
        "9|b|r|c2:6e616d6500",
        "9|b|r|c2:00736967",
        "9|b|r|c2:6e006d6500736967",
    }
    for encoded in invalid {
        plan, ok := execution_plan_decode(encoded)
        testing.expect_value(t, ok, false)
        execution_plan_delete(&plan)
    }
}
