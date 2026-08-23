// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "base:runtime"

builtin_macro_kind :: proc(head: string) -> Builtin_Macro_Kind {
    switch head {
    case "with-allocator":
        return .With_Allocator
    case "with-temp-allocator":
        return .With_Temp_Allocator
    }
    return .None
}

macro_record_source_map :: proc(e: ^Macro_Expander, start_line, end_line: int, span: Span) {
    if e.source_map == nil || end_line < start_line {
        return
    }
    append(e.source_map, Source_Map_Entry{
        generated_start_line = start_line,
        generated_end_line   = end_line,
        source_span          = span,
    })
}

macro_emit_line :: proc(e: ^Macro_Expander, text: string, span: Span) {
    strings.write_string(&e.builder, text)
    strings.write_byte(&e.builder, '\n')
    macro_record_source_map(e, e.line, e.line, span)
    e.line += 1
}

macro_symbol :: proc(text: string, span: Span) -> CST_Form {
    return CST_Form{kind = .Symbol, text = text, span = span}
}

parse_macro_param_vector :: proc(form: CST_Form) -> (params: Macro_Param_Spec, err: Compile_Error, ok: bool) {
    if form.kind != .Vector {
        return params, Compile_Error{message = "defmacro expects a parameter vector", span = form.span}, false
    }
    i := 0
    for i < len(form.items) {
        item := form.items[i]
        if item.kind != .Symbol {
            return params, Compile_Error{message = "defmacro parameter must be a symbol", span = item.span}, false
        }
        if item.text == "&" {
            if params.has_rest || i+1 != len(form.items)-1 || form.items[i+1].kind != .Symbol {
                return params, Compile_Error{message = "defmacro rest parameters must be written as '& name' at the end", span = item.span}, false
            }
            params.has_rest = true
            params.rest_name = form.items[i+1].text
            return params, Compile_Error{}, true
        }
        form_param := false
        if i+1 < len(form.items) &&
           form.items[i+1].kind == .Symbol &&
           form.items[i+1].text == "#form" {
            form_param = true
            i += 1
        }
        append(&params.names, item.text)
        append(&params.form_params, form_param)
        i += 1
    }
    return params, Compile_Error{}, true
}

parse_user_macro_decl :: proc(top: CST_Top_Form) -> (macro_decl: User_Macro, err: Compile_Error, ok: bool) {
    form := top.form
    if !is_defmacro_form(form) {
        return macro_decl, Compile_Error{message = "expected defmacro form", span = form.span}, false
    }
    if len(form.items) < 4 {
        return macro_decl, Compile_Error{message = "defmacro expects a name, parameter vector, and body", span = form.span}, false
    }
    if form.items[1].kind != .Symbol {
        return macro_decl, Compile_Error{message = "defmacro expects a symbol name", span = form.items[1].span}, false
    }

    params_index := 2
    doc_lines := top.doc_lines
    doc_lines_owned := false
    if len(form.items) > 4 && form.items[2].kind == .String {
        doc_text := unquote_string(form.items[2].text)
        extra_doc_lines := doc_lines_from_string(doc_text)
        doc_lines = append_doc_lines(doc_lines[:], extra_doc_lines[:])
        doc_lines_owned = true
        delete(doc_text)
        delete(extra_doc_lines)
        params_index = 3
    }
    defer if doc_lines_owned {
        delete(doc_lines)
    }
    if params_index >= len(form.items) || form.items[params_index].kind != .Vector {
        return macro_decl, Compile_Error{message = "defmacro expects a parameter vector", span = form.span}, false
    }
    params, err_params, ok_params := parse_macro_param_vector(form.items[params_index])
    if !ok_params {
        return macro_decl, err_params, false
    }
    defer delete(params.names)
    defer delete(params.form_params)
    if params_index+1 >= len(form.items) {
        return macro_decl, Compile_Error{message = "defmacro body is empty", span = form.span}, false
    }
    body: [dynamic]CST_Form
    defer delete(body)
    for item in form.items[params_index+1:] {
        append(&body, item)
    }
    return User_Macro{
        name      = strings.clone(form.items[1].text),
        doc_lines = clone_string_slice(doc_lines[:]),
        params    = Macro_Param_Spec{
            names       = clone_string_slice(params.names[:]),
            form_params = clone_bool_slice(params.form_params[:]),
            has_rest    = params.has_rest,
            rest_name   = strings.clone(params.rest_name),
        },
        body      = clone_cst_form_slice(body[:]),
        span      = form.span,
    }, Compile_Error{}, true
}

find_user_macro :: proc(macros: []User_Macro, name: string) -> (User_Macro, bool) {
    for i := len(macros) - 1; i >= 0; i -= 1 {
        if macros[i].name == name {
            return macros[i], true
        }
    }
    return User_Macro{}, false
}

macro_error_with_expansion_context :: proc(macro_decl: User_Macro, err: Compile_Error) -> Compile_Error {
    return Compile_Error{
        message = fmt.tprintf("while expanding macro %s: %s", macro_decl.name, err.message),
        span    = err.span,
    }
}

invoke_user_macro_value :: proc(macro_decl: User_Macro, call: CST_Form, macros: []User_Macro) -> (Macro_Value, Compile_Error, bool) {
    bindings, err_bindings, ok_bindings := macro_collect_call_bindings(macro_decl, call)
    if !ok_bindings {
        return Macro_Value{}, err_bindings, false
    }
    value, err, ok := macro_eval_sequence(macro_decl.body[:], macros, bindings[:])
    if !ok {
        macro_binding_slice_delete_backing(&bindings)
        return Macro_Value{}, macro_error_with_expansion_context(macro_decl, err), false
    }
    result := macro_value_clone_backing(value)
    macro_value_delete_backing(&value)
    macro_binding_slice_delete_backing(&bindings)
    return result, Compile_Error{}, true
}

macro_collect_call_bindings :: proc(macro_decl: User_Macro, call: CST_Form) -> ([]Macro_Binding, Compile_Error, bool) {
    if call.kind != .List || len(call.items) == 0 {
        return nil, Compile_Error{message = "macro call must be a list", span = call.span}, false
    }
    args := call.items[1:]
    macro_name := display_head_name(macro_decl.name)
    if !macro_decl.params.has_rest && len(args) != len(macro_decl.params.names) {
        return nil, Compile_Error{message = fmt.tprintf("%s expects %d arguments", macro_name, len(macro_decl.params.names)), span = call.span}, false
    }
    if macro_decl.params.has_rest && len(args) < len(macro_decl.params.names) {
        return nil, Compile_Error{message = fmt.tprintf("%s expects at least %d arguments", macro_name, len(macro_decl.params.names)), span = call.span}, false
    }

    bindings: [dynamic]Macro_Binding
    for name, idx in macro_decl.params.names {
        append(&bindings, Macro_Binding{name = name, value = macro_form_value(args[idx])})
    }
    if macro_decl.params.has_rest {
        rest_args := args[len(macro_decl.params.names):]
        append(&bindings, Macro_Binding{name = macro_decl.params.rest_name, value = macro_forms_value(rest_args)})
    }
    return bindings[:], Compile_Error{}, true
}

macro_collect_eval_call_bindings :: proc(macro_decl: User_Macro, call: CST_Form, macros: []User_Macro, bindings: []Macro_Binding) -> ([]Macro_Binding, Compile_Error, bool) {
    if call.kind != .List || len(call.items) == 0 {
        return nil, Compile_Error{message = "macro call must be a list", span = call.span}, false
    }
    args := call.items[1:]
    macro_name := display_head_name(macro_decl.name)
    if !macro_decl.params.has_rest && len(args) != len(macro_decl.params.names) {
        return nil, Compile_Error{message = fmt.tprintf("%s expects %d arguments", macro_name, len(macro_decl.params.names)), span = call.span}, false
    }
    if macro_decl.params.has_rest && len(args) < len(macro_decl.params.names) {
        return nil, Compile_Error{message = fmt.tprintf("%s expects at least %d arguments", macro_name, len(macro_decl.params.names)), span = call.span}, false
    }

    out: [dynamic]Macro_Binding
    for name, idx in macro_decl.params.names {
        if idx < len(macro_decl.params.form_params) && macro_decl.params.form_params[idx] {
            if args[idx].kind == .Symbol {
                if value, ok_binding := macro_lookup_binding(bindings, args[idx].text); ok_binding {
                    if value.kind == .Form {
                        append(&out, Macro_Binding{name = name, value = value})
                        continue
                    }
                    macro_value_delete_backing(&value)
                }
            }
            append(&out, Macro_Binding{name = name, value = macro_form_value(args[idx])})
            continue
        }
        value, err_value, ok_value := macro_eval_expr(args[idx], macros, bindings)
        if !ok_value {
            return nil, err_value, false
        }
        append(&out, Macro_Binding{name = name, value = value})
    }
    if macro_decl.params.has_rest {
        rest_out: [dynamic]CST_Form
        for arg in args[len(macro_decl.params.names):] {
            value, err_value, ok_value := macro_eval_expr(arg, macros, bindings)
            if !ok_value {
                return nil, err_value, false
            }
            forms, err_forms, ok_forms := macro_value_to_owned_forms(value, arg.span)
            if !ok_forms {
                macro_value_delete_backing(&value)
                return nil, err_forms, false
            }
            for item in forms {
                append(&rest_out, item)
            }
            delete(forms)
            macro_value_delete_backing(&value)
        }
        append(&out, Macro_Binding{name = macro_decl.params.rest_name, value = macro_owned_forms_value(rest_out[:])})
        delete(rest_out)
    }
    return out[:], Compile_Error{}, true
}

macro_eval_sequence :: proc(forms: []CST_Form, macros: []User_Macro, bindings: []Macro_Binding) -> (Macro_Value, Compile_Error, bool) {
    if len(forms) == 0 {
        return macro_nil_value(), Compile_Error{}, true
    }
    value := macro_nil_value()
    for form in forms {
        next_value, err_next, ok_next := macro_eval_expr(form, macros, bindings)
        if !ok_next {
            macro_value_delete_backing(&value)
            return Macro_Value{}, err_next, false
        }
        macro_value_delete_backing(&value)
        value = next_value
    }
    return value, Compile_Error{}, true
}

macro_eval_list_builder :: proc(kind: CST_Form_Kind, form: CST_Form, macros: []User_Macro, bindings: []Macro_Binding) -> (Macro_Value, Compile_Error, bool) {
    out := CST_Form{kind = kind, span = form.span}
    for arg in form.items[1:] {
        value, err_value, ok_value := macro_eval_expr(arg, macros, bindings)
        if !ok_value {
            return Macro_Value{}, err_value, false
        }
        forms, err_forms, ok_forms := macro_value_to_owned_forms(value, arg.span)
        if !ok_forms {
            macro_value_delete_backing(&value)
            return Macro_Value{}, err_forms, false
        }
        for item in forms {
            append(&out.items, item)
        }
        delete(forms)
        macro_value_delete_backing(&value)
    }
    return macro_owned_form_value(out), Compile_Error{}, true
}

macro_list_from_value :: proc(value: Macro_Value, span: Span) -> ([]CST_Form, Compile_Error, bool) {
    #partial switch value.kind {
    case .Forms:
        return value.forms[:], Compile_Error{}, true
    case .Form:
        if value.form.kind == .List || value.form.kind == .Vector || value.form.kind == .Brace {
            return value.form.items[:], Compile_Error{}, true
        }
        return nil, Compile_Error{message = "expected macro sequence value", span = span}, false
    case .Nil:
        return nil, Compile_Error{}, true
    case:
        return nil, Compile_Error{message = "expected macro sequence value", span = span}, false
    }
}

macro_slice_forms :: proc(forms: []CST_Form, start: int, end := -1) -> []CST_Form {
    from := start
    to := end
    if from < 0 {
        from = 0
    }
    if from > len(forms) {
        from = len(forms)
    }
    if to < 0 || to > len(forms) {
        to = len(forms)
    }
    if to < from {
        to = from
    }
    out: [dynamic]CST_Form
    for form in forms[from:to] {
        append(&out, form)
    }
    return out[:]
}

macro_slice_string :: proc(text: string, start: int, end := -1) -> string {
    from := start
    to := end
    if from < 0 {
        from = 0
    }
    if from > len(text) {
        from = len(text)
    }
    if to < 0 || to > len(text) {
        to = len(text)
    }
    if to < from {
        to = from
    }
    return strings.clone(text[from:to])
}

macro_name_value :: proc(value: Macro_Value, span: Span) -> (Macro_Value, Compile_Error, bool) {
    single, err_single, ok_single := macro_value_to_form(value, span)
    if !ok_single {
        return Macro_Value{}, err_single, false
    }
    #partial switch single.kind {
    case .Symbol:
        if len(single.text) > 1 && single.text[0] == '.' {
            return macro_owned_string_value(strings.clone(single.text[1:])), Compile_Error{}, true
        }
        if len(single.text) > 1 && single.text[len(single.text)-1] == ':' {
            return macro_owned_string_value(strings.clone(single.text[:len(single.text)-1])), Compile_Error{}, true
        }
        return macro_owned_string_value(strings.clone(single.text)), Compile_Error{}, true
    case .Keyword:
        if len(single.text) > 0 && single.text[0] == ':' {
            return macro_owned_string_value(strings.clone(single.text[1:])), Compile_Error{}, true
        }
        return macro_owned_string_value(strings.clone(single.text)), Compile_Error{}, true
    case:
        return Macro_Value{}, Compile_Error{message = "name expects one symbol or keyword", span = span}, false
    }
}

macro_is_symbol_call :: proc(form: CST_Form, name: string) -> bool {
    return form.kind == .List && len(form.items) > 0 && is_symbol(form.items[0], name)
}

macro_quasiquote_form :: proc(form: CST_Form, macros: []User_Macro, bindings: []Macro_Binding, depth: int = 0) -> (CST_Form, Compile_Error, bool) {
    if macro_is_symbol_call(form, "unquote") {
        if len(form.items) != 2 {
            return CST_Form{}, Compile_Error{message = "unquote expects one form", span = form.span}, false
        }
        if depth == 0 {
            value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
            if !ok_value {
                return CST_Form{}, err_value, false
            }
            result, err_form, ok_form := macro_value_to_owned_form(value, form.items[1].span)
            macro_value_delete_backing(&value)
            return result, err_form, ok_form
        }
        inner, err_inner, ok_inner := macro_quasiquote_form(form.items[1], macros, bindings, depth-1)
        if !ok_inner {
            return CST_Form{}, err_inner, false
        }
        out := CST_Form{kind = .List, span = form.span}
        append(&out.items, clone_cst_form(form.items[0]))
        append(&out.items, inner)
        return out, Compile_Error{}, true
    }

    if macro_is_symbol_call(form, "splice") {
        if len(form.items) != 2 {
            return CST_Form{}, Compile_Error{message = "splice expects one form", span = form.span}, false
        }
        if depth == 0 {
            return CST_Form{}, Compile_Error{message = "splice is only valid inside quasiquoted list, vector, or brace items", span = form.span}, false
        }
        inner, err_inner, ok_inner := macro_quasiquote_form(form.items[1], macros, bindings, depth-1)
        if !ok_inner {
            return CST_Form{}, err_inner, false
        }
        out := CST_Form{kind = .List, span = form.span}
        append(&out.items, clone_cst_form(form.items[0]))
        append(&out.items, inner)
        return out, Compile_Error{}, true
    }

    #partial switch form.kind {
    case .List:
        if macro_is_symbol_call(form, "quasiquote") {
            if len(form.items) != 2 {
                return CST_Form{}, Compile_Error{message = "quasiquote expects one form", span = form.span}, false
            }
            inner, err_inner, ok_inner := macro_quasiquote_form(form.items[1], macros, bindings, depth+1)
            if !ok_inner {
                return CST_Form{}, err_inner, false
            }
            out := CST_Form{kind = .List, span = form.span}
            append(&out.items, clone_cst_form(form.items[0]))
            append(&out.items, inner)
            return out, Compile_Error{}, true
        }

        out := CST_Form{kind = .List, span = form.span}
        for item in form.items {
            if macro_is_symbol_call(item, "splice") && depth == 0 {
                if len(item.items) != 2 {
                    return CST_Form{}, Compile_Error{message = "splice expects one form", span = item.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(item.items[1], macros, bindings)
                if !ok_value {
                    return CST_Form{}, err_value, false
                }
                forms, err_forms, ok_forms := macro_value_to_owned_forms(value, item.items[1].span)
                if !ok_forms {
                    macro_value_delete_backing(&value)
                    return CST_Form{}, err_forms, false
                }
                for expanded in forms {
                    append(&out.items, expanded)
                }
                delete(forms)
                macro_value_delete_backing(&value)
                continue
            }
            child, err_child, ok_child := macro_quasiquote_form(item, macros, bindings, depth)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&out.items, child)
        }
        return out, Compile_Error{}, true
    case .Vector:
        out := CST_Form{kind = .Vector, span = form.span}
        for item in form.items {
            if macro_is_symbol_call(item, "splice") && depth == 0 {
                if len(item.items) != 2 {
                    return CST_Form{}, Compile_Error{message = "splice expects one form", span = item.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(item.items[1], macros, bindings)
                if !ok_value {
                    return CST_Form{}, err_value, false
                }
                forms, err_forms, ok_forms := macro_value_to_owned_forms(value, item.items[1].span)
                if !ok_forms {
                    macro_value_delete_backing(&value)
                    return CST_Form{}, err_forms, false
                }
                for expanded in forms {
                    append(&out.items, expanded)
                }
                delete(forms)
                macro_value_delete_backing(&value)
                continue
            }
            child, err_child, ok_child := macro_quasiquote_form(item, macros, bindings, depth)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&out.items, child)
        }
        return out, Compile_Error{}, true
    case .Brace:
        out := CST_Form{kind = .Brace, span = form.span}
        for item in form.items {
            if macro_is_symbol_call(item, "splice") && depth == 0 {
                if len(item.items) != 2 {
                    return CST_Form{}, Compile_Error{message = "splice expects one form", span = item.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(item.items[1], macros, bindings)
                if !ok_value {
                    return CST_Form{}, err_value, false
                }
                forms, err_forms, ok_forms := macro_value_to_owned_forms(value, item.items[1].span)
                if !ok_forms {
                    macro_value_delete_backing(&value)
                    return CST_Form{}, err_forms, false
                }
                for expanded in forms {
                    append(&out.items, expanded)
                }
                delete(forms)
                macro_value_delete_backing(&value)
                continue
            }
            child, err_child, ok_child := macro_quasiquote_form(item, macros, bindings, depth)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&out.items, child)
        }
        return out, Compile_Error{}, true
    case .Set:
        out := CST_Form{kind = .Set, span = form.span}
        for item in form.items {
            if macro_is_symbol_call(item, "splice") && depth == 0 {
                if len(item.items) != 2 {
                    return CST_Form{}, Compile_Error{message = "splice expects one form", span = item.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(item.items[1], macros, bindings)
                if !ok_value {
                    return CST_Form{}, err_value, false
                }
                forms, err_forms, ok_forms := macro_value_to_owned_forms(value, item.items[1].span)
                if !ok_forms {
                    macro_value_delete_backing(&value)
                    return CST_Form{}, err_forms, false
                }
                for expanded in forms {
                    append(&out.items, expanded)
                }
                delete(forms)
                macro_value_delete_backing(&value)
                continue
            }
            child, err_child, ok_child := macro_quasiquote_form(item, macros, bindings, depth)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&out.items, child)
        }
        return out, Compile_Error{}, true
    case:
        return clone_cst_form(form), Compile_Error{}, true
    }
}

macro_eval_contains_expr :: proc(form: CST_Form, macros: []User_Macro, bindings: []Macro_Binding) -> (Macro_Value, Compile_Error, bool) {
    if len(form.items) != 3 {
        return Macro_Value{}, Compile_Error{message = "contains? expects collection and value", span = form.span}, false
    }
    collection, err_collection, ok_collection := macro_eval_expr(form.items[1], macros, bindings)
    if !ok_collection {
        return Macro_Value{}, err_collection, false
    }
    needle, err_needle, ok_needle := macro_eval_expr(form.items[2], macros, bindings)
    if !ok_needle {
        macro_value_delete_backing(&collection)
        return Macro_Value{}, err_needle, false
    }
    defer macro_value_delete_backing(&collection)
    defer macro_value_delete_backing(&needle)
    if collection.kind == .String {
        if needle.kind != .String {
            return Macro_Value{}, Compile_Error{message = "contains? on strings expects a string needle", span = form.items[2].span}, false
        }
        return macro_bool_value(strings.contains(collection.string_value, needle.string_value)), Compile_Error{}, true
    }
    forms, err_forms, ok_forms := macro_list_from_value(collection, form.items[1].span)
    if !ok_forms {
        return Macro_Value{}, err_forms, false
    }
    for candidate_form in forms {
        candidate, _, ok_candidate := macro_eval_expr(candidate_form, macros, bindings)
        if !ok_candidate {
            candidate = macro_form_value(candidate_form)
        }
        if macro_value_equal(candidate, needle) {
            macro_value_delete_backing(&candidate)
            return macro_bool_value(true), Compile_Error{}, true
        }
        macro_value_delete_backing(&candidate)
    }
    return macro_bool_value(false), Compile_Error{}, true
}

macro_eval_unary_sequence_call :: proc(operator, item: CST_Form, macros: []User_Macro, bindings: []Macro_Binding) -> (Macro_Value, Compile_Error, bool) {
    call := CST_Form{kind = .List, span = item.span}
    append(&call.items,
        clone_cst_form(operator),
        CST_Form{kind = .Symbol, text = strings.clone("__kvist_macro_sequence_item"), span = item.span},
    )
    defer delete_cst_form(&call)
    local: [dynamic]Macro_Binding
    defer delete(local)
    append(&local, ..bindings)
    append(&local, Macro_Binding{name = "__kvist_macro_sequence_item", value = macro_form_value(item)})
    return macro_eval_expr(call, macros, local[:])
}

macro_eval_sequence_helper :: proc(form: CST_Form, macros: []User_Macro, bindings: []Macro_Binding) -> (Macro_Value, Compile_Error, bool) {
    if len(form.items) != 3 {
        return Macro_Value{}, Compile_Error{message = fmt.tprintf("%s expects a unary operation and a sequence", form.items[0].text), span = form.span}, false
    }
    sequence, err_sequence, ok_sequence := macro_eval_expr(form.items[2], macros, bindings)
    if !ok_sequence {
        return Macro_Value{}, err_sequence, false
    }
    defer macro_value_delete_backing(&sequence)
    items, err_items, ok_items := macro_list_from_value(sequence, form.items[2].span)
    if !ok_items {
        return Macro_Value{}, err_items, false
    }

    switch form.items[0].text {
    case "map":
        out: [dynamic]CST_Form
        for item in items {
            value, err_value, ok_value := macro_eval_unary_sequence_call(form.items[1], item, macros, bindings)
            if !ok_value {
                delete_cst_form_slice(&out)
                return Macro_Value{}, err_value, false
            }
            forms, err_forms, ok_forms := macro_value_to_owned_forms(value, item.span)
            if !ok_forms {
                macro_value_delete_backing(&value)
                delete_cst_form_slice(&out)
                return Macro_Value{}, err_forms, false
            }
            append(&out, ..forms)
            delete(forms)
            macro_value_delete_backing(&value)
        }
        result := macro_owned_forms_value(out[:])
        delete(out)
        return result, Compile_Error{}, true
    case "filter":
        out: [dynamic]CST_Form
        for item in items {
            value, err_value, ok_value := macro_eval_unary_sequence_call(form.items[1], item, macros, bindings)
            if !ok_value {
                delete_cst_form_slice(&out)
                return Macro_Value{}, err_value, false
            }
            keep := macro_truthy(value)
            macro_value_delete_backing(&value)
            if keep {
                append(&out, clone_cst_form(item))
            }
        }
        result := macro_owned_forms_value(out[:])
        delete(out)
        return result, Compile_Error{}, true
    case "some?", "every?":
        every := form.items[0].text == "every?"
        for item in items {
            value, err_value, ok_value := macro_eval_unary_sequence_call(form.items[1], item, macros, bindings)
            if !ok_value {
                return Macro_Value{}, err_value, false
            }
            truthy := macro_truthy(value)
            macro_value_delete_backing(&value)
            if (!every && truthy) || (every && !truthy) {
                return macro_bool_value(!every), Compile_Error{}, true
            }
        }
        return macro_bool_value(every), Compile_Error{}, true
    }
    return Macro_Value{}, Compile_Error{message = "unknown macro sequence helper", span = form.span}, false
}

macro_eval_expr :: proc(form: CST_Form, macros: []User_Macro, bindings: []Macro_Binding) -> (Macro_Value, Compile_Error, bool) {
    #partial switch form.kind {
    case .Nil:
        return macro_nil_value(), Compile_Error{}, true
    case .Bool:
        return macro_bool_value(form.text == "true"), Compile_Error{}, true
    case .Number:
        value: int
        parsed, ok_parsed := strconv.parse_int(form.text)
        if ok_parsed {
            value = parsed
            return macro_int_value(value), Compile_Error{}, true
        }
        float_value, ok_float := strconv.parse_f64(form.text)
        if !ok_float {
            return Macro_Value{}, Compile_Error{message = "macro evaluator could not parse numeric literal", span = form.span}, false
        }
        return macro_float_value(float_value), Compile_Error{}, true
    case .String:
        return macro_owned_string_value(unquote_string(form.text)), Compile_Error{}, true
    case .Regex:
        return macro_owned_string_value(unquote_regex_literal(form.text)), Compile_Error{}, true
    case .Keyword:
        return macro_form_value(form), Compile_Error{}, true
    case .Symbol:
        if value, ok_lookup := macro_lookup_binding(bindings, form.text); ok_lookup {
            return value, Compile_Error{}, true
        }
        if form.text == "nil" {
            return macro_nil_value(), Compile_Error{}, true
        }
        if form.text == "true" {
            return macro_bool_value(true), Compile_Error{}, true
        }
        if form.text == "false" {
            return macro_bool_value(false), Compile_Error{}, true
        }
        return Macro_Value{}, Compile_Error{message = fmt.tprintf("unknown macro symbol: %s", form.text), span = form.span}, false
    case .Vector:
        return macro_form_value(form), Compile_Error{}, true
    case .Brace:
        return macro_form_value(form), Compile_Error{}, true
    case .Set:
        return macro_form_value(form), Compile_Error{}, true
    case .List:
        if len(form.items) == 0 {
            return macro_form_value(form), Compile_Error{}, true
        }
        head := form.items[0]
        if head.kind == .Symbol {
            switch head.text {
            case "quote":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "quote expects one form", span = form.span}, false
                }
                return macro_form_value(form.items[1]), Compile_Error{}, true
            case "quasiquote":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "quasiquote expects one form", span = form.span}, false
                }
                quoted, err_quoted, ok_quoted := macro_quasiquote_form(form.items[1], macros, bindings)
                if !ok_quoted {
                    return Macro_Value{}, err_quoted, false
                }
                return macro_owned_form_value(quoted), Compile_Error{}, true
            case "do":
                return macro_eval_sequence(form.items[1:], macros, bindings)
            case "not":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "not expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                truthy := macro_truthy(value)
                macro_value_delete_backing(&value)
                return macro_bool_value(!truthy), Compile_Error{}, true
            case "and":
                for arg in form.items[1:] {
                    value, err_value, ok_value := macro_eval_expr(arg, macros, bindings)
                    if !ok_value {
                        return Macro_Value{}, err_value, false
                    }
                    truthy := macro_truthy(value)
                    macro_value_delete_backing(&value)
                    if !truthy {
                        return macro_bool_value(false), Compile_Error{}, true
                    }
                }
                return macro_bool_value(true), Compile_Error{}, true
            case "or":
                for arg in form.items[1:] {
                    value, err_value, ok_value := macro_eval_expr(arg, macros, bindings)
                    if !ok_value {
                        return Macro_Value{}, err_value, false
                    }
                    truthy := macro_truthy(value)
                    macro_value_delete_backing(&value)
                    if truthy {
                        return macro_bool_value(true), Compile_Error{}, true
                    }
                }
                return macro_bool_value(false), Compile_Error{}, true
            case "if":
                if len(form.items) != 4 {
                    return Macro_Value{}, Compile_Error{message = "if expects condition, then, and else", span = form.span}, false
                }
                cond_value, err_cond, ok_cond := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_cond {
                    return Macro_Value{}, err_cond, false
                }
                cond_truthy := macro_truthy(cond_value)
                macro_value_delete_backing(&cond_value)
                if cond_truthy {
                    return macro_eval_expr(form.items[2], macros, bindings)
                }
                return macro_eval_expr(form.items[3], macros, bindings)
            case "cond":
                if len(form.items) < 3 {
                    return Macro_Value{}, Compile_Error{message = "cond expects at least one clause", span = form.span}, false
                }
                if (len(form.items)-1)%2 != 0 {
                    return Macro_Value{}, Compile_Error{message = "cond expects test/body pairs", span = form.span}, false
                }
                i := 1
                for i < len(form.items) {
                    test_form := form.items[i]
                    if test_form.kind == .Keyword && test_form.text == ":else" {
                        if i+2 < len(form.items) {
                            return Macro_Value{}, Compile_Error{message = "cond :else must be the final clause", span = test_form.span}, false
                        }
                        return macro_eval_expr(form.items[i+1], macros, bindings)
                    }
                    test_value, err_test, ok_test := macro_eval_expr(test_form, macros, bindings)
                    if !ok_test {
                        return Macro_Value{}, err_test, false
                    }
                    truthy := macro_truthy(test_value)
                    macro_value_delete_backing(&test_value)
                    if truthy {
                        return macro_eval_expr(form.items[i+1], macros, bindings)
                    }
                    i += 2
                }
                return macro_nil_value(), Compile_Error{}, true
            case "let":
                if len(form.items) < 3 || form.items[1].kind != .Vector {
                    return Macro_Value{}, Compile_Error{message = "macro let expects binding vector and body", span = form.span}, false
                }
                local: [dynamic]Macro_Binding
                defer delete(local)
                for binding in bindings {
                    append(&local, binding)
                }
                local_owned_start := len(local)
                binding_form := form.items[1]
                if len(binding_form.items)%2 != 0 {
                    return Macro_Value{}, Compile_Error{message = "macro let expects [name value ...] bindings", span = binding_form.span}, false
                }
                i := 0
                for i < len(binding_form.items) {
                    name_form := binding_form.items[i]
                    if name_form.kind != .Symbol {
                        return Macro_Value{}, Compile_Error{message = "macro let binding name must be a symbol", span = name_form.span}, false
                    }
                    value, err_value, ok_value := macro_eval_expr(binding_form.items[i+1], macros, local[:])
                    if !ok_value {
                        return Macro_Value{}, err_value, false
                    }
                    append(&local, Macro_Binding{name = name_form.text, value = value})
                    i += 2
                }
                value, err_value, ok_value := macro_eval_sequence(form.items[2:], macros, local[:])
                for idx in local_owned_start ..< len(local) {
                    macro_value_delete_backing(&local[idx].value)
                }
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                return value, Compile_Error{}, true
            case "list":
                return macro_eval_list_builder(.List, form, macros, bindings)
            case "vector":
                return macro_eval_list_builder(.Vector, form, macros, bindings)
            case "brace":
                return macro_eval_list_builder(.Brace, form, macros, bindings)
            case "first":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "first expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                forms, err_forms, ok_forms := macro_list_from_value(value, form.items[1].span)
                if !ok_forms {
                    macro_value_delete_backing(&value)
                    return Macro_Value{}, err_forms, false
                }
                if len(forms) == 0 {
                    macro_value_delete_backing(&value)
                    return macro_nil_value(), Compile_Error{}, true
                }
                result := macro_owned_form_value(clone_cst_form(forms[0]))
                macro_value_delete_backing(&value)
                return result, Compile_Error{}, true
            case "rest":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "rest expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                forms, err_forms, ok_forms := macro_list_from_value(value, form.items[1].span)
                if !ok_forms {
                    macro_value_delete_backing(&value)
                    return Macro_Value{}, err_forms, false
                }
                if len(forms) <= 1 {
                    macro_value_delete_backing(&value)
                    return macro_forms_value(nil), Compile_Error{}, true
                }
                cloned := clone_cst_form_slice(forms[1:])
                result := macro_owned_forms_value(cloned[:])
                delete(cloned)
                macro_value_delete_backing(&value)
                return result, Compile_Error{}, true
            case "nth":
                if len(form.items) != 3 {
                    return Macro_Value{}, Compile_Error{message = "nth expects sequence and index", span = form.span}, false
                }
                seq_form := form.items[1]
                index_form := form.items[2]
                seq_value, err_seq, ok_seq := macro_eval_expr(seq_form, macros, bindings)
                if !ok_seq {
                    return Macro_Value{}, err_seq, false
                }
                forms, err_forms, ok_forms := macro_list_from_value(seq_value, seq_form.span)
                if !ok_forms {
                    macro_value_delete_backing(&seq_value)
                    return Macro_Value{}, err_forms, false
                }
                index_value, err_index, ok_index := macro_eval_expr(index_form, macros, bindings)
                if !ok_index {
                    macro_value_delete_backing(&seq_value)
                    return Macro_Value{}, err_index, false
                }
                if index_value.kind != .Int {
                    macro_value_delete_backing(&seq_value)
                    return Macro_Value{}, Compile_Error{message = "nth index must be an integer", span = index_form.span}, false
                }
                if index_value.int_value < 0 || index_value.int_value >= len(forms) {
                    macro_value_delete_backing(&seq_value)
                    return macro_nil_value(), Compile_Error{}, true
                }
                result := macro_owned_form_value(clone_cst_form(forms[index_value.int_value]))
                macro_value_delete_backing(&seq_value)
                return result, Compile_Error{}, true
            case "count":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "count expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                #partial switch value.kind {
                case .Forms:
                    return macro_int_value(len(value.forms)), Compile_Error{}, true
                case .Form:
                    if value.form.kind == .List || value.form.kind == .Vector || value.form.kind == .Brace {
                        return macro_int_value(len(value.form.items)), Compile_Error{}, true
                    }
                    return macro_int_value(1), Compile_Error{}, true
                case .String:
                    return macro_int_value(len(value.string_value)), Compile_Error{}, true
                case .Nil:
                    return macro_int_value(0), Compile_Error{}, true
                case:
                    return macro_int_value(1), Compile_Error{}, true
                }
            case "slice":
                if len(form.items) != 3 && len(form.items) != 4 {
                    return Macro_Value{}, Compile_Error{message = "slice expects sequence, start, and optional end", span = form.span}, false
                }
                seq_value, err_seq, ok_seq := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_seq {
                    return Macro_Value{}, err_seq, false
                }
                start_value, err_start, ok_start := macro_eval_expr(form.items[2], macros, bindings)
                if !ok_start {
                    macro_value_delete_backing(&seq_value)
                    return Macro_Value{}, err_start, false
                }
                if start_value.kind != .Int {
                    macro_value_delete_backing(&seq_value)
                    return Macro_Value{}, Compile_Error{message = "slice start must be an integer", span = form.items[2].span}, false
                }
                end := -1
                if len(form.items) == 4 {
                    end_value, err_end, ok_end := macro_eval_expr(form.items[3], macros, bindings)
                    if !ok_end {
                        macro_value_delete_backing(&seq_value)
                        return Macro_Value{}, err_end, false
                    }
                    if end_value.kind != .Int {
                        macro_value_delete_backing(&seq_value)
                        return Macro_Value{}, Compile_Error{message = "slice end must be an integer", span = form.items[3].span}, false
                    }
                    end = end_value.int_value
                }
                if seq_value.kind == .String {
                    result := macro_owned_string_value(macro_slice_string(seq_value.string_value, start_value.int_value, end))
                    macro_value_delete_backing(&seq_value)
                    return result, Compile_Error{}, true
                }
                forms, err_forms, ok_forms := macro_list_from_value(seq_value, form.items[1].span)
                if !ok_forms {
                    macro_value_delete_backing(&seq_value)
                    return Macro_Value{}, err_forms, false
                }
                sliced := macro_slice_forms(forms, start_value.int_value, end)
                cloned := clone_cst_form_slice(sliced)
                result := macro_owned_forms_value(cloned[:])
                delete(cloned)
                delete(sliced)
                macro_value_delete_backing(&seq_value)
                return result, Compile_Error{}, true
            case "concat":
                out: [dynamic]CST_Form
                for arg in form.items[1:] {
                    value, err_value, ok_value := macro_eval_expr(arg, macros, bindings)
                    if !ok_value {
                        return Macro_Value{}, err_value, false
                    }
                    forms, err_forms, ok_forms := macro_value_to_owned_forms(value, arg.span)
                    if !ok_forms {
                        macro_value_delete_backing(&value)
                        return Macro_Value{}, err_forms, false
                    }
                    for item in forms {
                        append(&out, item)
                    }
                    delete(forms)
                    macro_value_delete_backing(&value)
                }
                result := macro_owned_forms_value(out[:])
                delete(out)
                return result, Compile_Error{}, true
            case "forms":
                out: [dynamic]CST_Form
                for arg in form.items[1:] {
                    value, err_value, ok_value := macro_eval_expr(arg, macros, bindings)
                    if !ok_value {
                        return Macro_Value{}, err_value, false
                    }
                    forms, err_forms, ok_forms := macro_value_to_owned_forms(value, arg.span)
                    if !ok_forms {
                        macro_value_delete_backing(&value)
                        return Macro_Value{}, err_forms, false
                    }
                    for item in forms {
                        append(&out, item)
                    }
                    delete(forms)
                    macro_value_delete_backing(&value)
                }
                result := macro_owned_forms_value(out[:])
                delete(out)
                return result, Compile_Error{}, true
            case "str":
                builder := strings.builder_make()
                defer strings.builder_destroy(&builder)
                for arg in form.items[1:] {
                    value, err_value, ok_value := macro_eval_expr(arg, macros, bindings)
                    if !ok_value {
                        return Macro_Value{}, err_value, false
                    }
                    text, err_text, ok_text := macro_value_to_string(value, arg.span)
                    if !ok_text {
                        macro_value_delete_backing(&value)
                        return Macro_Value{}, err_text, false
                    }
                    strings.write_string(&builder, text)
                    delete(text)
                    macro_value_delete_backing(&value)
                }
                return macro_owned_string_value(strings.clone(strings.to_string(builder))), Compile_Error{}, true
            case "read-file":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "read-file expects one path argument", span = form.span}, false
                }
                path_value, err_path_value, ok_path_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_path_value {
                    return Macro_Value{}, err_path_value, false
                }
                raw_path, err_raw_path, ok_raw_path := macro_value_to_string(path_value, form.items[1].span)
                if !ok_raw_path {
                    macro_value_delete_backing(&path_value)
                    return Macro_Value{}, err_raw_path, false
                }
                defer delete(raw_path)
                defer macro_value_delete_backing(&path_value)
                path, err_path, ok_path := macro_eval_read_file_path(raw_path, form.items[1].span)
                if !ok_path {
                    return Macro_Value{}, err_path, false
                }
                defer delete(path)
                data, read_err := os.read_entire_file_from_path(path, context.allocator)
                if read_err != nil {
                    return Macro_Value{}, Compile_Error{message = fmt.tprintf("compile-time read-file could not read file: %s", path), span = form.items[1].span}, false
                }
                text := strings.clone(string(data))
                delete(data)
                return macro_owned_string_value(text), Compile_Error{}, true
            case "symbol":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "symbol expects one string argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                if value.kind != .String {
                    macro_value_delete_backing(&value)
                    return Macro_Value{}, Compile_Error{message = "symbol expects one string argument", span = form.items[1].span}, false
                }
                symbol_text := strings.clone(value.string_value)
                macro_value_delete_backing(&value)
                return macro_owned_form_value(CST_Form{kind = .Symbol, text = symbol_text, span = form.span}), Compile_Error{}, true
            case "gensym":
                prefix := "__kvist_gensym"
                if len(form.items) > 2 {
                    return Macro_Value{}, Compile_Error{message = "gensym expects zero or one string argument", span = form.span}, false
                }
                gensym_value := Macro_Value{}
                gensym_has_value := false
                if len(form.items) == 2 {
                    value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                    if !ok_value {
                        return Macro_Value{}, err_value, false
                    }
                    if value.kind != .String {
                        macro_value_delete_backing(&value)
                        return Macro_Value{}, Compile_Error{message = "gensym expects zero or one string argument", span = form.items[1].span}, false
                    }
                    gensym_value = value
                    gensym_has_value = true
                    prefix = value.string_value
                }
                macro_gensym_counter += 1
                gensym_text := strings.clone(fmt.tprintf("%s_%d", prefix, macro_gensym_counter))
                if gensym_has_value {
                    macro_value_delete_backing(&gensym_value)
                }
                return macro_owned_form_value(CST_Form{
                    kind = .Symbol,
                    text = gensym_text,
                    span = form.span,
                }), Compile_Error{}, true
            case "keyword":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "keyword expects one string argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                if value.kind != .String {
                    macro_value_delete_backing(&value)
                    return Macro_Value{}, Compile_Error{message = "keyword expects one string argument", span = form.items[1].span}, false
                }
                keyword_text := strings.clone(fmt.tprintf(":%s", value.string_value))
                macro_value_delete_backing(&value)
                return macro_owned_form_value(CST_Form{kind = .Keyword, text = keyword_text, span = form.span}), Compile_Error{}, true
            case "name":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "name expects one symbol or keyword", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                single, err_single, ok_single := macro_value_to_form(value, form.items[1].span)
                if !ok_single {
                    macro_value_delete_backing(&value)
                    return Macro_Value{}, err_single, false
                }
                #partial switch single.kind {
                case .Symbol:
                    result := macro_owned_string_value(strings.clone(macro_unqualified_symbol_name(macro_source_symbol_text(single))))
                    macro_value_delete_backing(&value)
                    return result, Compile_Error{}, true
                case .Keyword:
                    if len(single.text) > 0 && single.text[0] == ':' {
                        result := macro_owned_string_value(strings.clone(single.text[1:]))
                        macro_value_delete_backing(&value)
                        return result, Compile_Error{}, true
                    }
                    result := macro_owned_string_value(strings.clone(single.text))
                    macro_value_delete_backing(&value)
                    return result, Compile_Error{}, true
                case:
                    macro_value_delete_backing(&value)
                    return Macro_Value{}, Compile_Error{message = "name expects one symbol or keyword", span = form.items[1].span}, false
                }
            case "+":
                int_sum := 0
                float_sum := 0.0
                all_int := true
                for item in form.items[1:] {
                    value, err_value, ok_value := macro_eval_expr(item, macros, bindings)
                    if !ok_value {
                        return Macro_Value{}, err_value, false
                    }
                    if value.kind == .Int {
                        int_sum += value.int_value
                        float_sum += f64(value.int_value)
                        macro_value_delete_backing(&value)
                        continue
                    }
                    if value.kind == .Form && value.form.kind == .Number {
                        parsed_int, ok_int := strconv.parse_int(value.form.text)
                        if ok_int {
                            int_sum += parsed_int
                            float_sum += f64(parsed_int)
                            macro_value_delete_backing(&value)
                            continue
                        }
                    }
                    number, ok_number := macro_value_number(value)
                    macro_value_delete_backing(&value)
                    if !ok_number {
                        return Macro_Value{}, Compile_Error{message = "+ expects numeric arguments", span = item.span}, false
                    }
                    all_int = false
                    float_sum += number
                }
                if all_int {
                    return macro_int_value(int_sum), Compile_Error{}, true
                }
                return macro_float_value(float_sum), Compile_Error{}, true
            case "-":
                if len(form.items) < 2 {
                    return Macro_Value{}, Compile_Error{message = "- expects at least one argument", span = form.span}, false
                }
                first, err_first, ok_first := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_first {
                    return Macro_Value{}, err_first, false
                }
                result, ok_first_number := macro_value_number(first)
                if !ok_first_number {
                    macro_value_delete_backing(&first)
                    return Macro_Value{}, Compile_Error{message = "- expects numeric arguments", span = form.items[1].span}, false
                }
                all_int := true
                int_result := 0
                if first.kind == .Int {
                    int_result = first.int_value
                } else if first.kind == .Form && first.form.kind == .Number {
                    parsed_int, ok_int := strconv.parse_int(first.form.text)
                    if ok_int {
                        int_result = parsed_int
                    } else {
                        all_int = false
                    }
                } else {
                    all_int = false
                }
                macro_value_delete_backing(&first)
                if len(form.items) == 2 {
                    result = -result
                    int_result = -int_result
                } else {
                    for item in form.items[2:] {
                        value, err_value, ok_value := macro_eval_expr(item, macros, bindings)
                        if !ok_value {
                            return Macro_Value{}, err_value, false
                        }
                        if all_int && value.kind == .Int {
                            int_result -= value.int_value
                            result -= f64(value.int_value)
                            macro_value_delete_backing(&value)
                            continue
                        }
                        if all_int && value.kind == .Form && value.form.kind == .Number {
                            parsed_int, ok_int := strconv.parse_int(value.form.text)
                            if ok_int {
                                int_result -= parsed_int
                                result -= f64(parsed_int)
                                macro_value_delete_backing(&value)
                                continue
                            }
                        }
                        number, ok_number := macro_value_number(value)
                        macro_value_delete_backing(&value)
                        if !ok_number {
                            return Macro_Value{}, Compile_Error{message = "- expects numeric arguments", span = item.span}, false
                        }
                        all_int = false
                        result -= number
                    }
                }
                if all_int {
                    return macro_int_value(int_result), Compile_Error{}, true
                }
                return macro_float_value(result), Compile_Error{}, true
            case "=":
                if len(form.items) < 3 {
                    return Macro_Value{}, Compile_Error{message = "= expects at least two arguments", span = form.span}, false
                }
                previous, err_previous, ok_previous := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_previous {
                    return Macro_Value{}, err_previous, false
                }
                for item in form.items[2:] {
                    current, err_current, ok_current := macro_eval_expr(item, macros, bindings)
                    if !ok_current {
                        macro_value_delete_backing(&previous)
                        return Macro_Value{}, err_current, false
                    }
                    if !macro_value_equal(previous, current) {
                        macro_value_delete_backing(&previous)
                        macro_value_delete_backing(&current)
                        return macro_bool_value(false), Compile_Error{}, true
                    }
                    macro_value_delete_backing(&previous)
                    previous = current
                }
                macro_value_delete_backing(&previous)
                return macro_bool_value(true), Compile_Error{}, true
            case "<", "<=", ">", ">=":
                if len(form.items) < 3 {
                    return Macro_Value{}, Compile_Error{message = fmt.tprintf("%s expects at least two arguments", head.text), span = form.span}, false
                }
                previous, err_previous, ok_previous := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_previous {
                    return Macro_Value{}, err_previous, false
                }
                previous_number, ok_previous_number := macro_value_number(previous)
                if !ok_previous_number {
                    macro_value_delete_backing(&previous)
                    return Macro_Value{}, Compile_Error{message = fmt.tprintf("%s expects numeric arguments", head.text), span = form.items[1].span}, false
                }
                macro_value_delete_backing(&previous)
                for item in form.items[2:] {
                    current, err_current, ok_current := macro_eval_expr(item, macros, bindings)
                    if !ok_current {
                        return Macro_Value{}, err_current, false
                    }
                    current_number, ok_current_number := macro_value_number(current)
                    if !ok_current_number {
                        macro_value_delete_backing(&current)
                        return Macro_Value{}, Compile_Error{message = fmt.tprintf("%s expects numeric arguments", head.text), span = item.span}, false
                    }
                    macro_value_delete_backing(&current)
                    matched := false
                    switch head.text {
                    case "<":
                        matched = previous_number < current_number
                    case "<=":
                        matched = previous_number <= current_number
                    case ">":
                        matched = previous_number > current_number
                    case ">=":
                        matched = previous_number >= current_number
                    }
                    if !matched {
                        return macro_bool_value(false), Compile_Error{}, true
                    }
                    previous_number = current_number
                }
                return macro_bool_value(true), Compile_Error{}, true
            case "contains?":
                return macro_eval_contains_expr(form, macros, bindings)
            case "map", "filter", "some?", "every?":
                return macro_eval_sequence_helper(form, macros, bindings)
            case "form?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "form? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                return macro_bool_value(value.kind == .Form), Compile_Error{}, true
            case "vector?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "vector? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .Vector), Compile_Error{}, true
            case "brace?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "brace? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .Brace), Compile_Error{}, true
            case "list?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "list? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .List), Compile_Error{}, true
            case "symbol?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "symbol? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .Symbol), Compile_Error{}, true
            case "keyword?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "keyword? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .Keyword), Compile_Error{}, true
            case "string?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "string? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind == .String {
                    return macro_bool_value(true), Compile_Error{}, true
                }
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .String || value.form.kind == .Regex), Compile_Error{}, true
            case "number?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "number? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind == .Int {
                    return macro_bool_value(true), Compile_Error{}, true
                }
                if value.kind == .Float {
                    return macro_bool_value(true), Compile_Error{}, true
                }
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .Number), Compile_Error{}, true
            case "source":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "source expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                single, err_single, ok_single := macro_value_to_form(value, form.items[1].span)
                if !ok_single {
                    macro_value_delete_backing(&value)
                    return Macro_Value{}, err_single, false
                }
                result := macro_owned_string_value(macro_form_text(single))
                macro_value_delete_backing(&value)
                return result, Compile_Error{}, true
            case "macro-doc":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "macro-doc expects one symbol", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                single, err_single, ok_single := macro_value_to_form(value, form.items[1].span)
                if !ok_single {
                    macro_value_delete_backing(&value)
                    return Macro_Value{}, err_single, false
                }
                target := single
                if single.kind == .List &&
                   len(single.items) == 2 &&
                   single.items[0].kind == .Symbol &&
                   single.items[0].text == "quote" {
                    target = single.items[1]
                }
                if target.kind != .Symbol {
                    macro_value_delete_backing(&value)
                    return Macro_Value{}, Compile_Error{message = "macro-doc expects one symbol", span = form.items[1].span}, false
                }
                macro_decl, found_macro := find_user_macro(macros, target.text)
                if !found_macro || len(macro_decl.doc_lines) == 0 {
                    macro_value_delete_backing(&value)
                    return macro_nil_value(), Compile_Error{}, true
                }
                builder := strings.builder_make()
                defer strings.builder_destroy(&builder)
                for line, i in macro_decl.doc_lines {
                    if i > 0 {
                        strings.write_byte(&builder, '\n')
                    }
                    strings.write_string(&builder, symbols_clean_doc_line(line))
                }
                result := macro_owned_string_value(strings.clone(strings.to_string(builder)))
                macro_value_delete_backing(&value)
                return result, Compile_Error{}, true
            case "text":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "text expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                if value.kind == .String {
                    result := macro_owned_string_value(strings.clone(value.string_value))
                    macro_value_delete_backing(&value)
                    return result, Compile_Error{}, true
                }
                if value.kind == .Int {
                    result := macro_owned_string_value(strings.clone(macro_int_text(value.int_value)))
                    macro_value_delete_backing(&value)
                    return result, Compile_Error{}, true
                }
                if value.kind == .Float {
                    result := macro_owned_string_value(strings.clone(macro_float_text(value.float_value)))
                    macro_value_delete_backing(&value)
                    return result, Compile_Error{}, true
                }
                if value.kind == .Bool {
                    if value.bool_value {
                        return macro_owned_string_value(strings.clone("true")), Compile_Error{}, true
                    }
                    return macro_owned_string_value(strings.clone("false")), Compile_Error{}, true
                }
                if value.kind == .Nil {
                    return macro_owned_string_value(strings.clone("nil")), Compile_Error{}, true
                }
                if value.kind == .Form {
                    #partial switch value.form.kind {
                    case .String:
                        result := macro_owned_string_value(unquote_string(value.form.text))
                        macro_value_delete_backing(&value)
                        return result, Compile_Error{}, true
                    case .Regex:
                        result := macro_owned_string_value(unquote_regex_literal(value.form.text))
                        macro_value_delete_backing(&value)
                        return result, Compile_Error{}, true
                    case .Symbol:
                        result := macro_owned_string_value(strings.clone(value.form.text))
                        macro_value_delete_backing(&value)
                        return result, Compile_Error{}, true
                    case .Keyword:
                        if len(value.form.text) > 0 && value.form.text[0] == ':' {
                            result := macro_owned_string_value(strings.clone(value.form.text[1:]))
                            macro_value_delete_backing(&value)
                            return result, Compile_Error{}, true
                        }
                        result := macro_owned_string_value(strings.clone(value.form.text))
                        macro_value_delete_backing(&value)
                        return result, Compile_Error{}, true
                    case .Number, .Bool, .Nil:
                        result := macro_owned_string_value(strings.clone(value.form.text))
                        macro_value_delete_backing(&value)
                        return result, Compile_Error{}, true
                    case:
                    }
                }
                macro_value_delete_backing(&value)
                return Macro_Value{}, Compile_Error{message = "text expects a scalar literal, symbol, or keyword", span = form.items[1].span}, false
            case "error":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "error expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                message, err_message, ok_message := macro_value_to_string(value, form.items[1].span)
                if !ok_message {
                    macro_value_delete_backing(&value)
                    return Macro_Value{}, err_message, false
                }
                macro_value_delete_backing(&value)
                return Macro_Value{}, Compile_Error{message = message, span = form.items[1].span}, false
            }
            if value, ok_binding := macro_lookup_binding(bindings, head.text); ok_binding {
                defer macro_value_delete_backing(&value)
                if value.kind == .Form && value.form.kind == .Symbol && value.form.text != head.text {
                    resolved := clone_cst_form(form)
                    delete_cst_form(&resolved.items[0])
                    resolved.items[0] = clone_cst_form(value.form)
                    result, err_result, ok_result := macro_eval_expr(resolved, macros, bindings)
                    delete_cst_form(&resolved)
                    return result, err_result, ok_result
                }
            }
        }
        if head.kind == .Symbol {
            if user_macro, ok_user := find_user_macro(macros, head.text); ok_user {
                local_bindings, err_bindings, ok_bindings := macro_collect_eval_call_bindings(user_macro, form, macros, bindings)
                if !ok_bindings {
                    return Macro_Value{}, err_bindings, false
                }
                value, err, ok := macro_eval_sequence(user_macro.body[:], macros, local_bindings[:])
                if !ok {
                    macro_binding_slice_delete_backing(&local_bindings)
                    return Macro_Value{}, macro_error_with_expansion_context(user_macro, err), false
                }
                result := macro_value_clone_backing(value)
                macro_value_delete_backing(&value)
                macro_binding_slice_delete_backing(&local_bindings)
                return result, Compile_Error{}, true
            }
        }
        return macro_form_value(form), Compile_Error{}, true
    }
    return Macro_Value{}, Compile_Error{message = "unsupported macro form", span = form.span}, false
}
