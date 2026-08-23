// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

lint_defer_in_loop_form :: proc(e: ^Emitter, form: CST_Form, in_loop_scope: bool) {
    if form.kind != .List || len(form.items) == 0 {
        for item in form.items {
            lint_defer_in_loop_form(e, item, in_loop_scope)
        }
        return
    }

    head, ok := form_head_symbol_text(form)
    if !ok {
        for item in form.items {
            lint_defer_in_loop_form(e, item, in_loop_scope)
        }
        return
    }

    if head == "defer" && in_loop_scope {
        emit_coded_warning(
            e,
            "defer inside loop runs when the surrounding scope exits, not after each iteration; wrap the iteration body in block or clean up explicitly",
            form.span,
            .Ownership_Defer_In_Loop,
        )
        return
    }

    switch head {
    case "for":
        if len(form.items) > 2 {
            lint_defer_in_loop_body(e, form.items[2:], true)
        }
        return
    case "while":
        if len(form.items) > 2 {
            lint_defer_in_loop_body(e, form.items[2:], true)
        }
        return
    case "block":
        if len(form.items) > 1 {
            lint_defer_in_loop_body(e, form.items[1:], false)
        }
        return
    case "let", "with-allocator", "with-temp-allocator":
        if len(form.items) > 2 {
            lint_defer_in_loop_body(e, form.items[2:], false)
        }
        return
    }

    for item in form.items[1:] {
        lint_defer_in_loop_form(e, item, in_loop_scope)
    }
}

lint_defer_in_loop_body :: proc(e: ^Emitter, forms: []CST_Form, in_loop_scope: bool) {
    for form in forms {
        lint_defer_in_loop_form(e, form, in_loop_scope)
    }
}

emit_for_in_loop_body :: proc(e: ^Emitter, coll_form: CST_Form, coll_text, first_name, second_name: string, body: []CST_Form) -> (Compile_Error, bool) {
    emit_indent(e)
    strings.write_string(&e.builder, "for ")
    strings.write_string(&e.builder, binding_output_name(first_name))
    prefix_len := len("for ") + len(binding_output_name(first_name))
    if second_name != "" {
        strings.write_string(&e.builder, ", ")
        strings.write_string(&e.builder, binding_output_name(second_name))
        prefix_len += len(", ") + len(binding_output_name(second_name))
    }
    strings.write_string(&e.builder, " in ")
    prefix_len += len(" in ")
    parenthesize_collection := false
    if coll_form.kind == .List &&
       len(coll_form.items) == 2 &&
       (coll_form.items[1].kind == .Vector ||
        coll_form.items[1].kind == .Brace ||
        coll_form.items[1].kind == .Set) {
        if type_text, _, ok_type := parse_type_text(coll_form.items[0]); ok_type {
            delete(type_text)
            parenthesize_collection = true
        }
    }
    if parenthesize_collection {
        strings.write_byte(&e.builder, '(')
        strings.write_string(&e.builder, coll_text)
        strings.write_byte(&e.builder, ')')
        record_current_line_fragment_map(e, prefix_len+1, coll_text, coll_form.span)
    } else {
        strings.write_string(&e.builder, coll_text)
        record_current_line_fragment_map(e, prefix_len, coll_text, coll_form.span)
    }
    strings.write_string(&e.builder, " {")
    emit_raw_newline(e)
    e.indent += 1
    push_local_type_scope(e)
    if coll_ty, ok_coll_ty := obvious_form_type(e, coll_form); ok_coll_ty {
        if key_ty, value_ty, ok_map := map_type_parts(coll_ty); ok_map {
            if second_name == "" {
                bind_local_type(e, first_name, value_ty)
            } else {
                bind_local_type(e, first_name, key_ty)
                bind_local_type(e, second_name, value_ty)
            }
        } else if item_ty, ok_item_ty := collection_element_type(coll_ty); ok_item_ty {
            if second_name == "" {
                bind_local_type(e, first_name, item_ty)
            } else {
                bind_local_type(e, first_name, item_ty)
                bind_local_type(e, second_name, "int")
            }
        }
    }
    err_body, ok_body := emit_body_forms(e, body, Return_Spec{kind = .None})
    pop_local_type_scope(e)
    if !ok_body {
        return err_body, false
    }
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

emit_for_in_loop :: proc(e: ^Emitter, coll_form: CST_Form, first_name, second_name: string, body: []CST_Form) -> (Compile_Error, bool) {
    if !loop_collection_needs_temp_binding(e, coll_form) {
        err_owned, bad_owned := owned_result_usage_error(coll_form, false, e)
        if bad_owned {
            return err_owned, false
        }
        coll, err_coll, ok_coll := emit_expr(e, coll_form)
        if !ok_coll {
            return err_coll, false
        }
        return emit_for_in_loop_body(e, coll_form, coll, first_name, second_name, body)
    }

    coll, err_coll, ok_coll := emit_expr(e, coll_form)
    if !ok_coll {
        return err_coll, false
    }
    e.temp_counter += 1
    temp := fmt.tprintf("kvist_loop_%d", e.temp_counter)
    emit_line(e, "{")
    e.indent += 1
    push_local_type_scope(e)
    emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), coll, coll_form.span)
    emit_line(e, fmt.tprintf("defer delete(%s)", temp))
    err_loop, ok_loop := emit_for_in_loop_body(e, coll_form, temp, first_name, second_name, body)
    pop_local_type_scope(e)
    if !ok_loop {
        return err_loop, false
    }
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

emit_for_data_pattern_body :: proc(e: ^Emitter, pattern: CST_Form, item_name: string, body: []CST_Form, index_name: string = "") -> (Compile_Error, bool) {
    emit_line(e, "{")
    e.indent += 1
    push_local_type_scope(e)
    if index_name != "" {
        bind_local_type(e, index_name, "int")
    }
    err_bind, ok_bind := emit_data_pattern_bindings(e, pattern, item_name)
    if !ok_bind {
        pop_local_type_scope(e)
        return err_bind, false
    }
    err_body, ok_body := emit_body_forms(e, body, Return_Spec{kind = .None})
    pop_local_type_scope(e)
    if !ok_body {
        return err_body, false
    }
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

emit_for_data_pattern_loop :: proc(e: ^Emitter, pattern, coll_form: CST_Form, body: []CST_Form, index_name: string = "") -> (Compile_Error, bool) {
    names: [dynamic]string
    defer delete(names)
    err_pattern, ok_pattern := validate_data_pattern_names(pattern, &names, true)
    if !ok_pattern {
        return err_pattern, false
    }
    coll_ty, ok_coll_ty := obvious_form_type(e, coll_form)
    literal_data_source := coll_form.kind == .Vector || coll_form.kind == .Set
    if literal_data_source {
        coll_ty = "Data"
        ok_coll_ty = true
    }
    if !ok_coll_ty {
        return Compile_Error{message = "Data destructuring for requires a statically known Data collection or native collection of Data", span = coll_form.span}, false
    }
    is_data_source := coll_ty == "Data"
    if !is_data_source {
        if !type_text_is_slice_or_fixed_array(coll_ty) && !type_text_is_dynamic_array(coll_ty) {
            return Compile_Error{message = "Data destructuring for supports native arrays, slices, and dynamic arrays", span = coll_form.span}, false
        }
        item_ty, ok_item_ty := collection_element_type(coll_ty)
        if !ok_item_ty || item_ty != "Data" {
            return Compile_Error{message = "Data destructuring for expects Data elements", span = coll_form.span}, false
        }
    }
    value, err_value, ok_value := emit_expr_for_expected_type(e, coll_form, coll_ty)
    if !ok_value {
        return err_value, false
    }
    mark_data_type(e)
    emit_line(e, "{")
    e.indent += 1
    push_local_type_scope(e)
    collection := thread_temp_name(e)
    if is_data_source {
        emit_owned_data_local(e, collection, value, coll_form.span, form_produces_owned_managed_type(e, coll_form, "Data"))
        emit_line_mapped(e, fmt.tprintf(
            "assert(%s.kind == .Nil || %s.kind == .List || %s.kind == .Vector || %s.kind == .Set, \"Data for source must be nil, list, vector, or set\")",
            collection,
            collection,
            collection,
            collection,
        ), coll_form.span)
        emit_line(e, fmt.tprintf("if %s.kind != .Nil {{", collection))
        e.indent += 1
        item_name := thread_temp_name(e)
        loop_names := item_name
        if index_name != "" {
            loop_names = fmt.tprintf("%s, %s", item_name, index_name)
        }
        emit_line(e, fmt.tprintf("for %s in %s.payload.items {{", loop_names, collection))
        e.indent += 1
        err_body, ok_body := emit_for_data_pattern_body(e, pattern, item_name, body, index_name)
        if !ok_body {
            pop_local_type_scope(e)
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        e.indent -= 1
        emit_line(e, "}")
    } else {
        emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", collection), value, coll_form.span)
        if loop_collection_needs_temp_binding(e, coll_form) {
            emit_line(e, fmt.tprintf("defer delete(%s)", collection))
        }
        item_name := thread_temp_name(e)
        loop_names := item_name
        if index_name != "" {
            loop_names = fmt.tprintf("%s, %s", item_name, index_name)
        }
        emit_line(e, fmt.tprintf("for %s in %s {{", loop_names, collection))
        e.indent += 1
        err_body, ok_body := emit_for_data_pattern_body(e, pattern, item_name, body, index_name)
        if !ok_body {
            pop_local_type_scope(e)
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
    }
    pop_local_type_scope(e)
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

emit_source_each_loop :: proc(e: ^Emitter, source_form: CST_Form, source: ^Source_Decl, value_name, index_name: string, body: []CST_Form) -> (Compile_Error, bool) {
    state_ty, err_state_ty, ok_state_ty := source_state_type(e, source)
    if !ok_state_ty {
        return err_state_ty, false
    }
    err_protocol, ok_protocol := validate_source_protocol(e, source, state_ty, source_form.span)
    if !ok_protocol {
        return err_protocol, false
    }
    arg_texts, err_args, ok_args := source_call_arg_texts(e, source, source_form)
    if !ok_args {
        return err_args, false
    }
    item_ty, err_item_ty, ok_item_ty := source_call_item_type(e, source, source_form)
    if !ok_item_ty {
        return err_item_ty, false
    }
    source_text := source_call_text(e, source, arg_texts[:])
    temp := source_temp_name(e)
    ok_name := source_ok_name(e)
    source_index := ""
    if index_name != "" {
        source_index = loop_temp_name(e, "source_index")
    }

    emit_line(e, "{")
    e.indent += 1
    push_local_type_scope(e)
    emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), source_text, source_form.span)
    if source.has_dispose {
        emit_line(e, fmt.tprintf("defer %s(&%s)", source.dispose_name, temp))
    }
    if source_index != "" {
        emit_line(e, fmt.tprintf("%s := 0", source_index))
    }
    emit_line(e, "for {")
    e.indent += 1
    emit_line(e, fmt.tprintf("%s, %s := %s(&%s)", binding_output_name(value_name), ok_name, source.next_name, temp))
    emit_line(e, fmt.tprintf("if !%s %s", ok_name, "{"))
    e.indent += 1
    emit_line(e, "break")
    e.indent -= 1
    emit_line(e, "}")
    push_local_type_scope(e)
    if source_index != "" {
        emit_loop_binding_assignment(e, index_name, source_index)
    }
    if !is_discard_binding_name(value_name) {
        bind_local_type(e, value_name, item_ty)
    }
    if !is_discard_binding_name(index_name) {
        bind_local_type(e, index_name, "int")
    }
    err_body, ok_body := emit_body_forms(e, body, Return_Spec{kind = .None})
    pop_local_type_scope(e)
    if !ok_body {
        return err_body, false
    }
    if source_index != "" {
        emit_line(e, fmt.tprintf("%s += 1", source_index))
    }
    e.indent -= 1
    emit_line(e, "}")
    pop_local_type_scope(e)
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

emit_transform_for_body :: proc(e: ^Emitter, steps: []Transform_Step, initial_text, initial_ty, index_name, value_name, key_name, key_ty: string, body: []CST_Form) -> (Compile_Error, bool) {
    base_indent := e.indent
    value_text, value_ty, close_count, err_pipeline, ok_pipeline := emit_transform_pipeline_body(e, &e.builder, steps, initial_text, initial_ty, base_indent)
    if !ok_pipeline {
        return err_pipeline, false
    }

    e.indent = base_indent + close_count
    emit_loop_binding_assignment(e, value_name, value_text)
    push_local_type_scope(e)
    if !is_discard_binding_name(index_name) {
        bind_local_type(e, index_name, "int")
    }
    if !is_discard_binding_name(key_name) {
        bind_local_type(e, key_name, key_ty)
    }
    if !is_discard_binding_name(value_name) {
        bind_local_type(e, value_name, value_ty)
    }
    err_body, ok_body := emit_body_forms(e, body, Return_Spec{kind = .None})
    pop_local_type_scope(e)
    e.indent = base_indent
    if !ok_body {
        return err_body, false
    }
    if !is_discard_binding_name(index_name) {
        e.indent = base_indent + close_count
        emit_line(e, fmt.tprintf("%s += 1", index_name))
        e.indent = base_indent
    }
    emit_transform_closers(&e.builder, base_indent+close_count, close_count)
    return {}, true
}

emit_transform_for_collection_loop_body :: proc(e: ^Emitter, coll_form: CST_Form, coll_text, coll_ty, index_name, value_name: string, transform_form: CST_Form, body: []CST_Form) -> (Compile_Error, bool) {
    source_elem_ty, ok_source_elem_ty := transform_source_value_type(coll_ty)
    if !ok_source_elem_ty {
        return Compile_Error{message = fmt.tprintf("for :transform expects slice, array, or map source, got %s", coll_ty), span = coll_form.span}, false
    }
    key_name := ""
    key_ty := ""
    loop_index_name := index_name
    if map_key_ty, _, ok_map := map_type_parts(coll_ty); ok_map {
        key_ty = map_key_ty
        key_name = index_name
        loop_index_name = ""
    }
    steps, err_steps, ok_steps := parse_transform_steps(e, transform_form)
    if !ok_steps {
        return err_steps, false
    }
    err_prelude, ok_prelude := emit_transform_state_prelude(e, &e.builder, steps[:], e.indent)
    if !ok_prelude {
        return err_prelude, false
    }
    if !is_discard_binding_name(loop_index_name) {
        emit_line(e, fmt.tprintf("%s := 0", loop_index_name))
    }
    emit_line(e, transform_source_loop_header(coll_ty, coll_text, key_name))
    e.indent += 1
    err_body, ok_body := emit_transform_for_body(e, steps[:], "kvist_item", source_elem_ty, loop_index_name, value_name, key_name, key_ty, body)
    e.indent -= 1
    if !ok_body {
        return err_body, false
    }
    emit_line(e, "}")
    return {}, true
}

emit_transform_for_collection_loop :: proc(e: ^Emitter, coll_form: CST_Form, index_name, value_name: string, transform_form: CST_Form, body: []CST_Form) -> (Compile_Error, bool) {
    if form_is_transform_loop_call(coll_form) {
        spec, err_spec, ok_spec := transform_loop_source(e, coll_form)
        if !ok_spec {
            return err_spec, false
        }
        steps, err_steps, ok_steps := parse_transform_steps(e, transform_form)
        if !ok_steps {
            return err_steps, false
        }
        err_prelude, ok_prelude := emit_transform_state_prelude(e, &e.builder, steps[:], e.indent)
        if !ok_prelude {
            return err_prelude, false
        }
        if !is_discard_binding_name(index_name) {
            emit_line(e, fmt.tprintf("%s := 0", index_name))
        }
        emit_line(e, fmt.tprintf("for %s, %s in %s %s", spec.key_name, spec.value_name, spec.source_text, "{"))
        e.indent += 1
        emit_line(e, fmt.tprintf("kvist_item := %s", spec.item_text))
        err_body, ok_body := emit_transform_for_body(e, steps[:], "kvist_item", spec.item_ty, index_name, value_name, "", "", body)
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    }
    coll_ty, ok_coll_ty := obvious_form_type(e, coll_form)
    if !ok_coll_ty {
        return Compile_Error{message = "for :transform expects a collection with an obvious type; bind or annotate it first", span = coll_form.span}, false
    }
    if !loop_collection_needs_temp_binding(e, coll_form) {
        err_owned, bad_owned := owned_result_usage_error(coll_form, false, e)
        if bad_owned {
            return err_owned, false
        }
        coll, err_coll, ok_coll := emit_expr(e, coll_form)
        if !ok_coll {
            return err_coll, false
        }
        return emit_transform_for_collection_loop_body(e, coll_form, coll, coll_ty, index_name, value_name, transform_form, body)
    }

    coll, err_coll, ok_coll := emit_expr(e, coll_form)
    if !ok_coll {
        return err_coll, false
    }
    e.temp_counter += 1
    temp := fmt.tprintf("kvist_loop_%d", e.temp_counter)
    emit_line(e, "{")
    e.indent += 1
    push_local_type_scope(e)
    emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), coll, coll_form.span)
    emit_line(e, fmt.tprintf("defer delete(%s)", temp))
    err_loop, ok_loop := emit_transform_for_collection_loop_body(e, coll_form, temp, coll_ty, index_name, value_name, transform_form, body)
    pop_local_type_scope(e)
    if !ok_loop {
        return err_loop, false
    }
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

emit_transform_for_source_loop :: proc(e: ^Emitter, source_form: CST_Form, source: ^Source_Decl, index_name, value_name: string, transform_form: CST_Form, body: []CST_Form) -> (Compile_Error, bool) {
    state_ty, err_state_ty, ok_state_ty := source_state_type(e, source)
    if !ok_state_ty {
        return err_state_ty, false
    }
    err_protocol, ok_protocol := validate_source_protocol(e, source, state_ty, source_form.span)
    if !ok_protocol {
        return err_protocol, false
    }
    arg_texts, err_args, ok_args := source_call_arg_texts(e, source, source_form)
    if !ok_args {
        return err_args, false
    }
    item_ty, err_item_ty, ok_item_ty := source_call_item_type(e, source, source_form)
    if !ok_item_ty {
        return err_item_ty, false
    }
    steps, err_steps, ok_steps := parse_transform_steps(e, transform_form)
    if !ok_steps {
        return err_steps, false
    }
    source_text := source_call_text(e, source, arg_texts[:])
    temp := source_temp_name(e)
    ok_name := source_ok_name(e)

    emit_line(e, "{")
    e.indent += 1
    push_local_type_scope(e)
    emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), source_text, source_form.span)
    if source.has_dispose {
        emit_line(e, fmt.tprintf("defer %s(&%s)", source.dispose_name, temp))
    }
    err_prelude, ok_prelude := emit_transform_state_prelude(e, &e.builder, steps[:], e.indent)
    if !ok_prelude {
        return err_prelude, false
    }
    if !is_discard_binding_name(index_name) {
        emit_line(e, fmt.tprintf("%s := 0", index_name))
    }
    emit_line(e, "for {")
    e.indent += 1
    emit_line(e, fmt.tprintf("kvist_item, %s := %s(&%s)", ok_name, source.next_name, temp))
    emit_line(e, fmt.tprintf("if !%s %s", ok_name, "{"))
    e.indent += 1
    emit_line(e, "break")
    e.indent -= 1
    emit_line(e, "}")
    err_body, ok_body := emit_transform_for_body(e, steps[:], "kvist_item", item_ty, index_name, value_name, "", "", body)
    e.indent -= 1
    if !ok_body {
        return err_body, false
    }
    emit_line(e, "}")
    pop_local_type_scope(e)
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

is_plain_identifier_text :: proc(text: string) -> bool {
    if len(text) == 0 {
        return false
    }
    for ch, idx in text {
        alpha := (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
        digit := ch >= '0' && ch <= '9'
        if !(alpha || digit || ch == '_') {
            return false
        }
        if idx == 0 && digit {
            return false
        }
    }
    return true
}

emit_proc_literal_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) < 2 || !is_symbol(form.items[0], "fn") || form.items[1].kind != .Vector {
        return "", Compile_Error{message = "invalid function literal", span = form.span}, false
    }

    parsed, err_parse, ok_parse := parse_proc_literal_form(form)
    if !ok_parse {
        return "", err_parse, false
    }
    return emit_proc_literal_text(e, parsed.params[:], parsed.returns, parsed.body[:])
}

Proc_Literal :: struct {
    params:  [dynamic]Param,
    returns: Return_Spec,
    body:    [dynamic]CST_Form,
}

parse_proc_literal_form :: proc(form: CST_Form) -> (Proc_Literal, Compile_Error, bool) {
    if len(form.items) < 2 || !is_symbol(form.items[0], "fn") || form.items[1].kind != .Vector {
        return Proc_Literal{}, Compile_Error{message = "invalid function literal", span = form.span}, false
    }

    params, err_params, ok_params := parse_param_vector(form.items[1])
    if !ok_params {
        return Proc_Literal{}, err_params, false
    }

    body_index := 2
    returns := Return_Spec{kind = .None}
    if body_index < len(form.items) && is_symbol(form.items[body_index], "->") {
        if body_index+1 >= len(form.items) {
            return Proc_Literal{}, Compile_Error{message = "missing function literal return spec", span = form.items[body_index].span}, false
        }
        return_form := form.items[body_index+1]
        #partial switch return_form.kind {
        case .Vector:
            if vector_is_named_returns(return_form) {
                named, err_named, ok_named := parse_named_returns(return_form)
                if !ok_named {
                    return Proc_Literal{}, err_named, false
                }
                returns.kind = .Named
                returns.named = named
                body_index += 2
            } else {
                return_text, next_index, err_return, ok_return := parse_type_text_from_forms(form.items[:], body_index+1)
                if !ok_return {
                    return Proc_Literal{}, err_return, false
                }
                returns.kind = .Single
                returns.single_ty = return_text
                body_index = next_index
            }
        case .Symbol, .List, .Keyword:
            return_text, next_index, err_return, ok_return := parse_type_text_from_forms(form.items[:], body_index+1)
            if !ok_return {
                return Proc_Literal{}, err_return, false
            }
            returns.kind = .Single
            returns.single_ty = return_text
            body_index = next_index
        case:
            return Proc_Literal{}, Compile_Error{message = "unsupported function literal return spec", span = return_form.span}, false
        }
    }
    if body_index >= len(form.items) {
        return Proc_Literal{}, Compile_Error{message = "function literal body is empty", span = form.span}, false
    }

    body: [dynamic]CST_Form
    for item in form.items[body_index:] {
        append(&body, item)
    }
    return Proc_Literal{
        params  = params,
        returns = returns,
        body    = body,
    }, Compile_Error{}, true
}

emit_proc_literal_text :: proc(e: ^Emitter, params: []Param, returns: Return_Spec, body: []CST_Form) -> (string, Compile_Error, bool) {
    for param in params {
        mark_keyword_type_for_text(e, param.ty)
    }
    mark_keyword_type_for_return_spec(e, returns)
    sub := Emitter{
        builder     = strings.builder_make(),
        indent      = 1,
        decls       = e.decls,
        structs     = e.structs,
        unions      = e.unions,
        local_structs = e.local_structs,
        local_unions  = e.local_unions,
        features    = e.features,
        source_map  = e.source_map,
        warnings    = e.warnings,
        line        = e.line,
        temp_counter = e.temp_counter,
        captured_proc_specializations = e.captured_proc_specializations,
        current_proc_returns = returns,
        repl_value_names = e.repl_value_names,
        repl_var_names = e.repl_var_names,
        repl_debug_enabled = e.repl_debug_enabled,
        repl_debug_capture_values = e.repl_debug_capture_values,
    }
    defer strings.builder_destroy(&sub.builder)

    for local in e.local_types {
        bind_local_type(&sub, local.name, local.ty)
    }
    for param in params {
        bind_local_type(&sub, param.name, param.ty)
    }

    strings.write_string(&sub.builder, "proc(")
    for param, idx in params {
        if idx > 0 {
            strings.write_string(&sub.builder, ", ")
        }
        fmt.sbprintf(&sub.builder, "%s: %s", param.name, param.ty)
    }
    strings.write_byte(&sub.builder, ')')
    emit_return_spec(&sub, returns)
    strings.write_string(&sub.builder, " {\n")
    debug_emit_proc_frame_scope(&sub)
    err_body, ok_body := emit_body_forms(&sub, body, returns)
    if !ok_body {
        return "", err_body, false
    }
    strings.write_string(&sub.builder, "}")
    return strings.clone(strings.to_string(sub.builder)), {}, true
}

name_in_list :: proc(names: []string, name: string) -> bool {
    for existing in names {
        if existing == name {
            return true
        }
    }
    return false
}

append_capture_param_unique :: proc(captures: ^[dynamic]Param, capture: Param) {
    for existing in captures^ {
        if existing.name == capture.name {
            return
        }
    }
    append(captures, capture)
}

collect_proc_literal_captures :: proc(e: ^Emitter, body: []CST_Form, param_names: []string) -> (captures: [dynamic]Param) {
    for form in body {
        collect_proc_literal_captures_from_form(e, form, param_names, &captures)
    }
    return captures
}

collect_proc_literal_captures_from_form :: proc(e: ^Emitter, form: CST_Form, bound_names: []string, captures: ^[dynamic]Param) {
    #partial switch form.kind {
    case .Symbol:
        name := map_name(form.text)
        if name_in_list(bound_names, name) {
            return
        }
        if ty, ok := lookup_local_type(e, name); ok {
            append_capture_param_unique(captures, Param{name = name, ty = ty})
            return
        }
        // Field selectors are represented as one symbol. Capture the typed
        // local at the selector root so block expressions can read fields of
        // parameters and locals inside their generated proc literal.
        if dot := strings.index(name, "."); dot > 0 {
            root := name[:dot]
            if !name_in_list(bound_names, root) {
                if ty, ok := lookup_local_type(e, root); ok {
                    append_capture_param_unique(captures, Param{name = root, ty = ty})
                }
            }
        }
    case .List:
        if len(form.items) > 0 && is_symbol(form.items[0], "fn") {
            return
        }
        if len(form.items) >= 4 && is_symbol(form.items[0], "match") {
            collect_proc_literal_captures_from_form(e, form.items[1], bound_names, captures)
            for i := 2; i+1 < len(form.items); i += 2 {
                names: [dynamic]string
                if _, ok_pattern := validate_match_pattern(form.items[i], &names); !ok_pattern {
                    delete(names)
                    continue
                }
                arm_bound: [dynamic]string
                for name in bound_names {
                    append(&arm_bound, name)
                }
                for name in names {
                    append(&arm_bound, name)
                }
                collect_proc_literal_captures_from_form(e, form.items[i+1], arm_bound[:], captures)
                delete(arm_bound)
                delete(names)
            }
            return
        }
        if len(form.items) > 1 && is_symbol(form.items[0], "let") {
            bindings, _, ok_bindings := parse_let_bindings(form.items[1])
            names: [dynamic]string
            for name in bound_names {
                append(&names, name)
            }
            for binding in bindings {
                collect_proc_literal_captures_from_form(e, binding.value, names[:], captures)
                if binding.name != "" {
                    append(&names, binding.name)
                } else if binding.target.kind == .Vector || binding.target.kind == .Brace {
                    pattern_names: [dynamic]string
                    if _, ok_pattern := validate_data_pattern_names(binding.target, &pattern_names, true); ok_pattern {
                        for pattern_name in pattern_names {
                            append(&names, pattern_name)
                        }
                    }
                    delete(pattern_names)
                }
            }
            for item in form.items[2:] {
                collect_proc_literal_captures_from_form(e, item, names[:], captures)
            }
            return
        }
        for item in form.items {
            collect_proc_literal_captures_from_form(e, item, bound_names, captures)
        }
    case .Vector, .Brace, .Set:
        for item in form.items {
            collect_proc_literal_captures_from_form(e, item, bound_names, captures)
        }
    case:
    }
}

Captured_Callback_Kind :: enum {
    Value,
    Predicate,
    Keep,
}

captured_unary_callback_proc :: proc(e: ^Emitter, callback: CST_Form, helper_name: string, kind: Captured_Callback_Kind) -> (proc_text: string, capture_names: [dynamic]string, captured: bool, err: Compile_Error, ok: bool) {
    if callback.kind != .List || len(callback.items) == 0 || !is_symbol(callback.items[0], "fn") {
        return "", capture_names, false, Compile_Error{}, true
    }
    parsed, err_parse, ok_parse := parse_proc_literal_form(callback)
    if !ok_parse {
        return "", capture_names, false, err_parse, false
    }
    if len(parsed.params) != 1 {
        return "", capture_names, false, Compile_Error{message = fmt.tprintf("capturing %s callback currently expects exactly one parameter", helper_name), span = callback.span}, false
    }
    switch kind {
    case .Value:
        if parsed.returns.kind != .Single {
            return "", capture_names, false, Compile_Error{message = fmt.tprintf("capturing %s callback currently requires an explicit single return type", helper_name), span = callback.span}, false
        }
    case .Predicate:
        if parsed.returns.kind != .Single || parsed.returns.single_ty != "bool" {
            return "", capture_names, false, Compile_Error{message = fmt.tprintf("capturing %s callback currently requires an explicit bool return type", helper_name), span = callback.span}, false
        }
    case .Keep:
        if parsed.returns.kind != .Named || len(parsed.returns.named) != 2 || parsed.returns.named[1].ty != "bool" {
            return "", capture_names, false, Compile_Error{message = fmt.tprintf("capturing %s callback currently requires explicit named returns [value: T, ok: bool]", helper_name), span = callback.span}, false
        }
    }
    param_names := []string{parsed.params[0].name}
    captures := collect_proc_literal_captures(e, parsed.body[:], param_names)
    if len(captures) == 0 {
        return "", capture_names, false, Compile_Error{}, true
    }
    params: [dynamic]Param
    for capture in captures {
        append(&params, capture)
        append(&capture_names, capture.name)
    }
    append(&params, parsed.params[0])
    proc_text_value, err_proc, ok_proc := emit_proc_literal_text(e, params[:], parsed.returns, parsed.body[:])
    if !ok_proc {
        return "", capture_names, false, err_proc, false
    }
    return proc_text_value, capture_names, true, Compile_Error{}, true
}

return_spec_text :: proc(returns: Return_Spec) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    switch returns.kind {
    case .None:
    case .Single:
        fmt.sbprintf(&builder, " -> %s", returns.single_ty)
    case .Named:
        strings.write_string(&builder, " -> (")
        for field, idx in returns.named {
            if idx > 0 {
                strings.write_string(&builder, ", ")
            }
            fmt.sbprintf(&builder, "%s: %s", field.name, field.ty)
        }
        strings.write_byte(&builder, ')')
    }
    return strings.clone(strings.to_string(builder))
}

proc_type_with_capture_params_text :: proc(capture_count: int, params: []Param, returns: Return_Spec) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "proc(")
    for idx in 0..<capture_count {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "c%d: $C%d", idx+1, idx+1)
    }
    for param, idx in params {
        if capture_count > 0 || idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "%s: %s", param.name, param.ty)
    }
    strings.write_byte(&builder, ')')
    ret := return_spec_text(returns)
    defer delete(ret)
    strings.write_string(&builder, ret)
    return strings.clone(strings.to_string(builder))
}

proc_type_insert_capture_params_text :: proc(proc_ty: string, capture_count: int) -> (string, bool) {
    if !strings.has_prefix(proc_ty, "proc(") {
        return "", false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "proc(")
    for idx in 0..<capture_count {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "c%d: $C%d", idx+1, idx+1)
    }
    rest := proc_ty[len("proc("):]
    if capture_count > 0 && len(rest) > 0 && rest[0] != ')' {
        strings.write_string(&builder, ", ")
    }
    strings.write_string(&builder, rest)
    return strings.clone(strings.to_string(builder)), true
}

captured_proc_literal_for_param :: proc(e: ^Emitter, callback: CST_Form) -> (proc_text: string, capture_names: [dynamic]string, parsed: Proc_Literal, captured: bool, err: Compile_Error, ok: bool) {
    if callback.kind != .List || len(callback.items) == 0 || !is_symbol(callback.items[0], "fn") {
        return "", capture_names, parsed, false, Compile_Error{}, true
    }
    parsed_value, err_parse, ok_parse := parse_proc_literal_form(callback)
    if !ok_parse {
        return "", capture_names, parsed, false, err_parse, false
    }
    parsed = parsed_value
    param_names: [dynamic]string
    for param in parsed.params {
        append(&param_names, param.name)
    }
    captures := collect_proc_literal_captures(e, parsed.body[:], param_names[:])
    if len(captures) == 0 {
        return "", capture_names, parsed, false, Compile_Error{}, true
    }

    params: [dynamic]Param
    for capture in captures {
        append(&params, capture)
        append(&capture_names, capture.name)
    }
    for param in parsed.params {
        append(&params, param)
    }
    proc_text_value, err_proc, ok_proc := emit_proc_literal_text(e, params[:], parsed.returns, parsed.body[:])
    if !ok_proc {
        return "", capture_names, parsed, false, err_proc, false
    }
    return proc_text_value, capture_names, parsed, true, Compile_Error{}, true
}

type_text_is_proc :: proc(ty: string) -> bool {
    return strings.has_prefix(ty, "proc(")
}

worker_arg_callback_is_non_escaping :: proc(e: ^Emitter, worker_decl: ^Proc_Decl, worker_args: []CST_Form, callback_name: string, arg_idx, depth: int) -> bool {
    if worker_decl == nil || arg_idx < 0 || arg_idx >= len(worker_decl.params) || arg_idx >= len(worker_args) {
        return false
    }
    arg := worker_args[arg_idx]
    if arg.kind != .Symbol {
        return false
    }
    arg_name := map_name(arg.text)
    defer delete(arg_name)
    if arg_name != callback_name {
        return false
    }
    if !type_text_is_proc(worker_decl.params[arg_idx].ty) {
        return false
    }
    return proc_callback_param_non_escaping_depth(e, worker_decl, arg_idx, depth+1)
}

thread_launch_callback_arg_is_non_escaping :: proc(e: ^Emitter, form: CST_Form, callback_name: string, worker_index, args_start, arg_idx, depth: int) -> bool {
    if worker_index >= len(form.items) || args_start > len(form.items) {
        return false
    }
    worker_form := form.items[worker_index]
    if worker_form.kind != .Symbol {
        return false
    }
    _, worker_decl, ok_worker := resolve_proc_call_decl(e, worker_form.text)
    if !ok_worker {
        return false
    }
    return worker_arg_callback_is_non_escaping(e, worker_decl, form.items[args_start:], callback_name, arg_idx, depth)
}

callback_symbol_escapes_form :: proc(e: ^Emitter, callback_name: string, form: CST_Form, depth: int) -> bool {
    #partial switch form.kind {
    case .Symbol:
        return map_name(form.text) == callback_name
    case .List:
        if len(form.items) == 0 {
            return false
        }
        if form.items[0].kind == .Symbol {
            head := form.items[0].text
            head_name := map_name(head)
            if head_name == callback_name {
                for arg in form.items[1:] {
                    if callback_symbol_escapes_form(e, callback_name, arg, depth) {
                        return true
                    }
                }
                return false
            }
            if head == "thread-start" && len(form.items) >= 3 {
                for item, idx in form.items[3:] {
                    if thread_launch_callback_arg_is_non_escaping(e, form, callback_name, 2, 3, idx, depth) {
                        continue
                    }
                    if callback_symbol_escapes_form(e, callback_name, item, depth) {
                        return true
                    }
                }
                return false
            }
            if head == "thread-detach" && len(form.items) >= 2 {
                for item, idx in form.items[2:] {
                    if thread_launch_callback_arg_is_non_escaping(e, form, callback_name, 1, 2, idx, depth) {
                        continue
                    }
                    if callback_symbol_escapes_form(e, callback_name, item, depth) {
                        return true
                    }
                }
                return false
            }
            if _, callee, ok_callee := resolve_proc_call_decl(e, head); ok_callee {
                for item, idx in form.items[1:] {
                    if worker_arg_callback_is_non_escaping(e, callee, form.items[1:], callback_name, idx, depth) {
                        continue
                    }
                    if callback_symbol_escapes_form(e, callback_name, item, depth) {
                        return true
                    }
                }
                return false
            }
        }
        for item in form.items {
            if callback_symbol_escapes_form(e, callback_name, item, depth) {
                return true
            }
        }
    case .Vector, .Brace, .Set:
        for item in form.items {
            if callback_symbol_escapes_form(e, callback_name, item, depth) {
                return true
            }
        }
    case:
    }
    return false
}

proc_callback_param_non_escaping_depth :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, callback_param_index: int, depth: int) -> bool {
    if depth > 8 {
        return false
    }
    if callback_param_index < 0 || callback_param_index >= len(proc_decl.params) {
        return false
    }
    callback_name := proc_decl.params[callback_param_index].name
    for form in proc_decl.body {
        if callback_symbol_escapes_form(e, callback_name, form, depth) {
            return false
        }
    }
    return true
}

proc_callback_param_non_escaping :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, callback_param_index: int) -> bool {
    return proc_callback_param_non_escaping_depth(e, proc_decl, callback_param_index, 0)
}

captured_specialization_name :: proc(proc_name: string, callback_param_index, capture_count: int) -> string {
    return fmt.tprintf("%s__kvist_capture_%d_%d", proc_name, callback_param_index, capture_count)
}

field_specialization_name :: proc(proc_name: string, callback_param_index: int, field: string) -> string {
    return fmt.tprintf("%s__kvist_field_%d_%s", proc_name, callback_param_index, field)
}

proc_specialization_name :: proc(spec: Captured_Proc_Specialization) -> string {
    if len(spec.field_callbacks) == 1 {
        field := spec.field_callbacks[0]
        return field_specialization_name(spec.original_name, field.callback_param_index, field.field_selector)
    }
    if len(spec.field_callbacks) > 1 {
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        strings.write_string(&builder, spec.original_name)
        for field in spec.field_callbacks {
            fmt.sbprintf(&builder, "__kvist_field_%d_%s", field.callback_param_index, field.field_selector)
        }
        return strings.clone(strings.to_string(builder))
    }
    if spec.field_selector != "" {
        return field_specialization_name(spec.original_name, spec.callback_param_index, spec.field_selector)
    }
    return captured_specialization_name(spec.original_name, spec.callback_param_index, spec.capture_count)
}

mark_proc_specialization :: proc(e: ^Emitter, proc_name: string, callback_param_index, capture_count: int, field_selector: string) {
    if e.captured_proc_specializations == nil {
        return
    }
    for spec in e.captured_proc_specializations^ {
        if spec.original_name == proc_name &&
           spec.callback_param_index == callback_param_index &&
           spec.capture_count == capture_count &&
           spec.field_selector == field_selector {
            return
        }
    }
    append(e.captured_proc_specializations, Captured_Proc_Specialization{
        original_name = proc_name,
        callback_param_index = callback_param_index,
        capture_count = capture_count,
        field_selector = field_selector,
    })
}

mark_field_proc_specializations :: proc(e: ^Emitter, proc_name: string, fields: []Field_Proc_Specialization) {
    if e.captured_proc_specializations == nil {
        return
    }
    for spec in e.captured_proc_specializations^ {
        if spec.original_name == proc_name &&
           spec.capture_count == 0 &&
           spec.field_selector == "" &&
           field_proc_specializations_match(spec.field_callbacks[:], fields) {
            return
        }
    }

    copied: [dynamic]Field_Proc_Specialization
    for field in fields {
        append(&copied, field)
    }
    append(e.captured_proc_specializations, Captured_Proc_Specialization{
        original_name = proc_name,
        field_callbacks = copied,
    })
}

mark_captured_proc_specialization :: proc(e: ^Emitter, proc_name: string, callback_param_index, capture_count: int) {
    mark_proc_specialization(e, proc_name, callback_param_index, capture_count, "")
}

mark_field_proc_specialization :: proc(e: ^Emitter, proc_name: string, callback_param_index: int, field: string) {
    mark_proc_specialization(e, proc_name, callback_param_index, 0, field)
}

field_callback_for_param :: proc(fields: []Field_Proc_Specialization, param_index: int) -> (Field_Proc_Specialization, bool) {
    for field in fields {
        if field.callback_param_index == param_index {
            return field, true
        }
    }
    return {}, false
}

emit_odin_operator_arg_texts :: proc(e: ^Emitter, form: CST_Form, start: int) -> (arg_texts: [dynamic]string, err: Compile_Error, ok: bool) {
    for arg in form.items[start:] {
        value, err_value, ok_value := emit_expr(e, arg)
        if !ok_value {
            return arg_texts, err_value, false
        }
        append(&arg_texts, value)
    }
    return arg_texts, {}, true
}

emit_odin_infix_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) < 4 || form.items[1].kind != .String {
        return "", Compile_Error{message = "odin-infix expects an operator string and at least two arguments", span = form.span}, false
    }
    op := unquote_string(form.items[1].text)
    defer delete(op)
    arg_texts, err_args, ok_args := emit_odin_operator_arg_texts(e, form, 2)
    if !ok_args {
        return "", err_args, false
    }
    defer delete(arg_texts)

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for arg_text, idx in arg_texts {
        if idx > 0 {
            fmt.sbprintf(&builder, " %s ", op)
        }
        fmt.sbprintf(&builder, "(%s)", arg_text)
    }
    return strings.clone(strings.to_string(builder)), {}, true
}

emit_odin_prefix_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 3 || form.items[1].kind != .String {
        return "", Compile_Error{message = "odin-prefix expects an operator string and one argument", span = form.span}, false
    }
    op := unquote_string(form.items[1].text)
    defer delete(op)
    value, err_value, ok_value := emit_expr(e, form.items[2])
    if !ok_value {
        return "", err_value, false
    }
    return fmt.tprintf("%s(%s)", op, value), {}, true
}

emit_odin_call_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) < 2 || form.items[1].kind != .String {
        return "", Compile_Error{message = "odin-call expects a callee string and optional arguments", span = form.span}, false
    }
    callee := unquote_string(form.items[1].text)
    defer delete(callee)
    if callee == "len" && len(form.items) == 3 {
        if ty, ok_ty := obvious_form_type(e, form.items[2]); ok_ty && ty == "Data" {
            value, err_value, ok_value := emit_expr(e, form.items[2])
            if !ok_value {
                return "", err_value, false
            }
            mark_data_type(e)
            return emit_call_text("kvist_data_count", []string{value}), Compile_Error{}, true
        }
    }
    arg_texts, err_args, ok_args := emit_odin_operator_arg_texts(e, form, 2)
    if !ok_args {
        return "", err_args, false
    }
    defer delete(arg_texts)
    return emit_call_text(callee, arg_texts[:]), {}, true
}

emit_operator_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    head := form.items[0]
    if head.kind != .Symbol {
        return "", {}, false
    }

    op := head.text
    if canonical_op, _, _, ok := resolve_kvist_head(e, op); ok {
        op = canonical_op
    }
    if op == "not" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "not expects one argument", span = form.span}, false
        }
        value, err_value, ok_value := emit_expr(e, form.items[1])
        if !ok_value {
            return "", err_value, false
        }
        return fmt.tprintf("!(%s)", value), {}, true
    }

    if op == "and" || op == "or" {
        if len(form.items) < 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects at least two arguments", op), span = form.span}, false
        }
        joiner := " && "
        if op == "or" {
            joiner = " || "
        }
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        for arg, idx in form.items[1:] {
            if idx > 0 {
                strings.write_string(&builder, joiner)
            }
            value, err_value, ok_value := emit_expr(e, arg)
            if !ok_value {
                return "", err_value, false
            }
            fmt.sbprintf(&builder, "(%s)", value)
        }
        return strings.clone(strings.to_string(builder)), {}, true
    }

    if op == "+" || op == "*" || op == "/" || op == "%" {
        if len(form.items) < 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects at least two arguments", op), span = form.span}, false
        }
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        for arg, idx in form.items[1:] {
            if idx > 0 {
                fmt.sbprintf(&builder, " %s ", op)
            }
            value, err_value, ok_value := emit_expr(e, arg)
            if !ok_value {
                return "", err_value, false
            }
            fmt.sbprintf(&builder, "(%s)", value)
        }
        return strings.clone(strings.to_string(builder)), {}, true
    }

    if op == "min" || op == "max" {
        if len(form.items) < 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects at least two arguments", op), span = form.span}, false
        }
        result, err_result, ok_result := emit_expr(e, form.items[1])
        if !ok_result {
            return "", err_result, false
        }
        for arg in form.items[2:] {
            value, err_value, ok_value := emit_expr(e, arg)
            if !ok_value {
                return "", err_value, false
            }
            result = fmt.tprintf("%s(%s, %s)", op, result, value)
        }
        return result, {}, true
    }

    if op == "-" {
        if len(form.items) == 2 {
            value, err_value, ok_value := emit_expr(e, form.items[1])
            if !ok_value {
                return "", err_value, false
            }
            return fmt.tprintf("-(%s)", value), {}, true
        }
        if len(form.items) >= 3 {
            builder := strings.builder_make()
            defer strings.builder_destroy(&builder)
            for arg, idx in form.items[1:] {
                if idx > 0 {
                    strings.write_string(&builder, " - ")
                }
                value, err_value, ok_value := emit_expr(e, arg)
                if !ok_value {
                    return "", err_value, false
                }
                fmt.sbprintf(&builder, "(%s)", value)
            }
            return strings.clone(strings.to_string(builder)), {}, true
        }
        return "", Compile_Error{message = "- expects at least one argument", span = form.span}, false
    }

    if op == "=" || op == "==" || op == "!=" || op == "<" || op == "<=" || op == ">" || op == ">=" {
        return emit_nary_comparison_expr(e, op, form.items[1:], form.span)
    }

    if op == "in?" || op == "in" || op == "core/in" {
        return "", Compile_Error{message = "`in` has been removed; use `contains?`", span = form.items[0].span}, false
    }

    if op == "not-in?" || op == "not-in" || op == "core/not-in" {
        return "", Compile_Error{message = "`not-in` has been removed; use `(not (contains? collection value))`", span = form.items[0].span}, false
    }

    if op == "odin-contains" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "odin-contains expects collection and key", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[1])
        if !ok_collection {
            return "", err_collection, false
        }
        key, err_key, ok_key := emit_expr(e, form.items[2])
        if !ok_key {
            return "", err_key, false
        }
        if ty, ok := obvious_form_type(e, form.items[1]); ok {
            if ty == "Data" {
                data_key, err_data_key, ok_data_key :=
                    emit_call_arg_for_expected_type(e, form.items[2], "Data")
                if !ok_data_key {
                    return "", err_data_key, false
                }
                return emit_call_text("kvist_data_contains", []string{collection, data_key}), {}, true
            }
            if ty == "string" {
                key_ty, ok_key_ty := obvious_form_type(e, form.items[2])
                if ok_key_ty && key_ty == "string" {
                    mark_core_strings(e)
                    return emit_call_text("strings.contains", []string{collection, key}), {}, true
                }
                return "", Compile_Error{message = "contains? on strings expects a string needle", span = form.items[2].span}, false
            }
            if strings.has_prefix(ty, "map[") {
                return fmt.tprintf("(%s) in (%s)", key, collection), {}, true
            }
            if type_text_is_pointer_to_map(ty) {
                return fmt.tprintf("(%s) in (%s)", key, deref_expr_text(collection)), {}, true
            }
            if strings.has_prefix(ty, "[]") || strings.has_prefix(ty, "[dynamic]") || (len(ty) > 1 && ty[0] == '[') {
                mark_core_contains_value(e)
                return emit_call_text("kvist_contains_value", []string{fmt.tprintf("(%s)[:]", collection), key}), {}, true
            }
        }
        return fmt.tprintf("(%s) in (%s)", key, collection), {}, true
    }

    return "", {}, false
}

find_union_decl :: proc(e: ^Emitter, name: string) -> (^Union_Decl, bool) {
    for i := len(e.local_unions) - 1; i >= 0; i -= 1 {
        if e.local_unions[i].name == name {
            return &e.local_unions[i], true
        }
    }
    ensure_emitter_indexes(e)
    if idx, found := e.union_indices[name]; found {
        return &e.unions[idx], true
    }
    return nil, false
}

find_struct_decl :: proc(e: ^Emitter, name: string) -> (^Struct_Decl, bool) {
    for i := len(e.local_structs) - 1; i >= 0; i -= 1 {
        if e.local_structs[i].name == name {
            return &e.local_structs[i], true
        }
    }
    ensure_emitter_indexes(e)
    if idx, found := e.struct_indices[name]; found {
        return &e.structs[idx], true
    }
    return nil, false
}

find_enum_decl :: proc(e: ^Emitter, name: string) -> (^Enum_Decl, bool) {
    ensure_emitter_indexes(e)
    if idx, found := e.enum_indices[name]; found {
        return &e.decls[idx].enum_decl, true
    }
    return nil, false
}

enum_type_exists :: proc(e: ^Emitter, name: string) -> bool {
    ensure_emitter_indexes(e)
    if _, found := e.enum_indices[name]; found {
        return true
    }
    if imported_odin_enum_type_exists(e, name) {
        return true
    }
    return false
}

find_struct_field :: proc(struct_decl: ^Struct_Decl, name: string) -> (^Struct_Field, bool) {
    for i in 0..<len(struct_decl.fields) {
        if struct_decl.fields[i].name == name {
            return &struct_decl.fields[i], true
        }
    }
    return nil, false
}

find_field_in_slice :: proc(fields: []Struct_Field, name: string) -> (^Struct_Field, bool) {
    for i in 0..<len(fields) {
        if fields[i].name == name {
            return &fields[i], true
        }
    }
    return nil, false
}

quoted_symbol_name :: proc(form: CST_Form) -> (string, bool) {
    if form.kind == .Symbol && len(form.text) >= 2 && form.text[0] == '\'' {
        return map_name(form.text[1:]), true
    }
    if form.kind == .List &&
       len(form.items) == 2 &&
       form.items[0].kind == .Symbol &&
       form.items[0].text == "quote" &&
       form.items[1].kind == .Symbol {
        return map_name(form.items[1].text), true
    }
    return "", false
}

find_decl_doc_text :: proc(e: ^Emitter, name: string) -> (string, bool) {
    ensure_emitter_indexes(e)
    lookup_name := name
    qualified_name := ""
    separator := strings.index(name, ".")
    if separator > 0 && separator < len(name)-1 {
        alias := name[:separator]
        suffix := name[separator+1:]
        if pkg, found := e.kvist_import_packages[alias]; found {
            qualified_name = fmt.tprintf("%s__%s", pkg, suffix)
            lookup_name = qualified_name
        }
    }
    defer delete(qualified_name)
    if idx, found := e.decl_indices[lookup_name]; found {
        decl := e.decls[idx]
        if len(decl.doc_lines) == 0 {
            return "", true
        }
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        for line, i in decl.doc_lines {
            if i > 0 {
                strings.write_byte(&builder, '\n')
            }
            strings.write_string(&builder, symbols_clean_doc_line(line))
        }
        return strings.clone(strings.to_string(builder)), true
    }
    return language_symbol_doc_text(name)
}

emit_struct_fields_literal :: proc(struct_decl: ^Struct_Decl) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "[]string{")
    for field, i in struct_decl.fields {
        if i > 0 {
            strings.write_string(&builder, ", ")
        }
        display_name := field.name
        if len(field.source_name) > 0 {
            display_name = field.source_name
        }
        strings.write_string(&builder, fmt.tprintf("%q", display_name))
    }
    strings.write_string(&builder, "}")
    return strings.clone(strings.to_string(builder))
}

surface_type_text :: proc(ty: string) -> string {
    switch ty {
    case "bool":
        return "bool"
    case "int":
        return "int"
    case "f64":
        return "float"
    case "string":
        return "string"
    case "rune":
        return "char"
    }

    if strings.has_prefix(ty, "[dynamic]") {
        elem := ty[len("[dynamic]"):]
        return fmt.tprintf("[dynamic]%s", surface_type_text(elem))
    }

    if strings.has_prefix(ty, "#soa[") {
        closing := strings.index(ty, "]")
        if closing > len("#soa[") {
            length := ty[len("#soa["):closing]
            elem := ty[closing+1:]
            return fmt.tprintf("#soa[%s]%s", length, surface_type_text(elem))
        }
    }

    if strings.has_prefix(ty, "#simd[") {
        closing := strings.index(ty, "]")
        if closing > len("#simd[") {
            length := ty[len("#simd["):closing]
            elem := ty[closing+1:]
            return fmt.tprintf("#simd[%s]%s", length, surface_type_text(elem))
        }
    }

    if strings.has_prefix(ty, "[]") {
        elem := ty[2:]
        return fmt.tprintf("[]%s", surface_type_text(elem))
    }

    if strings.has_prefix(ty, "map[") && strings.has_suffix(ty, "]struct{}") {
        return ty
    }

    if strings.has_prefix(ty, "bit_set[") {
        closing := strings.index(ty, "]")
        if closing > len("bit_set[") && closing == len(ty)-1 {
            return normalize_bit_set_text(ty[len("bit_set["):closing])
        }
    }

    if strings.has_prefix(ty, "matrix[") {
        closing := strings.index(ty, "]")
        if closing > len("matrix[") {
            dims := normalize_matrix_dims_text(ty[len("matrix["):closing])
            defer delete(dims)
            elem := ty[closing+1:]
            return fmt.tprintf("matrix[%s]%s", dims, surface_type_text(elem))
        }
    }

    if len(ty) > 2 && ty[0] == '[' {
        closing := strings.index(ty, "]")
        if closing > 1 {
            length := ty[1:closing]
            elem := ty[closing+1:]
            return fmt.tprintf("[%s]%s", length, surface_type_text(elem))
        }
    }

    return ty
}

emit_struct_types_literal :: proc(struct_decl: ^Struct_Decl) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "map[string]string{")
    for field, i in struct_decl.fields {
        if i > 0 {
            strings.write_string(&builder, ", ")
        }
        display_name := field.name
        if len(field.source_name) > 0 {
            display_name = field.source_name
        }
        strings.write_string(&builder, fmt.tprintf("%q = %q", display_name, surface_type_text(field.ty)))
    }
    strings.write_string(&builder, "}")
    return strings.clone(strings.to_string(builder))
}

brace_key_name :: proc(form: CST_Form) -> (string, bool) {
    if form.kind == .Symbol && len(form.text) > 1 && form.text[len(form.text)-1] == ':' {
        return map_name(form.text[:len(form.text)-1]), true
    }
    return "", false
}

number_looks_float :: proc(text: string) -> bool {
    for ch in text {
        if ch == '.' || ch == 'e' || ch == 'E' {
            return true
        }
    }
    return false
}

literal_matches_struct_field_type :: proc(e: ^Emitter, ty: string, value: CST_Form) -> bool {
    switch ty {
    case "string":
        if value.kind == .String || value.kind == .Regex {
            return true
        }
        return value.kind != .Number && value.kind != .Bool
    case "int":
        if value.kind == .Number {
            return !number_looks_float(value.text)
        }
        return value.kind != .String && value.kind != .Regex && value.kind != .Bool
    case "f64":
        if value.kind == .Number {
            return true
        }
        return value.kind != .String && value.kind != .Regex && value.kind != .Bool
    case "bool":
        if value.kind == .Bool {
            return true
        }
        return value.kind != .String && value.kind != .Regex && value.kind != .Number
    case "keyword":
        if value.kind == .Keyword {
            return true
        }
        return value.kind != .String && value.kind != .Regex && value.kind != .Number && value.kind != .Bool
    }

    nested_struct, ok_nested := find_struct_decl(e, ty)
    if ok_nested && value.kind == .List && len(value.items) == 2 && value.items[0].kind == .Symbol && map_name(value.items[0].text) == nested_struct.name && value.items[1].kind == .Brace {
        return true
    }

    return true
}

validate_struct_constructor :: proc(e: ^Emitter, struct_decl: ^Struct_Decl, form: CST_Form) -> (Compile_Error, bool) {
    if form.kind != .Brace {
        return Compile_Error{message = "struct construction expects a brace form", span = form.span}, false
    }

    seen: [dynamic]string
    for i := 0; i < len(form.items); i += 2 {
        if i+1 >= len(form.items) {
            return Compile_Error{message = "missing struct constructor value", span = form.span}, false
        }
        key := form.items[i]
        value := form.items[i+1]
        field_name, ok_key := brace_key_name(key)
        if !ok_key {
            return Compile_Error{message = "struct construction expects labeled fields", span = key.span}, false
        }
        for existing in seen {
            if existing == field_name {
                return Compile_Error{message = fmt.tprintf("duplicate struct constructor field %s", key.text), span = key.span}, false
            }
        }
        append(&seen, field_name)
        field, ok_field := find_struct_field(struct_decl, field_name)
        if !ok_field {
            return Compile_Error{message = fmt.tprintf("unknown struct constructor field %s", key.text), span = key.span}, false
        }
        if !literal_matches_struct_field_type(e, field.ty, value) {
            return Compile_Error{message = fmt.tprintf("struct constructor literal type mismatch for %s", key.text), span = value.span}, false
        }
    }

    return Compile_Error{}, true
}

is_numeric_scalar_type :: proc(text: string) -> bool {
    switch text {
    case "int", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "uintptr", "f32", "f64":
        return true
    case:
        return false
    }
}

emit_union_constructor :: proc(e: ^Emitter, union_decl: ^Union_Decl, arg: CST_Form) -> (string, Compile_Error, bool) {
    if arg.kind != .Brace {
        return "", Compile_Error{message = "union construction expects a brace form", span = arg.span}, false
    }
    if len(arg.items) != 2 {
        return "", Compile_Error{message = "union construction expects exactly one variant", span = arg.span}, false
    }

    key := arg.items[0]
    value := arg.items[1]
    variant_name, ok_key := brace_key_name(key)
    if !ok_key {
        return "", Compile_Error{message = "union construction expects a variant label", span = key.span}, false
    }

    found := false
    variant_ty := ""
    for variant in union_decl.variants {
        if variant.name == variant_name {
            found = true
            variant_ty = variant.ty
            break
        }
    }
    if !found {
        return "", Compile_Error{message = "unknown union variant", span = key.span}, false
    }

    value_text, err_value, ok_value := emit_expr(e, value)
    if !ok_value {
        return "", err_value, false
    }
    if value.kind == .Number && is_numeric_scalar_type(variant_ty) {
        value_text = fmt.tprintf("%s(%s)", variant_ty, value_text)
    }
    return fmt.tprintf("%s(%s)", union_decl.name, value_text), {}, true
}

emit_directive_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) < 2 || form.items[0].kind != .Symbol || len(form.items[0].text) == 0 || form.items[0].text[0] != '#' {
        return "", Compile_Error{message = "invalid directive expression", span = form.span}, false
    }

    if form.items[0].text == "#caller_expression" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "#caller_expression expects exactly one expression", span = form.span}, false
        }
        target_text, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        return fmt.tprintf("#caller_expression(%s)", target_text), {}, true
    }

    target := form.items[1]
    if len(form.items) > 2 {
        call_items: [dynamic]CST_Form
        for item in form.items[1:] {
            append(&call_items, item)
        }
        target = CST_Form{
            kind  = .List,
            items = call_items,
            span  = form.span,
        }
    }

    target_text, err_target, ok_target := emit_expr(e, target)
    if !ok_target {
        return "", err_target, false
    }
    return fmt.tprintf("%s %s", form.items[0].text, target_text), {}, true
}

is_call_directive_symbol :: proc(form: CST_Form) -> bool {
    return form.kind == .Symbol &&
           len(form.text) > 0 &&
           form.text[0] == '#' &&
           !strings.has_prefix(form.text, "#soa[") &&
           !strings.has_prefix(form.text, "#simd[")
}

captured_callback_arg_context :: proc(e: ^Emitter, arg: CST_Form) -> (proc_text: string, capture_names: [dynamic]string, field_selector: string, specialized: bool, err: Compile_Error, ok: bool) {
    if field, ok_field := field_from_selector(arg); ok_field {
        return "", capture_names, field, true, Compile_Error{}, true
    }

    if arg.kind == .Symbol {
        name := map_name(arg.text)
        if ctx, ok_context := lookup_callback_context(e, name); ok_context {
            if ctx.field_selector != "" {
                return name, capture_names, ctx.field_selector, true, Compile_Error{}, true
            }
            for capture_name in ctx.capture_names {
                append(&capture_names, capture_name)
            }
            return name, capture_names, "", true, Compile_Error{}, true
        }
        return "", capture_names, "", false, Compile_Error{}, true
    }

    proc_text_value, capture_names_value, _, captured_value, err_value, ok_value := captured_proc_literal_for_param(e, arg)
    return proc_text_value, capture_names_value, "", captured_value, err_value, ok_value
}

field_selector_typeid_bindings :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, args: []CST_Form, callback_index: int, field_selector: string) -> (bindings: [dynamic]Param, err: Compile_Error, ok: bool) {
    callback_ty := proc_decl.params[callback_index].ty
    generic_params := generic_type_params_in_text(callback_ty)
    if len(generic_params) == 0 {
        return bindings, Compile_Error{}, true
    }
    return_generic_params := proc_type_return_generic_params(callback_ty)
    input_generic_params := proc_type_param_generic_params(callback_ty)

    source_arg_idx := -1
    for param, idx in proc_decl.params {
        if idx == callback_index || type_text_is_proc(param.ty) {
            continue
        }
        if len(input_generic_params) > 0 {
            matches_input_generic := false
            for generic_param in input_generic_params {
                if type_text_mentions_generic_param(param.ty, generic_param) {
                    matches_input_generic = true
                    break
                }
            }
            if !matches_input_generic {
                continue
            }
        }
        source_arg_idx = idx
        break
    }
    if source_arg_idx < 0 {
        for param, idx in proc_decl.params {
            if idx == callback_index || type_text_is_proc(param.ty) {
                continue
            }
            source_arg_idx = idx
            break
        }
    }
    if source_arg_idx < 0 || source_arg_idx >= len(args) {
        return bindings, Compile_Error{message = "field-selector callback specialization could not infer generic return type"}, false
    }

    source_text, err_source, ok_source := emit_expr(e, args[source_arg_idx])
    if !ok_source {
        return bindings, err_source, false
    }

    source_param_ty := proc_decl.params[source_arg_idx].ty
    source_is_slice := strings.has_prefix(source_param_ty, "[]") || strings.has_prefix(source_param_ty, "[dynamic]")
    source_is_ptr_slice := strings.has_prefix(source_param_ty, "^[]") || strings.has_prefix(source_param_ty, "^[dynamic]")
    source_item_text := source_text
    if source_is_ptr_slice {
        source_item_text = deref_expr_text(source_text)
    }

    type_expr := ""
    if source_is_slice || source_is_ptr_slice {
        type_expr = fmt.tprintf("type_of((%s)[0].%s)", source_item_text, field_selector)
    } else {
        type_expr = fmt.tprintf("type_of((%s).%s)", source_text, field_selector)
    }
    item_type_expr := ""
    if source_is_slice || source_is_ptr_slice {
        item_type_expr = fmt.tprintf("type_of((%s)[0])", source_item_text)
    } else {
        item_type_expr = fmt.tprintf("type_of(%s)", source_text)
    }

    for generic_param in generic_params {
        if generic_param_in_slice(return_generic_params[:], generic_param) {
            append(&bindings, Param{name = generic_param, ty = type_expr})
        } else {
            append(&bindings, Param{name = generic_param, ty = item_type_expr})
        }
    }
    return bindings, Compile_Error{}, true
}

append_unique_typeid_binding :: proc(bindings: ^[dynamic]Param, binding: Param) {
    for existing in bindings^ {
        if existing.name == binding.name {
            return
        }
    }
    append(bindings, binding)
}

emit_specialized_proc_call_if_needed :: proc(e: ^Emitter, call_name: string, proc_decl: ^Proc_Decl, args: []CST_Form, span: Span) -> (text: string, handled: bool, err: Compile_Error, ok: bool) {
    specialized_index := -1
    proc_text := ""
    capture_names: [dynamic]string
    field_selector := ""
    field_callbacks: [dynamic]Field_Proc_Specialization

    for arg, idx in args {
        if idx >= len(proc_decl.params) || !type_text_is_proc(proc_decl.params[idx].ty) {
            continue
        }
        candidate_proc_text, candidate_capture_names, candidate_field, specialized, err_candidate, ok_candidate := captured_callback_arg_context(e, arg)
        if !ok_candidate {
            return "", true, err_candidate, false
        }
        if !specialized {
            continue
        }
        if specialized_index >= 0 {
            if field_selector == "" || candidate_field == "" {
                return "", true, Compile_Error{message = "callback specialization currently supports one captured callback argument per call", span = arg.span}, false
            }
        }
        if candidate_field != "" {
            append(&field_callbacks, Field_Proc_Specialization{callback_param_index = idx, field_selector = candidate_field})
        }
        specialized_index = idx
        proc_text = candidate_proc_text
        capture_names = candidate_capture_names
        field_selector = candidate_field
    }

    if specialized_index < 0 {
        return "", false, Compile_Error{}, true
    }

    if len(args) != len(proc_decl.params) {
        return "", true, Compile_Error{message = "callback specialization currently requires explicit positional arguments", span = span}, false
    }
    if len(field_callbacks) > 0 {
        for field_callback in field_callbacks {
            if !proc_callback_param_non_escaping(e, proc_decl, field_callback.callback_param_index) {
                return "", true, Compile_Error{message = fmt.tprintf("field-selector callback cannot be passed to %s because callback parameter %s may escape", call_name, proc_decl.params[field_callback.callback_param_index].name), span = args[field_callback.callback_param_index].span}, false
            }
        }
    } else if !proc_callback_param_non_escaping(e, proc_decl, specialized_index) {
        return "", true, Compile_Error{message = fmt.tprintf("captured callback cannot be passed to %s because callback parameter %s may escape", call_name, proc_decl.params[specialized_index].name), span = args[specialized_index].span}, false
    }

    specialized_name := ""
    if len(field_callbacks) > 0 {
        mark_field_proc_specializations(e, proc_decl.name, field_callbacks[:])
        specialized_name = proc_specialization_name(Captured_Proc_Specialization{original_name = proc_decl.name, field_callbacks = field_callbacks})
    } else {
        mark_captured_proc_specialization(e, proc_decl.name, specialized_index, len(capture_names))
        specialized_name = captured_specialization_name(proc_decl.name, specialized_index, len(capture_names))
    }

    arg_texts: [dynamic]string
    defer delete(arg_texts)
    if len(field_callbacks) > 0 {
        typeid_bindings: [dynamic]Param
        for field_callback in field_callbacks {
            bindings, err_typeid, ok_typeid := field_selector_typeid_bindings(e, proc_decl, args, field_callback.callback_param_index, field_callback.field_selector)
            if !ok_typeid {
                return "", true, err_typeid, false
            }
            for binding in bindings {
                append_unique_typeid_binding(&typeid_bindings, binding)
            }
        }
        for binding in typeid_bindings {
            append(&arg_texts, binding.ty)
        }
    }
    for arg, idx in args {
        if len(field_callbacks) > 0 {
            skip_field_callback := false
            for field_callback in field_callbacks {
                if idx == field_callback.callback_param_index {
                    skip_field_callback = true
                    break
                }
            }
            if skip_field_callback {
                continue
            }
        } else if idx == specialized_index {
            append(&arg_texts, proc_text)
            for capture_name in capture_names {
                append(&arg_texts, capture_name)
            }
            continue
        }
        arg_text, err_arg, ok_arg := emit_expr(e, arg)
        if !ok_arg {
            return "", true, err_arg, false
        }
        append(&arg_texts, arg_text)
    }
    return emit_call_text(specialized_name, arg_texts[:]), true, Compile_Error{}, true
}
