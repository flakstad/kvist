// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:sort"
import "core:strings"
import "core:sync"
import "core:time"
import "base:runtime"

Repl_Context_Expansion_Cache :: struct {
    key:      string,
    expanded: [dynamic]CST_Top_Form,
    macros:   [dynamic]User_Macro,
    aliases:  [dynamic]Alias_Prefix,
}

repl_context_expansion_cache: Repl_Context_Expansion_Cache
repl_context_expansion_cache_mutex: sync.RW_Mutex

repl_context_cache_top_form_clone :: proc(top: CST_Top_Form) -> CST_Top_Form {
    cloned := clone_cst_top_form(top)
    cloned.source_path = strings.clone(top.source_path)
    cloned.source_file = strings.clone(top.source_file)
    return cloned
}

repl_context_cache_alias_clone :: proc(alias: Alias_Prefix) -> Alias_Prefix {
    return Alias_Prefix{
        alias = strings.clone(alias.alias),
        prefix = strings.clone(alias.prefix),
        raw_prefix = strings.clone(alias.raw_prefix),
        exports = clone_string_slice(alias.exports[:]),
        raw_exports = clone_string_slice(alias.raw_exports[:]),
        refer_names = clone_string_slice(alias.refer_names[:]),
        preserve_qualified_calls = alias.preserve_qualified_calls,
        allow_unqualified_exports = alias.allow_unqualified_exports,
    }
}

repl_context_expansion_cache_clear :: proc() {
    delete(repl_context_expansion_cache.key)
    for &top in repl_context_expansion_cache.expanded {
        delete(top.source_path)
        delete(top.source_file)
        delete_cst_top_form(&top)
    }
    delete(repl_context_expansion_cache.expanded)
    delete_user_macro_slice(&repl_context_expansion_cache.macros)
    alias_prefix_slice_delete(&repl_context_expansion_cache.aliases)
    repl_context_expansion_cache = {}
}

repl_context_expansion_cache_borrow :: proc(
    key: string,
) -> (
    expanded: []CST_Top_Form,
    macros: []User_Macro,
    aliases: []Alias_Prefix,
    found: bool,
) {
    if key == "" {
        return nil, nil, nil, false
    }
    sync.rw_mutex_shared_lock(&repl_context_expansion_cache_mutex)
    if repl_context_expansion_cache.key != key {
        sync.rw_mutex_shared_unlock(&repl_context_expansion_cache_mutex)
        return nil, nil, nil, false
    }
    return repl_context_expansion_cache.expanded[:],
           repl_context_expansion_cache.macros[:],
           repl_context_expansion_cache.aliases[:],
           true
}

repl_context_expansion_cache_release :: proc(found: bool) {
    if found {
        sync.rw_mutex_shared_unlock(&repl_context_expansion_cache_mutex)
    }
}

repl_context_expansion_cache_store :: proc(
    key: string,
    expanded: []CST_Top_Form,
    macros: []User_Macro,
    aliases: []Alias_Prefix,
) {
    if key == "" {
        return
    }
    sync.rw_mutex_guard(&repl_context_expansion_cache_mutex)
    if repl_context_expansion_cache.key == key {
        return
    }
    current_allocator := context.allocator
    context.allocator = runtime.default_context().allocator
    defer context.allocator = current_allocator
    repl_context_expansion_cache_clear()
    repl_context_expansion_cache.key = strings.clone(key)
    for top in expanded {
        append(
            &repl_context_expansion_cache.expanded,
            repl_context_cache_top_form_clone(top),
        )
    }
    for macro_decl in macros {
        append(
            &repl_context_expansion_cache.macros,
            clone_user_macro(macro_decl),
        )
    }
    for alias in aliases {
        append(
            &repl_context_expansion_cache.aliases,
            repl_context_cache_alias_clone(alias),
        )
    }
}

top_form_belongs_to_package :: proc(top: CST_Top_Form, files: []Package_File) -> bool {
    if top.source_path == "" {
        return false
    }
    for file in files {
        if top.source_path == file.path {
            return true
        }
    }
    return false
}

profile_elapsed_ns :: proc(start: time.Tick) -> i64 {
    return time.duration_nanoseconds(time.tick_since(start))
}

load_path_expanded_forms :: proc(
    path: string,
    profile: ^Compile_Profile = nil,
    extra_imports: []CST_Top_Form = nil,
    declarations_only := false,
) -> (expanded: [dynamic]CST_Top_Form, macros: [dynamic]User_Macro, err: Compile_Error, ok: bool) {
    load_start: time.Tick
    if profile != nil {
        load_start = time.tick_now()
    }
    loaded, err_load, ok_load := load_root_file_forms(path, extra_imports)
    if profile != nil {
        profile.load_and_resolve_ns += profile_elapsed_ns(load_start)
    }
    if !ok_load {
        return expanded, macros, err_load, false
    }
    if !loaded.has_package {
        loaded.has_package = true
        loaded.package_decl = synthetic_package_decl("main")
    }
    combined: [dynamic]CST_Top_Form
    append(&combined, loaded.package_decl)
    for form in loaded.imports {
        append(&combined, form)
    }
    for form in loaded.decls {
        append(&combined, form)
    }
    macro_start: time.Tick
    if profile != nil {
        macro_start = time.tick_now()
    }
    expanded_forms, expanded_macros, err_expand, ok_expand := macroexpand_top_forms(combined[:], true, path)
    if profile != nil {
        profile.macro_expansion_ns += profile_elapsed_ns(macro_start)
    }
    if !ok_expand {
        return expanded, macros, err_expand, false
    }
    if declarations_only {
        declaration_forms: [dynamic]CST_Top_Form
        for form in expanded_forms {
            if eval_head_is_decl(eval_form_head(form.form)) {
                append(&declaration_forms, form)
            }
        }
        expanded_forms = declaration_forms
    }
    post_start: time.Tick
    if profile != nil {
        post_start = time.tick_now()
    }
    defer if profile != nil {
        profile.post_expand_resolution_ns += profile_elapsed_ns(post_start)
    }
    err_expanded_slash, ok_expanded_slash := validate_surface_package_slash_access(expanded_forms[:], loaded.source_aliases[:])
    if !ok_expanded_slash {
        return expanded, macros, err_expanded_slash, false
    }
    root_files, err_root_files, ok_root_files := read_root_package_files(path)
    if !ok_root_files {
        return expanded, macros, err_root_files, false
    }
    defer package_file_slice_delete(root_files)
    aliases, err_aliases, ok_aliases := collect_root_source_import_aliases_from_files(root_files)
    if !ok_aliases {
        return expanded, macros, err_aliases, false
    }
    for &alias in aliases {
        alias.allow_unqualified_exports = false
    }
    locals := collect_local_decl_names(expanded_forms[:])
    defer delete(locals)
    private_macros := collect_private_macro_decl_names(expanded_forms[:])
    defer delete(private_macros)
    rewritten_expanded: [dynamic]CST_Top_Form
    for top in expanded_forms {
        if !top_form_belongs_to_package(top, root_files) {
            append(&rewritten_expanded, clone_cst_top_form(top))
            continue
        }
        rewritten, err_rewrite, ok_rewrite := rewrite_top_form(top, locals[:], private_macros[:], aliases[:], "")
        if !ok_rewrite {
            return expanded, macros, err_rewrite, false
        }
        append(&rewritten_expanded, rewritten)
    }
    expanded = normalize_expanded_top_forms(rewritten_expanded[:])
    macros = expanded_macros
    return expanded, macros, Compile_Error{}, true
}

load_path_program :: proc(path: string, profile: ^Compile_Profile = nil) -> (AST_Program, Compile_Error, bool) {
    expanded, _, err_expand, ok_expand := load_path_expanded_forms(path, profile)
    if !ok_expand {
        return AST_Program{}, err_expand, false
    }
    parse_start: time.Tick
    if profile != nil {
        parse_start = time.tick_now()
    }
    program, err, ok := parse_program(expanded[:])
    if profile != nil {
        profile.ast_parse_ns += profile_elapsed_ns(parse_start)
    }
    return program, err, ok
}

compile_program_with_map :: proc(program: AST_Program, profile: ^Compile_Profile = nil) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    lower_start: time.Tick
    if profile != nil {
        lower_start = time.tick_now()
    }
    lowered, err_lower, ok_lower := lower_program(program)
    if profile != nil {
        profile.lowering_ns += profile_elapsed_ns(lower_start)
    }
    if !ok_lower {
        return result, clone_compile_error(err_lower, result_allocator), false
    }
    temp_result, err_emit, ok_emit := emit_ir_program_with_source_map(lowered, profile)
    if !ok_emit {
        return result, clone_compile_error(err_emit, result_allocator), false
    }
    result.output = strings.clone(temp_result.output, result_allocator)
    context.allocator = result_allocator
    for entry in temp_result.source_map {
        append(&result.source_map, clone_source_map_entry(entry, result_allocator))
    }
    for warning in temp_result.warnings {
        append(&result.warnings, clone_compile_warning(warning, result_allocator))
    }
    return result, Compile_Error{}, true
}

compile_program_eval_with_map :: proc(program: AST_Program, eval_source: string, no_print: bool = false) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    eval_form, err_eval, ok_eval := read_single_eval_form(eval_source)
    if !ok_eval {
        return result, err_eval, false
    }
    return compile_program_eval_form_with_map(program, eval_form, no_print)
}

compile_program_eval_form_with_map :: proc(
    program: AST_Program,
    eval_form: CST_Form,
    no_print: bool = false,
    profile: ^Compile_Profile = nil,
    repl_generation := false,
    repl_prior_proc_names: []string = nil,
    repl_current_proc_names: []string = nil,
    repl_has_runtime := true,
    repl_value_names: []string = nil,
    repl_current_value_names: []string = nil,
    repl_var_names: []string = nil,
    repl_current_var_names: []string = nil,
    repl_recent_result_types: []string = nil,
    repl_inspect_only := false,
    repl_inspection_source_slot := "",
    repl_inspection_source_type := "",
    repl_inspection_result_slot := "",
    repl_inspection_page_offset := 0,
    repl_inspection_page_limit := 0,
    repl_debug_capture_values := true,
) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    lower_start: time.Tick
    if profile != nil {
        lower_start = time.tick_now()
    }
    lowered, err_lower, ok_lower := lower_program(program)
    if profile != nil {
        profile.lowering_ns += profile_elapsed_ns(lower_start)
    }
    if !ok_lower {
        return result, clone_compile_error(err_lower, result_allocator), false
    }

    temp_result: Emit_Result
    err_emit: Compile_Error
    ok_emit: bool
    eval_head := eval_form_head(eval_form)
    if repl_generation {
        for repl_current_proc_name in repl_current_proc_names {
            current_decl: ^Proc_Decl
            for &decl in lowered.decls {
                if decl.kind == .Proc && decl.proc_decl.name == repl_current_proc_name {
                    current_decl = &decl.proc_decl
                }
            }
            if current_decl == nil || !repl_proc_is_concrete(current_decl) {
                return result, clone_compile_error(Compile_Error{
                    message = "persistent REPL defn currently requires concrete parameter and result types",
                    span = eval_form.span,
                }, result_allocator), false
            }
        }
        for value_name in repl_current_value_names {
            current_decl: ^Const_Decl
            for &decl in lowered.decls {
                if decl.kind == .Const && decl.const_decl.name == value_name {
                    current_decl = &decl.const_decl
                }
            }
            if current_decl == nil ||
               !current_decl.has_ty ||
               !repl_storage_type_supported(
                   lowered,
                   current_decl.ty,
                   allow_dynamic_array = true,
                   allow_slice = true,
               ) {
                message :=
                    "persistent REPL def requires an explicit retainable value type"
                if current_decl != nil &&
                   current_decl.has_ty &&
                   repl_storage_type_requires_lifecycle(
                       lowered,
                       current_decl.ty,
                    ) {
                    message =
                        "persistent REPL def with a pointer, foreign view, or opaque resource requires an owned copy until explicit lifecycle adapters are available"
                }
                return result, clone_compile_error(Compile_Error{
                    message = message,
                    span = eval_form.span,
                }, result_allocator), false
            }
        }
        for var_name in repl_current_var_names {
            current_decl: ^Var_Decl
            for &decl in lowered.decls {
                if decl.kind == .Var && decl.var_decl.name == var_name {
                    current_decl = &decl.var_decl
                }
            }
            if current_decl == nil ||
               !current_decl.has_ty ||
               !repl_storage_type_supported(
                   lowered,
                   current_decl.ty,
                   allow_dynamic_array = true,
                   allow_slice = true,
               ) {
                message :=
                    "persistent REPL defvar requires an explicit retainable value type"
                if current_decl != nil &&
                   current_decl.has_ty &&
                   repl_storage_type_requires_lifecycle(
                       lowered,
                       current_decl.ty,
                    ) {
                    message =
                        "persistent REPL defvar with a pointer, foreign view, or opaque resource requires an owned copy until explicit lifecycle adapters are available"
                }
                return result, clone_compile_error(Compile_Error{
                    message = message,
                    span = eval_form.span,
                }, result_allocator), false
            }
        }
        temp_result, err_emit, ok_emit = emit_eval_program_with_source_map(
            lowered,
            eval_form,
            no_print,
            true,
            repl_prior_proc_names,
            repl_current_proc_names,
            repl_has_runtime,
            repl_value_names,
            repl_current_value_names,
            repl_var_names,
            repl_current_var_names,
            repl_recent_result_types,
            repl_inspect_only,
            repl_inspection_source_slot,
            repl_inspection_source_type,
            repl_inspection_result_slot,
            repl_inspection_page_offset,
            repl_inspection_page_limit,
            repl_debug_capture_values,
            profile,
        )
    } else if eval_head_is_decl(eval_head) {
            eval_decl, err_decl, ok_decl := parse_decl(CST_Top_Form{form = eval_form})
            if !ok_decl {
                return result, clone_compile_error(err_decl, result_allocator), false
            }
            temp_result, err_emit, ok_emit = emit_eval_decl_program_with_source_map(lowered, IR_Decl(eval_decl))
    } else {
        temp_result, err_emit, ok_emit = emit_eval_program_with_source_map(
            lowered,
            eval_form,
            no_print,
            repl_generation,
            repl_prior_proc_names,
        )
    }
    if !ok_emit {
        return result, clone_compile_error(err_emit, result_allocator), false
    }
    result.output = strings.clone(temp_result.output, result_allocator)
    context.allocator = result_allocator
    for entry in temp_result.source_map {
        append(&result.source_map, clone_source_map_entry(entry, result_allocator))
    }
    for warning in temp_result.warnings {
        append(&result.warnings, clone_compile_warning(warning, result_allocator))
    }
    return result, Compile_Error{}, true
}

compile_source :: proc(source: string) -> (output: string, err: Compile_Error, ok: bool) {
    result, err_result, ok_result := compile_source_with_map(source)
    if !ok_result {
        return "", err_result, false
    }
    defer source_map_slice_delete(result.source_map)
    defer compile_warning_slice_delete(result.warnings)
    return result.output, {}, true
}

compile_source_with_map :: proc(source: string) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    forms, err_forms, ok_forms := read_kvist_top_forms(source)
    if !ok_forms {
        return result, clone_compile_error(err_forms, result_allocator), false
    }
    err_order, ok_order := validate_surface_top_level_order(forms[:])
    if !ok_order {
        return result, clone_compile_error(err_order, result_allocator), false
    }
    err_surface, ok_surface := validate_surface_internal_call_names(forms[:])
    if !ok_surface {
        return result, clone_compile_error(err_surface, result_allocator), false
    }
    err_slash, ok_slash := validate_surface_package_slash_access(forms[:])
    if !ok_slash {
        return result, clone_compile_error(err_slash, result_allocator), false
    }
    loaded, err_load, ok_load := load_root_source_forms(forms[:])
    if !ok_load {
        return result, clone_compile_error(err_load, result_allocator), false
    }
    if !loaded.has_package {
        loaded.has_package = true
        loaded.package_decl = synthetic_package_decl("main")
    }
    combined: [dynamic]CST_Top_Form
    append(&combined, loaded.package_decl)
    for form in loaded.imports {
        append(&combined, form)
    }
    for form in loaded.decls {
        append(&combined, form)
    }
    expanded, _, err_expand, ok_expand := macroexpand_top_forms(combined[:], true)
    if !ok_expand {
        return result, clone_compile_error(err_expand, result_allocator), false
    }
    err_expanded_slash, ok_expanded_slash := validate_surface_package_slash_access(expanded[:], loaded.source_aliases[:])
    if !ok_expanded_slash {
        return result, clone_compile_error(err_expanded_slash, result_allocator), false
    }
    normalized := normalize_expanded_top_forms(expanded[:])
    program, err_program, ok_program := parse_program(normalized[:])
    if !ok_program {
        return result, clone_compile_error(err_program, result_allocator), false
    }
    lowered, err_lower, ok_lower := lower_program(program)
    if !ok_lower {
        return result, clone_compile_error(err_lower, result_allocator), false
    }
    temp_result, err_emit, ok_emit := emit_ir_program_with_source_map(lowered)
    if !ok_emit {
        return result, clone_compile_error(err_emit, result_allocator), false
    }
    result.output = strings.clone(temp_result.output, result_allocator)
    context.allocator = result_allocator
    for entry in temp_result.source_map {
        append(&result.source_map, clone_source_map_entry(entry, result_allocator))
    }
    for warning in temp_result.warnings {
        append(&result.warnings, clone_compile_warning(warning, result_allocator))
    }
    return result, {}, true
}

read_single_eval_form :: proc(source: string) -> (form: CST_Form, err: Compile_Error, ok: bool) {
    forms, err_forms, ok_forms := read_top_forms_with_origin(source, .Eval)
    if !ok_forms {
        return form, err_forms, false
    }
    defer delete_borrowed_cst_top_form_slice(&forms)
    if len(forms) != 1 {
        return form, Compile_Error{message = "eval expects exactly one form", span = Span{source = .Eval}}, false
    }
    err_surface, ok_surface := validate_surface_internal_call_names(forms[:])
    if !ok_surface {
        return form, err_surface, false
    }
    err_slash, ok_slash := validate_surface_package_slash_access(forms[:])
    if !ok_slash {
        return form, err_slash, false
    }
    form = forms[0].form
    forms[0].form = {}
    return form, {}, true
}

eval_form_head :: proc(form: CST_Form) -> string {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return ""
    }
    return form.items[0].text
}

eval_head_is_decl :: proc(head: string) -> bool {
    switch head {
    case "package", "import", "foreign-import", "def", "def-", "defvar", "defvar-", "defstruct", "defstruct-", "defenum", "defenum-", "defunion", "defunion-", "odin", "@exports", "defn", "defn-", "defmacro", "defmacro-", "deftransform", "deftransform-", "defiter", "defiter-":
        return true
    }
    return false
}

compile_eval_source :: proc(source, eval_source: string, no_print: bool = false) -> (output: string, err: Compile_Error, ok: bool) {
    result, err_result, ok_result := compile_eval_source_with_map(source, eval_source, no_print)
    if !ok_result {
        return "", err_result, false
    }
    defer source_map_slice_delete(result.source_map)
    defer compile_warning_slice_delete(result.warnings)
    return result.output, {}, true
}

compile_eval_source_with_map :: proc(source, eval_source: string, no_print: bool = false) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    forms, err_forms, ok_forms := read_kvist_top_forms(source)
    if !ok_forms {
        return result, clone_compile_error(err_forms, result_allocator), false
    }
    err_order, ok_order := validate_surface_top_level_order(forms[:])
    if !ok_order {
        return result, clone_compile_error(err_order, result_allocator), false
    }
    err_surface, ok_surface := validate_surface_internal_call_names(forms[:])
    if !ok_surface {
        return result, clone_compile_error(err_surface, result_allocator), false
    }
    err_slash, ok_slash := validate_surface_package_slash_access(forms[:])
    if !ok_slash {
        return result, clone_compile_error(err_slash, result_allocator), false
    }
    loaded, err_load, ok_load := load_root_source_forms(forms[:])
    if !ok_load {
        return result, clone_compile_error(err_load, result_allocator), false
    }
    if !loaded.has_package {
        loaded.has_package = true
        loaded.package_decl = synthetic_package_decl("main")
    }
    combined: [dynamic]CST_Top_Form
    append(&combined, loaded.package_decl)
    for form in loaded.imports {
        append(&combined, form)
    }
    for form in loaded.decls {
        append(&combined, form)
    }
    expanded, macros, err_expand, ok_expand := macroexpand_top_forms(combined[:], true)
    if !ok_expand {
        return result, clone_compile_error(err_expand, result_allocator), false
    }
    err_expanded_slash, ok_expanded_slash := validate_surface_package_slash_access(expanded[:], loaded.source_aliases[:])
    if !ok_expanded_slash {
        return result, clone_compile_error(err_expanded_slash, result_allocator), false
    }
    normalized := normalize_expanded_top_forms(expanded[:])
    program, err_program, ok_program := parse_program(normalized[:])
    if !ok_program {
        return result, clone_compile_error(err_program, result_allocator), false
    }
    lowered, err_lower, ok_lower := lower_program(program)
    if !ok_lower {
        return result, clone_compile_error(err_lower, result_allocator), false
    }
    eval_form, err_eval, ok_eval := read_single_eval_form(eval_source)
    if !ok_eval {
        return result, clone_compile_error(err_eval, result_allocator), false
    }
    previous_macro_anchor := macro_eval_set_anchor(".")
    expanded_eval_form, err_eval_expand, ok_eval_expand := macroexpand_cst_form_with_macros(eval_form, macros[:])
    macro_eval_restore_anchor(previous_macro_anchor)
    if !ok_eval_expand {
        if err_eval_expand.span.source != .Eval {
            err_eval_expand.span = eval_form.span
        }
        return result, clone_compile_error(err_eval_expand, result_allocator), false
    }
    defer delete_cst_form(&expanded_eval_form)
    anchor_expanded_eval_spans(&expanded_eval_form, eval_form.span)
    err_eval_slash, ok_eval_slash := validate_surface_package_slash_access_form(expanded_eval_form, loaded.source_aliases[:])
    if !ok_eval_slash {
        return result, clone_compile_error(err_eval_slash, result_allocator), false
    }

    temp_result: Emit_Result
    err_emit: Compile_Error
    ok_emit: bool

    eval_head := eval_form_head(expanded_eval_form)
    if eval_head_is_decl(eval_head) {
        eval_decl, err_decl, ok_decl := parse_decl(CST_Top_Form{form = expanded_eval_form})
        if !ok_decl {
            return result, clone_compile_error(err_decl, result_allocator), false
        }
        temp_result, err_emit, ok_emit = emit_eval_decl_program_with_source_map(lowered, IR_Decl(eval_decl))
    } else {
        temp_result, err_emit, ok_emit = emit_eval_program_with_source_map(lowered, expanded_eval_form, no_print)
    }
    if !ok_emit {
        return result, clone_compile_error(err_emit, result_allocator), false
    }
    result.output = strings.clone(temp_result.output, result_allocator)
    context.allocator = result_allocator
    for entry in temp_result.source_map {
        append(&result.source_map, clone_source_map_entry(entry, result_allocator))
    }
    for warning in temp_result.warnings {
        append(&result.warnings, clone_compile_warning(warning, result_allocator))
    }
    return result, {}, true
}

anchor_expanded_eval_spans :: proc(form: ^CST_Form, enclosing_eval_span: Span) {
    anchor := enclosing_eval_span
    if form.span.source == .Eval {
        anchor = form.span
    } else {
        form.span = enclosing_eval_span
    }
    for index in 0 ..< len(form.items) {
        anchor_expanded_eval_spans(&form.items[index], anchor)
    }
}

compile_path :: proc(path: string) -> (output: string, err: Compile_Error, ok: bool) {
    result, err_result, ok_result := compile_path_with_map(path)
    if !ok_result {
        return "", err_result, false
    }
    defer source_map_slice_delete(result.source_map)
    defer compile_warning_slice_delete(result.warnings)
    source_dir, _ := os.split_path(path)
    if source_dir == "" {
        source_dir = "."
    }
    rebased, err_rebase, ok_rebase := rebase_emitted_odin_imports(result.output, source_dir)
    delete(result.output)
    if !ok_rebase {
        return "", err_rebase, false
    }
    result.output = rebased
    return result.output, {}, true
}

compile_path_with_map :: proc(path: string, profile: ^Compile_Profile = nil) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := result_allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator

    program, err_program, ok_program := load_path_program(path, profile)
    if !ok_program {
        context.allocator = old_allocator
        return result, clone_compile_error(err_program, result_allocator), false
    }
    context.allocator = old_allocator
    err_compile: Compile_Error
    ok_compile: bool
    result, err_compile, ok_compile = compile_program_with_map(program, profile)
    if !ok_compile {
        return result, err_compile, false
    }
    return result, {}, true
}

compile_path_with_package_artifacts :: proc(
    path: string,
    profile: ^Compile_Profile = nil,
    cache_dir := "",
) -> (result: Package_Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := result_allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    program, err_program, ok_program := load_path_program(path, profile)
    if !ok_program {
        return result, clone_compile_error(err_program, result_allocator), false
    }
    lower_start: time.Tick
    if profile != nil {
        lower_start = time.tick_now()
    }
    lowered, err_lower, ok_lower := lower_program(program)
    if profile != nil {
        profile.lowering_ns += profile_elapsed_ns(lower_start)
    }
    if !ok_lower {
        return result, clone_compile_error(err_lower, result_allocator), false
    }
    temp_result, err_emit, ok_emit := emit_ir_program_with_package_artifacts(
        lowered,
        path,
        profile,
        cache_dir,
    )
    if !ok_emit {
        return result, clone_compile_error(err_emit, result_allocator), false
    }

    context.allocator = result_allocator
    result.packages_reused = temp_result.packages_reused
    result.packages_emitted = temp_result.packages_emitted
    result.root.output = strings.clone(temp_result.root.output, result_allocator)
    for entry in temp_result.root.source_map {
        append(&result.root.source_map, clone_source_map_entry(entry, result_allocator))
    }
    for warning in temp_result.root.warnings {
        append(&result.root.warnings, clone_compile_warning(warning, result_allocator))
    }
    for artifact in temp_result.artifacts {
        cloned := Generated_Package_Artifact{
            id = strings.clone(artifact.id, result_allocator),
            source_root = strings.clone(artifact.source_root, result_allocator),
            output = strings.clone(artifact.output, result_allocator),
        }
        for entry in artifact.source_map {
            append(&cloned.source_map, clone_source_map_entry(entry, result_allocator))
        }
        for warning in artifact.warnings {
            append(&cloned.warnings, clone_compile_warning(warning, result_allocator))
        }
        for dependency in artifact.dependencies {
            append(&cloned.dependencies, strings.clone(dependency, result_allocator))
        }
        append(&result.artifacts, cloned)
    }
    return result, {}, true
}

rebase_emitted_odin_imports :: proc(source, output_dir: string) -> (output: string, err: Compile_Error, ok: bool) {
    canonical_output_dir, output_dir_err, output_dir_ok := canonicalize_generated_output_dir(output_dir)
    if !output_dir_ok {
        return "", output_dir_err, false
    }
    defer delete(canonical_output_dir)

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    changed := false
    line_start := 0
    for i := 0; i <= len(source); i += 1 {
        if i < len(source) && source[i] != '\n' {
            continue
        }

        line := source[line_start:i]
        rewritten := line
        if strings.has_prefix(line, "import ") {
            first_quote := strings.index(line, "\"")
            if first_quote >= 0 {
                rest := line[first_quote+1:]
                second_quote := strings.index(rest, "\"")
                if second_quote >= 0 {
                    import_path := unquote_string(line[first_quote:first_quote+second_quote+2])
                    defer delete(import_path)
                    if os.is_absolute_path(import_path) {
                        canonical_import_path, import_path_err := os.get_absolute_path(import_path, context.allocator)
                        if import_path_err != nil {
                            strings.write_string(&builder, rewritten)
                            if i < len(source) {
                                strings.write_byte(&builder, '\n')
                            }
                            line_start = i + 1
                            continue
                        }
                        relative_path, rel_err := os.get_relative_path(canonical_output_dir, canonical_import_path, context.allocator)
                        delete(canonical_import_path)
                        import_path_for_output := ""
                        if rel_err == nil {
                            import_path_for_output = relative_path
                        } else {
                            import_path_for_output = import_path
                        }
                        import_relative_path := forward_slash_path(import_path_for_output)
                        if rel_err == nil {
                            delete(relative_path)
                        }
                        rewritten = fmt.tprintf("%s%q%s", line[:first_quote], import_relative_path, rest[second_quote+1:])
                        delete(import_relative_path)
                        changed = true
                    }
                }
            }
        }
        strings.write_string(&builder, rewritten)
        if i < len(source) {
            strings.write_byte(&builder, '\n')
        }
        line_start = i + 1
    }

    if changed {
        return strings.clone(strings.to_string(builder)), Compile_Error{}, true
    }
    return strings.clone(source), Compile_Error{}, true
}

rebase_emitted_odin_imports_for_output_path :: proc(source, output_path: string) -> (output: string, err: Compile_Error, ok: bool) {
    output_dir, _ := os.split_path(output_path)
    if output_dir == "" {
        output_dir = "."
    }
    return rebase_emitted_odin_imports(source, output_dir)
}

forward_slash_path :: proc(path: string) -> string {
    normalized, allocated := strings.replace_all(path, "\\", "/", context.allocator)
    if allocated {
        return normalized
    }
    return strings.clone(path)
}

canonicalize_generated_output_dir :: proc(path: string) -> (canonical: string, err: Compile_Error, ok: bool) {
    if path == "" || path == "." {
        canonical, canonical_err := os.get_absolute_path(".", context.allocator)
        if canonical_err != nil {
            return "", Compile_Error{message = "could not canonicalize generated Odin output directory: ."}, false
        }
        return canonical, Compile_Error{}, true
    }
    if os.exists(path) {
        canonical, canonical_err := os.get_absolute_path(path, context.allocator)
        if canonical_err != nil {
            return "", Compile_Error{message = fmt.tprintf("could not canonicalize generated Odin output directory: %s", path)}, false
        }
        return canonical, Compile_Error{}, true
    }

    parent, leaf := os.split_path(path)
    if leaf == "" {
        return "", Compile_Error{message = fmt.tprintf("could not canonicalize generated Odin output directory: %s", path)}, false
    }
    if parent == "" || parent == path {
        parent = "."
    }

    canonical_parent, parent_err, parent_ok := canonicalize_generated_output_dir(parent)
    if !parent_ok {
        return "", parent_err, false
    }
    joined, join_err := os.join_path({canonical_parent, leaf}, context.allocator)
    delete(canonical_parent)
    if join_err != nil {
        return "", Compile_Error{message = fmt.tprintf("could not canonicalize generated Odin output directory: %s", path)}, false
    }
    cleaned, clean_err := os.clean_path(joined, context.allocator)
    delete(joined)
    if clean_err != nil {
        return "", Compile_Error{message = fmt.tprintf("could not canonicalize generated Odin output directory: %s", path)}, false
    }
    return cleaned, Compile_Error{}, true
}

compile_eval_path :: proc(path, eval_source: string, no_print: bool = false) -> (output: string, err: Compile_Error, ok: bool) {
    result, err_result, ok_result := compile_eval_path_with_map(path, eval_source, no_print)
    if !ok_result {
        return "", err_result, false
    }
    defer source_map_slice_delete(result.source_map)
    defer compile_warning_slice_delete(result.warnings)
    return result.output, {}, true
}

compile_eval_path_with_map :: proc(
    path,
    eval_source: string,
    no_print: bool = false,
    profile: ^Compile_Profile = nil,
    repl_generation := false,
    repl_session_source := "",
    repl_recent_result_types: []string = nil,
    repl_inspect_only := false,
    repl_inspection_source_slot := "",
    repl_inspection_source_type := "",
    repl_inspection_result_slot := "",
    repl_inspection_page_offset := 0,
    repl_inspection_page_limit := 0,
    repl_debug_capture_values := true,
    repl_context_cache_key := "",
    repl_execution_plan: ^Repl_Execution_Plan = nil,
    repl_stale_proc_names: []string = nil,
    repl_scalar_invokes: []Repl_Scalar_Invoke_Metadata = nil,
    repl_incremental_program: ^Repl_Incremental_Program = nil,
) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := result_allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator

    eval_form: CST_Form
    repl_batch: Repl_Batch
    repl_retained_forms: [dynamic]CST_Top_Form
    repl_import_forms: [dynamic]CST_Top_Form
    err_eval: Compile_Error
    ok_eval: bool
    if repl_generation {
        repl_batch, err_eval, ok_eval = read_repl_batch(eval_source)
        eval_form = repl_batch.eval_form
    } else {
        eval_form, err_eval, ok_eval = read_single_eval_form(eval_source)
    }
    if !ok_eval {
        context.allocator = old_allocator
        return result, clone_compile_error(err_eval, result_allocator), false
    }
    if repl_generation {
        retained_forms, err_session, ok_session :=
            repl_session_forms(repl_session_source)
        if !ok_session {
            context.allocator = old_allocator
            return result, clone_compile_error(err_session, result_allocator), false
        }
        repl_retained_forms = retained_forms
        all_import_forms: [dynamic]CST_Top_Form
        for top in repl_retained_forms {
            if eval_form_head(top.form) == "import" {
                append(&all_import_forms, top)
            }
        }
        for definition in repl_batch.definitions {
            if eval_form_head(definition) == "import" {
                append(&all_import_forms, CST_Top_Form{form = definition})
            }
        }
        retained_imports_reversed: [dynamic]CST_Top_Form
        seen_import_aliases := make(map[string]bool)
        for i := len(all_import_forms)-1; i >= 0; i -= 1 {
            alias, ok_alias := repl_form_decl_name(all_import_forms[i].form)
            if !ok_alias || seen_import_aliases[alias] {
                continue
            }
            seen_import_aliases[alias] = true
            append(&retained_imports_reversed, all_import_forms[i])
        }
        for i := len(retained_imports_reversed)-1; i >= 0; i -= 1 {
            append(&repl_import_forms, retained_imports_reversed[i])
        }
    }
    expanded_forms: [dynamic]CST_Top_Form
    macros: [dynamic]User_Macro
    aliases: []Alias_Prefix
    context_cache_key :=
        repl_context_cache_key if repl_generation else ""
    cached_expanded, cached_macros, cached_aliases, context_cache_hit :=
        repl_context_expansion_cache_borrow(context_cache_key)
    defer repl_context_expansion_cache_release(context_cache_hit)
    err_program: Compile_Error
    ok_program := context_cache_hit
    if context_cache_hit {
        // The shared cache lock keeps nested CST, macro, and alias storage
        // alive. Only the small top-level headers are copied so session forms
        // can be appended without mutating the cached slice.
        append(&expanded_forms, ..cached_expanded)
        append(&macros, ..cached_macros)
        aliases = cached_aliases
    } else {
        expanded_forms, macros, err_program, ok_program =
            load_path_expanded_forms(
                path,
                profile,
                repl_import_forms[:],
                declarations_only = repl_generation,
            )
    }
    if !ok_program {
        context.allocator = old_allocator
        return result, clone_compile_error(err_program, result_allocator), false
    }
    if !context_cache_hit {
        loaded_aliases, err_aliases, ok_aliases :=
            collect_root_source_import_aliases(path, repl_import_forms[:])
        if !ok_aliases {
            context.allocator = old_allocator
            return result, clone_compile_error(err_aliases, result_allocator), false
        }
        aliases = loaded_aliases
        if repl_generation {
            for &top in expanded_forms {
                rewrite_repl_stream_output_form(&top.form)
            }
        }
        repl_context_expansion_cache_store(
            context_cache_key,
            expanded_forms[:],
            macros[:],
            aliases,
        )
    }
    context_form_count := len(expanded_forms)
    alias_names := alias_prefix_names(aliases)
    defer delete(alias_names)
    if repl_generation {
        for top in repl_retained_forms {
            if !is_defmacro_form(top.form) {
                continue
            }
            macro_decl, err_macro, ok_macro := parse_user_macro_decl(top)
            if !ok_macro {
                context.allocator = old_allocator
                return result, clone_compile_error(err_macro, result_allocator), false
            }
            append(&macros, macro_decl)
        }
        for definition in repl_batch.definitions {
            if !is_defmacro_form(definition) {
                continue
            }
            macro_decl, err_macro, ok_macro := parse_user_macro_decl(
                CST_Top_Form{form = definition},
            )
            if !ok_macro {
                context.allocator = old_allocator
                return result, clone_compile_error(err_macro, result_allocator), false
            }
            append(&macros, macro_decl)
        }
    }
    eval_form_rewritten, err_rewrite_eval, ok_rewrite_eval := rewrite_form_symbols(eval_form, nil, aliases, "")
    if !ok_rewrite_eval {
        context.allocator = old_allocator
        return result, clone_compile_error(err_rewrite_eval, result_allocator), false
    }
    eval_form = eval_form_rewritten
    previous_macro_anchor := macro_eval_set_anchor(path)
    expanded_eval_form, err_eval_expand, ok_eval_expand := macroexpand_cst_form_with_macros(eval_form, macros[:])
    macro_eval_restore_anchor(previous_macro_anchor)
    if !ok_eval_expand {
        context.allocator = old_allocator
        return result, clone_compile_error(err_eval_expand, result_allocator), false
    }
    err_eval_slash, ok_eval_slash := validate_surface_package_slash_access_form(expanded_eval_form, alias_names[:])
    if !ok_eval_slash {
        context.allocator = old_allocator
        return result, clone_compile_error(err_eval_slash, result_allocator), false
    }

    repl_prior_proc_names: [dynamic]string
    repl_current_proc_names: [dynamic]string
    repl_value_names: [dynamic]string
    repl_current_value_names: [dynamic]string
    repl_var_names: [dynamic]string
    repl_current_var_names: [dynamic]string
    if repl_generation {
        seen_prior := make(map[string]bool)
        for top in repl_retained_forms {
            name, _ := repl_form_decl_name(top.form)
            head := eval_form_head(top.form)
            if !seen_prior[name] {
                seen_prior[name] = true
                if head == "defn" {
                    append(&repl_prior_proc_names, name)
                } else if head == "def" {
                    append(&repl_value_names, name)
                } else if head == "defvar" {
                    append(&repl_var_names, name)
                }
            }
            if is_defmacro_form(top.form) || head == "import" {
                continue
            }
            rewritten, err_rewritten, ok_rewritten := rewrite_form_symbols(top.form, nil, aliases, "")
            if !ok_rewritten {
                context.allocator = old_allocator
                return result, clone_compile_error(err_rewritten, result_allocator), false
            }
            previous_session_anchor := macro_eval_set_anchor(path)
            expanded_session, err_expanded, ok_expanded :=
                macroexpand_cst_form_with_macros(rewritten, macros[:])
            macro_eval_restore_anchor(previous_session_anchor)
            if !ok_expanded {
                context.allocator = old_allocator
                return result, clone_compile_error(err_expanded, result_allocator), false
            }
            err_session_slash, ok_session_slash :=
                validate_surface_package_slash_access_form(expanded_session, alias_names[:])
            if !ok_session_slash {
                context.allocator = old_allocator
                return result, clone_compile_error(err_session_slash, result_allocator), false
            }
            append(&expanded_forms, CST_Top_Form{form = expanded_session})
        }

        seen_current := make(map[string]bool)
        for definition in repl_batch.definitions {
            current_name, _ := repl_form_decl_name(definition)
            head := eval_form_head(definition)
            if !seen_current[current_name] {
                seen_current[current_name] = true
                if head == "defn" {
                    append(&repl_current_proc_names, current_name)
                } else if head == "def" {
                    append(&repl_current_value_names, current_name)
                } else if head == "defvar" {
                    append(&repl_current_var_names, current_name)
                }
            }
            if is_defmacro_form(definition) || head == "import" {
                continue
            }
            for i := len(repl_prior_proc_names)-1; i >= 0; i -= 1 {
                if repl_prior_proc_names[i] == current_name {
                    unordered_remove(&repl_prior_proc_names, i)
                }
            }
            for i := len(repl_value_names)-1; i >= 0; i -= 1 {
                if repl_value_names[i] == current_name {
                    unordered_remove(&repl_value_names, i)
                }
            }
            for i := len(repl_var_names)-1; i >= 0; i -= 1 {
                if repl_var_names[i] == current_name {
                    unordered_remove(&repl_var_names, i)
                }
            }
            rewritten_definition, err_definition, ok_definition :=
                rewrite_form_symbols(definition, nil, aliases, "")
            if !ok_definition {
                context.allocator = old_allocator
                return result, clone_compile_error(err_definition, result_allocator), false
            }
            previous_definition_anchor := macro_eval_set_anchor(path)
            expanded_definition, err_expanded_definition, ok_expanded_definition :=
                macroexpand_cst_form_with_macros(rewritten_definition, macros[:])
            macro_eval_restore_anchor(previous_definition_anchor)
            if !ok_expanded_definition {
                context.allocator = old_allocator
                return result, clone_compile_error(err_expanded_definition, result_allocator), false
            }
            append(&expanded_forms, CST_Top_Form{form = expanded_definition})
        }
    }

    if repl_generation {
        rewrite_repl_stream_output_form(&expanded_eval_form)
        for i := context_form_count; i < len(expanded_forms); i += 1 {
            rewrite_repl_stream_output_form(&expanded_forms[i].form)
        }
    }

    parse_start: time.Tick
    if profile != nil {
        parse_start = time.tick_now()
    }
    program, err_parse, ok_parse := parse_program(expanded_forms[:])
    if profile != nil {
        profile.ast_parse_ns += profile_elapsed_ns(parse_start)
    }
    if !ok_parse {
        context.allocator = old_allocator
        return result, clone_compile_error(err_parse, result_allocator), false
    }
    if repl_generation {
        program = repl_dedupe_session_decls(program)
        // Polymorphic declarations persist as compiler templates and are
        // specialized by Odin in each generation that calls them. Concrete
        // procedures use versioned runtime slots. Keeping the two paths
        // separate avoids taking an address of an unspecialized procedure
        // while preserving old native callers until explicit refresh.
        repl_filter_concrete_proc_names(
            &repl_prior_proc_names,
            program,
        )
        repl_filter_concrete_proc_names(
            &repl_current_proc_names,
            program,
        )
    }
    all_repl_value_names: [dynamic]string
    append(&all_repl_value_names, ..repl_value_names[:])
    for name in repl_current_value_names {
        if !name_in_list(all_repl_value_names[:], name) {
            append(&all_repl_value_names, name)
        }
    }
    all_repl_var_names: [dynamic]string
    append(&all_repl_var_names, ..repl_var_names[:])
    for name in repl_current_var_names {
        if !name_in_list(all_repl_var_names[:], name) {
            append(&all_repl_var_names, name)
        }
    }
    if repl_execution_plan != nil && repl_generation &&
       repl_batch.has_runtime && len(repl_batch.definitions) == 0 {
        semantic_plan, planned := repl_build_semantic_execution_plan(
            program,
            expanded_eval_form,
            repl_recent_result_types,
            all_repl_value_names[:],
            all_repl_var_names[:],
            repl_current_proc_names[:],
            repl_stale_proc_names,
            repl_scalar_invokes,
        )
        if planned {
            cloned := Repl_Execution_Plan{
                encoded = strings.clone(
                    semantic_plan.encoded,
                    result_allocator,
                ),
                result_abi = strings.clone(
                    semantic_plan.result_abi,
                    result_allocator,
                ),
                preserves_result_history =
                    semantic_plan.preserves_result_history,
                recent_result_mask = semantic_plan.recent_result_mask,
            }
            repl_execution_plan_delete(&semantic_plan)
            repl_execution_plan^ = cloned
            context.allocator = old_allocator
            return result, Compile_Error{}, true
        }
    }
    context.allocator = old_allocator
    result, err, ok = compile_program_eval_form_with_map(
        program,
        expanded_eval_form,
        no_print,
        profile,
        repl_generation,
        repl_prior_proc_names[:],
        repl_current_proc_names[:],
        repl_batch.has_runtime if repl_generation else true,
        all_repl_value_names[:],
        repl_current_value_names[:],
        all_repl_var_names[:],
        repl_current_var_names[:],
        repl_recent_result_types,
        repl_inspect_only,
        repl_inspection_source_slot,
        repl_inspection_source_type,
        repl_inspection_result_slot,
        repl_inspection_page_offset,
        repl_inspection_page_limit,
        repl_debug_capture_values,
    )
    if !ok || repl_incremental_program == nil || !repl_generation ||
       repl_batch.has_runtime || len(repl_batch.definitions) == 0 {
        return
    }
    definitions_are_procs := true
    for definition in repl_batch.definitions {
        if eval_form_head(definition) != "defn" {
            definitions_are_procs = false
            break
        }
    }
    if !definitions_are_procs {
        return
    }
    context.allocator = context.temp_allocator
    incremental, built := repl_build_incremental_program(
        program,
        repl_current_proc_names[:],
        repl_stale_proc_names,
        repl_scalar_invokes,
    )
    if built {
        repl_incremental_program^ = Repl_Incremental_Program{
            encoded = strings.clone(
                incremental.encoded,
                result_allocator,
            ),
        }
        repl_incremental_program_delete(&incremental)
    }
    context.allocator = old_allocator
    return
}
