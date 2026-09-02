package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

binding_value_is_let :: proc(binding: Binding) -> bool {
    return !binding.is_destructure &&
        !binding.is_result_binding &&
        binding.name != "" &&
        binding.value.kind == .List &&
        len(binding.value.items) > 0 &&
        binding.value.items[0].kind == .Symbol &&
        binding.value.items[0].text == "let"
}

emit_let_value_binding_assignment :: proc(e: ^Emitter, binding: Binding) -> (Compile_Error, bool) {
    let_form := binding.value
    if len(let_form.items) < 3 {
        return Compile_Error{message = "let expects bindings and body", span = let_form.span}, false
    }
    inner_bindings, err_bind, ok_bind := parse_let_bindings(let_form.items[1])
    if !ok_bind {
        return err_bind, false
    }
    err_tail, bad_tail := let_errdefer_tail_error(inner_bindings[:], false)
    if bad_tail {
        return err_tail, false
    }
    body := let_form.items[2:]
    if len(body) == 0 {
        return Compile_Error{message = "let expects bindings and body", span = let_form.span}, false
    }

    for inner in inner_bindings {
        native_sequence := binding_is_native_sequence_destructure(e, inner)
        if native_sequence {
            err_native, ok_native := emit_native_sequence_let_binding(e, inner)
            if !ok_native {
                return err_native, false
            }
        } else if binding_is_data_destructure(e, inner) {
            err_data, ok_data := emit_data_let_binding(e, inner)
            if !ok_data {
                return err_data, false
            }
        } else if binding_value_is_let(inner) {
            err_inner, ok_inner := emit_let_value_binding_assignment(e, inner)
            if !ok_inner {
                return err_inner, false
            }
        } else {
            value: string
            err_value: Compile_Error
            ok_value: bool
            if form_has_nested_owned_value(inner.value, e) {
                value, err_value, ok_value = emit_expr_with_owned_nested_temps(e, inner.value)
            } else {
                err_owned, bad_owned := owned_result_usage_error(inner.value, true, e)
                if bad_owned {
                    return err_owned, false
                }
                value, err_value, ok_value = emit_expr_for_expected_type(e, inner.value, inner.ty)
            }
            if !ok_value {
                return err_value, false
            }
            emit_binding_assignment(e, inner, value)
        }

        err_guard, ok_guard := emit_result_binding_guard(e, inner, Return_Spec{})
        if !ok_guard {
            return err_guard, false
        }
        if inner.deferred_delete {
            err_defer, ok_defer := emit_binding_deferred_delete(e, inner)
            if !ok_defer {
                return err_defer, false
            }
        }
        if inner.defer_with_cleanup {
            err_defer, ok_defer := emit_binding_defer_with_cleanup(e, inner)
            if !ok_defer {
                return err_defer, false
            }
        }
        if inner.err_deferred_delete {
            err_defer, ok_defer := emit_binding_err_deferred_delete(e, inner)
            if !ok_defer {
                return err_defer, false
            }
        }
        bind_obvious_binding_types(e, inner)
    }

    if len(body) > 1 {
        err_body, ok_body := emit_body_forms(e, body[:len(body)-1], Return_Spec{})
        if !ok_body {
            return err_body, false
        }
    }
    final_text, err_final, ok_final := emit_expr_for_expected_type(e, body[len(body)-1], binding.ty)
    if !ok_final {
        return err_final, false
    }
    emit_binding_assignment(e, binding, final_text)
    return {}, true
}

emit_result_binding_named_return_assignment :: proc(e: ^Emitter, binding: Binding, value: string) {
    line_builder := strings.builder_make()
    defer strings.builder_destroy(&line_builder)
    for name, idx in binding.pattern {
        if idx > 0 {
            strings.write_string(&line_builder, ", ")
        }
        strings.write_string(&line_builder, binding_output_name(name))
    }
    fmt.sbprintf(&line_builder, " = %s", value)
    emit_prefixed_expr_mapped(e, "", strings.clone(strings.to_string(line_builder)), binding.value.span)
}

form_is_owned_allocation_result :: proc(form: CST_Form) -> bool {
    if form.kind != .List || len(form.items) < 2 || form.items[0].kind != .Symbol {
        return false
    }
    head := form.items[0].text
    if head != "make" {
        return false
    }
    type_text, _, ok_type := parse_type_text(form.items[1])
    if !ok_type {
        return false
    }
    defer delete(type_text)
    return type_text_is_dynamic_array(type_text) || type_text_is_dynamic_soa(type_text) || type_text_is_map(type_text)
}

form_is_owned_constructor_result :: proc(form: CST_Form) -> bool {
    if form.kind == .Vector || form.kind == .Brace || form.kind == .Set {
        return true
    }
    if form.kind != .List || len(form.items) == 0 {
        return false
    }
    if len(form.items) == 2 &&
       (form.items[1].kind == .Vector || form.items[1].kind == .Brace || form.items[1].kind == .Set) {
        type_text, _, ok_type := parse_type_text(form.items[0])
        if ok_type {
            defer delete(type_text)
            return type_text_is_dynamic_array(type_text) || type_text_is_dynamic_soa(type_text) || type_text_is_map(type_text)
        }
    }
    return false
}

form_is_literal_constructor_call :: proc(form: CST_Form, e: ^Emitter = nil) -> bool {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    head_name := map_name(form.items[0].text)
    defer delete(head_name)
    if _, ok_struct := find_struct_decl(e, head_name); ok_struct {
        return true
    }
    if _, ok_union := find_union_decl(e, head_name); ok_union {
        return true
    }
    if symbol_tail_starts_upper(form.items[0].text) {
        imported_fields, ok_imported := imported_odin_type_fields(e, head_name)
        if ok_imported {
            delete_struct_field_slice(&imported_fields)
            return true
        }
    }
    return false
}

form_produces_owned_value :: proc(form: CST_Form, e: ^Emitter = nil) -> bool {
    return form_is_owned_result(form, e) || form_is_owned_allocation_result(form) || form_is_owned_constructor_result(form)
}

form_requires_explicit_owned_cleanup :: proc(form: CST_Form, e: ^Emitter = nil) -> bool {
    if !form_produces_owned_value(form, e) {
        return false
    }
    _, compiler_managed := owned_managed_form_type(e, form)
    return !compiler_managed
}

binding_value_produces_owned_value :: proc(binding: Binding, e: ^Emitter = nil) -> bool {
    if binding.is_typed &&
       (binding.value.kind == .Vector || binding.value.kind == .Brace || binding.value.kind == .Set) {
        return type_text_is_owned_result(binding.ty)
    }
    return form_produces_owned_value(binding.value, e)
}

form_is_owned_temp_escape_result :: proc(form: CST_Form, e: ^Emitter = nil) -> bool {
    return form_produces_owned_value(form, e)
}

with_temp_allocator_escape_error :: proc(e: ^Emitter, body: []CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    if err_span, ok := body_escape_owned_temp_result_span_names(e, body, nil, returns); ok {
        return Compile_Error{
            message = "owned value cannot escape with-temp-allocator; allocate it outside the temp scope or copy it before returning",
            span = err_span,
        }, true
    }
    return {}, false
}

loop_collection_needs_temp_binding :: proc(e: ^Emitter, form: CST_Form) -> bool {
    return form_is_owned_result(form, e) || form_is_owned_allocation_result(form) || form_is_owned_constructor_result(form)
}
