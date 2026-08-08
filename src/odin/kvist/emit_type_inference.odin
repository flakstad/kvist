// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

type_text_is_string :: proc(text: string) -> bool {
    return text == "string"
}

type_text_can_borrow_return_from_param :: proc(return_ty, param_ty: string) -> bool {
    if return_ty == "Data" {
        return param_ty == "Data"
    }
    if type_text_is_dynamic_array(return_ty) || type_text_is_map(return_ty) {
        return return_ty == param_ty
    }
    if type_text_is_string(return_ty) {
        return type_text_is_string(param_ty)
    }
    if type_text_is_slice_or_fixed_array(return_ty) {
        return type_text_is_slice_or_fixed_array(param_ty) || type_text_is_dynamic_array(param_ty)
    }
    return false
}

borrowed_return_type_text :: proc(returns: Return_Spec) -> (string, bool) {
    if returns.kind == .Single {
        if returns.single_ty == "Data" ||
           type_text_is_dynamic_array(returns.single_ty) ||
           type_text_is_map(returns.single_ty) ||
           type_text_is_string(returns.single_ty) ||
           type_text_is_slice_or_fixed_array(returns.single_ty) {
            return returns.single_ty, true
        }
        return "", false
    }
    if returns.kind == .Named {
        for named in returns.named {
            if named.ty == "Data" ||
               type_text_is_dynamic_array(named.ty) ||
               type_text_is_map(named.ty) ||
               type_text_is_string(named.ty) ||
               type_text_is_slice_or_fixed_array(named.ty) {
                return named.ty, true
            }
        }
    }
    return "", false
}

proc_decl_borrow_owner_arg_index :: proc(proc_decl: ^Proc_Decl) -> (int, bool) {
    return_ty, ok_return := borrowed_return_type_text(proc_decl.returns)
    if !ok_return {
        return -1, false
    }
    for param, idx in proc_decl.params {
        if type_text_can_borrow_return_from_param(return_ty, param.ty) {
            return idx, true
        }
    }
    return -1, false
}

return_spec_is_owned_result :: proc(returns: Return_Spec) -> bool {
    if returns.kind == .Single {
        return type_text_is_owned_result(returns.single_ty)
    }
    if returns.kind == .Named {
        for named in returns.named {
            if type_text_is_owned_result(named.ty) {
                return true
            }
        }
    }
    return false
}

map_type_parts :: proc(text: string) -> (key, value: string, ok: bool) {
    if !type_text_is_map(text) {
        return "", "", false
    }
    split := strings.index(text, "]")
    if split < 0 || split+1 > len(text) {
        return "", "", false
    }
    return text[4:split], text[split+1:], true
}

number_literal_type :: proc(text: string) -> string {
    for ch in text {
        if ch == '.' || ch == 'e' || ch == 'E' {
            return "f64"
        }
    }
    return "int"
}

infer_homogeneous_items_type :: proc(e: ^Emitter, items: []CST_Form, what: string) -> (string, Compile_Error, bool) {
    if len(items) == 0 {
        return "", Compile_Error{message = fmt.tprintf("cannot infer type for empty %s literal; add a type context or use an explicit constructor", what)}, false
    }
    first_ty, err_first, ok_first := infer_literal_value_type(e, items[0])
    if !ok_first {
        return "", err_first, false
    }
    for item in items[1:] {
        item_ty, err_item, ok_item := infer_literal_value_type(e, item)
        if !ok_item {
            return "", err_item, false
        }
        if item_ty != first_ty {
            return "", Compile_Error{message = fmt.tprintf("%s literal must be homogeneous; saw both %s and %s", what, first_ty, item_ty), span = item.span}, false
        }
    }
    return first_ty, Compile_Error{}, true
}

infer_literal_value_type :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    #partial switch form.kind {
    case .Number:
        return number_literal_type(form.text), Compile_Error{}, true
    case .String, .Regex:
        return "string", Compile_Error{}, true
    case .Bool:
        return "bool", Compile_Error{}, true
    case .Keyword:
        mark_keyword_type(e)
        return "keyword", Compile_Error{}, true
    case .Symbol:
        if ty, ok := lookup_local_type(e, map_name(form.text)); ok {
            return ty, Compile_Error{}, true
        }
        return "", Compile_Error{message = fmt.tprintf("cannot infer literal type from symbol %s", form.text), span = form.span}, false
    case .Vector:
        if len(form.items) == 0 {
            return "", Compile_Error{message = "cannot infer type for empty vector literal; add a type context or use arr/empty", span = form.span}, false
        }
        elem_ty, err_elem, ok_elem := infer_homogeneous_items_type(e, form.items[:], "vector")
        if !ok_elem {
            return "", err_elem, false
        }
        return fmt.tprintf("[dynamic]%s", elem_ty), Compile_Error{}, true
    case .Brace:
        if len(form.items) == 0 {
            return "", Compile_Error{message = "cannot infer type for empty map literal; add a type context or use map/empty", span = form.span}, false
        }
        if len(form.items)%2 != 0 {
            return "", Compile_Error{message = "map literal expects key/value pairs", span = form.span}, false
        }
        key_ty, err_key, ok_key := infer_literal_value_type(e, form.items[0])
        if !ok_key {
            return "", err_key, false
        }
        value_ty, err_value, ok_value := infer_literal_value_type(e, form.items[1])
        if !ok_value {
            return "", err_value, false
        }
        i := 2
        for i < len(form.items) {
            next_key_ty, err_next_key, ok_next_key := infer_literal_value_type(e, form.items[i])
            if !ok_next_key {
                return "", err_next_key, false
            }
            if next_key_ty != key_ty {
                return "", Compile_Error{message = fmt.tprintf("map literal keys must be homogeneous; saw both %s and %s", key_ty, next_key_ty), span = form.items[i].span}, false
            }
            next_value_ty, err_next_value, ok_next_value := infer_literal_value_type(e, form.items[i+1])
            if !ok_next_value {
                return "", err_next_value, false
            }
            if next_value_ty != value_ty {
                return "", Compile_Error{message = fmt.tprintf("map literal values must be homogeneous; saw both %s and %s", value_ty, next_value_ty), span = form.items[i+1].span}, false
            }
            i += 2
        }
        return fmt.tprintf("map[%s]%s", key_ty, value_ty), Compile_Error{}, true
    case .Set:
        if len(form.items) == 0 {
            return "", Compile_Error{message = "cannot infer type for empty set literal; add a type context or use set/empty", span = form.span}, false
        }
        elem_ty, err_elem, ok_elem := infer_homogeneous_items_type(e, form.items[:], "set")
        if !ok_elem {
            return "", err_elem, false
        }
        return fmt.tprintf("map[%s]struct{{}}", elem_ty), Compile_Error{}, true
    case .List:
        if len(form.items) == 2 && form.items[0].kind == .Symbol && form.items[1].kind == .Brace {
            head_name := map_name(form.items[0].text)
            if _, ok := find_struct_decl(e, head_name); ok {
                return head_name, Compile_Error{}, true
            }
        }
        return "", Compile_Error{message = "cannot infer inline literal type from this expression", span = form.span}, false
    case .Nil:
        return "", Compile_Error{message = "cannot infer literal type from nil", span = form.span}, false
    }
    return "", Compile_Error{message = "unsupported inline literal type inference", span = form.span}, false
}

indexed_symbol_type :: proc(e: ^Emitter, text: string, span: Span) -> (string, bool) {
    open := strings.index(text, "[")
    if open <= 0 {
        return "", false
    }
    rest := text[open+1:]
    close_rel := strings.index(rest, "]")
    if close_rel < 0 {
        return "", false
    }
    close := open + 1 + close_rel
    base_text := text[:open]
    suffix := text[close+1:]

    base_ty, ok_base_ty := obvious_form_type(e, CST_Form{kind = .Symbol, text = base_text, span = span})
    if !ok_base_ty {
        return "", false
    }

    elem_ty: string
    if _, value_ty, ok_map := map_type_parts(base_ty); ok_map {
        elem_ty = value_ty
    } else {
        ok_elem_ty: bool
        elem_ty, ok_elem_ty = collection_element_type(base_ty)
        if !ok_elem_ty {
            return "", false
        }
    }

    if suffix == "" {
        return elem_ty, true
    }
    if len(suffix) > 1 && suffix[0] == '.' {
        fields, ok_fields := split_field_path_text(suffix[1:])
        if ok_fields {
            defer delete(fields)
            field_ty, _, ok_field_ty := struct_field_type_for_update_path(e, elem_ty, fields[:], "field access", span)
            if ok_field_ty {
                return field_ty, true
            }
        }
    }
    return "", false
}

append_proc_generic_candidates :: proc(values: ^[dynamic]string, text: string) {
    params := generic_type_params_in_text(text)
    defer delete(params)
    for param in params {
        append_unique_text(values, param)
    }
}

proc_decl_generic_candidates :: proc(proc_decl: ^Proc_Decl) -> (values: [dynamic]string) {
    for param in proc_decl.params {
        append_proc_generic_candidates(&values, param.ty)
    }
    #partial switch proc_decl.returns.kind {
    case .Single:
        append_proc_generic_candidates(&values, proc_decl.returns.single_ty)
    case .Named:
        for ret in proc_decl.returns.named {
            append_proc_generic_candidates(&values, ret.ty)
        }
    case:
    }
    return values
}

bind_generic_candidate :: proc(names, types: ^[dynamic]string, candidates: []string, expected, actual: string) -> bool {
    name := expected
    if strings.has_prefix(name, "$") {
        name = name[1:]
    }
    if !generic_param_in_slice(candidates, name) {
        return true
    }
    if actual == name || actual == fmt.tprintf("$%s", name) {
        return true
    }
    for existing, idx in names^ {
        if existing == name {
            return types^[idx] == actual
        }
    }
    append(names, name)
    append(types, actual)
    return true
}

proc_type_param_types :: proc(ty: string) -> (types: [dynamic]string, ok: bool) {
    if !strings.has_prefix(ty, "proc(") {
        return types, false
    }
    close := strings.index(ty, ")")
    if close < len("proc(") {
        return types, false
    }
    parts := split_top_level_commas(ty[len("proc("):close])
    defer delete(parts)
    for part in parts {
        trimmed := strings.trim_space(part)
        if trimmed == "" {
            continue
        }
        colon := top_level_colon_index(trimmed)
        if colon >= 0 {
            append(&types, strings.clone(strings.trim_space(trimmed[colon+1:])))
        } else {
            append(&types, strings.clone(trimmed))
        }
    }
    return types, true
}

bind_generic_candidates_from_types :: proc(names, types: ^[dynamic]string, candidates: []string, expected, actual: string) -> bool {
    if !bind_generic_candidate(names, types, candidates, expected, actual) {
        return false
    }

    if strings.has_prefix(expected, "^") && strings.has_prefix(actual, "^") {
        return bind_generic_candidates_from_types(names, types, candidates, expected[1:], actual[1:])
    }

    expected_elem, ok_expected_elem := collection_element_type(expected)
    actual_elem, ok_actual_elem := collection_element_type(actual)
    if ok_expected_elem && ok_actual_elem {
        return bind_generic_candidates_from_types(names, types, candidates, expected_elem, actual_elem)
    }

    if expected_key, expected_value, ok_expected_map := map_type_parts(expected); ok_expected_map {
        if actual_key, actual_value, ok_actual_map := map_type_parts(actual); ok_actual_map {
            return bind_generic_candidates_from_types(names, types, candidates, expected_key, actual_key) &&
                   bind_generic_candidates_from_types(names, types, candidates, expected_value, actual_value)
        }
    }

    expected_params, ok_expected_proc := proc_type_param_types(expected)
    if ok_expected_proc {
        defer delete(expected_params)
        actual_params, ok_actual_proc := proc_type_param_types(actual)
        if ok_actual_proc {
            defer delete(actual_params)
            if len(expected_params) == len(actual_params) {
                for expected_param, idx in expected_params {
                    if !bind_generic_candidates_from_types(names, types, candidates, expected_param, actual_params[idx]) {
                        return false
                    }
                }
            }
        }
        expected_return, ok_expected_return := proc_type_single_return_type(expected)
        actual_return, ok_actual_return := proc_type_single_return_type(actual)
        if ok_expected_return && ok_actual_return {
            return bind_generic_candidates_from_types(names, types, candidates, expected_return, actual_return)
        }
    }

    return true
}

bind_proc_callback_generic_candidates :: proc(e: ^Emitter, names, types: ^[dynamic]string, candidates: []string, expected_ty: string, arg: CST_Form) -> bool {
    if !strings.has_prefix(expected_ty, "proc(") {
        return true
    }

    return_ty, ok_return_ty := proc_type_single_return_type(expected_ty)
    if ok_return_ty {
        if actual_return_ty, ok_actual_return_ty := source_callback_return_item_type(e, arg); ok_actual_return_ty {
            if !bind_generic_candidate(names, types, candidates, return_ty, actual_return_ty) {
                return false
            }
        }
    }

    if arg.kind != .Symbol {
        return true
    }
    actual_name := map_name(arg.text)
    actual_decl, ok_actual_decl := find_proc_decl(e, actual_name)
    if !ok_actual_decl || len(actual_decl.params) == 0 {
        return true
    }
    open := strings.index(expected_ty, "(")
    close := strings.index(expected_ty, ")")
    if open < 0 || close <= open+1 {
        return true
    }
    expected_param_ty := strings.trim_space(expected_ty[open+1:close])
    return bind_generic_candidate(names, types, candidates, expected_param_ty, actual_decl.params[0].ty)
}

proc_decl_obvious_call_return_type :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, args: []CST_Form) -> (string, bool) {
    if proc_decl.returns.kind != .Single {
        return "", false
    }

    names, types, ok_bindings := proc_decl_call_type_bindings(e, proc_decl, args)
    if !ok_bindings {
        return "", false
    }
    defer delete(names)
    defer delete(types)

    return substitute_type_names(proc_decl.returns.single_ty, names[:], types[:]), true
}

overload_obvious_call_return_type :: proc(e: ^Emitter, overload_name: string, args: []CST_Form) -> (string, bool) {
    overload_decl, ok_overload := find_overload_decl(e, overload_name)
    if !ok_overload {
        return "", false
    }
    selected := ""
    for member in overload_decl.overload_members {
        proc_decl, ok_proc := find_proc_decl(e, member)
        if !ok_proc || !proc_accepts_positional_arg_count(proc_decl, len(args)) {
            continue
        }
        return_ty, ok_return_ty := proc_decl_obvious_call_return_type(e, proc_decl, args)
        if !ok_return_ty {
            return "", false
        }
        if selected == "" {
            selected = return_ty
        } else if selected != return_ty {
            delete(return_ty)
            delete(selected)
            return "", false
        } else {
            delete(return_ty)
        }
    }
    return selected, selected != ""
}

proc_decl_call_type_bindings :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, args: []CST_Form) -> (names: [dynamic]string, types: [dynamic]string, ok: bool) {
    candidates := proc_decl_generic_candidates(proc_decl)
    defer delete(candidates)
    if len(candidates) == 0 {
        return names, types, true
    }

    for param, idx in proc_decl.params {
        if idx >= len(args) {
            break
        }
        if !bind_proc_callback_generic_candidates(e, &names, &types, candidates[:], param.ty, args[idx]) {
            return names, types, false
        }
        if actual_ty, ok_actual_ty := obvious_form_type(e, args[idx]); ok_actual_ty {
            if !bind_generic_candidates_from_types(&names, &types, candidates[:], param.ty, actual_ty) {
                return names, types, false
            }
        }
    }

    for candidate in candidates {
        if !generic_param_in_slice(names[:], candidate) &&
           (type_text_mentions_generic_param(proc_decl.returns.single_ty, candidate) || strings.contains(proc_decl.returns.single_ty, candidate)) {
            return names, types, false
        }
    }

    return names, types, true
}

specialize_params :: proc(params: []Param, names, types: []string) -> (out: [dynamic]Param) {
    for param in params {
        specialized := param
        specialized.ty = substitute_type_names(param.ty, names, types)
        append(&out, specialized)
    }
    return out
}

specialize_return_spec :: proc(returns: Return_Spec, names, types: []string) -> Return_Spec {
    specialized := returns
    #partial switch returns.kind {
    case .Single:
        specialized.single_ty = substitute_type_names(returns.single_ty, names, types)
    case .Named:
        named: [dynamic]Named_Return
        for ret in returns.named {
            append(&named, Named_Return{
                name = ret.name,
                ty = substitute_type_names(ret.ty, names, types),
                ownership = ret.ownership,
            })
        }
        specialized.named = named
    case:
    }
    return specialized
}

proc_decl_specialized_signature_for_args :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, args: []CST_Form) -> (params: [dynamic]Param, returns: Return_Spec, ok: bool) {
    names, types, ok_bindings := proc_decl_call_type_bindings(e, proc_decl, args)
    if !ok_bindings {
        return params, returns, false
    }
    defer delete(names)
    defer delete(types)
    if len(names) == 0 {
        for param in proc_decl.params {
            append(&params, param)
        }
        return params, proc_decl.returns, true
    }
    return specialize_params(proc_decl.params[:], names[:], types[:]), specialize_return_spec(proc_decl.returns, names[:], types[:]), true
}

obvious_form_type :: proc(e: ^Emitter, form: CST_Form) -> (string, bool) {
    if form.kind == .List && len(form.items) == 3 && is_symbol(form.items[0], "__kvist_index") {
        target_ty, ok_target_ty := obvious_form_type(e, form.items[1])
        if !ok_target_ty {
            return "", false
        }
        if _, value_ty, ok_map := map_type_parts(target_ty); ok_map {
            return value_ty, true
        }
        return collection_element_type(target_ty)
    }
    if target_form, fields, field_span, ok_place := field_path_place_parts(form); ok_place {
        target_ty, ok_target_ty := obvious_form_type(e, target_form)
        if !ok_target_ty {
            return "", false
        }
        ty, _, ok_ty := struct_field_type_for_update_path(e, target_ty, fields[:], "field access", field_span)
        return ty, ok_ty
    }
    if form.kind == .Symbol {
        if ty, ok := known_form_type(e, form); ok {
            return ty, true
        }
        if symbol_is_simple_deref_suffix(form.text) {
            if ty, ok := lookup_local_type(e, map_name(form.text[:len(form.text)-1])); ok && len(ty) > 0 && ty[0] == '^' {
                return ty[1:], true
            }
            return "", false
        }
        if ty, ok := indexed_symbol_type(e, form.text, form.span); ok {
            return ty, true
        }
        if ty, ok := lookup_local_type(e, map_name(form.text)); ok {
            return ty, true
        }
        name := map_name(form.text)
        ensure_emitter_indexes(e)
        if idx, found := e.const_indices[name]; found {
            decl := &e.decls[idx]
            if decl.const_decl.has_ty {
                return decl.const_decl.ty, true
            }
            if decl.const_decl.value.kind == .List &&
               len(decl.const_decl.value.items) == 2 &&
               is_symbol(decl.const_decl.value.items[0], "quote") {
                return "Data", true
            }
            // An unannotated static `def` still has the type of its literal
            // initializer. This matters when the symbol appears inside a
            // contextually-Data collection: the value must be lifted rather
            // than emitted as a native value in an Odin []Data literal.
            if ty, _, ok_ty := infer_literal_value_type(e, decl.const_decl.value); ok_ty {
                return ty, true
            }
        }
        return "", false
    }
    if form.kind == .Number || form.kind == .String || form.kind == .Regex || form.kind == .Bool || form.kind == .Keyword {
        if ty, _, ok := infer_literal_value_type(e, form); ok {
            return ty, true
        }
    }
    if form.kind == .List && len(form.items) >= 2 && len(form.items) <= 3 {
        if form.items[0].kind == .Keyword {
            return "Data", true
        }
        if form.items[0].kind == .Symbol {
            if head_ty, ok_head_ty := obvious_form_type(e, form.items[0]); ok_head_ty && head_ty == "Data" {
                return "Data", true
            }
        }
    }
    if form.kind == .List && len(form.items) == 2 && form.items[0].kind == .Symbol && form.items[1].kind == .Brace {
        head_name := map_name(form.items[0].text)
        if _, ok := find_struct_decl(e, head_name); ok {
            return head_name, true
        }
    }
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        // Scalar conversion forms are also type-producing expressions. Keep
        // their obvious type so a surrounding block-expression IIFE can
        // capture the converted local with an explicit parameter type.
        if len(form.items) == 2 {
            conversion_ty := normalize_surface_type_symbol(form.items[0].text)
            if type_text_is_builtin_odin_scalar(conversion_ty) {
                return conversion_ty, true
            }
        }
        if is_symbol(form.items[0], "quote") && len(form.items) == 2 {
            return "Data", true
        }
        if is_symbol(form.items[0], "quasiquote") && len(form.items) == 2 {
            return "Data", true
        }
        if is_symbol(form.items[0], "if") && len(form.items) == 4 {
            then_ty, ok_then_ty := obvious_form_type(e, form.items[2])
            else_ty, ok_else_ty := obvious_form_type(e, form.items[3])
            if ok_then_ty && ok_else_ty && then_ty == else_ty {
                return then_ty, true
            }
        }
        if is_symbol(form.items[0], "let") || form_head_is_do(form) || form_head_is_case(form) || form_head_is_match(form) {
            return obvious_block_expr_type(e, form)
        }
        if strings.has_prefix(form.items[0].text, "data.") || strings.has_prefix(form.items[0].text, "data/") {
            member := form.items[0].text[len("data."):]
            if strings.has_prefix(form.items[0].text, "data/") {
                member = form.items[0].text[len("data/"):]
            }
            switch member {
            case "item-at", "key-at", "value-at", "tagged-value", "retain": return "Data", true
            case "int": return "i64", true
            case "float": return "f64", true
            case "bool", "nil?", "bool?", "int?", "float?", "string?", "symbol?", "keyword?", "list?", "vector?", "map?", "set?", "tagged?": return "bool", true
            case "string", "keyword", "symbol", "text", "tag": return "string", true
            case "count": return "int", true
            case "kind": return "Data_Kind", true
            }
        }
        head_name := map_name(form.items[0].text)
        if proc_ty, ok_proc_ty := lookup_local_type(e, head_name); ok_proc_ty && type_text_is_proc(proc_ty) {
            if return_ty, ok_return_ty := proc_type_single_return_type(proc_ty); ok_return_ty {
                return return_ty, true
            }
        }
        if (head_is_core_assoc(form.items[0].text) ||
            head_is_core_update(form.items[0].text) ||
            head_is_core_dissoc(form.items[0].text)) &&
           len(form.items) >= 2 {
            return shallow_update_return_type(e, form)
        }
        if form_head_is_as_thread(form) {
            return obvious_as_thread_type(e, form)
        }
        if head_name == "odin_slice" && len(form.items) >= 2 {
            source_ty, ok_source_ty := obvious_form_type(e, form.items[1])
            if ok_source_ty {
                if type_text_is_string(source_ty) {
                    return "string", true
                }
                elem_ty, ok_elem_ty := collection_element_type(source_ty)
                if ok_elem_ty {
                    return fmt.tprintf("[]%s", elem_ty), true
                }
            }
        }
        if head_name == "odin_get" && len(form.items) >= 3 {
            if source_ty, ok_source_ty := obvious_form_type(e, form.items[1]); ok_source_ty && source_ty == "Data" {
                return "Data", true
            }
        }
        if form.items[0].text == "into" && len(form.items) >= 4 {
            ty, _, _, ok_ty := parse_type_text_from_forms(form.items[:], 1)
            return ty, ok_ty
        }
        if form.items[0].text == "transduce" && len(form.items) == 5 {
            return obvious_form_type(e, form.items[3])
        }
        if source, ok_source_call := source_call_decl(e, form); ok_source_call {
            if item_ty, _, ok_item_ty := source_call_item_type(e, source, form); ok_item_ty {
                return fmt.tprintf("[dynamic]%s", item_ty), true
            }
            return fmt.tprintf("[dynamic]%s", source.item_ty), true
        }
        if form.items[0].text == "thread-start" {
            spec, _, ok_spec := thread_start_signature(e, form)
            if ok_spec {
                return thread_task_type(spec), true
            }
        }
        if _, proc_decl, ok := resolve_proc_call_decl(e, form.items[0].text); ok && proc_decl != nil {
            return proc_decl_obvious_call_return_type(e, proc_decl, form.items[1:])
        }
        if return_ty, ok_return_ty := overload_obvious_call_return_type(e, head_name, form.items[1:]); ok_return_ty {
            return return_ty, true
        }
    }
    if form.kind == .Vector || form.kind == .Brace || form.kind == .Set {
        if ty, _, ok := infer_literal_value_type(e, form); ok {
            return ty, true
        }
    }
    return "", false
}

emit_set_literal :: proc(e: ^Emitter, elem_type: string, form: CST_Form) -> (string, Compile_Error, bool) {
    values, err_values, ok_values := emit_vector_item_texts(e, form, elem_type)
    if !ok_values {
        return "", err_values, false
    }
    if !has_multiline_items(values[:]) {
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        strings.write_string(&builder, "map[")
        strings.write_string(&builder, elem_type)
        strings.write_string(&builder, "]struct{}{")
        for value, idx in values {
            if idx > 0 {
                strings.write_string(&builder, ", ")
            }
            strings.write_string(&builder, value)
            strings.write_string(&builder, " = {}")
        }
        strings.write_byte(&builder, '}')
        return strings.clone(strings.to_string(builder)), Compile_Error{}, true
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "map[")
    strings.write_string(&builder, elem_type)
    strings.write_string(&builder, "]struct{}{\n")
    for value in values {
        append_indented_multiline(&builder, fmt.tprintf("%s = {{}}", value), "    ", ",")
        strings.write_byte(&builder, '\n')
    }
    strings.write_byte(&builder, '}')
    return strings.clone(strings.to_string(builder)), Compile_Error{}, true
}

emit_inferred_literal :: proc(e: ^Emitter, form: CST_Form, expected_type := "") -> (string, Compile_Error, bool) {
    #partial switch form.kind {
    case .Vector:
        prefix := expected_type
        if prefix == "" {
            elem_ty, err_elem, ok_elem := infer_homogeneous_items_type(e, form.items[:], "vector")
            if !ok_elem {
                return "", err_elem, false
            }
            prefix = fmt.tprintf("[dynamic]%s", elem_ty)
        }
        if type_text_is_dynamic_soa(prefix) {
            return emit_dynamic_soa_vector_literal(e, prefix, form)
        }
        if type_text_is_dynamic_array(prefix) {
            mark_dynamic_literals(e)
        }
        return emit_vector_literal(e, prefix, form)
    case .Brace:
        prefix := expected_type
        if prefix == "" {
            if len(form.items) == 0 {
                return emit_brace_literal(e, "", form)
            }
            inferred, err_inferred, ok_inferred := infer_literal_value_type(e, form)
            if !ok_inferred {
                return "", err_inferred, false
            }
            prefix = inferred
        } else if !type_text_is_map(prefix) {
            return emit_brace_literal(e, prefix, form)
        }
        mark_dynamic_literals(e)
        return emit_brace_literal(e, prefix, form)
    case .Set:
        elem_ty := ""
        if expected_type != "" {
            expected_elem, ok_elem := set_element_type(expected_type)
            if !ok_elem {
                return "", Compile_Error{message = fmt.tprintf("set literal does not match expected type %s", expected_type), span = form.span}, false
            }
            elem_ty = expected_elem
        } else {
            inferred, err_inferred, ok_inferred := infer_literal_value_type(e, form)
            if !ok_inferred {
                return "", err_inferred, false
            }
            inferred_elem, ok_elem := set_element_type(inferred)
            if !ok_elem {
                return "", Compile_Error{message = "internal error inferring set literal type", span = form.span}, false
            }
            elem_ty = inferred_elem
        }
        mark_dynamic_literals(e)
        return emit_set_literal(e, elem_ty, form)
    }
    return "", Compile_Error{message = "internal error: expected literal form", span = form.span}, false
}

emit_typed_literal_value :: proc(e: ^Emitter, type_form: CST_Form, type_text: string, value: CST_Form) -> (string, Compile_Error, bool, bool) {
    #partial switch value.kind {
    case .Vector:
        if type_form_needs_dynamic_literals(type_form) {
            mark_dynamic_literals(e)
        }
        if type_text_is_dynamic_soa(type_text) {
            text, err, ok := emit_dynamic_soa_vector_literal(e, type_text, value)
            return text, err, ok, true
        }
        text, err, ok := emit_vector_literal(e, type_text, value)
        return text, err, ok, true
    case .Brace:
        struct_decl, ok_struct := find_struct_decl(e, type_text)
        if ok_struct {
            err_struct, ok_struct_ctor := validate_struct_constructor(e, struct_decl, value)
            if !ok_struct_ctor {
                return "", err_struct, false, true
            }
            text, err, ok := emit_struct_brace_literal(e, struct_decl, value)
            return text, err, ok, true
        }
        text, err, ok := emit_inferred_literal(e, value, type_text)
        return text, err, ok, true
    case .Set:
        text, err, ok := emit_inferred_literal(e, value, type_text)
        return text, err, ok, true
    }
    return "", Compile_Error{}, false, false
}

push_local_type_scope :: proc(e: ^Emitter) {
    append(&e.local_type_scope_marks, len(e.local_types))
    append(&e.local_struct_scope_marks, len(e.local_structs))
    append(&e.local_union_scope_marks, len(e.local_unions))
    append(&e.callback_context_scope_marks, len(e.callback_contexts))
}

pop_local_type_scope :: proc(e: ^Emitter) {
    if len(e.local_type_scope_marks) == 0 {
        return
    }
    mark := e.local_type_scope_marks[len(e.local_type_scope_marks)-1]
    resize(&e.local_type_scope_marks, len(e.local_type_scope_marks)-1)
    resize(&e.local_types, mark)

    struct_mark := e.local_struct_scope_marks[len(e.local_struct_scope_marks)-1]
    resize(&e.local_struct_scope_marks, len(e.local_struct_scope_marks)-1)
    resize(&e.local_structs, struct_mark)

    union_mark := e.local_union_scope_marks[len(e.local_union_scope_marks)-1]
    resize(&e.local_union_scope_marks, len(e.local_union_scope_marks)-1)
    resize(&e.local_unions, union_mark)

    callback_mark := e.callback_context_scope_marks[len(e.callback_context_scope_marks)-1]
    resize(&e.callback_context_scope_marks, len(e.callback_context_scope_marks)-1)
    resize(&e.callback_contexts, callback_mark)
}

bind_local_type :: proc(e: ^Emitter, name, ty: string) {
    append(&e.local_types, Param{name = name, ty = ty})
}

bind_managed_local_owner :: proc(e: ^Emitter, name, owner_flag: string) {
    for i := len(e.local_types) - 1; i >= 0; i -= 1 {
        if e.local_types[i].name == name {
            e.local_types[i].owner_flag = owner_flag
            return
        }
    }
}

lookup_managed_local_owner :: proc(e: ^Emitter, name: string) -> (string, bool) {
    for i := len(e.local_types) - 1; i >= 0; i -= 1 {
        if e.local_types[i].name == name && e.local_types[i].owner_flag != "" {
            return e.local_types[i].owner_flag, true
        }
    }
    return "", false
}

lookup_local_type :: proc(e: ^Emitter, name: string) -> (string, bool) {
    for i := len(e.local_types) - 1; i >= 0; i -= 1 {
        if e.local_types[i].name == name {
            return e.local_types[i].ty, true
        }
    }
    return "", false
}

bind_callback_context :: proc(e: ^Emitter, name: string, capture_names: []string) {
    ctx := Callback_Context{name = name}
    for capture_name in capture_names {
        append(&ctx.capture_names, capture_name)
    }
    append(&e.callback_contexts, ctx)
}

bind_field_callback_context :: proc(e: ^Emitter, name, field: string) {
    append(&e.callback_contexts, Callback_Context{name = name, field_selector = field})
}

lookup_callback_context :: proc(e: ^Emitter, name: string) -> (^Callback_Context, bool) {
    for i := len(e.callback_contexts) - 1; i >= 0; i -= 1 {
        if e.callback_contexts[i].name == name {
            return &e.callback_contexts[i], true
        }
    }
    return nil, false
}

known_form_type :: proc(e: ^Emitter, form: CST_Form) -> (string, bool) {
    if form.kind == .Symbol {
        name := form.text
        if symbol_is_simple_deref_suffix(name) {
            if ty, ok := lookup_local_type(e, map_name(name[:len(name)-1])); ok && len(ty) > 0 && ty[0] == '^' {
                return ty[1:], true
            }
            return "", false
        }
        dot := strings.index(name, ".")
        if dot > 0 && dot+1 < len(name) {
            base_name := map_name(name[:dot])
            defer delete(base_name)
            if target_ty, ok_target := lookup_local_type(e, base_name); ok_target {
                fields, ok_fields := split_field_path_text(name[dot+1:])
                if ok_fields {
                    defer delete(fields)
                    field_ty, _, ok_field_ty := struct_field_type_for_update_path(e, target_ty, fields[:], "field access", form.span)
                    if ok_field_ty {
                        return field_ty, true
                    }
                }
            }
        }
        return lookup_local_type(e, map_name(name))
    }
    return "", false
}

obvious_binding_type :: proc(e: ^Emitter, binding: Binding) -> (string, bool) {
    if binding.is_destructure || binding.name == "" {
        return "", false
    }
    if binding.is_typed {
        return binding.ty, true
    }
    if binding.value.kind == .List && len(binding.value.items) > 0 && binding.value.items[0].kind == .Symbol {
        switch binding.value.items[0].text {
        case "str", "core.str", "core/str", "fmt.aprintf", "fmt/aprintf":
            return "string", true
        case:
        }
        if form_is_owned_alloc_call(binding.value, .String, e) {
            return "string", true
        }
    }
    if binding.value.kind == .Symbol {
        return obvious_form_type(e, binding.value)
    }
    if binding.value.kind == .Number || binding.value.kind == .String || binding.value.kind == .Regex || binding.value.kind == .Bool {
        if ty, _, ok := infer_literal_value_type(e, binding.value); ok {
            return ty, true
        }
    }
    if ty, ok := obvious_form_type(e, binding.value); ok {
        return ty, true
    }
    if binding.value.kind == .List && len(binding.value.items) == 2 && binding.value.items[0].kind == .Symbol && binding.value.items[1].kind == .Brace {
        head_name := map_name(binding.value.items[0].text)
        if _, ok := find_struct_decl(e, head_name); ok {
            return head_name, true
        }
    }
    if binding.value.kind == .List && len(binding.value.items) >= 2 && binding.value.items[0].kind == .Symbol {
        head := binding.value.items[0].text
        if head == "make" {
            type_text, _, ok_type := parse_type_text(binding.value.items[1])
            if ok_type {
                return type_text, true
            }
        }
    }
    if binding.value.kind == .List &&
       len(binding.value.items) == 2 &&
       (binding.value.items[1].kind == .Vector || binding.value.items[1].kind == .Brace || binding.value.items[1].kind == .Set) {
        type_text, _, ok_type := parse_type_text(binding.value.items[0])
        if ok_type {
            return type_text, true
        }
    }
    if binding.value.kind == .List && len(binding.value.items) > 0 && binding.value.items[0].kind == .Symbol {
        head := binding.value.items[0].text
        head_name := map_name(head)
        if (head_is_core_assoc(head) || head_is_core_update(head) || head_is_core_dissoc(head)) &&
           len(binding.value.items) >= 2 {
            return shallow_update_return_type(e, binding.value)
        }
        if form_head_is_as_thread(binding.value) {
            return obvious_as_thread_type(e, binding.value)
        }
        if head == "into" && len(binding.value.items) >= 4 {
            ty, _, _, ok_ty := parse_type_text_from_forms(binding.value.items[:], 1)
            return ty, ok_ty
        }
        if head == "transduce" && len(binding.value.items) == 5 {
            return obvious_form_type(e, binding.value.items[3])
        }
        if head == "thread-start" {
            spec, _, ok_spec := thread_start_signature(e, binding.value)
            if ok_spec {
                return thread_task_type(spec), true
            }
        }
        if proc_decl, ok := find_proc_decl(e, head_name); ok {
            return proc_decl_obvious_call_return_type(e, proc_decl, binding.value.items[1:])
        }
    }
    if binding.value.kind == .Vector || binding.value.kind == .Brace || binding.value.kind == .Set {
        if ty, _, ok := infer_literal_value_type(e, binding.value); ok {
            return ty, true
        }
    }
    return "", false
}

bind_obvious_binding_types :: proc(e: ^Emitter, binding: Binding) {
    if binding_is_data_destructure(e, binding) {
        names: [dynamic]string
        if _, ok_pattern := validate_data_pattern_names(binding.target, &names, true); ok_pattern {
            for name in names {
                bind_local_type(e, name, "Data")
            }
        }
        delete(names)
        return
    }
    if binding.is_destructure || binding.is_result_binding {
        if binding.value.kind == .List && len(binding.value.items) > 0 && binding.value.items[0].kind == .Symbol {
            head_name := map_name(binding.value.items[0].text)
            defer delete(head_name)
            if head_name == "decode_data" && len(binding.pattern) == 3 && len(binding.value.items) >= 2 {
                if target_ty, _, ok_target_ty := parse_type_text(binding.value.items[1]); ok_target_ty {
                    if binding.pattern[0] != "" {
                        bind_local_type(e, binding.pattern[0], target_ty)
                    }
                    if binding.pattern[1] != "" {
                        bind_local_type(e, binding.pattern[1], "data__Decode_Error")
                    }
                    if binding.pattern[2] != "" {
                        bind_local_type(e, binding.pattern[2], "bool")
                    }
                }
                return
            }
            if head_name == "validate_data" && len(binding.pattern) == 2 {
                if binding.pattern[0] != "" {
                    bind_local_type(e, binding.pattern[0], "data__Decode_Error")
                }
                if binding.pattern[1] != "" {
                    bind_local_type(e, binding.pattern[1], "bool")
                }
                return
            }
            if proc_decl, ok := find_proc_decl(e, head_name); ok && proc_decl.returns.kind == .Named && len(proc_decl.returns.named) == len(binding.pattern) {
                for name, idx in binding.pattern {
                    if name != "" {
                        bind_local_type(e, name, proc_decl.returns.named[idx].ty)
                    }
                }
            }
        }
        return
    }
    if ty, ok_ty := obvious_binding_type(e, binding); ok_ty {
        bind_local_type(e, binding.name, ty)
    }
}
