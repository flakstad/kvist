package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

emit_update_rhs :: proc(e: ^Emitter, fn_form: CST_Form, arg_texts: []string) -> (string, Compile_Error, bool) {
    if fn_form.kind == .Symbol {
        if fn_form.text == "inc" && len(arg_texts) == 1 {
            return fmt.tprintf("(%s) + 1", arg_texts[0]), {}, true
        }
        if fn_form.text == "dec" && len(arg_texts) == 1 {
            return fmt.tprintf("(%s) - 1", arg_texts[0]), {}, true
        }
        if operator_text, err_op, ok_op := emit_operator_text(fn_form.text, arg_texts, fn_form.span); ok_op {
            return operator_text, {}, true
        } else if err_op.message != "" {
            return "", err_op, false
        }
        return emit_call_text(map_name(fn_form.text), arg_texts), {}, true
    }

    fn_text, err_fn, ok_fn := emit_expr(e, fn_form)
    if !ok_fn {
        return "", err_fn, false
    }
    return emit_call_text(fn_text, arg_texts), {}, true
}

shallow_update_temp_name :: proc(e: ^Emitter) -> string {
    e.temp_counter += 1
    return fmt.tprintf("kvist_update_%d", e.temp_counter)
}

struct_field_type_for_update :: proc(e: ^Emitter, target_ty, field: string) -> (string, bool) {
    if key_ty, value_ty, ok_entry := entry_type_parts(target_ty); ok_entry {
        switch field {
        case "key":
            return key_ty, true
        case "value":
            return value_ty, true
        }
    }
    if struct_decl, ok_struct := find_struct_decl(e, target_ty); ok_struct {
        if struct_field, ok_field := find_struct_field(struct_decl, field); ok_field {
            return struct_field.ty, true
        }
    }
    if fields, ok_imported := imported_odin_type_fields(e, target_ty); ok_imported {
        defer delete_struct_field_slice(&fields)
        if struct_field, ok_field := find_field_in_slice(fields[:], field); ok_field {
            return struct_field.ty, true
        }
    }
    return "", false
}

split_field_path_text :: proc(text: string) -> (fields: [dynamic]string, ok: bool) {
    if text == "" {
        return fields, false
    }
    start := 0
    for i := 0; i <= len(text); i += 1 {
        if i == len(text) || text[i] == '.' {
            if i == start {
                return fields, false
            }
            append(&fields, map_name(text[start:i]))
            start = i + 1
        }
    }
    return fields, len(fields) > 0
}

field_path_text :: proc(fields: []string) -> string {
    return strings.join(fields, ".", context.allocator)
}

field_access_text :: proc(base: string, fields: []string) -> string {
    if len(fields) == 0 {
        return base
    }
    path := field_path_text(fields)
    defer delete(path)
    return fmt.tprintf("%s.%s", base, path)
}

field_path_from_selector :: proc(form: CST_Form) -> (fields: [dynamic]string, ok: bool) {
    if form.kind == .Symbol && len(form.text) > 1 && form.text[0] == '.' {
        return split_field_path_text(form.text[1:])
    }
    return fields, false
}

field_path_place_parts :: proc(place: CST_Form) -> (target: CST_Form, fields: [dynamic]string, field_span: Span, ok: bool) {
    if place.kind == .List &&
       len(place.items) == 3 &&
       place.items[0].kind == .Symbol &&
       place.items[0].text == "__kvist_field" &&
       place.items[2].kind == .Symbol {
        target, fields, _, ok = field_path_place_parts(place.items[1])
        if !ok {
            target = place.items[1]
        }
        more_fields, ok_more := split_field_path_text(place.items[2].text)
        if !ok_more {
            return place.items[1], fields, place.items[2].span, false
        }
        append(&fields, ..more_fields[:])
        return target, fields, place.items[2].span, true
    }
    if place.kind == .Symbol {
        dot := strings.index(place.text, ".")
        if dot > 0 && dot+1 < len(place.text) {
            fields, ok_fields := split_field_path_text(place.text[dot+1:])
            if !ok_fields {
                return {}, fields, place.span, false
            }
            return CST_Form{kind = .Symbol, text = place.text[:dot], span = place.span},
                   fields,
                   place.span,
                   true
        }
    }
    return {}, fields, {}, false
}

shallow_assoc_args :: proc(form: CST_Form) -> (target: CST_Form, fields: [dynamic]string, field_span: Span, value: CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) == 3 {
        place_target, place_fields, place_span, ok_place := field_path_place_parts(form.items[1])
        if !ok_place {
            return {}, fields, {}, {}, Compile_Error{message = "assoc expects a field place such as user.name or user.address.city", span = form.items[1].span}, false
        }
        return place_target, place_fields, place_span, form.items[2], {}, true
    }
    if len(form.items) == 4 {
        selector_fields, ok_field := field_path_from_selector(form.items[2])
        if !ok_field {
            return {}, fields, {}, {}, Compile_Error{message = "assoc expects a field selector such as .name or .address.city", span = form.items[2].span}, false
        }
        return form.items[1], selector_fields, form.items[2].span, form.items[3], {}, true
    }
    return {}, fields, {}, {}, Compile_Error{message = "assoc expects place and value, or target, field selector, and value", span = form.span}, false
}

shallow_update_args :: proc(form: CST_Form) -> (target: CST_Form, fields: [dynamic]string, field_span: Span, updater: CST_Form, rest: []CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) >= 3 {
        place_target, place_fields, place_span, ok_place := field_path_place_parts(form.items[1])
        if ok_place {
            return place_target, place_fields, place_span, form.items[2], form.items[3:], {}, true
        }
    }
    if len(form.items) >= 4 {
        selector_fields, ok_field := field_path_from_selector(form.items[2])
        if !ok_field {
            return {}, fields, {}, {}, form.items[:0], Compile_Error{message = "update expects a field selector such as .name or .address.city", span = form.items[2].span}, false
        }
        return form.items[1], selector_fields, form.items[2].span, form.items[3], form.items[4:], {}, true
    }
    return {}, fields, {}, {}, form.items[:0], Compile_Error{message = "update expects place and updater, or target, field selector, and updater", span = form.span}, false
}

shallow_update_return_type :: proc(e: ^Emitter, form: CST_Form) -> (string, bool) {
    if form.kind != .List || len(form.items) < 2 {
        return "", false
    }
    if place_target, _, _, ok_place := field_path_place_parts(form.items[1]); ok_place {
        return obvious_form_type(e, place_target)
    }
    return obvious_form_type(e, form.items[1])
}

struct_field_type_for_update_path :: proc(e: ^Emitter, target_ty: string, fields: []string, op: string, field_span: Span) -> (string, Compile_Error, bool) {
    ty := target_ty
    for field in fields {
        field_ty, ok_field_ty := struct_field_type_for_update(e, ty, field)
        if !ok_field_ty {
            return "", Compile_Error{message = fmt.tprintf("%s could not find field .%s on %s", op, field, ty), span = field_span}, false
        }
        ty = field_ty
    }
    return ty, {}, true
}

struct_field_owns_string_for_update_path :: proc(e: ^Emitter, target_ty: string, fields: []string) -> bool {
    ty := target_ty
    for field_name, idx in fields {
        struct_decl, ok_struct := find_struct_decl(e, ty)
        if !ok_struct {
            return false
        }
        field, ok_field := find_struct_field(struct_decl, field_name)
        if !ok_field {
            return false
        }
        if idx == len(fields)-1 {
            return field.owns_string
        }
        ty = field.ty
    }
    return false
}

struct_field_owns_dynamic_array_for_update_path :: proc(
    e: ^Emitter,
    target_ty: string,
    fields: []string,
) -> bool {
    ty := target_ty
    for field_name, idx in fields {
        struct_decl, ok_struct := find_struct_decl(e, ty)
        if !ok_struct {
            return false
        }
        field, ok_field := find_struct_field(struct_decl, field_name)
        if !ok_field {
            return false
        }
        if idx == len(fields)-1 {
            return field.owns_dynamic_array
        }
        ty = field.ty
    }
    return false
}

emit_shallow_assoc_copy_expr :: proc(e: ^Emitter, target_form: CST_Form, target_text, target_ty: string, fields: []string, field_span: Span, value_form: CST_Form) -> (string, Compile_Error, bool) {
    field_ty, err_field_ty, ok_field_ty := struct_field_type_for_update_path(e, target_ty, fields, "assoc", field_span)
    if !ok_field_ty {
        return "", err_field_ty, false
    }
    value_text, err_value, ok_value := emit_expr_for_expected_type(e, value_form, field_ty)
    if !ok_value {
        return "", err_value, false
    }
    temp := shallow_update_temp_name(e)
    target_field := field_access_text(temp, fields)
    target_init := "kvist_target"
    if type_text_has_managed_lifecycle(e, target_ty) &&
       !form_produces_owned_managed_type(e, target_form, target_ty) {
        target_init = managed_clone_value_text(e, target_ty, "kvist_target")
    }
    assignment := fmt.tprintf("%s = kvist_value", target_field)
    if struct_field_owns_string_for_update_path(e, target_ty, fields) {
        mark_core_strings(e)
        assignment = fmt.tprintf("delete(%s)\n    %s = strings.clone(kvist_value)", target_field, target_field)
    } else if struct_field_owns_dynamic_array_for_update_path(e, target_ty, fields) {
        move := form_produces_owned_value(value_form, e)
        assignment = managed_dynamic_array_assignment_text(
            e,
            field_ty,
            address_of_expr_text(target_field),
            "kvist_value",
            move,
        )
    } else if type_text_has_managed_lifecycle(e, field_ty) {
        move := form_produces_owned_managed_type(e, value_form, field_ty)
        helper := managed_assign_helper_name(e, field_ty, move)
        assignment = emit_call_text(helper, []string{address_of_expr_text(target_field), "kvist_value"})
    }
    return fmt.tprintf("(proc(kvist_target: %s, kvist_value: %s) -> %s %s\n    %s := %s\n    %s\n    return %s\n})(%s, %s)",
                       target_ty, field_ty, target_ty, "{", temp, target_init, assignment, temp, target_text, value_text), {}, true
}

emit_data_assoc_expr :: proc(e: ^Emitter, form: CST_Form, target_text: string) -> (string, Compile_Error, bool) {
    if len(form.items) != 4 {
        return "", Compile_Error{message = "assoc on Data expects collection, key, and value", span = form.span}, false
    }
    key_text, err_key, ok_key := emit_data_lookup_key(e, form.items[2])
    if !ok_key {
        return "", err_key, false
    }
    value_text := ""
    value_owned := false
    err_value: Compile_Error
    ok_value := false
    #partial switch form.items[3].kind {
    case .Nil, .Bool, .Number, .String, .Keyword, .Vector, .Brace, .Set:
        value_text, err_value, ok_value = emit_data_value_literal(e, form.items[3])
    case:
        value_text, value_owned, err_value, ok_value = runtime_data_unquote_expr(e, form.items[3])
    }
    if !ok_value {
        return "", err_value, false
    }
    mark_data_type(e)
    if value_owned {
        return fmt.tprintf(
            "(proc(kvist_target, kvist_key, kvist_value: Data) -> Data {{\n    defer kvist_data_release(kvist_value)\n    return kvist_data_assoc(kvist_target, kvist_key, kvist_value)\n}})(%s, %s, %s)",
            target_text,
            key_text,
            value_text,
        ), {}, true
    }
    return emit_call_text("kvist_data_assoc", []string{target_text, key_text, value_text}), {}, true
}

emit_data_update_expr :: proc(e: ^Emitter, form: CST_Form, target_text: string) -> (string, Compile_Error, bool) {
    if len(form.items) < 4 {
        return "", Compile_Error{message = "update on Data expects collection, key, updater, and optional arguments", span = form.span}, false
    }
    key_text, err_key, ok_key := emit_data_lookup_key(e, form.items[2])
    if !ok_key {
        return "", err_key, false
    }
    arg_texts: [dynamic]string
    append(&arg_texts, "kvist_data_get(kvist_target, kvist_key)")
    rest_texts: [dynamic]string
    rest_names: [dynamic]string
    rest_types: [dynamic]string
    defer delete(rest_texts)
    defer delete(rest_names)
    defer delete(rest_types)
    for rest_form, idx in form.items[4:] {
        rest_ty := ""
        ok_rest_ty := false
        if form.items[3].kind == .Symbol {
            updater_name := map_name(form.items[3].text)
            if updater_decl, ok_updater := find_proc_decl(e, updater_name); ok_updater && idx+1 < len(updater_decl.params) {
                rest_ty = updater_decl.params[idx+1].ty
                ok_rest_ty = true
            }
            delete(updater_name)
        }
        if !ok_rest_ty {
            rest_ty, ok_rest_ty = obvious_form_type(e, rest_form)
        }
        if !ok_rest_ty {
            return "", Compile_Error{
                message = "update on Data expects extra updater arguments with obvious types; bind or annotate the value first",
                span = rest_form.span,
            }, false
        }
        rest_text, err_rest, ok_rest := emit_expr_for_expected_type(e, rest_form, rest_ty)
        if !ok_rest {
            return "", err_rest, false
        }
        rest_name := fmt.tprintf("kvist_arg_%d", idx)
        append(&rest_names, rest_name)
        append(&rest_types, rest_ty)
        append(&rest_texts, rest_text)
        append(&arg_texts, rest_name)
    }
    updated_text, err_updated, ok_updated := emit_update_rhs(e, form.items[3], arg_texts[:])
    if !ok_updated {
        return "", err_updated, false
    }
    if form.items[3].kind == .Symbol {
        updater_name := map_name(form.items[3].text)
        if updater_decl, ok_updater := find_proc_decl(e, updater_name); ok_updater && updater_decl.borrows_result {
            updated_text = emit_call_text("kvist_data_retain", []string{updated_text})
        }
        delete(updater_name)
    }
    params_builder := strings.builder_make()
    defer strings.builder_destroy(&params_builder)
    call_builder := strings.builder_make()
    defer strings.builder_destroy(&call_builder)
    for name, idx in rest_names {
        fmt.sbprintf(&params_builder, ", %s: %s", name, rest_types[idx])
        fmt.sbprintf(&call_builder, ", %s", rest_texts[idx])
    }
    mark_data_type(e)
    return fmt.tprintf(
        "(proc(kvist_target, kvist_key: Data%s) -> Data {{\n    kvist_updated := %s\n    defer kvist_data_release(kvist_updated)\n    return kvist_data_assoc(kvist_target, kvist_key, kvist_updated)\n}})(%s, %s%s)",
        strings.to_string(params_builder),
        updated_text,
        target_text,
        key_text,
        strings.to_string(call_builder),
    ), {}, true
}

emit_data_dissoc_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) < 3 {
        return "", Compile_Error{message = "dissoc expects Data and at least one key", span = form.span}, false
    }
    target_ty, ok_target_ty := obvious_form_type(e, form.items[1])
    if !ok_target_ty || target_ty != "Data" {
        return "", Compile_Error{message = "dissoc currently expects a Data map", span = form.items[1].span}, false
    }
    target_text, err_target, ok_target := emit_expr(e, form.items[1])
    if !ok_target {
        return "", err_target, false
    }
    keys: [dynamic]string
    defer delete(keys)
    for key_form in form.items[2:] {
        key_text, err_key, ok_key := emit_data_lookup_key(e, key_form)
        if !ok_key {
            return "", err_key, false
        }
        append(&keys, key_text)
    }
    mark_data_type(e)
    if len(keys) == 1 {
        return emit_call_text("kvist_data_dissoc", []string{target_text, keys[0]}), {}, true
    }
    params_builder := strings.builder_make()
    defer strings.builder_destroy(&params_builder)
    call_builder := strings.builder_make()
    defer strings.builder_destroy(&call_builder)
    body_builder := strings.builder_make()
    defer strings.builder_destroy(&body_builder)
    for key, idx in keys {
        fmt.sbprintf(&params_builder, ", kvist_key_%d: Data", idx)
        fmt.sbprintf(&call_builder, ", %s", key)
        fmt.sbprintf(
            &body_builder,
            "    kvist_data_move_assign(&kvist_result, kvist_data_dissoc(kvist_result, kvist_key_%d))\n",
            idx,
        )
    }
    return fmt.tprintf(
        "(proc(kvist_target: Data%s) -> Data {{\n    kvist_result := kvist_data_retain(kvist_target)\n%s    return kvist_result\n}})(%s%s)",
        strings.to_string(params_builder),
        strings.to_string(body_builder),
        target_text,
        strings.to_string(call_builder),
    ), {}, true
}

emit_data_dissoc_in_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 3 {
        return "", Compile_Error{message = "dissoc-in expects Data and one Data path", span = form.span}, false
    }
    target_ty, ok_target_ty := obvious_form_type(e, form.items[1])
    if !ok_target_ty || target_ty != "Data" {
        return "", Compile_Error{message = "dissoc-in currently expects a Data map", span = form.items[1].span}, false
    }
    target_text, err_target, ok_target := emit_expr(e, form.items[1])
    if !ok_target {
        return "", err_target, false
    }
    path_text, err_path, ok_path := emit_expr_for_expected_type(e, form.items[2], "Data")
    if !ok_path {
        return "", err_path, false
    }
    mark_data_type(e)
    return emit_call_text("kvist_data_dissoc_in", []string{target_text, path_text}), {}, true
}
