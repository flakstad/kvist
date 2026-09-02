package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

Brace_Pair :: struct {
    key:   string,
    value: string,
}

emit_brace_pair_texts :: proc(e: ^Emitter, form: CST_Form, keyword_fields := true, expected_key_type := "", expected_value_type := "") -> (pairs: [dynamic]Brace_Pair, err: Compile_Error, ok: bool) {
    i := 0
    for i < len(form.items) {
        if i+1 >= len(form.items) {
            return pairs, Compile_Error{message = "missing brace-form value", span = form.span}, false
        }

        key := form.items[i]
        val := form.items[i+1]
        value_text: string
        err_value: Compile_Error
        ok_value: bool
        if expected_value_type != "" {
            value_text, err_value, ok_value = emit_expr_for_expected_type(e, val, expected_value_type)
        } else {
            value_text, err_value, ok_value = emit_expr(e, val)
        }
        if !ok_value {
            return pairs, err_value, false
        }

        #partial switch key.kind {
        case .Keyword:
            if keyword_fields {
                field_name, ok_field := brace_key_name(key)
                if !ok_field {
                    return pairs, Compile_Error{message = "aggregate field keys must be unqualified keywords such as :name", span = key.span}, false
                }
                append(&pairs, Brace_Pair{key = field_name, value = value_text})
            } else {
                append(&pairs, Brace_Pair{key = keyword_literal_text(e, key.text), value = value_text})
            }
        case .Symbol:
            if len(key.text) > 1 && key.text[len(key.text)-1] == ':' {
                return pairs, Compile_Error{
                    message = "suffix `:` is reserved for type annotations; use a keyword key such as :name",
                    span = key.span,
                }, false
            }
            key_text: string
            err_key: Compile_Error
            ok_key: bool
            if expected_key_type != "" {
                key_text, err_key, ok_key = emit_expr_for_expected_type(e, key, expected_key_type)
            } else {
                key_text, err_key, ok_key = emit_expr(e, key)
            }
            if !ok_key {
                return pairs, err_key, false
            }
            append(&pairs, Brace_Pair{key = key_text, value = value_text})
        case .String:
            append(&pairs, Brace_Pair{key = emit_string_literal_text(key), value = value_text})
        case .Regex:
            append(&pairs, Brace_Pair{key = emit_regex_literal_text(key), value = value_text})
        case:
            key_text: string
            err_key: Compile_Error
            ok_key: bool
            if expected_key_type != "" {
                key_text, err_key, ok_key = emit_expr_for_expected_type(e, key, expected_key_type)
            } else {
                key_text, err_key, ok_key = emit_expr(e, key)
            }
            if !ok_key {
                return pairs, err_key, false
            }
            append(&pairs, Brace_Pair{key = key_text, value = value_text})
        }
        i += 2
    }
    return pairs, {}, true
}

emit_brace_pairs :: proc(e: ^Emitter, form: CST_Form, keyword_fields := true) -> (string, Compile_Error, bool) {
    pairs, err_pairs, ok_pairs := emit_brace_pair_texts(e, form, keyword_fields)
    if !ok_pairs {
        return "", err_pairs, false
    }
    return emit_brace_pairs_text(pairs[:]), {}, true
}

emit_brace_pairs_text :: proc(pairs: []Brace_Pair) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for pair, idx in pairs {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "%s = %s", pair.key, pair.value)
    }
    return strings.clone(strings.to_string(builder))
}

emit_vector_item_texts :: proc(e: ^Emitter, form: CST_Form, expected_item_type := "") -> (items: [dynamic]string, err: Compile_Error, ok: bool) {
    for item in form.items {
        text: string
        err_item: Compile_Error
        ok_item: bool
        if expected_item_type != "" {
            text, err_item, ok_item = emit_expr_for_expected_type(e, item, expected_item_type)
        } else {
            text, err_item, ok_item = emit_expr(e, item)
        }
        if !ok_item {
            return items, err_item, false
        }
        append(&items, text)
    }
    return items, {}, true
}

emit_vector_items :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    items, err_items, ok_items := emit_vector_item_texts(e, form)
    if !ok_items {
        return "", err_items, false
    }
    return emit_vector_items_text(items[:]), {}, true
}

emit_vector_items_text :: proc(items: []string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for text, idx in items {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        strings.write_string(&builder, text)
    }
    return strings.clone(strings.to_string(builder))
}

emit_quaternion_vector_constructor :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 4 {
        return "", Compile_Error{message = "quaternion constructor expects four components", span = form.span}, false
    }
    items, err_items, ok_items := emit_vector_item_texts(e, form)
    if !ok_items {
        return "", err_items, false
    }
    return fmt.tprintf(
        "quaternion(x=%s, y=%s, z=%s, w=%s)",
        items[0],
        items[1],
        items[2],
        items[3],
    ), {}, true
}

emit_quaternion_arg_constructor :: proc(e: ^Emitter, args: []CST_Form, span: Span) -> (string, Compile_Error, bool) {
    if len(args) != 4 {
        return "", Compile_Error{message = "quaternion constructor expects four components", span = span}, false
    }
    items: [dynamic]string
    for arg in args {
        item, err_item, ok_item := emit_expr(e, arg)
        if !ok_item {
            return "", err_item, false
        }
        append(&items, item)
    }
    return fmt.tprintf(
        "quaternion(x=%s, y=%s, z=%s, w=%s)",
        items[0],
        items[1],
        items[2],
        items[3],
    ), {}, true
}

brace_form_starts_with_field_label :: proc(form: CST_Form) -> bool {
    if len(form.items) == 0 {
        return true
    }
    first := form.items[0]
    _, ok := brace_key_name(first)
    return ok
}

has_multiline_items :: proc(items: []string) -> bool {
    for item in items {
        if contains_newline(item) {
            return true
        }
    }
    return false
}

type_form_needs_dynamic_literals :: proc(form: CST_Form) -> bool {
    if form.kind == .Symbol {
        return len(form.text) >= 4 && form.text[:4] == "map[" ||
               len(form.text) >= 9 && form.text[:9] == "[dynamic]" ||
               strings.has_prefix(form.text, "#soa[")
    }
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    return form.items[0].text == "map" || form.items[0].text == "dynamic" || form.items[0].text == "#soa"
}

type_text_is_soa :: proc(text: string) -> bool {
    return strings.has_prefix(text, "#soa[")
}

type_text_is_dynamic_soa :: proc(text: string) -> bool {
    return strings.has_prefix(text, "#soa[dynamic]")
}

type_text_is_pointer_to_dynamic_soa :: proc(text: string) -> bool {
    return strings.has_prefix(text, "^#soa[dynamic]")
}

type_text_is_soa_array :: proc(text: string) -> bool {
    return type_text_is_soa(text)
}

emit_dynamic_soa_vector_literal :: proc(e: ^Emitter, type_text: string, form: CST_Form) -> (string, Compile_Error, bool) {
    items, err_items, ok_items := emit_vector_item_texts(e, form)
    if !ok_items {
        return "", err_items, false
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "(proc() -> ")
    strings.write_string(&builder, type_text)
    strings.write_string(&builder, " {\n")
    strings.write_string(&builder, fmt.tprintf("    out := make(%s)\n", type_text))
    if len(items) > 0 {
        strings.write_string(&builder, "    append_soa(&out")
        for item in items {
            strings.write_string(&builder, ", ")
            strings.write_string(&builder, item)
        }
        strings.write_string(&builder, ")\n")
    }
    strings.write_string(&builder, "    return out\n")
    strings.write_string(&builder, "})()")
    return strings.clone(strings.to_string(builder)), {}, true
}

emit_vector_literal :: proc(e: ^Emitter, prefix: string, form: CST_Form) -> (string, Compile_Error, bool) {
    expected_item_type, _ := collection_element_type(prefix)
    items, err_items, ok_items := emit_vector_item_texts(e, form, expected_item_type)
    if !ok_items {
        return "", err_items, false
    }
    if !has_multiline_items(items[:]) {
        inner := emit_vector_items_text(items[:])
        return surround_with_braces(prefix, inner), {}, true
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, prefix)
    strings.write_string(&builder, "{\n")
    for item in items {
        append_indented_multiline(&builder, item, "    ", ",")
        strings.write_byte(&builder, '\n')
    }
    strings.write_byte(&builder, '}')
    return strings.clone(strings.to_string(builder)), {}, true
}

emit_brace_literal :: proc(e: ^Emitter, prefix: string, form: CST_Form) -> (string, Compile_Error, bool) {
    keyword_fields := !type_text_is_map(prefix)
    if prefix != "" && keyword_fields && !brace_form_starts_with_field_label(form) {
        return "", Compile_Error{message = "positional aggregate literals use vector syntax", span = form.span}, false
    }

    expected_key_type := ""
    expected_value_type := ""
    if key_ty, value_ty, ok_map := map_type_parts(prefix); ok_map {
        expected_key_type = key_ty
        expected_value_type = value_ty
    }
    pairs, err_pairs, ok_pairs := emit_brace_pair_texts(e, form, keyword_fields, expected_key_type, expected_value_type)
    if !ok_pairs {
        return "", err_pairs, false
    }

    multiline := false
    for pair in pairs {
        if contains_newline(pair.value) {
            multiline = true
            break
        }
    }
    if !multiline {
        inner := emit_brace_pairs_text(pairs[:])
        return surround_with_braces(prefix, inner), {}, true
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, prefix)
    strings.write_string(&builder, "{\n")
    for pair in pairs {
        item := fmt.tprintf("%s = %s", pair.key, pair.value)
        append_indented_multiline(&builder, item, "    ", ",")
        strings.write_byte(&builder, '\n')
    }
    strings.write_byte(&builder, '}')
    return strings.clone(strings.to_string(builder)), {}, true
}

emit_struct_field_value_text :: proc(e: ^Emitter, field: Struct_Field, value: CST_Form) -> (string, Compile_Error, bool) {
    if (value.kind == .String || value.kind == .Regex || value.kind == .Bool || value.kind == .Number) &&
       type_text_is_builtin_odin_scalar(field.ty) &&
       !form_obviously_matches_expected_type(e, value, field.ty) {
        source_name := field.source_name
        if source_name == "" {
            source_name = field.name
        }
        return "", Compile_Error{
            message = fmt.tprintf("struct constructor literal type mismatch for :%s", source_name),
            span = value.span,
        }, false
    }
    value_text, err_value, ok_value := emit_expr_for_expected_type(e, value, field.ty)
    if !ok_value {
        return "", err_value, false
    }
    moved_local := false
    if value.kind == .Symbol && ownership_type_has_destructor(e, field.ty) {
        name := map_name(value.text)
        if owner_flag, ok_owner := lookup_managed_local_owner(e, name); ok_owner {
            value_text = managed_move_local_value_text(e, field.ty, value_text, owner_flag)
            moved_local = true
        }
        delete(name)
    } else if owner_name, has_owner := form_direct_borrow_owner_name(value, e); has_owner {
        if owner_flag, ok_owner := lookup_managed_local_owner(e, owner_name); ok_owner {
            value_text = managed_move_local_value_text(e, field.ty, value_text, owner_flag)
            moved_local = true
        }
        delete(owner_name)
    }
    if field.owns_string {
        if !form_produces_owned_value(value, e) {
            mark_core_strings(e)
            value_text = emit_call_text("strings.clone", []string{value_text})
        }
    } else if !field.owns_dynamic_array &&
       type_text_has_managed_lifecycle(e, field.ty) &&
       !moved_local &&
       !form_produces_owned_managed_type(e, value, field.ty) {
        value_text = managed_clone_value_text(e, field.ty, value_text)
    }
    return value_text, {}, true
}

emit_struct_pairs_literal :: proc(type_name: string, pairs: []Brace_Pair, include_field_names := true) -> string {
    multiline := false
    for pair in pairs {
        if contains_newline(pair.value) {
            multiline = true
            break
        }
    }
    if !multiline {
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        strings.write_string(&builder, type_name)
        strings.write_byte(&builder, '{')
        for pair, idx in pairs {
            if idx > 0 {
                strings.write_string(&builder, ", ")
            }
            if include_field_names {
                fmt.sbprintf(&builder, "%s = %s", pair.key, pair.value)
            } else {
                strings.write_string(&builder, pair.value)
            }
        }
        strings.write_byte(&builder, '}')
        return strings.clone(strings.to_string(builder))
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, type_name)
    strings.write_string(&builder, "{\n")
    for pair in pairs {
        item := pair.value
        if include_field_names {
            item = fmt.tprintf("%s = %s", pair.key, pair.value)
        }
        append_indented_multiline(&builder, item, "    ", ",")
        strings.write_byte(&builder, '\n')
    }
    strings.write_byte(&builder, '}')
    return strings.clone(strings.to_string(builder))
}

struct_args_use_named_fields :: proc(args: []CST_Form) -> bool {
    return keyword_arg_tail_is_syntax(args, 0)
}

imported_struct_args_use_named_fields :: proc(args: []CST_Form) -> bool {
    return keyword_arg_tail_is_syntax(args, 0)
}

emit_struct_named_literal :: proc(e: ^Emitter, struct_decl: ^Struct_Decl, named_args: []CST_Form, span: Span) -> (string, Compile_Error, bool) {
    if len(named_args) == 0 || len(named_args)%2 != 0 {
        return "", Compile_Error{message = "named struct construction uses alternating :field value pairs", span = span}, false
    }

    pairs: [dynamic]Brace_Pair
    seen: [dynamic]string
    i := 0
    for i < len(named_args) {
        if i+1 >= len(named_args) {
            return "", Compile_Error{message = "missing struct constructor value", span = span}, false
        }
        key := named_args[i]
        value := named_args[i+1]
        field_name, ok_key := brace_key_name(key)
        if !ok_key {
            return "", Compile_Error{message = "named struct construction uses alternating keyword/value pairs such as :name value", span = key.span}, false
        }
        field, ok_field := find_struct_field(struct_decl, field_name)
        if !ok_field {
            return "", Compile_Error{message = fmt.tprintf("unknown struct constructor field %s", key.text), span = key.span}, false
        }
        for existing in seen {
            if existing == field_name {
                return "", Compile_Error{message = fmt.tprintf("duplicate struct constructor field %s", key.text), span = key.span}, false
            }
        }
        append(&seen, field_name)
        value_text, err_value, ok_value := emit_struct_field_value_text(e, field^, value)
        if !ok_value {
            return "", err_value, false
        }
        append(&pairs, Brace_Pair{key = field_name, value = value_text})
        i += 2
    }
    for &field in struct_decl.fields {
        if !field.has_default {
            continue
        }
        provided := false
        for pair in pairs {
            if pair.key == field.name {
                provided = true
                break
            }
        }
        if provided {
            continue
        }
        default_text, err_default, ok_default := emit_struct_field_default(e, field)
        if !ok_default {
            return "", err_default, false
        }
        append(&pairs, Brace_Pair{key = field.name, value = default_text})
    }

    return emit_struct_pairs_literal(struct_decl.name, pairs[:]), {}, true
}

emit_struct_positional_literal :: proc(e: ^Emitter, struct_decl: ^Struct_Decl, values: []CST_Form, span: Span) -> (string, Compile_Error, bool) {
    if len(values) > len(struct_decl.fields) {
        return "", Compile_Error{message = fmt.tprintf("%s expects at most %d positional fields", struct_decl.name, len(struct_decl.fields)), span = span}, false
    }
    pairs: [dynamic]Brace_Pair
    for value, idx in values {
        field := struct_decl.fields[idx]
        value_text, err_value, ok_value := emit_struct_field_value_text(e, field, value)
        if !ok_value {
            return "", err_value, false
        }
        append(&pairs, Brace_Pair{key = field.name, value = value_text})
    }
    for idx := len(values); idx < len(struct_decl.fields); idx += 1 {
        field := struct_decl.fields[idx]
        if !field.has_default {
            continue
        }
        default_text, err_default, ok_default := emit_struct_field_default(e, field)
        if !ok_default {
            return "", err_default, false
        }
        append(&pairs, Brace_Pair{key = field.name, value = default_text})
    }
    return emit_struct_pairs_literal(struct_decl.name, pairs[:], false), {}, true
}

emit_imported_struct_named_literal :: proc(e: ^Emitter, type_text: string, fields: []Struct_Field, named_args: []CST_Form, span: Span) -> (string, Compile_Error, bool) {
    if len(named_args) == 0 || len(named_args)%2 != 0 {
        return "", Compile_Error{message = "named struct construction uses alternating :field value pairs", span = span}, false
    }

    pairs: [dynamic]Brace_Pair
    seen: [dynamic]string
    i := 0
    for i < len(named_args) {
        if i+1 >= len(named_args) {
            return "", Compile_Error{message = "missing struct constructor value", span = span}, false
        }
        key := named_args[i]
        value := named_args[i+1]
        field_name, ok_key := brace_key_name(key)
        if !ok_key {
            return "", Compile_Error{message = "named struct construction uses alternating keyword/value pairs such as :name value", span = key.span}, false
        }
        field, ok_field := find_field_in_slice(fields, field_name)
        if !ok_field {
            return "", Compile_Error{message = fmt.tprintf("unknown struct constructor field %s", key.text), span = key.span}, false
        }
        for existing in seen {
            if existing == field_name {
                return "", Compile_Error{message = fmt.tprintf("duplicate struct constructor field %s", key.text), span = key.span}, false
            }
        }
        append(&seen, field_name)
        value_text, err_value, ok_value := emit_struct_field_value_text(e, field^, value)
        if !ok_value {
            return "", err_value, false
        }
        append(&pairs, Brace_Pair{key = field_name, value = value_text})
        i += 2
    }

    return emit_struct_pairs_literal(type_text, pairs[:]), {}, true
}

emit_imported_struct_positional_literal :: proc(e: ^Emitter, type_text: string, fields: []Struct_Field, values: []CST_Form, span: Span) -> (string, Compile_Error, bool) {
    if len(values) > len(fields) {
        return "", Compile_Error{message = fmt.tprintf("%s expects at most %d positional fields", type_text, len(fields)), span = span}, false
    }
    pairs: [dynamic]Brace_Pair
    for value, idx in values {
        field := fields[idx]
        value_text, err_value, ok_value := emit_struct_field_value_text(e, field, value)
        if !ok_value {
            return "", err_value, false
        }
        append(&pairs, Brace_Pair{key = field.name, value = value_text})
    }
    return emit_struct_pairs_literal(type_text, pairs[:], false), {}, true
}

emit_call_text :: proc(name: string, arg_texts: []string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    multiline := false
    for arg_text in arg_texts {
        if contains_newline(arg_text) {
            multiline = true
            break
        }
    }

    if multiline {
        strings.write_string(&builder, name)
        strings.write_string(&builder, "(\n")
        for arg_text, idx in arg_texts {
            suffix := ","
            if idx == len(arg_texts)-1 {
                suffix = ""
            }
            append_indented_multiline(&builder, arg_text, "    ", suffix)
            strings.write_byte(&builder, '\n')
        }
        strings.write_byte(&builder, ')')
        return strings.clone(strings.to_string(builder))
    }

    fmt.sbprintf(&builder, "%s(", name)
    for arg_text, idx in arg_texts {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        strings.write_string(&builder, arg_text)
    }
    strings.write_byte(&builder, ')')
    return strings.clone(strings.to_string(builder))
}

find_proc_decl :: proc(e: ^Emitter, name: string) -> (^Proc_Decl, bool) {
    ensure_emitter_indexes(e)
    if idx, found := e.proc_indices[name]; found {
        return &e.decls[idx].proc_decl, true
    }
    dispatch_prefix := "kvist_repl_dispatch_"
    if strings.has_prefix(name, dispatch_prefix) {
        original_name := name[len(dispatch_prefix):]
        if name_in_list(
            e.repl_current_proc_names,
            original_name,
        ) {
            if idx, found := e.proc_indices[original_name]; found {
                return &e.decls[idx].proc_decl, true
            }
        }
    }
    return nil, false
}

find_overload_decl :: proc(e: ^Emitter, name: string) -> (^Const_Decl, bool) {
    ensure_emitter_indexes(e)
    if idx, found := e.overload_indices[name]; found {
        return &e.decls[idx].const_decl, true
    }
    return nil, false
}

proc_accepts_positional_arg_count :: proc(proc_decl: ^Proc_Decl, count: int) -> bool {
    if count > len(proc_decl.params) {
        return false
    }
    for param in proc_decl.params[count:] {
        if !param.has_default {
            return false
        }
    }
    return true
}

literal_matches_expected_type :: proc(e: ^Emitter, form: CST_Form, expected_type: string) -> bool {
    if type_text_is_managed_value(e, expected_type) {
        return form.kind == .Vector || form.kind == .Brace || form.kind == .Set
    }
    #partial switch form.kind {
    case .Vector:
        _, ok := collection_element_type(expected_type)
        _, is_set := set_element_type(expected_type)
        return ok && !type_text_is_map(expected_type) && !is_set
    case .Brace:
        return type_text_is_map(expected_type)
    case .Set:
        _, ok := set_element_type(expected_type)
        return ok
    }
    return false
}

overload_literal_arg_expected_type :: proc(
    e: ^Emitter,
    overload_name: string,
    args: []CST_Form,
    arg_index: int,
) -> (string, bool) {
    if arg_index < 0 || arg_index >= len(args) {
        return "", false
    }
    arg := args[arg_index]
    if arg.kind != .Vector && arg.kind != .Brace && arg.kind != .Set {
        return "", false
    }
    overload_decl, ok_overload := find_overload_decl(e, overload_name)
    if !ok_overload {
        return "", false
    }

    selected := ""
    for member in overload_decl.overload_members {
        proc_decl, ok_proc := find_proc_decl(e, member)
        if !ok_proc ||
           !proc_accepts_positional_arg_count(proc_decl, len(args)) ||
           arg_index >= len(proc_decl.params) {
            continue
        }
        expected_type := proc_decl.params[arg_index].ty
        if !literal_matches_expected_type(e, arg, expected_type) {
            continue
        }
        if selected == "" {
            selected = expected_type
        } else if selected != expected_type {
            return "", false
        }
    }
    if selected == "" {
        return "", false
    }
    return strings.clone(selected), true
}

call_head_is_overload :: proc(e: ^Emitter, head: CST_Form) -> bool {
    if head.kind != .Symbol {
        return false
    }
    name := map_name(head.text)
    defer delete(name)
    _, ok := find_overload_decl(e, name)
    return ok
}

call_arg_expected_type :: proc(e: ^Emitter, call: CST_Form, item_index: int) -> (string, bool) {
    if call.kind != .List ||
       len(call.items) == 0 ||
       call.items[0].kind != .Symbol ||
       item_index < 1 ||
       item_index >= len(call.items) {
        return "", false
    }
    arg_index := item_index-1
    head_name := map_name(call.items[0].text)
    defer delete(head_name)
    if (head_name == "decode_data" || head_name == "validate_data") &&
       (item_index == 2 || item_index == 3) {
        return strings.clone("Data"), true
    }
    if head_name == "odin_contains" &&
       arg_index == 1 &&
       len(call.items) == 3 {
        if collection_ty, ok_collection_ty := obvious_form_type(e, call.items[1]);
           ok_collection_ty && collection_ty == "Data" {
            return strings.clone("Data"), true
        }
    }
    if struct_decl, ok_struct := find_struct_decl(e, head_name); ok_struct {
        args := call.items[1:]
        if struct_args_use_named_fields(args) {
            if arg_index%2 == 1 {
                field_name, ok_key := brace_key_name(args[arg_index-1])
                if ok_key {
                    if field, ok_field := find_struct_field(struct_decl, field_name); ok_field {
                        return strings.clone(field.ty), true
                    }
                }
            }
            return "", false
        }
        if len(args) == 1 && args[0].kind == .Vector {
            return strings.clone(head_name), true
        }
        if arg_index < len(struct_decl.fields) {
            return strings.clone(struct_decl.fields[arg_index].ty), true
        }
        return "", false
    }
    if _, proc_decl, ok_proc := resolve_proc_call_decl(e, call.items[0].text); ok_proc && proc_decl != nil {
        args := call.items[1:]
        resolution := keyword_args_call_resolution(e, proc_decl, args)
        if resolution.mode == .Named {
            if arg_index < resolution.split && arg_index < len(proc_decl.params) {
                return strings.clone(proc_decl.params[arg_index].ty), true
            }
            relative := arg_index-resolution.split
            if relative >= 0 && relative%2 == 1 {
                field_name, ok_key := brace_key_name(args[arg_index-1])
                if ok_key {
                    if param, ok_param := find_proc_param(proc_decl, field_name); ok_param {
                        return strings.clone(param.ty), true
                    }
                }
            }
            return "", false
        }
        if resolution.mode == .Ambiguous {
            return "", false
        }
        if arg_index < len(proc_decl.params) {
            return strings.clone(proc_decl.params[arg_index].ty), true
        }
    }
    if expected_type, ok_expected := overload_literal_arg_expected_type(e, head_name, call.items[1:], arg_index); ok_expected {
        return expected_type, true
    }
    return "", false
}

symbol_tail_starts_upper :: proc(text: string) -> bool {
    start := 0
    for ch, idx in text {
        if ch == '.' || ch == '/' {
            start = idx + 1
        }
    }
    return start < len(text) && text[start] >= 'A' && text[start] <= 'Z'
}

static_def_call_head :: proc(text: string) -> bool {
    if strings.has_prefix(text, "[") ||
       strings.has_prefix(text, "^") ||
       strings.has_prefix(text, "map[") ||
       strings.has_prefix(text, "soa[") ||
       strings.has_prefix(text, "matrix[") {
        return true
    }
    switch text {
    case
        "+", "-", "*", "/", "%", "%%",
        "&", "|", "~", "^", "<<", ">>",
        "&&", "||", "==", "!=", "<", "<=", ">", ">=", "!",
        "min", "max", "abs", "clamp",
        "len", "cap", "size-of", "align-of", "offset-of", "type-of", "typeid-of",
        "bool", "string", "cstring", "rawptr", "uintptr",
        "int", "i8", "i16", "i32", "i64", "i128",
        "uint", "u8", "u16", "u32", "u64", "u128",
        "f16", "f32", "f64", "complex64", "complex128", "quaternion128",
        "fn", "quote":
        return true
    case:
        return symbol_tail_starts_upper(text)
    }
}

def_call_head_is_declared_type :: proc(e: ^Emitter, mapped_name: string) -> bool {
    ensure_emitter_indexes(e)
    if idx, found := e.const_indices[mapped_name]; found &&
       e.decls[idx].const_decl.is_type_alias {
        return true
    }
    if _, found := e.struct_indices[mapped_name]; found {
        return true
    }
    if _, found := e.enum_indices[mapped_name]; found {
        return true
    }
    if _, found := e.union_indices[mapped_name]; found {
        return true
    }
    return false
}

def_value_requires_runtime_init :: proc(e: ^Emitter, form: CST_Form, depth: int = 0) -> bool {
    if depth > 64 {
        return true
    }
    if form.kind != .List && form.kind != .Vector && form.kind != .Brace && form.kind != .Set {
        return false
    }
    if form.kind != .List {
        for item in form.items {
            if def_value_requires_runtime_init(e, item, depth+1) {
                return true
            }
        }
        return false
    }
    if len(form.items) == 0 {
        return false
    }
    head := form.items[0]
    if head.kind != .Symbol {
        for item in form.items[1:] {
            if def_value_requires_runtime_init(e, item, depth+1) {
                return true
            }
        }
        return false
    }
    if head.text == "quote" || head.text == "fn" {
        return false
    }
    if head.text == "if" || head.text == "case" {
        return true
    }
    mapped_head := map_name(head.text)
    defer delete(mapped_head)
    if _, ok_proc := find_proc_decl(e, mapped_head); ok_proc {
        return true
    }
    if _, proc_decl, ok_proc := resolve_proc_call_decl(e, head.text); ok_proc && proc_decl != nil {
        return true
    }
    if def_call_head_is_declared_type(e, mapped_head) || static_def_call_head(head.text) {
        for item in form.items[1:] {
            if def_value_requires_runtime_init(e, item, depth+1) {
                return true
            }
        }
        return false
    }
    return true
}

runtime_def_value_type :: proc(e: ^Emitter, form: CST_Form) -> (string, bool) {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return "", false
    }
    if form.items[0].text == "quasiquote" {
        return strings.clone("Data"), true
    }
    mapped_head := map_name(form.items[0].text)
    defer delete(mapped_head)
    if proc_decl, ok_proc := find_proc_decl(e, mapped_head); ok_proc {
        if return_ty, ok_return_ty := proc_decl_obvious_call_return_type(e, proc_decl, form.items[1:]); ok_return_ty {
            return return_ty, true
        }
        return "", false
    }
    if _, proc_decl, ok_proc := resolve_proc_call_decl(e, form.items[0].text); ok_proc && proc_decl != nil {
        if return_ty, ok_return_ty := proc_decl_obvious_call_return_type(e, proc_decl, form.items[1:]); ok_return_ty {
            return return_ty, true
        }
    }
    if return_ty, ok_return_ty := obvious_form_type(e, form); ok_return_ty {
        return strings.clone(return_ty), true
    }
    return "", false
}

classify_def_initializers :: proc(e: ^Emitter) -> (Compile_Error, bool) {
    for &decl in e.decls {
        if decl.kind != .Const || decl.const_decl.is_type_alias || decl.const_decl.is_overload {
            continue
        }
        if decl.const_decl.init_kind != .Auto {
            continue
        }
        if def_value_requires_runtime_init(e, decl.const_decl.value) {
            if !decl.const_decl.has_ty {
                inferred_ty, inferred := runtime_def_value_type(e, decl.const_decl.value)
                if !inferred {
                    return Compile_Error{
                        message = "cannot infer runtime-initialized def type; add an explicit type or call a single-result Kvist function",
                        span = decl.const_decl.value.span,
                    }, false
                }
                decl.const_decl.has_ty = true
                decl.const_decl.ty = inferred_ty
            }
            decl.const_decl.init_kind = .Runtime
        } else {
            decl.const_decl.init_kind = .Static
        }
    }
    return {}, true
}

find_transform_decl :: proc(e: ^Emitter, name: string) -> (^Transform_Decl, bool) {
    ensure_emitter_indexes(e)
    if idx, found := e.transform_indices[name]; found {
        return &e.decls[idx].transform_decl, true
    }
    return nil, false
}

find_source_decl :: proc(e: ^Emitter, name: string) -> (^Source_Decl, bool) {
    ensure_emitter_indexes(e)
    if idx, found := e.source_indices[name]; found {
        return &e.decls[idx].source_decl, true
    }
    return nil, false
}

resolve_proc_call_decl :: proc(e: ^Emitter, head: string) -> (call_name: string, proc_decl: ^Proc_Decl, ok: bool) {
    head_name := map_name(head)
    found_proc, ok_proc := find_proc_decl(e, head_name)
    if ok_proc {
        return head_name, found_proc, true
    }

    slash := strings.index(head, "/")
    dot := strings.index(head, ".")
    separator := slash
    if separator < 0 {
        separator = dot
    }
    if separator < 0 {
        return head_name, nil, false
    }

    alias_text := head[:separator]
    suffix_text := head[separator+1:]
    alias := map_name(alias_text)
    defer delete(alias)
    suffix := map_name(suffix_text)
    defer delete(suffix)
    ensure_emitter_indexes(e)
    if pkg, found := e.kvist_import_packages[alias_text]; found {
        package_name := fmt.tprintf("%s__%s", pkg, suffix)
        found_proc, ok_proc = find_proc_decl(e, package_name)
        if ok_proc {
            delete(head_name)
            return package_name, found_proc, true
        }
    }
    package_name := fmt.tprintf("%s__%s", alias, suffix)
    found_proc, ok_proc = find_proc_decl(e, package_name)
    if ok_proc {
        delete(head_name)
        return package_name, found_proc, true
    }
    return head_name, nil, false
}

emit_named_call_arg_texts :: proc(e: ^Emitter, named_args: []CST_Form, span: Span) -> (arg_texts: [dynamic]string, err: Compile_Error, ok: bool) {
    if len(named_args) == 0 || len(named_args)%2 != 0 {
        return arg_texts, Compile_Error{message = "named arguments use alternating :name value pairs", span = span}, false
    }

    seen: [dynamic]string
    for i := 0; i < len(named_args); i += 2 {
        if i+1 >= len(named_args) {
            return arg_texts, Compile_Error{message = "missing named argument value", span = span}, false
        }

        key := named_args[i]
        value := named_args[i+1]
        field_name, ok_key := brace_key_name(key)
        if !ok_key {
            return arg_texts, Compile_Error{message = "named arguments use alternating keyword/value pairs such as :name value", span = key.span}, false
        }
        for existing in seen {
            if existing == field_name {
                return arg_texts, Compile_Error{message = fmt.tprintf("duplicate named argument %s", key.text), span = key.span}, false
            }
        }
        append(&seen, field_name)

        value_text, err_value, ok_value := emit_expr(e, value)
        if !ok_value {
            return arg_texts, err_value, false
        }
        append(&arg_texts, fmt.tprintf("%s = %s", field_name, value_text))
    }

    return arg_texts, Compile_Error{}, true
}

find_proc_param :: proc(proc_decl: ^Proc_Decl, name: string) -> (^Param, bool) {
    for idx in 0..<len(proc_decl.params) {
        if proc_decl.params[idx].name == name {
            return &proc_decl.params[idx], true
        }
    }
    return nil, false
}

import_decl_alias_matches :: proc(decl: IR_Decl, alias: string) -> bool {
    if decl.kind != .Import {
        return false
    }
    if decl.import_decl.has_alias {
        return decl.import_decl.alias == alias
    }
    raw := decl.import_decl.path
    if len(raw) >= 2 && raw[0] == '"' && raw[len(raw)-1] == '"' {
        raw = unquote_string(raw)
    }
    return import_default_alias(raw) == alias
}

imported_call_parts :: proc(head_name: string) -> (alias, member: string, ok: bool) {
    dot := strings.index(head_name, ".")
    if dot <= 0 || dot+1 >= len(head_name) {
        return "", "", false
    }
    return head_name[:dot], head_name[dot+1:], true
}

head_is_imported_odin_call :: proc(e: ^Emitter, head_name: string) -> bool {
    if e == nil {
        return false
    }
    alias, _, ok_parts := imported_call_parts(head_name)
    if !ok_parts {
        return false
    }
    for decl in e.decls {
        if import_decl_alias_matches(decl, alias) && !decl_is_kvist_import(decl) {
            return true
        }
    }
    return false
}

imported_interop_call_parts :: proc(head_name: string) -> (alias, member: string, ok: bool) {
    dot := strings.index(head_name, ".")
    if dot > 0 && dot+1 < len(head_name) {
        return head_name[:dot], head_name[dot+1:], true
    }
    slash := strings.index(head_name, "/")
    if slash > 0 && slash+1 < len(head_name) {
        return head_name[:slash], head_name[slash+1:], true
    }
    return "", "", false
}

import_decl_path_matches :: proc(decl: IR_Decl, path: string) -> bool {
    if decl.kind != .Import {
        return false
    }
    raw := decl.import_decl.path
    if len(raw) >= 2 && raw[0] == '"' && raw[len(raw)-1] == '"' {
        raw = unquote_string(raw)
    }
    return raw == path
}

imported_interop_call_matches :: proc(e: ^Emitter, head_name, path, member: string) -> bool {
    if e == nil {
        return false
    }
    alias, call_member, ok_parts := imported_interop_call_parts(head_name)
    if !ok_parts || call_member != member {
        return false
    }
    for decl in e.decls {
        if import_decl_alias_matches(decl, alias) && import_decl_path_matches(decl, path) {
            return true
        }
    }
    return false
}

qualify_imported_odin_type :: proc(alias, type_text: string) -> string {
    text := strings.trim_space(type_text)
    if text == "" {
        return ""
    }
    if strings.has_prefix(text, "^") {
        inner := qualify_imported_odin_type(alias, text[1:])
        defer delete(inner)
        return fmt.tprintf("^%s", inner)
    }
    if strings.contains_any(text, ".[](), ") || strings.has_prefix(text, "#") {
        return strings.clone(text)
    }
    return fmt.tprintf("%s.%s", alias, text)
}

imported_odin_type_parts :: proc(type_text: string) -> (alias, member: string, ok: bool) {
    text := strings.trim_space(type_text)
    if strings.has_prefix(text, "^") {
        text = strings.trim_space(text[1:])
    }
    dot := strings.index(text, ".")
    if dot <= 0 || dot+1 >= len(text) {
        return "", "", false
    }
    return text[:dot], text[dot+1:], true
}

type_text_is_builtin_odin_scalar :: proc(text: string) -> bool {
    switch strings.trim_space(text) {
    case "bool", "int", "i8", "i16", "i32", "i64", "i128",
         "uint", "u8", "u16", "u32", "u64", "u128",
         "uintptr", "rune", "byte",
         "f16", "f32", "f64", "complex32", "complex64", "complex128",
         "string", "cstring", "rawptr", "any", "keyword":
        return true
    }
    return false
}

type_text_uses_keyword :: proc(text: string) -> bool {
    trimmed := strings.trim_space(text)
    if trimmed == "" {
        return false
    }
    needle := "keyword"
    limit := len(trimmed) - len(needle)
    for i := 0; i <= limit; i += 1 {
        if trimmed[i:i+len(needle)] != needle {
            continue
        }
        before_ok := i == 0
        if !before_ok {
            ch := trimmed[i-1]
            before_ok = !((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_')
        }
        after_ok := i+len(needle) == len(trimmed)
        if !after_ok {
            ch := trimmed[i+len(needle)]
            after_ok = !((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_')
        }
        if before_ok && after_ok {
            return true
        }
    }
    return false
}

mark_keyword_type :: proc(e: ^Emitter) {
    e.features.keyword_type = true
}

mark_keyword_type_for_text :: proc(e: ^Emitter, text: string) {
    if type_text_uses_keyword(text) {
        mark_keyword_type(e)
    }
}

mark_keyword_type_for_return_spec :: proc(e: ^Emitter, returns: Return_Spec) {
    #partial switch returns.kind {
    case .Single:
        mark_keyword_type_for_text(e, returns.single_ty)
    case .Named:
        for field in returns.named {
            mark_keyword_type_for_text(e, field.ty)
        }
    }
}

mark_decl_keyword_usage :: proc(e: ^Emitter, decl: IR_Decl) {
    #partial switch decl.kind {
    case .Const:
        if decl.const_decl.is_type_alias {
            mark_keyword_type_for_text(e, decl.const_decl.type_alias)
        }
        if decl.const_decl.has_ty {
            mark_keyword_type_for_text(e, decl.const_decl.ty)
        }
    case .Var:
        if decl.var_decl.has_ty {
            mark_keyword_type_for_text(e, decl.var_decl.ty)
        }
    case .Struct:
        for field in decl.struct_decl.fields {
            mark_keyword_type_for_text(e, field.ty)
        }
    case .Union:
        for variant in decl.union_decl.variants {
            mark_keyword_type_for_text(e, variant.ty)
        }
    case .Proc:
        for param in decl.proc_decl.params {
            mark_keyword_type_for_text(e, param.ty)
        }
        mark_keyword_type_for_return_spec(e, decl.proc_decl.returns)
    case .Source:
        for param in decl.source_decl.params {
            mark_keyword_type_for_text(e, param.ty)
        }
        mark_keyword_type_for_text(e, decl.source_decl.state_ty)
        mark_keyword_type_for_text(e, decl.source_decl.item_ty)
    }
}

keyword_literal_text :: proc(e: ^Emitter, text: string) -> string {
    mark_keyword_type(e)
    return emit_type_conversion_text("keyword", fmt.tprintf("%q", text))
}

mark_data_type :: proc(e: ^Emitter) {
    e.features.data_type = true
    e.features.core_strings = true
    e.features.core_fmt = true
    // Contextual Data's generic lift overload includes the distinct keyword
    // scalar even if this source has no native keyword expression.
    mark_keyword_type(e)
}

emit_data_items_literal :: proc(e: ^Emitter, items: []CST_Form) -> (string, Compile_Error, bool) {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "[]Data{")
    for item, idx in items {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        value, err_value, ok_value := emit_data_value_literal(e, item)
        if !ok_value {
            return "", err_value, false
        }
        strings.write_string(&builder, value)
    }
    strings.write_byte(&builder, '}')
    return strings.clone(strings.to_string(builder)), Compile_Error{}, true
}

emit_data_map_literal :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items)%2 != 0 {
        return "", Compile_Error{message = "quoted map expects key/value pairs", span = form.span}, false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "Data{kind = .Map, payload = {entries = []Data_Entry{")
    i := 0
    for i < len(form.items) {
        if i > 0 {
            strings.write_string(&builder, ", ")
        }
        key, err_key, ok_key := emit_data_value_literal(e, form.items[i])
        if !ok_key {
            return "", err_key, false
        }
        value, err_value, ok_value := emit_data_value_literal(e, form.items[i+1])
        if !ok_value {
            return "", err_value, false
        }
        fmt.sbprintf(&builder, "{{key = %s, value = %s}}", key, value)
        i += 2
    }
    strings.write_string(&builder, "}}}")
    return strings.clone(strings.to_string(builder)), Compile_Error{}, true
}

emit_data_value_literal :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    mark_data_type(e)
    #partial switch form.kind {
    case .Nil:
        return "Data{}", Compile_Error{}, true
    case .Bool:
        return fmt.tprintf("Data{{kind = .Bool, payload = {{bool_value = %s}}}}", form.text), Compile_Error{}, true
    case .Number:
        if number_literal_type(form.text) == "f64" {
            return fmt.tprintf("Data{{kind = .Float, payload = {{float_value = f64(%s)}}}}", form.text), Compile_Error{}, true
        }
        return fmt.tprintf("Data{{kind = .Int, payload = {{int_value = i64(%s)}}}}", form.text), Compile_Error{}, true
    case .String:
        text := unquote_string(form.text)
        defer delete(text)
        return fmt.tprintf("Data{{kind = .String, payload = {{text = %q}}}}", text), Compile_Error{}, true
    case .Regex:
        return "", Compile_Error{message = "regex literals are not Data values", span = form.span}, false
    case .Symbol:
        return fmt.tprintf("Data{{kind = .Symbol, payload = {{text = %q}}}}", form.text), Compile_Error{}, true
    case .Keyword:
        return fmt.tprintf("Data{{kind = .Keyword, payload = {{text = %q}}}}", form.text), Compile_Error{}, true
    case .List, .Vector, .Set:
        items, err_items, ok_items := emit_data_items_literal(e, form.items[:])
        if !ok_items {
            return "", err_items, false
        }
        kind := "List"
        if form.kind == .Vector {
            kind = "Vector"
        } else if form.kind == .Set {
            kind = "Set"
        }
        return fmt.tprintf("Data{{kind = .%s, payload = {{items = %s}}}}", kind, items), Compile_Error{}, true
    case .Brace:
        return emit_data_map_literal(e, form)
    }
    return "", Compile_Error{message = "unsupported quoted Data value", span = form.span}, false
}

emit_quoted_data_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 2 {
        return "", Compile_Error{message = "quote expects one form", span = form.span}, false
    }
    value, err_value, ok_value := emit_data_value_literal(e, form.items[1])
    if !ok_value {
        return "", err_value, false
    }
    name := ""
    for {
        e.temp_counter += 1
        if e.data_literal_prefix == "" {
            name = fmt.tprintf("kvist_data_literal_%d", e.temp_counter)
        } else {
            name = fmt.tprintf(
                "kvist_data_literal_%s_%d",
                e.data_literal_prefix,
                e.temp_counter,
            )
        }
        available := true
        for literal in e.features.data_literals {
            if literal.name == name {
                available = false
                break
            }
        }
        if available {
            break
        }
        delete(name)
    }
    append(&e.features.data_literals, Data_Literal{name = name, value = value})
    return name, Compile_Error{}, true
}

form_contains_runtime_unquote :: proc(form: CST_Form, depth: int = 0) -> bool {
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if (form.items[0].text == "unquote" || form.items[0].text == "splice") && depth == 0 {
            return true
        }
        next_depth := depth
        if form.items[0].text == "quasiquote" {
            next_depth += 1
        }
        for item in form.items[1:] {
            if form_contains_runtime_unquote(item, next_depth) {
                return true
            }
        }
        return false
    }
    for item in form.items {
        if form_contains_runtime_unquote(item, depth) {
            return true
        }
    }
    return false
}

contextual_data_source_type :: proc(e: ^Emitter, form: CST_Form) -> (string, bool) {
    if ty, ok_ty := obvious_form_type(e, form); ok_ty {
        return ty, true
    }
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return "", false
    }
    switch form.items[0].text {
    case "+", "-", "*", "/", "%", "%%", "min", "max":
        if len(form.items) < 2 {
            return "", false
        }
        selected := ""
        selected_from_literal := false
        for operand in form.items[1:] {
            operand_ty, ok_operand_ty := contextual_data_source_type(e, operand)
            if !ok_operand_ty {
                continue
            }
            if operand_ty == "f64" {
                return operand_ty, true
            }
            if operand_ty == "f32" {
                selected = operand_ty
                selected_from_literal = false
                continue
            }
            if selected == "" || (selected_from_literal && operand.kind != .Number) {
                selected = operand_ty
                selected_from_literal = operand.kind == .Number
            }
        }
        if selected != "" {
            return selected, true
        }
    case "==", "=", "!=", "<", "<=", ">", ">=", "not", "!":
        return "bool", true
    case:
    }
    return "", false
}

runtime_data_unquote_expr :: proc(e: ^Emitter, form: CST_Form) -> (text: string, owned: bool, err: Compile_Error, ok: bool) {
    value, err_value, ok_value := emit_expr(e, form)
    if !ok_value {
        return "", false, err_value, false
    }
    ty, ok_ty := contextual_data_source_type(e, form)
    if !ok_ty {
        expression := form.text
        if expression == "" && len(form.items) > 0 {
            expression = form.items[0].text
        }
        message := "runtime Data unquote needs an obvious Data or native scalar type"
        if expression != "" {
            message = fmt.tprintf("runtime Data unquote `%s` needs an obvious Data or native scalar type", expression)
        }
        return "", false, Compile_Error{message = message, span = form.span}, false
    }
    mark_data_type(e)
    if type_text_is_managed_value(e, ty) {
        return value, form_produces_owned_managed_value(e, form), {}, true
    }
    switch ty {
    case "bool":
        return emit_call_text("kvist_data_make_bool", []string{value}), true, {}, true
    case "int", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64":
        return emit_call_text("kvist_data_make_int", []string{fmt.tprintf("i64(%s)", value)}), true, {}, true
    case "f32", "f64":
        return emit_call_text("kvist_data_make_float", []string{fmt.tprintf("f64(%s)", value)}), true, {}, true
    case "string":
        return emit_call_text("kvist_data_make_text", []string{"Data_Kind.String", value}), true, {}, true
    case "keyword":
        return emit_call_text("kvist_data_make_text", []string{"Data_Kind.Keyword", fmt.tprintf("string(%s)", value)}), true, {}, true
    }
    return "", false, Compile_Error{message = fmt.tprintf("runtime Data unquote does not support native type %s", ty), span = form.span}, false
}

emit_runtime_data_quasiquote_value :: proc(e: ^Emitter, form: CST_Form, root: bool = false) -> (text: string, owned: bool, err: Compile_Error, ok: bool) {
    if form.kind == .List && len(form.items) > 0 && is_symbol(form.items[0], "unquote") {
        if len(form.items) != 2 {
            return "", false, Compile_Error{message = "runtime Data unquote expects one expression", span = form.span}, false
        }
        value, value_owned, err_value, ok_value := runtime_data_unquote_expr(e, form.items[1])
        if !ok_value {
            return "", false, err_value, false
        }
        if root && !value_owned {
            return emit_call_text("kvist_data_retain", []string{value}), true, {}, true
        }
        return value, value_owned, {}, true
    }
    if form.kind == .List && len(form.items) > 0 && is_symbol(form.items[0], "splice") {
        return "", false, Compile_Error{message = "runtime Data splice is valid only as an item in a quasiquoted list, vector, or set", span = form.span}, false
    }
    if !form_contains_runtime_unquote(form) {
        value, err_value, ok_value := emit_data_value_literal(e, form)
        return value, false, err_value, ok_value
    }
    if form.kind != .List && form.kind != .Vector && form.kind != .Brace && form.kind != .Set {
        return "", false, Compile_Error{message = "runtime Data unquote must appear inside a list, vector, map, or set", span = form.span}, false
    }

    values: [dynamic]string
    splice_flags: [dynamic]bool
    defer delete(values)
    defer delete(splice_flags)
    has_splice := false
    for item in form.items {
        splice := item.kind == .List && len(item.items) > 0 && is_symbol(item.items[0], "splice")
        if splice && form.kind == .Brace {
            return "", false, Compile_Error{message = "runtime Data map splice is not implemented; use data.merge", span = item.span}, false
        }
        value := ""
        value_owned := false
        err_value: Compile_Error
        ok_value := false
        if splice {
            if len(item.items) != 2 {
                return "", false, Compile_Error{message = "runtime Data splice expects one expression", span = item.span}, false
            }
            value, value_owned, err_value, ok_value = runtime_data_unquote_expr(e, item.items[1])
            if ok_value {
                ty, ok_ty := obvious_form_type(e, item.items[1])
                if !ok_ty || !type_text_is_managed_value(e, ty) {
                    return "", false, Compile_Error{message = "runtime Data splice expects Data", span = item.items[1].span}, false
                }
            }
            has_splice = true
        } else {
            value, value_owned, err_value, ok_value = emit_runtime_data_quasiquote_value(e, item)
        }
        if !ok_value {
            return "", false, err_value, false
        }
        if value_owned {
            temp := thread_temp_name(e)
            emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), value, item.span)
            emit_line(e, fmt.tprintf("defer kvist_data_release(%s)", temp))
            value = temp
        }
        append(&values, value)
        append(&splice_flags, splice)
    }
    if form.kind == .Brace {
        if len(form.items)%2 != 0 {
            return "", false, Compile_Error{message = "runtime quasiquoted map expects key/value pairs", span = form.span}, false
        }
        literal := fmt.tprintf("[]Data{{%s}}", strings.join(values[:], ", ", context.temp_allocator))
        return emit_call_text("kvist_data_make_map", []string{literal}), true, {}, true
    }
    kind := "Data_Kind.List"
    if form.kind == .Vector {
        kind = "Data_Kind.Vector"
    } else if form.kind == .Set {
        kind = "Data_Kind.Set"
    }
    if has_splice {
        pieces: [dynamic]string
        defer delete(pieces)
        for value, idx in values {
            splice_text := "false"
            if splice_flags[idx] {
                splice_text = "true"
            }
            append(&pieces, fmt.tprintf("Data_Piece{{value = %s, splice = %s}}", value, splice_text))
        }
        literal := fmt.tprintf("[]Data_Piece{{%s}}", strings.join(pieces[:], ", ", context.temp_allocator))
        return emit_call_text("kvist_data_make_items_spliced", []string{kind, literal}), true, {}, true
    }
    literal := fmt.tprintf("[]Data{{%s}}", strings.join(values[:], ", ", context.temp_allocator))
    return emit_call_text("kvist_data_make_items", []string{kind, literal}), true, {}, true
}

emit_runtime_data_quasiquote_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 2 {
        return "", Compile_Error{message = "quasiquote expects one form", span = form.span}, false
    }
    value, _, err_value, ok_value := emit_runtime_data_quasiquote_value(e, form.items[1], true)
    return value, err_value, ok_value
}

emit_contextual_data_value :: proc(e: ^Emitter, form: CST_Form) -> (text: string, owned: bool, err: Compile_Error, ok: bool) {
    mark_data_type(e)
    if form.kind != .Vector && form.kind != .Brace && form.kind != .Set {
        #partial switch form.kind {
        case .Nil, .Bool, .Number, .String, .Keyword:
            value, err_value, ok_value := emit_data_value_literal(e, form)
            return value, false, err_value, ok_value
        }
        if form.kind == .List &&
           ((len(form.items) > 0 && is_symbol(form.items[0], "if")) ||
            form_head_is_as_thread(form) ||
            (len(form.items) > 0 && is_symbol(form.items[0], "let")) ||
            form_head_is_do(form) ||
            form_head_is_allocator_scope(form) ||
            form_head_is_case(form) ||
            form_head_is_match(form)) {
            value, err_value, ok_value := emit_expr_for_expected_type(e, form, "Data")
            return value, true, err_value, ok_value
        }
        if form.kind == .List && len(form.items) > 0 && is_symbol(form.items[0], "odin-call") {
            // `odin-call` is an explicitly typed escape hatch. In a Data
            // context its result is already Data; wrapping it in the generic
            // scalar lift would alter its ownership contract.
            value, err_value, ok_value := emit_expr(e, form)
            return value, false, err_value, ok_value
        }
        if _, ok_ty := contextual_data_source_type(e, form); !ok_ty {
            value, err_value, ok_value := emit_expr(e, form)
            if !ok_value {
                return "", false, err_value, false
            }
            if form.kind == .Symbol {
                // Lowering a contextual call argument can revisit a
                // compiler-generated Data temporary as a symbol. Declared
                // scalar symbols have already been handled by inference.
                return value, false, {}, true
            }
            if form_produces_owned_value(form, e) {
                temp := thread_temp_name(e)
                emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), value, form.span)
                emit_line_mapped(e, fmt.tprintf("defer delete(%s)", temp), form.span)
                value = temp
            }
            // Imported Odin procedures do not carry signatures in Kvist's
            // IR. Let Odin's overload resolution select the scalar/Data lift
            // instead of emitting an untyped native value into []Data.
            return emit_call_text("kvist_data_lift", []string{value}), true, {}, true
        }
        value, value_owned, err_value, ok_value := runtime_data_unquote_expr(e, form)
        return value, value_owned, err_value, ok_value
    }

    if form.kind == .Brace && len(form.items)%2 != 0 {
        return "", false, Compile_Error{message = "contextual Data map expects key/value pairs", span = form.span}, false
    }

    values: [dynamic]string
    defer delete(values)
    for item in form.items {
        value, value_owned, err_value, ok_value := emit_contextual_data_value(e, item)
        if !ok_value {
            return "", false, err_value, false
        }
        if value_owned {
            temp := thread_temp_name(e)
            emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), value, item.span)
            emit_line(e, fmt.tprintf("defer kvist_data_release(%s)", temp))
            value = temp
        }
        append(&values, value)
    }

    literal := fmt.tprintf("[]Data{{%s}}", strings.join(values[:], ", ", context.temp_allocator))
    if form.kind == .Brace {
        return emit_call_text("kvist_data_make_map", []string{literal}), true, {}, true
    }
    kind := "Data_Kind.Vector"
    if form.kind == .Set {
        kind = "Data_Kind.Set"
    }
    return emit_call_text("kvist_data_make_items", []string{kind, literal}), true, {}, true
}

emit_data_lookup_key :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if form.kind != .Symbol {
        return emit_data_value_literal(e, form)
    }
    raw, err_raw, ok_raw := emit_expr(e, form)
    if !ok_raw {
        return "", err_raw, false
    }
    if ty, ok_ty := obvious_form_type(e, form); ok_ty {
        if ty == "Data" {
            return raw, Compile_Error{}, true
        }
        if ty == "int" || ty == "i64" || ty == "u64" {
            return fmt.tprintf("Data{{kind = .Int, payload = {{int_value = i64(%s)}}}}", raw), Compile_Error{}, true
        }
    }
    return raw, Compile_Error{}, true
}
