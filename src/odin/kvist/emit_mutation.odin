package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

comparison_odin_op :: proc(op: string) -> string {
    if op == "=" {
        return "=="
    }
    return op
}

comparison_supports_nary :: proc(op: string) -> bool {
    return op == "=" || op == "==" || op == "<" || op == "<=" || op == ">" || op == ">="
}

comparison_form_wants_context_type :: proc(form: CST_Form) -> bool {
    if form.kind == .Number || form.kind == .Vector || form.kind == .Brace || form.kind == .Set {
        return true
    }
    if form.kind == .Symbol && len(form.text) > 1 && form.text[0] == '.' {
        return true
    }
    return false
}

comparison_context_type :: proc(e: ^Emitter, operands: []CST_Form, idx: int) -> string {
    if !comparison_form_wants_context_type(operands[idx]) {
        return ""
    }

    distance := 1
    for idx-distance >= 0 || idx+distance < len(operands) {
        if idx-distance >= 0 {
            if ty, ok := obvious_form_type(e, operands[idx-distance]); ok {
                return ty
            }
        }
        if idx+distance < len(operands) {
            if ty, ok := obvious_form_type(e, operands[idx+distance]); ok {
                return ty
            }
        }
        distance += 1
    }
    return ""
}

emit_nary_comparison_expr :: proc(e: ^Emitter, op: string, operands: []CST_Form, span: Span) -> (string, Compile_Error, bool) {
    if len(operands) < 2 {
        return "", Compile_Error{message = fmt.tprintf("%s expects at least two arguments", op), span = span}, false
    }
    if op == "!=" && len(operands) != 2 {
        return "", Compile_Error{message = "!= expects exactly two arguments", span = span}, false
    }
    if len(operands) == 2 {
        lhs_expected := ""
        rhs_expected := ""
        if ty, ok := obvious_form_type(e, operands[0]); ok {
            rhs_expected = ty
        }
        if ty, ok := obvious_form_type(e, operands[1]); ok {
            lhs_expected = ty
        }
        lhs, err_lhs, ok_lhs := emit_expr_for_expected_type(e, operands[0], lhs_expected)
        if !ok_lhs {
            return "", err_lhs, false
        }
        rhs, err_rhs, ok_rhs := emit_expr_for_expected_type(e, operands[1], rhs_expected)
        if !ok_rhs {
            return "", err_rhs, false
        }
        if (lhs_expected == "Data" || rhs_expected == "Data") && (op == "=" || op == "==" || op == "!=") {
            mark_data_type(e)
            equal := emit_call_text("kvist_data_equal", []string{lhs, rhs})
            if op == "!=" {
                return fmt.tprintf("!(%s)", equal), {}, true
            }
            return equal, {}, true
        }
        return fmt.tprintf("(%s) %s (%s)", lhs, comparison_odin_op(op), rhs), {}, true
    }
    if !comparison_supports_nary(op) {
        return "", Compile_Error{message = fmt.tprintf("%s expects exactly two arguments", op), span = span}, false
    }

    names: [dynamic]string
    defer delete(names)

    e.temp_counter += 1
    proc_id := e.temp_counter
    for idx in 0..<len(operands) {
        append(&names, fmt.tprintf("kvist_cmp_%d_%d", proc_id, idx))
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "(proc() -> bool {\n")
    for operand, idx in operands {
        expected_type := comparison_context_type(e, operands, idx)
        value, err_value, ok_value := emit_expr_for_expected_type(e, operand, expected_type)
        if !ok_value {
            return "", err_value, false
        }
        if expected_type != "" {
            fmt.sbprintf(&builder, "    %s: %s = %s\n", names[idx], expected_type, value)
        } else {
            fmt.sbprintf(&builder, "    %s := %s\n", names[idx], value)
        }
    }
    strings.write_string(&builder, "    return ")
    odin_op := comparison_odin_op(op)
    for idx in 0..<len(operands)-1 {
        if idx > 0 {
            strings.write_string(&builder, " && ")
        }
        fmt.sbprintf(&builder, "(%s) %s (%s)", names[idx], odin_op, names[idx+1])
    }
    strings.write_string(&builder, "\n})()")
    return strings.clone(strings.to_string(builder)), {}, true
}

compound_assignment_operator :: proc(head: string) -> (string, bool) {
    switch head {
    case "+=":
        return "+=", true
    case "-=":
        return "-=", true
    case "*=":
        return "*=", true
    case "/=":
        return "/=", true
    case "%=":
        return "%=", true
    case "&=":
        return "&=", true
    case "|=":
        return "|=", true
    case "^=":
        return "^=", true
    }
    return "", false
}

form_is_assignable_place :: proc(form: CST_Form) -> bool {
    if form.kind == .Symbol {
        return true
    }
    if form.kind != .List || len(form.items) == 0 {
        return false
    }
    head := form.items[0]
    if head.kind == .Keyword {
        return false
    }
    if head.kind != .Symbol {
        return false
    }
    switch head.text {
    case "deref", "^":
        return len(form.items) == 2
    case "__kvist_field":
        return len(form.items) == 3
    case "__kvist_index":
        return len(form.items) == 3
    case "odin-get":
        return len(form.items) == 3
    }
    return false
}

form_is_omitted_slice_bound :: proc(form: CST_Form) -> bool {
    return form.kind == .Symbol && form.text == "__kvist_omitted"
}

emit_compound_assignment_stmt :: proc(e: ^Emitter, form: CST_Form, op: string) -> (Compile_Error, bool) {
    if len(form.items) != 3 {
        return Compile_Error{message = fmt.tprintf("%s expects place and value", op), span = form.span}, false
    }
    if !form_is_assignable_place(form.items[1]) {
        return Compile_Error{message = fmt.tprintf("%s expects an assignable place", op), span = form.items[1].span}, false
    }
    lhs, err_lhs, ok_lhs := emit_expr(e, form.items[1])
    if !ok_lhs {
        return err_lhs, false
    }
    err_owned, bad_owned := owned_result_usage_error(form.items[2], true, e)
    if bad_owned {
        return err_owned, false
    }
    rhs, err_rhs, ok_rhs := emit_expr(e, form.items[2])
    if !ok_rhs {
        return err_rhs, false
    }
    emit_indent(e)
    strings.write_string(&e.builder, lhs)
    record_current_line_fragment_map(e, 0, lhs, form.items[1].span)
    strings.write_string(&e.builder, " ")
    strings.write_string(&e.builder, op)
    strings.write_string(&e.builder, " ")
    strings.write_string(&e.builder, rhs)
    record_current_line_fragment_map(e, len(lhs) + len(" ") + len(op) + len(" "), rhs, form.items[2].span)
    emit_raw_newline(e)
    return {}, true
}

emit_mut_bang_stmt :: proc(e: ^Emitter, form: CST_Form) -> (Compile_Error, bool) {
    if len(form.items) != 4 {
        return Compile_Error{message = "mut! expects place, operator, and value", span = form.span}, false
    }
    op_form := form.items[2]
    if op_form.kind != .Symbol {
        return Compile_Error{message = "mut! expects an assignment operator symbol", span = op_form.span}, false
    }
    if op_form.text == "=" {
        return Compile_Error{message = "mut! does not support =; use set! for plain assignment", span = op_form.span}, false
    }
    op, ok_op := compound_assignment_operator(op_form.text)
    if !ok_op {
        return Compile_Error{message = "mut! expects a compound assignment operator", span = op_form.span}, false
    }
    if !form_is_assignable_place(form.items[1]) {
        return Compile_Error{message = "mut! expects an assignable place", span = form.items[1].span}, false
    }
    if err_immutable, immutable := immutable_def_mutation_error(e, form.items[1]); immutable {
        return err_immutable, false
    }
    lhs, err_lhs, ok_lhs := emit_expr(e, form.items[1])
    if !ok_lhs {
        return err_lhs, false
    }
    err_owned, bad_owned := owned_result_usage_error(form.items[3], true, e)
    if bad_owned {
        return err_owned, false
    }
    rhs, err_rhs, ok_rhs := emit_expr(e, form.items[3])
    if !ok_rhs {
        return err_rhs, false
    }
    emit_indent(e)
    strings.write_string(&e.builder, lhs)
    record_current_line_fragment_map(e, 0, lhs, form.items[1].span)
    strings.write_string(&e.builder, " ")
    strings.write_string(&e.builder, op)
    strings.write_string(&e.builder, " ")
    strings.write_string(&e.builder, rhs)
    record_current_line_fragment_map(e, len(lhs) + len(" ") + len(op) + len(" "), rhs, form.items[3].span)
    emit_raw_newline(e)
    return {}, true
}

emit_unary_mutation_stmt :: proc(e: ^Emitter, form: CST_Form, head: string) -> (Compile_Error, bool) {
    if len(form.items) != 2 {
        return Compile_Error{message = fmt.tprintf("%s expects one place", head), span = form.span}, false
    }
    if !form_is_assignable_place(form.items[1]) {
        return Compile_Error{message = fmt.tprintf("%s expects an assignable place", head), span = form.items[1].span}, false
    }
    if err_immutable, immutable := immutable_def_mutation_error(e, form.items[1]); immutable {
        return err_immutable, false
    }
    lhs, err_lhs, ok_lhs := emit_expr(e, form.items[1])
    if !ok_lhs {
        return err_lhs, false
    }

    emit_indent(e)
    strings.write_string(&e.builder, lhs)
    record_current_line_fragment_map(e, 0, lhs, form.items[1].span)
    switch head {
    case "inc!":
        strings.write_string(&e.builder, " += 1")
    case "dec!":
        strings.write_string(&e.builder, " -= 1")
    case "toggle!":
        strings.write_string(&e.builder, " = !(")
        strings.write_string(&e.builder, lhs)
        strings.write_string(&e.builder, ")")
    case "negate!":
        strings.write_string(&e.builder, " = -(")
        strings.write_string(&e.builder, lhs)
        strings.write_string(&e.builder, ")")
    }
    emit_raw_newline(e)
    return {}, true
}

head_is_core_assoc :: proc(head: string) -> bool {
    return head == "copy-with"
}

head_is_core_update :: proc(head: string) -> bool {
    return head == "copy-update"
}

head_is_core_dissoc :: proc(head: string) -> bool {
    return head == "copy-dissoc" || head == "copy-dissoc-in"
}

 thread_temp_name :: proc(e: ^Emitter) -> string {
    e.temp_counter += 1
    return fmt.tprintf("kvist_thread_%d", e.temp_counter)
}

eval_temp_name :: proc(e: ^Emitter) -> string {
    e.temp_counter += 1
    return fmt.tprintf("kvist_eval_%d", e.temp_counter)
}

 display_head_name :: proc(head_name: string) -> string {
    head := source_package_surface_head(head_name)
    slash := strings.index(head, "/")
    if slash > 0 {
        return fmt.tprintf("%s.%s", head[:slash], head[slash+1:])
    }
    return head
}

source_package_surface_head :: proc(head_name: string) -> string {
    dot := strings.index(head_name, ".")
    slash := strings.index(head_name, "/")
    if dot > 0 && (slash < 0 || dot < slash) {
        return fmt.tprintf("%s/%s", head_name[:dot], head_name[dot+1:])
    }
    sep := strings.index(head_name, "__")
    if sep > 0 {
        pkg := head_name[:sep]
        member := head_name[sep+2:]
        if source_package_prefix_text(pkg) {
            if strings.has_suffix(member, "_impl") {
                member = member[:len(member)-len("_impl")]
            } else if strings.has_suffix(member, "-impl") {
                member = member[:len(member)-len("-impl")]
            }
            surface_member := source_package_surface_member_name(member)
            defer delete(surface_member)
            return fmt.tprintf("%s/%s", pkg, surface_member)
        }
    }
    return head_name
}

source_package_surface_member_name :: proc(member: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    i := 0
    for i < len(member) {
        if strings.has_prefix(member[i:], "_bang") {
            strings.write_byte(&builder, '!')
            i += len("_bang")
        } else if strings.has_prefix(member[i:], "-bang") {
            strings.write_byte(&builder, '!')
            i += len("-bang")
        } else if strings.has_prefix(member[i:], "_p") {
            strings.write_byte(&builder, '?')
            i += len("_p")
        } else if member[i] == '_' {
            strings.write_byte(&builder, '-')
            i += 1
        } else {
            strings.write_byte(&builder, member[i])
            i += 1
        }
    }
    return strings.clone(strings.to_string(builder))
}

source_package_prefix_text :: proc(pkg: string) -> bool {
    if len(pkg) == 0 {
        return false
    }
    for ch in pkg {
        if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '-' {
            continue
        }
        return false
    }
    return true
}
