// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

emit_body_forms :: proc(
    e: ^Emitter,
    body: []CST_Form,
    returns: Return_Spec,
    discard_result := false,
) -> (Compile_Error, bool) {
    for form, idx in body {
        last := idx == len(body)-1
        start_line := e.line
        explicit_debug_pause :=
            form.kind == .List &&
            len(form.items) > 0 &&
            form.items[0].kind == .Symbol &&
            (form.items[0].text == "kvist-intrinsic-breakpoint" ||
             form.items[0].text == "kvist-intrinsic-signal-condition" ||
             form.items[0].text == "kvist-intrinsic-use-value-restart" ||
             form.items[0].text == "kvist-intrinsic-restart-case" ||
             form.items[0].text == "kvist-intrinsic-condition-operation")
        if e.repl_debug_enabled && !explicit_debug_pause {
            debug_emit_pause(e, form, false)
        }
        err_stmt, ok_stmt := emit_stmt(
            e,
            form,
            last,
            returns,
            discard_result && last,
        )
        if !ok_stmt {
            return err_stmt, false
        }
        record_source_map(e, start_line, e.line - 1, form.span)
    }
    return {}, true
}

returns_when_final :: proc(last_in_proc: bool, returns: Return_Spec) -> Return_Spec {
    if last_in_proc {
        return returns
    }
    return Return_Spec{kind = .None}
}

is_local_decl_head :: proc(head: string) -> bool {
    switch head {
    case "def", "defstruct", "defenum", "defunion":
        return true
    case:
        return false
    }
}

form_is_known_void_call :: proc(e: ^Emitter, form: CST_Form) -> bool {
    if form.kind != .List || len(form.items) == 0 ||
       form.items[0].kind != .Symbol {
        return false
    }
    _, proc_decl, resolved :=
        resolve_proc_call_decl(e, form.items[0].text)
    return resolved && proc_decl != nil && proc_decl.returns.kind == .None
}

emit_statement_expr :: proc(
    e: ^Emitter,
    form: CST_Form,
    expr: string,
    discard_result: bool,
) {
    if discard_result && !form_is_known_void_call(e, form) {
        emit_discarded_expr(e, form, expr)
        return
    }
    emit_prefixed_expr_mapped(e, "", expr, form.span)
}

emit_local_var_stmt :: proc(e: ^Emitter, form: CST_Form) -> (Compile_Error, bool) {
    if len(form.items) < 3 {
        return Compile_Error{message = "defvar expects a name, optional type, and value", span = form.span}, false
    }
    target := form.items[1]
    if target.kind != .Symbol {
        return Compile_Error{message = "defvar expects a symbol name", span = target.span}, false
    }

    name := target.text
    ty := ""
    value_index := 2
    is_typed := false
    if len(name) > 0 && name[len(name)-1] == ':' {
        if len(name) == 1 {
            return Compile_Error{message = "defvar expects a name before :", span = target.span}, false
        }
        parsed_ty, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], 2)
        if !ok_type {
            return err_type, false
        }
        if next_i >= len(form.items) {
            local_name := map_name(name[:len(name)-1])
            emit_line(e, fmt.tprintf("%s: %s", local_name, parsed_ty))
            bind_local_type(e, local_name, parsed_ty, mutable = true)
            return {}, true
        }
        ty = parsed_ty
        value_index = next_i
        name = name[:len(name)-1]
        is_typed = true
    }
    if value_index+1 != len(form.items) {
        return Compile_Error{message = "defvar expects exactly one value", span = form.items[value_index+1].span}, false
    }

    value_form := form.items[value_index]
    err_owned, bad_owned := owned_result_usage_error(value_form, true, e)
    if bad_owned {
        return err_owned, false
    }
    value, err_value, ok_value := emit_expr_for_expected_type(e, value_form, ty)
    if !ok_value {
        return err_value, false
    }

    local_name := map_name(name)
    if is_typed {
        emit_prefixed_expr_mapped(e, fmt.tprintf("%s: %s = ", local_name, ty), value, value_form.span)
        bind_local_type(e, local_name, ty, mutable = true)
    } else {
        emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", local_name), value, value_form.span)
        if form_ty, ok_ty := obvious_form_type(e, value_form); ok_ty {
            bind_local_type(e, local_name, form_ty, mutable = true)
        }
    }
    return {}, true
}

emit_local_decl_stmt :: proc(e: ^Emitter, form: CST_Form) -> (Compile_Error, bool) {
    decl_form := form

    decl, err_decl, ok_decl := parse_decl(CST_Top_Form{form = decl_form})
    if !ok_decl {
        return err_decl, false
    }
    #partial switch decl.kind {
    case .Const, .Struct, .Enum, .Union:
    case:
        return Compile_Error{message = "unsupported local declaration form", span = form.span}, false
    }

    err_emit, ok_emit := emit_decl(e, IR_Decl(decl))
    if !ok_emit {
        return err_emit, false
    }
    if decl.kind == .Struct {
        append(&e.local_structs, decl.struct_decl)
    }
    if decl.kind == .Union {
        append(&e.local_unions, decl.union_decl)
    }
    return {}, true
}

emit_if_branch_stmt :: proc(
    e: ^Emitter,
    branch: CST_Form,
    last_in_proc: bool,
    returns: Return_Spec,
    discard_result := false,
) -> (Compile_Error, bool) {
    if branch.kind == .List && len(branch.items) > 0 && branch.items[0].kind == .Symbol && branch.items[0].text == "do" {
        return emit_body_forms(
            e,
            branch.items[1:],
            returns,
            discard_result,
        )
    }
    return emit_stmt(e, branch, last_in_proc, returns, discard_result)
}

// An else-if test must not emit setup statements before the `else` token.
// Keep the flattened form only for expressions whose lowering is known to be
// inline. Other tests are emitted as a nested if inside an else block so
// contextual Data temporaries and similar preludes stay in the false branch.
form_is_inline_if_test :: proc(form: CST_Form) -> bool {
    #partial switch form.kind {
    case .String, .Regex, .Number, .Bool, .Nil, .Symbol, .Keyword:
        return true
    case .List:
        if len(form.items) == 0 || form.items[0].kind != .Symbol {
            return false
        }
        head := form.items[0].text
        switch head {
        case "=", "!=", "<", "<=", ">", ">=", "not", "and", "or", "__kvist_field", "__kvist_index":
            for arg in form.items[1:] {
                if !form_is_inline_if_test(arg) {
                    return false
                }
            }
            return true
        }
    }
    return false
}

emit_if_like_with_prefix :: proc(
    e: ^Emitter,
    head: string,
    form: CST_Form,
    last_in_proc: bool,
    returns: Return_Spec,
    prefix := "",
    discard_result := false,
) -> (Compile_Error, bool) {
    if len(form.items) < 3 || len(form.items) > 4 {
        return Compile_Error{message = fmt.tprintf("%s expects test, then, and optional else", head), span = form.span}, false
    }
    test, err_test, ok_test := emit_expr(e, form.items[1])
    if !ok_test {
        return err_test, false
    }
    emit_indent(e)
    strings.write_string(&e.builder, prefix)
    strings.write_string(&e.builder, "if ")
    strings.write_string(&e.builder, test)
    record_current_line_fragment_map(e, len(prefix)+len("if "), test, form.items[1].span)
    strings.write_string(&e.builder, " {")
    emit_raw_newline(e)
    e.indent += 1
    branch_returns := returns_when_final(last_in_proc, returns)
    push_local_type_scope(e)
    err_then, ok_then := emit_if_branch_stmt(
        e,
        form.items[2],
        last_in_proc,
        branch_returns,
        discard_result,
    )
    pop_local_type_scope(e)
    if !ok_then {
        return err_then, false
    }
    e.indent -= 1
    emit_line(e, "}")
    if len(form.items) == 4 {
        else_branch := form.items[3]
        if form_is_zero_call(else_branch) && branch_returns.kind != .Single {
            err_zero, ok_zero := validate_zero_stmt(else_branch)
            if !ok_zero {
                return err_zero, false
            }
            return {}, true
        }
        if else_branch.kind == .List && len(else_branch.items) > 2 &&
           else_branch.items[0].kind == .Symbol && else_branch.items[0].text == "if" &&
           form_is_inline_if_test(else_branch.items[1]) {
            return emit_if_like_with_prefix(
                e,
                "if",
                else_branch,
                last_in_proc,
                returns,
                "else ",
                discard_result,
            )
        }
        emit_indent(e)
        strings.write_string(&e.builder, "else {")
        emit_raw_newline(e)
        e.indent += 1
        push_local_type_scope(e)
        err_else, ok_else := emit_if_branch_stmt(
            e,
            else_branch,
            last_in_proc,
            branch_returns,
            discard_result,
        )
        pop_local_type_scope(e)
        if !ok_else {
            return err_else, false
        }
        e.indent -= 1
        emit_line(e, "}")
    }
    return {}, true
}

emit_if_like :: proc(
    e: ^Emitter,
    head: string,
    form: CST_Form,
    last_in_proc: bool,
    returns: Return_Spec,
    discard_result := false,
) -> (Compile_Error, bool) {
    return emit_if_like_with_prefix(
        e,
        head,
        form,
        last_in_proc,
        returns,
        discard_result = discard_result,
    )
}

is_else_keyword :: proc(form: CST_Form) -> bool {
    return form.kind == .Keyword && form.text == ":else"
}

emit_with_allocator_stmt :: proc(
    e: ^Emitter,
    form: CST_Form,
    last_in_proc: bool,
    returns: Return_Spec,
    discard_result := false,
) -> (Compile_Error, bool) {
    if len(form.items) < 3 {
        return Compile_Error{message = "with-allocator expects binding vector and body", span = form.span}, false
    }
    binding := form.items[1]
    if binding.kind != .Vector || len(binding.items) != 2 || binding.items[0].kind != .Symbol {
        return Compile_Error{message = "with-allocator expects [name allocator] binding", span = binding.span}, false
    }
    allocator_name := map_name(binding.items[0].text)
    allocator_expr, err_allocator, ok_allocator := emit_expr(e, binding.items[1])
    if !ok_allocator {
        return err_allocator, false
    }

    e.temp_counter += 1
    old_allocator := fmt.tprintf("kvist_old_allocator_%d", e.temp_counter)
    emit_line(e, "{")
    e.indent += 1
    push_local_type_scope(e)
    emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", allocator_name), allocator_expr, binding.items[1].span)
    emit_line(e, fmt.tprintf("%s := context.allocator", old_allocator))
    emit_line(e, fmt.tprintf("context.allocator = %s", allocator_name))
    emit_line(e, fmt.tprintf("defer context.allocator = %s", old_allocator))

    body: [dynamic]CST_Form
    for item in form.items[2:] {
        append(&body, item)
    }
    err_body, ok_body := emit_body_forms(
        e,
        body[:],
        returns_when_final(last_in_proc, returns),
        discard_result,
    )
    pop_local_type_scope(e)
    if !ok_body {
        return err_body, false
    }

    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

emit_with_temp_allocator_stmt :: proc(
    e: ^Emitter,
    form: CST_Form,
    last_in_proc: bool,
    returns: Return_Spec,
    discard_result := false,
) -> (Compile_Error, bool) {
    if len(form.items) < 3 {
        return Compile_Error{message = "with-temp-allocator expects binding vector and body", span = form.span}, false
    }
    binding := form.items[1]
    if binding.kind != .Vector || len(binding.items) != 1 || binding.items[0].kind != .Symbol {
        return Compile_Error{message = "with-temp-allocator expects [name] binding", span = binding.span}, false
    }
    allocator_name := map_name(binding.items[0].text)

    e.temp_counter += 1
    temp_scope := fmt.tprintf("kvist_temp_scope_%d", e.temp_counter)
    e.temp_counter += 1
    old_allocator := fmt.tprintf("kvist_old_allocator_%d", e.temp_counter)

    emit_line(e, "{")
    e.indent += 1
    push_local_type_scope(e)
    emit_line(e, fmt.tprintf("%s := runtime.default_temp_allocator_temp_begin()", temp_scope))
    emit_line(e, fmt.tprintf("defer runtime.default_temp_allocator_temp_end(%s)", temp_scope))
    emit_line(e, fmt.tprintf("%s := context.temp_allocator", allocator_name))
    emit_line(e, fmt.tprintf("%s := context.allocator", old_allocator))
    emit_line(e, fmt.tprintf("context.allocator = %s", allocator_name))
    emit_line(e, fmt.tprintf("defer context.allocator = %s", old_allocator))

    body: [dynamic]CST_Form
    for item in form.items[2:] {
        append(&body, item)
    }
    err_escape, bad_escape := with_temp_allocator_escape_error(e, body[:], last_in_proc, returns)
    if bad_escape {
        return err_escape, false
    }
    err_body, ok_body := emit_body_forms(
        e,
        body[:],
        returns_when_final(last_in_proc, returns),
        discard_result,
    )
    pop_local_type_scope(e)
    if !ok_body {
        return err_body, false
    }

    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

case_type_payload_pattern :: proc(clause: CST_Form) -> (ty, binding: string, ignored: bool, err: Compile_Error, ok: bool) {
    if clause.kind != .List {
        return "", "", false, Compile_Error{message = "type-case expects (Type binding)", span = clause.span}, false
    }
    if len(clause.items) != 2 || clause.items[0].kind != .Symbol || clause.items[1].kind != .Symbol {
        return "", "", false, Compile_Error{message = "type-case expects (Type binding)", span = clause.span}, false
    }
    ty = map_name(clause.items[0].text)
    binding = map_name(clause.items[1].text)
    ignored = clause.items[1].text == "_"
    return ty, binding, ignored, {}, true
}

emit_case_type_payload_stmt :: proc(
    e: ^Emitter,
    form: CST_Form,
    last_in_proc: bool,
    returns: Return_Spec,
    discard_result := false,
) -> (Compile_Error, bool) {
    if len(form.items) < 5 {
        return Compile_Error{message = "case expects subject, clause/body pairs, and default", span = form.span}, false
    }
    if len(form.items)%2 == 0 {
        return Compile_Error{message = "case expects clause/body pairs followed by default", span = form.span}, false
    }

    subject, err_subject, ok_subject := emit_expr(e, form.items[1])
    if !ok_subject {
        return err_subject, false
    }

    temp := fmt.tprintf("kvist_case_%d", e.temp_counter + 1)
    e.temp_counter += 1

    emit_indent(e)
    strings.write_string(&e.builder, "switch ")
    strings.write_string(&e.builder, temp)
    strings.write_string(&e.builder, " in ")
    strings.write_string(&e.builder, subject)
    record_current_line_fragment_map(e, len("switch ") + len(temp) + len(" in "), subject, form.items[1].span)
    strings.write_string(&e.builder, " {")
    emit_raw_newline(e)

    branch_returns := returns_when_final(last_in_proc, returns)
    i := 2
    for i < len(form.items)-1 {
        clause := form.items[i]
        body := form.items[i+1]

        ty, binding, ignored, err_pattern, ok_pattern := case_type_payload_pattern(clause)
        if !ok_pattern {
            return err_pattern, false
        }

        emit_line_mapped(e, fmt.tprintf("case %s:", ty), clause.span)
        e.indent += 1
        push_local_type_scope(e)
        if !ignored {
            emit_line(e, fmt.tprintf("%s := %s", binding, temp))
            bind_local_type(e, binding, ty)
        }
        err_body, ok_body := emit_stmt(
            e,
            body,
            last_in_proc,
            branch_returns,
            discard_result,
        )
        pop_local_type_scope(e)
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1

        i += 2
    }

    default_form := form.items[len(form.items)-1]
    emit_line_mapped(e, "case:", default_form.span)
    e.indent += 1
    err_default, ok_default := emit_stmt(
        e,
        default_form,
        last_in_proc,
        branch_returns,
        discard_result,
    )
    if !ok_default {
        return err_default, false
    }
    e.indent -= 1

    emit_line(e, "}")
    return {}, true
}

emit_case_stmt :: proc(
    e: ^Emitter,
    form: CST_Form,
    last_in_proc: bool,
    returns: Return_Spec,
    discard_result := false,
) -> (Compile_Error, bool) {
    if len(form.items) >= 4 {
        i := 2
        for i < len(form.items)-1 {
            if form.items[i].kind != .List {
                return Compile_Error{message = "type-case expects (Type binding)", span = form.items[i].span}, false
            }
            i += 2
        }
    }
    return emit_case_type_payload_stmt(
        e,
        form,
        last_in_proc,
        returns,
        discard_result,
    )
}

emit_stmt :: proc(
    e: ^Emitter,
    form: CST_Form,
    last_in_proc: bool,
    returns: Return_Spec,
    discard_result := false,
) -> (Compile_Error, bool) {
    if form.kind != .List {
        expr: string
        err_expr: Compile_Error
        ok_expr: bool
        if last_in_proc && returns.kind == .Single {
            expr, err_expr, ok_expr = emit_expr_for_expected_type(e, form, returns.single_ty)
        } else {
            expr, err_expr, ok_expr = emit_expr(e, form)
        }
        if !ok_expr {
            return err_expr, false
        }
        if last_in_proc && returns.kind != .None {
            expr = managed_return_value_text(e, form, expr, returns)
            emit_prefixed_expr_mapped(e, "return ", expr, form.span)
        } else if form_is_owned_allocation_result(form) ||
                  form_is_owned_constructor_result(form) ||
                  discard_result {
            emit_discarded_expr(e, form, expr)
        } else {
            emit_prefixed_expr_mapped(e, "", expr, form.span)
        }
        return {}, true
    }

    if len(form.items) == 0 {
        return Compile_Error{message = "empty list statement", span = form.span}, false
    }

    head := form.items[0]
    if head.kind != .Symbol {
        expr: string
        err_expr: Compile_Error
        ok_expr: bool
        if last_in_proc && returns.kind == .Single {
            expr, err_expr, ok_expr = emit_expr_for_expected_type(e, form, returns.single_ty)
        } else {
            expr, err_expr, ok_expr = emit_expr(e, form)
        }
        if !ok_expr {
            return err_expr, false
        }
        if last_in_proc && returns.kind != .None {
            expr = managed_return_value_text(e, form, expr, returns)
            emit_prefixed_expr_mapped(e, "return ", expr, form.span)
        } else if form_is_owned_allocation_result(form) ||
                  form_is_owned_constructor_result(form) ||
                  discard_result {
            emit_discarded_expr(e, form, expr)
        } else {
            emit_prefixed_expr_mapped(e, "", expr, form.span)
        }
        return {}, true
    }

    if head.text == "var" {
        return Compile_Error{message = "`var` has been removed; use `defvar`", span = head.span}, false
    }

    if head.text == "defvar" {
        return emit_local_var_stmt(e, form)
    }

    if is_local_decl_head(head.text) {
        return emit_local_decl_stmt(e, form)
    }

    if head.text == REPL_IGNORE_RESULT_HEAD {
        if len(form.items) != 2 {
            return Compile_Error{
                message = "internal REPL result discard expects one form",
                span = form.span,
            }, false
        }
        return emit_eval_intermediate_stmt(e, form.items[1])
    }

    switch builtin_macro_kind(head.text) {
    case .With_Allocator:
        return emit_with_allocator_stmt(
            e,
            form,
            last_in_proc,
            returns,
            discard_result,
        )
    case .With_Temp_Allocator:
        return emit_with_temp_allocator_stmt(
            e,
            form,
            last_in_proc,
            returns,
            discard_result,
        )
    case .None:
    }

    switch head.text {
    case "zero":
        if last_in_proc && returns.kind == .Single {
            value, err_value, ok_value := emit_expr_for_expected_type(e, form, returns.single_ty)
            if !ok_value {
                return err_value, false
            }
            value = managed_return_value_text(e, form, value, returns)
            emit_prefixed_expr_mapped(e, "return ", value, form.span)
            return {}, true
        }
        return validate_zero_stmt(form)
    case "inc!", "dec!", "toggle!", "negate!":
        return emit_unary_mutation_stmt(e, form, head.text)
    case "mut!":
        return emit_mut_bang_stmt(e, form)
    }

    canonical_head_text := head.text
    canonical_head, _, err_head, ok_head := resolve_kvist_head(e, head.text)
    if !ok_head {
        return err_head, false
    }
    canonical_head_text = canonical_head

    switch canonical_head_text {
    case "#partial":
        return Compile_Error{message = "#partial is not Kvist syntax; use case or cond", span = form.span}, false
    case "let":
        if len(form.items) < 3 {
            return Compile_Error{message = "let expects bindings and body", span = form.span}, false
        }
        bindings, err_bind, ok_bind := parse_let_bindings(form.items[1])
        if !ok_bind {
            return err_bind, false
        }
        err_tail, bad_tail := let_errdefer_tail_error(bindings[:], last_in_proc)
        if bad_tail {
            return err_tail, false
        }
        body: [dynamic]CST_Form
        for item in form.items[2:] {
            append(&body, item)
        }
        if last_in_proc && returns.kind != .None {
            err_let_return, bad_let_return := let_return_error(e, bindings[:], body[:])
            if bad_let_return {
                return err_let_return, false
            }
            err_let_defer_return, bad_let_defer_return :=
                let_defer_return_error(
                    e,
                    bindings[:],
                    body[:],
                    last_in_proc,
                    returns,
                )
            if bad_let_defer_return {
                return err_let_defer_return, false
            }
        }
        push_local_type_scope(e)
        defer pop_local_type_scope(e)
        scoped := !last_in_proc
        if scoped {
            emit_line(e, "{")
            e.indent += 1
        }
        for binding in bindings {
            managed := false
            managed_ty := ""
            if binding_is_native_sequence_destructure(e, binding) {
                err_native, ok_native := emit_native_sequence_let_binding(e, binding)
                if !ok_native {
                    return err_native, false
                }
            } else if binding_is_data_destructure(e, binding) {
                err_data, ok_data := emit_data_let_binding(e, binding)
                if !ok_data {
                    return err_data, false
                }
            } else if binding_value_is_let(binding) {
                err_flat, ok_flat := emit_let_value_binding_assignment(e, binding)
                if !ok_flat {
                    return err_flat, false
                }
            } else {
                value: string
                err_value: Compile_Error
                ok_value: bool
                if form_has_nested_owned_value(binding.value, e) {
                    value, err_value, ok_value = emit_expr_with_owned_nested_temps(e, binding.value)
                } else {
                    err_owned, bad_owned := owned_result_usage_error(binding.value, true, e)
                    if bad_owned {
                        return err_owned, false
                    }
                    value, err_value, ok_value = emit_expr_for_expected_type(e, binding.value, binding.ty)
                }
                if !ok_value {
                    return err_value, false
                }
                value, managed_ty, managed = managed_binding_value_text(e, binding, value)
                if binding.is_result_binding && binding.or_modifier == "or-return" {
                    if !named_returns_match_binding_pattern(returns, binding.pattern[:]) {
                        return Compile_Error{
                            message = ":or-return currently requires proc named returns matching the binding names exactly",
                            span = binding.value.span,
                        }, false
                    }
                    emit_result_binding_named_return_assignment(e, binding, value)
                } else {
                    emit_binding_assignment(e, binding, value)
                    emit_managed_destructure_cleanup(e, binding)
                }
            }
            err_guard, ok_guard := emit_result_binding_guard(e, binding, returns)
            if !ok_guard {
                return err_guard, false
            }
            if binding.deferred_delete {
                err_defer, ok_defer := emit_binding_deferred_delete(e, binding)
                if !ok_defer {
                    return err_defer, false
                }
            }
            if binding.defer_with_cleanup {
                err_defer, ok_defer := emit_binding_defer_with_cleanup(e, binding)
                if !ok_defer {
                    return err_defer, false
                }
            }
            if binding.err_deferred_delete {
                err_defer, ok_defer := emit_binding_err_deferred_delete(e, binding)
                if !ok_defer {
                    return err_defer, false
                }
            }
            bind_obvious_binding_types(e, binding)
            if managed &&
               !binding.deferred_delete &&
               !binding.err_deferred_delete &&
               !binding.defer_with_cleanup &&
               !body_deletes_name(body[:], binding.name) {
                owner_flag := managed_owner_flag_name(e)
                emit_line(e, fmt.tprintf("%s := true", owner_flag))
                emit_line(e, fmt.tprintf(
                    "defer (proc(kvist_place: ^%s, kvist_owner: ^bool) {{ if kvist_owner^ {{ %s }} }})(&%s, &%s)",
                    managed_ty,
                    ownership_destroy_value_text(e, managed_ty, "kvist_place^"),
                    binding.name,
                    owner_flag,
                ))
                bind_managed_local_owner(e, binding.name, owner_flag)
            }
        }
        err_body, ok_body := emit_body_forms(
            e,
            body[:],
            returns_when_final(last_in_proc, returns),
            discard_result,
        )
        if !ok_body {
            return err_body, false
        }
        if scoped {
            e.indent -= 1
            emit_line(e, "}")
        }
        return {}, true
    case "do", "block":
        emit_line(e, "{")
        e.indent += 1
        push_local_type_scope(e)
        body: [dynamic]CST_Form
        for item in form.items[1:] {
            append(&body, item)
        }
        err_body, ok_body := emit_body_forms(
            e,
            body[:],
            returns_when_final(last_in_proc, returns),
            discard_result,
        )
        pop_local_type_scope(e)
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "if":
        return emit_if_like(
            e,
            "if",
            form,
            last_in_proc,
            returns,
            discard_result,
        )
    case "type-case":
        return emit_case_stmt(
            e,
            form,
            last_in_proc,
            returns,
            discard_result,
        )
    case "match":
        return emit_match_stmt(
            e,
            form,
            last_in_proc,
            returns,
            discard_result,
        )
    case "switch":
        return Compile_Error{message = "`switch` has been removed; use `case` for subject dispatch or `cond` for predicate branches", span = head.span}, false
    case "return":
        return_context := returns
        if return_context.kind == .None {
            return_context = e.current_proc_returns
        }
        if len(form.items) == 1 {
            emit_line(e, "return")
            return {}, true
        }
        if len(form.items) == 2 {
            err_owned, bad_owned := owned_result_usage_error(form.items[1], true, e)
            if bad_owned {
                return err_owned, false
            }
            value: string
            err_value: Compile_Error
            ok_value: bool
            if form_has_nested_owned_value(form.items[1], e) {
                value, err_value, ok_value = emit_expr_with_owned_nested_temps(e, form.items[1])
            } else if return_context.kind == .Single {
                value, err_value, ok_value = emit_expr_for_expected_type(e, form.items[1], return_context.single_ty)
            } else if return_context.kind == .Named && len(return_context.named) == 1 {
                value, err_value, ok_value = emit_expr_for_expected_type(e, form.items[1], return_context.named[0].ty)
            } else {
                value, err_value, ok_value = emit_expr(e, form.items[1])
            }
            if !ok_value {
                return err_value, false
            }
            value = managed_return_value_text(e, form.items[1], value, return_context)
            emit_prefixed_expr_mapped(e, "return ", value, form.items[1].span)
            return {}, true
        }
        line_builder := strings.builder_make()
        defer strings.builder_destroy(&line_builder)
        strings.write_string(&line_builder, "return ")
        for item, idx in form.items[1:] {
            if idx > 0 {
                strings.write_string(&line_builder, ", ")
            }
            err_owned, bad_owned := owned_result_usage_error(item, true, e)
            if bad_owned {
                return err_owned, false
            }
            value: string
            err_value: Compile_Error
            ok_value: bool
            if return_context.kind == .Named && idx < len(return_context.named) {
                value, err_value, ok_value = emit_expr_for_expected_type(e, item, return_context.named[idx].ty)
            } else {
                value, err_value, ok_value = emit_expr(e, item)
            }
            if !ok_value {
                return err_value, false
            }
            if return_context.kind == .Named && idx < len(return_context.named) {
                value = managed_return_value_text_for_type(e, item, value, return_context.named[idx].ty)
            }
            strings.write_string(&line_builder, value)
        }
        emit_line_mapped(e, strings.clone(strings.to_string(line_builder)), form.items[1].span)
        return {}, true
    case "discard":
        if len(form.items) < 2 {
            return Compile_Error{message = "discard expects at least one expression", span = form.span}, false
        }
        for item in form.items[1:] {
            if !form_produces_owned_value(item, e) {
                err_owned, bad_owned := owned_result_usage_error(item, false, e)
                if bad_owned {
                    return err_owned, false
                }
            }
            expr, err_expr, ok_expr := emit_expr(e, item)
            if !ok_expr {
                return err_expr, false
            }
            emit_discarded_expr(e, item, expr)
        }
        return {}, true
    case "kvist-intrinsic-restart-case":
        if len(form.items) < 2 {
            return Compile_Error{
                message = "condition.restart-case expects a body",
                span = form.span,
            }, false
        }
        label :=
            fmt.tprintf("kvist_debug_restart_case_%d", e.temp_counter)
        e.temp_counter += 1
        emit_line(e, fmt.tprintf("%s: for %c", label, '{'))
        e.indent += 1
        push_local_type_scope(e)
        append(
            &e.debug_restart_contexts,
            Debug_Restart_Context{
                label = label,
                restart_flags = 4 | 8,
            },
        )
        body: [dynamic]CST_Form
        for item in form.items[1:] {
            append(&body, item)
        }
        err_body, ok_body :=
            emit_body_forms(e, body[:], Return_Spec{kind = .None})
        resize(
            &e.debug_restart_contexts,
            len(e.debug_restart_contexts)-1,
        )
        pop_local_type_scope(e)
        if !ok_body {
            return err_body, false
        }
        emit_line(e, fmt.tprintf("break %s", label))
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "kvist-intrinsic-condition-operation":
        if len(form.items) < 2 {
            return Compile_Error{
                message = "condition.operation expects a body",
                span = form.span,
            }, false
        }
        label :=
            fmt.tprintf("kvist_debug_operation_%d", e.temp_counter)
        e.temp_counter += 1
        emit_line(e, fmt.tprintf("%s: for %c", label, '{'))
        e.indent += 1
        push_local_type_scope(e)
        append(
            &e.debug_restart_contexts,
            Debug_Restart_Context{
                label = label,
                restart_flags = 16,
            },
        )
        body: [dynamic]CST_Form
        for item in form.items[1:] {
            append(&body, item)
        }
        err_body, ok_body :=
            emit_body_forms(e, body[:], Return_Spec{kind = .None})
        resize(
            &e.debug_restart_contexts,
            len(e.debug_restart_contexts)-1,
        )
        pop_local_type_scope(e)
        if !ok_body {
            return err_body, false
        }
        emit_line(e, fmt.tprintf("break %s", label))
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "kvist-intrinsic-breakpoint":
        if len(form.items) != 1 {
            return Compile_Error{
                message = "debug.break does not take arguments",
                span = form.span,
            }, false
        }
        if !e.repl_debug_enabled {
            return Compile_Error{
                message = "debug.break is available only in a native REPL generation",
                span = form.span,
            }, false
        }
        debug_emit_pause(e, form, true)
        return {}, true
    case "kvist-intrinsic-signal-condition":
        if len(form.items) != 6 {
            return Compile_Error{
                message =
                    "condition.signal expects type, message, and Data context",
                span = form.span,
            }, false
        }
        dispatch, err_dispatch, ok_dispatch := emit_expr(e, form.items[1])
        if !ok_dispatch {
            return err_dispatch, false
        }
        unhandled, err_unhandled, ok_unhandled := emit_expr(e, form.items[2])
        if !ok_unhandled {
            return err_unhandled, false
        }
        type_form := form.items[3]
        condition_type := ""
        owned_condition_type := ""
        defer delete(owned_condition_type)
        if type_form.kind != .Keyword &&
           type_form.kind != .String {
            return Compile_Error{
                message =
                    "condition.signal type must be a keyword or string literal",
                span = type_form.span,
            }, false
        }
        if type_form.kind == .String {
            owned_condition_type =
                unquote_string(type_form.text)
            condition_type = owned_condition_type
        } else {
            condition_type = type_form.text
            if len(condition_type) > 0 &&
               condition_type[0] == ':' {
                condition_type = condition_type[1:]
            }
        }
        if condition_type == "" {
            return Compile_Error{
                message =
                    "condition.signal type must not be empty",
                span = type_form.span,
            }, false
        }
        message, err_message, ok_message :=
            emit_expr_for_expected_type(
                e,
                form.items[4],
                "string",
            )
        if !ok_message {
            return err_message, false
        }
        message_name :=
            fmt.tprintf("kvist_condition_message_%d", e.temp_counter)
        e.temp_counter += 1
        emit_prefixed_expr_mapped(
            e,
            fmt.tprintf("%s: string = ", message_name),
            message,
            form.items[4].span,
        )
        if form_is_owned_result(form.items[4], e) {
            emit_line(e, fmt.tprintf("defer delete(%s)", message_name))
        }
        mark_data_type(e)
        condition_data, err_data, ok_data :=
            emit_expr_for_expected_type(e, form.items[5], "Data")
        if !ok_data {
            return err_data, false
        }
        data_name :=
            fmt.tprintf("kvist_condition_data_%d", e.temp_counter)
        e.temp_counter += 1
        data_text := condition_data
        if !form_produces_owned_managed_type(e, form.items[5], "Data") {
            data_text = emit_call_text(
                "kvist_data_retain",
                []string{condition_data},
            )
        }
        emit_prefixed_expr_mapped(
            e,
            fmt.tprintf("%s := ", data_name),
            data_text,
            form.items[5].span,
        )
        emit_line(e, fmt.tprintf("defer kvist_data_release(%s)", data_name))
        restart_flags: u32 = 1
        if len(e.debug_restart_contexts) > 0 {
            restart_flags |=
                e.debug_restart_contexts[
                    len(e.debug_restart_contexts)-1
                ].restart_flags
        }
        decision_name :=
            fmt.tprintf("kvist_condition_decision_%d", e.temp_counter)
        e.temp_counter += 1
        if form.items[1].kind == .Nil {
            emit_line(
                e,
                fmt.tprintf(
                    "%s := struct %c handled: bool, restart, value: string %c%c%c",
                    decision_name,
                    '{',
                    '}',
                    '{',
                    '}',
                ),
            )
        } else {
            emit_line(
                e,
                fmt.tprintf(
                    "%s := %s(%q, %s, %s, u32(%d))",
                    decision_name,
                    dispatch,
                    condition_type,
                    message_name,
                    data_name,
                    restart_flags,
                ),
            )
        }
        if len(e.debug_restart_contexts) == 0 {
            if e.repl_debug_enabled {
                emit_line(e, fmt.tprintf("if !%s.handled %c", decision_name, '{'))
                e.indent += 1
                // The intrinsic is introduced by condition.signal's macro,
                // whose own span belongs to the package that defines the
                // macro. The condition type is a spliced caller form and
                // therefore carries the signalling source location.
                pause_form := form
                pause_form.span = form.items[3].span
                debug_emit_pause(
                    e,
                    pause_form,
                    true,
                    message_name,
                    condition_data = data_name,
                    condition_type = condition_type,
                )
                e.indent -= 1
                emit_line(e, "}")
            } else {
                emit_line(
                    e,
                    fmt.tprintf(
                        "if !%s.handled %c %s(%q, %s) %c",
                        decision_name,
                        '{',
                        unhandled,
                        condition_type,
                        message_name,
                        '}',
                    ),
                )
            }
            return {}, true
        }
        selected_name :=
            fmt.tprintf("kvist_restart_name_%d", e.temp_counter)
        e.temp_counter += 1
        emit_line(e, fmt.tprintf("%s := %s.restart", selected_name, decision_name))
        if e.repl_debug_enabled {
            selection_name :=
                fmt.tprintf("kvist_restart_selection_%d", e.temp_counter)
            e.temp_counter += 1
            emit_line(
                e,
                fmt.tprintf(
                    "%s: Kvist_Repl_Restart_Selection",
                    selection_name,
                ),
            )
            emit_line(e, fmt.tprintf("if !%s.handled %c", decision_name, '{'))
            e.indent += 1
            debug_emit_pause(
                e,
                form,
                true,
                condition_message = message_name,
                condition_data = data_name,
                restart_selection_name = selection_name,
                condition_restart_flags = restart_flags,
                condition_type = condition_type,
            )
            selected_from_client :=
                debug_emit_selected_restart_name(e, selection_name)
            emit_line(e, fmt.tprintf("%s = %s", selected_name, selected_from_client))
            e.indent -= 1
            emit_line(e, "}")
        } else {
            emit_line(
                e,
                fmt.tprintf(
                    "if !%s.handled %c %s(%q, %s) %c",
                    decision_name,
                    '{',
                    unhandled,
                    condition_type,
                    message_name,
                    '}',
                ),
            )
        }
        debug_emit_restart_case_branch(e, selected_name)
        return {}, true
    case "kvist-intrinsic-use-value-restart":
        if len(form.items) != 5 {
            return Compile_Error{
                message =
                    "condition.use-value! expects a mutable local and one string literal",
                span = form.span,
            }, false
        }
        dispatch, err_dispatch, ok_dispatch := emit_expr(e, form.items[1])
        if !ok_dispatch {
            return err_dispatch, false
        }
        unhandled, err_unhandled, ok_unhandled := emit_expr(e, form.items[2])
        if !ok_unhandled {
            return err_unhandled, false
        }
        if form.items[3].kind != .Symbol {
            return Compile_Error{
                message =
                    "condition.use-value! target must be a mutable local",
                span = form.items[3].span,
            }, false
        }
        if form.items[4].kind != .String {
            return Compile_Error{
                message =
                    "condition.use-value! currently expects a string literal message",
                span = form.items[4].span,
            }, false
        }
        target_name := map_name(form.items[3].text)
        target_type := ""
        target_mutable := false
        for i := len(e.local_types)-1; i >= 0; i -= 1 {
            if e.local_types[i].name == target_name {
                target_type = e.local_types[i].ty
                target_mutable = e.local_types[i].mutable
                break
            }
        }
        if target_type == "" || !target_mutable {
            return Compile_Error{
                message =
                    "condition.use-value! target must be a visible mutable local",
                span = form.items[3].span,
            }, false
        }
        if target_type != "int" &&
           target_type != "bool" &&
           target_type != "f32" &&
           target_type != "f64" &&
           target_type != "string" {
            return Compile_Error{
                message =
                    "condition.use-value! currently supports mutable int, bool, f32, f64, and string locals",
                span = form.items[3].span,
            }, false
        }
        message, err_message, ok_message :=
            emit_expr_for_expected_type(e, form.items[4], "string")
        if !ok_message {
            return err_message, false
        }
        restart_flags: u32 = 1 | 2
        if len(e.debug_restart_contexts) > 0 {
            restart_flags |=
                e.debug_restart_contexts[
                    len(e.debug_restart_contexts)-1
                ].restart_flags
        }
        decision_name :=
            fmt.tprintf("kvist_condition_decision_%d", e.temp_counter)
        e.temp_counter += 1
        if form.items[1].kind == .Nil {
            emit_line(
                e,
                fmt.tprintf(
                    "%s := struct %c handled: bool, restart, value: string %c%c%c",
                    decision_name,
                    '{',
                    '}',
                    '{',
                    '}',
                ),
            )
        } else {
            emit_line(
                e,
                fmt.tprintf(
                    "%s := %s(%q, %s, Data%c%c, u32(%d))",
                    decision_name,
                    dispatch,
                    "kvist/condition",
                    message,
                    '{',
                    '}',
                    restart_flags,
                ),
            )
        }
        selected_name :=
            fmt.tprintf("kvist_restart_name_%d", e.temp_counter)
        e.temp_counter += 1
        emit_line(e, fmt.tprintf("%s := %s.restart", selected_name, decision_name))
        selected_value :=
            fmt.tprintf("kvist_restart_value_%d", e.temp_counter)
        e.temp_counter += 1
        emit_line(e, fmt.tprintf("%s := %s.value", selected_value, decision_name))
        if e.repl_debug_enabled {
            selection_name :=
                fmt.tprintf("kvist_restart_selection_%d", e.temp_counter)
            e.temp_counter += 1
            emit_line(
                e,
                fmt.tprintf(
                    "%s: Kvist_Repl_Restart_Selection",
                    selection_name,
                ),
            )
            emit_line(e, fmt.tprintf("if !%s.handled %c", decision_name, '{'))
            e.indent += 1
            debug_emit_pause(
                e,
                form,
                true,
                condition_message = message,
                condition_value_type = target_type,
                restart_selection_name = selection_name,
                condition_restart_flags = restart_flags,
            )
            selected_from_client :=
                debug_emit_selected_restart_name(e, selection_name)
            emit_line(e, fmt.tprintf("%s = %s", selected_name, selected_from_client))
            emit_line(
                e,
                fmt.tprintf(
                    "%s = string(%s.value.data[:%s.value.length])",
                    selected_value,
                    selection_name,
                    selection_name,
                ),
            )
            e.indent -= 1
            emit_line(e, "}")
        } else {
            emit_line(
                e,
                fmt.tprintf(
                    "if !%s.handled %c %s(%q, %s) %c",
                    decision_name,
                    '{',
                    unhandled,
                    "kvist/condition",
                    message,
                    '}',
                ),
            )
        }
        debug_emit_restart_case_branch(e, selected_name)
        emit_line(
            e,
            fmt.tprintf(
                "if %s == \"use-value\" %c",
                selected_name,
                '{',
            ),
        )
        e.indent += 1
        if target_type == "int" ||
           target_type == "f32" ||
           target_type == "f64" {
            parsed_name :=
                fmt.tprintf("kvist_restart_parsed_%d", e.temp_counter)
            e.temp_counter += 1
            ok_name :=
                fmt.tprintf("kvist_restart_ok_%d", e.temp_counter)
            e.temp_counter += 1
            emit_line(
                e,
                fmt.tprintf(
                    "%s, %s := kvist_condition_strconv.parse_%s(%s)",
                    parsed_name,
                    ok_name,
                    target_type,
                    selected_value,
                ),
            )
            emit_line(
                e,
                fmt.tprintf(
                    "assert(%s, \"invalid %s use-value restart payload\")",
                    ok_name,
                    target_type,
                ),
            )
            emit_line(
                e,
                fmt.tprintf("%s = %s", target_name, parsed_name),
            )
        } else if target_type == "bool" {
            emit_line(
                e,
                fmt.tprintf(
                    "assert(%s == \"true\" || %s == \"false\", \"invalid bool use-value restart payload\")",
                    selected_value,
                    selected_value,
                ),
            )
            emit_line(
                e,
                fmt.tprintf(
                    "%s = %s == \"true\"",
                    target_name,
                    selected_value,
                ),
            )
        } else {
            emit_line(
                e,
                fmt.tprintf("%s = %s", target_name, selected_value),
            )
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "break":
        if len(form.items) != 1 {
            return Compile_Error{message = "break does not take arguments", span = form.span}, false
        }
        emit_line(e, "break")
        return {}, true
    case "continue":
        if len(form.items) != 1 {
            return Compile_Error{message = "continue does not take arguments", span = form.span}, false
        }
        emit_line(e, "continue")
        return {}, true
    case "defer":
        if len(form.items) < 2 {
            return Compile_Error{message = "defer expects a body", span = form.span}, false
        }
        // Deferred cleanup runs while leaving a scope, including while a
        // debugger abort is already unwinding it. A safe point here could
        // pause during cleanup and its cooperative abort return would be
        // illegal inside Odin's defer statement.
        previous_repl_debug_enabled := e.repl_debug_enabled
        e.repl_debug_enabled = false
        defer e.repl_debug_enabled = previous_repl_debug_enabled
        if len(form.items) == 2 {
            deferred := form.items[1]
            if deferred.kind == .List && len(deferred.items) > 0 && deferred.items[0].kind == .Symbol {
                switch deferred.items[0].text {
                case "if", "cond", "type-case", "let", "do":
                case:
                    expr, err_expr, ok_expr := emit_expr(e, deferred)
                    if !ok_expr {
                        return err_expr, false
                    }
                    emit_prefixed_expr_mapped(e, "defer ", expr, deferred.span)
                    return {}, true
                }
            } else {
                expr, err_expr, ok_expr := emit_expr(e, deferred)
                if !ok_expr {
                    return err_expr, false
                }
                emit_prefixed_expr_mapped(e, "defer ", expr, deferred.span)
                return {}, true
            }
        }
        emit_line(e, "defer {")
        e.indent += 1
        body: [dynamic]CST_Form
        for item in form.items[1:] {
            append(&body, item)
        }
        err_body, ok_body := emit_body_forms(e, body[:], Return_Spec{kind = .None})
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "set!":
        if len(form.items) != 3 {
            return Compile_Error{message = "set! expects place and value", span = form.span}, false
        }
        if !form_is_assignable_place(form.items[1]) {
            return Compile_Error{message = "set! expects an assignable place", span = form.items[1].span}, false
        }
        if err_immutable, immutable := immutable_def_mutation_error(e, form.items[1]); immutable {
            return err_immutable, false
        }
        lhs, err_lhs, ok_lhs := emit_expr(e, form.items[1])
        if !ok_lhs {
            return err_lhs, false
        }
        err_owned, bad_owned := owned_result_usage_error(form.items[2], true, e)
        if bad_owned {
            return err_owned, false
        }
        rhs: string
        err_rhs: Compile_Error
        ok_rhs: bool
        place_ty, has_place_ty := obvious_form_type(e, form.items[1])
        is_repl_dynamic_place :=
            form.items[1].kind == .Symbol &&
            name_in_list(e.repl_var_names, map_name(form.items[1].text)) &&
            has_place_ty &&
            type_text_is_dynamic_array(place_ty)
        if has_place_ty &&
           (type_text_has_owned_lifecycle(e, place_ty) ||
            is_repl_dynamic_place) {
            rhs, err_rhs, ok_rhs =
                emit_expr_for_expected_type(e, form.items[2], place_ty)
        } else if form_has_nested_owned_value(form.items[2], e) {
            rhs, err_rhs, ok_rhs = emit_expr_with_owned_nested_temps(e, form.items[2])
        } else {
            rhs, err_rhs, ok_rhs = emit_expr(e, form.items[2])
        }
        if !ok_rhs {
            return err_rhs, false
        }
        moves_tracked_local: bool
        rhs, moves_tracked_local = assignment_move_tracked_local_text(
            e,
            form.items[1],
            form.items[2],
            rhs,
        )
        if assignment, managed := managed_assignment_text(
            e,
            form.items[1],
            form.items[2],
            lhs,
            rhs,
            moves_tracked_local,
        ); managed {
            emit_prefixed_expr_mapped(e, "", assignment, form.span)
            return {}, true
        }
        emit_indent(e)
        strings.write_string(&e.builder, lhs)
        record_current_line_fragment_map(e, 0, lhs, form.items[1].span)
        strings.write_string(&e.builder, " = ")
        strings.write_string(&e.builder, rhs)
        record_current_line_fragment_map(e, len(lhs) + len(" = "), rhs, form.items[2].span)
        emit_raw_newline(e)
        return {}, true
    case "loop":
        return Compile_Error{message = "`loop` has been removed; use `for` for collection iteration or `while` for condition loops", span = form.span}, false
    case "each":
        return Compile_Error{message = "`each` has been removed; use `for` for collection iteration", span = form.span}, false
    case "for":
        if len(form.items) >= 3 && form.items[1].kind == .Vector {
            binding := form.items[1]
            body_start := 2
            if len(binding.items) == 2 &&
               (binding.items[0].kind == .Vector || binding.items[0].kind == .Brace) {
                body: [dynamic]CST_Form
                for item in form.items[body_start:] {
                    append(&body, item)
                }
                return emit_for_data_pattern_loop(e, binding.items[0], binding.items[1], body[:])
            }
            if len(binding.items) == 3 &&
               binding.items[0].kind == .Symbol &&
               (binding.items[1].kind == .Vector || binding.items[1].kind == .Brace) {
                body: [dynamic]CST_Form
                for item in form.items[body_start:] {
                    append(&body, item)
                }
                return emit_for_data_pattern_loop(
                    e,
                    binding.items[1],
                    binding.items[2],
                    body[:],
                    map_name(binding.items[0].text),
                )
            }
            if len(binding.items) == 4 &&
               binding.items[0].kind == .Symbol &&
               binding.items[2].kind == .Keyword &&
               binding.items[2].text == ":transform" {
                value_name := map_name(binding.items[0].text)
                coll_form := binding.items[1]
                transform_form := binding.items[3]
                body: [dynamic]CST_Form
                for item in form.items[body_start:] {
                    append(&body, item)
                }
                if source, ok_source_call := source_call_decl(e, coll_form); ok_source_call {
                    return emit_transform_for_source_loop(e, coll_form, source, "", value_name, transform_form, body[:])
                }
                return emit_transform_for_collection_loop(e, coll_form, "", value_name, transform_form, body[:])
            }
            if len(binding.items) == 5 &&
               binding.items[0].kind == .Symbol &&
               binding.items[1].kind == .Symbol &&
               binding.items[3].kind == .Keyword &&
               binding.items[3].text == ":transform" {
                index_name := map_name(binding.items[0].text)
                value_name := map_name(binding.items[1].text)
                coll_form := binding.items[2]
                transform_form := binding.items[4]
                body: [dynamic]CST_Form
                for item in form.items[body_start:] {
                    append(&body, item)
                }
                if source, ok_source_call := source_call_decl(e, coll_form); ok_source_call {
                    return emit_transform_for_source_loop(e, coll_form, source, index_name, value_name, transform_form, body[:])
                }
                return emit_transform_for_collection_loop(e, coll_form, index_name, value_name, transform_form, body[:])
            }
            if len(binding.items) == 2 && binding.items[0].kind == .Symbol {
                value_name := map_name(binding.items[0].text)
                coll_form := binding.items[1]
                body: [dynamic]CST_Form
                for item in form.items[body_start:] {
                    append(&body, item)
                }
                if coll_ty, ok_coll_ty := obvious_form_type(e, coll_form); ok_coll_ty && coll_ty == "Data" {
                    return emit_for_data_pattern_loop(e, binding.items[0], coll_form, body[:])
                }
                if source, ok_source_call := source_call_decl(e, coll_form); ok_source_call {
                    return emit_source_each_loop(e, coll_form, source, value_name, "", body[:])
                }
                return emit_for_in_loop(e, coll_form, value_name, "", body[:])
            }
            if len(binding.items) == 3 && binding.items[0].kind == .Symbol && binding.items[1].kind == .Symbol {
                first_name := map_name(binding.items[0].text)
                second_name := map_name(binding.items[1].text)
                coll_form := binding.items[2]
                body: [dynamic]CST_Form
                for item in form.items[body_start:] {
                    append(&body, item)
                }
                if source, ok_source_call := source_call_decl(e, coll_form); ok_source_call {
                    return emit_source_each_loop(e, coll_form, source, first_name, second_name, body[:])
                }
                return emit_for_in_loop(e, coll_form, first_name, second_name, body[:])
            }
            return Compile_Error{message = fmt.tprintf("%s expects [value collection], [value collection :transform transform], [index value collection :transform transform], or [first second collection]", canonical_head_text), span = form.span}, false
        }
        return Compile_Error{message = "for expects [value collection], [value collection :transform transform], [index value collection :transform transform], or [first second collection] and body", span = form.span}, false
    case "while":
        if len(form.items) < 3 {
            return Compile_Error{message = "while expects condition and body", span = form.span}, false
        }
        cond, err_cond, ok_cond := emit_expr(e, form.items[1])
        if !ok_cond {
            return err_cond, false
        }
        emit_indent(e)
        strings.write_string(&e.builder, "for ")
        strings.write_string(&e.builder, cond)
        record_current_line_fragment_map(e, len("for "), cond, form.items[1].span)
        strings.write_string(&e.builder, " {")
        emit_raw_newline(e)
        e.indent += 1
        push_local_type_scope(e)
        body: [dynamic]CST_Form
        for item in form.items[2:] {
            append(&body, item)
        }
        err_body, ok_body := emit_body_forms(e, body[:], Return_Spec{kind = .None})
        pop_local_type_scope(e)
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "odin":
        raw, err_raw, ok_raw := emit_expr(e, form)
        if !ok_raw {
            return err_raw, false
        }
        emit_prefixed_expr(e, "", raw)
        return {}, true
    case:
        allow_root_owned := last_in_proc && returns.kind != .None
        if last_in_proc &&
           returns.kind != .None &&
           form_is_borrowed_view_result(form, e) &&
           borrowed_view_owner_has_nested_owned_value(e, form) {
            return Compile_Error{
                message = "cannot return a borrowed view that depends on an owned intermediate; bind the pipeline locally or return an owned result",
                span = form.span,
            }, false
        }
        if !(form_produces_owned_value(form, e) && !allow_root_owned) {
            err_owned, bad_owned := owned_result_usage_error(form, allow_root_owned, e)
            if bad_owned {
                return err_owned, false
            }
        }
        expr: string
        err_expr: Compile_Error
        ok_expr: bool
        if form_has_nested_owned_value(form, e) {
            expr, err_expr, ok_expr = emit_expr_with_owned_nested_temps(e, form)
        } else if last_in_proc && returns.kind == .Single {
            expr, err_expr, ok_expr = emit_expr_for_expected_type(e, form, returns.single_ty)
        } else {
            expr, err_expr, ok_expr = emit_expr(e, form)
        }
        if !ok_expr {
            return err_expr, false
        }
        if last_in_proc && returns.kind != .None {
            expr = managed_return_value_text(e, form, expr, returns)
            emit_prefixed_expr_mapped(e, "return ", expr, form.span)
        } else if form_is_owned_allocation_result(form) || form_is_owned_constructor_result(form) {
            emit_discarded_expr(e, form, expr)
        } else {
            emit_statement_expr(e, form, expr, discard_result)
        }
        if canonical_head_text == "delete" {
            for item in form.items[1:] {
                if item.kind == .Symbol {
                    name := map_name(item.text)
                    mark_debug_local_unavailable(e, name)
                    delete(name)
                }
            }
        }
        return {}, true
    }
}

emit_eval_print_expr :: proc(e: ^Emitter, form: CST_Form) -> (Compile_Error, bool) {
    if form_is_known_void_call(e, form) {
        err_stmt, ok_stmt := emit_stmt(
            e,
            form,
            false,
            Return_Spec{kind = .None},
        )
        if !ok_stmt {
            return err_stmt, false
        }
        emit_line_mapped(e, `fmt.println("nil")`, form.span)
        return {}, true
    }
    if form_is_owned_result(form, e) || form_is_owned_allocation_result(form) {
        value, err_value, ok_value := emit_expr(e, form)
        if !ok_value {
            return err_value, false
        }
        temp := eval_temp_name(e)
        emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), value, form.span)
        emit_line(e, fmt.tprintf("defer delete(%s)", temp))
        emit_line_mapped(e, fmt.tprintf("fmt.println(%s)", temp), form.span)
        return {}, true
    }

    value, err_value, ok_value := emit_expr(e, form)
    if !ok_value {
        return err_value, false
    }
    emit_line_mapped(e, fmt.tprintf("fmt.println(%s)", value), form.span)
    return {}, true
}

emit_eval_intermediate_stmt :: proc(
    e: ^Emitter,
    form: CST_Form,
) -> (Compile_Error, bool) {
    // A REPL batch evaluates every top-level runtime form but returns only the
    // final value.  Odin requires value-producing calls and expressions to be
    // handled explicitly, so discard intermediate values while leaving true
    // statement forms (including procedures with no return value) unchanged.
    return emit_stmt(
        e,
        form,
        false,
        Return_Spec{kind = .None},
        true,
    )
}

emit_eval_print_body :: proc(e: ^Emitter, body: []CST_Form) -> (Compile_Error, bool) {
    if len(body) == 0 {
        return Compile_Error{message = "eval print body is empty"}, false
    }
    for form, idx in body {
        last := idx == len(body)-1
        if last {
            return emit_eval_print_stmt(e, form)
        }
        err_stmt, ok_stmt := emit_stmt(e, form, false, Return_Spec{kind = .None})
        if !ok_stmt {
            return err_stmt, false
        }
    }
    return {}, true
}

emit_eval_print_stmt :: proc(e: ^Emitter, form: CST_Form) -> (Compile_Error, bool) {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return emit_eval_print_expr(e, form)
    }

    head := form.items[0].text
    switch head {
    case "let":
        if len(form.items) < 3 {
            return Compile_Error{message = "let expects bindings and body", span = form.span}, false
        }
        bindings, err_bind, ok_bind := parse_let_bindings(form.items[1])
        if !ok_bind {
            return err_bind, false
        }
        err_tail, bad_tail := let_errdefer_tail_error(bindings[:], false)
        if bad_tail {
            return err_tail, false
        }

        emit_line(e, "{")
        e.indent += 1
        push_local_type_scope(e)
        defer pop_local_type_scope(e)
        for binding in bindings {
            if binding_is_native_sequence_destructure(e, binding) {
                err_native, ok_native := emit_native_sequence_let_binding(e, binding)
                if !ok_native {
                    return err_native, false
                }
            } else if binding_is_data_destructure(e, binding) {
                err_data, ok_data := emit_data_let_binding(e, binding)
                if !ok_data {
                    return err_data, false
                }
            } else if binding_value_is_let(binding) {
                err_flat, ok_flat := emit_let_value_binding_assignment(e, binding)
                if !ok_flat {
                    return err_flat, false
                }
            } else {
                value: string
                err_value: Compile_Error
                ok_value: bool
                if form_has_nested_owned_value(binding.value, e) {
                    value, err_value, ok_value = emit_expr_with_owned_nested_temps(e, binding.value)
                } else {
                    err_owned, bad_owned := owned_result_usage_error(binding.value, true, e)
                    if bad_owned {
                        return err_owned, false
                    }
                    value, err_value, ok_value = emit_expr_for_expected_type(e, binding.value, binding.ty)
                }
                if !ok_value {
                    return err_value, false
                }
                emit_binding_assignment(e, binding, value)
            }
            bind_obvious_binding_types(e, binding)
        }
        err_body, ok_body := emit_eval_print_body(e, form.items[2:])
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "do":
        if len(form.items) < 2 {
            return Compile_Error{message = "do expects a body", span = form.span}, false
        }
        emit_line(e, "{")
        e.indent += 1
        err_body, ok_body := emit_eval_print_body(e, form.items[1:])
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "if":
        if len(form.items) < 3 || len(form.items) > 4 {
            return Compile_Error{message = "if expects test, then, and optional else", span = form.span}, false
        }
        test, err_test, ok_test := emit_expr(e, form.items[1])
        if !ok_test {
            return err_test, false
        }
        emit_indent(e)
        strings.write_string(&e.builder, "if ")
        strings.write_string(&e.builder, test)
        strings.write_string(&e.builder, " {")
        emit_raw_newline(e)
        e.indent += 1
        err_then, ok_then := emit_eval_print_stmt(e, form.items[2])
        if !ok_then {
            return err_then, false
        }
        e.indent -= 1
        emit_line(e, "}")
        if len(form.items) == 4 {
            emit_indent(e)
            strings.write_string(&e.builder, "else {")
            emit_raw_newline(e)
            e.indent += 1
            err_else, ok_else := emit_eval_print_stmt(e, form.items[3])
            if !ok_else {
                return err_else, false
            }
            e.indent -= 1
            emit_line(e, "}")
        }
        return {}, true
    }

    return emit_eval_print_expr(e, form)
}
