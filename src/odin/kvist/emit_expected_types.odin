package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

emit_expr_with_owned_nested_temps :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if form_is_owned_constructor_result(form) || form_is_literal_constructor_call(form, e) ||
       form_is_transform_loop_call(form) {
        return emit_expr(e, form)
    }
    #partial switch form.kind {
    case .List, .Vector, .Brace, .Set:
        rewritten := clone_cst_form(form)
        defer delete_cst_form(&rewritten)

        start := 0
        if rewritten.kind == .List && len(rewritten.items) > 0 {
            if len(rewritten.items) == 2 &&
               (rewritten.items[1].kind == .Vector || rewritten.items[1].kind == .Brace || rewritten.items[1].kind == .Set) {
                if type_text, _, ok_type := parse_type_text(rewritten.items[0]); ok_type {
                    delete(type_text)
                    start = len(rewritten.items)
                } else {
                    start = 1
                }
            } else if rewritten.items[0].kind == .Symbol && rewritten.items[0].text == "make" {
                start = 2
            } else if rewritten.items[0].kind == .Symbol {
                start = 1
                switch rewritten.items[0].text {
                case "fn", "let", "if", "when", "cond", "case", "do", "for", "while", "type-case", "match",
                     "with-allocator", "with-temp-allocator":
                    start = len(rewritten.items)
                }
            } else {
                start = 1
            }
        }
        if start > len(rewritten.items) {
            start = len(rewritten.items)
        }

        for idx in start ..< len(rewritten.items) {
            item := rewritten.items[idx]
            if owned_direct_source_allowed_in_transform_source_slot(rewritten, idx, e) {
                err_source, bad_source := owned_transform_source_args_usage_error(item, e)
                if bad_source {
                    return "", err_source, false
                }
                continue
            }
            expected_type, has_expected_type := call_arg_expected_type(e, rewritten, idx)
            item_is_owned_native := form_produces_owned_value(item, e)
            if item.kind == .Vector || item.kind == .Brace || item.kind == .Set {
                // Bare collection syntax is contextual. A vector accepted as
                // a native array/struct argument is not an owned dynamic
                // allocation and must not be hoisted into a deletable temp.
                // When a foreign Odin procedure has no imported signature,
                // leave it inline so Odin can provide that context.
                item_is_owned_native =
                    (has_expected_type && type_text_is_owned_result(expected_type)) ||
                    (!has_expected_type &&
                     !(rewritten.kind == .List &&
                       len(rewritten.items) > 0 &&
                       rewritten.items[0].kind == .Symbol &&
                       head_is_imported_odin_call(e, rewritten.items[0].text)))
            }
            managed_ty, item_is_owned_managed := owned_managed_form_type(e, item)
            if has_expected_type &&
               form_produces_owned_managed_type(e, item, expected_type) {
                managed_ty = expected_type
                item_is_owned_managed = true
            }
            if !(item_is_owned_native ||
                 item_is_owned_managed ||
                 form_has_nested_owned_value(item, e)) {
                if has_expected_type {
                    delete(expected_type)
                }
                continue
            }

            value := ""
            err_value: Compile_Error
            ok_value := false
            if has_expected_type && type_text_is_managed_value(e, expected_type) {
                value, err_value, ok_value = emit_expr_for_expected_type(e, item, expected_type)
            } else {
                value, err_value, ok_value = emit_expr_with_owned_nested_temps(e, item)
            }
            if has_expected_type {
                delete(expected_type)
            }
            if !ok_value {
                return "", err_value, false
            }
            temp := thread_temp_name(e)
            emit_prefixed_expr(e, fmt.tprintf("%s := ", temp), value)
            transfers_owned := rewritten.kind == .List &&
                               ((form_transfers_owned_args(rewritten) && idx >= 2) ||
                                call_arg_transfers_owned_result(e, rewritten, idx))
            if item_is_owned_managed && !transfers_owned {
                emit_line(e, fmt.tprintf("defer %s", managed_destroy_value_text(e, managed_ty, temp)))
            } else if item_is_owned_native && !transfers_owned {
                emit_line(e, fmt.tprintf("defer delete(%s)", temp))
            }

            delete_cst_form(&rewritten.items[idx])
            rewritten.items[idx] = macro_symbol(temp, item.span)
        }

        return emit_expr(e, rewritten)
    }

    return emit_expr(e, form)
}

form_head_is_case :: proc(form: CST_Form) -> bool {
    return len(form.items) > 0 &&
           is_symbol(form.items[0], "type-case")
}

form_head_is_match :: proc(form: CST_Form) -> bool {
    return len(form.items) > 0 && is_symbol(form.items[0], "match")
}

form_head_is_do :: proc(form: CST_Form) -> bool {
    return len(form.items) > 0 && (is_symbol(form.items[0], "do") || is_symbol(form.items[0], "block"))
}

form_head_is_allocator_scope :: proc(form: CST_Form) -> bool {
    return len(form.items) > 0 &&
           (is_symbol(form.items[0], "with-allocator") ||
            is_symbol(form.items[0], "with-temp-allocator"))
}

form_head_is_as_thread :: proc(form: CST_Form) -> bool {
    return len(form.items) > 0 &&
           is_symbol(form.items[0], "as->")
}

form_head_is_statement_only :: proc(form: CST_Form) -> (string, bool) {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return "", false
    }
    head := form.items[0].text
    switch head {
    case "for", "while", "defer", "errdefer", "set!", "mut!", "inc!", "dec!", "toggle!", "negate!", "return", "kvist-intrinsic-breakpoint", "kvist-intrinsic-signal-condition", "kvist-intrinsic-use-value-restart", "kvist-intrinsic-restart-case", "kvist-intrinsic-condition-operation":
        return head, true
    }
    return "", false
}

proc_decl_type_text :: proc(proc_decl: ^Proc_Decl) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "proc(")
    for param, idx in proc_decl.params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        strings.write_string(&builder, param.ty)
    }
    strings.write_byte(&builder, ')')
    #partial switch proc_decl.returns.kind {
    case .Single:
        fmt.sbprintf(&builder, " -> %s", proc_decl.returns.single_ty)
    case .Named:
        strings.write_string(&builder, " -> [")
        for ret, idx in proc_decl.returns.named {
            if idx > 0 {
                strings.write_string(&builder, ", ")
            }
            if ret.name != "" {
                fmt.sbprintf(&builder, "%s: ", ret.name)
            }
            strings.write_string(&builder, ret.ty)
        }
        strings.write_byte(&builder, ']')
    case:
    }
    return strings.clone(strings.to_string(builder))
}

proc_literal_type_text :: proc(lit: Proc_Literal) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "proc(")
    for param, idx in lit.params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        strings.write_string(&builder, param.ty)
    }
    strings.write_byte(&builder, ')')
    #partial switch lit.returns.kind {
    case .Single:
        fmt.sbprintf(&builder, " -> %s", lit.returns.single_ty)
    case .Named:
        strings.write_string(&builder, " -> [")
        for ret, idx in lit.returns.named {
            if idx > 0 {
                strings.write_string(&builder, ", ")
            }
            if ret.name != "" {
                fmt.sbprintf(&builder, "%s: ", ret.name)
            }
            strings.write_string(&builder, ret.ty)
        }
        strings.write_byte(&builder, ']')
    case:
    }
    return strings.clone(strings.to_string(builder))
}

validate_proc_literal_for_expected_type :: proc(form: CST_Form, expected_type: string) -> (Compile_Error, bool) {
    if expected_type == "" || !type_text_is_proc(expected_type) || form.kind != .List || len(form.items) == 0 || !is_symbol(form.items[0], "fn") {
        return {}, false
    }
    if strings.contains(expected_type, "$") ||
       type_text_mentions_generic_param(expected_type, "T") ||
       type_text_mentions_generic_param(expected_type, "U") ||
       type_text_mentions_generic_param(expected_type, "K") ||
       type_text_mentions_generic_param(expected_type, "V") {
        return {}, false
    }
    parsed, err_parse, ok_parse := parse_proc_literal_form(form)
    if !ok_parse {
        return err_parse, true
    }
    expected_params, ok_expected_params := proc_type_param_types(expected_type)
    if !ok_expected_params {
        return {}, false
    }
    defer delete(expected_params)
    if len(expected_params) != len(parsed.params) {
        actual := proc_literal_type_text(parsed)
        defer delete(actual)
        return Compile_Error{message = fmt.tprintf("expected %s callback, got %s", expected_type, actual), span = form.span}, true
    }
    for expected_param, idx in expected_params {
        if strings.contains(expected_param, "$") {
            continue
        }
        if expected_param != parsed.params[idx].ty {
            actual := proc_literal_type_text(parsed)
            defer delete(actual)
            return Compile_Error{message = fmt.tprintf("expected %s callback, got %s", expected_type, actual), span = form.span}, true
        }
    }
    expected_return, expected_has_return := proc_type_single_return_type(expected_type)
    if expected_has_return {
        if parsed.returns.kind != .Single || (!strings.contains(expected_return, "$") && parsed.returns.single_ty != expected_return) {
            actual := proc_literal_type_text(parsed)
            defer delete(actual)
            return Compile_Error{message = fmt.tprintf("expected %s callback, got %s", expected_type, actual), span = form.span}, true
        }
    } else if parsed.returns.kind != .None {
        actual := proc_literal_type_text(parsed)
        defer delete(actual)
        return Compile_Error{message = fmt.tprintf("expected %s callback, got %s", expected_type, actual), span = form.span}, true
    }
    return {}, false
}

validate_known_proc_for_expected_type :: proc(e: ^Emitter, form: CST_Form, expected_type: string) -> (Compile_Error, bool) {
    if expected_type == "" || !type_text_is_proc(expected_type) || form.kind != .Symbol {
        return {}, false
    }
    if strings.contains(expected_type, "$") ||
       type_text_mentions_generic_param(expected_type, "T") ||
       type_text_mentions_generic_param(expected_type, "U") ||
       type_text_mentions_generic_param(expected_type, "K") ||
       type_text_mentions_generic_param(expected_type, "V") {
        return {}, false
    }
    _, proc_decl, ok_proc := resolve_proc_call_decl(e, form.text)
    if !ok_proc {
        return {}, false
    }
    expected_params, ok_expected_params := proc_type_param_types(expected_type)
    if !ok_expected_params {
        return {}, false
    }
    defer delete(expected_params)
    if len(expected_params) != len(proc_decl.params) {
        actual := proc_decl_type_text(proc_decl)
        defer delete(actual)
        return Compile_Error{message = fmt.tprintf("expected %s callback, got %s", expected_type, actual), span = form.span}, true
    }
    for expected_param, idx in expected_params {
        if strings.contains(expected_param, "$") {
            continue
        }
        if expected_param != proc_decl.params[idx].ty {
            actual := proc_decl_type_text(proc_decl)
            defer delete(actual)
            return Compile_Error{message = fmt.tprintf("expected %s callback, got %s", expected_type, actual), span = form.span}, true
        }
    }
    expected_return, expected_has_return := proc_type_single_return_type(expected_type)
    if expected_has_return {
        if proc_decl.returns.kind != .Single || (!strings.contains(expected_return, "$") && proc_decl.returns.single_ty != expected_return) {
            actual := proc_decl_type_text(proc_decl)
            defer delete(actual)
            return Compile_Error{message = fmt.tprintf("expected %s callback, got %s", expected_type, actual), span = form.span}, true
        }
    } else if proc_decl.returns.kind != .None {
        actual := proc_decl_type_text(proc_decl)
        defer delete(actual)
        return Compile_Error{message = fmt.tprintf("expected %s callback, got %s", expected_type, actual), span = form.span}, true
    }
    return {}, false
}

emit_expr_for_expected_type :: proc(e: ^Emitter, form: CST_Form, expected_type := "") -> (string, Compile_Error, bool) {
    if err_proc, bad_proc := validate_known_proc_for_expected_type(e, form, expected_type); bad_proc {
        return "", err_proc, false
    }
    if err_proc_literal, bad_proc_literal := validate_proc_literal_for_expected_type(form, expected_type); bad_proc_literal {
        return "", err_proc_literal, false
    }
    if expected_type != "" && form_is_expected_zero(form) {
        return zero_value_for_type_text(e, expected_type), {}, true
    }
    if expected_type != "" && form.kind == .List {
        if expected_item_ty, ok_expected_item_ty := dynamic_array_element_type(expected_type); ok_expected_item_ty {
            if source, ok_source_call := source_call_decl(e, form); ok_source_call {
                return emit_source_materialized_expr(e, form, source, expected_item_ty)
            }
        }
        if len(form.items) > 0 {
            if operator_text, err_operator, ok_operator :=
                emit_operator_expr(e, form, expected_type);
                ok_operator {
                return operator_text, {}, true
            } else if err_operator.message != "" {
                return "", err_operator, false
            }
        }
    }
    if form.kind == .List && len(form.items) > 0 && is_symbol(form.items[0], "if") {
        return emit_if_expr(e, form, expected_type)
    }
    if form.kind == .List && form_head_is_as_thread(form) {
        return emit_as_thread_expr(e, form, expected_type)
    }
    if form.kind == .List && len(form.items) > 0 && is_symbol(form.items[0], "let") {
        return emit_block_expr(e, form, expected_type)
    }
    if form.kind == .List && form_head_is_do(form) {
        return emit_block_expr(e, form, expected_type)
    }
    if form.kind == .List && form_head_is_allocator_scope(form) {
        return emit_block_expr(e, form, expected_type)
    }
    if form.kind == .List && form_head_is_case(form) {
        return emit_case_expr(e, form, expected_type)
    }
    if form.kind == .List && form_head_is_match(form) {
        return emit_block_expr(e, form, expected_type)
    }
    if type_text_is_managed_value(e, expected_type) {
        value, _, err_value, ok_value := emit_contextual_data_value(e, form)
        return value, err_value, ok_value
    }
    if expected_type != "" && !strings.contains(expected_type, "$") && (form.kind == .Vector || form.kind == .Brace || form.kind == .Set) {
        return emit_inferred_literal(e, form, expected_type)
    }
    text, err, ok := emit_expr(e, form)
    if !ok {
        return "", err, false
    }
    if expected_type != "" && type_text_is_slice(expected_type) {
        actual_type, ok_actual := obvious_form_type(e, form)
        if !ok_actual && form.kind == .List && len(form.items) >= 2 {
            parsed_type, _, ok_parsed_type := parse_type_text(form.items[0])
            if ok_parsed_type {
                actual_type = parsed_type
                ok_actual = true
            }
        }
        expected_elem, ok_expected_elem := collection_element_type(expected_type)
        actual_elem, ok_actual_elem := dynamic_array_element_type(actual_type)
        if ok_actual && ok_expected_elem && ok_actual_elem && expected_elem == actual_elem {
            return slice_all_expr_text(text), {}, true
        }
    }
    return text, {}, true
}

emit_source_materialized_expr :: proc(e: ^Emitter, source_form: CST_Form, source: ^Source_Decl, expected_item_ty := "") -> (string, Compile_Error, bool) {
    state_ty, err_state_ty, ok_state_ty := source_state_type(e, source)
    if !ok_state_ty {
        return "", err_state_ty, false
    }
    err_protocol, ok_protocol := validate_source_protocol(e, source, state_ty, source_form.span)
    if !ok_protocol {
        return "", err_protocol, false
    }
    item_ty := expected_item_ty
    if item_ty == "" {
        err_item_ty: Compile_Error
        ok_item_ty: bool
        item_ty, err_item_ty, ok_item_ty = source_call_item_type(e, source, source_form)
        if !ok_item_ty {
            return "", err_item_ty, false
        }
    }
    arg_texts, err_args, ok_args := source_call_arg_texts(e, source, source_form, item_ty)
    if !ok_args {
        return "", err_args, false
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    param_texts: [dynamic]string
    call_arg_texts: [dynamic]string
    call_texts: [dynamic]string
    defer delete(param_texts)
    defer delete(call_arg_texts)
    defer delete(call_texts)
    for param, idx in source.params {
        arg_name := fmt.tprintf("kvist_source_arg_%d", idx+1)
        param_ty := source_param_type_for_item(param.ty, source.item_ty, item_ty)
        append(&param_texts, fmt.tprintf("%s: %s", arg_name, param_ty))
        append(&call_arg_texts, arg_name)
    }
    for arg_text in arg_texts {
        append(&call_texts, arg_text)
    }
    param_list := strings.join(param_texts[:], ", ", context.allocator)
    defer delete(param_list)
    call_args := strings.join(call_texts[:], ", ", context.allocator)
    defer delete(call_args)
    open_call := source_call_text(e, source, call_arg_texts[:])
    output_ty := fmt.tprintf("[dynamic]%s", item_ty)

    fmt.sbprintf(&builder, "(proc(%s) -> %s %s\n", param_list, output_ty, "{")
    fmt.sbprintf(&builder, "    kvist_source := %s\n", open_call)
    if source.has_dispose {
        fmt.sbprintf(&builder, "    defer %s(&kvist_source)\n", source.dispose_name)
    }
    fmt.sbprintf(&builder, "    kvist_out := make(%s)\n", output_ty)
    strings.write_string(&builder, "    for {\n")
    fmt.sbprintf(&builder, "        kvist_item, kvist_source_ok := %s(&kvist_source)\n", source.next_name)
    strings.write_string(&builder, "        if !kvist_source_ok {\n")
    strings.write_string(&builder, "            break\n")
    strings.write_string(&builder, "        }\n")
    strings.write_string(&builder, "        append(&kvist_out, kvist_item)\n")
    strings.write_string(&builder, "    }\n")
    strings.write_string(&builder, "    return kvist_out\n")
    strings.write_string(&builder, "})")
    return fmt.tprintf("%s(%s)", strings.to_string(builder), call_args), {}, true
}

obvious_block_expr_type :: proc(e: ^Emitter, form: CST_Form) -> (string, bool) {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return "", false
    }

    switch form.items[0].text {
    case "let":
        if len(form.items) < 3 {
            return "", false
        }
        bindings, _, ok_bind := parse_let_bindings(form.items[1])
        if !ok_bind {
            return "", false
        }
        defer delete(bindings)

        push_local_type_scope(e)
        defer pop_local_type_scope(e)
        for binding in bindings {
            bind_obvious_binding_types(e, binding)
        }
        return obvious_form_type(e, form.items[len(form.items)-1])
    case "do", "block":
        if len(form.items) < 2 {
            return "", false
        }
        return obvious_form_type(e, form.items[len(form.items)-1])
    case "type-case":
        if len(form.items) < 5 || len(form.items)%2 == 0 {
            return "", false
        }
        result_ty := ""
        i := 2
        for i < len(form.items)-1 {
            ty, binding, ignored, _, ok_pattern := case_type_payload_pattern(form.items[i])
            if !ok_pattern {
                return "", false
            }
            push_local_type_scope(e)
            if !ignored {
                bind_local_type(e, binding, ty)
            }
            branch_ty, ok_branch_ty := obvious_form_type(e, form.items[i+1])
            pop_local_type_scope(e)
            if !ok_branch_ty || (result_ty != "" && branch_ty != result_ty) {
                return "", false
            }
            result_ty = branch_ty
            i += 2
        }
        default_ty, ok_default_ty := obvious_form_type(e, form.items[len(form.items)-1])
        if !ok_default_ty || (result_ty != "" && default_ty != result_ty) {
            return "", false
        }
        return default_ty, true
    case "match":
        if len(form.items) < 6 || (len(form.items)-2)%2 != 0 {
            return "", false
        }
        result_ty := ""
        for i := 2; i < len(form.items); i += 2 {
            names: [dynamic]string
            if _, ok_pattern := validate_match_pattern(form.items[i], &names); !ok_pattern {
                delete(names)
                return "", false
            }
            push_local_type_scope(e)
            for name in names {
                bind_local_type(e, name, "Data")
            }
            branch_ty, ok_branch_ty := obvious_form_type(e, form.items[i+1])
            pop_local_type_scope(e)
            delete(names)
            if !ok_branch_ty || (result_ty != "" && branch_ty != result_ty) {
                return "", false
            }
            result_ty = branch_ty
        }
        return result_ty, result_ty != ""
    }

    return "", false
}

emit_block_expr :: proc(e: ^Emitter, form: CST_Form, expected_type := "") -> (string, Compile_Error, bool) {
    ty := expected_type
    if ty == "" {
        if inferred_ty, ok_inferred_ty := obvious_block_expr_type(e, form); ok_inferred_ty {
            ty = inferred_ty
        } else {
            label := "block"
            if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
                label = display_head_name(form.items[0].text)
            }
            return "", Compile_Error{message = fmt.tprintf("%s expression needs an expected type; add a let binding type or use it where the type is known", label), span = form.span}, false
        }
    }
    body := []CST_Form{form}
    captures := collect_proc_literal_captures(e, body, nil)
    defer delete(captures)
    proc_text, err_proc, ok_proc := emit_proc_literal_text(e, captures[:], Return_Spec{kind = .Single, single_ty = ty}, body)
    if !ok_proc {
        return "", err_proc, false
    }
    args: [dynamic]string
    defer delete(args)
    for capture in captures {
        append(&args, capture.name)
    }
    return fmt.tprintf("(%s)(%s)", proc_text, strings.join(args[:], ", ", context.temp_allocator)), {}, true
}

make_list_form :: proc(items: []CST_Form, span: Span) -> CST_Form {
    built: [dynamic]CST_Form
    for item in items {
        append(&built, item)
    }
    return CST_Form{
        kind  = .List,
        items = built,
        span  = span,
    }
}

make_vector_form :: proc(items: []CST_Form, span: Span) -> CST_Form {
    built: [dynamic]CST_Form
    for item in items {
        append(&built, item)
    }
    return CST_Form{
        kind  = .Vector,
        items = built,
        span  = span,
    }
}

obvious_as_thread_type :: proc(e: ^Emitter, form: CST_Form) -> (string, bool) {
    if !form_head_is_as_thread(form) || len(form.items) < 4 || form.items[2].kind != .Symbol {
        return "", false
    }
    name := map_name(form.items[2].text)
    current_ty, ok_current_ty := obvious_form_type(e, form.items[1])
    if !ok_current_ty {
        return "", false
    }
    for step in form.items[3:] {
        push_local_type_scope(e)
        bind_local_type(e, name, current_ty)
        next_ty, ok_next_ty := obvious_form_type(e, step)
        pop_local_type_scope(e)
        if !ok_next_ty {
            return "", false
        }
        current_ty = next_ty
    }
    return current_ty, true
}

replace_symbol_in_form :: proc(form: CST_Form, from, to: string, shadowed := false) -> CST_Form {
    if target_form, fields, field_span, ok_place := field_path_place_parts(form); ok_place {
        replaced_target := replace_symbol_in_form(target_form, from, to, shadowed)
        if len(fields) == 0 {
            return replaced_target
        }
        current := replaced_target
        for field in fields {
            current = make_list_form({make_symbol_form("__kvist_field", field_span), current, make_symbol_form(field, field_span)}, field_span)
        }
        return current
    }

    #partial switch form.kind {
    case .Symbol:
        if !shadowed && map_name(form.text) == from {
            return make_symbol_form(to, form.span)
        }
        return form
    case .List:
        if len(form.items) > 0 && is_symbol(form.items[0], "fn") && len(form.items) > 1 && form.items[1].kind == .Vector {
            shadowed_body := shadowed
            params, _, ok_params := parse_param_vector(form.items[1])
            if ok_params {
                for param in params {
                    if param.name == from {
                        shadowed_body = true
                        break
                    }
                }
            }
            items: [dynamic]CST_Form
            append(&items, form.items[0])
            append(&items, form.items[1])
            for item in form.items[2:] {
                append(&items, replace_symbol_in_form(item, from, to, shadowed_body))
            }
            return make_list_form(items[:], form.span)
        }
        if len(form.items) > 0 && is_symbol(form.items[0], "let") && len(form.items) > 1 && form.items[1].kind == .Vector {
            items: [dynamic]CST_Form
            append(&items, form.items[0])
            bindings_items: [dynamic]CST_Form
            binding_shadowed := shadowed
            for i := 0; i < len(form.items[1].items); i += 2 {
                if i+1 >= len(form.items[1].items) {
                    append(&bindings_items, form.items[1].items[i])
                    break
                }
                name_form := form.items[1].items[i]
                value_form := form.items[1].items[i+1]
                append(&bindings_items, name_form)
                append(&bindings_items, replace_symbol_in_form(value_form, from, to, binding_shadowed))
                if name_form.kind == .Symbol && map_name(name_form.text) == from {
                    binding_shadowed = true
                }
            }
            append(&items, make_vector_form(bindings_items[:], form.items[1].span))
            for item in form.items[2:] {
                append(&items, replace_symbol_in_form(item, from, to, binding_shadowed))
            }
            return make_list_form(items[:], form.span)
        }
        if form_head_is_as_thread(form) && len(form.items) >= 3 && form.items[2].kind == .Symbol {
            items: [dynamic]CST_Form
            append(&items, form.items[0])
            append(&items, replace_symbol_in_form(form.items[1], from, to, shadowed))
            append(&items, form.items[2])
            nested_shadowed := shadowed || map_name(form.items[2].text) == from
            for item in form.items[3:] {
                append(&items, replace_symbol_in_form(item, from, to, nested_shadowed))
            }
            return make_list_form(items[:], form.span)
        }
        items: [dynamic]CST_Form
        for item in form.items {
            append(&items, replace_symbol_in_form(item, from, to, shadowed))
        }
        return make_list_form(items[:], form.span)
    case .Vector:
        items: [dynamic]CST_Form
        for item in form.items {
            append(&items, replace_symbol_in_form(item, from, to, shadowed))
        }
        return make_vector_form(items[:], form.span)
    case .Brace, .Set:
        items: [dynamic]CST_Form
        for item in form.items {
            append(&items, replace_symbol_in_form(item, from, to, shadowed))
        }
        return CST_Form{
            kind  = form.kind,
            items = items,
            span  = form.span,
            text  = form.text,
        }
    case:
        return form
    }
    return form
}

emit_as_thread_expr :: proc(e: ^Emitter, form: CST_Form, expected_type := "") -> (string, Compile_Error, bool) {
    if len(form.items) < 4 {
        return "", Compile_Error{message = "as-> expects an initial expression, a name, and at least one step", span = form.span}, false
    }
    if form.items[2].kind != .Symbol {
        return "", Compile_Error{message = "as-> expects a symbol binding name", span = form.items[2].span}, false
    }

    ty := expected_type
    if ty == "" {
        inferred_ty, ok_inferred_ty := obvious_as_thread_type(e, form)
        if !ok_inferred_ty {
            return "", Compile_Error{message = "as-> expression needs an expected type; add a let binding type or use it where the type is known", span = form.span}, false
        }
        ty = inferred_ty
    }

    from_name := map_name(form.items[2].text)
    bindings_items: [dynamic]CST_Form
    current_name := thread_temp_name(e)
    append(&bindings_items, make_symbol_form(current_name, form.span))
    append(&bindings_items, form.items[1])
    for i := 3; i < len(form.items); i += 1 {
        next_name := thread_temp_name(e)
        step_form := replace_symbol_in_form(form.items[i], from_name, current_name)
        append(&bindings_items, make_symbol_form(next_name, form.items[i].span))
        append(&bindings_items, step_form)
        current_name = next_name
    }
    bindings := make_vector_form(bindings_items[:], form.span)
    top := make_list_form({make_symbol_form("let", form.span), bindings, make_symbol_form(current_name, form.span)}, form.span)
    return emit_block_expr(e, top, ty)
}

expected_type_numeric_literal_kind :: proc(expected_type: string) -> (integer: bool, numeric: bool) {
    switch strings.trim_space(expected_type) {
    case "int", "i8", "i16", "i32", "i64", "i128",
         "uint", "u8", "u16", "u32", "u64", "u128",
         "uintptr", "rune", "byte":
        return true, true
    case "f16", "f32", "f64", "complex32", "complex64", "complex128":
        return false, true
    }
    return false, false
}

number_literal_type_for_expected_type :: proc(
    form: CST_Form,
    expected_type: string,
) -> (string, bool) {
    if form.kind != .Number || expected_type == "" {
        return "", false
    }
    integer_expected, numeric_expected :=
        expected_type_numeric_literal_kind(expected_type)
    if numeric_expected &&
       (!integer_expected || number_literal_type(form.text) == "int") {
        return expected_type, true
    }
    return "", false
}

form_accepts_expected_numeric_type :: proc(
    e: ^Emitter,
    form: CST_Form,
    expected_type: string,
) -> bool {
    if _, numeric_expected :=
        expected_type_numeric_literal_kind(expected_type);
        !numeric_expected {
        return false
    }
    if _, contextual :=
        number_literal_type_for_expected_type(form, expected_type);
        contextual {
        return true
    }
    if form.kind != .List || len(form.items) < 2 ||
       form.items[0].kind != .Symbol {
        return false
    }
    switch form.items[0].text {
    case "+", "-", "*", "/", "%", "%%", "min", "max":
    case:
        return false
    }
    for operand in form.items[1:] {
        if _, contextual :=
            number_literal_type_for_expected_type(operand, expected_type);
            contextual {
            continue
        }
        if operand_type, obvious := obvious_form_type(e, operand); obvious {
            if operand_type != expected_type {
                return false
            }
            continue
        }
        if operand.kind == .List && len(operand.items) > 0 &&
           operand.items[0].kind == .Symbol {
            switch operand.items[0].text {
            case "+", "-", "*", "/", "%", "%%", "min", "max":
                if !form_accepts_expected_numeric_type(
                    e,
                    operand,
                    expected_type,
                ) {
                    return false
                }
            case:
            }
        }
    }
    return true
}

branch_obvious_type_for_expected_type :: proc(
    e: ^Emitter,
    form: CST_Form,
    expected_type: string,
) -> (string, bool) {
    if form_accepts_expected_numeric_type(e, form, expected_type) {
        return expected_type, true
    }
    return obvious_form_type(e, form)
}

branch_type_mismatch_error :: proc(
    e: ^Emitter,
    lhs,
    rhs: CST_Form,
    expected_type,
    what: string,
    span: Span,
) -> (Compile_Error, bool) {
    lhs_ty, ok_lhs_ty :=
        branch_obvious_type_for_expected_type(e, lhs, expected_type)
    rhs_ty, ok_rhs_ty :=
        branch_obvious_type_for_expected_type(e, rhs, expected_type)
    if ok_lhs_ty && ok_rhs_ty && lhs_ty != rhs_ty {
        return Compile_Error{message = fmt.tprintf("%s branches have different obvious types: %s and %s", what, lhs_ty, rhs_ty), span = span}, true
    }
    return {}, false
}

emit_if_expr :: proc(e: ^Emitter, form: CST_Form, expected_type := "") -> (string, Compile_Error, bool) {
    if len(form.items) != 4 {
        return "", Compile_Error{message = "if expression expects test, then, and else", span = form.span}, false
    }
    if err_branch, bad_branch := branch_type_mismatch_error(
        e,
        form.items[2],
        form.items[3],
        expected_type,
        "if expression",
        form.span,
    ); bad_branch {
        return "", err_branch, false
    }
    branch_expected_type := expected_type
    if branch_expected_type == "" {
        if form_is_expected_zero(form.items[3]) {
            if inferred_ty, ok_inferred_ty := obvious_form_type(e, form.items[2]); ok_inferred_ty {
                branch_expected_type = inferred_ty
            }
        } else if form_is_expected_zero(form.items[2]) {
            if inferred_ty, ok_inferred_ty := obvious_form_type(e, form.items[3]); ok_inferred_ty {
                branch_expected_type = inferred_ty
            }
        } else {
            then_ty, ok_then_ty := obvious_form_type(e, form.items[2])
            else_ty, ok_else_ty := obvious_form_type(e, form.items[3])
            if ok_then_ty && ok_else_ty && then_ty == else_ty {
                branch_expected_type = then_ty
            }
        }
    }
    test, err_test, ok_test := emit_expr(e, form.items[1])
    if !ok_test {
        return "", err_test, false
    }
    then_value, err_then, ok_then := emit_expr_for_expected_type(e, form.items[2], branch_expected_type)
    if !ok_then {
        return "", err_then, false
    }
    else_value, err_else, ok_else := emit_expr_for_expected_type(e, form.items[3], branch_expected_type)
    if !ok_else {
        return "", err_else, false
    }
    if type_text_is_managed_value(e, branch_expected_type) {
        mark_data_type(e)
        if !form_produces_owned_managed_type(e, form.items[2], branch_expected_type) {
            then_value = emit_call_text("kvist_data_retain", []string{then_value})
        }
        if !form_produces_owned_managed_type(e, form.items[3], branch_expected_type) {
            else_value = emit_call_text("kvist_data_retain", []string{else_value})
        }
    }
    return fmt.tprintf("(%s if %s else %s)", then_value, test, else_value), {}, true
}

emit_case_expr :: proc(e: ^Emitter, form: CST_Form, expected_type := "") -> (string, Compile_Error, bool) {
    if len(form.items) < 5 {
        return "", Compile_Error{message = "type-case expression expects subject, type/body pairs, and default", span = form.span}, false
    }
    if len(form.items)%2 == 0 {
        return "", Compile_Error{message = "type-case expression expects type/body pairs followed by default", span = form.span}, false
    }
    i := 2
    for i < len(form.items)-1 {
        if form.items[i].kind != .List {
            return "", Compile_Error{message = "type-case expects (Type binding)", span = form.items[i].span}, false
        }
        i += 2
    }
    return emit_block_expr(e, form, expected_type)
}
