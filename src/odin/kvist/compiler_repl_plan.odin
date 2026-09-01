// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:strings"
import repl_plan "../kvist_repl_plan"

Repl_Execution_Plan :: struct {
    encoded:                  string,
    result_abi:               string,
    preserves_result_history: bool,
    recent_result_mask:       u8,
}

Repl_Scalar_Invoke_Metadata :: struct {
    name:       string,
    signature:  string,
    result_abi: string,
}

repl_execution_plan_delete :: proc(plan: ^Repl_Execution_Plan) {
    if plan == nil {
        return
    }
    delete(plan.encoded)
    delete(plan.result_abi)
    plan^ = {}
}

Repl_Plan_Builder :: struct {
    plan: repl_plan.Execution_Plan,
}

REPL_PLAN_OPERATORS := [?]string{
    "+", "-", "*", "/", "%", "not", "and", "or", "if", "let",
    "=", "==", "!=", "<", "<=", ">", ">=",
}

repl_plan_operator_supported :: proc(name: string) -> bool {
    return contains_text(REPL_PLAN_OPERATORS[:], name)
}

repl_plan_append :: proc(
    builder: ^Repl_Plan_Builder,
    opcode: repl_plan.Opcode,
    operand := 0,
) -> int {
    index := len(builder.plan.instructions)
    append(&builder.plan.instructions, repl_plan.Instruction{
        opcode = opcode,
        operand = operand,
    })
    return index
}

repl_plan_append_text :: proc(
    builder: ^Repl_Plan_Builder,
    opcode: repl_plan.Opcode,
    text_operand: string,
) -> int {
    index := len(builder.plan.instructions)
    append(&builder.plan.instructions, repl_plan.Instruction{
        opcode = opcode,
        text_operand = strings.clone(text_operand),
    })
    return index
}

repl_plan_recent_result_mask :: proc(plan: repl_plan.Execution_Plan) -> u8 {
    mask: u8
    for instruction in plan.instructions {
        if instruction.opcode == .Load_Result &&
           instruction.operand >= 0 && instruction.operand < 3 {
            mask |= u8(1) << u8(instruction.operand)
        }
    }
    return mask
}

repl_plan_checked_add :: proc(a, b: int) -> (int, bool) {
    if (b > 0 && a > max(int)-b) ||
       (b < 0 && a < min(int)-b) {
        return 0, false
    }
    return a+b, true
}

repl_plan_checked_subtract :: proc(a, b: int) -> (int, bool) {
    if (b > 0 && a < min(int)+b) ||
       (b < 0 && a > max(int)+b) {
        return 0, false
    }
    return a-b, true
}

repl_plan_checked_multiply :: proc(a, b: int) -> (int, bool) {
    if a == 0 || b == 0 {
        return 0, true
    }
    if (a == min(int) && b == -1) ||
       (b == min(int) && a == -1) {
        return 0, false
    }
    if a > 0 {
        if (b > 0 && a > max(int)/b) ||
           (b < 0 && b < min(int)/a) {
            return 0, false
        }
    } else {
        if (b > 0 && a < min(int)/b) ||
           (b < 0 && a < max(int)/b) {
            return 0, false
        }
    }
    return a*b, true
}

repl_plan_integer_digit :: proc(ch: u8) -> (u64, bool) {
    if ch >= '0' && ch <= '9' {
        return u64(ch-'0'), true
    }
    if ch >= 'a' && ch <= 'f' {
        return u64(ch-'a'+10), true
    }
    if ch >= 'A' && ch <= 'F' {
        return u64(ch-'A'+10), true
    }
    return 0, false
}

repl_plan_parse_int :: proc(text: string) -> (int, bool) {
    if text == "" {
        return 0, false
    }
    index := 0
    negative := false
    if text[index] == '+' || text[index] == '-' {
        negative = text[index] == '-'
        index += 1
        if index >= len(text) {
            return 0, false
        }
    }
    base: u64 = 10
    if index+2 < len(text) && text[index] == '0' {
        switch text[index+1] {
        case 'b': base = 2
        case 'o': base = 8
        case 'd': base = 10
        case 'z': base = 12
        case 'x': base = 16
        case:
        }
        if base != 10 || text[index+1] == 'd' {
            index += 2
        }
    }
    limit := u64(max(int))
    if negative {
        limit += 1
    }
    magnitude: u64
    saw_digit := false
    for index < len(text) {
        ch := text[index]
        index += 1
        if ch == '_' {
            if !saw_digit || index >= len(text) {
                return 0, false
            }
            next_digit, next_ok := repl_plan_integer_digit(text[index])
            if !next_ok || next_digit >= base {
                return 0, false
            }
            continue
        }
        digit, digit_ok := repl_plan_integer_digit(ch)
        if !digit_ok || digit >= base ||
           magnitude > (limit-digit)/base {
            return 0, false
        }
        magnitude = magnitude*base+digit
        saw_digit = true
    }
    if !saw_digit {
        return 0, false
    }
    if negative {
        if magnitude == u64(max(int))+1 {
            return min(int), true
        }
        return -int(magnitude), true
    }
    return int(magnitude), true
}

repl_plan_recent_result_index :: proc(text: string) -> (int, bool) {
    switch text {
    case "*1", "kvist_repl_star_1": return 0, true
    case "*2", "kvist_repl_star_2": return 1, true
    case "*3", "kvist_repl_star_3": return 2, true
    }
    return 0, false
}

repl_plan_form_preserves_history :: proc(form: CST_Form) -> bool {
    if form.kind != .Symbol {
        return false
    }
    _, recent := repl_plan_recent_result_index(form.text)
    return recent
}

repl_build_semantic_execution_plan :: proc(
    program: AST_Program,
    form: CST_Form,
    recent_result_types: []string = nil,
    repl_value_names: []string = nil,
    repl_var_names: []string = nil,
    repl_current_proc_names: []string = nil,
    repl_stale_proc_names: []string = nil,
    repl_scalar_invokes: []Repl_Scalar_Invoke_Metadata = nil,
) -> (Repl_Execution_Plan, bool) {
    features := Emitter_Features{}
    emitter := Emitter{
        decls = program.decls[:],
        features = &features,
        repl_value_names = repl_value_names,
        repl_var_names = repl_var_names,
        repl_recent_result_types = recent_result_types,
        repl_current_proc_names = repl_current_proc_names,
    }
    for decl in program.decls {
        if decl.kind == .Struct {
            append(&emitter.structs, decl.struct_decl)
        }
        if decl.kind == .Union {
            append(&emitter.unions, decl.union_decl)
        }
    }
    semantic_ir, analyzed := repl_analyze_semantic_expression(
        &emitter,
        form,
        recent_result_types,
        repl_stale_proc_names,
        repl_scalar_invokes,
    )
    if !analyzed {
        return {}, false
    }
    defer semantic_expression_ir_delete(&semantic_ir)
    result_expression := semantic_ir.expressions[semantic_ir.result_expr]
    if result_expression.value.kind == .Data &&
       !result_expression.value.managed_handle {
        return {}, false
    }
    result_kind :=
        semantic_value_kind_to_plan_kind(result_expression.value.kind)
    if result_kind == .Invalid {
        return {}, false
    }
    builder := Repl_Plan_Builder{}
    defer repl_plan.execution_plan_delete(&builder.plan)
    if !repl_emit_semantic_expr(
        semantic_ir,
        &builder,
        semantic_ir.result_expr,
    ) ||
       len(builder.plan.instructions) == 0 {
        return {}, false
    }
    builder.plan.result_kind = result_kind
    builder.plan.result_action =
        .Preserve_History if
            repl_plan_form_preserves_history(form) else
        .Rotate_History
    encoded, encoded_ok :=
        repl_plan.execution_plan_encode(builder.plan)
    if !encoded_ok {
        return {}, false
    }
    return Repl_Execution_Plan{
        encoded = encoded,
        result_abi = strings.clone(
            fmt.tprintf(
                "value:%s",
                semantic_type_for_value_kind(
                    result_expression.value.kind,
                ),
            ),
        ),
        preserves_result_history =
            builder.plan.result_action == .Preserve_History,
        recent_result_mask = repl_plan_recent_result_mask(builder.plan),
    }, true
}
