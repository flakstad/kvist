// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "base:runtime"

expand_user_macro_call :: proc(macro_decl: User_Macro, call: CST_Form, macros: []User_Macro) -> (CST_Form, Compile_Error, bool) {
    value, err_value, ok_value := invoke_user_macro_value(macro_decl, call, macros)
    if !ok_value {
        return CST_Form{}, err_value, false
    }
    expanded, err_form, ok_form := macro_value_to_owned_form(value, call.span)
    if !ok_form {
        macro_value_delete_backing(&value)
        return CST_Form{}, err_form, false
    }
    macro_value_delete_backing(&value)
    if expanded.span.start == 0 && expanded.span.end == 0 {
        expanded.span = call.span
    }
    return expanded, Compile_Error{}, true
}

expand_user_macro_call_to_forms :: proc(macro_decl: User_Macro, call: CST_Form, macros: []User_Macro) -> ([]CST_Form, Compile_Error, bool) {
    value, err_value, ok_value := invoke_user_macro_value(macro_decl, call, macros)
    if !ok_value {
        return nil, err_value, false
    }
    forms, err_forms, ok_forms := macro_value_to_owned_forms(value, call.span)
    macro_value_delete_backing(&value)
    return forms, err_forms, ok_forms
}

macro_emit_expanded_form :: proc(e: ^Macro_Expander, indent: string, form: CST_Form, macros: []User_Macro, suffix: string = "") -> (Compile_Error, bool) {
    expanded, err_expand, ok_expand := macroexpand_form_with_macros(form, macros)
    if !ok_expand {
        return err_expand, false
    }
    defer delete(expanded.output)
    defer delete(expanded.source_map)

    start_line := e.line
    text_end := len(expanded.output)
    if text_end > 0 && expanded.output[text_end-1] == '\n' {
        text_end -= 1
    }

    start := 0
    i := 0
    for i < text_end {
        if expanded.output[i] == '\n' {
            strings.write_string(&e.builder, indent)
            strings.write_string(&e.builder, expanded.output[start:i])
            strings.write_byte(&e.builder, '\n')
            e.line += 1
            start = i + 1
        }
        i += 1
    }
    strings.write_string(&e.builder, indent)
    strings.write_string(&e.builder, expanded.output[start:text_end])
    strings.write_string(&e.builder, suffix)
    strings.write_byte(&e.builder, '\n')
    e.line += 1

    if len(expanded.source_map) == 0 {
        macro_record_source_map(e, start_line, e.line-1, form.span)
        return {}, true
    }

    for entry in expanded.source_map {
        adjusted := entry
        adjusted.generated_start_line = start_line + entry.generated_start_line - 1
        adjusted.generated_end_line = start_line + entry.generated_end_line - 1
        append(e.source_map, adjusted)
    }
    return {}, true
}

macro_emit_body_form :: proc(e: ^Macro_Expander, item: CST_Form, macros: []User_Macro, suffix: string) -> (Compile_Error, bool) {
    return macro_emit_expanded_form(e, "    ", item, macros, suffix)
}

write_macro_form :: proc(builder: ^strings.Builder, form: CST_Form) {
    #partial switch form.kind {
    case .List:
        if len(form.items) == 3 &&
           form.items[0].kind == .Symbol &&
           form.items[0].text == "__kvist_field" &&
           form.items[2].kind == .Symbol {
            write_macro_form(builder, form.items[1])
            strings.write_byte(builder, '.')
            strings.write_string(builder, form.items[2].text)
            return
        }
        if len(form.items) == 2 &&
           form.items[0].kind == .Symbol &&
           len(form.items[0].text) > 1 &&
           form.items[0].text[0] == '.' {
            write_macro_form(builder, form.items[1])
            strings.write_string(builder, form.items[0].text)
            return
        }
        strings.write_byte(builder, '(')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            write_macro_form(builder, item)
        }
        strings.write_byte(builder, ')')
    case .Vector:
        strings.write_byte(builder, '[')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            write_macro_form(builder, item)
        }
        strings.write_byte(builder, ']')
    case .Brace:
        strings.write_byte(builder, '{')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            write_macro_form(builder, item)
        }
        strings.write_byte(builder, '}')
    case .Symbol, .Keyword, .String, .Regex, .Number, .Bool, .Nil:
        strings.write_string(builder, form.text)
    }
}

write_macro_expanded_output :: proc(builder: ^strings.Builder, output: string) {
    text_end := len(output)
    if text_end > 0 && output[text_end-1] == '\n' {
        text_end -= 1
    }
    strings.write_string(builder, output[:text_end])
}

macroexpand_cst_child_forms_with_macros :: proc(form: CST_Form, macros: []User_Macro) -> (expanded: [dynamic]CST_Form, err: Compile_Error, ok: bool) {
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if user_macro, ok_user := find_user_macro(macros, form.items[0].text); ok_user {
            forms_out, err_user, ok_user_expand := expand_user_macro_call_to_forms(user_macro, form, macros)
            if !ok_user_expand {
                return expanded, err_user, false
            }
            defer {
                for i in 0 ..< len(forms_out) {
                    delete_cst_form(&forms_out[i])
                }
                delete(forms_out)
            }
            for form_out in forms_out {
                nested, err_nested, ok_nested := macroexpand_cst_child_forms_with_macros(form_out, macros)
                if !ok_nested {
                    delete_cst_form_slice(&expanded)
                    return expanded, err_nested, false
                }
                for nested_form in nested {
                    append(&expanded, nested_form)
                }
                delete(nested)
            }
            return expanded, Compile_Error{}, true
        }
    }

    child, err_child, ok_child := macroexpand_cst_form_with_macros(form, macros)
    if !ok_child {
        return expanded, err_child, false
    }
    append(&expanded, child)
    return expanded, Compile_Error{}, true
}

macroexpand_cst_form_with_macros :: proc(form: CST_Form, macros: []User_Macro) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    #partial switch form.kind {
    case .List:
        if len(form.items) > 0 && form.items[0].kind == .Symbol {
            if form.items[0].text == "quote" {
                return clone_cst_form(form), Compile_Error{}, true
            }
            switch form.items[0].text {
            case "def", "def-", "defvar", "defvar-":
                return macroexpand_def_binding_form_preserving_types(form, macros)
            case "defstruct", "defstruct-", "defunion", "defunion-":
                return clone_cst_form(form), Compile_Error{}, true
            case "defn", "defn-":
                return macroexpand_defn_form_preserving_types(form, macros)
            }
            if user_macro, ok_user := find_user_macro(macros, form.items[0].text); ok_user {
                expanded, err_user, ok_user_expand := expand_user_macro_call(user_macro, form, macros)
                if !ok_user_expand {
                    return CST_Form{}, err_user, false
                }
                defer delete_cst_form(&expanded)
                return macroexpand_cst_form_with_macros(expanded, macros)
            }
        }
        expanded = CST_Form{kind = form.kind, span = form.span}
        if form.text != "" {
            expanded.text = strings.clone(form.text)
        }
        if form.source_text != "" {
            expanded.source_text = strings.clone(form.source_text)
        }
        i := 0
        for i < len(form.items) {
            item := form.items[i]
            if macroexpand_item_starts_type_operand(form, i) {
                _, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], i)
                if !ok_type {
                    delete_cst_form(&expanded)
                    return CST_Form{}, err_type, false
                }
                for type_item in form.items[i:next_i] {
                    append(&expanded.items, clone_cst_form(type_item))
                }
                i = next_i
                continue
            }
            children, err_child, ok_child := macroexpand_cst_child_forms_with_macros(item, macros)
            if !ok_child {
                delete_cst_form(&expanded)
                return CST_Form{}, err_child, false
            }
            for child in children {
                append(&expanded.items, child)
            }
            delete(children)
            i += 1
        }
        return expanded, Compile_Error{}, true
    case .Vector, .Brace, .Set:
        expanded = CST_Form{kind = form.kind, span = form.span}
        if form.text != "" {
            expanded.text = strings.clone(form.text)
        }
        if form.source_text != "" {
            expanded.source_text = strings.clone(form.source_text)
        }
        for item in form.items {
            child, err_child, ok_child := macroexpand_cst_form_with_macros(item, macros)
            if !ok_child {
                delete_cst_form(&expanded)
                return CST_Form{}, err_child, false
            }
            append(&expanded.items, child)
        }
        return expanded, Compile_Error{}, true
    case:
        return clone_cst_form(form), Compile_Error{}, true
    }
}

macroexpand_item_starts_type_operand :: proc(form: CST_Form, idx: int) -> bool {
    if idx == 0 && form.items[idx].kind == .List {
        if _, _, ok_type := parse_type_text(form.items[idx]); ok_type {
            return true
        }
    }
    if len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    head := form.items[0].text
    if idx == 1 && (head == "make" || head == "alloc" || head == "zero" || head == "transmute") {
        return true
    }
    if idx == 2 && head == "type-assert" {
        return true
    }
    return false
}

macroexpand_def_binding_form_preserving_types :: proc(form: CST_Form, macros: []User_Macro) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 {
        return clone_cst_form(form), Compile_Error{}, true
    }
    expanded = CST_Form{kind = form.kind, span = form.span}
    if form.text != "" {
        expanded.text = strings.clone(form.text)
    }
    if form.source_text != "" {
        expanded.source_text = strings.clone(form.source_text)
    }

    append(&expanded.items, clone_cst_form(form.items[0]))
    append(&expanded.items, clone_cst_form(form.items[1]))

    value_index := 2
    if len(form.items) > 3 && form.items[2].kind == .String {
        append(&expanded.items, clone_cst_form(form.items[2]))
        value_index = 3
    }

    if form.items[1].kind == .Symbol &&
       len(form.items[1].text) > 0 &&
       form.items[1].text[len(form.items[1].text)-1] == ':' {
        _, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], value_index)
        if !ok_type {
            delete_cst_form(&expanded)
            return CST_Form{}, err_type, false
        }
        for type_item in form.items[value_index:next_i] {
            append(&expanded.items, clone_cst_form(type_item))
        }
        value_index = next_i
    }

    for item in form.items[value_index:] {
        child, err_child, ok_child := macroexpand_cst_form_with_macros(item, macros)
        if !ok_child {
            delete_cst_form(&expanded)
            return CST_Form{}, err_child, false
        }
        append(&expanded.items, child)
    }
    return expanded, Compile_Error{}, true
}

macroexpand_param_vector_preserving_types :: proc(form: CST_Form, macros: []User_Macro) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    if form.kind != .Vector {
        return macroexpand_cst_form_with_macros(form, macros)
    }
    expanded = CST_Form{kind = form.kind, span = form.span}
    if form.text != "" {
        expanded.text = strings.clone(form.text)
    }
    if form.source_text != "" {
        expanded.source_text = strings.clone(form.source_text)
    }

    i := 0
    for i < len(form.items) {
        target := form.items[i]
        append(&expanded.items, clone_cst_form(target))
        if target.kind != .Symbol || len(target.text) == 0 || target.text[len(target.text)-1] != ':' {
            i += 1
            continue
        }
        if i+1 >= len(form.items) {
            i += 1
            continue
        }
        _, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], i+1)
        if !ok_type {
            delete_cst_form(&expanded)
            return CST_Form{}, err_type, false
        }
        for type_item in form.items[i+1:next_i] {
            append(&expanded.items, clone_cst_form(type_item))
        }
        i = next_i
        if i < len(form.items) && is_symbol(form.items[i], "=") {
            append(&expanded.items, clone_cst_form(form.items[i]))
            if i+1 >= len(form.items) {
                delete_cst_form(&expanded)
                return CST_Form{}, Compile_Error{message = "missing default parameter value", span = form.items[i].span}, false
            }
            value, err_value, ok_value := macroexpand_cst_form_with_macros(form.items[i+1], macros)
            if !ok_value {
                delete_cst_form(&expanded)
                return CST_Form{}, err_value, false
            }
            append(&expanded.items, value)
            i += 2
        }
    }
    return expanded, Compile_Error{}, true
}

macroexpand_defn_form_preserving_types :: proc(form: CST_Form, macros: []User_Macro) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    expanded = CST_Form{kind = form.kind, span = form.span}
    if form.text != "" {
        expanded.text = strings.clone(form.text)
    }
    if form.source_text != "" {
        expanded.source_text = strings.clone(form.source_text)
    }

    params_index := 2
    if params_index+1 < len(form.items) &&
       form.items[params_index].kind == .Keyword &&
       form.items[params_index].text == ":abi" &&
       form.items[params_index+1].kind == .String {
        params_index += 2
    }
    if params_index < len(form.items) && form.items[params_index].kind == .String {
        params_index += 1
    }

    i := 0
    for i < len(form.items) {
        item := form.items[i]
        if i == params_index {
            params, err_params, ok_params := macroexpand_param_vector_preserving_types(item, macros)
            if !ok_params {
                delete_cst_form(&expanded)
                return CST_Form{}, err_params, false
            }
            append(&expanded.items, params)
            i += 1
            continue
        }
        if i == params_index+1 && is_symbol(item, "->") {
            append(&expanded.items, clone_cst_form(item))
            if i+1 >= len(form.items) {
                delete_cst_form(&expanded)
                return CST_Form{}, Compile_Error{message = "missing return spec after '->'", span = item.span}, false
            }
            if form.items[i+1].kind == .Vector && vector_is_named_returns(form.items[i+1]) {
                append(&expanded.items, clone_cst_form(form.items[i+1]))
                i += 2
                continue
            }
            _, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], i+1)
            if !ok_type {
                delete_cst_form(&expanded)
                return CST_Form{}, err_type, false
            }
            for type_item in form.items[i+1:next_i] {
                append(&expanded.items, clone_cst_form(type_item))
            }
            i = next_i
            continue
        }
        if i <= params_index {
            append(&expanded.items, clone_cst_form(item))
        } else {
            children, err_child, ok_child := macroexpand_cst_child_forms_with_macros(item, macros)
            if !ok_child {
                delete_cst_form(&expanded)
                return CST_Form{}, err_child, false
            }
            for child in children {
                append(&expanded.items, child)
            }
            delete(children)
        }
        i += 1
    }
    return expanded, Compile_Error{}, true
}

write_macro_form_expanded :: proc(builder: ^strings.Builder, form: CST_Form, macros: []User_Macro) -> (Compile_Error, bool) {
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if form.items[0].text == "quote" {
            write_macro_form(builder, form)
            return Compile_Error{}, true
        }
        if user_macro, ok_user := find_user_macro(macros, form.items[0].text); ok_user {
            expanded, err_user, ok_user_expand := expand_user_macro_call(user_macro, form, macros)
            if !ok_user_expand {
                return err_user, false
            }
            defer delete_cst_form(&expanded)
            return write_macro_form_expanded(builder, expanded, macros)
        }
        switch builtin_macro_kind(form.items[0].text) {
        case .With_Allocator:
            expanded, err_expand, ok_expand := macroexpand_with_allocator(form, macros)
            if !ok_expand {
                return err_expand, false
            }
            defer delete(expanded.output)
            defer delete(expanded.source_map)
            write_macro_expanded_output(builder, expanded.output)
            return Compile_Error{}, true
        case .With_Temp_Allocator:
            expanded, err_expand, ok_expand := macroexpand_with_temp_allocator(form, macros)
            if !ok_expand {
                return err_expand, false
            }
            defer delete(expanded.output)
            defer delete(expanded.source_map)
            write_macro_expanded_output(builder, expanded.output)
            return Compile_Error{}, true
        case .None:
        }
    }

    #partial switch form.kind {
    case .List:
        if len(form.items) == 3 &&
           form.items[0].kind == .Symbol &&
           form.items[0].text == "__kvist_field" &&
           form.items[2].kind == .Symbol {
            err_receiver, ok_receiver := write_macro_form_expanded(builder, form.items[1], macros)
            if !ok_receiver {
                return err_receiver, false
            }
            strings.write_byte(builder, '.')
            strings.write_string(builder, form.items[2].text)
            return Compile_Error{}, true
        }
        if len(form.items) == 2 &&
           form.items[0].kind == .Symbol &&
           len(form.items[0].text) > 1 &&
           form.items[0].text[0] == '.' {
            err_receiver, ok_receiver := write_macro_form_expanded(builder, form.items[1], macros)
            if !ok_receiver {
                return err_receiver, false
            }
            strings.write_string(builder, form.items[0].text)
            return Compile_Error{}, true
        }
        strings.write_byte(builder, '(')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            err_item, ok_item := write_macro_form_expanded(builder, item, macros)
            if !ok_item {
                return err_item, false
            }
        }
        strings.write_byte(builder, ')')
    case .Vector:
        strings.write_byte(builder, '[')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            err_item, ok_item := write_macro_form_expanded(builder, item, macros)
            if !ok_item {
                return err_item, false
            }
        }
        strings.write_byte(builder, ']')
    case .Brace:
        strings.write_byte(builder, '{')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            err_item, ok_item := write_macro_form_expanded(builder, item, macros)
            if !ok_item {
                return err_item, false
            }
        }
        strings.write_byte(builder, '}')
    case .Set:
        strings.write_string(builder, "#{")
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            err_item, ok_item := write_macro_form_expanded(builder, item, macros)
            if !ok_item {
                return err_item, false
            }
        }
        strings.write_byte(builder, '}')
    case .Symbol, .Keyword, .String, .Regex, .Number, .Bool, .Nil:
        strings.write_string(builder, form.text)
    }
    return Compile_Error{}, true
}

macro_form_text :: proc(form: CST_Form) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    write_macro_form(&builder, form)
    return strings.clone(strings.to_string(builder))
}

macro_output_line_count :: proc(output: string) -> int {
    if len(output) == 0 {
        return 1
    }
    lines := 1
    for ch in output {
        if ch == '\n' {
            lines += 1
        }
    }
    if output[len(output)-1] == '\n' {
        lines -= 1
    }
    if lines < 1 {
        return 1
    }
    return lines
}

macroexpand_with_allocator :: proc(form: CST_Form, macros: []User_Macro) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 || form.items[1].kind != .Vector {
        return result, Compile_Error{message = "with-allocator expects binding vector and body", span = form.span}, false
    }
    binding := form.items[1]
    if len(binding.items) != 2 || binding.items[0].kind != .Symbol {
        return result, Compile_Error{message = "with-allocator expects [name allocator] binding", span = binding.span}, false
    }

    allocator_name := binding.items[0].text
    expanded_allocator_expr, err_allocator_expr, ok_allocator_expr := macroexpand_cst_form_with_macros(binding.items[1], macros)
    if !ok_allocator_expr {
        return result, err_allocator_expr, false
    }
    defer delete_cst_form(&expanded_allocator_expr)
    allocator_expr := macro_form_text(expanded_allocator_expr)
    defer delete(allocator_expr)

    e := Macro_Expander{builder = strings.builder_make(), line = 1, source_map = &result.source_map}
    defer strings.builder_destroy(&e.builder)

    macro_emit_line(&e, "(do", form.span)
    macro_emit_line(&e, fmt.tprintf("  (let [%s %s", allocator_name, allocator_expr), binding.items[1].span)
    macro_emit_line(&e, "        kvist-old-allocator-1 context.allocator]", form.span)
    macro_emit_line(&e, fmt.tprintf("    (set! context.allocator %s)", allocator_name), form.span)
    macro_emit_line(&e, "    (defer (do", form.span)
    macro_emit_line(&e, "      (set! context.allocator kvist-old-allocator-1)))", form.span)
    body := form.items[2:]
    for item, idx in body {
        suffix := ""
        if idx == len(body)-1 {
            suffix = "))"
        }
        err_body, ok_body := macro_emit_body_form(&e, item, macros, suffix)
        if !ok_body {
            return result, err_body, false
        }
    }

    result.output = strings.clone(strings.to_string(e.builder))
    return result, {}, true
}

macroexpand_with_temp_allocator :: proc(form: CST_Form, macros: []User_Macro) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 || form.items[1].kind != .Vector {
        return result, Compile_Error{message = "with-temp-allocator expects binding vector and body", span = form.span}, false
    }
    binding := form.items[1]
    if len(binding.items) != 1 || binding.items[0].kind != .Symbol {
        return result, Compile_Error{message = "with-temp-allocator expects [name] binding", span = binding.span}, false
    }

    allocator_name := binding.items[0].text

    e := Macro_Expander{builder = strings.builder_make(), line = 1, source_map = &result.source_map}
    defer strings.builder_destroy(&e.builder)

    macro_emit_line(&e, "(do", form.span)
    macro_emit_line(&e, "  (let [kvist-temp-scope-1 (runtime.default-temp-allocator-temp-begin)", form.span)
    macro_emit_line(&e, fmt.tprintf("        %s context.temp-allocator", allocator_name), form.span)
    macro_emit_line(&e, "        kvist-old-allocator-1 context.allocator]", form.span)
    macro_emit_line(&e, fmt.tprintf("    (set! context.allocator %s)", allocator_name), form.span)
    macro_emit_line(&e, "    (defer (do", form.span)
    macro_emit_line(&e, "      (set! context.allocator kvist-old-allocator-1)", form.span)
    macro_emit_line(&e, "      (runtime.default-temp-allocator-temp-end kvist-temp-scope-1)))", form.span)
    body := form.items[2:]
    for item, idx in body {
        suffix := ""
        if idx == len(body)-1 {
            suffix = "))"
        }
        err_body, ok_body := macro_emit_body_form(&e, item, macros, suffix)
        if !ok_body {
            return result, err_body, false
        }
    }

    result.output = strings.clone(strings.to_string(e.builder))
    return result, {}, true
}

macroexpand_form_with_macros :: proc(form: CST_Form, macros: []User_Macro) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if user_macro, ok_user := find_user_macro(macros, form.items[0].text); ok_user {
            expanded, err_user, ok_user_expand := expand_user_macro_call(user_macro, form, macros)
            if !ok_user_expand {
                return result, err_user, false
            }
            defer delete_cst_form(&expanded)
            return macroexpand_form_with_macros(expanded, macros)
        }
        switch builtin_macro_kind(form.items[0].text) {
        case .With_Allocator:
            return macroexpand_with_allocator(form, macros)
        case .With_Temp_Allocator:
            return macroexpand_with_temp_allocator(form, macros)
        case .None:
        }
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    err_write, ok_write := write_macro_form_expanded(&builder, form, macros)
    if !ok_write {
        return result, err_write, false
    }
    strings.write_byte(&builder, '\n')
    result.output = strings.clone(strings.to_string(builder))
    append(&result.source_map, Source_Map_Entry{
        generated_start_line = 1,
        generated_end_line = macro_output_line_count(result.output),
        source_span = form.span,
    })
    return result, {}, true
}

macroexpand_form :: proc(form: CST_Form, anchor_path: string = ".") -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    previous_anchor := macro_eval_set_anchor(anchor_path)
    defer macro_eval_restore_anchor(previous_anchor)

    core_macros, err_core, ok_core := core_package_local_macros(anchor_path)
    if !ok_core {
        return result, err_core, false
    }
    defer {
        for i in 0..<len(core_macros) {
            delete_user_macro(&core_macros[i])
        }
        delete(core_macros)
    }
    return macroexpand_form_with_macros(form, core_macros[:])
}

macroexpand_source :: proc(source: string, anchor_path: string = ".") -> (output: string, err: Compile_Error, ok: bool) {
    result, err_result, ok_result := macroexpand_source_with_map(source, anchor_path)
    if !ok_result {
        return "", err_result, false
    }
    defer source_map_slice_delete(result.source_map)
    return result.output, {}, true
}

macroexpand_source_with_map :: proc(source: string, anchor_path: string = ".") -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    form, err_form, ok_form := read_single_eval_form(source)
    if !ok_form {
        return result, clone_compile_error(err_form, result_allocator), false
    }
    temp_result, err_expand, ok_expand := macroexpand_form(form, anchor_path)
    if !ok_expand {
        return result, clone_compile_error(err_expand, result_allocator), false
    }
    result.output = strings.clone(temp_result.output, result_allocator)
    context.allocator = result_allocator
    for entry in temp_result.source_map {
        append(&result.source_map, entry)
    }
    return result, {}, true
}

macroexpand_top_level_form_with_macros :: proc(form: CST_Form, macros: []User_Macro) -> (expanded: [dynamic]CST_Form, err: Compile_Error, ok: bool) {
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if user_macro, ok_user := find_user_macro(macros, form.items[0].text); ok_user {
            forms_out, err_user, ok_user_expand := expand_user_macro_call_to_forms(user_macro, form, macros)
            if !ok_user_expand {
                return expanded, err_user, false
            }
            for form_out in forms_out {
                nested, err_nested, ok_nested := macroexpand_top_level_form_with_macros(form_out, macros)
                if !ok_nested {
                    for i in 0 ..< len(forms_out) {
                        delete_cst_form(&forms_out[i])
                    }
                    delete(forms_out)
                    return expanded, err_nested, false
                }
                for nested_form in nested {
                    append(&expanded, nested_form)
                }
                delete(nested)
            }
            for i in 0 ..< len(forms_out) {
                delete_cst_form(&forms_out[i])
            }
            delete(forms_out)
            return expanded, Compile_Error{}, true
        }
    }

    rewritten, err_expand, ok_expand := macroexpand_cst_form_with_macros(form, macros)
    if !ok_expand {
        return expanded, err_expand, false
    }
    append(&expanded, rewritten)
    return expanded, Compile_Error{}, true
}

runtime_macro_symbol :: proc(text: string, span: Span) -> CST_Form {
    return CST_Form{kind = .Symbol, text = strings.clone(text), span = span}
}

macroexpand_builtin_runtime_form :: proc(form: CST_Form) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    #partial switch form.kind {
    case .List, .Vector, .Brace, .Set:
        expanded = form
        if form.text != "" {
            expanded.text = strings.clone(form.text)
        }
        if form.source_text != "" {
            expanded.source_text = strings.clone(form.source_text)
        }
        expanded.items = nil
        for item in form.items {
            child, err_child, ok_child := macroexpand_builtin_runtime_form(item)
            if !ok_child {
                delete_cst_form(&expanded)
                return CST_Form{}, err_child, false
            }
            append(&expanded.items, child)
        }
        return expanded, Compile_Error{}, true
    case:
        return clone_cst_form(form), Compile_Error{}, true
    }
}

macroexpand_top_forms :: proc(forms: []CST_Top_Form, include_core_macros: bool = false, anchor_path: string = ".") -> (expanded: [dynamic]CST_Top_Form, macros: [dynamic]User_Macro, err: Compile_Error, ok: bool) {
    previous_anchor := macro_eval_set_anchor(anchor_path)
    defer macro_eval_restore_anchor(previous_anchor)

    if include_core_macros {
        initial_macros, err_core, ok_core := core_package_local_macros(anchor_path)
        if !ok_core {
            return expanded, macros, err_core, false
        }
        for macro_decl in initial_macros {
            append(&macros, macro_decl)
        }
        delete(initial_macros)
    }
    for top in forms {
        if is_defmacro_form(top.form) {
            macro_decl, err_macro, ok_macro := parse_user_macro_decl(top)
            if !ok_macro {
                err_macro.source_path = top.source_path
                err_macro.source_file = top.source_file
                return expanded, macros, err_macro, false
            }
            append(&macros, macro_decl)
        }
    }
    for top in forms {
        if is_defmacro_form(top.form) {
            continue
        }
        expanded_forms, err_expand, ok_expand := macroexpand_top_level_form_with_macros(top.form, macros[:])
        if !ok_expand {
            err_expand.source_path = top.source_path
            err_expand.source_file = top.source_file
            return expanded, macros, err_expand, false
        }
        for i in 0 ..< len(expanded_forms) {
            rewritten := &expanded_forms[i]
            if is_defmacro_form(rewritten^) {
                macro_decl, err_macro, ok_macro := parse_user_macro_decl(CST_Top_Form{
                    form        = rewritten^,
                    doc_lines   = top.doc_lines,
                    source      = top.source,
                    source_path = top.source_path,
                    source_file = top.source_file,
                })
                if !ok_macro {
                    delete_cst_form_slice(&expanded_forms)
                    err_macro.source_path = top.source_path
                    err_macro.source_file = top.source_file
                    return expanded, macros, err_macro, false
                }
                append(&macros, macro_decl)
                delete_cst_form(rewritten)
                continue
            }
            append(&expanded, CST_Top_Form{
                form        = rewritten^,
                doc_lines   = clone_string_slice(top.doc_lines[:]),
                source      = strings.clone(top.source),
                source_path = top.source_path,
                source_file = top.source_file,
            })
            rewritten^ = CST_Form{}
        }
        delete(expanded_forms)
    }
    return expanded, macros, Compile_Error{}, true
}

macroexpand_program_source_with_map :: proc(source: string) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    forms, err_forms, ok_forms := read_top_forms(source)
    if !ok_forms {
        return result, clone_compile_error(err_forms, result_allocator), false
    }
    expanded, _, err_expand, ok_expand := macroexpand_top_forms(forms[:], true)
    if !ok_expand {
        return result, clone_compile_error(err_expand, result_allocator), false
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    line := 1
    for top in expanded {
        text := macro_form_text(top.form)
        defer delete(text)
        strings.write_string(&builder, text)
        strings.write_byte(&builder, '\n')
        append(&result.source_map, Source_Map_Entry{
            generated_start_line = line,
            generated_end_line   = line + macro_output_line_count(text) - 1,
            source_span          = top.form.span,
        })
        line += macro_output_line_count(text)
    }
    result.output = strings.clone(strings.to_string(builder), result_allocator)
    context.allocator = result_allocator
    copied: [dynamic]Source_Map_Entry
    for entry in result.source_map {
        append(&copied, entry)
    }
    result.source_map = copied
    return result, Compile_Error{}, true
}

macroexpand_eval_source_with_map :: proc(source, eval_source: string, anchor_path: string = ".") -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    forms, err_forms, ok_forms := read_top_forms(source)
    if !ok_forms {
        return result, clone_compile_error(err_forms, result_allocator), false
    }
    _, macros, err_expand, ok_expand := macroexpand_top_forms(forms[:], true, anchor_path)
    if !ok_expand {
        return result, clone_compile_error(err_expand, result_allocator), false
    }
    eval_form, err_eval, ok_eval := read_single_eval_form(eval_source)
    if !ok_eval {
        return result, clone_compile_error(err_eval, result_allocator), false
    }
    previous_anchor := macro_eval_set_anchor(anchor_path)
    temp_result, err_macro, ok_macro := macroexpand_form_with_macros(eval_form, macros[:])
    macro_eval_restore_anchor(previous_anchor)
    if !ok_macro {
        return result, clone_compile_error(err_macro, result_allocator), false
    }
    result.output = strings.clone(temp_result.output, result_allocator)
    context.allocator = result_allocator
    for entry in temp_result.source_map {
        append(&result.source_map, entry)
    }
    return result, Compile_Error{}, true
}
