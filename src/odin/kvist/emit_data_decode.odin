// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

decode_field_parts :: proc(ty, value_name: string) -> (expected_kind, decoded_text: string, managed: bool, ok: bool) {
    switch ty {
    case "Data":
        return "", value_name, true, true
    case "bool":
        return "Bool", fmt.tprintf("%s.payload.bool_value", value_name), false, true
    case "int", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64":
        return "Int", fmt.tprintf("%s(%s.payload.int_value)", ty, value_name), false, true
    case "f32", "f64":
        return "Float", fmt.tprintf("%s(%s.payload.float_value)", ty, value_name), false, true
    }
    return "", "", false, false
}

enum_variant_keyword :: proc(source_name: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_byte(&builder, ':')
    for ch in source_name {
        lowered := ch
        if ch >= 'A' && ch <= 'Z' {
            lowered = ch + ('a' - 'A')
        }
        strings.write_rune(&builder, lowered)
    }
    return strings.clone(strings.to_string(builder))
}

emit_decode_failure_return :: proc(
    builder: ^strings.Builder,
    path_keys: []string,
    expected_kind, actual_text: string,
    failure_id: int,
    body_depth: int = 2,
) {
    if len(path_keys) == 0 {
        fmt.sbprintf(
            builder,
            " return {{}}, data__decode_error(kvist_path, .%s, %s), false ",
            expected_kind,
            actual_text,
        )
        return
    }
    path_name := fmt.tprintf("kvist_error_path_%d", failure_id)
    strings.write_byte(builder, '\n')
    append_indent(builder, body_depth)
    fmt.sbprintf(builder, "%s := kvist_data_retain(kvist_path)\n", path_name)
    append_indent(builder, body_depth)
    fmt.sbprintf(builder, "defer kvist_data_release(%s)\n", path_name)
    for key_name in path_keys {
        append_indent(builder, body_depth)
        fmt.sbprintf(
            builder,
            "kvist_data_move_assign(&%s, kvist_data_append(%s, %s))\n",
            path_name,
            path_name,
            key_name,
        )
    }
    append_indent(builder, body_depth)
    fmt.sbprintf(
        builder,
        "return {{}}, data__decode_error(%s, .%s, %s), false\n",
        path_name,
        expected_kind,
        actual_text,
    )
    append_indent(builder, body_depth-1)
}

decode_guarded_condition :: proc(guard, condition: string) -> string {
    if guard == "" {
        return condition
    }
    return fmt.tprintf("%s && (%s)", guard, condition)
}

decode_combined_guard :: proc(parent, child: string) -> string {
    if parent == "" {
        return child
    }
    return fmt.tprintf("%s && %s", parent, child)
}

emit_struct_field_default :: proc(e: ^Emitter, field: Struct_Field) -> (string, Compile_Error, bool) {
    default_text, err_default, ok_default := emit_expr_for_expected_type(
        e,
        field.default_value,
        field.ty,
    )
    if !ok_default {
        return "", err_default, false
    }
    if field.owns_string {
        if !form_produces_owned_value(field.default_value, e) {
            mark_core_strings(e)
            default_text = emit_call_text("strings.clone", []string{default_text})
        }
    } else if field.owns_dynamic_array {
        if !form_produces_owned_value(field.default_value, e) {
            default_text = managed_clone_value_text(e, field.ty, default_text)
        }
    } else if type_text_has_managed_lifecycle(e, field.ty) &&
              !form_produces_owned_managed_type(e, field.default_value, field.ty) {
        default_text = managed_clone_value_text(e, field.ty, default_text)
    }
    return default_text, {}, true
}

decode_field_constructor_value :: proc(
    field: Struct_Field,
    decoded, present, default_value: string,
) -> string {
    value := decoded
    if field.has_default {
        value = fmt.tprintf("%s ? %s : %s", present, decoded, default_value)
    }
    return fmt.tprintf("%s = %s", field.name, value)
}

emit_decode_enum_failure_return :: proc(
    builder: ^strings.Builder,
    path_keys: []string,
    expected_type, actual_value: string,
    failure_id: int,
    body_depth: int = 2,
) {
    path_name := fmt.tprintf("kvist_enum_error_path_%d", failure_id)
    strings.write_byte(builder, '\n')
    append_indent(builder, body_depth)
    fmt.sbprintf(builder, "%s := kvist_data_retain(kvist_path)\n", path_name)
    append_indent(builder, body_depth)
    fmt.sbprintf(builder, "defer kvist_data_release(%s)\n", path_name)
    for key_name in path_keys {
        append_indent(builder, body_depth)
        fmt.sbprintf(
            builder,
            "kvist_data_move_assign(&%s, kvist_data_append(%s, %s))\n",
            path_name,
            path_name,
            key_name,
        )
    }
    append_indent(builder, body_depth)
    fmt.sbprintf(
        builder,
        "return {{}}, data__decode_enum_error(%s, %q, %s), false\n",
        path_name,
        expected_type,
        actual_value,
    )
    append_indent(builder, body_depth-1)
}

decode_enum_value_constructor_text :: proc(
    enum_decl: ^Enum_Decl,
    elem_ty, value_name: string,
) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    fmt.sbprintf(
        &builder,
        "(proc(kvist_item: Data) -> %s {{ kvist_value: %s; switch kvist_item.payload.text {{ ",
        elem_ty,
        elem_ty,
    )
    for variant in enum_decl.variants {
        keyword := enum_variant_keyword(variant.source_name)
        fmt.sbprintf(&builder, "case %q: kvist_value = .%s; ", keyword, variant.name)
        delete(keyword)
    }
    fmt.sbprintf(&builder, "case: }} return kvist_value }})(%s)", value_name)
    return strings.clone(strings.to_string(builder))
}

emit_decode_dynamic_array_unchecked_value :: proc(
    e: ^Emitter,
    field: Struct_Field,
    field_name: string,
    counter: ^int,
    root_span: Span,
    depth: int,
) -> (string, Compile_Error, bool) {
    elem_ty, ok_array := dynamic_array_element_type(field.ty)
    if !ok_array {
        return "", Compile_Error{
            message = fmt.tprintf(
                "data.decode field %s is marked as an owned dynamic array but has type %s",
                field.source_name,
                field.ty,
            ),
            span = root_span,
        }, false
    }
    _, constructed_item, managed, supported := decode_field_parts(elem_ty, "kvist_item")
    if enum_decl, enum_supported := find_enum_decl(e, elem_ty); enum_supported {
        constructed_item = decode_enum_value_constructor_text(enum_decl, elem_ty, "kvist_item")
        managed = false
        supported = true
    } else if nested_decl, nested_supported := find_struct_decl(e, elem_ty); nested_supported {
        nested_builder := strings.builder_make()
        defer strings.builder_destroy(&nested_builder)
        fmt.sbprintf(
            &nested_builder,
            "(proc(kvist_value: Data) -> %s {{\n",
            elem_ty,
        )
        nested_value, err_nested, ok_nested := emit_decode_struct_unchecked_value(
            e,
            &nested_builder,
            nested_decl,
            "kvist_value",
            counter,
            root_span,
            depth+1,
        )
        if !ok_nested {
            return "", err_nested, false
        }
        fmt.sbprintf(&nested_builder, "    return %s\n}})(kvist_item)", nested_value)
        constructed_item = strings.clone(strings.to_string(nested_builder))
        managed = false
        supported = true
    }
    if !supported {
        return "", Compile_Error{
            message = fmt.tprintf(
                "data.decode field %s has unsupported dynamic-array element type %s; supported elements are Data, bool, integer and floating-point scalars, Kvist enums, and Kvist structs",
                field.source_name,
                elem_ty,
            ),
            span = root_span,
        }, false
    }
    if managed {
        constructed_item = managed_clone_value_text(e, elem_ty, constructed_item)
    }
    return fmt.tprintf(
        "(proc(kvist_items: []Data) -> %s {{ kvist_out := make(%s, 0, len(kvist_items)); for kvist_item in kvist_items {{ append(&kvist_out, %s) }}; return kvist_out }})(%s.payload.items)",
        field.ty,
        field.ty,
        constructed_item,
        field_name,
    ), {}, true
}

emit_decode_struct_unchecked_value :: proc(
    e: ^Emitter,
    builder: ^strings.Builder,
    struct_decl: ^Struct_Decl,
    value_name: string,
    counter: ^int,
    root_span: Span,
    depth: int = 0,
) -> (string, Compile_Error, bool) {
    if depth > 16 {
        return "", Compile_Error{
            message = fmt.tprintf("data.decode nested struct depth exceeded at %s", struct_decl.name),
            span = root_span,
        }, false
    }
    field_values: [dynamic]string
    defer delete(field_values)
    for field in struct_decl.fields {
        field_id := counter^
        counter^ += 1
        key_name := fmt.tprintf("kvist_key_%d", field_id)
        field_name := fmt.tprintf("kvist_field_%d", field_id)
        key := fmt.tprintf(":%s", field.source_name)
        fmt.sbprintf(
            builder,
            "    %s := Data{{kind = .Keyword, payload = {{text = %q}}}}\n",
            key_name,
            key,
        )
        fmt.sbprintf(
            builder,
            "    %s := kvist_data_get(%s, %s)\n",
            field_name,
            value_name,
            key_name,
        )
        present_name := ""
        default_text := ""
        if field.has_default {
            present_name = fmt.tprintf("kvist_present_%d", field_id)
            fmt.sbprintf(
                builder,
                "    %s := kvist_data_contains(%s, %s)\n",
                present_name,
                value_name,
                key_name,
            )
            emitted_default, err_default, ok_default := emit_struct_field_default(e, field)
            if !ok_default {
                return "", err_default, false
            }
            default_text = emitted_default
        }

        decoded := ""
        if field.owns_dynamic_array {
            array_value, err_array, ok_array := emit_decode_dynamic_array_unchecked_value(
                e,
                field,
                field_name,
                counter,
                root_span,
                depth,
            )
            if !ok_array {
                return "", err_array, false
            }
            decoded = array_value
        } else if field.owns_string {
            mark_core_strings(e)
            decoded = fmt.tprintf("strings.clone(%s.payload.text)", field_name)
        } else if _, scalar_value, managed, supported := decode_field_parts(field.ty, field_name); supported {
            decoded = scalar_value
            if managed {
                decoded = managed_clone_value_text(e, field.ty, decoded)
            }
        } else if nested_decl, nested := find_struct_decl(e, field.ty); nested {
            nested_value, err_nested, ok_nested := emit_decode_struct_unchecked_value(
                e,
                builder,
                nested_decl,
                field_name,
                counter,
                root_span,
                depth+1,
            )
            if !ok_nested {
                return "", err_nested, false
            }
            decoded = nested_value
        } else if enum_decl, enum_found := find_enum_decl(e, field.ty); enum_found {
            decoded = decode_enum_value_constructor_text(enum_decl, field.ty, field_name)
        } else {
            return "", Compile_Error{
                message = fmt.tprintf(
                    "data.decode field %s.%s has unsupported type %s",
                    struct_decl.name,
                    field.source_name,
                    field.ty,
                ),
                span = root_span,
            }, false
        }
        append(&field_values, decode_field_constructor_value(
            field,
            decoded,
            present_name,
            default_text,
        ))
    }
    return fmt.tprintf(
        "%s{{%s}}",
        struct_decl.name,
        strings.join(field_values[:], ", ", context.temp_allocator),
    ), {}, true
}

emit_decode_dynamic_array_field :: proc(
    e: ^Emitter,
    builder: ^strings.Builder,
    field: Struct_Field,
    field_name, field_guard: string,
    field_path: []string,
    field_id: int,
    counter: ^int,
    root_span: Span,
) -> (string, Compile_Error, bool) {
    elem_ty, ok_array := dynamic_array_element_type(field.ty)
    if !ok_array {
        return "", Compile_Error{
            message = fmt.tprintf(
                "data.decode field %s is marked as an owned dynamic array but has type %s",
                field.source_name,
                field.ty,
            ),
            span = root_span,
        }, false
    }
    item_name := fmt.tprintf("kvist_item_%d", field_id)
    index_name := fmt.tprintf("kvist_index_%d", field_id)
    enum_decl, enum_supported := find_enum_decl(e, elem_ty)
    nested_decl, nested_supported := find_struct_decl(e, elem_ty)
    expected_kind, _, managed, supported := decode_field_parts(elem_ty, item_name)
    if enum_supported {
        expected_kind = "Keyword"
        managed = false
        supported = true
    } else if nested_supported {
        expected_kind = "Map"
        managed = false
        supported = true
    }
    if !supported {
        return "", Compile_Error{
            message = fmt.tprintf(
                "data.decode field %s has unsupported dynamic-array element type %s; supported elements are Data, bool, integer and floating-point scalars, Kvist enums, and Kvist structs",
                field.source_name,
                elem_ty,
            ),
            span = root_span,
        }, false
    }

    condition := decode_guarded_condition(
        field_guard,
        fmt.tprintf("%s.kind != .Vector", field_name),
    )
    fmt.sbprintf(builder, "    if %s {{", condition)
    emit_decode_failure_return(
        builder,
        field_path,
        "Vector",
        fmt.tprintf("%s.kind", field_name),
        field_id,
    )
    strings.write_string(builder, "}\n")

    if expected_kind != "" {
        loop_depth := 1
        if field_guard != "" {
            fmt.sbprintf(builder, "    if %s {{\n", field_guard)
            loop_depth = 2
        }
        append_indent(builder, loop_depth)
        fmt.sbprintf(
            builder,
            "for %s, %s in %s.payload.items {{\n",
            item_name,
            index_name,
            field_name,
        )
        index_key := fmt.tprintf("kvist_index_key_%d", field_id)
        append_indent(builder, loop_depth+1)
        fmt.sbprintf(
            builder,
            "%s := Data{{kind = .Int, payload = {{int_value = i64(%s)}}}}\n",
            index_key,
            index_name,
        )
        item_path: [dynamic]string
        defer delete(item_path)
        append(&item_path, ..field_path)
        append(&item_path, index_key)
        append_indent(builder, loop_depth+1)
        fmt.sbprintf(builder, "if %s.kind != .%s {{", item_name, expected_kind)
        emit_decode_failure_return(
            builder,
            item_path[:],
            expected_kind,
            fmt.tprintf("%s.kind", item_name),
            field_id,
            loop_depth+2,
        )
        strings.write_string(builder, "}\n")
        if enum_supported {
            invalid := strings.builder_make()
            defer strings.builder_destroy(&invalid)
            for variant, idx in enum_decl.variants {
                if idx > 0 {
                    strings.write_string(&invalid, " && ")
                }
                keyword := enum_variant_keyword(variant.source_name)
                fmt.sbprintf(&invalid, "%s.payload.text != %q", item_name, keyword)
                delete(keyword)
            }
            append_indent(builder, loop_depth+1)
            fmt.sbprintf(builder, "if %s {{", strings.to_string(invalid))
            emit_decode_enum_failure_return(
                builder,
                item_path[:],
                elem_ty,
                item_name,
                field_id,
                loop_depth+2,
            )
            strings.write_string(builder, "}\n")
        }
        if nested_supported {
            nested_validation := strings.builder_make()
            defer strings.builder_destroy(&nested_validation)
            _, err_nested, ok_nested := emit_decode_struct_value(
                e,
                &nested_validation,
                nested_decl,
                item_name,
                item_path[:],
                counter,
                root_span,
            )
            if !ok_nested {
                return "", err_nested, false
            }
            indent := strings.builder_make()
            defer strings.builder_destroy(&indent)
            for _ in 0..<loop_depth {
                strings.write_string(&indent, "    ")
            }
            append_indented_multiline(
                builder,
                strings.to_string(nested_validation),
                strings.to_string(indent),
            )
        }
        append_indent(builder, loop_depth)
        strings.write_string(builder, "}\n")
        if field_guard != "" {
            strings.write_string(builder, "    }\n")
        }
    }

    _ = enum_decl
    _ = managed
    return emit_decode_dynamic_array_unchecked_value(
        e,
        field,
        field_name,
        counter,
        root_span,
        0,
    )
}

emit_decode_struct_value :: proc(
    e: ^Emitter,
    builder: ^strings.Builder,
    struct_decl: ^Struct_Decl,
    value_name: string,
    path_keys: []string,
    counter: ^int,
    root_span: Span,
    depth: int = 0,
    parent_guard: string = "",
) -> (string, Compile_Error, bool) {
    if depth > 16 {
        return "", Compile_Error{
            message = fmt.tprintf("data.decode nested struct depth exceeded at %s", struct_decl.name),
            span = root_span,
        }, false
    }
    field_values: [dynamic]string
    defer delete(field_values)
    for field in struct_decl.fields {
        field_id := counter^
        counter^ += 1
        key_name := fmt.tprintf("kvist_key_%d", field_id)
        field_name := fmt.tprintf("kvist_field_%d", field_id)
        key := fmt.tprintf(":%s", field.source_name)
        fmt.sbprintf(
            builder,
            "    %s := Data{{kind = .Keyword, payload = {{text = %q}}}}\n",
            key_name,
            key,
        )
        fmt.sbprintf(
            builder,
            "    %s := kvist_data_get(%s, %s)\n",
            field_name,
            value_name,
            key_name,
        )
        present_name := ""
        field_guard := parent_guard
        default_text := ""
        if field.has_default {
            present_name = fmt.tprintf("kvist_present_%d", field_id)
            fmt.sbprintf(
                builder,
                "    %s := kvist_data_contains(%s, %s)\n",
                present_name,
                value_name,
                key_name,
            )
            field_guard = decode_combined_guard(parent_guard, present_name)
            emitted_default, err_default, ok_default := emit_struct_field_default(e, field)
            if !ok_default {
                return "", err_default, false
            }
            default_text = emitted_default
        }

        field_path: [dynamic]string
        defer delete(field_path)
        append(&field_path, ..path_keys)
        append(&field_path, key_name)

        if field.owns_dynamic_array {
            decoded, err_array, ok_array := emit_decode_dynamic_array_field(
                e,
                builder,
                field,
                field_name,
                field_guard,
                field_path[:],
                field_id,
                counter,
                root_span,
            )
            if !ok_array {
                return "", err_array, false
            }
            append(&field_values, decode_field_constructor_value(
                field,
                decoded,
                present_name,
                default_text,
            ))
            continue
        }

        if field.owns_string {
            condition := decode_guarded_condition(field_guard, fmt.tprintf("%s.kind != .String", field_name))
            fmt.sbprintf(builder, "    if %s {{", condition)
            emit_decode_failure_return(
                builder,
                field_path[:],
                "String",
                fmt.tprintf("%s.kind", field_name),
                field_id,
            )
            strings.write_string(builder, "}\n")
            mark_core_strings(e)
            decoded := fmt.tprintf("strings.clone(%s.payload.text)", field_name)
            append(&field_values, decode_field_constructor_value(
                field,
                decoded,
                present_name,
                default_text,
            ))
            continue
        }

        expected_kind, decoded_text, managed, supported := decode_field_parts(field.ty, field_name)
        if supported {
            if expected_kind != "" {
                condition := decode_guarded_condition(
                    field_guard,
                    fmt.tprintf("%s.kind != .%s", field_name, expected_kind),
                )
                fmt.sbprintf(builder, "    if %s {{", condition)
                emit_decode_failure_return(
                    builder,
                    field_path[:],
                    expected_kind,
                    fmt.tprintf("%s.kind", field_name),
                    field_id,
                )
                strings.write_string(builder, "}\n")
            }
            if managed {
                decoded_text = emit_call_text("kvist_data_retain", []string{decoded_text})
            }
            append(&field_values, decode_field_constructor_value(
                field,
                decoded_text,
                present_name,
                default_text,
            ))
            continue
        }

        nested_decl, nested := find_struct_decl(e, field.ty)
        if nested {
            condition := decode_guarded_condition(field_guard, fmt.tprintf("%s.kind != .Map", field_name))
            fmt.sbprintf(builder, "    if %s {{", condition)
            emit_decode_failure_return(
                builder,
                field_path[:],
                "Map",
                fmt.tprintf("%s.kind", field_name),
                field_id,
            )
            strings.write_string(builder, "}\n")
            nested_text, err_nested, ok_nested := emit_decode_struct_value(
                e,
                builder,
                nested_decl,
                field_name,
                field_path[:],
                counter,
                root_span,
                depth+1,
                field_guard,
            )
            if !ok_nested {
                return "", err_nested, false
            }
            append(&field_values, decode_field_constructor_value(
                field,
                nested_text,
                present_name,
                default_text,
            ))
            continue
        }

        enum_decl, enum_found := find_enum_decl(e, field.ty)
        if enum_found {
            condition := decode_guarded_condition(field_guard, fmt.tprintf("%s.kind != .Keyword", field_name))
            fmt.sbprintf(builder, "    if %s {{", condition)
            emit_decode_failure_return(
                builder,
                field_path[:],
                "Keyword",
                fmt.tprintf("%s.kind", field_name),
                field_id,
            )
            strings.write_string(builder, "}\n")
            enum_value_name := fmt.tprintf("kvist_enum_%d", field_id)
            fmt.sbprintf(builder, "    %s: %s\n", enum_value_name, field.ty)
            if field_guard != "" {
                fmt.sbprintf(builder, "    if %s {{\n", field_guard)
            }
            fmt.sbprintf(builder, "    switch %s.payload.text {{\n", field_name)
            for variant in enum_decl.variants {
                keyword := enum_variant_keyword(variant.source_name)
                fmt.sbprintf(
                    builder,
                    "    case %q: %s = .%s\n",
                    keyword,
                    enum_value_name,
                    variant.name,
                )
                delete(keyword)
            }
            strings.write_string(builder, "    case:\n")
            error_path_name := fmt.tprintf("kvist_enum_error_path_%d", field_id)
            fmt.sbprintf(builder, "        %s := kvist_data_retain(kvist_path)\n", error_path_name)
            fmt.sbprintf(builder, "        defer kvist_data_release(%s)\n", error_path_name)
            for key_path_name in field_path {
                fmt.sbprintf(
                    builder,
                    "        kvist_data_move_assign(&%s, kvist_data_append(%s, %s))\n",
                    error_path_name,
                    error_path_name,
                    key_path_name,
                )
            }
            fmt.sbprintf(
                builder,
                "        return {{}}, data__decode_enum_error(%s, %q, %s), false\n",
                error_path_name,
                field.ty,
                field_name,
            )
            strings.write_string(builder, "    }\n")
            if field_guard != "" {
                strings.write_string(builder, "    }\n")
            }
            append(&field_values, decode_field_constructor_value(
                field,
                enum_value_name,
                present_name,
                default_text,
            ))
            continue
        }

        return "", Compile_Error{
            message = fmt.tprintf(
                "data.decode field %s.%s has unsupported type %s; supported fields are string, Data, bool, integer and floating-point scalars, enums, nested Kvist structs, and dynamic arrays of supported non-string values",
                struct_decl.name,
                field.source_name,
                field.ty,
            ),
            span = root_span,
        }, false
    }
    return fmt.tprintf(
        "%s{{%s}}",
        struct_decl.name,
        strings.join(field_values[:], ", ", context.temp_allocator),
    ), {}, true
}

emit_data_decode_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 3 && len(form.items) != 4 {
        return "", Compile_Error{message = "data.decode expects type, value, and optional path", span = form.span}, false
    }
    target_ty, err_ty, ok_ty := parse_type_text(form.items[1])
    if !ok_ty {
        return "", err_ty, false
    }
    struct_decl, ok_struct := find_struct_decl(e, target_ty)
    _, ok_dynamic_array := dynamic_array_element_type(target_ty)
    if !ok_struct && !ok_dynamic_array {
        return "", Compile_Error{
            message = fmt.tprintf(
                "data.decode expects a Kvist struct or dynamic-array type, got %s",
                target_ty,
            ),
            span = form.items[1].span,
        }, false
    }
    value_text, err_value, ok_value := emit_expr_for_expected_type(
        e,
        form.items[2],
        "Data",
    )
    if !ok_value {
        return "", err_value, false
    }
    path_text := "Data{kind = .Vector}"
    if len(form.items) == 4 {
        err_path: Compile_Error
        ok_path: bool
        path_text, err_path, ok_path = emit_expr_for_expected_type(
            e,
            form.items[3],
            "Data",
        )
        if !ok_path {
            return "", err_path, false
        }
    }

    e.features.data_decode = true
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    fmt.sbprintf(
        &builder,
        "(proc(kvist_value, kvist_path: Data) -> (decoded: %s, err: data__Decode_Error, ok: bool) {{\n",
        target_ty,
    )
    counter := 0
    decoded_text: string
    err_decoded: Compile_Error
    ok_decoded: bool
    if ok_struct {
        strings.write_string(
            &builder,
            "    if kvist_value.kind != .Map { return {}, data__decode_error(kvist_path, .Map, kvist_value.kind), false }\n",
        )
        decoded_text, err_decoded, ok_decoded = emit_decode_struct_value(
            e,
            &builder,
            struct_decl,
            "kvist_value",
            nil,
            &counter,
            form.items[1].span,
        )
    } else {
        target_field := Struct_Field{
            name = "decoded",
            source_name = target_ty,
            ty = target_ty,
            owns_dynamic_array = true,
        }
        field_id := counter
        counter += 1
        decoded_text, err_decoded, ok_decoded = emit_decode_dynamic_array_field(
            e,
            &builder,
            target_field,
            "kvist_value",
            "",
            nil,
            field_id,
            &counter,
            form.items[1].span,
        )
    }
    if !ok_decoded {
        return "", err_decoded, false
    }
    fmt.sbprintf(
        &builder,
        "    return %s, {{}}, true\n",
        decoded_text,
    )
    fmt.sbprintf(&builder, "}})(%s, %s)", value_text, path_text)
    mark_data_type(e)
    return strings.clone(strings.to_string(builder)), {}, true
}

emit_data_validate_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 3 && len(form.items) != 4 {
        return "", Compile_Error{message = "data.validate expects type, value, and optional path", span = form.span}, false
    }
    target_ty, err_ty, ok_ty := parse_type_text(form.items[1])
    if !ok_ty {
        return "", err_ty, false
    }
    struct_decl, ok_struct := find_struct_decl(e, target_ty)
    _, ok_dynamic_array := dynamic_array_element_type(target_ty)
    if !ok_struct && !ok_dynamic_array {
        return "", Compile_Error{
            message = fmt.tprintf(
                "data.validate expects a Kvist struct or dynamic-array type, got %s",
                target_ty,
            ),
            span = form.items[1].span,
        }, false
    }
    value_text, err_value, ok_value := emit_expr_for_expected_type(
        e,
        form.items[2],
        "Data",
    )
    if !ok_value {
        return "", err_value, false
    }
    path_text := "Data{kind = .Vector}"
    if len(form.items) == 4 {
        err_path: Compile_Error
        ok_path: bool
        path_text, err_path, ok_path = emit_expr_for_expected_type(
            e,
            form.items[3],
            "Data",
        )
        if !ok_path {
            return "", err_path, false
        }
    }

    e.features.data_decode = true
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    fmt.sbprintf(
        &builder,
        "(proc(kvist_value, kvist_path: Data) -> (err: data__Decode_Error, ok: bool) {{\n    _, kvist_validation_err, kvist_validation_ok := (proc(kvist_value, kvist_path: Data) -> (decoded: %s, err: data__Decode_Error, ok: bool) {{\n",
        target_ty,
    )
    validation_builder := strings.builder_make()
    defer strings.builder_destroy(&validation_builder)
    counter := 0
    ignored_decoded: string
    err_validated: Compile_Error
    ok_validated: bool
    if ok_struct {
        strings.write_string(
            &builder,
            "        if kvist_value.kind != .Map { return {}, data__decode_error(kvist_path, .Map, kvist_value.kind), false }\n",
        )
        ignored_decoded, err_validated, ok_validated = emit_decode_struct_value(
            e,
            &validation_builder,
            struct_decl,
            "kvist_value",
            nil,
            &counter,
            form.items[1].span,
        )
    } else {
        target_field := Struct_Field{
            name = "validated",
            source_name = target_ty,
            ty = target_ty,
            owns_dynamic_array = true,
        }
        field_id := counter
        counter += 1
        ignored_decoded, err_validated, ok_validated = emit_decode_dynamic_array_field(
            e,
            &validation_builder,
            target_field,
            "kvist_value",
            "",
            nil,
            field_id,
            &counter,
            form.items[1].span,
        )
    }
    _ = ignored_decoded
    if !ok_validated {
        return "", err_validated, false
    }
    append_indented_multiline(
        &builder,
        strings.to_string(validation_builder),
        "    ",
    )
    strings.write_string(
        &builder,
        "        return {}, {}, true\n    })(kvist_value, kvist_path)\n    return kvist_validation_err, kvist_validation_ok\n",
    )
    fmt.sbprintf(&builder, "}})(%s, %s)", value_text, path_text)
    mark_data_type(e)
    return strings.clone(strings.to_string(builder)), {}, true
}

emit_shallow_update_copy_expr :: proc(e: ^Emitter, target_form: CST_Form, target_text, target_ty: string, fields: []string, field_span: Span, updater_form: CST_Form, rest_forms: []CST_Form) -> (string, Compile_Error, bool) {
    field_ty, err_field_ty, ok_field_ty := struct_field_type_for_update_path(e, target_ty, fields, "update", field_span)
    if !ok_field_ty {
        return "", err_field_ty, false
    }
    if type_text_has_managed_lifecycle(e, field_ty) {
        return "", Compile_Error{
            message = "update of a managed field is not yet supported; compute the new value first and use assoc",
            span = field_span,
        }, false
    }
    if struct_field_owns_string_for_update_path(e, target_ty, fields) {
        return "", Compile_Error{
            message = "update of an owned string field is not yet supported; compute the new value first and use assoc",
            span = field_span,
        }, false
    }
    if struct_field_owns_dynamic_array_for_update_path(e, target_ty, fields) {
        return "", Compile_Error{
            message = "update of an owned dynamic-array field is not yet supported; compute the new value first and use assoc",
            span = field_span,
        }, false
    }
    field_text := field_access_text("kvist_target", fields)
    arg_texts: [dynamic]string
    append(&arg_texts, field_text)
    rest_texts: [dynamic]string
    rest_names: [dynamic]string
    rest_types: [dynamic]string
    defer delete(rest_texts)
    defer delete(rest_names)
    defer delete(rest_types)
    for rest_form, idx in rest_forms {
        rest_ty, ok_rest_ty := obvious_form_type(e, rest_form)
        if !ok_rest_ty {
            return "", Compile_Error{message = "update expects extra updater arguments with obvious types; bind or annotate the value first", span = rest_form.span}, false
        }
        rest_text, err_rest, ok_rest := emit_expr(e, rest_form)
        if !ok_rest {
            return "", err_rest, false
        }
        rest_name := fmt.tprintf("kvist_arg_%d", idx)
        append(&rest_names, rest_name)
        append(&rest_types, rest_ty)
        append(&rest_texts, rest_text)
        append(&arg_texts, rest_name)
    }
    value_text, err_value, ok_value := emit_update_rhs(e, updater_form, arg_texts[:])
    if !ok_value {
        return "", err_value, false
    }
    temp := shallow_update_temp_name(e)
    target_field := field_access_text(temp, fields)
    params_builder := strings.builder_make()
    defer strings.builder_destroy(&params_builder)
    call_builder := strings.builder_make()
    defer strings.builder_destroy(&call_builder)
    for name, idx in rest_names {
        fmt.sbprintf(&params_builder, ", %s: %s", name, rest_types[idx])
        fmt.sbprintf(&call_builder, ", %s", rest_texts[idx])
    }
    target_init := "kvist_target"
    if type_text_has_managed_lifecycle(e, target_ty) &&
       !form_produces_owned_managed_type(e, target_form, target_ty) {
        target_init = managed_clone_value_text(e, target_ty, "kvist_target")
    }
    return fmt.tprintf("(proc(kvist_target: %s%s) -> %s %s\n    %s := %s\n    %s = %s\n    return %s\n})(%s%s)",
                       target_ty,
                       strings.to_string(params_builder),
                       target_ty,
                       "{",
                       temp,
                       target_init,
                       target_field,
                       value_text,
                       temp,
                       target_text,
                       strings.to_string(call_builder)), {}, true
}

emit_shallow_assoc_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) >= 2 {
        if target_ty, ok_target_ty := obvious_form_type(e, form.items[1]); ok_target_ty && target_ty == "Data" {
            target_text, err_target, ok_target := emit_expr(e, form.items[1])
            if !ok_target {
                return "", err_target, false
            }
            return emit_data_assoc_expr(e, form, target_text)
        }
    }
    target_form, fields, field_span, value_form, err_args, ok_args := shallow_assoc_args(form)
    if !ok_args {
        return "", err_args, false
    }
    target_ty, ok_ty := obvious_form_type(e, target_form)
    if !ok_ty {
        return "", Compile_Error{message = "assoc expects a target with an obvious struct type; bind or annotate the value first", span = target_form.span}, false
    }
    target_text, err_target, ok_target := emit_expr(e, target_form)
    if !ok_target {
        return "", err_target, false
    }
    return emit_shallow_assoc_copy_expr(e, target_form, target_text, target_ty, fields[:], field_span, value_form)
}

emit_shallow_update_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) >= 2 {
        if target_ty, ok_target_ty := obvious_form_type(e, form.items[1]); ok_target_ty && target_ty == "Data" {
            target_text, err_target, ok_target := emit_expr(e, form.items[1])
            if !ok_target {
                return "", err_target, false
            }
            return emit_data_update_expr(e, form, target_text)
        }
    }
    target_form, fields, field_span, updater_form, rest_forms, err_args, ok_args := shallow_update_args(form)
    if !ok_args {
        return "", err_args, false
    }
    target_ty, ok_ty := obvious_form_type(e, target_form)
    if !ok_ty {
        return "", Compile_Error{message = "update expects a target with an obvious struct type; bind or annotate the value first", span = target_form.span}, false
    }
    target_text, err_target, ok_target := emit_expr(e, target_form)
    if !ok_target {
        return "", err_target, false
    }
    return emit_shallow_update_copy_expr(e, target_form, target_text, target_ty, fields[:], field_span, updater_form, rest_forms)
}
