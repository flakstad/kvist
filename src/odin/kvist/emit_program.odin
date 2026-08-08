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
    if !emitted_core_strings_import && features_need_core_strings_import(features) &&
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

emit_eval_decls_with_source_map :: proc(decls: []IR_Decl, eval_form: CST_Form, no_print: bool) -> (Emit_Result, Compile_Error, bool) {
    result := Emit_Result{}
    features := Emitter_Features{}
    captured_specializations: [dynamic]Captured_Proc_Specialization
    e := Emitter{
        builder  = strings.builder_make(),
        decls    = decls,
        features = &features,
        source_map = &result.source_map,
        warnings = &result.warnings,
        line     = 1,
        captured_proc_specializations = &captured_specializations,
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
    needs_core_strings_import := decls_need_core_strings_import(decls) ||
                                 form_uses_core_strings(eval_form)
    needs_core_fmt_import := decls_need_core_fmt_import(decls) ||
                             (!decls_have_core_fmt_import(decls) && form_uses_core_fmt(eval_form))
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
    err_runtime_defs, ok_runtime_defs := emit_runtime_def_lifecycle(&e)
    if !ok_runtime_defs {
        return result, err_runtime_defs, false
    }

    if e.line > 1 {
        strings.write_byte(&e.builder, '\n')
        e.line += 1
    }

    start_line := e.line
    emit_line(&e, "main :: proc() {")
    e.indent += 1
    if no_print {
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
    if !emitted_core_strings_import && features_need_core_strings_import(features) &&
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

emit_eval_program_with_source_map :: proc(program: IR_Program, eval_form: CST_Form, no_print: bool) -> (Emit_Result, Compile_Error, bool) {
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

    return emit_eval_decls_with_source_map(decls[:], eval_form, no_print)
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
