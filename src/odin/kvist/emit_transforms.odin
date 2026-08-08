// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

transform_temp_name :: proc(e: ^Emitter) -> string {
    e.temp_counter += 1
    return fmt.tprintf("kvist_xform_%d", e.temp_counter)
}

loop_temp_name :: proc(e: ^Emitter, stem: string) -> string {
    e.temp_counter += 1
    return fmt.tprintf("kvist_loop_%s_%d", stem, e.temp_counter)
}

source_temp_name :: proc(e: ^Emitter) -> string {
    e.temp_counter += 1
    return fmt.tprintf("kvist_source_%d", e.temp_counter)
}

source_ok_name :: proc(e: ^Emitter) -> string {
    e.temp_counter += 1
    return fmt.tprintf("kvist_source_ok_%d", e.temp_counter)
}

source_call_decl :: proc(e: ^Emitter, form: CST_Form) -> (^Source_Decl, bool) {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return nil, false
    }
    name := map_name(form.items[0].text)
    return find_source_decl(e, name)
}

form_is_direct_transform_source_call :: proc(form: CST_Form) -> bool {
    return false
}

form_is_transform_loop_call :: proc(form: CST_Form) -> bool {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    return form.items[0].text == "transform-loop"
}

type_ident_byte :: proc(ch: u8) -> bool {
    return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_'
}

substitute_type_names :: proc(type_text: string, names, types: []string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    i := 0
    for i < len(type_text) {
        matched := false
        for name, idx in names {
            if name == "" {
                continue
            }
            prefixed := fmt.tprintf("$%s", name)
            if i+len(prefixed) <= len(type_text) && type_text[i:i+len(prefixed)] == prefixed {
                after := i + len(prefixed)
                after_ok := after == len(type_text) || !type_ident_byte(type_text[after])
                if after_ok {
                    strings.write_string(&builder, types[idx])
                    i += len(prefixed)
                    matched = true
                    break
                }
            }
            if i+len(name) > len(type_text) || type_text[i:i+len(name)] != name {
                continue
            }
            after := i + len(name)
            before_ok := i == 0 || !type_ident_byte(type_text[i-1])
            after_ok := after == len(type_text) || !type_ident_byte(type_text[after])
            if before_ok && after_ok {
                strings.write_string(&builder, types[idx])
                i += len(name)
                matched = true
                break
            }
        }
        if !matched {
            strings.write_byte(&builder, type_text[i])
            i += 1
        }
    }
    return strings.clone(strings.to_string(builder))
}

transform_loop_source :: proc(e: ^Emitter, form: CST_Form) -> (spec: Transform_Loop_Source, err: Compile_Error, ok: bool) {
    if !form_is_transform_loop_call(form) {
        return spec, {}, false
    }
    if len(form.items) != 4 {
        return spec, Compile_Error{message = "transform-loop expects bindings, item type, and item expression", span = form.span}, false
    }
    bindings := form.items[1]
    if bindings.kind != .Vector || len(bindings.items) != 3 {
        return spec, Compile_Error{message = "transform-loop expects [key value source] bindings", span = bindings.span}, false
    }
    key_form := bindings.items[0]
    value_form := bindings.items[1]
    source_form := bindings.items[2]
    if key_form.kind != .Symbol || value_form.kind != .Symbol {
        return spec, Compile_Error{message = "transform-loop key and value bindings must be symbols", span = bindings.span}, false
    }
    source_ty, ok_source_ty := obvious_form_type(e, source_form)
    if !ok_source_ty {
        return spec, Compile_Error{message = "transform-loop expects a map with an obvious type; bind or annotate it first", span = source_form.span}, false
    }
    key_ty, value_ty, ok_map := map_type_parts(source_ty)
    if !ok_map {
        return spec, Compile_Error{message = fmt.tprintf("transform-loop expects map source, got %s", source_ty), span = source_form.span}, false
    }
    source_text, err_source, ok_source := emit_expr(e, source_form)
    if !ok_source {
        return spec, err_source, false
    }
    key_name := map_name(key_form.text)
    value_name := map_name(value_form.text)
    push_local_type_scope(e)
    defer pop_local_type_scope(e)
    bind_local_type(e, key_name, key_ty)
    bind_local_type(e, value_name, value_ty)
    item_ty_template, err_item_ty, ok_item_ty := parse_type_text(form.items[2])
    if !ok_item_ty {
        return spec, err_item_ty, false
    }
    defer delete(item_ty_template)
    binding_names := []string{key_name, value_name}
    binding_types := []string{key_ty, value_ty}
    item_ty := substitute_type_names(item_ty_template, binding_names, binding_types)
    defer delete(item_ty)
    item_text, err_item, ok_item := emit_expr_for_expected_type(e, form.items[3], item_ty)
    if !ok_item {
        return spec, err_item, false
    }
    spec.source_text = source_text
    spec.source_ty = source_ty
    spec.item_ty = strings.clone(item_ty)
    spec.item_text = item_text
    spec.key_name = key_name
    spec.key_ty = key_ty
    spec.value_name = value_name
    spec.value_ty = value_ty
    return spec, {}, true
}

source_state_type :: proc(e: ^Emitter, source: ^Source_Decl) -> (string, Compile_Error, bool) {
    _ = e
    return source.state_ty, {}, true
}

source_item_var_name :: proc(source_item_ty: string) -> string {
    if strings.has_prefix(source_item_ty, "$") {
        return source_item_ty[1:]
    }
    return source_item_ty
}

type_text_is_source_item_var :: proc(ty, source_item_ty: string) -> bool {
    var_name := source_item_var_name(source_item_ty)
    return ty == var_name || ty == fmt.tprintf("$%s", var_name)
}

source_param_type_for_item :: proc(param_ty, source_item_ty, item_ty: string) -> string {
    if item_ty == "" {
        return param_ty
    }
    var_name := source_item_var_name(source_item_ty)
    if param_ty == var_name || param_ty == fmt.tprintf("$%s", var_name) {
        return item_ty
    }
    replaced, _ := strings.replace_all(param_ty, fmt.tprintf("$%s", var_name), item_ty, context.temp_allocator)
    replaced, _ = strings.replace_all(replaced, fmt.tprintf("-> %s", var_name), fmt.tprintf("-> %s", item_ty), context.temp_allocator)
    return replaced
}

proc_type_single_return_type :: proc(ty: string) -> (string, bool) {
    arrow := strings.index(ty, "->")
    if arrow < 0 {
        return "", false
    }
    return strings.trim_space(ty[arrow+len("->"):]), true
}

append_unique_text :: proc(values: ^[dynamic]string, value: string) {
    for existing in values^ {
        if existing == value {
            return
        }
    }
    append(values, value)
}

generic_type_params_in_text :: proc(text: string) -> (params: [dynamic]string) {
    i := 0
    for i < len(text) {
        if text[i] != '$' {
            i += 1
            continue
        }
        start := i + 1
        end := start
        for end < len(text) {
            ch := text[end]
            alpha := (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
            digit := ch >= '0' && ch <= '9'
            if !(alpha || digit || ch == '_') {
                break
            }
            end += 1
        }
        if end > start {
            append_unique_text(&params, text[start:end])
        }
        i = end
    }
    return params
}

proc_type_return_generic_params :: proc(proc_ty: string) -> (params: [dynamic]string) {
    return_ty, ok_return := proc_type_single_return_type(proc_ty)
    if !ok_return {
        return params
    }
    return generic_type_params_in_text(return_ty)
}

proc_type_param_generic_params :: proc(proc_ty: string) -> (params: [dynamic]string) {
    if !strings.has_prefix(proc_ty, "proc(") {
        return params
    }
    close := strings.index(proc_ty, ")")
    if close < len("proc(") {
        return params
    }
    return generic_type_params_in_text(proc_ty[len("proc("):close])
}

generic_param_in_slice :: proc(values: []string, value: string) -> bool {
    for existing in values {
        if existing == value {
            return true
        }
    }
    return false
}

type_text_mentions_generic_param :: proc(type_text, generic_param: string) -> bool {
    if strings.contains(type_text, fmt.tprintf("$%s", generic_param)) {
        return true
    }
    return strings.contains(type_text, generic_param)
}

source_callback_return_item_type :: proc(e: ^Emitter, callback: CST_Form) -> (string, bool) {
    if callback.kind == .Symbol {
        name := map_name(callback.text)
        if proc_decl, ok_proc := find_proc_decl(e, name); ok_proc && proc_decl.returns.kind == .Single {
            return proc_decl.returns.single_ty, true
        }
        if ty, ok_ty := lookup_local_type(e, name); ok_ty {
            return proc_type_single_return_type(ty)
        }
        return "", false
    }
    if callback.kind == .List && len(callback.items) > 0 && is_symbol(callback.items[0], "fn") {
        parsed, _, ok_parsed := parse_proc_literal_form(callback)
        if ok_parsed && parsed.returns.kind == .Single {
            return parsed.returns.single_ty, true
        }
    }
    return "", false
}

source_param_callback_yields_item :: proc(param_ty, source_item_ty: string) -> bool {
    return_ty, ok_return := proc_type_single_return_type(param_ty)
    if !ok_return {
        return false
    }
    return type_text_is_source_item_var(return_ty, source_item_ty)
}

source_param_collection_yields_item :: proc(param_ty, source_item_ty: string) -> bool {
    elem_ty, ok_elem_ty := collection_element_type(param_ty)
    return ok_elem_ty && type_text_is_source_item_var(elem_ty, source_item_ty)
}

source_call_arg_texts :: proc(e: ^Emitter, source: ^Source_Decl, form: CST_Form, item_ty := "") -> (arg_texts: [dynamic]string, err: Compile_Error, ok: bool) {
    provided := len(form.items) - 1
    if provided != len(source.params) {
        return arg_texts, Compile_Error{message = fmt.tprintf("iterator %s expects %d arguments, got %d", source.name, len(source.params), provided), span = form.span}, false
    }
    for arg, idx in form.items[1:] {
        expected_ty := source_param_type_for_item(source.params[idx].ty, source.item_ty, item_ty)
        arg_text, err_arg, ok_arg := emit_expr_for_expected_type(e, arg, expected_ty)
        if !ok_arg {
            return arg_texts, err_arg, false
        }
        append(&arg_texts, arg_text)
    }
    return arg_texts, {}, true
}

source_call_item_type :: proc(e: ^Emitter, source: ^Source_Decl, form: CST_Form) -> (string, Compile_Error, bool) {
    item_ty := source.item_ty
    if form.kind != .List {
        return item_ty, {}, true
    }
    for param, idx in source.params {
        if idx+1 >= len(form.items) {
            break
        }
        if !strings.has_prefix(param.ty, "$") {
            continue
        }
        var_name := param.ty[1:]
        if item_ty != var_name && item_ty != param.ty {
            continue
        }
        actual_ty, ok_actual_ty := obvious_form_type(e, form.items[idx+1])
        if !ok_actual_ty {
            return "", Compile_Error{message = fmt.tprintf("iterator %s expects argument %s to have an obvious type", source.name, param.name), span = form.items[idx+1].span}, false
        }
        return actual_ty, {}, true
    }
    for param, idx in source.params {
        if idx+1 >= len(form.items) {
            break
        }
        if !source_param_callback_yields_item(param.ty, item_ty) {
            continue
        }
        actual_ty, ok_actual_ty := source_callback_return_item_type(e, form.items[idx+1])
        if !ok_actual_ty {
            return "", Compile_Error{message = fmt.tprintf("iterator %s expects callback argument %s to have an obvious return type", source.name, param.name), span = form.items[idx+1].span}, false
        }
        return actual_ty, {}, true
    }
    for param, idx in source.params {
        if idx+1 >= len(form.items) {
            break
        }
        if !source_param_collection_yields_item(param.ty, item_ty) {
            continue
        }
        actual_ty, ok_actual_ty := obvious_form_type(e, form.items[idx+1])
        if !ok_actual_ty && form.items[idx+1].kind == .List && len(form.items[idx+1].items) >= 2 {
            parsed_type, _, ok_parsed_type := parse_type_text(form.items[idx+1].items[0])
            if ok_parsed_type {
                actual_ty = parsed_type
                ok_actual_ty = true
            }
        }
        if !ok_actual_ty {
            return "", Compile_Error{message = fmt.tprintf("iterator %s expects collection argument %s to have an obvious element type", source.name, param.name), span = form.items[idx+1].span}, false
        }
        actual_elem_ty, ok_actual_elem_ty := collection_element_type(actual_ty)
        if !ok_actual_elem_ty {
            return "", Compile_Error{message = fmt.tprintf("iterator %s expects argument %s to be a collection", source.name, param.name), span = form.items[idx+1].span}, false
        }
        return actual_elem_ty, {}, true
    }
    return item_ty, {}, true
}

source_call_text :: proc(e: ^Emitter, source: ^Source_Decl, arg_texts: []string) -> string {
    return emit_call_text(source.name, arg_texts)
}

generic_type_text_matches :: proc(actual, expected: string) -> bool {
    if actual == expected {
        return true
    }
    actual_plain, actual_allocated := strings.replace_all(actual, "$", "", context.allocator)
    if actual_allocated {
        defer delete(actual_plain)
    }
    expected_plain, expected_allocated := strings.replace_all(expected, "$", "", context.allocator)
    if expected_allocated {
        defer delete(expected_plain)
    }
    return actual_plain == expected_plain
}

validate_source_protocol :: proc(e: ^Emitter, source: ^Source_Decl, state_ty: string, span: Span) -> (Compile_Error, bool) {
    next_decl, ok_next := find_proc_decl(e, source.next_name)
    if !ok_next {
        return Compile_Error{message = fmt.tprintf("defiter %s :next must name a known function: %s", source.name, source.next_name), span = span}, false
    }
    expected_state_ptr := fmt.tprintf("^%s", state_ty)
    if len(next_decl.params) != 1 || !generic_type_text_matches(next_decl.params[0].ty, expected_state_ptr) {
        return Compile_Error{message = fmt.tprintf("defiter %s :next must take %s", source.name, expected_state_ptr), span = span}, false
    }
    if next_decl.returns.kind != .Named ||
       len(next_decl.returns.named) != 2 ||
       !generic_type_text_matches(next_decl.returns.named[0].ty, source.item_ty) ||
       next_decl.returns.named[1].ty != "bool" {
        return Compile_Error{message = fmt.tprintf("defiter %s :next must return [item: %s ok: bool]", source.name, source.item_ty), span = span}, false
    }
    if source.has_dispose {
        dispose_decl, ok_dispose := find_proc_decl(e, source.dispose_name)
        if !ok_dispose {
            return Compile_Error{message = fmt.tprintf("defiter %s :dispose must name a known function: %s", source.name, source.dispose_name), span = span}, false
        }
        if len(dispose_decl.params) != 1 || dispose_decl.params[0].ty != expected_state_ptr {
            return Compile_Error{message = fmt.tprintf("defiter %s :dispose must take %s", source.name, expected_state_ptr), span = span}, false
        }
        if dispose_decl.returns.kind != .None {
            return Compile_Error{message = fmt.tprintf("defiter %s :dispose must not return a value", source.name), span = span}, false
        }
    }
    return {}, true
}

transform_step_kind :: proc(head: string) -> (Transform_Step_Kind, bool) {
    switch head {
    case "map":
        return .Map, true
    case "filter":
        return .Filter, true
    case "remove":
        return .Remove, true
    case "keep":
        return .Keep, true
    case "take":
        return .Take, true
    case "take-while":
        return .Take_While, true
    case "drop":
        return .Drop, true
    case "drop-while":
        return .Drop_While, true
    case "map-indexed":
        return .Map_Indexed, true
    case "mapcat":
        return .Mapcat, true
    case "distinct":
        return .Distinct, true
    case "distinct-by":
        return .Distinct_By, true
    }
    return {}, false
}

transform_spec_form :: proc(e: ^Emitter, form: CST_Form) -> (CST_Form, Compile_Error, bool) {
    if form.kind == .Symbol {
        decl, ok_decl := find_transform_decl(e, map_name(form.text))
        if !ok_decl {
            return {}, Compile_Error{message = fmt.tprintf("unknown transform: %s", form.text), span = form.span}, false
        }
        return decl.spec, {}, true
    }
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if form.items[0].text == "comp" {
            return form, {}, true
        }
        if _, ok_kind := transform_step_kind(form.items[0].text); ok_kind {
            return form, {}, true
        }
        return {}, Compile_Error{message = "transform steps currently support map, map-indexed, mapcat, filter, remove, keep, take, take-while, drop, drop-while, distinct, and distinct-by", span = form.items[0].span}, false
    }
    return {}, Compile_Error{message = "transform expects a named transform, (comp ...), or a transform step", span = form.span}, false
}

parse_transform_steps_into :: proc(e: ^Emitter, form: CST_Form, steps: ^[dynamic]Transform_Step) -> (Compile_Error, bool) {
    spec, err_spec, ok_spec := transform_spec_form(e, form)
    if !ok_spec {
        return err_spec, false
    }
    if spec.kind != .List || len(spec.items) == 0 || spec.items[0].kind != .Symbol {
        return Compile_Error{message = "transform spec expects (comp ...) or a transform step", span = spec.span}, false
    }
    if spec.items[0].text == "comp" {
        for step_form in spec.items[1:] {
            err_step, ok_step := parse_transform_steps_into(e, step_form, steps)
            if !ok_step {
                return err_step, false
            }
        }
        return {}, true
    }
    kind, ok_kind := transform_step_kind(spec.items[0].text)
    if !ok_kind {
        return Compile_Error{message = "transform steps currently support map, map-indexed, mapcat, filter, remove, keep, take, take-while, drop, drop-while, distinct, and distinct-by", span = spec.items[0].span}, false
    }
    expected_items := 2
    if kind == .Distinct {
        expected_items = 1
    }
    if len(spec.items) != expected_items {
        if kind == .Distinct {
            return Compile_Error{message = "distinct transform step expects no arguments", span = spec.span}, false
        }
        return Compile_Error{message = "transform steps expect one argument", span = spec.span}, false
    }
    state_name := ""
    if kind == .Take || kind == .Drop || kind == .Drop_While || kind == .Map_Indexed ||
       kind == .Distinct || kind == .Distinct_By {
        state_name = transform_temp_name(e)
    }
    callback := CST_Form{}
    if len(spec.items) == 2 {
        callback = spec.items[1]
    }
    append(steps, Transform_Step{
        kind = kind,
        callback = callback,
        state_name = state_name,
        span = spec.span,
    })
    return {}, true
}

parse_transform_steps :: proc(e: ^Emitter, form: CST_Form) -> (steps: [dynamic]Transform_Step, err: Compile_Error, ok: bool) {
    err_steps, ok_steps := parse_transform_steps_into(e, form, &steps)
    if !ok_steps {
        return steps, err_steps, false
    }
    return steps, {}, true
}

transform_proc_literal_call :: proc(e: ^Emitter, callback: CST_Form, expected_params: []Param, label := "transform fn callback") -> (text: string, returns: Return_Spec, err: Compile_Error, ok: bool) {
	if callback.kind != .List || len(callback.items) == 0 || !is_symbol(callback.items[0], "fn") {
		return "", {}, {}, false
	}
    parsed, err_parse, ok_parse := parse_proc_literal_form(callback)
    if !ok_parse {
        return "", {}, err_parse, false
	}
	if len(parsed.params) != len(expected_params) {
		return "", {}, Compile_Error{message = fmt.tprintf("%s expects %d parameters", label, len(expected_params)), span = callback.span}, false
	}
	for expected, idx in expected_params {
		if parsed.params[idx].ty != expected.ty {
			return "", {}, Compile_Error{message = fmt.tprintf("%s parameter %s must be %s", label, parsed.params[idx].name, expected.ty), span = callback.span}, false
		}
	}

	param_names: [dynamic]string
	defer delete(param_names)
	for param in parsed.params {
		append(&param_names, param.name)
	}
	captures := collect_proc_literal_captures(e, parsed.body[:], param_names[:])
	defer delete(captures)

    proc_params: [dynamic]Param
    call_args: [dynamic]string
    defer delete(proc_params)
    defer delete(call_args)
    for capture in captures {
        append(&proc_params, capture)
        append(&call_args, capture.name)
    }
    for param in parsed.params {
        append(&proc_params, param)
    }
    for expected in expected_params {
        append(&call_args, expected.name)
    }

    proc_text, err_proc, ok_proc := emit_proc_literal_text(e, proc_params[:], parsed.returns, parsed.body[:])
    if !ok_proc {
        return "", {}, err_proc, false
    }
	return emit_call_text(proc_text, call_args[:]), parsed.returns, {}, true
}

transform_fn_capture_params :: proc(e: ^Emitter, callback: CST_Form) -> (captures: [dynamic]Param, err: Compile_Error, ok: bool) {
	if callback.kind != .List || len(callback.items) == 0 || !is_symbol(callback.items[0], "fn") {
		return captures, {}, true
	}
	parsed, err_parse, ok_parse := parse_proc_literal_form(callback)
	if !ok_parse {
		return captures, err_parse, false
	}
	param_names: [dynamic]string
	defer delete(param_names)
	for param in parsed.params {
		append(&param_names, param.name)
	}
	callback_captures := collect_proc_literal_captures(e, parsed.body[:], param_names[:])
	defer delete(callback_captures)
	for capture in callback_captures {
		append_capture_param_unique(&captures, capture)
	}
	return captures, {}, true
}

transform_step_capture_params :: proc(e: ^Emitter, steps: []Transform_Step) -> (captures: [dynamic]Param, err: Compile_Error, ok: bool) {
	for step in steps {
		callback_captures, err_callback, ok_callback := transform_fn_capture_params(e, step.callback)
		if !ok_callback {
			return captures, err_callback, false
		}
		defer delete(callback_captures)
		for capture in callback_captures {
			append_capture_param_unique(&captures, capture)
		}
	}
	return captures, {}, true
}

proc_callback_call :: proc(e: ^Emitter, callback: CST_Form, input_text, input_ty: string) -> (text, return_ty: string, err: Compile_Error, ok: bool) {
    if field, ok_field := field_from_selector(callback); ok_field {
        field_ty, ok_field_ty := struct_field_type_for_update(e, input_ty, field)
        if !ok_field_ty {
            return "", "", Compile_Error{message = fmt.tprintf("transform callback could not find field .%s on %s", field, input_ty), span = callback.span}, false
        }
        return fmt.tprintf("%s.%s", input_text, field), field_ty, {}, true
    }
    if callback.kind == .List && len(callback.items) > 0 && is_symbol(callback.items[0], "fn") {
        text, returns, err_literal, ok_literal := transform_proc_literal_call(e, callback, []Param{{name = input_text, ty = input_ty}})
        if !ok_literal {
            return "", "", err_literal, false
        }
        if returns.kind != .Single {
            return "", "", Compile_Error{message = "transform fn callback requires an explicit single return type", span = callback.span}, false
        }
        return text, returns.single_ty, {}, true
    }
    if callback.kind != .Symbol {
        return "", "", Compile_Error{message = "transform callback currently expects a function symbol, field selector, or fn literal", span = callback.span}, false
    }
    proc_name := map_name(callback.text)
    proc_decl, ok_proc := find_proc_decl(e, proc_name)
    if !ok_proc {
        return "", "", Compile_Error{message = fmt.tprintf("transform callback must be a known one-argument function: %s", callback.text), span = callback.span}, false
    }
    if len(proc_decl.params) != 1 {
        return "", "", Compile_Error{message = "transform callback currently expects a one-argument function", span = callback.span}, false
    }
    if proc_decl.params[0].ty != input_ty {
        return "", "", Compile_Error{message = fmt.tprintf("transform callback expects %s but pipeline has %s", proc_decl.params[0].ty, input_ty), span = callback.span}, false
    }
    if proc_decl.returns.kind != .Single {
        return "", "", Compile_Error{message = "transform callback currently expects a single return value", span = callback.span}, false
    }
    return emit_call_text(proc_name, []string{input_text}), proc_decl.returns.single_ty, {}, true
}

indexed_callback_call :: proc(e: ^Emitter, callback: CST_Form, index_text, input_text, input_ty: string) -> (text, return_ty: string, err: Compile_Error, ok: bool) {
    if callback.kind == .List && len(callback.items) > 0 && is_symbol(callback.items[0], "fn") {
        text, returns, err_literal, ok_literal := transform_proc_literal_call(e, callback, []Param{{name = index_text, ty = "int"}, {name = input_text, ty = input_ty}}, "map-indexed transform fn callback")
        if !ok_literal {
            return "", "", err_literal, false
        }
        if returns.kind != .Single {
            return "", "", Compile_Error{message = "map-indexed transform fn callback requires an explicit single return type", span = callback.span}, false
        }
        return text, returns.single_ty, {}, true
    }
    if callback.kind != .Symbol {
        return "", "", Compile_Error{message = "map-indexed transform currently expects a function symbol or fn literal", span = callback.span}, false
    }
    proc_name := map_name(callback.text)
    proc_decl, ok_proc := find_proc_decl(e, proc_name)
    if !ok_proc {
        return "", "", Compile_Error{message = fmt.tprintf("map-indexed transform must name a known two-argument function: %s", callback.text), span = callback.span}, false
    }
    if len(proc_decl.params) != 2 || proc_decl.params[0].ty != "int" || proc_decl.params[1].ty != input_ty {
        return "", "", Compile_Error{message = fmt.tprintf("map-indexed transform callback must be (fn [int %s] -> T)", input_ty), span = callback.span}, false
    }
    if proc_decl.returns.kind != .Single {
        return "", "", Compile_Error{message = "map-indexed transform callback currently expects a single return value", span = callback.span}, false
    }
    return emit_call_text(proc_name, []string{index_text, input_text}), proc_decl.returns.single_ty, {}, true
}

keep_callback_call :: proc(e: ^Emitter, callback: CST_Form, input_text, input_ty: string) -> (text, value_ty: string, err: Compile_Error, ok: bool) {
    if callback.kind == .List && len(callback.items) > 0 && is_symbol(callback.items[0], "fn") {
        text, returns, err_literal, ok_literal := transform_proc_literal_call(e, callback, []Param{{name = input_text, ty = input_ty}})
        if !ok_literal {
            return "", "", err_literal, false
        }
        if returns.kind != .Named || len(returns.named) != 2 || returns.named[1].ty != "bool" {
            return "", "", Compile_Error{message = "keep transform fn callback must return [value: T ok: bool]", span = callback.span}, false
        }
        return text, returns.named[0].ty, {}, true
    }
    if callback.kind != .Symbol {
        return "", "", Compile_Error{message = "keep transform currently expects a function symbol or fn literal", span = callback.span}, false
    }
    proc_name := map_name(callback.text)
    proc_decl, ok_proc := find_proc_decl(e, proc_name)
    if !ok_proc {
        return "", "", Compile_Error{message = fmt.tprintf("keep transform must name a known one-argument function: %s", callback.text), span = callback.span}, false
    }
    if len(proc_decl.params) != 1 {
        return "", "", Compile_Error{message = "keep transform currently expects a one-argument function", span = callback.span}, false
    }
    if proc_decl.params[0].ty != input_ty {
        return "", "", Compile_Error{message = fmt.tprintf("keep transform callback expects %s but pipeline has %s", proc_decl.params[0].ty, input_ty), span = callback.span}, false
    }
    if proc_decl.returns.kind != .Named || len(proc_decl.returns.named) != 2 || proc_decl.returns.named[1].ty != "bool" {
        return "", "", Compile_Error{message = "keep transform callback must return [value: T ok: bool]", span = callback.span}, false
    }
    return emit_call_text(proc_name, []string{input_text}), proc_decl.returns.named[0].ty, {}, true
}

emit_transform_state_prelude :: proc(e: ^Emitter, builder: ^strings.Builder, steps: []Transform_Step, depth: int) -> (Compile_Error, bool) {
    for step in steps {
        if step.kind == .Distinct || step.kind == .Distinct_By {
            mark_data_type(e)
            append_indent(builder, depth)
            fmt.sbprintf(builder, "%s := make([dynamic]Data)\n", step.state_name)
            append_indent(builder, depth)
            fmt.sbprintf(
                builder,
                "defer {{ for kvist_value in %s {{ kvist_data_release(kvist_value) }}; delete(%s) }}\n",
                step.state_name,
                step.state_name,
            )
            continue
        }
        if step.kind != .Take && step.kind != .Drop && step.kind != .Drop_While && step.kind != .Map_Indexed {
            continue
        }
        if step.kind == .Drop_While {
            append_indent(builder, depth)
            fmt.sbprintf(builder, "%s := true\n", step.state_name)
        } else if step.kind == .Map_Indexed {
            append_indent(builder, depth)
            fmt.sbprintf(builder, "%s := 0\n", step.state_name)
        } else {
            limit_text, err_limit, ok_limit := emit_expr(e, step.callback)
            if !ok_limit {
                return err_limit, false
            }
            append_indent(builder, depth)
            fmt.sbprintf(builder, "%s := %s\n", step.state_name, limit_text)
        }
    }
    return {}, true
}

transform_callback_borrows_data_result :: proc(e: ^Emitter, callback: CST_Form) -> bool {
    if callback.kind == .Symbol {
        if strings.has_prefix(callback.text, ".") {
            return true
        }
        return proc_decl_borrowed_view_head(e, callback.text)
    }
    if callback.kind == .List && len(callback.items) > 0 && is_symbol(callback.items[0], "fn") {
        parsed, _, ok := parse_proc_literal_form(callback)
        if !ok || len(parsed.body) == 0 {
            return false
        }
        return !form_produces_owned_managed_type(e, parsed.body[len(parsed.body)-1], "Data")
    }
    return false
}

emit_transform_pipeline_body :: proc(
    e: ^Emitter,
    builder: ^strings.Builder,
    steps: []Transform_Step,
    initial_text, initial_ty: string,
    depth: int,
) -> (value_text, value_ty: string, close_count: int, err: Compile_Error, ok: bool) {
    current_text := initial_text
    current_ty := initial_ty
    current_depth := depth
    inside_mapcat := false
    for step in steps {
        if inside_mapcat && (step.kind == .Take || step.kind == .Take_While) {
            return "", "", 0, Compile_Error{message = "take and take-while after mapcat need cross-loop termination and are not supported yet", span = step.span}, false
        }
        switch step.kind {
        case .Filter:
            pred_text, pred_ty, err_pred, ok_pred := proc_callback_call(e, step.callback, current_text, current_ty)
            if !ok_pred {
                return "", "", 0, err_pred, false
            }
            if pred_ty != "bool" {
                return "", "", 0, Compile_Error{message = fmt.tprintf("filter transform expects bool callback result, got %s", pred_ty), span = step.callback.span}, false
            }
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "if %s %s\n", pred_text, "{")
            current_depth += 1
            close_count += 1
        case .Remove:
            pred_text, pred_ty, err_pred, ok_pred := proc_callback_call(e, step.callback, current_text, current_ty)
            if !ok_pred {
                return "", "", 0, err_pred, false
            }
            if pred_ty != "bool" {
                return "", "", 0, Compile_Error{message = fmt.tprintf("remove transform expects bool callback result, got %s", pred_ty), span = step.callback.span}, false
            }
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "if !(%s) %s\n", pred_text, "{")
            current_depth += 1
            close_count += 1
        case .Keep:
            keep_text, keep_ty, err_keep, ok_keep := keep_callback_call(e, step.callback, current_text, current_ty)
            if !ok_keep {
                return "", "", 0, err_keep, false
            }
            value_temp := transform_temp_name(e)
            ok_temp := transform_temp_name(e)
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "%s, %s := %s\n", value_temp, ok_temp, keep_text)
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "if %s %s\n", ok_temp, "{")
            current_text = value_temp
            current_ty = keep_ty
            current_depth += 1
            close_count += 1
        case .Take:
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "if %s <= 0 %s\n", step.state_name, "{")
            append_indent(builder, current_depth+1)
            strings.write_string(builder, "break\n")
            append_indent(builder, current_depth)
            strings.write_string(builder, "}\n")
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "%s -= 1\n", step.state_name)
        case .Take_While:
            pred_text, pred_ty, err_pred, ok_pred := proc_callback_call(e, step.callback, current_text, current_ty)
            if !ok_pred {
                return "", "", 0, err_pred, false
            }
            if pred_ty != "bool" {
                return "", "", 0, Compile_Error{message = fmt.tprintf("take-while transform expects bool callback result, got %s", pred_ty), span = step.callback.span}, false
            }
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "if !(%s) %s\n", pred_text, "{")
            append_indent(builder, current_depth+1)
            strings.write_string(builder, "break\n")
            append_indent(builder, current_depth)
            strings.write_string(builder, "}\n")
        case .Drop:
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "if %s > 0 %s\n", step.state_name, "{")
            append_indent(builder, current_depth+1)
            fmt.sbprintf(builder, "%s -= 1\n", step.state_name)
            append_indent(builder, current_depth+1)
            strings.write_string(builder, "continue\n")
            append_indent(builder, current_depth)
            strings.write_string(builder, "}\n")
        case .Drop_While:
            pred_text, pred_ty, err_pred, ok_pred := proc_callback_call(e, step.callback, current_text, current_ty)
            if !ok_pred {
                return "", "", 0, err_pred, false
            }
            if pred_ty != "bool" {
                return "", "", 0, Compile_Error{message = fmt.tprintf("drop-while transform expects bool callback result, got %s", pred_ty), span = step.callback.span}, false
            }
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "if %s %s\n", step.state_name, "{")
            append_indent(builder, current_depth+1)
            fmt.sbprintf(builder, "if %s %s\n", pred_text, "{")
            append_indent(builder, current_depth+2)
            strings.write_string(builder, "continue\n")
            append_indent(builder, current_depth+1)
            strings.write_string(builder, "}\n")
            append_indent(builder, current_depth+1)
            fmt.sbprintf(builder, "%s = false\n", step.state_name)
            append_indent(builder, current_depth)
            strings.write_string(builder, "}\n")
        case .Distinct:
            if current_ty != "Data" {
                return "", "", 0, Compile_Error{message = fmt.tprintf("distinct transform currently expects Data items, got %s", current_ty), span = step.span}, false
            }
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "if !kvist_data_slice_contains(%s[:], %s) %s\n", step.state_name, current_text, "{")
            append_indent(builder, current_depth+1)
            fmt.sbprintf(builder, "kvist_data_append_retained(&%s, %s)\n", step.state_name, current_text)
            current_depth += 1
            close_count += 1
        case .Distinct_By:
            if current_ty != "Data" {
                return "", "", 0, Compile_Error{message = fmt.tprintf("distinct-by transform currently expects Data items, got %s", current_ty), span = step.span}, false
            }
            key_text, key_ty, err_key, ok_key := proc_callback_call(e, step.callback, current_text, current_ty)
            if !ok_key {
                return "", "", 0, err_key, false
            }
            if key_ty != "Data" {
                return "", "", 0, Compile_Error{message = fmt.tprintf("distinct-by transform expects a Data callback result, got %s", key_ty), span = step.callback.span}, false
            }
            if transform_callback_borrows_data_result(e, step.callback) {
                key_text = emit_call_text("kvist_data_retain", []string{key_text})
            }
            key_temp := transform_temp_name(e)
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "%s := %s\n", key_temp, key_text)
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "defer kvist_data_release(%s)\n", key_temp)
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "if !kvist_data_slice_contains(%s[:], %s) %s\n", step.state_name, key_temp, "{")
            append_indent(builder, current_depth+1)
            fmt.sbprintf(builder, "kvist_data_append_retained(&%s, %s)\n", step.state_name, key_temp)
            current_depth += 1
            close_count += 1
        case .Map_Indexed:
            mapped_text, mapped_ty, err_mapped, ok_mapped := indexed_callback_call(e, step.callback, step.state_name, current_text, current_ty)
            if !ok_mapped {
                return "", "", 0, err_mapped, false
            }
            temp := transform_temp_name(e)
            if mapped_ty == "Data" && transform_callback_borrows_data_result(e, step.callback) {
                mapped_text = emit_call_text("kvist_data_retain", []string{mapped_text})
            }
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "%s := %s\n", temp, mapped_text)
            if mapped_ty == "Data" {
                append_indent(builder, current_depth)
                fmt.sbprintf(builder, "defer kvist_data_release(%s)\n", temp)
            }
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "%s += 1\n", step.state_name)
            current_text = temp
            current_ty = mapped_ty
        case .Mapcat:
            mapped_text, mapped_ty, err_mapped, ok_mapped := proc_callback_call(e, step.callback, current_text, current_ty)
            if !ok_mapped {
                return "", "", 0, err_mapped, false
            }
            if mapped_ty == "Data" {
                if transform_callback_borrows_data_result(e, step.callback) {
                    mapped_text = emit_call_text("kvist_data_retain", []string{mapped_text})
                }
                mapped_temp := transform_temp_name(e)
                inner_temp := transform_temp_name(e)
                append_indent(builder, current_depth)
                fmt.sbprintf(builder, "%s := %s\n", mapped_temp, mapped_text)
                append_indent(builder, current_depth)
                fmt.sbprintf(builder, "defer kvist_data_release(%s)\n", mapped_temp)
                append_indent(builder, current_depth)
                fmt.sbprintf(
                    builder,
                    "assert(%s.kind == .Nil || %s.kind == .List || %s.kind == .Vector || %s.kind == .Set, \"Data mapcat transform callback expects nil, list, vector, or set\"); for %s in %s.payload.items %s\n",
                    mapped_temp,
                    mapped_temp,
                    mapped_temp,
                    mapped_temp,
                    inner_temp,
                    mapped_temp,
                    "{",
                )
                current_text = inner_temp
                current_ty = "Data"
                current_depth += 1
                close_count += 1
                inside_mapcat = true
                continue
            }
            if type_text_is_dynamic_array(mapped_ty) {
                return "", "", 0, Compile_Error{message = "mapcat transform callback currently expects a borrowed slice or fixed array result, not an owned dynamic array", span = step.callback.span}, false
            }
            inner_ty, ok_inner_ty := collection_element_type(mapped_ty)
            if !ok_inner_ty {
                return "", "", 0, Compile_Error{message = fmt.tprintf("mapcat transform expects array-family callback result, got %s", mapped_ty), span = step.callback.span}, false
            }
            mapped_temp := transform_temp_name(e)
            inner_temp := transform_temp_name(e)
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "%s := %s\n", mapped_temp, mapped_text)
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "for %s in %s %s\n", inner_temp, slice_all_expr_text(mapped_temp), "{")
            current_text = inner_temp
            current_ty = inner_ty
            current_depth += 1
            close_count += 1
            inside_mapcat = true
        case .Map:
            mapped_text, mapped_ty, err_mapped, ok_mapped := proc_callback_call(e, step.callback, current_text, current_ty)
            if !ok_mapped {
                return "", "", 0, err_mapped, false
            }
            temp := transform_temp_name(e)
            if mapped_ty == "Data" && transform_callback_borrows_data_result(e, step.callback) {
                mapped_text = emit_call_text("kvist_data_retain", []string{mapped_text})
            }
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "%s := %s\n", temp, mapped_text)
            if mapped_ty == "Data" {
                append_indent(builder, current_depth)
                fmt.sbprintf(builder, "defer kvist_data_release(%s)\n", temp)
            }
            current_text = temp
            current_ty = mapped_ty
        }
    }
    return current_text, current_ty, close_count, {}, true
}

emit_transform_closers :: proc(builder: ^strings.Builder, depth, close_count: int) {
    current_depth := depth
    remaining := close_count
    for remaining > 0 {
        current_depth -= 1
        append_indent(builder, current_depth)
        strings.write_string(builder, "}\n")
        remaining -= 1
    }
}

form_contains_reduced :: proc(form: CST_Form) -> bool {
    #partial switch form.kind {
    case .Symbol:
        return form.text == "reduced"
    case .List, .Vector, .Brace, .Set:
        for item in form.items {
            if form_contains_reduced(item) {
                return true
            }
        }
    case:
    }
    return false
}

emit_reduced_branch_update_text :: proc(e: ^Emitter, form: CST_Form, acc_text, acc_ty: string) -> (string, Compile_Error, bool) {
    if form.kind == .List && len(form.items) > 0 && is_symbol(form.items[0], "reduced") {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "reduced expects one value", span = form.span}, false
        }
        value_text, err_value, ok_value := emit_expr_for_expected_type(e, form.items[1], acc_ty)
        if !ok_value {
            return "", err_value, false
        }
        return fmt.tprintf("%s = %s; break", acc_text, value_text), {}, true
    }
    if form_contains_reduced(form) {
        return "", Compile_Error{message = "reduced in transduce fn reducers is currently supported only as a direct reducer branch", span = form.span}, false
    }
    value_text, err_value, ok_value := emit_expr_for_expected_type(e, form, acc_ty)
    if !ok_value {
        return "", err_value, false
    }
    return fmt.tprintf("%s = %s", acc_text, value_text), {}, true
}

emit_reduced_body_update_text :: proc(e: ^Emitter, form: CST_Form, acc_text, acc_ty: string) -> (string, Compile_Error, bool) {
    if form.kind == .List && len(form.items) > 0 && is_symbol(form.items[0], "if") {
        if len(form.items) != 4 {
            return "", Compile_Error{message = "reduced transduce fn reducer if expects test, then, and else", span = form.span}, false
        }
        test_text, err_test, ok_test := emit_expr(e, form.items[1])
        if !ok_test {
            return "", err_test, false
        }
        then_text, err_then, ok_then := emit_reduced_body_update_text(e, form.items[2], acc_text, acc_ty)
        if !ok_then {
            return "", err_then, false
        }
        else_text, err_else, ok_else := emit_reduced_body_update_text(e, form.items[3], acc_text, acc_ty)
        if !ok_else {
            return "", err_else, false
        }
        return fmt.tprintf("if %s %s %s %s else %s %s %s", test_text, "{", then_text, "}", "{", else_text, "}"), {}, true
    }
    if form.kind == .List && len(form.items) > 0 && is_symbol(form.items[0], "let") {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "reduced transduce fn reducer let expects bindings and one body expression", span = form.span}, false
        }
        bindings, err_bind, ok_bind := parse_let_bindings(form.items[1])
        if !ok_bind {
            return "", err_bind, false
        }
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        push_local_type_scope(e)
        defer pop_local_type_scope(e)
        for binding in bindings {
            if binding.is_destructure || binding.is_result_binding || binding.deferred_delete || binding.err_deferred_delete || binding.defer_with_cleanup {
                return "", Compile_Error{message = "reduced transduce fn reducer let supports only simple local bindings", span = binding.target_span}, false
            }
            value_text, err_value, ok_value := emit_expr_for_expected_type(e, binding.value, binding.ty)
            if !ok_value {
                return "", err_value, false
            }
            if is_discard_binding_name(binding.name) {
                fmt.sbprintf(&builder, "_ = %s\n", value_text)
            } else {
                fmt.sbprintf(&builder, "%s := %s\n", binding.name, value_text)
            }
            bind_obvious_binding_types(e, binding)
        }
        body_text, err_body, ok_body := emit_reduced_body_update_text(e, form.items[2], acc_text, acc_ty)
        if !ok_body {
            return "", err_body, false
        }
        strings.write_string(&builder, body_text)
        return strings.clone(strings.to_string(builder)), {}, true
    }
    return emit_reduced_branch_update_text(e, form, acc_text, acc_ty)
}

write_transform_reduce_text :: proc(builder: ^strings.Builder, depth: int, text: string) {
    lines := strings.split_lines(text, context.allocator)
    defer delete(lines)
    for line in lines {
        append_indent(builder, depth)
        strings.write_string(builder, line)
        strings.write_string(builder, "\n")
    }
}

transform_reduced_reduce_update_text :: proc(e: ^Emitter, reducer: CST_Form, acc_text, acc_ty, value_text: string, parsed: Proc_Literal) -> (string, Compile_Error, bool) {
    if len(parsed.body) != 1 {
        return "", Compile_Error{message = "reduced transduce fn reducer currently expects a single body expression", span = reducer.span}, false
    }
    prefix := fmt.tprintf("%s := %s\n%s := %s\n", parsed.params[0].name, acc_text, parsed.params[1].name, value_text)
    body := parsed.body[0]
    body_text, err_body, ok_body := emit_reduced_body_update_text(e, body, acc_text, acc_ty)
    if !ok_body {
        return "", err_body, false
    }
    return fmt.tprintf("%s%s", prefix, body_text), {}, true
}

transform_reduce_update_text :: proc(e: ^Emitter, reducer: CST_Form, acc_text, acc_ty, value_text, value_ty: string) -> (string, Compile_Error, bool) {
	if reducer.kind == .List && len(reducer.items) > 0 && is_symbol(reducer.items[0], "fn") {
        parsed, err_parse, ok_parse := parse_proc_literal_form(reducer)
        if !ok_parse {
            return "", err_parse, false
        }
        if len(parsed.params) != 2 {
            return "", Compile_Error{message = "transduce fn reducer expects 2 parameters", span = reducer.span}, false
        }
        if parsed.params[0].ty != acc_ty {
            return "", Compile_Error{message = fmt.tprintf("transduce fn reducer parameter %s must be %s", parsed.params[0].name, acc_ty), span = reducer.span}, false
        }
        if parsed.params[1].ty != value_ty {
            return "", Compile_Error{message = fmt.tprintf("transduce fn reducer parameter %s must be %s", parsed.params[1].name, value_ty), span = reducer.span}, false
        }
        returns := parsed.returns
		if returns.kind != .Single {
			return "", Compile_Error{message = "transduce fn reducer requires an explicit single return type", span = reducer.span}, false
		}
		if returns.single_ty != acc_ty {
			return "", Compile_Error{message = fmt.tprintf("transduce fn reducer must return %s", acc_ty), span = reducer.span}, false
		}
        if form_contains_reduced(reducer) {
            push_local_type_scope(e)
            bind_local_type(e, parsed.params[0].name, acc_ty)
            bind_local_type(e, parsed.params[1].name, value_ty)
            defer pop_local_type_scope(e)
            return transform_reduced_reduce_update_text(e, reducer, acc_text, acc_ty, value_text, parsed)
        }
		text, _, err_literal, ok_literal := transform_proc_literal_call(e, reducer, []Param{{name = acc_text, ty = acc_ty}, {name = value_text, ty = value_ty}}, "transduce fn reducer")
		if !ok_literal {
			return "", err_literal, false
		}
		return fmt.tprintf("%s = %s", acc_text, text), {}, true
	}
	if reducer.kind != .Symbol {
		return "", Compile_Error{message = "transduce reducer currently expects +, a known two-argument function, or a fn literal", span = reducer.span}, false
	}
    if reducer.text == "+" {
        if acc_ty != value_ty {
            return "", Compile_Error{message = fmt.tprintf("+ reducer expects pipeline value %s to match accumulator %s", value_ty, acc_ty), span = reducer.span}, false
        }
        return fmt.tprintf("%s += %s", acc_text, value_text), {}, true
    }
    if reducer.text == "min" || reducer.text == "max" {
        if acc_ty != value_ty {
            return "", Compile_Error{message = fmt.tprintf("%s reducer expects pipeline value %s to match accumulator %s", reducer.text, value_ty, acc_ty), span = reducer.span}, false
        }
        op := "<"
        if reducer.text == "max" {
            op = ">"
        }
        return fmt.tprintf("if %s %s %s %s %s = %s %s", value_text, op, acc_text, "{", acc_text, value_text, "}"), {}, true
    }
    proc_name := map_name(reducer.text)
    proc_decl, ok_proc := find_proc_decl(e, proc_name)
    if !ok_proc {
        return "", Compile_Error{message = fmt.tprintf("transduce reducer must be +, a known two-argument function, or a fn literal: %s", reducer.text), span = reducer.span}, false
    }
    if len(proc_decl.params) != 2 ||
       proc_decl.params[0].ty != acc_ty ||
       proc_decl.params[1].ty != value_ty ||
       proc_decl.returns.kind != .Single ||
       proc_decl.returns.single_ty != acc_ty {
        return "", Compile_Error{message = fmt.tprintf("transduce reducer must be (fn [%s %s] -> %s)", acc_ty, value_ty, acc_ty), span = reducer.span}, false
    }
    return fmt.tprintf("%s = %s", acc_text, emit_call_text(proc_name, []string{acc_text, value_text})), {}, true
}

emit_transform_into_source_expr :: proc(
    e: ^Emitter,
    form: CST_Form,
    output_ty, output_elem_ty: string,
    transform_form, source_form: CST_Form,
    source: ^Source_Decl,
) -> (string, Compile_Error, bool) {
    state_ty, err_state_ty, ok_state_ty := source_state_type(e, source)
    if !ok_state_ty {
        return "", err_state_ty, false
    }
    err_protocol, ok_protocol := validate_source_protocol(e, source, state_ty, source_form.span)
    if !ok_protocol {
        return "", err_protocol, false
    }
    item_ty, err_item_ty, ok_item_ty := source_call_item_type(e, source, source_form)
    if !ok_item_ty {
        return "", err_item_ty, false
    }
    arg_texts, err_args, ok_args := source_call_arg_texts(e, source, source_form, item_ty)
    if !ok_args {
        return "", err_args, false
    }
    steps, err_steps, ok_steps := parse_transform_steps(e, transform_form)
    if !ok_steps {
        return "", err_steps, false
    }
	captures, err_captures, ok_captures := transform_step_capture_params(e, steps[:])
	if !ok_captures {
		return "", err_captures, false
	}
	builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    param_texts: [dynamic]string
    call_arg_texts: [dynamic]string
    call_texts: [dynamic]string
    defer delete(param_texts)
    defer delete(call_arg_texts)
    defer delete(call_texts)
    for capture in captures {
        append(&param_texts, fmt.tprintf("%s: %s", capture.name, capture.ty))
        append(&call_texts, capture.name)
    }
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

    fmt.sbprintf(&builder, "(proc(%s) -> %s %s\n", param_list, output_ty, "{")
    fmt.sbprintf(&builder, "    kvist_source := %s\n", open_call)
    if source.has_dispose {
        fmt.sbprintf(&builder, "    defer %s(&kvist_source)\n", source.dispose_name)
    }
    fmt.sbprintf(&builder, "    kvist_out := make(%s)\n", output_ty)
    err_prelude, ok_prelude := emit_transform_state_prelude(e, &builder, steps[:], 1)
    if !ok_prelude {
        return "", err_prelude, false
    }
    strings.write_string(&builder, "    for {\n")
    fmt.sbprintf(&builder, "        kvist_item, kvist_source_ok := %s(&kvist_source)\n", source.next_name)
    strings.write_string(&builder, "        if !kvist_source_ok {\n")
    strings.write_string(&builder, "            break\n")
    strings.write_string(&builder, "        }\n")
    value_text, value_ty, close_count, err_body, ok_body := emit_transform_pipeline_body(e, &builder, steps[:], "kvist_item", item_ty, 2)
    if !ok_body {
        return "", err_body, false
    }
    if value_ty != output_elem_ty {
        return "", Compile_Error{message = fmt.tprintf("into transform output element type is %s, but pipeline produces %s", output_elem_ty, value_ty), span = form.items[1].span}, false
    }
    append_indent(&builder, 2+close_count)
    fmt.sbprintf(&builder, "append(&kvist_out, %s)\n", value_text)
    emit_transform_closers(&builder, 2+close_count, close_count)
    strings.write_string(&builder, "    }\n")
    strings.write_string(&builder, "    return kvist_out\n")
    strings.write_string(&builder, "})")
    return fmt.tprintf("%s(%s)", strings.to_string(builder), call_args), {}, true
}

emit_transform_into_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) < 4 {
        return "", Compile_Error{message = "into transform expects output type, transform, and source", span = form.span}, false
    }
    output_ty, next_i, err_output_ty, ok_output_ty := parse_type_text_from_forms(form.items[:], 1)
    if !ok_output_ty {
        return "", err_output_ty, false
    }
    if next_i+2 != len(form.items) {
        return "", Compile_Error{message = "into transform expects output type, transform, and source", span = form.span}, false
    }
    transform_form := form.items[next_i]
    source_form := form.items[next_i+1]
    output_spec, err_output_spec, ok_output_spec := transform_into_output_spec(output_ty)
    if !ok_output_spec {
        err_output_spec.span = form.items[1].span
        return "", err_output_spec, false
    }
    if source, ok_source_call := source_call_decl(e, source_form); ok_source_call {
        if output_spec.kind != .Dynamic_Array {
            return "", Compile_Error{message = "into transform over defiter sources currently expects a dynamic array output type", span = form.items[1].span}, false
        }
        return emit_transform_into_source_expr(e, form, output_ty, output_spec.value_ty, transform_form, source_form, source)
    }
    source_ty := ""
    source_elem_ty := ""
    source_text := ""
    loop_source_spec: Transform_Loop_Source
    source_is_loop_source := form_is_transform_loop_call(source_form)
    if source_is_loop_source {
        spec, err_loop, ok_loop := transform_loop_source(e, source_form)
        if !ok_loop {
            return "", err_loop, false
        }
        loop_source_spec = spec
        source_ty = spec.source_ty
        source_elem_ty = spec.item_ty
        source_text = spec.source_text
    } else {
        ok_source_ty := false
        source_ty, ok_source_ty = obvious_form_type(e, source_form)
        if !ok_source_ty {
            return "", Compile_Error{message = "into transform expects a source with an obvious collection type; bind or annotate it first", span = source_form.span}, false
        }
        ok_source_elem_ty := false
        source_elem_ty, ok_source_elem_ty = transform_source_value_type(source_ty)
        if !ok_source_elem_ty {
            return "", Compile_Error{message = fmt.tprintf("into transform expects slice, array, or map source, got %s", source_ty), span = source_form.span}, false
        }
        err_source: Compile_Error
        ok_source := false
        source_text, err_source, ok_source = emit_expr(e, source_form)
        if !ok_source {
            return "", err_source, false
        }
    }
    steps, err_steps, ok_steps := parse_transform_steps(e, transform_form)
    if !ok_steps {
        return "", err_steps, false
    }
	captures, err_captures, ok_captures := transform_step_capture_params(e, steps[:])
	if !ok_captures {
		return "", err_captures, false
	}

	builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    param_texts: [dynamic]string
    call_texts: [dynamic]string
    defer delete(param_texts)
    defer delete(call_texts)
    for capture in captures {
        append(&param_texts, fmt.tprintf("%s: %s", capture.name, capture.ty))
        append(&call_texts, capture.name)
    }
    append(&param_texts, fmt.tprintf("kvist_source: %s", source_ty))
    append(&call_texts, source_text)
    param_list := strings.join(param_texts[:], ", ", context.allocator)
    defer delete(param_list)
    call_args := strings.join(call_texts[:], ", ", context.allocator)
    defer delete(call_args)
    fmt.sbprintf(&builder, "(proc(%s) -> %s %s\n", param_list, output_ty, "{")
    capacity_text := transform_source_count_text(source_ty, "kvist_source")
    fmt.sbprintf(&builder, "    kvist_out := %s\n", transform_into_make_text(output_spec, capacity_text))
    if output_spec.kind == .Data_Vector {
        mark_data_type(e)
        strings.write_string(&builder, "    defer { for kvist_value in kvist_out { kvist_data_release(kvist_value) }; delete(kvist_out) }\n")
    }
    err_prelude, ok_prelude := emit_transform_state_prelude(e, &builder, steps[:], 1)
    if !ok_prelude {
        return "", err_prelude, false
    }
    if source_is_loop_source {
        emit_transform_loop_source_open(&builder, 1, "kvist_item", "kvist_source", loop_source_spec)
    } else {
        fmt.sbprintf(&builder, "    %s\n", transform_source_loop_header(source_ty, "kvist_source", ""))
    }
    value_text, value_ty, close_count, err_body, ok_body := emit_transform_pipeline_body(e, &builder, steps[:], "kvist_item", source_elem_ty, 2)
    if !ok_body {
        return "", err_body, false
    }
    if !transform_into_output_accepts_value(output_spec, value_ty) {
        return "", Compile_Error{message = fmt.tprintf("into transform output value type is %s, but pipeline produces %s", transform_into_output_value_description(output_spec), value_ty), span = form.items[1].span}, false
    }
    emit_transform_into_output_write(&builder, 2+close_count, output_spec, value_text)
    emit_transform_closers(&builder, 2+close_count, close_count)
    strings.write_string(&builder, "    }\n")
    fmt.sbprintf(&builder, "    return %s\n", transform_into_finalize_text(output_spec))
    strings.write_string(&builder, "})")
    return fmt.tprintf("%s(%s)", strings.to_string(builder), call_args), {}, true
}

emit_transform_into_bang_source_expr :: proc(
    e: ^Emitter,
    form: CST_Form,
    target_ty, target_elem_ty, target_text: string,
    transform_form, source_form: CST_Form,
    source: ^Source_Decl,
) -> (string, Compile_Error, bool) {
    state_ty, err_state_ty, ok_state_ty := source_state_type(e, source)
    if !ok_state_ty {
        return "", err_state_ty, false
    }
    err_protocol, ok_protocol := validate_source_protocol(e, source, state_ty, source_form.span)
    if !ok_protocol {
        return "", err_protocol, false
    }
    item_ty, err_item_ty, ok_item_ty := source_call_item_type(e, source, source_form)
    if !ok_item_ty {
        return "", err_item_ty, false
    }
    arg_texts, err_args, ok_args := source_call_arg_texts(e, source, source_form, item_ty)
    if !ok_args {
        return "", err_args, false
    }
    steps, err_steps, ok_steps := parse_transform_steps(e, transform_form)
    if !ok_steps {
        return "", err_steps, false
    }
	captures, err_captures, ok_captures := transform_step_capture_params(e, steps[:])
	if !ok_captures {
		return "", err_captures, false
	}

	builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    param_texts: [dynamic]string
    call_arg_texts: [dynamic]string
    call_texts: [dynamic]string
    defer delete(param_texts)
    defer delete(call_arg_texts)
    defer delete(call_texts)
    append(&param_texts, fmt.tprintf("kvist_out: ^%s", target_ty))
    append(&call_texts, address_of_expr_text(target_text))
    for capture in captures {
        append(&param_texts, fmt.tprintf("%s: %s", capture.name, capture.ty))
        append(&call_texts, capture.name)
    }
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

    fmt.sbprintf(&builder, "(proc(%s) %s\n", param_list, "{")
    fmt.sbprintf(&builder, "    kvist_source := %s\n", open_call)
    if source.has_dispose {
        fmt.sbprintf(&builder, "    defer %s(&kvist_source)\n", source.dispose_name)
    }
    err_prelude, ok_prelude := emit_transform_state_prelude(e, &builder, steps[:], 1)
    if !ok_prelude {
        return "", err_prelude, false
    }
    strings.write_string(&builder, "    for {\n")
    fmt.sbprintf(&builder, "        kvist_item, kvist_source_ok := %s(&kvist_source)\n", source.next_name)
    strings.write_string(&builder, "        if !kvist_source_ok {\n")
    strings.write_string(&builder, "            break\n")
    strings.write_string(&builder, "        }\n")
    value_text, value_ty, close_count, err_body, ok_body := emit_transform_pipeline_body(e, &builder, steps[:], "kvist_item", item_ty, 2)
    if !ok_body {
        return "", err_body, false
    }
    if value_ty != target_elem_ty {
        return "", Compile_Error{message = fmt.tprintf("into! transform target element type is %s, but pipeline produces %s", target_elem_ty, value_ty), span = form.items[1].span}, false
    }
    append_indent(&builder, 2+close_count)
    fmt.sbprintf(&builder, "append(kvist_out, %s)\n", value_text)
    emit_transform_closers(&builder, 2+close_count, close_count)
    strings.write_string(&builder, "    }\n")
    strings.write_string(&builder, "})")
    return fmt.tprintf("%s(%s)", strings.to_string(builder), call_args), {}, true
}

emit_transform_into_bang_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 4 {
        return "", Compile_Error{message = "into! transform expects target, transform, and source", span = form.span}, false
    }
    target_form := form.items[1]
    transform_form := form.items[2]
    source_form := form.items[3]
    target_ty, ok_target_ty := obvious_form_type(e, target_form)
    if !ok_target_ty {
        return "", Compile_Error{message = "into! transform expects a target with an obvious dynamic array type; bind or annotate it first", span = target_form.span}, false
    }
    target_elem_ty, ok_target_elem_ty := dynamic_array_element_type(target_ty)
    if !ok_target_elem_ty {
        return "", Compile_Error{message = "into! transform currently expects a dynamic array target", span = target_form.span}, false
    }
    target_text, err_target, ok_target := emit_expr(e, target_form)
    if !ok_target {
        return "", err_target, false
    }
    if source, ok_source_call := source_call_decl(e, source_form); ok_source_call {
        return emit_transform_into_bang_source_expr(e, form, target_ty, target_elem_ty, target_text, transform_form, source_form, source)
    }
    source_ty := ""
    source_elem_ty := ""
    source_text := ""
    loop_source_spec: Transform_Loop_Source
    source_is_loop_source := form_is_transform_loop_call(source_form)
    if source_is_loop_source {
        spec, err_loop, ok_loop := transform_loop_source(e, source_form)
        if !ok_loop {
            return "", err_loop, false
        }
        loop_source_spec = spec
        source_ty = spec.source_ty
        source_elem_ty = spec.item_ty
        source_text = spec.source_text
    } else {
        ok_source_ty := false
        source_ty, ok_source_ty = obvious_form_type(e, source_form)
        if !ok_source_ty {
            return "", Compile_Error{message = "into! transform expects a source with an obvious collection type; bind or annotate it first", span = source_form.span}, false
        }
        ok_source_elem_ty := false
        source_elem_ty, ok_source_elem_ty = transform_source_value_type(source_ty)
        if !ok_source_elem_ty {
            return "", Compile_Error{message = fmt.tprintf("into! transform expects slice, array, or map source, got %s", source_ty), span = source_form.span}, false
        }
        err_source: Compile_Error
        ok_source := false
        source_text, err_source, ok_source = emit_expr(e, source_form)
        if !ok_source {
            return "", err_source, false
        }
    }
    steps, err_steps, ok_steps := parse_transform_steps(e, transform_form)
    if !ok_steps {
        return "", err_steps, false
    }
	captures, err_captures, ok_captures := transform_step_capture_params(e, steps[:])
	if !ok_captures {
		return "", err_captures, false
	}

	builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    param_texts: [dynamic]string
    call_texts: [dynamic]string
    defer delete(param_texts)
    defer delete(call_texts)
    append(&param_texts, fmt.tprintf("kvist_out: ^%s", target_ty))
    append(&call_texts, address_of_expr_text(target_text))
    for capture in captures {
        append(&param_texts, fmt.tprintf("%s: %s", capture.name, capture.ty))
        append(&call_texts, capture.name)
    }
    append(&param_texts, fmt.tprintf("kvist_source: %s", source_ty))
    append(&call_texts, source_text)
    param_list := strings.join(param_texts[:], ", ", context.allocator)
    defer delete(param_list)
    call_args := strings.join(call_texts[:], ", ", context.allocator)
    defer delete(call_args)
    fmt.sbprintf(&builder, "(proc(%s) %s\n", param_list, "{")
    err_prelude, ok_prelude := emit_transform_state_prelude(e, &builder, steps[:], 1)
    if !ok_prelude {
        return "", err_prelude, false
    }
    if source_is_loop_source {
        emit_transform_loop_source_open(&builder, 1, "kvist_item", "kvist_source", loop_source_spec)
    } else {
        fmt.sbprintf(&builder, "    %s\n", transform_source_loop_header(source_ty, "kvist_source", ""))
    }
    value_text, value_ty, close_count, err_body, ok_body := emit_transform_pipeline_body(e, &builder, steps[:], "kvist_item", source_elem_ty, 2)
    if !ok_body {
        return "", err_body, false
    }
    if value_ty != target_elem_ty {
        return "", Compile_Error{message = fmt.tprintf("into! transform target element type is %s, but pipeline produces %s", target_elem_ty, value_ty), span = target_form.span}, false
    }
    append_indent(&builder, 2+close_count)
    fmt.sbprintf(&builder, "append(kvist_out, %s)\n", value_text)
    emit_transform_closers(&builder, 2+close_count, close_count)
    strings.write_string(&builder, "    }\n")
    strings.write_string(&builder, "})")
    return fmt.tprintf("%s(%s)", strings.to_string(builder), call_args), {}, true
}

emit_transform_transduce_source_expr :: proc(
	e: ^Emitter,
	form: CST_Form,
	transform_form: CST_Form,
	reducer: CST_Form,
    init_text, acc_ty: string,
    source_form: CST_Form,
    source: ^Source_Decl,
) -> (string, Compile_Error, bool) {
    state_ty, err_state_ty, ok_state_ty := source_state_type(e, source)
    if !ok_state_ty {
        return "", err_state_ty, false
    }
    err_protocol, ok_protocol := validate_source_protocol(e, source, state_ty, source_form.span)
    if !ok_protocol {
        return "", err_protocol, false
    }
    item_ty, err_item_ty, ok_item_ty := source_call_item_type(e, source, source_form)
    if !ok_item_ty {
        return "", err_item_ty, false
    }
    arg_texts, err_args, ok_args := source_call_arg_texts(e, source, source_form, item_ty)
    if !ok_args {
        return "", err_args, false
    }
    steps, err_steps, ok_steps := parse_transform_steps(e, transform_form)
    if !ok_steps {
        return "", err_steps, false
    }
	captures, err_captures, ok_captures := transform_step_capture_params(e, steps[:])
	if !ok_captures {
		return "", err_captures, false
	}
	reducer_captures, err_reducer_captures, ok_reducer_captures := transform_fn_capture_params(e, reducer)
	if !ok_reducer_captures {
		return "", err_reducer_captures, false
	}
	defer delete(reducer_captures)
	for capture in reducer_captures {
		append_capture_param_unique(&captures, capture)
	}

	builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    param_texts: [dynamic]string
    call_arg_texts: [dynamic]string
    call_args_texts: [dynamic]string
    defer delete(param_texts)
    defer delete(call_arg_texts)
    defer delete(call_args_texts)
    for capture in captures {
        append(&param_texts, fmt.tprintf("%s: %s", capture.name, capture.ty))
        append(&call_args_texts, capture.name)
    }
    for param, idx in source.params {
        arg_name := fmt.tprintf("kvist_source_arg_%d", idx+1)
        param_ty := source_param_type_for_item(param.ty, source.item_ty, item_ty)
        append(&param_texts, fmt.tprintf("%s: %s", arg_name, param_ty))
        append(&call_arg_texts, arg_name)
    }
    append(&param_texts, fmt.tprintf("kvist_init: %s", acc_ty))
    for arg_text in arg_texts {
        append(&call_args_texts, arg_text)
    }
    append(&call_args_texts, init_text)
    param_list := strings.join(param_texts[:], ", ", context.allocator)
    defer delete(param_list)
    call_args := strings.join(call_args_texts[:], ", ", context.allocator)
    defer delete(call_args)
    open_call := source_call_text(e, source, call_arg_texts[:])

    fmt.sbprintf(&builder, "(proc(%s) -> %s %s\n", param_list, acc_ty, "{")
    fmt.sbprintf(&builder, "    kvist_source := %s\n", open_call)
    if source.has_dispose {
        fmt.sbprintf(&builder, "    defer %s(&kvist_source)\n", source.dispose_name)
    }
    strings.write_string(&builder, "    kvist_acc := kvist_init\n")
    err_prelude, ok_prelude := emit_transform_state_prelude(e, &builder, steps[:], 1)
    if !ok_prelude {
        return "", err_prelude, false
    }
    strings.write_string(&builder, "    for {\n")
    fmt.sbprintf(&builder, "        kvist_item, kvist_source_ok := %s(&kvist_source)\n", source.next_name)
    strings.write_string(&builder, "        if !kvist_source_ok {\n")
    strings.write_string(&builder, "            break\n")
    strings.write_string(&builder, "        }\n")
    value_text, value_ty, close_count, err_body, ok_body := emit_transform_pipeline_body(e, &builder, steps[:], "kvist_item", item_ty, 2)
    if !ok_body {
        return "", err_body, false
    }
    reduce_text, err_reduce, ok_reduce := transform_reduce_update_text(e, reducer, "kvist_acc", acc_ty, value_text, value_ty)
    if !ok_reduce {
        return "", err_reduce, false
    }
    write_transform_reduce_text(&builder, 2+close_count, reduce_text)
    emit_transform_closers(&builder, 2+close_count, close_count)
    strings.write_string(&builder, "    }\n")
    strings.write_string(&builder, "    return kvist_acc\n")
    strings.write_string(&builder, "})")
    return fmt.tprintf("%s(%s)", strings.to_string(builder), call_args), {}, true
}

emit_transform_transduce_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 5 {
        return "", Compile_Error{message = "transduce expects transform, reducer, init, and source", span = form.span}, false
    }
    reducer := form.items[2]
    acc_ty, ok_acc_ty := obvious_form_type(e, form.items[3])
    if !ok_acc_ty {
        return "", Compile_Error{message = "transduce expects an init value with an obvious accumulator type; bind or annotate it first", span = form.items[3].span}, false
    }
    init_text, err_init, ok_init := emit_expr_for_expected_type(e, form.items[3], acc_ty)
    if !ok_init {
        return "", err_init, false
    }
    if source, ok_source_call := source_call_decl(e, form.items[4]); ok_source_call {
        return emit_transform_transduce_source_expr(e, form, form.items[1], reducer, init_text, acc_ty, form.items[4], source)
    }
    source_ty := ""
    source_elem_ty := ""
    source_text := ""
    loop_source_spec: Transform_Loop_Source
    source_is_loop_source := form_is_transform_loop_call(form.items[4])
    if source_is_loop_source {
        spec, err_loop, ok_loop := transform_loop_source(e, form.items[4])
        if !ok_loop {
            return "", err_loop, false
        }
        loop_source_spec = spec
        source_ty = spec.source_ty
        source_elem_ty = spec.item_ty
        source_text = spec.source_text
    } else {
        ok_source_ty := false
        source_ty, ok_source_ty = obvious_form_type(e, form.items[4])
        if !ok_source_ty {
            return "", Compile_Error{message = "transduce expects a source with an obvious collection type; bind or annotate it first", span = form.items[4].span}, false
        }
        ok_source_elem_ty := false
        source_elem_ty, ok_source_elem_ty = transform_source_value_type(source_ty)
        if !ok_source_elem_ty {
            return "", Compile_Error{message = fmt.tprintf("transduce expects slice, array, or map source, got %s", source_ty), span = form.items[4].span}, false
        }
        err_source: Compile_Error
        ok_source := false
        source_text, err_source, ok_source = emit_expr(e, form.items[4])
        if !ok_source {
            return "", err_source, false
        }
    }
    steps, err_steps, ok_steps := parse_transform_steps(e, form.items[1])
    if !ok_steps {
        return "", err_steps, false
    }
	captures, err_captures, ok_captures := transform_step_capture_params(e, steps[:])
	if !ok_captures {
		return "", err_captures, false
	}
	reducer_captures, err_reducer_captures, ok_reducer_captures := transform_fn_capture_params(e, reducer)
	if !ok_reducer_captures {
		return "", err_reducer_captures, false
	}
	defer delete(reducer_captures)
	for capture in reducer_captures {
		append_capture_param_unique(&captures, capture)
	}

	builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    param_texts: [dynamic]string
    call_texts: [dynamic]string
    defer delete(param_texts)
    defer delete(call_texts)
    for capture in captures {
        append(&param_texts, fmt.tprintf("%s: %s", capture.name, capture.ty))
        append(&call_texts, capture.name)
    }
    append(&param_texts, fmt.tprintf("kvist_source: %s", source_ty))
    append(&param_texts, fmt.tprintf("kvist_init: %s", acc_ty))
    append(&call_texts, source_text)
    append(&call_texts, init_text)
    param_list := strings.join(param_texts[:], ", ", context.allocator)
    defer delete(param_list)
    call_args := strings.join(call_texts[:], ", ", context.allocator)
    defer delete(call_args)
    fmt.sbprintf(&builder, "(proc(%s) -> %s %s\n", param_list, acc_ty, "{")
    strings.write_string(&builder, "    kvist_acc := kvist_init\n")
    err_prelude, ok_prelude := emit_transform_state_prelude(e, &builder, steps[:], 1)
    if !ok_prelude {
        return "", err_prelude, false
    }
    if source_is_loop_source {
        emit_transform_loop_source_open(&builder, 1, "kvist_item", "kvist_source", loop_source_spec)
    } else {
        fmt.sbprintf(&builder, "    %s\n", transform_source_loop_header(source_ty, "kvist_source", ""))
    }
    value_text, value_ty, close_count, err_body, ok_body := emit_transform_pipeline_body(e, &builder, steps[:], "kvist_item", source_elem_ty, 2)
    if !ok_body {
        return "", err_body, false
    }
    reduce_text, err_reduce, ok_reduce := transform_reduce_update_text(e, reducer, "kvist_acc", acc_ty, value_text, value_ty)
    if !ok_reduce {
        return "", err_reduce, false
    }
    write_transform_reduce_text(&builder, 2+close_count, reduce_text)
    emit_transform_closers(&builder, 2+close_count, close_count)
    strings.write_string(&builder, "    }\n")
    strings.write_string(&builder, "    return kvist_acc\n")
    strings.write_string(&builder, "})")
    return fmt.tprintf("%s(%s)", strings.to_string(builder), call_args), {}, true
}

captured_thread_callback_params :: proc(e: ^Emitter, ctx: ^Callback_Context) -> (params: [dynamic]Param, err: Compile_Error, ok: bool) {
    for capture_name, idx in ctx.capture_names {
        ty, ok_ty := lookup_local_type(e, capture_name)
        if !ok_ty {
            ty = fmt.tprintf("C%d", idx+1)
        }
        append(&params, Param{name = capture_name, ty = ty})
    }
    return params, Compile_Error{}, true
}

specialize_thread_worker_for_callback_contexts :: proc(e: ^Emitter, worker_name: string, params: []Param, args: []CST_Form, emit_callback: bool) -> (specialized_worker: string, specialized_params: [dynamic]Param, err: Compile_Error, ok: bool) {
    specialized_worker = worker_name
    specialized_index := -1
    capture_count := 0

    for param, idx in params {
        append(&specialized_params, param)
        if idx >= len(args) || !type_text_is_proc(param.ty) || args[idx].kind != .Symbol {
            continue
        }
        arg_name := map_name(args[idx].text)
        ctx, ok_context := lookup_callback_context(e, arg_name)
        if !ok_context || len(ctx.capture_names) == 0 || ctx.field_selector != "" {
            continue
        }
        if specialized_index >= 0 {
            return specialized_worker, specialized_params, Compile_Error{message = "thread-start currently supports one captured callback argument per worker"}, false
        }
        inserted_ty, ok_insert := proc_type_insert_capture_params_text(param.ty, len(ctx.capture_names))
        if !ok_insert {
            return specialized_worker, specialized_params, Compile_Error{message = fmt.tprintf("thread worker parameter %s is not a proc type", param.name)}, false
        }
        specialized_params[len(specialized_params)-1].ty = inserted_ty
        callback_params, err_params, ok_params := captured_thread_callback_params(e, ctx)
        if !ok_params {
            return specialized_worker, specialized_params, err_params, false
        }
        for callback_param in callback_params {
            append(&specialized_params, callback_param)
        }
        specialized_index = idx
        capture_count = len(ctx.capture_names)
    }

    if specialized_index >= 0 {
        if emit_callback {
            mark_captured_proc_specialization(e, worker_name, specialized_index, capture_count)
        }
        specialized_worker = captured_specialization_name(worker_name, specialized_index, capture_count)
    }
    return specialized_worker, specialized_params, Compile_Error{}, true
}

thread_start_signature :: proc(e: ^Emitter, form: CST_Form, emit_callback := false) -> (spec: Thread_Start_Spec, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 {
        return spec, Compile_Error{message = "thread-start expects task type and worker function", span = form.span}, false
    }
    task_form := form.items[1]
    if task_form.kind != .Symbol {
        return spec, Compile_Error{message = "thread-start task type must be a type constructor symbol", span = task_form.span}, false
    }
    task_ty := map_name(task_form.text)
    worker_form := form.items[2]
    if worker_form.kind == .Symbol {
        worker_name, worker_decl, ok_worker := resolve_proc_call_decl(e, worker_form.text)
        if !ok_worker {
            return spec, Compile_Error{message = fmt.tprintf("thread-start worker must name a known function: %s", worker_form.text), span = worker_form.span}, false
        }
        arg_count := len(form.items) - 3
        if arg_count != len(worker_decl.params) {
            return spec, Compile_Error{message = fmt.tprintf("thread-start worker %s expects %d arguments, got %d", worker_form.text, len(worker_decl.params), arg_count), span = form.span}, false
        }
        params, returns, ok_signature := proc_decl_specialized_signature_for_args(e, worker_decl, form.items[3:])
        if !ok_signature {
            return spec, Compile_Error{message = fmt.tprintf("thread-start worker %s generic types could not be inferred from arguments", worker_form.text), span = form.span}, false
        }
        if returns.kind != .Single {
            return spec, Compile_Error{message = "thread-start worker must return exactly one value", span = worker_form.span}, false
        }
        specialized_worker, specialized_params, err_specialized, ok_specialized := specialize_thread_worker_for_callback_contexts(e, worker_name, params[:], form.items[3:], emit_callback)
        if !ok_specialized {
            return spec, err_specialized, false
        }
        return Thread_Start_Spec{
            worker    = specialized_worker,
            task_ty   = task_ty,
            params    = specialized_params[:],
            result_ty = returns.single_ty,
        }, {}, true
    }

    if worker_form.kind == .List && len(worker_form.items) > 0 && is_symbol(worker_form.items[0], "fn") {
        parsed, err_parse, ok_parse := parse_proc_literal_form(worker_form)
        if !ok_parse {
            return spec, err_parse, false
        }
        arg_count := len(form.items) - 3
        if arg_count != len(parsed.params) {
            return spec, Compile_Error{message = fmt.tprintf("thread-start inline worker expects %d arguments, got %d", len(parsed.params), arg_count), span = form.span}, false
        }
        if parsed.returns.kind != .Single {
            return spec, Compile_Error{message = "thread-start inline worker must return exactly one value", span = worker_form.span}, false
        }
        param_names: [dynamic]string
        for param in parsed.params {
            append(&param_names, param.name)
        }
        captures := collect_proc_literal_captures(e, parsed.body[:], param_names[:])
        callback_proc := ""
        if emit_callback {
            params: [dynamic]Param
            for capture in captures {
                append(&params, capture)
            }
            for param in parsed.params {
                append(&params, param)
            }
            text, err_proc, ok_proc := emit_proc_literal_text(e, params[:], parsed.returns, parsed.body[:])
            if !ok_proc {
                return spec, err_proc, false
            }
            callback_proc = text
        }
        return Thread_Start_Spec{
            worker        = parallel_inline_worker_name(worker_form),
            task_ty       = task_ty,
            params        = parsed.params[:],
            result_ty     = parsed.returns.single_ty,
            captures      = captures[:],
            callback_proc = callback_proc,
        }, {}, true
    }

    return spec, Compile_Error{message = "thread-start expects a known worker function or inline fn", span = worker_form.span}, false
}

thread_detach_signature :: proc(e: ^Emitter, form: CST_Form, emit_callback := false) -> (spec: Thread_Detach_Spec, err: Compile_Error, ok: bool) {
    if len(form.items) < 2 {
        return spec, Compile_Error{message = "thread-detach expects a worker function", span = form.span}, false
    }
    worker_form := form.items[1]
    if worker_form.kind == .Symbol {
        worker_name, worker_decl, ok_worker := resolve_proc_call_decl(e, worker_form.text)
        if !ok_worker {
            return spec, Compile_Error{message = fmt.tprintf("thread-detach worker must name a known function: %s", worker_form.text), span = worker_form.span}, false
        }
        arg_count := len(form.items) - 2
        if arg_count != len(worker_decl.params) {
            return spec, Compile_Error{message = fmt.tprintf("thread-detach worker %s expects %d arguments, got %d", worker_form.text, len(worker_decl.params), arg_count), span = form.span}, false
        }
        params, returns, ok_signature := proc_decl_specialized_signature_for_args(e, worker_decl, form.items[2:])
        if !ok_signature {
            return spec, Compile_Error{message = fmt.tprintf("thread-detach worker %s generic types could not be inferred from arguments", worker_form.text), span = form.span}, false
        }
        if returns.kind != .None {
            return spec, Compile_Error{message = "thread-detach worker must not return a value", span = worker_form.span}, false
        }
        specialized_worker, specialized_params, err_specialized, ok_specialized := specialize_thread_worker_for_callback_contexts(e, worker_name, params[:], form.items[2:], emit_callback)
        if !ok_specialized {
            return spec, err_specialized, false
        }
        return Thread_Detach_Spec{
            worker = specialized_worker,
            params = specialized_params[:],
        }, {}, true
    }

    if worker_form.kind == .List && len(worker_form.items) > 0 && is_symbol(worker_form.items[0], "fn") {
        parsed, err_parse, ok_parse := parse_proc_literal_form(worker_form)
        if !ok_parse {
            return spec, err_parse, false
        }
        arg_count := len(form.items) - 2
        if arg_count != len(parsed.params) {
            return spec, Compile_Error{message = fmt.tprintf("thread-detach inline worker expects %d arguments, got %d", len(parsed.params), arg_count), span = form.span}, false
        }
        if parsed.returns.kind != .None {
            return spec, Compile_Error{message = "thread-detach inline worker must not return a value", span = worker_form.span}, false
        }
        param_names: [dynamic]string
        for param in parsed.params {
            append(&param_names, param.name)
        }
        captures := collect_proc_literal_captures(e, parsed.body[:], param_names[:])
        callback_proc := ""
        if emit_callback {
            params: [dynamic]Param
            for capture in captures {
                append(&params, capture)
            }
            for param in parsed.params {
                append(&params, param)
            }
            text, err_proc, ok_proc := emit_proc_literal_text(e, params[:], parsed.returns, parsed.body[:])
            if !ok_proc {
                return spec, err_proc, false
            }
            callback_proc = text
        }
        return Thread_Detach_Spec{
            worker        = parallel_inline_worker_name(worker_form),
            params        = parsed.params[:],
            captures      = captures[:],
            callback_proc = callback_proc,
        }, {}, true
    }

    return spec, Compile_Error{message = "thread-detach expects a known worker function or inline fn", span = worker_form.span}, false
}

parallel_inline_worker_name :: proc(worker_form: CST_Form) -> string {
    return fmt.tprintf("inline_%d_%d", worker_form.span.start, worker_form.span.end)
}

emit_parallel_args_for_params :: proc(e: ^Emitter, args: []CST_Form, params: []Param) -> (arg_texts: [dynamic]string, err: Compile_Error, ok: bool) {
    param_idx := 0
    for arg in args {
        if param_idx >= len(params) {
            return arg_texts, Compile_Error{message = "too many thread worker arguments"}, false
        }
        expected_ty := params[param_idx].ty
        arg_text, err_arg, ok_arg := emit_expr_for_expected_type(e, arg, expected_ty)
        if !ok_arg {
            return arg_texts, err_arg, false
        }
        append(&arg_texts, arg_text)
        param_idx += 1

        if type_text_is_proc(expected_ty) && arg.kind == .Symbol {
            arg_name := map_name(arg.text)
            if ctx, ok_context := lookup_callback_context(e, arg_name); ok_context && len(ctx.capture_names) > 0 && ctx.field_selector == "" {
                for capture_name in ctx.capture_names {
                    if param_idx >= len(params) || params[param_idx].name != capture_name {
                        return arg_texts, Compile_Error{message = "internal error: thread worker capture parameter mismatch", span = arg.span}, false
                    }
                    append(&arg_texts, capture_name)
                    param_idx += 1
                }
            }
        }
    }
    if param_idx != len(params) {
        return arg_texts, Compile_Error{message = "too few thread worker arguments"}, false
    }
    return arg_texts, {}, true
}

emit_thread_start_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    spec, err_spec, ok_spec := thread_start_signature(e, form, true)
    if !ok_spec {
        return "", err_spec, false
    }
    arg_texts, err_args, ok_args := emit_parallel_args_for_params(e, form.items[3:], spec.params)
    if !ok_args {
        return "", err_args, false
    }
    mark_thread_start(e, spec)
    call_args: [dynamic]string
    for capture in spec.captures {
        append(&call_args, capture.name)
    }
    for arg_text in arg_texts {
        append(&call_args, arg_text)
    }
    return emit_call_text(thread_start_helper_name(spec), call_args[:]), {}, true
}

emit_thread_detach_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    spec, err_spec, ok_spec := thread_detach_signature(e, form, true)
    if !ok_spec {
        return "", err_spec, false
    }
    arg_texts, err_args, ok_args := emit_parallel_args_for_params(e, form.items[2:], spec.params)
    if !ok_args {
        return "", err_args, false
    }
    mark_thread_detach(e, spec)
    call_args: [dynamic]string
    for capture in spec.captures {
        append(&call_args, capture.name)
    }
    for arg_text in arg_texts {
        append(&call_args, arg_text)
    }
    return emit_call_text(thread_detach_helper_name(spec), call_args[:]), {}, true
}

type_text_is_slice :: proc(text: string) -> bool {
    return len(text) >= 2 && text[:2] == "[]"
}

collection_element_type :: proc(type_text: string) -> (string, bool) {
    if type_text_is_dynamic_array(type_text) {
        return type_text[len("[dynamic]"):], true
    }
    if type_text_is_slice(type_text) {
        return type_text[len("[]"):], true
    }
    if len(type_text) > 0 && type_text[0] == '[' && !type_text_is_dynamic_array(type_text) {
        close := strings.index(type_text, "]")
        if close >= 0 && close+1 < len(type_text) {
            return type_text[close+1:], true
        }
    }
    return "", false
}

transform_source_value_type :: proc(type_text: string) -> (string, bool) {
    if type_text == "Data" {
        return "Data", true
    }
    if _, value_ty, ok_map := map_type_parts(type_text); ok_map {
        return value_ty, true
    }
    return collection_element_type(type_text)
}

transform_source_loop_header :: proc(source_ty, source_text, key_name: string) -> string {
    if source_ty == "Data" {
        return fmt.tprintf(
            "assert(%s.kind == .Nil || %s.kind == .List || %s.kind == .Vector || %s.kind == .Set, \"Data transform source expects nil, list, vector, or set\"); for kvist_item in %s.payload.items %s",
            source_text,
            source_text,
            source_text,
            source_text,
            source_text,
            "{",
        )
    }
    if type_text_is_map(source_ty) {
        if len(key_name) > 0 {
            return fmt.tprintf("for %s, kvist_item in %s %s", key_name, source_text, "{")
        }
        return fmt.tprintf("for _, kvist_item in %s %s", source_text, "{")
    }
    return fmt.tprintf("for kvist_item in %s %s", source_text, "{")
}

transform_source_count_text :: proc(source_ty, source_text: string) -> string {
    if source_ty == "Data" {
        return fmt.tprintf("kvist_data_count(%s)", source_text)
    }
    return fmt.tprintf("len(%s)", source_text)
}

emit_transform_loop_source_open :: proc(builder: ^strings.Builder, depth: int, item_name, source_text: string, spec: Transform_Loop_Source) {
    append_indent(builder, depth)
    fmt.sbprintf(builder, "for %s, %s in %s %s\n", spec.key_name, spec.value_name, source_text, "{")
    append_indent(builder, depth+1)
    fmt.sbprintf(builder, "%s := %s\n", item_name, spec.item_text)
}

dynamic_array_element_type :: proc(type_text: string) -> (string, bool) {
    if !type_text_is_dynamic_array(type_text) {
        return "", false
    }
    return type_text[len("[dynamic]"):], true
}

entry_type_parts :: proc(type_text: string) -> (key, value: string, ok: bool) {
    open := strings.index(type_text, "(")
    if open <= 0 || !strings.has_suffix(type_text, ")") {
        return "", "", false
    }
    constructor := strings.trim_space(type_text[:open])
    if !strings.has_suffix(constructor, ".entry") {
        return "", "", false
    }
    inner := type_text[open+1:len(type_text)-1]
    parts := split_top_level_commas(inner)
    defer delete(parts)
    if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
        return "", "", false
    }
    return parts[0], parts[1], true
}

transform_into_output_accepts_value :: proc(spec: Transform_Into_Output, value_ty: string) -> bool {
    if spec.kind == .Map && spec.value_ty == "" {
        key_ty, val_ty, ok_entry := entry_type_parts(value_ty)
        return ok_entry && key_ty == spec.map_key_ty && val_ty == spec.map_val_ty
    }
    return value_ty == spec.value_ty
}

transform_into_output_value_description :: proc(spec: Transform_Into_Output) -> string {
    if spec.kind == .Map && spec.value_ty == "" {
        return fmt.tprintf("entry(%s, %s)", spec.map_key_ty, spec.map_val_ty)
    }
    return spec.value_ty
}

transform_into_output_spec :: proc(output_ty: string) -> (spec: Transform_Into_Output, err: Compile_Error, ok: bool) {
    spec.output_ty = output_ty
    if output_ty == "Data" {
        spec.kind = .Data_Vector
        spec.value_ty = "Data"
        return spec, {}, true
    }
    if elem_ty, ok_elem := dynamic_array_element_type(output_ty); ok_elem {
        spec.kind = .Dynamic_Array
        spec.value_ty = elem_ty
        return spec, {}, true
    }
    if key_ty, value_ty, ok_map := map_type_parts(output_ty); ok_map && value_ty == "struct{}" {
        spec.kind = .Set
        spec.map_key_ty = key_ty
        spec.map_val_ty = value_ty
        spec.value_ty = key_ty
        return spec, {}, true
    }
    if key_ty, value_ty, ok_map := map_type_parts(output_ty); ok_map {
        spec.kind = .Map
        spec.map_key_ty = key_ty
        spec.map_val_ty = value_ty
        return spec, {}, true
    }
    return spec, Compile_Error{message = "into transform expects a dynamic array, map, or set output type"}, false
}

emit_transform_into_output_write :: proc(builder: ^strings.Builder, depth: int, spec: Transform_Into_Output, value_text: string) {
    append_indent(builder, depth)
    switch spec.kind {
    case .Dynamic_Array:
        fmt.sbprintf(builder, "append(&kvist_out, %s)\n", value_text)
    case .Data_Vector:
        fmt.sbprintf(builder, "kvist_data_append_retained(&kvist_out, %s)\n", value_text)
    case .Map:
        fmt.sbprintf(builder, "kvist_out[(%s).key] = (%s).value\n", value_text, value_text)
    case .Set:
        fmt.sbprintf(builder, "kvist_out[%s] = struct%s%s\n", value_text, "{}", "{}")
    }
}

transform_into_make_text :: proc(spec: Transform_Into_Output, capacity_text: string) -> string {
    if capacity_text == "" {
        return fmt.tprintf("make(%s)", spec.output_ty)
    }
    switch spec.kind {
    case .Dynamic_Array:
        return fmt.tprintf("make(%s, 0, %s)", spec.output_ty, capacity_text)
    case .Data_Vector:
        return fmt.tprintf("make([dynamic]Data, 0, %s)", capacity_text)
    case .Map:
        return fmt.tprintf("make(%s, %s)", spec.output_ty, capacity_text)
    case .Set:
        return fmt.tprintf("make(%s, %s)", spec.output_ty, capacity_text)
    }
    return fmt.tprintf("make(%s)", spec.output_ty)
}

transform_into_finalize_text :: proc(spec: Transform_Into_Output) -> string {
    if spec.kind == .Data_Vector {
        return "kvist_data_freeze_items(.Vector, &kvist_out)"
    }
    return "kvist_out"
}

append_indent :: proc(builder: ^strings.Builder, depth: int) {
    for _ in 0..<depth {
        strings.write_string(builder, "    ")
    }
}
