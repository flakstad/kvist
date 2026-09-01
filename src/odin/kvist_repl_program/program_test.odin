package kvist_repl_program

import "core:strings"
import "core:testing"

@(test)
program_round_trip_preserves_typed_procedures :: proc(t: ^testing.T) {
    expressions := [?]Expression{
        {
            kind = .Local,
            value_kind = .Int,
            operand = 0,
        },
        {
            kind = .Int_Literal,
            value_kind = .Int,
            int_value = 3,
        },
        {
            kind = .Multiply,
            value_kind = .Int,
            children_count = 2,
        },
    }
    procedure := Procedure{
        name = strings.clone("scale"),
        signature = strings.clone("proc(int:borrowed)->int"),
        result_kind = .Int,
        local_count = 2,
        result_expr = 2,
    }
    append(&procedure.parameter_kinds, Value_Kind.Int)
    append(&procedure.local_kinds, Value_Kind.Int, Value_Kind.Int)
    append(&procedure.expressions, ..expressions[:])
    append(&procedure.child_indices, 0, 1)
    managed_procedure := Procedure{
        name = strings.clone("managed"),
        signature = strings.clone("proc()->int"),
        result_kind = .Int,
        local_count = 1,
        result_expr = 2,
    }
    append(&managed_procedure.local_kinds, Value_Kind.String)
    append(
        &managed_procedure.expressions,
        Expression{
            kind = .String_Literal,
            value_kind = .String,
            string_value = strings.clone("Kvist"),
        },
        Expression{
            kind = .Int_Literal,
            value_kind = .Int,
            int_value = 42,
        },
        Expression{
            kind = .Let,
            value_kind = .Int,
            bindings_count = 1,
            body = 1,
        },
    )
    append(&managed_procedure.bindings, Binding{
        slot = 0,
        value_expr = 0,
        value_kind = .String,
        managed_cleanup = true,
    })
    source := Program{}
    append(&source.procedures, procedure, managed_procedure)
    defer program_delete(&source)
    encoded, encoded_ok := program_encode(source)
    testing.expect_value(t, encoded_ok, true)
    defer delete(encoded)
    decoded, decoded_ok := program_decode(encoded)
    testing.expect_value(t, decoded_ok, true)
    defer program_delete(&decoded)
    testing.expect_value(t, len(decoded.procedures), 2)
    decoded_procedure := decoded.procedures[0]
    testing.expect_value(t, decoded_procedure.name, "scale")
    testing.expect_value(t, decoded_procedure.signature, "proc(int:borrowed)->int")
    testing.expect_value(t, decoded_procedure.result_kind, Value_Kind.Int)
    testing.expect_value(t, decoded_procedure.parameter_kinds[0], Value_Kind.Int)
    testing.expect_value(t, decoded_procedure.local_kinds[1], Value_Kind.Int)
    testing.expect_value(t, decoded_procedure.local_count, 2)
    testing.expect_value(t, decoded_procedure.result_expr, 2)
    testing.expect_value(t, decoded_procedure.child_indices[1], 1)
    testing.expect_value(t, decoded_procedure.expressions[1].int_value, 3)
    testing.expect_value(
        t,
        decoded.procedures[1].bindings[0].managed_cleanup,
        true,
    )
}

@(test)
program_decode_rejects_malformed_references :: proc(t: ^testing.T) {
    decoded, ok := program_decode(
        "3|1|p:78:70726f6328292d3e696e74:i:0:::0:1:1:0" +
        "|e:int:i:0:0:1:0:0:0:1:0:0:::|c:9",
    )
    defer program_delete(&decoded)
    testing.expect_value(t, ok, false)
}
