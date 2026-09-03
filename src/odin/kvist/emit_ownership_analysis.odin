package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

Owned_Local_State :: enum {
    Live,
    Moved,
}

Owned_Local :: struct {
    name:              string,
    span:              Span,
    state:             Owned_Local_State,
    move_confidence:   Compile_Warning_Confidence,
    cleanup_scheduled: bool,
}

Borrowed_Local :: struct {
    name:       string,
    owner_name: string,
}

owned_warning_subject :: proc(form: CST_Form) -> string {
    if head, ok := form_head_symbol_text(form); ok {
        return display_head_name(head)
    }
    #partial switch form.kind {
    case .Vector:
        return "vector literal"
    case .Brace:
        return "map literal"
    case .Set:
        return "set literal"
    case:
        return "owned value"
    }
}

discarded_owned_warning_message :: proc(form: CST_Form) -> string {
    subject := owned_warning_subject(form)
    if subject == "owned value" {
        return "owned value is discarded; bind it, delete it, or return it"
    }
    return fmt.tprintf("owned result from %s is discarded; bind it, delete it, or return it", subject)
}

nested_owned_result_error_message :: proc(form: CST_Form) -> string {
    subject := owned_warning_subject(form)
    if subject == "owned value" {
        return "owned result must be bound or returned; nested owned results would leak"
    }
    return fmt.tprintf("%s returns an owned result; bind it so it can be deleted, or return it to transfer ownership", subject)
}

owned_locals_find_last :: proc(live: []Owned_Local, name: string) -> int {
    for i := len(live) - 1; i >= 0; i -= 1 {
        if live[i].name == name {
            return i
        }
    }
    return -1
}

owned_locals_live_find_last :: proc(live: []Owned_Local, name: string) -> int {
    for i := len(live) - 1; i >= 0; i -= 1 {
        if live[i].name == name && live[i].state == .Live {
            return i
        }
    }
    return -1
}

owned_locals_mark_moved_last :: proc(
    live: ^[dynamic]Owned_Local,
    name: string,
    confidence := Compile_Warning_Confidence.Conservative,
) -> bool {
    idx := owned_locals_find_last(live[:], name)
    if idx < 0 {
        return false
    }
    live[idx].state = .Moved
    live[idx].move_confidence = confidence
    return true
}

owned_locals_merge_definite_branch_moves :: proc(live: ^[dynamic]Owned_Local, then_live, else_live: []Owned_Local) {
    limit := min(len(live[:]), min(len(then_live), len(else_live)))
    for i := 0; i < limit; i += 1 {
        if live[i].state != .Live || live[i].name == "" {
            continue
        }
        if then_live[i].name == live[i].name &&
           else_live[i].name == live[i].name &&
           then_live[i].state == .Moved &&
           else_live[i].state == .Moved {
            live[i].state = .Moved
            // Branch merging is deliberately conservative until replacement
            // values and aliases are represented in the flow state.
            live[i].move_confidence = .Conservative
        }
    }
}

owned_locals_intersect_branch_moves :: proc(target: ^[dynamic]Owned_Local, branch_live: []Owned_Local) {
    limit := min(len(target[:]), len(branch_live))
    for i := 0; i < len(target[:]); i += 1 {
        if i >= limit ||
           target[i].name != branch_live[i].name ||
           branch_live[i].state != .Moved {
            target[i].state = .Live
        }
    }
}

owned_locals_apply_definite_moves :: proc(live: ^[dynamic]Owned_Local, definite_live: []Owned_Local) {
    limit := min(len(live[:]), len(definite_live))
    for i := 0; i < limit; i += 1 {
        if live[i].state == .Live &&
           live[i].name != "" &&
           definite_live[i].name == live[i].name &&
           definite_live[i].state == .Moved {
            live[i].state = .Moved
            live[i].move_confidence = .Conservative
        }
    }
}

form_is_struct_or_union_constructor :: proc(e: ^Emitter, form: CST_Form) -> bool {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }

    head_name := map_name(form.items[0].text)
    defer delete(head_name)
    if e != nil {
        if _, ok_struct := find_struct_decl(e, head_name); ok_struct {
            return true
        }
        if _, ok_union := find_union_decl(e, head_name); ok_union {
            return true
        }
    }

    return (len(head_name) > 0 && head_name[0] >= 'A' && head_name[0] <= 'Z') ||
           dotted_head_member_starts_upper(head_name)
}

composite_value_transfers_owned_name :: proc(e: ^Emitter, form: CST_Form, name: string) -> bool {
    if form.kind == .Symbol {
        return map_name(form.text) == name
    }
    if form.kind == .Vector || form.kind == .Set {
        for item in form.items {
            if composite_value_transfers_owned_name(e, item, name) {
                return true
            }
        }
        return false
    }
    return composite_literal_transfers_owned_name(e, form, name)
}

composite_literal_transfers_owned_name :: proc(e: ^Emitter, form: CST_Form, name: string) -> bool {
    if !form_is_struct_or_union_constructor(e, form) {
        return false
    }
    args := form.items[1:]
    if keyword_arg_tail_is_syntax(args, 0) {
        for i := 1; i < len(args); i += 2 {
            if composite_value_transfers_owned_name(e, args[i], name) {
                return true
            }
        }
        return false
    }
    for arg in args {
        if composite_value_transfers_owned_name(e, arg, name) {
            return true
        }
    }
    return false
}

form_head_symbol_text :: proc(form: CST_Form) -> (string, bool) {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return "", false
    }
    return form.items[0].text, true
}

cleanup_call_head :: proc(head: string) -> bool {
    normalized := map_name(head)
    defer delete(normalized)
    return strings.contains(normalized, "destroy") ||
           strings.contains(normalized, "free") ||
           strings.contains(normalized, "close") ||
           strings.contains(normalized, "release")
}

cleanup_arg_names_value :: proc(form: CST_Form, name: string) -> bool {
    if form.kind == .Symbol {
        return map_name(form.text) == name
    }
    head, ok := form_head_symbol_text(form)
    if ok && (head == "addr" || head == "deref") && len(form.items) == 2 {
        return cleanup_arg_names_value(form.items[1], name)
    }
    return false
}

form_is_delete_of_name :: proc(form: CST_Form, name: string) -> bool {
    head, ok := form_head_symbol_text(form)
    if !ok {
        return false
    }
    if head == "delete" && len(form.items) == 2 && form.items[1].kind == .Symbol {
        return map_name(form.items[1].text) == name
    }
    if cleanup_call_head(head) {
        for item in form.items[1:] {
            if cleanup_arg_names_value(item, name) {
                return true
            }
        }
    }
    if head == "defer" {
        for item in form.items[1:] {
            if form_is_delete_of_name(item, name) {
                return true
            }
        }
    }
    return false
}

body_deletes_name :: proc(forms: []CST_Form, name: string) -> bool {
    for form in forms {
        if form_contains_delete_of_name(form, name) {
            return true
        }
    }
    return false
}

form_contains_delete_of_name :: proc(form: CST_Form, name: string) -> bool {
    if form_is_delete_of_name(form, name) {
        return true
    }
    if form.kind != .List &&
       form.kind != .Vector &&
       form.kind != .Brace &&
       form.kind != .Set {
        return false
    }
    if form.kind == .List &&
       len(form.items) > 0 &&
       form.items[0].kind == .Symbol &&
       (form.items[0].text == "fn" ||
        form.items[0].text == "quote" ||
        form.items[0].text == "quasiquote") {
        return false
    }
    for item in form.items {
        if form_contains_delete_of_name(item, name) {
            return true
        }
    }
    return false
}

borrowed_locals_find :: proc(borrowed: []Borrowed_Local, name: string) -> int {
    for i := len(borrowed) - 1; i >= 0; i -= 1 {
        if borrowed[i].name == name {
            return i
        }
    }
    return -1
}

borrowed_locals_remove_name :: proc(borrowed: ^[dynamic]Borrowed_Local, name: string) {
    for i := len(borrowed[:]) - 1; i >= 0; i -= 1 {
        if borrowed[i].name == name {
            ordered_remove(borrowed, i)
        }
    }
}

borrowed_locals_set_owner :: proc(borrowed: ^[dynamic]Borrowed_Local, name, owner_name: string) {
    borrowed_locals_remove_name(borrowed, name)
    if name != "" && owner_name != "" {
        append(borrowed, Borrowed_Local{name = name, owner_name = owner_name})
    }
}

borrowed_locals_find_owner :: proc(borrowed: []Borrowed_Local, name, owner_name: string) -> bool {
    for item in borrowed {
        if item.name == name && item.owner_name == owner_name {
            return true
        }
    }
    return false
}

borrowed_locals_replace_with_intersection :: proc(target: ^[dynamic]Borrowed_Local, lhs, rhs: []Borrowed_Local) {
    clear(target)
    for item in lhs {
        if borrowed_locals_find_owner(rhs, item.name, item.owner_name) {
            append(target, item)
        }
    }
}

borrowed_locals_assign :: proc(target: ^[dynamic]Borrowed_Local, source: []Borrowed_Local) {
    clear(target)
    append(target, ..source)
}

borrowed_locals_intersect_branch :: proc(target: ^[dynamic]Borrowed_Local, branch_borrowed: []Borrowed_Local) {
    for i := len(target[:]) - 1; i >= 0; i -= 1 {
        if !borrowed_locals_find_owner(branch_borrowed, target[i].name, target[i].owner_name) {
            ordered_remove(target, i)
        }
    }
}

form_direct_borrow_owner_name :: proc(form: CST_Form, e: ^Emitter = nil) -> (string, bool) {
    if !form_is_borrowed_view_result(form, e) || form.kind != .List || len(form.items) < 2 {
        return "", false
    }
    head, ok_head := form_head_symbol_text(form)
    if !ok_head {
        return "", false
    }
    owner_idx := 1
    if proc_decl, ok_proc := proc_decl_borrowed_view_decl(e, head); ok_proc {
        if idx, ok_idx := proc_decl_borrow_owner_arg_index(proc_decl); ok_idx {
            owner_idx = idx + 1
        }
    }
    if owner_idx < len(form.items) && form.items[owner_idx].kind == .Symbol {
        return map_name(form.items[owner_idx].text), true
    }
    return "", false
}

form_borrowed_assignment_owner_name :: proc(e: ^Emitter, form: CST_Form, borrowed: []Borrowed_Local, live: []Owned_Local) -> (string, bool) {
    if form.kind == .Symbol {
        name := map_name(form.text)
        defer delete(name)
        if idx := borrowed_locals_find(borrowed, name); idx >= 0 && owned_locals_live_find_last(live, borrowed[idx].owner_name) >= 0 {
            return borrowed[idx].owner_name, true
        }
        return "", false
    }
    if owner, ok := form_direct_borrow_owner_name(form, e); ok && owned_locals_live_find_last(live, owner) >= 0 {
        return owner, true
    }
    return "", false
}

emit_borrowed_escape_warning :: proc(e: ^Emitter, owner_name: string, span: Span) {
    if owner_name == "" {
        return
    }
    emit_coded_warning(
        e,
        fmt.tprintf("borrowed value escapes owner %s", owner_name),
        span,
        .Ownership_Borrowed_Escape,
        .Conservative,
    )
}

borrowed_escape_owner_name :: proc(e: ^Emitter, form: CST_Form, borrowed: []Borrowed_Local, live: []Owned_Local) -> (string, bool) {
    if form.kind == .Symbol {
        name := map_name(form.text)
        if idx := borrowed_locals_find(borrowed, name); idx >= 0 {
            if owned_locals_live_find_last(live, borrowed[idx].owner_name) >= 0 {
                return borrowed[idx].owner_name, true
            }
        }
        return "", false
    }
    if owner, ok := form_direct_borrow_owner_name(form, e); ok {
        if owned_locals_live_find_last(live, owner) >= 0 {
            return owner, true
        }
    }
    if form.kind == .Vector || form.kind == .Set {
        for item in form.items {
            if owner, ok := borrowed_escape_owner_name(e, item, borrowed, live); ok {
                return owner, true
            }
        }
    }
    if form.kind == .Brace {
        for i := 1; i < len(form.items); i += 2 {
            if owner, ok := borrowed_escape_owner_name(e, form.items[i], borrowed, live); ok {
                return owner, true
            }
        }
    }
    if form_is_struct_or_union_constructor(e, form) {
        args := form.items[1:]
        if keyword_arg_tail_is_syntax(args, 0) {
            for i := 1; i < len(args); i += 2 {
                if owner, ok := borrowed_escape_owner_name(e, args[i], borrowed, live); ok {
                    return owner, true
                }
            }
            return "", false
        }
        for arg in args {
            if owner, ok := borrowed_escape_owner_name(e, arg, borrowed, live); ok {
                return owner, true
            }
        }
    }
    return "", false
}

warn_if_borrowed_escape :: proc(e: ^Emitter, form: CST_Form, borrowed: []Borrowed_Local, live: []Owned_Local) {
    if owner, ok := borrowed_escape_owner_name(e, form, borrowed, live); ok {
        emit_borrowed_escape_warning(e, owner, form.span)
    }
}

form_transfers_owned_args :: proc(form: CST_Form) -> bool {
    head, ok := form_head_symbol_text(form)
    if !ok {
        return false
    }
    switch head {
    case "append":
        return true
    }
    return false
}

proc_decl_transfers_param_in_result :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, param_index: int) -> bool {
    if proc_decl == nil ||
       param_index < 0 ||
       param_index >= len(proc_decl.params) ||
       len(proc_decl.body) == 0 {
        return false
    }
    name := map_name(proc_decl.params[param_index].name)
    defer delete(name)
    return form_transfers_owned_name(e, proc_decl.body[len(proc_decl.body)-1], name, true)
}

call_arg_transfers_owned_result :: proc(e: ^Emitter, form: CST_Form, arg_index: int) -> bool {
    if e == nil ||
       form.kind != .List ||
       len(form.items) == 0 ||
       form.items[0].kind != .Symbol ||
       arg_index <= 0 {
        return false
    }
    name := map_name(form.items[0].text)
    defer delete(name)
    proc_decl, ok := find_proc_decl(e, name)
    if ok {
        if arg_index-1 < len(proc_decl.params) &&
           proc_decl.params[arg_index-1].ownership == .Owned {
            return true
        }
        return proc_decl_transfers_param_in_result(e, proc_decl, arg_index-1)
    }
    overload_decl, ok_overload := find_overload_decl(e, name)
    if !ok_overload {
        return false
    }
    param_index := arg_index-1
    applicable := 0
    for member in overload_decl.overload_members {
        member_decl, ok_member := find_proc_decl(e, member)
        if !ok_member ||
           !proc_accepts_positional_arg_count(member_decl, len(form.items)-1) ||
           param_index >= len(member_decl.params) {
            continue
        }
        applicable += 1
        if member_decl.params[param_index].ownership != .Owned &&
           !proc_decl_transfers_param_in_result(e, member_decl, param_index) {
            return false
        }
    }
    return applicable > 0
}

mark_transferred_owned_args :: proc(e: ^Emitter, form: CST_Form, live: ^[dynamic]Owned_Local) {
    if form.kind != .List || len(form.items) == 0 {
        return
    }
    if form.items[0].kind == .Symbol {
        switch form.items[0].text {
        case "if", "when", "cond", "case", "type-case", "match", "let", "do",
             "block", "for", "while", "fn", "quote", "quasiquote", "return",
             "set!":
            // These forms have branch, scope, or statement semantics handled
            // by the surrounding ownership walk. Do not flatten them into one
            // unconditional evaluation path here.
            return
        }
    }
    // A proven consuming call can itself be nested in an ordinary call
    // argument, for example `(println (consume values))`. Do not recursively
    // flatten arbitrary forms here: only descend when the nested call is
    // itself a known transfer boundary.
    for item in form.items[1:] {
        if item.kind != .List || len(item.items) == 0 {
            continue
        }
        nested_transfers := form_transfers_owned_args(item)
        if !nested_transfers && item.items[0].kind == .Symbol {
            nested_name := map_name(item.items[0].text)
            // Imported source procedures are emitted with a package prefix.
            // Their internal audit is analyzed in their own declaration
            // bodies; do not project a conservative imported summary through
            // arbitrary nested root-package calls.
            if strings.index(nested_name, "__") < 0 {
                if nested_decl, ok_nested := find_proc_decl(e, nested_name); ok_nested {
                    for param in nested_decl.params {
                        if param.ownership == .Owned {
                            nested_transfers = true
                            break
                        }
                    }
                }
            }
            delete(nested_name)
        }
        if nested_transfers {
            mark_transferred_owned_args(e, item, live)
        }
    }
    if form_transfers_owned_args(form) {
        for item in form.items[2:] {
            if item.kind == .Symbol {
                _ = owned_locals_mark_moved_last(live, map_name(item.text))
            }
        }
    }
    if form.items[0].kind != .Symbol {
        return
    }
    head_name := map_name(form.items[0].text)
    defer delete(head_name)
    proc_decl, ok_proc := find_proc_decl(e, head_name)
    if !ok_proc {
        return
    }
    param_index := 0
    for arg in form.items[1:] {
        if arg.kind == .Brace {
            for pair_index := 0; pair_index+1 < len(arg.items); pair_index += 2 {
                field_name, ok_field := brace_key_name(arg.items[pair_index])
                if !ok_field {
                    continue
                }
                param, ok_param := find_proc_param(proc_decl, field_name)
                if !ok_param || param.ownership != .Owned {
                    continue
                }
                value := arg.items[pair_index+1]
                if value.kind == .Symbol {
                    _ = owned_locals_mark_moved_last(live, map_name(value.text), .Definite)
                }
            }
            continue
        }
        if param_index < len(proc_decl.params) &&
           proc_decl.params[param_index].ownership == .Owned &&
           arg.kind == .Symbol {
            _ = owned_locals_mark_moved_last(live, map_name(arg.text), .Definite)
        }
        param_index += 1
    }
}

warn_use_after_transfer_form :: proc(e: ^Emitter, form: CST_Form, live: []Owned_Local) {
    if form.kind == .Symbol {
        name := map_name(form.text)
        idx := owned_locals_find_last(live, name)
        if idx >= 0 && live[idx].state == .Moved {
            emit_coded_warning(
                e,
                fmt.tprintf("owned local %s is used after ownership transfer", name),
                form.span,
                .Ownership_Use_After_Transfer,
                live[idx].move_confidence,
            )
        }
        return
    }
    if head, ok := form_head_symbol_text(form); ok && head == "set!" && len(form.items) == 3 {
        // The assignment target is a storage location, not a read of its
        // previous value. Only the replacement expression can use a moved
        // local.
        warn_use_after_transfer_form(e, form.items[2], live)
        return
    }
    for item in form.items {
        warn_use_after_transfer_form(e, item, live)
    }
}

binding_declares_mapped_name :: proc(binding: Binding, name: string) -> bool {
    names: [dynamic]string
    defer delete(names)
    binding_declared_names_append(binding, &names)
    return binding_names_contain(names[:], name)
}

let_scope_transfers_owned_name :: proc(
    e: ^Emitter,
    bindings: []Binding,
    body: []CST_Form,
    name: string,
    can_transfer_final: bool,
) -> bool {
    for binding in bindings {
        // A binding value is evaluated before its target enters scope, so an
        // explicit delete or return here still refers to the outer binding.
        // A bare final symbol only moves into the new local and is not, by
        // itself, proof that the value is eventually cleaned up.
        if form_transfers_owned_name(e, binding.value, name, false) {
            return true
        }
        if binding_declares_mapped_name(binding, name) {
            return false
        }
    }
    return body_deletes_or_returns_name(e, body, name, can_transfer_final)
}

type_case_transfers_owned_name :: proc(e: ^Emitter, form: CST_Form, name: string, can_transfer_final: bool) -> bool {
    if len(form.items) < 5 || len(form.items)%2 == 0 {
        return false
    }
    for i := 2; i < len(form.items)-1; i += 2 {
        _, binding, ignored, _, ok_pattern :=
            case_type_payload_pattern(form.items[i])
        if !ok_pattern || (!ignored && binding == name) {
            return false
        }
        if !form_transfers_owned_name(e, form.items[i+1], name, can_transfer_final) {
            return false
        }
    }
    return form_transfers_owned_name(
        e,
        form.items[len(form.items)-1],
        name,
        can_transfer_final,
    )
}

form_transfers_owned_name :: proc(e: ^Emitter, form: CST_Form, name: string, can_transfer_final: bool) -> bool {
    if form_is_delete_of_name(form, name) {
        return true
    }

    head, ok := form_head_symbol_text(form)
    if ok && head == "return" {
        for item in form.items[1:] {
            if item.kind == .Symbol && map_name(item.text) == name {
                return true
            }
            if composite_literal_transfers_owned_name(e, item, name) {
                return true
            }
        }
    }

    if ok && form_transfers_owned_args(form) {
        for item in form.items[2:] {
            if item.kind == .Symbol && map_name(item.text) == name {
                return true
            }
        }
    }

    if ok && head == "let" && len(form.items) >= 3 {
        bindings, _, ok_bindings := parse_let_bindings(form.items[1])
        if !ok_bindings {
            return false
        }
        defer delete(bindings)
        return let_scope_transfers_owned_name(
            e,
            bindings[:],
            form.items[2:],
            name,
            can_transfer_final,
        )
    }

    if ok && head == "do" && len(form.items) >= 2 {
        return body_deletes_or_returns_name(e, form.items[1:], name, can_transfer_final)
    }

    if ok && head == "if" {
        if len(form.items) < 4 {
            return false
        }
        return form_transfers_owned_name(e, form.items[2], name, can_transfer_final) &&
            form_transfers_owned_name(e, form.items[3], name, can_transfer_final)
    }

    if ok && head == "type-case" {
        return type_case_transfers_owned_name(e, form, name, can_transfer_final)
    }

    if ok && head == "match" {
        if len(form.items) < 4 {
            return false
        }
        for i := 2; i+1 < len(form.items); i += 2 {
            names: [dynamic]string
            _, ok_pattern := validate_match_pattern(form.items[i], &names)
            shadows_name := binding_names_contain(names[:], name)
            delete(names)
            if !ok_pattern || shadows_name {
                return false
            }
            if !form_transfers_owned_name(e, form.items[i+1], name, can_transfer_final) {
                return false
            }
        }
        return true
    }

    if can_transfer_final && form.kind == .Symbol && map_name(form.text) == name {
        return true
    }

    if can_transfer_final && composite_literal_transfers_owned_name(e, form, name) {
        return true
    }

    return false
}

body_deletes_or_returns_name :: proc(e: ^Emitter, forms: []CST_Form, name: string, can_transfer_final: bool) -> bool {
    for form, idx in forms {
        if form_transfers_owned_name(e, form, name, can_transfer_final && idx == len(forms)-1) {
            return true
        }
    }
    return false
}

form_all_explicit_managed_returns_owned :: proc(
    e: ^Emitter,
    form: CST_Form,
    return_ty: string,
    depth: int = 0,
) -> bool {
    if depth > 16 || form.kind != .List || len(form.items) == 0 {
        return true
    }
    if form.items[0].kind == .Symbol {
        switch form.items[0].text {
        case "return":
            if len(form.items) != 2 {
                return false
            }
            return form_produces_owned_managed_type(e, form.items[1], return_ty)
        case "fn", "quote", "quasiquote":
            return true
        }
    }
    for item in form.items[1:] {
        if !form_all_explicit_managed_returns_owned(e, item, return_ty, depth+1) {
            return false
        }
    }
    return true
}

proc_decl_infers_owned_managed_result :: proc(e: ^Emitter, proc_decl: ^Proc_Decl) -> bool {
    if proc_decl == nil || len(proc_decl.body) == 0 {
        return false
    }
    return_ty := ""
    ok_return_ty := false
    if proc_decl.returns.kind == .Single {
        return_ty = proc_decl.returns.single_ty
        ok_return_ty = true
    } else if proc_decl.returns.kind == .Named && len(proc_decl.returns.named) == 1 {
        return_ty = proc_decl.returns.named[0].ty
        ok_return_ty = true
    }
    if !ok_return_ty || !type_text_has_managed_lifecycle(e, return_ty) {
        return false
    }
    if !form_produces_owned_managed_type(
        e,
        proc_decl.body[len(proc_decl.body)-1],
        return_ty,
    ) {
        return false
    }
    for form in proc_decl.body {
        if !form_all_explicit_managed_returns_owned(e, form, return_ty) {
            return false
        }
    }
    return true
}

infer_proc_lifetime_facts :: proc(e: ^Emitter) {
    // Lifetime contracts are compiler facts derived from ordinary procedure
    // bodies. Iterate because one procedure may forward an owned or borrowed
    // result produced by another procedure in the same source package.
    for _ in 0..<8 {
        changed := false
        for &decl in e.decls {
            if decl.kind != .Proc {
                continue
            }
            proc_decl := &decl.proc_decl
            borrows_result := proc_decl_infers_borrowed_tail_call(e, proc_decl, 0)
            owns_result := !borrows_result &&
                           (proc_decl_infers_owned_result(e, proc_decl) ||
                            proc_decl_infers_owned_managed_result(e, proc_decl) ||
                            (len(proc_decl.body) > 0 &&
                             form_produces_owned_value(
                                 proc_decl.body[len(proc_decl.body)-1],
                                 e,
                             )) ||
                            (len(proc_decl.body) > 0 &&
                             form_infers_known_foreign_lifetime(
                                 proc_decl.body[len(proc_decl.body)-1],
                                 .Owned,
                                 0,
                                 e,
                             )))
            if owns_result && !proc_decl.owns_result {
                proc_decl.owns_result = true
                changed = true
            }
            if borrows_result && !proc_decl.borrows_result {
                proc_decl.borrows_result = true
                changed = true
            }
            for &param in proc_decl.params {
                if param.ownership == .Owned {
                    continue
                }
                explicit_consumption :=
                    body_deletes_or_returns_name(e, proc_decl.body[:], param.name, false)
                transferred_result :=
                    proc_decl.owns_result &&
                    body_deletes_or_returns_name(e, proc_decl.body[:], param.name, true)
                if explicit_consumption || transferred_result {
                    param.ownership = .Owned
                    changed = true
                }
            }
        }
        if !changed {
            break
        }
    }
}

infer_decoded_struct_lifetime :: proc(e: ^Emitter, type_name: string, depth: int = 0) {
    if depth > 16 {
        return
    }
    if elem_ty, ok_elem := dynamic_array_element_type(strings.trim_space(type_name)); ok_elem {
        infer_decoded_struct_lifetime(e, elem_ty, depth+1)
        return
    }
    struct_decl, ok_struct := find_struct_decl(e, strings.trim_space(type_name))
    if !ok_struct {
        return
    }
    for &field in struct_decl.fields {
        if field.ty == "string" {
            field.owns_string = true
            continue
        }
        if type_text_is_dynamic_array(field.ty) {
            field.owns_dynamic_array = true
            if elem_ty, ok_elem := dynamic_array_element_type(field.ty); ok_elem {
                infer_decoded_struct_lifetime(e, elem_ty, depth+1)
            }
            continue
        }
        infer_decoded_struct_lifetime(e, field.ty, depth+1)
    }
}

infer_decoded_struct_lifetimes_form :: proc(e: ^Emitter, form: CST_Form) {
    if form.kind == .List &&
       len(form.items) >= 2 &&
       form.items[0].kind == .Symbol {
        head_name := map_name(form.items[0].text)
        if head_name == "decode_data" ||
           head_name == "validate_data" ||
           head_name == "data_decode" ||
           head_name == "data_validate" ||
           head_name == "data.decode" ||
           head_name == "data.validate" {
            if target_ty, _, ok_target := parse_type_text(form.items[1]); ok_target {
                infer_decoded_struct_lifetime(e, target_ty)
            }
        }
        delete(head_name)
    }
    for item in form.items {
        infer_decoded_struct_lifetimes_form(e, item)
    }
}

infer_decoded_struct_lifetimes :: proc(e: ^Emitter, extra_form: ^CST_Form = nil) {
    for decl in e.decls {
        #partial switch decl.kind {
        case .Proc:
            for form in decl.proc_decl.body {
                infer_decoded_struct_lifetimes_form(e, form)
            }
        case .Source:
            for form in decl.source_decl.body {
                infer_decoded_struct_lifetimes_form(e, form)
            }
        case .Const:
            infer_decoded_struct_lifetimes_form(e, decl.const_decl.value)
        case .Var:
            if decl.var_decl.has_value {
                infer_decoded_struct_lifetimes_form(e, decl.var_decl.value)
            }
        case:
        }
    }
    if extra_form != nil {
        infer_decoded_struct_lifetimes_form(e, extra_form^)
    }
}

analyze_owned_branch_body :: proc(e: ^Emitter, forms: []CST_Form, can_transfer_final: bool, live: []Owned_Local, borrowed: []Borrowed_Local) {
    branch_live: [dynamic]Owned_Local
    branch_borrowed: [dynamic]Borrowed_Local
    append(&branch_live, ..live)
    append(&branch_borrowed, ..borrowed)
    analyze_owned_scope_body(e, forms, can_transfer_final, &branch_live, &branch_borrowed)
    delete(branch_live)
    delete(branch_borrowed)
}

analyze_owned_scope_body :: proc(e: ^Emitter, forms: []CST_Form, can_transfer_final: bool, live: ^[dynamic]Owned_Local, borrowed: ^[dynamic]Borrowed_Local) {
    for form, idx in forms {
        final_in_scope := idx == len(forms)-1
        warn_use_after_transfer_form(e, form, live[:])

        if form.kind == .Symbol && final_in_scope && can_transfer_final {
            warn_if_borrowed_escape(e, form, borrowed[:], live[:])
            _ = owned_locals_mark_moved_last(live, map_name(form.text))
            continue
        }

        if final_in_scope && can_transfer_final {
            warn_if_borrowed_escape(e, form, borrowed[:], live[:])
            for i := len(live[:]) - 1; i >= 0; i -= 1 {
                if live[i].state == .Live && composite_literal_transfers_owned_name(e, form, live[i].name) {
                    _ = owned_locals_mark_moved_last(live, live[i].name)
                }
            }
        }

        head, ok := form_head_symbol_text(form)
        if !ok {
            if form_requires_explicit_owned_cleanup(form, e) && !(final_in_scope && can_transfer_final) {
                emit_coded_warning(e, discarded_owned_warning_message(form), form.span, .Ownership_Discarded_Result)
            }
            continue
        }

        switch head {
        case "return":
            for item in form.items[1:] {
                warn_if_borrowed_escape(e, item, borrowed[:], live[:])
                if item.kind == .Symbol {
                    _ = owned_locals_mark_moved_last(live, map_name(item.text), .Definite)
                    continue
                }
                for i := len(live[:]) - 1; i >= 0; i -= 1 {
                    if live[i].state == .Live && composite_literal_transfers_owned_name(e, item, live[i].name) {
                        _ = owned_locals_mark_moved_last(live, live[i].name)
                    }
                }
                mark_transferred_owned_args(e, item, live)
            }
        case "discard":
            for item in form.items[1:] {
                if form_requires_explicit_owned_cleanup(item, e) {
                    emit_coded_warning(e, discarded_owned_warning_message(item), item.span, .Ownership_Discarded_Result)
                }
            }
        case "delete":
            for item in form.items[1:] {
                if form_is_borrowed_view_result(item, e) {
                    emit_coded_warning(e, borrowed_delete_warning_message(item), item.span, .Ownership_Delete_Borrowed)
                }
                if item.kind == .Symbol {
                    _ = owned_locals_mark_moved_last(live, map_name(item.text), .Definite)
                }
            }
        case "defer", "errdefer":
            // The deferred call consumes its arguments when the surrounding
            // scope exits, not where the defer is declared. Keep owned locals
            // live for subsequent statements; the scope cleanup check below
            // recognizes the scheduled release.
        case "set!":
            if len(form.items) == 3 && form.items[1].kind == .Symbol {
                name := map_name(form.items[1].text)
                if name == "" {
                    continue
                }
                existing_idx := owned_locals_find_last(live[:], name)
                if existing_idx >= 0 && live[existing_idx].state == .Live {
                    emit_coded_warning(
                        e,
                        fmt.tprintf("owned local %s is overwritten before cleanup; delete it or return it before set!", name),
                        form.items[1].span,
                        .Ownership_Overwrite,
                    )
                }
                if existing_idx >= 0 {
                    // `set!` replaces the storage; it is not a later read of
                    // the value deleted immediately beforehand. The target's
                    // native type still determines that the replacement is an
                    // owned value even when the RHS is a local symbol.
                    live[existing_idx].state = .Live
                    live[existing_idx].move_confidence = .Conservative
                    if form.items[2].kind == .Symbol {
                        rhs_name := map_name(form.items[2].text)
                        if rhs_name != name {
                            _ = owned_locals_mark_moved_last(live, rhs_name)
                        }
                    }
                } else if form_produces_owned_value(form.items[2], e) {
                    append(live, Owned_Local{name = name, span = form.items[1].span})
                }
                if owner, ok_owner := form_borrowed_assignment_owner_name(e, form.items[2], borrowed[:], live[:]); ok_owner {
                    borrowed_locals_set_owner(borrowed, name, owner)
                } else {
                    borrowed_locals_remove_name(borrowed, name)
                }
            }
        case "let":
            if len(form.items) < 3 {
                continue
            }
            bindings, _, ok_bind := parse_let_bindings(form.items[1])
            if !ok_bind {
                continue
            }
            start := len(live)
            borrowed_start := len(borrowed)
            for binding in bindings {
                warn_use_after_transfer_form(e, binding.value, live[:])
                for i := len(live[:]) - 1; i >= 0; i -= 1 {
                    if live[i].state == .Live && !live[i].cleanup_scheduled &&
                       composite_literal_transfers_owned_name(e, binding.value, live[i].name) {
                        _ = owned_locals_mark_moved_last(live, live[i].name)
                    }
                }
                mark_transferred_owned_args(e, binding.value, live)
                if (binding.deferred_delete || binding.defer_with_cleanup) && form_is_borrowed_view_result(binding.value, e) {
                    emit_coded_warning(e, borrowed_delete_warning_message(binding.value), binding.value.span, .Ownership_Delete_Borrowed)
                }
                if !binding.is_destructure && binding.name != "" && form_is_borrowed_view_result(binding.value, e) {
                    if owner, ok_owner := form_direct_borrow_owner_name(binding.value, e); ok_owner && owned_locals_live_find_last(live[:], owner) >= 0 {
                        append(borrowed, Borrowed_Local{name = binding.name, owner_name = owner})
                    }
                }
                delete_name, has_delete_name := binding_delete_target_name(binding)
                if binding.is_destructure || (!has_delete_name && binding.name == "") {
                    continue
                }
                if binding_value_produces_owned_value(binding, e) || binding.deferred_delete || binding.err_deferred_delete || binding.defer_with_cleanup {
                    owned_name := binding.name
                    if owned_name == "" {
                        owned_name = delete_name
                    }
                    if owned_name == "" {
                        continue
                    }
                    append(live, Owned_Local{
                        name = owned_name,
                        span = form.items[0].span,
                        cleanup_scheduled = binding.deferred_delete || binding.err_deferred_delete || binding.defer_with_cleanup,
                    })
                }
            }
            analyze_owned_scope_body(e, form.items[2:], final_in_scope && can_transfer_final, live, borrowed)
            for i := start; i < len(live); i += 1 {
                if live[i].name == "" || live[i].state == .Moved {
                    continue
                }
                skip_warning := false
                for binding in bindings {
                    delete_name, ok_delete_name := binding_delete_target_name(binding)
                    if ok_delete_name && delete_name == live[i].name && (binding.deferred_delete || binding.err_deferred_delete || binding.defer_with_cleanup) {
                        skip_warning = true
                        break
                    }
                }
                if !skip_warning && !body_deletes_or_returns_name(e, form.items[2:], live[i].name, final_in_scope && can_transfer_final) {
                    emit_coded_warning(
                        e,
                        fmt.tprintf("owned local %s is never deleted or returned; add (defer (delete %s)) or return it", live[i].name, live[i].name),
                        live[i].span,
                        .Ownership_Unreleased_Local,
                        .Conservative,
                    )
                }
            }
            resize(live, start)
            resize(borrowed, borrowed_start)
        case "do":
            analyze_owned_scope_body(e, form.items[1:], final_in_scope && can_transfer_final, live, borrowed)
        case "if":
            if len(form.items) >= 3 {
                then_live: [dynamic]Owned_Local
                then_borrowed: [dynamic]Borrowed_Local
                append(&then_live, ..live[:])
                append(&then_borrowed, ..borrowed[:])
                analyze_owned_scope_body(e, []CST_Form{form.items[2]}, final_in_scope && can_transfer_final, &then_live, &then_borrowed)
                if len(form.items) >= 4 {
                    else_live: [dynamic]Owned_Local
                    else_borrowed: [dynamic]Borrowed_Local
                    append(&else_live, ..live[:])
                    append(&else_borrowed, ..borrowed[:])
                    analyze_owned_scope_body(e, []CST_Form{form.items[3]}, final_in_scope && can_transfer_final, &else_live, &else_borrowed)
                    owned_locals_merge_definite_branch_moves(live, then_live[:], else_live[:])
                    borrowed_locals_replace_with_intersection(borrowed, then_borrowed[:], else_borrowed[:])
                    delete(else_live)
                    delete(else_borrowed)
                }
                delete(then_live)
                delete(then_borrowed)
            }
        case "type-case":
            if len(form.items) >= 4 {
                definite_live: [dynamic]Owned_Local
                definite_borrowed: [dynamic]Borrowed_Local
                branch_seen := false
                i := 3
                for i < len(form.items)-1 {
                    branch_live: [dynamic]Owned_Local
                    branch_borrowed: [dynamic]Borrowed_Local
                    append(&branch_live, ..live[:])
                    append(&branch_borrowed, ..borrowed[:])
                    analyze_owned_scope_body(e, []CST_Form{form.items[i]}, final_in_scope && can_transfer_final, &branch_live, &branch_borrowed)
                    if !branch_seen {
                        append(&definite_live, ..branch_live[:])
                        append(&definite_borrowed, ..branch_borrowed[:])
                        branch_seen = true
                    } else {
                        owned_locals_intersect_branch_moves(&definite_live, branch_live[:])
                        borrowed_locals_intersect_branch(&definite_borrowed, branch_borrowed[:])
                    }
                    delete(branch_live)
                    delete(branch_borrowed)
                    i += 2
                }
                default_live: [dynamic]Owned_Local
                default_borrowed: [dynamic]Borrowed_Local
                append(&default_live, ..live[:])
                append(&default_borrowed, ..borrowed[:])
                analyze_owned_scope_body(e, []CST_Form{form.items[len(form.items)-1]}, final_in_scope && can_transfer_final, &default_live, &default_borrowed)
                if branch_seen {
                    owned_locals_intersect_branch_moves(&definite_live, default_live[:])
                    borrowed_locals_intersect_branch(&definite_borrowed, default_borrowed[:])
                    owned_locals_apply_definite_moves(live, definite_live[:])
                    borrowed_locals_assign(borrowed, definite_borrowed[:])
                }
                delete(default_live)
                delete(default_borrowed)
                delete(definite_live)
                delete(definite_borrowed)
            }
        case "match":
            if len(form.items) >= 4 {
                definite_live: [dynamic]Owned_Local
                definite_borrowed: [dynamic]Borrowed_Local
                branch_seen := false
                for i := 3; i < len(form.items); i += 2 {
                    branch_live: [dynamic]Owned_Local
                    branch_borrowed: [dynamic]Borrowed_Local
                    append(&branch_live, ..live[:])
                    append(&branch_borrowed, ..borrowed[:])
                    analyze_owned_scope_body(e, []CST_Form{form.items[i]}, final_in_scope && can_transfer_final, &branch_live, &branch_borrowed)
                    if !branch_seen {
                        append(&definite_live, ..branch_live[:])
                        append(&definite_borrowed, ..branch_borrowed[:])
                        branch_seen = true
                    } else {
                        owned_locals_intersect_branch_moves(&definite_live, branch_live[:])
                        borrowed_locals_intersect_branch(&definite_borrowed, branch_borrowed[:])
                    }
                    delete(branch_live)
                    delete(branch_borrowed)
                }
                if branch_seen {
                    owned_locals_apply_definite_moves(live, definite_live[:])
                    borrowed_locals_assign(borrowed, definite_borrowed[:])
                }
                delete(definite_live)
                delete(definite_borrowed)
            }
        case:
            mark_transferred_owned_args(e, form, live)
            if form_requires_explicit_owned_cleanup(form, e) && !(final_in_scope && can_transfer_final) {
                emit_coded_warning(e, discarded_owned_warning_message(form), form.span, .Ownership_Discarded_Result)
            }
        }
    }
}
