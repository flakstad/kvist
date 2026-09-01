package kvist

import "core:fmt"
import "core:os"
import "core:sort"
import "core:strings"
import "base:runtime"

symbols_proc_lifetime_detail :: proc(decl: ^Proc_Decl) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    first := true
    borrowed_result := decl.borrows_result ||
                       (decl.returns.kind == .Single &&
                       len(decl.body) > 0 &&
                       (borrowed_source_param_tracked(
                            decl.body[len(decl.body)-1],
                            decl.returns.single_ty,
                            decl.params[:],
                        ) ||
                        known_odin_call_lifetime(decl.body[len(decl.body)-1]) == .Borrowed))
    owned_result := !borrowed_result &&
                    (decl.owns_result ||
                     proc_decl_infers_owned_result(nil, decl) ||
                     (len(decl.body) > 0 &&
                      form_infers_known_foreign_lifetime(
                          decl.body[len(decl.body)-1],
                          .Owned,
                      )))
    if owned_result {
        strings.write_string(&builder, "lifetime=result-owned")
        first = false
    } else if borrowed_result {
        strings.write_string(&builder, "lifetime=result-borrowed")
        first = false
    }
    for param, idx in decl.params {
        explicit_consumption :=
            body_deletes_or_returns_name(decl.body[:], param.name, false)
        transferred_result :=
            owned_result &&
            body_deletes_or_returns_name(decl.body[:], param.name, true)
        if param.ownership != .Owned &&
           !explicit_consumption &&
           !transferred_result {
            continue
        }
        if !first {
            strings.write_byte(&builder, ';')
        }
        fmt.sbprintf(&builder, "consumes=%d", idx)
        first = false
    }
    return strings.to_string(builder)
}

lifetime_type_is_relevant :: proc(ty: string) -> bool {
    text := strings.trim_space(ty)
    return text == "Data" ||
           text == "string" ||
           text == "cstring" ||
           text == "rawptr" ||
           type_text_is_slice_or_fixed_array(text) ||
           type_text_is_dynamic_array(text) ||
           type_text_is_map(text) ||
           strings.has_prefix(text, "^")
}

lifetimes_write_proc :: proc(builder: ^strings.Builder, name: string, decl: ^Proc_Decl) {
    detail := symbols_proc_lifetime_detail(decl)
    defer delete(detail)
    relevant := detail != ""
    if !relevant {
        for param in decl.params {
            if lifetime_type_is_relevant(param.ty) {
                relevant = true
                break
            }
        }
    }
    if !relevant && decl.returns.kind == .Single {
        relevant = lifetime_type_is_relevant(decl.returns.single_ty)
    }
    if !relevant {
        return
    }

    display_name, display_allocated := strings.replace_all(name, "_", "-")
    if display_allocated {
        defer delete(display_name)
    }
    signature := symbols_proc_signature(display_name, decl^)
    defer delete(signature)
    fmt.sbprintf(builder, "%s\n  %s\n", display_name, signature)

    borrowed_result := strings.contains(detail, "lifetime=result-borrowed")
    owned_result := strings.contains(detail, "lifetime=result-owned")
    if decl.returns.kind == .Single && lifetime_type_is_relevant(decl.returns.single_ty) {
        if decl.returns.single_ty == "Data" && borrowed_result {
            strings.write_string(builder, "  result: caller-owned Data reference; the compiler retains the borrowed source at the return boundary\n")
        } else if decl.returns.single_ty == "Data" && owned_result {
            strings.write_string(builder, "  result: caller-owned Data reference; every inferred return path already produces a new reference\n")
        } else if owned_result {
            strings.write_string(builder, "  result: owned; every inferred return path produces a new value\n")
        } else if borrowed_result {
            strings.write_string(builder, "  result: borrowed; the return aliases an input or a known foreign view\n")
        } else {
            strings.write_string(builder, "  result: explicit/unknown; Kvist does not infer transfer at this boundary\n")
        }
    }

    for param, idx in decl.params {
        if !lifetime_type_is_relevant(param.ty) {
            continue
        }
        marker := fmt.tprintf("consumes=%d", idx)
        if strings.contains(detail, marker) {
            fmt.sbprintf(
                builder,
                "  %s: consumed; the body explicitly deletes it or transfers it through an owned result\n",
                param.name,
            )
        } else {
            fmt.sbprintf(
                builder,
                "  %s: borrowed; no consuming path was inferred\n",
                param.name,
            )
        }
    }
    strings.write_byte(builder, '\n')
}

lifetimes_source :: proc(source: string) -> (output: string, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    forms, err_forms, ok_forms := read_kvist_top_forms(source)
    if !ok_forms {
        return "", clone_compile_error(err_forms, result_allocator), false
    }
    defer delete_borrowed_cst_top_form_slice(&forms)

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(
        &builder,
        "Inferred lifetime boundaries (no source annotations):\n\n",
    )
    for top in forms {
        form := top.form
        if form.kind != .List ||
           len(form.items) < 3 ||
           form.items[0].kind != .Symbol ||
           (form.items[0].text != "defn" && form.items[0].text != "defn-") ||
           form.items[1].kind != .Symbol {
            continue
        }
        proc_form := form
        if len(form.items) > 3 && form.items[2].kind == .String {
            items: [dynamic]CST_Form
            append(&items, form.items[0], form.items[1])
            for item in form.items[3:] {
                append(&items, item)
            }
            proc_form = CST_Form{kind = .List, items = items, span = form.span}
        }
        decl, err_decl, ok_decl := parse_proc_decl(proc_form)
        if !ok_decl {
            return "", clone_compile_error(err_decl, result_allocator), false
        }
        lifetimes_write_proc(&builder, form.items[1].text, &decl)
    }
    return strings.clone(strings.to_string(builder), result_allocator), {}, true
}

lifetimes_path :: proc(path: string) -> (output: string, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    program, err_program, ok_program := load_path_program(path)
    if !ok_program {
        return "", clone_compile_error(err_program, result_allocator), false
    }
    lowered, err_lower, ok_lower := lower_program(program)
    if !ok_lower {
        return "", clone_compile_error(err_lower, result_allocator), false
    }

    import_cache := Emitter_Import_Cache{}
    emitter_import_cache_init(&import_cache)
    defer emitter_import_cache_delete(&import_cache)
    emitter := Emitter{
        decls = lowered.decls[:],
        import_cache = &import_cache,
    }
    for decl in lowered.decls {
        if decl.kind == .Struct {
            append(&emitter.structs, decl.struct_decl)
        }
        if decl.kind == .Union {
            append(&emitter.unions, decl.union_decl)
        }
    }
    infer_decoded_struct_lifetimes(&emitter)
    infer_proc_lifetime_facts(&emitter)

    canonical_path, canonical_err := os.get_absolute_path(path, context.allocator)
    if canonical_err != nil {
        canonical_path = path
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(
        &builder,
        "Inferred lifetime boundaries (no source annotations):\n\n",
    )
    for &decl in emitter.decls {
        if decl.kind != .Proc {
            continue
        }
        if decl.source_path != "" {
            decl_path, decl_path_err := os.get_absolute_path(decl.source_path, context.allocator)
            same_file := decl_path_err == nil && decl_path == canonical_path
            if decl_path_err == nil {
                delete(decl_path)
            }
            if !same_file {
                continue
            }
        }
        lifetimes_write_proc(&builder, decl.proc_decl.name, &decl.proc_decl)
    }
    return strings.clone(strings.to_string(builder), result_allocator), {}, true
}
