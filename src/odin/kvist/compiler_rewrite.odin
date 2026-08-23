// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:sort"
import "core:strings"
import "core:time"
import "base:runtime"

bare_source_import_symbol_text :: proc(body: string, aliases: []Alias_Prefix, span: Span) -> (text: string, matched: bool, err: Compile_Error, ok: bool) {
    for alias_map in aliases {
        if alias_map.preserve_qualified_calls && contains_text(alias_map.exports[:], body) {
            return "", false, Compile_Error{}, true
        }
    }
    matched_alias := ""
    matched_prefix := ""
    for alias_map in aliases {
        if !alias_map.allow_unqualified_exports {
            continue
        }
        if !contains_text(alias_map.refer_names[:], body) {
            continue
        }
        if !contains_text(alias_map.exports[:], body) {
            continue
        }
        if matched {
            return "", false, Compile_Error{message = fmt.tprintf("ambiguous bare source package member `%s`; use `%s.%s` or `%s.%s`", body, matched_alias, body, alias_map.alias, body), span = span}, false
        }
        matched = true
        matched_alias = alias_map.alias
        matched_prefix = alias_map.prefix
    }
    if !matched {
        return "", false, Compile_Error{}, true
    }
    return fmt.tprintf("%s__%s", matched_prefix, body), true, Compile_Error{}, true
}

rewrite_symbol_text :: proc(text: string, locals: []string, aliases: []Alias_Prefix, prefix: string, span: Span = {}, allow_bare_import: bool = false) -> (string, Compile_Error, bool) {
    quote_prefix := ""
    body := text
    if len(body) > 0 && body[0] == '\'' {
        quote_prefix = "'"
        body = body[1:]
    }
    operator_prefix := ""
    for len(body) > 0 && (body[0] == '^' || body[0] == '&') {
        operator_prefix = fmt.tprintf("%s%c", operator_prefix, body[0])
        body = body[1:]
    }
    if quote_prefix == "" && operator_prefix == "" {
        switch body {
        case "*1":
            return "kvist_repl_star_1", Compile_Error{}, true
        case "*2":
            return "kvist_repl_star_2", Compile_Error{}, true
        case "*3":
            return "kvist_repl_star_3", Compile_Error{}, true
        }
    }
    for alias_map in aliases {
        prefix_text := fmt.tprintf("%s.", alias_map.alias)
        if len(body) > len(prefix_text) && body[:len(prefix_text)] == prefix_text {
            member := body[len(prefix_text):]
            if alias_map.preserve_qualified_calls {
                return text, Compile_Error{}, true
            }
            raw_member := map_name(member)
            defer delete(raw_member)
            is_raw_export := contains_text(alias_map.raw_exports[:], raw_member)
            if len(alias_map.exports) > 0 && !contains_text(alias_map.exports[:], member) && !is_raw_export {
                return "", Compile_Error{message = fmt.tprintf("source package member is private or undefined: %s.%s", alias_map.alias, member), span = span}, false
            }
            if is_raw_export {
                raw_prefix := alias_map.raw_prefix
                if raw_prefix == "" {
                    raw_prefix = alias_map.prefix
                }
                return fmt.tprintf("%s%s%s.%s", quote_prefix, operator_prefix, raw_prefix, raw_member), Compile_Error{}, true
            }
            return fmt.tprintf("%s%s%s__%s", quote_prefix, operator_prefix, alias_map.prefix, member), Compile_Error{}, true
        }
        old_prefix_text := fmt.tprintf("%s/", alias_map.alias)
        if len(body) > len(old_prefix_text) && body[:len(old_prefix_text)] == old_prefix_text {
            member := body[len(old_prefix_text):]
            return "", Compile_Error{message = fmt.tprintf("use `%s.%s` for package access", alias_map.alias, member), span = span}, false
        }
    }
    if prefix != "" {
        for alias_map in aliases {
            if alias_map.prefix != prefix || alias_map.alias == "" {
                continue
            }
            package_name := map_name(alias_map.alias)
            package_prefix := fmt.tprintf("%s__", package_name)
            if strings.has_prefix(body, package_prefix) && len(body) > len(package_prefix) {
                member := body[len(package_prefix):]
                delete(package_name)
                return fmt.tprintf("%s%s%s__%s", quote_prefix, operator_prefix, prefix, member), Compile_Error{}, true
            }
            delete(package_name)
        }
    }
    if prefix != "" && contains_text(locals, body) {
        return fmt.tprintf("%s%s%s__%s", quote_prefix, operator_prefix, prefix, body), Compile_Error{}, true
    }
    if allow_bare_import && quote_prefix == "" && operator_prefix == "" && !strings.contains_any(body, "./") {
        bare_text, matched_bare, err_bare, ok_bare := bare_source_import_symbol_text(body, aliases, span)
        if !ok_bare {
            return "", err_bare, false
        }
        if matched_bare {
            return bare_text, Compile_Error{}, true
        }
    }
    if len(body) > 0 && body[0] == '[' {
        close := -1
        for ch, i in body {
            if ch == ']' {
                close = i
                break
            }
        }
        if close >= 0 && close+1 < len(body) {
            suffix := body[close+1:]
            rewritten_suffix, err_suffix, ok_suffix := rewrite_symbol_text(suffix, locals, aliases, prefix, span)
            if !ok_suffix {
                return "", err_suffix, false
            }
            if rewritten_suffix != suffix {
                return fmt.tprintf("%s%s%s%s", quote_prefix, operator_prefix, body[:close+1], rewritten_suffix), Compile_Error{}, true
            }
        }
    }
    return text, Compile_Error{}, true
}

rewrite_symbol_form_text :: proc(form: CST_Form, text: string) -> CST_Form {
    rewritten := form
    rewritten.text = text
    if form.source_text != "" {
        rewritten.source_text = strings.clone(form.source_text)
    } else if text != form.text {
        rewritten.source_text = strings.clone(form.text)
    }
    return rewritten
}

append_pattern_shadow_names :: proc(form: CST_Form, names: ^[dynamic]string) {
    #partial switch form.kind {
    case .Symbol:
        text := form.text
        if text == "_" || text == "&" || text == "" {
            return
        }
        if text[len(text)-1] == ':' {
            text = text[:len(text)-1]
        }
        name := map_name(text)
        if !contains_text(names[:], name) {
            append(names, name)
        }
    case .Vector, .Brace:
        for item in form.items {
            append_pattern_shadow_names(item, names)
        }
    }
}

append_for_shadow_names :: proc(binding: CST_Form, names: ^[dynamic]string) {
    if binding.kind != .Vector {
        return
    }
    switch len(binding.items) {
    case 2:
        append_pattern_shadow_names(binding.items[0], names)
    case 3:
        append_pattern_shadow_names(binding.items[0], names)
        if binding.items[1].kind == .Symbol || binding.items[1].kind == .Vector || binding.items[1].kind == .Brace {
            append_pattern_shadow_names(binding.items[1], names)
        }
    case 4:
        append_pattern_shadow_names(binding.items[0], names)
    case 5:
        append_pattern_shadow_names(binding.items[0], names)
        append_pattern_shadow_names(binding.items[1], names)
    }
}

rewrite_form_symbols :: proc(form: CST_Form, locals: []string, aliases: []Alias_Prefix, prefix: string, allow_bare_import: bool = false) -> (CST_Form, Compile_Error, bool) {
    rewritten := form
    #partial switch form.kind {
    case .Symbol:
        text, err_text, ok_text := rewrite_symbol_text(form.text, locals, aliases, prefix, form.span, allow_bare_import)
        if !ok_text {
            return CST_Form{}, err_text, false
        }
        return rewrite_symbol_form_text(form, text), Compile_Error{}, true
    case .List, .Vector, .Brace, .Set:
        if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
            head := form.items[0].text
            if head == "quasiquote" {
                rewritten.items = nil
                append(&rewritten.items, form.items[0])
                for item in form.items[1:] {
                    child, err_child, ok_child := rewrite_quasiquote_form_symbols(item, locals, aliases, prefix)
                    if !ok_child {
                        return CST_Form{}, err_child, false
                    }
                    append(&rewritten.items, child)
                }
                return rewritten, Compile_Error{}, true
            }
            if head == "let" && len(form.items) >= 3 && form.items[1].kind == .Vector {
                rewritten.items = nil
                append(&rewritten.items, form.items[0])
                bindings, err_bindings, ok_bindings := parse_let_bindings(form.items[1])
                defer delete(bindings)
                if !ok_bindings {
                    return CST_Form{}, err_bindings, false
                }

                binding_form := form.items[1]
                binding_form.items = nil
                shadowed: [dynamic]string
                defer delete(shadowed)
                binding_index := 0
                for item in form.items[1].items {
                    active_aliases := aliases_without_shadowed_names(aliases, shadowed[:])
                    child, err_child, ok_child := rewrite_form_symbols(item, locals, active_aliases[:], prefix)
                    delete(active_aliases)
                    if !ok_child {
                        return CST_Form{}, err_child, false
                    }
                    append(&binding_form.items, child)
                    if binding_index < len(bindings) &&
                       item.span == bindings[binding_index].value.span {
                        binding_declared_names_append(bindings[binding_index], &shadowed)
                        binding_index += 1
                    }
                }
                append(&rewritten.items, binding_form)

                body_aliases := aliases_without_shadowed_names(aliases, shadowed[:])
                defer delete(body_aliases)
                for item in form.items[2:] {
                    child, err_child, ok_child := rewrite_form_symbols(item, locals, body_aliases[:], prefix)
                    if !ok_child {
                        return CST_Form{}, err_child, false
                    }
                    append(&rewritten.items, child)
                }
                return rewritten, Compile_Error{}, true
            }
            if head == "for" && len(form.items) >= 3 && form.items[1].kind == .Vector {
                rewritten.items = nil
                append(&rewritten.items, form.items[0])
                shadowed: [dynamic]string
                append_for_shadow_names(form.items[1], &shadowed)
                defer delete(shadowed)
                body_aliases := aliases_without_shadowed_names(aliases, shadowed[:])
                defer delete(body_aliases)
                binding_form, err_binding, ok_binding := rewrite_form_symbols(form.items[1], locals, aliases, prefix)
                if !ok_binding {
                    return CST_Form{}, err_binding, false
                }
                append(&rewritten.items, binding_form)
                for item in form.items[2:] {
                    child, err_child, ok_child := rewrite_form_symbols(item, locals, body_aliases[:], prefix)
                    if !ok_child {
                        return CST_Form{}, err_child, false
                    }
                    append(&rewritten.items, child)
                }
                return rewritten, Compile_Error{}, true
            }
            if head == "make" || head == "alloc" || head == "zero" || head == "transmute" || head == "type-assert" {
                rewritten.items = nil
                append(&rewritten.items, form.items[0])
                type_start := 1
                if head == "type-assert" {
                    if len(form.items) > 1 {
                        value, err_value, ok_value := rewrite_form_symbols(form.items[1], locals, aliases, prefix)
                        if !ok_value {
                            return CST_Form{}, err_value, false
                        }
                        append(&rewritten.items, value)
                    }
                    type_start = 2
                }
                if type_start < len(form.items) {
                    _, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], type_start)
                    if !ok_type {
                        return CST_Form{}, err_type, false
                    }
                    for type_item in form.items[type_start:next_i] {
                        rewritten_type_item, err_type_item, ok_type_item := rewrite_type_form_symbols(type_item, locals, aliases, prefix)
                        if !ok_type_item {
                            return CST_Form{}, err_type_item, false
                        }
                        append(&rewritten.items, rewritten_type_item)
                    }
                    for item in form.items[next_i:] {
                        child, err_child, ok_child := rewrite_form_symbols(item, locals, aliases, prefix)
                        if !ok_child {
                            return CST_Form{}, err_child, false
                        }
                        append(&rewritten.items, child)
                    }
                }
                return rewritten, Compile_Error{}, true
            }
        }
        rewritten.items = nil
        for item, idx in form.items {
            child, err_child, ok_child := rewrite_form_symbols(item, locals, aliases, prefix, form.kind == .List && idx == 0)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&rewritten.items, child)
        }
    }
    return rewritten, Compile_Error{}, true
}

rewrite_quasiquote_form_symbols :: proc(form: CST_Form, locals: []string, aliases: []Alias_Prefix, prefix: string, depth: int = 0, allow_bare_import: bool = false) -> (CST_Form, Compile_Error, bool) {
    rewritten := form
    #partial switch form.kind {
    case .Symbol:
        text, err_text, ok_text := rewrite_symbol_text(form.text, locals, aliases, prefix, form.span, allow_bare_import)
        if !ok_text {
            return CST_Form{}, err_text, false
        }
        return rewrite_symbol_form_text(form, text), Compile_Error{}, true
    case .List, .Vector, .Brace, .Set:
        if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
            head := form.items[0].text
            if head == "unquote" || head == "splice" {
                rewritten.items = nil
                append(&rewritten.items, form.items[0])
                if depth == 0 {
                    for item in form.items[1:] {
                        child, err_child, ok_child := rewrite_form_symbols(item, locals, aliases, prefix)
                        if !ok_child {
                            return CST_Form{}, err_child, false
                        }
                        append(&rewritten.items, child)
                    }
                    return rewritten, Compile_Error{}, true
                }
                for item in form.items[1:] {
                    child, err_child, ok_child := rewrite_quasiquote_form_symbols(item, locals, aliases, prefix, depth-1)
                    if !ok_child {
                        return CST_Form{}, err_child, false
                    }
                    append(&rewritten.items, child)
                }
                return rewritten, Compile_Error{}, true
            }
            if head == "quasiquote" {
                rewritten.items = nil
                append(&rewritten.items, form.items[0])
                for item in form.items[1:] {
                    child, err_child, ok_child := rewrite_quasiquote_form_symbols(item, locals, aliases, prefix, depth+1)
                    if !ok_child {
                        return CST_Form{}, err_child, false
                    }
                    append(&rewritten.items, child)
                }
                return rewritten, Compile_Error{}, true
            }
            if depth == 0 && (head == "make" || head == "alloc" || head == "zero" || head == "transmute" || head == "type-assert") {
                rewritten.items = nil
                append(&rewritten.items, form.items[0])
                type_start := 1
                if head == "type-assert" {
                    if len(form.items) > 1 {
                        value, err_value, ok_value := rewrite_quasiquote_form_symbols(form.items[1], locals, aliases, prefix)
                        if !ok_value {
                            return CST_Form{}, err_value, false
                        }
                        append(&rewritten.items, value)
                    }
                    type_start = 2
                }
                if type_start < len(form.items) {
                    next_i := type_start + 1
                    if _, parsed_next_i, _, ok_type := parse_type_text_from_forms(form.items[:], type_start); ok_type {
                        next_i = parsed_next_i
                    }
                    for type_item in form.items[type_start:next_i] {
                        child, err_child, ok_child := rewrite_quasiquote_type_form_symbols(type_item, locals, aliases, prefix)
                        if !ok_child {
                            return CST_Form{}, err_child, false
                        }
                        append(&rewritten.items, child)
                    }
                    for item in form.items[next_i:] {
                        child, err_child, ok_child := rewrite_quasiquote_form_symbols(item, locals, aliases, prefix)
                        if !ok_child {
                            return CST_Form{}, err_child, false
                        }
                        append(&rewritten.items, child)
                    }
                }
                return rewritten, Compile_Error{}, true
            }
        }
        rewritten.items = nil
        for item, idx in form.items {
            if form.kind == .List && idx == 0 && quasiquote_type_form_candidate(item) {
                child, err_child, ok_child := rewrite_quasiquote_type_form_symbols(item, locals, aliases, prefix)
                if !ok_child {
                    return CST_Form{}, err_child, false
                }
                append(&rewritten.items, child)
                continue
            }
            child, err_child, ok_child := rewrite_quasiquote_form_symbols(item, locals, aliases, prefix, depth, form.kind == .List && idx == 0)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&rewritten.items, child)
        }
    }
    return rewritten, Compile_Error{}, true
}

quasiquote_type_form_candidate :: proc(form: CST_Form) -> bool {
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        return type_constructor_symbol(form.items[0].text)
    }
    if form.kind == .Vector && len(form.items) > 0 {
        head := form.items[0]
        if head.kind == .Keyword || head.kind == .Symbol {
            text := head.text
            if head.kind == .Keyword && len(text) > 0 {
                text = text[1:]
            }
            return type_constructor_symbol(text)
        }
    }
    return false
}

rewrite_quasiquote_type_form_symbols :: proc(form: CST_Form, locals: []string, aliases: []Alias_Prefix, prefix: string) -> (CST_Form, Compile_Error, bool) {
    rewritten := form
    #partial switch form.kind {
    case .Symbol:
        if type_constructor_symbol(form.text) {
            return rewritten, Compile_Error{}, true
        }
        text, err_text, ok_text := rewrite_symbol_text(form.text, locals, aliases, prefix, form.span)
        if !ok_text {
            return CST_Form{}, err_text, false
        }
        return rewrite_symbol_form_text(form, text), Compile_Error{}, true
    case .List:
        if len(form.items) > 0 && form.items[0].kind == .Symbol && form.items[0].text == "unquote" {
            rewritten.items = nil
            append(&rewritten.items, form.items[0])
            for item in form.items[1:] {
                child, err_child, ok_child := rewrite_form_symbols(item, locals, aliases, prefix)
                if !ok_child {
                    return CST_Form{}, err_child, false
                }
                append(&rewritten.items, child)
            }
            return rewritten, Compile_Error{}, true
        }
        rewritten.items = nil
        for item, idx in form.items {
            if idx == 0 && item.kind == .Symbol && type_constructor_symbol(item.text) {
                append(&rewritten.items, item)
                continue
            }
            child, err_child, ok_child := rewrite_quasiquote_type_form_symbols(item, locals, aliases, prefix)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&rewritten.items, child)
        }
    case .Vector:
        rewritten.items = nil
        for item, idx in form.items {
            if idx == 0 && (item.kind == .Keyword || item.kind == .Symbol) {
                head := item.text
                if item.kind == .Keyword && len(head) > 0 {
                    head = head[1:]
                }
                if type_constructor_symbol(head) {
                    append(&rewritten.items, item)
                    continue
                }
            }
            child, err_child, ok_child := rewrite_quasiquote_type_form_symbols(item, locals, aliases, prefix)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&rewritten.items, child)
        }
    }
    return rewritten, Compile_Error{}, true
}

rewrite_decl_name :: proc(form: ^CST_Form, prefix: string) {
    if prefix == "" || form^.kind != .List || len(form^.items) < 2 || form^.items[1].kind != .Symbol {
        return
    }
    switch decl_head_name(form^) {
    case "def", "def-", "defvar", "defvar-", "defstruct", "defstruct-", "defenum", "defenum-", "defunion", "defunion-", "defn", "defn-", "defmacro", "defmacro-", "deftransform", "deftransform-", "defiter", "defiter-":
        form^.items[1] = rewrite_symbol_form_text(form^.items[1], fmt.tprintf("%s__%s", prefix, form^.items[1].text))
    }
}

type_constructor_symbol :: proc(text: string) -> bool {
    switch text {
    case "slice", "dynamic", "array", "map", "matrix", "ptr", "distinct", "fn", "type":
        return true
    }
    return false
}

rewrite_type_form_symbols :: proc(form: CST_Form, locals: []string, aliases: []Alias_Prefix, prefix: string) -> (CST_Form, Compile_Error, bool) {
    rewritten := form
    #partial switch form.kind {
    case .Symbol:
        if type_constructor_symbol(form.text) ||
           type_text_is_builtin_odin_scalar(form.text) ||
           form.text == "float" || form.text == "char" ||
           form.text == "Data" || form.text == "Data-Kind" || form.text == "Data-Entry" {
            return rewritten, Compile_Error{}, true
        }
        text, err_text, ok_text := rewrite_symbol_text(form.text, locals, aliases, prefix, form.span)
        if !ok_text {
            return CST_Form{}, err_text, false
        }
        return rewrite_symbol_form_text(form, text), Compile_Error{}, true
    case .List:
        rewritten.items = nil
        for item, idx in form.items {
            if idx == 0 && item.kind == .Symbol && type_constructor_symbol(item.text) {
                append(&rewritten.items, item)
                continue
            }
            child, err_child, ok_child := rewrite_type_form_symbols(item, locals, aliases, prefix)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&rewritten.items, child)
        }
    case .Vector:
        rewritten.items = nil
        for item, idx in form.items {
            if idx == 0 && (item.kind == .Keyword || item.kind == .Symbol) {
                head := item.text
                if item.kind == .Keyword && len(head) > 0 {
                    head = head[1:]
                }
                if type_constructor_symbol(head) {
                    append(&rewritten.items, item)
                    continue
                }
            }
            if item.kind == .Symbol && len(item.text) > 0 && item.text[len(item.text)-1] == ':' {
                append(&rewritten.items, item)
                continue
            }
            child, err_child, ok_child := rewrite_type_form_symbols(item, locals, aliases, prefix)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&rewritten.items, child)
        }
    }
    return rewritten, Compile_Error{}, true
}

rewrite_param_vector_signature :: proc(form: CST_Form, locals: []string, aliases: []Alias_Prefix, prefix: string) -> (CST_Form, Compile_Error, bool) {
    if form.kind != .Vector {
        return form, Compile_Error{}, true
    }
    rewritten := form
    rewritten.items = nil
    i := 0
    for i < len(form.items) {
        target := form.items[i]
        type_start := -1
        #partial switch target.kind {
        case .Symbol:
            append(&rewritten.items, target)
            if len(target.text) == 0 || target.text[len(target.text)-1] != ':' {
                i += 1
                continue
            }
            type_start = i + 1
        case .Brace:
            append(&rewritten.items, target)
            if i+1 < len(form.items) {
                append(&rewritten.items, form.items[i+1])
            }
            type_start = i + 2
        case:
            child, err_child, ok_child := rewrite_form_symbols(target, locals, aliases, prefix)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&rewritten.items, child)
            i += 1
            continue
        }

        if type_start >= len(form.items) {
            i += 1
            continue
        }
        _, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], type_start)
        if !ok_type {
            return CST_Form{}, err_type, false
        }
        for item in form.items[type_start:next_i] {
            type_item, err_type_item, ok_type_item := rewrite_type_form_symbols(item, locals, aliases, prefix)
            if !ok_type_item {
                return CST_Form{}, err_type_item, false
            }
            append(&rewritten.items, type_item)
        }
        i = next_i
        if i < len(form.items) && is_symbol(form.items[i], "=") {
            append(&rewritten.items, form.items[i])
            if i+1 >= len(form.items) {
                return CST_Form{}, Compile_Error{message = "missing default parameter value", span = form.items[i].span}, false
            }
            value, err_value, ok_value := rewrite_form_symbols(form.items[i+1], locals, aliases, prefix)
            if !ok_value {
                return CST_Form{}, err_value, false
            }
            append(&rewritten.items, value)
            i += 2
        }
    }
    return rewritten, Compile_Error{}, true
}

param_names_from_signature_vector :: proc(form: CST_Form) -> (names: [dynamic]string, err: Compile_Error, ok: bool) {
    if form.kind != .Vector {
        return names, Compile_Error{}, true
    }
    i := 0
    for i < len(form.items) {
        target := form.items[i]
        if target.kind != .Symbol || len(target.text) == 0 || target.text[len(target.text)-1] != ':' {
            i += 1
            continue
        }
        append(&names, target.text[:len(target.text)-1])
        _, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], i+1)
        if !ok_type {
            return names, err_type, false
        }
        i = next_i
        if i < len(form.items) && is_symbol(form.items[i], "=") {
            i += 2
        }
    }
    return names, Compile_Error{}, true
}

locals_without_shadowed_names :: proc(locals: []string, shadowed: []string) -> (out: [dynamic]string) {
    for local in locals {
        if contains_text(shadowed, local) {
            continue
        }
        append(&out, local)
    }
    return out
}

aliases_without_shadowed_names :: proc(aliases: []Alias_Prefix, shadowed: []string) -> (out: [dynamic]Alias_Prefix) {
    for alias in aliases {
        if contains_text(shadowed, alias.alias) {
            continue
        }
        append(&out, alias)
    }
    return out
}

append_macro_time_helper_names :: proc(names: ^[dynamic]string, private_macros: []string) {
    helpers := [?]string{
        "not", "and", "or",
        "list", "vector", "brace", "forms",
        "first", "rest", "nth", "count", "slice", "concat",
        "str", "symbol", "keyword", "gensym",
        "contains?",
        "form?", "vector?", "brace?", "list?", "symbol?", "keyword?", "string?", "number?",
        "name", "source", "text",
    }
    for helper in helpers {
        if contains_text(private_macros, helper) {
            continue
        }
        if !contains_text(names[:], helper) {
            append(names, helper)
        }
    }
}

macro_param_names_from_vector :: proc(form: CST_Form) -> (names: [dynamic]string, err: Compile_Error, ok: bool) {
    if form.kind != .Vector {
        return names, Compile_Error{}, true
    }
    i := 0
    for i < len(form.items) {
        item := form.items[i]
        if item.kind != .Symbol {
            return names, Compile_Error{message = "defmacro parameter must be a symbol", span = item.span}, false
        }
        if item.text == "&" {
            if i+1 >= len(form.items) || form.items[i+1].kind != .Symbol {
                return names, Compile_Error{message = "defmacro rest parameters must be written as '& name'", span = item.span}, false
            }
            append(&names, form.items[i+1].text)
            return names, Compile_Error{}, true
        }
        append(&names, item.text)
        i += 1
        if i < len(form.items) && form.items[i].kind == .Symbol && form.items[i].text == "#form" {
            i += 1
        }
    }
    return names, Compile_Error{}, true
}

rewrite_macro_top_form :: proc(top: CST_Top_Form, locals: []string, private_macros: []string, aliases: []Alias_Prefix, prefix: string) -> (CST_Top_Form, Compile_Error, bool) {
    form := top.form
    rewritten := top
    rewritten.form = form
    rewritten.form.items = nil

    params_index := 2
    if params_index < len(form.items) && form.items[params_index].kind == .String {
        params_index += 1
    }

    body_locals := locals
    body_aliases := aliases
    shadowed_names: [dynamic]string
    filtered_locals: [dynamic]string
    filtered_aliases: [dynamic]Alias_Prefix
    if params_index < len(form.items) && form.items[params_index].kind == .Vector {
        param_names, err_param_names, ok_param_names := macro_param_names_from_vector(form.items[params_index])
        if !ok_param_names {
            return CST_Top_Form{}, err_param_names, false
        }
        shadowed_names = param_names
        defer delete(shadowed_names)
        append_macro_time_helper_names(&shadowed_names, private_macros)
        filtered_locals = locals_without_shadowed_names(locals, shadowed_names[:])
        defer delete(filtered_locals)
        body_locals = filtered_locals[:]
        filtered_aliases = aliases_without_shadowed_names(aliases, shadowed_names[:])
        defer delete(filtered_aliases)
        body_aliases = filtered_aliases[:]
    }

    for item, idx in form.items {
        if idx == 1 && item.kind == .Symbol {
            renamed := rewrite_symbol_form_text(item, fmt.tprintf("%s__%s", prefix, item.text))
            append(&rewritten.form.items, renamed)
            continue
        }
        if idx <= params_index {
            append(&rewritten.form.items, clone_cst_form(item))
            continue
        }
        child, err_child, ok_child := rewrite_form_symbols(item, body_locals, body_aliases, prefix)
        if !ok_child {
            return CST_Top_Form{}, err_child, false
        }
        append(&rewritten.form.items, child)
    }
    return rewritten, Compile_Error{}, true
}

rewrite_proc_like_top_form :: proc(top: CST_Top_Form, locals: []string, aliases: []Alias_Prefix, prefix: string) -> (CST_Top_Form, Compile_Error, bool) {
    form := top.form
    rewritten := top
    rewritten.form = form
    rewritten.form.items = nil

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

    body_locals := locals
    body_aliases := aliases
    shadowed_params: [dynamic]string
    filtered_locals: [dynamic]string
    filtered_aliases: [dynamic]Alias_Prefix
    if params_index < len(form.items) && form.items[params_index].kind == .Vector {
        param_names, err_param_names, ok_param_names := param_names_from_signature_vector(form.items[params_index])
        if !ok_param_names {
            return CST_Top_Form{}, err_param_names, false
        }
        shadowed_params = param_names
        defer delete(shadowed_params)
        filtered_locals = locals_without_shadowed_names(locals, shadowed_params[:])
        defer delete(filtered_locals)
        body_locals = filtered_locals[:]
        filtered_aliases = aliases_without_shadowed_names(aliases, shadowed_params[:])
        defer delete(filtered_aliases)
        body_aliases = filtered_aliases[:]
    }

    i := 0
    for i < len(form.items) {
        item := form.items[i]
        if i == 1 && item.kind == .Symbol {
            renamed := rewrite_symbol_form_text(item, fmt.tprintf("%s__%s", prefix, item.text))
            append(&rewritten.form.items, renamed)
            i += 1
            continue
        }
        if i == params_index {
            params, err_params, ok_params := rewrite_param_vector_signature(item, locals, aliases, prefix)
            if !ok_params {
                return CST_Top_Form{}, err_params, false
            }
            append(&rewritten.form.items, params)
            i += 1
            continue
        }
        if i == params_index+1 && is_symbol(item, "->") {
            append(&rewritten.form.items, item)
            if i+1 >= len(form.items) {
                return CST_Top_Form{}, Compile_Error{message = "missing return spec after '->'", span = item.span}, false
            }
            if form.items[i+1].kind == .Vector && vector_is_named_returns(form.items[i+1]) {
                named, err_named, ok_named := rewrite_type_form_symbols(form.items[i+1], locals, aliases, prefix)
                if !ok_named {
                    return CST_Top_Form{}, err_named, false
                }
                append(&rewritten.form.items, named)
                i += 2
                continue
            }
            _, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], i+1)
            if !ok_type {
                return CST_Top_Form{}, err_type, false
            }
            for type_item in form.items[i+1:next_i] {
                rewritten_type_item, err_type_item, ok_type_item := rewrite_type_form_symbols(type_item, locals, aliases, prefix)
                if !ok_type_item {
                    return CST_Top_Form{}, err_type_item, false
                }
                append(&rewritten.form.items, rewritten_type_item)
            }
            if (decl_head_name(form) == "defiter" || decl_head_name(form) == "defiter-") &&
               next_i < len(form.items) &&
               form.items[next_i].kind == .Keyword &&
               form.items[next_i].text == ":yield" {
                append(&rewritten.form.items, form.items[next_i])
                if next_i+1 >= len(form.items) {
                    return CST_Top_Form{}, Compile_Error{message = "missing item type after ':yield'", span = form.items[next_i].span}, false
                }
                _, next_item_i, err_item_type, ok_item_type := parse_type_text_from_forms(form.items[:], next_i+1)
                if !ok_item_type {
                    return CST_Top_Form{}, err_item_type, false
                }
                for type_item in form.items[next_i+1:next_item_i] {
                    rewritten_type_item, err_type_item, ok_type_item := rewrite_type_form_symbols(type_item, locals, aliases, prefix)
                    if !ok_type_item {
                        return CST_Top_Form{}, err_type_item, false
                    }
                    append(&rewritten.form.items, rewritten_type_item)
                }
                i = next_item_i
                continue
            }
            i = next_i
            continue
        }

        child, err_child, ok_child := rewrite_form_symbols(item, body_locals, body_aliases, prefix)
        if !ok_child {
            return CST_Top_Form{}, err_child, false
        }
        append(&rewritten.form.items, child)
        i += 1
    }
    return rewritten, Compile_Error{}, true
}

rewrite_struct_top_form :: proc(top: CST_Top_Form, locals: []string, aliases: []Alias_Prefix, prefix: string) -> (CST_Top_Form, Compile_Error, bool) {
    rewritten := top
    rewritten.form = top.form
    rewritten.form.items = nil
    rewrote_fields := false
    for item, idx in top.form.items {
        if idx == 1 {
            renamed := rewrite_symbol_form_text(item, fmt.tprintf("%s__%s", prefix, item.text))
            append(&rewritten.form.items, renamed)
            continue
        }
        if item.kind != .Brace || rewrote_fields {
            append(&rewritten.form.items, clone_cst_form(item))
            continue
        }
        rewrote_fields = true
        fields := item
        fields.items = nil
        field_idx := 0
        for field_idx < len(item.items) {
            append(&fields.items, clone_cst_form(item.items[field_idx]))
            if field_idx+1 >= len(item.items) {
                field_idx += 1
                continue
            }
            field_type, err_type, ok_type := rewrite_type_form_symbols(item.items[field_idx+1], locals, aliases, prefix)
            if !ok_type {
                return CST_Top_Form{}, err_type, false
            }
            append(&fields.items, field_type)
            field_idx += 2
            parsing_modifiers := true
            for parsing_modifiers &&
                field_idx < len(item.items) &&
                item.items[field_idx].kind == .Keyword {
                marker := item.items[field_idx]
                switch marker.text {
                case ":using":
                    append(&fields.items, clone_cst_form(marker))
                    field_idx += 1
                case ":default":
                    append(&fields.items, clone_cst_form(marker))
                    if field_idx+1 >= len(item.items) {
                        field_idx += 1
                        continue
                    }
                    default_value, err_default, ok_default := rewrite_form_symbols(
                        item.items[field_idx+1],
                        locals,
                        aliases,
                        prefix,
                    )
                    if !ok_default {
                        return CST_Top_Form{}, err_default, false
                    }
                    append(&fields.items, default_value)
                    field_idx += 2
                case:
                    parsing_modifiers = false
                }
            }
        }
        append(&rewritten.form.items, fields)
    }
    return rewritten, Compile_Error{}, true
}

rewrite_top_form :: proc(top: CST_Top_Form, locals: []string, private_macros: []string, aliases: []Alias_Prefix, prefix: string) -> (CST_Top_Form, Compile_Error, bool) {
    rewritten := top
    if prefix != "" &&
       top.form.kind == .List &&
       len(top.form.items) == 2 &&
       is_symbol(top.form.items[0], "odin") &&
       top.form.items[1].kind == .String {
        for alias_map in aliases {
            if alias_map.prefix != prefix || alias_map.alias == "" {
                continue
            }
            package_prefix := map_name(alias_map.alias)
            old_prefix := fmt.tprintf("%s__", package_prefix)
            new_prefix := fmt.tprintf("%s__", prefix)
            replacement, allocated := strings.replace_all(top.form.items[1].text, old_prefix, new_prefix, context.allocator)
            rewritten = clone_cst_top_form(top)
            delete(rewritten.form.items[1].text)
            if allocated {
                rewritten.form.items[1].text = replacement
            } else {
                rewritten.form.items[1].text = strings.clone(replacement)
            }
            delete(package_prefix)
            delete(old_prefix)
            delete(new_prefix)
            return rewritten, Compile_Error{}, true
        }
    }
    if prefix != "" &&
       top.form.kind == .List &&
       len(top.form.items) >= 2 &&
       top.form.items[1].kind == .Symbol {
        head := decl_head_name(top.form)
        if head == "defn" || head == "defn-" || head == "defiter" || head == "defiter-" {
            return rewrite_proc_like_top_form(top, locals, aliases, prefix)
        }
        if is_macro_decl_head(head) {
            return rewrite_macro_top_form(top, locals, private_macros, aliases, prefix)
        }
        if is_top_level_decl_head(head) {
            if head == "defstruct" || head == "defstruct-" {
                return rewrite_struct_top_form(top, locals, aliases, prefix)
            }
            if head == "defenum" || head == "defenum-" {
                renamed := top
                renamed.form = top.form
                renamed.form.items = nil
                for item, idx in top.form.items {
                    if idx == 1 {
                        name := rewrite_symbol_form_text(item, fmt.tprintf("%s__%s", prefix, item.text))
                        append(&renamed.form.items, name)
                    } else {
                        append(&renamed.form.items, clone_cst_form(item))
                    }
                }
                return renamed, Compile_Error{}, true
            }
            if head == "def" || head == "def-" {
                value_index := 2
                if len(top.form.items) > 3 && top.form.items[2].kind == .String {
                    value_index = 3
                }
                if value_index < len(top.form.items) &&
                   top.form.items[value_index].kind == .List &&
                   len(top.form.items[value_index].items) > 0 &&
                   is_symbol(top.form.items[value_index].items[0], "overload") {
                    rewritten.form = top.form
                    rewritten.form.items = nil
                    for item, idx in top.form.items {
                        if idx == 1 {
                            renamed := rewrite_symbol_form_text(item, fmt.tprintf("%s__%s", prefix, item.text))
                            append(&rewritten.form.items, renamed)
                            continue
                        }
                        if idx == value_index {
                            overload_form := item
                            overload_form.items = nil
                            append(&overload_form.items, item.items[0])
                            for member in item.items[1:] {
                                child, err_child, ok_child := rewrite_form_symbols(member, locals, aliases, prefix)
                                if !ok_child {
                                    return CST_Top_Form{}, err_child, false
                                }
                                append(&overload_form.items, child)
                            }
                            append(&rewritten.form.items, overload_form)
                            continue
                        }
                        append(&rewritten.form.items, item)
                    }
                    return rewritten, Compile_Error{}, true
                }
                if type_alias_candidate_from_forms(top.form.items[:], value_index) {
                    _, next_type, _, ok_type := parse_type_text_from_forms(top.form.items[:], value_index)
                    if ok_type && next_type == len(top.form.items) {
                        rewritten.form = top.form
                        rewritten.form.items = nil
                        for item, idx in top.form.items {
                            if idx == 1 {
                                renamed := rewrite_symbol_form_text(item, fmt.tprintf("%s__%s", prefix, item.text))
                                append(&rewritten.form.items, renamed)
                                continue
                            }
                            if idx >= value_index {
                                child, err_child, ok_child := rewrite_type_form_symbols(item, locals, aliases, prefix)
                                if !ok_child {
                                    return CST_Top_Form{}, err_child, false
                                }
                                append(&rewritten.form.items, child)
                                continue
                            }
                            append(&rewritten.form.items, item)
                        }
                        return rewritten, Compile_Error{}, true
                    }
                }
            }
            rewritten.form = top.form
            rewritten.form.items = nil
            for item, idx in top.form.items {
                if idx == 1 {
                    renamed := rewrite_symbol_form_text(item, fmt.tprintf("%s__%s", prefix, item.text))
                    append(&rewritten.form.items, renamed)
                } else {
                    child, err_child, ok_child := rewrite_form_symbols(item, locals, aliases, prefix)
                    if !ok_child {
                        return CST_Top_Form{}, err_child, false
                    }
                    append(&rewritten.form.items, child)
                }
            }
            return rewritten, Compile_Error{}, true
        }
    }
    form, err_form, ok_form := rewrite_form_symbols(top.form, locals, aliases, prefix)
    if !ok_form {
        return CST_Top_Form{}, err_form, false
    }
    rewritten.form = form
    rewrite_decl_name(&rewritten.form, prefix)
    return rewritten, Compile_Error{}, true
}
