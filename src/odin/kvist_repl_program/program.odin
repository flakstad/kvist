// Package kvist_repl_program defines the backend-neutral, typed program
// handed from the ordinary Kvist compiler to an incremental REPL backend.
// It deliberately contains no execution semantics: interpreters and native
// code generators consume this format only after the compiler has resolved
// names, types, ownership, overloads, and control flow.
package kvist_repl_program

import "core:fmt"
import "core:strconv"
import "core:strings"

VERSION :: 3
MAX_PROCEDURES :: 256
MAX_EXPRESSIONS :: 65_536
MAX_TEXT_BYTES :: 4 * 1024 * 1024

Value_Kind :: enum u8 {
    Invalid,
    Void,
    Bool,
    Int,
    F64,
    String,
    Data,
}

Expr_Kind :: enum u8 {
    Invalid,
    Sequence,
    Discard,
    Set_Local,
    While,
    Return,
    Break,
    Continue,
    Bool_Literal,
    Int_Literal,
    F64_Literal,
    String_Literal,
    Recent_Result,
    Local,
    Let,
    Native_Call,
    Program_Call,
    If,
    Not,
    And,
    Or,
    Add,
    Subtract,
    Multiply,
    Divide,
    Modulo,
    Equal,
    Not_Equal,
    Less,
    Less_Equal,
    Greater,
    Greater_Equal,
}

Expression :: struct {
    kind:             Expr_Kind,
    value_kind:       Value_Kind,
    operand:          int,
    children_start:   int,
    children_count:   int,
    bindings_start:   int,
    bindings_count:   int,
    body:             int,
    int_value:        int,
    float_value:      f64,
    bool_value:       bool,
    resolved_name:    string,
    scalar_signature: string,
    string_value:     string,
}

Binding :: struct {
    slot:       int,
    value_expr: int,
    value_kind: Value_Kind,
    managed_cleanup: bool,
}

Procedure :: struct {
    name:            string,
    signature:       string,
    result_kind:     Value_Kind,
    parameter_kinds: [dynamic]Value_Kind,
    local_kinds:     [dynamic]Value_Kind,
    local_count:     int,
    expressions:     [dynamic]Expression,
    child_indices:   [dynamic]int,
    bindings:        [dynamic]Binding,
    result_expr:     int,
}

Program :: struct {
    procedures: [dynamic]Procedure,
}

procedure_delete :: proc(procedure: ^Procedure) {
    if procedure == nil {
        return
    }
    delete(procedure.name)
    delete(procedure.signature)
    delete(procedure.parameter_kinds)
    delete(procedure.local_kinds)
    for &expression in procedure.expressions {
        delete(expression.resolved_name)
        delete(expression.scalar_signature)
        delete(expression.string_value)
    }
    delete(procedure.expressions)
    delete(procedure.child_indices)
    delete(procedure.bindings)
    procedure^ = {}
}

program_delete :: proc(program: ^Program) {
    if program == nil {
        return
    }
    for &procedure in program.procedures {
        procedure_delete(&procedure)
    }
    delete(program.procedures)
    program^ = {}
}

value_kind_code :: proc(kind: Value_Kind) -> string {
    switch kind {
    case .Void:   return "v"
    case .Bool:   return "b"
    case .Int:    return "i"
    case .F64:    return "f"
    case .String: return "s"
    case .Data:   return "d"
    case .Invalid:
    }
    return ""
}

value_kind_from_code :: proc(code: string) -> (Value_Kind, bool) {
    switch code {
    case "v": return .Void, true
    case "b": return .Bool, true
    case "i": return .Int, true
    case "f": return .F64, true
    case "s": return .String, true
    case "d": return .Data, true
    }
    return .Invalid, false
}

expr_kind_code :: proc(kind: Expr_Kind) -> string {
    switch kind {
    case .Sequence:      return "seq"
    case .Discard:       return "discard"
    case .Set_Local:     return "set-local"
    case .While:         return "while"
    case .Return:        return "return"
    case .Break:         return "break"
    case .Continue:      return "continue"
    case .Bool_Literal:   return "bool"
    case .Int_Literal:    return "int"
    case .F64_Literal:    return "f64"
    case .String_Literal: return "str"
    case .Recent_Result:  return "recent"
    case .Local:          return "local"
    case .Let:            return "let"
    case .Native_Call:    return "native-call"
    case .Program_Call:   return "program-call"
    case .If:             return "if"
    case .Not:            return "not"
    case .And:            return "and"
    case .Or:             return "or"
    case .Add:            return "add"
    case .Subtract:       return "sub"
    case .Multiply:       return "mul"
    case .Divide:         return "div"
    case .Modulo:         return "mod"
    case .Equal:          return "eq"
    case .Not_Equal:      return "ne"
    case .Less:           return "lt"
    case .Less_Equal:     return "le"
    case .Greater:        return "gt"
    case .Greater_Equal:  return "ge"
    case .Invalid:
    }
    return ""
}

expr_kind_from_code :: proc(code: string) -> (Expr_Kind, bool) {
    switch code {
    case "seq":          return .Sequence, true
    case "discard":      return .Discard, true
    case "set-local":    return .Set_Local, true
    case "while":        return .While, true
    case "return":       return .Return, true
    case "break":        return .Break, true
    case "continue":     return .Continue, true
    case "bool":         return .Bool_Literal, true
    case "int":          return .Int_Literal, true
    case "f64":          return .F64_Literal, true
    case "str":          return .String_Literal, true
    case "recent":       return .Recent_Result, true
    case "local":        return .Local, true
    case "let":          return .Let, true
    case "native-call":  return .Native_Call, true
    case "program-call": return .Program_Call, true
    case "if":           return .If, true
    case "not":          return .Not, true
    case "and":          return .And, true
    case "or":           return .Or, true
    case "add":          return .Add, true
    case "sub":          return .Subtract, true
    case "mul":          return .Multiply, true
    case "div":          return .Divide, true
    case "mod":          return .Modulo, true
    case "eq":           return .Equal, true
    case "ne":           return .Not_Equal, true
    case "lt":           return .Less, true
    case "le":           return .Less_Equal, true
    case "gt":           return .Greater, true
    case "ge":           return .Greater_Equal, true
    }
    return .Invalid, false
}

hex_digit_value :: proc(ch: u8) -> (u8, bool) {
    switch ch {
    case '0' ..= '9': return ch-'0', true
    case 'a' ..= 'f': return ch-'a'+10, true
    case 'A' ..= 'F': return ch-'A'+10, true
    }
    return 0, false
}

write_hex_text :: proc(builder: ^strings.Builder, value: string) {
    digits := "0123456789abcdef"
    for ch in transmute([]u8)value {
        strings.write_byte(builder, digits[ch >> 4])
        strings.write_byte(builder, digits[ch & 0xf])
    }
}

decode_hex_text :: proc(encoded: string) -> (string, bool) {
    if len(encoded)%2 != 0 || len(encoded)/2 > MAX_TEXT_BYTES {
        return "", false
    }
    result := make([]u8, len(encoded)/2)
    for index := 0; index < len(encoded); index += 2 {
        high, high_ok := hex_digit_value(encoded[index])
        low, low_ok := hex_digit_value(encoded[index+1])
        if !high_ok || !low_ok {
            delete(result)
            return "", false
        }
        result[index/2] = high << 4 | low
    }
    return transmute(string)result, true
}

parse_non_negative :: proc(value: string) -> (int, bool) {
    parsed, ok := strconv.parse_int(value)
    return parsed, ok && parsed >= 0
}

procedure_valid :: proc(procedure: Procedure) -> bool {
    if procedure.name == "" || procedure.signature == "" ||
       procedure.result_kind == .Invalid ||
       procedure.result_kind == .Void ||
       len(procedure.parameter_kinds) > MAX_EXPRESSIONS ||
       procedure.local_count < len(procedure.parameter_kinds) ||
       len(procedure.local_kinds) != procedure.local_count ||
       procedure.local_count > MAX_EXPRESSIONS ||
       len(procedure.expressions) == 0 ||
       len(procedure.expressions) > MAX_EXPRESSIONS ||
       len(procedure.child_indices) > MAX_EXPRESSIONS ||
       len(procedure.bindings) > MAX_EXPRESSIONS ||
       procedure.result_expr < 0 ||
       procedure.result_expr >= len(procedure.expressions) {
        return false
    }
    for kind in procedure.parameter_kinds {
        if kind == .Invalid || kind == .Void {
            return false
        }
    }
    for kind, index in procedure.local_kinds {
        if kind == .Invalid || kind == .Void ||
           (index < len(procedure.parameter_kinds) &&
            kind != procedure.parameter_kinds[index]) {
            return false
        }
    }
    for expression in procedure.expressions {
        children_end := expression.children_start+expression.children_count
        bindings_end := expression.bindings_start+expression.bindings_count
        if expression.kind == .Invalid || expression.value_kind == .Invalid ||
           expression.children_start < 0 || expression.children_count < 0 ||
           children_end > len(procedure.child_indices) ||
           expression.bindings_start < 0 || expression.bindings_count < 0 ||
           bindings_end > len(procedure.bindings) {
            return false
        }
        if expression.kind == .Let &&
           (expression.body < 0 || expression.body >= len(procedure.expressions)) {
            return false
        }
        if (expression.kind == .Native_Call ||
            expression.kind == .Program_Call) &&
           (expression.resolved_name == "" || expression.scalar_signature == "") {
            return false
        }
        if (expression.kind == .Local ||
            expression.kind == .Set_Local) &&
           (expression.operand < 0 ||
            expression.operand >= procedure.local_count ||
            expression.value_kind !=
                (Value_Kind.Void if expression.kind == .Set_Local else
                 procedure.local_kinds[expression.operand])) {
            return false
        }
    }
    for child in procedure.child_indices {
        if child < 0 || child >= len(procedure.expressions) {
            return false
        }
    }
    for binding in procedure.bindings {
        if binding.slot < 0 || binding.slot >= procedure.local_count ||
           binding.value_expr < 0 ||
           binding.value_expr >= len(procedure.expressions) ||
           binding.value_kind == .Invalid ||
           binding.value_kind == .Void ||
           (binding.managed_cleanup &&
            binding.value_kind != .String && binding.value_kind != .Data) {
            return false
        }
    }
    return true
}

program_encode :: proc(program: Program) -> (string, bool) {
    if len(program.procedures) == 0 ||
       len(program.procedures) > MAX_PROCEDURES {
        return "", false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    fmt.sbprintf(&builder, "%d|%d", VERSION, len(program.procedures))
    expression_count := 0
    text_bytes := 0
    for procedure in program.procedures {
        if !procedure_valid(procedure) {
            return "", false
        }
        expression_count += len(procedure.expressions)
        if expression_count > MAX_EXPRESSIONS {
            return "", false
        }
        parameter_codes := strings.builder_make()
        for kind in procedure.parameter_kinds {
            code := value_kind_code(kind)
            if code == "" {
                strings.builder_destroy(&parameter_codes)
                return "", false
            }
            strings.write_string(&parameter_codes, code)
        }
        local_codes := strings.builder_make()
        for kind in procedure.local_kinds {
            code := value_kind_code(kind)
            if code == "" {
                strings.builder_destroy(&parameter_codes)
                strings.builder_destroy(&local_codes)
                return "", false
            }
            strings.write_string(&local_codes, code)
        }
        text_bytes += len(procedure.name)+len(procedure.signature)
        if text_bytes > MAX_TEXT_BYTES {
            strings.builder_destroy(&parameter_codes)
            strings.builder_destroy(&local_codes)
            return "", false
        }
        strings.write_string(&builder, "|p:")
        write_hex_text(&builder, procedure.name)
        strings.write_byte(&builder, ':')
        write_hex_text(&builder, procedure.signature)
        fmt.sbprintf(
            &builder,
            ":%s:%d:%s:%s:%d:%d:%d:%d",
            value_kind_code(procedure.result_kind),
            procedure.local_count,
            strings.to_string(parameter_codes),
            strings.to_string(local_codes),
            procedure.result_expr,
            len(procedure.expressions),
            len(procedure.child_indices),
            len(procedure.bindings),
        )
        strings.builder_destroy(&parameter_codes)
        strings.builder_destroy(&local_codes)
        for expression in procedure.expressions {
            text_bytes += len(expression.resolved_name)+
                          len(expression.scalar_signature)+
                          len(expression.string_value)
            if text_bytes > MAX_TEXT_BYTES {
                return "", false
            }
            float_bits := transmute(i64)expression.float_value
            fmt.sbprintf(
                &builder,
                "|e:%s:%s:%d:%d:%d:%d:%d:%d:%d:%d:%d:",
                expr_kind_code(expression.kind),
                value_kind_code(expression.value_kind),
                expression.operand,
                expression.children_start,
                expression.children_count,
                expression.bindings_start,
                expression.bindings_count,
                expression.body,
                expression.int_value,
                float_bits,
                1 if expression.bool_value else 0,
            )
            write_hex_text(&builder, expression.resolved_name)
            strings.write_byte(&builder, ':')
            write_hex_text(&builder, expression.scalar_signature)
            strings.write_byte(&builder, ':')
            write_hex_text(&builder, expression.string_value)
        }
        for child in procedure.child_indices {
            fmt.sbprintf(&builder, "|c:%d", child)
        }
        for binding in procedure.bindings {
            fmt.sbprintf(
                &builder,
                "|b:%d:%d:%s:%d",
                binding.slot,
                binding.value_expr,
                value_kind_code(binding.value_kind),
                1 if binding.managed_cleanup else 0,
            )
        }
    }
    return strings.clone(strings.to_string(builder)), true
}

program_decode :: proc(encoded: string) -> (Program, bool) {
    program := Program{}
    records := strings.split(encoded, "|", context.temp_allocator)
    if len(records) < 3 {
        return program, false
    }
    version, version_ok := strconv.parse_int(records[0])
    procedure_count, count_ok := parse_non_negative(records[1])
    if !version_ok || version != VERSION || !count_ok ||
       procedure_count == 0 || procedure_count > MAX_PROCEDURES {
        return program, false
    }
    cursor := 2
    total_expressions := 0
    total_text_bytes := 0
    for _ in 0..<procedure_count {
        if cursor >= len(records) {
            program_delete(&program)
            return {}, false
        }
        fields := strings.split(records[cursor], ":", context.temp_allocator)
        cursor += 1
        if len(fields) != 11 || fields[0] != "p" {
            program_delete(&program)
            return {}, false
        }
        name, name_ok := decode_hex_text(fields[1])
        signature, signature_ok := decode_hex_text(fields[2])
        result_kind, result_ok := value_kind_from_code(fields[3])
        local_count, locals_ok := parse_non_negative(fields[4])
        result_expr, result_expr_ok := parse_non_negative(fields[7])
        expression_count, expressions_ok := parse_non_negative(fields[8])
        child_count, children_ok := parse_non_negative(fields[9])
        binding_count, bindings_ok := parse_non_negative(fields[10])
        if !name_ok || !signature_ok || !result_ok || !locals_ok ||
           !result_expr_ok || !expressions_ok || !children_ok || !bindings_ok ||
           expression_count == 0 || expression_count > MAX_EXPRESSIONS ||
           child_count > MAX_EXPRESSIONS || binding_count > MAX_EXPRESSIONS {
            delete(name)
            delete(signature)
            program_delete(&program)
            return {}, false
        }
        procedure := Procedure{
            name = name,
            signature = signature,
            result_kind = result_kind,
            local_count = local_count,
            result_expr = result_expr,
        }
        parameter_codes := fields[5]
        for index := 0; index < len(parameter_codes); index += 1 {
            kind, kind_ok := value_kind_from_code(parameter_codes[index:index+1])
            if !kind_ok {
                procedure_delete(&procedure)
                program_delete(&program)
                return {}, false
            }
            append(&procedure.parameter_kinds, kind)
        }
        local_codes := fields[6]
        for index := 0; index < len(local_codes); index += 1 {
            kind, kind_ok := value_kind_from_code(local_codes[index:index+1])
            if !kind_ok {
                procedure_delete(&procedure)
                program_delete(&program)
                return {}, false
            }
            append(&procedure.local_kinds, kind)
        }
        total_expressions += expression_count
        total_text_bytes += len(name)+len(signature)
        if total_expressions > MAX_EXPRESSIONS ||
           total_text_bytes > MAX_TEXT_BYTES ||
           cursor+expression_count+child_count+binding_count > len(records) {
            procedure_delete(&procedure)
            program_delete(&program)
            return {}, false
        }
        for _ in 0..<expression_count {
            expression_fields := strings.split(
                records[cursor],
                ":",
                context.temp_allocator,
            )
            cursor += 1
            if len(expression_fields) != 15 || expression_fields[0] != "e" {
                procedure_delete(&procedure)
                program_delete(&program)
                return {}, false
            }
            kind, kind_ok := expr_kind_from_code(expression_fields[1])
            value_kind, value_ok := value_kind_from_code(expression_fields[2])
            operand, operand_ok := strconv.parse_int(expression_fields[3])
            children_start, children_start_ok := parse_non_negative(expression_fields[4])
            children_count, children_count_ok := parse_non_negative(expression_fields[5])
            bindings_start, bindings_start_ok := parse_non_negative(expression_fields[6])
            bindings_count, bindings_count_ok := parse_non_negative(expression_fields[7])
            body, body_ok := strconv.parse_int(expression_fields[8])
            int_value, int_ok := strconv.parse_int(expression_fields[9])
            float_bits, float_ok := strconv.parse_i64(expression_fields[10])
            bool_value, bool_ok := strconv.parse_int(expression_fields[11])
            resolved_name, name_text_ok := decode_hex_text(expression_fields[12])
            scalar_signature, signature_text_ok := decode_hex_text(expression_fields[13])
            string_value, string_ok := decode_hex_text(expression_fields[14])
            if !kind_ok || !value_ok || !operand_ok || !children_start_ok ||
               !children_count_ok || !bindings_start_ok || !bindings_count_ok ||
               !body_ok || !int_ok || !float_ok || !bool_ok ||
               (bool_value != 0 && bool_value != 1) || !name_text_ok ||
               !signature_text_ok || !string_ok {
                delete(resolved_name)
                delete(scalar_signature)
                delete(string_value)
                procedure_delete(&procedure)
                program_delete(&program)
                return {}, false
            }
            total_text_bytes += len(resolved_name)+len(scalar_signature)+len(string_value)
            if total_text_bytes > MAX_TEXT_BYTES {
                delete(resolved_name)
                delete(scalar_signature)
                delete(string_value)
                procedure_delete(&procedure)
                program_delete(&program)
                return {}, false
            }
            append(&procedure.expressions, Expression{
                kind = kind,
                value_kind = value_kind,
                operand = operand,
                children_start = children_start,
                children_count = children_count,
                bindings_start = bindings_start,
                bindings_count = bindings_count,
                body = body,
                int_value = int_value,
                float_value = transmute(f64)float_bits,
                bool_value = bool_value == 1,
                resolved_name = resolved_name,
                scalar_signature = scalar_signature,
                string_value = string_value,
            })
        }
        for _ in 0..<child_count {
            child_fields := strings.split(records[cursor], ":", context.temp_allocator)
            cursor += 1
            child := 0
            child_ok := false
            if len(child_fields) == 2 && child_fields[0] == "c" {
                child, child_ok = strconv.parse_int(child_fields[1])
            }
            if !child_ok {
                procedure_delete(&procedure)
                program_delete(&program)
                return {}, false
            }
            append(&procedure.child_indices, child)
        }
        for _ in 0..<binding_count {
            binding_fields := strings.split(records[cursor], ":", context.temp_allocator)
            cursor += 1
            if len(binding_fields) != 5 || binding_fields[0] != "b" {
                procedure_delete(&procedure)
                program_delete(&program)
                return {}, false
            }
            slot, slot_ok := strconv.parse_int(binding_fields[1])
            value_expr, expression_ok := strconv.parse_int(binding_fields[2])
            value_kind, value_ok := value_kind_from_code(binding_fields[3])
            managed_cleanup, cleanup_ok := strconv.parse_int(binding_fields[4])
            if !slot_ok || !expression_ok || !value_ok || !cleanup_ok ||
               (managed_cleanup != 0 && managed_cleanup != 1) {
                procedure_delete(&procedure)
                program_delete(&program)
                return {}, false
            }
            append(&procedure.bindings, Binding{
                slot = slot,
                value_expr = value_expr,
                value_kind = value_kind,
                managed_cleanup = managed_cleanup == 1,
            })
        }
        if !procedure_valid(procedure) {
            procedure_delete(&procedure)
            program_delete(&program)
            return {}, false
        }
        append(&program.procedures, procedure)
    }
    if cursor != len(records) {
        program_delete(&program)
        return {}, false
    }
    return program, true
}
