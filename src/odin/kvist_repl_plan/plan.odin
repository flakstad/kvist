package kvist_repl_plan

import "core:fmt"
import "core:strconv"
import "core:strings"

VERSION :: 9
MAX_INSTRUCTIONS :: 4096
MAX_TEXT_BYTES :: 1_048_576

Value_Kind :: enum u8 {
    Invalid,
    Bool,
    Int,
    F64,
    String,
    Data,
}

Result_Action :: enum u8 {
    Invalid,
    Preserve_History,
    Rotate_History,
}

Opcode :: enum u8 {
    Invalid,
    Push_Bool,
    Push_Int,
    Push_F64,
    Push_String,
    Invoke_Scalar_0,
    Invoke_Scalar_1,
    Invoke_Scalar_2,
    Invoke_Scalar_3,
    Invoke_Scalar_4,
    Load_Result,
    Store_Local,
    Load_Local,
    Add,
    Subtract,
    Multiply,
    Divide,
    Modulo,
    Not,
    Equal,
    Not_Equal,
    Less,
    Less_Equal,
    Greater,
    Greater_Equal,
    Jump,
    Branch_False,
    Short_False,
    Short_True,
}

Instruction :: struct {
    opcode:       Opcode,
    operand:      int,
    text_operand: string,
}

Execution_Plan :: struct {
    result_kind:   Value_Kind,
    result_action: Result_Action,
    instructions:  [dynamic]Instruction,
}

execution_plan_delete :: proc(plan: ^Execution_Plan) {
    if plan == nil {
        return
    }
    for &instruction in plan.instructions {
        delete(instruction.text_operand)
    }
    delete(plan.instructions)
    plan^ = {}
}

value_kind_code :: proc(kind: Value_Kind) -> string {
    switch kind {
    case .Bool: return "b"
    case .Int:  return "i"
    case .F64:  return "f"
    case .String: return "s"
    case .Data: return "d"
    case .Invalid:
    }
    return ""
}

value_kind_from_code :: proc(code: string) -> (Value_Kind, bool) {
    switch code {
    case "b": return .Bool, true
    case "i": return .Int, true
    case "f": return .F64, true
    case "s": return .String, true
    case "d": return .Data, true
    }
    return .Invalid, false
}

result_action_code :: proc(action: Result_Action) -> string {
    switch action {
    case .Preserve_History: return "p"
    case .Rotate_History:   return "r"
    case .Invalid:
    }
    return ""
}

result_action_from_code :: proc(code: string) -> (Result_Action, bool) {
    switch code {
    case "p": return .Preserve_History, true
    case "r": return .Rotate_History, true
    }
    return .Invalid, false
}

opcode_code :: proc(opcode: Opcode) -> string {
    switch opcode {
    case .Push_Bool:     return "b"
    case .Push_Int:      return "i"
    case .Push_F64:      return "f"
    case .Push_String:   return "s"
    case .Invoke_Scalar_0: return "c0"
    case .Invoke_Scalar_1: return "c1"
    case .Invoke_Scalar_2: return "c2"
    case .Invoke_Scalar_3: return "c3"
    case .Invoke_Scalar_4: return "c4"
    case .Load_Result:   return "r"
    case .Store_Local:   return "sl"
    case .Load_Local:    return "ll"
    case .Add:           return "add"
    case .Subtract:      return "sub"
    case .Multiply:      return "mul"
    case .Divide:        return "div"
    case .Modulo:        return "mod"
    case .Not:           return "not"
    case .Equal:         return "eq"
    case .Not_Equal:     return "ne"
    case .Less:          return "lt"
    case .Less_Equal:    return "le"
    case .Greater:       return "gt"
    case .Greater_Equal: return "ge"
    case .Jump:          return "jmp"
    case .Branch_False:  return "jf"
    case .Short_False:   return "sf"
    case .Short_True:    return "st"
    case .Invalid:
    }
    return ""
}

opcode_from_code :: proc(code: string) -> (Opcode, bool) {
    switch code {
    case "b":   return .Push_Bool, true
    case "i":   return .Push_Int, true
    case "f":   return .Push_F64, true
    case "s":   return .Push_String, true
    case "c0":  return .Invoke_Scalar_0, true
    case "c1":  return .Invoke_Scalar_1, true
    case "c2":  return .Invoke_Scalar_2, true
    case "c3":  return .Invoke_Scalar_3, true
    case "c4":  return .Invoke_Scalar_4, true
    case "r":   return .Load_Result, true
    case "sl":  return .Store_Local, true
    case "ll":  return .Load_Local, true
    case "add": return .Add, true
    case "sub": return .Subtract, true
    case "mul": return .Multiply, true
    case "div": return .Divide, true
    case "mod": return .Modulo, true
    case "not": return .Not, true
    case "eq":  return .Equal, true
    case "ne":  return .Not_Equal, true
    case "lt":  return .Less, true
    case "le":  return .Less_Equal, true
    case "gt":  return .Greater, true
    case "ge":  return .Greater_Equal, true
    case "jmp": return .Jump, true
    case "jf":  return .Branch_False, true
    case "sf":  return .Short_False, true
    case "st":  return .Short_True, true
    }
    return .Invalid, false
}

opcode_has_operand :: proc(opcode: Opcode) -> bool {
    switch opcode {
    case .Push_Bool, .Push_Int, .Push_F64, .Load_Result,
         .Store_Local, .Load_Local,
         .Add, .Subtract, .Multiply, .Divide, .Modulo,
         .Jump, .Branch_False, .Short_False, .Short_True:
        return true
    case .Push_String,
         .Invoke_Scalar_0, .Invoke_Scalar_1, .Invoke_Scalar_2,
         .Invoke_Scalar_3, .Invoke_Scalar_4,
         .Not, .Equal, .Not_Equal,
         .Less, .Less_Equal, .Greater, .Greater_Equal,
         .Invalid:
        return false
    }
    return false
}

opcode_has_text_operand :: proc(opcode: Opcode) -> bool {
    #partial switch opcode {
    case .Push_String,
         .Invoke_Scalar_0, .Invoke_Scalar_1, .Invoke_Scalar_2,
         .Invoke_Scalar_3, .Invoke_Scalar_4:
        return true
    case:
        return false
    }
}

opcode_scalar_invoke_arity :: proc(opcode: Opcode) -> (int, bool) {
    #partial switch opcode {
    case .Invoke_Scalar_0: return 0, true
    case .Invoke_Scalar_1: return 1, true
    case .Invoke_Scalar_2: return 2, true
    case .Invoke_Scalar_3: return 3, true
    case .Invoke_Scalar_4: return 4, true
    case:
        return 0, false
    }
}

scalar_invoke_target_valid :: proc(target: string) -> bool {
    separator := -1
    for ch, index in target {
        if ch == 0 {
            if separator >= 0 {
                return false
            }
            separator = index
        }
    }
    return separator > 0 && separator+1 < len(target)
}

hex_digit_value :: proc(ch: u8) -> (u8, bool) {
    switch ch {
    case '0' ..= '9': return ch-'0', true
    case 'a' ..= 'f': return ch-'a'+10, true
    case 'A' ..= 'F': return ch-'A'+10, true
    }
    return 0, false
}

write_hex_text :: proc(builder: ^strings.Builder, text: string) {
    digits := "0123456789abcdef"
    for index := 0; index < len(text); index += 1 {
        ch := text[index]
        strings.write_byte(builder, digits[ch >> 4])
        strings.write_byte(builder, digits[ch & 0xf])
    }
}

decode_hex_text :: proc(encoded: string) -> (string, bool) {
    if len(encoded)%2 != 0 || len(encoded)/2 > MAX_TEXT_BYTES {
        return "", false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for index := 0; index < len(encoded); index += 2 {
        high, high_ok := hex_digit_value(encoded[index])
        low, low_ok := hex_digit_value(encoded[index+1])
        if !high_ok || !low_ok {
            return "", false
        }
        strings.write_byte(&builder, high << 4 | low)
    }
    return strings.clone(strings.to_string(builder)), true
}

execution_plan_encode :: proc(plan: Execution_Plan) -> (string, bool) {
    result_code := value_kind_code(plan.result_kind)
    action_code := result_action_code(plan.result_action)
    if result_code == "" || action_code == "" ||
       len(plan.instructions) == 0 ||
       len(plan.instructions) > MAX_INSTRUCTIONS {
        return "", false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    fmt.sbprintf(&builder, "%d|%s|%s", VERSION, result_code, action_code)
    text_bytes := 0
    for instruction in plan.instructions {
        code := opcode_code(instruction.opcode)
        if code == "" ||
           (opcode_has_text_operand(instruction.opcode) &&
            instruction.operand != 0) ||
           (!opcode_has_text_operand(instruction.opcode) &&
            instruction.text_operand != "") {
            return "", false
        }
        strings.write_byte(&builder, '|')
        strings.write_string(&builder, code)
        if opcode_has_text_operand(instruction.opcode) {
            if len(instruction.text_operand) > MAX_TEXT_BYTES-text_bytes {
                return "", false
            }
            text_bytes += len(instruction.text_operand)
            strings.write_byte(&builder, ':')
            write_hex_text(&builder, instruction.text_operand)
        } else if opcode_has_operand(instruction.opcode) {
            fmt.sbprintf(&builder, ":%d", instruction.operand)
        }
    }
    return strings.clone(strings.to_string(builder)), true
}

execution_plan_decode :: proc(encoded: string) -> (Execution_Plan, bool) {
    plan := Execution_Plan{}
    fields := strings.split(encoded, "|", context.temp_allocator)
    if len(fields) < 4 || len(fields)-3 > MAX_INSTRUCTIONS {
        return plan, false
    }
    version, version_ok := strconv.parse_int(fields[0])
    if !version_ok || version != VERSION {
        return plan, false
    }
    result_kind, result_ok := value_kind_from_code(fields[1])
    if !result_ok {
        return plan, false
    }
    result_action, action_ok := result_action_from_code(fields[2])
    if !action_ok {
        return plan, false
    }
    plan.result_kind = result_kind
    plan.result_action = result_action
    text_bytes := 0
    for field in fields[3:] {
        code := field
        operand_text := ""
        has_operand := false
        if separator := strings.index(field, ":"); separator >= 0 {
            code = field[:separator]
            operand_text = field[separator+1:]
            has_operand = true
        }
        opcode, opcode_ok := opcode_from_code(code)
        if !opcode_ok ||
           (opcode_has_operand(opcode) ||
            opcode_has_text_operand(opcode)) != has_operand {
            execution_plan_delete(&plan)
            return {}, false
        }
        operand := 0
        text_operand := ""
        if opcode_has_text_operand(opcode) {
            decoded_text, text_ok := decode_hex_text(operand_text)
            if !text_ok || len(decoded_text) > MAX_TEXT_BYTES-text_bytes {
                delete(decoded_text)
                execution_plan_delete(&plan)
                return {}, false
            }
            text_bytes += len(decoded_text)
            text_operand = decoded_text
        } else if has_operand {
            parsed_operand, operand_ok := strconv.parse_int(operand_text)
            if !operand_ok {
                execution_plan_delete(&plan)
                return {}, false
            }
            operand = parsed_operand
        }
        append(&plan.instructions, Instruction{
            opcode = opcode,
            operand = operand,
            text_operand = text_operand,
        })
    }
    for instruction, index in plan.instructions {
        switch instruction.opcode {
        case .Push_Bool:
            if instruction.operand != 0 && instruction.operand != 1 {
                execution_plan_delete(&plan)
                return {}, false
            }
        case .Invoke_Scalar_0, .Invoke_Scalar_1, .Invoke_Scalar_2,
             .Invoke_Scalar_3, .Invoke_Scalar_4:
            if !scalar_invoke_target_valid(instruction.text_operand) {
                execution_plan_delete(&plan)
                return {}, false
            }
        case .Load_Result:
            if instruction.operand < 0 || instruction.operand >= 3 {
                execution_plan_delete(&plan)
                return {}, false
            }
        case .Store_Local, .Load_Local:
            if instruction.operand < 0 ||
               instruction.operand >= MAX_INSTRUCTIONS {
                execution_plan_delete(&plan)
                return {}, false
            }
        case .Add, .Multiply, .Divide, .Modulo:
            if instruction.operand < 2 {
                execution_plan_delete(&plan)
                return {}, false
            }
        case .Subtract:
            if instruction.operand < 1 {
                execution_plan_delete(&plan)
                return {}, false
            }
        case .Jump, .Branch_False, .Short_False, .Short_True:
            if instruction.operand <= index ||
               instruction.operand > len(plan.instructions) {
                execution_plan_delete(&plan)
                return {}, false
            }
        case .Push_Int, .Push_F64, .Push_String, .Not, .Equal, .Not_Equal,
             .Less, .Less_Equal, .Greater, .Greater_Equal,
             .Invalid:
        }
    }
    return plan, true
}
