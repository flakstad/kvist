package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

borrowed_name_tracked :: proc(form: CST_Form, borrowed_names: []string) -> bool {
    if form.kind != .Symbol {
        return false
    }
    name := map_name(form.text)
    defer delete(name)
    return string_slice_contains_name(borrowed_names, name)
}

borrowed_source_param_tracked :: proc(form: CST_Form, return_ty: string, params: []Param) -> bool {
    if form.kind != .Symbol {
        return false
    }
    name := map_name(form.text)
    defer delete(name)
    for param in params {
        if param.name == name &&
           param.ownership != .Owned &&
           type_text_can_borrow_return_from_param(return_ty, param.ty) {
            return true
        }
    }
    return false
}

form_is_borrowed_result_zero_value :: proc(form: CST_Form, return_ty: string) -> bool {
    if form_is_zero_call(form) {
        return true
    }
    if type_text_is_string(return_ty) && form.kind == .String {
        text := unquote_string(form.text)
        defer delete(text)
        return text == ""
    }
    return type_text_is_slice(return_ty) && form.kind == .Nil
}

borrowed_names_untrack :: proc(borrowed_names: ^[dynamic]string, name: string) {
    for i := len(borrowed_names[:]) - 1; i >= 0; i -= 1 {
        if borrowed_names[i] == name {
            ordered_remove(borrowed_names, i)
        }
    }
}

borrowed_names_untrack_assigned :: proc(form: CST_Form, borrowed_names: ^[dynamic]string) {
    if form.kind != .List || len(form.items) == 0 {
        return
    }
    if form.items[0].kind == .Symbol && form.items[0].text == "set!" && len(form.items) == 3 {
        if form.items[1].kind == .Symbol {
            name := map_name(form.items[1].text)
            if name != "" {
                borrowed_names_untrack(borrowed_names, name)
            }
            delete(name)
        }
        return
    }
    for item in form.items[1:] {
        borrowed_names_untrack_assigned(item, borrowed_names)
    }
}

borrowed_names_replace_with_intersection :: proc(target: ^[dynamic]string, lhs, rhs: []string) {
    clear(target)
    for name in lhs {
        if string_slice_contains_name(rhs, name) {
            append(target, name)
        }
    }
}

borrowed_names_keep_intersection :: proc(target: ^[dynamic]string, branch: []string) {
    for i := len(target[:]) - 1; i >= 0; i -= 1 {
        if !string_slice_contains_name(branch, target[i]) {
            ordered_remove(target, i)
        }
    }
}

append_borrowed_binding_name :: proc(e: ^Emitter, form: CST_Form, borrowed_names: ^[dynamic]string, depth: int, return_ty: string, params: []Param) {
    if form.kind != .List || len(form.items) != 3 || form.items[0].kind != .Symbol || form.items[0].text != "set!" {
        return
    }
    if form.items[1].kind != .Symbol {
        return
    }
    name := map_name(form.items[1].text)
    if name == "" {
        delete(name)
        return
    }
    borrowed_names_untrack(borrowed_names, name)
    if !proc_decl_infers_borrowed_tail_call_form(e, form.items[2], depth+1, return_ty, params, borrowed_names[:]) {
        delete(name)
        return
    }
    append(borrowed_names, name)
}

track_borrowed_assignment :: proc(e: ^Emitter, form: CST_Form, borrowed_names: ^[dynamic]string, depth: int, return_ty: string, params: []Param) {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return
    }
    head := form.items[0].text
    switch head {
    case "set!":
        append_borrowed_binding_name(e, form, borrowed_names, depth+1, return_ty, params)
    case "do":
        for item in form.items[1:] {
            track_borrowed_assignment(e, item, borrowed_names, depth+1, return_ty, params)
        }
    case "if":
        if len(form.items) < 3 {
            return
        }
        then_names := make([dynamic]string, len(borrowed_names[:]))
        defer delete(then_names)
        copy(then_names[:], borrowed_names[:])
        track_borrowed_assignment(e, form.items[2], &then_names, depth+1, return_ty, params)

        else_names := make([dynamic]string, len(borrowed_names[:]))
        defer delete(else_names)
        copy(else_names[:], borrowed_names[:])
        if len(form.items) >= 4 {
            track_borrowed_assignment(e, form.items[3], &else_names, depth+1, return_ty, params)
        }
        borrowed_names_replace_with_intersection(borrowed_names, then_names[:], else_names[:])
    case "type-case":
        if len(form.items) < 5 || len(form.items)%2 == 0 {
            borrowed_names_untrack_assigned(form, borrowed_names)
            return
        }
        definite_names := make([dynamic]string, len(borrowed_names[:]))
        defer delete(definite_names)
        copy(definite_names[:], borrowed_names[:])

        first_branch := true
        i := 2
        for i < len(form.items)-1 {
            branch_names := make([dynamic]string, len(borrowed_names[:]))
            copy(branch_names[:], borrowed_names[:])
            track_borrowed_assignment(e, form.items[i+1], &branch_names, depth+1, return_ty, params)
            if first_branch {
                clear(&definite_names)
                for name in branch_names {
                    append(&definite_names, name)
                }
                first_branch = false
            } else {
                borrowed_names_keep_intersection(&definite_names, branch_names[:])
            }
            delete(branch_names)
            i += 2
        }

        default_names := make([dynamic]string, len(borrowed_names[:]))
        defer delete(default_names)
        copy(default_names[:], borrowed_names[:])
        track_borrowed_assignment(e, form.items[len(form.items)-1], &default_names, depth+1, return_ty, params)
        borrowed_names_keep_intersection(&definite_names, default_names[:])

        clear(borrowed_names)
        for name in definite_names {
            append(borrowed_names, name)
        }
    case "match":
        if len(form.items) < 4 {
            return
        }
        definite_names: [dynamic]string
        first_branch := true
        for i := 3; i < len(form.items); i += 2 {
            branch_names := make([dynamic]string, len(borrowed_names[:]))
            copy(branch_names[:], borrowed_names[:])
            track_borrowed_assignment(e, form.items[i], &branch_names, depth+1, return_ty, params)
            if first_branch {
                append(&definite_names, ..branch_names[:])
                first_branch = false
            } else {
                borrowed_names_keep_intersection(&definite_names, branch_names[:])
            }
            delete(branch_names)
        }
        clear(borrowed_names)
        append(borrowed_names, ..definite_names[:])
        delete(definite_names)
    case "let":
        if len(form.items) < 3 {
            return
        }
        bindings, _, ok_bind := parse_let_bindings(form.items[1])
        if !ok_bind {
            borrowed_names_untrack_assigned(form, borrowed_names)
            return
        }
        defer delete(bindings)

        scoped_names := make([dynamic]string, len(borrowed_names[:]))
        defer delete(scoped_names)
        copy(scoped_names[:], borrowed_names[:])

        local_names: [dynamic]string
        defer delete(local_names)
        for binding in bindings {
            binding_declared_names_append(binding, &local_names)
            if binding.is_destructure &&
               len(binding.pattern) > 0 &&
               binding.pattern[0] != "" &&
               proc_decl_infers_borrowed_tail_call_form(e, binding.value, depth+1, return_ty, params, scoped_names[:]) {
                borrowed_names_untrack(&scoped_names, binding.pattern[0])
                append(&scoped_names, binding.pattern[0])
            } else if !binding.is_destructure &&
                      binding.name != "" &&
                      proc_decl_infers_borrowed_tail_call_form(e, binding.value, depth+1, return_ty, params, scoped_names[:]) {
                borrowed_names_untrack(&scoped_names, binding.name)
                append(&scoped_names, binding.name)
            }
        }
        for item in form.items[2:] {
            track_borrowed_assignment(e, item, &scoped_names, depth+1, return_ty, params)
        }
        clear(borrowed_names)
        for name in scoped_names {
            if !string_slice_contains_name(local_names[:], name) {
                append(borrowed_names, name)
            }
        }
    case "fn", "quote", "quasiquote":
        return
    case:
        borrowed_names_untrack_assigned(form, borrowed_names)
        return
    }
}

proc_decl_infers_borrowed_tail_call_form :: proc(e: ^Emitter, form: CST_Form, depth: int, return_ty: string, params: []Param, borrowed_names: []string = nil) -> bool {
    if e == nil || depth > 8 {
        return false
    }
    if borrowed_name_tracked(form, borrowed_names) || borrowed_source_param_tracked(form, return_ty, params) {
        return true
    }
    if form_is_borrowed_interop_view_result(e, form) {
        return true
    }
    if known_odin_call_lifetime(form) == .Borrowed {
        return true
    }
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    head := form.items[0].text
    switch head {
    case "return":
        return return_values_infer_borrowed_tail_call(e, form.items[1:], depth+1, return_ty, params, borrowed_names)
    case "do":
        return len(form.items) > 1 && proc_decl_infers_borrowed_tail_call_body(e, form.items[1:], depth+1, return_ty, params, borrowed_names)
    case "let":
        if len(form.items) < 3 {
            return false
        }
        bindings, _, ok_bind := parse_let_bindings(form.items[1])
        if !ok_bind {
            return false
        }
        scoped_names: [dynamic]string
        for name in borrowed_names {
            append(&scoped_names, name)
        }
        for binding in bindings {
            if binding.is_destructure &&
               len(binding.pattern) > 0 &&
               binding.pattern[0] != "" &&
               proc_decl_infers_borrowed_tail_call_form(e, binding.value, depth+1, return_ty, params, scoped_names[:]) {
                borrowed_names_untrack(&scoped_names, binding.pattern[0])
                append(&scoped_names, binding.pattern[0])
            } else if !binding.is_destructure &&
                      binding.name != "" &&
                      proc_decl_infers_borrowed_tail_call_form(e, binding.value, depth+1, return_ty, params, scoped_names[:]) {
                borrowed_names_untrack(&scoped_names, binding.name)
                append(&scoped_names, binding.name)
            }
        }
        return proc_decl_infers_borrowed_tail_call_body(e, form.items[2:], depth+1, return_ty, params, scoped_names[:])
    case "if":
        if len(form.items) != 4 {
            return false
        }
        then_borrowed := proc_decl_infers_borrowed_tail_call_form(e, form.items[2], depth+1, return_ty, params, borrowed_names)
        else_borrowed := proc_decl_infers_borrowed_tail_call_form(e, form.items[3], depth+1, return_ty, params, borrowed_names)
        return (then_borrowed || form_is_borrowed_result_zero_value(form.items[2], return_ty)) &&
               (else_borrowed || form_is_borrowed_result_zero_value(form.items[3], return_ty)) &&
               (then_borrowed || else_borrowed)
    case "type-case":
        if len(form.items) < 5 || len(form.items)%2 == 0 {
            return false
        }
        i := 2
        for i < len(form.items)-1 {
            if !proc_decl_infers_borrowed_tail_call_form(e, form.items[i+1], depth+1, return_ty, params, borrowed_names) {
                return false
            }
            i += 2
        }
        return proc_decl_infers_borrowed_tail_call_form(e, form.items[len(form.items)-1], depth+1, return_ty, params, borrowed_names)
    case "match":
        if len(form.items) < 4 {
            return false
        }
        for i := 3; i < len(form.items); i += 2 {
            if !proc_decl_infers_borrowed_tail_call_form(e, form.items[i], depth+1, return_ty, params, borrowed_names) {
                return false
            }
        }
        return true
    }
    _, ok := proc_decl_borrowed_view_decl_depth(e, head, depth+1)
    return ok
}

return_values_infer_borrowed_tail_call :: proc(e: ^Emitter, values: []CST_Form, depth: int, return_ty: string, params: []Param, borrowed_names: []string = nil) -> bool {
    if len(values) == 0 {
        return false
    }
    for value in values {
        if proc_decl_infers_borrowed_tail_call_form(e, value, depth+1, return_ty, params, borrowed_names) {
            return true
        }
    }
    return false
}

proc_decl_infers_borrowed_tail_call_body :: proc(e: ^Emitter, body: []CST_Form, depth: int, return_ty: string, params: []Param, borrowed_names: []string = nil) -> bool {
    if len(body) == 0 {
        return false
    }
    scoped_names: [dynamic]string
    for name in borrowed_names {
        append(&scoped_names, name)
    }
    for form in body[:len(body)-1] {
        track_borrowed_assignment(e, form, &scoped_names, depth+1, return_ty, params)
    }
    return proc_decl_infers_borrowed_tail_call_form(e, body[len(body)-1], depth, return_ty, params, scoped_names[:])
}

proc_decl_all_returns_infer_borrowed_tail_call_form :: proc(e: ^Emitter, form: CST_Form, depth: int, return_ty: string, params: []Param, borrowed_names: []string = nil) -> bool {
    if form.kind != .List || len(form.items) == 0 {
        return true
    }
    if form.items[0].kind == .Symbol {
        head := form.items[0].text
        switch head {
        case "return":
            return return_values_infer_borrowed_tail_call(e, form.items[1:], depth+1, return_ty, params, borrowed_names)
        case "fn", "quote", "quasiquote":
            return true
        case "let":
            if len(form.items) < 3 {
                return true
            }
            bindings, _, ok_bind := parse_let_bindings(form.items[1])
            if !ok_bind {
                return true
            }
            scoped_names: [dynamic]string
            for name in borrowed_names {
                append(&scoped_names, name)
            }
            for binding in bindings {
                if binding.is_destructure &&
                   len(binding.pattern) > 0 &&
                   binding.pattern[0] != "" &&
                   proc_decl_infers_borrowed_tail_call_form(e, binding.value, depth+1, return_ty, params, scoped_names[:]) {
                    borrowed_names_untrack(&scoped_names, binding.pattern[0])
                    append(&scoped_names, binding.pattern[0])
                } else if !binding.is_destructure &&
                          binding.name != "" &&
                          proc_decl_infers_borrowed_tail_call_form(e, binding.value, depth+1, return_ty, params, scoped_names[:]) {
                    borrowed_names_untrack(&scoped_names, binding.name)
                    append(&scoped_names, binding.name)
                }
            }
            return proc_decl_all_returns_infer_borrowed_tail_call_body(e, form.items[2:], depth+1, return_ty, params, scoped_names[:])
        case "type-case":
            if len(form.items) < 5 || len(form.items)%2 == 0 {
                return true
            }
            i := 2
            for i < len(form.items)-1 {
                if !proc_decl_all_returns_infer_borrowed_tail_call_form(e, form.items[i+1], depth+1, return_ty, params, borrowed_names) {
                    return false
                }
                i += 2
            }
            return proc_decl_all_returns_infer_borrowed_tail_call_form(e, form.items[len(form.items)-1], depth+1, return_ty, params, borrowed_names)
        case "match":
            for i := 3; i < len(form.items); i += 2 {
                if !proc_decl_all_returns_infer_borrowed_tail_call_form(e, form.items[i], depth+1, return_ty, params, borrowed_names) {
                    return false
                }
            }
            return true
        }
    }
    for item in form.items[1:] {
        if !proc_decl_all_returns_infer_borrowed_tail_call_form(e, item, depth+1, return_ty, params, borrowed_names) {
            return false
        }
    }
    return true
}

proc_decl_all_returns_infer_borrowed_tail_call_body :: proc(e: ^Emitter, body: []CST_Form, depth: int, return_ty: string, params: []Param, borrowed_names: []string = nil) -> bool {
    scoped_names: [dynamic]string
    for name in borrowed_names {
        append(&scoped_names, name)
    }
    for form in body {
        if !proc_decl_all_returns_infer_borrowed_tail_call_form(e, form, depth, return_ty, params, scoped_names[:]) {
            return false
        }
        track_borrowed_assignment(e, form, &scoped_names, depth+1, return_ty, params)
    }
    return true
}

proc_decl_infers_borrowed_tail_call :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, depth: int) -> bool {
    if proc_decl == nil {
        return false
    }
    return_ty, ok_return := borrowed_return_type_text(proc_decl.returns)
    if !ok_return {
        return false
    }
    return proc_decl_infers_borrowed_tail_call_body(e, proc_decl.body[:], depth, return_ty, proc_decl.params[:]) &&
           proc_decl_all_returns_infer_borrowed_tail_call_body(e, proc_decl.body[:], depth, return_ty, proc_decl.params[:])
}

proc_decl_borrowed_view_decl_depth :: proc(e: ^Emitter, name: string, depth: int) -> (^Proc_Decl, bool) {
    if e == nil {
        return nil, false
    }
    if depth > 8 {
        return nil, false
    }
    direct_name := map_name(name)
    if proc_decl, ok_proc := find_proc_decl(e, direct_name); ok_proc {
        if proc_decl.borrows_result || proc_decl_infers_borrowed_tail_call(e, proc_decl, depth+1) {
            return proc_decl, true
        }
    }
    return nil, false
}

proc_decl_borrowed_view_decl :: proc(e: ^Emitter, name: string) -> (^Proc_Decl, bool) {
    return proc_decl_borrowed_view_decl_depth(e, name, 0)
}

proc_decl_borrowed_view_head :: proc(e: ^Emitter, name: string) -> bool {
    _, ok := proc_decl_borrowed_view_decl(e, name)
    return ok
}

borrowed_strings_view_member :: proc(member: string) -> bool {
    switch member {
    case "trim",
         "trim_left",
         "trim_left_null",
         "trim_left_proc",
         "trim_left_proc_with_state",
         "trim_left_space",
         "trim_null",
         "trim_prefix",
         "trim_right",
         "trim_right_null",
         "trim_right_proc",
         "trim_right_proc_with_state",
         "trim_right_space",
         "trim_space",
         "trim_suffix":
        return true
    }
    return false
}

form_is_borrowed_interop_view_result :: proc(e: ^Emitter, form: CST_Form) -> bool {
    if form.kind != .List || len(form.items) < 2 || form.items[0].kind != .Symbol {
        return false
    }
    head_name := map_name(form.items[0].text)
    defer delete(head_name)
    if e != nil {
        if alias, member, ok_parts := imported_interop_call_parts(head_name); ok_parts && borrowed_strings_view_member(member) {
            for decl in e.decls {
                if import_decl_alias_matches(decl, alias) && import_decl_path_matches(decl, "core:strings") {
                    return true
                }
            }
        }
    }
    switch head_name {
    case "odin_slice",
         "odin-slice":
        return true
    }
    return false
}

form_has_owned_output_type_operand :: proc(form: CST_Form) -> bool {
    if form.kind != .List || len(form.items) < 4 || form.items[0].kind != .Symbol {
        return false
    }
    raw_head := form.items[0].text
    if raw_head != "into" {
        return false
    }
    output_ty, _, _, ok_output_ty := parse_type_text_from_forms(form.items[:], 1)
    if !ok_output_ty {
        return false
    }
    defer delete(output_ty)
    return type_text_is_owned_result(output_ty)
}

Owned_Alloc_Result_Kind :: enum {
    String,
    Bytes,
    Slice,
    Opaque,
    Container,
}

Known_Foreign_Lifetime :: enum {
    Unknown,
    Borrowed,
    Owned,
}

Foreign_Lifetime_Binding :: struct {
    target: string,
    result: Known_Foreign_Lifetime,
}

FOREIGN_LIFETIME_BINDINGS :: []Foreign_Lifetime_Binding{
    {"kvist_data_empty_map", .Owned},
    {"kvist_data_make_unique_set", .Owned},
    {"kvist_data_freeze_items", .Owned},
    {"kvist_data_freeze_map", .Owned},
    {"kvist_data_freeze_unique_map", .Owned},
    {"kvist_data_retain", .Owned},
    {"kvist_data_assoc", .Owned},
    {"kvist_data_update", .Owned},
    {"kvist_data_dissoc", .Owned},
    {"kvist_data_conj", .Owned},
    {"kvist_data_disj", .Owned},
    {"kvist_data_string", .Borrowed},
    {"kvist_data_symbol", .Borrowed},
    {"kvist_data_keyword", .Borrowed},
    {"kvist_data_text", .Borrowed},
    {"kvist_data_tag", .Borrowed},
    {"kvist_data_tagged_value", .Borrowed},
    {"kvist_data_key_at", .Borrowed},
    {"kvist_data_value_at", .Borrowed},
    {"kvist_data_item_at", .Borrowed},
    {"kvist_data_get", .Borrowed},
}

known_odin_call_lifetime :: proc(form: CST_Form) -> Known_Foreign_Lifetime {
    if form.kind != .List ||
       len(form.items) < 2 ||
       form.items[0].kind != .Symbol ||
       form.items[0].text != "odin-call" ||
       form.items[1].kind != .String {
        return .Unknown
    }
    target := unquote_string(form.items[1].text)
    defer delete(target)
    // All `kvist_data_make_*` functions are constructors in the Kvist runtime
    // ABI and return one shared reference owned by the caller.
    if strings.has_prefix(target, "kvist_data_make_") {
        return .Owned
    }
    for binding in FOREIGN_LIFETIME_BINDINGS {
        if binding.target == target {
            return binding.result
        }
    }
    return .Unknown
}

form_infers_known_foreign_lifetime :: proc(
    form: CST_Form,
    expected: Known_Foreign_Lifetime,
    depth: int = 0,
    e: ^Emitter = nil,
) -> bool {
    if depth > 16 {
        return false
    }
    if known_odin_call_lifetime(form) == expected {
        return true
    }
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    switch form.items[0].text {
    case "return":
        if len(form.items) != 2 {
            return false
        }
        return form_infers_known_foreign_lifetime(form.items[1], expected, depth+1, e)
    case "do", "block":
        return len(form.items) > 1 &&
               form_infers_known_foreign_lifetime(form.items[len(form.items)-1], expected, depth+1, e)
    case "let":
        return len(form.items) > 2 &&
               form_infers_known_foreign_lifetime(form.items[len(form.items)-1], expected, depth+1, e)
    case "if":
        return len(form.items) == 4 &&
               form_infers_known_foreign_lifetime(form.items[2], expected, depth+1, e) &&
               form_infers_known_foreign_lifetime(form.items[3], expected, depth+1, e)
    case "case", "type-case":
        if len(form.items) < 5 || len(form.items)%2 == 0 {
            return false
        }
        i := 3
        for i < len(form.items)-1 {
            if !form_infers_known_foreign_lifetime(form.items[i], expected, depth+1, e) {
                return false
            }
            i += 2
        }
        return form_infers_known_foreign_lifetime(
            form.items[len(form.items)-1],
            expected,
            depth+1,
            e,
        )
    case "match":
        if len(form.items) < 4 {
            return false
        }
        for i := 3; i < len(form.items); i += 2 {
            if !form_infers_known_foreign_lifetime(form.items[i], expected, depth+1, e) {
                return false
            }
        }
        return true
    }
    if e != nil {
        if _, proc_decl, ok_proc := resolve_proc_call_decl(e, form.items[0].text);
           ok_proc && proc_decl != nil {
            return proc_decl.owns_result if expected == .Owned else proc_decl.borrows_result
        }
    }
    return false
}

owned_import_alloc_call_head :: proc(e: ^Emitter, text: string, kind: Owned_Alloc_Result_Kind) -> bool {
    switch kind {
    case .String:
        // `fmt` is an implicit core import when a form uses that namespace,
        // so it is not necessarily represented by an import declaration.
        return text == "fmt.aprintf" ||
               text == "fmt/aprintf" ||
               imported_interop_call_matches(e, text, "core:fmt", "aprintf") ||
               imported_interop_call_matches(e, text, "core:strings", "clone") ||
               imported_interop_call_matches(e, text, "core:strings", "to_lower") ||
               imported_interop_call_matches(e, text, "core:strings", "to_upper") ||
               imported_interop_call_matches(e, text, "core:strings", "replace")
    case .Bytes:
        return imported_interop_call_matches(e, text, "core:os", "read_entire_file")
    case .Slice:
        return imported_interop_call_matches(e, text, "core:strings", "split")
    case .Opaque:
        return imported_interop_call_matches(e, text, "core:text/regex", "create") ||
               imported_interop_call_matches(e, text, "core:text/regex", "match_and_allocate_capture")
    case .Container:
        return false
    }
    return false
}

form_is_owned_alloc_call :: proc(form: CST_Form, kind: Owned_Alloc_Result_Kind, e: ^Emitter = nil) -> bool {
    if kind == .Container {
        return form_is_owned_allocation_result(form) || form_is_owned_constructor_result(form)
    }
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    head_name := map_name(form.items[0].text)
    defer delete(head_name)
    return owned_import_alloc_call_head(e, head_name, kind)
}

string_slice_contains_name :: proc(names: []string, name: string) -> bool {
    for candidate in names {
        if candidate == name {
            return true
        }
    }
    return false
}

return_type_matches_owned_alloc_kind :: proc(ty: string, kind: Owned_Alloc_Result_Kind) -> bool {
    switch kind {
    case .String:
        return ty == "string"
    case .Bytes:
        return ty == "[]byte"
    case .Slice:
        return type_text_is_slice(ty)
    case .Opaque:
        return true
    case .Container:
        return type_text_is_owned_result(ty)
    }
    return false
}

return_spec_matches_owned_alloc_kind :: proc(returns: Return_Spec, kind: Owned_Alloc_Result_Kind) -> bool {
    if returns.kind == .Single {
        return return_type_matches_owned_alloc_kind(returns.single_ty, kind)
    }
    if returns.kind == .Named {
        for named in returns.named {
            if return_type_matches_owned_alloc_kind(named.ty, kind) {
                return true
            }
        }
    }
    return false
}

form_is_untracked_symbol_result :: proc(form: CST_Form, owned_names: []string) -> bool {
    if form.kind != .Symbol {
        return false
    }
    name := map_name(form.text)
    defer delete(name)
    return !string_slice_contains_name(owned_names, name)
}

form_is_owned_result_zero_value :: proc(form: CST_Form, kind: Owned_Alloc_Result_Kind) -> bool {
    if form_is_zero_call(form) {
        return true
    }
    switch kind {
    case .String:
        if form.kind != .String {
            return false
        }
        text := unquote_string(form.text)
        defer delete(text)
        return text == ""
    case .Bytes, .Slice, .Container:
        return form.kind == .Nil
    case .Opaque:
        return false
    }
    return false
}

untrack_owned_name :: proc(owned_names: ^[dynamic]string, name: string) {
    for i := len(owned_names[:]) - 1; i >= 0; i -= 1 {
        if owned_names[i] != name {
            continue
        }
        ordered_remove(owned_names, i)
    }
}

untrack_assigned_names :: proc(form: CST_Form, owned_names: ^[dynamic]string) {
    if form.kind != .List || len(form.items) == 0 {
        return
    }
    if form.items[0].kind == .Symbol && form.items[0].text == "set!" && len(form.items) == 3 {
        if form.items[1].kind == .Symbol {
            name := map_name(form.items[1].text)
            if name != "" {
                untrack_owned_name(owned_names, name)
            }
            delete(name)
        }
        return
    }
    for item in form.items[1:] {
        untrack_assigned_names(item, owned_names)
    }
}

owned_names_replace_with_intersection :: proc(target: ^[dynamic]string, lhs, rhs: []string) {
    clear(target)
    for name in lhs {
        if string_slice_contains_name(rhs, name) {
            append(target, name)
        }
    }
}

owned_names_keep_intersection :: proc(target: ^[dynamic]string, branch: []string) {
    for i := len(target[:]) - 1; i >= 0; i -= 1 {
        if !string_slice_contains_name(branch, target[i]) {
            ordered_remove(target, i)
        }
    }
}

append_owned_binding_name :: proc(form: CST_Form, owned_names: ^[dynamic]string, kind: Owned_Alloc_Result_Kind, e: ^Emitter, depth: int) {
    if form.kind != .List || len(form.items) != 3 || form.items[0].kind != .Symbol || form.items[0].text != "set!" {
        return
    }
    if form.items[1].kind != .Symbol {
        return
    }
    name := map_name(form.items[1].text)
    if name == "" {
        delete(name)
        return
    }
    untrack_owned_name(owned_names, name)
    if !form_infers_owned_alloc_result(form.items[2], owned_names[:], kind, e, depth+1) {
        delete(name)
        return
    }
    append(owned_names, name)
}

track_owned_assignment :: proc(form: CST_Form, owned_names: ^[dynamic]string, kind: Owned_Alloc_Result_Kind, e: ^Emitter = nil, depth: int = 0) {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return
    }
    head := form.items[0].text
    switch head {
    case "set!":
        append_owned_binding_name(form, owned_names, kind, e, depth+1)
    case "do":
        for item in form.items[1:] {
            track_owned_assignment(item, owned_names, kind, e, depth+1)
        }
    case "if":
        if len(form.items) < 3 {
            return
        }
        then_names := make([dynamic]string, len(owned_names[:]))
        defer delete(then_names)
        copy(then_names[:], owned_names[:])
        track_owned_assignment(form.items[2], &then_names, kind, e, depth+1)

        else_names := make([dynamic]string, len(owned_names[:]))
        defer delete(else_names)
        copy(else_names[:], owned_names[:])
        if len(form.items) >= 4 {
            track_owned_assignment(form.items[3], &else_names, kind, e, depth+1)
        }
        owned_names_replace_with_intersection(owned_names, then_names[:], else_names[:])
    case "type-case":
        if len(form.items) < 5 || len(form.items)%2 == 0 {
            untrack_assigned_names(form, owned_names)
            return
        }
        definite_names := make([dynamic]string, len(owned_names[:]))
        defer delete(definite_names)
        copy(definite_names[:], owned_names[:])

        first_branch := true
        i := 2
        for i < len(form.items)-1 {
            branch_names := make([dynamic]string, len(owned_names[:]))
            copy(branch_names[:], owned_names[:])
            track_owned_assignment(form.items[i+1], &branch_names, kind, e, depth+1)
            if first_branch {
                clear(&definite_names)
                for name in branch_names {
                    append(&definite_names, name)
                }
                first_branch = false
            } else {
                owned_names_keep_intersection(&definite_names, branch_names[:])
            }
            delete(branch_names)
            i += 2
        }

        default_names := make([dynamic]string, len(owned_names[:]))
        defer delete(default_names)
        copy(default_names[:], owned_names[:])
        track_owned_assignment(form.items[len(form.items)-1], &default_names, kind, e, depth+1)
        owned_names_keep_intersection(&definite_names, default_names[:])

        clear(owned_names)
        for name in definite_names {
            append(owned_names, name)
        }
    case "match":
        if len(form.items) < 4 {
            return
        }
        definite_names: [dynamic]string
        first_branch := true
        for i := 3; i < len(form.items); i += 2 {
            branch_names := make([dynamic]string, len(owned_names[:]))
            copy(branch_names[:], owned_names[:])
            track_owned_assignment(form.items[i], &branch_names, kind, e, depth+1)
            if first_branch {
                append(&definite_names, ..branch_names[:])
                first_branch = false
            } else {
                owned_names_keep_intersection(&definite_names, branch_names[:])
            }
            delete(branch_names)
        }
        clear(owned_names)
        append(owned_names, ..definite_names[:])
        delete(definite_names)
    case "let":
        if len(form.items) < 3 {
            return
        }
        bindings, _, ok_bind := parse_let_bindings(form.items[1])
        if !ok_bind {
            untrack_assigned_names(form, owned_names)
            return
        }
        defer delete(bindings)

        scoped_names := make([dynamic]string, len(owned_names[:]))
        defer delete(scoped_names)
        copy(scoped_names[:], owned_names[:])

        local_names: [dynamic]string
        defer delete(local_names)
        for binding in bindings {
            binding_declared_names_append(binding, &local_names)
            if binding.is_destructure &&
               len(binding.pattern) > 0 &&
               binding.pattern[0] != "" &&
               form_infers_owned_alloc_result(binding.value, scoped_names[:], kind, e, depth+1) {
                append(&scoped_names, binding.pattern[0])
            } else if !binding.is_destructure &&
                      binding.name != "" &&
                      form_infers_owned_alloc_result(binding.value, scoped_names[:], kind, e, depth+1) {
                append(&scoped_names, binding.name)
            }
        }
        for item in form.items[2:] {
            track_owned_assignment(item, &scoped_names, kind, e, depth+1)
        }
        clear(owned_names)
        for name in scoped_names {
            if !string_slice_contains_name(local_names[:], name) {
                append(owned_names, name)
            }
        }
    case "fn", "quote", "quasiquote":
        return
    case:
        untrack_assigned_names(form, owned_names)
        return
    }
}

form_is_owned_source_proc_call :: proc(form: CST_Form, kind: Owned_Alloc_Result_Kind, e: ^Emitter, depth: int) -> bool {
    if e == nil || depth > 8 || form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    direct_name := map_name(form.items[0].text)
    defer delete(direct_name)
    if proc_decl, ok_proc := find_proc_decl(e, direct_name); ok_proc {
        return proc_decl.owns_result ||
               proc_decl_infers_owned_alloc_result_depth(e, proc_decl, kind, depth+1)
    }
    return false
}

form_infers_owned_alloc_result :: proc(form: CST_Form, owned_names: []string, kind: Owned_Alloc_Result_Kind, e: ^Emitter = nil, depth: int = 0) -> bool {
    if form_is_owned_alloc_call(form, kind, e) {
        return true
    }
    if form.kind == .Symbol {
        name := map_name(form.text)
        defer delete(name)
        return string_slice_contains_name(owned_names, name)
    }
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    if form_is_owned_source_proc_call(form, kind, e, depth+1) {
        return true
    }
    head := form.items[0].text
    switch head {
    case "return":
        for item in form.items[1:] {
            if form_infers_owned_alloc_result(item, owned_names, kind, e, depth+1) {
                return true
            }
        }
    case "do":
        return body_tail_infers_owned_alloc_result(form.items[1:], owned_names, kind, e, depth+1)
    case "if":
        if len(form.items) != 4 {
            return false
        }
        if form_is_untracked_symbol_result(form.items[2], owned_names) ||
           form_is_untracked_symbol_result(form.items[3], owned_names) {
            return false
        }
        then_owned := form_infers_owned_alloc_result(form.items[2], owned_names, kind, e, depth+1)
        else_owned := form_infers_owned_alloc_result(form.items[3], owned_names, kind, e, depth+1)
        return (then_owned || form_is_owned_result_zero_value(form.items[2], kind)) &&
               (else_owned || form_is_owned_result_zero_value(form.items[3], kind)) &&
               (then_owned || else_owned)
    case "type-case":
        if len(form.items) < 5 || len(form.items)%2 == 0 {
            return false
        }
        i := 2
        for i < len(form.items)-1 {
            if form_is_untracked_symbol_result(form.items[i+1], owned_names) ||
               !form_infers_owned_alloc_result(form.items[i+1], owned_names, kind, e, depth+1) {
                return false
            }
            i += 2
        }
        return !form_is_untracked_symbol_result(form.items[len(form.items)-1], owned_names) &&
               form_infers_owned_alloc_result(form.items[len(form.items)-1], owned_names, kind, e, depth+1)
    case "match":
        if len(form.items) < 4 {
            return false
        }
        for i := 3; i < len(form.items); i += 2 {
            if form_is_untracked_symbol_result(form.items[i], owned_names) ||
               !form_infers_owned_alloc_result(form.items[i], owned_names, kind, e, depth+1) {
                return false
            }
        }
        return true
    case "let":
        if len(form.items) < 3 {
            return false
        }
        bindings, _, ok_bind := parse_let_bindings(form.items[1])
        if !ok_bind {
            return false
        }
        scoped_names: [dynamic]string
        for name in owned_names {
            append(&scoped_names, name)
        }
        for binding in bindings {
            if binding.is_destructure &&
               len(binding.pattern) > 0 &&
               binding.pattern[0] != "" &&
               form_infers_owned_alloc_result(binding.value, scoped_names[:], kind, e, depth+1) {
                append(&scoped_names, binding.pattern[0])
            } else if !binding.is_destructure &&
                      binding.name != "" &&
                      form_infers_owned_alloc_result(binding.value, scoped_names[:], kind, e, depth+1) {
                append(&scoped_names, binding.name)
            }
        }
        return body_tail_infers_owned_alloc_result(form.items[2:], scoped_names[:], kind, e, depth+1)
    }
    return false
}

return_values_infer_owned_alloc_result :: proc(values: []CST_Form, owned_names: []string, kind: Owned_Alloc_Result_Kind, e: ^Emitter = nil, depth: int = 0) -> bool {
    if len(values) == 0 {
        return false
    }
    for value in values {
        if form_infers_owned_alloc_result(value, owned_names, kind, e, depth+1) {
            return true
        }
    }
    return false
}

form_all_returns_infer_owned_alloc_result :: proc(form: CST_Form, owned_names: []string, kind: Owned_Alloc_Result_Kind, e: ^Emitter = nil, depth: int = 0) -> bool {
    if form.kind != .List || len(form.items) == 0 {
        return true
    }
    if form.items[0].kind == .Symbol {
        head := form.items[0].text
        switch head {
        case "return":
            return return_values_infer_owned_alloc_result(form.items[1:], owned_names, kind, e, depth+1)
        case "do":
            return body_all_returns_infer_owned_alloc_result(form.items[1:], owned_names, kind, e, depth+1)
        case "fn", "quote", "quasiquote":
            return true
        case "let":
            if len(form.items) < 3 {
                return true
            }
            bindings, _, ok_bind := parse_let_bindings(form.items[1])
            if !ok_bind {
                return true
            }
            scoped_names: [dynamic]string
            for name in owned_names {
                append(&scoped_names, name)
            }
            for binding in bindings {
                if binding.is_destructure &&
                   len(binding.pattern) > 0 &&
                   binding.pattern[0] != "" &&
                   form_infers_owned_alloc_result(binding.value, scoped_names[:], kind, e, depth+1) {
                    append(&scoped_names, binding.pattern[0])
                } else if !binding.is_destructure &&
                          binding.name != "" &&
                          form_infers_owned_alloc_result(binding.value, scoped_names[:], kind, e, depth+1) {
                    append(&scoped_names, binding.name)
                }
            }
            return body_all_returns_infer_owned_alloc_result(form.items[2:], scoped_names[:], kind, e, depth+1)
        case "type-case":
            if len(form.items) < 5 || len(form.items)%2 == 0 {
                return true
            }
            i := 2
            for i < len(form.items)-1 {
                if !form_all_returns_infer_owned_alloc_result(form.items[i+1], owned_names, kind, e, depth+1) {
                    return false
                }
                i += 2
            }
            return form_all_returns_infer_owned_alloc_result(form.items[len(form.items)-1], owned_names, kind, e, depth+1)
        case "match":
            for i := 3; i < len(form.items); i += 2 {
                if !form_all_returns_infer_owned_alloc_result(form.items[i], owned_names, kind, e, depth+1) {
                    return false
                }
            }
            return true
        }
    }
    for item in form.items[1:] {
        if !form_all_returns_infer_owned_alloc_result(item, owned_names, kind, e, depth+1) {
            return false
        }
    }
    return true
}

body_all_returns_infer_owned_alloc_result :: proc(body: []CST_Form, owned_names: []string, kind: Owned_Alloc_Result_Kind, e: ^Emitter = nil, depth: int = 0) -> bool {
    scoped_names: [dynamic]string
    for name in owned_names {
        append(&scoped_names, name)
    }
    for form in body {
        if !form_all_returns_infer_owned_alloc_result(form, scoped_names[:], kind, e, depth+1) {
            return false
        }
        track_owned_assignment(form, &scoped_names, kind, e, depth+1)
    }
    return true
}

body_tail_infers_owned_alloc_result :: proc(body: []CST_Form, owned_names: []string, kind: Owned_Alloc_Result_Kind, e: ^Emitter = nil, depth: int = 0) -> bool {
    if len(body) == 0 {
        return false
    }
    scoped_names: [dynamic]string
    for name in owned_names {
        append(&scoped_names, name)
    }
    for form in body[:len(body)-1] {
        track_owned_assignment(form, &scoped_names, kind, e, depth+1)
    }
    return form_infers_owned_alloc_result(body[len(body)-1], scoped_names[:], kind, e, depth+1)
}

proc_decl_infers_owned_alloc_result_depth :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, kind: Owned_Alloc_Result_Kind, depth: int = 0) -> bool {
    if depth > 8 {
        return false
    }
    if !return_spec_matches_owned_alloc_kind(proc_decl.returns, kind) {
        return false
    }
    return body_tail_infers_owned_alloc_result(proc_decl.body[:], nil, kind, e, depth+1) &&
           body_all_returns_infer_owned_alloc_result(proc_decl.body[:], nil, kind, e, depth+1)
}

proc_decl_infers_owned_alloc_result :: proc(proc_decl: ^Proc_Decl, kind: Owned_Alloc_Result_Kind) -> bool {
    return proc_decl_infers_owned_alloc_result_depth(nil, proc_decl, kind)
}

proc_decl_infers_owned_result :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, depth: int = 0) -> bool {
    return proc_decl_infers_owned_alloc_result_depth(e, proc_decl, .String, depth+1) ||
           proc_decl_infers_owned_alloc_result_depth(e, proc_decl, .Bytes, depth+1) ||
           proc_decl_infers_owned_alloc_result_depth(e, proc_decl, .Slice, depth+1) ||
           proc_decl_infers_owned_alloc_result_depth(e, proc_decl, .Opaque, depth+1) ||
           proc_decl_infers_owned_alloc_result_depth(e, proc_decl, .Container, depth+1)
}

proc_decl_owned_result_head :: proc(e: ^Emitter, name: string) -> bool {
    if e == nil {
        return false
    }
    direct_name := map_name(name)
    defer delete(direct_name)
    if proc_decl, ok_proc := find_proc_decl(e, direct_name); ok_proc {
        // Data ownership is handled by the managed-value path. Treating it as
        // an ordinary native owned result here would reject valid nested Data
        // expressions before contextual management can retain or release them.
        if proc_decl.returns.kind == .Single &&
           type_text_is_managed_value(e, proc_decl.returns.single_ty) {
            return false
        }
        return proc_decl.owns_result || proc_decl_infers_owned_result(e, proc_decl)
    }
    return false
}

form_is_owned_result :: proc(form: CST_Form, e: ^Emitter = nil) -> bool {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    // Core macros are expanded while emitting expressions. Preserve their
    // ownership contract for the earlier ownership-analysis pass without
    // making their lowering a compiler special form.
    switch form.items[0].text {
    case "str", "core.str", "core/str", "fmt.aprintf", "fmt/aprintf":
        return true
    }
    if proc_decl_owned_result_head(e, form.items[0].text) {
        return true
    }
    if form_has_owned_output_type_operand(form) {
        return true
    }
    return false
}

form_is_borrowed_view_result :: proc(form: CST_Form, e: ^Emitter = nil) -> bool {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    if proc_decl_borrowed_view_head(e, form.items[0].text) {
        return true
    }
    if form_is_borrowed_interop_view_result(e, form) {
        return true
    }
    return false
}

borrowed_delete_warning_message :: proc(form: CST_Form) -> string {
    subject := "borrowed view"
    if head, ok := form_head_symbol_text(form); ok {
        subject = display_head_name(head)
    }
    return fmt.tprintf("%s returns a borrowed view; do not delete it, delete the owner instead", subject)
}

form_is_transform_source_call :: proc(e: ^Emitter, form: CST_Form) -> bool {
    if form_is_direct_transform_source_call(form) {
        return true
    }
    if e != nil {
        if _, ok_source_call := source_call_decl(e, form); ok_source_call {
            return true
        }
    }
    return false
}

owned_transform_source_args_usage_error :: proc(form: CST_Form, e: ^Emitter = nil) -> (Compile_Error, bool) {
    if !form_is_transform_source_call(e, form) {
        return {}, false
    }
    if form.kind != .List {
        return {}, false
    }
    for item in form.items[1:] {
        err_item, bad_item := owned_result_usage_error(item, false, e)
        if bad_item {
            return err_item, true
        }
    }
    return {}, false
}

owned_direct_source_allowed_in_transform_source_slot :: proc(parent: CST_Form, item_index: int, e: ^Emitter = nil) -> bool {
    if parent.kind != .List || len(parent.items) == 0 || parent.items[0].kind != .Symbol {
        return false
    }
    raw_head := parent.items[0].text
    if raw_head == "transduce" {
        return len(parent.items) == 5 && item_index == 4 && form_is_transform_source_call(e, parent.items[item_index])
    }
    if raw_head == "into" || raw_head == "transform-into!" {
        return item_index == len(parent.items)-1 && form_is_transform_source_call(e, parent.items[item_index])
    }
    if raw_head == "for" && len(parent.items) >= 3 && parent.items[1].kind == .Vector {
        binding := parent.items[1]
        return (len(binding.items) == 4 &&
                item_index == 1 &&
                binding.items[2].kind == .Keyword &&
                binding.items[2].text == ":transform" &&
                form_is_transform_source_call(e, binding.items[1])) ||
               (len(binding.items) == 5 &&
                item_index == 1 &&
                binding.items[3].kind == .Keyword &&
                binding.items[3].text == ":transform" &&
                form_is_transform_source_call(e, binding.items[2]))
    }
    return false
}

transform_direct_source_item_index :: proc(form: CST_Form, e: ^Emitter = nil) -> (int, bool) {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return -1, false
    }
    raw_head := form.items[0].text
    if raw_head == "transduce" {
        if len(form.items) == 5 && form_is_transform_source_call(e, form.items[4]) {
            return 4, true
        }
    }
    if raw_head == "into" || raw_head == "transform-into!" {
        idx := len(form.items) - 1
        if idx >= 0 && form_is_transform_source_call(e, form.items[idx]) {
            return idx, true
        }
    }
    return -1, false
}

owned_let_result_usage_error :: proc(
    form: CST_Form,
    allow_root_owned: bool,
    e: ^Emitter = nil,
) -> (Compile_Error, bool) {
    if len(form.items) < 3 {
        return {}, false
    }
    bindings, err_bindings, ok_bindings := parse_let_bindings(form.items[1])
    if !ok_bindings {
        return err_bindings, true
    }
    defer delete(bindings)

    body := form.items[2:]
    if e != nil {
        push_local_type_scope(e)
        defer pop_local_type_scope(e)
    }
    for binding, binding_idx in bindings {
        binding_cleans_up := binding.deferred_delete ||
                            binding.err_deferred_delete ||
                            binding.defer_with_cleanup
        if binding.name != "" &&
           let_scope_transfers_owned_name(
               e,
               bindings[binding_idx+1:],
               body,
               binding.name,
               allow_root_owned,
           ) {
            binding_cleans_up = true
        }
        if err_value, bad_value :=
            owned_result_usage_error(
                binding.value,
                binding_cleans_up,
                e,
            );
            bad_value {
            return err_value, true
        }
        if e != nil {
            bind_obvious_binding_types(e, binding)
        }
    }

    for item, idx in body {
        item_can_escape := allow_root_owned && idx == len(body)-1
        if err_item, bad_item :=
            owned_result_usage_error(item, item_can_escape, e);
            bad_item {
            return err_item, true
        }
    }
    return {}, false
}

owned_result_usage_error :: proc(form: CST_Form, allow_root_owned: bool, e: ^Emitter = nil) -> (Compile_Error, bool) {
    if form_is_owned_result(form, e) {
        _, compiler_managed := owned_managed_form_type(e, form)
        if !allow_root_owned && !compiler_managed {
            return Compile_Error{
                message = nested_owned_result_error_message(form),
                span = form.span,
            }, true
        }
    }

    // A let binding establishes an ownership boundary. Respect its cleanup or
    // transfer before checking the body, rather than treating every resource
    // created inside it as an unbound temporary in the parent expression.
    if form.kind == .List && len(form.items) > 0 &&
       is_symbol(form.items[0], "let") {
        return owned_let_result_usage_error(form, allow_root_owned, e)
    }

    if skip_index, ok_skip := transform_direct_source_item_index(form, e); ok_skip {
        for item, idx in form.items {
            if idx == skip_index {
                err_source, bad_source := owned_transform_source_args_usage_error(item, e)
                if bad_source {
                    return err_source, true
                }
                continue
            }
            err_item, bad_item := owned_result_usage_error(item, false, e)
            if bad_item {
                return err_item, true
            }
        }
        return {}, false
    }

    // A composite literal owns values assigned directly to its fields. This is
    // the expression form of the local-transfer rule in
    // composite_literal_transfers_owned_name.
    if allow_root_owned &&
       form.kind == .List &&
       len(form.items) >= 1 &&
       form.items[0].kind == .Symbol {
        if form_is_struct_or_union_constructor(e, form) {
            constructor_args := form.items[1:]
            named_constructor := keyword_arg_tail_is_syntax(constructor_args, 0)
            for arg, arg_index in constructor_args {
                if named_constructor && arg_index%2 == 0 {
                    continue
                }
                err_item, bad_item := owned_result_usage_error(arg, true, e)
                if bad_item {
                    return err_item, true
                }
            }
            return {}, false
        }
    }

    if allow_root_owned &&
       form.kind == .List &&
       len(form.items) == 2 &&
       form.items[0].kind == .Symbol &&
       form.items[1].kind == .Brace {
        fields := form.items[1]
        for i := 1; i < len(fields.items); i += 2 {
            err_item, bad_item := owned_result_usage_error(fields.items[i], true, e)
            if bad_item {
                return err_item, true
            }
        }
        return {}, false
    }

    if allow_root_owned &&
       form.kind == .List &&
       len(form.items) == 4 &&
       form.items[0].kind == .Symbol &&
       form.items[0].text == "if" {
        err_predicate, bad_predicate := owned_result_usage_error(form.items[1], false, e)
        if bad_predicate {
            return err_predicate, true
        }
        for branch in form.items[2:] {
            err_branch, bad_branch := owned_result_usage_error(branch, true, e)
            if bad_branch {
                return err_branch, true
            }
        }
        return {}, false
    }

    #partial switch form.kind {
    case .List, .Vector, .Brace, .Set:
        start := 0
        if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
            head := form.items[0].text
            if head == "make" {
                start = 2
            } else if allow_root_owned && form_is_owned_result(form, e) {
                start = 1
            }
        }
        if start > len(form.items) {
            start = len(form.items)
        }
        for item, item_index in form.items[start:] {
            absolute_index := start + item_index
            if owned_direct_source_allowed_in_transform_source_slot(form, absolute_index, e) {
                err_source, bad_source := owned_transform_source_args_usage_error(item, e)
                if bad_source {
                    return err_source, true
                }
                continue
            }
            transfers_arg := (form.kind == .List &&
                              ((form_transfers_owned_args(form) && absolute_index >= 2) ||
                               call_arg_transfers_owned_result(e, form, absolute_index)))
            err_item, bad_item := owned_result_usage_error(item, transfers_arg, e)
            if bad_item {
                return err_item, true
            }
        }
    }
    return {}, false
}

form_has_nested_owned_value :: proc(form: CST_Form, e: ^Emitter = nil) -> bool {
    if form_is_owned_constructor_result(form) || form_is_literal_constructor_call(form, e) ||
       form_is_transform_loop_call(form) {
        return false
    }
    #partial switch form.kind {
    case .List, .Vector, .Brace, .Set:
        start := 0
        if form.kind == .List && len(form.items) > 0 {
            if len(form.items) == 2 &&
               (form.items[1].kind == .Vector || form.items[1].kind == .Brace || form.items[1].kind == .Set) {
                if type_text, _, ok_type := parse_type_text(form.items[0]); ok_type {
                    delete(type_text)
                    start = len(form.items)
                } else {
                    start = 1
                }
            } else if form.items[0].kind == .Symbol && form.items[0].text == "make" {
                start = 2
            } else if form.items[0].kind == .Symbol {
                start = 1
                switch form.items[0].text {
                case "fn", "let", "if", "when", "cond", "case", "do", "for", "while", "type-case", "match",
                     "with-allocator", "with-temp-allocator":
                    start = len(form.items)
                }
            } else {
                start = 1
            }
        }
        if start > len(form.items) {
            start = len(form.items)
        }
        for item, item_index in form.items[start:] {
            absolute_index := start + item_index
            if owned_direct_source_allowed_in_transform_source_slot(form, absolute_index, e) {
                if _, bad_source := owned_transform_source_args_usage_error(item, e); !bad_source {
                    continue
                }
            }
            _, item_is_owned_managed := owned_managed_form_type(e, item)
            if expected_type, ok_expected := call_arg_expected_type(e, form, absolute_index); ok_expected {
                item_is_owned_managed =
                    form_produces_owned_managed_type(e, item, expected_type)
                delete(expected_type)
            }
            if (form_produces_owned_value(item, e) ||
                item_is_owned_managed ||
                form_has_nested_owned_value(item, e)) {
                return true
            }
        }
    }
    return false
}
