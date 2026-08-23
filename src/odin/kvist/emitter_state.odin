// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

Thread_Start_Spec :: struct {
    worker:        string,
    task_ty:       string,
    params:        []Param,
    result_ty:     string,
    captures:      []Param,
    callback_proc: string,
}

Thread_Detach_Spec :: struct {
    worker:        string,
    params:        []Param,
    captures:      []Param,
    callback_proc: string,
}

Captured_Proc_Specialization :: struct {
    original_name:         string,
    callback_param_index:  int,
    capture_count:         int,
    field_selector:        string,
    field_callbacks:       [dynamic]Field_Proc_Specialization,
}

Field_Proc_Specialization :: struct {
    callback_param_index: int,
    field_selector:       string,
}

Callback_Context :: struct {
    name:          string,
    capture_names: [dynamic]string,
    field_selector: string,
}

Transform_Step_Kind :: enum {
    Map,
    Filter,
    Remove,
    Keep,
    Take,
    Take_While,
    Drop,
    Drop_While,
    Map_Indexed,
    Mapcat,
    Distinct,
    Distinct_By,
}

Transform_Step :: struct {
    kind:     Transform_Step_Kind,
    callback: CST_Form,
    state_name: string,
    span:     Span,
}

Transform_Loop_Source :: struct {
    source_text: string,
    source_ty:   string,
    item_ty:     string,
    item_text:   string,
    key_name:    string,
    key_ty:      string,
    value_name:  string,
    value_ty:    string,
}

Transform_Into_Output_Kind :: enum {
    Dynamic_Array,
    Data_Vector,
    Map,
    Set,
}

Transform_Into_Output :: struct {
    kind:       Transform_Into_Output_Kind,
    output_ty:  string,
    value_ty:   string,
    map_key_ty: string,
    map_val_ty: string,
}

Emitter_Features :: struct {
    keyword_type:     bool,
    data_type:        bool,
    data_decode:      bool,
    dynamic_literals: bool,
    core_get_or_default: bool,
    core_contains_value: bool,
    core_strings:     bool,
    core_fmt:         bool,
    runtime_defs:     bool,
    thread_starts:  [dynamic]Thread_Start_Spec,
    thread_detaches: [dynamic]Thread_Detach_Spec,
    data_literals:   [dynamic]Data_Literal,
}

Data_Literal :: struct {
    name:  string,
    value: string,
}

Emitter_Import_Cache :: struct {
    proc_param_types: map[string][dynamic]string,
    proc_params_known: map[string]bool,
    type_fields: map[string][dynamic]Struct_Field,
    type_fields_known: map[string]bool,
    enum_exists: map[string]bool,
    enum_known: map[string]bool,
}

emitter_import_cache_init :: proc(cache: ^Emitter_Import_Cache) {
    if cache.proc_param_types == nil {
        cache.proc_param_types = make(map[string][dynamic]string)
    }
    if cache.proc_params_known == nil {
        cache.proc_params_known = make(map[string]bool)
    }
    if cache.type_fields == nil {
        cache.type_fields = make(map[string][dynamic]Struct_Field)
    }
    if cache.type_fields_known == nil {
        cache.type_fields_known = make(map[string]bool)
    }
    if cache.enum_exists == nil {
        cache.enum_exists = make(map[string]bool)
    }
    if cache.enum_known == nil {
        cache.enum_known = make(map[string]bool)
    }
}

emitter_import_cache_delete :: proc(cache: ^Emitter_Import_Cache) {
    for _, param_types in cache.proc_param_types {
        owned := param_types
        delete_string_slice(&owned)
    }
    for _, fields in cache.type_fields {
        owned := fields
        delete_struct_field_slice(&owned)
    }
    delete(cache.proc_param_types)
    delete(cache.proc_params_known)
    delete(cache.type_fields)
    delete(cache.type_fields_known)
    delete(cache.enum_exists)
    delete(cache.enum_known)
    cache^ = {}
}

Emitter :: struct {
    builder:                   strings.Builder,
    indent:                    int,
    decls:                     []IR_Decl,
    structs:                   [dynamic]Struct_Decl,
    unions:                    [dynamic]Union_Decl,
    local_structs:             [dynamic]Struct_Decl,
    local_unions:              [dynamic]Union_Decl,
    features:                  ^Emitter_Features,
    source_map:                ^[dynamic]Source_Map_Entry,
    warnings:                  ^[dynamic]Compile_Warning,
    line:                      int,
    temp_counter:              int,
    data_literal_prefix:       string,
    owner_counter:             int,
    attach_next_decl:          bool,
    pending_prefix_directives: [dynamic]string,
    pending_suffix_directives: [dynamic]string,
    emitted_raw_decls:        [dynamic]string,
    local_types:               [dynamic]Param,
    local_type_scope_marks:    [dynamic]int,
    local_struct_scope_marks:  [dynamic]int,
    local_union_scope_marks:   [dynamic]int,
    callback_contexts:         [dynamic]Callback_Context,
    callback_context_scope_marks: [dynamic]int,
    captured_proc_specializations: ^[dynamic]Captured_Proc_Specialization,
    current_proc_owns_managed_result: bool,
    current_proc_borrows_managed_result: bool,
    current_proc_returns: Return_Spec,
    current_source_path: string,
    current_source_file: string,
    warning_source_files: map[string]string,
    indexes_ready: bool,
    proc_indices: map[string]int,
    overload_indices: map[string]int,
    const_indices: map[string]int,
    transform_indices: map[string]int,
    source_indices: map[string]int,
    enum_indices: map[string]int,
    struct_indices: map[string]int,
    union_indices: map[string]int,
    decl_indices: map[string]int,
    kvist_import_packages: map[string]string,
    odin_import_aliases: map[string]bool,
    odin_import_paths: map[string]string,
    odin_import_cache_keys: map[string]string,
    import_cache: ^Emitter_Import_Cache,
    repl_value_names: []string,
    repl_var_names: []string,
    repl_recent_result_types: []string,
    repl_current_proc_names: []string,
    repl_dispatch_adapters_emitted: bool,
    repl_debug_enabled: bool,
    debug_restart_contexts: [dynamic]Debug_Restart_Context,
}

ensure_emitter_indexes :: proc(e: ^Emitter) {
    if e.indexes_ready {
        return
    }
    e.indexes_ready = true
    e.proc_indices = make(map[string]int, context.temp_allocator)
    e.overload_indices = make(map[string]int, context.temp_allocator)
    e.const_indices = make(map[string]int, context.temp_allocator)
    e.transform_indices = make(map[string]int, context.temp_allocator)
    e.source_indices = make(map[string]int, context.temp_allocator)
    e.enum_indices = make(map[string]int, context.temp_allocator)
    e.struct_indices = make(map[string]int, context.temp_allocator)
    e.union_indices = make(map[string]int, context.temp_allocator)
    e.decl_indices = make(map[string]int, context.temp_allocator)
    e.kvist_import_packages = make(map[string]string, context.temp_allocator)
    e.odin_import_aliases = make(map[string]bool, context.temp_allocator)
    e.odin_import_paths = make(map[string]string, context.temp_allocator)
    e.odin_import_cache_keys = make(map[string]string, context.temp_allocator)
    for &decl, idx in e.decls {
        name := decl_name(decl)
        if name != "" {
            if _, found := e.decl_indices[name]; !found {
                e.decl_indices[name] = idx
            }
        }
        #partial switch decl.kind {
        case .Proc:
            if _, found := e.proc_indices[decl.proc_decl.name]; !found {
                e.proc_indices[decl.proc_decl.name] = idx
            }
        case .Const:
            if _, found := e.const_indices[decl.const_decl.name]; !found {
                e.const_indices[decl.const_decl.name] = idx
            }
            if decl.const_decl.is_overload {
                if _, found := e.overload_indices[decl.const_decl.name]; !found {
                    e.overload_indices[decl.const_decl.name] = idx
                }
            }
        case .Transform:
            if _, found := e.transform_indices[decl.transform_decl.name]; !found {
                e.transform_indices[decl.transform_decl.name] = idx
            }
        case .Source:
            if _, found := e.source_indices[decl.source_decl.name]; !found {
                e.source_indices[decl.source_decl.name] = idx
            }
        case .Enum:
            if _, found := e.enum_indices[decl.enum_decl.name]; !found {
                e.enum_indices[decl.enum_decl.name] = idx
            }
        case .Import:
            if alias, pkg, ok := kvist_import_alias_for_decl(decl); ok {
                if _, found := e.kvist_import_packages[alias]; !found {
                    e.kvist_import_packages[alias] = pkg
                }
            } else {
                alias := decl.import_decl.alias
                if !decl.import_decl.has_alias {
                    alias = import_default_alias(unquote_string(decl.import_decl.path))
                }
                if alias != "" {
                    e.odin_import_aliases[alias] = true
                    if _, found := e.odin_import_paths[alias]; !found {
                        raw := decl.import_decl.path
                        if len(raw) >= 2 && raw[0] == '"' && raw[len(raw)-1] == '"' {
                            raw = unquote_string(raw)
                        }
                        e.odin_import_paths[alias] = raw
                    }
                }
            }
        }
    }
    for _, idx in e.structs {
        if _, found := e.struct_indices[e.structs[idx].name]; !found {
            e.struct_indices[e.structs[idx].name] = idx
        }
    }
    for _, idx in e.unions {
        if _, found := e.union_indices[e.unions[idx].name]; !found {
            e.union_indices[e.unions[idx].name] = idx
        }
    }
}

emitter_import_cache_key :: proc(
    e: ^Emitter,
    reference, raw, alias, member: string,
) -> string {
    if key, found := e.odin_import_cache_keys[reference]; found {
        return key
    }
    key := fmt.tprintf("%s\x1f%s\x1f%s", raw, alias, member)
    e.odin_import_cache_keys[reference] = key
    return key
}

merge_emitter_features :: proc(target: ^Emitter_Features, source: Emitter_Features) {
    target.keyword_type = target.keyword_type || source.keyword_type
    target.data_type = target.data_type || source.data_type
    target.data_decode = target.data_decode || source.data_decode
    target.dynamic_literals = target.dynamic_literals || source.dynamic_literals
    target.core_get_or_default = target.core_get_or_default || source.core_get_or_default
    target.core_contains_value = target.core_contains_value || source.core_contains_value
    target.core_strings = target.core_strings || source.core_strings
    target.core_fmt = target.core_fmt || source.core_fmt
    target.runtime_defs = target.runtime_defs || source.runtime_defs
    for spec in source.thread_starts {
        append_unique_thread_start(&target.thread_starts, spec)
    }
    for spec in source.thread_detaches {
        append_unique_thread_detach(&target.thread_detaches, spec)
    }
    for literal in source.data_literals {
        found := false
        for existing in target.data_literals {
            if existing.name == literal.name {
                found = true
                break
            }
        }
        if !found {
            append(&target.data_literals, literal)
        }
    }
}

prepare_ir_decls_for_emission :: proc(
    decls: []IR_Decl,
    profile: ^Compile_Profile = nil,
) -> (Compile_Error, bool) {
    analysis_start: time.Tick
    if profile != nil {
        analysis_start = time.tick_now()
    }
    defer if profile != nil {
        profile.analysis_ns += profile_elapsed_ns(analysis_start)
    }
    features := Emitter_Features{}
    e := Emitter{
        decls = decls,
        features = &features,
    }
    for decl in decls {
        if decl.kind == .Struct {
            append(&e.structs, decl.struct_decl)
        }
        if decl.kind == .Union {
            append(&e.unions, decl.union_decl)
        }
    }
    infer_decoded_struct_lifetimes(&e)
    infer_proc_lifetime_facts(&e)
    return classify_def_initializers(&e)
}

kvist_package_name_for_import_path :: proc(path: string) -> (string, bool) {
    raw := path
    if len(raw) >= 2 && raw[0] == '"' && raw[len(raw)-1] == '"' {
        raw = unquote_string(raw)
    }
    if !strings.has_prefix(raw, "kvist:") {
        return "", false
    }
    pkg := import_default_alias(raw)
    if pkg == "" {
        return "", false
    }
    return pkg, true
}

decl_is_kvist_import :: proc(decl: IR_Decl) -> bool {
    if decl.kind != .Import {
        return false
    }
    _, ok := kvist_package_name_for_import_path(decl.import_decl.path)
    return ok
}

kvist_import_alias_for_decl :: proc(decl: IR_Decl) -> (alias, pkg: string, ok: bool) {
    pkg, ok = kvist_package_name_for_import_path(decl.import_decl.path)
    if !ok {
        return "", "", false
    }
    if decl.import_decl.has_alias {
        return decl.import_decl.alias, pkg, true
    }
    return import_default_alias(unquote_string(decl.import_decl.path)), pkg, true
}

kvist_package_imported :: proc(e: ^Emitter, pkg: string) -> bool {
    prefix := fmt.tprintf("%s__", pkg)
    for decl in e.decls {
        _, import_pkg, ok_import := kvist_import_alias_for_decl(decl)
        if ok_import && import_pkg == pkg {
            return true
        }
        #partial switch decl.kind {
        case .Const:
            if strings.has_prefix(decl.const_decl.name, prefix) {
                return true
            }
        case .Var:
            if strings.has_prefix(decl.var_decl.name, prefix) {
                return true
            }
        case .Struct:
            if strings.has_prefix(decl.struct_decl.name, prefix) {
                return true
            }
        case .Enum:
            if strings.has_prefix(decl.enum_decl.name, prefix) {
                return true
            }
        case .Union:
            if strings.has_prefix(decl.union_decl.name, prefix) {
                return true
            }
        case .Proc:
            if strings.has_prefix(decl.proc_decl.name, prefix) {
                return true
            }
        case .Transform:
            if strings.has_prefix(decl.transform_decl.name, prefix) {
                return true
            }
        case .Source:
            if strings.has_prefix(decl.source_decl.name, prefix) {
                return true
            }
        }
    }
    return false
}

resolve_kvist_head :: proc(e: ^Emitter, head: string) -> (canonical: string, matched_builtin: bool, err: Compile_Error, ok: bool) {
    ensure_emitter_indexes(e)
    slash := strings.index(head, "/")
    dot := strings.index(head, ".")
    sep := -1
    if dot > 0 {
        sep = dot
    }
    if slash > 0 && (sep < 0 || slash < sep) {
        sep = slash
    }
    if sep <= 0 {
        return head, false, Compile_Error{}, true
    }
    alias := head[:sep]
    suffix := head[sep+1:]
    if slash > 0 && slash == sep {
        if alias == "kvist" {
            return "", false, Compile_Error{message = fmt.tprintf("use `%s.%s` for package access", alias, suffix)}, false
        }
        if _, found := e.kvist_import_packages[alias]; found {
            return "", false, Compile_Error{message = fmt.tprintf("use `%s.%s` for package access", alias, suffix)}, false
        }
    }
    if alias == "kvist" {
        return suffix, true, Compile_Error{}, true
    }
    if pkg, found := e.kvist_import_packages[alias]; found {
        return fmt.tprintf("%s/%s", pkg, suffix), true, Compile_Error{}, true
    }
    if e.odin_import_aliases[alias] {
        return head, false, Compile_Error{}, true
    }
    return head, false, Compile_Error{}, true
}

mark_dynamic_literals :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.dynamic_literals = true
    }
}

emit_coded_warning :: proc(
    e: ^Emitter,
    message: string,
    span: Span,
    code := Compile_Warning_Code.General,
    confidence := Compile_Warning_Confidence.Definite,
) {
    if e.warnings == nil {
        return
    }
    source_file := e.current_source_file
    if e.current_source_path != "" {
        if e.warning_source_files == nil {
            e.warning_source_files = make(
                map[string]string,
                context.temp_allocator,
            )
        }
        if cached, found := e.warning_source_files[e.current_source_path]; found {
            source_file = cached
        } else {
            data, read_err := os.read_entire_file_from_path(
                e.current_source_path,
                context.temp_allocator,
            )
            if read_err == nil {
                source_file = string(data)
                e.warning_source_files[e.current_source_path] = source_file
            }
        }
    }
    line, column, _, _ := source_position(source_file, span.start)
    append(e.warnings, Compile_Warning{
        message = strings.clone(message),
        span = span,
        source_path = e.current_source_path,
        line = line,
        column = column,
        code = code,
        confidence = confidence,
    })
}

emit_warning :: proc(e: ^Emitter, message: string, span: Span) {
    emit_coded_warning(e, message, span)
}

mark_core_get_or_default :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_get_or_default = true
    }
}

mark_core_contains_value :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_contains_value = true
    }
}

mark_core_strings :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_strings = true
    }
}

mark_core_fmt :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_fmt = true
    }
}

append_unique_string :: proc(items: ^[dynamic]string, value: string) {
    for item in items^ {
        if item == value {
            return
        }
    }
    append(items, value)
}

parallel_params_match :: proc(a, b: []Param) -> bool {
    if len(a) != len(b) {
        return false
    }
    for param, idx in a {
        if param.name != b[idx].name || param.ty != b[idx].ty {
            return false
        }
    }
    return true
}

field_proc_specializations_match :: proc(a, b: []Field_Proc_Specialization) -> bool {
    if len(a) != len(b) {
        return false
    }
    for field, idx in a {
        if field.callback_param_index != b[idx].callback_param_index ||
           field.field_selector != b[idx].field_selector {
            return false
        }
    }
    return true
}

append_unique_thread_start :: proc(items: ^[dynamic]Thread_Start_Spec, spec: Thread_Start_Spec) {
    for item in items^ {
        if item.worker == spec.worker &&
           item.task_ty == spec.task_ty &&
           item.result_ty == spec.result_ty &&
           parallel_params_match(item.params, spec.params) &&
           parallel_params_match(item.captures, spec.captures) {
            return
        }
    }
    append(items, spec)
}

append_unique_thread_detach :: proc(items: ^[dynamic]Thread_Detach_Spec, spec: Thread_Detach_Spec) {
    for item in items^ {
        if item.worker == spec.worker &&
           parallel_params_match(item.params, spec.params) &&
           parallel_params_match(item.captures, spec.captures) {
            return
        }
    }
    append(items, spec)
}

mark_thread_start :: proc(e: ^Emitter, spec: Thread_Start_Spec) {
    if e.features != nil {
        append_unique_thread_start(&e.features.thread_starts, spec)
    }
}

mark_thread_detach :: proc(e: ^Emitter, spec: Thread_Detach_Spec) {
    if e.features != nil {
        append_unique_thread_detach(&e.features.thread_detaches, spec)
    }
}

parallel_type_fragment :: proc(text: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for ch in text {
        if (ch >= 'a' && ch <= 'z') ||
           (ch >= 'A' && ch <= 'Z') ||
           (ch >= '0' && ch <= '9') ||
           ch == '_' {
            strings.write_byte(&builder, byte(ch))
        } else {
            strings.write_byte(&builder, '_')
        }
    }
    return strings.clone(strings.to_string(builder))
}

thread_task_type :: proc(spec: Thread_Start_Spec) -> string {
    return fmt.tprintf("%s(%s)", spec.task_ty, spec.result_ty)
}

parallel_params_fragment :: proc(params: []Param) -> string {
    if len(params) == 0 {
        return strings.clone("void")
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for param, idx in params {
        if idx > 0 {
            strings.write_byte(&builder, '_')
        }
        fragment := parallel_type_fragment(param.ty)
        strings.write_string(&builder, fragment)
        delete(fragment)
    }
    return strings.clone(strings.to_string(builder))
}

thread_start_data_name :: proc(spec: Thread_Start_Spec) -> string {
    params_fragment := parallel_params_fragment(spec.params)
    result_fragment := parallel_type_fragment(spec.result_ty)
    defer delete(params_fragment)
    defer delete(result_fragment)
    return fmt.tprintf("thread_Start_Data_%s_%s_%s", spec.worker, params_fragment, result_fragment)
}

thread_start_worker_name :: proc(spec: Thread_Start_Spec) -> string {
    params_fragment := parallel_params_fragment(spec.params)
    result_fragment := parallel_type_fragment(spec.result_ty)
    defer delete(params_fragment)
    defer delete(result_fragment)
    return fmt.tprintf("thread_start_worker_%s_%s_%s", spec.worker, params_fragment, result_fragment)
}

thread_start_helper_name :: proc(spec: Thread_Start_Spec) -> string {
    params_fragment := parallel_params_fragment(spec.params)
    result_fragment := parallel_type_fragment(spec.result_ty)
    defer delete(params_fragment)
    defer delete(result_fragment)
    return fmt.tprintf("thread_start_%s_%s_%s", spec.worker, params_fragment, result_fragment)
}

thread_start_callback_name :: proc(spec: Thread_Start_Spec) -> string {
    params_fragment := parallel_params_fragment(spec.params)
    result_fragment := parallel_type_fragment(spec.result_ty)
    defer delete(params_fragment)
    defer delete(result_fragment)
    return fmt.tprintf("thread_start_callback_%s_%s_%s", spec.worker, params_fragment, result_fragment)
}

thread_detach_data_name :: proc(spec: Thread_Detach_Spec) -> string {
    params_fragment := parallel_params_fragment(spec.params)
    defer delete(params_fragment)
    return fmt.tprintf("thread_Detach_Data_%s_%s", spec.worker, params_fragment)
}

thread_detach_worker_name :: proc(spec: Thread_Detach_Spec) -> string {
    params_fragment := parallel_params_fragment(spec.params)
    defer delete(params_fragment)
    return fmt.tprintf("thread_detach_worker_%s_%s", spec.worker, params_fragment)
}

thread_detach_helper_name :: proc(spec: Thread_Detach_Spec) -> string {
    params_fragment := parallel_params_fragment(spec.params)
    defer delete(params_fragment)
    return fmt.tprintf("thread_detach_%s_%s", spec.worker, params_fragment)
}

thread_detach_callback_name :: proc(spec: Thread_Detach_Spec) -> string {
    params_fragment := parallel_params_fragment(spec.params)
    defer delete(params_fragment)
    return fmt.tprintf("thread_detach_callback_%s_%s", spec.worker, params_fragment)
}

raw_attaches_to_next_decl :: proc(text: string) -> bool {
    return len(text) >= 2 && text[0] == '@' && text[1] == '('
}

raw_is_proc_directive :: proc(text: string) -> bool {
    return len(text) > 1 && text[0] == '#' && !contains_newline(text)
}

emit_indent :: proc(e: ^Emitter) {
    i := 0
    for i < e.indent {
        strings.write_string(&e.builder, "    ")
        i += 1
    }
}

emit_line :: proc(e: ^Emitter, text: string = "") {
    emit_indent(e)
    strings.write_string(&e.builder, text)
    strings.write_byte(&e.builder, '\n')
    e.line += 1
}

emit_raw_newline :: proc(e: ^Emitter) {
    strings.write_byte(&e.builder, '\n')
    e.line += 1
}

record_source_map :: proc(e: ^Emitter, start_line, end_line: int, span: Span) {
    record_source_map_columns(e, start_line, end_line, 0, 0, span)
}

record_source_map_columns :: proc(e: ^Emitter, start_line, end_line, start_column, end_column: int, span: Span) {
    if e.source_map == nil {
        return
    }
    if end_line < start_line {
        return
    }
    append(e.source_map, Source_Map_Entry{
        generated_start_line   = start_line,
        generated_end_line     = end_line,
        generated_start_column = start_column,
        generated_end_column   = end_column,
        source_span            = span,
    })
}

indent_column :: proc(e: ^Emitter) -> int {
    return e.indent*4 + 1
}

single_line_span_end_column :: proc(start_column: int, text: string) -> int {
    if len(text) == 0 {
        return start_column
    }
    return start_column + len(text) - 1
}

contains_newline :: proc(text: string) -> bool {
    for ch in text {
        if ch == '\n' {
            return true
        }
    }
    return false
}

append_indented_multiline :: proc(builder: ^strings.Builder, text: string, indent: string, final_suffix: string = "") {
    start := 0
    i := 0
    for i < len(text) {
        if text[i] == '\n' {
            strings.write_string(builder, indent)
            strings.write_string(builder, text[start:i])
            strings.write_byte(builder, '\n')
            start = i + 1
        }
        i += 1
    }
    strings.write_string(builder, indent)
    strings.write_string(builder, text[start:])
    strings.write_string(builder, final_suffix)
}

emit_prefixed_expr :: proc(e: ^Emitter, prefix, expr: string) {
    if !contains_newline(expr) {
        emit_indent(e)
        strings.write_string(&e.builder, prefix)
        strings.write_string(&e.builder, expr)
        strings.write_byte(&e.builder, '\n')
        e.line += 1
        return
    }

    start := 0
    i := 0
    emit_indent(e)
    strings.write_string(&e.builder, prefix)
    for i < len(expr) {
        if expr[i] == '\n' {
            strings.write_string(&e.builder, expr[start:i])
            strings.write_byte(&e.builder, '\n')
            e.line += 1
            start = i + 1
            if start < len(expr) {
                emit_indent(e)
            }
        }
        i += 1
    }
    strings.write_string(&e.builder, expr[start:])
    strings.write_byte(&e.builder, '\n')
    e.line += 1
}

emit_prefixed_expr_mapped :: proc(e: ^Emitter, prefix, expr: string, span: Span) {
    start_line := e.line
    start_column := 0
    end_column := 0
    if !contains_newline(expr) {
        start_column = indent_column(e) + len(prefix)
        end_column = single_line_span_end_column(start_column, expr)
    }
    emit_prefixed_expr(e, prefix, expr)
    record_source_map_columns(e, start_line, e.line - 1, start_column, end_column, span)
}

emit_line_mapped :: proc(e: ^Emitter, text: string, span: Span) {
    start_line := e.line
    emit_line(e, text)
    record_source_map(e, start_line, e.line - 1, span)
}

record_current_line_fragment_map :: proc(e: ^Emitter, prefix_len: int, text: string, span: Span) {
    start_column := indent_column(e) + prefix_len
    end_column := single_line_span_end_column(start_column, text)
    record_source_map_columns(e, e.line, e.line, start_column, end_column, span)
}

surround_with_braces :: proc(prefix, inner: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, prefix)
    strings.write_byte(&builder, '{')
    strings.write_string(&builder, inner)
    strings.write_byte(&builder, '}')
    return strings.clone(strings.to_string(builder))
}

odin_quote_string_value :: proc(text: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_byte(&builder, '"')
    for i := 0; i < len(text); i += 1 {
        ch := text[i]
        switch ch {
        case '\\':
            strings.write_string(&builder, "\\\\")
        case '"':
            strings.write_string(&builder, "\\\"")
        case '\n':
            strings.write_string(&builder, "\\n")
        case '\r':
            strings.write_string(&builder, "\\r")
        case '\t':
            strings.write_string(&builder, "\\t")
        case:
            strings.write_byte(&builder, ch)
        }
    }
    strings.write_byte(&builder, '"')
    return strings.clone(strings.to_string(builder))
}

emit_string_literal_text :: proc(form: CST_Form) -> string {
    unquoted := unquote_string(form.text)
    defer delete(unquoted)
    return odin_quote_string_value(unquoted)
}

emit_regex_literal_text :: proc(form: CST_Form) -> string {
    unquoted := unquote_regex_literal(form.text)
    defer delete(unquoted)
    return odin_quote_string_value(unquoted)
}
