// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

emit_return_spec :: proc(e: ^Emitter, returns: Return_Spec) {
    #partial switch returns.kind {
    case .None:
        return
    case .Single:
        fmt.sbprintf(&e.builder, " -> %s", returns.single_ty)
    case .Named:
        strings.write_string(&e.builder, " -> (")
        for field, idx in returns.named {
            if idx > 0 {
                strings.write_string(&e.builder, ", ")
            }
            fmt.sbprintf(&e.builder, "%s: %s", field.name, field.ty)
        }
        strings.write_byte(&e.builder, ')')
    }
}

emit_proc_directives :: proc(e: ^Emitter, directives: []string) {
    for directive in directives {
        strings.write_string(&e.builder, directive)
        strings.write_byte(&e.builder, ' ')
    }
}

emit_proc_suffix_directives :: proc(e: ^Emitter, directives: []string) {
    for directive in directives {
        strings.write_byte(&e.builder, ' ')
        strings.write_string(&e.builder, directive)
    }
}

emit_proc_where_constraints :: proc(e: ^Emitter, constraints: []CST_Form) -> (Compile_Error, bool) {
    if len(constraints) == 0 {
        return {}, true
    }
    strings.write_string(&e.builder, " where ")
    for constraint, idx in constraints {
        if idx > 0 {
            strings.write_string(&e.builder, " && ")
        }
        text, err_text, ok_text := emit_expr(e, constraint)
        if !ok_text {
            return err_text, false
        }
        strings.write_string(&e.builder, text)
    }
    return {}, true
}

known_decl_type_with_suffix :: proc(e: ^Emitter, owner, token: string) -> (string, bool) {
    suffix := fmt.tprintf("__%s", token)
    selected := ""
    for decl in e.decls {
        name := ""
        #partial switch decl.kind {
        case .Struct:
            name = decl.struct_decl.name
        case .Union:
            name = decl.union_decl.name
        case .Enum:
            name = decl.enum_decl.name
        }
        if name == "" ||
           !strings.has_suffix(name, suffix) ||
           len(name) <= len(suffix) {
            continue
        }
        prefix := name[:len(name)-len(suffix)]
        if !strings.has_prefix(owner, prefix) ||
           len(owner) <= len(prefix)+1 ||
           owner[len(prefix)] != '_' ||
           owner[len(prefix)+1] != '_' {
            continue
        }
        if selected != "" && selected != name {
            return "", false
        }
        selected = name
    }
    if selected == "" {
        return "", false
    }
    return strings.clone(selected), true
}

type_identifier_start :: proc(ch: u8) -> bool {
    return (ch >= 'A' && ch <= 'Z') ||
           (ch >= 'a' && ch <= 'z') ||
           ch == '_'
}

type_identifier_continue :: proc(ch: u8) -> bool {
    return type_identifier_start(ch) || (ch >= '0' && ch <= '9')
}

qualify_flattened_decl_type :: proc(e: ^Emitter, owner, text: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    i := 0
    for i < len(text) {
        if !type_identifier_start(text[i]) {
            strings.write_byte(&builder, text[i])
            i += 1
            continue
        }
        start := i
        i += 1
        for i < len(text) && type_identifier_continue(text[i]) {
            i += 1
        }
        token := text[start:i]
        if qualified, ok_qualified := known_decl_type_with_suffix(e, owner, token); ok_qualified {
            strings.write_string(&builder, qualified)
            delete(qualified)
        } else {
            strings.write_string(&builder, token)
        }
    }
    return strings.clone(strings.to_string(builder))
}

emit_decl :: proc(e: ^Emitter, decl: IR_Decl) -> (Compile_Error, bool) {
    mark_decl_keyword_usage(e, decl)
    for line in decl.doc_lines {
        emit_line(e, line)
    }
    has_pending_proc_directives := len(e.pending_prefix_directives) > 0 || len(e.pending_suffix_directives) > 0
    if has_pending_proc_directives && decl.kind != .Proc && decl.kind != .Raw {
        return Compile_Error{message = "procedure directive must be followed by a proc declaration", span = decl.span}, false
    }
    #partial switch decl.kind {
    case .Package:
        emit_line(e, fmt.tprintf("package %s", decl.package_name))
    case .Import:
        if decl.import_decl.has_refer {
            return Compile_Error{message = "import :refer is only supported for Kvist source package imports", span = decl.span}, false
        }
        if decl_is_kvist_import(decl) {
            return Compile_Error{}, true
        }
        if decl.import_decl.has_alias {
            emit_line(e, fmt.tprintf("import %s %s", decl.import_decl.alias, decl.import_decl.path))
        } else {
            emit_line(e, fmt.tprintf("import %s", decl.import_decl.path))
        }
    case .Const:
        if decl.const_decl.is_overload {
            emit_indent(e)
            strings.write_string(&e.builder, decl.const_decl.name)
            strings.write_string(&e.builder, " :: proc{")
            for member, idx in decl.const_decl.overload_members {
                if idx > 0 {
                    strings.write_string(&e.builder, ", ")
                }
                strings.write_string(&e.builder, member)
            }
            strings.write_string(&e.builder, "}")
            emit_raw_newline(e)
            return Compile_Error{}, true
        }
        if decl.const_decl.is_type_alias {
            emit_line(e, fmt.tprintf("%s :: %s", decl.const_decl.name, decl.const_decl.type_alias))
            return Compile_Error{}, true
        }
        if decl.const_decl.value.kind == .List &&
           len(decl.const_decl.value.items) == 2 &&
           is_symbol(decl.const_decl.value.items[0], "quote") {
            value, err_value, ok_value := emit_data_value_literal(e, decl.const_decl.value.items[1])
            if !ok_value {
                return err_value, false
            }
            emit_line(e, fmt.tprintf("%s: Data = %s", decl.const_decl.name, value))
            return Compile_Error{}, true
        }
        if decl.const_decl.init_kind == .Runtime {
            emit_line(e, fmt.tprintf("%s: %s", decl.const_decl.name, decl.const_decl.ty))
            return Compile_Error{}, true
        }
        expected_type := ""
        if decl.const_decl.has_ty {
            expected_type = decl.const_decl.ty
        }
        value, err_value, ok_value := emit_expr_for_expected_type(e, decl.const_decl.value, expected_type)
        if !ok_value {
            return err_value, false
        }
        if decl.const_decl.has_ty {
            emit_line(e, fmt.tprintf("%s: %s : %s", decl.const_decl.name, decl.const_decl.ty, value))
        } else {
            emit_line(e, fmt.tprintf("%s :: %s", decl.const_decl.name, value))
        }
    case .Var:
        if !decl.var_decl.has_value {
            if !decl.var_decl.has_ty {
                return Compile_Error{message = "defvar without a value requires an explicit type", span = decl.span}, false
            }
            emit_line(e, fmt.tprintf("%s: %s", decl.var_decl.name, decl.var_decl.ty))
            return {}, true
        }
        expected_type := ""
        if decl.var_decl.has_ty {
            expected_type = decl.var_decl.ty
        }
        value, err_value, ok_value := emit_expr_for_expected_type(e, decl.var_decl.value, expected_type)
        if !ok_value {
            return err_value, false
        }
        if decl.var_decl.has_ty {
            emit_line(e, fmt.tprintf("%s: %s = %s", decl.var_decl.name, decl.var_decl.ty, value))
        } else {
            emit_line(e, fmt.tprintf("%s := %s", decl.var_decl.name, value))
        }
    case .Struct:
        for field in decl.struct_decl.fields {
            if field.has_default &&
               !literal_matches_struct_field_type(e, field.ty, field.default_value) {
                return Compile_Error{
                    message = fmt.tprintf(
                        "struct field default type mismatch for %s:",
                        field.source_name,
                    ),
                    span = field.default_value.span,
                }, false
            }
        }
        emit_indent(e)
        strings.write_string(&e.builder, decl.struct_decl.name)
        strings.write_string(&e.builder, " :: struct {")
        emit_raw_newline(e)
        e.indent += 1
        for field in decl.struct_decl.fields {
            prefix := ""
            if field.is_using {
                prefix = "using "
            }
            field_ty := qualify_flattened_decl_type(e, decl.struct_decl.name, field.ty)
            emit_line(e, fmt.tprintf("%s%s: %s,", prefix, field.name, field_ty))
            delete(field_ty)
        }
        e.indent -= 1
        emit_line(e, "}")
        inferred_struct, found_inferred_struct := find_struct_decl(e, decl.struct_decl.name)
        if found_inferred_struct {
            emit_managed_struct_helpers(e, inferred_struct^)
        }
    case .Enum:
        emit_indent(e)
        strings.write_string(&e.builder, decl.enum_decl.name)
        strings.write_string(&e.builder, " :: enum {")
        emit_raw_newline(e)
        e.indent += 1
        for variant in decl.enum_decl.variants {
            if variant.has_value {
                value, err_value, ok_value := emit_expr(e, variant.value)
                if !ok_value {
                    return err_value, false
                }
                emit_line(e, fmt.tprintf("%s = %s,", variant.name, value))
            } else {
                emit_line(e, fmt.tprintf("%s,", variant.name))
            }
        }
        e.indent -= 1
        emit_line(e, "}")
    case .Union:
        emit_indent(e)
        strings.write_string(&e.builder, decl.union_decl.name)
        strings.write_string(&e.builder, " :: union {")
        emit_raw_newline(e)
        e.indent += 1
        for variant in decl.union_decl.variants {
            emit_line(e, fmt.tprintf("%s,", variant.ty))
        }
        e.indent -= 1
        emit_line(e, "}")
    case .Proc:
        proc_live: [dynamic]Owned_Local
        proc_borrowed: [dynamic]Borrowed_Local
        analyze_owned_scope_body(e, decl.proc_decl.body[:], decl.proc_decl.returns.kind != .None, &proc_live, &proc_borrowed)
        delete(proc_live)
        delete(proc_borrowed)
        lint_defer_in_loop_body(e, decl.proc_decl.body[:], false)
        push_local_type_scope(e)
        defer pop_local_type_scope(e)
        for param in decl.proc_decl.params {
            bind_local_type(e, param.name, param.ty)
        }
        emit_indent(e)
        fmt.sbprintf(&e.builder, "%s :: ", decl.proc_decl.name)
        emit_proc_directives(e, e.pending_prefix_directives[:])
        emit_proc_directives(e, decl.proc_decl.prefix_directives[:])
        if decl.proc_decl.calling_convention != "" {
            fmt.sbprintf(&e.builder, "proc %q (", decl.proc_decl.calling_convention)
        } else {
            strings.write_string(&e.builder, "proc(")
        }
        idx := 0
        for idx < len(decl.proc_decl.params) {
            if idx > 0 {
                strings.write_string(&e.builder, ", ")
            }
            if decl.proc_decl.params[idx].has_default &&
               default_is_odin_caller_intrinsic(decl.proc_decl.params[idx].default_value) {
                default_text, err_default, ok_default := emit_expr(e, decl.proc_decl.params[idx].default_value)
                if !ok_default {
                    return err_default, false
                }
                fmt.sbprintf(
                    &e.builder,
                    "%s: %s = %s",
                    decl.proc_decl.params[idx].name,
                    decl.proc_decl.params[idx].ty,
                    default_text,
                )
                idx += 1
                continue
            }
            ty := decl.proc_decl.params[idx].ty
            fmt.sbprintf(&e.builder, "%s", decl.proc_decl.params[idx].name)
            next_idx := idx + 1
            for next_idx < len(decl.proc_decl.params) &&
                decl.proc_decl.params[next_idx].ty == ty &&
                !(decl.proc_decl.params[next_idx].has_default &&
                  default_is_odin_caller_intrinsic(decl.proc_decl.params[next_idx].default_value)) {
                fmt.sbprintf(&e.builder, ", %s", decl.proc_decl.params[next_idx].name)
                next_idx += 1
            }
            fmt.sbprintf(&e.builder, ": %s", ty)
            idx = next_idx
        }
        strings.write_byte(&e.builder, ')')
        emit_return_spec(e, decl.proc_decl.returns)
        emit_proc_suffix_directives(e, e.pending_suffix_directives[:])
        emit_proc_suffix_directives(e, decl.proc_decl.suffix_directives[:])
        err_where, ok_where := emit_proc_where_constraints(e, decl.proc_decl.where_constraints[:])
        if !ok_where {
            return err_where, false
        }
        clear(&e.pending_prefix_directives)
        clear(&e.pending_suffix_directives)
        strings.write_string(&e.builder, " {")
        emit_raw_newline(e)
        e.indent += 1
        previous_owns_managed_result := e.current_proc_owns_managed_result
        previous_borrows_managed_result := e.current_proc_borrows_managed_result
        previous_proc_returns := e.current_proc_returns
        e.current_proc_owns_managed_result = decl.proc_decl.owns_result
        e.current_proc_borrows_managed_result = decl.proc_decl.borrows_result
        e.current_proc_returns = decl.proc_decl.returns
        err_body, ok_body := emit_body_forms(e, decl.proc_decl.body[:], decl.proc_decl.returns)
        e.current_proc_owns_managed_result = previous_owns_managed_result
        e.current_proc_borrows_managed_result = previous_borrows_managed_result
        e.current_proc_returns = previous_proc_returns
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
    case .Transform:
        // Compile-time declaration only; emitted through into/transduce use sites.
        return {}, true
    case .Source:
        source_decl := decl.source_decl
        state_ty := source_decl.state_ty
        push_local_type_scope(e)
        defer pop_local_type_scope(e)
        for param in source_decl.params {
            bind_local_type(e, param.name, param.ty)
        }
        err_protocol, ok_protocol := validate_source_protocol(e, &source_decl, state_ty, decl.span)
        if !ok_protocol {
            return err_protocol, false
        }
        emit_indent(e)
        fmt.sbprintf(&e.builder, "%s :: proc(", source_decl.name)
        for param, idx in source_decl.params {
            if idx > 0 {
                strings.write_string(&e.builder, ", ")
            }
            fmt.sbprintf(&e.builder, "%s: %s", param.name, param.ty)
        }
        fmt.sbprintf(&e.builder, ") -> %s %s", state_ty, "{")
        emit_raw_newline(e)
        e.indent += 1
        err_body, ok_body := emit_body_forms(e, source_decl.body[:], Return_Spec{kind = .Single, single_ty = state_ty})
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
    case .Raw:
        if raw_is_proc_directive(decl.raw_text) {
            if is_proc_prefix_directive(decl.raw_text) {
                append(&e.pending_prefix_directives, decl.raw_text)
            } else {
                append(&e.pending_suffix_directives, decl.raw_text)
            }
            return {}, true
        }
        if has_pending_proc_directives && !raw_attaches_to_next_decl(decl.raw_text) {
            return Compile_Error{message = "procedure directive must be followed by a proc declaration", span = decl.span}, false
        }
        if raw_attaches_to_next_decl(decl.raw_text) {
            e.attach_next_decl = true
        } else if contains_text(e.emitted_raw_decls[:], decl.raw_text) {
            return {}, true
        } else {
            append(&e.emitted_raw_decls, decl.raw_text)
        }
        emit_prefixed_expr(e, "", decl.raw_text)
    case:
        return Compile_Error{message = "unsupported declaration kind", span = decl.span}, false
    }
    return {}, true
}

emit_captured_proc_specialization :: proc(e: ^Emitter, spec: Captured_Proc_Specialization) -> (Compile_Error, bool) {
    proc_decl, ok_proc := find_proc_decl(e, spec.original_name)
    if !ok_proc {
        return Compile_Error{message = fmt.tprintf("internal error: missing proc for callback specialization %s", spec.original_name)}, false
    }
    has_field_callbacks := len(spec.field_callbacks) > 0
    if spec.callback_param_index < 0 || spec.callback_param_index >= len(proc_decl.params) {
        if !has_field_callbacks {
            return Compile_Error{message = "internal error: invalid callback specialization parameter index"}, false
        }
    }

    callback_param: Param
    callback_ty := ""
    if !has_field_callbacks {
        callback_param = proc_decl.params[spec.callback_param_index]
        callback_ty = callback_param.ty
    }
    if !has_field_callbacks && spec.field_selector == "" {
        inserted_ty, ok_callback_ty := proc_type_insert_capture_params_text(callback_param.ty, spec.capture_count)
        if !ok_callback_ty {
            return Compile_Error{message = fmt.tprintf("internal error: callback parameter %s is not a proc type", callback_param.name)}, false
        }
        callback_ty = inserted_ty
        defer delete(callback_ty)
    }

    emit_indent(e)
    fmt.sbprintf(&e.builder, "%s :: proc(", proc_specialization_name(spec))
    first := true
    if has_field_callbacks {
        generic_params: [dynamic]string
        for field_callback in spec.field_callbacks {
            if field_callback.callback_param_index < 0 || field_callback.callback_param_index >= len(proc_decl.params) {
                return Compile_Error{message = "internal error: invalid field callback specialization parameter index"}, false
            }
            for generic_param in generic_type_params_in_text(proc_decl.params[field_callback.callback_param_index].ty) {
                append_unique_string(&generic_params, generic_param)
            }
        }
        for generic_param in generic_params {
            if !first {
                strings.write_string(&e.builder, ", ")
            }
            first = false
            fmt.sbprintf(&e.builder, "$%s: typeid", generic_param)
        }
    } else if spec.field_selector != "" {
        generic_params := generic_type_params_in_text(callback_param.ty)
        for generic_param in generic_params {
            if !first {
                strings.write_string(&e.builder, ", ")
            }
            first = false
            fmt.sbprintf(&e.builder, "$%s: typeid", generic_param)
        }
    }
    for param, idx in proc_decl.params {
        if has_field_callbacks {
            if _, ok_field := field_callback_for_param(spec.field_callbacks[:], idx); ok_field {
                continue
            }
        } else if spec.field_selector != "" && idx == spec.callback_param_index {
            continue
        }
        if !first {
            strings.write_string(&e.builder, ", ")
        }
        first = false
        if idx == spec.callback_param_index {
            fmt.sbprintf(&e.builder, "%s: %s", param.name, callback_ty)
            for capture_idx in 0..<spec.capture_count {
                fmt.sbprintf(&e.builder, ", kvist_capture_%d: C%d", capture_idx+1, capture_idx+1)
            }
        } else {
            fmt.sbprintf(&e.builder, "%s: %s", param.name, param.ty)
        }
    }
    strings.write_byte(&e.builder, ')')
    emit_return_spec(e, proc_decl.returns)
    strings.write_string(&e.builder, " {")
    emit_raw_newline(e)

    e.indent += 1
    push_local_type_scope(e)
    for param, idx in proc_decl.params {
        if has_field_callbacks {
            if _, ok_field := field_callback_for_param(spec.field_callbacks[:], idx); ok_field {
                continue
            }
        } else if param.name == callback_param.name && spec.field_selector != "" {
            continue
        } else if param.name == callback_param.name {
            bind_local_type(e, param.name, callback_ty)
        } else {
            bind_local_type(e, param.name, param.ty)
        }
    }
    if has_field_callbacks {
        for field_callback in spec.field_callbacks {
            bind_field_callback_context(e, proc_decl.params[field_callback.callback_param_index].name, field_callback.field_selector)
        }
    } else if spec.field_selector != "" {
        bind_field_callback_context(e, callback_param.name, spec.field_selector)
    } else {
        capture_names: [dynamic]string
        for capture_idx in 0..<spec.capture_count {
            capture_name := fmt.tprintf("kvist_capture_%d", capture_idx+1)
            append(&capture_names, capture_name)
            bind_local_type(e, capture_name, fmt.tprintf("C%d", capture_idx+1))
        }
        bind_callback_context(e, callback_param.name, capture_names[:])
    }
    err_body, ok_body := emit_body_forms(e, proc_decl.body[:], proc_decl.returns)
    pop_local_type_scope(e)
    if !ok_body {
        return err_body, false
    }
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

emit_captured_proc_specializations :: proc(e: ^Emitter) -> (Compile_Error, bool) {
    if e.captured_proc_specializations == nil {
        return Compile_Error{}, true
    }
    emitted_any := false
    idx := 0
    for idx < len(e.captured_proc_specializations^) {
        if emitted_any || e.line > 1 {
            strings.write_byte(&e.builder, '\n')
            e.line += 1
        }
        err_spec, ok_spec := emit_captured_proc_specialization(e, e.captured_proc_specializations^[idx])
        if !ok_spec {
            return err_spec, false
        }
        emitted_any = true
        idx += 1
    }
    return Compile_Error{}, true
}

parallel_param_list_text :: proc(params: []Param) -> string {
    if len(params) == 0 {
        return strings.clone("")
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for param, idx in params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "%s: %s", param.name, param.ty)
    }
    return strings.clone(strings.to_string(builder))
}

parallel_data_arg_list_text :: proc(params: []Param) -> string {
    if len(params) == 0 {
        return strings.clone("")
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for param, idx in params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "data.%s", param.name)
    }
    return strings.clone(strings.to_string(builder))
}

parallel_generic_params :: proc(params: []Param, result_ty := "") -> (values: [dynamic]string) {
    for param in params {
        append_proc_generic_candidates(&values, param.ty)
    }
    if result_ty != "" {
        append_proc_generic_candidates(&values, result_ty)
    }
    return values
}

parallel_generic_decl_suffix :: proc(params: []string) -> string {
    if len(params) == 0 {
        return strings.clone("")
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_byte(&builder, '(')
    for param, idx in params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "$%s: typeid", param)
    }
    strings.write_byte(&builder, ')')
    return strings.clone(strings.to_string(builder))
}

parallel_generic_type_args :: proc(params: []string, introduce := false) -> string {
    if len(params) == 0 {
        return strings.clone("")
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_byte(&builder, '(')
    for param, idx in params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        if introduce {
            strings.write_byte(&builder, '$')
        }
        strings.write_string(&builder, param)
    }
    strings.write_byte(&builder, ')')
    return strings.clone(strings.to_string(builder))
}

parallel_data_type_text :: proc(data_name: string, generic_params: []string, introduce := false) -> string {
    if len(generic_params) == 0 {
        return strings.clone(data_name)
    }
    args := parallel_generic_type_args(generic_params, introduce)
    defer delete(args)
    return fmt.tprintf("%s%s", data_name, args)
}

parallel_field_type_text :: proc(ty: string, generic_params: []string) -> string {
    if len(generic_params) == 0 {
        return strings.clone(ty)
    }
    return substitute_type_names(ty, generic_params, generic_params)
}

emit_parallel_task_data_fields :: proc(e: ^Emitter, params: []Param, generic_params: []string = nil) {
    for param in params {
        ty := parallel_field_type_text(param.ty, generic_params)
        defer delete(ty)
        emit_line(e, fmt.tprintf("%s: %s,", param.name, ty))
    }
}

emit_parallel_task_data_assignments :: proc(e: ^Emitter, params: []Param) {
    for param in params {
        emit_line(e, fmt.tprintf("data.%s = %s", param.name, param.name))
    }
}

emit_thread_start_helper :: proc(e: ^Emitter, spec: Thread_Start_Spec) {
    data_name := thread_start_data_name(spec)
    worker_name := thread_start_worker_name(spec)
    start_name := thread_start_helper_name(spec)
    callback_name := thread_start_callback_name(spec)
    task_ty := thread_task_type(spec)
    helper_params: [dynamic]Param
    for capture in spec.captures {
        append(&helper_params, capture)
    }
    for param in spec.params {
        append(&helper_params, param)
    }
    params_text := parallel_param_list_text(helper_params[:])
    data_args_text := parallel_data_arg_list_text(helper_params[:])
    generic_params := parallel_generic_params(helper_params[:], spec.result_ty)
    data_decl_suffix := parallel_generic_decl_suffix(generic_params[:])
    worker_data_ty := parallel_data_type_text(data_name, generic_params[:], true)
    helper_data_ty := parallel_data_type_text(data_name, generic_params[:], false)
    defer delete(data_name)
    defer delete(worker_name)
    defer delete(start_name)
    defer delete(callback_name)
    defer delete(task_ty)
    defer delete(params_text)
    defer delete(data_args_text)
    defer delete(generic_params)
    defer delete(data_decl_suffix)
    defer delete(worker_data_ty)
    defer delete(helper_data_ty)

    if spec.callback_proc != "" {
        emit_named_proc_text(e, callback_name, spec.callback_proc)
        emit_raw_newline(e)
    }

    emit_line(e, fmt.tprintf("%s :: struct%s %s", data_name, data_decl_suffix, "{"))
    e.indent += 1
    result_ty := parallel_field_type_text(spec.result_ty, generic_params[:])
    emit_line(e, fmt.tprintf("result: chan.Chan(%s),", result_ty))
    delete(result_ty)
    emit_parallel_task_data_fields(e, spec.captures, generic_params[:])
    emit_parallel_task_data_fields(e, spec.params, generic_params[:])
    e.indent -= 1
    emit_line(e, "}")
    emit_raw_newline(e)

    emit_line(e, fmt.tprintf("%s :: proc(data: ^%s) %s", worker_name, worker_data_ty, "{"))
    e.indent += 1
    call_name := spec.worker
    if spec.callback_proc != "" {
        call_name = callback_name
    }
    emit_line(e, fmt.tprintf("chan.send(data.result, %s(%s))", call_name, data_args_text))
    e.indent -= 1
    emit_line(e, "}")
    emit_raw_newline(e)

    emit_line(e, fmt.tprintf("%s :: proc(%s) -> %s %s", start_name, params_text, task_ty, "{"))
    e.indent += 1
    emit_line(e, fmt.tprintf("result, err := chan.create(chan.Chan(%s), 1, context.allocator)", spec.result_ty))
    emit_line(e, "assert(err == .None, \"thread-start could not create result channel\")")
    emit_line(e, fmt.tprintf("data := new(%s)", helper_data_ty))
    emit_line(e, "data.result = result")
    emit_parallel_task_data_assignments(e, spec.captures)
    emit_parallel_task_data_assignments(e, spec.params)
    emit_line(e, fmt.tprintf("task_thread := thread.create_and_start_with_poly_data(data, %s)", worker_name))
    emit_line(e, "assert(task_thread != nil, \"thread-start could not start worker thread\")")
    emit_line(e, fmt.tprintf("return %s%sresult = result, thread = task_thread, data = data}", task_ty, "{"))
    e.indent -= 1
    emit_line(e, "}")
}

emit_thread_detach_helper :: proc(e: ^Emitter, spec: Thread_Detach_Spec) {
    data_name := thread_detach_data_name(spec)
    worker_name := thread_detach_worker_name(spec)
    detach_name := thread_detach_helper_name(spec)
    callback_name := thread_detach_callback_name(spec)
    helper_params: [dynamic]Param
    for capture in spec.captures {
        append(&helper_params, capture)
    }
    for param in spec.params {
        append(&helper_params, param)
    }
    params_text := parallel_param_list_text(helper_params[:])
    data_args_text := parallel_data_arg_list_text(helper_params[:])
    defer delete(data_name)
    defer delete(worker_name)
    defer delete(detach_name)
    defer delete(callback_name)
    defer delete(params_text)
    defer delete(data_args_text)

    if spec.callback_proc != "" {
        emit_named_proc_text(e, callback_name, spec.callback_proc)
        emit_raw_newline(e)
    }

    emit_line(e, fmt.tprintf("%s :: struct %s", data_name, "{"))
    e.indent += 1
    emit_parallel_task_data_fields(e, spec.captures)
    emit_parallel_task_data_fields(e, spec.params)
    e.indent -= 1
    emit_line(e, "}")
    emit_raw_newline(e)

    emit_line(e, fmt.tprintf("%s :: proc(data: ^%s) %s", worker_name, data_name, "{"))
    e.indent += 1
    call_name := spec.worker
    if spec.callback_proc != "" {
        call_name = callback_name
    }
    emit_line(e, fmt.tprintf("%s(%s)", call_name, data_args_text))
    emit_line(e, "free(data)")
    e.indent -= 1
    emit_line(e, "}")
    emit_raw_newline(e)

    emit_line(e, fmt.tprintf("%s :: proc(%s) %s", detach_name, params_text, "{"))
    e.indent += 1
    emit_line(e, fmt.tprintf("data := new(%s)", data_name))
    emit_parallel_task_data_assignments(e, spec.captures)
    emit_parallel_task_data_assignments(e, spec.params)
    emit_line(e, fmt.tprintf("task_thread := thread.create_and_start_with_poly_data(data, %s, nil, .Normal, true)", worker_name))
    emit_line(e, "if task_thread == nil {")
    e.indent += 1
    emit_line(e, "free(data)")
    emit_line(e, "assert(false, \"thread-detach could not start worker thread\")")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
}

emit_named_proc_text :: proc(e: ^Emitter, name, proc_text: string) {
    emit_indent(e)
    strings.write_string(&e.builder, name)
    strings.write_string(&e.builder, " :: ")
    strings.write_string(&e.builder, proc_text)
    strings.write_byte(&e.builder, '\n')
    e.line += 1
    for ch in proc_text {
        if ch == '\n' {
            e.line += 1
        }
    }
}

parallel_helpers_needed :: proc(features: Emitter_Features) -> bool {
    return len(features.thread_starts) > 0 ||
           len(features.thread_detaches) > 0
}

emit_parallel_helpers :: proc(e: ^Emitter, features: Emitter_Features, emitted: ^bool) {
    if !parallel_helpers_needed(features) {
        return
    }

    for spec in features.thread_starts {
        emit_core_helper_separator(e, emitted)
        emit_thread_start_helper(e, spec)
    }

    for spec in features.thread_detaches {
        emit_core_helper_separator(e, emitted)
        emit_thread_detach_helper(e, spec)
    }

}

emit_keyword_type_helper :: proc(e: ^Emitter) {
    emit_line(e, "keyword :: distinct string")
}

emit_data_type_helper :: proc(e: ^Emitter) {
    emit_line(e, "Data_Kind :: enum { Nil, Bool, Int, Float, String, Symbol, Keyword, List, Vector, Map, Set, Tagged }")
    emit_line(e, "Data_Entry :: struct { key, value: Data }")
    emit_line(e, "Data_Node :: struct {")
    e.indent += 1
    emit_line(e, "refs: int,")
    emit_line(e, "allocator: kvist_runtime.Allocator,")
    emit_line(e, "text: string,")
    emit_line(e, "items: [dynamic]Data,")
    emit_line(e, "entries: [dynamic]Data_Entry,")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "Data_Payload :: struct #raw_union {")
    e.indent += 1
    emit_line(e, "bool_value: bool,")
    emit_line(e, "int_value: i64,")
    emit_line(e, "float_value: f64,")
    emit_line(e, "text: string,")
    emit_line(e, "items: []Data,")
    emit_line(e, "entries: []Data_Entry,")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "Data :: struct {")
    e.indent += 1
    emit_line(e, "kind: Data_Kind,")
    emit_line(e, "payload: Data_Payload,")
    emit_line(e, "node: ^Data_Node,")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "Data_Piece :: struct { value: Data, splice: bool }")
    emit_raw_newline(e)
    emit_line(e, "kvist_data_retain :: proc(value: Data) -> Data {")
    e.indent += 1
    emit_line(e, "if value.node != nil { kvist_sync.atomic_add(&value.node.refs, 1) }")
    emit_line(e, "return value")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_append_retained :: proc(values: ^[dynamic]Data, value: Data) { append(values, kvist_data_retain(value)) }")
    emit_line(e, "kvist_data_release :: proc(value: Data) {")
    e.indent += 1
    emit_line(e, "if value.node == nil || kvist_sync.atomic_sub(&value.node.refs, 1) != 1 { return }")
    emit_line(e, "for item in value.node.items { kvist_data_release(item) }")
    emit_line(e, "for entry in value.node.entries { kvist_data_release(entry.key); kvist_data_release(entry.value) }")
    emit_line(e, "delete(value.node.text, value.node.allocator)")
    emit_line(e, "delete(value.node.items)")
    emit_line(e, "delete(value.node.entries)")
    emit_line(e, "free(value.node, value.node.allocator)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_assign :: proc(place: ^Data, value: Data) {")
    e.indent += 1
    emit_line(e, "replacement := kvist_data_retain(value)")
    emit_line(e, "previous := place^")
    emit_line(e, "place^ = replacement")
    emit_line(e, "kvist_data_release(previous)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_move_assign :: proc(place: ^Data, value: Data) {")
    e.indent += 1
    emit_line(e, "previous := place^")
    emit_line(e, "place^ = value")
    emit_line(e, "kvist_data_release(previous)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_new_node :: proc(allocator: kvist_runtime.Allocator = context.allocator) -> ^Data_Node {")
    e.indent += 1
    emit_line(e, "node := new(Data_Node, allocator)")
    emit_line(e, "node^ = Data_Node{refs = 1, allocator = allocator}")
    emit_line(e, "return node")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_make_nil :: proc() -> Data { return Data{} }")
    emit_line(e, "kvist_data_make_bool :: proc(value: bool) -> Data { return Data{kind = .Bool, payload = {bool_value = value}} }")
    emit_line(e, "kvist_data_make_int :: proc(value: i64) -> Data { return Data{kind = .Int, payload = {int_value = value}} }")
    emit_line(e, "kvist_data_make_float :: proc(value: f64) -> Data { return Data{kind = .Float, payload = {float_value = value}} }")
    emit_line(e, "kvist_data_make_text :: proc(kind: Data_Kind, value: string, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(kind == .String || kind == .Symbol || kind == .Keyword)")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.text = strings.clone(value, allocator)")
    emit_line(e, "return Data{kind = kind, payload = {text = node.text}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_lift_data :: proc(value: Data) -> Data { return kvist_data_retain(value) }")
    emit_line(e, "kvist_data_lift_bool :: proc(value: bool) -> Data { return kvist_data_make_bool(value) }")
    emit_line(e, "kvist_data_lift_int :: proc(value: int) -> Data { return kvist_data_make_int(i64(value)) }")
    emit_line(e, "kvist_data_lift_i8 :: proc(value: i8) -> Data { return kvist_data_make_int(i64(value)) }")
    emit_line(e, "kvist_data_lift_i16 :: proc(value: i16) -> Data { return kvist_data_make_int(i64(value)) }")
    emit_line(e, "kvist_data_lift_i32 :: proc(value: i32) -> Data { return kvist_data_make_int(i64(value)) }")
    emit_line(e, "kvist_data_lift_i64 :: proc(value: i64) -> Data { return kvist_data_make_int(i64(value)) }")
    emit_line(e, "kvist_data_lift_u8 :: proc(value: u8) -> Data { return kvist_data_make_int(i64(value)) }")
    emit_line(e, "kvist_data_lift_u16 :: proc(value: u16) -> Data { return kvist_data_make_int(i64(value)) }")
    emit_line(e, "kvist_data_lift_u32 :: proc(value: u32) -> Data { return kvist_data_make_int(i64(value)) }")
    emit_line(e, "kvist_data_lift_u64 :: proc(value: u64) -> Data { return kvist_data_make_int(i64(value)) }")
    emit_line(e, "kvist_data_lift_f32 :: proc(value: f32) -> Data { return kvist_data_make_float(f64(value)) }")
    emit_line(e, "kvist_data_lift_f64 :: proc(value: f64) -> Data { return kvist_data_make_float(f64(value)) }")
    emit_line(e, "kvist_data_lift_string :: proc(value: string) -> Data { return kvist_data_make_text(.String, value) }")
    emit_line(e, "kvist_data_lift_keyword :: proc(value: keyword) -> Data { return kvist_data_make_text(.Keyword, string(value)) }")
    emit_line(e, "kvist_data_lift :: proc{kvist_data_lift_data, kvist_data_lift_bool, kvist_data_lift_int, kvist_data_lift_i8, kvist_data_lift_i16, kvist_data_lift_i32, kvist_data_lift_i64, kvist_data_lift_u8, kvist_data_lift_u16, kvist_data_lift_u32, kvist_data_lift_u64, kvist_data_lift_f32, kvist_data_lift_f64, kvist_data_lift_string, kvist_data_lift_keyword}")
    emit_line(e, "kvist_data_make_tagged :: proc(tag: string, value: Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(len(tag) > 0, \"Data tag must not be empty\")")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.text = strings.clone(tag, allocator)")
    emit_line(e, "node.items = make([dynamic]Data, 0, 1, allocator)")
    emit_line(e, "append(&node.items, kvist_data_retain(value))")
    emit_line(e, "return Data{kind = .Tagged, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_make_items :: proc(kind: Data_Kind, values: []Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(kind == .List || kind == .Vector || kind == .Set)")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.items = make([dynamic]Data, 0, len(values), allocator)")
    emit_line(e, "for value in values {")
    e.indent += 1
    emit_line(e, "if kind == .Set { found := false; for item in node.items { if kvist_data_equal(item, value) { found = true; break } }; if found { continue } }")
    emit_line(e, "append(&node.items, kvist_data_retain(value))")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return Data{kind = kind, payload = {items = node.items[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_freeze_items :: proc(kind: Data_Kind, values: ^[dynamic]Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(kind == .List || kind == .Vector || kind == .Set)")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.items = values^")
    emit_line(e, "values^ = nil")
    emit_line(e, "return Data{kind = kind, payload = {items = node.items[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_make_unique_set :: proc(values: []Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.items = make([dynamic]Data, 0, len(values), allocator)")
    emit_line(e, "for value in values { append(&node.items, kvist_data_retain(value)) }")
    emit_line(e, "return Data{kind = .Set, payload = {items = node.items[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_make_items_spliced :: proc(kind: Data_Kind, pieces: []Data_Piece, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(kind == .List || kind == .Vector || kind == .Set)")
    emit_line(e, "capacity := 0")
    emit_line(e, "for piece in pieces { if piece.splice { assert(piece.value.kind == .List || piece.value.kind == .Vector || piece.value.kind == .Set, \"Data splice expects a list, vector, or set\"); capacity += len(piece.value.payload.items) } else { capacity += 1 } }")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.items = make([dynamic]Data, 0, capacity, allocator)")
    emit_line(e, "for piece in pieces {")
    e.indent += 1
    emit_line(e, "values := []Data{piece.value}")
    emit_line(e, "if piece.splice { values = piece.value.payload.items }")
    emit_line(e, "for value in values {")
    e.indent += 1
    emit_line(e, "if kind == .Set { found := false; for item in node.items { if kvist_data_equal(item, value) { found = true; break } }; if found { continue } }")
    emit_line(e, "append(&node.items, kvist_data_retain(value))")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return Data{kind = kind, payload = {items = node.items[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_make_map :: proc(values: []Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(len(values)%2 == 0, \"Data map expects alternating keys and values\")")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.entries = make([dynamic]Data_Entry, 0, len(values)/2, allocator)")
    emit_line(e, "for i := 0; i < len(values); i += 2 {")
    e.indent += 1
    emit_line(e, "replaced := false")
    emit_line(e, "for &entry in node.entries { if kvist_data_equal(entry.key, values[i]) { kvist_data_assign(&entry.value, values[i+1]); replaced = true; break } }")
    emit_line(e, "if !replaced { append(&node.entries, Data_Entry{key = kvist_data_retain(values[i]), value = kvist_data_retain(values[i+1])}) }")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return Data{kind = .Map, payload = {entries = node.entries[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_freeze_map :: proc(values: ^[dynamic]Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(len(values^)%2 == 0, \"Data map builder expects alternating keys and values\")")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.entries = make([dynamic]Data_Entry, 0, len(values^)/2, allocator)")
    emit_line(e, "for i := 0; i < len(values^); i += 2 {")
    e.indent += 1
    emit_line(e, "replaced := false")
    emit_line(e, "for &entry in node.entries { if kvist_data_equal(entry.key, values^[i]) { kvist_data_release(values^[i]); kvist_data_release(entry.value); entry.value = values^[i+1]; replaced = true; break } }")
    emit_line(e, "if !replaced { append(&node.entries, Data_Entry{key = values^[i], value = values^[i+1]}) }")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "delete(values^)")
    emit_line(e, "values^ = nil")
    emit_line(e, "return Data{kind = .Map, payload = {entries = node.entries[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_freeze_unique_map :: proc(values: ^[dynamic]Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(len(values^)%2 == 0, \"unique Data map builder expects alternating keys and values\")")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.entries = make([dynamic]Data_Entry, 0, len(values^)/2, allocator)")
    emit_line(e, "for i := 0; i < len(values^); i += 2 { append(&node.entries, Data_Entry{key = values^[i], value = values^[i+1]}) }")
    emit_line(e, "delete(values^)")
    emit_line(e, "values^ = nil")
    emit_line(e, "return Data{kind = .Map, payload = {entries = node.entries[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_empty_map :: proc(allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.entries = make([dynamic]Data_Entry, allocator)")
    emit_line(e, "return Data{kind = .Map, payload = {entries = node.entries[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_raw_newline(e)
    emit_line(e, "kvist_data_same_backing :: proc(a, b: Data) -> bool {")
    e.indent += 1
    emit_line(e, "if a.kind != b.kind { return false }")
    emit_line(e, "switch a.kind {")
    e.indent += 1
    emit_line(e, "case .Nil: return true")
    emit_line(e, "case .Bool: return a.payload.bool_value == b.payload.bool_value")
    emit_line(e, "case .Int: return a.payload.int_value == b.payload.int_value")
    emit_line(e, "case .Float: return a.payload.float_value == b.payload.float_value")
    emit_line(e, "case .String, .Symbol, .Keyword, .Tagged: return a.node != nil && a.node == b.node")
    emit_line(e, "case .List, .Vector, .Set:")
    e.indent += 1
    emit_line(e, "if a.node == nil || a.node != b.node || len(a.payload.items) != len(b.payload.items) { return false }")
    emit_line(e, "return len(a.payload.items) == 0 || &a.payload.items[0] == &b.payload.items[0]")
    e.indent -= 1
    emit_line(e, "case .Map:")
    e.indent += 1
    emit_line(e, "if a.node == nil || a.node != b.node || len(a.payload.entries) != len(b.payload.entries) { return false }")
    emit_line(e, "return len(a.payload.entries) == 0 || &a.payload.entries[0] == &b.payload.entries[0]")
    e.indent -= 1
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return false")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_equal :: proc(a, b: Data) -> bool {")
    e.indent += 1
    emit_line(e, "if a.kind != b.kind { return false }")
    emit_line(e, "switch a.kind {")
    e.indent += 1
    emit_line(e, "case .Nil: return true")
    emit_line(e, "case .Bool: return a.payload.bool_value == b.payload.bool_value")
    emit_line(e, "case .Int: return a.payload.int_value == b.payload.int_value")
    emit_line(e, "case .Float: return a.payload.float_value == b.payload.float_value")
    emit_line(e, "case .String, .Symbol, .Keyword: return a.payload.text == b.payload.text")
    emit_line(e, "case .Tagged:")
    e.indent += 1
    emit_line(e, "if kvist_data_same_backing(a, b) { return true }")
    emit_line(e, "return a.node.text == b.node.text && kvist_data_equal(a.node.items[0], b.node.items[0])")
    e.indent -= 1
    emit_line(e, "case .List, .Vector:")
    e.indent += 1
    emit_line(e, "if kvist_data_same_backing(a, b) { return true }")
    emit_line(e, "if len(a.payload.items) != len(b.payload.items) { return false }")
    emit_line(e, "for value, i in a.payload.items { if !kvist_data_equal(value, b.payload.items[i]) { return false } }")
    emit_line(e, "return true")
    e.indent -= 1
    emit_line(e, "case .Set:")
    e.indent += 1
    emit_line(e, "if kvist_data_same_backing(a, b) { return true }")
    emit_line(e, "if len(a.payload.items) != len(b.payload.items) { return false }")
    emit_line(e, "same_order := true")
    emit_line(e, "for value, i in a.payload.items { if !kvist_data_equal(value, b.payload.items[i]) { same_order = false; break } }")
    emit_line(e, "if same_order { return true }")
    emit_line(e, "for value in a.payload.items { found := false; for other in b.payload.items { if kvist_data_equal(value, other) { found = true; break } }; if !found { return false } }")
    emit_line(e, "return true")
    e.indent -= 1
    emit_line(e, "case .Map:")
    e.indent += 1
    emit_line(e, "if kvist_data_same_backing(a, b) { return true }")
    emit_line(e, "if len(a.payload.entries) != len(b.payload.entries) { return false }")
    emit_line(e, "same_order := true")
    emit_line(e, "for entry, i in a.payload.entries { if !kvist_data_equal(entry.key, b.payload.entries[i].key) || !kvist_data_equal(entry.value, b.payload.entries[i].value) { same_order = false; break } }")
    emit_line(e, "if same_order { return true }")
    emit_line(e, "for entry in a.payload.entries {")
    e.indent += 1
    emit_line(e, "found := false")
    emit_line(e, "for other in b.payload.entries { if kvist_data_equal(entry.key, other.key) && kvist_data_equal(entry.value, other.value) { found = true; break } }")
    emit_line(e, "if !found { return false }")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return true")
    e.indent -= 1
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return false")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_slice_contains :: proc(values: []Data, value: Data) -> bool { for existing in values { if kvist_data_equal(existing, value) { return true } }; return false }")
    emit_line(e, "kvist_data_assoc :: proc(collection, key, value: Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "if collection.kind == .Map {")
    e.indent += 1
    emit_line(e, "found_index := -1")
    emit_line(e, "for entry, i in collection.payload.entries { if kvist_data_equal(entry.key, key) { found_index = i; break } }")
    emit_line(e, "if found_index >= 0 && kvist_data_equal(collection.payload.entries[found_index].value, value) { return kvist_data_retain(collection) }")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.entries = make([dynamic]Data_Entry, 0, len(collection.payload.entries)+1, allocator)")
    emit_line(e, "for entry, i in collection.payload.entries { if i == found_index { append(&node.entries, Data_Entry{key = kvist_data_retain(entry.key), value = kvist_data_retain(value)}) } else { append(&node.entries, Data_Entry{key = kvist_data_retain(entry.key), value = kvist_data_retain(entry.value)}) } }")
    emit_line(e, "if found_index < 0 { append(&node.entries, Data_Entry{key = kvist_data_retain(key), value = kvist_data_retain(value)}) }")
    emit_line(e, "return Data{kind = .Map, payload = {entries = node.entries[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "if collection.kind == .Vector && key.kind == .Int && key.payload.int_value >= 0 && key.payload.int_value < i64(len(collection.payload.items)) {")
    e.indent += 1
    emit_line(e, "index := int(key.payload.int_value)")
    emit_line(e, "if kvist_data_equal(collection.payload.items[index], value) { return kvist_data_retain(collection) }")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.items = make([dynamic]Data, 0, len(collection.payload.items), allocator)")
    emit_line(e, "for item, i in collection.payload.items { if i == index { append(&node.items, kvist_data_retain(value)) } else { append(&node.items, kvist_data_retain(item)) } }")
    emit_line(e, "return Data{kind = .Vector, payload = {items = node.items[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "assert(false, \"Data assoc expects a map or an in-range vector index\")")
    emit_line(e, "return Data{}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_dissoc :: proc(collection, key: Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(collection.kind == .Map, \"Data dissoc expects a map\")")
    emit_line(e, "found_index := -1")
    emit_line(e, "for entry, i in collection.payload.entries { if kvist_data_equal(entry.key, key) { found_index = i; break } }")
    emit_line(e, "if found_index < 0 { return kvist_data_retain(collection) }")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.entries = make([dynamic]Data_Entry, 0, len(collection.payload.entries)-1, allocator)")
    emit_line(e, "for entry, i in collection.payload.entries { if i != found_index { append(&node.entries, Data_Entry{key = kvist_data_retain(entry.key), value = kvist_data_retain(entry.value)}) } }")
    emit_line(e, "return Data{kind = .Map, payload = {entries = node.entries[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_dissoc_in :: proc(collection, path: Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(collection.kind == .Map, \"Data dissoc-in expects a map\")")
    emit_line(e, "assert(path.kind == .List || path.kind == .Vector, \"Data dissoc-in expects a list or vector path\")")
    emit_line(e, "if len(path.payload.items) == 0 { return kvist_data_retain(collection) }")
    emit_line(e, "key := path.payload.items[0]")
    emit_line(e, "if len(path.payload.items) == 1 { return kvist_data_dissoc(collection, key, allocator) }")
    emit_line(e, "child := kvist_data_get(collection, key)")
    emit_line(e, "if child.kind != .Map { return kvist_data_retain(collection) }")
    emit_line(e, "tail := Data{kind = path.kind, payload = {items = path.payload.items[1:]}, node = path.node}")
    emit_line(e, "updated := kvist_data_dissoc_in(child, tail, allocator)")
    emit_line(e, "defer kvist_data_release(updated)")
    emit_line(e, "return kvist_data_assoc(collection, key, updated, allocator)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_conj :: proc(collection, value: Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(collection.kind == .List || collection.kind == .Vector || collection.kind == .Set, \"Data conj expects a list, vector, or set\")")
    emit_line(e, "if collection.kind == .Set { for item in collection.payload.items { if kvist_data_equal(item, value) { return kvist_data_retain(collection) } } }")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.items = make([dynamic]Data, 0, len(collection.payload.items)+1, allocator)")
    emit_line(e, "if collection.kind == .List { append(&node.items, kvist_data_retain(value)) }")
    emit_line(e, "for item in collection.payload.items { append(&node.items, kvist_data_retain(item)) }")
    emit_line(e, "if collection.kind != .List { append(&node.items, kvist_data_retain(value)) }")
    emit_line(e, "return Data{kind = collection.kind, payload = {items = node.items[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_append :: proc(collection, value: Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(collection.kind == .List || collection.kind == .Vector || collection.kind == .Set, \"Data append expects a list, vector, or set\")")
    emit_line(e, "if collection.kind == .Set { for item in collection.payload.items { if kvist_data_equal(item, value) { return kvist_data_retain(collection) } } }")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.items = make([dynamic]Data, 0, len(collection.payload.items)+1, allocator)")
    emit_line(e, "for item in collection.payload.items { append(&node.items, kvist_data_retain(item)) }")
    emit_line(e, "append(&node.items, kvist_data_retain(value))")
    emit_line(e, "return Data{kind = collection.kind, payload = {items = node.items[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_raw_newline(e)
    emit_line(e, "kvist_data_get :: proc(value, key: Data) -> Data {")
    e.indent += 1
    emit_line(e, "if value.kind == .Map { for entry in value.payload.entries { if kvist_data_equal(entry.key, key) { return entry.value } } }")
    emit_line(e, "if (value.kind == .List || value.kind == .Vector) && key.kind == .Int && key.payload.int_value >= 0 && key.payload.int_value < i64(len(value.payload.items)) { return value.payload.items[int(key.payload.int_value)] }")
    emit_line(e, "return Data{}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_get_present :: proc(value, key: Data) -> (result: Data, present: bool) {")
    e.indent += 1
    emit_line(e, "if value.kind != .Map { return Data{}, false }")
    emit_line(e, "for entry in value.payload.entries { if kvist_data_equal(entry.key, key) { return kvist_data_retain(entry.value), true } }")
    emit_line(e, "return Data{}, false")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_nth_or_nil :: proc(value: Data, index: int) -> Data {")
    e.indent += 1
    emit_line(e, "if (value.kind == .List || value.kind == .Vector) && index >= 0 && index < len(value.payload.items) { return value.payload.items[index] }")
    emit_line(e, "return Data{}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_rest_from :: proc(value: Data, index: int, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "if (value.kind != .List && value.kind != .Vector) || index >= len(value.payload.items) { return Data{} }")
    emit_line(e, "return kvist_data_make_items(value.kind, value.payload.items[index:], allocator)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_or :: proc(value, fallback: Data) -> Data { if value.kind == .Nil { return fallback }; return value }")
    emit_line(e, "kvist_data_get_or :: proc(value, key, fallback: Data) -> Data {")
    e.indent += 1
    emit_line(e, "if value.kind == .Map { for entry in value.payload.entries { if kvist_data_equal(entry.key, key) { return entry.value } }; return fallback }")
    emit_line(e, "if (value.kind == .List || value.kind == .Vector) && key.kind == .Int && key.payload.int_value >= 0 && key.payload.int_value < i64(len(value.payload.items)) { return value.payload.items[int(key.payload.int_value)] }")
    emit_line(e, "return fallback")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_map_call :: proc(value, key: Data) -> Data { assert(value.kind == .Nil || value.kind == .Map, \"Data invocation expects a map or nil\"); return kvist_data_get(value, key) }")
    emit_line(e, "kvist_data_map_call_or :: proc(value, key, fallback: Data) -> Data { assert(value.kind == .Nil || value.kind == .Map, \"Data invocation expects a map or nil\"); return kvist_data_get_or(value, key, fallback) }")
    emit_line(e, "kvist_data_contains :: proc(value, key: Data) -> bool {")
    e.indent += 1
    emit_line(e, "if value.kind == .Map { for entry in value.payload.entries { if kvist_data_equal(entry.key, key) { return true } }; return false }")
    emit_line(e, "if value.kind == .Set { for item in value.payload.items { if kvist_data_equal(item, key) { return true } } }")
    emit_line(e, "return false")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_int :: proc(value: Data) -> i64 { assert(value.kind == .Int, \"expected Data int\"); return value.payload.int_value }")
    emit_line(e, "kvist_data_float :: proc(value: Data) -> f64 { assert(value.kind == .Float, \"expected Data float\"); return value.payload.float_value }")
    emit_line(e, "kvist_data_bool :: proc(value: Data) -> bool { assert(value.kind == .Bool, \"expected Data bool\"); return value.payload.bool_value }")
    emit_line(e, "kvist_data_string :: proc(value: Data) -> string { assert(value.kind == .String, \"expected Data string\"); return value.payload.text }")
    emit_line(e, "kvist_data_keyword :: proc(value: Data) -> string { assert(value.kind == .Keyword, \"expected Data keyword\"); return value.payload.text }")
    emit_line(e, "kvist_data_symbol :: proc(value: Data) -> string { assert(value.kind == .Symbol, \"expected Data symbol\"); return value.payload.text }")
    emit_line(e, "kvist_data_text :: proc(value: Data) -> string { assert(value.kind == .String || value.kind == .Symbol || value.kind == .Keyword, \"expected textual Data\"); return value.payload.text }")
    emit_line(e, "kvist_data_tag :: proc(value: Data) -> string { assert(value.kind == .Tagged, \"expected tagged Data\"); return value.node.text }")
    emit_line(e, "kvist_data_tagged_value :: proc(value: Data) -> Data { assert(value.kind == .Tagged, \"expected tagged Data\"); return value.node.items[0] }")
    emit_line(e, "kvist_data_count :: proc(value: Data) -> int { if value.kind == .Nil { return 0 }; if value.kind == .Map { return len(value.payload.entries) }; if value.kind == .List || value.kind == .Vector || value.kind == .Set { return len(value.payload.items) }; if value.kind == .String { return len(value.payload.text) }; assert(false, \"count expects collection, string, or nil Data\"); return 0 }")
    emit_line(e, "kvist_data_kind :: proc(value: Data) -> Data_Kind { return value.kind }")
    emit_line(e, "kvist_data_nil_p :: proc(value: Data) -> bool { return value.kind == .Nil }")
    emit_line(e, "kvist_data_bool_p :: proc(value: Data) -> bool { return value.kind == .Bool }")
    emit_line(e, "kvist_data_int_p :: proc(value: Data) -> bool { return value.kind == .Int }")
    emit_line(e, "kvist_data_float_p :: proc(value: Data) -> bool { return value.kind == .Float }")
    emit_line(e, "kvist_data_string_p :: proc(value: Data) -> bool { return value.kind == .String }")
    emit_line(e, "kvist_data_symbol_p :: proc(value: Data) -> bool { return value.kind == .Symbol }")
    emit_line(e, "kvist_data_keyword_p :: proc(value: Data) -> bool { return value.kind == .Keyword }")
    emit_line(e, "kvist_data_list_p :: proc(value: Data) -> bool { return value.kind == .List }")
    emit_line(e, "kvist_data_vector_p :: proc(value: Data) -> bool { return value.kind == .Vector }")
    emit_line(e, "kvist_data_map_p :: proc(value: Data) -> bool { return value.kind == .Map }")
    emit_line(e, "kvist_data_set_p :: proc(value: Data) -> bool { return value.kind == .Set }")
    emit_line(e, "kvist_data_tagged_p :: proc(value: Data) -> bool { return value.kind == .Tagged }")
    emit_line(e, "kvist_data_item_at :: proc(value: Data, index: int) -> Data { assert((value.kind == .List || value.kind == .Vector || value.kind == .Set) && index >= 0 && index < len(value.payload.items), \"Data collection index out of bounds\"); return value.payload.items[index] }")
    emit_line(e, "kvist_data_key_at :: proc(value: Data, index: int) -> Data { assert(value.kind == .Map && index >= 0 && index < len(value.payload.entries), \"Data map index out of bounds\"); return value.payload.entries[index].key }")
    emit_line(e, "kvist_data_value_at :: proc(value: Data, index: int) -> Data { assert(value.kind == .Map && index >= 0 && index < len(value.payload.entries), \"Data map index out of bounds\"); return value.payload.entries[index].value }")
}

emit_data_literals :: proc(e: ^Emitter, literals: []Data_Literal) {
    for literal in literals {
        emit_raw_newline(e)
        emit_line(e, fmt.tprintf("%s: Data = %s", literal.name, literal.value))
    }
}

emit_core_get_or_default_helper :: proc(e: ^Emitter) {
    emit_line(e, "kvist_get_or_default :: proc(m: map[$K]$V, key: K, default: V) -> V {")
    e.indent += 1
    emit_line(e, "value, ok := m[key]")
    emit_line(e, "if ok {")
    e.indent += 1
    emit_line(e, "return value")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return default")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_contains_value_helper :: proc(e: ^Emitter) {
    emit_line(e, "kvist_contains_value :: #force_inline proc(xs: []$T, value: T) -> bool {")
    e.indent += 1
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "if x == value {")
    e.indent += 1
    emit_line(e, "return true")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return false")
    e.indent -= 1
    emit_line(e, "}")
}

core_helpers_needed :: proc(features: Emitter_Features) -> bool {
    return features.keyword_type ||
           features.data_type ||
           features.core_get_or_default ||
           features.core_contains_value ||
           parallel_helpers_needed(features)
}

emit_core_helper_separator :: proc(e: ^Emitter, emitted: ^bool) {
    if emitted^ {
        emit_raw_newline(e)
    }
    emitted^ = true
}

emit_core_helpers :: proc(e: ^Emitter, features: Emitter_Features) {
    if !core_helpers_needed(features) {
        return
    }

    emit_raw_newline(e)
    emitted := false
    if features.keyword_type {
        emit_core_helper_separator(e, &emitted)
        emit_keyword_type_helper(e)
    }
    if features.data_type {
        emit_core_helper_separator(e, &emitted)
        emit_data_type_helper(e)
        emit_data_literals(e, features.data_literals[:])
    }
    if features.core_get_or_default {
        emit_core_helper_separator(e, &emitted)
        emit_core_get_or_default_helper(e)
    }
    if features.core_contains_value {
        emit_core_helper_separator(e, &emitted)
        emit_core_contains_value_helper(e)
    }
    emit_parallel_helpers(e, features, &emitted)
}

emit_decls :: proc(decls: []IR_Decl) -> (string, Compile_Error, bool) {
    result, err, ok := emit_decls_with_source_map(decls)
    return result.output, err, ok
}

form_uses_core_strings :: proc(form: CST_Form) -> bool {
    if form.kind == .Symbol {
        return strings.has_prefix(form.text, "strings.") || strings.has_prefix(form.text, "strings/")
    }
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if strings.has_prefix(form.items[0].text, "strings.") ||
           strings.has_prefix(form.items[0].text, "strings/") {
            return true
        }
    }
    for item in form.items {
        if form_uses_core_strings(item) {
            return true
        }
    }
    return false
}

form_uses_core_fmt :: proc(form: CST_Form) -> bool {
    if form.kind == .Symbol {
        return strings.has_prefix(form.text, "fmt.") || strings.has_prefix(form.text, "fmt/")
    }
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if strings.has_prefix(form.items[0].text, "fmt.") ||
           strings.has_prefix(form.items[0].text, "fmt/") {
            return true
        }
    }
    for item in form.items {
        if form_uses_core_fmt(item) {
            return true
        }
    }
    return false
}

decls_need_core_strings_import :: proc(decls: []IR_Decl) -> bool {
    for decl in decls {
        if decl.kind == .Import {
            if (!decl.import_decl.has_alias && decl.import_decl.path == "\"core:strings\"") ||
               (decl.import_decl.has_alias && decl.import_decl.alias == "strings" && decl.import_decl.path == "\"core:strings\"") {
                return false
            }
        }
    }
    for decl in decls {
        #partial switch decl.kind {
        case .Const:
            if form_uses_core_strings(decl.const_decl.value) {
                return true
            }
        case .Var:
            if form_uses_core_strings(decl.var_decl.value) {
                return true
            }
        case .Enum:
            for variant in decl.enum_decl.variants {
                if variant.has_value && form_uses_core_strings(variant.value) {
                    return true
                }
            }
        case .Proc:
            for form in decl.proc_decl.body {
                if form_uses_core_strings(form) {
                    return true
                }
            }
        }
    }
    return false
}

decls_need_core_fmt_import :: proc(decls: []IR_Decl) -> bool {
    if decls_have_core_fmt_import(decls) {
        return false
    }
    for decl in decls {
        #partial switch decl.kind {
        case .Const:
            if form_uses_core_fmt(decl.const_decl.value) {
                return true
            }
        case .Var:
            if form_uses_core_fmt(decl.var_decl.value) {
                return true
            }
        case .Enum:
            for variant in decl.enum_decl.variants {
                if variant.has_value && form_uses_core_fmt(variant.value) {
                    return true
                }
            }
        case .Proc:
            for form in decl.proc_decl.body {
                if form_uses_core_fmt(form) {
                    return true
                }
            }
        }
    }
    return false
}

decls_have_core_fmt_import :: proc(decls: []IR_Decl) -> bool {
    for decl in decls {
        if decl.kind == .Import {
            if (!decl.import_decl.has_alias && decl.import_decl.path == "\"core:fmt\"") ||
               (decl.import_decl.has_alias && decl.import_decl.alias == "fmt" && decl.import_decl.path == "\"core:fmt\"") {
                return true
            }
        }
    }
    return false
}

emit_core_strings_import :: proc(e: ^Emitter, emitted: ^bool, needed: bool) {
    if !needed || emitted^ {
        return
    }
    emit_line(e, "import strings \"core:strings\"")
    strings.write_byte(&e.builder, '\n')
    e.line += 1
    emitted^ = true
}

emit_core_fmt_import :: proc(e: ^Emitter, emitted: ^bool, needed: bool) {
    if !needed || emitted^ {
        return
    }
    emit_line(e, "import \"core:fmt\"")
    strings.write_byte(&e.builder, '\n')
    e.line += 1
    emitted^ = true
}

output_needs_core_slice_import :: proc(output: string, features: Emitter_Features) -> bool {
    return strings.contains(output, "kvist_slice.")
}

features_need_core_strings_import :: proc(features: Emitter_Features) -> bool {
    return features.core_strings
}

features_need_core_fmt_import :: proc(features: Emitter_Features) -> bool {
    return features.core_fmt
}

features_need_core_thread_import :: proc(features: Emitter_Features) -> bool {
    return len(features.thread_detaches) > 0 ||
           len(features.thread_starts) > 0
}

features_need_core_chan_import :: proc(features: Emitter_Features) -> bool {
    return len(features.thread_starts) > 0
}

features_need_core_os_import :: proc(features: Emitter_Features) -> bool {
    return false
}

features_need_data_runtime_imports :: proc(features: Emitter_Features) -> bool {
    return features.data_type
}

features_need_base_runtime_import :: proc(features: Emitter_Features) -> bool {
    return features.data_type || features.runtime_defs
}

output_has_import_line :: proc(output, line: string) -> bool {
    start := 0
    for start <= len(output) {
        found := strings.index(output[start:], line)
        if found < 0 {
            return false
        }
        at := start + found
        before_ok := at == 0 || output[at-1] == '\n'
        after_at := at + len(line)
        after_ok := after_at == len(output) || output[after_at] == '\n'
        if before_ok && after_ok {
            return true
        }
        start = at + len(line)
    }
    return false
}

output_has_import_path :: proc(output, path: string) -> bool {
    start := 0
    needle := strings.concatenate({"\"", path, "\""}, context.temp_allocator)
    defer delete(needle)
    for start <= len(output) {
        found := strings.index(output[start:], "import ")
        if found < 0 {
            return false
        }
        at := start + found
        line_end := strings.index(output[at:], "\n")
        if line_end < 0 {
            line_end = len(output) - at
        }
        line_text := output[at : at+line_end]
        if strings.contains(line_text, needle) {
            return true
        }
        start = at + line_end
        if start < len(output) && output[start] == '\n' {
            start += 1
        }
    }
    return false
}

inject_imports_into_output_header :: proc(output: string, imports: []string) -> (string, int) {
    if len(imports) == 0 {
        return strings.clone(output), 0
    }

    insert_at := 0
    offset := 0
    saw_package := false

    for offset < len(output) {
        line_end := strings.index(output[offset:], "\n")
        if line_end < 0 {
            line_end = len(output) - offset
        }
        line_text := output[offset : offset+line_end]
        trimmed := strings.trim_space(line_text)
        next_offset := offset + line_end
        if next_offset < len(output) && output[next_offset] == '\n' {
            next_offset += 1
        }

        if !saw_package {
            if strings.has_prefix(trimmed, "package ") {
                saw_package = true
                insert_at = next_offset
                offset = next_offset
                continue
            }
            if trimmed == "" || strings.has_prefix(trimmed, "#+") || strings.has_prefix(trimmed, "//") {
                offset = next_offset
                continue
            }
            break
        }

        if trimmed == "" || strings.has_prefix(trimmed, "import ") {
            insert_at = next_offset
            offset = next_offset
            continue
        }
        break
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, output[:insert_at])
    for import_line in imports {
        strings.write_string(&builder, import_line)
        strings.write_byte(&builder, '\n')
    }
    strings.write_string(&builder, output[insert_at:])
    return strings.clone(strings.to_string(builder)), len(imports)
}

shift_source_map_lines :: proc(entries: ^[dynamic]Source_Map_Entry, delta: int) {
    if delta == 0 {
        return
    }
    for &entry in entries {
        entry.generated_start_line += delta
        entry.generated_end_line += delta
    }
}

emit_runtime_def_lifecycle :: proc(e: ^Emitter, emitted_decls: []IR_Decl = nil) -> (Compile_Error, bool) {
    lifecycle_decls := emitted_decls
    if lifecycle_decls == nil {
        lifecycle_decls = e.decls
    }
    runtime_count := 0
    managed_count := 0
    for decl in lifecycle_decls {
        if decl.kind == .Const && decl.const_decl.init_kind == .Runtime {
            runtime_count += 1
            if type_text_is_managed_value(e, decl.const_decl.ty) {
                managed_count += 1
            }
        }
    }
    if runtime_count == 0 {
        return {}, true
    }
    e.features.runtime_defs = true

    emit_raw_newline(e)
    emit_line(e, "@(init)")
    emit_line(e, "__kvist_runtime_defs_init :: proc \"contextless\" () {")
    e.indent += 1
    emit_line(e, "context = kvist_runtime.default_context()")
    for decl in lifecycle_decls {
        if decl.kind != .Const || decl.const_decl.init_kind != .Runtime {
            continue
        }
        value, err_value, ok_value := emit_expr_for_expected_type(e, decl.const_decl.value, decl.const_decl.ty)
        if !ok_value {
            return err_value, false
        }
        if type_text_is_managed_value(e, decl.const_decl.ty) {
            mark_data_type(e)
            if !form_produces_owned_managed_type(e, decl.const_decl.value, decl.const_decl.ty) {
                retained := emit_call_text("kvist_data_retain", []string{value})
                delete(value)
                value = retained
            }
        }
        emit_prefixed_expr_mapped(e, fmt.tprintf("%s = ", decl.const_decl.name), value, decl.const_decl.value.span)
        delete(value)
    }
    e.indent -= 1
    emit_line(e, "}")

    if managed_count > 0 {
        emit_raw_newline(e)
        emit_line(e, "@(fini)")
        emit_line(e, "__kvist_runtime_defs_fini :: proc \"contextless\" () {")
        e.indent += 1
        emit_line(e, "context = kvist_runtime.default_context()")
        for offset in 0..<len(lifecycle_decls) {
            decl := lifecycle_decls[len(lifecycle_decls)-1-offset]
            if decl.kind == .Const &&
               decl.const_decl.init_kind == .Runtime &&
               type_text_is_managed_value(e, decl.const_decl.ty) {
                emit_line_mapped(e, fmt.tprintf("kvist_data_release(%s)", decl.const_decl.name), decl.span)
            }
        }
        e.indent -= 1
        emit_line(e, "}")
    }
    return {}, true
}

emit_data_decode_aliases :: proc(e: ^Emitter, features: Emitter_Features) {
    if !features.data_decode {
        return
    }
    selected := ""
    for decl in e.decls {
        if decl.kind != .Struct {
            continue
        }
        name := decl.struct_decl.name
        if name != "data__Decode_Error" && !strings.has_suffix(name, "__data__Decode_Error") {
            continue
        }
        if selected == "" || len(name) < len(selected) {
            selected = name
        }
    }
    if selected == "" || selected == "data__Decode_Error" {
        return
    }
    suffix := "Decode_Error"
    prefix := selected[:len(selected)-len(suffix)]
    emit_raw_newline(e)
    emit_line(e, fmt.tprintf("data__Decode_Error :: %s", selected))
    emit_line(e, fmt.tprintf("data__decode_error :: %sdecode_error", prefix))
    emit_line(e, fmt.tprintf("data__decode_enum_error :: %sdecode_enum_error", prefix))
    emit_line(e, fmt.tprintf("kvist_managed_clone_data__Decode_Error :: kvist_managed_clone_%s", selected))
    emit_line(e, fmt.tprintf("kvist_managed_destroy_data__Decode_Error :: kvist_managed_destroy_%s", selected))
    emit_line(e, fmt.tprintf("kvist_managed_assign_data__Decode_Error :: kvist_managed_assign_%s", selected))
    emit_line(e, fmt.tprintf("kvist_managed_move_assign_data__Decode_Error :: kvist_managed_move_assign_%s", selected))
}
