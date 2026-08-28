// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

returned_binding_name :: proc(form: CST_Form) -> (string, bool) {
    if form.kind == .Symbol {
        return map_name(form.text), true
    }
    if form.kind == .List && len(form.items) == 2 &&
       form.items[0].kind == .Symbol && form.items[0].text == "return" &&
       form.items[1].kind == .Symbol {
        return map_name(form.items[1].text), true
    }
    return "", false
}

borrowed_view_owner_has_nested_owned_value :: proc(e: ^Emitter, form: CST_Form) -> bool {
    if form.kind == .List && len(form.items) > 1 && form.items[0].kind == .Symbol {
        if _, proc_decl, ok_proc := resolve_proc_call_decl(e, form.items[0].text);
           ok_proc && proc_decl != nil {
            if index, ok_index := proc_decl_borrow_owner_arg_index(proc_decl);
               ok_index && index+1 < len(form.items) {
                return form_has_nested_owned_value(form.items[index+1], e)
            }
        }
    }
    return form_has_nested_owned_value(form, e)
}

let_return_error :: proc(e: ^Emitter, bindings: []Binding, body: []CST_Form) -> (Compile_Error, bool) {
    if len(body) == 0 {
        return {}, false
    }
    returned_name, ok_name := returned_binding_name(body[len(body)-1])
    if !ok_name {
        return {}, false
    }
    for binding in bindings {
        if binding.name != returned_name {
            continue
        }
        if form_is_borrowed_view_result(binding.value, e) &&
           borrowed_view_owner_has_nested_owned_value(e, binding.value) {
            return Compile_Error{
                message = "cannot return a borrowed view that depends on an owned intermediate; return an owned result or keep the pipeline local",
                span = binding.value.span,
            }, true
        }
    }
    return {}, false
}

form_mentions_binding_name :: proc(form: CST_Form, name: string) -> bool {
    #partial switch form.kind {
    case .Symbol:
        return map_name(form.text) == name
    case .List, .Vector, .Brace, .Set:
        for item in form.items {
            if form_mentions_binding_name(item, name) {
                return true
            }
        }
    }
    return false
}

form_mentions_any_binding_name :: proc(form: CST_Form, names: []string) -> bool {
    for name in names {
        if form_mentions_binding_name(form, name) {
            return true
        }
    }
    return false
}

binding_names_contain :: proc(names: []string, name: string) -> bool {
    for existing in names {
        if existing == name {
            return true
        }
    }
    return false
}

binding_names_append_unique :: proc(names: ^[dynamic]string, name: string) {
    if name == "" || binding_names_contain(names[:], name) {
        return
    }
    append(names, name)
}

set_bang_assigned_name :: proc(form: CST_Form) -> (string, bool) {
    if form.kind != .List || len(form.items) != 3 || form.items[0].kind != .Symbol || form.items[0].text != "set!" {
        return "", false
    }
    if form.items[1].kind != .Symbol {
        return "", false
    }
    return map_name(form.items[1].text), true
}

type_text_is_non_owned_scalar :: proc(text: string) -> bool {
    switch text {
    case "bool", "int", "i64", "f64", "float", "string", "rune", "byte", "typeid", "rawptr":
        return true
    }
    return false
}

return_spec_is_non_owned_scalar :: proc(returns: Return_Spec) -> bool {
    return returns.kind == .Single && type_text_is_non_owned_scalar(returns.single_ty)
}

body_escape_deferred_binding_span_names :: proc(e: ^Emitter, forms: []CST_Form, names: []string, returns: Return_Spec) -> (Span, bool) {
    scoped_names := make([dynamic]string, len(names))
    defer delete(scoped_names)
    copy(scoped_names[:], names)

    for form in forms {
        if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol && form.items[0].text == "return" {
            if span, ok := form_escape_deferred_binding_span_names(e, form, scoped_names[:], returns); ok {
                return span, true
            }
        }
        if assigned_name, ok_assigned := set_bang_assigned_name(form); ok_assigned &&
           form_may_escape_deferred_binding_names(e, form.items[2], scoped_names[:], returns) {
            binding_names_append_unique(&scoped_names, assigned_name)
        }
    }
    if returns.kind != .None && len(forms) > 0 {
        return form_escape_deferred_binding_span_names(e, forms[len(forms)-1], scoped_names[:], returns)
    }
    return {}, false
}

body_may_escape_deferred_binding_names :: proc(e: ^Emitter, forms: []CST_Form, names: []string, returns: Return_Spec) -> bool {
    _, ok := body_escape_deferred_binding_span_names(e, forms, names, returns)
    return ok
}

body_may_escape_deferred_binding :: proc(e: ^Emitter, forms: []CST_Form, name: string, returns: Return_Spec) -> bool {
    names: [dynamic]string
    defer delete(names)
    append(&names, name)
    return body_may_escape_deferred_binding_names(e, forms, names[:], returns)
}

switch_escape_deferred_binding_span_names :: proc(e: ^Emitter, form: CST_Form, names: []string, returns: Return_Spec) -> (Span, bool) {
    if len(form.items) < 4 {
        return {}, false
    }
    i := 2
    for i < len(form.items) {
        if i+1 >= len(form.items) {
            return {}, false
        }
        if span, ok := form_escape_deferred_binding_span_names(e, form.items[i+1], names, returns); ok {
            return span, true
        }
        i += 2
    }
    return {}, false
}

switch_may_escape_deferred_binding_names :: proc(e: ^Emitter, form: CST_Form, names: []string, returns: Return_Spec) -> bool {
    _, ok := switch_escape_deferred_binding_span_names(e, form, names, returns)
    return ok
}

switch_may_escape_deferred_binding :: proc(e: ^Emitter, form: CST_Form, name: string, returns: Return_Spec) -> bool {
    names: [dynamic]string
    defer delete(names)
    append(&names, name)
    return switch_may_escape_deferred_binding_names(e, form, names[:], returns)
}

form_returns_owned_managed_call_result :: proc(e: ^Emitter, form: CST_Form) -> bool {
    if e == nil || form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    _, proc_decl, ok_proc := resolve_proc_call_decl(e, form.items[0].text)
    if !ok_proc || proc_decl == nil || !proc_decl.owns_result {
        return false
    }
    return proc_decl.returns.kind == .Single &&
           type_text_has_managed_lifecycle(e, proc_decl.returns.single_ty)
}

form_escape_deferred_binding_span_names :: proc(e: ^Emitter, form: CST_Form, names: []string, returns: Return_Spec) -> (Span, bool) {
    if !form_mentions_any_binding_name(form, names) {
        return {}, false
    }
    if return_spec_is_non_owned_scalar(returns) {
        return {}, false
    }
    if form_is_borrowed_view_of_tracked_name(form, names) {
        return {}, false
    }
    // An owned managed result has its own retained reference. It remains valid
    // after a resource passed to the call is cleaned up, so the resource does
    // not escape through that result.
    if form_returns_owned_managed_call_result(e, form) {
        return {}, false
    }

    #partial switch form.kind {
    case .Symbol:
        return form.span, true
    case .Vector, .Brace, .Set:
        for item in form.items {
            if span, ok := form_escape_deferred_binding_span_names(e, item, names, returns); ok {
                return span, true
            }
        }
        return {}, false
    case .List:
        if len(form.items) == 0 || form.items[0].kind != .Symbol {
            for item in form.items {
                if span, ok := form_escape_deferred_binding_span_names(e, item, names, returns); ok {
                    return span, true
                }
            }
            return {}, false
        }
        switch form.items[0].text {
        case "return":
            for returned in form.items[1:] {
                if span, ok := form_escape_deferred_binding_span_names(e, returned, names, returns); ok {
                    return span, true
                }
            }
            return {}, false
        case "let":
            bindings, _, ok_bind := parse_let_bindings(form.items[1])
            if !ok_bind {
                if len(form.items) >= 3 {
                    return body_escape_deferred_binding_span_names(e, form.items[2:], names, returns)
                }
                return {}, false
            }
            scoped_names := make([dynamic]string, len(names))
            defer delete(scoped_names)
            copy(scoped_names[:], names)
            for binding in bindings {
                if binding.name != "" && form_may_escape_deferred_binding_names(e, binding.value, scoped_names[:], returns) {
                    binding_names_append_unique(&scoped_names, binding.name)
                }
            }
            if len(form.items) >= 3 {
                return body_escape_deferred_binding_span_names(e, form.items[2:], scoped_names[:], returns)
            }
            return {}, false
        case "do":
            if len(form.items) >= 2 {
                return body_escape_deferred_binding_span_names(e, form.items[1:], names, returns)
            }
            return {}, false
        case "if":
            if len(form.items) >= 3 {
                if span, ok := form_escape_deferred_binding_span_names(e, form.items[2], names, returns); ok {
                    return span, true
                }
            }
            if len(form.items) >= 4 {
                if span, ok := form_escape_deferred_binding_span_names(e, form.items[3], names, returns); ok {
                    return span, true
                }
            }
            return {}, false
        case "type-case":
            return switch_escape_deferred_binding_span_names(e, form, names, returns)
        case "match":
            for i := 3; i < len(form.items); i += 2 {
                if span, ok := form_escape_deferred_binding_span_names(e, form.items[i], names, returns); ok {
                    return span, true
                }
            }
            return {}, false
        case "with-allocator", "with-temp-allocator":
            if len(form.items) >= 3 {
                return body_escape_deferred_binding_span_names(e, form.items[2:], names, returns)
            }
            return {}, false
        case:
            for item in form.items[1:] {
                if span, ok := form_escape_deferred_binding_span_names(e, item, names, returns); ok {
                    return span, true
                }
            }
            return {}, false
        }
    }
    return {}, false
}

form_may_escape_deferred_binding_names :: proc(e: ^Emitter, form: CST_Form, names: []string, returns: Return_Spec) -> bool {
    _, ok := form_escape_deferred_binding_span_names(e, form, names, returns)
    return ok
}

form_may_escape_deferred_binding :: proc(e: ^Emitter, form: CST_Form, name: string, returns: Return_Spec) -> bool {
    names: [dynamic]string
    defer delete(names)
    append(&names, name)
    return form_may_escape_deferred_binding_names(e, form, names[:], returns)
}

body_escape_owned_temp_result_span_names :: proc(e: ^Emitter, forms: []CST_Form, names: []string, returns: Return_Spec) -> (Span, bool) {
    scoped_names := make([dynamic]string, len(names))
    defer delete(scoped_names)
    copy(scoped_names[:], names)

    for form in forms {
        if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol && form.items[0].text == "return" {
            if span, ok := form_escape_owned_temp_result_span_names(e, form, scoped_names[:], returns); ok {
                return span, true
            }
        }
        track_owned_temp_result_assignments(e, form, &scoped_names, returns)
    }
    if returns.kind != .None && len(forms) > 0 {
        return form_escape_owned_temp_result_span_names(e, forms[len(forms)-1], scoped_names[:], returns)
    }
    return {}, false
}

body_may_escape_owned_temp_result_names :: proc(e: ^Emitter, forms: []CST_Form, names: []string, returns: Return_Spec) -> bool {
    _, ok := body_escape_owned_temp_result_span_names(e, forms, names, returns)
    return ok
}

body_may_escape_owned_temp_result :: proc(e: ^Emitter, forms: []CST_Form, returns: Return_Spec) -> bool {
    return body_may_escape_owned_temp_result_names(e, forms, nil, returns)
}

switch_escape_owned_temp_result_span_names :: proc(e: ^Emitter, form: CST_Form, names: []string, returns: Return_Spec) -> (Span, bool) {
    if len(form.items) < 4 {
        return {}, false
    }
    i := 2
    for i < len(form.items) {
        if i+1 >= len(form.items) {
            return {}, false
        }
        if span, ok := form_escape_owned_temp_result_span_names(e, form.items[i+1], names, returns); ok {
            return span, true
        }
        i += 2
    }
    return {}, false
}

switch_may_escape_owned_temp_result_names :: proc(e: ^Emitter, form: CST_Form, names: []string, returns: Return_Spec) -> bool {
    _, ok := switch_escape_owned_temp_result_span_names(e, form, names, returns)
    return ok
}

switch_may_escape_owned_temp_result :: proc(e: ^Emitter, form: CST_Form, returns: Return_Spec) -> bool {
    return switch_may_escape_owned_temp_result_names(e, form, nil, returns)
}

form_is_borrowed_view_of_tracked_name :: proc(form: CST_Form, names: []string) -> bool {
    if form.kind != .List || len(form.items) < 2 || form.items[0].kind != .Symbol {
        return false
    }
    head := form.items[0].text
    if head != "odin-slice" {
        return false
    }
    source := form.items[1]
    return source.kind == .Symbol && binding_names_contain(names, map_name(source.text))
}

binding_declared_names_append :: proc(binding: Binding, names: ^[dynamic]string) {
    if binding.target.kind == .Vector || binding.target.kind == .Brace {
        pattern_names: [dynamic]string
        if _, ok_pattern := validate_data_pattern_names(binding.target, &pattern_names, true); ok_pattern {
            for name in pattern_names {
                binding_names_append_unique(names, name)
            }
        }
        delete(pattern_names)
        if binding.is_data_destructure || binding.target.kind == .Brace {
            return
        }
    }
    if binding.is_destructure || binding.is_result_binding {
        for name in binding.pattern {
            binding_names_append_unique(names, name)
        }
        return
    }
    binding_names_append_unique(names, binding.name)
}

track_owned_temp_result_assignments :: proc(e: ^Emitter, form: CST_Form, names: ^[dynamic]string, returns: Return_Spec) {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return
    }
    head := form.items[0].text
    if head == "set!" && len(form.items) == 3 {
        if assigned_name, ok_assigned := set_bang_assigned_name(form); ok_assigned &&
           form_may_escape_owned_temp_result_names(e, form.items[2], names[:], returns) {
            binding_names_append_unique(names, assigned_name)
        }
        return
    }
    switch head {
    case "let":
        bindings, _, ok_bind := parse_let_bindings(form.items[1])
        if !ok_bind {
            if len(form.items) >= 3 {
                for body_form in form.items[2:] {
                    track_owned_temp_result_assignments(e, body_form, names, returns)
                }
            }
            return
        }
        defer delete(bindings)

        scoped_names := make([dynamic]string, len(names[:]))
        defer delete(scoped_names)
        copy(scoped_names[:], names[:])

        local_names: [dynamic]string
        defer delete(local_names)
        for binding in bindings {
            binding_declared_names_append(binding, &local_names)
            if binding.is_destructure &&
               len(binding.pattern) > 0 &&
               binding.pattern[0] != "" &&
               form_may_escape_owned_temp_result_names(e, binding.value, scoped_names[:], returns) {
                binding_names_append_unique(&scoped_names, binding.pattern[0])
            } else if !binding.is_destructure &&
                      binding.name != "" &&
                      form_may_escape_owned_temp_result_names(e, binding.value, scoped_names[:], returns) {
                binding_names_append_unique(&scoped_names, binding.name)
            }
        }
        if len(form.items) >= 3 {
            for body_form in form.items[2:] {
                track_owned_temp_result_assignments(e, body_form, &scoped_names, returns)
            }
        }
        for name in scoped_names {
            if !binding_names_contain(names[:], name) && !binding_names_contain(local_names[:], name) {
                binding_names_append_unique(names, name)
            }
        }
    case "do":
        for item in form.items[1:] {
            track_owned_temp_result_assignments(e, item, names, returns)
        }
    case "if":
        if len(form.items) >= 3 {
            track_owned_temp_result_assignments(e, form.items[2], names, returns)
        }
        if len(form.items) >= 4 {
            track_owned_temp_result_assignments(e, form.items[3], names, returns)
        }
    case "type-case":
        i := 2
        for i < len(form.items) {
            if i+1 >= len(form.items) {
                return
            }
            track_owned_temp_result_assignments(e, form.items[i+1], names, returns)
            i += 2
        }
    case "match":
        for i := 3; i < len(form.items); i += 2 {
            track_owned_temp_result_assignments(e, form.items[i], names, returns)
        }
    case "with-allocator", "with-temp-allocator":
        if len(form.items) >= 3 {
            for item in form.items[2:] {
                track_owned_temp_result_assignments(e, item, names, returns)
            }
        }
    case:
        for item in form.items[1:] {
            track_owned_temp_result_assignments(e, item, names, returns)
        }
    }
}

form_escape_owned_temp_result_span_names :: proc(e: ^Emitter, form: CST_Form, names: []string, returns: Return_Spec) -> (Span, bool) {
    if len(names) == 0 && form_is_owned_temp_escape_result(form, e) {
        return form.span, true
    }
    if len(names) > 0 && return_spec_is_non_owned_scalar(returns) {
        return {}, false
    }

    #partial switch form.kind {
    case .Symbol:
        if binding_names_contain(names, map_name(form.text)) {
            return form.span, true
        }
        return {}, false
    case .Vector, .Brace, .Set:
        for item in form.items {
            if span, ok := form_escape_owned_temp_result_span_names(e, item, names, returns); ok {
                return span, true
            }
        }
        return {}, false
    case .List:
        if form_is_borrowed_view_of_tracked_name(form, names) {
            return {}, false
        }
        if len(form.items) == 0 || form.items[0].kind != .Symbol {
            if len(names) > 0 {
                for item in form.items {
                    if span, ok := form_escape_owned_temp_result_span_names(e, item, names, returns); ok {
                        return span, true
                    }
                }
                return {}, false
            }
            if !return_spec_is_non_owned_scalar(returns) {
                return form.span, true
            }
            return {}, false
        }
        switch form.items[0].text {
        case "return":
            for returned in form.items[1:] {
                if span, ok := form_escape_owned_temp_result_span_names(e, returned, names, returns); ok {
                    return span, true
                }
            }
            return {}, false
        case "let":
            bindings, _, ok_bind := parse_let_bindings(form.items[1])
            if !ok_bind {
                if len(form.items) >= 3 {
                    return body_escape_owned_temp_result_span_names(e, form.items[2:], names, returns)
                }
                return {}, false
            }
            scoped_names := make([dynamic]string, len(names))
            defer delete(scoped_names)
            copy(scoped_names[:], names)
            for binding in bindings {
                if binding.is_destructure &&
                   len(binding.pattern) > 0 &&
                   binding.pattern[0] != "" &&
                   form_may_escape_owned_temp_result_names(e, binding.value, scoped_names[:], returns) {
                    binding_names_append_unique(&scoped_names, binding.pattern[0])
                } else if !binding.is_destructure &&
                          binding.name != "" &&
                          form_may_escape_owned_temp_result_names(e, binding.value, scoped_names[:], returns) {
                    binding_names_append_unique(&scoped_names, binding.name)
                }
            }
            if len(form.items) >= 3 {
                return body_escape_owned_temp_result_span_names(e, form.items[2:], scoped_names[:], returns)
            }
            return {}, false
        case "do":
            if len(form.items) >= 2 {
                return body_escape_owned_temp_result_span_names(e, form.items[1:], names, returns)
            }
            return {}, false
        case "if":
            if len(form.items) >= 3 {
                if span, ok := form_escape_owned_temp_result_span_names(e, form.items[2], names, returns); ok {
                    return span, true
                }
            }
            if len(form.items) >= 4 {
                if span, ok := form_escape_owned_temp_result_span_names(e, form.items[3], names, returns); ok {
                    return span, true
                }
            }
            return {}, false
        case "type-case":
            return switch_escape_owned_temp_result_span_names(e, form, names, returns)
        case "match":
            for i := 3; i < len(form.items); i += 2 {
                if span, ok := form_escape_owned_temp_result_span_names(e, form.items[i], names, returns); ok {
                    return span, true
                }
            }
            return {}, false
        case "with-allocator", "with-temp-allocator":
            if len(form.items) >= 3 {
                return body_escape_owned_temp_result_span_names(e, form.items[2:], names, returns)
            }
            return {}, false
        case:
            if len(names) > 0 {
                for item in form.items[1:] {
                    if span, ok := form_escape_owned_temp_result_span_names(e, item, names, returns); ok {
                        return span, true
                    }
                }
                return {}, false
            }
            if !return_spec_is_non_owned_scalar(returns) {
                return form.span, true
            }
            return {}, false
        }
    }
    return {}, false
}

form_may_escape_owned_temp_result_names :: proc(e: ^Emitter, form: CST_Form, names: []string, returns: Return_Spec) -> bool {
    _, ok := form_escape_owned_temp_result_span_names(e, form, names, returns)
    return ok
}

form_may_escape_owned_temp_result :: proc(e: ^Emitter, form: CST_Form, returns: Return_Spec) -> bool {
    return form_may_escape_owned_temp_result_names(e, form, nil, returns)
}

let_defer_return_error :: proc(
    e: ^Emitter,
    bindings: []Binding,
    body: []CST_Form,
    last_in_proc: bool,
    returns: Return_Spec,
) -> (Compile_Error, bool) {
    // The REPL inserts this internal wrapper only when retained storage has a
    // real clone operation. It snapshots the tail before this let's deferred
    // cleanup runs. Keep the exception at the exact generated REPL boundary;
    // ordinary function returns still use the normal escape analysis.
    if e.repl_debug_enabled &&
       len(body) > 0 &&
       form_is_repl_snapshot_call(body[len(body)-1]) {
        return {}, false
    }
    for binding in bindings {
        if !binding.deferred_delete && !binding.defer_with_cleanup {
            continue
        }
        delete_name, ok_delete_name := binding_delete_target_name(binding)
        if !ok_delete_name {
            continue
        }
        names: [dynamic]string
        defer delete(names)
        append(&names, delete_name)
        for alias_binding in bindings {
            if alias_binding.name != "" && form_may_escape_deferred_binding_names(e, alias_binding.value, names[:], returns) {
                binding_names_append_unique(&names, alias_binding.name)
            }
        }
        if err_span, ok := body_escape_deferred_binding_span_names(e, body, names[:], returns); ok {
            message := "defer-marked binding cannot be returned; remove defer or transfer ownership explicitly"
            if binding.defer_with_cleanup {
                message = "defer-with binding cannot be returned; remove cleanup marker or transfer ownership explicitly"
            }
            return Compile_Error{
                message = message,
                span    = err_span,
            }, true
        }
    }
    return {}, false
}

let_errdefer_tail_error :: proc(bindings: []Binding, last_in_proc: bool) -> (Compile_Error, bool) {
    if last_in_proc {
        return {}, false
    }
    for binding in bindings {
        if binding.err_deferred_delete {
            return Compile_Error{
                message = ":errdefer is only supported in tail-position let forms",
                span    = binding.target_span,
            }, true
        }
    }
    return {}, false
}
