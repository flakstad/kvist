// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

emit_data_callable_lookup :: proc(
    e: ^Emitter,
    target_form, key_form: CST_Form,
    fallback_form: ^CST_Form,
    span: Span,
) -> (string, Compile_Error, bool) {
    target, err_target, ok_target := emit_expr(e, target_form)
    if !ok_target {
        return "", err_target, false
    }
    key, err_key, ok_key := emit_data_lookup_key(e, key_form)
    if !ok_key {
        return "", err_key, false
    }
    mark_data_type(e)
    if fallback_form == nil {
        return emit_call_text("kvist_data_map_call", []string{target, key}), {}, true
    }
    fallback, fallback_owned, err_fallback, ok_fallback := emit_contextual_data_value(e, fallback_form^)
    if !ok_fallback {
        err_fallback.span = span
        return "", err_fallback, false
    }
    if fallback_owned {
        temp := thread_temp_name(e)
        emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), fallback, fallback_form.span)
        emit_line_mapped(e, fmt.tprintf("defer kvist_data_release(%s)", temp), fallback_form.span)
        fallback = temp
    }
    return emit_call_text("kvist_data_map_call_or", []string{target, key, fallback}), {}, true
}

emit_call_like :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    head := form.items[0]
    if head.kind != .Symbol {
        return "", Compile_Error{message = "unsupported call head", span = head.span}, false
    }

    if head_ty, ok_head_ty := obvious_form_type(e, head);
       ok_head_ty && type_text_is_managed_value(e, head_ty) {
        if len(form.items) != 2 && len(form.items) != 3 {
            return "", Compile_Error{message = "Data map invocation expects key and optional fallback", span = form.span}, false
        }
        fallback: ^CST_Form
        if len(form.items) == 3 {
            fallback = &form.items[2]
        }
        return emit_data_callable_lookup(e, head, form.items[1], fallback, form.span)
    }

    if len(form.items) > 1 && is_call_directive_symbol(form.items[len(form.items)-1]) {
        directive := form.items[len(form.items)-1]
        stripped_items: [dynamic]CST_Form
        defer delete(stripped_items)
        for item in form.items[:len(form.items)-1] {
            append(&stripped_items, item)
        }
        stripped := form
        stripped.items = stripped_items
        target_text, err_target, ok_target := emit_call_like(e, stripped)
        if !ok_target {
            return "", err_target, false
        }
        return fmt.tprintf("%s %s", directive.text, target_text), {}, true
    }

    if head.text == "zero" {
        if len(form.items) < 2 {
            return "", Compile_Error{message = "zero expects a type", span = form.span}, false
        }
        type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], 1)
        if !ok_type {
            return "", err_type, false
        }
        if next_i != len(form.items) {
            return "", Compile_Error{message = "zero expects exactly one type", span = form.items[next_i].span}, false
        }
        return fmt.tprintf("%s{{}}", type_text), {}, true
    }

    if !kvist_package_imported(e, "data") &&
       (strings.has_prefix(head.text, "data.") ||
        strings.has_prefix(head.text, "data/")) {
        member := head.text[len("data."):]
        if strings.has_prefix(head.text, "data/") {
            member = head.text[len("data/"):]
        }
        if member == "tagged" {
            if len(form.items) != 3 {
                return "", Compile_Error{message = fmt.tprintf("%s expects tag text and a Data value", head.text), span = form.span}, false
            }
            tag, err_tag, ok_tag := emit_expr(e, form.items[1])
            if !ok_tag {
                return "", err_tag, false
            }
            value, err_value, ok_value := emit_expr(e, form.items[2])
            if !ok_value {
                return "", err_value, false
            }
            mark_data_type(e)
            return emit_call_text("kvist_data_make_tagged", []string{tag, value}), Compile_Error{}, true
        }
        if member == "item-at" || member == "key-at" || member == "value-at" {
            if len(form.items) != 3 {
                return "", Compile_Error{message = fmt.tprintf("%s expects Data map and index", head.text), span = form.span}, false
            }
            value, err_value, ok_value := emit_expr(e, form.items[1])
            if !ok_value {
                return "", err_value, false
            }
            index, err_index, ok_index := emit_expr(e, form.items[2])
            if !ok_index {
                return "", err_index, false
            }
            mark_data_type(e)
            return emit_call_text(fmt.tprintf("kvist_data_%s", map_name(member)), []string{value, index}), Compile_Error{}, true
        }
        if len(form.items) != 2 {
            return "", Compile_Error{message = fmt.tprintf("%s expects one Data value", head.text), span = form.span}, false
        }
        value, err_value, ok_value := emit_expr(e, form.items[1])
        if !ok_value {
            return "", err_value, false
        }
        mark_data_type(e)
        switch member {
        case "retain":
            return emit_call_text("kvist_data_retain", []string{value}), Compile_Error{}, true
        case "release":
            return emit_call_text("kvist_data_release", []string{value}), Compile_Error{}, true
        case "int", "float", "bool", "string", "keyword", "symbol", "text", "tag", "tagged-value", "count", "kind",
             "nil?", "bool?", "int?", "float?", "string?", "symbol?", "keyword?", "list?", "vector?", "map?", "set?", "tagged?":
            return emit_call_text(fmt.tprintf("kvist_data_%s", map_name(member)), []string{value}), Compile_Error{}, true
        case:
            return "", Compile_Error{message = fmt.tprintf("unknown Data operation: %s", head.text), span = head.span}, false
        }
    }

    canonical_head, _, err_head, ok_head := resolve_kvist_head(e, head.text)
    if !ok_head {
        err_head.span = head.span
        return "", err_head, false
    }
    head.text = canonical_head
    if head.text == "into" {
        return emit_transform_into_expr(e, form)
    }
    if head.text == "transform-into!" {
        return emit_transform_into_bang_expr(e, form)
    }

    if head.text == "transduce" {
        return emit_transform_transduce_expr(e, form)
    }

    if head.text == "thread-start" {
        return emit_thread_start_expr(e, form)
    }

    if head.text == "thread-detach" {
        return emit_thread_detach_expr(e, form)
    }

    if source, ok_source_call := source_call_decl(e, form); ok_source_call {
        return emit_source_materialized_expr(e, form, source)
    }

    if _, ok_step := transform_step_kind(head.text); ok_step && len(form.items) == 2 {
        return "", Compile_Error{message = fmt.tprintf("transform step `%s` cannot be used as a runtime value; use it with into, transduce, or for :transform", display_head_name(head.text)), span = head.span}, false
    }

    surface_head := display_head_name(head.text)

    if ctx, ok_context := lookup_callback_context(e, map_name(head.text)); ok_context {
        if ctx.field_selector != "" {
            if len(form.items) != 2 {
                return "", Compile_Error{message = "field-selector callback expects exactly one argument", span = form.span}, false
            }
            receiver, err_receiver, ok_receiver := emit_expr(e, form.items[1])
            if !ok_receiver {
                return "", err_receiver, false
            }
            return fmt.tprintf("%s.%s", receiver, ctx.field_selector), {}, true
        }
        arg_texts: [dynamic]string
        defer delete(arg_texts)
        for capture_name in ctx.capture_names {
            append(&arg_texts, capture_name)
        }
        for arg in form.items[1:] {
            arg_text, err_arg, ok_arg := emit_expr(e, arg)
            if !ok_arg {
                return "", err_arg, false
            }
            append(&arg_texts, arg_text)
        }
        return emit_call_text(map_name(head.text), arg_texts[:]), {}, true
    }

    if operator_text, err_op, ok_op := emit_operator_expr(e, form); ok_op {
        return operator_text, {}, true
    } else if err_op.message != "" {
        return "", err_op, false
    }

    if head.text == "new" {
        return "", Compile_Error{message = "`new` has been removed; use type-call syntax like (T literal)", span = form.items[0].span}, false
    }

    if head.text == "as" {
        return "", Compile_Error{message = "`as` has been removed; use type-call syntax like (T x)", span = form.items[0].span}, false
    }

    if head.text == "foreign-import" {
        return "", Compile_Error{message = "foreign-import is a top-level declaration form", span = form.items[0].span}, false
    }

    if head.text == "transmute" {
        if len(form.items) < 3 {
            return "", Compile_Error{message = "transmute expects type and value", span = form.span}, false
        }
        type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], 1)
        if !ok_type {
            return "", err_type, false
        }
        if next_i >= len(form.items) {
            return "", Compile_Error{message = "transmute missing value", span = form.span}, false
        }
        if next_i+1 != len(form.items) {
            return "", Compile_Error{message = "transmute expects exactly one value", span = form.items[next_i+1].span}, false
        }
        value, err_value, ok_value := emit_expr(e, form.items[next_i])
        if !ok_value {
            return "", err_value, false
        }
        return fmt.tprintf("transmute(%s)%s", type_text, value), {}, true
    }

    if head.text == "type-assert" {
        if len(form.items) < 3 {
            return "", Compile_Error{message = "type-assert expects value and type", span = form.span}, false
        }
        value, err_value, ok_value := emit_expr(e, form.items[1])
        if !ok_value {
            return "", err_value, false
        }
        type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], 2)
        if !ok_type {
            return "", err_type, false
        }
        if next_i != len(form.items) {
            return "", Compile_Error{message = "type-assert expects exactly one type", span = form.items[next_i].span}, false
        }
        return fmt.tprintf("(%s).(%s)", value, type_text), {}, true
    }

    if head.text == "odin-get" {
        if len(form.items) != 3 && len(form.items) != 4 {
            return "", Compile_Error{message = "odin-get expects collection, key, and optional default", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        target_ty, target_is_typed := obvious_form_type(e, form.items[1])
        if target_is_typed && target_ty == "Data" {
            key, err_key, ok_key := emit_data_lookup_key(e, form.items[2])
            if !ok_key {
                return "", err_key, false
            }
            call := emit_call_text("kvist_data_get", []string{target, key})
            if len(form.items) == 4 {
                fallback, err_fallback, ok_fallback := emit_data_value_literal(e, form.items[3])
                if form.items[3].kind == .Symbol ||
                   (form.items[3].kind == .List && len(form.items[3].items) > 0 && is_symbol(form.items[3].items[0], "quote")) {
                    fallback, err_fallback, ok_fallback = emit_expr(e, form.items[3])
                }
                if !ok_fallback {
                    return "", err_fallback, false
                }
                return emit_call_text("kvist_data_get_or", []string{target, key, fallback}), Compile_Error{}, true
            }
            return call, Compile_Error{}, true
        }
        map_target := map_index_target_text(e, form.items[1], target)
        if field, ok_field := selector_accesses_field(e, form.items[1], form.items[2]); ok_field {
            if len(form.items) == 4 {
                return "", Compile_Error{message = "odin-get field access does not support a default value", span = form.items[2].span}, false
            }
            return fmt.tprintf("(%s).%s", target, field), {}, true
        }
        key, err_key, ok_key := emit_expr(e, form.items[2])
        if !ok_key {
            return "", err_key, false
        }
        if len(form.items) == 4 {
            default_value, err_default, ok_default := emit_expr(e, form.items[3])
            if !ok_default {
                return "", err_default, false
            }
            mark_core_get_or_default(e)
            return emit_call_text("kvist_get_or_default", []string{map_target, key, default_value}), {}, true
        }
        return fmt.tprintf("%s[%s]", map_target, key), {}, true
    }

    is_struct_fields := head.text == "struct-fields"
    is_struct_types := head.text == "struct-types"
    if is_struct_fields || is_struct_types {
        if len(form.items) != 2 {
            return "", Compile_Error{message = fmt.tprintf("%s expects a quoted struct name", head.text), span = form.span}, false
        }
        struct_name, ok_name := quoted_symbol_name(form.items[1])
        if !ok_name {
            return "", Compile_Error{message = fmt.tprintf("%s currently expects a quoted struct name", head.text), span = form.items[1].span}, false
        }
        struct_decl, ok_struct := find_struct_decl(e, struct_name)
        if !ok_struct {
            return "", Compile_Error{message = fmt.tprintf("unknown struct: %s", struct_name), span = form.items[1].span}, false
        }
        if is_struct_fields {
            return emit_struct_fields_literal(struct_decl), {}, true
        }
        mark_dynamic_literals(e)
        return emit_struct_types_literal(struct_decl), {}, true
    }

    if head.text == "source-doc" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "source-doc expects one declaration name", span = form.span}, false
        }
        name := ""
        ok_name := false
        if form.items[1].kind == .Symbol &&
           (len(form.items[1].text) == 0 || form.items[1].text[0] != '\'') {
            name = map_name(form.items[1].text)
            ok_name = true
        } else {
            name, ok_name = quoted_symbol_name(form.items[1])
        }
        if !ok_name {
            return "", Compile_Error{message = "source-doc expects a declaration symbol", span = form.items[1].span}, false
        }
        defer delete(name)
        text, ok_doc := find_decl_doc_text(e, name)
        if !ok_doc {
            return "", Compile_Error{message = fmt.tprintf("unknown declaration: %s", name), span = form.items[1].span}, false
        }
        defer delete(text)
        return fmt.tprintf("%q", text), {}, true
    }

    if head.text == "odin-slice" {
        if len(form.items) < 2 || len(form.items) > 4 {
            return "", Compile_Error{message = "odin-slice expects target, optional start, and optional end", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        if len(form.items) == 2 {
            return fmt.tprintf("(%s)[:]", target), {}, true
        }
        start, err_start, ok_start := emit_expr(e, form.items[2])
        if !ok_start {
            return "", err_start, false
        }
        if len(form.items) == 3 {
            return fmt.tprintf("(%s)[%s:]", target, start), {}, true
        }
        end, err_end, ok_end := emit_expr(e, form.items[3])
        if !ok_end {
            return "", err_end, false
        }
        return fmt.tprintf("(%s)[%s:%s]", target, start, end), {}, true
    }

    if head.text == "^" || head.text == "deref" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = fmt.tprintf("%s expects one pointer expression", head.text), span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        return deref_expr_text(target), {}, true
    }

    if head.text == "&" {
        return "", Compile_Error{message = "address-of list form is not supported; use &value or (addr value)", span = form.span}, false
    }

    if head.text == "addr" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = fmt.tprintf("%s expects one addressable expression", head.text), span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        return addr_expr_text(target), {}, true
    }

    if head.text == "mut" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "mut expects one mutable target expression", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        return map_mutation_target_text(e, form.items[1], target), {}, true
    }

    if head.text == "copy-with" {
        return emit_shallow_assoc_expr(e, form)
    }
    if head.text == "copy-update" {
        return emit_shallow_update_expr(e, form)
    }
    if head.text == "copy-dissoc" {
        return emit_data_dissoc_expr(e, form)
    }
    if head.text == "copy-dissoc-in" {
        return emit_data_dissoc_in_expr(e, form)
    }
    if head.text == "decode-data" {
        return emit_data_decode_expr(e, form)
    }
    if head.text == "validate-data" {
        return emit_data_validate_expr(e, form)
    }

    if head.text == "as->" {
        return emit_as_thread_expr(e, form)
    }

    if head.text == "make" {
        if len(form.items) < 2 {
            return "", Compile_Error{message = "make expects a type and optional arguments", span = form.span}, false
        }
        type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], 1)
        if !ok_type {
            return "", err_type, false
        }
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        fmt.sbprintf(&builder, "make(%s", type_text)
        for arg in form.items[next_i:] {
            arg_text, err_arg, ok_arg := emit_expr(e, arg)
            if !ok_arg {
                return "", err_arg, false
            }
            strings.write_string(&builder, ", ")
            strings.write_string(&builder, arg_text)
        }
        strings.write_byte(&builder, ')')
        return strings.clone(strings.to_string(builder)), {}, true
    }

    if head.text == "alloc" {
        if len(form.items) < 2 {
            return "", Compile_Error{message = "alloc expects a type and optional allocator", span = form.span}, false
        }
        type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], 1)
        if !ok_type {
            return "", err_type, false
        }
        if next_i != len(form.items) && next_i+1 != len(form.items) {
            return "", Compile_Error{message = "alloc expects a type and optional allocator", span = form.items[next_i].span}, false
        }
        if next_i == len(form.items) {
            return fmt.tprintf("new(%s)", type_text), {}, true
        }
        allocator, err_allocator, ok_allocator := emit_expr(e, form.items[next_i])
        if !ok_allocator {
            return "", err_allocator, false
        }
        return fmt.tprintf("new(%s, %s)", type_text, allocator), {}, true
    }

    if len(form.items) == 2 && form.items[1].kind == .Vector {
        if head.text == "quaternion" {
            return emit_quaternion_vector_constructor(e, form.items[1])
        }
        head_name := map_name(head.text)
        if !strings.contains(head_name, ".") {
            if call_head_is_overload(e, head) {
                // Let the normal call path apply the overload's literal context.
            } else if _, _, ok_proc := resolve_proc_call_decl(e, head.text); ok_proc {
                // Let the normal call path handle declared procedures with vector arguments.
            } else {
                type_text, err_type, ok_type := parse_type_text(head)
                if !ok_type {
                    return "", err_type, false
                }
                text, err_literal, ok_literal, _ := emit_typed_literal_value(e, head, type_text, form.items[1])
                return text, err_literal, ok_literal
            }
        } else {
            imported_fields, ok_imported_type := imported_odin_type_fields(e, head_name)
            if ok_imported_type {
                defer delete_struct_field_slice(&imported_fields)
                type_text, err_type, ok_type := parse_type_text(head)
                if !ok_type {
                    return "", err_type, false
                }
                text, err_literal, ok_literal, _ := emit_typed_literal_value(e, head, type_text, form.items[1])
                return text, err_literal, ok_literal
            }
            if _, ok_expected := imported_odin_proc_arg_type(e, head_name, 0); !ok_expected {
                type_text, err_type, ok_type := parse_type_text(head)
                if !ok_type {
                    return "", err_type, false
                }
                text, err_literal, ok_literal, _ := emit_typed_literal_value(e, head, type_text, form.items[1])
                return text, err_literal, ok_literal
            }
        }
    }

    if len(form.items) == 2 && form.items[1].kind == .Set && !call_head_is_overload(e, head) {
        type_text, err_type, ok_type := parse_type_text(head)
        if !ok_type {
            return "", err_type, false
        }
        text, err_literal, ok_literal, _ := emit_typed_literal_value(e, head, type_text, form.items[1])
        return text, err_literal, ok_literal
    }

    if head.text == "quaternion" {
        return emit_quaternion_arg_constructor(e, form.items[1:], form.span)
    }

    if len(form.items) == 2 && form.items[1].kind == .Brace && !call_head_is_overload(e, head) {
        head_name := map_name(head.text)
        struct_decl, ok_struct := find_struct_decl(e, head_name)
        if ok_struct {
            err_struct, ok_struct_ctor := validate_struct_constructor(e, struct_decl, form.items[1])
            if !ok_struct_ctor {
                return "", err_struct, false
            }
            return emit_struct_brace_literal(e, struct_decl, form.items[1])
        }
        union_decl, ok_union := find_union_decl(e, head_name)
        if ok_union {
            return emit_union_constructor(e, union_decl, form.items[1])
        }
        imported_fields, ok_imported := imported_odin_type_fields(e, head_name)
        if ok_imported {
            defer delete_struct_field_slice(&imported_fields)
            return emit_imported_struct_brace_literal(e, head_name, imported_fields[:], form.items[1])
        }
        if type_text_is_map(head_name) {
            mark_dynamic_literals(e)
            return emit_brace_literal(e, head_name, form.items[1])
        }
        if dotted_head_member_starts_upper(head_name) {
            return emit_brace_literal(e, head_name, form.items[1])
        }
        if !strings.contains(head_name, ".") {
            if call_name, proc_decl, ok_proc := resolve_proc_call_decl(e, head.text); ok_proc {
                named_arg_texts, err_named, ok_named := emit_named_call_with_defaults(e, proc_decl, form.items[1])
                if !ok_named {
                    return "", err_named, false
                }
                return emit_call_text(call_name, named_arg_texts[:]), {}, true
            }
        }
        named_arg_texts, err_named, ok_named := emit_named_call_arg_texts(e, form.items[1])
        if ok_named {
            return emit_call_text(head_name, named_arg_texts[:]), {}, true
        }
        if err_named.message != "" && err_named.message != "named arguments expect field: labels" {
            return "", err_named, false
        }
        return emit_brace_literal(e, head_name, form.items[1])
    }

    arg_texts: [dynamic]string
    head_name := map_name(head.text)
    if !strings.contains(head_name, ".") {
        if call_name, proc_decl, ok_proc := resolve_proc_call_decl(e, head.text); ok_proc {
            specialized_call, handled_specialized, err_specialized, ok_specialized := emit_specialized_proc_call_if_needed(e, call_name, proc_decl, form.items[1:], form.span)
            if handled_specialized {
                if !ok_specialized {
                    return "", err_specialized, false
                }
                return specialized_call, {}, true
            }
            if len(form.items) >= 3 &&
               form.items[len(form.items)-1].kind == .Brace &&
               form_is_named_arg_brace(form.items[len(form.items)-1]) {
                arg_texts_with_mixed, err_args, ok_args := emit_mixed_call_with_defaults(e, proc_decl, form.items[1:len(form.items)-1], form.items[len(form.items)-1], form.span)
                if !ok_args {
                    return "", err_args, false
                }
                return emit_call_text(call_name, arg_texts_with_mixed[:]), {}, true
            }
            arg_texts_with_defaults, err_args, ok_args := emit_positional_call_with_defaults(e, proc_decl, form.items[1:], form.span)
            if !ok_args {
                return "", err_args, false
            }
            return emit_call_text(call_name, arg_texts_with_defaults[:]), {}, true
        }
    }
    if len(form.items) != 2 {
        if _, ok_struct := find_struct_decl(e, head_name); ok_struct {
            return "", Compile_Error{
                message = fmt.tprintf(
                    "struct construction expects one brace or vector aggregate; use (%s {{field: value ...}}) or (%s [value ...])",
                    head.text,
                    head.text,
                ),
                span    = form.span,
            }, false
        }
    }
    if len(form.items) == 2 && symbol_head_needs_type_conversion_parens(head.text) {
        type_text, err_type, ok_type := parse_type_text(head)
        if !ok_type {
            return "", err_type, false
        }
        mark_keyword_type_for_text(e, type_text)
        value_text, err_value, ok_value := emit_expr(e, form.items[1])
        if !ok_value {
            return "", err_value, false
        }
        return emit_type_conversion_text(type_text, value_text), {}, true
    }
    generic_ctor, err_generic_ctor, ok_generic_ctor := emit_generic_type_constructor_call(e, form)
    if ok_generic_ctor || err_generic_ctor.message != "" {
        return generic_ctor, err_generic_ctor, ok_generic_ctor
    }
    if len(form.items) >= 3 &&
       form.items[len(form.items)-1].kind == .Brace &&
       form_is_named_arg_brace(form.items[len(form.items)-1]) {
        arg_texts_with_mixed, err_mixed, ok_mixed := emit_general_mixed_call_arg_texts(e, head_name, form.items[1:len(form.items)-1], form.items[len(form.items)-1])
        if ok_mixed {
            return emit_call_text(head_name, arg_texts_with_mixed[:]), {}, true
        }
        if err_mixed.message != "" && err_mixed.message != "named arguments expect field: labels" {
            return "", err_mixed, false
        }
    }
    for arg, arg_idx in form.items[1:] {
        arg_text := ""
        err_arg: Compile_Error
        ok_arg := false
        if expected_type, ok_expected := overload_literal_arg_expected_type(e, head_name, form.items[1:], arg_idx); ok_expected {
            arg_text, err_arg, ok_arg = emit_call_arg_for_expected_type(e, arg, expected_type)
            delete(expected_type)
        } else if expected_type, ok_expected := imported_odin_proc_arg_type(e, head_name, arg_idx); ok_expected {
            arg_text, err_arg, ok_arg = emit_call_arg_for_expected_type(e, arg, expected_type)
            delete(expected_type)
        } else {
            arg_text, err_arg, ok_arg = emit_expr(e, arg)
        }
        if !ok_arg {
            return "", err_arg, false
        }
        append(&arg_texts, arg_text)
    }
    return emit_call_text(head_name, arg_texts[:]), {}, true
}

emit_type_application_expr :: proc(e: ^Emitter, type_form: CST_Form, args: []CST_Form, span: Span) -> (string, Compile_Error, bool) {
    if len(args) != 1 {
        return "", Compile_Error{message = "type application expects exactly one value", span = span}, false
    }

    type_text, err_type, ok_type := parse_type_text(type_form)
    if !ok_type {
        return "", err_type, false
    }
    mark_keyword_type_for_text(e, type_text)

    value := args[0]
    if text, err_literal, ok_literal, handled := emit_typed_literal_value(e, type_form, type_text, value); handled {
        return text, err_literal, ok_literal
    }
    value_text, err_value, ok_value := emit_expr(e, value)
    if !ok_value {
        return "", err_value, false
    }
    return emit_type_conversion_text(type_text, value_text), {}, true
}

generic_type_constructor_call_candidate :: proc(head: CST_Form) -> bool {
    if head.kind != .Symbol || len(head.text) == 0 {
        return false
    }
    if head.text[0] >= 'A' && head.text[0] <= 'Z' {
        return true
    }
    dot := strings.last_index(head.text, ".")
    return dot >= 0 && dot+1 < len(head.text) && head.text[dot+1] >= 'A' && head.text[dot+1] <= 'Z'
}

emit_generic_type_constructor_call :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) < 3 || !generic_type_constructor_call_candidate(form.items[0]) {
        return "", Compile_Error{}, false
    }
    if _, ok_expected := imported_odin_proc_arg_type(e, map_name(form.items[0].text), 0); ok_expected {
        return "", Compile_Error{}, false
    }

    value := form.items[len(form.items)-1]
    if value.kind != .Vector && value.kind != .Brace {
        return "", Compile_Error{}, false
    }

    type_form := CST_Form{
        kind  = .List,
        span  = form.span,
        items = make([dynamic]CST_Form, 0, len(form.items)),
    }
    append(&type_form.items, CST_Form{kind = .Symbol, text = "typeid", span = form.items[0].span})
    for item in form.items[:len(form.items)-1] {
        append(&type_form.items, item)
    }

    result, err, ok := emit_type_application_expr(e, type_form, form.items[len(form.items)-1:], form.span)
    delete(type_form.items)
    return result, err, ok
}

emit_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    #partial switch form.kind {
    case .String:
        return emit_string_literal_text(form), {}, true
    case .Regex:
        return emit_regex_literal_text(form), {}, true
    case .Number:
        return form.text, {}, true
    case .Bool:
        return form.text, {}, true
    case .Nil:
        return form.text, {}, true
    case .Symbol:
        if dot := strings.index(form.text, "."); dot > 0 && dot+1 < len(form.text) {
            root := map_name(form.text[:dot])
            if _, local := lookup_local_type(e, root); !local {
                field_path := map_name(form.text[dot+1:])
                if name_in_list(e.repl_var_names, root) {
                    return fmt.tprintf("((%s())^).%s", root, field_path), {}, true
                }
                if name_in_list(e.repl_value_names, root) {
                    return fmt.tprintf("(%s()).%s", root, field_path), {}, true
                }
            }
        }
        if len(form.text) > 1 && form.text[0] == '&' {
            target := map_name(form.text[1:])
            if name_in_list(e.repl_var_names, target) {
                if _, local := lookup_local_type(e, target); !local {
                    return fmt.tprintf("%s()", target), {}, true
                }
            }
            return addr_expr_text(target), {}, true
        }
        if symbol_is_simple_deref_suffix(form.text) {
            return deref_expr_text(map_name(form.text[:len(form.text)-1])), {}, true
        }
        name := map_name(form.text)
        if name_in_list(e.repl_var_names, name) {
            if _, local := lookup_local_type(e, name); !local {
                return deref_expr_text(fmt.tprintf("%s()", name)), {}, true
            }
        }
        if name_in_list(e.repl_value_names, name) {
            if _, local := lookup_local_type(e, name); !local {
                return fmt.tprintf("%s()", name), {}, true
            }
        }
        return name, {}, true
    case .Keyword:
        return keyword_literal_text(e, form.text), {}, true
    case .List:
        if len(form.items) == 0 {
            return "", Compile_Error{message = "empty list expression", span = form.span}, false
        }
        if form.items[0].kind == .Symbol &&
           len(form.items[0].text) > 0 &&
           form.items[0].text[0] == '#' &&
           !strings.has_prefix(form.items[0].text, "#soa[") &&
           !strings.has_prefix(form.items[0].text, "#simd[") {
            return emit_directive_expr(e, form)
        }
        if is_symbol(form.items[0], "proc") {
            return "", Compile_Error{message = "`proc` has been removed; use `fn` for function literals and function types, or `defn` for named functions", span = form.items[0].span}, false
        }
        if is_symbol(form.items[0], "quote") {
            return emit_quoted_data_expr(e, form)
        }
        if is_symbol(form.items[0], "quasiquote") {
            return emit_runtime_data_quasiquote_expr(e, form)
        }
        if head, ok_statement := form_head_is_statement_only(form); ok_statement {
            return "", Compile_Error{message = fmt.tprintf("%s is a statement and cannot be used as an expression", display_head_name(head)), span = form.items[0].span}, false
        }
        if is_symbol(form.items[0], "if") {
            return emit_if_expr(e, form)
        }
        if is_symbol(form.items[0], "let") || form_head_is_do(form) {
            return emit_block_expr(e, form)
        }
        if form_head_is_allocator_scope(form) {
            return emit_block_expr(e, form)
        }
        if form_head_is_case(form) {
            return emit_case_expr(e, form)
        }
        if form_head_is_match(form) {
            return emit_block_expr(e, form)
        }
        if is_symbol(form.items[0], "fn") {
            return emit_proc_literal_expr(e, form)
        }
        if is_symbol(form.items[0], "__kvist_field") {
            if len(form.items) != 3 || form.items[2].kind != .Symbol {
                return "", Compile_Error{message = "field access expects receiver and field", span = form.span}, false
            }
            receiver, err_receiver, ok_receiver := emit_expr(e, form.items[1])
            if !ok_receiver {
                return "", err_receiver, false
            }
            return fmt.tprintf("%s.%s", receiver, map_name(form.items[2].text)), {}, true
        }
        if is_symbol(form.items[0], "__kvist_index") {
            if len(form.items) != 3 {
                return "", Compile_Error{message = "index expression expects target and index", span = form.span}, false
            }
            target, err_target, ok_target := emit_expr(e, form.items[1])
            if !ok_target {
                return "", err_target, false
            }
            index, err_index, ok_index := emit_expr(e, form.items[2])
            if !ok_index {
                return "", err_index, false
            }
            return fmt.tprintf("(%s)[%s]", target, index), {}, true
        }
        if is_symbol(form.items[0], "__kvist_slice") {
            if len(form.items) != 4 {
                return "", Compile_Error{message = "slice expression expects target, start, and end", span = form.span}, false
            }
            target, err_target, ok_target := emit_expr(e, form.items[1])
            if !ok_target {
                return "", err_target, false
            }
            start_omitted := form_is_omitted_slice_bound(form.items[2])
            end_omitted := form_is_omitted_slice_bound(form.items[3])
            if start_omitted && end_omitted {
                return fmt.tprintf("(%s)[:]", target), {}, true
            }
            if start_omitted {
                end, err_end, ok_end := emit_expr(e, form.items[3])
                if !ok_end {
                    return "", err_end, false
                }
                return fmt.tprintf("(%s)[:%s]", target, end), {}, true
            }
            start, err_start, ok_start := emit_expr(e, form.items[2])
            if !ok_start {
                return "", err_start, false
            }
            if end_omitted {
                return fmt.tprintf("(%s)[%s:]", target, start), {}, true
            }
            end, err_end, ok_end := emit_expr(e, form.items[3])
            if !ok_end {
                return "", err_end, false
            }
            return fmt.tprintf("(%s)[%s:%s]", target, start, end), {}, true
        }
        if is_symbol(form.items[0], "odin") {
            if len(form.items) != 2 || form.items[1].kind != .String {
                return "", Compile_Error{message = "odin expects one string literal", span = form.span}, false
            }
            return unquote_string(form.items[1].text), {}, true
        }
        if is_symbol(form.items[0], "odin-infix") {
            return emit_odin_infix_expr(e, form)
        }
        if is_symbol(form.items[0], "odin-prefix") {
            return emit_odin_prefix_expr(e, form)
        }
        if is_symbol(form.items[0], "odin-call") {
            return emit_odin_call_expr(e, form)
        }
        if is_symbol(form.items[0], "type") {
            return emit_runtime_type_expr(e, form)
        }
        if is_symbol(form.items[0], "typeid") {
            type_text, err_type, ok_type := parse_type_text(form)
            if !ok_type {
                return "", err_type, false
            }
            return type_text, {}, true
        }
        _, local_data_struct := find_struct_decl(e, "Data")
        if is_symbol(form.items[0], "Data") && !local_data_struct {
            if len(form.items) != 2 {
                return "", Compile_Error{message = "Data conversion expects one value", span = form.span}, false
            }
            value, _, err_value, ok_value :=
                emit_contextual_data_value(e, form.items[1])
            return value, err_value, ok_value
        }
        if form.items[0].kind == .Keyword {
            if len(form.items) != 2 && len(form.items) != 3 {
                return "", Compile_Error{message = "keyword invocation expects map and optional fallback", span = form.span}, false
            }
            fallback: ^CST_Form
            if len(form.items) == 3 {
                fallback = &form.items[2]
            }
            return emit_data_callable_lookup(e, form.items[1], form.items[0], fallback, form.span)
        }
        if form.items[0].kind != .Symbol {
            return emit_type_application_expr(e, form.items[0], form.items[1:], form.span)
        }
        return emit_call_like(e, form)
    case .Vector, .Brace, .Set:
        return emit_inferred_literal(e, form)
    }
    return "", Compile_Error{message = "unsupported expression", span = form.span}, false
}
