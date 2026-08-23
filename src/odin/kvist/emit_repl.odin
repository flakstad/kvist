// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

Debug_Restart_Context :: struct {
    label:         string,
    restart_flags: u32,
}
repl_type_mentions_name :: proc(text, name: string) -> bool {
    offset := 0
    for offset < len(text) {
        idx := strings.index(text[offset:], name)
        if idx < 0 {
            return false
        }
        start := offset + idx
        end := start + len(name)
        left_ok := start == 0 || !type_identifier_continue(text[start-1])
        right_ok := end == len(text) || !type_identifier_continue(text[end])
        if left_ok && right_ok {
            return true
        }
        offset = end
    }
    return false
}

repl_append_type_layout :: proc(
    builder: ^strings.Builder,
    e: ^Emitter,
    ty: string,
    seen: ^map[string]bool,
) {
    if e == nil {
        return
    }
    for decl in e.decls {
        name := ""
        #partial switch decl.kind {
        case .Struct: name = decl.struct_decl.name
        case .Enum: name = decl.enum_decl.name
        case .Union: name = decl.union_decl.name
        case .Const:
            if decl.const_decl.is_type_alias {
                name = decl.const_decl.name
            }
        }
        if name == "" || !repl_type_mentions_name(ty, name) || seen^[name] {
            continue
        }
        seen^[name] = true
        fmt.sbprintf(builder, "|layout:%s=", name)
        #partial switch decl.kind {
        case .Struct:
            strings.write_string(builder, "struct{")
            for field in decl.struct_decl.fields {
                fmt.sbprintf(builder, "%s:%s;", field.name, field.ty)
            }
            strings.write_byte(builder, '}')
            for field in decl.struct_decl.fields {
                repl_append_type_layout(builder, e, field.ty, seen)
            }
        case .Enum:
            strings.write_string(builder, "enum{")
            for variant in decl.enum_decl.variants {
                fmt.sbprintf(builder, "%s;", variant.name)
            }
            strings.write_byte(builder, '}')
        case .Union:
            strings.write_string(builder, "union{")
            for variant in decl.union_decl.variants {
                fmt.sbprintf(builder, "%s;", variant.ty)
            }
            strings.write_byte(builder, '}')
            for variant in decl.union_decl.variants {
                repl_append_type_layout(builder, e, variant.ty, seen)
            }
        case .Const:
            fmt.sbprintf(builder, "alias:%s", decl.const_decl.type_alias)
            repl_append_type_layout(builder, e, decl.const_decl.type_alias, seen)
        }
    }
}

repl_proc_signature :: proc(proc_decl: ^Proc_Decl, e: ^Emitter = nil) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    if proc_decl.calling_convention != "" {
        fmt.sbprintf(&builder, "abi=%s;", proc_decl.calling_convention)
    }
    strings.write_string(&builder, "proc(")
    for param, idx in proc_decl.params {
        if idx > 0 {
            strings.write_byte(&builder, ',')
        }
        strings.write_string(&builder, param.ty)
        if param.ownership == .Owned {
            strings.write_string(&builder, ":owned")
        } else if param.ownership == .Borrowed {
            strings.write_string(&builder, ":borrowed")
        }
        if param.owner_flag != "" {
            fmt.sbprintf(&builder, ":owner=%s", param.owner_flag)
        }
    }
    strings.write_byte(&builder, ')')
    #partial switch proc_decl.returns.kind {
    case .None:
        strings.write_string(&builder, "->()")
    case .Single:
        fmt.sbprintf(&builder, "->%s", proc_decl.returns.single_ty)
        if proc_decl.returns.single_ownership == .Owned || proc_decl.owns_result {
            strings.write_string(&builder, ":owned")
        } else if proc_decl.returns.single_ownership == .Borrowed || proc_decl.borrows_result {
            strings.write_string(&builder, ":borrowed")
        }
    case .Named:
        strings.write_string(&builder, "->(")
        for ret, idx in proc_decl.returns.named {
            if idx > 0 {
                strings.write_byte(&builder, ',')
            }
            strings.write_string(&builder, ret.ty)
            if ret.ownership == .Owned {
                strings.write_string(&builder, ":owned")
            } else if ret.ownership == .Borrowed {
                strings.write_string(&builder, ":borrowed")
            }
        }
        strings.write_byte(&builder, ')')
    }
    seen := make(map[string]bool)
    defer delete(seen)
    for param in proc_decl.params {
        repl_append_type_layout(&builder, e, param.ty, &seen)
    }
    #partial switch proc_decl.returns.kind {
    case .Single:
        repl_append_type_layout(&builder, e, proc_decl.returns.single_ty, &seen)
    case .Named:
        for ret in proc_decl.returns.named {
            repl_append_type_layout(&builder, e, ret.ty, &seen)
        }
    case:
    }
    return strings.clone(strings.to_string(builder))
}

repl_proc_is_concrete :: proc(proc_decl: ^Proc_Decl) -> bool {
    for param in proc_decl.params {
        // Kvist defaults are expanded by each caller.  The registered native
        // slot still has the complete concrete parameter ABI, so defaults do
        // not make a persistent procedure unsafe to version or replace.
        if strings.contains(param.ty, "$") {
            return false
        }
    }
    if proc_decl.returns.kind == .Single &&
       strings.contains(proc_decl.returns.single_ty, "$") {
        return false
    }
    if proc_decl.returns.kind == .Named {
        for ret in proc_decl.returns.named {
            if strings.contains(ret.ty, "$") {
                return false
            }
        }
    }
    return true
}

repl_emit_proc_params :: proc(builder: ^strings.Builder, proc_decl: ^Proc_Decl, include_names: bool) {
    for param, idx in proc_decl.params {
        if idx > 0 {
            strings.write_string(builder, ", ")
        }
        if include_names {
            fmt.sbprintf(builder, "%s: %s", param.name, param.ty)
        } else {
            strings.write_string(builder, param.ty)
        }
    }
}

repl_emit_proc_returns :: proc(builder: ^strings.Builder, returns: Return_Spec, include_names: bool) {
    #partial switch returns.kind {
    case .None:
        return
    case .Single:
        fmt.sbprintf(builder, " -> %s", returns.single_ty)
    case .Named:
        strings.write_string(builder, " -> (")
        for ret, idx in returns.named {
            if idx > 0 {
                strings.write_string(builder, ", ")
            }
            if include_names && ret.name != "" {
                fmt.sbprintf(builder, "%s: %s", ret.name, ret.ty)
            } else {
                strings.write_string(builder, ret.ty)
            }
        }
        strings.write_byte(builder, ')')
    }
}

repl_proc_adapter_text :: proc(
    e: ^Emitter,
    proc_decl: ^Proc_Decl,
    adapter_name := "",
    lookup_name := "",
) -> string {
    for param in proc_decl.params {
        if type_text_has_data_lifecycle(e, param.ty) {
            mark_data_type(e)
        }
    }
    #partial switch proc_decl.returns.kind {
    case .None:
    case .Single:
        if type_text_has_data_lifecycle(
            e,
            proc_decl.returns.single_ty,
        ) {
            mark_data_type(e)
        }
    case .Named:
        for result in proc_decl.returns.named {
            if type_text_has_data_lifecycle(e, result.ty) {
                mark_data_type(e)
            }
        }
    }
    signature := repl_proc_signature(proc_decl, e)
    defer delete(signature)
    effective_adapter_name := adapter_name
    if effective_adapter_name == "" {
        effective_adapter_name = proc_decl.name
    }
    effective_lookup_name := lookup_name
    if effective_lookup_name == "" {
        effective_lookup_name = proc_decl.name
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    fmt.sbprintf(&builder, "%s :: proc(", effective_adapter_name)
    repl_emit_proc_params(&builder, proc_decl, true)
    strings.write_byte(&builder, ')')
    repl_emit_proc_returns(&builder, proc_decl.returns, true)
    strings.write_string(&builder, " {\n    target := transmute(proc")
    if proc_decl.calling_convention != "" {
        fmt.sbprintf(&builder, " %q (", proc_decl.calling_convention)
    } else {
        strings.write_byte(&builder, '(')
    }
    repl_emit_proc_params(&builder, proc_decl, false)
    strings.write_byte(&builder, ')')
    repl_emit_proc_returns(&builder, proc_decl.returns, false)
    fmt.sbprintf(
        &builder,
        ") kvist_repl_host.lookup_proc(kvist_repl_host.ctx, %q, %q)\n",
        effective_lookup_name,
        signature,
    )
    fmt.sbprintf(&builder, "    assert(target != nil, %q)\n", fmt.tprintf("stale REPL procedure: %s", effective_lookup_name))
    strings.write_string(&builder, "    ")
    if proc_decl.returns.kind != .None {
        strings.write_string(&builder, "return ")
    }
    strings.write_string(&builder, "target(")
    for param, idx in proc_decl.params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        strings.write_string(&builder, param.name)
    }
    strings.write_string(&builder, ")\n}")
    return strings.clone(strings.to_string(builder))
}

repl_dispatch_proc_name :: proc(name: string) -> string {
    return fmt.tprintf("kvist_repl_dispatch_%s", name)
}

repl_replace_proc_symbol_in_form :: proc(
    form: CST_Form,
    from,
    to: string,
    shadowed := false,
) -> CST_Form {
    if form.kind == .Symbol {
        if !shadowed && map_name(form.text) == from {
            rewritten := form
            rewritten.text = to
            return rewritten
        }
        return form
    }
    if len(form.items) == 0 {
        return form
    }
    if form.kind == .List &&
       (is_symbol(form.items[0], "quote") ||
        is_symbol(form.items[0], "quasiquote")) {
        return form
    }

    rewritten := form
    rewritten.items = nil
    if form.kind == .List &&
       is_symbol(form.items[0], "fn") &&
       len(form.items) > 1 &&
       form.items[1].kind == .Vector {
        append(&rewritten.items, form.items[0])
        append(&rewritten.items, form.items[1])
        body_shadowed := shadowed
        params, _, ok_params := parse_param_vector(form.items[1])
        if ok_params {
            for param in params {
                if param.name == from {
                    body_shadowed = true
                    break
                }
            }
        }
        for item in form.items[2:] {
            append(
                &rewritten.items,
                repl_replace_proc_symbol_in_form(
                    item,
                    from,
                    to,
                    body_shadowed,
                ),
            )
        }
        return rewritten
    }
    if form.kind == .List &&
       is_symbol(form.items[0], "let") &&
       len(form.items) > 1 &&
       form.items[1].kind == .Vector {
        append(&rewritten.items, form.items[0])
        bindings := form.items[1]
        rewritten_bindings := bindings
        rewritten_bindings.items = nil
        binding_shadowed := shadowed
        for i := 0; i < len(bindings.items); i += 2 {
            name_form := bindings.items[i]
            append(&rewritten_bindings.items, name_form)
            if i+1 >= len(bindings.items) {
                break
            }
            append(
                &rewritten_bindings.items,
                repl_replace_proc_symbol_in_form(
                    bindings.items[i+1],
                    from,
                    to,
                    binding_shadowed,
                ),
            )
            if name_form.kind == .Symbol &&
               map_name(name_form.text) == from {
                binding_shadowed = true
            }
        }
        append(&rewritten.items, rewritten_bindings)
        for item in form.items[2:] {
            append(
                &rewritten.items,
                repl_replace_proc_symbol_in_form(
                    item,
                    from,
                    to,
                    binding_shadowed,
                ),
            )
        }
        return rewritten
    }
    for item in form.items {
        append(
            &rewritten.items,
            repl_replace_proc_symbol_in_form(
                item,
                from,
                to,
                shadowed,
            ),
        )
    }
    return rewritten
}

repl_value_type_supported :: proc(ty: string) -> bool {
    switch ty {
    case "bool", "string", "int", "i8", "i16", "i32", "i64", "i128",
         "uint", "u8", "u16", "u32", "u64", "u128",
         "uintptr", "f16", "f32", "f64":
        return true
    }
    return false
}

repl_value_signature :: proc(ty: string, e: ^Emitter = nil) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    fmt.sbprintf(&builder, "value:%s", ty)
    seen := make(map[string]bool)
    defer delete(seen)
    repl_append_type_layout(&builder, e, ty, &seen)
    return strings.clone(strings.to_string(builder))
}

repl_value_adapter_text :: proc(e: ^Emitter, decl: ^Const_Decl) -> string {
    signature := repl_value_signature(decl.ty, e)
    defer delete(signature)
    returned_value := "target()"
    returned_value_owned := false
    if type_text_has_managed_lifecycle(e, decl.ty) ||
       type_text_is_dynamic_array(decl.ty) ||
       type_text_is_map(decl.ty) {
        returned_value = managed_clone_value_text(e, decl.ty, returned_value)
        returned_value_owned = true
    }
    defer if returned_value_owned {
        delete(returned_value)
    }
    return fmt.tprintf(
        `%s :: proc() -> %s %c
    target := transmute(proc() -> %s) kvist_repl_host.lookup_proc(kvist_repl_host.ctx, %q, %q)
    assert(target != nil, %q)
    return %s
%c`,
        decl.name,
        decl.ty,
        '{',
        decl.ty,
        decl.name,
        signature,
        fmt.tprintf("stale REPL value: %s", decl.name),
        returned_value,
        '}',
    )
}

repl_current_value_text :: proc(e: ^Emitter, decl: ^Const_Decl) -> string {
    adapter := repl_value_adapter_text(e, decl)
    defer delete(adapter)
    return fmt.tprintf(
        "%s__repl_storage: %s\n%s__repl_impl :: proc() -> %s %c return %s__repl_storage %c\n%s",
        decl.name, decl.ty, decl.name, decl.ty, '{', decl.name, '}', adapter,
    )
}

repl_snapshot_value_text :: proc(e: ^Emitter, ty, value: string) -> string {
    trimmed := strings.trim_space(ty)
    if type_text_is_string(trimmed) {
        mark_core_strings(e)
        return emit_call_text("strings.clone", []string{value})
    }
    if type_text_is_slice(trimmed) {
        elem_ty := strings.trim_space(trimmed[2:])
        if type_text_needs_repl_snapshot(e, elem_ty) {
            cloned_item :=
                repl_snapshot_value_text(e, elem_ty, "kvist_item")
            return fmt.tprintf(
                "(proc(kvist_values: %s) -> %s {{ kvist_out := make([dynamic]%s, 0, len(kvist_values)); for kvist_item in kvist_values {{ append(&kvist_out, %s) }}; return kvist_out[:] }})(%s)",
                trimmed,
                trimmed,
                elem_ty,
                cloned_item,
                value,
            )
        }
        return fmt.tprintf(
            "(proc(kvist_values: %s) -> %s {{ kvist_out := make([dynamic]%s, len(kvist_values)); copy(kvist_out[:], kvist_values); return kvist_out[:] }})(%s)",
            trimmed,
            trimmed,
            elem_ty,
            value,
        )
    }
    if elem_ty, ok_dynamic := dynamic_array_element_type(trimmed); ok_dynamic {
        if type_text_needs_repl_snapshot(e, elem_ty) {
            cloned_item :=
                repl_snapshot_value_text(e, elem_ty, "kvist_item")
            return fmt.tprintf(
                "(proc(kvist_values: %s) -> %s {{ kvist_out := make(%s, 0, len(kvist_values)); for kvist_item in kvist_values {{ append(&kvist_out, %s) }}; return kvist_out }})(%s)",
                trimmed,
                trimmed,
                trimmed,
                cloned_item,
                value,
            )
        }
        return fmt.tprintf(
            "(proc(kvist_values: %s) -> %s {{ kvist_out := make(%s, len(kvist_values)); copy(kvist_out[:], kvist_values[:]); return kvist_out }})(%s)",
            trimmed,
            trimmed,
            trimmed,
            value,
        )
    }
    if key_ty, value_ty, ok_map := map_type_parts(trimmed); ok_map {
        cloned_key := "kvist_key"
        if type_text_needs_repl_snapshot(e, key_ty) {
            cloned_key =
                repl_snapshot_value_text(e, key_ty, cloned_key)
        }
        cloned_value := "kvist_value"
        if type_text_needs_repl_snapshot(e, value_ty) {
            cloned_value =
                repl_snapshot_value_text(e, value_ty, cloned_value)
        }
        return fmt.tprintf(
            "(proc(kvist_values: %s) -> %s {{ kvist_out := make(%s, len(kvist_values)); for kvist_key, kvist_value in kvist_values {{ kvist_out[%s] = %s }}; return kvist_out }})(%s)",
            trimmed,
            trimmed,
            trimmed,
            cloned_key,
            cloned_value,
            value,
        )
    }
    if elem_ty, fixed := repl_type_is_fixed_array(trimmed); fixed {
        if type_text_needs_repl_snapshot(e, elem_ty) {
            cloned_item :=
                repl_snapshot_value_text(e, elem_ty, "kvist_item")
            return fmt.tprintf(
                "(proc(kvist_values: %s) -> %s {{ kvist_out := kvist_values; for kvist_item, kvist_index in kvist_values {{ kvist_out[kvist_index] = %s }}; return kvist_out }})(%s)",
                trimmed,
                trimmed,
                cloned_item,
                value,
            )
        }
        return strings.clone(value)
    }
    if struct_decl, ok_struct := find_struct_decl(e, trimmed); ok_struct {
        assignments := strings.builder_make()
        defer strings.builder_destroy(&assignments)
        for field in struct_decl.fields {
            if !type_text_needs_repl_snapshot(e, field.ty) {
                continue
            }
            snapshot := repl_snapshot_value_text(
                e,
                field.ty,
                fmt.tprintf("kvist_value.%s", field.name),
            )
            fmt.sbprintf(
                &assignments,
                " kvist_out.%s = %s;",
                field.name,
                snapshot,
            )
            delete(snapshot)
        }
        return fmt.tprintf(
            "(proc(kvist_value: %s) -> %s {{ kvist_out := kvist_value;%s return kvist_out }})(%s)",
            trimmed,
            trimmed,
            strings.to_string(assignments),
            value,
        )
    }
    if type_text_has_managed_lifecycle(e, trimmed) {
        return managed_clone_value_text(e, trimmed, value)
    }
    return strings.clone(value)
}

repl_result_transfer_body_text :: proc(
    e: ^Emitter,
    ty,
    value: string,
    depth: int = 0,
    binding_owner: string = "",
    data_helper: string =
        "kvist_repl_retain_data_allocations",
) -> string {
    if depth > 16 {
        return ""
    }
    trimmed := strings.trim_space(ty)
    if type_text_is_string(trimmed) {
        if binding_owner != "" {
            return fmt.aprintf(
                "kvist_repl_host.transfer_binding_allocation(kvist_repl_host.ctx, %q, rawptr(raw_data(%s)));",
                binding_owner,
                value,
            )
        }
        return fmt.aprintf(
            "kvist_repl_host.transfer_result_allocation(kvist_repl_host.ctx, rawptr(raw_data(%s)));",
            value,
        )
    }
    if type_text_is_managed_value(e, trimmed) {
        return fmt.aprintf(
            "%s(%s, &kvist_repl_data_visited);",
            data_helper,
            value,
        )
    }
    elem_ty := ""
    collection_root := false
    if dynamic_elem, ok_dynamic :=
           dynamic_array_element_type(trimmed);
       ok_dynamic {
        elem_ty = dynamic_elem
        collection_root = true
    } else if type_text_is_slice(trimmed) {
        elem_ty = strings.trim_space(trimmed[2:])
        collection_root = true
    }
    if collection_root {
        root := ""
        if binding_owner != "" {
            root = fmt.aprintf(
                "kvist_repl_host.transfer_binding_allocation(kvist_repl_host.ctx, %q, rawptr(raw_data(%s)));",
                binding_owner,
                value,
            )
        } else {
            root = fmt.aprintf(
                "kvist_repl_host.transfer_result_allocation(kvist_repl_host.ctx, rawptr(raw_data(%s)));",
                value,
            )
        }
        nested_value := fmt.tprintf(
            "kvist_transfer_item_%d",
            e.temp_counter,
        )
        e.temp_counter += 1
        nested :=
            repl_result_transfer_body_text(
                e,
                elem_ty,
                nested_value,
                depth+1,
                binding_owner,
                data_helper,
            )
        if nested == "" {
            return root
        }
        result := fmt.aprintf(
            "%s for %s in %s %c %s %c",
            root,
            nested_value,
            value,
            '{',
            nested,
            '}',
        )
        delete(root)
        delete(nested)
        return result
    }
    if key_ty, value_ty, map_type := map_type_parts(trimmed);
       map_type {
        root := ""
        if binding_owner != "" {
            root = fmt.aprintf(
                "kvist_repl_host.transfer_binding_allocation(kvist_repl_host.ctx, %q, rawptr(repl_runtime.map_data(transmute(repl_runtime.Raw_Map)%s)));",
                binding_owner,
                value,
            )
        } else {
            root = fmt.aprintf(
                "kvist_repl_host.transfer_result_allocation(kvist_repl_host.ctx, rawptr(repl_runtime.map_data(transmute(repl_runtime.Raw_Map)%s)));",
                value,
            )
        }
        key_name :=
            fmt.tprintf("kvist_transfer_key_%d", e.temp_counter)
        e.temp_counter += 1
        value_name :=
            fmt.tprintf("kvist_transfer_value_%d", e.temp_counter)
        e.temp_counter += 1
        key_body :=
            repl_result_transfer_body_text(
                e,
                key_ty,
                key_name,
                depth+1,
                binding_owner,
                data_helper,
            )
        value_body :=
            repl_result_transfer_body_text(
                e,
                value_ty,
                value_name,
                depth+1,
                binding_owner,
                data_helper,
            )
        if key_body == "" && value_body == "" {
            return root
        }
        result := fmt.aprintf(
            "%s for %s, %s in %s %c %s %s %c",
            root,
            key_name,
            value_name,
            value,
            '{',
            key_body,
            value_body,
            '}',
        )
        delete(root)
        delete(key_body)
        delete(value_body)
        return result
    }
    if fixed_elem, fixed := repl_type_is_fixed_array(trimmed);
       fixed {
        nested_value := fmt.tprintf(
            "kvist_transfer_item_%d",
            e.temp_counter,
        )
        e.temp_counter += 1
        nested :=
            repl_result_transfer_body_text(
                e,
                fixed_elem,
                nested_value,
                depth+1,
                binding_owner,
                data_helper,
            )
        if nested == "" {
            return ""
        }
        result := fmt.aprintf(
            "for %s in %s %c %s %c",
            nested_value,
            value,
            '{',
            nested,
            '}',
        )
        delete(nested)
        return result
    }
    if struct_decl, found := find_struct_decl(e, trimmed); found {
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        for field in struct_decl.fields {
            field_value :=
                fmt.tprintf("%s.%s", value, field.name)
            nested :=
                repl_result_transfer_body_text(
                    e,
                    field.ty,
                    field_value,
                    depth+1,
                    binding_owner,
                    data_helper,
                )
            if nested != "" {
                strings.write_string(&builder, nested)
                strings.write_byte(&builder, ' ')
                delete(nested)
            }
        }
        return strings.clone(strings.to_string(builder))
    }
    return ""
}

emit_repl_binding_allocation_adapter :: proc(
    e: ^Emitter,
    name,
    ty: string,
) -> bool {
    data_helper :=
        fmt.tprintf("%s__repl_retain_data_allocations", name)
    body := repl_result_transfer_body_text(
        e,
        ty,
        "value",
        binding_owner = name,
        data_helper = data_helper,
    )
    if body == "" {
        return false
    }
    has_data := type_text_has_repl_result_data(e, ty)
    if has_data {
        emit_line(
            e,
            fmt.tprintf(
                "%s :: proc(value: Data, visited: ^map[^Data_Node]bool) %c",
                data_helper,
                '{',
            ),
        )
        e.indent += 1
        emit_line(
            e,
            "if value.node == nil || value.node in visited^ { return }",
        )
        emit_line(e, "visited^[value.node] = true")
        data_memories := []string{
            "rawptr(value.node)",
            "rawptr(raw_data(value.node.text))",
            "rawptr(raw_data(value.node.items))",
            "rawptr(raw_data(value.node.entries))",
        }
        for memory in data_memories {
            emit_line(
                e,
                fmt.tprintf(
                    "kvist_repl_host.retain_binding_allocation(kvist_repl_host.ctx, %q, %s)",
                    name,
                    memory,
                ),
            )
        }
        emit_line(
            e,
            fmt.tprintf(
                "for item in value.node.items %c %s(item, visited) %c",
                '{',
                data_helper,
                '}',
            ),
        )
        emit_line(e, "for entry in value.node.entries {")
        e.indent += 1
        emit_line(
            e,
            fmt.tprintf("%s(entry.key, visited)", data_helper),
        )
        emit_line(
            e,
            fmt.tprintf("%s(entry.value, visited)", data_helper),
        )
        e.indent -= 1
        emit_line(e, "}")
        e.indent -= 1
        emit_line(e, "}")
    }
    setup := ""
    if has_data {
        setup =
            "kvist_repl_data_visited := make(map[^Data_Node]bool); defer delete(kvist_repl_data_visited); "
    }
    emit_line(
        e,
        fmt.tprintf(
            "%s__repl_register_allocations :: proc(value: %s) %c %s%s %c",
            name,
            ty,
            '{',
            setup,
            body,
            '}',
        ),
    )
    delete(body)
    return true
}

type_text_needs_repl_snapshot :: proc(e: ^Emitter, ty: string, depth: int = 0) -> bool {
    trimmed := strings.trim_space(ty)
    if depth > 16 {
        return false
    }
    if type_text_is_string(trimmed) ||
       type_text_is_managed_value(e, trimmed) ||
       type_text_is_slice(trimmed) ||
       type_text_is_dynamic_array(trimmed) ||
       type_text_is_map(trimmed) {
        return true
    }
    if elem_ty, fixed := repl_type_is_fixed_array(trimmed); fixed {
        return type_text_needs_repl_snapshot(e, elem_ty, depth+1)
    }
    if struct_decl, ok_struct := find_struct_decl(e, trimmed); ok_struct {
        for field in struct_decl.fields {
            if type_text_needs_repl_snapshot(e, field.ty, depth+1) {
                return true
            }
        }
    }
    return false
}

type_text_has_repl_borrowed_view :: proc(
    e: ^Emitter,
    ty: string,
    depth: int = 0,
) -> bool {
    trimmed := strings.trim_space(ty)
    if depth > 16 {
        return false
    }
    if type_text_is_slice(trimmed) {
        return true
    }
    if elem_ty, ok_dynamic := dynamic_array_element_type(trimmed); ok_dynamic {
        return type_text_has_repl_borrowed_view(e, elem_ty, depth+1)
    }
    if key_ty, value_ty, ok_map := map_type_parts(trimmed); ok_map {
        return type_text_has_repl_borrowed_view(e, key_ty, depth+1) ||
               type_text_has_repl_borrowed_view(e, value_ty, depth+1)
    }
    if elem_ty, fixed := repl_type_is_fixed_array(trimmed); fixed {
        return type_text_has_repl_borrowed_view(e, elem_ty, depth+1)
    }
    if struct_decl, ok_struct := find_struct_decl(e, trimmed); ok_struct {
        for field in struct_decl.fields {
            if type_text_has_repl_borrowed_view(e, field.ty, depth+1) {
                return true
            }
        }
    }
    return false
}

repl_result_needs_snapshot :: proc(e: ^Emitter, ty: string) -> bool {
    return type_text_needs_repl_snapshot(e, ty)
}

repl_snapshot_call_form :: proc(form: CST_Form) -> CST_Form {
    return repl_snapshot_call_form_named(
        form,
        "kvist_repl_snapshot_value",
    )
}

repl_snapshot_call_form_named :: proc(
    form: CST_Form,
    helper_name: string,
) -> CST_Form {
    return make_list_form(
        {
            make_symbol_form("odin-call", form.span),
            CST_Form{
                kind = .String,
                text = fmt.tprintf("%q", helper_name),
                span = form.span,
            },
            form,
        },
        form.span,
    )
}

repl_snapshot_tail_form :: proc(form: CST_Form) -> CST_Form {
    return repl_snapshot_tail_form_named(
        form,
        "kvist_repl_snapshot_value",
    )
}

repl_snapshot_tail_form_named :: proc(
    form: CST_Form,
    helper_name: string,
) -> CST_Form {
    if form.kind != .List ||
       len(form.items) == 0 ||
       form.items[0].kind != .Symbol {
        return repl_snapshot_call_form_named(form, helper_name)
    }

    items: [dynamic]CST_Form
    append(&items, ..form.items[:])
    switch form.items[0].text {
    case "let":
        if len(items) >= 3 {
            items[len(items)-1] =
                repl_snapshot_tail_form_named(
                    items[len(items)-1],
                    helper_name,
                )
            return make_list_form(items[:], form.span)
        }
    case "do", "block":
        if len(items) >= 2 {
            items[len(items)-1] =
                repl_snapshot_tail_form_named(
                    items[len(items)-1],
                    helper_name,
                )
            return make_list_form(items[:], form.span)
        }
    case "if":
        if len(items) == 4 {
            items[2] =
                repl_snapshot_tail_form_named(items[2], helper_name)
            items[3] =
                repl_snapshot_tail_form_named(items[3], helper_name)
            return make_list_form(items[:], form.span)
        }
    case "type-case":
        if len(items) >= 5 && len(items)%2 == 1 {
            for i := 3; i < len(items)-1; i += 2 {
                items[i] =
                    repl_snapshot_tail_form_named(items[i], helper_name)
            }
            items[len(items)-1] =
                repl_snapshot_tail_form_named(
                    items[len(items)-1],
                    helper_name,
                )
            return make_list_form(items[:], form.span)
        }
    case "match":
        if len(items) >= 4 {
            for i := 3; i < len(items); i += 2 {
                items[i] =
                    repl_snapshot_tail_form_named(items[i], helper_name)
            }
            return make_list_form(items[:], form.span)
        }
    }
    return repl_snapshot_call_form_named(form, helper_name)
}

repl_var_signature :: proc(ty: string, e: ^Emitter = nil) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    fmt.sbprintf(&builder, "var:%s", ty)
    seen := make(map[string]bool)
    defer delete(seen)
    repl_append_type_layout(&builder, e, ty, &seen)
    return strings.clone(strings.to_string(builder))
}

repl_var_adapter_text :: proc(e: ^Emitter, decl: ^Var_Decl) -> string {
    signature := repl_var_signature(decl.ty, e)
    defer delete(signature)
    has_repl_data := type_text_has_data_lifecycle(e, decl.ty)
    if elem_ty, ok_dynamic := dynamic_array_element_type(decl.ty); ok_dynamic {
        has_repl_data = type_text_has_data_lifecycle(e, elem_ty)
    }
    if has_repl_data {
        mark_data_type(e)
    }
    return fmt.tprintf(
        `%s :: proc() -> ^%s %c
    target := transmute(proc() -> ^%s) kvist_repl_host.lookup_proc(kvist_repl_host.ctx, %q, %q)
    assert(target != nil, %q)
    return target()
%c`,
        decl.name, decl.ty, '{', decl.ty, decl.name, signature,
        fmt.tprintf("stale REPL var: %s", decl.name), '}',
    )
}

repl_current_var_text :: proc(e: ^Emitter, decl: ^Var_Decl) -> string {
    adapter := repl_var_adapter_text(e, decl)
    defer delete(adapter)
    snapshot := repl_snapshot_value_text(e, decl.ty, "value")
    defer delete(snapshot)
    return fmt.tprintf(
        `%s__repl_storage: %s
%s__repl_impl :: proc() -> ^%s %c return &%s__repl_storage %c
%s
%s__repl_checkpoint_clone :: proc "c" (opaque: rawptr) %c
    context = repl_runtime.default_context()
    value := %s__repl_storage
    snapshot := transmute(^%s)opaque
    snapshot^ = %s
%c
%s__repl_checkpoint_restore :: proc "c" (opaque: rawptr) %c
    context = repl_runtime.default_context()
    snapshot := transmute(^%s)opaque
    value := snapshot^
    %s__repl_storage = %s
%c`,
        decl.name, decl.ty,
        decl.name, decl.ty, '{', decl.name, '}',
        adapter,
        decl.name, '{',
        decl.name,
        decl.ty,
        snapshot,
        '}',
        decl.name, '{',
        decl.ty,
        decl.name,
        snapshot,
        '}',
    )
}

form_is_repl_snapshot_call :: proc(form: CST_Form) -> bool {
    return form.kind == .List &&
           len(form.items) == 3 &&
           form.items[0].kind == .Symbol &&
           form.items[0].text == "odin-call" &&
           form.items[1].kind == .String &&
           form.items[1].text == `"kvist_repl_snapshot_value"`
}

type_text_has_repl_result_data :: proc(
    e: ^Emitter,
    text: string,
    depth: int = 0,
) -> bool {
    trimmed := strings.trim_space(text)
    if type_text_is_managed_value(e, trimmed) {
        return true
    }
    if e == nil || depth > 16 {
        return false
    }
    if elem_ty, ok_dynamic :=
           dynamic_array_element_type(trimmed);
       ok_dynamic {
        return type_text_has_repl_result_data(
            e,
            elem_ty,
            depth+1,
        )
    }
    if type_text_is_slice(trimmed) {
        return type_text_has_repl_result_data(
            e,
            strings.trim_space(trimmed[2:]),
            depth+1,
        )
    }
    if elem_ty, fixed := repl_type_is_fixed_array(trimmed);
       fixed {
        return type_text_has_repl_result_data(
            e,
            elem_ty,
            depth+1,
        )
    }
    if key_ty, value_ty, map_type :=
           map_type_parts(trimmed);
       map_type {
        return type_text_has_repl_result_data(
                   e,
                   key_ty,
                   depth+1,
               ) ||
               type_text_has_repl_result_data(
                   e,
                   value_ty,
                   depth+1,
               )
    }
    struct_decl, ok_struct := find_struct_decl(e, trimmed)
    if !ok_struct {
        return false
    }
    for field in struct_decl.fields {
        if type_text_has_repl_result_data(
            e,
            field.ty,
            depth+1,
        ) {
            return true
        }
    }
    return false
}

type_text_needs_managed_copy :: proc(e: ^Emitter, ty: string) -> bool {
    return type_text_is_string(ty) ||
           type_text_is_dynamic_array(ty) ||
           type_text_is_map(ty) ||
           type_text_has_managed_lifecycle(e, ty)
}

debug_hex_write :: proc(builder: ^strings.Builder, value: string) {
    digits := "0123456789abcdef"
    for byte in transmute([]byte)value {
        strings.write_byte(builder, digits[int(byte >> 4)])
        strings.write_byte(builder, digits[int(byte & 0xf)])
    }
}

debug_local_ownership_text :: proc(local: Param) -> string {
    if local.owner_flag != "" || local.ownership == .Owned {
        return "owned"
    }
    if local.ownership == .Borrowed {
        return "borrowed"
    }
    return "value"
}

debug_visible_local_indices :: proc(e: ^Emitter) -> [dynamic]int {
    visible: [dynamic]int
    for i := len(e.local_types)-1; i >= 0; i -= 1 {
        shadowed := false
        for visible_i in visible {
            if e.local_types[visible_i].name == e.local_types[i].name {
                shadowed = true
                break
            }
        }
        if !shadowed {
            append(&visible, i)
        }
    }
    return visible
}

debug_struct_field_name :: proc(field: Struct_Field) -> string {
    return field.source_name if field.source_name != "" else field.name
}

REPL_DEBUG_PATH_LIMIT :: 256
REPL_DEBUG_DYNAMIC_ARRAY_LIMIT :: 64
REPL_DEBUG_PAGE_DISCOVERY_DEPTH :: 8
REPL_TRACE_VALUE_LOCAL_LIMIT :: 32
REPL_TRACE_VALUE_STRING_LIMIT :: 256

debug_map_key_supported :: proc(ty: string) -> bool {
    switch strings.trim_space(ty) {
    case "string", "bool",
         "int", "i8", "i16", "i32", "i64", "i128",
         "uint", "u8", "u16", "u32", "u64", "u128",
         "uintptr", "rune", "byte":
        return true
    }
    return false
}

debug_fixed_array_parts :: proc(ty: string) -> (
    elem_ty: string,
    count: int,
    ok: bool,
) {
    if !type_text_is_fixed_array(ty) {
        return "", 0, false
    }
    close := strings.index(ty, "]")
    if close <= 1 || close+1 >= len(ty) {
        return "", 0, false
    }
    for byte in transmute([]byte)ty[1:close] {
        if byte < '0' || byte > '9' {
            return "", 0, false
        }
        digit := int(byte-'0')
        if count > (max(int)-digit)/10 {
            return "", 0, false
        }
        count = count*10+digit
    }
    return ty[close+1:], count, true
}

debug_type_contains_runtime_collection :: proc(
    e: ^Emitter,
    ty: string,
    depth := REPL_DEBUG_PATH_LIMIT,
) -> bool {
    if depth == 0 {
        // Invalid recursive aggregates and extremely deep valid aggregates
        // must stay bounded even before Odin rejects or lays them out.
        return true
    }
    if _, dynamic_array := dynamic_array_element_type(ty);
       dynamic_array {
        return true
    }
    if _, _, is_map := map_type_parts(ty); is_map {
        return true
    }
    if struct_decl, struct_ok := find_struct_decl(e, ty); struct_ok {
        for field in struct_decl.fields {
            if debug_type_contains_runtime_collection(
                e,
                field.ty,
                depth-1,
            ) {
                return true
            }
        }
    } else if elem_ty, _, array_ok :=
        debug_fixed_array_parts(ty); array_ok {
        return debug_type_contains_runtime_collection(
            e,
            elem_ty,
            depth-1,
        )
    }
    return false
}

debug_child_value_count :: proc(
    e: ^Emitter,
    ty: string,
    remaining: ^int,
) -> int {
    count := 0
    if struct_decl, ok := find_struct_decl(e, ty); ok {
        for field in struct_decl.fields {
            if remaining^ == 0 {
                break
            }
            remaining^ -= 1
            count += 1
            count += debug_child_value_count(e, field.ty, remaining)
        }
    } else if elem_ty, length, ok_array :=
        debug_fixed_array_parts(ty); ok_array {
        for _ in 0..<length {
            if remaining^ == 0 {
                break
            }
            remaining^ -= 1
            count += 1
            count += debug_child_value_count(e, elem_ty, remaining)
        }
    }
    return count
}

debug_visible_value_count :: proc(e: ^Emitter, visible: []int) -> int {
    count := len(visible)
    for visible_i in visible {
        local := e.local_types[visible_i]
        remaining := REPL_DEBUG_PATH_LIMIT
        count += debug_child_value_count(e, local.ty, &remaining)
    }
    return count
}

debug_write_path_metadata :: proc(
    builder: ^strings.Builder,
    e: ^Emitter,
    ty: string,
    source_prefix: string,
    remaining: ^int,
) {
    if struct_decl, ok := find_struct_decl(e, ty); ok {
        for field in struct_decl.fields {
            if remaining^ == 0 {
                break
            }
            remaining^ -= 1
            source_name := debug_struct_field_name(field)
            source_path := source_name
            if source_prefix != "" {
                source_path =
                    fmt.tprintf("%s.%s", source_prefix, source_name)
            }
            debug_hex_write(builder, source_path)
            strings.write_byte(builder, '=')
            debug_hex_write(builder, field.ty)
            strings.write_byte(builder, ';')
            debug_write_path_metadata(
                builder,
                e,
                field.ty,
                source_path,
                remaining,
            )
        }
    } else if elem_ty, length, ok_array :=
        debug_fixed_array_parts(ty); ok_array {
        for i in 0..<length {
            if remaining^ == 0 {
                break
            }
            remaining^ -= 1
            source_path := fmt.tprintf("%s[%d]", source_prefix, i)
            debug_hex_write(builder, source_path)
            strings.write_byte(builder, '=')
            debug_hex_write(builder, elem_ty)
            strings.write_byte(builder, ';')
            debug_write_path_metadata(
                builder,
                e,
                elem_ty,
                source_path,
                remaining,
            )
        }
    }
}

debug_pause_placeholder :: proc(e: ^Emitter, span: Span) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    fmt.sbprintf(
        &builder,
        "__KVIST_DEBUG_PAUSE_%s_%d_%d_L",
        "F" if span.source == .File else "E",
        span.start,
        span.end,
    )
    visible := debug_visible_local_indices(e)
    defer delete(visible)
    for i := len(visible)-1; i >= 0; i -= 1 {
        local := e.local_types[visible[i]]
        debug_hex_write(&builder, local.name)
        strings.write_byte(&builder, ':')
        debug_hex_write(&builder, local.ty)
        fmt.sbprintf(
            &builder,
            ":%d:%s",
            1 if local.mutable else 0,
            debug_local_ownership_text(local),
        )
        if map_key_ty, map_value_ty, is_map :=
            map_type_parts(local.ty);
           is_map && debug_map_key_supported(map_key_ty) {
            strings.write_string(&builder, "::::")
            debug_hex_write(&builder, map_key_ty)
            strings.write_byte(&builder, ':')
            debug_hex_write(&builder, map_value_ty)
            value_remaining := REPL_DEBUG_DYNAMIC_ARRAY_LIMIT-1
            if debug_child_value_count(
                e,
                map_value_ty,
                &value_remaining,
            ) > 0 {
                strings.write_byte(&builder, ':')
                value_remaining =
                    REPL_DEBUG_DYNAMIC_ARRAY_LIMIT-1
                debug_write_path_metadata(
                    &builder,
                    e,
                    map_value_ty,
                    "",
                    &value_remaining,
                )
            }
            strings.write_byte(&builder, ',')
            continue
        }
        remaining := REPL_DEBUG_PATH_LIMIT
        path_count := debug_child_value_count(e, local.ty, &remaining)
        dynamic_elem_ty, dynamic_array :=
            dynamic_array_element_type(local.ty)
        if path_count > 0 || dynamic_array {
            strings.write_byte(&builder, ':')
            if path_count > 0 {
                remaining = REPL_DEBUG_PATH_LIMIT
                debug_write_path_metadata(
                    &builder,
                    e,
                    local.ty,
                    "",
                    &remaining,
                )
            }
        }
        if dynamic_array {
            strings.write_byte(&builder, ':')
            debug_hex_write(&builder, dynamic_elem_ty)
            element_remaining := REPL_DEBUG_DYNAMIC_ARRAY_LIMIT-1
            if debug_child_value_count(
                e,
                dynamic_elem_ty,
                &element_remaining,
            ) > 0 {
                strings.write_byte(&builder, ':')
                element_remaining =
                    REPL_DEBUG_DYNAMIC_ARRAY_LIMIT-1
                debug_write_path_metadata(
                    &builder,
                    e,
                    dynamic_elem_ty,
                    "",
                    &element_remaining,
                )
            }
        }
        strings.write_byte(&builder, ',')
    }
    strings.write_string(&builder, "__")
    return strings.clone(strings.to_string(builder))
}

debug_write_rendered_value :: proc(
    builder: ^strings.Builder,
    local: Param,
    target: string,
) {
    if local.debug_unavailable {
        strings.write_string(
            builder,
            `fmt.aprintf("<unavailable>")`,
        )
    } else if local.owner_flag != "" {
        fmt.sbprintf(
            builder,
            "fmt.aprintf(\"%%#v\", %s) if %s else fmt.aprintf(\"<moved>\")",
            target,
            local.owner_flag,
        )
    } else {
        fmt.sbprintf(
            builder,
            "fmt.aprintf(\"%%#v\", %s)",
            target,
        )
    }
}

debug_write_trace_value :: proc(
    builder: ^strings.Builder,
    e: ^Emitter,
    local: Param,
    target: string,
) {
    if local.debug_unavailable {
        debug_write_rendered_value(builder, local, target)
        return
    }
    ty := strings.trim_space(local.ty)
    rendered := ""
    if type_text_is_string(ty) {
        rendered = fmt.tprintf(
            `fmt.aprintf("%%q%%s", %s[:min(len(%s), %d)], "<truncated>" if len(%s) > %d else "")`,
            target,
            target,
            REPL_TRACE_VALUE_STRING_LIMIT,
            target,
            REPL_TRACE_VALUE_STRING_LIMIT,
        )
    } else if (type_text_is_builtin_odin_scalar(ty) && ty != "any") ||
              enum_type_exists(e, ty) {
        debug_write_rendered_value(builder, local, target)
        return
    } else {
        placeholder :=
            fmt.tprintf("<not-captured type=%s>", ty)
        rendered = fmt.tprintf(
            "fmt.aprintf(%q)",
            placeholder,
        )
        delete(placeholder)
    }
    defer delete(rendered)
    if local.owner_flag != "" {
        fmt.sbprintf(
            builder,
            "%s if %s else fmt.aprintf(\"<moved>\")",
            rendered,
            local.owner_flag,
        )
    } else {
        strings.write_string(builder, rendered)
    }
}

debug_emit_trace_values :: proc(
    e: ^Emitter,
    visible: []int,
    flags_name,
    placeholder: string,
) {
    emit_line(
        e,
        fmt.tprintf(
            "if %s & u32(4) != 0 %c",
            flags_name,
            '{',
        ),
    )
    e.indent += 1
    capture_count := min(
        len(visible),
        REPL_TRACE_VALUE_LOCAL_LIMIT,
    )
    if capture_count == 0 {
        emit_line(
            e,
            fmt.tprintf(
                "kvist_repl_host.trace_values(kvist_repl_host.ctx, %q, nil, 0)",
                placeholder,
            ),
        )
    } else {
        values_name :=
            fmt.tprintf("kvist_trace_values_%d", e.temp_counter)
        e.temp_counter += 1
        pointers_name :=
            fmt.tprintf(
                "kvist_trace_rendered_values_%d",
                e.temp_counter,
            )
        e.temp_counter += 1
        emit_indent(e)
        fmt.sbprintf(
            &e.builder,
            "%s := [%d]string%c",
            values_name,
            capture_count,
            '{',
        )
        captured := 0
        for i := len(visible)-1;
            i >= 0 && captured < capture_count;
            i -= 1 {
            if captured > 0 {
                strings.write_string(&e.builder, ", ")
            }
            local := e.local_types[visible[i]]
            debug_write_trace_value(
                &e.builder,
                e,
                local,
                local.name,
            )
            captured += 1
        }
        strings.write_string(&e.builder, "}")
        emit_raw_newline(e)
        emit_line(
            e,
            fmt.tprintf(
                "defer for value in %s %c delete(value) %c",
                values_name,
                '{',
                '}',
            ),
        )
        emit_line(
            e,
            fmt.tprintf(
                "%s: [%d]Kvist_Repl_Rendered_Value",
                pointers_name,
                capture_count,
            ),
        )
        emit_line(
            e,
            fmt.tprintf(
                "for value, i in %s %c %s[i] = Kvist_Repl_Rendered_Value%cdata = raw_data(value), length = len(value)%c %c",
                values_name,
                '{',
                pointers_name,
                '{',
                '}',
                '}',
            ),
        )
        emit_line(
            e,
            fmt.tprintf(
                "kvist_repl_host.trace_values(kvist_repl_host.ctx, %q, &%s[0], %d)",
                placeholder,
                pointers_name,
                capture_count,
            ),
        )
    }
    e.indent -= 1
    emit_line(e, "}")
}

debug_write_rendered_paths :: proc(
    builder: ^strings.Builder,
    e: ^Emitter,
    local: Param,
    ty: string,
    target_prefix: string,
    value_i: ^int,
    remaining: ^int,
) {
    if struct_decl, ok := find_struct_decl(e, ty); ok {
        for field in struct_decl.fields {
            if remaining^ == 0 {
                break
            }
            remaining^ -= 1
            target_path :=
                fmt.tprintf("%s.%s", target_prefix, field.name)
            strings.write_string(builder, ", ")
            debug_write_rendered_value(builder, local, target_path)
            value_i^ += 1
            debug_write_rendered_paths(
                builder,
                e,
                local,
                field.ty,
                target_path,
                value_i,
                remaining,
            )
        }
    } else if elem_ty, length, ok_array :=
        debug_fixed_array_parts(ty); ok_array {
        for i in 0..<length {
            if remaining^ == 0 {
                break
            }
            remaining^ -= 1
            target_path := fmt.tprintf("%s[%d]", target_prefix, i)
            strings.write_string(builder, ", ")
            debug_write_rendered_value(builder, local, target_path)
            value_i^ += 1
            debug_write_rendered_paths(
                builder,
                e,
                local,
                elem_ty,
                target_path,
                value_i,
                remaining,
            )
        }
    }
}

debug_rendered_value_text :: proc(local: Param, target: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    debug_write_rendered_value(&builder, local, target)
    return strings.clone(strings.to_string(builder))
}

debug_emit_append_rendered_value :: proc(
    e: ^Emitter,
    values_name: string,
    local: Param,
    target: string,
) {
    rendered := debug_rendered_value_text(local, target)
    defer delete(rendered)
    emit_line(
        e,
        fmt.tprintf("append(&%s, %s)", values_name, rendered),
    )
}

debug_emit_append_aggregate_root :: proc(
    e: ^Emitter,
    values_name: string,
    local: Param,
    ty: string,
) {
    if local.debug_unavailable {
        emit_line(
            e,
            fmt.tprintf(
                `append(&%s, fmt.aprintf("<unavailable>"))`,
                values_name,
            ),
        )
    } else {
        summary := fmt.tprintf("<aggregate type=%s>", ty)
        defer delete(summary)
        if local.owner_flag != "" {
            emit_line(
                e,
                fmt.tprintf(
                    `append(&%s, fmt.aprintf(%q) if %s else fmt.aprintf("<moved>"))`,
                    values_name,
                    summary,
                    local.owner_flag,
                ),
            )
        } else {
            emit_line(
                e,
                fmt.tprintf(
                    `append(&%s, fmt.aprintf(%q))`,
                    values_name,
                    summary,
                ),
            )
        }
    }
}

debug_emit_append_typed_rendered_value :: proc(
    e: ^Emitter,
    values_name: string,
    local: Param,
    ty,
    target: string,
) {
    if _, dynamic_array := dynamic_array_element_type(ty);
       dynamic_array {
        debug_emit_append_dynamic_array_root(
            e,
            values_name,
            local,
            target,
        )
    } else if _, _, is_map := map_type_parts(ty); is_map {
        debug_emit_append_map_root(
            e,
            values_name,
            local,
            target,
        )
    } else if debug_type_contains_runtime_collection(e, ty) {
        debug_emit_append_aggregate_root(
            e,
            values_name,
            local,
            ty,
        )
    } else {
        debug_emit_append_rendered_value(
            e,
            values_name,
            local,
            target,
        )
    }
}

debug_emit_append_static_paths :: proc(
    e: ^Emitter,
    values_name: string,
    local: Param,
    ty,
    target_prefix: string,
    remaining: ^int,
) {
    if struct_decl, ok := find_struct_decl(e, ty); ok {
        for field in struct_decl.fields {
            if remaining^ == 0 {
                break
            }
            remaining^ -= 1
            target_path :=
                fmt.tprintf("%s.%s", target_prefix, field.name)
            debug_emit_append_typed_rendered_value(
                e,
                values_name,
                local,
                field.ty,
                target_path,
            )
            debug_emit_append_static_paths(
                e,
                values_name,
                local,
                field.ty,
                target_path,
                remaining,
            )
        }
    } else if elem_ty, length, ok_array :=
        debug_fixed_array_parts(ty); ok_array {
        for i in 0..<length {
            if remaining^ == 0 {
                break
            }
            remaining^ -= 1
            target_path := fmt.tprintf("%s[%d]", target_prefix, i)
            debug_emit_append_typed_rendered_value(
                e,
                values_name,
                local,
                elem_ty,
                target_path,
            )
            debug_emit_append_static_paths(
                e,
                values_name,
                local,
                elem_ty,
                target_path,
                remaining,
            )
        }
    }
}

debug_emit_append_dynamic_array :: proc(
    e: ^Emitter,
    values_name: string,
    local: Param,
    elem_ty: string,
) {
    if local.debug_unavailable {
        emit_line(
            e,
            fmt.tprintf(
                `append(&%s, fmt.aprintf("-1"))`,
                values_name,
            ),
        )
        return
    }
    guarded := local.owner_flag != ""
    if guarded {
        emit_line(
            e,
            fmt.tprintf("if %s %c", local.owner_flag, '{'),
        )
        e.indent += 1
    }
    emit_line(
        e,
        fmt.tprintf(
            `append(&%s, fmt.aprintf("%%d", len(%s)))`,
            values_name,
            local.name,
        ),
    )
    element_remaining := REPL_DEBUG_DYNAMIC_ARRAY_LIMIT-1
    element_path_count :=
        debug_child_value_count(e, elem_ty, &element_remaining)
    capture_limit :=
        max(
            1,
            REPL_DEBUG_DYNAMIC_ARRAY_LIMIT/
                (1+element_path_count),
        )
    index_name := fmt.tprintf("kvist_debug_index_%d", e.temp_counter)
    e.temp_counter += 1
    emit_line(
        e,
        fmt.tprintf(
            "for %s in 0..<min(len(%s), %d) %c",
            index_name,
            local.name,
            capture_limit,
            '{',
        ),
    )
    e.indent += 1
    element_target :=
        fmt.tprintf("%s[%s]", local.name, index_name)
    debug_emit_append_typed_rendered_value(
        e,
        values_name,
        local,
        elem_ty,
        element_target,
    )
    element_remaining = REPL_DEBUG_DYNAMIC_ARRAY_LIMIT-1
    debug_emit_append_static_paths(
        e,
        values_name,
        local,
        elem_ty,
        element_target,
        &element_remaining,
    )
    e.indent -= 1
    emit_line(e, "}")
    if guarded {
        e.indent -= 1
        emit_line(e, "} else {")
        e.indent += 1
        emit_line(
            e,
            fmt.tprintf(
                `append(&%s, fmt.aprintf("-1"))`,
                values_name,
            ),
        )
        e.indent -= 1
        emit_line(e, "}")
    }
}

debug_emit_append_dynamic_array_root :: proc(
    e: ^Emitter,
    values_name: string,
    local: Param,
    target: string,
) {
    if local.debug_unavailable {
        emit_line(
            e,
            fmt.tprintf(
                `append(&%s, fmt.aprintf("<unavailable>"))`,
                values_name,
            ),
        )
    } else if local.owner_flag != "" {
        emit_line(
            e,
            fmt.tprintf(
                `append(&%s, fmt.aprintf("<dynamic-array count=%%d>", len(%s)) if %s else fmt.aprintf("<moved>"))`,
                values_name,
                target,
                local.owner_flag,
            ),
        )
    } else {
        emit_line(
            e,
            fmt.tprintf(
                `append(&%s, fmt.aprintf("<dynamic-array count=%%d>", len(%s)))`,
                values_name,
                target,
            ),
        )
    }
}

debug_emit_append_map_root :: proc(
    e: ^Emitter,
    values_name: string,
    local: Param,
    target: string,
) {
    if local.debug_unavailable {
        emit_line(
            e,
            fmt.tprintf(
                `append(&%s, fmt.aprintf("<unavailable>"))`,
                values_name,
            ),
        )
    } else if local.owner_flag != "" {
        emit_line(
            e,
            fmt.tprintf(
                `append(&%s, fmt.aprintf("<map count=%%d>", len(%s)) if %s else fmt.aprintf("<moved>"))`,
                values_name,
                target,
                local.owner_flag,
            ),
        )
    } else {
        emit_line(
            e,
            fmt.tprintf(
                `append(&%s, fmt.aprintf("<map count=%%d>", len(%s)))`,
                values_name,
                target,
            ),
        )
    }
}

debug_emit_append_map :: proc(
    e: ^Emitter,
    values_name: string,
    local: Param,
    key_ty,
    value_ty: string,
) {
    if local.debug_unavailable {
        emit_line(
            e,
            fmt.tprintf(
                `append(&%s, fmt.aprintf("-1"))`,
                values_name,
            ),
        )
        return
    }
    guarded := local.owner_flag != ""
    if guarded {
        emit_line(
            e,
            fmt.tprintf("if %s %c", local.owner_flag, '{'),
        )
        e.indent += 1
    }
    emit_line(
        e,
        fmt.tprintf(
            `append(&%s, fmt.aprintf("%%d", len(%s)))`,
            values_name,
            local.name,
        ),
    )
    value_remaining := REPL_DEBUG_DYNAMIC_ARRAY_LIMIT-1
    value_path_count :=
        debug_child_value_count(e, value_ty, &value_remaining)
    capture_limit :=
        max(
            1,
            REPL_DEBUG_DYNAMIC_ARRAY_LIMIT/
                (1+value_path_count),
        )
    keys_name := fmt.tprintf("kvist_debug_keys_%d", e.temp_counter)
    e.temp_counter += 1
    candidate_name :=
        fmt.tprintf("kvist_debug_key_%d", e.temp_counter)
    e.temp_counter += 1
    insert_name :=
        fmt.tprintf("kvist_debug_insert_%d", e.temp_counter)
    e.temp_counter += 1
    index_name :=
        fmt.tprintf("kvist_debug_key_index_%d", e.temp_counter)
    e.temp_counter += 1
    shift_name :=
        fmt.tprintf("kvist_debug_shift_%d", e.temp_counter)
    e.temp_counter += 1
    emit_line(
        e,
        fmt.tprintf(
            "%s := make([dynamic]%s, 0, %d)",
            keys_name,
            key_ty,
            capture_limit,
        ),
    )
    emit_line(e, fmt.tprintf("defer delete(%s)", keys_name))
    emit_line(
        e,
        fmt.tprintf(
            "for %s, _ in %s %c",
            candidate_name,
            local.name,
            '{',
        ),
    )
    e.indent += 1
    emit_line(
        e,
        fmt.tprintf("%s := len(%s)", insert_name, keys_name),
    )
    emit_line(
        e,
        fmt.tprintf(
            "for %s in 0..<len(%s) %c",
            index_name,
            keys_name,
            '{',
        ),
    )
    e.indent += 1
    less_text := fmt.tprintf(
        "%s < %s[%s]",
        candidate_name,
        keys_name,
        index_name,
    )
    if key_ty == "bool" {
        less_text = fmt.tprintf(
            "!%s && %s[%s]",
            candidate_name,
            keys_name,
            index_name,
        )
    }
    emit_line(e, fmt.tprintf("if %s %c", less_text, '{'))
    e.indent += 1
    emit_line(
        e,
        fmt.tprintf("%s = %s", insert_name, index_name),
    )
    emit_line(e, "break")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(
        e,
        fmt.tprintf("if %s < %d %c", insert_name, capture_limit, '{'),
    )
    e.indent += 1
    emit_line(
        e,
        fmt.tprintf("if len(%s) < %d %c", keys_name, capture_limit, '{'),
    )
    e.indent += 1
    emit_line(
        e,
        fmt.tprintf("append(&%s, %s)", keys_name, candidate_name),
    )
    e.indent -= 1
    emit_line(e, "}")
    emit_line(
        e,
        fmt.tprintf(
            "for %s := len(%s)-1; %s > %s; %s -= 1 %c",
            shift_name,
            keys_name,
            shift_name,
            insert_name,
            shift_name,
            '{',
        ),
    )
    e.indent += 1
    emit_line(
        e,
        fmt.tprintf(
            "%s[%s] = %s[%s-1]",
            keys_name,
            shift_name,
            keys_name,
            shift_name,
        ),
    )
    e.indent -= 1
    emit_line(e, "}")
    emit_line(
        e,
        fmt.tprintf(
            "%s[%s] = %s",
            keys_name,
            insert_name,
            candidate_name,
        ),
    )
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(
        e,
        fmt.tprintf("for %s in %s %c", candidate_name, keys_name, '{'),
    )
    e.indent += 1
    key_format := "%q" if key_ty == "string" else "%v"
    emit_line(
        e,
        fmt.tprintf(
            `append(&%s, fmt.aprintf(%q, %s))`,
            values_name,
            key_format,
            candidate_name,
        ),
    )
    value_target :=
        fmt.tprintf("%s[%s]", local.name, candidate_name)
    debug_emit_append_typed_rendered_value(
        e,
        values_name,
        local,
        value_ty,
        value_target,
    )
    value_remaining = REPL_DEBUG_DYNAMIC_ARRAY_LIMIT-1
    debug_emit_append_static_paths(
        e,
        values_name,
        local,
        value_ty,
        value_target,
        &value_remaining,
    )
    e.indent -= 1
    emit_line(e, "}")
    if guarded {
        e.indent -= 1
        emit_line(e, "} else {")
        e.indent += 1
        emit_line(
            e,
            fmt.tprintf(
                `append(&%s, fmt.aprintf("-1"))`,
                values_name,
            ),
        )
        e.indent -= 1
        emit_line(e, "}")
    }
}

debug_visible_has_runtime_collection :: proc(
    e: ^Emitter,
    visible: []int,
) -> bool {
    for visible_i in visible {
        if _, ok := dynamic_array_element_type(
            e.local_types[visible_i].ty,
        ); ok {
            return true
        }
        if debug_type_contains_runtime_collection(
            e,
            e.local_types[visible_i].ty,
        ) {
            return true
        }
    }
    return false
}

debug_page_rendered_value_text :: proc(
    e: ^Emitter,
    ty,
    target: string,
) -> string {
    if _, dynamic_array := dynamic_array_element_type(ty);
       dynamic_array {
        return fmt.tprintf(
            `fmt.aprintf("<dynamic-array count=%%d>", len(%s))`,
            target,
        )
    }
    if _, _, is_map := map_type_parts(ty); is_map {
        return fmt.tprintf(
            `fmt.aprintf("<map count=%%d>", len(%s))`,
            target,
        )
    }
    if debug_type_contains_runtime_collection(e, ty) {
        return fmt.tprintf(
            `fmt.aprintf(%q)`,
            fmt.tprintf("<aggregate type=%s>", ty),
        )
    }
    return fmt.tprintf(`fmt.aprintf("%%#v", %s)`, target)
}

debug_emit_dynamic_array_page_renderer :: proc(
    e: ^Emitter,
    elem_ty: string,
    depth := REPL_DEBUG_PAGE_DISCOVERY_DEPTH,
) -> string {
    remaining := REPL_DEBUG_PATH_LIMIT
    specs: [dynamic]Debug_Runtime_Collection_Spec
    defer delete(specs)
    debug_collect_runtime_collection_specs(
        e,
        &specs,
        elem_ty,
        "",
        "",
        &remaining,
    )
    child_renderers: [dynamic]string
    defer delete(child_renderers)
    page_name :=
        fmt.tprintf("kvist_debug_render_page_%d", e.temp_counter)
    e.temp_counter += 1
    emit_line(
        e,
        fmt.tprintf(
            `%s := proc "c" (collection_ctx: rawptr, offset, limit: int, emit_ctx: rawptr, emit: Kvist_Repl_Page_Emit, emit_collection: Kvist_Repl_Collection_Emit) -> int %c`,
            page_name,
            '{',
        ),
    )
    e.indent += 1
    emit_line(e, "context = repl_runtime.default_context()")
    emit_line(e, "_ = emit_collection")
    for spec in specs {
        if nested_elem_ty, dynamic_array :=
            dynamic_array_element_type(spec.ty);
           depth > 0 && dynamic_array {
            append(
                &child_renderers,
                debug_emit_dynamic_array_page_renderer(
                    e,
                    nested_elem_ty,
                    depth-1,
                ),
            )
        } else if nested_key_ty, nested_value_ty, is_map :=
            map_type_parts(spec.ty);
           depth > 0 && is_map &&
           debug_map_key_supported(nested_key_ty) {
            append(
                &child_renderers,
                debug_emit_map_page_renderer(
                    e,
                    nested_key_ty,
                    nested_value_ty,
                    depth-1,
                ),
            )
        } else {
            append(&child_renderers, "")
        }
    }
    emit_line(
        e,
        fmt.tprintf(
            "collection := transmute(^[dynamic]%s)collection_ctx",
            elem_ty,
        ),
    )
    emit_line(
        e,
        "page_start := min(max(offset, 0), len(collection^))",
    )
    emit_line(
        e,
        "page_end := min(page_start + max(limit, 0), len(collection^))",
    )
    emit_line(e, "for page_index in page_start..<page_end {")
    e.indent += 1
    rendered := debug_page_rendered_value_text(
        e,
        elem_ty,
        "collection^[page_index]",
    )
    emit_line(e, fmt.tprintf("page_value := %s", rendered))
    delete(rendered)
    emit_line(
        e,
        "emit(emit_ctx, page_index, Kvist_Repl_Rendered_Value{}, Kvist_Repl_Rendered_Value{data = raw_data(page_value), length = len(page_value)})",
    )
    emit_line(e, "delete(page_value)")
    for spec, spec_i in specs {
        child_renderer := child_renderers[spec_i]
        if child_renderer == "" {
            continue
        }
        relative_path_name :=
            fmt.tprintf(
                "kvist_debug_discovered_path_%d",
                e.temp_counter,
            )
        e.temp_counter += 1
        shape_name :=
            fmt.tprintf(
                "kvist_debug_discovered_shape_%d",
                e.temp_counter,
            )
        e.temp_counter += 1
        element_type_name :=
            fmt.tprintf(
                "kvist_debug_discovered_element_type_%d",
                e.temp_counter,
            )
        e.temp_counter += 1
        key_type_name :=
            fmt.tprintf(
                "kvist_debug_discovered_key_type_%d",
                e.temp_counter,
            )
        e.temp_counter += 1
        value_type_name :=
            fmt.tprintf(
                "kvist_debug_discovered_value_type_%d",
                e.temp_counter,
            )
        e.temp_counter += 1
        nested_elem_ty, dynamic_array :=
            dynamic_array_element_type(spec.ty)
        nested_key_ty, nested_value_ty, is_map :=
            map_type_parts(spec.ty)
        emit_line(
            e,
            fmt.tprintf(
                `%s := fmt.aprintf(%q, page_index)`,
                relative_path_name,
                fmt.tprintf("[%%d]%s", spec.path_suffix),
            ),
        )
        emit_line(
            e,
            fmt.tprintf(
                "%s: string = %q",
                shape_name,
                "dynamic-array" if dynamic_array else "map",
            ),
        )
        emit_line(
            e,
            fmt.tprintf(
                "%s: string = %q",
                element_type_name,
                nested_elem_ty if dynamic_array else "",
            ),
        )
        emit_line(
            e,
            fmt.tprintf(
                "%s: string = %q",
                key_type_name,
                nested_key_ty if is_map else "",
            ),
        )
        emit_line(
            e,
            fmt.tprintf(
                "%s: string = %q",
                value_type_name,
                nested_value_ty if is_map else "",
            ),
        )
        emit_line(
            e,
            fmt.tprintf(
                `emit_collection(emit_ctx, Kvist_Repl_Rendered_Value%cdata = raw_data(%s), length = len(%s)%c, Kvist_Repl_Rendered_Value%cdata = raw_data(%s), length = len(%s)%c, Kvist_Repl_Rendered_Value%cdata = raw_data(%s), length = len(%s)%c, Kvist_Repl_Rendered_Value%cdata = raw_data(%s), length = len(%s)%c, Kvist_Repl_Rendered_Value%cdata = raw_data(%s), length = len(%s)%c, rawptr(&collection^[page_index]%s), rawptr(%s), 0, 0)`,
                '{',
                relative_path_name,
                relative_path_name,
                '}',
                '{',
                shape_name,
                shape_name,
                '}',
                '{',
                element_type_name,
                element_type_name,
                '}',
                '{',
                key_type_name,
                key_type_name,
                '}',
                '{',
                value_type_name,
                value_type_name,
                '}',
                spec.target_suffix,
                child_renderer,
            ),
        )
        emit_line(e, fmt.tprintf("delete(%s)", relative_path_name))
    }
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return len(collection^)")
    e.indent -= 1
    emit_line(e, "}")
    return page_name
}

debug_emit_dynamic_array_page_descriptor :: proc(
    e: ^Emitter,
    descriptors_name: string,
    local: Param,
    elem_ty: string,
    target,
    path: string,
    context_by_reference := false,
    path_is_expression := false,
) {
    if local.debug_unavailable {
        return
    }
    page_name :=
        debug_emit_dynamic_array_page_renderer(e, elem_ty)
    context_name :=
        fmt.tprintf("kvist_debug_page_context_%d", e.temp_counter)
    e.temp_counter += 1
    path_name :=
        fmt.tprintf("kvist_debug_page_path_%d", e.temp_counter)
    e.temp_counter += 1
    shape_name :=
        fmt.tprintf("kvist_debug_page_shape_%d", e.temp_counter)
    e.temp_counter += 1
    element_type_name :=
        fmt.tprintf("kvist_debug_page_element_type_%d", e.temp_counter)
    e.temp_counter += 1
    key_type_name :=
        fmt.tprintf("kvist_debug_page_key_type_%d", e.temp_counter)
    e.temp_counter += 1
    value_type_name :=
        fmt.tprintf("kvist_debug_page_value_type_%d", e.temp_counter)
    e.temp_counter += 1
    guarded := local.owner_flag != ""
    if guarded {
        emit_line(
            e,
            fmt.tprintf("if %s %c", local.owner_flag, '{'),
        )
        e.indent += 1
    }
    if context_by_reference {
        emit_line(
            e,
            fmt.tprintf("%s := rawptr(&%s)", context_name, target),
        )
    } else {
        emit_line(
            e,
            fmt.tprintf("%s := %s", context_name, target),
        )
    }
    if path_is_expression {
        emit_line(e, fmt.tprintf("%s := %s", path_name, path))
    } else {
        emit_line(
            e,
            fmt.tprintf("%s: string = %q", path_name, path),
        )
    }
    emit_line(
        e,
        fmt.tprintf("%s: string = \"dynamic-array\"", shape_name),
    )
    emit_line(
        e,
        fmt.tprintf(
            "%s: string = %q",
            element_type_name,
            elem_ty,
        ),
    )
    emit_line(e, fmt.tprintf("%s: string = \"\"", key_type_name))
    emit_line(e, fmt.tprintf("%s: string = \"\"", value_type_name))
    context_expression :=
        context_name if context_by_reference else
            fmt.tprintf("rawptr(&%s)", context_name)
    emit_line(
        e,
        fmt.tprintf(
            `append(&%s, Kvist_Repl_Debug_Collection%cpath = %cdata = raw_data(%s), length = len(%s)%c, shape = %cdata = raw_data(%s), length = len(%s)%c, element_type = %cdata = raw_data(%s), length = len(%s)%c, key_type = %cdata = raw_data(%s), length = len(%s)%c, value_type = %cdata = raw_data(%s), length = len(%s)%c, collection_ctx = %s, render_page = %s%c)`,
            descriptors_name,
            '{',
            '{',
            path_name,
            path_name,
            '}',
            '{',
            shape_name,
            shape_name,
            '}',
            '{',
            element_type_name,
            element_type_name,
            '}',
            '{',
            key_type_name,
            key_type_name,
            '}',
            '{',
            value_type_name,
            value_type_name,
            '}',
            context_expression,
            page_name,
            '}',
        ),
    )
    if guarded {
        e.indent -= 1
        emit_line(e, "}")
    }
}

debug_emit_map_page_renderer :: proc(
    e: ^Emitter,
    key_ty,
    value_ty: string,
    depth := REPL_DEBUG_PAGE_DISCOVERY_DEPTH,
) -> string {
    remaining := REPL_DEBUG_PATH_LIMIT
    specs: [dynamic]Debug_Runtime_Collection_Spec
    defer delete(specs)
    debug_collect_runtime_collection_specs(
        e,
        &specs,
        value_ty,
        "",
        "",
        &remaining,
    )
    child_renderers: [dynamic]string
    defer delete(child_renderers)
    page_name :=
        fmt.tprintf("kvist_debug_render_page_%d", e.temp_counter)
    e.temp_counter += 1
    keys_name :=
        fmt.tprintf("kvist_debug_page_keys_%d", e.temp_counter)
    e.temp_counter += 1
    candidate_name :=
        fmt.tprintf("kvist_debug_page_key_%d", e.temp_counter)
    e.temp_counter += 1
    insert_name :=
        fmt.tprintf("kvist_debug_page_insert_%d", e.temp_counter)
    e.temp_counter += 1
    index_name :=
        fmt.tprintf("kvist_debug_page_key_index_%d", e.temp_counter)
    e.temp_counter += 1
    shift_name :=
        fmt.tprintf("kvist_debug_page_shift_%d", e.temp_counter)
    e.temp_counter += 1
    emit_line(
        e,
        fmt.tprintf(
            `%s := proc "c" (collection_ctx: rawptr, offset, limit: int, emit_ctx: rawptr, emit: Kvist_Repl_Page_Emit, emit_collection: Kvist_Repl_Collection_Emit) -> int %c`,
            page_name,
            '{',
        ),
    )
    e.indent += 1
    emit_line(e, "context = repl_runtime.default_context()")
    emit_line(e, "_ = emit_collection")
    for spec in specs {
        if nested_elem_ty, dynamic_array :=
            dynamic_array_element_type(spec.ty);
           depth > 0 && dynamic_array {
            append(
                &child_renderers,
                debug_emit_dynamic_array_page_renderer(
                    e,
                    nested_elem_ty,
                    depth-1,
                ),
            )
        } else if nested_key_ty, nested_value_ty, is_map :=
            map_type_parts(spec.ty);
           depth > 0 && is_map &&
           debug_map_key_supported(nested_key_ty) {
            append(
                &child_renderers,
                debug_emit_map_page_renderer(
                    e,
                    nested_key_ty,
                    nested_value_ty,
                    depth-1,
                ),
            )
        } else {
            append(&child_renderers, "")
        }
    }
    emit_line(
        e,
        fmt.tprintf(
            "collection := transmute(^map[%s]%s)collection_ctx",
            key_ty,
            value_ty,
        ),
    )
    emit_line(
        e,
        "page_start := min(max(offset, 0), len(collection^))",
    )
    emit_line(
        e,
        "page_end := min(page_start + max(limit, 0), len(collection^))",
    )
    emit_line(
        e,
        fmt.tprintf(
            "%s := make([dynamic]%s, 0, page_end)",
            keys_name,
            key_ty,
        ),
    )
    emit_line(e, fmt.tprintf("defer delete(%s)", keys_name))
    emit_line(
        e,
        fmt.tprintf(
            "for %s, _ in collection^ %c",
            candidate_name,
            '{',
        ),
    )
    e.indent += 1
    emit_line(
        e,
        fmt.tprintf("%s := len(%s)", insert_name, keys_name),
    )
    emit_line(
        e,
        fmt.tprintf(
            "for %s in 0..<len(%s) %c",
            index_name,
            keys_name,
            '{',
        ),
    )
    e.indent += 1
    less_text := fmt.tprintf(
        "%s < %s[%s]",
        candidate_name,
        keys_name,
        index_name,
    )
    if key_ty == "bool" {
        less_text = fmt.tprintf(
            "!%s && %s[%s]",
            candidate_name,
            keys_name,
            index_name,
        )
    }
    emit_line(e, fmt.tprintf("if %s %c", less_text, '{'))
    e.indent += 1
    emit_line(
        e,
        fmt.tprintf("%s = %s", insert_name, index_name),
    )
    emit_line(e, "break")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(
        e,
        fmt.tprintf("if %s < page_end %c", insert_name, '{'),
    )
    e.indent += 1
    emit_line(
        e,
        fmt.tprintf("if len(%s) < page_end %c", keys_name, '{'),
    )
    e.indent += 1
    emit_line(
        e,
        fmt.tprintf("append(&%s, %s)", keys_name, candidate_name),
    )
    e.indent -= 1
    emit_line(e, "}")
    emit_line(
        e,
        fmt.tprintf(
            "for %s := len(%s)-1; %s > %s; %s -= 1 %c",
            shift_name,
            keys_name,
            shift_name,
            insert_name,
            shift_name,
            '{',
        ),
    )
    e.indent += 1
    emit_line(
        e,
        fmt.tprintf(
            "%s[%s] = %s[%s-1]",
            keys_name,
            shift_name,
            keys_name,
            shift_name,
        ),
    )
    e.indent -= 1
    emit_line(e, "}")
    emit_line(
        e,
        fmt.tprintf(
            "%s[%s] = %s",
            keys_name,
            insert_name,
            candidate_name,
        ),
    )
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "for page_index in page_start..<page_end {")
    e.indent += 1
    emit_line(
        e,
        fmt.tprintf(
            "page_key_value := %s[page_index]",
            keys_name,
        ),
    )
    key_format := "%s" if key_ty == "string" else "%v"
    emit_line(
        e,
        fmt.tprintf(
            "page_key := fmt.aprintf(%q, page_key_value)",
            key_format,
        ),
    )
    rendered := debug_page_rendered_value_text(
        e,
        value_ty,
        "collection^[page_key_value]",
    )
    emit_line(e, fmt.tprintf("page_value := %s", rendered))
    delete(rendered)
    emit_line(
        e,
        "emit(emit_ctx, page_index, Kvist_Repl_Rendered_Value{data = raw_data(page_key), length = len(page_key)}, Kvist_Repl_Rendered_Value{data = raw_data(page_value), length = len(page_value)})",
    )
    for spec, spec_i in specs {
        child_renderer := child_renderers[spec_i]
        if child_renderer == "" {
            continue
        }
        relative_path_name :=
            fmt.tprintf(
                "kvist_debug_discovered_path_%d",
                e.temp_counter,
            )
        e.temp_counter += 1
        shape_name :=
            fmt.tprintf(
                "kvist_debug_discovered_shape_%d",
                e.temp_counter,
            )
        e.temp_counter += 1
        element_type_name :=
            fmt.tprintf(
                "kvist_debug_discovered_element_type_%d",
                e.temp_counter,
            )
        e.temp_counter += 1
        key_type_name :=
            fmt.tprintf(
                "kvist_debug_discovered_key_type_%d",
                e.temp_counter,
            )
        e.temp_counter += 1
        value_type_name :=
            fmt.tprintf(
                "kvist_debug_discovered_value_type_%d",
                e.temp_counter,
            )
        e.temp_counter += 1
        context_value_name :=
            fmt.tprintf(
                "kvist_debug_discovered_context_%d",
                e.temp_counter,
            )
        e.temp_counter += 1
        nested_elem_ty, dynamic_array :=
            dynamic_array_element_type(spec.ty)
        nested_key_ty, nested_value_ty, is_map :=
            map_type_parts(spec.ty)
        relative_key_format := "%q" if key_ty == "string" else "%v"
        emit_line(
            e,
            fmt.tprintf(
                `%s := fmt.aprintf(%q, page_key_value)`,
                relative_path_name,
                fmt.tprintf(
                    "[%s]%s",
                    relative_key_format,
                    spec.path_suffix,
                ),
            ),
        )
        emit_line(
            e,
            fmt.tprintf(
                "%s: string = %q",
                shape_name,
                "dynamic-array" if dynamic_array else "map",
            ),
        )
        emit_line(
            e,
            fmt.tprintf(
                "%s: string = %q",
                element_type_name,
                nested_elem_ty if dynamic_array else "",
            ),
        )
        emit_line(
            e,
            fmt.tprintf(
                "%s: string = %q",
                key_type_name,
                nested_key_ty if is_map else "",
            ),
        )
        emit_line(
            e,
            fmt.tprintf(
                "%s: string = %q",
                value_type_name,
                nested_value_ty if is_map else "",
            ),
        )
        emit_line(
            e,
            fmt.tprintf(
                "%s := collection^[page_key_value]%s",
                context_value_name,
                spec.target_suffix,
            ),
        )
        emit_line(
            e,
            fmt.tprintf(
                `emit_collection(emit_ctx, Kvist_Repl_Rendered_Value%cdata = raw_data(%s), length = len(%s)%c, Kvist_Repl_Rendered_Value%cdata = raw_data(%s), length = len(%s)%c, Kvist_Repl_Rendered_Value%cdata = raw_data(%s), length = len(%s)%c, Kvist_Repl_Rendered_Value%cdata = raw_data(%s), length = len(%s)%c, Kvist_Repl_Rendered_Value%cdata = raw_data(%s), length = len(%s)%c, rawptr(&%s), rawptr(%s), size_of(%s), align_of(%s))`,
                '{',
                relative_path_name,
                relative_path_name,
                '}',
                '{',
                shape_name,
                shape_name,
                '}',
                '{',
                element_type_name,
                element_type_name,
                '}',
                '{',
                key_type_name,
                key_type_name,
                '}',
                '{',
                value_type_name,
                value_type_name,
                '}',
                context_value_name,
                child_renderer,
                spec.ty,
                spec.ty,
            ),
        )
        emit_line(e, fmt.tprintf("delete(%s)", relative_path_name))
    }
    emit_line(e, "delete(page_key)")
    emit_line(e, "delete(page_value)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return len(collection^)")
    e.indent -= 1
    emit_line(e, "}")
    return page_name
}

debug_emit_map_page_descriptor :: proc(
    e: ^Emitter,
    descriptors_name: string,
    local: Param,
    key_ty,
    value_ty,
    target,
    path: string,
    context_by_reference := false,
    path_is_expression := false,
) {
    if local.debug_unavailable || !debug_map_key_supported(key_ty) {
        return
    }
    page_name :=
        debug_emit_map_page_renderer(e, key_ty, value_ty)
    context_name :=
        fmt.tprintf("kvist_debug_page_context_%d", e.temp_counter)
    e.temp_counter += 1
    path_name :=
        fmt.tprintf("kvist_debug_page_path_%d", e.temp_counter)
    e.temp_counter += 1
    shape_name :=
        fmt.tprintf("kvist_debug_page_shape_%d", e.temp_counter)
    e.temp_counter += 1
    element_type_name :=
        fmt.tprintf("kvist_debug_page_element_type_%d", e.temp_counter)
    e.temp_counter += 1
    key_type_name :=
        fmt.tprintf("kvist_debug_page_key_type_%d", e.temp_counter)
    e.temp_counter += 1
    value_type_name :=
        fmt.tprintf("kvist_debug_page_value_type_%d", e.temp_counter)
    e.temp_counter += 1
    guarded := local.owner_flag != ""
    if guarded {
        emit_line(
            e,
            fmt.tprintf("if %s %c", local.owner_flag, '{'),
        )
        e.indent += 1
    }
    if context_by_reference {
        emit_line(
            e,
            fmt.tprintf("%s := rawptr(&%s)", context_name, target),
        )
    } else {
        emit_line(e, fmt.tprintf("%s := %s", context_name, target))
    }
    if path_is_expression {
        emit_line(e, fmt.tprintf("%s := %s", path_name, path))
    } else {
        emit_line(e, fmt.tprintf("%s: string = %q", path_name, path))
    }
    emit_line(e, fmt.tprintf("%s: string = \"map\"", shape_name))
    emit_line(e, fmt.tprintf("%s: string = \"\"", element_type_name))
    emit_line(e, fmt.tprintf("%s: string = %q", key_type_name, key_ty))
    emit_line(
        e,
        fmt.tprintf("%s: string = %q", value_type_name, value_ty),
    )
    context_expression :=
        context_name if context_by_reference else
            fmt.tprintf("rawptr(&%s)", context_name)
    emit_line(
        e,
        fmt.tprintf(
            `append(&%s, Kvist_Repl_Debug_Collection%cpath = %cdata = raw_data(%s), length = len(%s)%c, shape = %cdata = raw_data(%s), length = len(%s)%c, element_type = %cdata = raw_data(%s), length = len(%s)%c, key_type = %cdata = raw_data(%s), length = len(%s)%c, value_type = %cdata = raw_data(%s), length = len(%s)%c, collection_ctx = %s, render_page = %s%c)`,
            descriptors_name,
            '{',
            '{',
            path_name,
            path_name,
            '}',
            '{',
            shape_name,
            shape_name,
            '}',
            '{',
            element_type_name,
            element_type_name,
            '}',
            '{',
            key_type_name,
            key_type_name,
            '}',
            '{',
            value_type_name,
            value_type_name,
            '}',
            context_expression,
            page_name,
            '}',
        ),
    )
    if guarded {
        e.indent -= 1
        emit_line(e, "}")
    }
}

Debug_Runtime_Collection_Spec :: struct {
    ty:            string,
    target_suffix: string,
    path_suffix:   string,
}

debug_collect_runtime_collection_specs :: proc(
    e: ^Emitter,
    specs: ^[dynamic]Debug_Runtime_Collection_Spec,
    ty,
    target_suffix,
    path_suffix: string,
    remaining: ^int,
) {
    if _, dynamic_array := dynamic_array_element_type(ty);
       dynamic_array {
        append(specs, Debug_Runtime_Collection_Spec{
            ty = ty,
            target_suffix = target_suffix,
            path_suffix = path_suffix,
        })
        return
    }
    if _, _, is_map := map_type_parts(ty); is_map {
        append(specs, Debug_Runtime_Collection_Spec{
            ty = ty,
            target_suffix = target_suffix,
            path_suffix = path_suffix,
        })
        return
    }
    if struct_decl, ok := find_struct_decl(e, ty); ok {
        for field in struct_decl.fields {
            if remaining^ == 0 {
                break
            }
            remaining^ -= 1
            debug_collect_runtime_collection_specs(
                e,
                specs,
                field.ty,
                fmt.tprintf("%s.%s", target_suffix, field.name),
                fmt.tprintf(
                    "%s.%s",
                    path_suffix,
                    debug_struct_field_name(field),
                ),
                remaining,
            )
        }
    } else if elem_ty, length, ok_array :=
        debug_fixed_array_parts(ty); ok_array {
        for i in 0..<length {
            if remaining^ == 0 {
                break
            }
            remaining^ -= 1
            debug_collect_runtime_collection_specs(
                e,
                specs,
                elem_ty,
                fmt.tprintf("%s[%d]", target_suffix, i),
                fmt.tprintf("%s[%d]", path_suffix, i),
                remaining,
            )
        }
    }
}

debug_emit_sorted_map_keys :: proc(
    e: ^Emitter,
    map_target,
    key_ty: string,
    capture_limit: int,
) -> string {
    keys_name :=
        fmt.tprintf("kvist_debug_runtime_keys_%d", e.temp_counter)
    e.temp_counter += 1
    candidate_name :=
        fmt.tprintf("kvist_debug_runtime_key_%d", e.temp_counter)
    e.temp_counter += 1
    insert_name :=
        fmt.tprintf("kvist_debug_runtime_insert_%d", e.temp_counter)
    e.temp_counter += 1
    index_name :=
        fmt.tprintf(
            "kvist_debug_runtime_key_index_%d",
            e.temp_counter,
        )
    e.temp_counter += 1
    shift_name :=
        fmt.tprintf("kvist_debug_runtime_shift_%d", e.temp_counter)
    e.temp_counter += 1
    emit_line(
        e,
        fmt.tprintf(
            "%s := make([dynamic]%s, 0, %d)",
            keys_name,
            key_ty,
            capture_limit,
        ),
    )
    emit_line(e, fmt.tprintf("defer delete(%s)", keys_name))
    emit_line(
        e,
        fmt.tprintf(
            "for %s, _ in %s %c",
            candidate_name,
            map_target,
            '{',
        ),
    )
    e.indent += 1
    emit_line(
        e,
        fmt.tprintf("%s := len(%s)", insert_name, keys_name),
    )
    emit_line(
        e,
        fmt.tprintf(
            "for %s in 0..<len(%s) %c",
            index_name,
            keys_name,
            '{',
        ),
    )
    e.indent += 1
    less_text := fmt.tprintf(
        "%s < %s[%s]",
        candidate_name,
        keys_name,
        index_name,
    )
    if key_ty == "bool" {
        less_text = fmt.tprintf(
            "!%s && %s[%s]",
            candidate_name,
            keys_name,
            index_name,
        )
    }
    emit_line(e, fmt.tprintf("if %s %c", less_text, '{'))
    e.indent += 1
    emit_line(
        e,
        fmt.tprintf("%s = %s", insert_name, index_name),
    )
    emit_line(e, "break")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(
        e,
        fmt.tprintf(
            "if %s < %d %c",
            insert_name,
            capture_limit,
            '{',
        ),
    )
    e.indent += 1
    emit_line(
        e,
        fmt.tprintf(
            "if len(%s) < %d %c",
            keys_name,
            capture_limit,
            '{',
        ),
    )
    e.indent += 1
    emit_line(
        e,
        fmt.tprintf("append(&%s, %s)", keys_name, candidate_name),
    )
    e.indent -= 1
    emit_line(e, "}")
    emit_line(
        e,
        fmt.tprintf(
            "for %s := len(%s)-1; %s > %s; %s -= 1 %c",
            shift_name,
            keys_name,
            shift_name,
            insert_name,
            shift_name,
            '{',
        ),
    )
    e.indent += 1
    emit_line(
        e,
        fmt.tprintf(
            "%s[%s] = %s[%s-1]",
            keys_name,
            shift_name,
            keys_name,
            shift_name,
        ),
    )
    e.indent -= 1
    emit_line(e, "}")
    emit_line(
        e,
        fmt.tprintf(
            "%s[%s] = %s",
            keys_name,
            insert_name,
            candidate_name,
        ),
    )
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    return keys_name
}

debug_emit_map_value_page_descriptors :: proc(
    e: ^Emitter,
    descriptors_name: string,
    local: Param,
    key_ty,
    value_ty,
    map_target,
    map_path: string,
) {
    if local.debug_unavailable || !debug_map_key_supported(key_ty) {
        return
    }
    remaining := REPL_DEBUG_DYNAMIC_ARRAY_LIMIT-1
    specs: [dynamic]Debug_Runtime_Collection_Spec
    defer delete(specs)
    debug_collect_runtime_collection_specs(
        e,
        &specs,
        value_ty,
        "",
        "",
        &remaining,
    )
    if len(specs) == 0 {
        return
    }
    value_remaining := REPL_DEBUG_DYNAMIC_ARRAY_LIMIT-1
    value_path_count :=
        debug_child_value_count(e, value_ty, &value_remaining)
    capture_limit :=
        max(
            1,
            REPL_DEBUG_DYNAMIC_ARRAY_LIMIT/
                (1+value_path_count),
        )
    paths_name :=
        fmt.tprintf("kvist_debug_runtime_paths_%d", e.temp_counter)
    e.temp_counter += 1
    emit_line(
        e,
        fmt.tprintf(
            "%s := make([dynamic]string, 0, %d)",
            paths_name,
            capture_limit*len(specs),
        ),
    )
    emit_line(e, "defer {")
    e.indent += 1
    emit_line(
        e,
        fmt.tprintf(
            "for path in %s %c delete(path) %c",
            paths_name,
            '{',
            '}',
        ),
    )
    emit_line(e, fmt.tprintf("delete(%s)", paths_name))
    e.indent -= 1
    emit_line(e, "}")
    pools: [dynamic]string
    defer delete(pools)
    for spec in specs {
        pool_name :=
            fmt.tprintf("kvist_debug_runtime_pool_%d", e.temp_counter)
        e.temp_counter += 1
        append(&pools, pool_name)
        emit_line(
            e,
            fmt.tprintf(
                "%s := make([dynamic]%s, 0, %d)",
                pool_name,
                spec.ty,
                capture_limit,
            ),
        )
        emit_line(e, fmt.tprintf("defer delete(%s)", pool_name))
    }
    guarded := local.owner_flag != ""
    if guarded {
        emit_line(
            e,
            fmt.tprintf("if %s %c", local.owner_flag, '{'),
        )
        e.indent += 1
    }
    keys_name := debug_emit_sorted_map_keys(
        e,
        map_target,
        key_ty,
        capture_limit,
    )
    key_name :=
        fmt.tprintf("kvist_debug_runtime_value_key_%d", e.temp_counter)
    e.temp_counter += 1
    emit_line(
        e,
        fmt.tprintf("for %s in %s %c", key_name, keys_name, '{'),
    )
    e.indent += 1
    for spec, spec_i in specs {
        emit_line(
            e,
            fmt.tprintf(
                "append(&%s, %s[%s]%s)",
                pools[spec_i],
                map_target,
                key_name,
                spec.target_suffix,
            ),
        )
        path_value_name :=
            fmt.tprintf(
                "kvist_debug_runtime_path_%d",
                e.temp_counter,
            )
        e.temp_counter += 1
        key_format := "%q" if key_ty == "string" else "%v"
        emit_line(
            e,
            fmt.tprintf(
                `%s := fmt.aprintf(%q, %s)`,
                path_value_name,
                fmt.tprintf(
                    "%s[%s]%s",
                    map_path,
                    key_format,
                    spec.path_suffix,
                ),
                key_name,
            ),
        )
        emit_line(
            e,
            fmt.tprintf("append(&%s, %s)", paths_name, path_value_name),
        )
        target :=
            fmt.tprintf(
                "%s[len(%s)-1]",
                pools[spec_i],
                pools[spec_i],
            )
        path :=
            fmt.tprintf(
                "%s[len(%s)-1]",
                paths_name,
                paths_name,
            )
        if nested_elem_ty, dynamic_array :=
            dynamic_array_element_type(spec.ty);
           dynamic_array {
            debug_emit_dynamic_array_page_descriptor(
                e,
                descriptors_name,
                local,
                nested_elem_ty,
                target,
                path,
                true,
                true,
            )
        } else if nested_key_ty, nested_value_ty, is_map :=
            map_type_parts(spec.ty);
           is_map {
            debug_emit_map_page_descriptor(
                e,
                descriptors_name,
                local,
                nested_key_ty,
                nested_value_ty,
                target,
                path,
                true,
                true,
            )
        }
    }
    e.indent -= 1
    emit_line(e, "}")
    if guarded {
        e.indent -= 1
        emit_line(e, "}")
    }
}

debug_emit_dynamic_element_page_descriptors :: proc(
    e: ^Emitter,
    descriptors_name: string,
    local: Param,
    elem_ty: string,
    array_target,
    array_path: string,
) {
    remaining := REPL_DEBUG_DYNAMIC_ARRAY_LIMIT-1
    specs: [dynamic]Debug_Runtime_Collection_Spec
    defer delete(specs)
    debug_collect_runtime_collection_specs(
        e,
        &specs,
        elem_ty,
        "",
        "",
        &remaining,
    )
    if len(specs) == 0 || local.debug_unavailable {
        return
    }
    element_remaining := REPL_DEBUG_DYNAMIC_ARRAY_LIMIT-1
    element_path_count :=
        debug_child_value_count(e, elem_ty, &element_remaining)
    capture_limit :=
        max(
            1,
            REPL_DEBUG_DYNAMIC_ARRAY_LIMIT/
                (1+element_path_count),
        )
    paths_name :=
        fmt.tprintf("kvist_debug_runtime_paths_%d", e.temp_counter)
    e.temp_counter += 1
    emit_line(
        e,
        fmt.tprintf(
            "%s := make([dynamic]string, 0, %d)",
            paths_name,
            capture_limit*len(specs),
        ),
    )
    emit_line(e, "defer {")
    e.indent += 1
    emit_line(
        e,
        fmt.tprintf(
            "for path in %s %c delete(path) %c",
            paths_name,
            '{',
            '}',
        ),
    )
    emit_line(e, fmt.tprintf("delete(%s)", paths_name))
    e.indent -= 1
    emit_line(e, "}")
    pools: [dynamic]string
    defer delete(pools)
    for spec in specs {
        pool_name :=
            fmt.tprintf("kvist_debug_runtime_pool_%d", e.temp_counter)
        e.temp_counter += 1
        append(&pools, pool_name)
        emit_line(
            e,
            fmt.tprintf(
                "%s := make([dynamic]%s, 0, %d)",
                pool_name,
                spec.ty,
                capture_limit,
            ),
        )
        emit_line(e, fmt.tprintf("defer delete(%s)", pool_name))
    }
    guarded := local.owner_flag != ""
    if guarded {
        emit_line(
            e,
            fmt.tprintf("if %s %c", local.owner_flag, '{'),
        )
        e.indent += 1
    }
    index_name :=
        fmt.tprintf("kvist_debug_runtime_index_%d", e.temp_counter)
    e.temp_counter += 1
    emit_line(
        e,
        fmt.tprintf(
            "for %s in 0..<min(len(%s), %d) %c",
            index_name,
            array_target,
            capture_limit,
            '{',
        ),
    )
    e.indent += 1
    for spec, spec_i in specs {
        emit_line(
            e,
            fmt.tprintf(
                "append(&%s, %s[%s]%s)",
                pools[spec_i],
                array_target,
                index_name,
                spec.target_suffix,
            ),
        )
        path_value_name :=
            fmt.tprintf(
                "kvist_debug_runtime_path_%d",
                e.temp_counter,
            )
        e.temp_counter += 1
        emit_line(
            e,
            fmt.tprintf(
                `%s := fmt.aprintf(%q, %s)`,
                path_value_name,
                fmt.tprintf(
                    "%s[%%d]%s",
                    array_path,
                    spec.path_suffix,
                ),
                index_name,
            ),
        )
        emit_line(
            e,
            fmt.tprintf("append(&%s, %s)", paths_name, path_value_name),
        )
        target :=
            fmt.tprintf(
                "%s[len(%s)-1]",
                pools[spec_i],
                pools[spec_i],
            )
        path :=
            fmt.tprintf(
                "%s[len(%s)-1]",
                paths_name,
                paths_name,
            )
        if nested_elem_ty, dynamic_array :=
            dynamic_array_element_type(spec.ty);
           dynamic_array {
            debug_emit_dynamic_array_page_descriptor(
                e,
                descriptors_name,
                local,
                nested_elem_ty,
                target,
                path,
                true,
                true,
            )
        } else if key_ty, value_ty, is_map :=
            map_type_parts(spec.ty);
           is_map {
            debug_emit_map_page_descriptor(
                e,
                descriptors_name,
                local,
                key_ty,
                value_ty,
                target,
                path,
                true,
                true,
            )
        }
    }
    e.indent -= 1
    emit_line(e, "}")
    if guarded {
        e.indent -= 1
        emit_line(e, "}")
    }
}

debug_emit_nested_page_descriptors :: proc(
    e: ^Emitter,
    descriptors_name: string,
    local: Param,
    ty,
    target_prefix,
    path_prefix: string,
    remaining: ^int,
) {
    if struct_decl, ok := find_struct_decl(e, ty); ok {
        for field in struct_decl.fields {
            if remaining^ == 0 {
                break
            }
            remaining^ -= 1
            target :=
                fmt.tprintf("%s.%s", target_prefix, field.name)
            source_name := debug_struct_field_name(field)
            path :=
                fmt.tprintf("%s.%s", path_prefix, source_name)
            if elem_ty, dynamic_array :=
                dynamic_array_element_type(field.ty);
               dynamic_array {
                debug_emit_dynamic_array_page_descriptor(
                    e,
                    descriptors_name,
                    local,
                    elem_ty,
                    target,
                    path,
                )
                debug_emit_dynamic_element_page_descriptors(
                    e,
                    descriptors_name,
                    local,
                    elem_ty,
                    target,
                    path,
                )
            } else if key_ty, value_ty, is_map :=
                map_type_parts(field.ty);
               is_map {
                debug_emit_map_page_descriptor(
                    e,
                    descriptors_name,
                    local,
                    key_ty,
                    value_ty,
                    target,
                    path,
                )
                debug_emit_map_value_page_descriptors(
                    e,
                    descriptors_name,
                    local,
                    key_ty,
                    value_ty,
                    target,
                    path,
                )
            } else {
                debug_emit_nested_page_descriptors(
                    e,
                    descriptors_name,
                    local,
                    field.ty,
                    target,
                    path,
                    remaining,
                )
            }
        }
    } else if elem_ty, length, ok_array :=
        debug_fixed_array_parts(ty); ok_array {
        for i in 0..<length {
            if remaining^ == 0 {
                break
            }
            remaining^ -= 1
            target := fmt.tprintf("%s[%d]", target_prefix, i)
            path := fmt.tprintf("%s[%d]", path_prefix, i)
            if nested_elem_ty, dynamic_array :=
                dynamic_array_element_type(elem_ty);
               dynamic_array {
                debug_emit_dynamic_array_page_descriptor(
                    e,
                    descriptors_name,
                    local,
                    nested_elem_ty,
                    target,
                    path,
                )
                debug_emit_dynamic_element_page_descriptors(
                    e,
                    descriptors_name,
                    local,
                    nested_elem_ty,
                    target,
                    path,
                )
            } else if key_ty, value_ty, is_map :=
                map_type_parts(elem_ty);
               is_map {
                debug_emit_map_page_descriptor(
                    e,
                    descriptors_name,
                    local,
                    key_ty,
                    value_ty,
                    target,
                    path,
                )
                debug_emit_map_value_page_descriptors(
                    e,
                    descriptors_name,
                    local,
                    key_ty,
                    value_ty,
                    target,
                    path,
                )
            } else {
                debug_emit_nested_page_descriptors(
                    e,
                    descriptors_name,
                    local,
                    elem_ty,
                    target,
                    path,
                    remaining,
                )
            }
        }
    }
}

mark_debug_local_unavailable :: proc(e: ^Emitter, name: string) {
    for i := len(e.local_types)-1; i >= 0; i -= 1 {
        if e.local_types[i].name == name {
            e.local_types[i].debug_unavailable = true
            return
        }
    }
}

emit_runtime_type_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 2 {
        return "", Compile_Error{message = "type expects one value", span = form.span}, false
    }

    value_form := form.items[1]
    value_ty := ""
    value := ""
    owned := false
    value_ty_owned := false
    symbol_name := ""
    defer if value_ty_owned { delete(value_ty) }
    defer if symbol_name != "" { delete(symbol_name) }

    if value_form.kind == .Symbol {
        symbol_name = map_name(value_form.text)
        if proc_decl, ok_proc := find_proc_decl(e, symbol_name); ok_proc {
            if !repl_proc_is_concrete(proc_decl) {
                return "", Compile_Error{
                    message = "type needs a specialized concrete function",
                    span = value_form.span,
                }, false
            }
            value_ty = proc_decl_type_text(proc_decl)
            value_ty_owned = true
            value = symbol_name
        } else if def_call_head_is_declared_type(e, symbol_name) ||
                  type_text_is_builtin_odin_scalar(symbol_name) ||
                  symbol_name == "typeid" ||
                  symbol_tail_starts_upper(value_form.text) {
            mark_keyword_type(e)
            return fmt.tprintf(
                "(proc(kvist_type_id: typeid) -> keyword {{ _ = kvist_type_id; return keyword(%q) }})(typeid_of(%s))",
                "typeid",
                symbol_name,
            ), {}, true
        }
    }

    if value_ty == "" &&
       value_form.kind == .List &&
       len(value_form.items) > 0 &&
       is_symbol(value_form.items[0], "fn") {
        parsed, err_parse, ok_parse := parse_proc_literal_form(value_form)
        if !ok_parse {
            return "", err_parse, false
        }
        value_ty = proc_literal_type_text(parsed)
        value_ty_owned = true
        value_text, err_value, ok_value := emit_expr(e, value_form)
        if !ok_value {
            return "", err_value, false
        }
        value = value_text
    }

    if value_ty != "" {
        // A concrete procedure is a first-class value whose complete
        // signature is known from its declaration or literal.
    } else if value_form.kind == .Vector ||
       value_form.kind == .Brace ||
       value_form.kind == .Set {
        err_value: Compile_Error
        ok_value: bool
        value, owned, err_value, ok_value =
            emit_contextual_data_value(e, value_form)
        if !ok_value {
            return "", err_value, false
        }
        value_ty = "Data"
    } else {
        inferred_ty, inferred := obvious_form_type(e, value_form)
        if !inferred {
            return "", Compile_Error{
                message = "type needs a statically known value type",
                span = value_form.span,
            }, false
        }
        value_ty = inferred_ty
        value_text, err_value, ok_value := emit_expr(e, value_form)
        if !ok_value {
            return "", err_value, false
        }
        value = value_text
        owned =
            form_produces_owned_managed_type(e, value_form, value_ty)
    }

    mark_keyword_type(e)
    if type_text_is_managed_value(e, value_ty) {
        mark_data_type(e)
        cleanup := ""
        if owned {
            cleanup = "defer kvist_data_release(kvist_type_value); "
        }
        return fmt.tprintf(
            "(proc(kvist_type_value: Data) -> keyword {{ %sreturn kvist_data_type(kvist_type_value) }})(%s)",
            cleanup,
            value,
        ), {}, true
    }

    cleanup := ""
    if owned {
        cleanup = fmt.tprintf(
            "defer %s; ",
            managed_destroy_value_text(e, value_ty, "kvist_type_value"),
        )
    }
    display_ty := surface_type_text(value_ty)
    return fmt.tprintf(
        "(proc(kvist_type_value: %s) -> keyword {{ %s_ = kvist_type_value; return keyword(%q) }})(%s)",
        value_ty,
        cleanup,
        display_ty,
        value,
    ), {}, true
}

debug_emit_proc_frame_scope :: proc(e: ^Emitter) {
    if !e.repl_debug_enabled {
        return
    }
    emit_line(
        e,
        "kvist_repl_host.enter_frame(kvist_repl_host.ctx)",
    )
    emit_line(
        e,
        "defer kvist_repl_host.leave_frame(kvist_repl_host.ctx)",
    )
}

debug_emit_pause :: proc(
    e: ^Emitter,
    form: CST_Form,
    required: bool,
    condition_message := "",
    condition_data := "",
    condition_value_type := "",
    restart_selection_name := "",
    condition_restart_flags: u32 = 1,
    condition_type := "kvist/condition",
) {
    placeholder := debug_pause_placeholder(e, form.span)
    defer delete(placeholder)
    visible := debug_visible_local_indices(e)
    defer delete(visible)
    required_text := "true" if required else "false"
    restart_selection_text := "nil"
    if restart_selection_name != "" {
        restart_selection_text =
            fmt.tprintf("&%s", restart_selection_name)
    }
    if condition_message != "" {
        condition_type_name :=
            fmt.tprintf("kvist_condition_type_%d", e.temp_counter)
        e.temp_counter += 1
        condition_message_name :=
            fmt.tprintf("kvist_condition_message_%d", e.temp_counter)
        e.temp_counter += 1
        condition_data_name :=
            fmt.tprintf("kvist_condition_data_rendered_%d", e.temp_counter)
        e.temp_counter += 1
        condition_value_type_name :=
            fmt.tprintf(
                "kvist_condition_value_type_%d",
                e.temp_counter,
            )
        e.temp_counter += 1
        emit_line(
            e,
            fmt.tprintf(
                "%s: string = %q",
                condition_type_name,
                condition_type,
            ),
        )
        emit_line(
            e,
            fmt.tprintf(
                "%s: string = %s",
                condition_message_name,
                condition_message,
            ),
        )
        if condition_data == "" {
            emit_line(e, fmt.tprintf("%s: string", condition_data_name))
        } else {
            mark_data_type(e)
            emit_line(
                e,
                fmt.tprintf(
                    "%s := kvist_data_repr(%s)",
                    condition_data_name,
                    condition_data,
                ),
            )
            emit_line(e, fmt.tprintf("defer delete(%s)", condition_data_name))
        }
        emit_line(
            e,
            fmt.tprintf(
                "%s: string = %q",
                condition_value_type_name,
                condition_value_type,
            ),
        )
        emit_line_mapped(
            e,
            fmt.tprintf(
                "kvist_repl_host.condition(kvist_repl_host.ctx, %q, Kvist_Repl_Rendered_Value%cdata = raw_data(%s), length = len(%s)%c, Kvist_Repl_Rendered_Value%cdata = raw_data(%s), length = len(%s)%c, Kvist_Repl_Rendered_Value%cdata = raw_data(%s), length = len(%s)%c, Kvist_Repl_Rendered_Value%cdata = raw_data(%s), length = len(%s)%c, %d)",
                placeholder,
                '{',
                condition_type_name,
                condition_type_name,
                '}',
                '{',
                condition_message_name,
                condition_message_name,
                '}',
                '{',
                condition_data_name,
                condition_data_name,
                '}',
                '{',
                condition_value_type_name,
                condition_value_type_name,
                '}',
                condition_restart_flags,
            ),
            form.span,
        )
    }
    flags_name :=
        fmt.tprintf("kvist_debug_flags_%d", e.temp_counter)
    e.temp_counter += 1
    emit_line(
        e,
        fmt.tprintf(
            "%s := kvist_repl_host.debug_flags(kvist_repl_host.ctx)",
            flags_name,
        ),
    )
    emit_line_mapped(
        e,
        fmt.tprintf(
            "if %s & u32(2) != 0 %c kvist_repl_host.trace_point(kvist_repl_host.ctx, %q) %c",
            flags_name,
            '{',
            placeholder,
            '}',
        ),
        form.span,
    )
    debug_emit_trace_values(
        e,
        visible[:],
        flags_name,
        placeholder,
    )
    if !required {
        emit_line(
            e,
            fmt.tprintf(
                "if %s & u32(1) != 0 %c",
                flags_name,
                '{',
            ),
        )
        e.indent += 1
    }
    emit_line(e, "{")
    e.indent += 1
    if len(visible) == 0 {
        emit_line_mapped(
            e,
            fmt.tprintf(
                "kvist_repl_host.pause(kvist_repl_host.ctx, %q, nil, 0, nil, 0, %s, %s)",
                placeholder,
                required_text,
                restart_selection_text,
            ),
            form.span,
        )
    } else if debug_visible_has_runtime_collection(e, visible[:]) {
        values_name :=
            fmt.tprintf("kvist_debug_values_%d", e.temp_counter)
        e.temp_counter += 1
        pointers_name :=
            fmt.tprintf(
                "kvist_debug_rendered_values_%d",
                e.temp_counter,
            )
        e.temp_counter += 1
        emit_line(
            e,
            fmt.tprintf(
                "%s := make([dynamic]string, 0, %d)",
                values_name,
                len(visible),
            ),
        )
        for i := len(visible)-1; i >= 0; i -= 1 {
            local := e.local_types[visible[i]]
            if dynamic_elem_ty, dynamic_array :=
                dynamic_array_element_type(local.ty);
               dynamic_array {
                debug_emit_append_dynamic_array_root(
                    e,
                    values_name,
                    local,
                    local.name,
                )
                debug_emit_append_dynamic_array(
                    e,
                    values_name,
                    local,
                    dynamic_elem_ty,
                )
            } else if map_key_ty, map_value_ty, is_map :=
                map_type_parts(local.ty);
               is_map {
                debug_emit_append_map_root(
                    e,
                    values_name,
                    local,
                    local.name,
                )
                if debug_map_key_supported(map_key_ty) {
                    debug_emit_append_map(
                        e,
                        values_name,
                        local,
                        map_key_ty,
                        map_value_ty,
                    )
                }
            } else {
                debug_emit_append_typed_rendered_value(
                    e,
                    values_name,
                    local,
                    local.ty,
                    local.name,
                )
                remaining := REPL_DEBUG_PATH_LIMIT
                debug_emit_append_static_paths(
                    e,
                    values_name,
                    local,
                    local.ty,
                    local.name,
                    &remaining,
                )
            }
        }
        emit_line(e, "defer {")
        e.indent += 1
        emit_line(
            e,
            fmt.tprintf(
                "for value in %s %c delete(value) %c",
                values_name,
                '{',
                '}',
            ),
        )
        emit_line(e, fmt.tprintf("delete(%s)", values_name))
        e.indent -= 1
        emit_line(e, "}")
        emit_line(
            e,
            fmt.tprintf(
                "%s := make([dynamic]Kvist_Repl_Rendered_Value, len(%s))",
                pointers_name,
                values_name,
            ),
        )
        emit_line(e, fmt.tprintf("defer delete(%s)", pointers_name))
        emit_line(
            e,
            fmt.tprintf(
                "for value, i in %s %c %s[i] = Kvist_Repl_Rendered_Value%cdata = raw_data(value), length = len(value)%c %c",
                values_name,
                '{',
                pointers_name,
                '{',
                '}',
                '}',
            ),
        )
        collections_name :=
            fmt.tprintf(
                "kvist_debug_collections_%d",
                e.temp_counter,
            )
        e.temp_counter += 1
        emit_line(
            e,
            fmt.tprintf(
                "%s := make([dynamic]Kvist_Repl_Debug_Collection)",
                collections_name,
            ),
        )
        emit_line(
            e,
            fmt.tprintf("defer delete(%s)", collections_name),
        )
        for i := len(visible)-1; i >= 0; i -= 1 {
            local := e.local_types[visible[i]]
            if dynamic_elem_ty, dynamic_array :=
                dynamic_array_element_type(local.ty);
               dynamic_array {
                debug_emit_dynamic_array_page_descriptor(
                    e,
                    collections_name,
                    local,
                    dynamic_elem_ty,
                    local.name,
                    local.name,
                )
                debug_emit_dynamic_element_page_descriptors(
                    e,
                    collections_name,
                    local,
                    dynamic_elem_ty,
                    local.name,
                    local.name,
                )
            } else if map_key_ty, map_value_ty, is_map :=
                map_type_parts(local.ty);
               is_map {
                debug_emit_map_page_descriptor(
                    e,
                    collections_name,
                    local,
                    map_key_ty,
                    map_value_ty,
                    local.name,
                    local.name,
                )
                debug_emit_map_value_page_descriptors(
                    e,
                    collections_name,
                    local,
                    map_key_ty,
                    map_value_ty,
                    local.name,
                    local.name,
                )
            }
            remaining := REPL_DEBUG_PATH_LIMIT
            debug_emit_nested_page_descriptors(
                e,
                collections_name,
                local,
                local.ty,
                local.name,
                local.name,
                &remaining,
            )
        }
        emit_line_mapped(
            e,
            fmt.tprintf(
                "kvist_repl_host.pause(kvist_repl_host.ctx, %q, raw_data(%s), len(%s), raw_data(%s), len(%s), %s, %s)",
                placeholder,
                pointers_name,
                pointers_name,
                collections_name,
                collections_name,
                required_text,
                restart_selection_text,
            ),
            form.span,
        )
    } else {
        value_count := debug_visible_value_count(e, visible[:])
        values_name := fmt.tprintf("kvist_debug_values_%d", e.temp_counter)
        e.temp_counter += 1
        pointers_name := fmt.tprintf("kvist_debug_rendered_values_%d", e.temp_counter)
        e.temp_counter += 1
        emit_indent(e)
        fmt.sbprintf(
            &e.builder,
            "%s := [%d]string%c",
            values_name,
            value_count,
            '{',
        )
        value_i := 0
        for i := len(visible)-1; i >= 0; i -= 1 {
            if value_i > 0 {
                strings.write_string(&e.builder, ", ")
            }
            local := e.local_types[visible[i]]
            debug_write_rendered_value(&e.builder, local, local.name)
            value_i += 1
            remaining := REPL_DEBUG_PATH_LIMIT
            debug_write_rendered_paths(
                &e.builder,
                e,
                local,
                local.ty,
                local.name,
                &value_i,
                &remaining,
            )
        }
        strings.write_string(&e.builder, "}")
        emit_raw_newline(e)
        emit_line(
            e,
            fmt.tprintf(
                "defer for value in %s %c delete(value) %c",
                values_name,
                '{',
                '}',
            ),
        )
        emit_line(
            e,
            fmt.tprintf(
                "%s: [%d]Kvist_Repl_Rendered_Value",
                pointers_name,
                value_count,
            ),
        )
        emit_line(
            e,
            fmt.tprintf(
                "for value, i in %s %c %s[i] = Kvist_Repl_Rendered_Value%cdata = raw_data(value), length = len(value)%c %c",
                values_name,
                '{',
                pointers_name,
                '{',
                '}',
                '}',
            ),
        )
        emit_line_mapped(
            e,
            fmt.tprintf(
                "kvist_repl_host.pause(kvist_repl_host.ctx, %q, &%s[0], %d, nil, 0, %s, %s)",
                placeholder,
                pointers_name,
                value_count,
                required_text,
                restart_selection_text,
            ),
            form.span,
        )
    }
    e.indent -= 1
    emit_line(e, "}")
    if !required {
        e.indent -= 1
        emit_line(e, "}")
    }
    emit_line(e, "if kvist_repl_host.abort_requested(kvist_repl_host.ctx) {")
    e.indent += 1
    #partial switch e.current_proc_returns.kind {
    case .None:
        emit_line(e, "return")
    case .Single:
        emit_line(
            e,
            fmt.tprintf(
                "return %s",
                zero_value_for_type_text(
                    e,
                    e.current_proc_returns.single_ty,
                ),
            ),
        )
    case .Named:
        emit_line(e, "return")
    }
    e.indent -= 1
    emit_line(e, "}")
}

debug_emit_selected_restart_name :: proc(
    e: ^Emitter,
    selection_name: string,
) -> string {
    selected_name :=
        fmt.tprintf("kvist_restart_name_%d", e.temp_counter)
    e.temp_counter += 1
    emit_line(e, fmt.tprintf("%s := \"\"", selected_name))
    emit_line(
        e,
        fmt.tprintf(
            "if %s.name.length > 0 %c %s = string(%s.name.data[:%s.name.length]) %c",
            selection_name,
            '{',
            selected_name,
            selection_name,
            selection_name,
            '}',
        ),
    )
    return selected_name
}

debug_emit_restart_case_branch :: proc(
    e: ^Emitter,
    selected_name: string,
) {
    if len(e.debug_restart_contexts) == 0 {
        return
    }
    restart_context :=
        e.debug_restart_contexts[len(e.debug_restart_contexts)-1]
    if restart_context.restart_flags&4 != 0 {
        emit_line(
            e,
            fmt.tprintf(
                "if %s == \"retry\" %c continue %s %c",
                selected_name,
                '{',
                restart_context.label,
                '}',
            ),
        )
    }
    if restart_context.restart_flags&8 != 0 {
        emit_line(
            e,
            fmt.tprintf(
                "if %s == \"skip\" %c break %s %c",
                selected_name,
                '{',
                restart_context.label,
                '}',
            ),
        )
    }
    if restart_context.restart_flags&16 != 0 {
        emit_line(
            e,
            fmt.tprintf(
                "if %s == \"abort-operation\" %c break %s %c",
                selected_name,
                '{',
                restart_context.label,
                '}',
            ),
        )
    }
}
