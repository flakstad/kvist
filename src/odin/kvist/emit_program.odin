// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

emit_selected_decls_with_source_map :: proc(
    analysis_decls, emitted_decls: []IR_Decl,
    suppress_shared_helpers := false,
    aggregate_features: ^Emitter_Features = nil,
    initial_features: ^Emitter_Features = nil,
    data_literal_prefix := "",
    analysis_prepared := false,
    profile: ^Compile_Profile = nil,
    shared_import_cache: ^Emitter_Import_Cache = nil,
) -> (Emit_Result, Compile_Error, bool) {
    total_start: time.Tick
    analysis_before, source_map_before: i64
    if profile != nil {
        total_start = time.tick_now()
        analysis_before = profile.analysis_ns
        source_map_before = profile.source_map_ns
    }
    defer if profile != nil {
        total_ns := profile_elapsed_ns(total_start)
        analysis_ns := profile.analysis_ns - analysis_before
        source_map_ns := profile.source_map_ns - source_map_before
        profile.emission_ns += total_ns - analysis_ns - source_map_ns
    }
    result := Emit_Result{}
    local_import_cache := Emitter_Import_Cache{}
    import_cache := shared_import_cache
    if import_cache == nil {
        import_cache = &local_import_cache
        defer emitter_import_cache_delete(&local_import_cache)
    }
    emitter_import_cache_init(import_cache)
    features := Emitter_Features{}
    if initial_features != nil {
        merge_emitter_features(&features, initial_features^)
    }
    captured_specializations: [dynamic]Captured_Proc_Specialization
    e := Emitter{
        builder  = strings.builder_make(),
        decls    = analysis_decls,
        features = &features,
        source_map = &result.source_map,
        warnings = &result.warnings,
        line     = 1,
        data_literal_prefix = data_literal_prefix,
        captured_proc_specializations = &captured_specializations,
        import_cache = import_cache,
    }
    defer strings.builder_destroy(&e.builder)
    for decl in analysis_decls {
        if decl.kind == .Struct {
            append(&e.structs, decl.struct_decl)
        }
        if decl.kind == .Union {
            append(&e.unions, decl.union_decl)
        }
    }
    if !analysis_prepared {
        analysis_start: time.Tick
        if profile != nil {
            analysis_start = time.tick_now()
        }
        infer_decoded_struct_lifetimes(&e)
        infer_proc_lifetime_facts(&e)
        err_classify, ok_classify := classify_def_initializers(&e)
        if profile != nil {
            profile.analysis_ns += profile_elapsed_ns(analysis_start)
        }
        if !ok_classify {
            return result, err_classify, false
        }
    }
    needs_core_strings_import := decls_need_core_strings_import(emitted_decls)
    needs_core_fmt_import := decls_need_core_fmt_import(emitted_decls)
    emitted_core_strings_import := false
    emitted_core_fmt_import := false
    for decl, idx in emitted_decls {
        e.current_source_path = decl.source_path
        e.current_source_file = decl.source_file
        if decl.kind != .Package && decl.kind != .Import {
            emit_core_strings_import(&e, &emitted_core_strings_import, needs_core_strings_import)
            emit_core_fmt_import(&e, &emitted_core_fmt_import, needs_core_fmt_import)
        }
        start_line := e.line
        err_decl, ok_decl := emit_decl(&e, decl)
        if !ok_decl {
            err_decl.source_path = decl.source_path
            err_decl.source_file = decl.source_file
            return result, err_decl, false
        }
        emitted_lines := e.line > start_line
        end_line := e.line - 1
        if !emitted_lines {
            end_line = start_line
        }
        source_map_start: time.Tick
        if profile != nil {
            source_map_start = time.tick_now()
        }
        append(&result.source_map, Source_Map_Entry{
            generated_start_line = start_line,
            generated_end_line   = end_line,
            source_span          = decl.span,
            source_path          = strings.clone(decl.source_path),
        })
        if profile != nil {
            profile.source_map_ns += profile_elapsed_ns(source_map_start)
        }
        if idx+1 < len(emitted_decls) && emitted_lines {
            if e.attach_next_decl {
                e.attach_next_decl = false
                continue
            }
            strings.write_byte(&e.builder, '\n')
            e.line += 1
        }
    }
    err_runtime_defs, ok_runtime_defs := emit_runtime_def_lifecycle(&e, emitted_decls)
    if !ok_runtime_defs {
        return result, err_runtime_defs, false
    }
    emit_core_strings_import(&e, &emitted_core_strings_import, needs_core_strings_import)
    emit_core_fmt_import(&e, &emitted_core_fmt_import, needs_core_fmt_import)
    err_specializations, ok_specializations := emit_captured_proc_specializations(&e)
    if !ok_specializations {
        return result, err_specializations, false
    }
    if suppress_shared_helpers && parallel_helpers_needed(features) {
        emit_raw_newline(&e)
        emitted := false
        emit_parallel_helpers(&e, features, &emitted)
    } else if !suppress_shared_helpers {
        emit_data_decode_aliases(&e, features)
        emit_core_helpers(&e, features)
    }
    output := strings.clone(strings.to_string(e.builder))
    late_imports: [dynamic]string
    if output_needs_core_slice_import(output, features) &&
       !output_has_import_line(output, "import kvist_slice \"core:slice\"") {
        append(&late_imports, "import kvist_slice \"core:slice\"")
    }
    if !emitted_core_strings_import &&
       (features_need_core_strings_import(features) ||
        strings.contains(output, "strings.")) &&
       !output_has_import_path(output, "core:strings") {
        append(&late_imports, "import strings \"core:strings\"")
    }
    if !emitted_core_fmt_import && features_need_core_fmt_import(features) &&
       !output_has_import_path(output, "core:fmt") {
        append(&late_imports, "import \"core:fmt\"")
    }
    if features_need_core_thread_import(features) &&
       !output_has_import_path(output, "core:thread") {
        append(&late_imports, "import thread \"core:thread\"")
    }
    if features_need_core_chan_import(features) &&
       !output_has_import_path(output, "core:sync/chan") {
        append(&late_imports, "import chan \"core:sync/chan\"")
    }
    if features_need_core_os_import(features) &&
       !output_has_import_path(output, "core:os") {
        append(&late_imports, "import os \"core:os\"")
    }
    if features_need_base_runtime_import(features) &&
       !output_has_import_line(output, "import kvist_runtime \"base:runtime\"") {
        append(&late_imports, "import kvist_runtime \"base:runtime\"")
    }
    if strings.contains(output, "kvist_condition_strconv.") &&
       !output_has_import_line(output, "import kvist_condition_strconv \"core:strconv\"") {
        append(&late_imports, "import kvist_condition_strconv \"core:strconv\"")
    }
    if features_need_data_runtime_imports(features) &&
       !output_has_import_line(output, "import kvist_sync \"core:sync\"") {
        append(&late_imports, "import kvist_sync \"core:sync\"")
    }
    if len(late_imports) > 0 {
        adjusted_output, added_lines := inject_imports_into_output_header(output, late_imports[:])
        delete(output)
        output = adjusted_output
        shift_source_map_lines(&result.source_map, added_lines)
    }
    if features.dynamic_literals {
        output_builder := strings.builder_make()
        defer strings.builder_destroy(&output_builder)
        strings.write_string(&output_builder, "#+feature dynamic-literals\n")
        strings.write_string(&output_builder, output)
        for &entry in result.source_map {
            entry.generated_start_line += 1
            entry.generated_end_line += 1
        }
        result.output = strings.clone(strings.to_string(output_builder))
        delete(output)
        if aggregate_features != nil {
            merge_emitter_features(aggregate_features, features)
        }
        return result, {}, true
    }
    result.output = output
    if aggregate_features != nil {
        merge_emitter_features(aggregate_features, features)
    }
    return result, {}, true
}

emit_decls_with_source_map :: proc(decls: []IR_Decl, profile: ^Compile_Profile = nil) -> (Emit_Result, Compile_Error, bool) {
    return emit_selected_decls_with_source_map(decls, decls, profile = profile)
}

emit_eval_decls_with_source_map :: proc(
    decls: []IR_Decl,
    eval_form: CST_Form,
    no_print: bool,
    entry_name := "main",
    export_entry := false,
    initialize_context := false,
    repl_proc_names: []string = nil,
    repl_prior_proc_names: []string = nil,
    repl_value_names: []string = nil,
    repl_current_value_names: []string = nil,
    repl_var_names: []string = nil,
    repl_current_var_names: []string = nil,
    repl_recent_result_types: []string = nil,
    skip_eval := false,
    repl_inspect_only := false,
    repl_inspection_result_slot := "",
    repl_inspection_page_offset := 0,
    repl_inspection_page_limit := 0,
    repl_debug_capture_values := true,
) -> (Emit_Result, Compile_Error, bool) {
    result := Emit_Result{}
    features := Emitter_Features{}
    captured_specializations: [dynamic]Captured_Proc_Specialization
    all_repl_value_names: [dynamic]string
    append(&all_repl_value_names, ..repl_value_names)
    all_repl_var_names: [dynamic]string
    append(&all_repl_var_names, ..repl_var_names)
    for _, result_idx in repl_recent_result_types {
        append(
            &all_repl_value_names,
            fmt.tprintf("kvist_repl_star_%d", result_idx+1),
        )
    }
    defer delete(all_repl_value_names)
    defer delete(all_repl_var_names)
    e := Emitter{
        builder  = strings.builder_make(),
        decls    = decls,
        features = &features,
        source_map = &result.source_map,
        warnings = &result.warnings,
        line     = 1,
        captured_proc_specializations = &captured_specializations,
        repl_value_names = all_repl_value_names[:],
        repl_var_names = all_repl_var_names[:],
        repl_recent_result_types = repl_recent_result_types,
        repl_current_proc_names = repl_proc_names,
        repl_debug_enabled = initialize_context,
        repl_debug_capture_values = repl_debug_capture_values,
    }
    defer strings.builder_destroy(&e.builder)
    for decl in decls {
        if decl.kind == .Struct {
            append(&e.structs, decl.struct_decl)
        }
        if decl.kind == .Union {
            append(&e.unions, decl.union_decl)
        }
    }
    eval_lifetime_form := eval_form
    infer_decoded_struct_lifetimes(&e, &eval_lifetime_form)
    infer_proc_lifetime_facts(&e)
    err_classify, ok_classify := classify_def_initializers(&e)
    if !ok_classify {
        return result, err_classify, false
    }
    package_once_value_names: [dynamic]string
    package_once_var_names: [dynamic]string
    defer delete(package_once_value_names)
    defer delete(package_once_var_names)
    for &decl in e.decls {
        if decl.kind == .Const && name_in_list(repl_value_names, decl.const_decl.name) {
            decl.const_decl.init_kind = .Static
        }
        if !initialize_context {
            continue
        }
        if decl.kind == .Const &&
           decl.const_decl.init_kind == .Runtime &&
           !name_in_list(repl_value_names, decl.const_decl.name) {
            append(&package_once_value_names, decl.const_decl.name)
            append(&all_repl_value_names, decl.const_decl.name)
        }
        if decl.kind == .Var &&
           !name_in_list(repl_var_names, decl.var_decl.name) {
            if !decl.var_decl.has_ty && decl.var_decl.has_value {
                if inferred_ty, inferred :=
                    obvious_form_type(&e, decl.var_decl.value);
                   inferred {
                    decl.var_decl.has_ty = true
                    decl.var_decl.ty = inferred_ty
                }
            }
            if !decl.var_decl.has_ty {
                return result, Compile_Error{
                    message = "native REPL package defvar requires an explicit or inferable value type",
                    span = decl.span,
                }, false
            }
            append(&package_once_var_names, decl.var_decl.name)
            append(&all_repl_var_names, decl.var_decl.name)
        }
    }
    e.repl_value_names = all_repl_value_names[:]
    e.repl_var_names = all_repl_var_names[:]
    needs_core_strings_import := decls_need_core_strings_import(decls) ||
                                 form_uses_core_strings(eval_form)
    needs_core_fmt_import := decls_need_core_fmt_import(decls) ||
                             (!decls_have_core_fmt_import(decls) &&
                              (form_uses_core_fmt(eval_form) || initialize_context))
    emitted_core_strings_import := false
    emitted_core_fmt_import := false
    for decl, idx in decls {
        e.current_source_path = decl.source_path
        e.current_source_file = decl.source_file
        if decl.kind != .Package && decl.kind != .Import {
            emit_core_strings_import(&e, &emitted_core_strings_import, needs_core_strings_import)
            emit_core_fmt_import(&e, &emitted_core_fmt_import, needs_core_fmt_import)
        }
        start_line := e.line
        is_prior_repl_proc := false
        is_current_repl_proc := false
        is_prior_repl_value := false
        is_current_repl_value := false
        is_prior_repl_var := false
        is_current_repl_var := false
        is_package_once_value := false
        is_package_once_var := false
        if decl.kind == .Proc {
            for name in repl_prior_proc_names {
                if decl.proc_decl.name == name {
                    is_prior_repl_proc = true
                    break
                }
            }
            is_current_repl_proc =
                name_in_list(repl_proc_names, decl.proc_decl.name)
        }
        if decl.kind == .Const {
            is_package_once_value =
                name_in_list(package_once_value_names[:], decl.const_decl.name)
            is_prior_repl_value = name_in_list(repl_value_names, decl.const_decl.name) &&
                                  !name_in_list(repl_current_value_names, decl.const_decl.name)
            is_current_repl_value = name_in_list(repl_current_value_names, decl.const_decl.name)
        }
        if decl.kind == .Var {
            is_package_once_var =
                name_in_list(package_once_var_names[:], decl.var_decl.name)
            is_prior_repl_var = name_in_list(repl_var_names, decl.var_decl.name) &&
                                !name_in_list(repl_current_var_names, decl.var_decl.name)
            is_current_repl_var = name_in_list(repl_current_var_names, decl.var_decl.name)
        }
        err_decl: Compile_Error
        ok_decl := true
        if is_prior_repl_proc {
            proc_decl := decl.proc_decl
            adapter := repl_proc_adapter_text(&e, &proc_decl)
            emit_prefixed_expr(&e, "", adapter)
            delete(adapter)
        } else if is_prior_repl_value ||
                  is_current_repl_value ||
                  is_package_once_value {
            const_decl := decl.const_decl
            adapter := repl_value_adapter_text(&e, &const_decl)
            if is_current_repl_value || is_package_once_value {
                delete(adapter)
                adapter = repl_current_value_text(&e, &const_decl)
            }
            emit_prefixed_expr(&e, "", adapter)
            delete(adapter)
        } else if is_prior_repl_var ||
                  is_current_repl_var ||
                  is_package_once_var {
            var_decl := decl.var_decl
            adapter := repl_var_adapter_text(&e, &var_decl)
            if is_current_repl_var || is_package_once_var {
                delete(adapter)
                adapter = repl_current_var_text(&e, &var_decl)
            }
            emit_prefixed_expr(&e, "", adapter)
            delete(adapter)
        } else {
            if is_current_repl_proc &&
               !e.repl_dispatch_adapters_emitted {
                for current_name in repl_proc_names {
                    if current_decl, found :=
                        find_proc_decl(&e, current_name);
                       found {
                        adapter_name :=
                            repl_dispatch_proc_name(current_name)
                        adapter := repl_proc_adapter_text(
                            &e,
                            current_decl,
                            adapter_name,
                            current_name,
                        )
                        emit_prefixed_expr(&e, "", adapter)
                        delete(adapter)
                    }
                }
                e.repl_dispatch_adapters_emitted = true
            }
            err_decl, ok_decl = emit_decl(&e, decl)
        }
        if !ok_decl {
            err_decl.source_path = decl.source_path
            err_decl.source_file = decl.source_file
            return result, err_decl, false
        }
        emitted_lines := e.line > start_line
        end_line := e.line - 1
        if !emitted_lines {
            end_line = start_line
        }
        append(&result.source_map, Source_Map_Entry{
            generated_start_line = start_line,
            generated_end_line   = end_line,
            source_span          = decl.span,
            source_path          = strings.clone(decl.source_path),
        })
        if idx+1 < len(decls) && emitted_lines {
            if e.attach_next_decl {
                e.attach_next_decl = false
                continue
            }
            strings.write_byte(&e.builder, '\n')
            e.line += 1
        }
    }
    emit_core_strings_import(&e, &emitted_core_strings_import, needs_core_strings_import)
    emit_core_fmt_import(&e, &emitted_core_fmt_import, needs_core_fmt_import)
    if !initialize_context {
        err_runtime_defs, ok_runtime_defs := emit_runtime_def_lifecycle(&e)
        if !ok_runtime_defs {
            return result, err_runtime_defs, false
        }
    }

    if e.line > 1 {
        strings.write_byte(&e.builder, '\n')
        e.line += 1
    }

    if initialize_context {
        emitted_type_abis := false
        for decl in decls {
            type_name := ""
            #partial switch decl.kind {
            case .Struct:
                type_name = decl.struct_decl.name
            case .Enum:
                type_name = decl.enum_decl.name
            case .Union:
                type_name = decl.union_decl.name
            case .Const:
                if decl.const_decl.is_type_alias {
                    type_name = decl.const_decl.name
                }
            }
            if type_name == "" {
                continue
            }
            value_signature := repl_value_signature(type_name, &e)
            type_signature :=
                fmt.tprintf(
                    "type:%s",
                    value_signature[len("value:"):],
                )
            emit_line(
                &e,
                fmt.tprintf(
                    "kvist_repl_definition_abi_%s :: %q",
                    type_name,
                    type_signature,
                ),
            )
            emitted_type_abis = true
            delete(value_signature)
        }
        if emitted_type_abis {
            strings.write_byte(&e.builder, '\n')
            e.line += 1
        }
        for result_ty, result_idx in repl_recent_result_types {
            result_name := fmt.tprintf("kvist_repl_star_%d", result_idx+1)
            result_decl := Const_Decl{
                name = result_name,
                has_ty = true,
                ty = result_ty,
            }
            adapter := repl_value_adapter_text(&e, &result_decl)
            emit_prefixed_expr(&e, "", adapter)
            delete(adapter)
            strings.write_byte(&e.builder, '\n')
            e.line += 1
        }
    }

    eval_result_ty := ""
    captures_eval_result := false
    has_result_transfer_adapter := false
    preserves_recent_result_history :=
        eval_form.kind == .Symbol &&
        (eval_form.text == "kvist_repl_star_1" ||
         eval_form.text == "kvist_repl_star_2" ||
         eval_form.text == "kvist_repl_star_3")
    if initialize_context && !skip_eval {
        inferred_ty, inferred := obvious_form_type(&e, eval_form)
        storage_program := IR_Program{}
        append(&storage_program.decls, ..decls)
        defer delete(storage_program.decls)
        if inferred &&
           repl_storage_type_supported(
               storage_program,
               inferred_ty,
               allow_dynamic_array = true,
               allow_slice = true,
           ) {
            eval_result_ty = inferred_ty
            captures_eval_result = true
            if repl_result_needs_snapshot(&e, eval_result_ty) {
                snapshot := repl_snapshot_value_text(
                    &e,
                    eval_result_ty,
                    "value",
                )
                emit_line(
                    &e,
                    fmt.tprintf(
                        "kvist_repl_snapshot_value :: proc(value: %s) -> %s %c return %s %c",
                        eval_result_ty,
                        eval_result_ty,
                        '{',
                        snapshot,
                        '}',
                    ),
                )
                delete(snapshot)
            }
            emit_line(&e, fmt.tprintf("kvist_repl_result_storage: %s", eval_result_ty))
            emit_line(
                &e,
                fmt.tprintf(
                    "kvist_repl_result_impl :: proc() -> %s %c return kvist_repl_result_storage %c",
                    eval_result_ty,
                    '{',
                    '}',
                ),
            )
            transfer_body :=
                repl_result_transfer_body_text(
                    &e,
                    eval_result_ty,
                    "value",
                )
            if transfer_body != "" {
                has_data_result :=
                    type_text_has_repl_result_data(
                        &e,
                        eval_result_ty,
                    )
                if has_data_result {
                    emit_line(
                        &e,
                        `kvist_repl_retain_data_allocations :: proc(value: Data, visited: ^map[^Data_Node]bool) {
    if value.node == nil || value.node in visited^ { return }
    visited^[value.node] = true
    kvist_repl_host.retain_result_allocation(kvist_repl_host.ctx, rawptr(value.node))
    kvist_repl_host.retain_result_allocation(kvist_repl_host.ctx, rawptr(raw_data(value.node.text)))
    kvist_repl_host.retain_result_allocation(kvist_repl_host.ctx, rawptr(raw_data(value.node.items)))
    kvist_repl_host.retain_result_allocation(kvist_repl_host.ctx, rawptr(raw_data(value.node.entries)))
    for item in value.node.items { kvist_repl_retain_data_allocations(item, visited) }
    for entry in value.node.entries {
        kvist_repl_retain_data_allocations(entry.key, visited)
        kvist_repl_retain_data_allocations(entry.value, visited)
    }
}`,
                    )
                }
                transfer_setup := ""
                if has_data_result {
                    transfer_setup =
                        "kvist_repl_data_visited := make(map[^Data_Node]bool); defer delete(kvist_repl_data_visited); "
                }
                emit_line(
                    &e,
                    fmt.tprintf(
                        "kvist_repl_transfer_result_allocations :: proc(value: %s) %c %s%s %c",
                        eval_result_ty,
                        '{',
                        transfer_setup,
                        transfer_body,
                        '}',
                    ),
                )
                has_result_transfer_adapter = true
                delete(transfer_body)
            }
            if repl_inspect_only {
                signature := repl_value_signature(eval_result_ty, &e)
                emit_line(
                    &e,
                    fmt.tprintf(
                        "kvist_repl_inspection_abi :: %q",
                        signature,
                    ),
                )
                delete(signature)
            }
            strings.write_byte(&e.builder, '\n')
            e.line += 1
        } else if inferred &&
                  repl_storage_type_requires_lifecycle(
                      storage_program,
                      inferred_ty,
                  ) {
            if repl_inspect_only {
                return result, Compile_Error{
                    message =
                        "native inspection cannot retain a pointer, foreign view, or opaque resource; use an owned copy until explicit lifecycle adapters are available",
                    span = eval_form.span,
                }, false
            }
            emit_coded_warning(
                &e,
                fmt.tprintf(
                    "REPL result of type %s is evaluated for this submission but is not retained in *1; use an owned copy until explicit pointer, foreign-view, and opaque-resource lifecycle adapters are available",
                    inferred_ty,
                ),
                eval_form.span,
                .Repl_Unretained_Lifecycle,
            )
        }
    }

    if initialize_context {
        for value_name in repl_current_value_names {
            const_decl: ^Const_Decl
            for &decl in e.decls {
                if decl.kind == .Const &&
                   decl.const_decl.name == value_name {
                    const_decl = &decl.const_decl
                }
            }
            if const_decl == nil ||
               !type_text_has_repl_borrowed_view(&e, const_decl.ty) {
                continue
            }
            snapshot := repl_snapshot_value_text(
                &e,
                const_decl.ty,
                "value",
            )
            emit_line(
                &e,
                fmt.tprintf(
                    "%s__repl_snapshot_value :: proc(value: %s) -> %s %c return %s %c",
                    value_name,
                    const_decl.ty,
                    const_decl.ty,
                    '{',
                    snapshot,
                    '}',
                ),
            )
            delete(snapshot)
        }
        for var_name in repl_current_var_names {
            var_decl: ^Var_Decl
            for &decl in e.decls {
                if decl.kind == .Var &&
                   decl.var_decl.name == var_name {
                    var_decl = &decl.var_decl
                }
            }
            if var_decl == nil ||
               !type_text_has_repl_borrowed_view(&e, var_decl.ty) {
                continue
            }
            snapshot := repl_snapshot_value_text(
                &e,
                var_decl.ty,
                "value",
            )
            emit_line(
                &e,
                fmt.tprintf(
                    "%s__repl_snapshot_value :: proc(value: %s) -> %s %c return %s %c",
                    var_name,
                    var_decl.ty,
                    var_decl.ty,
                    '{',
                    snapshot,
                    '}',
                ),
            )
            delete(snapshot)
        }
    }

    repl_binding_allocation_adapters :=
        make(map[string]bool)
    defer delete(repl_binding_allocation_adapters)
    if initialize_context {
        binding_names: [dynamic]string
        defer delete(binding_names)
        append(&binding_names, ..package_once_value_names[:])
        append(&binding_names, ..package_once_var_names[:])
        append(&binding_names, ..repl_current_value_names[:])
        append(&binding_names, ..repl_current_var_names[:])
        for binding_name in binding_names {
            if repl_binding_allocation_adapters[binding_name] {
                continue
            }
            binding_ty := ""
            for &decl in e.decls {
                if decl.kind == .Const &&
                   decl.const_decl.name == binding_name {
                    binding_ty = decl.const_decl.ty
                } else if decl.kind == .Var &&
                          decl.var_decl.name == binding_name {
                    binding_ty = decl.var_decl.ty
                }
            }
            if binding_ty != "" &&
               emit_repl_binding_allocation_adapter(
                   &e,
                   binding_name,
                   binding_ty,
               ) {
                repl_binding_allocation_adapters[
                    binding_name
                ] = true
            }
        }
        if len(repl_binding_allocation_adapters) > 0 {
            strings.write_byte(&e.builder, '\n')
            e.line += 1
        }
    }

    start_line := e.line
    if export_entry {
        emit_line(&e, "@(export)")
    }
    if export_entry && initialize_context {
        emit_line(&e, fmt.tprintf("%s :: proc \"c\" (host: ^Kvist_Repl_Host_API) %c", entry_name, '{'))
    } else if export_entry {
        emit_line(&e, fmt.tprintf("%s :: proc \"c\" () %c", entry_name, '{'))
    } else {
        emit_line(&e, fmt.tprintf("%s :: proc() %c", entry_name, '{'))
    }
    e.indent += 1
    if initialize_context {
        emit_line(&e, "context = repl_runtime.default_context()")
        emit_line(&e, "kvist_repl_host = host")
        emit_line(&e, "context.allocator = host.allocator")
        for decl in e.decls {
            if decl.kind == .Import &&
               strings.contains(decl.import_decl.path, "kvist_condition") {
                condition_runtime_alias := decl.import_decl.alias
                if !decl.import_decl.has_alias {
                    condition_runtime_alias = "kvist_condition"
                }
                emit_line(
                    &e,
                    fmt.tprintf(
                        "%s.set_repl_host(host.ctx, transmute(%s.Repl_Push_Handler)host.condition_handler_push, host.condition_handler_pop, host.condition_handler_count, transmute(%s.Repl_Handler_Kind_At)host.condition_handler_kind_at, host.condition_handler_at)",
                        condition_runtime_alias,
                        condition_runtime_alias,
                        condition_runtime_alias,
                    ),
                )
                break
            }
        }
    }
    // Package globals are compiled into every native generation, but their
    // authoritative storage lives in the worker registry. Register each
    // mutable cell once, then initialize only the generation that won the
    // registration check.
    for var_name in package_once_var_names {
        var_decl: ^Var_Decl
        for &decl in e.decls {
            if decl.kind == .Var && decl.var_decl.name == var_name {
                var_decl = &decl.var_decl
                break
            }
        }
        if var_decl == nil {
            continue
        }
        signature := repl_var_signature(var_decl.ty, &e)
        initialize_flag := fmt.tprintf("%s__repl_initialize", var_name)
        emit_line(
            &e,
            fmt.tprintf(
                "%s := host.lookup_proc(host.ctx, %q, %q) == nil",
                initialize_flag,
                var_name,
                signature,
            ),
        )
        emit_line(&e, fmt.tprintf("if %s %c", initialize_flag, '{'))
        e.indent += 1
        emit_line(
            &e,
            fmt.tprintf(
                "host.register_proc(host.ctx, %q, %q, transmute(rawptr)%s)",
                var_name,
                signature,
                fmt.tprintf("%s__repl_impl", var_name),
            ),
        )
        emit_line(
            &e,
            fmt.tprintf(
                "host.register_state(host.ctx, %q, %q, size_of(%s), align_of(%s), %s__repl_checkpoint_clone, %s__repl_checkpoint_restore)",
                var_name,
                signature,
                var_decl.ty,
                var_decl.ty,
                var_name,
                var_name,
            ),
        )
        e.indent -= 1
        emit_line(&e, "}")
        delete(signature)
    }
    for var_name in package_once_var_names {
        var_decl: ^Var_Decl
        for &decl in e.decls {
            if decl.kind == .Var && decl.var_decl.name == var_name {
                var_decl = &decl.var_decl
                break
            }
        }
        if var_decl == nil || !var_decl.has_value {
            continue
        }
        value, err_value, ok_value :=
            emit_expr_for_expected_type(&e, var_decl.value, var_decl.ty)
        if !ok_value {
            return result, err_value, false
        }
        stored_value := value
        if type_text_is_map(var_decl.ty) {
            stored_value =
                managed_clone_value_text(&e, var_decl.ty, value)
        }
        emit_line(
            &e,
            fmt.tprintf(
                "if %s__repl_initialize %c %s__repl_storage = %s %c",
                var_name,
                '{',
                var_name,
                stored_value,
                '}',
            ),
        )
        if repl_binding_allocation_adapters[var_name] {
            emit_line(
                &e,
                fmt.tprintf(
                    "if %s__repl_initialize %c %s__repl_register_allocations(%s__repl_storage) %c",
                    var_name,
                    '{',
                    var_name,
                    var_name,
                    '}',
                ),
            )
        }
        if stored_value != value {
            delete(stored_value)
        }
        delete(value)
    }
    // Runtime-initialized immutable defs retain their first value and side
    // effects for the worker lifetime. Later generations bind to that exact
    // typed value instead of replaying the initializer.
    for value_name in package_once_value_names {
        const_decl: ^Const_Decl
        for &decl in e.decls {
            if decl.kind == .Const && decl.const_decl.name == value_name {
                const_decl = &decl.const_decl
                break
            }
        }
        if const_decl == nil {
            continue
        }
        signature := repl_value_signature(const_decl.ty, &e)
        emit_line(
            &e,
            fmt.tprintf(
                "if host.lookup_proc(host.ctx, %q, %q) == nil %c",
                value_name,
                signature,
                '{',
            ),
        )
        e.indent += 1
        value, err_value, ok_value :=
            emit_expr_for_expected_type(&e, const_decl.value, const_decl.ty)
        if !ok_value {
            delete(signature)
            return result, err_value, false
        }
        stored_value := value
        if type_text_is_map(const_decl.ty) {
            stored_value =
                managed_clone_value_text(&e, const_decl.ty, value)
        } else if type_text_is_managed_value(&e, const_decl.ty) &&
                  !form_produces_owned_managed_type(
                      &e,
                      const_decl.value,
                      const_decl.ty,
                  ) {
            stored_value =
                emit_call_text("kvist_data_retain", []string{value})
        }
        emit_line(
            &e,
            fmt.tprintf(
                "%s__repl_storage = %s",
                value_name,
                stored_value,
            ),
        )
        if repl_binding_allocation_adapters[value_name] {
            emit_line(
                &e,
                fmt.tprintf(
                    "%s__repl_register_allocations(%s__repl_storage)",
                    value_name,
                    value_name,
                ),
            )
        }
        if stored_value != value {
            delete(stored_value)
        }
        delete(value)
        emit_line(
            &e,
            fmt.tprintf(
                "host.register_proc(host.ctx, %q, %q, transmute(rawptr)%s)",
                value_name,
                signature,
                fmt.tprintf("%s__repl_impl", value_name),
            ),
        )
        e.indent -= 1
        emit_line(&e, "}")
        delete(signature)
    }
    // Register current mutable slots before immutable initializers. A batch
    // such as `(defvar count ...) (def value ... count ...)` must be able to
    // resolve `count` while initializing `value`, while procedure bodies keep
    // using the host adapter so later compatible redefinitions remain live.
    for var_name in repl_current_var_names {
        var_decl: ^Var_Decl
        for &decl in e.decls {
            if decl.kind == .Var && decl.var_decl.name == var_name {
                var_decl = &decl.var_decl
            }
        }
        if var_decl != nil {
            if var_decl.has_value {
                initializer := var_decl.value
                if type_text_has_repl_borrowed_view(&e, var_decl.ty) {
                    initializer =
                        repl_snapshot_tail_form_named(
                            var_decl.value,
                            fmt.tprintf(
                                "%s__repl_snapshot_value",
                                var_name,
                            ),
                        )
                }
                value, err_value, ok_value :=
                    emit_expr_for_expected_type(&e, initializer, var_decl.ty)
                if !ok_value {
                    return result, err_value, false
                }
                stored_value := value
                if type_text_is_map(var_decl.ty) {
                    stored_value =
                        managed_clone_value_text(&e, var_decl.ty, value)
                }
                emit_line(
                    &e,
                    fmt.tprintf(
                        "%s__repl_storage = %s",
                        var_name,
                        stored_value,
                    ),
                )
                if repl_binding_allocation_adapters[var_name] {
                    emit_line(
                        &e,
                        fmt.tprintf(
                            "%s__repl_register_allocations(%s__repl_storage)",
                            var_name,
                            var_name,
                        ),
                    )
                }
                if stored_value != value {
                    delete(stored_value)
                }
                delete(value)
            }
            signature := repl_var_signature(var_decl.ty, &e)
            emit_line(&e, fmt.tprintf(
                "host.register_proc(host.ctx, %q, %q, transmute(rawptr)%s)",
                var_name, signature, fmt.tprintf("%s__repl_impl", var_name),
            ))
            emit_line(&e, fmt.tprintf(
                "host.register_state(host.ctx, %q, %q, size_of(%s), align_of(%s), %s__repl_checkpoint_clone, %s__repl_checkpoint_restore)",
                var_name, signature, var_decl.ty, var_decl.ty,
                var_name, var_name,
            ))
            delete(signature)
        }
    }
    for value_name in repl_current_value_names {
        const_decl: ^Const_Decl
        for &decl in e.decls {
            if decl.kind == .Const && decl.const_decl.name == value_name {
                const_decl = &decl.const_decl
            }
        }
        if const_decl != nil {
            initializer := const_decl.value
            if type_text_has_repl_borrowed_view(&e, const_decl.ty) {
                initializer =
                    repl_snapshot_tail_form_named(
                        const_decl.value,
                        fmt.tprintf(
                            "%s__repl_snapshot_value",
                            value_name,
                        ),
                    )
            }
            value, err_value, ok_value :=
                emit_expr_for_expected_type(&e, initializer, const_decl.ty)
            if !ok_value {
                return result, err_value, false
            }
            stored_value := value
            if type_text_is_map(const_decl.ty) {
                stored_value =
                    managed_clone_value_text(&e, const_decl.ty, value)
            }
            emit_line(
                &e,
                fmt.tprintf(
                    "%s__repl_storage = %s",
                    value_name,
                    stored_value,
                ),
            )
            if repl_binding_allocation_adapters[value_name] {
                emit_line(
                    &e,
                    fmt.tprintf(
                        "%s__repl_register_allocations(%s__repl_storage)",
                        value_name,
                        value_name,
                    ),
                )
            }
            if stored_value != value {
                delete(stored_value)
            }
            delete(value)
            signature := repl_value_signature(const_decl.ty, &e)
            emit_line(
                &e,
                fmt.tprintf(
                    "host.register_proc(host.ctx, %q, %q, transmute(rawptr)%s)",
                    value_name,
                    signature,
                    fmt.tprintf("%s__repl_impl", value_name),
                ),
            )
            delete(signature)
        }
    }
    for repl_proc_name in repl_proc_names {
        repl_proc_signature_text := ""
        if proc_decl, found := find_proc_decl(&e, repl_proc_name); found {
            repl_proc_signature_text = repl_proc_signature(proc_decl, &e)
        }
        emit_line(
            &e,
            fmt.tprintf(
                "host.register_proc(host.ctx, %q, %q, transmute(rawptr)%s)",
                repl_proc_name,
                repl_proc_signature_text,
                repl_proc_name,
            ),
        )
        delete(repl_proc_signature_text)
    }
    if skip_eval {
        // A declaration generation performs its work through registration.
    } else if captures_eval_result {
        captured_form := eval_form
        if repl_result_needs_snapshot(&e, eval_result_ty) {
            captured_form = repl_snapshot_tail_form(eval_form)
        }
        value, err_value, ok_value :=
            emit_expr_for_expected_type(&e, captured_form, eval_result_ty)
        if !ok_value {
            return result, err_value, false
        }
        emit_line(&e, fmt.tprintf("kvist_repl_result_value := %s", value))
        delete(value)
        emit_line(
            &e,
            "if host.abort_requested(host.ctx) { return }",
        )
        emit_line(
            &e,
            "kvist_repl_result_storage = kvist_repl_result_value",
        )
        if !repl_inspect_only &&
           !preserves_recent_result_history {
            signature := repl_value_signature(eval_result_ty, &e)
            emit_line(
                &e,
                fmt.tprintf(
                    "host.register_result(host.ctx, %q, transmute(rawptr)kvist_repl_result_impl)",
                    signature,
                ),
            )
            delete(signature)
            if has_result_transfer_adapter {
                emit_line(
                    &e,
                    "kvist_repl_transfer_result_allocations(kvist_repl_result_storage)",
                )
            }
        } else if repl_inspection_result_slot != "" {
            signature := repl_value_signature(eval_result_ty, &e)
            emit_line(
                &e,
                fmt.tprintf(
                    "host.register_proc(host.ctx, %q, %q, transmute(rawptr)kvist_repl_result_impl)",
                    repl_inspection_result_slot,
                    signature,
                ),
            )
            delete(signature)
        }
        inspection_pageable :=
            type_text_is_map(eval_result_ty) ||
            strings.has_prefix(eval_result_ty, "[dynamic]") ||
            strings.has_prefix(eval_result_ty, "[]") ||
            (strings.has_prefix(eval_result_ty, "[") &&
             strings.index(eval_result_ty, "]") > 1)
        if repl_inspection_page_limit > 0 && inspection_pageable {
            emit_line(
                &e,
                "kvist_repl_page_output := strings.builder_make()",
            )
            emit_line(
                &e,
                "defer strings.builder_destroy(&kvist_repl_page_output)",
            )
            emit_line(
                &e,
                fmt.tprintf(
                    `fmt.sbprintf(&kvist_repl_page_output, "KVIST_REPL_LAYOUT\t%%d\t%%d\n", size_of(%s), align_of(%s))`,
                    eval_result_ty,
                    eval_result_ty,
                ),
            )
            emit_line(
                &e,
                `fmt.sbprintf(&kvist_repl_page_output, "KVIST_REPL_PAGE_TOTAL\t%d\n", len(kvist_repl_result_storage))`,
            )
            emit_line(
                &e,
                fmt.tprintf(
                    "kvist_repl_page_start := min(%d, len(kvist_repl_result_storage))",
                    repl_inspection_page_offset,
                ),
            )
            emit_line(
                &e,
                fmt.tprintf(
                    "kvist_repl_page_end := min(kvist_repl_page_start + %d, len(kvist_repl_result_storage))",
                    repl_inspection_page_limit,
                ),
            )
            if type_text_is_map(eval_result_ty) {
                emit_line(
                    &e,
                    "kvist_repl_page_entries := make([dynamic]string, 0, len(kvist_repl_result_storage))",
                )
                emit_line(&e, "defer {")
                e.indent += 1
                emit_line(&e, "for kvist_repl_page_entry in kvist_repl_page_entries { delete(kvist_repl_page_entry) }")
                emit_line(&e, "delete(kvist_repl_page_entries)")
                e.indent -= 1
                emit_line(&e, "}")
                emit_line(&e, "for kvist_repl_page_key, kvist_repl_page_value in kvist_repl_result_storage {")
                e.indent += 1
                emit_line(
                    &e,
                    `append(&kvist_repl_page_entries, fmt.aprintf("%#v\t%#v", kvist_repl_page_key, kvist_repl_page_value))`,
                )
                e.indent -= 1
                emit_line(&e, "}")
                emit_line(&e, "kvist_repl_slice.sort(kvist_repl_page_entries[:])")
                emit_line(&e, "for kvist_repl_page_index in kvist_repl_page_start ..< kvist_repl_page_end {")
                e.indent += 1
                emit_line(
                    &e,
                    `fmt.sbprintf(&kvist_repl_page_output, "KVIST_REPL_PAGE_ENTRY\t%s\n", kvist_repl_page_entries[kvist_repl_page_index])`,
                )
                e.indent -= 1
                emit_line(&e, "}")
            } else {
                emit_line(&e, "for kvist_repl_page_index in kvist_repl_page_start ..< kvist_repl_page_end {")
                e.indent += 1
                emit_line(
                    &e,
                    `fmt.sbprintf(&kvist_repl_page_output, "KVIST_REPL_PAGE_ITEM\t%d\t%#v\n", kvist_repl_page_index, kvist_repl_result_storage[kvist_repl_page_index])`,
                )
                e.indent -= 1
                emit_line(&e, "}")
            }
            emit_line(
                &e,
                "kvist_repl_page_text := strings.to_string(kvist_repl_page_output)",
            )
            emit_line(
                &e,
                "host.emit_output(host.ctx, Kvist_Repl_Rendered_Value{data = raw_data(kvist_repl_page_text), length = len(kvist_repl_page_text)})",
            )
        } else if !no_print {
            if eval_result_ty == "Data" {
                emit_line_mapped(
                    &e,
                    "kvist_repl_rendered_data := kvist_data_repr(kvist_repl_result_storage)",
                    eval_form.span,
                )
                emit_line(&e, "defer delete(kvist_repl_rendered_data)")
                if repl_inspect_only {
                    emit_line_mapped(
                        &e,
                        fmt.tprintf(
                            `kvist_repl_output := fmt.aprintf("KVIST_REPL_LAYOUT\t%%d\t%%d\n%%s\n", size_of(%s), align_of(%s), kvist_repl_rendered_data)`,
                            eval_result_ty,
                            eval_result_ty,
                        ),
                        eval_form.span,
                    )
                } else {
                    emit_line_mapped(
                        &e,
                        `kvist_repl_output := fmt.aprintf("%s\n", kvist_repl_rendered_data)`,
                        eval_form.span,
                    )
                }
            } else {
                if repl_inspect_only {
                    emit_line_mapped(
                        &e,
                        fmt.tprintf(
                            `kvist_repl_output := fmt.aprintf("KVIST_REPL_LAYOUT\t%%d\t%%d\n%%v\n", size_of(%s), align_of(%s), kvist_repl_result_storage)`,
                            eval_result_ty,
                            eval_result_ty,
                        ),
                        eval_form.span,
                    )
                } else {
                    emit_line_mapped(
                        &e,
                        `kvist_repl_output := fmt.aprintf("%v\n", kvist_repl_result_storage)`,
                        eval_form.span,
                    )
                }
            }
            emit_line(&e, "defer delete(kvist_repl_output)")
            emit_line(
                &e,
                "host.emit_output(host.ctx, Kvist_Repl_Rendered_Value{data = raw_data(kvist_repl_output), length = len(kvist_repl_output)})",
            )
        }
    } else if no_print {
        err_stmt, ok_stmt := emit_stmt(&e, eval_form, false, Return_Spec{kind = .None})
        if !ok_stmt {
            return result, err_stmt, false
        }
    } else {
        err_stmt, ok_stmt := emit_eval_print_stmt(&e, eval_form)
        if !ok_stmt {
            return result, err_stmt, false
        }
    }
    e.indent -= 1
    emit_line(&e, "}")
    append(&result.source_map, Source_Map_Entry{
        generated_start_line = start_line,
        generated_end_line   = e.line - 1,
        source_span          = eval_form.span,
    })

    err_specializations, ok_specializations := emit_captured_proc_specializations(&e)
    if !ok_specializations {
        return result, err_specializations, false
    }
    emit_data_decode_aliases(&e, features)
    emit_core_helpers(&e, features)
    output := strings.clone(strings.to_string(e.builder))
    late_imports: [dynamic]string
    if output_needs_core_slice_import(output, features) &&
       !output_has_import_line(output, "import kvist_slice \"core:slice\"") {
        append(&late_imports, "import kvist_slice \"core:slice\"")
    }
    if !emitted_core_strings_import &&
       (features_need_core_strings_import(features) ||
        strings.contains(output, "strings.")) &&
       !output_has_import_path(output, "core:strings") {
        append(&late_imports, "import strings \"core:strings\"")
    }
    if !emitted_core_fmt_import && features_need_core_fmt_import(features) &&
       !output_has_import_path(output, "core:fmt") {
        append(&late_imports, "import \"core:fmt\"")
    }
    if features_need_core_thread_import(features) &&
       !output_has_import_path(output, "core:thread") {
        append(&late_imports, "import thread \"core:thread\"")
    }
    if features_need_core_chan_import(features) &&
       !output_has_import_path(output, "core:sync/chan") {
        append(&late_imports, "import chan \"core:sync/chan\"")
    }
    if features_need_core_os_import(features) &&
       !output_has_import_path(output, "core:os") {
        append(&late_imports, "import os \"core:os\"")
    }
    if features_need_base_runtime_import(features) &&
       !output_has_import_line(output, "import kvist_runtime \"base:runtime\"") {
        append(&late_imports, "import kvist_runtime \"base:runtime\"")
    }
    if strings.contains(output, "kvist_condition_strconv.") &&
       !output_has_import_line(output, "import kvist_condition_strconv \"core:strconv\"") {
        append(&late_imports, "import kvist_condition_strconv \"core:strconv\"")
    }
    if features_need_data_runtime_imports(features) &&
       !output_has_import_line(output, "import kvist_sync \"core:sync\"") {
        append(&late_imports, "import kvist_sync \"core:sync\"")
    }
    if len(late_imports) > 0 {
        adjusted_output, added_lines := inject_imports_into_output_header(output, late_imports[:])
        delete(output)
        output = adjusted_output
        shift_source_map_lines(&result.source_map, added_lines)
    }
    if features.dynamic_literals {
        output_builder := strings.builder_make()
        defer strings.builder_destroy(&output_builder)
        strings.write_string(&output_builder, "#+feature dynamic-literals\n")
        strings.write_string(&output_builder, output)
        for &entry in result.source_map {
            entry.generated_start_line += 1
            entry.generated_end_line += 1
        }
        result.output = strings.clone(strings.to_string(output_builder))
        delete(output)
        return result, {}, true
    }
    result.output = output
    return result, {}, true
}

emit_ir_program :: proc(program: IR_Program) -> (string, Compile_Error, bool) {
    return emit_decls(program.decls[:])
}

emit_ir_program_with_source_map :: proc(program: IR_Program, profile: ^Compile_Profile = nil) -> (Emit_Result, Compile_Error, bool) {
    return emit_decls_with_source_map(program.decls[:], profile)
}

program_imports_fmt :: proc(program: IR_Program) -> bool {
    for decl in program.decls {
        if decl.kind == .Import && decl.import_decl.path == "\"core:fmt\"" {
            if !decl.import_decl.has_alias || decl.import_decl.alias == "fmt" {
                return true
            }
        }
    }
    return false
}

proc_decl_is_main :: proc(decl: IR_Decl) -> bool {
    return decl.kind == .Proc && decl.proc_decl.name == "main"
}

make_symbol_form :: proc(text: string, span: Span) -> CST_Form {
    return CST_Form{
        kind = .Symbol,
        text = text,
        span = span,
    }
}

make_println_form :: proc(value: CST_Form) -> CST_Form {
    items: [dynamic]CST_Form
    append(&items, make_symbol_form("fmt.println", value.span))
    append(&items, value)
    return CST_Form{
        kind = .List,
        items = items,
        span = value.span,
    }
}

emit_eval_program_with_source_map :: proc(
    program: IR_Program,
    eval_form: CST_Form,
    no_print: bool,
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
) -> (Emit_Result, Compile_Error, bool) {
    decls: [dynamic]IR_Decl
    append(&decls, IR_Decl{
        kind = .Package,
        span = eval_form.span,
        package_name = "main",
    })

    if !no_print && !program_imports_fmt(program) {
        append(&decls, IR_Decl{
            kind = .Import,
            span = eval_form.span,
            import_decl = Import_Decl{
                alias = "fmt",
                path = "\"core:fmt\"",
                has_alias = true,
            },
        })
    }
    if repl_generation {
        append(&decls, IR_Decl{
            kind = .Import,
            span = eval_form.span,
            import_decl = Import_Decl{
                alias = "repl_runtime",
                path = "\"base:runtime\"",
                has_alias = true,
            },
        })
        if repl_inspection_page_limit > 0 {
            append(&decls, IR_Decl{
                kind = .Import,
                span = eval_form.span,
                import_decl = Import_Decl{
                    alias = "kvist_repl_slice",
                    path = "\"core:slice\"",
                    has_alias = true,
                },
            })
        }
        append(&decls, IR_Decl{
            kind = .Raw,
            span = eval_form.span,
            raw_text = `@(export)
kvist_repl_api_version: u32 = 26

Kvist_Repl_Register_Proc :: proc "c" (ctx: rawptr, name: cstring, signature: cstring, address: rawptr)
Kvist_Repl_Lookup_Proc :: proc "c" (ctx: rawptr, name: cstring, signature: cstring) -> rawptr
Kvist_Repl_Register_Result :: proc "c" (ctx: rawptr, signature: cstring, address: rawptr)
Kvist_Repl_State_Restore :: proc "c" (snapshot: rawptr)
Kvist_Repl_State_Clone :: proc "c" (snapshot: rawptr)
Kvist_Repl_Register_State :: proc "c" (ctx: rawptr, name: cstring, signature: cstring, size, align: int, clone: Kvist_Repl_State_Clone, restore: Kvist_Repl_State_Restore)
Kvist_Repl_Debug_Flags :: proc "c" (ctx: rawptr) -> u32
Kvist_Repl_Trace_Point :: proc "c" (ctx: rawptr, trace_id: cstring)
Kvist_Repl_Enter_Frame :: proc "c" (ctx: rawptr)
Kvist_Repl_Leave_Frame :: proc "c" (ctx: rawptr)
Kvist_Repl_Rendered_Value :: struct {
    data: [^]u8,
    length: int,
}
Kvist_Repl_Trace_Values :: proc "c" (ctx: rawptr, trace_id: cstring, values: [^]Kvist_Repl_Rendered_Value, value_count: int)
Kvist_Repl_Condition :: proc "c" (ctx: rawptr, pause_id: cstring, condition_type, message, data, value_type: Kvist_Repl_Rendered_Value, restart_flags: u32)
Kvist_Repl_Emit_Output :: proc "c" (ctx: rawptr, value: Kvist_Repl_Rendered_Value)
Kvist_Repl_Page_Emit :: proc "c" (ctx: rawptr, index: int, key, value: Kvist_Repl_Rendered_Value)
Kvist_Repl_Collection_Emit :: proc "c" (ctx: rawptr, relative_path, shape, element_type, key_type, value_type: Kvist_Repl_Rendered_Value, collection_ctx: rawptr, render_page: rawptr, copy_context_size, copy_context_align: int)
Kvist_Repl_Render_Page :: proc "c" (collection_ctx: rawptr, offset, limit: int, emit_ctx: rawptr, emit: Kvist_Repl_Page_Emit, emit_collection: Kvist_Repl_Collection_Emit) -> int
Kvist_Repl_Debug_Collection :: struct {
    path: Kvist_Repl_Rendered_Value,
    shape: Kvist_Repl_Rendered_Value,
    element_type: Kvist_Repl_Rendered_Value,
    key_type: Kvist_Repl_Rendered_Value,
    value_type: Kvist_Repl_Rendered_Value,
    collection_ctx: rawptr,
    render_page: Kvist_Repl_Render_Page,
}
Kvist_Repl_Restart_Selection :: struct {
    name: Kvist_Repl_Rendered_Value,
    value: Kvist_Repl_Rendered_Value,
}
Kvist_Repl_Pause :: proc "c" (ctx: rawptr, pause_id: cstring, values: [^]Kvist_Repl_Rendered_Value, value_count: int, collections: [^]Kvist_Repl_Debug_Collection, collection_count: int, required: bool, restart_selection: ^Kvist_Repl_Restart_Selection)
Kvist_Repl_Abort_Requested :: proc "c" (ctx: rawptr) -> bool
Kvist_Repl_Transfer_Result_Allocation :: proc "c" (ctx: rawptr, memory: rawptr)
Kvist_Repl_Retain_Result_Allocation :: proc "c" (ctx: rawptr, memory: rawptr)
Kvist_Repl_Transfer_Binding_Allocation :: proc "c" (ctx: rawptr, name: cstring, memory: rawptr)
Kvist_Repl_Retain_Binding_Allocation :: proc "c" (ctx: rawptr, name: cstring, memory: rawptr)
Kvist_Repl_Condition_Handler_Push :: proc "c" (ctx: rawptr, kind: Kvist_Repl_Rendered_Value, handler: rawptr)
Kvist_Repl_Condition_Handler_Pop :: proc "c" (ctx: rawptr)
Kvist_Repl_Condition_Handler_Count :: proc "c" (ctx: rawptr) -> int
Kvist_Repl_Condition_Handler_Kind_At :: proc "c" (ctx: rawptr, index: int) -> Kvist_Repl_Rendered_Value
Kvist_Repl_Condition_Handler_At :: proc "c" (ctx: rawptr, index: int) -> rawptr
Kvist_Repl_Host_API :: struct {
    ctx: rawptr,
    allocator: repl_runtime.Allocator,
    register_proc: Kvist_Repl_Register_Proc,
    lookup_proc: Kvist_Repl_Lookup_Proc,
    register_result: Kvist_Repl_Register_Result,
    register_state: Kvist_Repl_Register_State,
    debug_flags: Kvist_Repl_Debug_Flags,
    trace_point: Kvist_Repl_Trace_Point,
    trace_values: Kvist_Repl_Trace_Values,
    condition: Kvist_Repl_Condition,
    emit_output: Kvist_Repl_Emit_Output,
    emit_stream_output: Kvist_Repl_Emit_Output,
    enter_frame: Kvist_Repl_Enter_Frame,
    leave_frame: Kvist_Repl_Leave_Frame,
    pause: Kvist_Repl_Pause,
    abort_requested: Kvist_Repl_Abort_Requested,
    transfer_result_allocation: Kvist_Repl_Transfer_Result_Allocation,
    retain_result_allocation: Kvist_Repl_Retain_Result_Allocation,
    transfer_binding_allocation: Kvist_Repl_Transfer_Binding_Allocation,
    retain_binding_allocation: Kvist_Repl_Retain_Binding_Allocation,
    condition_handler_push: Kvist_Repl_Condition_Handler_Push,
    condition_handler_pop: Kvist_Repl_Condition_Handler_Pop,
    condition_handler_count: Kvist_Repl_Condition_Handler_Count,
    condition_handler_kind_at: Kvist_Repl_Condition_Handler_Kind_At,
    condition_handler_at: Kvist_Repl_Condition_Handler_At,
}
kvist_repl_host: ^Kvist_Repl_Host_API

kvist_repl_println :: proc(args: ..any, sep := " ", flush := true) -> int {
    output := fmt.aprintln(..args, sep=sep)
    defer delete(output)
    kvist_repl_host.emit_stream_output(
        kvist_repl_host.ctx,
        Kvist_Repl_Rendered_Value{
            data = raw_data(output),
            length = len(output),
        },
    )
    _ = flush
    return len(output)
}`,
        })
    }

    effective_repl_value_names: [dynamic]string
    append(&effective_repl_value_names, ..repl_value_names)
    if repl_generation &&
       repl_inspection_source_slot != "" &&
       repl_inspection_source_type != "" {
        append(&decls, IR_Decl{
            kind = .Const,
            span = eval_form.span,
            const_decl = Const_Decl{
                name = repl_inspection_source_slot,
                has_ty = true,
                ty = repl_inspection_source_type,
            },
        })
        append(&effective_repl_value_names, repl_inspection_source_slot)
    }
    defer delete(effective_repl_value_names)

    for decl, idx in program.decls {
        if decl.kind == .Package {
            continue
        }
        if proc_decl_is_main(decl) {
            continue
        }
        if decl.kind == .Raw && idx+1 < len(program.decls) && proc_decl_is_main(program.decls[idx+1]) {
            if raw_is_proc_directive(decl.raw_text) || raw_attaches_to_next_decl(decl.raw_text) {
                continue
            }
        }
        append(&decls, decl)
    }

    return emit_eval_decls_with_source_map(
        decls[:],
        eval_form,
        no_print,
        entry_name = "kvist_repl_run" if repl_generation else "main",
        export_entry = repl_generation,
        initialize_context = repl_generation,
        repl_proc_names = repl_current_proc_names,
        repl_prior_proc_names = repl_prior_proc_names,
        repl_value_names = effective_repl_value_names[:],
        repl_current_value_names = repl_current_value_names,
        repl_var_names = repl_var_names,
        repl_current_var_names = repl_current_var_names,
        repl_recent_result_types = repl_recent_result_types,
        skip_eval = !repl_has_runtime,
        repl_inspect_only = repl_inspect_only,
        repl_inspection_result_slot = repl_inspection_result_slot,
        repl_inspection_page_offset = repl_inspection_page_offset,
        repl_inspection_page_limit = repl_inspection_page_limit,
        repl_debug_capture_values = repl_debug_capture_values,
    )
}

decl_name :: proc(decl: IR_Decl) -> string {
    #partial switch decl.kind {
    case .Const:
        return decl.const_decl.name
    case .Var:
        return decl.var_decl.name
    case .Struct:
        return decl.struct_decl.name
    case .Enum:
        return decl.enum_decl.name
    case .Union:
        return decl.union_decl.name
    case .Proc:
        return decl.proc_decl.name
    }
    return ""
}

decl_matches :: proc(a, b: IR_Decl) -> bool {
    if a.kind != b.kind {
        return false
    }
    if a.kind == .Import {
        return a.import_decl.path == b.import_decl.path &&
               a.import_decl.alias == b.import_decl.alias &&
               a.import_decl.has_alias == b.import_decl.has_alias &&
               a.import_decl.has_refer == b.import_decl.has_refer
    }
    a_name := decl_name(a)
    if a_name == "" {
        return false
    }
    return a_name == decl_name(b)
}

emit_eval_decl_program_with_source_map :: proc(program: IR_Program, eval_decl: IR_Decl) -> (Emit_Result, Compile_Error, bool) {
    decls: [dynamic]IR_Decl
    append(&decls, IR_Decl{
        kind = .Package,
        span = eval_decl.span,
        package_name = "main",
    })

    found_eval_decl := eval_decl.kind == .Ignored ||
                       eval_decl.kind == .Package
    if eval_decl.kind == .Import {
        for decl in program.decls {
            if decl_matches(decl, eval_decl) {
                found_eval_decl = true
                break
            }
        }
        if !found_eval_decl {
            append(&decls, eval_decl)
        }
    }

    for decl, idx in program.decls {
        if decl.kind == .Package {
            continue
        }
        if proc_decl_is_main(decl) && !proc_decl_is_main(eval_decl) {
            continue
        }
        if decl.kind == .Raw && idx+1 < len(program.decls) && proc_decl_is_main(program.decls[idx+1]) {
            if !proc_decl_is_main(eval_decl) &&
               (raw_is_proc_directive(decl.raw_text) || raw_attaches_to_next_decl(decl.raw_text)) {
                continue
            }
        }
        if decl_matches(decl, eval_decl) {
            found_eval_decl = true
        }
        append(&decls, decl)
    }

    if !found_eval_decl && eval_decl.kind != .Import {
        append(&decls, eval_decl)
    }

    if !proc_decl_is_main(eval_decl) {
        append(&decls, IR_Decl{
            kind = .Proc,
            span = eval_decl.span,
            proc_decl = Proc_Decl{
                name = "main",
            },
        })
    }

    return emit_decls_with_source_map(decls[:])
}

emit_eval_program :: proc(program: IR_Program, eval_form: CST_Form, no_print: bool) -> (string, Compile_Error, bool) {
    result, err, ok := emit_eval_program_with_source_map(program, eval_form, no_print)
    if !ok {
        return "", err, false
    }
    defer source_map_slice_delete(result.source_map)
    return result.output, {}, true
}
