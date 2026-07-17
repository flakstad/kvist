// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:strings"

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
        for decl in e.decls {
            import_alias, _, ok_import := kvist_import_alias_for_decl(decl)
            if ok_import && import_alias == alias {
                return "", false, Compile_Error{message = fmt.tprintf("use `%s.%s` for package access", alias, suffix)}, false
            }
        }
    }
    if alias == "kvist" {
        return suffix, true, Compile_Error{}, true
    }
    for decl in e.decls {
        import_alias, pkg, ok_import := kvist_import_alias_for_decl(decl)
        if !ok_import {
            continue
        }
        if import_alias == alias {
            return fmt.tprintf("%s/%s", pkg, suffix), true, Compile_Error{}, true
        }
    }
    for decl in e.decls {
        if import_decl_alias_matches(decl, alias) {
            return head, false, Compile_Error{}, true
        }
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
    line, column, _, _ := source_position(e.current_source_file, span.start)
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

Brace_Pair :: struct {
    key:   string,
    value: string,
}

emit_brace_pair_texts :: proc(e: ^Emitter, form: CST_Form, keyword_fields := true, expected_key_type := "", expected_value_type := "") -> (pairs: [dynamic]Brace_Pair, err: Compile_Error, ok: bool) {
    i := 0
    for i < len(form.items) {
        if i+1 >= len(form.items) {
            return pairs, Compile_Error{message = "missing brace-form value", span = form.span}, false
        }

        key := form.items[i]
        val := form.items[i+1]
        value_text: string
        err_value: Compile_Error
        ok_value: bool
        if expected_value_type != "" {
            value_text, err_value, ok_value = emit_expr_for_expected_type(e, val, expected_value_type)
        } else {
            value_text, err_value, ok_value = emit_expr(e, val)
        }
        if !ok_value {
            return pairs, err_value, false
        }

        #partial switch key.kind {
        case .Keyword:
            append(&pairs, Brace_Pair{key = keyword_literal_text(e, key.text), value = value_text})
        case .Symbol:
            if len(key.text) > 1 && key.text[len(key.text)-1] == ':' {
                if keyword_fields {
                    append(&pairs, Brace_Pair{key = map_name(key.text[:len(key.text)-1]), value = value_text})
                    i += 2
                    continue
                }
            }
            key_text: string
            err_key: Compile_Error
            ok_key: bool
            if expected_key_type != "" {
                key_text, err_key, ok_key = emit_expr_for_expected_type(e, key, expected_key_type)
            } else {
                key_text, err_key, ok_key = emit_expr(e, key)
            }
            if !ok_key {
                return pairs, err_key, false
            }
            append(&pairs, Brace_Pair{key = key_text, value = value_text})
        case .String:
            append(&pairs, Brace_Pair{key = emit_string_literal_text(key), value = value_text})
        case .Regex:
            append(&pairs, Brace_Pair{key = emit_regex_literal_text(key), value = value_text})
        case:
            key_text: string
            err_key: Compile_Error
            ok_key: bool
            if expected_key_type != "" {
                key_text, err_key, ok_key = emit_expr_for_expected_type(e, key, expected_key_type)
            } else {
                key_text, err_key, ok_key = emit_expr(e, key)
            }
            if !ok_key {
                return pairs, err_key, false
            }
            append(&pairs, Brace_Pair{key = key_text, value = value_text})
        }
        i += 2
    }
    return pairs, {}, true
}

emit_brace_pairs :: proc(e: ^Emitter, form: CST_Form, keyword_fields := true) -> (string, Compile_Error, bool) {
    pairs, err_pairs, ok_pairs := emit_brace_pair_texts(e, form, keyword_fields)
    if !ok_pairs {
        return "", err_pairs, false
    }
    return emit_brace_pairs_text(pairs[:]), {}, true
}

emit_brace_pairs_text :: proc(pairs: []Brace_Pair) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for pair, idx in pairs {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "%s = %s", pair.key, pair.value)
    }
    return strings.clone(strings.to_string(builder))
}

emit_vector_item_texts :: proc(e: ^Emitter, form: CST_Form, expected_item_type := "") -> (items: [dynamic]string, err: Compile_Error, ok: bool) {
    for item in form.items {
        text: string
        err_item: Compile_Error
        ok_item: bool
        if expected_item_type != "" {
            text, err_item, ok_item = emit_expr_for_expected_type(e, item, expected_item_type)
        } else {
            text, err_item, ok_item = emit_expr(e, item)
        }
        if !ok_item {
            return items, err_item, false
        }
        append(&items, text)
    }
    return items, {}, true
}

emit_vector_items :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    items, err_items, ok_items := emit_vector_item_texts(e, form)
    if !ok_items {
        return "", err_items, false
    }
    return emit_vector_items_text(items[:]), {}, true
}

emit_vector_items_text :: proc(items: []string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for text, idx in items {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        strings.write_string(&builder, text)
    }
    return strings.clone(strings.to_string(builder))
}

emit_quaternion_vector_constructor :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 4 {
        return "", Compile_Error{message = "quaternion constructor expects four components", span = form.span}, false
    }
    items, err_items, ok_items := emit_vector_item_texts(e, form)
    if !ok_items {
        return "", err_items, false
    }
    return fmt.tprintf(
        "quaternion(x=%s, y=%s, z=%s, w=%s)",
        items[0],
        items[1],
        items[2],
        items[3],
    ), {}, true
}

emit_quaternion_arg_constructor :: proc(e: ^Emitter, args: []CST_Form, span: Span) -> (string, Compile_Error, bool) {
    if len(args) != 4 {
        return "", Compile_Error{message = "quaternion constructor expects four components", span = span}, false
    }
    items: [dynamic]string
    for arg in args {
        item, err_item, ok_item := emit_expr(e, arg)
        if !ok_item {
            return "", err_item, false
        }
        append(&items, item)
    }
    return fmt.tprintf(
        "quaternion(x=%s, y=%s, z=%s, w=%s)",
        items[0],
        items[1],
        items[2],
        items[3],
    ), {}, true
}

brace_form_starts_with_field_label :: proc(form: CST_Form) -> bool {
    if len(form.items) == 0 {
        return true
    }
    first := form.items[0]
    return first.kind == .Symbol && len(first.text) > 1 && first.text[len(first.text)-1] == ':'
}

has_multiline_items :: proc(items: []string) -> bool {
    for item in items {
        if contains_newline(item) {
            return true
        }
    }
    return false
}

type_form_needs_dynamic_literals :: proc(form: CST_Form) -> bool {
    if form.kind == .Symbol {
        return len(form.text) >= 4 && form.text[:4] == "map[" ||
               len(form.text) >= 9 && form.text[:9] == "[dynamic]" ||
               strings.has_prefix(form.text, "#soa[")
    }
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    return form.items[0].text == "map" || form.items[0].text == "dynamic" || form.items[0].text == "#soa"
}

type_text_is_soa :: proc(text: string) -> bool {
    return strings.has_prefix(text, "#soa[")
}

type_text_is_dynamic_soa :: proc(text: string) -> bool {
    return strings.has_prefix(text, "#soa[dynamic]")
}

type_text_is_pointer_to_dynamic_soa :: proc(text: string) -> bool {
    return strings.has_prefix(text, "^#soa[dynamic]")
}

type_text_is_soa_array :: proc(text: string) -> bool {
    return type_text_is_soa(text)
}

emit_dynamic_soa_vector_literal :: proc(e: ^Emitter, type_text: string, form: CST_Form) -> (string, Compile_Error, bool) {
    items, err_items, ok_items := emit_vector_item_texts(e, form)
    if !ok_items {
        return "", err_items, false
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "(proc() -> ")
    strings.write_string(&builder, type_text)
    strings.write_string(&builder, " {\n")
    strings.write_string(&builder, fmt.tprintf("    out := make(%s)\n", type_text))
    if len(items) > 0 {
        strings.write_string(&builder, "    append_soa(&out")
        for item in items {
            strings.write_string(&builder, ", ")
            strings.write_string(&builder, item)
        }
        strings.write_string(&builder, ")\n")
    }
    strings.write_string(&builder, "    return out\n")
    strings.write_string(&builder, "})()")
    return strings.clone(strings.to_string(builder)), {}, true
}

emit_vector_literal :: proc(e: ^Emitter, prefix: string, form: CST_Form) -> (string, Compile_Error, bool) {
    expected_item_type, _ := collection_element_type(prefix)
    items, err_items, ok_items := emit_vector_item_texts(e, form, expected_item_type)
    if !ok_items {
        return "", err_items, false
    }
    if !has_multiline_items(items[:]) {
        inner := emit_vector_items_text(items[:])
        return surround_with_braces(prefix, inner), {}, true
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, prefix)
    strings.write_string(&builder, "{\n")
    for item in items {
        append_indented_multiline(&builder, item, "    ", ",")
        strings.write_byte(&builder, '\n')
    }
    strings.write_byte(&builder, '}')
    return strings.clone(strings.to_string(builder)), {}, true
}

emit_brace_literal :: proc(e: ^Emitter, prefix: string, form: CST_Form) -> (string, Compile_Error, bool) {
    keyword_fields := !type_text_is_map(prefix)
    if prefix != "" && keyword_fields && !brace_form_starts_with_field_label(form) {
        return "", Compile_Error{message = "positional aggregate literals use vector syntax", span = form.span}, false
    }

    expected_key_type := ""
    expected_value_type := ""
    if key_ty, value_ty, ok_map := map_type_parts(prefix); ok_map {
        expected_key_type = key_ty
        expected_value_type = value_ty
    }
    pairs, err_pairs, ok_pairs := emit_brace_pair_texts(e, form, keyword_fields, expected_key_type, expected_value_type)
    if !ok_pairs {
        return "", err_pairs, false
    }

    multiline := false
    for pair in pairs {
        if contains_newline(pair.value) {
            multiline = true
            break
        }
    }
    if !multiline {
        inner := emit_brace_pairs_text(pairs[:])
        return surround_with_braces(prefix, inner), {}, true
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, prefix)
    strings.write_string(&builder, "{\n")
    for pair in pairs {
        item := fmt.tprintf("%s = %s", pair.key, pair.value)
        append_indented_multiline(&builder, item, "    ", ",")
        strings.write_byte(&builder, '\n')
    }
    strings.write_byte(&builder, '}')
    return strings.clone(strings.to_string(builder)), {}, true
}

emit_struct_brace_literal :: proc(e: ^Emitter, struct_decl: ^Struct_Decl, form: CST_Form) -> (string, Compile_Error, bool) {
    if form.kind != .Brace {
        return "", Compile_Error{message = "struct construction expects a brace form", span = form.span}, false
    }

    pairs: [dynamic]Brace_Pair
    i := 0
    for i < len(form.items) {
        if i+1 >= len(form.items) {
            return "", Compile_Error{message = "missing struct constructor value", span = form.span}, false
        }
        key := form.items[i]
        value := form.items[i+1]
        field_name, ok_key := brace_key_name(key)
        if !ok_key {
            return "", Compile_Error{message = "struct construction expects field: labels", span = key.span}, false
        }
        field, ok_field := find_struct_field(struct_decl, field_name)
        if !ok_field {
            return "", Compile_Error{message = fmt.tprintf("unknown struct constructor field %s", key.text), span = key.span}, false
        }
        value_text, err_value, ok_value := emit_expr_for_expected_type(e, value, field.ty)
        if !ok_value {
            return "", err_value, false
        }
        if field.owns_string {
            if !form_produces_owned_value(value, e) {
                mark_core_strings(e)
                value_text = emit_call_text("strings.clone", []string{value_text})
            }
        } else if !field.owns_dynamic_array &&
           type_text_has_managed_lifecycle(e, field.ty) &&
           !form_produces_owned_managed_type(e, value, field.ty) {
            value_text = managed_clone_value_text(e, field.ty, value_text)
        }
        append(&pairs, Brace_Pair{key = field_name, value = value_text})
        i += 2
    }
    for &field in struct_decl.fields {
        if !field.has_default {
            continue
        }
        provided := false
        for pair in pairs {
            if pair.key == field.name {
                provided = true
                break
            }
        }
        if provided {
            continue
        }
        default_text, err_default, ok_default := emit_struct_field_default(e, field)
        if !ok_default {
            return "", err_default, false
        }
        append(&pairs, Brace_Pair{key = field.name, value = default_text})
    }

    multiline := false
    for pair in pairs {
        if contains_newline(pair.value) {
            multiline = true
            break
        }
    }
    if !multiline {
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        strings.write_string(&builder, struct_decl.name)
        strings.write_byte(&builder, '{')
        for pair, idx in pairs {
            if idx > 0 {
                strings.write_string(&builder, ", ")
            }
            fmt.sbprintf(&builder, "%s = %s", pair.key, pair.value)
        }
        strings.write_byte(&builder, '}')
        return strings.clone(strings.to_string(builder)), Compile_Error{}, true
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, struct_decl.name)
    strings.write_string(&builder, "{\n")
    for pair in pairs {
        append_indented_multiline(&builder, fmt.tprintf("%s = %s", pair.key, pair.value), "    ", ",")
        strings.write_byte(&builder, '\n')
    }
    strings.write_byte(&builder, '}')
    return strings.clone(strings.to_string(builder)), Compile_Error{}, true
}

emit_imported_struct_brace_literal :: proc(e: ^Emitter, type_text: string, fields: []Struct_Field, form: CST_Form) -> (string, Compile_Error, bool) {
    if form.kind != .Brace {
        return "", Compile_Error{message = "struct construction expects a brace form", span = form.span}, false
    }
    if !brace_form_starts_with_field_label(form) {
        return "", Compile_Error{message = "positional aggregate literals use vector syntax", span = form.span}, false
    }

    pairs: [dynamic]Brace_Pair
    i := 0
    for i < len(form.items) {
        if i+1 >= len(form.items) {
            return "", Compile_Error{message = "missing struct constructor value", span = form.span}, false
        }
        key := form.items[i]
        value := form.items[i+1]
        field_name, ok_key := brace_key_name(key)
        if !ok_key {
            return "", Compile_Error{message = "struct construction expects field: labels", span = key.span}, false
        }
        field, ok_field := find_field_in_slice(fields, field_name)
        if !ok_field {
            return "", Compile_Error{message = fmt.tprintf("unknown struct constructor field %s", key.text), span = key.span}, false
        }
        value_text, err_value, ok_value := emit_expr_for_expected_type(e, value, field.ty)
        if !ok_value {
            return "", err_value, false
        }
        append(&pairs, Brace_Pair{key = field_name, value = value_text})
        i += 2
    }

    multiline := false
    for pair in pairs {
        if contains_newline(pair.value) {
            multiline = true
            break
        }
    }
    if !multiline {
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        strings.write_string(&builder, type_text)
        strings.write_byte(&builder, '{')
        for pair, idx in pairs {
            if idx > 0 {
                strings.write_string(&builder, ", ")
            }
            fmt.sbprintf(&builder, "%s = %s", pair.key, pair.value)
        }
        strings.write_byte(&builder, '}')
        return strings.clone(strings.to_string(builder)), Compile_Error{}, true
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, type_text)
    strings.write_string(&builder, "{\n")
    for pair in pairs {
        append_indented_multiline(&builder, fmt.tprintf("%s = %s", pair.key, pair.value), "    ", ",")
        strings.write_byte(&builder, '\n')
    }
    strings.write_byte(&builder, '}')
    return strings.clone(strings.to_string(builder)), Compile_Error{}, true
}

emit_call_text :: proc(name: string, arg_texts: []string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    multiline := false
    for arg_text in arg_texts {
        if contains_newline(arg_text) {
            multiline = true
            break
        }
    }

    if multiline {
        strings.write_string(&builder, name)
        strings.write_string(&builder, "(\n")
        for arg_text, idx in arg_texts {
            suffix := ","
            if idx == len(arg_texts)-1 {
                suffix = ""
            }
            append_indented_multiline(&builder, arg_text, "    ", suffix)
            strings.write_byte(&builder, '\n')
        }
        strings.write_byte(&builder, ')')
        return strings.clone(strings.to_string(builder))
    }

    fmt.sbprintf(&builder, "%s(", name)
    for arg_text, idx in arg_texts {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        strings.write_string(&builder, arg_text)
    }
    strings.write_byte(&builder, ')')
    return strings.clone(strings.to_string(builder))
}

find_proc_decl :: proc(e: ^Emitter, name: string) -> (^Proc_Decl, bool) {
    for idx in 0..<len(e.decls) {
        decl := &e.decls[idx]
        if decl.kind == .Proc && decl.proc_decl.name == name {
            return &decl.proc_decl, true
        }
    }
    return nil, false
}

find_overload_decl :: proc(e: ^Emitter, name: string) -> (^Const_Decl, bool) {
    for idx in 0..<len(e.decls) {
        decl := &e.decls[idx]
        if decl.kind == .Const &&
           decl.const_decl.is_overload &&
           decl.const_decl.name == name {
            return &decl.const_decl, true
        }
    }
    return nil, false
}

proc_accepts_positional_arg_count :: proc(proc_decl: ^Proc_Decl, count: int) -> bool {
    if count > len(proc_decl.params) {
        return false
    }
    for param in proc_decl.params[count:] {
        if !param.has_default {
            return false
        }
    }
    return true
}

literal_matches_expected_type :: proc(form: CST_Form, expected_type: string) -> bool {
    if expected_type == "Data" {
        return form.kind == .Vector || form.kind == .Brace || form.kind == .Set
    }
    #partial switch form.kind {
    case .Vector:
        _, ok := collection_element_type(expected_type)
        _, is_set := set_element_type(expected_type)
        return ok && !type_text_is_map(expected_type) && !is_set
    case .Brace:
        return type_text_is_map(expected_type)
    case .Set:
        _, ok := set_element_type(expected_type)
        return ok
    }
    return false
}

overload_literal_arg_expected_type :: proc(
    e: ^Emitter,
    overload_name: string,
    args: []CST_Form,
    arg_index: int,
) -> (string, bool) {
    if arg_index < 0 || arg_index >= len(args) {
        return "", false
    }
    arg := args[arg_index]
    if arg.kind != .Vector && arg.kind != .Brace && arg.kind != .Set {
        return "", false
    }
    overload_decl, ok_overload := find_overload_decl(e, overload_name)
    if !ok_overload {
        return "", false
    }

    selected := ""
    for member in overload_decl.overload_members {
        proc_decl, ok_proc := find_proc_decl(e, member)
        if !ok_proc ||
           !proc_accepts_positional_arg_count(proc_decl, len(args)) ||
           arg_index >= len(proc_decl.params) {
            continue
        }
        expected_type := proc_decl.params[arg_index].ty
        if !literal_matches_expected_type(arg, expected_type) {
            continue
        }
        if selected == "" {
            selected = expected_type
        } else if selected != expected_type {
            return "", false
        }
    }
    if selected == "" {
        return "", false
    }
    return strings.clone(selected), true
}

call_head_is_overload :: proc(e: ^Emitter, head: CST_Form) -> bool {
    if head.kind != .Symbol {
        return false
    }
    name := map_name(head.text)
    defer delete(name)
    _, ok := find_overload_decl(e, name)
    return ok
}

call_arg_expected_type :: proc(e: ^Emitter, call: CST_Form, item_index: int) -> (string, bool) {
    if call.kind != .List ||
       len(call.items) == 0 ||
       call.items[0].kind != .Symbol ||
       item_index < 1 ||
       item_index >= len(call.items) {
        return "", false
    }
    arg_index := item_index-1
    head_name := map_name(call.items[0].text)
    defer delete(head_name)
    if (head_name == "decode_data" || head_name == "validate_data") &&
       (item_index == 2 || item_index == 3) {
        return strings.clone("Data"), true
    }
    if head_name == "odin_contains" &&
       arg_index == 1 &&
       len(call.items) == 3 {
        if collection_ty, ok_collection_ty := obvious_form_type(e, call.items[1]);
           ok_collection_ty && collection_ty == "Data" {
            return strings.clone("Data"), true
        }
    }
    if expected_type, ok_expected := overload_literal_arg_expected_type(e, head_name, call.items[1:], arg_index); ok_expected {
        return expected_type, true
    }
    if _, proc_decl, ok_proc := resolve_proc_call_decl(e, call.items[0].text); ok_proc &&
       proc_decl != nil &&
       arg_index < len(proc_decl.params) {
        return strings.clone(proc_decl.params[arg_index].ty), true
    }
    return "", false
}

symbol_tail_starts_upper :: proc(text: string) -> bool {
    start := 0
    for ch, idx in text {
        if ch == '.' || ch == '/' {
            start = idx + 1
        }
    }
    return start < len(text) && text[start] >= 'A' && text[start] <= 'Z'
}

static_def_call_head :: proc(text: string) -> bool {
    if strings.has_prefix(text, "[") ||
       strings.has_prefix(text, "^") ||
       strings.has_prefix(text, "map[") ||
       strings.has_prefix(text, "soa[") ||
       strings.has_prefix(text, "matrix[") {
        return true
    }
    switch text {
    case
        "+", "-", "*", "/", "%", "%%",
        "&", "|", "~", "^", "<<", ">>",
        "&&", "||", "==", "!=", "<", "<=", ">", ">=", "!",
        "min", "max", "abs", "clamp",
        "len", "cap", "size-of", "align-of", "offset-of", "type-of", "typeid-of",
        "bool", "string", "cstring", "rawptr", "uintptr",
        "int", "i8", "i16", "i32", "i64", "i128",
        "uint", "u8", "u16", "u32", "u64", "u128",
        "f16", "f32", "f64", "complex64", "complex128", "quaternion128",
        "fn", "quote":
        return true
    case:
        return symbol_tail_starts_upper(text)
    }
}

def_call_head_is_declared_type :: proc(e: ^Emitter, mapped_name: string) -> bool {
    for decl in e.decls {
        #partial switch decl.kind {
        case .Const:
            if decl.const_decl.is_type_alias && decl.const_decl.name == mapped_name {
                return true
            }
        case .Struct:
            if decl.struct_decl.name == mapped_name {
                return true
            }
        case .Enum:
            if decl.enum_decl.name == mapped_name {
                return true
            }
        case .Union:
            if decl.union_decl.name == mapped_name {
                return true
            }
        case:
        }
    }
    return false
}

def_value_requires_runtime_init :: proc(e: ^Emitter, form: CST_Form, depth: int = 0) -> bool {
    if depth > 64 {
        return true
    }
    if form.kind != .List && form.kind != .Vector && form.kind != .Brace && form.kind != .Set {
        return false
    }
    if form.kind != .List {
        for item in form.items {
            if def_value_requires_runtime_init(e, item, depth+1) {
                return true
            }
        }
        return false
    }
    if len(form.items) == 0 {
        return false
    }
    head := form.items[0]
    if head.kind != .Symbol {
        for item in form.items[1:] {
            if def_value_requires_runtime_init(e, item, depth+1) {
                return true
            }
        }
        return false
    }
    if head.text == "quote" || head.text == "fn" {
        return false
    }
    if head.text == "if" || head.text == "case" {
        return true
    }
    mapped_head := map_name(head.text)
    defer delete(mapped_head)
    if _, ok_proc := find_proc_decl(e, mapped_head); ok_proc {
        return true
    }
    if _, proc_decl, ok_proc := resolve_proc_call_decl(e, head.text); ok_proc && proc_decl != nil {
        return true
    }
    if def_call_head_is_declared_type(e, mapped_head) || static_def_call_head(head.text) {
        for item in form.items[1:] {
            if def_value_requires_runtime_init(e, item, depth+1) {
                return true
            }
        }
        return false
    }
    return true
}

runtime_def_value_type :: proc(e: ^Emitter, form: CST_Form) -> (string, bool) {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return "", false
    }
    if form.items[0].text == "quasiquote" {
        return strings.clone("Data"), true
    }
    mapped_head := map_name(form.items[0].text)
    defer delete(mapped_head)
    if proc_decl, ok_proc := find_proc_decl(e, mapped_head); ok_proc {
        if return_ty, ok_return_ty := proc_decl_obvious_call_return_type(e, proc_decl, form.items[1:]); ok_return_ty {
            return return_ty, true
        }
        return "", false
    }
    if _, proc_decl, ok_proc := resolve_proc_call_decl(e, form.items[0].text); ok_proc && proc_decl != nil {
        if return_ty, ok_return_ty := proc_decl_obvious_call_return_type(e, proc_decl, form.items[1:]); ok_return_ty {
            return return_ty, true
        }
    }
    if return_ty, ok_return_ty := obvious_form_type(e, form); ok_return_ty {
        return strings.clone(return_ty), true
    }
    return "", false
}

classify_def_initializers :: proc(e: ^Emitter) -> (Compile_Error, bool) {
    for &decl in e.decls {
        if decl.kind != .Const || decl.const_decl.is_type_alias || decl.const_decl.is_overload {
            continue
        }
        if decl.const_decl.init_kind != .Auto {
            continue
        }
        if def_value_requires_runtime_init(e, decl.const_decl.value) {
            if !decl.const_decl.has_ty {
                inferred_ty, inferred := runtime_def_value_type(e, decl.const_decl.value)
                if !inferred {
                    return Compile_Error{
                        message = "cannot infer runtime-initialized def type; add an explicit type or call a single-result Kvist function",
                        span = decl.const_decl.value.span,
                    }, false
                }
                decl.const_decl.has_ty = true
                decl.const_decl.ty = inferred_ty
            }
            decl.const_decl.init_kind = .Runtime
        } else {
            decl.const_decl.init_kind = .Static
        }
    }
    return {}, true
}

find_transform_decl :: proc(e: ^Emitter, name: string) -> (^Transform_Decl, bool) {
    for idx in 0..<len(e.decls) {
        decl := &e.decls[idx]
        if decl.kind == .Transform && decl.transform_decl.name == name {
            return &decl.transform_decl, true
        }
    }
    return nil, false
}

find_source_decl :: proc(e: ^Emitter, name: string) -> (^Source_Decl, bool) {
    for idx in 0..<len(e.decls) {
        decl := &e.decls[idx]
        if decl.kind == .Source && decl.source_decl.name == name {
            return &decl.source_decl, true
        }
    }
    return nil, false
}

resolve_proc_call_decl :: proc(e: ^Emitter, head: string) -> (call_name: string, proc_decl: ^Proc_Decl, ok: bool) {
    head_name := map_name(head)
    found_proc, ok_proc := find_proc_decl(e, head_name)
    if ok_proc {
        return head_name, found_proc, true
    }

    slash := strings.index(head, "/")
    if slash < 0 {
        return head_name, nil, false
    }

    alias := map_name(head[:slash])
    defer delete(alias)
    suffix := map_name(head[slash+1:])
    defer delete(suffix)
    package_name := fmt.tprintf("%s__%s", alias, suffix)
    found_proc, ok_proc = find_proc_decl(e, package_name)
    if ok_proc {
        delete(head_name)
        return package_name, found_proc, true
    }
    return head_name, nil, false
}

emit_named_call_arg_texts :: proc(e: ^Emitter, form: CST_Form) -> (arg_texts: [dynamic]string, err: Compile_Error, ok: bool) {
    if form.kind != .Brace {
        return arg_texts, Compile_Error{message = "named arguments expect a brace form", span = form.span}, false
    }

    seen: [dynamic]string
    for i := 0; i < len(form.items); i += 2 {
        if i+1 >= len(form.items) {
            return arg_texts, Compile_Error{message = "missing named argument value", span = form.span}, false
        }

        key := form.items[i]
        value := form.items[i+1]
        field_name, ok_key := brace_key_name(key)
        if !ok_key {
            return arg_texts, Compile_Error{message = "named arguments expect field: labels", span = key.span}, false
        }
        for existing in seen {
            if existing == field_name {
                return arg_texts, Compile_Error{message = fmt.tprintf("duplicate named argument %s", key.text), span = key.span}, false
            }
        }
        append(&seen, field_name)

        value_text, err_value, ok_value := emit_expr(e, value)
        if !ok_value {
            return arg_texts, err_value, false
        }
        append(&arg_texts, fmt.tprintf("%s = %s", field_name, value_text))
    }

    return arg_texts, Compile_Error{}, true
}

find_proc_param :: proc(proc_decl: ^Proc_Decl, name: string) -> (^Param, bool) {
    for idx in 0..<len(proc_decl.params) {
        if proc_decl.params[idx].name == name {
            return &proc_decl.params[idx], true
        }
    }
    return nil, false
}

import_decl_alias_matches :: proc(decl: IR_Decl, alias: string) -> bool {
    if decl.kind != .Import {
        return false
    }
    if decl.import_decl.has_alias {
        return decl.import_decl.alias == alias
    }
    raw := decl.import_decl.path
    if len(raw) >= 2 && raw[0] == '"' && raw[len(raw)-1] == '"' {
        raw = unquote_string(raw)
    }
    return import_default_alias(raw) == alias
}

imported_call_parts :: proc(head_name: string) -> (alias, member: string, ok: bool) {
    dot := strings.index(head_name, ".")
    if dot <= 0 || dot+1 >= len(head_name) {
        return "", "", false
    }
    return head_name[:dot], head_name[dot+1:], true
}

imported_interop_call_parts :: proc(head_name: string) -> (alias, member: string, ok: bool) {
    dot := strings.index(head_name, ".")
    if dot > 0 && dot+1 < len(head_name) {
        return head_name[:dot], head_name[dot+1:], true
    }
    slash := strings.index(head_name, "/")
    if slash > 0 && slash+1 < len(head_name) {
        return head_name[:slash], head_name[slash+1:], true
    }
    return "", "", false
}

import_decl_path_matches :: proc(decl: IR_Decl, path: string) -> bool {
    if decl.kind != .Import {
        return false
    }
    raw := decl.import_decl.path
    if len(raw) >= 2 && raw[0] == '"' && raw[len(raw)-1] == '"' {
        raw = unquote_string(raw)
    }
    return raw == path
}

imported_interop_call_matches :: proc(e: ^Emitter, head_name, path, member: string) -> bool {
    if e == nil {
        return false
    }
    alias, call_member, ok_parts := imported_interop_call_parts(head_name)
    if !ok_parts || call_member != member {
        return false
    }
    for decl in e.decls {
        if import_decl_alias_matches(decl, alias) && import_decl_path_matches(decl, path) {
            return true
        }
    }
    return false
}

qualify_imported_odin_type :: proc(alias, type_text: string) -> string {
    text := strings.trim_space(type_text)
    if text == "" {
        return ""
    }
    if strings.has_prefix(text, "^") {
        inner := qualify_imported_odin_type(alias, text[1:])
        defer delete(inner)
        return fmt.tprintf("^%s", inner)
    }
    if strings.contains_any(text, ".[](), ") || strings.has_prefix(text, "#") {
        return strings.clone(text)
    }
    return fmt.tprintf("%s.%s", alias, text)
}

imported_odin_type_parts :: proc(type_text: string) -> (alias, member: string, ok: bool) {
    text := strings.trim_space(type_text)
    if strings.has_prefix(text, "^") {
        text = strings.trim_space(text[1:])
    }
    dot := strings.index(text, ".")
    if dot <= 0 || dot+1 >= len(text) {
        return "", "", false
    }
    return text[:dot], text[dot+1:], true
}

type_text_is_builtin_odin_scalar :: proc(text: string) -> bool {
    switch strings.trim_space(text) {
    case "bool", "int", "i8", "i16", "i32", "i64", "i128",
         "uint", "u8", "u16", "u32", "u64", "u128",
         "uintptr", "rune", "byte",
         "f16", "f32", "f64", "complex32", "complex64", "complex128",
         "string", "cstring", "rawptr", "any", "keyword":
        return true
    }
    return false
}

type_text_uses_keyword :: proc(text: string) -> bool {
    trimmed := strings.trim_space(text)
    if trimmed == "" {
        return false
    }
    needle := "keyword"
    limit := len(trimmed) - len(needle)
    for i := 0; i <= limit; i += 1 {
        if trimmed[i:i+len(needle)] != needle {
            continue
        }
        before_ok := i == 0
        if !before_ok {
            ch := trimmed[i-1]
            before_ok = !((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_')
        }
        after_ok := i+len(needle) == len(trimmed)
        if !after_ok {
            ch := trimmed[i+len(needle)]
            after_ok = !((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_')
        }
        if before_ok && after_ok {
            return true
        }
    }
    return false
}

mark_keyword_type :: proc(e: ^Emitter) {
    e.features.keyword_type = true
}

mark_keyword_type_for_text :: proc(e: ^Emitter, text: string) {
    if type_text_uses_keyword(text) {
        mark_keyword_type(e)
    }
}

mark_keyword_type_for_return_spec :: proc(e: ^Emitter, returns: Return_Spec) {
    #partial switch returns.kind {
    case .Single:
        mark_keyword_type_for_text(e, returns.single_ty)
    case .Named:
        for field in returns.named {
            mark_keyword_type_for_text(e, field.ty)
        }
    }
}

mark_decl_keyword_usage :: proc(e: ^Emitter, decl: IR_Decl) {
    #partial switch decl.kind {
    case .Const:
        if decl.const_decl.is_type_alias {
            mark_keyword_type_for_text(e, decl.const_decl.type_alias)
        }
        if decl.const_decl.has_ty {
            mark_keyword_type_for_text(e, decl.const_decl.ty)
        }
    case .Var:
        if decl.var_decl.has_ty {
            mark_keyword_type_for_text(e, decl.var_decl.ty)
        }
    case .Struct:
        for field in decl.struct_decl.fields {
            mark_keyword_type_for_text(e, field.ty)
        }
    case .Union:
        for variant in decl.union_decl.variants {
            mark_keyword_type_for_text(e, variant.ty)
        }
    case .Proc:
        for param in decl.proc_decl.params {
            mark_keyword_type_for_text(e, param.ty)
        }
        mark_keyword_type_for_return_spec(e, decl.proc_decl.returns)
    case .Source:
        for param in decl.source_decl.params {
            mark_keyword_type_for_text(e, param.ty)
        }
        mark_keyword_type_for_text(e, decl.source_decl.state_ty)
        mark_keyword_type_for_text(e, decl.source_decl.item_ty)
    }
}

keyword_literal_text :: proc(e: ^Emitter, text: string) -> string {
    mark_keyword_type(e)
    return emit_type_conversion_text("keyword", fmt.tprintf("%q", text))
}

mark_data_type :: proc(e: ^Emitter) {
    e.features.data_type = true
    e.features.core_strings = true
    // Contextual Data's generic lift overload includes the distinct keyword
    // scalar even if this source has no native keyword expression.
    mark_keyword_type(e)
}

emit_data_items_literal :: proc(e: ^Emitter, items: []CST_Form) -> (string, Compile_Error, bool) {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "[]Data{")
    for item, idx in items {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        value, err_value, ok_value := emit_data_value_literal(e, item)
        if !ok_value {
            return "", err_value, false
        }
        strings.write_string(&builder, value)
    }
    strings.write_byte(&builder, '}')
    return strings.clone(strings.to_string(builder)), Compile_Error{}, true
}

emit_data_map_literal :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items)%2 != 0 {
        return "", Compile_Error{message = "quoted map expects key/value pairs", span = form.span}, false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "Data{kind = .Map, payload = {entries = []Data_Entry{")
    i := 0
    for i < len(form.items) {
        if i > 0 {
            strings.write_string(&builder, ", ")
        }
        key, err_key, ok_key := emit_data_value_literal(e, form.items[i])
        if !ok_key {
            return "", err_key, false
        }
        value, err_value, ok_value := emit_data_value_literal(e, form.items[i+1])
        if !ok_value {
            return "", err_value, false
        }
        fmt.sbprintf(&builder, "{{key = %s, value = %s}}", key, value)
        i += 2
    }
    strings.write_string(&builder, "}}}")
    return strings.clone(strings.to_string(builder)), Compile_Error{}, true
}

emit_data_value_literal :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    mark_data_type(e)
    #partial switch form.kind {
    case .Nil:
        return "Data{}", Compile_Error{}, true
    case .Bool:
        return fmt.tprintf("Data{{kind = .Bool, payload = {{bool_value = %s}}}}", form.text), Compile_Error{}, true
    case .Number:
        if number_literal_type(form.text) == "f64" {
            return fmt.tprintf("Data{{kind = .Float, payload = {{float_value = f64(%s)}}}}", form.text), Compile_Error{}, true
        }
        return fmt.tprintf("Data{{kind = .Int, payload = {{int_value = i64(%s)}}}}", form.text), Compile_Error{}, true
    case .String:
        text := unquote_string(form.text)
        defer delete(text)
        return fmt.tprintf("Data{{kind = .String, payload = {{text = %q}}}}", text), Compile_Error{}, true
    case .Regex:
        return "", Compile_Error{message = "regex literals are not Data values", span = form.span}, false
    case .Symbol:
        return fmt.tprintf("Data{{kind = .Symbol, payload = {{text = %q}}}}", form.text), Compile_Error{}, true
    case .Keyword:
        return fmt.tprintf("Data{{kind = .Keyword, payload = {{text = %q}}}}", form.text), Compile_Error{}, true
    case .List, .Vector, .Set:
        items, err_items, ok_items := emit_data_items_literal(e, form.items[:])
        if !ok_items {
            return "", err_items, false
        }
        kind := "List"
        if form.kind == .Vector {
            kind = "Vector"
        } else if form.kind == .Set {
            kind = "Set"
        }
        return fmt.tprintf("Data{{kind = .%s, payload = {{items = %s}}}}", kind, items), Compile_Error{}, true
    case .Brace:
        return emit_data_map_literal(e, form)
    }
    return "", Compile_Error{message = "unsupported quoted Data value", span = form.span}, false
}

emit_quoted_data_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 2 {
        return "", Compile_Error{message = "quote expects one form", span = form.span}, false
    }
    value, err_value, ok_value := emit_data_value_literal(e, form.items[1])
    if !ok_value {
        return "", err_value, false
    }
    name := ""
    for {
        e.temp_counter += 1
        name = fmt.tprintf("kvist_data_literal_%d", e.temp_counter)
        available := true
        for literal in e.features.data_literals {
            if literal.name == name {
                available = false
                break
            }
        }
        if available {
            break
        }
        delete(name)
    }
    append(&e.features.data_literals, Data_Literal{name = name, value = value})
    return name, Compile_Error{}, true
}

form_contains_runtime_unquote :: proc(form: CST_Form, depth: int = 0) -> bool {
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if (form.items[0].text == "unquote" || form.items[0].text == "splice") && depth == 0 {
            return true
        }
        next_depth := depth
        if form.items[0].text == "quasiquote" {
            next_depth += 1
        }
        for item in form.items[1:] {
            if form_contains_runtime_unquote(item, next_depth) {
                return true
            }
        }
        return false
    }
    for item in form.items {
        if form_contains_runtime_unquote(item, depth) {
            return true
        }
    }
    return false
}

contextual_data_source_type :: proc(e: ^Emitter, form: CST_Form) -> (string, bool) {
    if ty, ok_ty := obvious_form_type(e, form); ok_ty {
        return ty, true
    }
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return "", false
    }
    switch form.items[0].text {
    case "+", "-", "*", "/", "%", "%%", "min", "max":
        if len(form.items) < 2 {
            return "", false
        }
        selected := ""
        selected_from_literal := false
        for operand in form.items[1:] {
            operand_ty, ok_operand_ty := contextual_data_source_type(e, operand)
            if !ok_operand_ty {
                continue
            }
            if operand_ty == "f64" {
                return operand_ty, true
            }
            if operand_ty == "f32" {
                selected = operand_ty
                selected_from_literal = false
                continue
            }
            if selected == "" || (selected_from_literal && operand.kind != .Number) {
                selected = operand_ty
                selected_from_literal = operand.kind == .Number
            }
        }
        if selected != "" {
            return selected, true
        }
    case "==", "=", "!=", "<", "<=", ">", ">=", "not", "!":
        return "bool", true
    case:
    }
    return "", false
}

runtime_data_unquote_expr :: proc(e: ^Emitter, form: CST_Form) -> (text: string, owned: bool, err: Compile_Error, ok: bool) {
    value, err_value, ok_value := emit_expr(e, form)
    if !ok_value {
        return "", false, err_value, false
    }
    ty, ok_ty := contextual_data_source_type(e, form)
    if !ok_ty {
        expression := form.text
        if expression == "" && len(form.items) > 0 {
            expression = form.items[0].text
        }
        message := "runtime Data unquote needs an obvious Data or native scalar type"
        if expression != "" {
            message = fmt.tprintf("runtime Data unquote `%s` needs an obvious Data or native scalar type", expression)
        }
        return "", false, Compile_Error{message = message, span = form.span}, false
    }
    mark_data_type(e)
    if type_text_is_managed_value(ty) {
        return value, form_produces_owned_managed_value(e, form), {}, true
    }
    switch ty {
    case "bool":
        return emit_call_text("kvist_data_make_bool", []string{value}), true, {}, true
    case "int", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64":
        return emit_call_text("kvist_data_make_int", []string{fmt.tprintf("i64(%s)", value)}), true, {}, true
    case "f32", "f64":
        return emit_call_text("kvist_data_make_float", []string{fmt.tprintf("f64(%s)", value)}), true, {}, true
    case "string":
        return emit_call_text("kvist_data_make_text", []string{"Data_Kind.String", value}), true, {}, true
    case "keyword":
        return emit_call_text("kvist_data_make_text", []string{"Data_Kind.Keyword", fmt.tprintf("string(%s)", value)}), true, {}, true
    }
    return "", false, Compile_Error{message = fmt.tprintf("runtime Data unquote does not support native type %s", ty), span = form.span}, false
}

emit_runtime_data_quasiquote_value :: proc(e: ^Emitter, form: CST_Form, root: bool = false) -> (text: string, owned: bool, err: Compile_Error, ok: bool) {
    if form.kind == .List && len(form.items) > 0 && is_symbol(form.items[0], "unquote") {
        if len(form.items) != 2 {
            return "", false, Compile_Error{message = "runtime Data unquote expects one expression", span = form.span}, false
        }
        value, value_owned, err_value, ok_value := runtime_data_unquote_expr(e, form.items[1])
        if !ok_value {
            return "", false, err_value, false
        }
        if root && !value_owned {
            return emit_call_text("kvist_data_retain", []string{value}), true, {}, true
        }
        return value, value_owned, {}, true
    }
    if form.kind == .List && len(form.items) > 0 && is_symbol(form.items[0], "splice") {
        return "", false, Compile_Error{message = "runtime Data splice is valid only as an item in a quasiquoted list, vector, or set", span = form.span}, false
    }
    if !form_contains_runtime_unquote(form) {
        value, err_value, ok_value := emit_data_value_literal(e, form)
        return value, false, err_value, ok_value
    }
    if form.kind != .List && form.kind != .Vector && form.kind != .Brace && form.kind != .Set {
        return "", false, Compile_Error{message = "runtime Data unquote must appear inside a list, vector, map, or set", span = form.span}, false
    }

    values: [dynamic]string
    splice_flags: [dynamic]bool
    defer delete(values)
    defer delete(splice_flags)
    has_splice := false
    for item in form.items {
        splice := item.kind == .List && len(item.items) > 0 && is_symbol(item.items[0], "splice")
        if splice && form.kind == .Brace {
            return "", false, Compile_Error{message = "runtime Data map splice is not implemented; use data.merge", span = item.span}, false
        }
        value := ""
        value_owned := false
        err_value: Compile_Error
        ok_value := false
        if splice {
            if len(item.items) != 2 {
                return "", false, Compile_Error{message = "runtime Data splice expects one expression", span = item.span}, false
            }
            value, value_owned, err_value, ok_value = runtime_data_unquote_expr(e, item.items[1])
            if ok_value {
                ty, ok_ty := obvious_form_type(e, item.items[1])
                if !ok_ty || !type_text_is_managed_value(ty) {
                    return "", false, Compile_Error{message = "runtime Data splice expects Data", span = item.items[1].span}, false
                }
            }
            has_splice = true
        } else {
            value, value_owned, err_value, ok_value = emit_runtime_data_quasiquote_value(e, item)
        }
        if !ok_value {
            return "", false, err_value, false
        }
        if value_owned {
            temp := thread_temp_name(e)
            emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), value, item.span)
            emit_line(e, fmt.tprintf("defer kvist_data_release(%s)", temp))
            value = temp
        }
        append(&values, value)
        append(&splice_flags, splice)
    }
    if form.kind == .Brace {
        if len(form.items)%2 != 0 {
            return "", false, Compile_Error{message = "runtime quasiquoted map expects key/value pairs", span = form.span}, false
        }
        literal := fmt.tprintf("[]Data{{%s}}", strings.join(values[:], ", ", context.temp_allocator))
        return emit_call_text("kvist_data_make_map", []string{literal}), true, {}, true
    }
    kind := "Data_Kind.List"
    if form.kind == .Vector {
        kind = "Data_Kind.Vector"
    } else if form.kind == .Set {
        kind = "Data_Kind.Set"
    }
    if has_splice {
        pieces: [dynamic]string
        defer delete(pieces)
        for value, idx in values {
            splice_text := "false"
            if splice_flags[idx] {
                splice_text = "true"
            }
            append(&pieces, fmt.tprintf("Data_Piece{{value = %s, splice = %s}}", value, splice_text))
        }
        literal := fmt.tprintf("[]Data_Piece{{%s}}", strings.join(pieces[:], ", ", context.temp_allocator))
        return emit_call_text("kvist_data_make_items_spliced", []string{kind, literal}), true, {}, true
    }
    literal := fmt.tprintf("[]Data{{%s}}", strings.join(values[:], ", ", context.temp_allocator))
    return emit_call_text("kvist_data_make_items", []string{kind, literal}), true, {}, true
}

emit_runtime_data_quasiquote_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 2 {
        return "", Compile_Error{message = "quasiquote expects one form", span = form.span}, false
    }
    value, _, err_value, ok_value := emit_runtime_data_quasiquote_value(e, form.items[1], true)
    return value, err_value, ok_value
}

emit_contextual_data_value :: proc(e: ^Emitter, form: CST_Form) -> (text: string, owned: bool, err: Compile_Error, ok: bool) {
    mark_data_type(e)
    if form.kind != .Vector && form.kind != .Brace && form.kind != .Set {
        #partial switch form.kind {
        case .Nil, .Bool, .Number, .String, .Keyword:
            value, err_value, ok_value := emit_data_value_literal(e, form)
            return value, false, err_value, ok_value
        }
        if form.kind == .List &&
           ((len(form.items) > 0 && is_symbol(form.items[0], "if")) ||
            form_head_is_as_thread(form) ||
            (len(form.items) > 0 && is_symbol(form.items[0], "let")) ||
            form_head_is_do(form) ||
            form_head_is_allocator_scope(form) ||
            form_head_is_case(form) ||
            form_head_is_match(form)) {
            value, err_value, ok_value := emit_expr_for_expected_type(e, form, "Data")
            return value, true, err_value, ok_value
        }
        if form.kind == .List && len(form.items) > 0 && is_symbol(form.items[0], "odin-call") {
            // `odin-call` is an explicitly typed escape hatch. In a Data
            // context its result is already Data; wrapping it in the generic
            // scalar lift would alter its ownership contract.
            value, err_value, ok_value := emit_expr(e, form)
            return value, false, err_value, ok_value
        }
        if _, ok_ty := contextual_data_source_type(e, form); !ok_ty {
            value, err_value, ok_value := emit_expr(e, form)
            if !ok_value {
                return "", false, err_value, false
            }
            if form.kind == .Symbol {
                // Lowering a contextual call argument can revisit a
                // compiler-generated Data temporary as a symbol. Declared
                // scalar symbols have already been handled by inference.
                return value, false, {}, true
            }
            if form_produces_owned_value(form, e) {
                temp := thread_temp_name(e)
                emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), value, form.span)
                emit_line_mapped(e, fmt.tprintf("defer delete(%s)", temp), form.span)
                value = temp
            }
            // Imported Odin procedures do not carry signatures in Kvist's
            // IR. Let Odin's overload resolution select the scalar/Data lift
            // instead of emitting an untyped native value into []Data.
            return emit_call_text("kvist_data_lift", []string{value}), true, {}, true
        }
        value, value_owned, err_value, ok_value := runtime_data_unquote_expr(e, form)
        return value, value_owned, err_value, ok_value
    }

    if form.kind == .Brace && len(form.items)%2 != 0 {
        return "", false, Compile_Error{message = "contextual Data map expects key/value pairs", span = form.span}, false
    }

    values: [dynamic]string
    defer delete(values)
    for item in form.items {
        value, value_owned, err_value, ok_value := emit_contextual_data_value(e, item)
        if !ok_value {
            return "", false, err_value, false
        }
        if value_owned {
            temp := thread_temp_name(e)
            emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), value, item.span)
            emit_line(e, fmt.tprintf("defer kvist_data_release(%s)", temp))
            value = temp
        }
        append(&values, value)
    }

    literal := fmt.tprintf("[]Data{{%s}}", strings.join(values[:], ", ", context.temp_allocator))
    if form.kind == .Brace {
        return emit_call_text("kvist_data_make_map", []string{literal}), true, {}, true
    }
    kind := "Data_Kind.Vector"
    if form.kind == .Set {
        kind = "Data_Kind.Set"
    }
    return emit_call_text("kvist_data_make_items", []string{kind, literal}), true, {}, true
}

emit_data_lookup_key :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if form.kind != .Symbol {
        return emit_data_value_literal(e, form)
    }
    raw, err_raw, ok_raw := emit_expr(e, form)
    if !ok_raw {
        return "", err_raw, false
    }
    if ty, ok_ty := obvious_form_type(e, form); ok_ty {
        if ty == "Data" {
            return raw, Compile_Error{}, true
        }
        if ty == "int" || ty == "i64" || ty == "u64" {
            return fmt.tprintf("Data{{kind = .Int, payload = {{int_value = i64(%s)}}}}", raw), Compile_Error{}, true
        }
    }
    return raw, Compile_Error{}, true
}

type_text_needs_conversion_parens :: proc(text: string) -> bool {
    trimmed := strings.trim_space(text)
    if trimmed == "" {
        return false
    }
    for ch in trimmed {
        if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
           (ch >= '0' && ch <= '9') || ch == '_' || ch == '.' {
            continue
        }
        return true
    }
    return false
}

emit_type_conversion_text :: proc(type_text, value_text: string) -> string {
    if type_text_needs_conversion_parens(type_text) {
        return fmt.tprintf("(%s)(%s)", type_text, value_text)
    }
    return fmt.tprintf("%s(%s)", type_text, value_text)
}

symbol_head_needs_type_conversion_parens :: proc(head: string) -> bool {
    type_text := normalize_surface_type_symbol(head)
    return type_text_needs_conversion_parens(type_text)
}

qualify_imported_odin_field_type :: proc(alias, type_text: string) -> string {
    text := strings.trim_space(type_text)
    if text == "" || type_text_is_builtin_odin_scalar(text) ||
       strings.contains_any(text, ".[](), ") || strings.has_prefix(text, "#") {
        return strings.clone(text)
    }
    return fmt.tprintf("%s.%s", alias, text)
}

delete_struct_field_slice :: proc(fields: ^[dynamic]Struct_Field) {
    for field in fields^ {
        delete(field.name)
        delete(field.source_name)
        delete(field.ty)
    }
    delete(fields^)
}

split_top_level_commas :: proc(text: string) -> (parts: [dynamic]string) {
    start := 0
    depth := 0
    for ch, idx in text {
        switch ch {
        case '(', '[', '{':
            depth += 1
        case ')', ']', '}':
            if depth > 0 {
                depth -= 1
            }
        case ',':
            if depth == 0 {
                append(&parts, strings.trim_space(text[start:idx]))
                start = idx + 1
            }
        }
    }
    append(&parts, strings.trim_space(text[start:]))
    return parts
}

top_level_colon_index :: proc(text: string) -> int {
    depth := 0
    for ch, idx in text {
        switch ch {
        case '(', '[', '{':
            depth += 1
        case ')', ']', '}':
            if depth > 0 {
                depth -= 1
            }
        case ':':
            if depth == 0 {
                return idx
            }
        }
    }
    return -1
}

strip_odin_line_comment :: proc(text: string) -> string {
    out := text
    idx := strings.index(text, "//")
    if idx >= 0 {
        out = text[:idx]
    }
    return strings.trim_space(out)
}

odin_decl_rhs_from_line :: proc(line, type_name: string) -> (string, bool) {
    trimmed := strip_odin_line_comment(line)
    decl_idx := strings.index(trimmed, "::")
    if decl_idx <= 0 {
        return "", false
    }
    name := strings.trim_space(trimmed[:decl_idx])
    if name != type_name {
        return "", false
    }
    return strings.trim_space(trimmed[decl_idx+2:]), true
}

append_imported_field :: proc(fields: ^[dynamic]Struct_Field, alias, name, ty: string) {
    mapped := map_name(strings.trim_space(name))
    defer delete(mapped)
    append(fields, Struct_Field{
        name        = strings.clone(mapped),
        source_name = strings.clone(mapped),
        ty          = qualify_imported_odin_field_type(alias, ty),
    })
}

odin_struct_fields_from_body :: proc(alias, body: string) -> (fields: [dynamic]Struct_Field) {
    lines := strings.split_lines(body, context.allocator)
    defer delete(lines)
    for line in lines {
        trimmed := strip_odin_line_comment(line)
        if trimmed == "" {
            continue
        }
        if strings.has_suffix(trimmed, ",") {
            trimmed = strings.trim_space(trimmed[:len(trimmed)-1])
        }
        colon := top_level_colon_index(trimmed)
        if colon <= 0 {
            continue
        }
        names_text := strings.trim_space(trimmed[:colon])
        ty := strings.trim_space(trimmed[colon+1:])
        names := split_top_level_commas(names_text)
        for name in names {
            if name != "" {
                append_imported_field(&fields, alias, name, ty)
            }
        }
        delete(names)
    }
    return fields
}

odin_vector_alias_fields :: proc(alias, rhs: string) -> (fields: [dynamic]Struct_Field, ok: bool) {
    text := strings.trim_space(rhs)
    if strings.has_prefix(text, "distinct ") {
        text = strings.trim_space(text[len("distinct "):])
    }
    if len(text) < 4 || text[0] != '[' {
        return fields, false
    }
    close_idx := strings.index(text, "]")
    if close_idx < 0 {
        return fields, false
    }
    count_text := strings.trim_space(text[1:close_idx])
    count := 0
    switch count_text {
    case "2":
        count = 2
    case "3":
        count = 3
    case "4":
        count = 4
    case:
        return fields, false
    }
    elem_ty := strings.trim_space(text[close_idx+1:])
    names := []string{"x", "y", "z", "w"}
    for idx in 0..<count {
        append_imported_field(&fields, alias, names[idx], elem_ty)
    }
    if count == 4 {
        color_names := []string{"r", "g", "b", "a"}
        for idx in 0..<count {
            append_imported_field(&fields, alias, color_names[idx], elem_ty)
        }
    }
    return fields, true
}

odin_import_type_fields_from_dir :: proc(alias, dir, type_name: string) -> (fields: [dynamic]Struct_Field, ok: bool) {
    if !os.exists(dir) {
        return fields, false
    }
    entries, err := os.read_directory_by_path(dir, -1, context.allocator)
    if err != nil {
        return fields, false
    }
    defer os.file_info_slice_delete(entries, context.allocator)

    for entry in entries {
        if entry.type != .Regular || !strings.has_suffix(entry.name, ".odin") {
            continue
        }
        path, join_err := os.join_path({dir, entry.name}, context.allocator)
        if join_err != nil {
            continue
        }
        data, read_err := os.read_entire_file_from_path(path, context.allocator)
        delete(path)
        if read_err != nil {
            continue
        }
        source := string(data)
        lines := strings.split_lines(source, context.allocator)

        for line, line_idx in lines {
            rhs, ok_decl := odin_decl_rhs_from_line(line, type_name)
            if !ok_decl {
                continue
            }
            if vector_fields, ok_vector := odin_vector_alias_fields(alias, rhs); ok_vector {
                delete(lines)
                delete(data)
                return vector_fields, true
            }
            if !strings.has_prefix(rhs, "struct") {
                break
            }
            open_idx := strings.index(rhs, "{")
            if open_idx < 0 {
                break
            }
            builder := strings.builder_make()
            depth := 1
            segment := rhs[open_idx+1:]
            line_cursor := line_idx
            for {
                for ch, idx in segment {
                    switch ch {
                    case '{':
                        depth += 1
                    case '}':
                        depth -= 1
                        if depth == 0 {
                            strings.write_string(&builder, segment[:idx])
                            body := strings.to_string(builder)
                            out_fields := odin_struct_fields_from_body(alias, body)
                            strings.builder_destroy(&builder)
                            delete(lines)
                            delete(data)
                            return out_fields, true
                        }
                    }
                }
                strings.write_string(&builder, segment)
                strings.write_byte(&builder, '\n')
                line_cursor += 1
                if line_cursor >= len(lines) {
                    break
                }
                segment = strip_odin_line_comment(lines[line_cursor])
            }
            strings.builder_destroy(&builder)
            break
        }
        delete(lines)
        delete(data)
    }
    return fields, false
}

odin_import_enum_exists_from_dir :: proc(dir, type_name: string) -> bool {
    if !os.exists(dir) {
        return false
    }
    entries, err := os.read_directory_by_path(dir, -1, context.allocator)
    if err != nil {
        return false
    }
    defer os.file_info_slice_delete(entries, context.allocator)

    for entry in entries {
        if entry.type != .Regular || !strings.has_suffix(entry.name, ".odin") {
            continue
        }
        path, join_err := os.join_path({dir, entry.name}, context.allocator)
        if join_err != nil {
            continue
        }
        data, read_err := os.read_entire_file_from_path(path, context.allocator)
        delete(path)
        if read_err != nil {
            continue
        }
        source := string(data)
        lines := strings.split_lines(source, context.allocator)

        for line in lines {
            rhs, ok_decl := odin_decl_rhs_from_line(line, type_name)
            if !ok_decl {
                continue
            }
            if strings.has_prefix(rhs, "enum") {
                delete(lines)
                delete(data)
                return true
            }
            break
        }
        delete(lines)
        delete(data)
    }
    return false
}

odin_proc_param_types_from_text :: proc(params_text: string) -> (types: [dynamic]string) {
    parts := split_top_level_commas(params_text)
    defer delete(parts)
    pending_names := 0
    for part in parts {
        if part == "" {
            continue
        }
        colon := top_level_colon_index(part)
        if colon < 0 {
            pending_names += 1
            continue
        }
        type_text := strings.trim_space(part[colon+1:])
        count := pending_names + 1
        for _ in 0..<count {
            append(&types, strings.clone(type_text))
        }
        pending_names = 0
    }
    return types
}

odin_proc_params_text_from_line :: proc(line, proc_name: string) -> (string, bool) {
    trimmed := strings.trim_left(line, " \t")
    decl_idx := strings.index(trimmed, "::")
    if decl_idx <= 0 {
        return "", false
    }
    name := strings.trim_space(trimmed[:decl_idx])
    if name != proc_name {
        return "", false
    }
    after_decl := strings.trim_left(trimmed[decl_idx+2:], " \t")
    if !strings.has_prefix(after_decl, "proc") {
        return "", false
    }
    after := strings.trim_left(after_decl[len("proc"):], " \t")
    open := strings.index(after, "(")
    if open < 0 {
        return "", false
    }
    start := open + 1
    depth := 1
    for ch, idx in after[start:] {
        switch ch {
        case '(':
            depth += 1
        case ')':
            depth -= 1
            if depth == 0 {
                return strings.clone(after[start:start+idx]), true
            }
        }
    }
    return "", false
}

odin_import_proc_arg_type_from_dir :: proc(dir, proc_name: string, arg_idx: int) -> (string, bool) {
    if !os.exists(dir) {
        return "", false
    }
    entries, err := os.read_directory_by_path(dir, -1, context.allocator)
    if err != nil {
        return "", false
    }
    defer os.file_info_slice_delete(entries, context.allocator)

    for entry in entries {
        if entry.type != .Regular || !strings.has_suffix(entry.name, ".odin") {
            continue
        }
        path, join_err := os.join_path({dir, entry.name}, context.allocator)
        if join_err != nil {
            continue
        }
        data, read_err := os.read_entire_file_from_path(path, context.allocator)
        delete(path)
        if read_err != nil {
            continue
        }
        source := string(data)
        lines := strings.split_lines(source, context.allocator)
        for line in lines {
            params_text, ok_params := odin_proc_params_text_from_line(line, proc_name)
            if !ok_params {
                continue
            }
            param_types := odin_proc_param_types_from_text(params_text)
            delete(params_text)
            delete(lines)
            delete(data)
            defer delete_string_slice(&param_types)
            if arg_idx < len(param_types) {
                return strings.clone(param_types[arg_idx]), true
            }
            return "", false
        }
        delete(lines)
        delete(data)
    }
    return "", false
}

imported_odin_proc_arg_type :: proc(e: ^Emitter, head_name: string, arg_idx: int) -> (string, bool) {
    alias, member, ok_parts := imported_call_parts(head_name)
    if !ok_parts {
        return "", false
    }
    for decl in e.decls {
        if !import_decl_alias_matches(decl, alias) {
            continue
        }
        raw := decl.import_decl.path
        if len(raw) >= 2 && raw[0] == '"' && raw[len(raw)-1] == '"' {
            raw = unquote_string(raw)
        }
        if strings.has_prefix(raw, "kvist:") {
            return "", false
        }
        odin_root, ok_root := odin_root_path()
        if !ok_root {
            return "", false
        }
        defer delete(odin_root)
        dir, ok_dir := odin_import_dir(odin_root, raw)
        if !ok_dir {
            return "", false
        }
        defer delete(dir)
        raw_type, ok_type := odin_import_proc_arg_type_from_dir(dir, member, arg_idx)
        if !ok_type {
            return "", false
        }
        defer delete(raw_type)
        return qualify_imported_odin_type(alias, raw_type), true
    }
    return "", false
}

imported_odin_type_fields :: proc(e: ^Emitter, type_text: string) -> (fields: [dynamic]Struct_Field, ok: bool) {
    alias, member, ok_parts := imported_odin_type_parts(type_text)
    if !ok_parts {
        return fields, false
    }
    for decl in e.decls {
        if !import_decl_alias_matches(decl, alias) {
            continue
        }
        raw := decl.import_decl.path
        if len(raw) >= 2 && raw[0] == '"' && raw[len(raw)-1] == '"' {
            raw = unquote_string(raw)
        }
        if strings.has_prefix(raw, "kvist:") {
            return fields, false
        }
        odin_root, ok_root := odin_root_path()
        if !ok_root {
            return fields, false
        }
        defer delete(odin_root)
        dir, ok_dir := odin_import_dir(odin_root, raw)
        if !ok_dir {
            return fields, false
        }
        defer delete(dir)
        return odin_import_type_fields_from_dir(alias, dir, member)
    }
    return fields, false
}

imported_odin_enum_type_exists :: proc(e: ^Emitter, type_text: string) -> bool {
    alias, member, ok_parts := imported_odin_type_parts(type_text)
    if !ok_parts {
        return false
    }

    for decl in e.decls {
        if !import_decl_alias_matches(decl, alias) {
            continue
        }
        raw := decl.import_decl.path
        if len(raw) >= 2 && raw[0] == '"' && raw[len(raw)-1] == '"' {
            raw = unquote_string(raw)
        }
        if strings.has_prefix(raw, "kvist:") {
            return false
        }
        odin_root, ok_root := odin_root_path()
        if !ok_root {
            continue
        }
        defer delete(odin_root)
        dir, ok_dir := odin_import_dir(odin_root, raw)
        if !ok_dir {
            continue
        }
        defer delete(dir)
        if odin_import_enum_exists_from_dir(dir, member) {
            return true
        }
    }
    return false
}

proc_param_keyword_names :: proc(proc_decl: ^Proc_Decl) -> (names: [dynamic]string) {
    for param, param_idx in proc_decl.params {
        append(&names, label_text(param.name))
    }
    return names
}

label_text :: proc(name: string) -> string {
    return fmt.tprintf("%s:", name)
}

join_strings :: proc(items: []string, sep: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for item, idx in items {
        if idx > 0 {
            strings.write_string(&builder, sep)
        }
        strings.write_string(&builder, item)
    }
    return strings.clone(strings.to_string(builder))
}

named_arg_message_with_valid_keys :: proc(prefix: string, proc_decl: ^Proc_Decl) -> string {
    names := proc_param_keyword_names(proc_decl)
    defer delete_string_slice(&names)
    return fmt.tprintf("%s; valid named args: %s", prefix, join_strings(names[:], ", "))
}

min3 :: proc(a, b, c: int) -> int {
    if a <= b && a <= c {
        return a
    }
    if b <= c {
        return b
    }
    return c
}

edit_distance :: proc(a, b: string) -> int {
    if a == b {
        return 0
    }
    prev := make([dynamic]int, len(b)+1)
    curr := make([dynamic]int, len(b)+1)
    defer delete(prev)
    defer delete(curr)
    for j := 0; j <= len(b); j += 1 {
        append(&prev, j)
        append(&curr, 0)
    }
    for i := 1; i <= len(a); i += 1 {
        curr[0] = i
        for j := 1; j <= len(b); j += 1 {
            cost := 1
            if a[i-1] == b[j-1] {
                cost = 0
            }
            curr[j] = min3(
                prev[j]+1,
                curr[j-1]+1,
                prev[j-1]+cost,
            )
        }
        for j := 0; j <= len(b); j += 1 {
            prev[j] = curr[j]
        }
    }
    return prev[len(b)]
}

closest_proc_param_keyword :: proc(proc_decl: ^Proc_Decl, name: string) -> (string, bool) {
    best := ""
    best_distance := 999999
    for param, param_idx in proc_decl.params {
        distance := edit_distance(name, param.name)
        if distance < best_distance {
            best_distance = distance
            best = param.name
        }
    }
    if best == "" {
        return "", false
    }
    threshold := 3
    if len(name) >= 8 {
        threshold = 4
    }
    if best_distance > threshold {
        return "", false
    }
    return best, true
}

emit_default_expr_for_call :: proc(e: ^Emitter, default_form: CST_Form, provided_names: []string, provided_forms: []CST_Form) -> (string, Compile_Error, bool) {
    if default_form.kind == .List &&
       len(default_form.items) == 2 &&
       is_symbol(default_form.items[0], "#caller_expression") &&
       default_form.items[1].kind == .Symbol {
        referenced_name := map_name(default_form.items[1].text)
        defer delete(referenced_name)
        for name, idx in provided_names {
            if name == referenced_name && idx < len(provided_forms) {
                target_text, err_target, ok_target := emit_expr(e, provided_forms[idx])
                if !ok_target {
                    return "", err_target, false
                }
                return fmt.tprintf("#caller_expression(%s)", target_text), {}, true
            }
        }
    }
    return emit_expr(e, default_form)
}

default_is_odin_caller_intrinsic :: proc(form: CST_Form) -> bool {
    if is_symbol(form, "#caller_location") {
        return true
    }
    return form.kind == .List &&
           len(form.items) == 2 &&
           is_symbol(form.items[0], "#caller_expression")
}

zero_value_for_type_text :: proc(ty: string) -> string {
    return fmt.tprintf("%s{{}}", ty)
}

form_is_expected_zero :: proc(form: CST_Form) -> bool {
    return form.kind == .List &&
           len(form.items) == 1 &&
           is_symbol(form.items[0], "zero")
}

form_is_zero_call :: proc(form: CST_Form) -> bool {
    return form.kind == .List &&
           len(form.items) > 0 &&
           is_symbol(form.items[0], "zero")
}

validate_zero_stmt :: proc(form: CST_Form) -> (Compile_Error, bool) {
    if form_is_expected_zero(form) {
        return {}, true
    }
    type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], 1)
    if !ok_type {
        return err_type, false
    }
    delete(type_text)
    if next_i != len(form.items) {
        return Compile_Error{message = "zero expects exactly one type", span = form.items[next_i].span}, false
    }
    return {}, true
}

missing_required_arg_error :: proc(proc_name, param_name: string, span: Span) -> Compile_Error {
    return Compile_Error{
        message = fmt.tprintf("%s missing required argument %s", proc_name, label_text(param_name)),
        span = span,
    }
}

emit_named_call_with_defaults :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, form: CST_Form) -> (arg_texts: [dynamic]string, err: Compile_Error, ok: bool) {
    if form.kind != .Brace {
        return arg_texts, Compile_Error{message = "named arguments expect a brace form", span = form.span}, false
    }

    named_values := make([dynamic]Brace_Pair, 0, len(form.items)/2)
    defer delete(named_values)
    provided_names := make([dynamic]string, 0, len(form.items)/2)
    defer delete(provided_names)
    provided_forms := make([dynamic]CST_Form, 0, len(form.items)/2)
    defer delete(provided_forms)

    seen: [dynamic]string
    for i := 0; i < len(form.items); i += 2 {
        if i+1 >= len(form.items) {
            return arg_texts, Compile_Error{message = "missing named argument value", span = form.span}, false
        }
        key := form.items[i]
        value := form.items[i+1]
        field_name, ok_key := brace_key_name(key)
        if !ok_key {
            return arg_texts, Compile_Error{message = "named arguments expect field: labels", span = key.span}, false
        }
        for existing in seen {
            if existing == field_name {
                return arg_texts, Compile_Error{message = fmt.tprintf("duplicate named argument %s", key.text), span = key.span}, false
            }
        }
        append(&seen, field_name)
        if _, ok_param := find_proc_param(proc_decl, field_name); !ok_param {
            message := fmt.tprintf("unknown named argument %s", key.text)
            if closest, ok_closest := closest_proc_param_keyword(proc_decl, field_name); ok_closest {
                message = fmt.tprintf("%s; did you mean %s", message, label_text(closest))
            }
            return arg_texts, Compile_Error{message = named_arg_message_with_valid_keys(message, proc_decl), span = key.span}, false
        }
        value_text, err_value, ok_value := emit_expr(e, value)
        if !ok_value {
            return arg_texts, err_value, false
        }
        append(&named_values, Brace_Pair{key = field_name, value = value_text})
        append(&provided_names, field_name)
        append(&provided_forms, value)
    }

    for param, param_idx in proc_decl.params {
        matched := false
        for pair in named_values {
            if pair.key == param.name {
                append(&arg_texts, fmt.tprintf("%s = %s", param.name, pair.value))
                matched = true
                break
            }
        }
        if matched {
            continue
        }
        if param.has_default {
            if default_is_odin_caller_intrinsic(param.default_value) {
                continue
            }
            default_text, err_default, ok_default := emit_default_expr_for_call(e, param.default_value, provided_names[:], provided_forms[:])
            if !ok_default {
                return arg_texts, err_default, false
            }
            append(&arg_texts, fmt.tprintf("%s = %s", param.name, default_text))
            continue
        }
        return arg_texts, missing_required_arg_error(proc_decl.name, param.name, form.span), false
    }

    return arg_texts, Compile_Error{}, true
}

emit_call_arg_for_expected_type :: proc(e: ^Emitter, arg: CST_Form, expected_type: string) -> (string, Compile_Error, bool) {
    value, err_value, ok_value := emit_expr_for_expected_type(e, arg, expected_type)
    if !ok_value {
        return "", err_value, false
    }
    if expected_type == "Data" &&
       (arg.kind == .Vector || arg.kind == .Brace || arg.kind == .Set) {
        temp := thread_temp_name(e)
        emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), value, arg.span)
        emit_line_mapped(e, fmt.tprintf("defer kvist_data_release(%s)", temp), arg.span)
        return temp, {}, true
    }
    return value, {}, true
}

emit_positional_call_with_defaults :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, args: []CST_Form, span: Span) -> (arg_texts: [dynamic]string, err: Compile_Error, ok: bool) {
    if len(args) > len(proc_decl.params) {
        return arg_texts, Compile_Error{message = fmt.tprintf("%s expects at most %d arguments", proc_decl.name, len(proc_decl.params)), span = span}, false
    }
    params, _, ok_signature := proc_decl_specialized_signature_for_args(e, proc_decl, args)
    if !ok_signature {
        for param in proc_decl.params {
            append(&params, param)
        }
    }
    defer delete(params)

    provided_names := make([dynamic]string, 0, len(args))
    defer delete(provided_names)
    provided_forms := make([dynamic]CST_Form, 0, len(args))
    defer delete(provided_forms)

    for arg, arg_idx in args {
        arg_text, err_arg, ok_arg := emit_call_arg_for_expected_type(e, arg, params[arg_idx].ty)
        if !ok_arg {
            return arg_texts, err_arg, false
        }
        append(&arg_texts, arg_text)
        append(&provided_names, params[arg_idx].name)
        append(&provided_forms, arg)
    }
    for idx := len(args); idx < len(params); idx += 1 {
        param := params[idx]
        if !param.has_default {
            return arg_texts, missing_required_arg_error(proc_decl.name, param.name, span), false
        }
        if default_is_odin_caller_intrinsic(param.default_value) {
            continue
        }
        default_text, err_default, ok_default := emit_default_expr_for_call(e, param.default_value, provided_names[:], provided_forms[:])
        if !ok_default {
            return arg_texts, err_default, false
        }
        append(&arg_texts, default_text)
    }
    return arg_texts, Compile_Error{}, true
}

emit_general_mixed_call_arg_texts :: proc(e: ^Emitter, head_name: string, positional_args: []CST_Form, named_form: CST_Form) -> (arg_texts: [dynamic]string, err: Compile_Error, ok: bool) {
    for arg, arg_idx in positional_args {
        arg_text := ""
        err_arg: Compile_Error
        ok_arg := false
        if expected_type, ok_expected := imported_odin_proc_arg_type(e, head_name, arg_idx); ok_expected {
            arg_text, err_arg, ok_arg = emit_call_arg_for_expected_type(e, arg, expected_type)
            delete(expected_type)
        } else {
            arg_text, err_arg, ok_arg = emit_expr(e, arg)
        }
        if !ok_arg {
            return arg_texts, err_arg, false
        }
        append(&arg_texts, arg_text)
    }

    named_arg_texts, err_named, ok_named := emit_named_call_arg_texts(e, named_form)
    if !ok_named {
        return arg_texts, err_named, false
    }
    append(&arg_texts, ..named_arg_texts[:])
    return arg_texts, Compile_Error{}, true
}

dotted_head_member_starts_upper :: proc(head_name: string) -> bool {
    dot := strings.index(head_name, ".")
    if dot < 0 || dot+1 >= len(head_name) {
        return false
    }
    ch := head_name[dot+1]
    return ch >= 'A' && ch <= 'Z'
}

emit_mixed_call_with_defaults :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, positional_args: []CST_Form, named_form: CST_Form, span: Span) -> (arg_texts: [dynamic]string, err: Compile_Error, ok: bool) {
    if len(positional_args) > len(proc_decl.params) {
        return arg_texts, Compile_Error{message = fmt.tprintf("%s expects at most %d arguments", proc_decl.name, len(proc_decl.params)), span = span}, false
    }

    named_values := make([dynamic]Brace_Pair, 0, len(named_form.items)/2)
    defer delete(named_values)
    provided_names := make([dynamic]string, 0, len(positional_args)+len(named_form.items)/2)
    defer delete(provided_names)
    provided_forms := make([dynamic]CST_Form, 0, len(positional_args)+len(named_form.items)/2)
    defer delete(provided_forms)

    seen: [dynamic]string
    for i := 0; i < len(named_form.items); i += 2 {
        if i+1 >= len(named_form.items) {
            return arg_texts, Compile_Error{message = "missing named argument value", span = named_form.span}, false
        }
        key := named_form.items[i]
        value := named_form.items[i+1]
        field_name, ok_key := brace_key_name(key)
        if !ok_key {
            return arg_texts, Compile_Error{message = "named arguments expect field: labels", span = key.span}, false
        }
        for existing in seen {
            if existing == field_name {
                return arg_texts, Compile_Error{message = fmt.tprintf("duplicate named argument %s", key.text), span = key.span}, false
            }
        }
        append(&seen, field_name)
        if _, ok_param := find_proc_param(proc_decl, field_name); !ok_param {
            message := fmt.tprintf("unknown named argument %s", key.text)
            if closest, ok_closest := closest_proc_param_keyword(proc_decl, field_name); ok_closest {
                message = fmt.tprintf("%s; did you mean %s", message, label_text(closest))
            }
            return arg_texts, Compile_Error{message = named_arg_message_with_valid_keys(message, proc_decl), span = key.span}, false
        }
        value_text, err_value, ok_value := emit_expr(e, value)
        if !ok_value {
            return arg_texts, err_value, false
        }
        append(&named_values, Brace_Pair{key = field_name, value = value_text})
        append(&provided_names, field_name)
        append(&provided_forms, value)
    }

    for arg, idx in positional_args {
        param := proc_decl.params[idx]
        arg_text, err_arg, ok_arg := emit_call_arg_for_expected_type(e, arg, param.ty)
        if !ok_arg {
            return arg_texts, err_arg, false
        }
        for pair in named_values {
            if pair.key == param.name {
                return arg_texts, Compile_Error{message = fmt.tprintf("named argument %s overlaps positional argument %d", label_text(param.name), idx+1), span = named_form.span}, false
            }
        }
        append(&arg_texts, arg_text)
        append(&provided_names, param.name)
        append(&provided_forms, arg)
    }

    for idx := len(positional_args); idx < len(proc_decl.params); idx += 1 {
        param := proc_decl.params[idx]
        matched := false
        for pair in named_values {
            if pair.key == param.name {
                append(&arg_texts, fmt.tprintf("%s = %s", param.name, pair.value))
                matched = true
                break
            }
        }
        if matched {
            continue
        }
        if param.has_default {
            if default_is_odin_caller_intrinsic(param.default_value) {
                continue
            }
            default_text, err_default, ok_default := emit_default_expr_for_call(e, param.default_value, provided_names[:], provided_forms[:])
            if !ok_default {
                return arg_texts, err_default, false
            }
            append(&arg_texts, fmt.tprintf("%s = %s", param.name, default_text))
            continue
        }
        return arg_texts, missing_required_arg_error(proc_decl.name, param.name, named_form.span), false
    }

    return arg_texts, Compile_Error{}, true
}

emit_operator_text :: proc(op: string, arg_texts: []string, span: Span) -> (string, Compile_Error, bool) {
    if op == "not" {
        if len(arg_texts) != 1 {
            return "", Compile_Error{message = "not expects one argument", span = span}, false
        }
        return fmt.tprintf("!(%s)", arg_texts[0]), {}, true
    }

    if op == "and" || op == "or" {
        if len(arg_texts) < 2 {
            return "", Compile_Error{message = fmt.tprintf("%s expects at least two arguments", op), span = span}, false
        }
        joiner := " && "
        if op == "or" {
            joiner = " || "
        }
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        for arg_text, idx in arg_texts {
            if idx > 0 {
                strings.write_string(&builder, joiner)
            }
            fmt.sbprintf(&builder, "(%s)", arg_text)
        }
        return strings.clone(strings.to_string(builder)), {}, true
    }

    if op == "+" || op == "*" || op == "/" || op == "%" {
        if len(arg_texts) < 2 {
            return "", Compile_Error{message = fmt.tprintf("%s expects at least two arguments", op), span = span}, false
        }
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        for arg_text, idx in arg_texts {
            if idx > 0 {
                fmt.sbprintf(&builder, " %s ", op)
            }
            fmt.sbprintf(&builder, "(%s)", arg_text)
        }
        return strings.clone(strings.to_string(builder)), {}, true
    }

    if op == "-" {
        if len(arg_texts) == 1 {
            return fmt.tprintf("-(%s)", arg_texts[0]), {}, true
        }
        if len(arg_texts) >= 2 {
            builder := strings.builder_make()
            defer strings.builder_destroy(&builder)
            for arg_text, idx in arg_texts {
                if idx > 0 {
                    strings.write_string(&builder, " - ")
                }
                fmt.sbprintf(&builder, "(%s)", arg_text)
            }
            return strings.clone(strings.to_string(builder)), {}, true
        }
        return "", Compile_Error{message = "- expects at least one argument", span = span}, false
    }

    if op == "=" || op == "==" || op == "!=" || op == "<" || op == "<=" || op == ">" || op == ">=" {
        if len(arg_texts) != 2 {
            return "", Compile_Error{message = fmt.tprintf("%s expects exactly two arguments", op), span = span}, false
        }
        odin_op := op
        if odin_op == "=" {
            odin_op = "=="
        }
        return fmt.tprintf("(%s) %s (%s)", arg_texts[0], odin_op, arg_texts[1]), {}, true
    }

    return "", Compile_Error{}, false
}

emit_update_rhs :: proc(e: ^Emitter, fn_form: CST_Form, arg_texts: []string) -> (string, Compile_Error, bool) {
    if fn_form.kind == .Symbol {
        if fn_form.text == "inc" && len(arg_texts) == 1 {
            return fmt.tprintf("(%s) + 1", arg_texts[0]), {}, true
        }
        if fn_form.text == "dec" && len(arg_texts) == 1 {
            return fmt.tprintf("(%s) - 1", arg_texts[0]), {}, true
        }
        if operator_text, err_op, ok_op := emit_operator_text(fn_form.text, arg_texts, fn_form.span); ok_op {
            return operator_text, {}, true
        } else if err_op.message != "" {
            return "", err_op, false
        }
        return emit_call_text(map_name(fn_form.text), arg_texts), {}, true
    }

    fn_text, err_fn, ok_fn := emit_expr(e, fn_form)
    if !ok_fn {
        return "", err_fn, false
    }
    return emit_call_text(fn_text, arg_texts), {}, true
}

shallow_update_temp_name :: proc(e: ^Emitter) -> string {
    e.temp_counter += 1
    return fmt.tprintf("kvist_update_%d", e.temp_counter)
}

struct_field_type_for_update :: proc(e: ^Emitter, target_ty, field: string) -> (string, bool) {
    if key_ty, value_ty, ok_entry := entry_type_parts(target_ty); ok_entry {
        switch field {
        case "key":
            return key_ty, true
        case "value":
            return value_ty, true
        }
    }
    if struct_decl, ok_struct := find_struct_decl(e, target_ty); ok_struct {
        if struct_field, ok_field := find_struct_field(struct_decl, field); ok_field {
            return struct_field.ty, true
        }
    }
    if fields, ok_imported := imported_odin_type_fields(e, target_ty); ok_imported {
        defer delete_struct_field_slice(&fields)
        if struct_field, ok_field := find_field_in_slice(fields[:], field); ok_field {
            return struct_field.ty, true
        }
    }
    return "", false
}

split_field_path_text :: proc(text: string) -> (fields: [dynamic]string, ok: bool) {
    if text == "" {
        return fields, false
    }
    start := 0
    for i := 0; i <= len(text); i += 1 {
        if i == len(text) || text[i] == '.' {
            if i == start {
                return fields, false
            }
            append(&fields, map_name(text[start:i]))
            start = i + 1
        }
    }
    return fields, len(fields) > 0
}

field_path_text :: proc(fields: []string) -> string {
    return strings.join(fields, ".", context.allocator)
}

field_access_text :: proc(base: string, fields: []string) -> string {
    if len(fields) == 0 {
        return base
    }
    path := field_path_text(fields)
    defer delete(path)
    return fmt.tprintf("%s.%s", base, path)
}

field_path_from_selector :: proc(form: CST_Form) -> (fields: [dynamic]string, ok: bool) {
    if form.kind == .Symbol && len(form.text) > 1 && form.text[0] == '.' {
        return split_field_path_text(form.text[1:])
    }
    return fields, false
}

field_path_place_parts :: proc(place: CST_Form) -> (target: CST_Form, fields: [dynamic]string, field_span: Span, ok: bool) {
    if place.kind == .List &&
       len(place.items) == 3 &&
       place.items[0].kind == .Symbol &&
       place.items[0].text == "__kvist_field" &&
       place.items[2].kind == .Symbol {
        target, fields, _, ok = field_path_place_parts(place.items[1])
        if !ok {
            target = place.items[1]
        }
        more_fields, ok_more := split_field_path_text(place.items[2].text)
        if !ok_more {
            return place.items[1], fields, place.items[2].span, false
        }
        append(&fields, ..more_fields[:])
        return target, fields, place.items[2].span, true
    }
    if place.kind == .Symbol {
        dot := strings.index(place.text, ".")
        if dot > 0 && dot+1 < len(place.text) {
            fields, ok_fields := split_field_path_text(place.text[dot+1:])
            if !ok_fields {
                return {}, fields, place.span, false
            }
            return CST_Form{kind = .Symbol, text = place.text[:dot], span = place.span},
                   fields,
                   place.span,
                   true
        }
    }
    return {}, fields, {}, false
}

shallow_assoc_args :: proc(form: CST_Form) -> (target: CST_Form, fields: [dynamic]string, field_span: Span, value: CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) == 3 {
        place_target, place_fields, place_span, ok_place := field_path_place_parts(form.items[1])
        if !ok_place {
            return {}, fields, {}, {}, Compile_Error{message = "assoc expects a field place such as user.name or user.address.city", span = form.items[1].span}, false
        }
        return place_target, place_fields, place_span, form.items[2], {}, true
    }
    if len(form.items) == 4 {
        selector_fields, ok_field := field_path_from_selector(form.items[2])
        if !ok_field {
            return {}, fields, {}, {}, Compile_Error{message = "assoc expects a field selector such as .name or .address.city", span = form.items[2].span}, false
        }
        return form.items[1], selector_fields, form.items[2].span, form.items[3], {}, true
    }
    return {}, fields, {}, {}, Compile_Error{message = "assoc expects place and value, or target, field selector, and value", span = form.span}, false
}

shallow_update_args :: proc(form: CST_Form) -> (target: CST_Form, fields: [dynamic]string, field_span: Span, updater: CST_Form, rest: []CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) >= 3 {
        place_target, place_fields, place_span, ok_place := field_path_place_parts(form.items[1])
        if ok_place {
            return place_target, place_fields, place_span, form.items[2], form.items[3:], {}, true
        }
    }
    if len(form.items) >= 4 {
        selector_fields, ok_field := field_path_from_selector(form.items[2])
        if !ok_field {
            return {}, fields, {}, {}, form.items[:0], Compile_Error{message = "update expects a field selector such as .name or .address.city", span = form.items[2].span}, false
        }
        return form.items[1], selector_fields, form.items[2].span, form.items[3], form.items[4:], {}, true
    }
    return {}, fields, {}, {}, form.items[:0], Compile_Error{message = "update expects place and updater, or target, field selector, and updater", span = form.span}, false
}

shallow_update_return_type :: proc(e: ^Emitter, form: CST_Form) -> (string, bool) {
    if form.kind != .List || len(form.items) < 2 {
        return "", false
    }
    if place_target, _, _, ok_place := field_path_place_parts(form.items[1]); ok_place {
        return obvious_form_type(e, place_target)
    }
    return obvious_form_type(e, form.items[1])
}

struct_field_type_for_update_path :: proc(e: ^Emitter, target_ty: string, fields: []string, op: string, field_span: Span) -> (string, Compile_Error, bool) {
    ty := target_ty
    for field in fields {
        field_ty, ok_field_ty := struct_field_type_for_update(e, ty, field)
        if !ok_field_ty {
            return "", Compile_Error{message = fmt.tprintf("%s could not find field .%s on %s", op, field, ty), span = field_span}, false
        }
        ty = field_ty
    }
    return ty, {}, true
}

struct_field_owns_string_for_update_path :: proc(e: ^Emitter, target_ty: string, fields: []string) -> bool {
    ty := target_ty
    for field_name, idx in fields {
        struct_decl, ok_struct := find_struct_decl(e, ty)
        if !ok_struct {
            return false
        }
        field, ok_field := find_struct_field(struct_decl, field_name)
        if !ok_field {
            return false
        }
        if idx == len(fields)-1 {
            return field.owns_string
        }
        ty = field.ty
    }
    return false
}

struct_field_owns_dynamic_array_for_update_path :: proc(
    e: ^Emitter,
    target_ty: string,
    fields: []string,
) -> bool {
    ty := target_ty
    for field_name, idx in fields {
        struct_decl, ok_struct := find_struct_decl(e, ty)
        if !ok_struct {
            return false
        }
        field, ok_field := find_struct_field(struct_decl, field_name)
        if !ok_field {
            return false
        }
        if idx == len(fields)-1 {
            return field.owns_dynamic_array
        }
        ty = field.ty
    }
    return false
}

emit_shallow_assoc_copy_expr :: proc(e: ^Emitter, target_form: CST_Form, target_text, target_ty: string, fields: []string, field_span: Span, value_form: CST_Form) -> (string, Compile_Error, bool) {
    field_ty, err_field_ty, ok_field_ty := struct_field_type_for_update_path(e, target_ty, fields, "assoc", field_span)
    if !ok_field_ty {
        return "", err_field_ty, false
    }
    value_text, err_value, ok_value := emit_expr_for_expected_type(e, value_form, field_ty)
    if !ok_value {
        return "", err_value, false
    }
    temp := shallow_update_temp_name(e)
    target_field := field_access_text(temp, fields)
    target_init := "kvist_target"
    if type_text_has_managed_lifecycle(e, target_ty) &&
       !form_produces_owned_managed_type(e, target_form, target_ty) {
        target_init = managed_clone_value_text(e, target_ty, "kvist_target")
    }
    assignment := fmt.tprintf("%s = kvist_value", target_field)
    if struct_field_owns_string_for_update_path(e, target_ty, fields) {
        mark_core_strings(e)
        assignment = fmt.tprintf("delete(%s)\n    %s = strings.clone(kvist_value)", target_field, target_field)
    } else if struct_field_owns_dynamic_array_for_update_path(e, target_ty, fields) {
        move := form_produces_owned_value(value_form, e)
        assignment = managed_dynamic_array_assignment_text(
            e,
            field_ty,
            address_of_expr_text(target_field),
            "kvist_value",
            move,
        )
    } else if type_text_has_managed_lifecycle(e, field_ty) {
        move := form_produces_owned_managed_type(e, value_form, field_ty)
        helper := managed_assign_helper_name(field_ty, move)
        assignment = emit_call_text(helper, []string{address_of_expr_text(target_field), "kvist_value"})
    }
    return fmt.tprintf("(proc(kvist_target: %s, kvist_value: %s) -> %s %s\n    %s := %s\n    %s\n    return %s\n})(%s, %s)",
                       target_ty, field_ty, target_ty, "{", temp, target_init, assignment, temp, target_text, value_text), {}, true
}

emit_data_assoc_expr :: proc(e: ^Emitter, form: CST_Form, target_text: string) -> (string, Compile_Error, bool) {
    if len(form.items) != 4 {
        return "", Compile_Error{message = "assoc on Data expects collection, key, and value", span = form.span}, false
    }
    key_text, err_key, ok_key := emit_data_lookup_key(e, form.items[2])
    if !ok_key {
        return "", err_key, false
    }
    value_text := ""
    value_owned := false
    err_value: Compile_Error
    ok_value := false
    #partial switch form.items[3].kind {
    case .Nil, .Bool, .Number, .String, .Keyword, .Vector, .Brace, .Set:
        value_text, err_value, ok_value = emit_data_value_literal(e, form.items[3])
    case:
        value_text, value_owned, err_value, ok_value = runtime_data_unquote_expr(e, form.items[3])
    }
    if !ok_value {
        return "", err_value, false
    }
    mark_data_type(e)
    if value_owned {
        return fmt.tprintf(
            "(proc(kvist_target, kvist_key, kvist_value: Data) -> Data {{\n    defer kvist_data_release(kvist_value)\n    return kvist_data_assoc(kvist_target, kvist_key, kvist_value)\n}})(%s, %s, %s)",
            target_text,
            key_text,
            value_text,
        ), {}, true
    }
    return emit_call_text("kvist_data_assoc", []string{target_text, key_text, value_text}), {}, true
}

emit_data_update_expr :: proc(e: ^Emitter, form: CST_Form, target_text: string) -> (string, Compile_Error, bool) {
    if len(form.items) < 4 {
        return "", Compile_Error{message = "update on Data expects collection, key, updater, and optional arguments", span = form.span}, false
    }
    key_text, err_key, ok_key := emit_data_lookup_key(e, form.items[2])
    if !ok_key {
        return "", err_key, false
    }
    arg_texts: [dynamic]string
    append(&arg_texts, "kvist_data_get(kvist_target, kvist_key)")
    rest_texts: [dynamic]string
    rest_names: [dynamic]string
    rest_types: [dynamic]string
    defer delete(rest_texts)
    defer delete(rest_names)
    defer delete(rest_types)
    for rest_form, idx in form.items[4:] {
        rest_ty := ""
        ok_rest_ty := false
        if form.items[3].kind == .Symbol {
            updater_name := map_name(form.items[3].text)
            if updater_decl, ok_updater := find_proc_decl(e, updater_name); ok_updater && idx+1 < len(updater_decl.params) {
                rest_ty = updater_decl.params[idx+1].ty
                ok_rest_ty = true
            }
            delete(updater_name)
        }
        if !ok_rest_ty {
            rest_ty, ok_rest_ty = obvious_form_type(e, rest_form)
        }
        if !ok_rest_ty {
            return "", Compile_Error{
                message = "update on Data expects extra updater arguments with obvious types; bind or annotate the value first",
                span = rest_form.span,
            }, false
        }
        rest_text, err_rest, ok_rest := emit_expr_for_expected_type(e, rest_form, rest_ty)
        if !ok_rest {
            return "", err_rest, false
        }
        rest_name := fmt.tprintf("kvist_arg_%d", idx)
        append(&rest_names, rest_name)
        append(&rest_types, rest_ty)
        append(&rest_texts, rest_text)
        append(&arg_texts, rest_name)
    }
    updated_text, err_updated, ok_updated := emit_update_rhs(e, form.items[3], arg_texts[:])
    if !ok_updated {
        return "", err_updated, false
    }
    if form.items[3].kind == .Symbol {
        updater_name := map_name(form.items[3].text)
        if updater_decl, ok_updater := find_proc_decl(e, updater_name); ok_updater && updater_decl.borrows_result {
            updated_text = emit_call_text("kvist_data_retain", []string{updated_text})
        }
        delete(updater_name)
    }
    params_builder := strings.builder_make()
    defer strings.builder_destroy(&params_builder)
    call_builder := strings.builder_make()
    defer strings.builder_destroy(&call_builder)
    for name, idx in rest_names {
        fmt.sbprintf(&params_builder, ", %s: %s", name, rest_types[idx])
        fmt.sbprintf(&call_builder, ", %s", rest_texts[idx])
    }
    mark_data_type(e)
    return fmt.tprintf(
        "(proc(kvist_target, kvist_key: Data%s) -> Data {{\n    kvist_updated := %s\n    defer kvist_data_release(kvist_updated)\n    return kvist_data_assoc(kvist_target, kvist_key, kvist_updated)\n}})(%s, %s%s)",
        strings.to_string(params_builder),
        updated_text,
        target_text,
        key_text,
        strings.to_string(call_builder),
    ), {}, true
}

emit_data_dissoc_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) < 3 {
        return "", Compile_Error{message = "dissoc expects Data and at least one key", span = form.span}, false
    }
    target_ty, ok_target_ty := obvious_form_type(e, form.items[1])
    if !ok_target_ty || target_ty != "Data" {
        return "", Compile_Error{message = "dissoc currently expects a Data map", span = form.items[1].span}, false
    }
    target_text, err_target, ok_target := emit_expr(e, form.items[1])
    if !ok_target {
        return "", err_target, false
    }
    keys: [dynamic]string
    defer delete(keys)
    for key_form in form.items[2:] {
        key_text, err_key, ok_key := emit_data_lookup_key(e, key_form)
        if !ok_key {
            return "", err_key, false
        }
        append(&keys, key_text)
    }
    mark_data_type(e)
    if len(keys) == 1 {
        return emit_call_text("kvist_data_dissoc", []string{target_text, keys[0]}), {}, true
    }
    params_builder := strings.builder_make()
    defer strings.builder_destroy(&params_builder)
    call_builder := strings.builder_make()
    defer strings.builder_destroy(&call_builder)
    body_builder := strings.builder_make()
    defer strings.builder_destroy(&body_builder)
    for key, idx in keys {
        fmt.sbprintf(&params_builder, ", kvist_key_%d: Data", idx)
        fmt.sbprintf(&call_builder, ", %s", key)
        fmt.sbprintf(
            &body_builder,
            "    kvist_data_move_assign(&kvist_result, kvist_data_dissoc(kvist_result, kvist_key_%d))\n",
            idx,
        )
    }
    return fmt.tprintf(
        "(proc(kvist_target: Data%s) -> Data {{\n    kvist_result := kvist_data_retain(kvist_target)\n%s    return kvist_result\n}})(%s%s)",
        strings.to_string(params_builder),
        strings.to_string(body_builder),
        target_text,
        strings.to_string(call_builder),
    ), {}, true
}

emit_data_dissoc_in_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 3 {
        return "", Compile_Error{message = "dissoc-in expects Data and one Data path", span = form.span}, false
    }
    target_ty, ok_target_ty := obvious_form_type(e, form.items[1])
    if !ok_target_ty || target_ty != "Data" {
        return "", Compile_Error{message = "dissoc-in currently expects a Data map", span = form.items[1].span}, false
    }
    target_text, err_target, ok_target := emit_expr(e, form.items[1])
    if !ok_target {
        return "", err_target, false
    }
    path_text, err_path, ok_path := emit_expr_for_expected_type(e, form.items[2], "Data")
    if !ok_path {
        return "", err_path, false
    }
    mark_data_type(e)
    return emit_call_text("kvist_data_dissoc_in", []string{target_text, path_text}), {}, true
}

decode_field_parts :: proc(ty, value_name: string) -> (expected_kind, decoded_text: string, managed: bool, ok: bool) {
    switch ty {
    case "Data":
        return "", value_name, true, true
    case "bool":
        return "Bool", fmt.tprintf("%s.payload.bool_value", value_name), false, true
    case "int", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64":
        return "Int", fmt.tprintf("%s(%s.payload.int_value)", ty, value_name), false, true
    case "f32", "f64":
        return "Float", fmt.tprintf("%s(%s.payload.float_value)", ty, value_name), false, true
    }
    return "", "", false, false
}

enum_variant_keyword :: proc(source_name: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_byte(&builder, ':')
    for ch in source_name {
        lowered := ch
        if ch >= 'A' && ch <= 'Z' {
            lowered = ch + ('a' - 'A')
        }
        strings.write_rune(&builder, lowered)
    }
    return strings.clone(strings.to_string(builder))
}

emit_decode_failure_return :: proc(
    builder: ^strings.Builder,
    path_keys: []string,
    expected_kind, actual_text: string,
    failure_id: int,
    body_depth: int = 2,
) {
    if len(path_keys) == 0 {
        fmt.sbprintf(
            builder,
            " return {{}}, data__decode_error(kvist_path, .%s, %s), false ",
            expected_kind,
            actual_text,
        )
        return
    }
    path_name := fmt.tprintf("kvist_error_path_%d", failure_id)
    strings.write_byte(builder, '\n')
    append_indent(builder, body_depth)
    fmt.sbprintf(builder, "%s := kvist_data_retain(kvist_path)\n", path_name)
    append_indent(builder, body_depth)
    fmt.sbprintf(builder, "defer kvist_data_release(%s)\n", path_name)
    for key_name in path_keys {
        append_indent(builder, body_depth)
        fmt.sbprintf(
            builder,
            "kvist_data_move_assign(&%s, kvist_data_append(%s, %s))\n",
            path_name,
            path_name,
            key_name,
        )
    }
    append_indent(builder, body_depth)
    fmt.sbprintf(
        builder,
        "return {{}}, data__decode_error(%s, .%s, %s), false\n",
        path_name,
        expected_kind,
        actual_text,
    )
    append_indent(builder, body_depth-1)
}

decode_guarded_condition :: proc(guard, condition: string) -> string {
    if guard == "" {
        return condition
    }
    return fmt.tprintf("%s && (%s)", guard, condition)
}

decode_combined_guard :: proc(parent, child: string) -> string {
    if parent == "" {
        return child
    }
    return fmt.tprintf("%s && %s", parent, child)
}

emit_struct_field_default :: proc(e: ^Emitter, field: Struct_Field) -> (string, Compile_Error, bool) {
    default_text, err_default, ok_default := emit_expr_for_expected_type(
        e,
        field.default_value,
        field.ty,
    )
    if !ok_default {
        return "", err_default, false
    }
    if field.owns_string {
        if !form_produces_owned_value(field.default_value, e) {
            mark_core_strings(e)
            default_text = emit_call_text("strings.clone", []string{default_text})
        }
    } else if field.owns_dynamic_array {
        if !form_produces_owned_value(field.default_value, e) {
            default_text = managed_clone_value_text(e, field.ty, default_text)
        }
    } else if type_text_has_managed_lifecycle(e, field.ty) &&
              !form_produces_owned_managed_type(e, field.default_value, field.ty) {
        default_text = managed_clone_value_text(e, field.ty, default_text)
    }
    return default_text, {}, true
}

decode_field_constructor_value :: proc(
    field: Struct_Field,
    decoded, present, default_value: string,
) -> string {
    value := decoded
    if field.has_default {
        value = fmt.tprintf("%s ? %s : %s", present, decoded, default_value)
    }
    return fmt.tprintf("%s = %s", field.name, value)
}

emit_decode_enum_failure_return :: proc(
    builder: ^strings.Builder,
    path_keys: []string,
    expected_type, actual_value: string,
    failure_id: int,
    body_depth: int = 2,
) {
    path_name := fmt.tprintf("kvist_enum_error_path_%d", failure_id)
    strings.write_byte(builder, '\n')
    append_indent(builder, body_depth)
    fmt.sbprintf(builder, "%s := kvist_data_retain(kvist_path)\n", path_name)
    append_indent(builder, body_depth)
    fmt.sbprintf(builder, "defer kvist_data_release(%s)\n", path_name)
    for key_name in path_keys {
        append_indent(builder, body_depth)
        fmt.sbprintf(
            builder,
            "kvist_data_move_assign(&%s, kvist_data_append(%s, %s))\n",
            path_name,
            path_name,
            key_name,
        )
    }
    append_indent(builder, body_depth)
    fmt.sbprintf(
        builder,
        "return {{}}, data__decode_enum_error(%s, %q, %s), false\n",
        path_name,
        expected_type,
        actual_value,
    )
    append_indent(builder, body_depth-1)
}

decode_enum_value_constructor_text :: proc(
    enum_decl: ^Enum_Decl,
    elem_ty, value_name: string,
) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    fmt.sbprintf(
        &builder,
        "(proc(kvist_item: Data) -> %s {{ kvist_value: %s; switch kvist_item.payload.text {{ ",
        elem_ty,
        elem_ty,
    )
    for variant in enum_decl.variants {
        keyword := enum_variant_keyword(variant.source_name)
        fmt.sbprintf(&builder, "case %q: kvist_value = .%s; ", keyword, variant.name)
        delete(keyword)
    }
    fmt.sbprintf(&builder, "case: }} return kvist_value }})(%s)", value_name)
    return strings.clone(strings.to_string(builder))
}

emit_decode_dynamic_array_unchecked_value :: proc(
    e: ^Emitter,
    field: Struct_Field,
    field_name: string,
    counter: ^int,
    root_span: Span,
    depth: int,
) -> (string, Compile_Error, bool) {
    elem_ty, ok_array := dynamic_array_element_type(field.ty)
    if !ok_array {
        return "", Compile_Error{
            message = fmt.tprintf(
                "data.decode field %s is marked as an owned dynamic array but has type %s",
                field.source_name,
                field.ty,
            ),
            span = root_span,
        }, false
    }
    _, constructed_item, managed, supported := decode_field_parts(elem_ty, "kvist_item")
    if enum_decl, enum_supported := find_enum_decl(e, elem_ty); enum_supported {
        constructed_item = decode_enum_value_constructor_text(enum_decl, elem_ty, "kvist_item")
        managed = false
        supported = true
    } else if nested_decl, nested_supported := find_struct_decl(e, elem_ty); nested_supported {
        nested_builder := strings.builder_make()
        defer strings.builder_destroy(&nested_builder)
        fmt.sbprintf(
            &nested_builder,
            "(proc(kvist_value: Data) -> %s {{\n",
            elem_ty,
        )
        nested_value, err_nested, ok_nested := emit_decode_struct_unchecked_value(
            e,
            &nested_builder,
            nested_decl,
            "kvist_value",
            counter,
            root_span,
            depth+1,
        )
        if !ok_nested {
            return "", err_nested, false
        }
        fmt.sbprintf(&nested_builder, "    return %s\n}})(kvist_item)", nested_value)
        constructed_item = strings.clone(strings.to_string(nested_builder))
        managed = false
        supported = true
    }
    if !supported {
        return "", Compile_Error{
            message = fmt.tprintf(
                "data.decode field %s has unsupported dynamic-array element type %s; supported elements are Data, bool, integer and floating-point scalars, Kvist enums, and Kvist structs",
                field.source_name,
                elem_ty,
            ),
            span = root_span,
        }, false
    }
    if managed {
        constructed_item = managed_clone_value_text(e, elem_ty, constructed_item)
    }
    return fmt.tprintf(
        "(proc(kvist_items: []Data) -> %s {{ kvist_out := make(%s, 0, len(kvist_items)); for kvist_item in kvist_items {{ append(&kvist_out, %s) }}; return kvist_out }})(%s.payload.items)",
        field.ty,
        field.ty,
        constructed_item,
        field_name,
    ), {}, true
}

emit_decode_struct_unchecked_value :: proc(
    e: ^Emitter,
    builder: ^strings.Builder,
    struct_decl: ^Struct_Decl,
    value_name: string,
    counter: ^int,
    root_span: Span,
    depth: int = 0,
) -> (string, Compile_Error, bool) {
    if depth > 16 {
        return "", Compile_Error{
            message = fmt.tprintf("data.decode nested struct depth exceeded at %s", struct_decl.name),
            span = root_span,
        }, false
    }
    field_values: [dynamic]string
    defer delete(field_values)
    for field in struct_decl.fields {
        field_id := counter^
        counter^ += 1
        key_name := fmt.tprintf("kvist_key_%d", field_id)
        field_name := fmt.tprintf("kvist_field_%d", field_id)
        key := fmt.tprintf(":%s", field.source_name)
        fmt.sbprintf(
            builder,
            "    %s := Data{{kind = .Keyword, payload = {{text = %q}}}}\n",
            key_name,
            key,
        )
        fmt.sbprintf(
            builder,
            "    %s := kvist_data_get(%s, %s)\n",
            field_name,
            value_name,
            key_name,
        )
        present_name := ""
        default_text := ""
        if field.has_default {
            present_name = fmt.tprintf("kvist_present_%d", field_id)
            fmt.sbprintf(
                builder,
                "    %s := kvist_data_contains(%s, %s)\n",
                present_name,
                value_name,
                key_name,
            )
            emitted_default, err_default, ok_default := emit_struct_field_default(e, field)
            if !ok_default {
                return "", err_default, false
            }
            default_text = emitted_default
        }

        decoded := ""
        if field.owns_dynamic_array {
            array_value, err_array, ok_array := emit_decode_dynamic_array_unchecked_value(
                e,
                field,
                field_name,
                counter,
                root_span,
                depth,
            )
            if !ok_array {
                return "", err_array, false
            }
            decoded = array_value
        } else if field.owns_string {
            mark_core_strings(e)
            decoded = fmt.tprintf("strings.clone(%s.payload.text)", field_name)
        } else if _, scalar_value, managed, supported := decode_field_parts(field.ty, field_name); supported {
            decoded = scalar_value
            if managed {
                decoded = managed_clone_value_text(e, field.ty, decoded)
            }
        } else if nested_decl, nested := find_struct_decl(e, field.ty); nested {
            nested_value, err_nested, ok_nested := emit_decode_struct_unchecked_value(
                e,
                builder,
                nested_decl,
                field_name,
                counter,
                root_span,
                depth+1,
            )
            if !ok_nested {
                return "", err_nested, false
            }
            decoded = nested_value
        } else if enum_decl, enum_found := find_enum_decl(e, field.ty); enum_found {
            decoded = decode_enum_value_constructor_text(enum_decl, field.ty, field_name)
        } else {
            return "", Compile_Error{
                message = fmt.tprintf(
                    "data.decode field %s.%s has unsupported type %s",
                    struct_decl.name,
                    field.source_name,
                    field.ty,
                ),
                span = root_span,
            }, false
        }
        append(&field_values, decode_field_constructor_value(
            field,
            decoded,
            present_name,
            default_text,
        ))
    }
    return fmt.tprintf(
        "%s{{%s}}",
        struct_decl.name,
        strings.join(field_values[:], ", ", context.temp_allocator),
    ), {}, true
}

emit_decode_dynamic_array_field :: proc(
    e: ^Emitter,
    builder: ^strings.Builder,
    field: Struct_Field,
    field_name, field_guard: string,
    field_path: []string,
    field_id: int,
    counter: ^int,
    root_span: Span,
) -> (string, Compile_Error, bool) {
    elem_ty, ok_array := dynamic_array_element_type(field.ty)
    if !ok_array {
        return "", Compile_Error{
            message = fmt.tprintf(
                "data.decode field %s is marked as an owned dynamic array but has type %s",
                field.source_name,
                field.ty,
            ),
            span = root_span,
        }, false
    }
    item_name := fmt.tprintf("kvist_item_%d", field_id)
    index_name := fmt.tprintf("kvist_index_%d", field_id)
    enum_decl, enum_supported := find_enum_decl(e, elem_ty)
    nested_decl, nested_supported := find_struct_decl(e, elem_ty)
    expected_kind, _, managed, supported := decode_field_parts(elem_ty, item_name)
    if enum_supported {
        expected_kind = "Keyword"
        managed = false
        supported = true
    } else if nested_supported {
        expected_kind = "Map"
        managed = false
        supported = true
    }
    if !supported {
        return "", Compile_Error{
            message = fmt.tprintf(
                "data.decode field %s has unsupported dynamic-array element type %s; supported elements are Data, bool, integer and floating-point scalars, Kvist enums, and Kvist structs",
                field.source_name,
                elem_ty,
            ),
            span = root_span,
        }, false
    }

    condition := decode_guarded_condition(
        field_guard,
        fmt.tprintf("%s.kind != .Vector", field_name),
    )
    fmt.sbprintf(builder, "    if %s {{", condition)
    emit_decode_failure_return(
        builder,
        field_path,
        "Vector",
        fmt.tprintf("%s.kind", field_name),
        field_id,
    )
    strings.write_string(builder, "}\n")

    if expected_kind != "" {
        loop_depth := 1
        if field_guard != "" {
            fmt.sbprintf(builder, "    if %s {{\n", field_guard)
            loop_depth = 2
        }
        append_indent(builder, loop_depth)
        fmt.sbprintf(
            builder,
            "for %s, %s in %s.payload.items {{\n",
            item_name,
            index_name,
            field_name,
        )
        index_key := fmt.tprintf("kvist_index_key_%d", field_id)
        append_indent(builder, loop_depth+1)
        fmt.sbprintf(
            builder,
            "%s := Data{{kind = .Int, payload = {{int_value = i64(%s)}}}}\n",
            index_key,
            index_name,
        )
        item_path: [dynamic]string
        defer delete(item_path)
        append(&item_path, ..field_path)
        append(&item_path, index_key)
        append_indent(builder, loop_depth+1)
        fmt.sbprintf(builder, "if %s.kind != .%s {{", item_name, expected_kind)
        emit_decode_failure_return(
            builder,
            item_path[:],
            expected_kind,
            fmt.tprintf("%s.kind", item_name),
            field_id,
            loop_depth+2,
        )
        strings.write_string(builder, "}\n")
        if enum_supported {
            invalid := strings.builder_make()
            defer strings.builder_destroy(&invalid)
            for variant, idx in enum_decl.variants {
                if idx > 0 {
                    strings.write_string(&invalid, " && ")
                }
                keyword := enum_variant_keyword(variant.source_name)
                fmt.sbprintf(&invalid, "%s.payload.text != %q", item_name, keyword)
                delete(keyword)
            }
            append_indent(builder, loop_depth+1)
            fmt.sbprintf(builder, "if %s {{", strings.to_string(invalid))
            emit_decode_enum_failure_return(
                builder,
                item_path[:],
                elem_ty,
                item_name,
                field_id,
                loop_depth+2,
            )
            strings.write_string(builder, "}\n")
        }
        if nested_supported {
            nested_validation := strings.builder_make()
            defer strings.builder_destroy(&nested_validation)
            _, err_nested, ok_nested := emit_decode_struct_value(
                e,
                &nested_validation,
                nested_decl,
                item_name,
                item_path[:],
                counter,
                root_span,
            )
            if !ok_nested {
                return "", err_nested, false
            }
            indent := strings.builder_make()
            defer strings.builder_destroy(&indent)
            for _ in 0..<loop_depth {
                strings.write_string(&indent, "    ")
            }
            append_indented_multiline(
                builder,
                strings.to_string(nested_validation),
                strings.to_string(indent),
            )
        }
        append_indent(builder, loop_depth)
        strings.write_string(builder, "}\n")
        if field_guard != "" {
            strings.write_string(builder, "    }\n")
        }
    }

    _ = enum_decl
    _ = managed
    return emit_decode_dynamic_array_unchecked_value(
        e,
        field,
        field_name,
        counter,
        root_span,
        0,
    )
}

emit_decode_struct_value :: proc(
    e: ^Emitter,
    builder: ^strings.Builder,
    struct_decl: ^Struct_Decl,
    value_name: string,
    path_keys: []string,
    counter: ^int,
    root_span: Span,
    depth: int = 0,
    parent_guard: string = "",
) -> (string, Compile_Error, bool) {
    if depth > 16 {
        return "", Compile_Error{
            message = fmt.tprintf("data.decode nested struct depth exceeded at %s", struct_decl.name),
            span = root_span,
        }, false
    }
    field_values: [dynamic]string
    defer delete(field_values)
    for field in struct_decl.fields {
        field_id := counter^
        counter^ += 1
        key_name := fmt.tprintf("kvist_key_%d", field_id)
        field_name := fmt.tprintf("kvist_field_%d", field_id)
        key := fmt.tprintf(":%s", field.source_name)
        fmt.sbprintf(
            builder,
            "    %s := Data{{kind = .Keyword, payload = {{text = %q}}}}\n",
            key_name,
            key,
        )
        fmt.sbprintf(
            builder,
            "    %s := kvist_data_get(%s, %s)\n",
            field_name,
            value_name,
            key_name,
        )
        present_name := ""
        field_guard := parent_guard
        default_text := ""
        if field.has_default {
            present_name = fmt.tprintf("kvist_present_%d", field_id)
            fmt.sbprintf(
                builder,
                "    %s := kvist_data_contains(%s, %s)\n",
                present_name,
                value_name,
                key_name,
            )
            field_guard = decode_combined_guard(parent_guard, present_name)
            emitted_default, err_default, ok_default := emit_struct_field_default(e, field)
            if !ok_default {
                return "", err_default, false
            }
            default_text = emitted_default
        }

        field_path: [dynamic]string
        defer delete(field_path)
        append(&field_path, ..path_keys)
        append(&field_path, key_name)

        if field.owns_dynamic_array {
            decoded, err_array, ok_array := emit_decode_dynamic_array_field(
                e,
                builder,
                field,
                field_name,
                field_guard,
                field_path[:],
                field_id,
                counter,
                root_span,
            )
            if !ok_array {
                return "", err_array, false
            }
            append(&field_values, decode_field_constructor_value(
                field,
                decoded,
                present_name,
                default_text,
            ))
            continue
        }

        if field.owns_string {
            condition := decode_guarded_condition(field_guard, fmt.tprintf("%s.kind != .String", field_name))
            fmt.sbprintf(builder, "    if %s {{", condition)
            emit_decode_failure_return(
                builder,
                field_path[:],
                "String",
                fmt.tprintf("%s.kind", field_name),
                field_id,
            )
            strings.write_string(builder, "}\n")
            mark_core_strings(e)
            decoded := fmt.tprintf("strings.clone(%s.payload.text)", field_name)
            append(&field_values, decode_field_constructor_value(
                field,
                decoded,
                present_name,
                default_text,
            ))
            continue
        }

        expected_kind, decoded_text, managed, supported := decode_field_parts(field.ty, field_name)
        if supported {
            if expected_kind != "" {
                condition := decode_guarded_condition(
                    field_guard,
                    fmt.tprintf("%s.kind != .%s", field_name, expected_kind),
                )
                fmt.sbprintf(builder, "    if %s {{", condition)
                emit_decode_failure_return(
                    builder,
                    field_path[:],
                    expected_kind,
                    fmt.tprintf("%s.kind", field_name),
                    field_id,
                )
                strings.write_string(builder, "}\n")
            }
            if managed {
                decoded_text = emit_call_text("kvist_data_retain", []string{decoded_text})
            }
            append(&field_values, decode_field_constructor_value(
                field,
                decoded_text,
                present_name,
                default_text,
            ))
            continue
        }

        nested_decl, nested := find_struct_decl(e, field.ty)
        if nested {
            condition := decode_guarded_condition(field_guard, fmt.tprintf("%s.kind != .Map", field_name))
            fmt.sbprintf(builder, "    if %s {{", condition)
            emit_decode_failure_return(
                builder,
                field_path[:],
                "Map",
                fmt.tprintf("%s.kind", field_name),
                field_id,
            )
            strings.write_string(builder, "}\n")
            nested_text, err_nested, ok_nested := emit_decode_struct_value(
                e,
                builder,
                nested_decl,
                field_name,
                field_path[:],
                counter,
                root_span,
                depth+1,
                field_guard,
            )
            if !ok_nested {
                return "", err_nested, false
            }
            append(&field_values, decode_field_constructor_value(
                field,
                nested_text,
                present_name,
                default_text,
            ))
            continue
        }

        enum_decl, enum_found := find_enum_decl(e, field.ty)
        if enum_found {
            condition := decode_guarded_condition(field_guard, fmt.tprintf("%s.kind != .Keyword", field_name))
            fmt.sbprintf(builder, "    if %s {{", condition)
            emit_decode_failure_return(
                builder,
                field_path[:],
                "Keyword",
                fmt.tprintf("%s.kind", field_name),
                field_id,
            )
            strings.write_string(builder, "}\n")
            enum_value_name := fmt.tprintf("kvist_enum_%d", field_id)
            fmt.sbprintf(builder, "    %s: %s\n", enum_value_name, field.ty)
            if field_guard != "" {
                fmt.sbprintf(builder, "    if %s {{\n", field_guard)
            }
            fmt.sbprintf(builder, "    switch %s.payload.text {{\n", field_name)
            for variant in enum_decl.variants {
                keyword := enum_variant_keyword(variant.source_name)
                fmt.sbprintf(
                    builder,
                    "    case %q: %s = .%s\n",
                    keyword,
                    enum_value_name,
                    variant.name,
                )
                delete(keyword)
            }
            strings.write_string(builder, "    case:\n")
            error_path_name := fmt.tprintf("kvist_enum_error_path_%d", field_id)
            fmt.sbprintf(builder, "        %s := kvist_data_retain(kvist_path)\n", error_path_name)
            fmt.sbprintf(builder, "        defer kvist_data_release(%s)\n", error_path_name)
            for key_path_name in field_path {
                fmt.sbprintf(
                    builder,
                    "        kvist_data_move_assign(&%s, kvist_data_append(%s, %s))\n",
                    error_path_name,
                    error_path_name,
                    key_path_name,
                )
            }
            fmt.sbprintf(
                builder,
                "        return {{}}, data__decode_enum_error(%s, %q, %s), false\n",
                error_path_name,
                field.ty,
                field_name,
            )
            strings.write_string(builder, "    }\n")
            if field_guard != "" {
                strings.write_string(builder, "    }\n")
            }
            append(&field_values, decode_field_constructor_value(
                field,
                enum_value_name,
                present_name,
                default_text,
            ))
            continue
        }

        return "", Compile_Error{
            message = fmt.tprintf(
                "data.decode field %s.%s has unsupported type %s; use (owned string) for decoded strings and (owned [dynamic]T) for supported vectors; other supported fields are Data, bool, integer and floating-point scalars, enums, and nested Kvist structs",
                struct_decl.name,
                field.source_name,
                field.ty,
            ),
            span = root_span,
        }, false
    }
    return fmt.tprintf(
        "%s{{%s}}",
        struct_decl.name,
        strings.join(field_values[:], ", ", context.temp_allocator),
    ), {}, true
}

emit_data_decode_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 3 && len(form.items) != 4 {
        return "", Compile_Error{message = "data.decode expects type, value, and optional path", span = form.span}, false
    }
    target_ty, err_ty, ok_ty := parse_type_text(form.items[1])
    if !ok_ty {
        return "", err_ty, false
    }
    struct_decl, ok_struct := find_struct_decl(e, target_ty)
    _, ok_dynamic_array := dynamic_array_element_type(target_ty)
    if !ok_struct && !ok_dynamic_array {
        return "", Compile_Error{
            message = fmt.tprintf(
                "data.decode expects a Kvist struct or dynamic-array type, got %s",
                target_ty,
            ),
            span = form.items[1].span,
        }, false
    }
    value_text, err_value, ok_value := emit_expr_for_expected_type(
        e,
        form.items[2],
        "Data",
    )
    if !ok_value {
        return "", err_value, false
    }
    path_text := "Data{kind = .Vector}"
    if len(form.items) == 4 {
        err_path: Compile_Error
        ok_path: bool
        path_text, err_path, ok_path = emit_expr_for_expected_type(
            e,
            form.items[3],
            "Data",
        )
        if !ok_path {
            return "", err_path, false
        }
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    fmt.sbprintf(
        &builder,
        "(proc(kvist_value, kvist_path: Data) -> (decoded: %s, err: data__Decode_Error, ok: bool) {{\n",
        target_ty,
    )
    counter := 0
    decoded_text: string
    err_decoded: Compile_Error
    ok_decoded: bool
    if ok_struct {
        strings.write_string(
            &builder,
            "    if kvist_value.kind != .Map { return {}, data__decode_error(kvist_path, .Map, kvist_value.kind), false }\n",
        )
        decoded_text, err_decoded, ok_decoded = emit_decode_struct_value(
            e,
            &builder,
            struct_decl,
            "kvist_value",
            nil,
            &counter,
            form.items[1].span,
        )
    } else {
        target_field := Struct_Field{
            name = "decoded",
            source_name = target_ty,
            ty = target_ty,
            owns_dynamic_array = true,
        }
        field_id := counter
        counter += 1
        decoded_text, err_decoded, ok_decoded = emit_decode_dynamic_array_field(
            e,
            &builder,
            target_field,
            "kvist_value",
            "",
            nil,
            field_id,
            &counter,
            form.items[1].span,
        )
    }
    if !ok_decoded {
        return "", err_decoded, false
    }
    fmt.sbprintf(
        &builder,
        "    return %s, {{}}, true\n",
        decoded_text,
    )
    fmt.sbprintf(&builder, "}})(%s, %s)", value_text, path_text)
    mark_data_type(e)
    return strings.clone(strings.to_string(builder)), {}, true
}

emit_data_validate_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 3 && len(form.items) != 4 {
        return "", Compile_Error{message = "data.validate expects type, value, and optional path", span = form.span}, false
    }
    target_ty, err_ty, ok_ty := parse_type_text(form.items[1])
    if !ok_ty {
        return "", err_ty, false
    }
    struct_decl, ok_struct := find_struct_decl(e, target_ty)
    _, ok_dynamic_array := dynamic_array_element_type(target_ty)
    if !ok_struct && !ok_dynamic_array {
        return "", Compile_Error{
            message = fmt.tprintf(
                "data.validate expects a Kvist struct or dynamic-array type, got %s",
                target_ty,
            ),
            span = form.items[1].span,
        }, false
    }
    value_text, err_value, ok_value := emit_expr_for_expected_type(
        e,
        form.items[2],
        "Data",
    )
    if !ok_value {
        return "", err_value, false
    }
    path_text := "Data{kind = .Vector}"
    if len(form.items) == 4 {
        err_path: Compile_Error
        ok_path: bool
        path_text, err_path, ok_path = emit_expr_for_expected_type(
            e,
            form.items[3],
            "Data",
        )
        if !ok_path {
            return "", err_path, false
        }
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    fmt.sbprintf(
        &builder,
        "(proc(kvist_value, kvist_path: Data) -> (err: data__Decode_Error, ok: bool) {{\n    _, kvist_validation_err, kvist_validation_ok := (proc(kvist_value, kvist_path: Data) -> (decoded: %s, err: data__Decode_Error, ok: bool) {{\n",
        target_ty,
    )
    validation_builder := strings.builder_make()
    defer strings.builder_destroy(&validation_builder)
    counter := 0
    ignored_decoded: string
    err_validated: Compile_Error
    ok_validated: bool
    if ok_struct {
        strings.write_string(
            &builder,
            "        if kvist_value.kind != .Map { return {}, data__decode_error(kvist_path, .Map, kvist_value.kind), false }\n",
        )
        ignored_decoded, err_validated, ok_validated = emit_decode_struct_value(
            e,
            &validation_builder,
            struct_decl,
            "kvist_value",
            nil,
            &counter,
            form.items[1].span,
        )
    } else {
        target_field := Struct_Field{
            name = "validated",
            source_name = target_ty,
            ty = target_ty,
            owns_dynamic_array = true,
        }
        field_id := counter
        counter += 1
        ignored_decoded, err_validated, ok_validated = emit_decode_dynamic_array_field(
            e,
            &validation_builder,
            target_field,
            "kvist_value",
            "",
            nil,
            field_id,
            &counter,
            form.items[1].span,
        )
    }
    _ = ignored_decoded
    if !ok_validated {
        return "", err_validated, false
    }
    append_indented_multiline(
        &builder,
        strings.to_string(validation_builder),
        "    ",
    )
    strings.write_string(
        &builder,
        "        return {}, {}, true\n    })(kvist_value, kvist_path)\n    return kvist_validation_err, kvist_validation_ok\n",
    )
    fmt.sbprintf(&builder, "}})(%s, %s)", value_text, path_text)
    mark_data_type(e)
    return strings.clone(strings.to_string(builder)), {}, true
}

emit_shallow_update_copy_expr :: proc(e: ^Emitter, target_form: CST_Form, target_text, target_ty: string, fields: []string, field_span: Span, updater_form: CST_Form, rest_forms: []CST_Form) -> (string, Compile_Error, bool) {
    field_ty, err_field_ty, ok_field_ty := struct_field_type_for_update_path(e, target_ty, fields, "update", field_span)
    if !ok_field_ty {
        return "", err_field_ty, false
    }
    if type_text_has_managed_lifecycle(e, field_ty) {
        return "", Compile_Error{
            message = "update of a managed field is not yet supported; compute the new value first and use assoc",
            span = field_span,
        }, false
    }
    if struct_field_owns_string_for_update_path(e, target_ty, fields) {
        return "", Compile_Error{
            message = "update of an owned string field is not yet supported; compute the new value first and use assoc",
            span = field_span,
        }, false
    }
    if struct_field_owns_dynamic_array_for_update_path(e, target_ty, fields) {
        return "", Compile_Error{
            message = "update of an owned dynamic-array field is not yet supported; compute the new value first and use assoc",
            span = field_span,
        }, false
    }
    field_text := field_access_text("kvist_target", fields)
    arg_texts: [dynamic]string
    append(&arg_texts, field_text)
    rest_texts: [dynamic]string
    rest_names: [dynamic]string
    rest_types: [dynamic]string
    defer delete(rest_texts)
    defer delete(rest_names)
    defer delete(rest_types)
    for rest_form, idx in rest_forms {
        rest_ty, ok_rest_ty := obvious_form_type(e, rest_form)
        if !ok_rest_ty {
            return "", Compile_Error{message = "update expects extra updater arguments with obvious types; bind or annotate the value first", span = rest_form.span}, false
        }
        rest_text, err_rest, ok_rest := emit_expr(e, rest_form)
        if !ok_rest {
            return "", err_rest, false
        }
        rest_name := fmt.tprintf("kvist_arg_%d", idx)
        append(&rest_names, rest_name)
        append(&rest_types, rest_ty)
        append(&rest_texts, rest_text)
        append(&arg_texts, rest_name)
    }
    value_text, err_value, ok_value := emit_update_rhs(e, updater_form, arg_texts[:])
    if !ok_value {
        return "", err_value, false
    }
    temp := shallow_update_temp_name(e)
    target_field := field_access_text(temp, fields)
    params_builder := strings.builder_make()
    defer strings.builder_destroy(&params_builder)
    call_builder := strings.builder_make()
    defer strings.builder_destroy(&call_builder)
    for name, idx in rest_names {
        fmt.sbprintf(&params_builder, ", %s: %s", name, rest_types[idx])
        fmt.sbprintf(&call_builder, ", %s", rest_texts[idx])
    }
    target_init := "kvist_target"
    if type_text_has_managed_lifecycle(e, target_ty) &&
       !form_produces_owned_managed_type(e, target_form, target_ty) {
        target_init = managed_clone_value_text(e, target_ty, "kvist_target")
    }
    return fmt.tprintf("(proc(kvist_target: %s%s) -> %s %s\n    %s := %s\n    %s = %s\n    return %s\n})(%s%s)",
                       target_ty,
                       strings.to_string(params_builder),
                       target_ty,
                       "{",
                       temp,
                       target_init,
                       target_field,
                       value_text,
                       temp,
                       target_text,
                       strings.to_string(call_builder)), {}, true
}

emit_shallow_assoc_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) >= 2 {
        if target_ty, ok_target_ty := obvious_form_type(e, form.items[1]); ok_target_ty && target_ty == "Data" {
            target_text, err_target, ok_target := emit_expr(e, form.items[1])
            if !ok_target {
                return "", err_target, false
            }
            return emit_data_assoc_expr(e, form, target_text)
        }
    }
    target_form, fields, field_span, value_form, err_args, ok_args := shallow_assoc_args(form)
    if !ok_args {
        return "", err_args, false
    }
    target_ty, ok_ty := obvious_form_type(e, target_form)
    if !ok_ty {
        return "", Compile_Error{message = "assoc expects a target with an obvious struct type; bind or annotate the value first", span = target_form.span}, false
    }
    target_text, err_target, ok_target := emit_expr(e, target_form)
    if !ok_target {
        return "", err_target, false
    }
    return emit_shallow_assoc_copy_expr(e, target_form, target_text, target_ty, fields[:], field_span, value_form)
}

emit_shallow_update_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) >= 2 {
        if target_ty, ok_target_ty := obvious_form_type(e, form.items[1]); ok_target_ty && target_ty == "Data" {
            target_text, err_target, ok_target := emit_expr(e, form.items[1])
            if !ok_target {
                return "", err_target, false
            }
            return emit_data_update_expr(e, form, target_text)
        }
    }
    target_form, fields, field_span, updater_form, rest_forms, err_args, ok_args := shallow_update_args(form)
    if !ok_args {
        return "", err_args, false
    }
    target_ty, ok_ty := obvious_form_type(e, target_form)
    if !ok_ty {
        return "", Compile_Error{message = "update expects a target with an obvious struct type; bind or annotate the value first", span = target_form.span}, false
    }
    target_text, err_target, ok_target := emit_expr(e, target_form)
    if !ok_target {
        return "", err_target, false
    }
    return emit_shallow_update_copy_expr(e, target_form, target_text, target_ty, fields[:], field_span, updater_form, rest_forms)
}

comparison_odin_op :: proc(op: string) -> string {
    if op == "=" {
        return "=="
    }
    return op
}

comparison_supports_nary :: proc(op: string) -> bool {
    return op == "=" || op == "==" || op == "<" || op == "<=" || op == ">" || op == ">="
}

comparison_form_wants_context_type :: proc(form: CST_Form) -> bool {
    if form.kind == .Number || form.kind == .Vector || form.kind == .Brace || form.kind == .Set {
        return true
    }
    if form.kind == .Symbol && len(form.text) > 1 && form.text[0] == '.' {
        return true
    }
    return false
}

comparison_context_type :: proc(e: ^Emitter, operands: []CST_Form, idx: int) -> string {
    if !comparison_form_wants_context_type(operands[idx]) {
        return ""
    }

    distance := 1
    for idx-distance >= 0 || idx+distance < len(operands) {
        if idx-distance >= 0 {
            if ty, ok := obvious_form_type(e, operands[idx-distance]); ok {
                return ty
            }
        }
        if idx+distance < len(operands) {
            if ty, ok := obvious_form_type(e, operands[idx+distance]); ok {
                return ty
            }
        }
        distance += 1
    }
    return ""
}

emit_nary_comparison_expr :: proc(e: ^Emitter, op: string, operands: []CST_Form, span: Span) -> (string, Compile_Error, bool) {
    if len(operands) < 2 {
        return "", Compile_Error{message = fmt.tprintf("%s expects at least two arguments", op), span = span}, false
    }
    if op == "!=" && len(operands) != 2 {
        return "", Compile_Error{message = "!= expects exactly two arguments", span = span}, false
    }
    if len(operands) == 2 {
        lhs_expected := ""
        rhs_expected := ""
        if ty, ok := obvious_form_type(e, operands[0]); ok {
            rhs_expected = ty
        }
        if ty, ok := obvious_form_type(e, operands[1]); ok {
            lhs_expected = ty
        }
        lhs, err_lhs, ok_lhs := emit_expr_for_expected_type(e, operands[0], lhs_expected)
        if !ok_lhs {
            return "", err_lhs, false
        }
        rhs, err_rhs, ok_rhs := emit_expr_for_expected_type(e, operands[1], rhs_expected)
        if !ok_rhs {
            return "", err_rhs, false
        }
        if (lhs_expected == "Data" || rhs_expected == "Data") && (op == "=" || op == "==" || op == "!=") {
            mark_data_type(e)
            equal := emit_call_text("kvist_data_equal", []string{lhs, rhs})
            if op == "!=" {
                return fmt.tprintf("!(%s)", equal), {}, true
            }
            return equal, {}, true
        }
        return fmt.tprintf("(%s) %s (%s)", lhs, comparison_odin_op(op), rhs), {}, true
    }
    if !comparison_supports_nary(op) {
        return "", Compile_Error{message = fmt.tprintf("%s expects exactly two arguments", op), span = span}, false
    }

    names: [dynamic]string
    defer delete(names)

    e.temp_counter += 1
    proc_id := e.temp_counter
    for idx in 0..<len(operands) {
        append(&names, fmt.tprintf("kvist_cmp_%d_%d", proc_id, idx))
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "(proc() -> bool {\n")
    for operand, idx in operands {
        expected_type := comparison_context_type(e, operands, idx)
        value, err_value, ok_value := emit_expr_for_expected_type(e, operand, expected_type)
        if !ok_value {
            return "", err_value, false
        }
        if expected_type != "" {
            fmt.sbprintf(&builder, "    %s: %s = %s\n", names[idx], expected_type, value)
        } else {
            fmt.sbprintf(&builder, "    %s := %s\n", names[idx], value)
        }
    }
    strings.write_string(&builder, "    return ")
    odin_op := comparison_odin_op(op)
    for idx in 0..<len(operands)-1 {
        if idx > 0 {
            strings.write_string(&builder, " && ")
        }
        fmt.sbprintf(&builder, "(%s) %s (%s)", names[idx], odin_op, names[idx+1])
    }
    strings.write_string(&builder, "\n})()")
    return strings.clone(strings.to_string(builder)), {}, true
}

compound_assignment_operator :: proc(head: string) -> (string, bool) {
    switch head {
    case "+=":
        return "+=", true
    case "-=":
        return "-=", true
    case "*=":
        return "*=", true
    case "/=":
        return "/=", true
    case "%=":
        return "%=", true
    case "&=":
        return "&=", true
    case "|=":
        return "|=", true
    case "^=":
        return "^=", true
    }
    return "", false
}

form_is_assignable_place :: proc(form: CST_Form) -> bool {
    if form.kind == .Symbol {
        return true
    }
    if form.kind != .List || len(form.items) == 0 {
        return false
    }
    head := form.items[0]
    if head.kind == .Keyword {
        return false
    }
    if head.kind != .Symbol {
        return false
    }
    switch head.text {
    case "deref", "^":
        return len(form.items) == 2
    case "__kvist_field":
        return len(form.items) == 3
    case "__kvist_index":
        return len(form.items) == 3
    case "odin-get":
        return len(form.items) == 3
    }
    return false
}

form_is_omitted_slice_bound :: proc(form: CST_Form) -> bool {
    return form.kind == .Symbol && form.text == "__kvist_omitted"
}

emit_compound_assignment_stmt :: proc(e: ^Emitter, form: CST_Form, op: string) -> (Compile_Error, bool) {
    if len(form.items) != 3 {
        return Compile_Error{message = fmt.tprintf("%s expects place and value", op), span = form.span}, false
    }
    if !form_is_assignable_place(form.items[1]) {
        return Compile_Error{message = fmt.tprintf("%s expects an assignable place", op), span = form.items[1].span}, false
    }
    lhs, err_lhs, ok_lhs := emit_expr(e, form.items[1])
    if !ok_lhs {
        return err_lhs, false
    }
    err_owned, bad_owned := owned_result_usage_error(form.items[2], true, e)
    if bad_owned {
        return err_owned, false
    }
    rhs, err_rhs, ok_rhs := emit_expr(e, form.items[2])
    if !ok_rhs {
        return err_rhs, false
    }
    emit_indent(e)
    strings.write_string(&e.builder, lhs)
    record_current_line_fragment_map(e, 0, lhs, form.items[1].span)
    strings.write_string(&e.builder, " ")
    strings.write_string(&e.builder, op)
    strings.write_string(&e.builder, " ")
    strings.write_string(&e.builder, rhs)
    record_current_line_fragment_map(e, len(lhs) + len(" ") + len(op) + len(" "), rhs, form.items[2].span)
    emit_raw_newline(e)
    return {}, true
}

emit_mut_bang_stmt :: proc(e: ^Emitter, form: CST_Form) -> (Compile_Error, bool) {
    if len(form.items) != 4 {
        return Compile_Error{message = "mut! expects place, operator, and value", span = form.span}, false
    }
    op_form := form.items[2]
    if op_form.kind != .Symbol {
        return Compile_Error{message = "mut! expects an assignment operator symbol", span = op_form.span}, false
    }
    if op_form.text == "=" {
        return Compile_Error{message = "mut! does not support =; use set! for plain assignment", span = op_form.span}, false
    }
    op, ok_op := compound_assignment_operator(op_form.text)
    if !ok_op {
        return Compile_Error{message = "mut! expects a compound assignment operator", span = op_form.span}, false
    }
    if !form_is_assignable_place(form.items[1]) {
        return Compile_Error{message = "mut! expects an assignable place", span = form.items[1].span}, false
    }
    if err_immutable, immutable := immutable_def_mutation_error(e, form.items[1]); immutable {
        return err_immutable, false
    }
    lhs, err_lhs, ok_lhs := emit_expr(e, form.items[1])
    if !ok_lhs {
        return err_lhs, false
    }
    err_owned, bad_owned := owned_result_usage_error(form.items[3], true, e)
    if bad_owned {
        return err_owned, false
    }
    rhs, err_rhs, ok_rhs := emit_expr(e, form.items[3])
    if !ok_rhs {
        return err_rhs, false
    }
    emit_indent(e)
    strings.write_string(&e.builder, lhs)
    record_current_line_fragment_map(e, 0, lhs, form.items[1].span)
    strings.write_string(&e.builder, " ")
    strings.write_string(&e.builder, op)
    strings.write_string(&e.builder, " ")
    strings.write_string(&e.builder, rhs)
    record_current_line_fragment_map(e, len(lhs) + len(" ") + len(op) + len(" "), rhs, form.items[3].span)
    emit_raw_newline(e)
    return {}, true
}

emit_unary_mutation_stmt :: proc(e: ^Emitter, form: CST_Form, head: string) -> (Compile_Error, bool) {
    if len(form.items) != 2 {
        return Compile_Error{message = fmt.tprintf("%s expects one place", head), span = form.span}, false
    }
    if !form_is_assignable_place(form.items[1]) {
        return Compile_Error{message = fmt.tprintf("%s expects an assignable place", head), span = form.items[1].span}, false
    }
    if err_immutable, immutable := immutable_def_mutation_error(e, form.items[1]); immutable {
        return err_immutable, false
    }
    lhs, err_lhs, ok_lhs := emit_expr(e, form.items[1])
    if !ok_lhs {
        return err_lhs, false
    }

    emit_indent(e)
    strings.write_string(&e.builder, lhs)
    record_current_line_fragment_map(e, 0, lhs, form.items[1].span)
    switch head {
    case "inc!":
        strings.write_string(&e.builder, " += 1")
    case "dec!":
        strings.write_string(&e.builder, " -= 1")
    case "toggle!":
        strings.write_string(&e.builder, " = !(")
        strings.write_string(&e.builder, lhs)
        strings.write_string(&e.builder, ")")
    case "negate!":
        strings.write_string(&e.builder, " = -(")
        strings.write_string(&e.builder, lhs)
        strings.write_string(&e.builder, ")")
    }
    emit_raw_newline(e)
    return {}, true
}

head_is_core_assoc :: proc(head: string) -> bool {
    return head == "copy-with"
}

head_is_core_update :: proc(head: string) -> bool {
    return head == "copy-update"
}

head_is_core_dissoc :: proc(head: string) -> bool {
    return head == "copy-dissoc" || head == "copy-dissoc-in"
}

 thread_temp_name :: proc(e: ^Emitter) -> string {
    e.temp_counter += 1
    return fmt.tprintf("kvist_thread_%d", e.temp_counter)
}

eval_temp_name :: proc(e: ^Emitter) -> string {
    e.temp_counter += 1
    return fmt.tprintf("kvist_eval_%d", e.temp_counter)
}

 display_head_name :: proc(head_name: string) -> string {
    head := source_package_surface_head(head_name)
    slash := strings.index(head, "/")
    if slash > 0 {
        return fmt.tprintf("%s.%s", head[:slash], head[slash+1:])
    }
    return head
}

source_package_surface_head :: proc(head_name: string) -> string {
    dot := strings.index(head_name, ".")
    slash := strings.index(head_name, "/")
    if dot > 0 && (slash < 0 || dot < slash) {
        return fmt.tprintf("%s/%s", head_name[:dot], head_name[dot+1:])
    }
    sep := strings.index(head_name, "__")
    if sep > 0 {
        pkg := head_name[:sep]
        member := head_name[sep+2:]
        if source_package_prefix_text(pkg) {
            if strings.has_suffix(member, "_impl") {
                member = member[:len(member)-len("_impl")]
            } else if strings.has_suffix(member, "-impl") {
                member = member[:len(member)-len("-impl")]
            }
            surface_member := source_package_surface_member_name(member)
            defer delete(surface_member)
            return fmt.tprintf("%s/%s", pkg, surface_member)
        }
    }
    return head_name
}

source_package_surface_member_name :: proc(member: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    i := 0
    for i < len(member) {
        if strings.has_prefix(member[i:], "_bang") {
            strings.write_byte(&builder, '!')
            i += len("_bang")
        } else if strings.has_prefix(member[i:], "-bang") {
            strings.write_byte(&builder, '!')
            i += len("-bang")
        } else if strings.has_prefix(member[i:], "_p") {
            strings.write_byte(&builder, '?')
            i += len("_p")
        } else if member[i] == '_' {
            strings.write_byte(&builder, '-')
            i += 1
        } else {
            strings.write_byte(&builder, member[i])
            i += 1
        }
    }
    return strings.clone(strings.to_string(builder))
}

source_package_prefix_text :: proc(pkg: string) -> bool {
    if len(pkg) == 0 {
        return false
    }
    for ch in pkg {
        if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '-' {
            continue
        }
        return false
    }
    return true
}

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
        if param.name == name && type_text_can_borrow_return_from_param(return_ty, param.ty) {
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
        if proc_decl.returns.kind == .Single && type_text_is_managed_value(proc_decl.returns.single_ty) {
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
    if e != nil {
        if _, ok_source_call := source_call_decl(e, form); ok_source_call {
            return true
        }
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

owned_result_usage_error :: proc(form: CST_Form, allow_root_owned: bool, e: ^Emitter = nil) -> (Compile_Error, bool) {
    if form_is_owned_result(form, e) {
        if !allow_root_owned {
            return Compile_Error{
                message = nested_owned_result_error_message(form),
                span = form.span,
            }, true
        }
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
    if form_is_owned_constructor_result(form) || form_is_literal_constructor_call(form) ||
       form_is_named_arg_brace(form) || form_is_transform_loop_call(form) {
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
                case "fn", "let", "if", "do", "for", "while", "type-case", "match",
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
            if !form_is_named_arg_brace(item) &&
               (form_produces_owned_value(item, e) ||
                item_is_owned_managed ||
                form_has_nested_owned_value(item, e)) {
                return true
            }
        }
    }
    return false
}

emit_expr_with_owned_nested_temps :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if form_is_owned_constructor_result(form) || form_is_literal_constructor_call(form) ||
       form_is_named_arg_brace(form) || form_is_transform_loop_call(form) {
        return emit_expr(e, form)
    }
    #partial switch form.kind {
    case .List, .Vector, .Brace, .Set:
        rewritten := clone_cst_form(form)
        defer delete_cst_form(&rewritten)

        start := 0
        if rewritten.kind == .List && len(rewritten.items) > 0 {
            if len(rewritten.items) == 2 &&
               (rewritten.items[1].kind == .Vector || rewritten.items[1].kind == .Brace || rewritten.items[1].kind == .Set) {
                if type_text, _, ok_type := parse_type_text(rewritten.items[0]); ok_type {
                    delete(type_text)
                    start = len(rewritten.items)
                } else {
                    start = 1
                }
            } else if rewritten.items[0].kind == .Symbol && rewritten.items[0].text == "make" {
                start = 2
            } else if rewritten.items[0].kind == .Symbol {
                start = 1
                switch rewritten.items[0].text {
                case "fn", "let", "if", "do", "for", "while", "type-case", "match",
                     "with-allocator", "with-temp-allocator":
                    start = len(rewritten.items)
                }
            } else {
                start = 1
            }
        }
        if start > len(rewritten.items) {
            start = len(rewritten.items)
        }

        for idx in start ..< len(rewritten.items) {
            item := rewritten.items[idx]
            if owned_direct_source_allowed_in_transform_source_slot(rewritten, idx, e) {
                err_source, bad_source := owned_transform_source_args_usage_error(item, e)
                if bad_source {
                    return "", err_source, false
                }
                continue
            }
            expected_type, has_expected_type := call_arg_expected_type(e, rewritten, idx)
            managed_ty, item_is_owned_managed := owned_managed_form_type(e, item)
            if has_expected_type &&
               form_produces_owned_managed_type(e, item, expected_type) {
                managed_ty = expected_type
                item_is_owned_managed = true
            }
            if form_is_named_arg_brace(item) ||
               !(form_produces_owned_value(item, e) ||
                 item_is_owned_managed ||
                 form_has_nested_owned_value(item, e)) {
                if has_expected_type {
                    delete(expected_type)
                }
                continue
            }

            value := ""
            err_value: Compile_Error
            ok_value := false
            if has_expected_type && expected_type == "Data" {
                value, err_value, ok_value = emit_expr_for_expected_type(e, item, expected_type)
            } else {
                value, err_value, ok_value = emit_expr_with_owned_nested_temps(e, item)
            }
            if has_expected_type {
                delete(expected_type)
            }
            if !ok_value {
                return "", err_value, false
            }
            temp := thread_temp_name(e)
            emit_prefixed_expr(e, fmt.tprintf("%s := ", temp), value)
            transfers_owned := rewritten.kind == .List &&
                               ((form_transfers_owned_args(rewritten) && idx >= 2) ||
                                call_arg_transfers_owned_result(e, rewritten, idx))
            if item_is_owned_managed {
                emit_line(e, fmt.tprintf("defer %s", managed_destroy_value_text(e, managed_ty, temp)))
            } else if form_produces_owned_value(item, e) && !transfers_owned {
                emit_line(e, fmt.tprintf("defer delete(%s)", temp))
            }

            delete_cst_form(&rewritten.items[idx])
            rewritten.items[idx] = macro_symbol(temp, item.span)
        }

        return emit_expr(e, rewritten)
    }

    return emit_expr(e, form)
}

form_head_is_case :: proc(form: CST_Form) -> bool {
    return len(form.items) > 0 &&
           is_symbol(form.items[0], "type-case")
}

form_head_is_match :: proc(form: CST_Form) -> bool {
    return len(form.items) > 0 && is_symbol(form.items[0], "match")
}

form_head_is_do :: proc(form: CST_Form) -> bool {
    return len(form.items) > 0 && (is_symbol(form.items[0], "do") || is_symbol(form.items[0], "block"))
}

form_head_is_allocator_scope :: proc(form: CST_Form) -> bool {
    return len(form.items) > 0 &&
           (is_symbol(form.items[0], "with-allocator") ||
            is_symbol(form.items[0], "with-temp-allocator"))
}

form_head_is_as_thread :: proc(form: CST_Form) -> bool {
    return len(form.items) > 0 &&
           is_symbol(form.items[0], "as->")
}

form_head_is_statement_only :: proc(form: CST_Form) -> (string, bool) {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return "", false
    }
    head := form.items[0].text
    switch head {
    case "for", "while", "defer", "errdefer", "set!", "mut!", "inc!", "dec!", "toggle!", "negate!", "return":
        return head, true
    }
    return "", false
}

proc_decl_type_text :: proc(proc_decl: ^Proc_Decl) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "proc(")
    for param, idx in proc_decl.params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        strings.write_string(&builder, param.ty)
    }
    strings.write_byte(&builder, ')')
    #partial switch proc_decl.returns.kind {
    case .Single:
        fmt.sbprintf(&builder, " -> %s", proc_decl.returns.single_ty)
    case .Named:
        strings.write_string(&builder, " -> [")
        for ret, idx in proc_decl.returns.named {
            if idx > 0 {
                strings.write_string(&builder, ", ")
            }
            if ret.name != "" {
                fmt.sbprintf(&builder, "%s: ", ret.name)
            }
            strings.write_string(&builder, ret.ty)
        }
        strings.write_byte(&builder, ']')
    case:
    }
    return strings.clone(strings.to_string(builder))
}

proc_literal_type_text :: proc(lit: Proc_Literal) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "proc(")
    for param, idx in lit.params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        strings.write_string(&builder, param.ty)
    }
    strings.write_byte(&builder, ')')
    #partial switch lit.returns.kind {
    case .Single:
        fmt.sbprintf(&builder, " -> %s", lit.returns.single_ty)
    case .Named:
        strings.write_string(&builder, " -> [")
        for ret, idx in lit.returns.named {
            if idx > 0 {
                strings.write_string(&builder, ", ")
            }
            if ret.name != "" {
                fmt.sbprintf(&builder, "%s: ", ret.name)
            }
            strings.write_string(&builder, ret.ty)
        }
        strings.write_byte(&builder, ']')
    case:
    }
    return strings.clone(strings.to_string(builder))
}

validate_proc_literal_for_expected_type :: proc(form: CST_Form, expected_type: string) -> (Compile_Error, bool) {
    if expected_type == "" || !type_text_is_proc(expected_type) || form.kind != .List || len(form.items) == 0 || !is_symbol(form.items[0], "fn") {
        return {}, false
    }
    if strings.contains(expected_type, "$") ||
       type_text_mentions_generic_param(expected_type, "T") ||
       type_text_mentions_generic_param(expected_type, "U") ||
       type_text_mentions_generic_param(expected_type, "K") ||
       type_text_mentions_generic_param(expected_type, "V") {
        return {}, false
    }
    parsed, err_parse, ok_parse := parse_proc_literal_form(form)
    if !ok_parse {
        return err_parse, true
    }
    expected_params, ok_expected_params := proc_type_param_types(expected_type)
    if !ok_expected_params {
        return {}, false
    }
    defer delete(expected_params)
    if len(expected_params) != len(parsed.params) {
        actual := proc_literal_type_text(parsed)
        defer delete(actual)
        return Compile_Error{message = fmt.tprintf("expected %s callback, got %s", expected_type, actual), span = form.span}, true
    }
    for expected_param, idx in expected_params {
        if strings.contains(expected_param, "$") {
            continue
        }
        if expected_param != parsed.params[idx].ty {
            actual := proc_literal_type_text(parsed)
            defer delete(actual)
            return Compile_Error{message = fmt.tprintf("expected %s callback, got %s", expected_type, actual), span = form.span}, true
        }
    }
    expected_return, expected_has_return := proc_type_single_return_type(expected_type)
    if expected_has_return {
        if parsed.returns.kind != .Single || (!strings.contains(expected_return, "$") && parsed.returns.single_ty != expected_return) {
            actual := proc_literal_type_text(parsed)
            defer delete(actual)
            return Compile_Error{message = fmt.tprintf("expected %s callback, got %s", expected_type, actual), span = form.span}, true
        }
    } else if parsed.returns.kind != .None {
        actual := proc_literal_type_text(parsed)
        defer delete(actual)
        return Compile_Error{message = fmt.tprintf("expected %s callback, got %s", expected_type, actual), span = form.span}, true
    }
    return {}, false
}

validate_known_proc_for_expected_type :: proc(e: ^Emitter, form: CST_Form, expected_type: string) -> (Compile_Error, bool) {
    if expected_type == "" || !type_text_is_proc(expected_type) || form.kind != .Symbol {
        return {}, false
    }
    if strings.contains(expected_type, "$") ||
       type_text_mentions_generic_param(expected_type, "T") ||
       type_text_mentions_generic_param(expected_type, "U") ||
       type_text_mentions_generic_param(expected_type, "K") ||
       type_text_mentions_generic_param(expected_type, "V") {
        return {}, false
    }
    _, proc_decl, ok_proc := resolve_proc_call_decl(e, form.text)
    if !ok_proc {
        return {}, false
    }
    expected_params, ok_expected_params := proc_type_param_types(expected_type)
    if !ok_expected_params {
        return {}, false
    }
    defer delete(expected_params)
    if len(expected_params) != len(proc_decl.params) {
        actual := proc_decl_type_text(proc_decl)
        defer delete(actual)
        return Compile_Error{message = fmt.tprintf("expected %s callback, got %s", expected_type, actual), span = form.span}, true
    }
    for expected_param, idx in expected_params {
        if strings.contains(expected_param, "$") {
            continue
        }
        if expected_param != proc_decl.params[idx].ty {
            actual := proc_decl_type_text(proc_decl)
            defer delete(actual)
            return Compile_Error{message = fmt.tprintf("expected %s callback, got %s", expected_type, actual), span = form.span}, true
        }
    }
    expected_return, expected_has_return := proc_type_single_return_type(expected_type)
    if expected_has_return {
        if proc_decl.returns.kind != .Single || (!strings.contains(expected_return, "$") && proc_decl.returns.single_ty != expected_return) {
            actual := proc_decl_type_text(proc_decl)
            defer delete(actual)
            return Compile_Error{message = fmt.tprintf("expected %s callback, got %s", expected_type, actual), span = form.span}, true
        }
    } else if proc_decl.returns.kind != .None {
        actual := proc_decl_type_text(proc_decl)
        defer delete(actual)
        return Compile_Error{message = fmt.tprintf("expected %s callback, got %s", expected_type, actual), span = form.span}, true
    }
    return {}, false
}

emit_expr_for_expected_type :: proc(e: ^Emitter, form: CST_Form, expected_type := "") -> (string, Compile_Error, bool) {
    if err_proc, bad_proc := validate_known_proc_for_expected_type(e, form, expected_type); bad_proc {
        return "", err_proc, false
    }
    if err_proc_literal, bad_proc_literal := validate_proc_literal_for_expected_type(form, expected_type); bad_proc_literal {
        return "", err_proc_literal, false
    }
    if expected_type != "" && form_is_expected_zero(form) {
        return zero_value_for_type_text(expected_type), {}, true
    }
    if expected_type != "" && form.kind == .List {
        if expected_item_ty, ok_expected_item_ty := dynamic_array_element_type(expected_type); ok_expected_item_ty {
            if source, ok_source_call := source_call_decl(e, form); ok_source_call {
                return emit_source_materialized_expr(e, form, source, expected_item_ty)
            }
        }
    }
    if form.kind == .List && len(form.items) > 0 && is_symbol(form.items[0], "if") {
        return emit_if_expr(e, form, expected_type)
    }
    if form.kind == .List && form_head_is_as_thread(form) {
        return emit_as_thread_expr(e, form, expected_type)
    }
    if form.kind == .List && len(form.items) > 0 && is_symbol(form.items[0], "let") {
        return emit_block_expr(e, form, expected_type)
    }
    if form.kind == .List && form_head_is_do(form) {
        return emit_block_expr(e, form, expected_type)
    }
    if form.kind == .List && form_head_is_allocator_scope(form) {
        return emit_block_expr(e, form, expected_type)
    }
    if form.kind == .List && form_head_is_case(form) {
        return emit_case_expr(e, form, expected_type)
    }
    if form.kind == .List && form_head_is_match(form) {
        return emit_block_expr(e, form, expected_type)
    }
    if expected_type == "Data" {
        value, _, err_value, ok_value := emit_contextual_data_value(e, form)
        return value, err_value, ok_value
    }
    if expected_type != "" && !strings.contains(expected_type, "$") && (form.kind == .Vector || form.kind == .Brace || form.kind == .Set) {
        return emit_inferred_literal(e, form, expected_type)
    }
    text, err, ok := emit_expr(e, form)
    if !ok {
        return "", err, false
    }
    if expected_type != "" && type_text_is_slice(expected_type) {
        actual_type, ok_actual := obvious_form_type(e, form)
        if !ok_actual && form.kind == .List && len(form.items) >= 2 {
            parsed_type, _, ok_parsed_type := parse_type_text(form.items[0])
            if ok_parsed_type {
                actual_type = parsed_type
                ok_actual = true
            }
        }
        expected_elem, ok_expected_elem := collection_element_type(expected_type)
        actual_elem, ok_actual_elem := dynamic_array_element_type(actual_type)
        if ok_actual && ok_expected_elem && ok_actual_elem && expected_elem == actual_elem {
            return slice_all_expr_text(text), {}, true
        }
    }
    return text, {}, true
}

emit_source_materialized_expr :: proc(e: ^Emitter, source_form: CST_Form, source: ^Source_Decl, expected_item_ty := "") -> (string, Compile_Error, bool) {
    state_ty, err_state_ty, ok_state_ty := source_state_type(e, source)
    if !ok_state_ty {
        return "", err_state_ty, false
    }
    err_protocol, ok_protocol := validate_source_protocol(e, source, state_ty, source_form.span)
    if !ok_protocol {
        return "", err_protocol, false
    }
    item_ty := expected_item_ty
    if item_ty == "" {
        err_item_ty: Compile_Error
        ok_item_ty: bool
        item_ty, err_item_ty, ok_item_ty = source_call_item_type(e, source, source_form)
        if !ok_item_ty {
            return "", err_item_ty, false
        }
    }
    arg_texts, err_args, ok_args := source_call_arg_texts(e, source, source_form, item_ty)
    if !ok_args {
        return "", err_args, false
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    param_texts: [dynamic]string
    call_arg_texts: [dynamic]string
    call_texts: [dynamic]string
    defer delete(param_texts)
    defer delete(call_arg_texts)
    defer delete(call_texts)
    for param, idx in source.params {
        arg_name := fmt.tprintf("kvist_source_arg_%d", idx+1)
        param_ty := source_param_type_for_item(param.ty, source.item_ty, item_ty)
        append(&param_texts, fmt.tprintf("%s: %s", arg_name, param_ty))
        append(&call_arg_texts, arg_name)
    }
    for arg_text in arg_texts {
        append(&call_texts, arg_text)
    }
    param_list := strings.join(param_texts[:], ", ", context.allocator)
    defer delete(param_list)
    call_args := strings.join(call_texts[:], ", ", context.allocator)
    defer delete(call_args)
    open_call := source_call_text(e, source, call_arg_texts[:])
    output_ty := fmt.tprintf("[dynamic]%s", item_ty)

    fmt.sbprintf(&builder, "(proc(%s) -> %s %s\n", param_list, output_ty, "{")
    fmt.sbprintf(&builder, "    kvist_source := %s\n", open_call)
    if source.has_dispose {
        fmt.sbprintf(&builder, "    defer %s(&kvist_source)\n", source.dispose_name)
    }
    fmt.sbprintf(&builder, "    kvist_out := make(%s)\n", output_ty)
    strings.write_string(&builder, "    for {\n")
    fmt.sbprintf(&builder, "        kvist_item, kvist_source_ok := %s(&kvist_source)\n", source.next_name)
    strings.write_string(&builder, "        if !kvist_source_ok {\n")
    strings.write_string(&builder, "            break\n")
    strings.write_string(&builder, "        }\n")
    strings.write_string(&builder, "        append(&kvist_out, kvist_item)\n")
    strings.write_string(&builder, "    }\n")
    strings.write_string(&builder, "    return kvist_out\n")
    strings.write_string(&builder, "})")
    return fmt.tprintf("%s(%s)", strings.to_string(builder), call_args), {}, true
}

obvious_block_expr_type :: proc(e: ^Emitter, form: CST_Form) -> (string, bool) {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return "", false
    }

    switch form.items[0].text {
    case "let":
        if len(form.items) < 3 {
            return "", false
        }
        bindings, _, ok_bind := parse_let_bindings(form.items[1])
        if !ok_bind {
            return "", false
        }
        defer delete(bindings)

        push_local_type_scope(e)
        defer pop_local_type_scope(e)
        for binding in bindings {
            bind_obvious_binding_types(e, binding)
        }
        return obvious_form_type(e, form.items[len(form.items)-1])
    case "do", "block":
        if len(form.items) < 2 {
            return "", false
        }
        return obvious_form_type(e, form.items[len(form.items)-1])
    case "type-case":
        if len(form.items) < 5 || len(form.items)%2 == 0 {
            return "", false
        }
        result_ty := ""
        i := 2
        for i < len(form.items)-1 {
            ty, binding, ignored, _, ok_pattern := case_type_payload_pattern(form.items[i])
            if !ok_pattern {
                return "", false
            }
            push_local_type_scope(e)
            if !ignored {
                bind_local_type(e, binding, ty)
            }
            branch_ty, ok_branch_ty := obvious_form_type(e, form.items[i+1])
            pop_local_type_scope(e)
            if !ok_branch_ty || (result_ty != "" && branch_ty != result_ty) {
                return "", false
            }
            result_ty = branch_ty
            i += 2
        }
        default_ty, ok_default_ty := obvious_form_type(e, form.items[len(form.items)-1])
        if !ok_default_ty || (result_ty != "" && default_ty != result_ty) {
            return "", false
        }
        return default_ty, true
    case "match":
        if len(form.items) < 6 || (len(form.items)-2)%2 != 0 {
            return "", false
        }
        result_ty := ""
        for i := 2; i < len(form.items); i += 2 {
            names: [dynamic]string
            if _, ok_pattern := validate_match_pattern(form.items[i], &names); !ok_pattern {
                delete(names)
                return "", false
            }
            push_local_type_scope(e)
            for name in names {
                bind_local_type(e, name, "Data")
            }
            branch_ty, ok_branch_ty := obvious_form_type(e, form.items[i+1])
            pop_local_type_scope(e)
            delete(names)
            if !ok_branch_ty || (result_ty != "" && branch_ty != result_ty) {
                return "", false
            }
            result_ty = branch_ty
        }
        return result_ty, result_ty != ""
    }

    return "", false
}

emit_block_expr :: proc(e: ^Emitter, form: CST_Form, expected_type := "") -> (string, Compile_Error, bool) {
    ty := expected_type
    if ty == "" {
        if inferred_ty, ok_inferred_ty := obvious_block_expr_type(e, form); ok_inferred_ty {
            ty = inferred_ty
        } else {
            label := "block"
            if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
                label = display_head_name(form.items[0].text)
            }
            return "", Compile_Error{message = fmt.tprintf("%s expression needs an expected type; add a let binding type or use it where the type is known", label), span = form.span}, false
        }
    }
    body := []CST_Form{form}
    captures := collect_proc_literal_captures(e, body, nil)
    defer delete(captures)
    proc_text, err_proc, ok_proc := emit_proc_literal_text(e, captures[:], Return_Spec{kind = .Single, single_ty = ty}, body)
    if !ok_proc {
        return "", err_proc, false
    }
    args: [dynamic]string
    defer delete(args)
    for capture in captures {
        append(&args, capture.name)
    }
    return fmt.tprintf("(%s)(%s)", proc_text, strings.join(args[:], ", ", context.temp_allocator)), {}, true
}

make_list_form :: proc(items: []CST_Form, span: Span) -> CST_Form {
    built: [dynamic]CST_Form
    for item in items {
        append(&built, item)
    }
    return CST_Form{
        kind  = .List,
        items = built,
        span  = span,
    }
}

make_vector_form :: proc(items: []CST_Form, span: Span) -> CST_Form {
    built: [dynamic]CST_Form
    for item in items {
        append(&built, item)
    }
    return CST_Form{
        kind  = .Vector,
        items = built,
        span  = span,
    }
}

obvious_as_thread_type :: proc(e: ^Emitter, form: CST_Form) -> (string, bool) {
    if !form_head_is_as_thread(form) || len(form.items) < 4 || form.items[2].kind != .Symbol {
        return "", false
    }
    name := map_name(form.items[2].text)
    current_ty, ok_current_ty := obvious_form_type(e, form.items[1])
    if !ok_current_ty {
        return "", false
    }
    for step in form.items[3:] {
        push_local_type_scope(e)
        bind_local_type(e, name, current_ty)
        next_ty, ok_next_ty := obvious_form_type(e, step)
        pop_local_type_scope(e)
        if !ok_next_ty {
            return "", false
        }
        current_ty = next_ty
    }
    return current_ty, true
}

replace_symbol_in_form :: proc(form: CST_Form, from, to: string, shadowed := false) -> CST_Form {
    if target_form, fields, field_span, ok_place := field_path_place_parts(form); ok_place {
        replaced_target := replace_symbol_in_form(target_form, from, to, shadowed)
        if len(fields) == 0 {
            return replaced_target
        }
        current := replaced_target
        for field in fields {
            current = make_list_form({make_symbol_form("__kvist_field", field_span), current, make_symbol_form(field, field_span)}, field_span)
        }
        return current
    }

    #partial switch form.kind {
    case .Symbol:
        if !shadowed && map_name(form.text) == from {
            return make_symbol_form(to, form.span)
        }
        return form
    case .List:
        if len(form.items) > 0 && is_symbol(form.items[0], "fn") && len(form.items) > 1 && form.items[1].kind == .Vector {
            shadowed_body := shadowed
            params, _, ok_params := parse_param_vector(form.items[1])
            if ok_params {
                for param in params {
                    if param.name == from {
                        shadowed_body = true
                        break
                    }
                }
            }
            items: [dynamic]CST_Form
            append(&items, form.items[0])
            append(&items, form.items[1])
            for item in form.items[2:] {
                append(&items, replace_symbol_in_form(item, from, to, shadowed_body))
            }
            return make_list_form(items[:], form.span)
        }
        if len(form.items) > 0 && is_symbol(form.items[0], "let") && len(form.items) > 1 && form.items[1].kind == .Vector {
            items: [dynamic]CST_Form
            append(&items, form.items[0])
            bindings_items: [dynamic]CST_Form
            binding_shadowed := shadowed
            for i := 0; i < len(form.items[1].items); i += 2 {
                if i+1 >= len(form.items[1].items) {
                    append(&bindings_items, form.items[1].items[i])
                    break
                }
                name_form := form.items[1].items[i]
                value_form := form.items[1].items[i+1]
                append(&bindings_items, name_form)
                append(&bindings_items, replace_symbol_in_form(value_form, from, to, binding_shadowed))
                if name_form.kind == .Symbol && map_name(name_form.text) == from {
                    binding_shadowed = true
                }
            }
            append(&items, make_vector_form(bindings_items[:], form.items[1].span))
            for item in form.items[2:] {
                append(&items, replace_symbol_in_form(item, from, to, binding_shadowed))
            }
            return make_list_form(items[:], form.span)
        }
        if form_head_is_as_thread(form) && len(form.items) >= 3 && form.items[2].kind == .Symbol {
            items: [dynamic]CST_Form
            append(&items, form.items[0])
            append(&items, replace_symbol_in_form(form.items[1], from, to, shadowed))
            append(&items, form.items[2])
            nested_shadowed := shadowed || map_name(form.items[2].text) == from
            for item in form.items[3:] {
                append(&items, replace_symbol_in_form(item, from, to, nested_shadowed))
            }
            return make_list_form(items[:], form.span)
        }
        items: [dynamic]CST_Form
        for item in form.items {
            append(&items, replace_symbol_in_form(item, from, to, shadowed))
        }
        return make_list_form(items[:], form.span)
    case .Vector:
        items: [dynamic]CST_Form
        for item in form.items {
            append(&items, replace_symbol_in_form(item, from, to, shadowed))
        }
        return make_vector_form(items[:], form.span)
    case .Brace, .Set:
        items: [dynamic]CST_Form
        for item in form.items {
            append(&items, replace_symbol_in_form(item, from, to, shadowed))
        }
        return CST_Form{
            kind  = form.kind,
            items = items,
            span  = form.span,
            text  = form.text,
        }
    case:
        return form
    }
    return form
}

emit_as_thread_expr :: proc(e: ^Emitter, form: CST_Form, expected_type := "") -> (string, Compile_Error, bool) {
    if len(form.items) < 4 {
        return "", Compile_Error{message = "as-> expects an initial expression, a name, and at least one step", span = form.span}, false
    }
    if form.items[2].kind != .Symbol {
        return "", Compile_Error{message = "as-> expects a symbol binding name", span = form.items[2].span}, false
    }

    ty := expected_type
    if ty == "" {
        inferred_ty, ok_inferred_ty := obvious_as_thread_type(e, form)
        if !ok_inferred_ty {
            return "", Compile_Error{message = "as-> expression needs an expected type; add a let binding type or use it where the type is known", span = form.span}, false
        }
        ty = inferred_ty
    }

    from_name := map_name(form.items[2].text)
    bindings_items: [dynamic]CST_Form
    current_name := thread_temp_name(e)
    append(&bindings_items, make_symbol_form(current_name, form.span))
    append(&bindings_items, form.items[1])
    for i := 3; i < len(form.items); i += 1 {
        next_name := thread_temp_name(e)
        step_form := replace_symbol_in_form(form.items[i], from_name, current_name)
        append(&bindings_items, make_symbol_form(next_name, form.items[i].span))
        append(&bindings_items, step_form)
        current_name = next_name
    }
    bindings := make_vector_form(bindings_items[:], form.span)
    top := make_list_form({make_symbol_form("let", form.span), bindings, make_symbol_form(current_name, form.span)}, form.span)
    return emit_block_expr(e, top, ty)
}

branch_type_mismatch_error :: proc(e: ^Emitter, lhs, rhs: CST_Form, what: string, span: Span) -> (Compile_Error, bool) {
    lhs_ty, ok_lhs_ty := obvious_form_type(e, lhs)
    rhs_ty, ok_rhs_ty := obvious_form_type(e, rhs)
    if ok_lhs_ty && ok_rhs_ty && lhs_ty != rhs_ty {
        return Compile_Error{message = fmt.tprintf("%s branches have different obvious types: %s and %s", what, lhs_ty, rhs_ty), span = span}, true
    }
    return {}, false
}

emit_if_expr :: proc(e: ^Emitter, form: CST_Form, expected_type := "") -> (string, Compile_Error, bool) {
    if len(form.items) != 4 {
        return "", Compile_Error{message = "if expression expects test, then, and else", span = form.span}, false
    }
    if err_branch, bad_branch := branch_type_mismatch_error(e, form.items[2], form.items[3], "if expression", form.span); bad_branch {
        return "", err_branch, false
    }
    branch_expected_type := expected_type
    if branch_expected_type == "" {
        if form_is_expected_zero(form.items[3]) {
            if inferred_ty, ok_inferred_ty := obvious_form_type(e, form.items[2]); ok_inferred_ty {
                branch_expected_type = inferred_ty
            }
        } else if form_is_expected_zero(form.items[2]) {
            if inferred_ty, ok_inferred_ty := obvious_form_type(e, form.items[3]); ok_inferred_ty {
                branch_expected_type = inferred_ty
            }
        } else {
            then_ty, ok_then_ty := obvious_form_type(e, form.items[2])
            else_ty, ok_else_ty := obvious_form_type(e, form.items[3])
            if ok_then_ty && ok_else_ty && then_ty == else_ty {
                branch_expected_type = then_ty
            }
        }
    }
    test, err_test, ok_test := emit_expr(e, form.items[1])
    if !ok_test {
        return "", err_test, false
    }
    then_value, err_then, ok_then := emit_expr_for_expected_type(e, form.items[2], branch_expected_type)
    if !ok_then {
        return "", err_then, false
    }
    else_value, err_else, ok_else := emit_expr_for_expected_type(e, form.items[3], branch_expected_type)
    if !ok_else {
        return "", err_else, false
    }
    if type_text_is_managed_value(branch_expected_type) {
        mark_data_type(e)
        if !form_produces_owned_managed_type(e, form.items[2], branch_expected_type) {
            then_value = emit_call_text("kvist_data_retain", []string{then_value})
        }
        if !form_produces_owned_managed_type(e, form.items[3], branch_expected_type) {
            else_value = emit_call_text("kvist_data_retain", []string{else_value})
        }
    }
    return fmt.tprintf("(%s if %s else %s)", then_value, test, else_value), {}, true
}

emit_case_expr :: proc(e: ^Emitter, form: CST_Form, expected_type := "") -> (string, Compile_Error, bool) {
    if len(form.items) < 5 {
        return "", Compile_Error{message = "type-case expression expects subject, type/body pairs, and default", span = form.span}, false
    }
    if len(form.items)%2 == 0 {
        return "", Compile_Error{message = "type-case expression expects type/body pairs followed by default", span = form.span}, false
    }
    i := 2
    for i < len(form.items)-1 {
        if form.items[i].kind != .List {
            return "", Compile_Error{message = "type-case expects (Type binding)", span = form.items[i].span}, false
        }
        i += 2
    }
    return emit_block_expr(e, form, expected_type)
}

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
        if form_is_borrowed_view_result(binding.value, e) && form_has_nested_owned_value(binding.value, e) {
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

body_escape_deferred_binding_span_names :: proc(forms: []CST_Form, names: []string, returns: Return_Spec) -> (Span, bool) {
    scoped_names := make([dynamic]string, len(names))
    defer delete(scoped_names)
    copy(scoped_names[:], names)

    for form in forms {
        if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol && form.items[0].text == "return" {
            if span, ok := form_escape_deferred_binding_span_names(form, scoped_names[:], returns); ok {
                return span, true
            }
        }
        if assigned_name, ok_assigned := set_bang_assigned_name(form); ok_assigned &&
           form_may_escape_deferred_binding_names(form.items[2], scoped_names[:], returns) {
            binding_names_append_unique(&scoped_names, assigned_name)
        }
    }
    if returns.kind != .None && len(forms) > 0 {
        return form_escape_deferred_binding_span_names(forms[len(forms)-1], scoped_names[:], returns)
    }
    return {}, false
}

body_may_escape_deferred_binding_names :: proc(forms: []CST_Form, names: []string, returns: Return_Spec) -> bool {
    _, ok := body_escape_deferred_binding_span_names(forms, names, returns)
    return ok
}

body_may_escape_deferred_binding :: proc(forms: []CST_Form, name: string, returns: Return_Spec) -> bool {
    names: [dynamic]string
    defer delete(names)
    append(&names, name)
    return body_may_escape_deferred_binding_names(forms, names[:], returns)
}

switch_escape_deferred_binding_span_names :: proc(form: CST_Form, names: []string, returns: Return_Spec) -> (Span, bool) {
    if len(form.items) < 4 {
        return {}, false
    }
    i := 2
    for i < len(form.items) {
        if i+1 >= len(form.items) {
            return {}, false
        }
        if span, ok := form_escape_deferred_binding_span_names(form.items[i+1], names, returns); ok {
            return span, true
        }
        i += 2
    }
    return {}, false
}

switch_may_escape_deferred_binding_names :: proc(form: CST_Form, names: []string, returns: Return_Spec) -> bool {
    _, ok := switch_escape_deferred_binding_span_names(form, names, returns)
    return ok
}

switch_may_escape_deferred_binding :: proc(form: CST_Form, name: string, returns: Return_Spec) -> bool {
    names: [dynamic]string
    defer delete(names)
    append(&names, name)
    return switch_may_escape_deferred_binding_names(form, names[:], returns)
}

form_escape_deferred_binding_span_names :: proc(form: CST_Form, names: []string, returns: Return_Spec) -> (Span, bool) {
    if !form_mentions_any_binding_name(form, names) {
        return {}, false
    }
    if return_spec_is_non_owned_scalar(returns) {
        return {}, false
    }
    if form_is_borrowed_view_of_tracked_name(form, names) {
        return {}, false
    }

    #partial switch form.kind {
    case .Symbol:
        return form.span, true
    case .Vector, .Brace, .Set:
        for item in form.items {
            if span, ok := form_escape_deferred_binding_span_names(item, names, returns); ok {
                return span, true
            }
        }
        return {}, false
    case .List:
        if len(form.items) == 0 || form.items[0].kind != .Symbol {
            for item in form.items {
                if span, ok := form_escape_deferred_binding_span_names(item, names, returns); ok {
                    return span, true
                }
            }
            return {}, false
        }
        switch form.items[0].text {
        case "return":
            for returned in form.items[1:] {
                if span, ok := form_escape_deferred_binding_span_names(returned, names, returns); ok {
                    return span, true
                }
            }
            return {}, false
        case "let":
            bindings, _, ok_bind := parse_let_bindings(form.items[1])
            if !ok_bind {
                if len(form.items) >= 3 {
                    return body_escape_deferred_binding_span_names(form.items[2:], names, returns)
                }
                return {}, false
            }
            scoped_names := make([dynamic]string, len(names))
            defer delete(scoped_names)
            copy(scoped_names[:], names)
            for binding in bindings {
                if binding.name != "" && form_may_escape_deferred_binding_names(binding.value, scoped_names[:], returns) {
                    binding_names_append_unique(&scoped_names, binding.name)
                }
            }
            if len(form.items) >= 3 {
                return body_escape_deferred_binding_span_names(form.items[2:], scoped_names[:], returns)
            }
            return {}, false
        case "do":
            if len(form.items) >= 2 {
                return body_escape_deferred_binding_span_names(form.items[1:], names, returns)
            }
            return {}, false
        case "if":
            if len(form.items) >= 3 {
                if span, ok := form_escape_deferred_binding_span_names(form.items[2], names, returns); ok {
                    return span, true
                }
            }
            if len(form.items) >= 4 {
                if span, ok := form_escape_deferred_binding_span_names(form.items[3], names, returns); ok {
                    return span, true
                }
            }
            return {}, false
        case "type-case":
            return switch_escape_deferred_binding_span_names(form, names, returns)
        case "match":
            for i := 3; i < len(form.items); i += 2 {
                if span, ok := form_escape_deferred_binding_span_names(form.items[i], names, returns); ok {
                    return span, true
                }
            }
            return {}, false
        case "with-allocator", "with-temp-allocator":
            if len(form.items) >= 3 {
                return body_escape_deferred_binding_span_names(form.items[2:], names, returns)
            }
            return {}, false
        case:
            for item in form.items[1:] {
                if span, ok := form_escape_deferred_binding_span_names(item, names, returns); ok {
                    return span, true
                }
            }
            return {}, false
        }
    }
    return {}, false
}

form_may_escape_deferred_binding_names :: proc(form: CST_Form, names: []string, returns: Return_Spec) -> bool {
    _, ok := form_escape_deferred_binding_span_names(form, names, returns)
    return ok
}

form_may_escape_deferred_binding :: proc(form: CST_Form, name: string, returns: Return_Spec) -> bool {
    names: [dynamic]string
    defer delete(names)
    append(&names, name)
    return form_may_escape_deferred_binding_names(form, names[:], returns)
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

let_defer_return_error :: proc(bindings: []Binding, body: []CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
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
            if alias_binding.name != "" && form_may_escape_deferred_binding_names(alias_binding.value, names[:], returns) {
                binding_names_append_unique(&names, alias_binding.name)
            }
        }
        if err_span, ok := body_escape_deferred_binding_span_names(body, names[:], returns); ok {
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

emit_binding_assignment :: proc(e: ^Emitter, binding: Binding, value: string) {
    if binding.is_destructure || binding.is_result_binding {
        line_builder := strings.builder_make()
        defer strings.builder_destroy(&line_builder)
        for name, idx in binding.pattern {
            if idx > 0 {
                strings.write_string(&line_builder, ", ")
            }
            strings.write_string(&line_builder, binding_output_name(name))
        }
        fmt.sbprintf(&line_builder, " := %s", value)
        emit_prefixed_expr_mapped(e, "", strings.clone(strings.to_string(line_builder)), binding.value.span)
    } else if binding.name == "" {
        emit_prefixed_expr_mapped(e, "_ = ", value, binding.value.span)
    } else if binding.is_typed {
        emit_prefixed_expr_mapped(e, fmt.tprintf("%s: %s = ", binding.name, binding.ty), value, binding.value.span)
    } else {
        emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", binding.name), value, binding.value.span)
    }
}

binding_delete_target_name :: proc(binding: Binding) -> (string, bool) {
    if binding.name != "" {
        return binding.name, true
    }
    if binding.is_result_binding && len(binding.pattern) > 0 {
        if binding.pattern[0] != "" {
            return binding.pattern[0], true
        }
    }
    return "", false
}

emit_binding_deferred_delete :: proc(e: ^Emitter, binding: Binding) -> (Compile_Error, bool) {
    delete_name, ok_delete_name := binding_delete_target_name(binding)
    if !ok_delete_name {
        return Compile_Error{message = ":defer binding marker is only supported on delete-able local bindings", span = binding.value.span}, false
    }
    emit_line(e, fmt.tprintf("defer delete(%s)", delete_name))
    return {}, true
}

emit_binding_defer_with_cleanup :: proc(e: ^Emitter, binding: Binding) -> (Compile_Error, bool) {
    delete_name, ok_delete_name := binding_delete_target_name(binding)
    if !ok_delete_name {
        return Compile_Error{message = ":defer-with binding marker is only supported on cleanable local bindings", span = binding.value.span}, false
    }
    cleanup, err_cleanup, ok_cleanup := emit_expr(e, binding.cleanup)
    if !ok_cleanup {
        return err_cleanup, false
    }
    emit_line(e, fmt.tprintf("defer %s(%s)", cleanup, delete_name))
    return {}, true
}

emit_binding_err_deferred_delete :: proc(e: ^Emitter, binding: Binding) -> (Compile_Error, bool) {
    delete_name, ok_delete_name := binding_delete_target_name(binding)
    if !ok_delete_name {
        return Compile_Error{message = ":errdefer binding marker is only supported on delete-able local bindings", span = binding.value.span}, false
    }
    if !binding.is_result_binding || binding.or_modifier != "or-return" || len(binding.pattern) != 2 || binding.pattern[1] != "err" {
        return Compile_Error{message = ":errdefer is only supported on [value err] :or-return bindings", span = binding.value.span}, false
    }
    emit_line(e, "defer {")
    e.indent += 1
    emit_line(e, "if err != nil {")
    e.indent += 1
    emit_line(e, fmt.tprintf("delete(%s)", delete_name))
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

named_returns_match_binding_pattern :: proc(returns: Return_Spec, pattern: []string) -> bool {
    if returns.kind != .Named || len(returns.named) != len(pattern) {
        return false
    }
    for item, idx in pattern {
        if item == "" {
            return false
        }
        if returns.named[idx].name != item {
            return false
        }
    }
    return true
}

emit_result_binding_guard :: proc(e: ^Emitter, binding: Binding, returns: Return_Spec) -> (Compile_Error, bool) {
    if !binding.is_result_binding {
        return {}, true
    }
    if len(binding.pattern) != 2 {
        return Compile_Error{message = "or-* let binding expects exactly two names", span = binding.value.span}, false
    }
    status_name := binding.pattern[1]
    condition := ""
    switch status_name {
    case "ok":
        condition = fmt.tprintf("!%s", status_name)
    case "err":
        condition = fmt.tprintf("%s != nil", status_name)
    case:
        return Compile_Error{message = "or-* let binding requires [value ok] or [value err]", span = binding.value.span}, false
    }

    action := ""
    switch binding.or_modifier {
    case "or-break":
        action = "break"
    case "or-continue":
        action = "continue"
    case "or-return":
        if !named_returns_match_binding_pattern(returns, binding.pattern[:]) {
            return Compile_Error{
                message = ":or-return currently requires proc named returns matching the binding names exactly",
                span = binding.value.span,
            }, false
        }
        action = "return"
    case:
        return Compile_Error{message = "unsupported let binding modifier", span = binding.value.span}, false
    }

    emit_line(e, fmt.tprintf("if %s {{", condition))
    e.indent += 1
    emit_line(e, action)
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

slice_all_expr_text :: proc(text: string) -> string {
    if len(text) >= 2 && text[0] == '[' && text[1] == ']' {
        return text
    }
    return fmt.tprintf("(%s)[:]", text)
}

address_of_expr_text :: proc(text: string) -> string {
    return fmt.tprintf("&(%s)", text)
}

deref_expr_text :: proc(text: string) -> string {
    if is_plain_identifier_text(text) {
        return fmt.tprintf("%s^", text)
    }
    return fmt.tprintf("(%s)^", text)
}

addr_expr_text :: proc(text: string) -> string {
    if is_plain_identifier_text(text) {
        return fmt.tprintf("&%s", text)
    }
    return fmt.tprintf("&(%s)", text)
}

symbol_is_simple_deref_suffix :: proc(text: string) -> bool {
    return len(text) > 1 && text[len(text)-1] == '^' && is_plain_identifier_text(map_name(text[:len(text)-1]))
}

field_from_selector :: proc(form: CST_Form) -> (field: string, ok: bool) {
    if form.kind == .Symbol && len(form.text) > 1 && form.text[0] == '.' {
        return map_name(form.text[1:]), true
    }
    return "", false
}

field_selector_looks_like_field :: proc(form: CST_Form) -> bool {
    if form.kind != .Symbol || len(form.text) <= 1 || form.text[0] != '.' {
        return false
    }
    ch := form.text[1]
    return (ch >= 'a' && ch <= 'z') || ch == '_'
}

selector_accesses_field :: proc(e: ^Emitter, target_form, selector_form: CST_Form) -> (field: string, ok: bool) {
    selector_field, ok_field := field_from_selector(selector_form)
    if !ok_field {
        return "", false
    }
    if target_form.kind == .Symbol {
        target_name := target_form.text
        if symbol_is_simple_deref_suffix(target_name) {
            target_name = target_name[:len(target_name)-1]
        }
        if target_ty, ok_ty := lookup_local_type(e, map_name(target_name)); ok_ty {
            ty := target_ty
            if strings.has_prefix(ty, "^") {
                ty = ty[1:]
            }
            if _, ok_struct := find_struct_decl(e, ty); ok_struct {
                return selector_field, true
            }
            return "", false
        }
    }
    if field_selector_looks_like_field(selector_form) {
        return selector_field, true
    }
    return "", false
}

field_type_expr_text :: proc(collection, field: string) -> string {
    return fmt.tprintf("type_of((%s)[0].%s)", collection, field)
}

type_text_is_dynamic_array :: proc(text: string) -> bool {
    return len(text) >= 9 && text[:9] == "[dynamic]"
}

type_text_is_pointer_to_dynamic_array :: proc(text: string) -> bool {
    return len(text) >= 10 && text[:10] == "^[dynamic]"
}

type_text_is_slice_or_fixed_array :: proc(text: string) -> bool {
    return len(text) >= 2 && text[0] == '[' && !type_text_is_dynamic_array(text) ||
           type_text_is_soa(text) && !type_text_is_dynamic_soa(text)
}

type_text_is_fixed_array :: proc(text: string) -> bool {
    return len(text) > 2 && text[0] == '[' && text[1] != ']' && !type_text_is_dynamic_array(text)
}

type_text_is_map :: proc(text: string) -> bool {
    return len(text) >= 4 && text[:4] == "map["
}

type_text_is_pointer_to_map :: proc(text: string) -> bool {
    return len(text) >= 5 && text[0] == '^' && type_text_is_map(text[1:])
}

set_element_type :: proc(text: string) -> (string, bool) {
    if key_ty, value_ty, ok_map := map_type_parts(text); ok_map && value_ty == "struct{}" {
        return key_ty, true
    }
    return "", false
}

map_index_target_text :: proc(e: ^Emitter, form: CST_Form, emitted: string) -> string {
    if ty, ok_ty := obvious_form_type(e, form); ok_ty && type_text_is_pointer_to_map(ty) {
        return deref_expr_text(emitted)
    }
    return emitted
}

map_mutation_target_text :: proc(e: ^Emitter, form: CST_Form, emitted: string) -> string {
    if ty, ok_ty := obvious_form_type(e, form); ok_ty && type_text_is_pointer_to_map(ty) {
        return emitted
    }
    return address_of_expr_text(emitted)
}

type_text_is_owned_result :: proc(text: string) -> bool {
    return type_text_is_dynamic_array(text) || type_text_is_dynamic_soa(text) || type_text_is_map(text)
}

type_text_is_managed_value :: proc(text: string) -> bool {
    return strings.trim_space(text) == "Data"
}

type_text_has_managed_lifecycle :: proc(e: ^Emitter, text: string, depth: int = 0) -> bool {
    if type_text_is_managed_value(text) {
        return true
    }
    if e == nil || depth > 16 {
        return false
    }
    struct_decl, ok_struct := find_struct_decl(e, strings.trim_space(text))
    if !ok_struct {
        return false
    }
    for field in struct_decl.fields {
        if field.owns_string ||
           field.owns_dynamic_array ||
           type_text_has_managed_lifecycle(e, field.ty, depth+1) {
            return true
        }
    }
    return false
}

managed_struct_helper_name :: proc(op, ty: string) -> string {
    return fmt.tprintf("kvist_managed_%s_%s", op, ty)
}

managed_clone_value_text :: proc(e: ^Emitter, ty, value: string) -> string {
    if type_text_is_managed_value(ty) {
        mark_data_type(e)
        return emit_call_text("kvist_data_retain", []string{value})
    }
    if elem_ty, ok_dynamic := dynamic_array_element_type(ty); ok_dynamic {
        if type_text_has_managed_lifecycle(e, elem_ty) {
            cloned_item := managed_clone_value_text(e, elem_ty, "kvist_item")
            return fmt.tprintf(
                "(proc(kvist_values: %s) -> %s {{ kvist_out := make(%s, 0, len(kvist_values)); for kvist_item in kvist_values {{ append(&kvist_out, %s) }}; return kvist_out }})(%s)",
                ty,
                ty,
                ty,
                cloned_item,
                value,
            )
        }
        return fmt.tprintf(
            "(proc(kvist_values: %s) -> %s {{ kvist_out := make(%s, len(kvist_values)); copy(kvist_out[:], kvist_values[:]); return kvist_out }})(%s)",
            ty,
            ty,
            ty,
            value,
        )
    }
    return emit_call_text(managed_struct_helper_name("clone", ty), []string{value})
}

managed_destroy_value_text :: proc(e: ^Emitter, ty, value: string) -> string {
    if type_text_is_managed_value(ty) {
        mark_data_type(e)
        return emit_call_text("kvist_data_release", []string{value})
    }
    if elem_ty, ok_dynamic := dynamic_array_element_type(ty); ok_dynamic {
        if type_text_has_managed_lifecycle(e, elem_ty) {
            destroyed_item := managed_destroy_value_text(e, elem_ty, "kvist_item")
            return fmt.tprintf(
                "(proc(kvist_values: %s) {{ for kvist_item in kvist_values {{ %s }}; delete(kvist_values) }})(%s)",
                ty,
                destroyed_item,
                value,
            )
        }
        return emit_call_text("delete", []string{value})
    }
    return emit_call_text(managed_struct_helper_name("destroy", ty), []string{value})
}

managed_dynamic_array_assignment_text :: proc(
    e: ^Emitter,
    ty, place, value: string,
    move: bool,
) -> string {
    destroy_previous := managed_destroy_value_text(e, ty, "kvist_previous")
    if move {
        return fmt.tprintf(
            "(proc(kvist_place: ^%s, kvist_value: %s) {{ kvist_previous := kvist_place^; kvist_place^ = kvist_value; %s }})(%s, %s)",
            ty,
            ty,
            destroy_previous,
            place,
            value,
        )
    }
    replacement := managed_clone_value_text(e, ty, "kvist_value")
    return fmt.tprintf(
        "(proc(kvist_place: ^%s, kvist_value: %s) {{ kvist_replacement := %s; kvist_previous := kvist_place^; kvist_place^ = kvist_replacement; %s }})(%s, %s)",
        ty,
        ty,
        replacement,
        destroy_previous,
        place,
        value,
    )
}

managed_assign_helper_name :: proc(ty: string, move: bool) -> string {
    if type_text_is_managed_value(ty) {
        return "kvist_data_move_assign" if move else "kvist_data_assign"
    }
    return managed_struct_helper_name("move_assign" if move else "assign", ty)
}

emit_managed_struct_helpers :: proc(e: ^Emitter, struct_decl: Struct_Decl) {
    if !type_text_has_managed_lifecycle(e, struct_decl.name) {
        return
    }
    clone_name := managed_struct_helper_name("clone", struct_decl.name)
    destroy_name := managed_struct_helper_name("destroy", struct_decl.name)
    assign_name := managed_struct_helper_name("assign", struct_decl.name)
    move_assign_name := managed_struct_helper_name("move_assign", struct_decl.name)

    emit_raw_newline(e)
    emit_line(e, fmt.tprintf("%s :: proc(value: %s) -> %s {{", clone_name, struct_decl.name, struct_decl.name))
    e.indent += 1
    emit_line(e, "out := value")
    for field in struct_decl.fields {
        if field.owns_string {
            mark_core_strings(e)
            emit_line(e, fmt.tprintf("out.%s = strings.clone(value.%s)", field.name, field.name))
        } else if field.owns_dynamic_array {
            cloned := managed_clone_value_text(e, field.ty, fmt.tprintf("value.%s", field.name))
            emit_line(e, fmt.tprintf("out.%s = %s", field.name, cloned))
        } else if type_text_has_managed_lifecycle(e, field.ty) {
            retained := managed_clone_value_text(e, field.ty, fmt.tprintf("value.%s", field.name))
            emit_line(e, fmt.tprintf("out.%s = %s", field.name, retained))
        }
    }
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")

    emit_raw_newline(e)
    emit_line(e, fmt.tprintf("%s :: proc(value: %s) {{", destroy_name, struct_decl.name))
    e.indent += 1
    for offset in 0..<len(struct_decl.fields) {
        field := struct_decl.fields[len(struct_decl.fields)-1-offset]
        if field.owns_string {
            emit_line(e, fmt.tprintf("delete(value.%s)", field.name))
        } else if field.owns_dynamic_array {
            emit_line(e, managed_destroy_value_text(e, field.ty, fmt.tprintf("value.%s", field.name)))
        } else if type_text_has_managed_lifecycle(e, field.ty) {
            emit_line(e, managed_destroy_value_text(e, field.ty, fmt.tprintf("value.%s", field.name)))
        }
    }
    e.indent -= 1
    emit_line(e, "}")

    emit_raw_newline(e)
    emit_line(e, fmt.tprintf("%s :: proc(place: ^%s, value: %s) {{", assign_name, struct_decl.name, struct_decl.name))
    e.indent += 1
    emit_line(e, fmt.tprintf("replacement := %s(value)", clone_name))
    emit_line(e, "previous := place^")
    emit_line(e, "place^ = replacement")
    emit_line(e, fmt.tprintf("%s(previous)", destroy_name))
    e.indent -= 1
    emit_line(e, "}")

    emit_raw_newline(e)
    emit_line(e, fmt.tprintf("%s :: proc(place: ^%s, value: %s) {{", move_assign_name, struct_decl.name, struct_decl.name))
    e.indent += 1
    emit_line(e, "previous := place^")
    emit_line(e, "place^ = value")
    emit_line(e, fmt.tprintf("%s(previous)", destroy_name))
    e.indent -= 1
    emit_line(e, "}")
}

form_produces_owned_managed_value :: proc(e: ^Emitter, form: CST_Form, depth: int = 0) -> bool {
    if depth > 8 || form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    head_name := map_name(form.items[0].text)
    defer delete(head_name)
    if form.items[0].text == "quasiquote" {
        return true
    }
    if form.items[0].text == "into" {
        output_ty, _, _, ok_output_ty := parse_type_text_from_forms(form.items[:], 1)
        if ok_output_ty {
            defer delete(output_ty)
            if type_text_is_managed_value(output_ty) {
                return true
            }
        }
    }
    if head_is_core_assoc(form.items[0].text) ||
       head_is_core_update(form.items[0].text) ||
       head_is_core_dissoc(form.items[0].text) {
        if ty, ok_ty := obvious_form_type(e, form); ok_ty && type_text_is_managed_value(ty) {
            return true
        }
    }
    switch form.items[0].text {
    case "if", "let", "do", "block", "type-case", "match":
        if ty, ok_ty := obvious_form_type(e, form); ok_ty && type_text_is_managed_value(ty) {
            return true
        }
    case:
    }
    if proc_decl, ok_proc := find_proc_decl(e, head_name); ok_proc {
        return proc_decl.returns.kind == .Single &&
               type_text_is_managed_value(proc_decl.returns.single_ty) &&
               !proc_decl.borrows_result
    }
    if proc_ty, ok_proc_ty := lookup_local_type(e, head_name); ok_proc_ty && type_text_is_proc(proc_ty) {
        if return_ty, ok_return_ty := proc_type_single_return_type(proc_ty); ok_return_ty {
            return type_text_is_managed_value(return_ty)
        }
    }
    if form.items[0].text == "if" && len(form.items) == 4 {
        return form_produces_owned_managed_value(e, form.items[2], depth+1) &&
               form_produces_owned_managed_value(e, form.items[3], depth+1)
    }
    return false
}

form_produces_owned_managed_type :: proc(e: ^Emitter, form: CST_Form, ty: string, depth: int = 0) -> bool {
    if type_text_is_managed_value(ty) {
        if form.kind == .Vector || form.kind == .Brace || form.kind == .Set {
            return true
        }
        return form_produces_owned_managed_value(e, form, depth)
    }
    if depth > 8 || !type_text_has_managed_lifecycle(e, ty) {
        return false
    }
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    head_name := map_name(form.items[0].text)
    defer delete(head_name)
    if head_name == ty &&
       len(form.items) == 2 &&
       form.items[1].kind == .Brace {
        return true
    }
    if form.items[0].text == "copy-with" || form.items[0].text == "copy-update" {
        if result_ty, ok_result_ty := obvious_form_type(e, form); ok_result_ty && result_ty == ty {
            return true
        }
    }
    if proc_decl, ok_proc := find_proc_decl(e, head_name); ok_proc {
        return proc_decl.returns.kind == .Single &&
               proc_decl.returns.single_ty == ty &&
               !proc_decl.borrows_result
    }
    return false
}

owned_managed_form_type :: proc(e: ^Emitter, form: CST_Form) -> (string, bool) {
    ty, ok_ty := obvious_form_type(e, form)
    if !ok_ty || !type_text_has_managed_lifecycle(e, ty) ||
       !form_produces_owned_managed_type(e, form, ty) {
        return "", false
    }
    return ty, true
}

emit_discarded_expr :: proc(e: ^Emitter, form: CST_Form, expr: string) {
    if managed_ty, managed := owned_managed_form_type(e, form); managed {
        temp := thread_temp_name(e)
        emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), expr, form.span)
        emit_line_mapped(e, managed_destroy_value_text(e, managed_ty, temp), form.span)
        return
    }
    emit_prefixed_expr_mapped(e, "_ = ", expr, form.span)
}

managed_binding_value_text :: proc(e: ^Emitter, binding: Binding, value: string) -> (text, managed_ty: string, managed: bool) {
    ty, ok_ty := obvious_binding_type(e, binding)
    if !ok_ty || !type_text_has_managed_lifecycle(e, ty) || binding.name == "" || binding.is_destructure || binding.is_result_binding {
        return value, "", false
    }
    if form_produces_owned_managed_type(e, binding.value, ty) {
        return value, ty, true
    }
    return managed_clone_value_text(e, ty, value), ty, true
}

managed_return_value_text_for_type :: proc(e: ^Emitter, form: CST_Form, value, return_ty: string) -> string {
    if !type_text_has_managed_lifecycle(e, return_ty) ||
       e.current_proc_owns_managed_result ||
       e.current_proc_borrows_managed_result ||
       form_produces_owned_managed_type(e, form, return_ty) {
        return value
    }
    return managed_clone_value_text(e, return_ty, value)
}

managed_return_value_text :: proc(e: ^Emitter, form: CST_Form, value: string, returns: Return_Spec) -> string {
    if returns.kind != .Single {
        return value
    }
    return managed_return_value_text_for_type(e, form, value, returns.single_ty)
}

emit_managed_destructure_cleanup :: proc(e: ^Emitter, binding: Binding) {
    if !binding.is_destructure || binding.value.kind != .List || len(binding.value.items) == 0 || binding.value.items[0].kind != .Symbol {
        return
    }
    head_name := map_name(binding.value.items[0].text)
    defer delete(head_name)
    if head_name == "decode_data" && len(binding.pattern) == 3 && len(binding.value.items) >= 2 {
        target_ty, _, ok_target_ty := parse_type_text(binding.value.items[1])
        if ok_target_ty {
            if binding.pattern[0] != "" &&
               (type_text_has_managed_lifecycle(e, target_ty) ||
                type_text_is_owned_result(target_ty)) {
                emit_line(e, fmt.tprintf(
                    "defer %s",
                    managed_destroy_value_text(e, target_ty, binding.pattern[0]),
                ))
            }
            if binding.pattern[1] != "" {
                emit_line(e, fmt.tprintf(
                    "defer %s",
                    managed_destroy_value_text(e, "data__Decode_Error", binding.pattern[1]),
                ))
            }
        }
        return
    }
    if head_name == "validate_data" && len(binding.pattern) == 2 {
        if binding.pattern[0] != "" {
            emit_line(e, fmt.tprintf(
                "defer %s",
                managed_destroy_value_text(e, "data__Decode_Error", binding.pattern[0]),
            ))
        }
        return
    }
    proc_decl, ok_proc := find_proc_decl(e, head_name)
    if !ok_proc || proc_decl.borrows_result || proc_decl.returns.kind != .Named || len(proc_decl.returns.named) != len(binding.pattern) {
        return
    }
    for name, idx in binding.pattern {
        if name != "" && type_text_has_managed_lifecycle(e, proc_decl.returns.named[idx].ty) {
            emit_line(e, fmt.tprintf(
                "defer %s",
                managed_destroy_value_text(e, proc_decl.returns.named[idx].ty, name),
            ))
        }
    }
}

managed_assignment_text :: proc(e: ^Emitter, place_form, value_form: CST_Form, place, value: string) -> (string, bool) {
    if target_form, fields, _, ok_place := field_path_place_parts(place_form); ok_place {
        if target_ty, ok_target_ty := obvious_form_type(e, target_form);
           ok_target_ty && struct_field_owns_string_for_update_path(e, target_ty, fields[:]) {
            mark_core_strings(e)
            if form_produces_owned_value(value_form, e) {
                return fmt.tprintf(
                    "(proc(kvist_place: ^string, kvist_value: string) {{ kvist_previous := kvist_place^; kvist_place^ = kvist_value; delete(kvist_previous) }})(%s, %s)",
                    address_of_expr_text(place),
                    value,
                ), true
            }
            return fmt.tprintf(
                "(proc(kvist_place: ^string, kvist_value: string) {{ kvist_replacement := strings.clone(kvist_value); kvist_previous := kvist_place^; kvist_place^ = kvist_replacement; delete(kvist_previous) }})(%s, %s)",
                address_of_expr_text(place),
                value,
            ), true
        }
        if target_ty, ok_target_ty := obvious_form_type(e, target_form);
           ok_target_ty &&
           struct_field_owns_dynamic_array_for_update_path(e, target_ty, fields[:]) {
            field_ty, err_field_ty, ok_field_ty := struct_field_type_for_update_path(
                e,
                target_ty,
                fields[:],
                "set!",
                place_form.span,
            )
            _ = err_field_ty
            if ok_field_ty {
                move := form_produces_owned_value(value_form, e)
                return managed_dynamic_array_assignment_text(
                    e,
                    field_ty,
                    address_of_expr_text(place),
                    value,
                    move,
                ), true
            }
        }
    }
    place_ty, ok_place_ty := obvious_form_type(e, place_form)
    if !ok_place_ty || !type_text_has_managed_lifecycle(e, place_ty) {
        return "", false
    }
    move := form_produces_owned_managed_type(e, value_form, place_ty)
    helper := managed_assign_helper_name(place_ty, move)
    return emit_call_text(helper, []string{address_of_expr_text(place), value}), true
}

immutable_def_mutation_error :: proc(e: ^Emitter, place: CST_Form) -> (Compile_Error, bool) {
    if place.kind != .Symbol {
        return {}, false
    }
    name := map_name(place.text)
    defer delete(name)
    if _, local := lookup_local_type(e, name); local {
        return {}, false
    }
    for decl in e.decls {
        if decl.kind == .Const &&
           !decl.const_decl.is_type_alias &&
           !decl.const_decl.is_overload &&
           decl.const_decl.name == name {
            return Compile_Error{
                message = fmt.tprintf("cannot mutate immutable def %s; use defvar for mutable package state", place.text),
                span = place.span,
            }, true
        }
    }
    return {}, false
}

type_text_is_string :: proc(text: string) -> bool {
    return text == "string"
}

type_text_can_borrow_return_from_param :: proc(return_ty, param_ty: string) -> bool {
    if type_text_is_string(return_ty) {
        return type_text_is_string(param_ty)
    }
    if type_text_is_slice_or_fixed_array(return_ty) {
        return type_text_is_slice_or_fixed_array(param_ty) || type_text_is_dynamic_array(param_ty)
    }
    return false
}

borrowed_return_type_text :: proc(returns: Return_Spec) -> (string, bool) {
    if returns.kind == .Single {
        if type_text_is_string(returns.single_ty) || type_text_is_slice_or_fixed_array(returns.single_ty) {
            return returns.single_ty, true
        }
        return "", false
    }
    if returns.kind == .Named {
        for named in returns.named {
            if type_text_is_string(named.ty) || type_text_is_slice_or_fixed_array(named.ty) {
                return named.ty, true
            }
        }
    }
    return "", false
}

proc_decl_borrow_owner_arg_index :: proc(proc_decl: ^Proc_Decl) -> (int, bool) {
    return_ty, ok_return := borrowed_return_type_text(proc_decl.returns)
    if !ok_return {
        return -1, false
    }
    for param, idx in proc_decl.params {
        if type_text_can_borrow_return_from_param(return_ty, param.ty) {
            return idx, true
        }
    }
    return -1, false
}

return_spec_is_owned_result :: proc(returns: Return_Spec) -> bool {
    if returns.kind == .Single {
        return type_text_is_owned_result(returns.single_ty)
    }
    if returns.kind == .Named {
        for named in returns.named {
            if type_text_is_owned_result(named.ty) {
                return true
            }
        }
    }
    return false
}

map_type_parts :: proc(text: string) -> (key, value: string, ok: bool) {
    if !type_text_is_map(text) {
        return "", "", false
    }
    split := strings.index(text, "]")
    if split < 0 || split+1 > len(text) {
        return "", "", false
    }
    return text[4:split], text[split+1:], true
}

number_literal_type :: proc(text: string) -> string {
    for ch in text {
        if ch == '.' || ch == 'e' || ch == 'E' {
            return "f64"
        }
    }
    return "int"
}

infer_homogeneous_items_type :: proc(e: ^Emitter, items: []CST_Form, what: string) -> (string, Compile_Error, bool) {
    if len(items) == 0 {
        return "", Compile_Error{message = fmt.tprintf("cannot infer type for empty %s literal; add a type context or use an explicit constructor", what)}, false
    }
    first_ty, err_first, ok_first := infer_literal_value_type(e, items[0])
    if !ok_first {
        return "", err_first, false
    }
    for item in items[1:] {
        item_ty, err_item, ok_item := infer_literal_value_type(e, item)
        if !ok_item {
            return "", err_item, false
        }
        if item_ty != first_ty {
            return "", Compile_Error{message = fmt.tprintf("%s literal must be homogeneous; saw both %s and %s", what, first_ty, item_ty), span = item.span}, false
        }
    }
    return first_ty, Compile_Error{}, true
}

infer_literal_value_type :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    #partial switch form.kind {
    case .Number:
        return number_literal_type(form.text), Compile_Error{}, true
    case .String, .Regex:
        return "string", Compile_Error{}, true
    case .Bool:
        return "bool", Compile_Error{}, true
    case .Keyword:
        mark_keyword_type(e)
        return "keyword", Compile_Error{}, true
    case .Symbol:
        if ty, ok := lookup_local_type(e, map_name(form.text)); ok {
            return ty, Compile_Error{}, true
        }
        return "", Compile_Error{message = fmt.tprintf("cannot infer literal type from symbol %s", form.text), span = form.span}, false
    case .Vector:
        if len(form.items) == 0 {
            return "", Compile_Error{message = "cannot infer type for empty vector literal; add a type context or use arr/empty", span = form.span}, false
        }
        elem_ty, err_elem, ok_elem := infer_homogeneous_items_type(e, form.items[:], "vector")
        if !ok_elem {
            return "", err_elem, false
        }
        return fmt.tprintf("[dynamic]%s", elem_ty), Compile_Error{}, true
    case .Brace:
        if len(form.items) == 0 {
            return "", Compile_Error{message = "cannot infer type for empty map literal; add a type context or use map/empty", span = form.span}, false
        }
        if len(form.items)%2 != 0 {
            return "", Compile_Error{message = "map literal expects key/value pairs", span = form.span}, false
        }
        key_ty, err_key, ok_key := infer_literal_value_type(e, form.items[0])
        if !ok_key {
            return "", err_key, false
        }
        value_ty, err_value, ok_value := infer_literal_value_type(e, form.items[1])
        if !ok_value {
            return "", err_value, false
        }
        i := 2
        for i < len(form.items) {
            next_key_ty, err_next_key, ok_next_key := infer_literal_value_type(e, form.items[i])
            if !ok_next_key {
                return "", err_next_key, false
            }
            if next_key_ty != key_ty {
                return "", Compile_Error{message = fmt.tprintf("map literal keys must be homogeneous; saw both %s and %s", key_ty, next_key_ty), span = form.items[i].span}, false
            }
            next_value_ty, err_next_value, ok_next_value := infer_literal_value_type(e, form.items[i+1])
            if !ok_next_value {
                return "", err_next_value, false
            }
            if next_value_ty != value_ty {
                return "", Compile_Error{message = fmt.tprintf("map literal values must be homogeneous; saw both %s and %s", value_ty, next_value_ty), span = form.items[i+1].span}, false
            }
            i += 2
        }
        return fmt.tprintf("map[%s]%s", key_ty, value_ty), Compile_Error{}, true
    case .Set:
        if len(form.items) == 0 {
            return "", Compile_Error{message = "cannot infer type for empty set literal; add a type context or use set/empty", span = form.span}, false
        }
        elem_ty, err_elem, ok_elem := infer_homogeneous_items_type(e, form.items[:], "set")
        if !ok_elem {
            return "", err_elem, false
        }
        return fmt.tprintf("map[%s]struct{{}}", elem_ty), Compile_Error{}, true
    case .List:
        if len(form.items) == 2 && form.items[0].kind == .Symbol && form.items[1].kind == .Brace {
            head_name := map_name(form.items[0].text)
            if _, ok := find_struct_decl(e, head_name); ok {
                return head_name, Compile_Error{}, true
            }
        }
        return "", Compile_Error{message = "cannot infer inline literal type from this expression", span = form.span}, false
    case .Nil:
        return "", Compile_Error{message = "cannot infer literal type from nil", span = form.span}, false
    }
    return "", Compile_Error{message = "unsupported inline literal type inference", span = form.span}, false
}

indexed_symbol_type :: proc(e: ^Emitter, text: string, span: Span) -> (string, bool) {
    open := strings.index(text, "[")
    if open <= 0 {
        return "", false
    }
    rest := text[open+1:]
    close_rel := strings.index(rest, "]")
    if close_rel < 0 {
        return "", false
    }
    close := open + 1 + close_rel
    base_text := text[:open]
    suffix := text[close+1:]

    base_ty, ok_base_ty := obvious_form_type(e, CST_Form{kind = .Symbol, text = base_text, span = span})
    if !ok_base_ty {
        return "", false
    }

    elem_ty: string
    if _, value_ty, ok_map := map_type_parts(base_ty); ok_map {
        elem_ty = value_ty
    } else {
        ok_elem_ty: bool
        elem_ty, ok_elem_ty = collection_element_type(base_ty)
        if !ok_elem_ty {
            return "", false
        }
    }

    if suffix == "" {
        return elem_ty, true
    }
    if len(suffix) > 1 && suffix[0] == '.' {
        fields, ok_fields := split_field_path_text(suffix[1:])
        if ok_fields {
            defer delete(fields)
            field_ty, _, ok_field_ty := struct_field_type_for_update_path(e, elem_ty, fields[:], "field access", span)
            if ok_field_ty {
                return field_ty, true
            }
        }
    }
    return "", false
}

append_proc_generic_candidates :: proc(values: ^[dynamic]string, text: string) {
    params := generic_type_params_in_text(text)
    defer delete(params)
    for param in params {
        append_unique_text(values, param)
    }
}

proc_decl_generic_candidates :: proc(proc_decl: ^Proc_Decl) -> (values: [dynamic]string) {
    for param in proc_decl.params {
        append_proc_generic_candidates(&values, param.ty)
    }
    #partial switch proc_decl.returns.kind {
    case .Single:
        append_proc_generic_candidates(&values, proc_decl.returns.single_ty)
    case .Named:
        for ret in proc_decl.returns.named {
            append_proc_generic_candidates(&values, ret.ty)
        }
    case:
    }
    return values
}

bind_generic_candidate :: proc(names, types: ^[dynamic]string, candidates: []string, expected, actual: string) -> bool {
    name := expected
    if strings.has_prefix(name, "$") {
        name = name[1:]
    }
    if !generic_param_in_slice(candidates, name) {
        return true
    }
    if actual == name || actual == fmt.tprintf("$%s", name) {
        return true
    }
    for existing, idx in names^ {
        if existing == name {
            return types^[idx] == actual
        }
    }
    append(names, name)
    append(types, actual)
    return true
}

proc_type_param_types :: proc(ty: string) -> (types: [dynamic]string, ok: bool) {
    if !strings.has_prefix(ty, "proc(") {
        return types, false
    }
    close := strings.index(ty, ")")
    if close < len("proc(") {
        return types, false
    }
    parts := split_top_level_commas(ty[len("proc("):close])
    defer delete(parts)
    for part in parts {
        trimmed := strings.trim_space(part)
        if trimmed == "" {
            continue
        }
        colon := top_level_colon_index(trimmed)
        if colon >= 0 {
            append(&types, strings.clone(strings.trim_space(trimmed[colon+1:])))
        } else {
            append(&types, strings.clone(trimmed))
        }
    }
    return types, true
}

bind_generic_candidates_from_types :: proc(names, types: ^[dynamic]string, candidates: []string, expected, actual: string) -> bool {
    if !bind_generic_candidate(names, types, candidates, expected, actual) {
        return false
    }

    if strings.has_prefix(expected, "^") && strings.has_prefix(actual, "^") {
        return bind_generic_candidates_from_types(names, types, candidates, expected[1:], actual[1:])
    }

    expected_elem, ok_expected_elem := collection_element_type(expected)
    actual_elem, ok_actual_elem := collection_element_type(actual)
    if ok_expected_elem && ok_actual_elem {
        return bind_generic_candidates_from_types(names, types, candidates, expected_elem, actual_elem)
    }

    if expected_key, expected_value, ok_expected_map := map_type_parts(expected); ok_expected_map {
        if actual_key, actual_value, ok_actual_map := map_type_parts(actual); ok_actual_map {
            return bind_generic_candidates_from_types(names, types, candidates, expected_key, actual_key) &&
                   bind_generic_candidates_from_types(names, types, candidates, expected_value, actual_value)
        }
    }

    expected_params, ok_expected_proc := proc_type_param_types(expected)
    if ok_expected_proc {
        defer delete(expected_params)
        actual_params, ok_actual_proc := proc_type_param_types(actual)
        if ok_actual_proc {
            defer delete(actual_params)
            if len(expected_params) == len(actual_params) {
                for expected_param, idx in expected_params {
                    if !bind_generic_candidates_from_types(names, types, candidates, expected_param, actual_params[idx]) {
                        return false
                    }
                }
            }
        }
        expected_return, ok_expected_return := proc_type_single_return_type(expected)
        actual_return, ok_actual_return := proc_type_single_return_type(actual)
        if ok_expected_return && ok_actual_return {
            return bind_generic_candidates_from_types(names, types, candidates, expected_return, actual_return)
        }
    }

    return true
}

bind_proc_callback_generic_candidates :: proc(e: ^Emitter, names, types: ^[dynamic]string, candidates: []string, expected_ty: string, arg: CST_Form) -> bool {
    if !strings.has_prefix(expected_ty, "proc(") {
        return true
    }

    return_ty, ok_return_ty := proc_type_single_return_type(expected_ty)
    if ok_return_ty {
        if actual_return_ty, ok_actual_return_ty := source_callback_return_item_type(e, arg); ok_actual_return_ty {
            if !bind_generic_candidate(names, types, candidates, return_ty, actual_return_ty) {
                return false
            }
        }
    }

    if arg.kind != .Symbol {
        return true
    }
    actual_name := map_name(arg.text)
    actual_decl, ok_actual_decl := find_proc_decl(e, actual_name)
    if !ok_actual_decl || len(actual_decl.params) == 0 {
        return true
    }
    open := strings.index(expected_ty, "(")
    close := strings.index(expected_ty, ")")
    if open < 0 || close <= open+1 {
        return true
    }
    expected_param_ty := strings.trim_space(expected_ty[open+1:close])
    return bind_generic_candidate(names, types, candidates, expected_param_ty, actual_decl.params[0].ty)
}

proc_decl_obvious_call_return_type :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, args: []CST_Form) -> (string, bool) {
    if proc_decl.returns.kind != .Single {
        return "", false
    }

    names, types, ok_bindings := proc_decl_call_type_bindings(e, proc_decl, args)
    if !ok_bindings {
        return "", false
    }
    defer delete(names)
    defer delete(types)

    return substitute_type_names(proc_decl.returns.single_ty, names[:], types[:]), true
}

overload_obvious_call_return_type :: proc(e: ^Emitter, overload_name: string, args: []CST_Form) -> (string, bool) {
    overload_decl, ok_overload := find_overload_decl(e, overload_name)
    if !ok_overload {
        return "", false
    }
    selected := ""
    for member in overload_decl.overload_members {
        proc_decl, ok_proc := find_proc_decl(e, member)
        if !ok_proc || !proc_accepts_positional_arg_count(proc_decl, len(args)) {
            continue
        }
        return_ty, ok_return_ty := proc_decl_obvious_call_return_type(e, proc_decl, args)
        if !ok_return_ty {
            return "", false
        }
        if selected == "" {
            selected = return_ty
        } else if selected != return_ty {
            delete(return_ty)
            delete(selected)
            return "", false
        } else {
            delete(return_ty)
        }
    }
    return selected, selected != ""
}

proc_decl_call_type_bindings :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, args: []CST_Form) -> (names: [dynamic]string, types: [dynamic]string, ok: bool) {
    candidates := proc_decl_generic_candidates(proc_decl)
    defer delete(candidates)
    if len(candidates) == 0 {
        return names, types, true
    }

    for param, idx in proc_decl.params {
        if idx >= len(args) {
            break
        }
        if !bind_proc_callback_generic_candidates(e, &names, &types, candidates[:], param.ty, args[idx]) {
            return names, types, false
        }
        if actual_ty, ok_actual_ty := obvious_form_type(e, args[idx]); ok_actual_ty {
            if !bind_generic_candidates_from_types(&names, &types, candidates[:], param.ty, actual_ty) {
                return names, types, false
            }
        }
    }

    for candidate in candidates {
        if !generic_param_in_slice(names[:], candidate) &&
           (type_text_mentions_generic_param(proc_decl.returns.single_ty, candidate) || strings.contains(proc_decl.returns.single_ty, candidate)) {
            return names, types, false
        }
    }

    return names, types, true
}

specialize_params :: proc(params: []Param, names, types: []string) -> (out: [dynamic]Param) {
    for param in params {
        specialized := param
        specialized.ty = substitute_type_names(param.ty, names, types)
        append(&out, specialized)
    }
    return out
}

specialize_return_spec :: proc(returns: Return_Spec, names, types: []string) -> Return_Spec {
    specialized := returns
    #partial switch returns.kind {
    case .Single:
        specialized.single_ty = substitute_type_names(returns.single_ty, names, types)
    case .Named:
        named: [dynamic]Named_Return
        for ret in returns.named {
            append(&named, Named_Return{name = ret.name, ty = substitute_type_names(ret.ty, names, types)})
        }
        specialized.named = named
    case:
    }
    return specialized
}

proc_decl_specialized_signature_for_args :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, args: []CST_Form) -> (params: [dynamic]Param, returns: Return_Spec, ok: bool) {
    names, types, ok_bindings := proc_decl_call_type_bindings(e, proc_decl, args)
    if !ok_bindings {
        return params, returns, false
    }
    defer delete(names)
    defer delete(types)
    if len(names) == 0 {
        for param in proc_decl.params {
            append(&params, param)
        }
        return params, proc_decl.returns, true
    }
    return specialize_params(proc_decl.params[:], names[:], types[:]), specialize_return_spec(proc_decl.returns, names[:], types[:]), true
}

obvious_form_type :: proc(e: ^Emitter, form: CST_Form) -> (string, bool) {
    if form.kind == .List && len(form.items) == 3 && is_symbol(form.items[0], "__kvist_index") {
        target_ty, ok_target_ty := obvious_form_type(e, form.items[1])
        if !ok_target_ty {
            return "", false
        }
        if _, value_ty, ok_map := map_type_parts(target_ty); ok_map {
            return value_ty, true
        }
        return collection_element_type(target_ty)
    }
    if target_form, fields, field_span, ok_place := field_path_place_parts(form); ok_place {
        target_ty, ok_target_ty := obvious_form_type(e, target_form)
        if !ok_target_ty {
            return "", false
        }
        ty, _, ok_ty := struct_field_type_for_update_path(e, target_ty, fields[:], "field access", field_span)
        return ty, ok_ty
    }
    if form.kind == .Symbol {
        if ty, ok := known_form_type(e, form); ok {
            return ty, true
        }
        if symbol_is_simple_deref_suffix(form.text) {
            if ty, ok := lookup_local_type(e, map_name(form.text[:len(form.text)-1])); ok && len(ty) > 0 && ty[0] == '^' {
                return ty[1:], true
            }
            return "", false
        }
        if ty, ok := indexed_symbol_type(e, form.text, form.span); ok {
            return ty, true
        }
        if ty, ok := lookup_local_type(e, map_name(form.text)); ok {
            return ty, true
        }
        name := map_name(form.text)
        for decl in e.decls {
            if decl.kind != .Const || decl.const_decl.name != name {
                continue
            }
            if decl.const_decl.has_ty {
                return decl.const_decl.ty, true
            }
            if decl.const_decl.value.kind == .List &&
               len(decl.const_decl.value.items) == 2 &&
               is_symbol(decl.const_decl.value.items[0], "quote") {
                return "Data", true
            }
            // An unannotated static `def` still has the type of its literal
            // initializer. This matters when the symbol appears inside a
            // contextually-Data collection: the value must be lifted rather
            // than emitted as a native value in an Odin []Data literal.
            if ty, _, ok_ty := infer_literal_value_type(e, decl.const_decl.value); ok_ty {
                return ty, true
            }
        }
        return "", false
    }
    if form.kind == .Number || form.kind == .String || form.kind == .Regex || form.kind == .Bool || form.kind == .Keyword {
        if ty, _, ok := infer_literal_value_type(e, form); ok {
            return ty, true
        }
    }
    if form.kind == .List && len(form.items) == 2 && form.items[0].kind == .Symbol && form.items[1].kind == .Brace {
        head_name := map_name(form.items[0].text)
        if _, ok := find_struct_decl(e, head_name); ok {
            return head_name, true
        }
    }
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        // Scalar conversion forms are also type-producing expressions. Keep
        // their obvious type so a surrounding block-expression IIFE can
        // capture the converted local with an explicit parameter type.
        if len(form.items) == 2 {
            conversion_ty := normalize_surface_type_symbol(form.items[0].text)
            if type_text_is_builtin_odin_scalar(conversion_ty) {
                return conversion_ty, true
            }
        }
        if is_symbol(form.items[0], "quote") && len(form.items) == 2 {
            return "Data", true
        }
        if is_symbol(form.items[0], "quasiquote") && len(form.items) == 2 {
            return "Data", true
        }
        if is_symbol(form.items[0], "if") && len(form.items) == 4 {
            then_ty, ok_then_ty := obvious_form_type(e, form.items[2])
            else_ty, ok_else_ty := obvious_form_type(e, form.items[3])
            if ok_then_ty && ok_else_ty && then_ty == else_ty {
                return then_ty, true
            }
        }
        if is_symbol(form.items[0], "let") || form_head_is_do(form) || form_head_is_case(form) || form_head_is_match(form) {
            return obvious_block_expr_type(e, form)
        }
        if strings.has_prefix(form.items[0].text, "data.") || strings.has_prefix(form.items[0].text, "data/") {
            member := form.items[0].text[len("data."):]
            if strings.has_prefix(form.items[0].text, "data/") {
                member = form.items[0].text[len("data/"):]
            }
            switch member {
            case "item-at", "key-at", "value-at", "tagged-value", "retain": return "Data", true
            case "int": return "i64", true
            case "float": return "f64", true
            case "bool", "nil?", "bool?", "int?", "float?", "string?", "symbol?", "keyword?", "list?", "vector?", "map?", "set?", "tagged?": return "bool", true
            case "string", "keyword", "symbol", "text", "tag": return "string", true
            case "count": return "int", true
            case "kind": return "Data_Kind", true
            }
        }
        head_name := map_name(form.items[0].text)
        if proc_ty, ok_proc_ty := lookup_local_type(e, head_name); ok_proc_ty && type_text_is_proc(proc_ty) {
            if return_ty, ok_return_ty := proc_type_single_return_type(proc_ty); ok_return_ty {
                return return_ty, true
            }
        }
        if (head_is_core_assoc(form.items[0].text) ||
            head_is_core_update(form.items[0].text) ||
            head_is_core_dissoc(form.items[0].text)) &&
           len(form.items) >= 2 {
            return shallow_update_return_type(e, form)
        }
        if form_head_is_as_thread(form) {
            return obvious_as_thread_type(e, form)
        }
        if head_name == "odin_slice" && len(form.items) >= 2 {
            source_ty, ok_source_ty := obvious_form_type(e, form.items[1])
            if ok_source_ty {
                if type_text_is_string(source_ty) {
                    return "string", true
                }
                elem_ty, ok_elem_ty := collection_element_type(source_ty)
                if ok_elem_ty {
                    return fmt.tprintf("[]%s", elem_ty), true
                }
            }
        }
        if head_name == "odin_get" && len(form.items) >= 3 {
            if source_ty, ok_source_ty := obvious_form_type(e, form.items[1]); ok_source_ty && source_ty == "Data" {
                return "Data", true
            }
        }
        if form.items[0].text == "into" && len(form.items) >= 4 {
            ty, _, _, ok_ty := parse_type_text_from_forms(form.items[:], 1)
            return ty, ok_ty
        }
        if form.items[0].text == "transduce" && len(form.items) == 5 {
            return obvious_form_type(e, form.items[3])
        }
        if source, ok_source_call := source_call_decl(e, form); ok_source_call {
            if item_ty, _, ok_item_ty := source_call_item_type(e, source, form); ok_item_ty {
                return fmt.tprintf("[dynamic]%s", item_ty), true
            }
            return fmt.tprintf("[dynamic]%s", source.item_ty), true
        }
        if form.items[0].text == "thread-start" {
            spec, _, ok_spec := thread_start_signature(e, form)
            if ok_spec {
                return thread_task_type(spec), true
            }
        }
        if _, proc_decl, ok := resolve_proc_call_decl(e, form.items[0].text); ok && proc_decl != nil {
            return proc_decl_obvious_call_return_type(e, proc_decl, form.items[1:])
        }
        if return_ty, ok_return_ty := overload_obvious_call_return_type(e, head_name, form.items[1:]); ok_return_ty {
            return return_ty, true
        }
    }
    if form.kind == .Vector || form.kind == .Brace || form.kind == .Set {
        if ty, _, ok := infer_literal_value_type(e, form); ok {
            return ty, true
        }
    }
    return "", false
}

emit_set_literal :: proc(e: ^Emitter, elem_type: string, form: CST_Form) -> (string, Compile_Error, bool) {
    values, err_values, ok_values := emit_vector_item_texts(e, form, elem_type)
    if !ok_values {
        return "", err_values, false
    }
    if !has_multiline_items(values[:]) {
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        strings.write_string(&builder, "map[")
        strings.write_string(&builder, elem_type)
        strings.write_string(&builder, "]struct{}{")
        for value, idx in values {
            if idx > 0 {
                strings.write_string(&builder, ", ")
            }
            strings.write_string(&builder, value)
            strings.write_string(&builder, " = {}")
        }
        strings.write_byte(&builder, '}')
        return strings.clone(strings.to_string(builder)), Compile_Error{}, true
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "map[")
    strings.write_string(&builder, elem_type)
    strings.write_string(&builder, "]struct{}{\n")
    for value in values {
        append_indented_multiline(&builder, fmt.tprintf("%s = {{}}", value), "    ", ",")
        strings.write_byte(&builder, '\n')
    }
    strings.write_byte(&builder, '}')
    return strings.clone(strings.to_string(builder)), Compile_Error{}, true
}

emit_inferred_literal :: proc(e: ^Emitter, form: CST_Form, expected_type := "") -> (string, Compile_Error, bool) {
    #partial switch form.kind {
    case .Vector:
        prefix := expected_type
        if prefix == "" {
            elem_ty, err_elem, ok_elem := infer_homogeneous_items_type(e, form.items[:], "vector")
            if !ok_elem {
                return "", err_elem, false
            }
            prefix = fmt.tprintf("[dynamic]%s", elem_ty)
        }
        if type_text_is_dynamic_soa(prefix) {
            return emit_dynamic_soa_vector_literal(e, prefix, form)
        }
        if type_text_is_dynamic_array(prefix) {
            mark_dynamic_literals(e)
        }
        return emit_vector_literal(e, prefix, form)
    case .Brace:
        prefix := expected_type
        if prefix == "" {
            if len(form.items) == 0 {
                return emit_brace_literal(e, "", form)
            }
            inferred, err_inferred, ok_inferred := infer_literal_value_type(e, form)
            if !ok_inferred {
                return "", err_inferred, false
            }
            prefix = inferred
        } else if !type_text_is_map(prefix) {
            return emit_brace_literal(e, prefix, form)
        }
        mark_dynamic_literals(e)
        return emit_brace_literal(e, prefix, form)
    case .Set:
        elem_ty := ""
        if expected_type != "" {
            expected_elem, ok_elem := set_element_type(expected_type)
            if !ok_elem {
                return "", Compile_Error{message = fmt.tprintf("set literal does not match expected type %s", expected_type), span = form.span}, false
            }
            elem_ty = expected_elem
        } else {
            inferred, err_inferred, ok_inferred := infer_literal_value_type(e, form)
            if !ok_inferred {
                return "", err_inferred, false
            }
            inferred_elem, ok_elem := set_element_type(inferred)
            if !ok_elem {
                return "", Compile_Error{message = "internal error inferring set literal type", span = form.span}, false
            }
            elem_ty = inferred_elem
        }
        mark_dynamic_literals(e)
        return emit_set_literal(e, elem_ty, form)
    }
    return "", Compile_Error{message = "internal error: expected literal form", span = form.span}, false
}

emit_typed_literal_value :: proc(e: ^Emitter, type_form: CST_Form, type_text: string, value: CST_Form) -> (string, Compile_Error, bool, bool) {
    #partial switch value.kind {
    case .Vector:
        if type_form_needs_dynamic_literals(type_form) {
            mark_dynamic_literals(e)
        }
        if type_text_is_dynamic_soa(type_text) {
            text, err, ok := emit_dynamic_soa_vector_literal(e, type_text, value)
            return text, err, ok, true
        }
        text, err, ok := emit_vector_literal(e, type_text, value)
        return text, err, ok, true
    case .Brace:
        struct_decl, ok_struct := find_struct_decl(e, type_text)
        if ok_struct {
            err_struct, ok_struct_ctor := validate_struct_constructor(e, struct_decl, value)
            if !ok_struct_ctor {
                return "", err_struct, false, true
            }
            text, err, ok := emit_struct_brace_literal(e, struct_decl, value)
            return text, err, ok, true
        }
        text, err, ok := emit_inferred_literal(e, value, type_text)
        return text, err, ok, true
    case .Set:
        text, err, ok := emit_inferred_literal(e, value, type_text)
        return text, err, ok, true
    }
    return "", Compile_Error{}, false, false
}

push_local_type_scope :: proc(e: ^Emitter) {
    append(&e.local_type_scope_marks, len(e.local_types))
    append(&e.local_struct_scope_marks, len(e.local_structs))
    append(&e.local_union_scope_marks, len(e.local_unions))
    append(&e.callback_context_scope_marks, len(e.callback_contexts))
}

pop_local_type_scope :: proc(e: ^Emitter) {
    if len(e.local_type_scope_marks) == 0 {
        return
    }
    mark := e.local_type_scope_marks[len(e.local_type_scope_marks)-1]
    resize(&e.local_type_scope_marks, len(e.local_type_scope_marks)-1)
    resize(&e.local_types, mark)

    struct_mark := e.local_struct_scope_marks[len(e.local_struct_scope_marks)-1]
    resize(&e.local_struct_scope_marks, len(e.local_struct_scope_marks)-1)
    resize(&e.local_structs, struct_mark)

    union_mark := e.local_union_scope_marks[len(e.local_union_scope_marks)-1]
    resize(&e.local_union_scope_marks, len(e.local_union_scope_marks)-1)
    resize(&e.local_unions, union_mark)

    callback_mark := e.callback_context_scope_marks[len(e.callback_context_scope_marks)-1]
    resize(&e.callback_context_scope_marks, len(e.callback_context_scope_marks)-1)
    resize(&e.callback_contexts, callback_mark)
}

bind_local_type :: proc(e: ^Emitter, name, ty: string) {
    append(&e.local_types, Param{name = name, ty = ty})
}

lookup_local_type :: proc(e: ^Emitter, name: string) -> (string, bool) {
    for i := len(e.local_types) - 1; i >= 0; i -= 1 {
        if e.local_types[i].name == name {
            return e.local_types[i].ty, true
        }
    }
    return "", false
}

bind_callback_context :: proc(e: ^Emitter, name: string, capture_names: []string) {
    ctx := Callback_Context{name = name}
    for capture_name in capture_names {
        append(&ctx.capture_names, capture_name)
    }
    append(&e.callback_contexts, ctx)
}

bind_field_callback_context :: proc(e: ^Emitter, name, field: string) {
    append(&e.callback_contexts, Callback_Context{name = name, field_selector = field})
}

lookup_callback_context :: proc(e: ^Emitter, name: string) -> (^Callback_Context, bool) {
    for i := len(e.callback_contexts) - 1; i >= 0; i -= 1 {
        if e.callback_contexts[i].name == name {
            return &e.callback_contexts[i], true
        }
    }
    return nil, false
}

known_form_type :: proc(e: ^Emitter, form: CST_Form) -> (string, bool) {
    if form.kind == .Symbol {
        name := form.text
        if symbol_is_simple_deref_suffix(name) {
            if ty, ok := lookup_local_type(e, map_name(name[:len(name)-1])); ok && len(ty) > 0 && ty[0] == '^' {
                return ty[1:], true
            }
            return "", false
        }
        dot := strings.index(name, ".")
        if dot > 0 && dot+1 < len(name) {
            base_name := map_name(name[:dot])
            defer delete(base_name)
            if target_ty, ok_target := lookup_local_type(e, base_name); ok_target {
                fields, ok_fields := split_field_path_text(name[dot+1:])
                if ok_fields {
                    defer delete(fields)
                    field_ty, _, ok_field_ty := struct_field_type_for_update_path(e, target_ty, fields[:], "field access", form.span)
                    if ok_field_ty {
                        return field_ty, true
                    }
                }
            }
        }
        return lookup_local_type(e, map_name(name))
    }
    return "", false
}

obvious_binding_type :: proc(e: ^Emitter, binding: Binding) -> (string, bool) {
    if binding.is_destructure || binding.name == "" {
        return "", false
    }
    if binding.is_typed {
        return binding.ty, true
    }
    if binding.value.kind == .Symbol {
        return obvious_form_type(e, binding.value)
    }
    if binding.value.kind == .Number || binding.value.kind == .String || binding.value.kind == .Regex || binding.value.kind == .Bool {
        if ty, _, ok := infer_literal_value_type(e, binding.value); ok {
            return ty, true
        }
    }
    if ty, ok := obvious_form_type(e, binding.value); ok {
        return ty, true
    }
    if binding.value.kind == .List && len(binding.value.items) == 2 && binding.value.items[0].kind == .Symbol && binding.value.items[1].kind == .Brace {
        head_name := map_name(binding.value.items[0].text)
        if _, ok := find_struct_decl(e, head_name); ok {
            return head_name, true
        }
    }
    if binding.value.kind == .List && len(binding.value.items) >= 2 && binding.value.items[0].kind == .Symbol {
        head := binding.value.items[0].text
        if head == "make" {
            type_text, _, ok_type := parse_type_text(binding.value.items[1])
            if ok_type {
                return type_text, true
            }
        }
    }
    if binding.value.kind == .List &&
       len(binding.value.items) == 2 &&
       (binding.value.items[1].kind == .Vector || binding.value.items[1].kind == .Brace || binding.value.items[1].kind == .Set) {
        type_text, _, ok_type := parse_type_text(binding.value.items[0])
        if ok_type {
            return type_text, true
        }
    }
    if binding.value.kind == .List && len(binding.value.items) > 0 && binding.value.items[0].kind == .Symbol {
        head := binding.value.items[0].text
        head_name := map_name(head)
        if (head_is_core_assoc(head) || head_is_core_update(head) || head_is_core_dissoc(head)) &&
           len(binding.value.items) >= 2 {
            return shallow_update_return_type(e, binding.value)
        }
        if form_head_is_as_thread(binding.value) {
            return obvious_as_thread_type(e, binding.value)
        }
        if head == "into" && len(binding.value.items) >= 4 {
            ty, _, _, ok_ty := parse_type_text_from_forms(binding.value.items[:], 1)
            return ty, ok_ty
        }
        if head == "transduce" && len(binding.value.items) == 5 {
            return obvious_form_type(e, binding.value.items[3])
        }
        if head == "thread-start" {
            spec, _, ok_spec := thread_start_signature(e, binding.value)
            if ok_spec {
                return thread_task_type(spec), true
            }
        }
        if proc_decl, ok := find_proc_decl(e, head_name); ok {
            return proc_decl_obvious_call_return_type(e, proc_decl, binding.value.items[1:])
        }
    }
    if binding.value.kind == .Vector || binding.value.kind == .Brace || binding.value.kind == .Set {
        if ty, _, ok := infer_literal_value_type(e, binding.value); ok {
            return ty, true
        }
    }
    return "", false
}

bind_obvious_binding_types :: proc(e: ^Emitter, binding: Binding) {
    if binding_is_data_destructure(e, binding) {
        names: [dynamic]string
        if _, ok_pattern := validate_data_pattern_names(binding.target, &names, true); ok_pattern {
            for name in names {
                bind_local_type(e, name, "Data")
            }
        }
        delete(names)
        return
    }
    if binding.is_destructure || binding.is_result_binding {
        if binding.value.kind == .List && len(binding.value.items) > 0 && binding.value.items[0].kind == .Symbol {
            head_name := map_name(binding.value.items[0].text)
            defer delete(head_name)
            if head_name == "decode_data" && len(binding.pattern) == 3 && len(binding.value.items) >= 2 {
                if target_ty, _, ok_target_ty := parse_type_text(binding.value.items[1]); ok_target_ty {
                    if binding.pattern[0] != "" {
                        bind_local_type(e, binding.pattern[0], target_ty)
                    }
                    if binding.pattern[1] != "" {
                        bind_local_type(e, binding.pattern[1], "data__Decode_Error")
                    }
                    if binding.pattern[2] != "" {
                        bind_local_type(e, binding.pattern[2], "bool")
                    }
                }
                return
            }
            if head_name == "validate_data" && len(binding.pattern) == 2 {
                if binding.pattern[0] != "" {
                    bind_local_type(e, binding.pattern[0], "data__Decode_Error")
                }
                if binding.pattern[1] != "" {
                    bind_local_type(e, binding.pattern[1], "bool")
                }
                return
            }
            if proc_decl, ok := find_proc_decl(e, head_name); ok && proc_decl.returns.kind == .Named && len(proc_decl.returns.named) == len(binding.pattern) {
                for name, idx in binding.pattern {
                    if name != "" {
                        bind_local_type(e, name, proc_decl.returns.named[idx].ty)
                    }
                }
            }
        }
        return
    }
    if ty, ok_ty := obvious_binding_type(e, binding); ok_ty {
        bind_local_type(e, binding.name, ty)
    }
}

binding_value_is_let :: proc(binding: Binding) -> bool {
    return !binding.is_destructure &&
        !binding.is_result_binding &&
        binding.name != "" &&
        binding.value.kind == .List &&
        len(binding.value.items) > 0 &&
        binding.value.items[0].kind == .Symbol &&
        binding.value.items[0].text == "let"
}

emit_let_value_binding_assignment :: proc(e: ^Emitter, binding: Binding) -> (Compile_Error, bool) {
    let_form := binding.value
    if len(let_form.items) < 3 {
        return Compile_Error{message = "let expects bindings and body", span = let_form.span}, false
    }
    inner_bindings, err_bind, ok_bind := parse_let_bindings(let_form.items[1])
    if !ok_bind {
        return err_bind, false
    }
    err_tail, bad_tail := let_errdefer_tail_error(inner_bindings[:], false)
    if bad_tail {
        return err_tail, false
    }
    body := let_form.items[2:]
    if len(body) == 0 {
        return Compile_Error{message = "let expects bindings and body", span = let_form.span}, false
    }

    for inner in inner_bindings {
        if binding_is_data_destructure(e, inner) {
            err_data, ok_data := emit_data_let_binding(e, inner)
            if !ok_data {
                return err_data, false
            }
        } else if binding_value_is_let(inner) {
            err_inner, ok_inner := emit_let_value_binding_assignment(e, inner)
            if !ok_inner {
                return err_inner, false
            }
        } else {
            value: string
            err_value: Compile_Error
            ok_value: bool
            if form_has_nested_owned_value(inner.value, e) {
                value, err_value, ok_value = emit_expr_with_owned_nested_temps(e, inner.value)
            } else {
                err_owned, bad_owned := owned_result_usage_error(inner.value, true, e)
                if bad_owned {
                    return err_owned, false
                }
                value, err_value, ok_value = emit_expr_for_expected_type(e, inner.value, inner.ty)
            }
            if !ok_value {
                return err_value, false
            }
            emit_binding_assignment(e, inner, value)
        }

        err_guard, ok_guard := emit_result_binding_guard(e, inner, Return_Spec{})
        if !ok_guard {
            return err_guard, false
        }
        if inner.deferred_delete {
            err_defer, ok_defer := emit_binding_deferred_delete(e, inner)
            if !ok_defer {
                return err_defer, false
            }
        }
        if inner.defer_with_cleanup {
            err_defer, ok_defer := emit_binding_defer_with_cleanup(e, inner)
            if !ok_defer {
                return err_defer, false
            }
        }
        if inner.err_deferred_delete {
            err_defer, ok_defer := emit_binding_err_deferred_delete(e, inner)
            if !ok_defer {
                return err_defer, false
            }
        }
        if ty, ok_ty := obvious_binding_type(e, inner); ok_ty {
            bind_local_type(e, inner.name, ty)
        }
    }

    if len(body) > 1 {
        err_body, ok_body := emit_body_forms(e, body[:len(body)-1], Return_Spec{})
        if !ok_body {
            return err_body, false
        }
    }
    final_text, err_final, ok_final := emit_expr_for_expected_type(e, body[len(body)-1], binding.ty)
    if !ok_final {
        return err_final, false
    }
    emit_binding_assignment(e, binding, final_text)
    return {}, true
}

emit_result_binding_named_return_assignment :: proc(e: ^Emitter, binding: Binding, value: string) {
    line_builder := strings.builder_make()
    defer strings.builder_destroy(&line_builder)
    for name, idx in binding.pattern {
        if idx > 0 {
            strings.write_string(&line_builder, ", ")
        }
        strings.write_string(&line_builder, binding_output_name(name))
    }
    fmt.sbprintf(&line_builder, " = %s", value)
    emit_prefixed_expr_mapped(e, "", strings.clone(strings.to_string(line_builder)), binding.value.span)
}

form_is_owned_allocation_result :: proc(form: CST_Form) -> bool {
    if form.kind != .List || len(form.items) < 2 || form.items[0].kind != .Symbol {
        return false
    }
    head := form.items[0].text
    if head != "make" {
        return false
    }
    type_text, _, ok_type := parse_type_text(form.items[1])
    if !ok_type {
        return false
    }
    defer delete(type_text)
    return type_text_is_dynamic_array(type_text) || type_text_is_dynamic_soa(type_text) || type_text_is_map(type_text)
}

form_is_owned_constructor_result :: proc(form: CST_Form) -> bool {
    if form.kind == .Vector || form.kind == .Brace || form.kind == .Set {
        return true
    }
    if form.kind != .List || len(form.items) == 0 {
        return false
    }
    if len(form.items) == 2 &&
       (form.items[1].kind == .Vector || form.items[1].kind == .Brace || form.items[1].kind == .Set) {
        type_text, _, ok_type := parse_type_text(form.items[0])
        if ok_type {
            defer delete(type_text)
            return type_text_is_dynamic_array(type_text) || type_text_is_dynamic_soa(type_text) || type_text_is_map(type_text)
        }
    }
    return false
}

form_is_literal_constructor_call :: proc(form: CST_Form) -> bool {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    return false
}

form_is_named_arg_brace :: proc(form: CST_Form) -> bool {
    if form.kind != .Brace || len(form.items)%2 != 0 {
        return false
    }
    for i := 0; i < len(form.items); i += 2 {
        if _, ok_key := brace_key_name(form.items[i]); !ok_key {
            return false
        }
    }
    return true
}

form_produces_owned_value :: proc(form: CST_Form, e: ^Emitter = nil) -> bool {
    return form_is_owned_result(form, e) || form_is_owned_allocation_result(form) || form_is_owned_constructor_result(form)
}

binding_value_produces_owned_value :: proc(binding: Binding, e: ^Emitter = nil) -> bool {
    if binding.is_typed &&
       (binding.value.kind == .Vector || binding.value.kind == .Brace || binding.value.kind == .Set) {
        return type_text_is_owned_result(binding.ty)
    }
    return form_produces_owned_value(binding.value, e)
}

form_is_owned_temp_escape_result :: proc(form: CST_Form, e: ^Emitter = nil) -> bool {
    return form_produces_owned_value(form, e)
}

with_temp_allocator_escape_error :: proc(e: ^Emitter, body: []CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    if err_span, ok := body_escape_owned_temp_result_span_names(e, body, nil, returns); ok {
        return Compile_Error{
            message = "owned value cannot escape with-temp-allocator; allocate it outside the temp scope or copy it before returning",
            span = err_span,
        }, true
    }
    return {}, false
}

loop_collection_needs_temp_binding :: proc(e: ^Emitter, form: CST_Form) -> bool {
    return form_is_owned_result(form, e) || form_is_owned_allocation_result(form) || form_is_owned_constructor_result(form)
}

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

brace_directly_contains_owned_name :: proc(form: CST_Form, name: string) -> bool {
    if form.kind != .Brace || len(form.items)%2 != 0 {
        return false
    }
    for i := 1; i < len(form.items); i += 2 {
        value := form.items[i]
        if value.kind == .Symbol && map_name(value.text) == name {
            return true
        }
    }
    return false
}

composite_literal_transfers_owned_name :: proc(form: CST_Form, name: string) -> bool {
    return form.kind == .List &&
           len(form.items) == 2 &&
           form.items[0].kind == .Symbol &&
           brace_directly_contains_owned_name(form.items[1], name)
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
        if form_is_delete_of_name(form, name) {
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
    if form.kind == .List && len(form.items) == 2 && form.items[1].kind == .Brace {
        return borrowed_escape_owner_name(e, form.items[1], borrowed, live)
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

proc_decl_transfers_param_in_result :: proc(proc_decl: ^Proc_Decl, param_index: int) -> bool {
    if proc_decl == nil ||
       param_index < 0 ||
       param_index >= len(proc_decl.params) ||
       len(proc_decl.body) == 0 {
        return false
    }
    name := map_name(proc_decl.params[param_index].name)
    defer delete(name)
    return form_transfers_owned_name(proc_decl.body[len(proc_decl.body)-1], name, true)
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
    if !ok {
        return false
    }
    return proc_decl_transfers_param_in_result(proc_decl, arg_index-1)
}

mark_transferred_owned_args :: proc(form: CST_Form, live: ^[dynamic]Owned_Local) {
    if !form_transfers_owned_args(form) {
        return
    }
    for item in form.items[2:] {
        if item.kind == .Symbol {
            _ = owned_locals_mark_moved_last(live, map_name(item.text))
        }
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

switch_transfers_owned_name :: proc(form: CST_Form, name: string, can_transfer_final: bool) -> bool {
    if len(form.items) < 4 {
        return false
    }
    i := 2
    any_branch := false
    for i < len(form.items) {
        if i+1 >= len(form.items) {
            return false
        }
        any_branch = true
        if !form_transfers_owned_name(form.items[i+1], name, can_transfer_final) {
            return false
        }
        i += 2
    }
    return any_branch
}

form_transfers_owned_name :: proc(form: CST_Form, name: string, can_transfer_final: bool) -> bool {
    if form_is_delete_of_name(form, name) {
        return true
    }

    head, ok := form_head_symbol_text(form)
    if ok && head == "return" {
        for item in form.items[1:] {
            if item.kind == .Symbol && map_name(item.text) == name {
                return true
            }
            if composite_literal_transfers_owned_name(item, name) {
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
        return body_deletes_or_returns_name(form.items[2:], name, can_transfer_final)
    }

    if ok && head == "do" && len(form.items) >= 2 {
        return body_deletes_or_returns_name(form.items[1:], name, can_transfer_final)
    }

    if ok && head == "if" {
        if len(form.items) < 4 {
            return false
        }
        return form_transfers_owned_name(form.items[2], name, can_transfer_final) &&
            form_transfers_owned_name(form.items[3], name, can_transfer_final)
    }

    if ok && head == "type-case" {
        return switch_transfers_owned_name(form, name, can_transfer_final)
    }

    if ok && head == "match" {
        if len(form.items) < 4 {
            return false
        }
        for i := 3; i < len(form.items); i += 2 {
            if !form_transfers_owned_name(form.items[i], name, can_transfer_final) {
                return false
            }
        }
        return true
    }

    if can_transfer_final && form.kind == .Symbol && map_name(form.text) == name {
        return true
    }

    if can_transfer_final && composite_literal_transfers_owned_name(form, name) {
        return true
    }

    return false
}

body_deletes_or_returns_name :: proc(forms: []CST_Form, name: string, can_transfer_final: bool) -> bool {
    for form, idx in forms {
        if form_transfers_owned_name(form, name, can_transfer_final && idx == len(forms)-1) {
            return true
        }
    }
    return false
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
                if live[i].state == .Live && composite_literal_transfers_owned_name(form, live[i].name) {
                    _ = owned_locals_mark_moved_last(live, live[i].name)
                }
            }
        }

        head, ok := form_head_symbol_text(form)
        if !ok {
            if form_produces_owned_value(form, e) && !(final_in_scope && can_transfer_final) {
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
                    if live[i].state == .Live && composite_literal_transfers_owned_name(item, live[i].name) {
                        _ = owned_locals_mark_moved_last(live, live[i].name)
                    }
                }
                mark_transferred_owned_args(item, live)
            }
        case "discard":
            for item in form.items[1:] {
                if form_produces_owned_value(item, e) {
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
                       composite_literal_transfers_owned_name(binding.value, live[i].name) {
                        _ = owned_locals_mark_moved_last(live, live[i].name)
                    }
                }
                mark_transferred_owned_args(binding.value, live)
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
                if !skip_warning && !body_deletes_or_returns_name(form.items[2:], live[i].name, final_in_scope && can_transfer_final) {
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
            mark_transferred_owned_args(form, live)
            if form_produces_owned_value(form, e) && !(final_in_scope && can_transfer_final) {
                emit_coded_warning(e, discarded_owned_warning_message(form), form.span, .Ownership_Discarded_Result)
            }
        }
    }
}

lint_defer_in_loop_form :: proc(e: ^Emitter, form: CST_Form, in_loop_scope: bool) {
    if form.kind != .List || len(form.items) == 0 {
        for item in form.items {
            lint_defer_in_loop_form(e, item, in_loop_scope)
        }
        return
    }

    head, ok := form_head_symbol_text(form)
    if !ok {
        for item in form.items {
            lint_defer_in_loop_form(e, item, in_loop_scope)
        }
        return
    }

    if head == "defer" && in_loop_scope {
        emit_coded_warning(
            e,
            "defer inside loop runs when the surrounding scope exits, not after each iteration; wrap the iteration body in block or clean up explicitly",
            form.span,
            .Ownership_Defer_In_Loop,
        )
        return
    }

    switch head {
    case "for":
        if len(form.items) > 2 {
            lint_defer_in_loop_body(e, form.items[2:], true)
        }
        return
    case "while":
        if len(form.items) > 2 {
            lint_defer_in_loop_body(e, form.items[2:], true)
        }
        return
    case "block":
        if len(form.items) > 1 {
            lint_defer_in_loop_body(e, form.items[1:], false)
        }
        return
    case "let", "with-allocator", "with-temp-allocator":
        if len(form.items) > 2 {
            lint_defer_in_loop_body(e, form.items[2:], false)
        }
        return
    }

    for item in form.items[1:] {
        lint_defer_in_loop_form(e, item, in_loop_scope)
    }
}

lint_defer_in_loop_body :: proc(e: ^Emitter, forms: []CST_Form, in_loop_scope: bool) {
    for form in forms {
        lint_defer_in_loop_form(e, form, in_loop_scope)
    }
}

emit_for_in_loop_body :: proc(e: ^Emitter, coll_form: CST_Form, coll_text, first_name, second_name: string, body: []CST_Form) -> (Compile_Error, bool) {
    emit_indent(e)
    strings.write_string(&e.builder, "for ")
    strings.write_string(&e.builder, binding_output_name(first_name))
    prefix_len := len("for ") + len(binding_output_name(first_name))
    if second_name != "" {
        strings.write_string(&e.builder, ", ")
        strings.write_string(&e.builder, binding_output_name(second_name))
        prefix_len += len(", ") + len(binding_output_name(second_name))
    }
    strings.write_string(&e.builder, " in ")
    prefix_len += len(" in ")
    strings.write_string(&e.builder, coll_text)
    record_current_line_fragment_map(e, prefix_len, coll_text, coll_form.span)
    strings.write_string(&e.builder, " {")
    emit_raw_newline(e)
    e.indent += 1
    push_local_type_scope(e)
    if coll_ty, ok_coll_ty := obvious_form_type(e, coll_form); ok_coll_ty {
        if key_ty, value_ty, ok_map := map_type_parts(coll_ty); ok_map {
            if second_name == "" {
                bind_local_type(e, first_name, value_ty)
            } else {
                bind_local_type(e, first_name, key_ty)
                bind_local_type(e, second_name, value_ty)
            }
        } else if item_ty, ok_item_ty := collection_element_type(coll_ty); ok_item_ty {
            if second_name == "" {
                bind_local_type(e, first_name, item_ty)
            } else {
                bind_local_type(e, first_name, "int")
                bind_local_type(e, second_name, item_ty)
            }
        }
    }
    err_body, ok_body := emit_body_forms(e, body, Return_Spec{kind = .None})
    pop_local_type_scope(e)
    if !ok_body {
        return err_body, false
    }
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

emit_for_in_loop :: proc(e: ^Emitter, coll_form: CST_Form, first_name, second_name: string, body: []CST_Form) -> (Compile_Error, bool) {
    if !loop_collection_needs_temp_binding(e, coll_form) {
        err_owned, bad_owned := owned_result_usage_error(coll_form, false, e)
        if bad_owned {
            return err_owned, false
        }
        coll, err_coll, ok_coll := emit_expr(e, coll_form)
        if !ok_coll {
            return err_coll, false
        }
        return emit_for_in_loop_body(e, coll_form, coll, first_name, second_name, body)
    }

    coll, err_coll, ok_coll := emit_expr(e, coll_form)
    if !ok_coll {
        return err_coll, false
    }
    e.temp_counter += 1
    temp := fmt.tprintf("kvist_loop_%d", e.temp_counter)
    emit_line(e, "{")
    e.indent += 1
    push_local_type_scope(e)
    emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), coll, coll_form.span)
    emit_line(e, fmt.tprintf("defer delete(%s)", temp))
    err_loop, ok_loop := emit_for_in_loop_body(e, coll_form, temp, first_name, second_name, body)
    pop_local_type_scope(e)
    if !ok_loop {
        return err_loop, false
    }
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

emit_for_data_pattern_body :: proc(e: ^Emitter, pattern: CST_Form, item_name: string, body: []CST_Form, index_name: string = "") -> (Compile_Error, bool) {
    emit_line(e, "{")
    e.indent += 1
    push_local_type_scope(e)
    if index_name != "" {
        bind_local_type(e, index_name, "int")
    }
    err_bind, ok_bind := emit_data_pattern_bindings(e, pattern, item_name)
    if !ok_bind {
        pop_local_type_scope(e)
        return err_bind, false
    }
    err_body, ok_body := emit_body_forms(e, body, Return_Spec{kind = .None})
    pop_local_type_scope(e)
    if !ok_body {
        return err_body, false
    }
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

emit_for_data_pattern_loop :: proc(e: ^Emitter, pattern, coll_form: CST_Form, body: []CST_Form, index_name: string = "") -> (Compile_Error, bool) {
    names: [dynamic]string
    defer delete(names)
    err_pattern, ok_pattern := validate_data_pattern_names(pattern, &names, true)
    if !ok_pattern {
        return err_pattern, false
    }
    coll_ty, ok_coll_ty := obvious_form_type(e, coll_form)
    literal_data_source := coll_form.kind == .Vector || coll_form.kind == .Set
    if literal_data_source {
        coll_ty = "Data"
        ok_coll_ty = true
    }
    if !ok_coll_ty {
        return Compile_Error{message = "Data destructuring for requires a statically known Data collection or native collection of Data", span = coll_form.span}, false
    }
    is_data_source := coll_ty == "Data"
    if !is_data_source {
        if !type_text_is_slice_or_fixed_array(coll_ty) && !type_text_is_dynamic_array(coll_ty) {
            return Compile_Error{message = "Data destructuring for supports native arrays, slices, and dynamic arrays", span = coll_form.span}, false
        }
        item_ty, ok_item_ty := collection_element_type(coll_ty)
        if !ok_item_ty || item_ty != "Data" {
            return Compile_Error{message = "Data destructuring for expects Data elements", span = coll_form.span}, false
        }
    }
    value, err_value, ok_value := emit_expr_for_expected_type(e, coll_form, coll_ty)
    if !ok_value {
        return err_value, false
    }
    mark_data_type(e)
    emit_line(e, "{")
    e.indent += 1
    push_local_type_scope(e)
    collection := thread_temp_name(e)
    if is_data_source {
        emit_owned_data_local(e, collection, value, coll_form.span, form_produces_owned_managed_type(e, coll_form, "Data"))
        emit_line_mapped(e, fmt.tprintf(
            "assert(%s.kind == .Nil || %s.kind == .List || %s.kind == .Vector || %s.kind == .Set, \"Data for source must be nil, list, vector, or set\")",
            collection,
            collection,
            collection,
            collection,
        ), coll_form.span)
        emit_line(e, fmt.tprintf("if %s.kind != .Nil {{", collection))
        e.indent += 1
        item_name := thread_temp_name(e)
        loop_names := item_name
        if index_name != "" {
            loop_names = fmt.tprintf("%s, %s", item_name, index_name)
        }
        emit_line(e, fmt.tprintf("for %s in %s.payload.items {{", loop_names, collection))
        e.indent += 1
        err_body, ok_body := emit_for_data_pattern_body(e, pattern, item_name, body, index_name)
        if !ok_body {
            pop_local_type_scope(e)
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        e.indent -= 1
        emit_line(e, "}")
    } else {
        emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", collection), value, coll_form.span)
        if loop_collection_needs_temp_binding(e, coll_form) {
            emit_line(e, fmt.tprintf("defer delete(%s)", collection))
        }
        item_name := thread_temp_name(e)
        loop_names := item_name
        if index_name != "" {
            loop_names = fmt.tprintf("%s, %s", item_name, index_name)
        }
        emit_line(e, fmt.tprintf("for %s in %s {{", loop_names, collection))
        e.indent += 1
        err_body, ok_body := emit_for_data_pattern_body(e, pattern, item_name, body, index_name)
        if !ok_body {
            pop_local_type_scope(e)
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
    }
    pop_local_type_scope(e)
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

emit_source_each_loop :: proc(e: ^Emitter, source_form: CST_Form, source: ^Source_Decl, value_name, index_name: string, body: []CST_Form) -> (Compile_Error, bool) {
    state_ty, err_state_ty, ok_state_ty := source_state_type(e, source)
    if !ok_state_ty {
        return err_state_ty, false
    }
    err_protocol, ok_protocol := validate_source_protocol(e, source, state_ty, source_form.span)
    if !ok_protocol {
        return err_protocol, false
    }
    arg_texts, err_args, ok_args := source_call_arg_texts(e, source, source_form)
    if !ok_args {
        return err_args, false
    }
    item_ty, err_item_ty, ok_item_ty := source_call_item_type(e, source, source_form)
    if !ok_item_ty {
        return err_item_ty, false
    }
    source_text := source_call_text(e, source, arg_texts[:])
    temp := source_temp_name(e)
    ok_name := source_ok_name(e)
    source_index := ""
    if index_name != "" {
        source_index = loop_temp_name(e, "source_index")
    }

    emit_line(e, "{")
    e.indent += 1
    push_local_type_scope(e)
    emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), source_text, source_form.span)
    if source.has_dispose {
        emit_line(e, fmt.tprintf("defer %s(&%s)", source.dispose_name, temp))
    }
    if source_index != "" {
        emit_line(e, fmt.tprintf("%s := 0", source_index))
    }
    emit_line(e, "for {")
    e.indent += 1
    emit_line(e, fmt.tprintf("%s, %s := %s(&%s)", binding_output_name(value_name), ok_name, source.next_name, temp))
    emit_line(e, fmt.tprintf("if !%s %s", ok_name, "{"))
    e.indent += 1
    emit_line(e, "break")
    e.indent -= 1
    emit_line(e, "}")
    push_local_type_scope(e)
    if source_index != "" {
        emit_loop_binding_assignment(e, index_name, source_index)
    }
    if !is_discard_binding_name(value_name) {
        bind_local_type(e, value_name, item_ty)
    }
    if !is_discard_binding_name(index_name) {
        bind_local_type(e, index_name, "int")
    }
    err_body, ok_body := emit_body_forms(e, body, Return_Spec{kind = .None})
    pop_local_type_scope(e)
    if !ok_body {
        return err_body, false
    }
    if source_index != "" {
        emit_line(e, fmt.tprintf("%s += 1", source_index))
    }
    e.indent -= 1
    emit_line(e, "}")
    pop_local_type_scope(e)
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

emit_transform_for_body :: proc(e: ^Emitter, steps: []Transform_Step, initial_text, initial_ty, index_name, value_name, key_name, key_ty: string, body: []CST_Form) -> (Compile_Error, bool) {
    base_indent := e.indent
    value_text, value_ty, close_count, err_pipeline, ok_pipeline := emit_transform_pipeline_body(e, &e.builder, steps, initial_text, initial_ty, base_indent)
    if !ok_pipeline {
        return err_pipeline, false
    }

    e.indent = base_indent + close_count
    emit_loop_binding_assignment(e, value_name, value_text)
    push_local_type_scope(e)
    if !is_discard_binding_name(index_name) {
        bind_local_type(e, index_name, "int")
    }
    if !is_discard_binding_name(key_name) {
        bind_local_type(e, key_name, key_ty)
    }
    if !is_discard_binding_name(value_name) {
        bind_local_type(e, value_name, value_ty)
    }
    err_body, ok_body := emit_body_forms(e, body, Return_Spec{kind = .None})
    pop_local_type_scope(e)
    e.indent = base_indent
    if !ok_body {
        return err_body, false
    }
    if !is_discard_binding_name(index_name) {
        e.indent = base_indent + close_count
        emit_line(e, fmt.tprintf("%s += 1", index_name))
        e.indent = base_indent
    }
    emit_transform_closers(&e.builder, base_indent+close_count, close_count)
    return {}, true
}

emit_transform_for_collection_loop_body :: proc(e: ^Emitter, coll_form: CST_Form, coll_text, coll_ty, index_name, value_name: string, transform_form: CST_Form, body: []CST_Form) -> (Compile_Error, bool) {
    source_elem_ty, ok_source_elem_ty := transform_source_value_type(coll_ty)
    if !ok_source_elem_ty {
        return Compile_Error{message = fmt.tprintf("for :transform expects slice, array, or map source, got %s", coll_ty), span = coll_form.span}, false
    }
    key_name := ""
    key_ty := ""
    loop_index_name := index_name
    if map_key_ty, _, ok_map := map_type_parts(coll_ty); ok_map {
        key_ty = map_key_ty
        key_name = index_name
        loop_index_name = ""
    }
    steps, err_steps, ok_steps := parse_transform_steps(e, transform_form)
    if !ok_steps {
        return err_steps, false
    }
    err_prelude, ok_prelude := emit_transform_state_prelude(e, &e.builder, steps[:], e.indent)
    if !ok_prelude {
        return err_prelude, false
    }
    if !is_discard_binding_name(loop_index_name) {
        emit_line(e, fmt.tprintf("%s := 0", loop_index_name))
    }
    emit_line(e, transform_source_loop_header(coll_ty, coll_text, key_name))
    e.indent += 1
    err_body, ok_body := emit_transform_for_body(e, steps[:], "kvist_item", source_elem_ty, loop_index_name, value_name, key_name, key_ty, body)
    e.indent -= 1
    if !ok_body {
        return err_body, false
    }
    emit_line(e, "}")
    return {}, true
}

emit_transform_for_collection_loop :: proc(e: ^Emitter, coll_form: CST_Form, index_name, value_name: string, transform_form: CST_Form, body: []CST_Form) -> (Compile_Error, bool) {
    if form_is_transform_loop_call(coll_form) {
        spec, err_spec, ok_spec := transform_loop_source(e, coll_form)
        if !ok_spec {
            return err_spec, false
        }
        steps, err_steps, ok_steps := parse_transform_steps(e, transform_form)
        if !ok_steps {
            return err_steps, false
        }
        err_prelude, ok_prelude := emit_transform_state_prelude(e, &e.builder, steps[:], e.indent)
        if !ok_prelude {
            return err_prelude, false
        }
        if !is_discard_binding_name(index_name) {
            emit_line(e, fmt.tprintf("%s := 0", index_name))
        }
        emit_line(e, fmt.tprintf("for %s, %s in %s %s", spec.key_name, spec.value_name, spec.source_text, "{"))
        e.indent += 1
        emit_line(e, fmt.tprintf("kvist_item := %s", spec.item_text))
        err_body, ok_body := emit_transform_for_body(e, steps[:], "kvist_item", spec.item_ty, index_name, value_name, "", "", body)
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    }
    coll_ty, ok_coll_ty := obvious_form_type(e, coll_form)
    if !ok_coll_ty {
        return Compile_Error{message = "for :transform expects a collection with an obvious type; bind or annotate it first", span = coll_form.span}, false
    }
    if !loop_collection_needs_temp_binding(e, coll_form) {
        err_owned, bad_owned := owned_result_usage_error(coll_form, false, e)
        if bad_owned {
            return err_owned, false
        }
        coll, err_coll, ok_coll := emit_expr(e, coll_form)
        if !ok_coll {
            return err_coll, false
        }
        return emit_transform_for_collection_loop_body(e, coll_form, coll, coll_ty, index_name, value_name, transform_form, body)
    }

    coll, err_coll, ok_coll := emit_expr(e, coll_form)
    if !ok_coll {
        return err_coll, false
    }
    e.temp_counter += 1
    temp := fmt.tprintf("kvist_loop_%d", e.temp_counter)
    emit_line(e, "{")
    e.indent += 1
    push_local_type_scope(e)
    emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), coll, coll_form.span)
    emit_line(e, fmt.tprintf("defer delete(%s)", temp))
    err_loop, ok_loop := emit_transform_for_collection_loop_body(e, coll_form, temp, coll_ty, index_name, value_name, transform_form, body)
    pop_local_type_scope(e)
    if !ok_loop {
        return err_loop, false
    }
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

emit_transform_for_source_loop :: proc(e: ^Emitter, source_form: CST_Form, source: ^Source_Decl, index_name, value_name: string, transform_form: CST_Form, body: []CST_Form) -> (Compile_Error, bool) {
    state_ty, err_state_ty, ok_state_ty := source_state_type(e, source)
    if !ok_state_ty {
        return err_state_ty, false
    }
    err_protocol, ok_protocol := validate_source_protocol(e, source, state_ty, source_form.span)
    if !ok_protocol {
        return err_protocol, false
    }
    arg_texts, err_args, ok_args := source_call_arg_texts(e, source, source_form)
    if !ok_args {
        return err_args, false
    }
    item_ty, err_item_ty, ok_item_ty := source_call_item_type(e, source, source_form)
    if !ok_item_ty {
        return err_item_ty, false
    }
    steps, err_steps, ok_steps := parse_transform_steps(e, transform_form)
    if !ok_steps {
        return err_steps, false
    }
    source_text := source_call_text(e, source, arg_texts[:])
    temp := source_temp_name(e)
    ok_name := source_ok_name(e)

    emit_line(e, "{")
    e.indent += 1
    push_local_type_scope(e)
    emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), source_text, source_form.span)
    if source.has_dispose {
        emit_line(e, fmt.tprintf("defer %s(&%s)", source.dispose_name, temp))
    }
    err_prelude, ok_prelude := emit_transform_state_prelude(e, &e.builder, steps[:], e.indent)
    if !ok_prelude {
        return err_prelude, false
    }
    if !is_discard_binding_name(index_name) {
        emit_line(e, fmt.tprintf("%s := 0", index_name))
    }
    emit_line(e, "for {")
    e.indent += 1
    emit_line(e, fmt.tprintf("kvist_item, %s := %s(&%s)", ok_name, source.next_name, temp))
    emit_line(e, fmt.tprintf("if !%s %s", ok_name, "{"))
    e.indent += 1
    emit_line(e, "break")
    e.indent -= 1
    emit_line(e, "}")
    err_body, ok_body := emit_transform_for_body(e, steps[:], "kvist_item", item_ty, index_name, value_name, "", "", body)
    e.indent -= 1
    if !ok_body {
        return err_body, false
    }
    emit_line(e, "}")
    pop_local_type_scope(e)
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

is_plain_identifier_text :: proc(text: string) -> bool {
    if len(text) == 0 {
        return false
    }
    for ch, idx in text {
        alpha := (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
        digit := ch >= '0' && ch <= '9'
        if !(alpha || digit || ch == '_') {
            return false
        }
        if idx == 0 && digit {
            return false
        }
    }
    return true
}

emit_proc_literal_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) < 2 || !is_symbol(form.items[0], "fn") || form.items[1].kind != .Vector {
        return "", Compile_Error{message = "invalid function literal", span = form.span}, false
    }

    parsed, err_parse, ok_parse := parse_proc_literal_form(form)
    if !ok_parse {
        return "", err_parse, false
    }
    return emit_proc_literal_text(e, parsed.params[:], parsed.returns, parsed.body[:])
}

Proc_Literal :: struct {
    params:  [dynamic]Param,
    returns: Return_Spec,
    body:    [dynamic]CST_Form,
}

parse_proc_literal_form :: proc(form: CST_Form) -> (Proc_Literal, Compile_Error, bool) {
    if len(form.items) < 2 || !is_symbol(form.items[0], "fn") || form.items[1].kind != .Vector {
        return Proc_Literal{}, Compile_Error{message = "invalid function literal", span = form.span}, false
    }

    params, err_params, ok_params := parse_param_vector(form.items[1])
    if !ok_params {
        return Proc_Literal{}, err_params, false
    }

    body_index := 2
    returns := Return_Spec{kind = .None}
    if body_index < len(form.items) && is_symbol(form.items[body_index], "->") {
        if body_index+1 >= len(form.items) {
            return Proc_Literal{}, Compile_Error{message = "missing function literal return spec", span = form.items[body_index].span}, false
        }
        return_form := form.items[body_index+1]
        #partial switch return_form.kind {
        case .Vector:
            if vector_is_named_returns(return_form) {
                named, err_named, ok_named := parse_named_returns(return_form)
                if !ok_named {
                    return Proc_Literal{}, err_named, false
                }
                returns.kind = .Named
                returns.named = named
                body_index += 2
            } else {
                return_text, next_index, err_return, ok_return := parse_type_text_from_forms(form.items[:], body_index+1)
                if !ok_return {
                    return Proc_Literal{}, err_return, false
                }
                returns.kind = .Single
                returns.single_ty = return_text
                body_index = next_index
            }
        case .Symbol, .List, .Keyword:
            return_text, next_index, err_return, ok_return := parse_type_text_from_forms(form.items[:], body_index+1)
            if !ok_return {
                return Proc_Literal{}, err_return, false
            }
            returns.kind = .Single
            returns.single_ty = return_text
            body_index = next_index
        case:
            return Proc_Literal{}, Compile_Error{message = "unsupported function literal return spec", span = return_form.span}, false
        }
    }
    if body_index >= len(form.items) {
        return Proc_Literal{}, Compile_Error{message = "function literal body is empty", span = form.span}, false
    }

    body: [dynamic]CST_Form
    for item in form.items[body_index:] {
        append(&body, item)
    }
    return Proc_Literal{
        params  = params,
        returns = returns,
        body    = body,
    }, Compile_Error{}, true
}

emit_proc_literal_text :: proc(e: ^Emitter, params: []Param, returns: Return_Spec, body: []CST_Form) -> (string, Compile_Error, bool) {
    for param in params {
        mark_keyword_type_for_text(e, param.ty)
    }
    mark_keyword_type_for_return_spec(e, returns)
    sub := Emitter{
        builder     = strings.builder_make(),
        indent      = 1,
        decls       = e.decls,
        structs     = e.structs,
        unions      = e.unions,
        local_structs = e.local_structs,
        local_unions  = e.local_unions,
        features    = e.features,
        source_map  = e.source_map,
        warnings    = e.warnings,
        line        = e.line,
        temp_counter = e.temp_counter,
        captured_proc_specializations = e.captured_proc_specializations,
        current_proc_returns = returns,
    }
    defer strings.builder_destroy(&sub.builder)

    for local in e.local_types {
        bind_local_type(&sub, local.name, local.ty)
    }
    for param in params {
        bind_local_type(&sub, param.name, param.ty)
    }

    strings.write_string(&sub.builder, "proc(")
    for param, idx in params {
        if idx > 0 {
            strings.write_string(&sub.builder, ", ")
        }
        fmt.sbprintf(&sub.builder, "%s: %s", param.name, param.ty)
    }
    strings.write_byte(&sub.builder, ')')
    emit_return_spec(&sub, returns)
    strings.write_string(&sub.builder, " {\n")
    err_body, ok_body := emit_body_forms(&sub, body, returns)
    if !ok_body {
        return "", err_body, false
    }
    strings.write_string(&sub.builder, "}")
    return strings.clone(strings.to_string(sub.builder)), {}, true
}

name_in_list :: proc(names: []string, name: string) -> bool {
    for existing in names {
        if existing == name {
            return true
        }
    }
    return false
}

append_capture_param_unique :: proc(captures: ^[dynamic]Param, capture: Param) {
    for existing in captures^ {
        if existing.name == capture.name {
            return
        }
    }
    append(captures, capture)
}

collect_proc_literal_captures :: proc(e: ^Emitter, body: []CST_Form, param_names: []string) -> (captures: [dynamic]Param) {
    for form in body {
        collect_proc_literal_captures_from_form(e, form, param_names, &captures)
    }
    return captures
}

collect_proc_literal_captures_from_form :: proc(e: ^Emitter, form: CST_Form, bound_names: []string, captures: ^[dynamic]Param) {
    #partial switch form.kind {
    case .Symbol:
        name := map_name(form.text)
        if name_in_list(bound_names, name) {
            return
        }
        if ty, ok := lookup_local_type(e, name); ok {
            append_capture_param_unique(captures, Param{name = name, ty = ty})
            return
        }
        // Field selectors are represented as one symbol. Capture the typed
        // local at the selector root so block expressions can read fields of
        // parameters and locals inside their generated proc literal.
        if dot := strings.index(name, "."); dot > 0 {
            root := name[:dot]
            if !name_in_list(bound_names, root) {
                if ty, ok := lookup_local_type(e, root); ok {
                    append_capture_param_unique(captures, Param{name = root, ty = ty})
                }
            }
        }
    case .List:
        if len(form.items) > 0 && is_symbol(form.items[0], "fn") {
            return
        }
        if len(form.items) >= 4 && is_symbol(form.items[0], "match") {
            collect_proc_literal_captures_from_form(e, form.items[1], bound_names, captures)
            for i := 2; i+1 < len(form.items); i += 2 {
                names: [dynamic]string
                if _, ok_pattern := validate_match_pattern(form.items[i], &names); !ok_pattern {
                    delete(names)
                    continue
                }
                arm_bound: [dynamic]string
                for name in bound_names {
                    append(&arm_bound, name)
                }
                for name in names {
                    append(&arm_bound, name)
                }
                collect_proc_literal_captures_from_form(e, form.items[i+1], arm_bound[:], captures)
                delete(arm_bound)
                delete(names)
            }
            return
        }
        if len(form.items) > 1 && is_symbol(form.items[0], "let") {
            bindings, _, ok_bindings := parse_let_bindings(form.items[1])
            names: [dynamic]string
            for name in bound_names {
                append(&names, name)
            }
            for binding in bindings {
                collect_proc_literal_captures_from_form(e, binding.value, names[:], captures)
                if binding.name != "" {
                    append(&names, binding.name)
                } else if binding.target.kind == .Vector || binding.target.kind == .Brace {
                    pattern_names: [dynamic]string
                    if _, ok_pattern := validate_data_pattern_names(binding.target, &pattern_names, true); ok_pattern {
                        for pattern_name in pattern_names {
                            append(&names, pattern_name)
                        }
                    }
                    delete(pattern_names)
                }
            }
            for item in form.items[2:] {
                collect_proc_literal_captures_from_form(e, item, names[:], captures)
            }
            return
        }
        for item in form.items {
            collect_proc_literal_captures_from_form(e, item, bound_names, captures)
        }
    case .Vector, .Brace, .Set:
        for item in form.items {
            collect_proc_literal_captures_from_form(e, item, bound_names, captures)
        }
    case:
    }
}

Captured_Callback_Kind :: enum {
    Value,
    Predicate,
    Keep,
}

captured_unary_callback_proc :: proc(e: ^Emitter, callback: CST_Form, helper_name: string, kind: Captured_Callback_Kind) -> (proc_text: string, capture_names: [dynamic]string, captured: bool, err: Compile_Error, ok: bool) {
    if callback.kind != .List || len(callback.items) == 0 || !is_symbol(callback.items[0], "fn") {
        return "", capture_names, false, Compile_Error{}, true
    }
    parsed, err_parse, ok_parse := parse_proc_literal_form(callback)
    if !ok_parse {
        return "", capture_names, false, err_parse, false
    }
    if len(parsed.params) != 1 {
        return "", capture_names, false, Compile_Error{message = fmt.tprintf("capturing %s callback currently expects exactly one parameter", helper_name), span = callback.span}, false
    }
    switch kind {
    case .Value:
        if parsed.returns.kind != .Single {
            return "", capture_names, false, Compile_Error{message = fmt.tprintf("capturing %s callback currently requires an explicit single return type", helper_name), span = callback.span}, false
        }
    case .Predicate:
        if parsed.returns.kind != .Single || parsed.returns.single_ty != "bool" {
            return "", capture_names, false, Compile_Error{message = fmt.tprintf("capturing %s callback currently requires an explicit bool return type", helper_name), span = callback.span}, false
        }
    case .Keep:
        if parsed.returns.kind != .Named || len(parsed.returns.named) != 2 || parsed.returns.named[1].ty != "bool" {
            return "", capture_names, false, Compile_Error{message = fmt.tprintf("capturing %s callback currently requires explicit named returns [value: T, ok: bool]", helper_name), span = callback.span}, false
        }
    }
    param_names := []string{parsed.params[0].name}
    captures := collect_proc_literal_captures(e, parsed.body[:], param_names)
    if len(captures) == 0 {
        return "", capture_names, false, Compile_Error{}, true
    }
    params: [dynamic]Param
    for capture in captures {
        append(&params, capture)
        append(&capture_names, capture.name)
    }
    append(&params, parsed.params[0])
    proc_text_value, err_proc, ok_proc := emit_proc_literal_text(e, params[:], parsed.returns, parsed.body[:])
    if !ok_proc {
        return "", capture_names, false, err_proc, false
    }
    return proc_text_value, capture_names, true, Compile_Error{}, true
}

return_spec_text :: proc(returns: Return_Spec) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    switch returns.kind {
    case .None:
    case .Single:
        fmt.sbprintf(&builder, " -> %s", returns.single_ty)
    case .Named:
        strings.write_string(&builder, " -> (")
        for field, idx in returns.named {
            if idx > 0 {
                strings.write_string(&builder, ", ")
            }
            fmt.sbprintf(&builder, "%s: %s", field.name, field.ty)
        }
        strings.write_byte(&builder, ')')
    }
    return strings.clone(strings.to_string(builder))
}

proc_type_with_capture_params_text :: proc(capture_count: int, params: []Param, returns: Return_Spec) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "proc(")
    for idx in 0..<capture_count {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "c%d: $C%d", idx+1, idx+1)
    }
    for param, idx in params {
        if capture_count > 0 || idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "%s: %s", param.name, param.ty)
    }
    strings.write_byte(&builder, ')')
    ret := return_spec_text(returns)
    defer delete(ret)
    strings.write_string(&builder, ret)
    return strings.clone(strings.to_string(builder))
}

proc_type_insert_capture_params_text :: proc(proc_ty: string, capture_count: int) -> (string, bool) {
    if !strings.has_prefix(proc_ty, "proc(") {
        return "", false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "proc(")
    for idx in 0..<capture_count {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "c%d: $C%d", idx+1, idx+1)
    }
    rest := proc_ty[len("proc("):]
    if capture_count > 0 && len(rest) > 0 && rest[0] != ')' {
        strings.write_string(&builder, ", ")
    }
    strings.write_string(&builder, rest)
    return strings.clone(strings.to_string(builder)), true
}

captured_proc_literal_for_param :: proc(e: ^Emitter, callback: CST_Form) -> (proc_text: string, capture_names: [dynamic]string, parsed: Proc_Literal, captured: bool, err: Compile_Error, ok: bool) {
    if callback.kind != .List || len(callback.items) == 0 || !is_symbol(callback.items[0], "fn") {
        return "", capture_names, parsed, false, Compile_Error{}, true
    }
    parsed_value, err_parse, ok_parse := parse_proc_literal_form(callback)
    if !ok_parse {
        return "", capture_names, parsed, false, err_parse, false
    }
    parsed = parsed_value
    param_names: [dynamic]string
    for param in parsed.params {
        append(&param_names, param.name)
    }
    captures := collect_proc_literal_captures(e, parsed.body[:], param_names[:])
    if len(captures) == 0 {
        return "", capture_names, parsed, false, Compile_Error{}, true
    }

    params: [dynamic]Param
    for capture in captures {
        append(&params, capture)
        append(&capture_names, capture.name)
    }
    for param in parsed.params {
        append(&params, param)
    }
    proc_text_value, err_proc, ok_proc := emit_proc_literal_text(e, params[:], parsed.returns, parsed.body[:])
    if !ok_proc {
        return "", capture_names, parsed, false, err_proc, false
    }
    return proc_text_value, capture_names, parsed, true, Compile_Error{}, true
}

type_text_is_proc :: proc(ty: string) -> bool {
    return strings.has_prefix(ty, "proc(")
}

worker_arg_callback_is_non_escaping :: proc(e: ^Emitter, worker_decl: ^Proc_Decl, worker_args: []CST_Form, callback_name: string, arg_idx, depth: int) -> bool {
    if worker_decl == nil || arg_idx < 0 || arg_idx >= len(worker_decl.params) || arg_idx >= len(worker_args) {
        return false
    }
    arg := worker_args[arg_idx]
    if arg.kind != .Symbol {
        return false
    }
    arg_name := map_name(arg.text)
    defer delete(arg_name)
    if arg_name != callback_name {
        return false
    }
    if !type_text_is_proc(worker_decl.params[arg_idx].ty) {
        return false
    }
    return proc_callback_param_non_escaping_depth(e, worker_decl, arg_idx, depth+1)
}

thread_launch_callback_arg_is_non_escaping :: proc(e: ^Emitter, form: CST_Form, callback_name: string, worker_index, args_start, arg_idx, depth: int) -> bool {
    if worker_index >= len(form.items) || args_start > len(form.items) {
        return false
    }
    worker_form := form.items[worker_index]
    if worker_form.kind != .Symbol {
        return false
    }
    _, worker_decl, ok_worker := resolve_proc_call_decl(e, worker_form.text)
    if !ok_worker {
        return false
    }
    return worker_arg_callback_is_non_escaping(e, worker_decl, form.items[args_start:], callback_name, arg_idx, depth)
}

callback_symbol_escapes_form :: proc(e: ^Emitter, callback_name: string, form: CST_Form, depth: int) -> bool {
    #partial switch form.kind {
    case .Symbol:
        return map_name(form.text) == callback_name
    case .List:
        if len(form.items) == 0 {
            return false
        }
        if form.items[0].kind == .Symbol {
            head := form.items[0].text
            head_name := map_name(head)
            if head_name == callback_name {
                for arg in form.items[1:] {
                    if callback_symbol_escapes_form(e, callback_name, arg, depth) {
                        return true
                    }
                }
                return false
            }
            if head == "thread-start" && len(form.items) >= 3 {
                for item, idx in form.items[3:] {
                    if thread_launch_callback_arg_is_non_escaping(e, form, callback_name, 2, 3, idx, depth) {
                        continue
                    }
                    if callback_symbol_escapes_form(e, callback_name, item, depth) {
                        return true
                    }
                }
                return false
            }
            if head == "thread-detach" && len(form.items) >= 2 {
                for item, idx in form.items[2:] {
                    if thread_launch_callback_arg_is_non_escaping(e, form, callback_name, 1, 2, idx, depth) {
                        continue
                    }
                    if callback_symbol_escapes_form(e, callback_name, item, depth) {
                        return true
                    }
                }
                return false
            }
            if _, callee, ok_callee := resolve_proc_call_decl(e, head); ok_callee {
                for item, idx in form.items[1:] {
                    if worker_arg_callback_is_non_escaping(e, callee, form.items[1:], callback_name, idx, depth) {
                        continue
                    }
                    if callback_symbol_escapes_form(e, callback_name, item, depth) {
                        return true
                    }
                }
                return false
            }
        }
        for item in form.items {
            if callback_symbol_escapes_form(e, callback_name, item, depth) {
                return true
            }
        }
    case .Vector, .Brace, .Set:
        for item in form.items {
            if callback_symbol_escapes_form(e, callback_name, item, depth) {
                return true
            }
        }
    case:
    }
    return false
}

proc_callback_param_non_escaping_depth :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, callback_param_index: int, depth: int) -> bool {
    if depth > 8 {
        return false
    }
    if callback_param_index < 0 || callback_param_index >= len(proc_decl.params) {
        return false
    }
    callback_name := proc_decl.params[callback_param_index].name
    for form in proc_decl.body {
        if callback_symbol_escapes_form(e, callback_name, form, depth) {
            return false
        }
    }
    return true
}

proc_callback_param_non_escaping :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, callback_param_index: int) -> bool {
    return proc_callback_param_non_escaping_depth(e, proc_decl, callback_param_index, 0)
}

captured_specialization_name :: proc(proc_name: string, callback_param_index, capture_count: int) -> string {
    return fmt.tprintf("%s__kvist_capture_%d_%d", proc_name, callback_param_index, capture_count)
}

field_specialization_name :: proc(proc_name: string, callback_param_index: int, field: string) -> string {
    return fmt.tprintf("%s__kvist_field_%d_%s", proc_name, callback_param_index, field)
}

proc_specialization_name :: proc(spec: Captured_Proc_Specialization) -> string {
    if len(spec.field_callbacks) == 1 {
        field := spec.field_callbacks[0]
        return field_specialization_name(spec.original_name, field.callback_param_index, field.field_selector)
    }
    if len(spec.field_callbacks) > 1 {
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        strings.write_string(&builder, spec.original_name)
        for field in spec.field_callbacks {
            fmt.sbprintf(&builder, "__kvist_field_%d_%s", field.callback_param_index, field.field_selector)
        }
        return strings.clone(strings.to_string(builder))
    }
    if spec.field_selector != "" {
        return field_specialization_name(spec.original_name, spec.callback_param_index, spec.field_selector)
    }
    return captured_specialization_name(spec.original_name, spec.callback_param_index, spec.capture_count)
}

mark_proc_specialization :: proc(e: ^Emitter, proc_name: string, callback_param_index, capture_count: int, field_selector: string) {
    if e.captured_proc_specializations == nil {
        return
    }
    for spec in e.captured_proc_specializations^ {
        if spec.original_name == proc_name &&
           spec.callback_param_index == callback_param_index &&
           spec.capture_count == capture_count &&
           spec.field_selector == field_selector {
            return
        }
    }
    append(e.captured_proc_specializations, Captured_Proc_Specialization{
        original_name = proc_name,
        callback_param_index = callback_param_index,
        capture_count = capture_count,
        field_selector = field_selector,
    })
}

mark_field_proc_specializations :: proc(e: ^Emitter, proc_name: string, fields: []Field_Proc_Specialization) {
    if e.captured_proc_specializations == nil {
        return
    }
    for spec in e.captured_proc_specializations^ {
        if spec.original_name == proc_name &&
           spec.capture_count == 0 &&
           spec.field_selector == "" &&
           field_proc_specializations_match(spec.field_callbacks[:], fields) {
            return
        }
    }

    copied: [dynamic]Field_Proc_Specialization
    for field in fields {
        append(&copied, field)
    }
    append(e.captured_proc_specializations, Captured_Proc_Specialization{
        original_name = proc_name,
        field_callbacks = copied,
    })
}

mark_captured_proc_specialization :: proc(e: ^Emitter, proc_name: string, callback_param_index, capture_count: int) {
    mark_proc_specialization(e, proc_name, callback_param_index, capture_count, "")
}

mark_field_proc_specialization :: proc(e: ^Emitter, proc_name: string, callback_param_index: int, field: string) {
    mark_proc_specialization(e, proc_name, callback_param_index, 0, field)
}

field_callback_for_param :: proc(fields: []Field_Proc_Specialization, param_index: int) -> (Field_Proc_Specialization, bool) {
    for field in fields {
        if field.callback_param_index == param_index {
            return field, true
        }
    }
    return {}, false
}

emit_odin_operator_arg_texts :: proc(e: ^Emitter, form: CST_Form, start: int) -> (arg_texts: [dynamic]string, err: Compile_Error, ok: bool) {
    for arg in form.items[start:] {
        value, err_value, ok_value := emit_expr(e, arg)
        if !ok_value {
            return arg_texts, err_value, false
        }
        append(&arg_texts, value)
    }
    return arg_texts, {}, true
}

emit_odin_infix_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) < 4 || form.items[1].kind != .String {
        return "", Compile_Error{message = "odin-infix expects an operator string and at least two arguments", span = form.span}, false
    }
    op := unquote_string(form.items[1].text)
    defer delete(op)
    arg_texts, err_args, ok_args := emit_odin_operator_arg_texts(e, form, 2)
    if !ok_args {
        return "", err_args, false
    }
    defer delete(arg_texts)

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for arg_text, idx in arg_texts {
        if idx > 0 {
            fmt.sbprintf(&builder, " %s ", op)
        }
        fmt.sbprintf(&builder, "(%s)", arg_text)
    }
    return strings.clone(strings.to_string(builder)), {}, true
}

emit_odin_prefix_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 3 || form.items[1].kind != .String {
        return "", Compile_Error{message = "odin-prefix expects an operator string and one argument", span = form.span}, false
    }
    op := unquote_string(form.items[1].text)
    defer delete(op)
    value, err_value, ok_value := emit_expr(e, form.items[2])
    if !ok_value {
        return "", err_value, false
    }
    return fmt.tprintf("%s(%s)", op, value), {}, true
}

emit_odin_call_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) < 2 || form.items[1].kind != .String {
        return "", Compile_Error{message = "odin-call expects a callee string and optional arguments", span = form.span}, false
    }
    callee := unquote_string(form.items[1].text)
    defer delete(callee)
    if callee == "len" && len(form.items) == 3 {
        if ty, ok_ty := obvious_form_type(e, form.items[2]); ok_ty && ty == "Data" {
            value, err_value, ok_value := emit_expr(e, form.items[2])
            if !ok_value {
                return "", err_value, false
            }
            mark_data_type(e)
            return emit_call_text("kvist_data_count", []string{value}), Compile_Error{}, true
        }
    }
    arg_texts, err_args, ok_args := emit_odin_operator_arg_texts(e, form, 2)
    if !ok_args {
        return "", err_args, false
    }
    defer delete(arg_texts)
    return emit_call_text(callee, arg_texts[:]), {}, true
}

emit_operator_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    head := form.items[0]
    if head.kind != .Symbol {
        return "", {}, false
    }

    op := head.text
    if canonical_op, _, _, ok := resolve_kvist_head(e, op); ok {
        op = canonical_op
    }
    if op == "not" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "not expects one argument", span = form.span}, false
        }
        value, err_value, ok_value := emit_expr(e, form.items[1])
        if !ok_value {
            return "", err_value, false
        }
        return fmt.tprintf("!(%s)", value), {}, true
    }

    if op == "and" || op == "or" {
        if len(form.items) < 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects at least two arguments", op), span = form.span}, false
        }
        joiner := " && "
        if op == "or" {
            joiner = " || "
        }
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        for arg, idx in form.items[1:] {
            if idx > 0 {
                strings.write_string(&builder, joiner)
            }
            value, err_value, ok_value := emit_expr(e, arg)
            if !ok_value {
                return "", err_value, false
            }
            fmt.sbprintf(&builder, "(%s)", value)
        }
        return strings.clone(strings.to_string(builder)), {}, true
    }

    if op == "+" || op == "*" || op == "/" || op == "%" {
        if len(form.items) < 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects at least two arguments", op), span = form.span}, false
        }
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        for arg, idx in form.items[1:] {
            if idx > 0 {
                fmt.sbprintf(&builder, " %s ", op)
            }
            value, err_value, ok_value := emit_expr(e, arg)
            if !ok_value {
                return "", err_value, false
            }
            fmt.sbprintf(&builder, "(%s)", value)
        }
        return strings.clone(strings.to_string(builder)), {}, true
    }

    if op == "min" || op == "max" {
        if len(form.items) < 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects at least two arguments", op), span = form.span}, false
        }
        result, err_result, ok_result := emit_expr(e, form.items[1])
        if !ok_result {
            return "", err_result, false
        }
        for arg in form.items[2:] {
            value, err_value, ok_value := emit_expr(e, arg)
            if !ok_value {
                return "", err_value, false
            }
            result = fmt.tprintf("%s(%s, %s)", op, result, value)
        }
        return result, {}, true
    }

    if op == "-" {
        if len(form.items) == 2 {
            value, err_value, ok_value := emit_expr(e, form.items[1])
            if !ok_value {
                return "", err_value, false
            }
            return fmt.tprintf("-(%s)", value), {}, true
        }
        if len(form.items) >= 3 {
            builder := strings.builder_make()
            defer strings.builder_destroy(&builder)
            for arg, idx in form.items[1:] {
                if idx > 0 {
                    strings.write_string(&builder, " - ")
                }
                value, err_value, ok_value := emit_expr(e, arg)
                if !ok_value {
                    return "", err_value, false
                }
                fmt.sbprintf(&builder, "(%s)", value)
            }
            return strings.clone(strings.to_string(builder)), {}, true
        }
        return "", Compile_Error{message = "- expects at least one argument", span = form.span}, false
    }

    if op == "=" || op == "==" || op == "!=" || op == "<" || op == "<=" || op == ">" || op == ">=" {
        return emit_nary_comparison_expr(e, op, form.items[1:], form.span)
    }

    if op == "in?" || op == "in" || op == "core/in" {
        return "", Compile_Error{message = "`in` has been removed; use `contains?`", span = form.items[0].span}, false
    }

    if op == "not-in?" || op == "not-in" || op == "core/not-in" {
        return "", Compile_Error{message = "`not-in` has been removed; use `(not (contains? collection value))`", span = form.items[0].span}, false
    }

    if op == "odin-contains" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "odin-contains expects collection and key", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[1])
        if !ok_collection {
            return "", err_collection, false
        }
        key, err_key, ok_key := emit_expr(e, form.items[2])
        if !ok_key {
            return "", err_key, false
        }
        if ty, ok := obvious_form_type(e, form.items[1]); ok {
            if ty == "Data" {
                data_key, err_data_key, ok_data_key :=
                    emit_call_arg_for_expected_type(e, form.items[2], "Data")
                if !ok_data_key {
                    return "", err_data_key, false
                }
                return emit_call_text("kvist_data_contains", []string{collection, data_key}), {}, true
            }
            if ty == "string" {
                key_ty, ok_key_ty := obvious_form_type(e, form.items[2])
                if ok_key_ty && key_ty == "string" {
                    mark_core_strings(e)
                    return emit_call_text("strings.contains", []string{collection, key}), {}, true
                }
                return "", Compile_Error{message = "contains? on strings expects a string needle", span = form.items[2].span}, false
            }
            if strings.has_prefix(ty, "map[") {
                return fmt.tprintf("(%s) in (%s)", key, collection), {}, true
            }
            if type_text_is_pointer_to_map(ty) {
                return fmt.tprintf("(%s) in (%s)", key, deref_expr_text(collection)), {}, true
            }
            if strings.has_prefix(ty, "[]") || strings.has_prefix(ty, "[dynamic]") || (len(ty) > 1 && ty[0] == '[') {
                mark_core_contains_value(e)
                return emit_call_text("kvist_contains_value", []string{fmt.tprintf("(%s)[:]", collection), key}), {}, true
            }
        }
        return fmt.tprintf("(%s) in (%s)", key, collection), {}, true
    }

    return "", {}, false
}

find_union_decl :: proc(e: ^Emitter, name: string) -> (^Union_Decl, bool) {
    for i := len(e.local_unions) - 1; i >= 0; i -= 1 {
        if e.local_unions[i].name == name {
            return &e.local_unions[i], true
        }
    }
    for i in 0..<len(e.unions) {
        if e.unions[i].name == name {
            return &e.unions[i], true
        }
    }
    return nil, false
}

find_struct_decl :: proc(e: ^Emitter, name: string) -> (^Struct_Decl, bool) {
    for i := len(e.local_structs) - 1; i >= 0; i -= 1 {
        if e.local_structs[i].name == name {
            return &e.local_structs[i], true
        }
    }
    for i in 0..<len(e.structs) {
        if e.structs[i].name == name {
            return &e.structs[i], true
        }
    }
    return nil, false
}

find_enum_decl :: proc(e: ^Emitter, name: string) -> (^Enum_Decl, bool) {
    for i in 0..<len(e.decls) {
        if e.decls[i].kind == .Enum && e.decls[i].enum_decl.name == name {
            return &e.decls[i].enum_decl, true
        }
    }
    return nil, false
}

enum_type_exists :: proc(e: ^Emitter, name: string) -> bool {
    for decl in e.decls {
        if decl.kind == .Enum && decl.enum_decl.name == name {
            return true
        }
    }
    if imported_odin_enum_type_exists(e, name) {
        return true
    }
    return false
}

find_struct_field :: proc(struct_decl: ^Struct_Decl, name: string) -> (^Struct_Field, bool) {
    for i in 0..<len(struct_decl.fields) {
        if struct_decl.fields[i].name == name {
            return &struct_decl.fields[i], true
        }
    }
    return nil, false
}

find_field_in_slice :: proc(fields: []Struct_Field, name: string) -> (^Struct_Field, bool) {
    for i in 0..<len(fields) {
        if fields[i].name == name {
            return &fields[i], true
        }
    }
    return nil, false
}

quoted_symbol_name :: proc(form: CST_Form) -> (string, bool) {
    if form.kind == .Symbol && len(form.text) >= 2 && form.text[0] == '\'' {
        return map_name(form.text[1:]), true
    }
    if form.kind == .List &&
       len(form.items) == 2 &&
       form.items[0].kind == .Symbol &&
       form.items[0].text == "quote" &&
       form.items[1].kind == .Symbol {
        return map_name(form.items[1].text), true
    }
    return "", false
}

find_decl_doc_text :: proc(e: ^Emitter, name: string) -> (string, bool) {
    for decl in e.decls {
        if decl_name(decl) != name {
            continue
        }
        if len(decl.doc_lines) == 0 {
            return "", true
        }
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        for line, i in decl.doc_lines {
            if i > 0 {
                strings.write_byte(&builder, '\n')
            }
            strings.write_string(&builder, symbols_clean_doc_line(line))
        }
        return strings.clone(strings.to_string(builder)), true
    }
    return "", false
}

emit_struct_fields_literal :: proc(struct_decl: ^Struct_Decl) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "[]string{")
    for field, i in struct_decl.fields {
        if i > 0 {
            strings.write_string(&builder, ", ")
        }
        display_name := field.name
        if len(field.source_name) > 0 {
            display_name = field.source_name
        }
        strings.write_string(&builder, fmt.tprintf("%q", display_name))
    }
    strings.write_string(&builder, "}")
    return strings.clone(strings.to_string(builder))
}

surface_type_text :: proc(ty: string) -> string {
    switch ty {
    case "bool":
        return "bool"
    case "int":
        return "int"
    case "f64":
        return "float"
    case "string":
        return "string"
    case "rune":
        return "char"
    }

    if strings.has_prefix(ty, "[dynamic]") {
        elem := ty[len("[dynamic]"):]
        return fmt.tprintf("[dynamic]%s", surface_type_text(elem))
    }

    if strings.has_prefix(ty, "#soa[") {
        closing := strings.index(ty, "]")
        if closing > len("#soa[") {
            length := ty[len("#soa["):closing]
            elem := ty[closing+1:]
            return fmt.tprintf("#soa[%s]%s", length, surface_type_text(elem))
        }
    }

    if strings.has_prefix(ty, "#simd[") {
        closing := strings.index(ty, "]")
        if closing > len("#simd[") {
            length := ty[len("#simd["):closing]
            elem := ty[closing+1:]
            return fmt.tprintf("#simd[%s]%s", length, surface_type_text(elem))
        }
    }

    if strings.has_prefix(ty, "[]") {
        elem := ty[2:]
        return fmt.tprintf("[]%s", surface_type_text(elem))
    }

    if strings.has_prefix(ty, "map[") && strings.has_suffix(ty, "]struct{}") {
        return ty
    }

    if strings.has_prefix(ty, "bit_set[") {
        closing := strings.index(ty, "]")
        if closing > len("bit_set[") && closing == len(ty)-1 {
            return normalize_bit_set_text(ty[len("bit_set["):closing])
        }
    }

    if strings.has_prefix(ty, "matrix[") {
        closing := strings.index(ty, "]")
        if closing > len("matrix[") {
            dims := normalize_matrix_dims_text(ty[len("matrix["):closing])
            defer delete(dims)
            elem := ty[closing+1:]
            return fmt.tprintf("matrix[%s]%s", dims, surface_type_text(elem))
        }
    }

    if len(ty) > 2 && ty[0] == '[' {
        closing := strings.index(ty, "]")
        if closing > 1 {
            length := ty[1:closing]
            elem := ty[closing+1:]
            return fmt.tprintf("[%s]%s", length, surface_type_text(elem))
        }
    }

    return ty
}

emit_struct_types_literal :: proc(struct_decl: ^Struct_Decl) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "map[string]string{")
    for field, i in struct_decl.fields {
        if i > 0 {
            strings.write_string(&builder, ", ")
        }
        display_name := field.name
        if len(field.source_name) > 0 {
            display_name = field.source_name
        }
        strings.write_string(&builder, fmt.tprintf("%q = %q", display_name, surface_type_text(field.ty)))
    }
    strings.write_string(&builder, "}")
    return strings.clone(strings.to_string(builder))
}

brace_key_name :: proc(form: CST_Form) -> (string, bool) {
    if form.kind == .Symbol && len(form.text) > 1 && form.text[len(form.text)-1] == ':' {
        return map_name(form.text[:len(form.text)-1]), true
    }
    return "", false
}

number_looks_float :: proc(text: string) -> bool {
    for ch in text {
        if ch == '.' || ch == 'e' || ch == 'E' {
            return true
        }
    }
    return false
}

literal_matches_struct_field_type :: proc(e: ^Emitter, ty: string, value: CST_Form) -> bool {
    switch ty {
    case "string":
        if value.kind == .String || value.kind == .Regex {
            return true
        }
        return value.kind != .Number && value.kind != .Bool
    case "int":
        if value.kind == .Number {
            return !number_looks_float(value.text)
        }
        return value.kind != .String && value.kind != .Regex && value.kind != .Bool
    case "f64":
        if value.kind == .Number {
            return true
        }
        return value.kind != .String && value.kind != .Regex && value.kind != .Bool
    case "bool":
        if value.kind == .Bool {
            return true
        }
        return value.kind != .String && value.kind != .Regex && value.kind != .Number
    case "keyword":
        if value.kind == .Keyword {
            return true
        }
        return value.kind != .String && value.kind != .Regex && value.kind != .Number && value.kind != .Bool
    }

    nested_struct, ok_nested := find_struct_decl(e, ty)
    if ok_nested && value.kind == .List && len(value.items) == 2 && value.items[0].kind == .Symbol && map_name(value.items[0].text) == nested_struct.name && value.items[1].kind == .Brace {
        return true
    }

    return true
}

validate_struct_constructor :: proc(e: ^Emitter, struct_decl: ^Struct_Decl, form: CST_Form) -> (Compile_Error, bool) {
    if form.kind != .Brace {
        return Compile_Error{message = "struct construction expects a brace form", span = form.span}, false
    }

    seen: [dynamic]string
    for i := 0; i < len(form.items); i += 2 {
        if i+1 >= len(form.items) {
            return Compile_Error{message = "missing struct constructor value", span = form.span}, false
        }
        key := form.items[i]
        value := form.items[i+1]
        field_name, ok_key := brace_key_name(key)
        if !ok_key {
            return Compile_Error{message = "struct construction expects labeled fields", span = key.span}, false
        }
        for existing in seen {
            if existing == field_name {
                return Compile_Error{message = fmt.tprintf("duplicate struct constructor field %s", key.text), span = key.span}, false
            }
        }
        append(&seen, field_name)
        field, ok_field := find_struct_field(struct_decl, field_name)
        if !ok_field {
            return Compile_Error{message = fmt.tprintf("unknown struct constructor field %s", key.text), span = key.span}, false
        }
        if !literal_matches_struct_field_type(e, field.ty, value) {
            return Compile_Error{message = fmt.tprintf("struct constructor literal type mismatch for %s", key.text), span = value.span}, false
        }
    }

    return Compile_Error{}, true
}

is_numeric_scalar_type :: proc(text: string) -> bool {
    switch text {
    case "int", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "uintptr", "f32", "f64":
        return true
    case:
        return false
    }
}

emit_union_constructor :: proc(e: ^Emitter, union_decl: ^Union_Decl, arg: CST_Form) -> (string, Compile_Error, bool) {
    if arg.kind != .Brace {
        return "", Compile_Error{message = "union construction expects a brace form", span = arg.span}, false
    }
    if len(arg.items) != 2 {
        return "", Compile_Error{message = "union construction expects exactly one variant", span = arg.span}, false
    }

    key := arg.items[0]
    value := arg.items[1]
    variant_name, ok_key := brace_key_name(key)
    if !ok_key {
        return "", Compile_Error{message = "union construction expects a variant label", span = key.span}, false
    }

    found := false
    variant_ty := ""
    for variant in union_decl.variants {
        if variant.name == variant_name {
            found = true
            variant_ty = variant.ty
            break
        }
    }
    if !found {
        return "", Compile_Error{message = "unknown union variant", span = key.span}, false
    }

    value_text, err_value, ok_value := emit_expr(e, value)
    if !ok_value {
        return "", err_value, false
    }
    if value.kind == .Number && is_numeric_scalar_type(variant_ty) {
        value_text = fmt.tprintf("%s(%s)", variant_ty, value_text)
    }
    return fmt.tprintf("%s(%s)", union_decl.name, value_text), {}, true
}

emit_directive_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) < 2 || form.items[0].kind != .Symbol || len(form.items[0].text) == 0 || form.items[0].text[0] != '#' {
        return "", Compile_Error{message = "invalid directive expression", span = form.span}, false
    }

    if form.items[0].text == "#caller_expression" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "#caller_expression expects exactly one expression", span = form.span}, false
        }
        target_text, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        return fmt.tprintf("#caller_expression(%s)", target_text), {}, true
    }

    target := form.items[1]
    if len(form.items) > 2 {
        call_items: [dynamic]CST_Form
        for item in form.items[1:] {
            append(&call_items, item)
        }
        target = CST_Form{
            kind  = .List,
            items = call_items,
            span  = form.span,
        }
    }

    target_text, err_target, ok_target := emit_expr(e, target)
    if !ok_target {
        return "", err_target, false
    }
    return fmt.tprintf("%s %s", form.items[0].text, target_text), {}, true
}

is_call_directive_symbol :: proc(form: CST_Form) -> bool {
    return form.kind == .Symbol &&
           len(form.text) > 0 &&
           form.text[0] == '#' &&
           !strings.has_prefix(form.text, "#soa[") &&
           !strings.has_prefix(form.text, "#simd[")
}

captured_callback_arg_context :: proc(e: ^Emitter, arg: CST_Form) -> (proc_text: string, capture_names: [dynamic]string, field_selector: string, specialized: bool, err: Compile_Error, ok: bool) {
    if field, ok_field := field_from_selector(arg); ok_field {
        return "", capture_names, field, true, Compile_Error{}, true
    }

    if arg.kind == .Symbol {
        name := map_name(arg.text)
        if ctx, ok_context := lookup_callback_context(e, name); ok_context {
            if ctx.field_selector != "" {
                return name, capture_names, ctx.field_selector, true, Compile_Error{}, true
            }
            for capture_name in ctx.capture_names {
                append(&capture_names, capture_name)
            }
            return name, capture_names, "", true, Compile_Error{}, true
        }
        return "", capture_names, "", false, Compile_Error{}, true
    }

    proc_text_value, capture_names_value, _, captured_value, err_value, ok_value := captured_proc_literal_for_param(e, arg)
    return proc_text_value, capture_names_value, "", captured_value, err_value, ok_value
}

field_selector_typeid_bindings :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, args: []CST_Form, callback_index: int, field_selector: string) -> (bindings: [dynamic]Param, err: Compile_Error, ok: bool) {
    callback_ty := proc_decl.params[callback_index].ty
    generic_params := generic_type_params_in_text(callback_ty)
    if len(generic_params) == 0 {
        return bindings, Compile_Error{}, true
    }
    return_generic_params := proc_type_return_generic_params(callback_ty)
    input_generic_params := proc_type_param_generic_params(callback_ty)

    source_arg_idx := -1
    for param, idx in proc_decl.params {
        if idx == callback_index || type_text_is_proc(param.ty) {
            continue
        }
        if len(input_generic_params) > 0 {
            matches_input_generic := false
            for generic_param in input_generic_params {
                if type_text_mentions_generic_param(param.ty, generic_param) {
                    matches_input_generic = true
                    break
                }
            }
            if !matches_input_generic {
                continue
            }
        }
        source_arg_idx = idx
        break
    }
    if source_arg_idx < 0 {
        for param, idx in proc_decl.params {
            if idx == callback_index || type_text_is_proc(param.ty) {
                continue
            }
            source_arg_idx = idx
            break
        }
    }
    if source_arg_idx < 0 || source_arg_idx >= len(args) {
        return bindings, Compile_Error{message = "field-selector callback specialization could not infer generic return type"}, false
    }

    source_text, err_source, ok_source := emit_expr(e, args[source_arg_idx])
    if !ok_source {
        return bindings, err_source, false
    }

    source_param_ty := proc_decl.params[source_arg_idx].ty
    source_is_slice := strings.has_prefix(source_param_ty, "[]") || strings.has_prefix(source_param_ty, "[dynamic]")
    source_is_ptr_slice := strings.has_prefix(source_param_ty, "^[]") || strings.has_prefix(source_param_ty, "^[dynamic]")
    source_item_text := source_text
    if source_is_ptr_slice {
        source_item_text = deref_expr_text(source_text)
    }

    type_expr := ""
    if source_is_slice || source_is_ptr_slice {
        type_expr = fmt.tprintf("type_of((%s)[0].%s)", source_item_text, field_selector)
    } else {
        type_expr = fmt.tprintf("type_of((%s).%s)", source_text, field_selector)
    }
    item_type_expr := ""
    if source_is_slice || source_is_ptr_slice {
        item_type_expr = fmt.tprintf("type_of((%s)[0])", source_item_text)
    } else {
        item_type_expr = fmt.tprintf("type_of(%s)", source_text)
    }

    for generic_param in generic_params {
        if generic_param_in_slice(return_generic_params[:], generic_param) {
            append(&bindings, Param{name = generic_param, ty = type_expr})
        } else {
            append(&bindings, Param{name = generic_param, ty = item_type_expr})
        }
    }
    return bindings, Compile_Error{}, true
}

append_unique_typeid_binding :: proc(bindings: ^[dynamic]Param, binding: Param) {
    for existing in bindings^ {
        if existing.name == binding.name {
            return
        }
    }
    append(bindings, binding)
}

emit_specialized_proc_call_if_needed :: proc(e: ^Emitter, call_name: string, proc_decl: ^Proc_Decl, args: []CST_Form, span: Span) -> (text: string, handled: bool, err: Compile_Error, ok: bool) {
    specialized_index := -1
    proc_text := ""
    capture_names: [dynamic]string
    field_selector := ""
    field_callbacks: [dynamic]Field_Proc_Specialization

    for arg, idx in args {
        if idx >= len(proc_decl.params) || !type_text_is_proc(proc_decl.params[idx].ty) {
            continue
        }
        candidate_proc_text, candidate_capture_names, candidate_field, specialized, err_candidate, ok_candidate := captured_callback_arg_context(e, arg)
        if !ok_candidate {
            return "", true, err_candidate, false
        }
        if !specialized {
            continue
        }
        if specialized_index >= 0 {
            if field_selector == "" || candidate_field == "" {
                return "", true, Compile_Error{message = "callback specialization currently supports one captured callback argument per call", span = arg.span}, false
            }
        }
        if candidate_field != "" {
            append(&field_callbacks, Field_Proc_Specialization{callback_param_index = idx, field_selector = candidate_field})
        }
        specialized_index = idx
        proc_text = candidate_proc_text
        capture_names = candidate_capture_names
        field_selector = candidate_field
    }

    if specialized_index < 0 {
        return "", false, Compile_Error{}, true
    }

    if len(args) != len(proc_decl.params) {
        return "", true, Compile_Error{message = "callback specialization currently requires explicit positional arguments", span = span}, false
    }
    if len(field_callbacks) > 0 {
        for field_callback in field_callbacks {
            if !proc_callback_param_non_escaping(e, proc_decl, field_callback.callback_param_index) {
                return "", true, Compile_Error{message = fmt.tprintf("field-selector callback cannot be passed to %s because callback parameter %s may escape", call_name, proc_decl.params[field_callback.callback_param_index].name), span = args[field_callback.callback_param_index].span}, false
            }
        }
    } else if !proc_callback_param_non_escaping(e, proc_decl, specialized_index) {
        return "", true, Compile_Error{message = fmt.tprintf("captured callback cannot be passed to %s because callback parameter %s may escape", call_name, proc_decl.params[specialized_index].name), span = args[specialized_index].span}, false
    }

    specialized_name := ""
    if len(field_callbacks) > 0 {
        mark_field_proc_specializations(e, proc_decl.name, field_callbacks[:])
        specialized_name = proc_specialization_name(Captured_Proc_Specialization{original_name = proc_decl.name, field_callbacks = field_callbacks})
    } else {
        mark_captured_proc_specialization(e, proc_decl.name, specialized_index, len(capture_names))
        specialized_name = captured_specialization_name(proc_decl.name, specialized_index, len(capture_names))
    }

    arg_texts: [dynamic]string
    defer delete(arg_texts)
    if len(field_callbacks) > 0 {
        typeid_bindings: [dynamic]Param
        for field_callback in field_callbacks {
            bindings, err_typeid, ok_typeid := field_selector_typeid_bindings(e, proc_decl, args, field_callback.callback_param_index, field_callback.field_selector)
            if !ok_typeid {
                return "", true, err_typeid, false
            }
            for binding in bindings {
                append_unique_typeid_binding(&typeid_bindings, binding)
            }
        }
        for binding in typeid_bindings {
            append(&arg_texts, binding.ty)
        }
    }
    for arg, idx in args {
        if len(field_callbacks) > 0 {
            skip_field_callback := false
            for field_callback in field_callbacks {
                if idx == field_callback.callback_param_index {
                    skip_field_callback = true
                    break
                }
            }
            if skip_field_callback {
                continue
            }
        } else if idx == specialized_index {
            append(&arg_texts, proc_text)
            for capture_name in capture_names {
                append(&arg_texts, capture_name)
            }
            continue
        }
        arg_text, err_arg, ok_arg := emit_expr(e, arg)
        if !ok_arg {
            return "", true, err_arg, false
        }
        append(&arg_texts, arg_text)
    }
    return emit_call_text(specialized_name, arg_texts[:]), true, Compile_Error{}, true
}

transform_temp_name :: proc(e: ^Emitter) -> string {
    e.temp_counter += 1
    return fmt.tprintf("kvist_xform_%d", e.temp_counter)
}

loop_temp_name :: proc(e: ^Emitter, stem: string) -> string {
    e.temp_counter += 1
    return fmt.tprintf("kvist_loop_%s_%d", stem, e.temp_counter)
}

source_temp_name :: proc(e: ^Emitter) -> string {
    e.temp_counter += 1
    return fmt.tprintf("kvist_source_%d", e.temp_counter)
}

source_ok_name :: proc(e: ^Emitter) -> string {
    e.temp_counter += 1
    return fmt.tprintf("kvist_source_ok_%d", e.temp_counter)
}

source_call_decl :: proc(e: ^Emitter, form: CST_Form) -> (^Source_Decl, bool) {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return nil, false
    }
    name := map_name(form.items[0].text)
    return find_source_decl(e, name)
}

form_is_direct_transform_source_call :: proc(form: CST_Form) -> bool {
    return false
}

form_is_transform_loop_call :: proc(form: CST_Form) -> bool {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    return form.items[0].text == "transform-loop"
}

type_ident_byte :: proc(ch: u8) -> bool {
    return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_'
}

substitute_type_names :: proc(type_text: string, names, types: []string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    i := 0
    for i < len(type_text) {
        matched := false
        for name, idx in names {
            if name == "" {
                continue
            }
            prefixed := fmt.tprintf("$%s", name)
            if i+len(prefixed) <= len(type_text) && type_text[i:i+len(prefixed)] == prefixed {
                after := i + len(prefixed)
                after_ok := after == len(type_text) || !type_ident_byte(type_text[after])
                if after_ok {
                    strings.write_string(&builder, types[idx])
                    i += len(prefixed)
                    matched = true
                    break
                }
            }
            if i+len(name) > len(type_text) || type_text[i:i+len(name)] != name {
                continue
            }
            after := i + len(name)
            before_ok := i == 0 || !type_ident_byte(type_text[i-1])
            after_ok := after == len(type_text) || !type_ident_byte(type_text[after])
            if before_ok && after_ok {
                strings.write_string(&builder, types[idx])
                i += len(name)
                matched = true
                break
            }
        }
        if !matched {
            strings.write_byte(&builder, type_text[i])
            i += 1
        }
    }
    return strings.clone(strings.to_string(builder))
}

transform_loop_source :: proc(e: ^Emitter, form: CST_Form) -> (spec: Transform_Loop_Source, err: Compile_Error, ok: bool) {
    if !form_is_transform_loop_call(form) {
        return spec, {}, false
    }
    if len(form.items) != 4 {
        return spec, Compile_Error{message = "transform-loop expects bindings, item type, and item expression", span = form.span}, false
    }
    bindings := form.items[1]
    if bindings.kind != .Vector || len(bindings.items) != 3 {
        return spec, Compile_Error{message = "transform-loop expects [key value source] bindings", span = bindings.span}, false
    }
    key_form := bindings.items[0]
    value_form := bindings.items[1]
    source_form := bindings.items[2]
    if key_form.kind != .Symbol || value_form.kind != .Symbol {
        return spec, Compile_Error{message = "transform-loop key and value bindings must be symbols", span = bindings.span}, false
    }
    source_ty, ok_source_ty := obvious_form_type(e, source_form)
    if !ok_source_ty {
        return spec, Compile_Error{message = "transform-loop expects a map with an obvious type; bind or annotate it first", span = source_form.span}, false
    }
    key_ty, value_ty, ok_map := map_type_parts(source_ty)
    if !ok_map {
        return spec, Compile_Error{message = fmt.tprintf("transform-loop expects map source, got %s", source_ty), span = source_form.span}, false
    }
    source_text, err_source, ok_source := emit_expr(e, source_form)
    if !ok_source {
        return spec, err_source, false
    }
    key_name := map_name(key_form.text)
    value_name := map_name(value_form.text)
    push_local_type_scope(e)
    defer pop_local_type_scope(e)
    bind_local_type(e, key_name, key_ty)
    bind_local_type(e, value_name, value_ty)
    item_ty_template, err_item_ty, ok_item_ty := parse_type_text(form.items[2])
    if !ok_item_ty {
        return spec, err_item_ty, false
    }
    defer delete(item_ty_template)
    binding_names := []string{key_name, value_name}
    binding_types := []string{key_ty, value_ty}
    item_ty := substitute_type_names(item_ty_template, binding_names, binding_types)
    defer delete(item_ty)
    item_text, err_item, ok_item := emit_expr_for_expected_type(e, form.items[3], item_ty)
    if !ok_item {
        return spec, err_item, false
    }
    spec.source_text = source_text
    spec.source_ty = source_ty
    spec.item_ty = strings.clone(item_ty)
    spec.item_text = item_text
    spec.key_name = key_name
    spec.key_ty = key_ty
    spec.value_name = value_name
    spec.value_ty = value_ty
    return spec, {}, true
}

source_state_type :: proc(e: ^Emitter, source: ^Source_Decl) -> (string, Compile_Error, bool) {
    _ = e
    return source.state_ty, {}, true
}

source_item_var_name :: proc(source_item_ty: string) -> string {
    if strings.has_prefix(source_item_ty, "$") {
        return source_item_ty[1:]
    }
    return source_item_ty
}

type_text_is_source_item_var :: proc(ty, source_item_ty: string) -> bool {
    var_name := source_item_var_name(source_item_ty)
    return ty == var_name || ty == fmt.tprintf("$%s", var_name)
}

source_param_type_for_item :: proc(param_ty, source_item_ty, item_ty: string) -> string {
    if item_ty == "" {
        return param_ty
    }
    var_name := source_item_var_name(source_item_ty)
    if param_ty == var_name || param_ty == fmt.tprintf("$%s", var_name) {
        return item_ty
    }
    replaced, _ := strings.replace_all(param_ty, fmt.tprintf("$%s", var_name), item_ty, context.temp_allocator)
    replaced, _ = strings.replace_all(replaced, fmt.tprintf("-> %s", var_name), fmt.tprintf("-> %s", item_ty), context.temp_allocator)
    return replaced
}

proc_type_single_return_type :: proc(ty: string) -> (string, bool) {
    arrow := strings.index(ty, "->")
    if arrow < 0 {
        return "", false
    }
    return strings.trim_space(ty[arrow+len("->"):]), true
}

append_unique_text :: proc(values: ^[dynamic]string, value: string) {
    for existing in values^ {
        if existing == value {
            return
        }
    }
    append(values, value)
}

generic_type_params_in_text :: proc(text: string) -> (params: [dynamic]string) {
    i := 0
    for i < len(text) {
        if text[i] != '$' {
            i += 1
            continue
        }
        start := i + 1
        end := start
        for end < len(text) {
            ch := text[end]
            alpha := (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
            digit := ch >= '0' && ch <= '9'
            if !(alpha || digit || ch == '_') {
                break
            }
            end += 1
        }
        if end > start {
            append_unique_text(&params, text[start:end])
        }
        i = end
    }
    return params
}

proc_type_return_generic_params :: proc(proc_ty: string) -> (params: [dynamic]string) {
    return_ty, ok_return := proc_type_single_return_type(proc_ty)
    if !ok_return {
        return params
    }
    return generic_type_params_in_text(return_ty)
}

proc_type_param_generic_params :: proc(proc_ty: string) -> (params: [dynamic]string) {
    if !strings.has_prefix(proc_ty, "proc(") {
        return params
    }
    close := strings.index(proc_ty, ")")
    if close < len("proc(") {
        return params
    }
    return generic_type_params_in_text(proc_ty[len("proc("):close])
}

generic_param_in_slice :: proc(values: []string, value: string) -> bool {
    for existing in values {
        if existing == value {
            return true
        }
    }
    return false
}

type_text_mentions_generic_param :: proc(type_text, generic_param: string) -> bool {
    if strings.contains(type_text, fmt.tprintf("$%s", generic_param)) {
        return true
    }
    return strings.contains(type_text, generic_param)
}

source_callback_return_item_type :: proc(e: ^Emitter, callback: CST_Form) -> (string, bool) {
    if callback.kind == .Symbol {
        name := map_name(callback.text)
        if proc_decl, ok_proc := find_proc_decl(e, name); ok_proc && proc_decl.returns.kind == .Single {
            return proc_decl.returns.single_ty, true
        }
        if ty, ok_ty := lookup_local_type(e, name); ok_ty {
            return proc_type_single_return_type(ty)
        }
        return "", false
    }
    if callback.kind == .List && len(callback.items) > 0 && is_symbol(callback.items[0], "fn") {
        parsed, _, ok_parsed := parse_proc_literal_form(callback)
        if ok_parsed && parsed.returns.kind == .Single {
            return parsed.returns.single_ty, true
        }
    }
    return "", false
}

source_param_callback_yields_item :: proc(param_ty, source_item_ty: string) -> bool {
    return_ty, ok_return := proc_type_single_return_type(param_ty)
    if !ok_return {
        return false
    }
    return type_text_is_source_item_var(return_ty, source_item_ty)
}

source_param_collection_yields_item :: proc(param_ty, source_item_ty: string) -> bool {
    elem_ty, ok_elem_ty := collection_element_type(param_ty)
    return ok_elem_ty && type_text_is_source_item_var(elem_ty, source_item_ty)
}

source_call_arg_texts :: proc(e: ^Emitter, source: ^Source_Decl, form: CST_Form, item_ty := "") -> (arg_texts: [dynamic]string, err: Compile_Error, ok: bool) {
    provided := len(form.items) - 1
    if provided != len(source.params) {
        return arg_texts, Compile_Error{message = fmt.tprintf("iterator %s expects %d arguments, got %d", source.name, len(source.params), provided), span = form.span}, false
    }
    for arg, idx in form.items[1:] {
        expected_ty := source_param_type_for_item(source.params[idx].ty, source.item_ty, item_ty)
        arg_text, err_arg, ok_arg := emit_expr_for_expected_type(e, arg, expected_ty)
        if !ok_arg {
            return arg_texts, err_arg, false
        }
        append(&arg_texts, arg_text)
    }
    return arg_texts, {}, true
}

source_call_item_type :: proc(e: ^Emitter, source: ^Source_Decl, form: CST_Form) -> (string, Compile_Error, bool) {
    item_ty := source.item_ty
    if form.kind != .List {
        return item_ty, {}, true
    }
    for param, idx in source.params {
        if idx+1 >= len(form.items) {
            break
        }
        if !strings.has_prefix(param.ty, "$") {
            continue
        }
        var_name := param.ty[1:]
        if item_ty != var_name && item_ty != param.ty {
            continue
        }
        actual_ty, ok_actual_ty := obvious_form_type(e, form.items[idx+1])
        if !ok_actual_ty {
            return "", Compile_Error{message = fmt.tprintf("iterator %s expects argument %s to have an obvious type", source.name, param.name), span = form.items[idx+1].span}, false
        }
        return actual_ty, {}, true
    }
    for param, idx in source.params {
        if idx+1 >= len(form.items) {
            break
        }
        if !source_param_callback_yields_item(param.ty, item_ty) {
            continue
        }
        actual_ty, ok_actual_ty := source_callback_return_item_type(e, form.items[idx+1])
        if !ok_actual_ty {
            return "", Compile_Error{message = fmt.tprintf("iterator %s expects callback argument %s to have an obvious return type", source.name, param.name), span = form.items[idx+1].span}, false
        }
        return actual_ty, {}, true
    }
    for param, idx in source.params {
        if idx+1 >= len(form.items) {
            break
        }
        if !source_param_collection_yields_item(param.ty, item_ty) {
            continue
        }
        actual_ty, ok_actual_ty := obvious_form_type(e, form.items[idx+1])
        if !ok_actual_ty && form.items[idx+1].kind == .List && len(form.items[idx+1].items) >= 2 {
            parsed_type, _, ok_parsed_type := parse_type_text(form.items[idx+1].items[0])
            if ok_parsed_type {
                actual_ty = parsed_type
                ok_actual_ty = true
            }
        }
        if !ok_actual_ty {
            return "", Compile_Error{message = fmt.tprintf("iterator %s expects collection argument %s to have an obvious element type", source.name, param.name), span = form.items[idx+1].span}, false
        }
        actual_elem_ty, ok_actual_elem_ty := collection_element_type(actual_ty)
        if !ok_actual_elem_ty {
            return "", Compile_Error{message = fmt.tprintf("iterator %s expects argument %s to be a collection", source.name, param.name), span = form.items[idx+1].span}, false
        }
        return actual_elem_ty, {}, true
    }
    return item_ty, {}, true
}

source_call_text :: proc(e: ^Emitter, source: ^Source_Decl, arg_texts: []string) -> string {
    return emit_call_text(source.name, arg_texts)
}

generic_type_text_matches :: proc(actual, expected: string) -> bool {
    if actual == expected {
        return true
    }
    actual_plain, actual_allocated := strings.replace_all(actual, "$", "", context.allocator)
    if actual_allocated {
        defer delete(actual_plain)
    }
    expected_plain, expected_allocated := strings.replace_all(expected, "$", "", context.allocator)
    if expected_allocated {
        defer delete(expected_plain)
    }
    return actual_plain == expected_plain
}

validate_source_protocol :: proc(e: ^Emitter, source: ^Source_Decl, state_ty: string, span: Span) -> (Compile_Error, bool) {
    next_decl, ok_next := find_proc_decl(e, source.next_name)
    if !ok_next {
        return Compile_Error{message = fmt.tprintf("defiter %s :next must name a known function: %s", source.name, source.next_name), span = span}, false
    }
    expected_state_ptr := fmt.tprintf("^%s", state_ty)
    if len(next_decl.params) != 1 || !generic_type_text_matches(next_decl.params[0].ty, expected_state_ptr) {
        return Compile_Error{message = fmt.tprintf("defiter %s :next must take %s", source.name, expected_state_ptr), span = span}, false
    }
    if next_decl.returns.kind != .Named ||
       len(next_decl.returns.named) != 2 ||
       !generic_type_text_matches(next_decl.returns.named[0].ty, source.item_ty) ||
       next_decl.returns.named[1].ty != "bool" {
        return Compile_Error{message = fmt.tprintf("defiter %s :next must return [item: %s ok: bool]", source.name, source.item_ty), span = span}, false
    }
    if source.has_dispose {
        dispose_decl, ok_dispose := find_proc_decl(e, source.dispose_name)
        if !ok_dispose {
            return Compile_Error{message = fmt.tprintf("defiter %s :dispose must name a known function: %s", source.name, source.dispose_name), span = span}, false
        }
        if len(dispose_decl.params) != 1 || dispose_decl.params[0].ty != expected_state_ptr {
            return Compile_Error{message = fmt.tprintf("defiter %s :dispose must take %s", source.name, expected_state_ptr), span = span}, false
        }
        if dispose_decl.returns.kind != .None {
            return Compile_Error{message = fmt.tprintf("defiter %s :dispose must not return a value", source.name), span = span}, false
        }
    }
    return {}, true
}

transform_step_kind :: proc(head: string) -> (Transform_Step_Kind, bool) {
    switch head {
    case "map":
        return .Map, true
    case "filter":
        return .Filter, true
    case "remove":
        return .Remove, true
    case "keep":
        return .Keep, true
    case "take":
        return .Take, true
    case "take-while":
        return .Take_While, true
    case "drop":
        return .Drop, true
    case "drop-while":
        return .Drop_While, true
    case "map-indexed":
        return .Map_Indexed, true
    case "mapcat":
        return .Mapcat, true
    }
    return {}, false
}

transform_spec_form :: proc(e: ^Emitter, form: CST_Form) -> (CST_Form, Compile_Error, bool) {
    if form.kind == .Symbol {
        decl, ok_decl := find_transform_decl(e, map_name(form.text))
        if !ok_decl {
            return {}, Compile_Error{message = fmt.tprintf("unknown transform: %s", form.text), span = form.span}, false
        }
        return decl.spec, {}, true
    }
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if form.items[0].text == "comp" {
            return form, {}, true
        }
        if _, ok_kind := transform_step_kind(form.items[0].text); ok_kind {
            return form, {}, true
        }
        return {}, Compile_Error{message = "transform steps currently support map, map-indexed, mapcat, filter, remove, keep, take, take-while, drop, and drop-while", span = form.items[0].span}, false
    }
    return {}, Compile_Error{message = "transform expects a named transform, (comp ...), or a transform step", span = form.span}, false
}

parse_transform_steps_into :: proc(e: ^Emitter, form: CST_Form, steps: ^[dynamic]Transform_Step) -> (Compile_Error, bool) {
    spec, err_spec, ok_spec := transform_spec_form(e, form)
    if !ok_spec {
        return err_spec, false
    }
    if spec.kind != .List || len(spec.items) == 0 || spec.items[0].kind != .Symbol {
        return Compile_Error{message = "transform spec expects (comp ...) or a transform step", span = spec.span}, false
    }
    if spec.items[0].text == "comp" {
        for step_form in spec.items[1:] {
            err_step, ok_step := parse_transform_steps_into(e, step_form, steps)
            if !ok_step {
                return err_step, false
            }
        }
        return {}, true
    }
    if len(spec.items) != 2 {
        return Compile_Error{message = "transform steps expect one argument", span = spec.span}, false
    }
    kind, ok_kind := transform_step_kind(spec.items[0].text)
    if !ok_kind {
        return Compile_Error{message = "transform steps currently support map, map-indexed, mapcat, filter, remove, keep, take, take-while, drop, and drop-while", span = spec.items[0].span}, false
    }
    state_name := ""
    if kind == .Take || kind == .Drop || kind == .Drop_While || kind == .Map_Indexed {
        state_name = transform_temp_name(e)
    }
    append(steps, Transform_Step{
        kind = kind,
        callback = spec.items[1],
        state_name = state_name,
        span = spec.span,
    })
    return {}, true
}

parse_transform_steps :: proc(e: ^Emitter, form: CST_Form) -> (steps: [dynamic]Transform_Step, err: Compile_Error, ok: bool) {
    err_steps, ok_steps := parse_transform_steps_into(e, form, &steps)
    if !ok_steps {
        return steps, err_steps, false
    }
    return steps, {}, true
}

transform_proc_literal_call :: proc(e: ^Emitter, callback: CST_Form, expected_params: []Param, label := "transform fn callback") -> (text: string, returns: Return_Spec, err: Compile_Error, ok: bool) {
	if callback.kind != .List || len(callback.items) == 0 || !is_symbol(callback.items[0], "fn") {
		return "", {}, {}, false
	}
    parsed, err_parse, ok_parse := parse_proc_literal_form(callback)
    if !ok_parse {
        return "", {}, err_parse, false
	}
	if len(parsed.params) != len(expected_params) {
		return "", {}, Compile_Error{message = fmt.tprintf("%s expects %d parameters", label, len(expected_params)), span = callback.span}, false
	}
	for expected, idx in expected_params {
		if parsed.params[idx].ty != expected.ty {
			return "", {}, Compile_Error{message = fmt.tprintf("%s parameter %s must be %s", label, parsed.params[idx].name, expected.ty), span = callback.span}, false
		}
	}

	param_names: [dynamic]string
	defer delete(param_names)
	for param in parsed.params {
		append(&param_names, param.name)
	}
	captures := collect_proc_literal_captures(e, parsed.body[:], param_names[:])
	defer delete(captures)

    proc_params: [dynamic]Param
    call_args: [dynamic]string
    defer delete(proc_params)
    defer delete(call_args)
    for capture in captures {
        append(&proc_params, capture)
        append(&call_args, capture.name)
    }
    for param in parsed.params {
        append(&proc_params, param)
    }
    for expected in expected_params {
        append(&call_args, expected.name)
    }

    proc_text, err_proc, ok_proc := emit_proc_literal_text(e, proc_params[:], parsed.returns, parsed.body[:])
    if !ok_proc {
        return "", {}, err_proc, false
    }
	return emit_call_text(proc_text, call_args[:]), parsed.returns, {}, true
}

transform_fn_capture_params :: proc(e: ^Emitter, callback: CST_Form) -> (captures: [dynamic]Param, err: Compile_Error, ok: bool) {
	if callback.kind != .List || len(callback.items) == 0 || !is_symbol(callback.items[0], "fn") {
		return captures, {}, true
	}
	parsed, err_parse, ok_parse := parse_proc_literal_form(callback)
	if !ok_parse {
		return captures, err_parse, false
	}
	param_names: [dynamic]string
	defer delete(param_names)
	for param in parsed.params {
		append(&param_names, param.name)
	}
	callback_captures := collect_proc_literal_captures(e, parsed.body[:], param_names[:])
	defer delete(callback_captures)
	for capture in callback_captures {
		append_capture_param_unique(&captures, capture)
	}
	return captures, {}, true
}

transform_step_capture_params :: proc(e: ^Emitter, steps: []Transform_Step) -> (captures: [dynamic]Param, err: Compile_Error, ok: bool) {
	for step in steps {
		callback_captures, err_callback, ok_callback := transform_fn_capture_params(e, step.callback)
		if !ok_callback {
			return captures, err_callback, false
		}
		defer delete(callback_captures)
		for capture in callback_captures {
			append_capture_param_unique(&captures, capture)
		}
	}
	return captures, {}, true
}

proc_callback_call :: proc(e: ^Emitter, callback: CST_Form, input_text, input_ty: string) -> (text, return_ty: string, err: Compile_Error, ok: bool) {
    if field, ok_field := field_from_selector(callback); ok_field {
        field_ty, ok_field_ty := struct_field_type_for_update(e, input_ty, field)
        if !ok_field_ty {
            return "", "", Compile_Error{message = fmt.tprintf("transform callback could not find field .%s on %s", field, input_ty), span = callback.span}, false
        }
        return fmt.tprintf("%s.%s", input_text, field), field_ty, {}, true
    }
    if callback.kind == .List && len(callback.items) > 0 && is_symbol(callback.items[0], "fn") {
        text, returns, err_literal, ok_literal := transform_proc_literal_call(e, callback, []Param{{name = input_text, ty = input_ty}})
        if !ok_literal {
            return "", "", err_literal, false
        }
        if returns.kind != .Single {
            return "", "", Compile_Error{message = "transform fn callback requires an explicit single return type", span = callback.span}, false
        }
        return text, returns.single_ty, {}, true
    }
    if callback.kind != .Symbol {
        return "", "", Compile_Error{message = "transform callback currently expects a function symbol, field selector, or fn literal", span = callback.span}, false
    }
    proc_name := map_name(callback.text)
    proc_decl, ok_proc := find_proc_decl(e, proc_name)
    if !ok_proc {
        return "", "", Compile_Error{message = fmt.tprintf("transform callback must be a known one-argument function: %s", callback.text), span = callback.span}, false
    }
    if len(proc_decl.params) != 1 {
        return "", "", Compile_Error{message = "transform callback currently expects a one-argument function", span = callback.span}, false
    }
    if proc_decl.params[0].ty != input_ty {
        return "", "", Compile_Error{message = fmt.tprintf("transform callback expects %s but pipeline has %s", proc_decl.params[0].ty, input_ty), span = callback.span}, false
    }
    if proc_decl.returns.kind != .Single {
        return "", "", Compile_Error{message = "transform callback currently expects a single return value", span = callback.span}, false
    }
    return emit_call_text(proc_name, []string{input_text}), proc_decl.returns.single_ty, {}, true
}

indexed_callback_call :: proc(e: ^Emitter, callback: CST_Form, index_text, input_text, input_ty: string) -> (text, return_ty: string, err: Compile_Error, ok: bool) {
    if callback.kind == .List && len(callback.items) > 0 && is_symbol(callback.items[0], "fn") {
        text, returns, err_literal, ok_literal := transform_proc_literal_call(e, callback, []Param{{name = index_text, ty = "int"}, {name = input_text, ty = input_ty}}, "map-indexed transform fn callback")
        if !ok_literal {
            return "", "", err_literal, false
        }
        if returns.kind != .Single {
            return "", "", Compile_Error{message = "map-indexed transform fn callback requires an explicit single return type", span = callback.span}, false
        }
        return text, returns.single_ty, {}, true
    }
    if callback.kind != .Symbol {
        return "", "", Compile_Error{message = "map-indexed transform currently expects a function symbol or fn literal", span = callback.span}, false
    }
    proc_name := map_name(callback.text)
    proc_decl, ok_proc := find_proc_decl(e, proc_name)
    if !ok_proc {
        return "", "", Compile_Error{message = fmt.tprintf("map-indexed transform must name a known two-argument function: %s", callback.text), span = callback.span}, false
    }
    if len(proc_decl.params) != 2 || proc_decl.params[0].ty != "int" || proc_decl.params[1].ty != input_ty {
        return "", "", Compile_Error{message = fmt.tprintf("map-indexed transform callback must be (fn [int %s] -> T)", input_ty), span = callback.span}, false
    }
    if proc_decl.returns.kind != .Single {
        return "", "", Compile_Error{message = "map-indexed transform callback currently expects a single return value", span = callback.span}, false
    }
    return emit_call_text(proc_name, []string{index_text, input_text}), proc_decl.returns.single_ty, {}, true
}

keep_callback_call :: proc(e: ^Emitter, callback: CST_Form, input_text, input_ty: string) -> (text, value_ty: string, err: Compile_Error, ok: bool) {
    if callback.kind == .List && len(callback.items) > 0 && is_symbol(callback.items[0], "fn") {
        text, returns, err_literal, ok_literal := transform_proc_literal_call(e, callback, []Param{{name = input_text, ty = input_ty}})
        if !ok_literal {
            return "", "", err_literal, false
        }
        if returns.kind != .Named || len(returns.named) != 2 || returns.named[1].ty != "bool" {
            return "", "", Compile_Error{message = "keep transform fn callback must return [value: T ok: bool]", span = callback.span}, false
        }
        return text, returns.named[0].ty, {}, true
    }
    if callback.kind != .Symbol {
        return "", "", Compile_Error{message = "keep transform currently expects a function symbol or fn literal", span = callback.span}, false
    }
    proc_name := map_name(callback.text)
    proc_decl, ok_proc := find_proc_decl(e, proc_name)
    if !ok_proc {
        return "", "", Compile_Error{message = fmt.tprintf("keep transform must name a known one-argument function: %s", callback.text), span = callback.span}, false
    }
    if len(proc_decl.params) != 1 {
        return "", "", Compile_Error{message = "keep transform currently expects a one-argument function", span = callback.span}, false
    }
    if proc_decl.params[0].ty != input_ty {
        return "", "", Compile_Error{message = fmt.tprintf("keep transform callback expects %s but pipeline has %s", proc_decl.params[0].ty, input_ty), span = callback.span}, false
    }
    if proc_decl.returns.kind != .Named || len(proc_decl.returns.named) != 2 || proc_decl.returns.named[1].ty != "bool" {
        return "", "", Compile_Error{message = "keep transform callback must return [value: T ok: bool]", span = callback.span}, false
    }
    return emit_call_text(proc_name, []string{input_text}), proc_decl.returns.named[0].ty, {}, true
}

emit_transform_state_prelude :: proc(e: ^Emitter, builder: ^strings.Builder, steps: []Transform_Step, depth: int) -> (Compile_Error, bool) {
    for step in steps {
        if step.kind != .Take && step.kind != .Drop && step.kind != .Drop_While && step.kind != .Map_Indexed {
            continue
        }
        if step.kind == .Drop_While {
            append_indent(builder, depth)
            fmt.sbprintf(builder, "%s := true\n", step.state_name)
        } else if step.kind == .Map_Indexed {
            append_indent(builder, depth)
            fmt.sbprintf(builder, "%s := 0\n", step.state_name)
        } else {
            limit_text, err_limit, ok_limit := emit_expr(e, step.callback)
            if !ok_limit {
                return err_limit, false
            }
            append_indent(builder, depth)
            fmt.sbprintf(builder, "%s := %s\n", step.state_name, limit_text)
        }
    }
    return {}, true
}

transform_callback_borrows_data_result :: proc(e: ^Emitter, callback: CST_Form) -> bool {
    if callback.kind == .Symbol {
        if strings.has_prefix(callback.text, ".") {
            return true
        }
        return proc_decl_borrowed_view_head(e, callback.text)
    }
    if callback.kind == .List && len(callback.items) > 0 && is_symbol(callback.items[0], "fn") {
        parsed, _, ok := parse_proc_literal_form(callback)
        if !ok || len(parsed.body) == 0 {
            return false
        }
        return !form_produces_owned_managed_type(e, parsed.body[len(parsed.body)-1], "Data")
    }
    return false
}

emit_transform_pipeline_body :: proc(
    e: ^Emitter,
    builder: ^strings.Builder,
    steps: []Transform_Step,
    initial_text, initial_ty: string,
    depth: int,
) -> (value_text, value_ty: string, close_count: int, err: Compile_Error, ok: bool) {
    current_text := initial_text
    current_ty := initial_ty
    current_depth := depth
    inside_mapcat := false
    for step in steps {
        if inside_mapcat && (step.kind == .Take || step.kind == .Take_While) {
            return "", "", 0, Compile_Error{message = "take and take-while after mapcat need cross-loop termination and are not supported yet", span = step.span}, false
        }
        switch step.kind {
        case .Filter:
            pred_text, pred_ty, err_pred, ok_pred := proc_callback_call(e, step.callback, current_text, current_ty)
            if !ok_pred {
                return "", "", 0, err_pred, false
            }
            if pred_ty != "bool" {
                return "", "", 0, Compile_Error{message = fmt.tprintf("filter transform expects bool callback result, got %s", pred_ty), span = step.callback.span}, false
            }
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "if %s %s\n", pred_text, "{")
            current_depth += 1
            close_count += 1
        case .Remove:
            pred_text, pred_ty, err_pred, ok_pred := proc_callback_call(e, step.callback, current_text, current_ty)
            if !ok_pred {
                return "", "", 0, err_pred, false
            }
            if pred_ty != "bool" {
                return "", "", 0, Compile_Error{message = fmt.tprintf("remove transform expects bool callback result, got %s", pred_ty), span = step.callback.span}, false
            }
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "if !(%s) %s\n", pred_text, "{")
            current_depth += 1
            close_count += 1
        case .Keep:
            keep_text, keep_ty, err_keep, ok_keep := keep_callback_call(e, step.callback, current_text, current_ty)
            if !ok_keep {
                return "", "", 0, err_keep, false
            }
            value_temp := transform_temp_name(e)
            ok_temp := transform_temp_name(e)
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "%s, %s := %s\n", value_temp, ok_temp, keep_text)
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "if %s %s\n", ok_temp, "{")
            current_text = value_temp
            current_ty = keep_ty
            current_depth += 1
            close_count += 1
        case .Take:
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "if %s <= 0 %s\n", step.state_name, "{")
            append_indent(builder, current_depth+1)
            strings.write_string(builder, "break\n")
            append_indent(builder, current_depth)
            strings.write_string(builder, "}\n")
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "%s -= 1\n", step.state_name)
        case .Take_While:
            pred_text, pred_ty, err_pred, ok_pred := proc_callback_call(e, step.callback, current_text, current_ty)
            if !ok_pred {
                return "", "", 0, err_pred, false
            }
            if pred_ty != "bool" {
                return "", "", 0, Compile_Error{message = fmt.tprintf("take-while transform expects bool callback result, got %s", pred_ty), span = step.callback.span}, false
            }
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "if !(%s) %s\n", pred_text, "{")
            append_indent(builder, current_depth+1)
            strings.write_string(builder, "break\n")
            append_indent(builder, current_depth)
            strings.write_string(builder, "}\n")
        case .Drop:
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "if %s > 0 %s\n", step.state_name, "{")
            append_indent(builder, current_depth+1)
            fmt.sbprintf(builder, "%s -= 1\n", step.state_name)
            append_indent(builder, current_depth+1)
            strings.write_string(builder, "continue\n")
            append_indent(builder, current_depth)
            strings.write_string(builder, "}\n")
        case .Drop_While:
            pred_text, pred_ty, err_pred, ok_pred := proc_callback_call(e, step.callback, current_text, current_ty)
            if !ok_pred {
                return "", "", 0, err_pred, false
            }
            if pred_ty != "bool" {
                return "", "", 0, Compile_Error{message = fmt.tprintf("drop-while transform expects bool callback result, got %s", pred_ty), span = step.callback.span}, false
            }
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "if %s %s\n", step.state_name, "{")
            append_indent(builder, current_depth+1)
            fmt.sbprintf(builder, "if %s %s\n", pred_text, "{")
            append_indent(builder, current_depth+2)
            strings.write_string(builder, "continue\n")
            append_indent(builder, current_depth+1)
            strings.write_string(builder, "}\n")
            append_indent(builder, current_depth+1)
            fmt.sbprintf(builder, "%s = false\n", step.state_name)
            append_indent(builder, current_depth)
            strings.write_string(builder, "}\n")
        case .Map_Indexed:
            mapped_text, mapped_ty, err_mapped, ok_mapped := indexed_callback_call(e, step.callback, step.state_name, current_text, current_ty)
            if !ok_mapped {
                return "", "", 0, err_mapped, false
            }
            temp := transform_temp_name(e)
            if mapped_ty == "Data" && transform_callback_borrows_data_result(e, step.callback) {
                mapped_text = emit_call_text("kvist_data_retain", []string{mapped_text})
            }
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "%s := %s\n", temp, mapped_text)
            if mapped_ty == "Data" {
                append_indent(builder, current_depth)
                fmt.sbprintf(builder, "defer kvist_data_release(%s)\n", temp)
            }
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "%s += 1\n", step.state_name)
            current_text = temp
            current_ty = mapped_ty
        case .Mapcat:
            mapped_text, mapped_ty, err_mapped, ok_mapped := proc_callback_call(e, step.callback, current_text, current_ty)
            if !ok_mapped {
                return "", "", 0, err_mapped, false
            }
            if type_text_is_dynamic_array(mapped_ty) {
                return "", "", 0, Compile_Error{message = "mapcat transform callback currently expects a borrowed slice or fixed array result, not an owned dynamic array", span = step.callback.span}, false
            }
            inner_ty, ok_inner_ty := collection_element_type(mapped_ty)
            if !ok_inner_ty {
                return "", "", 0, Compile_Error{message = fmt.tprintf("mapcat transform expects array-family callback result, got %s", mapped_ty), span = step.callback.span}, false
            }
            mapped_temp := transform_temp_name(e)
            inner_temp := transform_temp_name(e)
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "%s := %s\n", mapped_temp, mapped_text)
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "for %s in %s %s\n", inner_temp, slice_all_expr_text(mapped_temp), "{")
            current_text = inner_temp
            current_ty = inner_ty
            current_depth += 1
            close_count += 1
            inside_mapcat = true
        case .Map:
            mapped_text, mapped_ty, err_mapped, ok_mapped := proc_callback_call(e, step.callback, current_text, current_ty)
            if !ok_mapped {
                return "", "", 0, err_mapped, false
            }
            temp := transform_temp_name(e)
            if mapped_ty == "Data" && transform_callback_borrows_data_result(e, step.callback) {
                mapped_text = emit_call_text("kvist_data_retain", []string{mapped_text})
            }
            append_indent(builder, current_depth)
            fmt.sbprintf(builder, "%s := %s\n", temp, mapped_text)
            if mapped_ty == "Data" {
                append_indent(builder, current_depth)
                fmt.sbprintf(builder, "defer kvist_data_release(%s)\n", temp)
            }
            current_text = temp
            current_ty = mapped_ty
        }
    }
    return current_text, current_ty, close_count, {}, true
}

emit_transform_closers :: proc(builder: ^strings.Builder, depth, close_count: int) {
    current_depth := depth
    remaining := close_count
    for remaining > 0 {
        current_depth -= 1
        append_indent(builder, current_depth)
        strings.write_string(builder, "}\n")
        remaining -= 1
    }
}

form_contains_reduced :: proc(form: CST_Form) -> bool {
    #partial switch form.kind {
    case .Symbol:
        return form.text == "reduced"
    case .List, .Vector, .Brace, .Set:
        for item in form.items {
            if form_contains_reduced(item) {
                return true
            }
        }
    case:
    }
    return false
}

emit_reduced_branch_update_text :: proc(e: ^Emitter, form: CST_Form, acc_text, acc_ty: string) -> (string, Compile_Error, bool) {
    if form.kind == .List && len(form.items) > 0 && is_symbol(form.items[0], "reduced") {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "reduced expects one value", span = form.span}, false
        }
        value_text, err_value, ok_value := emit_expr_for_expected_type(e, form.items[1], acc_ty)
        if !ok_value {
            return "", err_value, false
        }
        return fmt.tprintf("%s = %s; break", acc_text, value_text), {}, true
    }
    if form_contains_reduced(form) {
        return "", Compile_Error{message = "reduced in transduce fn reducers is currently supported only as a direct reducer branch", span = form.span}, false
    }
    value_text, err_value, ok_value := emit_expr_for_expected_type(e, form, acc_ty)
    if !ok_value {
        return "", err_value, false
    }
    return fmt.tprintf("%s = %s", acc_text, value_text), {}, true
}

emit_reduced_body_update_text :: proc(e: ^Emitter, form: CST_Form, acc_text, acc_ty: string) -> (string, Compile_Error, bool) {
    if form.kind == .List && len(form.items) > 0 && is_symbol(form.items[0], "if") {
        if len(form.items) != 4 {
            return "", Compile_Error{message = "reduced transduce fn reducer if expects test, then, and else", span = form.span}, false
        }
        test_text, err_test, ok_test := emit_expr(e, form.items[1])
        if !ok_test {
            return "", err_test, false
        }
        then_text, err_then, ok_then := emit_reduced_body_update_text(e, form.items[2], acc_text, acc_ty)
        if !ok_then {
            return "", err_then, false
        }
        else_text, err_else, ok_else := emit_reduced_body_update_text(e, form.items[3], acc_text, acc_ty)
        if !ok_else {
            return "", err_else, false
        }
        return fmt.tprintf("if %s %s %s %s else %s %s %s", test_text, "{", then_text, "}", "{", else_text, "}"), {}, true
    }
    if form.kind == .List && len(form.items) > 0 && is_symbol(form.items[0], "let") {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "reduced transduce fn reducer let expects bindings and one body expression", span = form.span}, false
        }
        bindings, err_bind, ok_bind := parse_let_bindings(form.items[1])
        if !ok_bind {
            return "", err_bind, false
        }
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        push_local_type_scope(e)
        defer pop_local_type_scope(e)
        for binding in bindings {
            if binding.is_destructure || binding.is_result_binding || binding.deferred_delete || binding.err_deferred_delete || binding.defer_with_cleanup {
                return "", Compile_Error{message = "reduced transduce fn reducer let supports only simple local bindings", span = binding.target_span}, false
            }
            value_text, err_value, ok_value := emit_expr_for_expected_type(e, binding.value, binding.ty)
            if !ok_value {
                return "", err_value, false
            }
            if is_discard_binding_name(binding.name) {
                fmt.sbprintf(&builder, "_ = %s\n", value_text)
            } else {
                fmt.sbprintf(&builder, "%s := %s\n", binding.name, value_text)
            }
            bind_obvious_binding_types(e, binding)
        }
        body_text, err_body, ok_body := emit_reduced_body_update_text(e, form.items[2], acc_text, acc_ty)
        if !ok_body {
            return "", err_body, false
        }
        strings.write_string(&builder, body_text)
        return strings.clone(strings.to_string(builder)), {}, true
    }
    return emit_reduced_branch_update_text(e, form, acc_text, acc_ty)
}

write_transform_reduce_text :: proc(builder: ^strings.Builder, depth: int, text: string) {
    lines := strings.split_lines(text, context.allocator)
    defer delete(lines)
    for line in lines {
        append_indent(builder, depth)
        strings.write_string(builder, line)
        strings.write_string(builder, "\n")
    }
}

transform_reduced_reduce_update_text :: proc(e: ^Emitter, reducer: CST_Form, acc_text, acc_ty, value_text: string, parsed: Proc_Literal) -> (string, Compile_Error, bool) {
    if len(parsed.body) != 1 {
        return "", Compile_Error{message = "reduced transduce fn reducer currently expects a single body expression", span = reducer.span}, false
    }
    prefix := fmt.tprintf("%s := %s\n%s := %s\n", parsed.params[0].name, acc_text, parsed.params[1].name, value_text)
    body := parsed.body[0]
    body_text, err_body, ok_body := emit_reduced_body_update_text(e, body, acc_text, acc_ty)
    if !ok_body {
        return "", err_body, false
    }
    return fmt.tprintf("%s%s", prefix, body_text), {}, true
}

transform_reduce_update_text :: proc(e: ^Emitter, reducer: CST_Form, acc_text, acc_ty, value_text, value_ty: string) -> (string, Compile_Error, bool) {
	if reducer.kind == .List && len(reducer.items) > 0 && is_symbol(reducer.items[0], "fn") {
        parsed, err_parse, ok_parse := parse_proc_literal_form(reducer)
        if !ok_parse {
            return "", err_parse, false
        }
        if len(parsed.params) != 2 {
            return "", Compile_Error{message = "transduce fn reducer expects 2 parameters", span = reducer.span}, false
        }
        if parsed.params[0].ty != acc_ty {
            return "", Compile_Error{message = fmt.tprintf("transduce fn reducer parameter %s must be %s", parsed.params[0].name, acc_ty), span = reducer.span}, false
        }
        if parsed.params[1].ty != value_ty {
            return "", Compile_Error{message = fmt.tprintf("transduce fn reducer parameter %s must be %s", parsed.params[1].name, value_ty), span = reducer.span}, false
        }
        returns := parsed.returns
		if returns.kind != .Single {
			return "", Compile_Error{message = "transduce fn reducer requires an explicit single return type", span = reducer.span}, false
		}
		if returns.single_ty != acc_ty {
			return "", Compile_Error{message = fmt.tprintf("transduce fn reducer must return %s", acc_ty), span = reducer.span}, false
		}
        if form_contains_reduced(reducer) {
            push_local_type_scope(e)
            bind_local_type(e, parsed.params[0].name, acc_ty)
            bind_local_type(e, parsed.params[1].name, value_ty)
            defer pop_local_type_scope(e)
            return transform_reduced_reduce_update_text(e, reducer, acc_text, acc_ty, value_text, parsed)
        }
		text, _, err_literal, ok_literal := transform_proc_literal_call(e, reducer, []Param{{name = acc_text, ty = acc_ty}, {name = value_text, ty = value_ty}}, "transduce fn reducer")
		if !ok_literal {
			return "", err_literal, false
		}
		return fmt.tprintf("%s = %s", acc_text, text), {}, true
	}
	if reducer.kind != .Symbol {
		return "", Compile_Error{message = "transduce reducer currently expects +, a known two-argument function, or a fn literal", span = reducer.span}, false
	}
    if reducer.text == "+" {
        if acc_ty != value_ty {
            return "", Compile_Error{message = fmt.tprintf("+ reducer expects pipeline value %s to match accumulator %s", value_ty, acc_ty), span = reducer.span}, false
        }
        return fmt.tprintf("%s += %s", acc_text, value_text), {}, true
    }
    if reducer.text == "min" || reducer.text == "max" {
        if acc_ty != value_ty {
            return "", Compile_Error{message = fmt.tprintf("%s reducer expects pipeline value %s to match accumulator %s", reducer.text, value_ty, acc_ty), span = reducer.span}, false
        }
        op := "<"
        if reducer.text == "max" {
            op = ">"
        }
        return fmt.tprintf("if %s %s %s %s %s = %s %s", value_text, op, acc_text, "{", acc_text, value_text, "}"), {}, true
    }
    proc_name := map_name(reducer.text)
    proc_decl, ok_proc := find_proc_decl(e, proc_name)
    if !ok_proc {
        return "", Compile_Error{message = fmt.tprintf("transduce reducer must be +, a known two-argument function, or a fn literal: %s", reducer.text), span = reducer.span}, false
    }
    if len(proc_decl.params) != 2 ||
       proc_decl.params[0].ty != acc_ty ||
       proc_decl.params[1].ty != value_ty ||
       proc_decl.returns.kind != .Single ||
       proc_decl.returns.single_ty != acc_ty {
        return "", Compile_Error{message = fmt.tprintf("transduce reducer must be (fn [%s %s] -> %s)", acc_ty, value_ty, acc_ty), span = reducer.span}, false
    }
    return fmt.tprintf("%s = %s", acc_text, emit_call_text(proc_name, []string{acc_text, value_text})), {}, true
}

emit_transform_into_source_expr :: proc(
    e: ^Emitter,
    form: CST_Form,
    output_ty, output_elem_ty: string,
    transform_form, source_form: CST_Form,
    source: ^Source_Decl,
) -> (string, Compile_Error, bool) {
    state_ty, err_state_ty, ok_state_ty := source_state_type(e, source)
    if !ok_state_ty {
        return "", err_state_ty, false
    }
    err_protocol, ok_protocol := validate_source_protocol(e, source, state_ty, source_form.span)
    if !ok_protocol {
        return "", err_protocol, false
    }
    item_ty, err_item_ty, ok_item_ty := source_call_item_type(e, source, source_form)
    if !ok_item_ty {
        return "", err_item_ty, false
    }
    arg_texts, err_args, ok_args := source_call_arg_texts(e, source, source_form, item_ty)
    if !ok_args {
        return "", err_args, false
    }
    steps, err_steps, ok_steps := parse_transform_steps(e, transform_form)
    if !ok_steps {
        return "", err_steps, false
    }
	captures, err_captures, ok_captures := transform_step_capture_params(e, steps[:])
	if !ok_captures {
		return "", err_captures, false
	}
	builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    param_texts: [dynamic]string
    call_arg_texts: [dynamic]string
    call_texts: [dynamic]string
    defer delete(param_texts)
    defer delete(call_arg_texts)
    defer delete(call_texts)
    for capture in captures {
        append(&param_texts, fmt.tprintf("%s: %s", capture.name, capture.ty))
        append(&call_texts, capture.name)
    }
    for param, idx in source.params {
        arg_name := fmt.tprintf("kvist_source_arg_%d", idx+1)
        param_ty := source_param_type_for_item(param.ty, source.item_ty, item_ty)
        append(&param_texts, fmt.tprintf("%s: %s", arg_name, param_ty))
        append(&call_arg_texts, arg_name)
    }
    for arg_text in arg_texts {
        append(&call_texts, arg_text)
    }
    param_list := strings.join(param_texts[:], ", ", context.allocator)
    defer delete(param_list)
    call_args := strings.join(call_texts[:], ", ", context.allocator)
    defer delete(call_args)
    open_call := source_call_text(e, source, call_arg_texts[:])

    fmt.sbprintf(&builder, "(proc(%s) -> %s %s\n", param_list, output_ty, "{")
    fmt.sbprintf(&builder, "    kvist_source := %s\n", open_call)
    if source.has_dispose {
        fmt.sbprintf(&builder, "    defer %s(&kvist_source)\n", source.dispose_name)
    }
    fmt.sbprintf(&builder, "    kvist_out := make(%s)\n", output_ty)
    err_prelude, ok_prelude := emit_transform_state_prelude(e, &builder, steps[:], 1)
    if !ok_prelude {
        return "", err_prelude, false
    }
    strings.write_string(&builder, "    for {\n")
    fmt.sbprintf(&builder, "        kvist_item, kvist_source_ok := %s(&kvist_source)\n", source.next_name)
    strings.write_string(&builder, "        if !kvist_source_ok {\n")
    strings.write_string(&builder, "            break\n")
    strings.write_string(&builder, "        }\n")
    value_text, value_ty, close_count, err_body, ok_body := emit_transform_pipeline_body(e, &builder, steps[:], "kvist_item", item_ty, 2)
    if !ok_body {
        return "", err_body, false
    }
    if value_ty != output_elem_ty {
        return "", Compile_Error{message = fmt.tprintf("into transform output element type is %s, but pipeline produces %s", output_elem_ty, value_ty), span = form.items[1].span}, false
    }
    append_indent(&builder, 2+close_count)
    fmt.sbprintf(&builder, "append(&kvist_out, %s)\n", value_text)
    emit_transform_closers(&builder, 2+close_count, close_count)
    strings.write_string(&builder, "    }\n")
    strings.write_string(&builder, "    return kvist_out\n")
    strings.write_string(&builder, "})")
    return fmt.tprintf("%s(%s)", strings.to_string(builder), call_args), {}, true
}

emit_transform_into_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) < 4 {
        return "", Compile_Error{message = "into transform expects output type, transform, and source", span = form.span}, false
    }
    output_ty, next_i, err_output_ty, ok_output_ty := parse_type_text_from_forms(form.items[:], 1)
    if !ok_output_ty {
        return "", err_output_ty, false
    }
    if next_i+2 != len(form.items) {
        return "", Compile_Error{message = "into transform expects output type, transform, and source", span = form.span}, false
    }
    transform_form := form.items[next_i]
    source_form := form.items[next_i+1]
    output_spec, err_output_spec, ok_output_spec := transform_into_output_spec(output_ty)
    if !ok_output_spec {
        err_output_spec.span = form.items[1].span
        return "", err_output_spec, false
    }
    if source, ok_source_call := source_call_decl(e, source_form); ok_source_call {
        if output_spec.kind != .Dynamic_Array {
            return "", Compile_Error{message = "into transform over defiter sources currently expects a dynamic array output type", span = form.items[1].span}, false
        }
        return emit_transform_into_source_expr(e, form, output_ty, output_spec.value_ty, transform_form, source_form, source)
    }
    source_ty := ""
    source_elem_ty := ""
    source_text := ""
    loop_source_spec: Transform_Loop_Source
    source_is_loop_source := form_is_transform_loop_call(source_form)
    if source_is_loop_source {
        spec, err_loop, ok_loop := transform_loop_source(e, source_form)
        if !ok_loop {
            return "", err_loop, false
        }
        loop_source_spec = spec
        source_ty = spec.source_ty
        source_elem_ty = spec.item_ty
        source_text = spec.source_text
    } else {
        ok_source_ty := false
        source_ty, ok_source_ty = obvious_form_type(e, source_form)
        if !ok_source_ty {
            return "", Compile_Error{message = "into transform expects a source with an obvious collection type; bind or annotate it first", span = source_form.span}, false
        }
        ok_source_elem_ty := false
        source_elem_ty, ok_source_elem_ty = transform_source_value_type(source_ty)
        if !ok_source_elem_ty {
            return "", Compile_Error{message = fmt.tprintf("into transform expects slice, array, or map source, got %s", source_ty), span = source_form.span}, false
        }
        err_source: Compile_Error
        ok_source := false
        source_text, err_source, ok_source = emit_expr(e, source_form)
        if !ok_source {
            return "", err_source, false
        }
    }
    steps, err_steps, ok_steps := parse_transform_steps(e, transform_form)
    if !ok_steps {
        return "", err_steps, false
    }
	captures, err_captures, ok_captures := transform_step_capture_params(e, steps[:])
	if !ok_captures {
		return "", err_captures, false
	}

	builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    param_texts: [dynamic]string
    call_texts: [dynamic]string
    defer delete(param_texts)
    defer delete(call_texts)
    for capture in captures {
        append(&param_texts, fmt.tprintf("%s: %s", capture.name, capture.ty))
        append(&call_texts, capture.name)
    }
    append(&param_texts, fmt.tprintf("kvist_source: %s", source_ty))
    append(&call_texts, source_text)
    param_list := strings.join(param_texts[:], ", ", context.allocator)
    defer delete(param_list)
    call_args := strings.join(call_texts[:], ", ", context.allocator)
    defer delete(call_args)
    fmt.sbprintf(&builder, "(proc(%s) -> %s %s\n", param_list, output_ty, "{")
    capacity_text := transform_source_count_text(source_ty, "kvist_source")
    fmt.sbprintf(&builder, "    kvist_out := %s\n", transform_into_make_text(output_spec, capacity_text))
    if output_spec.kind == .Data_Vector {
        mark_data_type(e)
        strings.write_string(&builder, "    defer { for kvist_value in kvist_out { kvist_data_release(kvist_value) }; delete(kvist_out) }\n")
    }
    err_prelude, ok_prelude := emit_transform_state_prelude(e, &builder, steps[:], 1)
    if !ok_prelude {
        return "", err_prelude, false
    }
    if source_is_loop_source {
        emit_transform_loop_source_open(&builder, 1, "kvist_item", "kvist_source", loop_source_spec)
    } else {
        fmt.sbprintf(&builder, "    %s\n", transform_source_loop_header(source_ty, "kvist_source", ""))
    }
    value_text, value_ty, close_count, err_body, ok_body := emit_transform_pipeline_body(e, &builder, steps[:], "kvist_item", source_elem_ty, 2)
    if !ok_body {
        return "", err_body, false
    }
    if !transform_into_output_accepts_value(output_spec, value_ty) {
        return "", Compile_Error{message = fmt.tprintf("into transform output value type is %s, but pipeline produces %s", transform_into_output_value_description(output_spec), value_ty), span = form.items[1].span}, false
    }
    emit_transform_into_output_write(&builder, 2+close_count, output_spec, value_text)
    emit_transform_closers(&builder, 2+close_count, close_count)
    strings.write_string(&builder, "    }\n")
    fmt.sbprintf(&builder, "    return %s\n", transform_into_finalize_text(output_spec))
    strings.write_string(&builder, "})")
    return fmt.tprintf("%s(%s)", strings.to_string(builder), call_args), {}, true
}

emit_transform_into_bang_source_expr :: proc(
    e: ^Emitter,
    form: CST_Form,
    target_ty, target_elem_ty, target_text: string,
    transform_form, source_form: CST_Form,
    source: ^Source_Decl,
) -> (string, Compile_Error, bool) {
    state_ty, err_state_ty, ok_state_ty := source_state_type(e, source)
    if !ok_state_ty {
        return "", err_state_ty, false
    }
    err_protocol, ok_protocol := validate_source_protocol(e, source, state_ty, source_form.span)
    if !ok_protocol {
        return "", err_protocol, false
    }
    item_ty, err_item_ty, ok_item_ty := source_call_item_type(e, source, source_form)
    if !ok_item_ty {
        return "", err_item_ty, false
    }
    arg_texts, err_args, ok_args := source_call_arg_texts(e, source, source_form, item_ty)
    if !ok_args {
        return "", err_args, false
    }
    steps, err_steps, ok_steps := parse_transform_steps(e, transform_form)
    if !ok_steps {
        return "", err_steps, false
    }
	captures, err_captures, ok_captures := transform_step_capture_params(e, steps[:])
	if !ok_captures {
		return "", err_captures, false
	}

	builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    param_texts: [dynamic]string
    call_arg_texts: [dynamic]string
    call_texts: [dynamic]string
    defer delete(param_texts)
    defer delete(call_arg_texts)
    defer delete(call_texts)
    append(&param_texts, fmt.tprintf("kvist_out: ^%s", target_ty))
    append(&call_texts, address_of_expr_text(target_text))
    for capture in captures {
        append(&param_texts, fmt.tprintf("%s: %s", capture.name, capture.ty))
        append(&call_texts, capture.name)
    }
    for param, idx in source.params {
        arg_name := fmt.tprintf("kvist_source_arg_%d", idx+1)
        param_ty := source_param_type_for_item(param.ty, source.item_ty, item_ty)
        append(&param_texts, fmt.tprintf("%s: %s", arg_name, param_ty))
        append(&call_arg_texts, arg_name)
    }
    for arg_text in arg_texts {
        append(&call_texts, arg_text)
    }
    param_list := strings.join(param_texts[:], ", ", context.allocator)
    defer delete(param_list)
    call_args := strings.join(call_texts[:], ", ", context.allocator)
    defer delete(call_args)
    open_call := source_call_text(e, source, call_arg_texts[:])

    fmt.sbprintf(&builder, "(proc(%s) %s\n", param_list, "{")
    fmt.sbprintf(&builder, "    kvist_source := %s\n", open_call)
    if source.has_dispose {
        fmt.sbprintf(&builder, "    defer %s(&kvist_source)\n", source.dispose_name)
    }
    err_prelude, ok_prelude := emit_transform_state_prelude(e, &builder, steps[:], 1)
    if !ok_prelude {
        return "", err_prelude, false
    }
    strings.write_string(&builder, "    for {\n")
    fmt.sbprintf(&builder, "        kvist_item, kvist_source_ok := %s(&kvist_source)\n", source.next_name)
    strings.write_string(&builder, "        if !kvist_source_ok {\n")
    strings.write_string(&builder, "            break\n")
    strings.write_string(&builder, "        }\n")
    value_text, value_ty, close_count, err_body, ok_body := emit_transform_pipeline_body(e, &builder, steps[:], "kvist_item", item_ty, 2)
    if !ok_body {
        return "", err_body, false
    }
    if value_ty != target_elem_ty {
        return "", Compile_Error{message = fmt.tprintf("into! transform target element type is %s, but pipeline produces %s", target_elem_ty, value_ty), span = form.items[1].span}, false
    }
    append_indent(&builder, 2+close_count)
    fmt.sbprintf(&builder, "append(kvist_out, %s)\n", value_text)
    emit_transform_closers(&builder, 2+close_count, close_count)
    strings.write_string(&builder, "    }\n")
    strings.write_string(&builder, "})")
    return fmt.tprintf("%s(%s)", strings.to_string(builder), call_args), {}, true
}

emit_transform_into_bang_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 4 {
        return "", Compile_Error{message = "into! transform expects target, transform, and source", span = form.span}, false
    }
    target_form := form.items[1]
    transform_form := form.items[2]
    source_form := form.items[3]
    target_ty, ok_target_ty := obvious_form_type(e, target_form)
    if !ok_target_ty {
        return "", Compile_Error{message = "into! transform expects a target with an obvious dynamic array type; bind or annotate it first", span = target_form.span}, false
    }
    target_elem_ty, ok_target_elem_ty := dynamic_array_element_type(target_ty)
    if !ok_target_elem_ty {
        return "", Compile_Error{message = "into! transform currently expects a dynamic array target", span = target_form.span}, false
    }
    target_text, err_target, ok_target := emit_expr(e, target_form)
    if !ok_target {
        return "", err_target, false
    }
    if source, ok_source_call := source_call_decl(e, source_form); ok_source_call {
        return emit_transform_into_bang_source_expr(e, form, target_ty, target_elem_ty, target_text, transform_form, source_form, source)
    }
    source_ty := ""
    source_elem_ty := ""
    source_text := ""
    loop_source_spec: Transform_Loop_Source
    source_is_loop_source := form_is_transform_loop_call(source_form)
    if source_is_loop_source {
        spec, err_loop, ok_loop := transform_loop_source(e, source_form)
        if !ok_loop {
            return "", err_loop, false
        }
        loop_source_spec = spec
        source_ty = spec.source_ty
        source_elem_ty = spec.item_ty
        source_text = spec.source_text
    } else {
        ok_source_ty := false
        source_ty, ok_source_ty = obvious_form_type(e, source_form)
        if !ok_source_ty {
            return "", Compile_Error{message = "into! transform expects a source with an obvious collection type; bind or annotate it first", span = source_form.span}, false
        }
        ok_source_elem_ty := false
        source_elem_ty, ok_source_elem_ty = transform_source_value_type(source_ty)
        if !ok_source_elem_ty {
            return "", Compile_Error{message = fmt.tprintf("into! transform expects slice, array, or map source, got %s", source_ty), span = source_form.span}, false
        }
        err_source: Compile_Error
        ok_source := false
        source_text, err_source, ok_source = emit_expr(e, source_form)
        if !ok_source {
            return "", err_source, false
        }
    }
    steps, err_steps, ok_steps := parse_transform_steps(e, transform_form)
    if !ok_steps {
        return "", err_steps, false
    }
	captures, err_captures, ok_captures := transform_step_capture_params(e, steps[:])
	if !ok_captures {
		return "", err_captures, false
	}

	builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    param_texts: [dynamic]string
    call_texts: [dynamic]string
    defer delete(param_texts)
    defer delete(call_texts)
    append(&param_texts, fmt.tprintf("kvist_out: ^%s", target_ty))
    append(&call_texts, address_of_expr_text(target_text))
    for capture in captures {
        append(&param_texts, fmt.tprintf("%s: %s", capture.name, capture.ty))
        append(&call_texts, capture.name)
    }
    append(&param_texts, fmt.tprintf("kvist_source: %s", source_ty))
    append(&call_texts, source_text)
    param_list := strings.join(param_texts[:], ", ", context.allocator)
    defer delete(param_list)
    call_args := strings.join(call_texts[:], ", ", context.allocator)
    defer delete(call_args)
    fmt.sbprintf(&builder, "(proc(%s) %s\n", param_list, "{")
    err_prelude, ok_prelude := emit_transform_state_prelude(e, &builder, steps[:], 1)
    if !ok_prelude {
        return "", err_prelude, false
    }
    if source_is_loop_source {
        emit_transform_loop_source_open(&builder, 1, "kvist_item", "kvist_source", loop_source_spec)
    } else {
        fmt.sbprintf(&builder, "    %s\n", transform_source_loop_header(source_ty, "kvist_source", ""))
    }
    value_text, value_ty, close_count, err_body, ok_body := emit_transform_pipeline_body(e, &builder, steps[:], "kvist_item", source_elem_ty, 2)
    if !ok_body {
        return "", err_body, false
    }
    if value_ty != target_elem_ty {
        return "", Compile_Error{message = fmt.tprintf("into! transform target element type is %s, but pipeline produces %s", target_elem_ty, value_ty), span = target_form.span}, false
    }
    append_indent(&builder, 2+close_count)
    fmt.sbprintf(&builder, "append(kvist_out, %s)\n", value_text)
    emit_transform_closers(&builder, 2+close_count, close_count)
    strings.write_string(&builder, "    }\n")
    strings.write_string(&builder, "})")
    return fmt.tprintf("%s(%s)", strings.to_string(builder), call_args), {}, true
}

emit_transform_transduce_source_expr :: proc(
	e: ^Emitter,
	form: CST_Form,
	transform_form: CST_Form,
	reducer: CST_Form,
    init_text, acc_ty: string,
    source_form: CST_Form,
    source: ^Source_Decl,
) -> (string, Compile_Error, bool) {
    state_ty, err_state_ty, ok_state_ty := source_state_type(e, source)
    if !ok_state_ty {
        return "", err_state_ty, false
    }
    err_protocol, ok_protocol := validate_source_protocol(e, source, state_ty, source_form.span)
    if !ok_protocol {
        return "", err_protocol, false
    }
    item_ty, err_item_ty, ok_item_ty := source_call_item_type(e, source, source_form)
    if !ok_item_ty {
        return "", err_item_ty, false
    }
    arg_texts, err_args, ok_args := source_call_arg_texts(e, source, source_form, item_ty)
    if !ok_args {
        return "", err_args, false
    }
    steps, err_steps, ok_steps := parse_transform_steps(e, transform_form)
    if !ok_steps {
        return "", err_steps, false
    }
	captures, err_captures, ok_captures := transform_step_capture_params(e, steps[:])
	if !ok_captures {
		return "", err_captures, false
	}
	reducer_captures, err_reducer_captures, ok_reducer_captures := transform_fn_capture_params(e, reducer)
	if !ok_reducer_captures {
		return "", err_reducer_captures, false
	}
	defer delete(reducer_captures)
	for capture in reducer_captures {
		append_capture_param_unique(&captures, capture)
	}

	builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    param_texts: [dynamic]string
    call_arg_texts: [dynamic]string
    call_args_texts: [dynamic]string
    defer delete(param_texts)
    defer delete(call_arg_texts)
    defer delete(call_args_texts)
    for capture in captures {
        append(&param_texts, fmt.tprintf("%s: %s", capture.name, capture.ty))
        append(&call_args_texts, capture.name)
    }
    for param, idx in source.params {
        arg_name := fmt.tprintf("kvist_source_arg_%d", idx+1)
        param_ty := source_param_type_for_item(param.ty, source.item_ty, item_ty)
        append(&param_texts, fmt.tprintf("%s: %s", arg_name, param_ty))
        append(&call_arg_texts, arg_name)
    }
    append(&param_texts, fmt.tprintf("kvist_init: %s", acc_ty))
    for arg_text in arg_texts {
        append(&call_args_texts, arg_text)
    }
    append(&call_args_texts, init_text)
    param_list := strings.join(param_texts[:], ", ", context.allocator)
    defer delete(param_list)
    call_args := strings.join(call_args_texts[:], ", ", context.allocator)
    defer delete(call_args)
    open_call := source_call_text(e, source, call_arg_texts[:])

    fmt.sbprintf(&builder, "(proc(%s) -> %s %s\n", param_list, acc_ty, "{")
    fmt.sbprintf(&builder, "    kvist_source := %s\n", open_call)
    if source.has_dispose {
        fmt.sbprintf(&builder, "    defer %s(&kvist_source)\n", source.dispose_name)
    }
    strings.write_string(&builder, "    kvist_acc := kvist_init\n")
    err_prelude, ok_prelude := emit_transform_state_prelude(e, &builder, steps[:], 1)
    if !ok_prelude {
        return "", err_prelude, false
    }
    strings.write_string(&builder, "    for {\n")
    fmt.sbprintf(&builder, "        kvist_item, kvist_source_ok := %s(&kvist_source)\n", source.next_name)
    strings.write_string(&builder, "        if !kvist_source_ok {\n")
    strings.write_string(&builder, "            break\n")
    strings.write_string(&builder, "        }\n")
    value_text, value_ty, close_count, err_body, ok_body := emit_transform_pipeline_body(e, &builder, steps[:], "kvist_item", item_ty, 2)
    if !ok_body {
        return "", err_body, false
    }
    reduce_text, err_reduce, ok_reduce := transform_reduce_update_text(e, reducer, "kvist_acc", acc_ty, value_text, value_ty)
    if !ok_reduce {
        return "", err_reduce, false
    }
    write_transform_reduce_text(&builder, 2+close_count, reduce_text)
    emit_transform_closers(&builder, 2+close_count, close_count)
    strings.write_string(&builder, "    }\n")
    strings.write_string(&builder, "    return kvist_acc\n")
    strings.write_string(&builder, "})")
    return fmt.tprintf("%s(%s)", strings.to_string(builder), call_args), {}, true
}

emit_transform_transduce_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) != 5 {
        return "", Compile_Error{message = "transduce expects transform, reducer, init, and source", span = form.span}, false
    }
    reducer := form.items[2]
    acc_ty, ok_acc_ty := obvious_form_type(e, form.items[3])
    if !ok_acc_ty {
        return "", Compile_Error{message = "transduce expects an init value with an obvious accumulator type; bind or annotate it first", span = form.items[3].span}, false
    }
    init_text, err_init, ok_init := emit_expr_for_expected_type(e, form.items[3], acc_ty)
    if !ok_init {
        return "", err_init, false
    }
    if source, ok_source_call := source_call_decl(e, form.items[4]); ok_source_call {
        return emit_transform_transduce_source_expr(e, form, form.items[1], reducer, init_text, acc_ty, form.items[4], source)
    }
    source_ty := ""
    source_elem_ty := ""
    source_text := ""
    loop_source_spec: Transform_Loop_Source
    source_is_loop_source := form_is_transform_loop_call(form.items[4])
    if source_is_loop_source {
        spec, err_loop, ok_loop := transform_loop_source(e, form.items[4])
        if !ok_loop {
            return "", err_loop, false
        }
        loop_source_spec = spec
        source_ty = spec.source_ty
        source_elem_ty = spec.item_ty
        source_text = spec.source_text
    } else {
        ok_source_ty := false
        source_ty, ok_source_ty = obvious_form_type(e, form.items[4])
        if !ok_source_ty {
            return "", Compile_Error{message = "transduce expects a source with an obvious collection type; bind or annotate it first", span = form.items[4].span}, false
        }
        ok_source_elem_ty := false
        source_elem_ty, ok_source_elem_ty = transform_source_value_type(source_ty)
        if !ok_source_elem_ty {
            return "", Compile_Error{message = fmt.tprintf("transduce expects slice, array, or map source, got %s", source_ty), span = form.items[4].span}, false
        }
        err_source: Compile_Error
        ok_source := false
        source_text, err_source, ok_source = emit_expr(e, form.items[4])
        if !ok_source {
            return "", err_source, false
        }
    }
    steps, err_steps, ok_steps := parse_transform_steps(e, form.items[1])
    if !ok_steps {
        return "", err_steps, false
    }
	captures, err_captures, ok_captures := transform_step_capture_params(e, steps[:])
	if !ok_captures {
		return "", err_captures, false
	}
	reducer_captures, err_reducer_captures, ok_reducer_captures := transform_fn_capture_params(e, reducer)
	if !ok_reducer_captures {
		return "", err_reducer_captures, false
	}
	defer delete(reducer_captures)
	for capture in reducer_captures {
		append_capture_param_unique(&captures, capture)
	}

	builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    param_texts: [dynamic]string
    call_texts: [dynamic]string
    defer delete(param_texts)
    defer delete(call_texts)
    for capture in captures {
        append(&param_texts, fmt.tprintf("%s: %s", capture.name, capture.ty))
        append(&call_texts, capture.name)
    }
    append(&param_texts, fmt.tprintf("kvist_source: %s", source_ty))
    append(&param_texts, fmt.tprintf("kvist_init: %s", acc_ty))
    append(&call_texts, source_text)
    append(&call_texts, init_text)
    param_list := strings.join(param_texts[:], ", ", context.allocator)
    defer delete(param_list)
    call_args := strings.join(call_texts[:], ", ", context.allocator)
    defer delete(call_args)
    fmt.sbprintf(&builder, "(proc(%s) -> %s %s\n", param_list, acc_ty, "{")
    strings.write_string(&builder, "    kvist_acc := kvist_init\n")
    err_prelude, ok_prelude := emit_transform_state_prelude(e, &builder, steps[:], 1)
    if !ok_prelude {
        return "", err_prelude, false
    }
    if source_is_loop_source {
        emit_transform_loop_source_open(&builder, 1, "kvist_item", "kvist_source", loop_source_spec)
    } else {
        fmt.sbprintf(&builder, "    %s\n", transform_source_loop_header(source_ty, "kvist_source", ""))
    }
    value_text, value_ty, close_count, err_body, ok_body := emit_transform_pipeline_body(e, &builder, steps[:], "kvist_item", source_elem_ty, 2)
    if !ok_body {
        return "", err_body, false
    }
    reduce_text, err_reduce, ok_reduce := transform_reduce_update_text(e, reducer, "kvist_acc", acc_ty, value_text, value_ty)
    if !ok_reduce {
        return "", err_reduce, false
    }
    write_transform_reduce_text(&builder, 2+close_count, reduce_text)
    emit_transform_closers(&builder, 2+close_count, close_count)
    strings.write_string(&builder, "    }\n")
    strings.write_string(&builder, "    return kvist_acc\n")
    strings.write_string(&builder, "})")
    return fmt.tprintf("%s(%s)", strings.to_string(builder), call_args), {}, true
}

captured_thread_callback_params :: proc(e: ^Emitter, ctx: ^Callback_Context) -> (params: [dynamic]Param, err: Compile_Error, ok: bool) {
    for capture_name, idx in ctx.capture_names {
        ty, ok_ty := lookup_local_type(e, capture_name)
        if !ok_ty {
            ty = fmt.tprintf("C%d", idx+1)
        }
        append(&params, Param{name = capture_name, ty = ty})
    }
    return params, Compile_Error{}, true
}

specialize_thread_worker_for_callback_contexts :: proc(e: ^Emitter, worker_name: string, params: []Param, args: []CST_Form, emit_callback: bool) -> (specialized_worker: string, specialized_params: [dynamic]Param, err: Compile_Error, ok: bool) {
    specialized_worker = worker_name
    specialized_index := -1
    capture_count := 0

    for param, idx in params {
        append(&specialized_params, param)
        if idx >= len(args) || !type_text_is_proc(param.ty) || args[idx].kind != .Symbol {
            continue
        }
        arg_name := map_name(args[idx].text)
        ctx, ok_context := lookup_callback_context(e, arg_name)
        if !ok_context || len(ctx.capture_names) == 0 || ctx.field_selector != "" {
            continue
        }
        if specialized_index >= 0 {
            return specialized_worker, specialized_params, Compile_Error{message = "thread-start currently supports one captured callback argument per worker"}, false
        }
        inserted_ty, ok_insert := proc_type_insert_capture_params_text(param.ty, len(ctx.capture_names))
        if !ok_insert {
            return specialized_worker, specialized_params, Compile_Error{message = fmt.tprintf("thread worker parameter %s is not a proc type", param.name)}, false
        }
        specialized_params[len(specialized_params)-1].ty = inserted_ty
        callback_params, err_params, ok_params := captured_thread_callback_params(e, ctx)
        if !ok_params {
            return specialized_worker, specialized_params, err_params, false
        }
        for callback_param in callback_params {
            append(&specialized_params, callback_param)
        }
        specialized_index = idx
        capture_count = len(ctx.capture_names)
    }

    if specialized_index >= 0 {
        if emit_callback {
            mark_captured_proc_specialization(e, worker_name, specialized_index, capture_count)
        }
        specialized_worker = captured_specialization_name(worker_name, specialized_index, capture_count)
    }
    return specialized_worker, specialized_params, Compile_Error{}, true
}

thread_start_signature :: proc(e: ^Emitter, form: CST_Form, emit_callback := false) -> (spec: Thread_Start_Spec, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 {
        return spec, Compile_Error{message = "thread-start expects task type and worker function", span = form.span}, false
    }
    task_form := form.items[1]
    if task_form.kind != .Symbol {
        return spec, Compile_Error{message = "thread-start task type must be a type constructor symbol", span = task_form.span}, false
    }
    task_ty := map_name(task_form.text)
    worker_form := form.items[2]
    if worker_form.kind == .Symbol {
        worker_name, worker_decl, ok_worker := resolve_proc_call_decl(e, worker_form.text)
        if !ok_worker {
            return spec, Compile_Error{message = fmt.tprintf("thread-start worker must name a known function: %s", worker_form.text), span = worker_form.span}, false
        }
        arg_count := len(form.items) - 3
        if arg_count != len(worker_decl.params) {
            return spec, Compile_Error{message = fmt.tprintf("thread-start worker %s expects %d arguments, got %d", worker_form.text, len(worker_decl.params), arg_count), span = form.span}, false
        }
        params, returns, ok_signature := proc_decl_specialized_signature_for_args(e, worker_decl, form.items[3:])
        if !ok_signature {
            return spec, Compile_Error{message = fmt.tprintf("thread-start worker %s generic types could not be inferred from arguments", worker_form.text), span = form.span}, false
        }
        if returns.kind != .Single {
            return spec, Compile_Error{message = "thread-start worker must return exactly one value", span = worker_form.span}, false
        }
        specialized_worker, specialized_params, err_specialized, ok_specialized := specialize_thread_worker_for_callback_contexts(e, worker_name, params[:], form.items[3:], emit_callback)
        if !ok_specialized {
            return spec, err_specialized, false
        }
        return Thread_Start_Spec{
            worker    = specialized_worker,
            task_ty   = task_ty,
            params    = specialized_params[:],
            result_ty = returns.single_ty,
        }, {}, true
    }

    if worker_form.kind == .List && len(worker_form.items) > 0 && is_symbol(worker_form.items[0], "fn") {
        parsed, err_parse, ok_parse := parse_proc_literal_form(worker_form)
        if !ok_parse {
            return spec, err_parse, false
        }
        arg_count := len(form.items) - 3
        if arg_count != len(parsed.params) {
            return spec, Compile_Error{message = fmt.tprintf("thread-start inline worker expects %d arguments, got %d", len(parsed.params), arg_count), span = form.span}, false
        }
        if parsed.returns.kind != .Single {
            return spec, Compile_Error{message = "thread-start inline worker must return exactly one value", span = worker_form.span}, false
        }
        param_names: [dynamic]string
        for param in parsed.params {
            append(&param_names, param.name)
        }
        captures := collect_proc_literal_captures(e, parsed.body[:], param_names[:])
        callback_proc := ""
        if emit_callback {
            params: [dynamic]Param
            for capture in captures {
                append(&params, capture)
            }
            for param in parsed.params {
                append(&params, param)
            }
            text, err_proc, ok_proc := emit_proc_literal_text(e, params[:], parsed.returns, parsed.body[:])
            if !ok_proc {
                return spec, err_proc, false
            }
            callback_proc = text
        }
        return Thread_Start_Spec{
            worker        = parallel_inline_worker_name(worker_form),
            task_ty       = task_ty,
            params        = parsed.params[:],
            result_ty     = parsed.returns.single_ty,
            captures      = captures[:],
            callback_proc = callback_proc,
        }, {}, true
    }

    return spec, Compile_Error{message = "thread-start expects a known worker function or inline fn", span = worker_form.span}, false
}

thread_detach_signature :: proc(e: ^Emitter, form: CST_Form, emit_callback := false) -> (spec: Thread_Detach_Spec, err: Compile_Error, ok: bool) {
    if len(form.items) < 2 {
        return spec, Compile_Error{message = "thread-detach expects a worker function", span = form.span}, false
    }
    worker_form := form.items[1]
    if worker_form.kind == .Symbol {
        worker_name, worker_decl, ok_worker := resolve_proc_call_decl(e, worker_form.text)
        if !ok_worker {
            return spec, Compile_Error{message = fmt.tprintf("thread-detach worker must name a known function: %s", worker_form.text), span = worker_form.span}, false
        }
        arg_count := len(form.items) - 2
        if arg_count != len(worker_decl.params) {
            return spec, Compile_Error{message = fmt.tprintf("thread-detach worker %s expects %d arguments, got %d", worker_form.text, len(worker_decl.params), arg_count), span = form.span}, false
        }
        params, returns, ok_signature := proc_decl_specialized_signature_for_args(e, worker_decl, form.items[2:])
        if !ok_signature {
            return spec, Compile_Error{message = fmt.tprintf("thread-detach worker %s generic types could not be inferred from arguments", worker_form.text), span = form.span}, false
        }
        if returns.kind != .None {
            return spec, Compile_Error{message = "thread-detach worker must not return a value", span = worker_form.span}, false
        }
        specialized_worker, specialized_params, err_specialized, ok_specialized := specialize_thread_worker_for_callback_contexts(e, worker_name, params[:], form.items[2:], emit_callback)
        if !ok_specialized {
            return spec, err_specialized, false
        }
        return Thread_Detach_Spec{
            worker = specialized_worker,
            params = specialized_params[:],
        }, {}, true
    }

    if worker_form.kind == .List && len(worker_form.items) > 0 && is_symbol(worker_form.items[0], "fn") {
        parsed, err_parse, ok_parse := parse_proc_literal_form(worker_form)
        if !ok_parse {
            return spec, err_parse, false
        }
        arg_count := len(form.items) - 2
        if arg_count != len(parsed.params) {
            return spec, Compile_Error{message = fmt.tprintf("thread-detach inline worker expects %d arguments, got %d", len(parsed.params), arg_count), span = form.span}, false
        }
        if parsed.returns.kind != .None {
            return spec, Compile_Error{message = "thread-detach inline worker must not return a value", span = worker_form.span}, false
        }
        param_names: [dynamic]string
        for param in parsed.params {
            append(&param_names, param.name)
        }
        captures := collect_proc_literal_captures(e, parsed.body[:], param_names[:])
        callback_proc := ""
        if emit_callback {
            params: [dynamic]Param
            for capture in captures {
                append(&params, capture)
            }
            for param in parsed.params {
                append(&params, param)
            }
            text, err_proc, ok_proc := emit_proc_literal_text(e, params[:], parsed.returns, parsed.body[:])
            if !ok_proc {
                return spec, err_proc, false
            }
            callback_proc = text
        }
        return Thread_Detach_Spec{
            worker        = parallel_inline_worker_name(worker_form),
            params        = parsed.params[:],
            captures      = captures[:],
            callback_proc = callback_proc,
        }, {}, true
    }

    return spec, Compile_Error{message = "thread-detach expects a known worker function or inline fn", span = worker_form.span}, false
}

parallel_inline_worker_name :: proc(worker_form: CST_Form) -> string {
    return fmt.tprintf("inline_%d_%d", worker_form.span.start, worker_form.span.end)
}

emit_parallel_args_for_params :: proc(e: ^Emitter, args: []CST_Form, params: []Param) -> (arg_texts: [dynamic]string, err: Compile_Error, ok: bool) {
    param_idx := 0
    for arg in args {
        if param_idx >= len(params) {
            return arg_texts, Compile_Error{message = "too many thread worker arguments"}, false
        }
        expected_ty := params[param_idx].ty
        arg_text, err_arg, ok_arg := emit_expr_for_expected_type(e, arg, expected_ty)
        if !ok_arg {
            return arg_texts, err_arg, false
        }
        append(&arg_texts, arg_text)
        param_idx += 1

        if type_text_is_proc(expected_ty) && arg.kind == .Symbol {
            arg_name := map_name(arg.text)
            if ctx, ok_context := lookup_callback_context(e, arg_name); ok_context && len(ctx.capture_names) > 0 && ctx.field_selector == "" {
                for capture_name in ctx.capture_names {
                    if param_idx >= len(params) || params[param_idx].name != capture_name {
                        return arg_texts, Compile_Error{message = "internal error: thread worker capture parameter mismatch", span = arg.span}, false
                    }
                    append(&arg_texts, capture_name)
                    param_idx += 1
                }
            }
        }
    }
    if param_idx != len(params) {
        return arg_texts, Compile_Error{message = "too few thread worker arguments"}, false
    }
    return arg_texts, {}, true
}

emit_thread_start_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    spec, err_spec, ok_spec := thread_start_signature(e, form, true)
    if !ok_spec {
        return "", err_spec, false
    }
    arg_texts, err_args, ok_args := emit_parallel_args_for_params(e, form.items[3:], spec.params)
    if !ok_args {
        return "", err_args, false
    }
    mark_thread_start(e, spec)
    call_args: [dynamic]string
    for capture in spec.captures {
        append(&call_args, capture.name)
    }
    for arg_text in arg_texts {
        append(&call_args, arg_text)
    }
    return emit_call_text(thread_start_helper_name(spec), call_args[:]), {}, true
}

emit_thread_detach_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    spec, err_spec, ok_spec := thread_detach_signature(e, form, true)
    if !ok_spec {
        return "", err_spec, false
    }
    arg_texts, err_args, ok_args := emit_parallel_args_for_params(e, form.items[2:], spec.params)
    if !ok_args {
        return "", err_args, false
    }
    mark_thread_detach(e, spec)
    call_args: [dynamic]string
    for capture in spec.captures {
        append(&call_args, capture.name)
    }
    for arg_text in arg_texts {
        append(&call_args, arg_text)
    }
    return emit_call_text(thread_detach_helper_name(spec), call_args[:]), {}, true
}

emit_call_like :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    head := form.items[0]
    if head.kind != .Symbol {
        return "", Compile_Error{message = "unsupported call head", span = head.span}, false
    }

    if len(form.items) > 1 && is_call_directive_symbol(form.items[len(form.items)-1]) {
        directive := form.items[len(form.items)-1]
        stripped_items: [dynamic]CST_Form
        defer delete(stripped_items)
        for item in form.items[:len(form.items)-1] {
            append(&stripped_items, item)
        }
        stripped := form
        stripped.items = stripped_items
        target_text, err_target, ok_target := emit_call_like(e, stripped)
        if !ok_target {
            return "", err_target, false
        }
        return fmt.tprintf("%s %s", directive.text, target_text), {}, true
    }

    if head.text == "zero" {
        if len(form.items) < 2 {
            return "", Compile_Error{message = "zero expects a type", span = form.span}, false
        }
        type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], 1)
        if !ok_type {
            return "", err_type, false
        }
        if next_i != len(form.items) {
            return "", Compile_Error{message = "zero expects exactly one type", span = form.items[next_i].span}, false
        }
        return fmt.tprintf("%s{{}}", type_text), {}, true
    }

    if strings.has_prefix(head.text, "data.") || strings.has_prefix(head.text, "data/") {
        member := head.text[len("data."):]
        if strings.has_prefix(head.text, "data/") {
            member = head.text[len("data/"):]
        }
        if member == "tagged" {
            if len(form.items) != 3 {
                return "", Compile_Error{message = fmt.tprintf("%s expects tag text and a Data value", head.text), span = form.span}, false
            }
            tag, err_tag, ok_tag := emit_expr(e, form.items[1])
            if !ok_tag {
                return "", err_tag, false
            }
            value, err_value, ok_value := emit_expr(e, form.items[2])
            if !ok_value {
                return "", err_value, false
            }
            mark_data_type(e)
            return emit_call_text("kvist_data_make_tagged", []string{tag, value}), Compile_Error{}, true
        }
        if member == "item-at" || member == "key-at" || member == "value-at" {
            if len(form.items) != 3 {
                return "", Compile_Error{message = fmt.tprintf("%s expects Data map and index", head.text), span = form.span}, false
            }
            value, err_value, ok_value := emit_expr(e, form.items[1])
            if !ok_value {
                return "", err_value, false
            }
            index, err_index, ok_index := emit_expr(e, form.items[2])
            if !ok_index {
                return "", err_index, false
            }
            mark_data_type(e)
            return emit_call_text(fmt.tprintf("kvist_data_%s", map_name(member)), []string{value, index}), Compile_Error{}, true
        }
        if len(form.items) != 2 {
            return "", Compile_Error{message = fmt.tprintf("%s expects one Data value", head.text), span = form.span}, false
        }
        value, err_value, ok_value := emit_expr(e, form.items[1])
        if !ok_value {
            return "", err_value, false
        }
        mark_data_type(e)
        switch member {
        case "retain":
            return emit_call_text("kvist_data_retain", []string{value}), Compile_Error{}, true
        case "release":
            return emit_call_text("kvist_data_release", []string{value}), Compile_Error{}, true
        case "int", "float", "bool", "string", "keyword", "symbol", "text", "tag", "tagged-value", "count", "kind",
             "nil?", "bool?", "int?", "float?", "string?", "symbol?", "keyword?", "list?", "vector?", "map?", "set?", "tagged?":
            return emit_call_text(fmt.tprintf("kvist_data_%s", map_name(member)), []string{value}), Compile_Error{}, true
        case:
            return "", Compile_Error{message = fmt.tprintf("unknown Data operation: %s", head.text), span = head.span}, false
        }
    }

    canonical_head, _, err_head, ok_head := resolve_kvist_head(e, head.text)
    if !ok_head {
        err_head.span = head.span
        return "", err_head, false
    }
    head.text = canonical_head
    if head.text == "into" {
        return emit_transform_into_expr(e, form)
    }
    if head.text == "transform-into!" {
        return emit_transform_into_bang_expr(e, form)
    }

    if head.text == "transduce" {
        return emit_transform_transduce_expr(e, form)
    }

    if head.text == "thread-start" {
        return emit_thread_start_expr(e, form)
    }

    if head.text == "thread-detach" {
        return emit_thread_detach_expr(e, form)
    }

    if source, ok_source_call := source_call_decl(e, form); ok_source_call {
        return emit_source_materialized_expr(e, form, source)
    }

    if _, ok_step := transform_step_kind(head.text); ok_step && len(form.items) == 2 {
        return "", Compile_Error{message = fmt.tprintf("transform step `%s` cannot be used as a runtime value; use it with into, transduce, or for :transform", display_head_name(head.text)), span = head.span}, false
    }

    surface_head := display_head_name(head.text)

    if ctx, ok_context := lookup_callback_context(e, map_name(head.text)); ok_context {
        if ctx.field_selector != "" {
            if len(form.items) != 2 {
                return "", Compile_Error{message = "field-selector callback expects exactly one argument", span = form.span}, false
            }
            receiver, err_receiver, ok_receiver := emit_expr(e, form.items[1])
            if !ok_receiver {
                return "", err_receiver, false
            }
            return fmt.tprintf("%s.%s", receiver, ctx.field_selector), {}, true
        }
        arg_texts: [dynamic]string
        defer delete(arg_texts)
        for capture_name in ctx.capture_names {
            append(&arg_texts, capture_name)
        }
        for arg in form.items[1:] {
            arg_text, err_arg, ok_arg := emit_expr(e, arg)
            if !ok_arg {
                return "", err_arg, false
            }
            append(&arg_texts, arg_text)
        }
        return emit_call_text(map_name(head.text), arg_texts[:]), {}, true
    }

    if operator_text, err_op, ok_op := emit_operator_expr(e, form); ok_op {
        return operator_text, {}, true
    } else if err_op.message != "" {
        return "", err_op, false
    }

    if head.text == "new" {
        return "", Compile_Error{message = "`new` has been removed; use type-call syntax like (T literal)", span = form.items[0].span}, false
    }

    if head.text == "as" {
        return "", Compile_Error{message = "`as` has been removed; use type-call syntax like (T x)", span = form.items[0].span}, false
    }

    if head.text == "foreign-import" {
        return "", Compile_Error{message = "foreign-import is a top-level declaration form", span = form.items[0].span}, false
    }

    if head.text == "transmute" {
        if len(form.items) < 3 {
            return "", Compile_Error{message = "transmute expects type and value", span = form.span}, false
        }
        type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], 1)
        if !ok_type {
            return "", err_type, false
        }
        if next_i >= len(form.items) {
            return "", Compile_Error{message = "transmute missing value", span = form.span}, false
        }
        if next_i+1 != len(form.items) {
            return "", Compile_Error{message = "transmute expects exactly one value", span = form.items[next_i+1].span}, false
        }
        value, err_value, ok_value := emit_expr(e, form.items[next_i])
        if !ok_value {
            return "", err_value, false
        }
        return fmt.tprintf("transmute(%s)%s", type_text, value), {}, true
    }

    if head.text == "type-assert" {
        if len(form.items) < 3 {
            return "", Compile_Error{message = "type-assert expects value and type", span = form.span}, false
        }
        value, err_value, ok_value := emit_expr(e, form.items[1])
        if !ok_value {
            return "", err_value, false
        }
        type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], 2)
        if !ok_type {
            return "", err_type, false
        }
        if next_i != len(form.items) {
            return "", Compile_Error{message = "type-assert expects exactly one type", span = form.items[next_i].span}, false
        }
        return fmt.tprintf("(%s).(%s)", value, type_text), {}, true
    }

    if head.text == "odin-get" {
        if len(form.items) != 3 && len(form.items) != 4 {
            return "", Compile_Error{message = "odin-get expects collection, key, and optional default", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        target_ty, target_is_typed := obvious_form_type(e, form.items[1])
        if target_is_typed && target_ty == "Data" {
            key, err_key, ok_key := emit_data_lookup_key(e, form.items[2])
            if !ok_key {
                return "", err_key, false
            }
            call := emit_call_text("kvist_data_get", []string{target, key})
            if len(form.items) == 4 {
                fallback, err_fallback, ok_fallback := emit_data_value_literal(e, form.items[3])
                if form.items[3].kind == .Symbol ||
                   (form.items[3].kind == .List && len(form.items[3].items) > 0 && is_symbol(form.items[3].items[0], "quote")) {
                    fallback, err_fallback, ok_fallback = emit_expr(e, form.items[3])
                }
                if !ok_fallback {
                    return "", err_fallback, false
                }
                return emit_call_text("kvist_data_get_or", []string{target, key, fallback}), Compile_Error{}, true
            }
            return call, Compile_Error{}, true
        }
        map_target := map_index_target_text(e, form.items[1], target)
        if field, ok_field := selector_accesses_field(e, form.items[1], form.items[2]); ok_field {
            if len(form.items) == 4 {
                return "", Compile_Error{message = "odin-get field access does not support a default value", span = form.items[2].span}, false
            }
            return fmt.tprintf("(%s).%s", target, field), {}, true
        }
        key, err_key, ok_key := emit_expr(e, form.items[2])
        if !ok_key {
            return "", err_key, false
        }
        if len(form.items) == 4 {
            default_value, err_default, ok_default := emit_expr(e, form.items[3])
            if !ok_default {
                return "", err_default, false
            }
            mark_core_get_or_default(e)
            return emit_call_text("kvist_get_or_default", []string{map_target, key, default_value}), {}, true
        }
        return fmt.tprintf("%s[%s]", map_target, key), {}, true
    }

    is_struct_fields := head.text == "struct-fields"
    is_struct_types := head.text == "struct-types"
    if is_struct_fields || is_struct_types {
        if len(form.items) != 2 {
            return "", Compile_Error{message = fmt.tprintf("%s expects a quoted struct name", head.text), span = form.span}, false
        }
        struct_name, ok_name := quoted_symbol_name(form.items[1])
        if !ok_name {
            return "", Compile_Error{message = fmt.tprintf("%s currently expects a quoted struct name", head.text), span = form.items[1].span}, false
        }
        struct_decl, ok_struct := find_struct_decl(e, struct_name)
        if !ok_struct {
            return "", Compile_Error{message = fmt.tprintf("unknown struct: %s", struct_name), span = form.items[1].span}, false
        }
        if is_struct_fields {
            return emit_struct_fields_literal(struct_decl), {}, true
        }
        mark_dynamic_literals(e)
        return emit_struct_types_literal(struct_decl), {}, true
    }

    if head.text == "source-doc" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "source-doc expects a quoted declaration name", span = form.span}, false
        }
        name, ok_name := quoted_symbol_name(form.items[1])
        if !ok_name {
            return "", Compile_Error{message = "source-doc currently expects a quoted declaration name", span = form.items[1].span}, false
        }
        text, ok_doc := find_decl_doc_text(e, name)
        if !ok_doc {
            return "", Compile_Error{message = fmt.tprintf("unknown declaration: %s", name), span = form.items[1].span}, false
        }
        defer delete(text)
        return fmt.tprintf("%q", text), {}, true
    }

    if head.text == "odin-slice" {
        if len(form.items) < 2 || len(form.items) > 4 {
            return "", Compile_Error{message = "odin-slice expects target, optional start, and optional end", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        if len(form.items) == 2 {
            return fmt.tprintf("(%s)[:]", target), {}, true
        }
        start, err_start, ok_start := emit_expr(e, form.items[2])
        if !ok_start {
            return "", err_start, false
        }
        if len(form.items) == 3 {
            return fmt.tprintf("(%s)[%s:]", target, start), {}, true
        }
        end, err_end, ok_end := emit_expr(e, form.items[3])
        if !ok_end {
            return "", err_end, false
        }
        return fmt.tprintf("(%s)[%s:%s]", target, start, end), {}, true
    }

    if head.text == "^" || head.text == "deref" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = fmt.tprintf("%s expects one pointer expression", head.text), span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        return deref_expr_text(target), {}, true
    }

    if head.text == "&" {
        return "", Compile_Error{message = "address-of list form is not supported; use &value or (addr value)", span = form.span}, false
    }

    if head.text == "addr" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = fmt.tprintf("%s expects one addressable expression", head.text), span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        return addr_expr_text(target), {}, true
    }

    if head.text == "mut" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "mut expects one mutable target expression", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        return map_mutation_target_text(e, form.items[1], target), {}, true
    }

    if head.text == "copy-with" {
        return emit_shallow_assoc_expr(e, form)
    }
    if head.text == "copy-update" {
        return emit_shallow_update_expr(e, form)
    }
    if head.text == "copy-dissoc" {
        return emit_data_dissoc_expr(e, form)
    }
    if head.text == "copy-dissoc-in" {
        return emit_data_dissoc_in_expr(e, form)
    }
    if head.text == "decode-data" {
        return emit_data_decode_expr(e, form)
    }
    if head.text == "validate-data" {
        return emit_data_validate_expr(e, form)
    }

    if head.text == "as->" {
        return emit_as_thread_expr(e, form)
    }

    if head.text == "make" {
        if len(form.items) < 2 {
            return "", Compile_Error{message = "make expects a type and optional arguments", span = form.span}, false
        }
        type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], 1)
        if !ok_type {
            return "", err_type, false
        }
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        fmt.sbprintf(&builder, "make(%s", type_text)
        for arg in form.items[next_i:] {
            arg_text, err_arg, ok_arg := emit_expr(e, arg)
            if !ok_arg {
                return "", err_arg, false
            }
            strings.write_string(&builder, ", ")
            strings.write_string(&builder, arg_text)
        }
        strings.write_byte(&builder, ')')
        return strings.clone(strings.to_string(builder)), {}, true
    }

    if head.text == "alloc" {
        if len(form.items) < 2 {
            return "", Compile_Error{message = "alloc expects a type and optional allocator", span = form.span}, false
        }
        type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], 1)
        if !ok_type {
            return "", err_type, false
        }
        if next_i != len(form.items) && next_i+1 != len(form.items) {
            return "", Compile_Error{message = "alloc expects a type and optional allocator", span = form.items[next_i].span}, false
        }
        if next_i == len(form.items) {
            return fmt.tprintf("new(%s)", type_text), {}, true
        }
        allocator, err_allocator, ok_allocator := emit_expr(e, form.items[next_i])
        if !ok_allocator {
            return "", err_allocator, false
        }
        return fmt.tprintf("new(%s, %s)", type_text, allocator), {}, true
    }

    if len(form.items) == 2 && form.items[1].kind == .Vector {
        if head.text == "quaternion" {
            return emit_quaternion_vector_constructor(e, form.items[1])
        }
        head_name := map_name(head.text)
        if !strings.contains(head_name, ".") {
            if call_head_is_overload(e, head) {
                // Let the normal call path apply the overload's literal context.
            } else if _, _, ok_proc := resolve_proc_call_decl(e, head.text); ok_proc {
                // Let the normal call path handle declared procedures with vector arguments.
            } else {
                type_text, err_type, ok_type := parse_type_text(head)
                if !ok_type {
                    return "", err_type, false
                }
                text, err_literal, ok_literal, _ := emit_typed_literal_value(e, head, type_text, form.items[1])
                return text, err_literal, ok_literal
            }
        } else {
            imported_fields, ok_imported_type := imported_odin_type_fields(e, head_name)
            if ok_imported_type {
                defer delete_struct_field_slice(&imported_fields)
                type_text, err_type, ok_type := parse_type_text(head)
                if !ok_type {
                    return "", err_type, false
                }
                text, err_literal, ok_literal, _ := emit_typed_literal_value(e, head, type_text, form.items[1])
                return text, err_literal, ok_literal
            }
            if _, ok_expected := imported_odin_proc_arg_type(e, head_name, 0); !ok_expected {
                type_text, err_type, ok_type := parse_type_text(head)
                if !ok_type {
                    return "", err_type, false
                }
                text, err_literal, ok_literal, _ := emit_typed_literal_value(e, head, type_text, form.items[1])
                return text, err_literal, ok_literal
            }
        }
    }

    if len(form.items) == 2 && form.items[1].kind == .Set && !call_head_is_overload(e, head) {
        type_text, err_type, ok_type := parse_type_text(head)
        if !ok_type {
            return "", err_type, false
        }
        text, err_literal, ok_literal, _ := emit_typed_literal_value(e, head, type_text, form.items[1])
        return text, err_literal, ok_literal
    }

    if head.text == "quaternion" {
        return emit_quaternion_arg_constructor(e, form.items[1:], form.span)
    }

    if len(form.items) == 2 && form.items[1].kind == .Brace && !call_head_is_overload(e, head) {
        head_name := map_name(head.text)
        struct_decl, ok_struct := find_struct_decl(e, head_name)
        if ok_struct {
            err_struct, ok_struct_ctor := validate_struct_constructor(e, struct_decl, form.items[1])
            if !ok_struct_ctor {
                return "", err_struct, false
            }
            return emit_struct_brace_literal(e, struct_decl, form.items[1])
        }
        union_decl, ok_union := find_union_decl(e, head_name)
        if ok_union {
            return emit_union_constructor(e, union_decl, form.items[1])
        }
        imported_fields, ok_imported := imported_odin_type_fields(e, head_name)
        if ok_imported {
            defer delete_struct_field_slice(&imported_fields)
            return emit_imported_struct_brace_literal(e, head_name, imported_fields[:], form.items[1])
        }
        if type_text_is_map(head_name) {
            mark_dynamic_literals(e)
            return emit_brace_literal(e, head_name, form.items[1])
        }
        if dotted_head_member_starts_upper(head_name) {
            return emit_brace_literal(e, head_name, form.items[1])
        }
        if !strings.contains(head_name, ".") {
            if call_name, proc_decl, ok_proc := resolve_proc_call_decl(e, head.text); ok_proc {
                named_arg_texts, err_named, ok_named := emit_named_call_with_defaults(e, proc_decl, form.items[1])
                if !ok_named {
                    return "", err_named, false
                }
                return emit_call_text(call_name, named_arg_texts[:]), {}, true
            }
        }
        named_arg_texts, err_named, ok_named := emit_named_call_arg_texts(e, form.items[1])
        if ok_named {
            return emit_call_text(head_name, named_arg_texts[:]), {}, true
        }
        if err_named.message != "" && err_named.message != "named arguments expect field: labels" {
            return "", err_named, false
        }
        return emit_brace_literal(e, head_name, form.items[1])
    }

    arg_texts: [dynamic]string
    head_name := map_name(head.text)
    if !strings.contains(head_name, ".") {
        if call_name, proc_decl, ok_proc := resolve_proc_call_decl(e, head.text); ok_proc {
            specialized_call, handled_specialized, err_specialized, ok_specialized := emit_specialized_proc_call_if_needed(e, call_name, proc_decl, form.items[1:], form.span)
            if handled_specialized {
                if !ok_specialized {
                    return "", err_specialized, false
                }
                return specialized_call, {}, true
            }
            if len(form.items) >= 3 && form.items[len(form.items)-1].kind == .Brace {
                arg_texts_with_mixed, err_args, ok_args := emit_mixed_call_with_defaults(e, proc_decl, form.items[1:len(form.items)-1], form.items[len(form.items)-1], form.span)
                if !ok_args {
                    return "", err_args, false
                }
                return emit_call_text(call_name, arg_texts_with_mixed[:]), {}, true
            }
            arg_texts_with_defaults, err_args, ok_args := emit_positional_call_with_defaults(e, proc_decl, form.items[1:], form.span)
            if !ok_args {
                return "", err_args, false
            }
            return emit_call_text(call_name, arg_texts_with_defaults[:]), {}, true
        }
    }
    if len(form.items) == 2 && symbol_head_needs_type_conversion_parens(head.text) {
        type_text, err_type, ok_type := parse_type_text(head)
        if !ok_type {
            return "", err_type, false
        }
        mark_keyword_type_for_text(e, type_text)
        value_text, err_value, ok_value := emit_expr(e, form.items[1])
        if !ok_value {
            return "", err_value, false
        }
        return emit_type_conversion_text(type_text, value_text), {}, true
    }
    generic_ctor, err_generic_ctor, ok_generic_ctor := emit_generic_type_constructor_call(e, form)
    if ok_generic_ctor || err_generic_ctor.message != "" {
        return generic_ctor, err_generic_ctor, ok_generic_ctor
    }
    if len(form.items) >= 3 && form.items[len(form.items)-1].kind == .Brace {
        arg_texts_with_mixed, err_mixed, ok_mixed := emit_general_mixed_call_arg_texts(e, head_name, form.items[1:len(form.items)-1], form.items[len(form.items)-1])
        if ok_mixed {
            return emit_call_text(head_name, arg_texts_with_mixed[:]), {}, true
        }
        if err_mixed.message != "" && err_mixed.message != "named arguments expect field: labels" {
            return "", err_mixed, false
        }
    }
    for arg, arg_idx in form.items[1:] {
        arg_text := ""
        err_arg: Compile_Error
        ok_arg := false
        if expected_type, ok_expected := overload_literal_arg_expected_type(e, head_name, form.items[1:], arg_idx); ok_expected {
            arg_text, err_arg, ok_arg = emit_call_arg_for_expected_type(e, arg, expected_type)
            delete(expected_type)
        } else if expected_type, ok_expected := imported_odin_proc_arg_type(e, head_name, arg_idx); ok_expected {
            arg_text, err_arg, ok_arg = emit_call_arg_for_expected_type(e, arg, expected_type)
            delete(expected_type)
        } else {
            arg_text, err_arg, ok_arg = emit_expr(e, arg)
        }
        if !ok_arg {
            return "", err_arg, false
        }
        append(&arg_texts, arg_text)
    }
    return emit_call_text(head_name, arg_texts[:]), {}, true
}

emit_type_application_expr :: proc(e: ^Emitter, type_form: CST_Form, args: []CST_Form, span: Span) -> (string, Compile_Error, bool) {
    if len(args) != 1 {
        return "", Compile_Error{message = "type application expects exactly one value", span = span}, false
    }

    type_text, err_type, ok_type := parse_type_text(type_form)
    if !ok_type {
        return "", err_type, false
    }
    mark_keyword_type_for_text(e, type_text)

    value := args[0]
    if text, err_literal, ok_literal, handled := emit_typed_literal_value(e, type_form, type_text, value); handled {
        return text, err_literal, ok_literal
    }
    value_text, err_value, ok_value := emit_expr(e, value)
    if !ok_value {
        return "", err_value, false
    }
    return emit_type_conversion_text(type_text, value_text), {}, true
}

generic_type_constructor_call_candidate :: proc(head: CST_Form) -> bool {
    if head.kind != .Symbol || len(head.text) == 0 {
        return false
    }
    if head.text[0] >= 'A' && head.text[0] <= 'Z' {
        return true
    }
    dot := strings.last_index(head.text, ".")
    return dot >= 0 && dot+1 < len(head.text) && head.text[dot+1] >= 'A' && head.text[dot+1] <= 'Z'
}

emit_generic_type_constructor_call :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) < 3 || !generic_type_constructor_call_candidate(form.items[0]) {
        return "", Compile_Error{}, false
    }
    if _, ok_expected := imported_odin_proc_arg_type(e, map_name(form.items[0].text), 0); ok_expected {
        return "", Compile_Error{}, false
    }

    value := form.items[len(form.items)-1]
    if value.kind != .Vector && value.kind != .Brace {
        return "", Compile_Error{}, false
    }

    type_form := CST_Form{
        kind  = .List,
        span  = form.span,
        items = make([dynamic]CST_Form, 0, len(form.items)),
    }
    append(&type_form.items, CST_Form{kind = .Symbol, text = "type", span = form.items[0].span})
    for item in form.items[:len(form.items)-1] {
        append(&type_form.items, item)
    }

    result, err, ok := emit_type_application_expr(e, type_form, form.items[len(form.items)-1:], form.span)
    delete(type_form.items)
    return result, err, ok
}

emit_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    #partial switch form.kind {
    case .String:
        return emit_string_literal_text(form), {}, true
    case .Regex:
        return emit_regex_literal_text(form), {}, true
    case .Number:
        return form.text, {}, true
    case .Bool:
        return form.text, {}, true
    case .Nil:
        return form.text, {}, true
    case .Symbol:
        if len(form.text) > 1 && form.text[0] == '&' {
            target := map_name(form.text[1:])
            return addr_expr_text(target), {}, true
        }
        if symbol_is_simple_deref_suffix(form.text) {
            return deref_expr_text(map_name(form.text[:len(form.text)-1])), {}, true
        }
        return map_name(form.text), {}, true
    case .Keyword:
        return keyword_literal_text(e, form.text), {}, true
    case .List:
        if len(form.items) == 0 {
            return "", Compile_Error{message = "empty list expression", span = form.span}, false
        }
        if form.items[0].kind == .Symbol &&
           len(form.items[0].text) > 0 &&
           form.items[0].text[0] == '#' &&
           !strings.has_prefix(form.items[0].text, "#soa[") &&
           !strings.has_prefix(form.items[0].text, "#simd[") {
            return emit_directive_expr(e, form)
        }
        if is_symbol(form.items[0], "proc") {
            return "", Compile_Error{message = "`proc` has been removed; use `fn` for function literals and function types, or `defn` for named functions", span = form.items[0].span}, false
        }
        if is_symbol(form.items[0], "quote") {
            return emit_quoted_data_expr(e, form)
        }
        if is_symbol(form.items[0], "quasiquote") {
            return emit_runtime_data_quasiquote_expr(e, form)
        }
        if head, ok_statement := form_head_is_statement_only(form); ok_statement {
            return "", Compile_Error{message = fmt.tprintf("%s is a statement and cannot be used as an expression", display_head_name(head)), span = form.items[0].span}, false
        }
        if is_symbol(form.items[0], "if") {
            return emit_if_expr(e, form)
        }
        if is_symbol(form.items[0], "let") || form_head_is_do(form) {
            return emit_block_expr(e, form)
        }
        if form_head_is_allocator_scope(form) {
            return emit_block_expr(e, form)
        }
        if form_head_is_case(form) {
            return emit_case_expr(e, form)
        }
        if form_head_is_match(form) {
            return emit_block_expr(e, form)
        }
        if is_symbol(form.items[0], "fn") {
            return emit_proc_literal_expr(e, form)
        }
        if is_symbol(form.items[0], "__kvist_field") {
            if len(form.items) != 3 || form.items[2].kind != .Symbol {
                return "", Compile_Error{message = "field access expects receiver and field", span = form.span}, false
            }
            receiver, err_receiver, ok_receiver := emit_expr(e, form.items[1])
            if !ok_receiver {
                return "", err_receiver, false
            }
            return fmt.tprintf("%s.%s", receiver, map_name(form.items[2].text)), {}, true
        }
        if is_symbol(form.items[0], "__kvist_index") {
            if len(form.items) != 3 {
                return "", Compile_Error{message = "index expression expects target and index", span = form.span}, false
            }
            target, err_target, ok_target := emit_expr(e, form.items[1])
            if !ok_target {
                return "", err_target, false
            }
            index, err_index, ok_index := emit_expr(e, form.items[2])
            if !ok_index {
                return "", err_index, false
            }
            return fmt.tprintf("(%s)[%s]", target, index), {}, true
        }
        if is_symbol(form.items[0], "__kvist_slice") {
            if len(form.items) != 4 {
                return "", Compile_Error{message = "slice expression expects target, start, and end", span = form.span}, false
            }
            target, err_target, ok_target := emit_expr(e, form.items[1])
            if !ok_target {
                return "", err_target, false
            }
            start_omitted := form_is_omitted_slice_bound(form.items[2])
            end_omitted := form_is_omitted_slice_bound(form.items[3])
            if start_omitted && end_omitted {
                return fmt.tprintf("(%s)[:]", target), {}, true
            }
            if start_omitted {
                end, err_end, ok_end := emit_expr(e, form.items[3])
                if !ok_end {
                    return "", err_end, false
                }
                return fmt.tprintf("(%s)[:%s]", target, end), {}, true
            }
            start, err_start, ok_start := emit_expr(e, form.items[2])
            if !ok_start {
                return "", err_start, false
            }
            if end_omitted {
                return fmt.tprintf("(%s)[%s:]", target, start), {}, true
            }
            end, err_end, ok_end := emit_expr(e, form.items[3])
            if !ok_end {
                return "", err_end, false
            }
            return fmt.tprintf("(%s)[%s:%s]", target, start, end), {}, true
        }
        if is_symbol(form.items[0], "odin") {
            if len(form.items) != 2 || form.items[1].kind != .String {
                return "", Compile_Error{message = "odin expects one string literal", span = form.span}, false
            }
            return unquote_string(form.items[1].text), {}, true
        }
        if is_symbol(form.items[0], "odin-infix") {
            return emit_odin_infix_expr(e, form)
        }
        if is_symbol(form.items[0], "odin-prefix") {
            return emit_odin_prefix_expr(e, form)
        }
        if is_symbol(form.items[0], "odin-call") {
            return emit_odin_call_expr(e, form)
        }
        if is_symbol(form.items[0], "type") {
            type_text, err_type, ok_type := parse_type_text(form)
            if !ok_type {
                return "", err_type, false
            }
            return type_text, {}, true
        }
        if form.items[0].kind != .Symbol {
            return emit_type_application_expr(e, form.items[0], form.items[1:], form.span)
        }
        return emit_call_like(e, form)
    case .Vector, .Brace, .Set:
        return emit_inferred_literal(e, form)
    }
    return "", Compile_Error{message = "unsupported expression", span = form.span}, false
}

type_text_is_slice :: proc(text: string) -> bool {
    return len(text) >= 2 && text[:2] == "[]"
}

collection_element_type :: proc(type_text: string) -> (string, bool) {
    if type_text_is_dynamic_array(type_text) {
        return type_text[len("[dynamic]"):], true
    }
    if type_text_is_slice(type_text) {
        return type_text[len("[]"):], true
    }
    if len(type_text) > 0 && type_text[0] == '[' && !type_text_is_dynamic_array(type_text) {
        close := strings.index(type_text, "]")
        if close >= 0 && close+1 < len(type_text) {
            return type_text[close+1:], true
        }
    }
    return "", false
}

transform_source_value_type :: proc(type_text: string) -> (string, bool) {
    if type_text == "Data" {
        return "Data", true
    }
    if _, value_ty, ok_map := map_type_parts(type_text); ok_map {
        return value_ty, true
    }
    return collection_element_type(type_text)
}

transform_source_loop_header :: proc(source_ty, source_text, key_name: string) -> string {
    if source_ty == "Data" {
        return fmt.tprintf(
            "assert(%s.kind == .Nil || %s.kind == .List || %s.kind == .Vector || %s.kind == .Set, \"Data transform source expects nil, list, vector, or set\"); for kvist_item in %s.payload.items %s",
            source_text,
            source_text,
            source_text,
            source_text,
            source_text,
            "{",
        )
    }
    if type_text_is_map(source_ty) {
        if len(key_name) > 0 {
            return fmt.tprintf("for %s, kvist_item in %s %s", key_name, source_text, "{")
        }
        return fmt.tprintf("for _, kvist_item in %s %s", source_text, "{")
    }
    return fmt.tprintf("for kvist_item in %s %s", source_text, "{")
}

transform_source_count_text :: proc(source_ty, source_text: string) -> string {
    if source_ty == "Data" {
        return fmt.tprintf("kvist_data_count(%s)", source_text)
    }
    return fmt.tprintf("len(%s)", source_text)
}

emit_transform_loop_source_open :: proc(builder: ^strings.Builder, depth: int, item_name, source_text: string, spec: Transform_Loop_Source) {
    append_indent(builder, depth)
    fmt.sbprintf(builder, "for %s, %s in %s %s\n", spec.key_name, spec.value_name, source_text, "{")
    append_indent(builder, depth+1)
    fmt.sbprintf(builder, "%s := %s\n", item_name, spec.item_text)
}

dynamic_array_element_type :: proc(type_text: string) -> (string, bool) {
    if !type_text_is_dynamic_array(type_text) {
        return "", false
    }
    return type_text[len("[dynamic]"):], true
}

entry_type_parts :: proc(type_text: string) -> (key, value: string, ok: bool) {
    open := strings.index(type_text, "(")
    if open <= 0 || !strings.has_suffix(type_text, ")") {
        return "", "", false
    }
    constructor := strings.trim_space(type_text[:open])
    if !strings.has_suffix(constructor, ".entry") {
        return "", "", false
    }
    inner := type_text[open+1:len(type_text)-1]
    parts := split_top_level_commas(inner)
    defer delete(parts)
    if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
        return "", "", false
    }
    return parts[0], parts[1], true
}

transform_into_output_accepts_value :: proc(spec: Transform_Into_Output, value_ty: string) -> bool {
    if spec.kind == .Map && spec.value_ty == "" {
        key_ty, val_ty, ok_entry := entry_type_parts(value_ty)
        return ok_entry && key_ty == spec.map_key_ty && val_ty == spec.map_val_ty
    }
    return value_ty == spec.value_ty
}

transform_into_output_value_description :: proc(spec: Transform_Into_Output) -> string {
    if spec.kind == .Map && spec.value_ty == "" {
        return fmt.tprintf("entry(%s, %s)", spec.map_key_ty, spec.map_val_ty)
    }
    return spec.value_ty
}

transform_into_output_spec :: proc(output_ty: string) -> (spec: Transform_Into_Output, err: Compile_Error, ok: bool) {
    spec.output_ty = output_ty
    if output_ty == "Data" {
        spec.kind = .Data_Vector
        spec.value_ty = "Data"
        return spec, {}, true
    }
    if elem_ty, ok_elem := dynamic_array_element_type(output_ty); ok_elem {
        spec.kind = .Dynamic_Array
        spec.value_ty = elem_ty
        return spec, {}, true
    }
    if key_ty, value_ty, ok_map := map_type_parts(output_ty); ok_map && value_ty == "struct{}" {
        spec.kind = .Set
        spec.map_key_ty = key_ty
        spec.map_val_ty = value_ty
        spec.value_ty = key_ty
        return spec, {}, true
    }
    if key_ty, value_ty, ok_map := map_type_parts(output_ty); ok_map {
        spec.kind = .Map
        spec.map_key_ty = key_ty
        spec.map_val_ty = value_ty
        return spec, {}, true
    }
    return spec, Compile_Error{message = "into transform expects a dynamic array, map, or set output type"}, false
}

emit_transform_into_output_write :: proc(builder: ^strings.Builder, depth: int, spec: Transform_Into_Output, value_text: string) {
    append_indent(builder, depth)
    switch spec.kind {
    case .Dynamic_Array:
        fmt.sbprintf(builder, "append(&kvist_out, %s)\n", value_text)
    case .Data_Vector:
        fmt.sbprintf(builder, "kvist_data_append_retained(&kvist_out, %s)\n", value_text)
    case .Map:
        fmt.sbprintf(builder, "kvist_out[(%s).key] = (%s).value\n", value_text, value_text)
    case .Set:
        fmt.sbprintf(builder, "kvist_out[%s] = struct%s%s\n", value_text, "{}", "{}")
    }
}

transform_into_make_text :: proc(spec: Transform_Into_Output, capacity_text: string) -> string {
    if capacity_text == "" {
        return fmt.tprintf("make(%s)", spec.output_ty)
    }
    switch spec.kind {
    case .Dynamic_Array:
        return fmt.tprintf("make(%s, 0, %s)", spec.output_ty, capacity_text)
    case .Data_Vector:
        return fmt.tprintf("make([dynamic]Data, 0, %s)", capacity_text)
    case .Map:
        return fmt.tprintf("make(%s, %s)", spec.output_ty, capacity_text)
    case .Set:
        return fmt.tprintf("make(%s, %s)", spec.output_ty, capacity_text)
    }
    return fmt.tprintf("make(%s)", spec.output_ty)
}

transform_into_finalize_text :: proc(spec: Transform_Into_Output) -> string {
    if spec.kind == .Data_Vector {
        return "kvist_data_freeze_items(.Vector, &kvist_out)"
    }
    return "kvist_out"
}

append_indent :: proc(builder: ^strings.Builder, depth: int) {
    for _ in 0..<depth {
        strings.write_string(builder, "    ")
    }
}

Binding :: struct {
    is_destructure:      bool,
    is_result_binding:   bool,
    is_data_destructure: bool,
    name:                string,
    pattern:             [dynamic]string,
    target:              CST_Form,
    is_typed:            bool,
    ty:                  string,
    deferred_delete:     bool,
    err_deferred_delete: bool,
    defer_with_cleanup:  bool,
    cleanup:             CST_Form,
    or_modifier:         string,
    target_span:         Span,
    value:               CST_Form,
}

data_binding_rhs_is_data :: proc(e: ^Emitter, form: CST_Form) -> bool {
    if form.kind == .Vector || form.kind == .Brace || form.kind == .Set {
        return true
    }
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol &&
       (form.items[0].text == "quote" || form.items[0].text == "quasiquote") {
        return true
    }
    ty, ok_ty := obvious_form_type(e, form)
    return ok_ty && ty == "Data"
}

binding_is_data_destructure :: proc(e: ^Emitter, binding: Binding) -> bool {
    if binding.is_data_destructure || binding.target.kind == .Brace {
        return true
    }
    return binding.target.kind == .Vector && data_binding_rhs_is_data(e, binding.value)
}

data_pattern_append_name :: proc(names: ^[dynamic]string, form: CST_Form) -> (Compile_Error, bool) {
    if form.kind != .Symbol || form.text == "_" || form.text == "&" {
        return {}, true
    }
    name := map_name(form.text)
    for existing in names^ {
        if existing == name {
            return Compile_Error{message = fmt.tprintf("duplicate Data pattern binding `%s`", form.text), span = form.span}, false
        }
    }
    append(names, name)
    return {}, true
}

validate_data_pattern_names :: proc(form: CST_Form, names: ^[dynamic]string, let_pattern: bool) -> (Compile_Error, bool) {
    #partial switch form.kind {
    case .Symbol:
        return data_pattern_append_name(names, form)
    case .Vector:
        saw_rest := false
        saw_as := false
        i := 0
        for i < len(form.items) {
            item := form.items[i]
            if item.kind == .Symbol && item.text == "&" {
                if saw_rest || saw_as || i+1 >= len(form.items) {
                    return Compile_Error{message = "sequential Data pattern expects one binding after &", span = item.span}, false
                }
                saw_rest = true
                err_rest, ok_rest := validate_data_pattern_names(form.items[i+1], names, let_pattern)
                if !ok_rest {
                    return err_rest, false
                }
                i += 2
                continue
            }
            if item.kind == .Keyword && item.text == ":as" {
                if !let_pattern || saw_as || i+1 >= len(form.items) || i+2 != len(form.items) {
                    return Compile_Error{message = "sequential let destructuring expects :as followed by one final binding", span = item.span}, false
                }
                if form.items[i+1].kind != .Symbol {
                    return Compile_Error{message = "sequential :as expects a symbol binding", span = form.items[i+1].span}, false
                }
                saw_as = true
                err_as, ok_as := validate_data_pattern_names(form.items[i+1], names, let_pattern)
                if !ok_as {
                    return err_as, false
                }
                i += 2
                continue
            }
            if saw_rest {
                return Compile_Error{message = "only :as may follow a sequential & binding", span = item.span}, false
            }
            err_item, ok_item := validate_data_pattern_names(item, names, let_pattern)
            if !ok_item {
                return err_item, false
            }
            i += 1
        }
    case .Brace:
        if len(form.items)%2 != 0 {
            return Compile_Error{message = "map Data pattern expects key/value pairs", span = form.span}, false
        }
        i := 0
        for i < len(form.items) {
            key := form.items[i]
            value := form.items[i+1]
            if key.kind == .Keyword {
                if key.text == ":as" {
                    if !let_pattern {
                        return Compile_Error{message = "map :as is only valid in let destructuring; use (as name pattern) in match", span = key.span}, false
                    }
                    if value.kind != .Symbol {
                        return Compile_Error{message = "map :as expects a symbol binding", span = value.span}, false
                    }
                    err_as, ok_as := validate_data_pattern_names(value, names, let_pattern)
                    if !ok_as {
                        return err_as, false
                    }
                    i += 2
                    continue
                }
                if key.text == ":or" {
                    if !let_pattern || value.kind != .Brace {
                        return Compile_Error{message = "map :or expects a defaults map in let destructuring", span = value.span}, false
                    }
                    i += 2
                    continue
                }
                shorthand := key.text == ":keys" || key.text == ":strs" || key.text == ":syms" || strings.has_suffix(key.text, "/keys")
                if shorthand {
                    if value.kind != .Vector {
                        return Compile_Error{message = fmt.tprintf("%s destructuring expects a vector of symbols", key.text), span = value.span}, false
                    }
                    for name_form in value.items {
                        if name_form.kind != .Symbol {
                            return Compile_Error{message = fmt.tprintf("%s destructuring expects symbols", key.text), span = name_form.span}, false
                        }
                        err_name, ok_name := data_pattern_append_name(names, name_form)
                        if !ok_name {
                            return err_name, false
                        }
                    }
                    i += 2
                    continue
                }
            }
            err_target, ok_target := validate_data_pattern_names(key, names, let_pattern)
            if !ok_target {
                return err_target, false
            }
            i += 2
        }
    case:
        if let_pattern {
            return Compile_Error{message = "let Data destructuring expects symbol, vector, or map binding forms", span = form.span}, false
        }
    }
    return {}, true
}

data_pattern_default_for_name :: proc(map_pattern: CST_Form, name: string) -> (CST_Form, bool) {
    if map_pattern.kind != .Brace {
        return {}, false
    }
    i := 0
    for i+1 < len(map_pattern.items) {
        if map_pattern.items[i].kind == .Keyword && map_pattern.items[i].text == ":or" {
            defaults := map_pattern.items[i+1]
            if defaults.kind == .Brace {
                j := 0
                for j+1 < len(defaults.items) {
                    if defaults.items[j].kind == .Symbol && map_name(defaults.items[j].text) == name {
                        return defaults.items[j+1], true
                    }
                    j += 2
                }
            }
        }
        i += 2
    }
    return {}, false
}

emit_owned_data_local :: proc(e: ^Emitter, name, value: string, span: Span, already_owned: bool) {
    text := value
    if !already_owned {
        text = emit_call_text("kvist_data_retain", []string{value})
    }
    emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", name), text, span)
    emit_line(e, fmt.tprintf("defer kvist_data_release(%s)", name))
    bind_local_type(e, name, "Data")
}

emit_data_pattern_literal_temp :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    mark_data_type(e)
    value, _, err_value, ok_value := emit_contextual_data_value(e, form)
    if !ok_value {
        return "", err_value, false
    }
    temp := thread_temp_name(e)
    emit_owned_data_local(e, temp, value, form.span, true)
    return temp, {}, true
}

data_shorthand_key :: proc(kind_text, local_text: string, span: Span) -> CST_Form {
    if kind_text == ":strs" {
        return CST_Form{kind = .String, text = local_text, span = span}
    }
    if kind_text == ":syms" {
        quoted := CST_Form{kind = .Symbol, text = local_text, span = span}
        return make_list_form({make_symbol_form("quote", span), quoted}, span)
    }
    namespace := ""
    if strings.has_suffix(kind_text, "/keys") && kind_text != ":keys" {
        namespace = kind_text[1:len(kind_text)-len("/keys")]
    }
    text := fmt.tprintf(":%s", local_text)
    if namespace != "" {
        text = fmt.tprintf(":%s/%s", namespace, local_text)
    }
    return CST_Form{kind = .Keyword, text = text, span = span}
}

emit_data_pattern_bindings :: proc(e: ^Emitter, pattern: CST_Form, source: string, defaults_owner: CST_Form = {}) -> (Compile_Error, bool) {
    #partial switch pattern.kind {
    case .Symbol:
        if pattern.text == "_" {
            return {}, true
        }
        name := map_name(pattern.text)
        emit_owned_data_local(e, name, source, pattern.span, false)
        return {}, true
    case .Vector:
        item_index := 0
        i := 0
        for i < len(pattern.items) {
            item := pattern.items[i]
            if item.kind == .Symbol && item.text == "&" {
                rest_temp := thread_temp_name(e)
                rest_value := fmt.tprintf("kvist_data_rest_from(%s, %d)", source, item_index)
                emit_owned_data_local(e, rest_temp, rest_value, item.span, true)
                err_rest, ok_rest := emit_data_pattern_bindings(e, pattern.items[i+1], rest_temp)
                if !ok_rest {
                    return err_rest, false
                }
                i += 2
                continue
            }
            if item.kind == .Keyword && item.text == ":as" {
                return emit_data_pattern_bindings(e, pattern.items[i+1], source)
            }
            child := thread_temp_name(e)
            emit_line_mapped(e, fmt.tprintf("%s := kvist_data_nth_or_nil(%s, %d)", child, source, item_index), item.span)
            err_child, ok_child := emit_data_pattern_bindings(e, item, child)
            if !ok_child {
                return err_child, false
            }
            item_index += 1
            i += 1
        }
        return {}, true
    case .Brace:
        i := 0
        for i < len(pattern.items) {
            key_form := pattern.items[i]
            target := pattern.items[i+1]
            if key_form.kind == .Keyword && (key_form.text == ":or") {
                i += 2
                continue
            }
            if key_form.kind == .Keyword && key_form.text == ":as" {
                err_as, ok_as := emit_data_pattern_bindings(e, target, source)
                if !ok_as {
                    return err_as, false
                }
                i += 2
                continue
            }
            if key_form.kind == .Keyword &&
               (key_form.text == ":keys" || key_form.text == ":strs" || key_form.text == ":syms" || strings.has_suffix(key_form.text, "/keys")) {
                for local_form in target.items {
                    lookup_key := data_shorthand_key(key_form.text, local_form.text, key_form.span)
                    key_temp, err_key, ok_key := emit_data_pattern_literal_temp(e, lookup_key)
                    if !ok_key {
                        return err_key, false
                    }
                    child := thread_temp_name(e)
                    present := thread_temp_name(e)
                    emit_line(e, fmt.tprintf("%s, %s := kvist_data_get_present(%s, %s)", child, present, source, key_temp))
                    local_name := map_name(local_form.text)
                    if default_form, has_default := data_pattern_default_for_name(pattern, local_name); has_default {
                        owned_child := thread_temp_name(e)
                        emit_line(e, fmt.tprintf("%s := Data{{}}", owned_child))
                        emit_line(e, fmt.tprintf("if %s {{", present))
                        e.indent += 1
                        emit_line(e, fmt.tprintf("%s = kvist_data_retain(%s)", owned_child, child))
                        e.indent -= 1
                        emit_line(e, "} else {")
                        e.indent += 1
                        fallback, err_fallback, ok_fallback := emit_expr_for_expected_type(e, default_form, "Data")
                        if !ok_fallback {
                            return err_fallback, false
                        }
                        if !form_produces_owned_managed_type(e, default_form, "Data") {
                            fallback = emit_call_text("kvist_data_retain", []string{fallback})
                        }
                        emit_prefixed_expr_mapped(e, fmt.tprintf("%s = ", owned_child), fallback, default_form.span)
                        e.indent -= 1
                        emit_line(e, "}")
                        emit_line(e, fmt.tprintf("defer kvist_data_release(%s)", owned_child))
                        child = owned_child
                    }
                    err_local, ok_local := emit_data_pattern_bindings(e, local_form, child)
                    if !ok_local {
                        return err_local, false
                    }
                }
                i += 2
                continue
            }
            key_temp, err_key, ok_key := emit_data_pattern_literal_temp(e, target)
            if !ok_key {
                return err_key, false
            }
            child := thread_temp_name(e)
            present := thread_temp_name(e)
            emit_line(e, fmt.tprintf("%s, %s := kvist_data_get_present(%s, %s)", child, present, source, key_temp))
            if key_form.kind == .Symbol {
                local_name := map_name(key_form.text)
                if default_form, has_default := data_pattern_default_for_name(pattern, local_name); has_default {
                    owned_child := thread_temp_name(e)
                    emit_line(e, fmt.tprintf("%s := Data{{}}", owned_child))
                    emit_line(e, fmt.tprintf("if %s {{", present))
                    e.indent += 1
                    emit_line(e, fmt.tprintf("%s = kvist_data_retain(%s)", owned_child, child))
                    e.indent -= 1
                    emit_line(e, "} else {")
                    e.indent += 1
                    fallback, err_fallback, ok_fallback := emit_expr_for_expected_type(e, default_form, "Data")
                    if !ok_fallback {
                        return err_fallback, false
                    }
                    if !form_produces_owned_managed_type(e, default_form, "Data") {
                        fallback = emit_call_text("kvist_data_retain", []string{fallback})
                    }
                    emit_prefixed_expr_mapped(e, fmt.tprintf("%s = ", owned_child), fallback, default_form.span)
                    e.indent -= 1
                    emit_line(e, "}")
                    emit_line(e, fmt.tprintf("defer kvist_data_release(%s)", owned_child))
                    child = owned_child
                }
            }
            err_target, ok_target := emit_data_pattern_bindings(e, key_form, child, pattern)
            if !ok_target {
                return err_target, false
            }
            i += 2
        }
        return {}, true
    case:
        return Compile_Error{message = "unsupported Data destructuring pattern", span = pattern.span}, false
    }
}

emit_data_let_binding :: proc(e: ^Emitter, binding: Binding) -> (Compile_Error, bool) {
    if !data_binding_rhs_is_data(e, binding.value) {
        return Compile_Error{
            message = "Data destructuring requires a statically known Data value; bind or annotate an opaque imported result as Data first",
            span = binding.value.span,
        }, false
    }
    names: [dynamic]string
    defer delete(names)
    err_pattern, ok_pattern := validate_data_pattern_names(binding.target, &names, true)
    if !ok_pattern {
        return err_pattern, false
    }
    mark_data_type(e)
    value, err_value, ok_value := emit_expr_for_expected_type(e, binding.value, "Data")
    if !ok_value {
        return err_value, false
    }
    source := thread_temp_name(e)
    emit_owned_data_local(e, source, value, binding.value.span, form_produces_owned_managed_type(e, binding.value, "Data"))
    return emit_data_pattern_bindings(e, binding.target, source)
}

match_pattern_is_catchall :: proc(form: CST_Form) -> bool {
    return (form.kind == .Keyword && form.text == ":else") ||
           (form.kind == .Symbol && form.text == "_")
}

match_kind_name :: proc(form: CST_Form) -> (string, bool) {
    if form.kind != .Keyword {
        return "", false
    }
    switch form.text {
    case ":nil": return "Nil", true
    case ":bool": return "Bool", true
    case ":int": return "Int", true
    case ":float": return "Float", true
    case ":string": return "String", true
    case ":symbol": return "Symbol", true
    case ":keyword": return "Keyword", true
    case ":list": return "List", true
    case ":vector": return "Vector", true
    case ":map": return "Map", true
    case ":set": return "Set", true
    case ":tagged": return "Tagged", true
    }
    return "", false
}

match_pattern_is_literal :: proc(form: CST_Form) -> bool {
    #partial switch form.kind {
    case .Nil, .Bool, .Number, .String, .Keyword:
        return true
    case .List:
        return len(form.items) == 2 &&
               form.items[0].kind == .Symbol &&
               form.items[0].text == "quote" &&
               form.items[1].kind == .Symbol
    case:
        return false
    }
}

match_literals_equal :: proc(a, b: CST_Form) -> bool {
    if !match_pattern_is_literal(a) || !match_pattern_is_literal(b) || a.kind != b.kind {
        return false
    }
    if a.kind == .Nil {
        return true
    }
    if a.kind == .List {
        return a.items[1].text == b.items[1].text
    }
    return a.text == b.text
}

validate_match_pattern :: proc(form: CST_Form, names: ^[dynamic]string) -> (Compile_Error, bool) {
    if match_pattern_is_catchall(form) || match_pattern_is_literal(form) {
        return {}, true
    }
    #partial switch form.kind {
    case .Symbol:
        return data_pattern_append_name(names, form)
    case .Vector:
        saw_rest := false
        i := 0
        for i < len(form.items) {
            if form.items[i].kind == .Symbol && form.items[i].text == "&" {
                if saw_rest || i+2 != len(form.items) {
                    return Compile_Error{message = "match sequence pattern expects one final binding after &", span = form.items[i].span}, false
                }
                saw_rest = true
                err_rest, ok_rest := validate_match_pattern(form.items[i+1], names)
                if !ok_rest {
                    return err_rest, false
                }
                i += 2
                continue
            }
            err_item, ok_item := validate_match_pattern(form.items[i], names)
            if !ok_item {
                return err_item, false
            }
            i += 1
        }
    case .Brace:
        if len(form.items)%2 != 0 {
            return Compile_Error{message = "match map pattern expects literal-key/pattern pairs", span = form.span}, false
        }
        i := 0
        for i < len(form.items) {
            if !match_pattern_is_literal(form.items[i]) {
                return Compile_Error{message = "match map keys must be compile-time Data literals", span = form.items[i].span}, false
            }
            err_value, ok_value := validate_match_pattern(form.items[i+1], names)
            if !ok_value {
                return err_value, false
            }
            i += 2
        }
    case .Set:
        for item in form.items {
            if !match_pattern_is_literal(item) {
                return Compile_Error{message = "match set patterns are exact and may contain only literals", span = item.span}, false
            }
        }
    case .List:
        if len(form.items) != 3 || form.items[0].kind != .Symbol {
            return Compile_Error{message = "match list pattern expects (as name pattern) or (kind :kind pattern)", span = form.span}, false
        }
        if form.items[0].text == "as" {
            if form.items[1].kind != .Symbol || form.items[1].text == "_" {
                return Compile_Error{message = "match as pattern expects a binding name", span = form.items[1].span}, false
            }
            err_name, ok_name := data_pattern_append_name(names, form.items[1])
            if !ok_name {
                return err_name, false
            }
            return validate_match_pattern(form.items[2], names)
        }
        if form.items[0].text == "kind" {
            if _, ok_kind := match_kind_name(form.items[1]); !ok_kind {
                return Compile_Error{message = "unknown Data kind in match pattern", span = form.items[1].span}, false
            }
            return validate_match_pattern(form.items[2], names)
        }
        return Compile_Error{message = "match list pattern expects (as name pattern) or (kind :kind pattern)", span = form.span}, false
    case:
        return Compile_Error{message = "unsupported Data match pattern", span = form.span}, false
    }
    return {}, true
}

emit_match_pattern_condition :: proc(e: ^Emitter, pattern: CST_Form, source: string) -> (string, Compile_Error, bool) {
    if match_pattern_is_catchall(pattern) || pattern.kind == .Symbol {
        return "true", {}, true
    }
    if match_pattern_is_literal(pattern) {
        literal, err_literal, ok_literal := emit_data_pattern_literal_temp(e, pattern)
        if !ok_literal {
            return "", err_literal, false
        }
        return fmt.tprintf("kvist_data_equal(%s, %s)", source, literal), {}, true
    }
    conditions: [dynamic]string
    defer delete(conditions)
    #partial switch pattern.kind {
    case .Vector:
        rest_index := -1
        for item, idx in pattern.items {
            if item.kind == .Symbol && item.text == "&" {
                rest_index = idx
                break
            }
        }
        fixed_count := len(pattern.items)
        if rest_index >= 0 {
            fixed_count = rest_index
        }
        append(&conditions, fmt.tprintf("(%s.kind == .List || %s.kind == .Vector)", source, source))
        if rest_index >= 0 {
            append(&conditions, fmt.tprintf("len(%s.payload.items) >= %d", source, fixed_count))
        } else {
            append(&conditions, fmt.tprintf("len(%s.payload.items) == %d", source, fixed_count))
        }
        for item, idx in pattern.items[:fixed_count] {
            child := fmt.tprintf("kvist_data_nth_or_nil(%s, %d)", source, idx)
            condition, err_condition, ok_condition := emit_match_pattern_condition(e, item, child)
            if !ok_condition {
                return "", err_condition, false
            }
            append(&conditions, condition)
        }
    case .Brace:
        append(&conditions, fmt.tprintf("%s.kind == .Map", source))
        i := 0
        for i < len(pattern.items) {
            key, err_key, ok_key := emit_data_pattern_literal_temp(e, pattern.items[i])
            if !ok_key {
                return "", err_key, false
            }
            append(&conditions, fmt.tprintf("kvist_data_contains(%s, %s)", source, key))
            child := fmt.tprintf("kvist_data_get(%s, %s)", source, key)
            condition, err_condition, ok_condition := emit_match_pattern_condition(e, pattern.items[i+1], child)
            if !ok_condition {
                return "", err_condition, false
            }
            append(&conditions, condition)
            i += 2
        }
    case .Set:
        append(&conditions, fmt.tprintf("%s.kind == .Set", source))
        append(&conditions, fmt.tprintf("len(%s.payload.items) == %d", source, len(pattern.items)))
        for item in pattern.items {
            literal, err_literal, ok_literal := emit_data_pattern_literal_temp(e, item)
            if !ok_literal {
                return "", err_literal, false
            }
            append(&conditions, fmt.tprintf("kvist_data_contains(%s, %s)", source, literal))
        }
    case .List:
        if pattern.items[0].text == "as" {
            return emit_match_pattern_condition(e, pattern.items[2], source)
        }
        kind_name, _ := match_kind_name(pattern.items[1])
        append(&conditions, fmt.tprintf("%s.kind == .%s", source, kind_name))
        inner, err_inner, ok_inner := emit_match_pattern_condition(e, pattern.items[2], source)
        if !ok_inner {
            return "", err_inner, false
        }
        append(&conditions, inner)
    case:
        return "", Compile_Error{message = "unsupported Data match pattern", span = pattern.span}, false
    }
    return strings.join(conditions[:], " && ", context.allocator), {}, true
}

emit_match_capture_bindings :: proc(e: ^Emitter, pattern: CST_Form, source: string) -> (Compile_Error, bool) {
    if match_pattern_is_catchall(pattern) || match_pattern_is_literal(pattern) {
        return {}, true
    }
    #partial switch pattern.kind {
    case .Symbol:
        return emit_data_pattern_bindings(e, pattern, source)
    case .Vector:
        item_index := 0
        i := 0
        for i < len(pattern.items) {
            item := pattern.items[i]
            if item.kind == .Symbol && item.text == "&" {
                rest_temp := thread_temp_name(e)
                emit_owned_data_local(e, rest_temp, fmt.tprintf("kvist_data_rest_from(%s, %d)", source, item_index), item.span, true)
                return emit_match_capture_bindings(e, pattern.items[i+1], rest_temp)
            }
            child := fmt.tprintf("kvist_data_nth_or_nil(%s, %d)", source, item_index)
            err_child, ok_child := emit_match_capture_bindings(e, item, child)
            if !ok_child {
                return err_child, false
            }
            item_index += 1
            i += 1
        }
    case .Brace:
        i := 0
        for i < len(pattern.items) {
            key, err_key, ok_key := emit_data_pattern_literal_temp(e, pattern.items[i])
            if !ok_key {
                return err_key, false
            }
            child := fmt.tprintf("kvist_data_get(%s, %s)", source, key)
            err_child, ok_child := emit_match_capture_bindings(e, pattern.items[i+1], child)
            if !ok_child {
                return err_child, false
            }
            i += 2
        }
    case .Set:
        return {}, true
    case .List:
        if pattern.items[0].text == "as" {
            err_alias, ok_alias := emit_data_pattern_bindings(e, pattern.items[1], source)
            if !ok_alias {
                return err_alias, false
            }
        }
        return emit_match_capture_bindings(e, pattern.items[2], source)
    }
    return {}, true
}

validate_match_form :: proc(e: ^Emitter, form: CST_Form) -> (Compile_Error, bool) {
    if len(form.items) < 6 || (len(form.items)-2)%2 != 0 {
        return Compile_Error{message = "match expects a Data subject followed by pattern/result pairs and a final :else or _ arm", span = form.span}, false
    }
    subject := form.items[1]
    literal_subject := match_pattern_is_literal(subject) ||
                       subject.kind == .Vector ||
                       subject.kind == .Brace ||
                       subject.kind == .Set
    if !literal_subject {
        if ty, ok_ty := obvious_form_type(e, subject); !ok_ty || ty != "Data" {
            return Compile_Error{message = "match subject must be statically known as Data", span = subject.span}, false
        }
    }
    previous_literals: [dynamic]CST_Form
    defer delete(previous_literals)
    for i := 2; i < len(form.items); i += 2 {
        pattern := form.items[i]
        names: [dynamic]string
        err_pattern, ok_pattern := validate_match_pattern(pattern, &names)
        delete(names)
        if !ok_pattern {
            return err_pattern, false
        }
        if match_pattern_is_catchall(pattern) && i != len(form.items)-2 {
            return Compile_Error{message = "match catch-all must be the final arm", span = pattern.span}, false
        }
        if match_pattern_is_literal(pattern) {
            for previous in previous_literals {
                if match_literals_equal(previous, pattern) {
                    return Compile_Error{message = "duplicate exact literal match arm", span = pattern.span}, false
                }
            }
            append(&previous_literals, pattern)
        }
    }
    if !match_pattern_is_catchall(form.items[len(form.items)-2]) {
        return Compile_Error{message = "match requires a final :else or _ catch-all arm", span = form.items[len(form.items)-2].span}, false
    }
    return {}, true
}

emit_match_stmt :: proc(e: ^Emitter, form: CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    err_form, ok_form := validate_match_form(e, form)
    if !ok_form {
        return err_form, false
    }
    mark_data_type(e)
    subject_value, err_subject, ok_subject := emit_expr_for_expected_type(e, form.items[1], "Data")
    if !ok_subject {
        return err_subject, false
    }
    emit_line(e, "{")
    e.indent += 1
    push_local_type_scope(e)
    subject := thread_temp_name(e)
    subject_form := form.items[1]
    contextual_literal := match_pattern_is_literal(subject_form) ||
                          subject_form.kind == .Vector ||
                          subject_form.kind == .Brace ||
                          subject_form.kind == .Set
    emit_owned_data_local(
        e,
        subject,
        subject_value,
        subject_form.span,
        contextual_literal || form_produces_owned_managed_type(e, subject_form, "Data"),
    )
    conditions: [dynamic]string
    defer delete(conditions)
    for i := 2; i < len(form.items); i += 2 {
        pattern := form.items[i]
        catchall := match_pattern_is_catchall(pattern)
        condition := "true"
        if !catchall {
            err_condition: Compile_Error
            ok_condition: bool
            condition, err_condition, ok_condition = emit_match_pattern_condition(e, pattern, subject)
            if !ok_condition {
                pop_local_type_scope(e)
                return err_condition, false
            }
        }
        append(&conditions, condition)
    }
    arm_index := 0
    for i := 2; i < len(form.items); i += 2 {
        pattern := form.items[i]
        result := form.items[i+1]
        catchall := match_pattern_is_catchall(pattern)
        condition := conditions[arm_index]
        if i == 2 {
            emit_line(e, fmt.tprintf("if %s {{", condition))
        } else if catchall {
            emit_line(e, "} else {")
        } else {
            emit_line(e, fmt.tprintf("}} else if %s {{", condition))
        }
        e.indent += 1
        push_local_type_scope(e)
        err_captures, ok_captures := emit_match_capture_bindings(e, pattern, subject)
        if !ok_captures {
            pop_local_type_scope(e)
            pop_local_type_scope(e)
            return err_captures, false
        }
        err_result, ok_result := emit_if_branch_stmt(e, result, last_in_proc, returns_when_final(last_in_proc, returns))
        pop_local_type_scope(e)
        if !ok_result {
            pop_local_type_scope(e)
            return err_result, false
        }
        e.indent -= 1
        arm_index += 1
    }
    emit_line(e, "}")
    pop_local_type_scope(e)
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

discard_mapped_name :: proc(text: string) -> string {
    name := map_name(text)
    if name == "_" {
        delete(name)
        return ""
    }
    return name
}

binding_output_name :: proc(name: string) -> string {
    if name == "" {
        return "_"
    }
    return name
}

is_discard_binding_name :: proc(name: string) -> bool {
    return name == "" || name == "_"
}

emit_loop_binding_assignment :: proc(e: ^Emitter, name, value: string) {
    if is_discard_binding_name(name) {
        emit_line(e, fmt.tprintf("_ = %s", value))
    } else {
        emit_line(e, fmt.tprintf("%s := %s", name, value))
    }
}

let_binding_has_defer_marker :: proc(items: []CST_Form, idx: int) -> bool {
    return idx < len(items) &&
           items[idx].kind == .Keyword &&
           items[idx].text == ":defer"
}

let_binding_has_errdefer_marker :: proc(items: []CST_Form, idx: int) -> bool {
    return idx < len(items) &&
           items[idx].kind == .Keyword &&
           items[idx].text == ":errdefer"
}

let_binding_has_defer_with_marker :: proc(items: []CST_Form, idx: int) -> bool {
    return idx < len(items) &&
           items[idx].kind == .Keyword &&
           items[idx].text == ":defer-with"
}

let_binding_or_modifier :: proc(items: []CST_Form, idx: int) -> (string, bool) {
    if idx >= len(items) || items[idx].kind != .Keyword {
        return "", false
    }
    switch items[idx].text {
    case ":or-return", ":or-break", ":or-continue":
        return items[idx].text[1:], true
    case:
        return "", false
    }
}

parse_let_bindings :: proc(form: CST_Form) -> (bindings: [dynamic]Binding, err: Compile_Error, ok: bool) {
    if form.kind != .Vector {
        return bindings, Compile_Error{message = "let expects a binding vector", span = form.span}, false
    }
    i := 0
    for i < len(form.items) {
        target := form.items[i]
        #partial switch target.kind {
        case .Vector:
            if i+1 >= len(form.items) {
                return bindings, Compile_Error{message = "multi-return binding missing value", span = target.span}, false
            }
            names: [dynamic]string
            simple_symbols := true
            for part in target.items {
                if part.kind == .Symbol {
                    append(&names, discard_mapped_name(part.text))
                } else {
                    simple_symbols = false
                }
            }
            or_modifier, has_or_modifier := let_binding_or_modifier(form.items[:], i+2)
            if has_or_modifier && !simple_symbols {
                return bindings, Compile_Error{message = "or-* multi-return binding expects symbols", span = target.span}, false
            }
            deferred_delete := false
            err_deferred_delete := false
            defer_with_cleanup := false
            cleanup := CST_Form{}
            next_i := i + 2
            if has_or_modifier {
                if len(names) != 2 {
                    return bindings, Compile_Error{message = "or-* let binding expects exactly two names", span = target.span}, false
                }
                if names[1] != "ok" && names[1] != "err" {
                    return bindings, Compile_Error{message = "or-* let binding requires [value ok] or [value err]", span = target.span}, false
                }
                next_i += 1
                for next_i < len(form.items) {
                    if let_binding_has_defer_marker(form.items[:], next_i) {
                        if deferred_delete {
                            return bindings, Compile_Error{message = "duplicate :defer binding marker", span = form.items[next_i].span}, false
                        }
                        deferred_delete = true
                        next_i += 1
                    } else if let_binding_has_errdefer_marker(form.items[:], next_i) {
                        if err_deferred_delete {
                            return bindings, Compile_Error{message = "duplicate :errdefer binding marker", span = form.items[next_i].span}, false
                        }
                        err_deferred_delete = true
                        next_i += 1
                    } else if let_binding_has_defer_with_marker(form.items[:], next_i) {
                        if defer_with_cleanup {
                            return bindings, Compile_Error{message = "duplicate :defer-with binding marker", span = form.items[next_i].span}, false
                        }
                        if next_i+1 >= len(form.items) {
                            return bindings, Compile_Error{message = ":defer-with expects a cleanup function", span = form.items[next_i].span}, false
                        }
                        defer_with_cleanup = true
                        cleanup = form.items[next_i+1]
                        next_i += 2
                    } else {
                        break
                    }
                }
                cleanup_count := 0
                if deferred_delete {
                    cleanup_count += 1
                }
                if err_deferred_delete {
                    cleanup_count += 1
                }
                if defer_with_cleanup {
                    cleanup_count += 1
                }
                if cleanup_count > 1 {
                    return bindings, Compile_Error{message = "use only one cleanup marker: :defer, :errdefer, or :defer-with", span = target.span}, false
                }
                if err_deferred_delete && (or_modifier != "or-return" || names[1] != "err") {
                    return bindings, Compile_Error{message = ":errdefer is only supported on [value err] :or-return bindings", span = target.span}, false
                }
            } else if let_binding_has_defer_marker(form.items[:], i+2) {
                return bindings, Compile_Error{message = ":defer binding marker is only supported on named local bindings or [value ok/err] :or-* bindings", span = form.items[i+2].span}, false
            } else if let_binding_has_errdefer_marker(form.items[:], i+2) {
                return bindings, Compile_Error{message = ":errdefer is only supported on [value err] :or-return bindings", span = form.items[i+2].span}, false
            } else if let_binding_has_defer_with_marker(form.items[:], i+2) {
                return bindings, Compile_Error{message = ":defer-with binding marker is only supported on named local bindings or [value ok/err] :or-* bindings", span = form.items[i+2].span}, false
            }
            append(&bindings, Binding{
                is_destructure      = !has_or_modifier,
                is_result_binding   = has_or_modifier,
                is_data_destructure = !simple_symbols,
                pattern             = names,
                target              = target,
                deferred_delete     = deferred_delete,
                err_deferred_delete = err_deferred_delete,
                defer_with_cleanup  = defer_with_cleanup,
                cleanup             = cleanup,
                or_modifier         = or_modifier,
                target_span         = target.span,
                value               = form.items[i+1],
            })
            i = next_i
        case .Symbol:
            if len(target.text) > 0 && target.text[len(target.text)-1] == ':' {
                if i+2 >= len(form.items) {
                    return bindings, Compile_Error{message = "typed binding missing type or value", span = target.span}, false
                }
                type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], i+1)
                if !ok_type {
                    return bindings, err_type, false
                }
                if next_i >= len(form.items) {
                    return bindings, Compile_Error{message = "typed binding missing value", span = target.span}, false
                }
                deferred_delete := false
                defer_with_cleanup := false
                cleanup := CST_Form{}
                marker_i := next_i + 1
                if let_binding_has_defer_marker(form.items[:], marker_i) {
                    deferred_delete = true
                    marker_i += 1
                } else if let_binding_has_defer_with_marker(form.items[:], marker_i) {
                    if marker_i+1 >= len(form.items) {
                        return bindings, Compile_Error{message = ":defer-with expects a cleanup function", span = form.items[marker_i].span}, false
                    }
                    defer_with_cleanup = true
                    cleanup = form.items[marker_i+1]
                    marker_i += 2
                } else if let_binding_has_errdefer_marker(form.items[:], marker_i) {
                    return bindings, Compile_Error{message = ":errdefer is only supported on [value err] :or-return bindings", span = form.items[marker_i].span}, false
                }
                name := discard_mapped_name(target.text[:len(target.text)-1])
                append(&bindings, Binding{
                    name               = name,
                    is_typed           = true,
                    ty                 = type_text,
                    deferred_delete    = deferred_delete,
                    defer_with_cleanup = defer_with_cleanup,
                    cleanup            = cleanup,
                    target_span        = target.span,
                    value              = form.items[next_i],
                })
                i = next_i + 1
                if deferred_delete || defer_with_cleanup {
                    i = marker_i
                }
            } else {
                if i+1 >= len(form.items) {
                    return bindings, Compile_Error{message = "binding missing value", span = target.span}, false
                }
                deferred_delete := false
                defer_with_cleanup := false
                cleanup := CST_Form{}
                next_i := i + 2
                if let_binding_has_defer_marker(form.items[:], next_i) {
                    deferred_delete = true
                    next_i += 1
                } else if let_binding_has_defer_with_marker(form.items[:], next_i) {
                    if next_i+1 >= len(form.items) {
                        return bindings, Compile_Error{message = ":defer-with expects a cleanup function", span = form.items[next_i].span}, false
                    }
                    defer_with_cleanup = true
                    cleanup = form.items[next_i+1]
                    next_i += 2
                } else if let_binding_has_errdefer_marker(form.items[:], next_i) {
                    return bindings, Compile_Error{message = ":errdefer is only supported on [value err] :or-return bindings", span = form.items[next_i].span}, false
                }
                name := discard_mapped_name(target.text)
                append(&bindings, Binding{
                    name               = name,
                    deferred_delete    = deferred_delete,
                    defer_with_cleanup = defer_with_cleanup,
                    cleanup            = cleanup,
                    target_span        = target.span,
                    value              = form.items[i+1],
                })
                i = next_i
            }
        case .Brace:
            if i+1 >= len(form.items) {
                return bindings, Compile_Error{message = "Data map destructuring binding missing value", span = target.span}, false
            }
            if let_binding_has_defer_marker(form.items[:], i+2) ||
               let_binding_has_errdefer_marker(form.items[:], i+2) ||
               let_binding_has_defer_with_marker(form.items[:], i+2) {
                return bindings, Compile_Error{message = "Data destructuring is automatically managed and does not accept ownership modifiers", span = form.items[i+2].span}, false
            }
            append(&bindings, Binding{
                is_destructure      = true,
                is_data_destructure = true,
                target              = target,
                target_span         = target.span,
                value               = form.items[i+1],
            })
            i += 2
        case:
            return bindings, Compile_Error{message = "unsupported binding target", span = target.span}, false
        }
    }
    return bindings, {}, true
}

emit_body_forms :: proc(e: ^Emitter, body: []CST_Form, returns: Return_Spec) -> (Compile_Error, bool) {
    for form, idx in body {
        last := idx == len(body)-1
        start_line := e.line
        err_stmt, ok_stmt := emit_stmt(e, form, last, returns)
        if !ok_stmt {
            return err_stmt, false
        }
        record_source_map(e, start_line, e.line - 1, form.span)
    }
    return {}, true
}

returns_when_final :: proc(last_in_proc: bool, returns: Return_Spec) -> Return_Spec {
    if last_in_proc {
        return returns
    }
    return Return_Spec{kind = .None}
}

is_local_decl_head :: proc(head: string) -> bool {
    switch head {
    case "def", "defstruct", "defenum", "defunion":
        return true
    case:
        return false
    }
}

emit_local_var_stmt :: proc(e: ^Emitter, form: CST_Form) -> (Compile_Error, bool) {
    if len(form.items) < 3 {
        return Compile_Error{message = "defvar expects a name, optional type, and value", span = form.span}, false
    }
    target := form.items[1]
    if target.kind != .Symbol {
        return Compile_Error{message = "defvar expects a symbol name", span = target.span}, false
    }

    name := target.text
    ty := ""
    value_index := 2
    is_typed := false
    if len(name) > 0 && name[len(name)-1] == ':' {
        if len(name) == 1 {
            return Compile_Error{message = "defvar expects a name before :", span = target.span}, false
        }
        parsed_ty, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], 2)
        if !ok_type {
            return err_type, false
        }
        if next_i >= len(form.items) {
            local_name := map_name(name[:len(name)-1])
            emit_line(e, fmt.tprintf("%s: %s", local_name, parsed_ty))
            bind_local_type(e, local_name, parsed_ty)
            return {}, true
        }
        ty = parsed_ty
        value_index = next_i
        name = name[:len(name)-1]
        is_typed = true
    }
    if value_index+1 != len(form.items) {
        return Compile_Error{message = "defvar expects exactly one value", span = form.items[value_index+1].span}, false
    }

    value_form := form.items[value_index]
    err_owned, bad_owned := owned_result_usage_error(value_form, true, e)
    if bad_owned {
        return err_owned, false
    }
    value, err_value, ok_value := emit_expr_for_expected_type(e, value_form, ty)
    if !ok_value {
        return err_value, false
    }

    local_name := map_name(name)
    if is_typed {
        emit_prefixed_expr_mapped(e, fmt.tprintf("%s: %s = ", local_name, ty), value, value_form.span)
        bind_local_type(e, local_name, ty)
    } else {
        emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", local_name), value, value_form.span)
        if form_ty, ok_ty := obvious_form_type(e, value_form); ok_ty {
            bind_local_type(e, local_name, form_ty)
        }
    }
    return {}, true
}

emit_local_decl_stmt :: proc(e: ^Emitter, form: CST_Form) -> (Compile_Error, bool) {
    decl_form := form

    decl, err_decl, ok_decl := parse_decl(CST_Top_Form{form = decl_form})
    if !ok_decl {
        return err_decl, false
    }
    #partial switch decl.kind {
    case .Const, .Struct, .Enum, .Union:
    case:
        return Compile_Error{message = "unsupported local declaration form", span = form.span}, false
    }

    err_emit, ok_emit := emit_decl(e, IR_Decl(decl))
    if !ok_emit {
        return err_emit, false
    }
    if decl.kind == .Struct {
        append(&e.local_structs, decl.struct_decl)
    }
    if decl.kind == .Union {
        append(&e.local_unions, decl.union_decl)
    }
    return {}, true
}

emit_if_branch_stmt :: proc(e: ^Emitter, branch: CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    if branch.kind == .List && len(branch.items) > 0 && branch.items[0].kind == .Symbol && branch.items[0].text == "do" {
        return emit_body_forms(e, branch.items[1:], returns)
    }
    return emit_stmt(e, branch, last_in_proc, returns)
}

emit_if_like_with_prefix :: proc(e: ^Emitter, head: string, form: CST_Form, last_in_proc: bool, returns: Return_Spec, prefix: string = "") -> (Compile_Error, bool) {
    if len(form.items) < 3 || len(form.items) > 4 {
        return Compile_Error{message = fmt.tprintf("%s expects test, then, and optional else", head), span = form.span}, false
    }
    test, err_test, ok_test := emit_expr(e, form.items[1])
    if !ok_test {
        return err_test, false
    }
    emit_indent(e)
    strings.write_string(&e.builder, prefix)
    strings.write_string(&e.builder, "if ")
    strings.write_string(&e.builder, test)
    record_current_line_fragment_map(e, len(prefix)+len("if "), test, form.items[1].span)
    strings.write_string(&e.builder, " {")
    emit_raw_newline(e)
    e.indent += 1
    branch_returns := returns_when_final(last_in_proc, returns)
    push_local_type_scope(e)
    err_then, ok_then := emit_if_branch_stmt(e, form.items[2], last_in_proc, branch_returns)
    pop_local_type_scope(e)
    if !ok_then {
        return err_then, false
    }
    e.indent -= 1
    emit_line(e, "}")
    if len(form.items) == 4 {
        else_branch := form.items[3]
        if form_is_zero_call(else_branch) && branch_returns.kind != .Single {
            err_zero, ok_zero := validate_zero_stmt(else_branch)
            if !ok_zero {
                return err_zero, false
            }
            return {}, true
        }
        if else_branch.kind == .List && len(else_branch.items) > 0 &&
           else_branch.items[0].kind == .Symbol && else_branch.items[0].text == "if" {
            return emit_if_like_with_prefix(e, "if", else_branch, last_in_proc, returns, "else ")
        }
        emit_indent(e)
        strings.write_string(&e.builder, "else {")
        emit_raw_newline(e)
        e.indent += 1
        push_local_type_scope(e)
        err_else, ok_else := emit_if_branch_stmt(e, else_branch, last_in_proc, branch_returns)
        pop_local_type_scope(e)
        if !ok_else {
            return err_else, false
        }
        e.indent -= 1
        emit_line(e, "}")
    }
    return {}, true
}

emit_if_like :: proc(e: ^Emitter, head: string, form: CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    return emit_if_like_with_prefix(e, head, form, last_in_proc, returns)
}

is_else_keyword :: proc(form: CST_Form) -> bool {
    return form.kind == .Keyword && form.text == ":else"
}

emit_with_allocator_stmt :: proc(e: ^Emitter, form: CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    if len(form.items) < 3 {
        return Compile_Error{message = "with-allocator expects binding vector and body", span = form.span}, false
    }
    binding := form.items[1]
    if binding.kind != .Vector || len(binding.items) != 2 || binding.items[0].kind != .Symbol {
        return Compile_Error{message = "with-allocator expects [name allocator] binding", span = binding.span}, false
    }
    allocator_name := map_name(binding.items[0].text)
    allocator_expr, err_allocator, ok_allocator := emit_expr(e, binding.items[1])
    if !ok_allocator {
        return err_allocator, false
    }

    e.temp_counter += 1
    old_allocator := fmt.tprintf("kvist_old_allocator_%d", e.temp_counter)
    emit_line(e, "{")
    e.indent += 1
    push_local_type_scope(e)
    emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", allocator_name), allocator_expr, binding.items[1].span)
    emit_line(e, fmt.tprintf("%s := context.allocator", old_allocator))
    emit_line(e, fmt.tprintf("context.allocator = %s", allocator_name))
    emit_line(e, fmt.tprintf("defer context.allocator = %s", old_allocator))

    body: [dynamic]CST_Form
    for item in form.items[2:] {
        append(&body, item)
    }
    err_body, ok_body := emit_body_forms(e, body[:], returns_when_final(last_in_proc, returns))
    pop_local_type_scope(e)
    if !ok_body {
        return err_body, false
    }

    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

emit_with_temp_allocator_stmt :: proc(e: ^Emitter, form: CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    if len(form.items) < 3 {
        return Compile_Error{message = "with-temp-allocator expects binding vector and body", span = form.span}, false
    }
    binding := form.items[1]
    if binding.kind != .Vector || len(binding.items) != 1 || binding.items[0].kind != .Symbol {
        return Compile_Error{message = "with-temp-allocator expects [name] binding", span = binding.span}, false
    }
    allocator_name := map_name(binding.items[0].text)

    e.temp_counter += 1
    temp_scope := fmt.tprintf("kvist_temp_scope_%d", e.temp_counter)
    e.temp_counter += 1
    old_allocator := fmt.tprintf("kvist_old_allocator_%d", e.temp_counter)

    emit_line(e, "{")
    e.indent += 1
    push_local_type_scope(e)
    emit_line(e, fmt.tprintf("%s := runtime.default_temp_allocator_temp_begin()", temp_scope))
    emit_line(e, fmt.tprintf("defer runtime.default_temp_allocator_temp_end(%s)", temp_scope))
    emit_line(e, fmt.tprintf("%s := context.temp_allocator", allocator_name))
    emit_line(e, fmt.tprintf("%s := context.allocator", old_allocator))
    emit_line(e, fmt.tprintf("context.allocator = %s", allocator_name))
    emit_line(e, fmt.tprintf("defer context.allocator = %s", old_allocator))

    body: [dynamic]CST_Form
    for item in form.items[2:] {
        append(&body, item)
    }
    err_escape, bad_escape := with_temp_allocator_escape_error(e, body[:], last_in_proc, returns)
    if bad_escape {
        return err_escape, false
    }
    err_body, ok_body := emit_body_forms(e, body[:], returns_when_final(last_in_proc, returns))
    pop_local_type_scope(e)
    if !ok_body {
        return err_body, false
    }

    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

case_type_payload_pattern :: proc(clause: CST_Form) -> (ty, binding: string, ignored: bool, err: Compile_Error, ok: bool) {
    if clause.kind != .List {
        return "", "", false, Compile_Error{message = "type-case expects (Type binding)", span = clause.span}, false
    }
    if len(clause.items) != 2 || clause.items[0].kind != .Symbol || clause.items[1].kind != .Symbol {
        return "", "", false, Compile_Error{message = "type-case expects (Type binding)", span = clause.span}, false
    }
    ty = map_name(clause.items[0].text)
    binding = map_name(clause.items[1].text)
    ignored = clause.items[1].text == "_"
    return ty, binding, ignored, {}, true
}

emit_case_type_payload_stmt :: proc(e: ^Emitter, form: CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    if len(form.items) < 5 {
        return Compile_Error{message = "case expects subject, clause/body pairs, and default", span = form.span}, false
    }
    if len(form.items)%2 == 0 {
        return Compile_Error{message = "case expects clause/body pairs followed by default", span = form.span}, false
    }

    subject, err_subject, ok_subject := emit_expr(e, form.items[1])
    if !ok_subject {
        return err_subject, false
    }

    temp := fmt.tprintf("kvist_case_%d", e.temp_counter + 1)
    e.temp_counter += 1

    emit_indent(e)
    strings.write_string(&e.builder, "switch ")
    strings.write_string(&e.builder, temp)
    strings.write_string(&e.builder, " in ")
    strings.write_string(&e.builder, subject)
    record_current_line_fragment_map(e, len("switch ") + len(temp) + len(" in "), subject, form.items[1].span)
    strings.write_string(&e.builder, " {")
    emit_raw_newline(e)

    branch_returns := returns_when_final(last_in_proc, returns)
    i := 2
    for i < len(form.items)-1 {
        clause := form.items[i]
        body := form.items[i+1]

        ty, binding, ignored, err_pattern, ok_pattern := case_type_payload_pattern(clause)
        if !ok_pattern {
            return err_pattern, false
        }

        emit_line_mapped(e, fmt.tprintf("case %s:", ty), clause.span)
        e.indent += 1
        push_local_type_scope(e)
        if !ignored {
            emit_line(e, fmt.tprintf("%s := %s", binding, temp))
            bind_local_type(e, binding, ty)
        }
        err_body, ok_body := emit_stmt(e, body, last_in_proc, branch_returns)
        pop_local_type_scope(e)
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1

        i += 2
    }

    default_form := form.items[len(form.items)-1]
    emit_line_mapped(e, "case:", default_form.span)
    e.indent += 1
    err_default, ok_default := emit_stmt(e, default_form, last_in_proc, branch_returns)
    if !ok_default {
        return err_default, false
    }
    e.indent -= 1

    emit_line(e, "}")
    return {}, true
}

emit_case_stmt :: proc(e: ^Emitter, form: CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    if len(form.items) >= 4 {
        i := 2
        for i < len(form.items)-1 {
            if form.items[i].kind != .List {
                return Compile_Error{message = "type-case expects (Type binding)", span = form.items[i].span}, false
            }
            i += 2
        }
    }
    return emit_case_type_payload_stmt(e, form, last_in_proc, returns)
}

emit_stmt :: proc(e: ^Emitter, form: CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    if form.kind != .List {
        expr: string
        err_expr: Compile_Error
        ok_expr: bool
        if last_in_proc && returns.kind == .Single {
            expr, err_expr, ok_expr = emit_expr_for_expected_type(e, form, returns.single_ty)
        } else {
            expr, err_expr, ok_expr = emit_expr(e, form)
        }
        if !ok_expr {
            return err_expr, false
        }
        if last_in_proc && returns.kind != .None {
            expr = managed_return_value_text(e, form, expr, returns)
            emit_prefixed_expr_mapped(e, "return ", expr, form.span)
        } else if form_is_owned_allocation_result(form) || form_is_owned_constructor_result(form) {
            emit_discarded_expr(e, form, expr)
        } else {
            emit_prefixed_expr_mapped(e, "", expr, form.span)
        }
        return {}, true
    }

    if len(form.items) == 0 {
        return Compile_Error{message = "empty list statement", span = form.span}, false
    }

    head := form.items[0]
    if head.kind != .Symbol {
        expr: string
        err_expr: Compile_Error
        ok_expr: bool
        if last_in_proc && returns.kind == .Single {
            expr, err_expr, ok_expr = emit_expr_for_expected_type(e, form, returns.single_ty)
        } else {
            expr, err_expr, ok_expr = emit_expr(e, form)
        }
        if !ok_expr {
            return err_expr, false
        }
        if last_in_proc && returns.kind != .None {
            expr = managed_return_value_text(e, form, expr, returns)
            emit_prefixed_expr_mapped(e, "return ", expr, form.span)
        } else if form_is_owned_allocation_result(form) || form_is_owned_constructor_result(form) {
            emit_discarded_expr(e, form, expr)
        } else {
            emit_prefixed_expr_mapped(e, "", expr, form.span)
        }
        return {}, true
    }

    if head.text == "var" {
        return Compile_Error{message = "`var` has been removed; use `defvar`", span = head.span}, false
    }

    if head.text == "defvar" {
        return emit_local_var_stmt(e, form)
    }

    if is_local_decl_head(head.text) {
        return emit_local_decl_stmt(e, form)
    }

    switch builtin_macro_kind(head.text) {
    case .With_Allocator:
        return emit_with_allocator_stmt(e, form, last_in_proc, returns)
    case .With_Temp_Allocator:
        return emit_with_temp_allocator_stmt(e, form, last_in_proc, returns)
    case .None:
    }

    switch head.text {
    case "zero":
        if last_in_proc && returns.kind == .Single {
            value, err_value, ok_value := emit_expr_for_expected_type(e, form, returns.single_ty)
            if !ok_value {
                return err_value, false
            }
            value = managed_return_value_text(e, form, value, returns)
            emit_prefixed_expr_mapped(e, "return ", value, form.span)
            return {}, true
        }
        return validate_zero_stmt(form)
    case "inc!", "dec!", "toggle!", "negate!":
        return emit_unary_mutation_stmt(e, form, head.text)
    case "mut!":
        return emit_mut_bang_stmt(e, form)
    }

    canonical_head_text := head.text
    canonical_head, _, err_head, ok_head := resolve_kvist_head(e, head.text)
    if !ok_head {
        return err_head, false
    }
    canonical_head_text = canonical_head

    switch canonical_head_text {
    case "#partial":
        return Compile_Error{message = "#partial is not Kvist syntax; use case or cond", span = form.span}, false
    case "let":
        if len(form.items) < 3 {
            return Compile_Error{message = "let expects bindings and body", span = form.span}, false
        }
        bindings, err_bind, ok_bind := parse_let_bindings(form.items[1])
        if !ok_bind {
            return err_bind, false
        }
        err_tail, bad_tail := let_errdefer_tail_error(bindings[:], last_in_proc)
        if bad_tail {
            return err_tail, false
        }
        body: [dynamic]CST_Form
        for item in form.items[2:] {
            append(&body, item)
        }
        if last_in_proc && returns.kind != .None {
            err_let_return, bad_let_return := let_return_error(e, bindings[:], body[:])
            if bad_let_return {
                return err_let_return, false
            }
            err_let_defer_return, bad_let_defer_return := let_defer_return_error(bindings[:], body[:], last_in_proc, returns)
            if bad_let_defer_return {
                return err_let_defer_return, false
            }
        }
        push_local_type_scope(e)
        defer pop_local_type_scope(e)
        scoped := !last_in_proc
        if scoped {
            emit_line(e, "{")
            e.indent += 1
        }
        for binding in bindings {
            if binding_is_data_destructure(e, binding) {
                err_data, ok_data := emit_data_let_binding(e, binding)
                if !ok_data {
                    return err_data, false
                }
            } else if binding_value_is_let(binding) {
                err_flat, ok_flat := emit_let_value_binding_assignment(e, binding)
                if !ok_flat {
                    return err_flat, false
                }
            } else {
                value: string
                err_value: Compile_Error
                ok_value: bool
                if form_has_nested_owned_value(binding.value, e) {
                    value, err_value, ok_value = emit_expr_with_owned_nested_temps(e, binding.value)
                } else {
                    err_owned, bad_owned := owned_result_usage_error(binding.value, true, e)
                    if bad_owned {
                        return err_owned, false
                    }
                    value, err_value, ok_value = emit_expr_for_expected_type(e, binding.value, binding.ty)
                }
                if !ok_value {
                    return err_value, false
                }
                managed := false
                managed_ty := ""
                value, managed_ty, managed = managed_binding_value_text(e, binding, value)
                if binding.is_result_binding && binding.or_modifier == "or-return" {
                    if !named_returns_match_binding_pattern(returns, binding.pattern[:]) {
                        return Compile_Error{
                            message = ":or-return currently requires proc named returns matching the binding names exactly",
                            span = binding.value.span,
                        }, false
                    }
                    emit_result_binding_named_return_assignment(e, binding, value)
                } else {
                    emit_binding_assignment(e, binding, value)
                    emit_managed_destructure_cleanup(e, binding)
                }
                if managed && !binding.deferred_delete && !binding.err_deferred_delete && !binding.defer_with_cleanup {
                    emit_line(e, fmt.tprintf("defer %s", managed_destroy_value_text(e, managed_ty, binding.name)))
                }
            }
            err_guard, ok_guard := emit_result_binding_guard(e, binding, returns)
            if !ok_guard {
                return err_guard, false
            }
            if binding.deferred_delete {
                err_defer, ok_defer := emit_binding_deferred_delete(e, binding)
                if !ok_defer {
                    return err_defer, false
                }
            }
            if binding.defer_with_cleanup {
                err_defer, ok_defer := emit_binding_defer_with_cleanup(e, binding)
                if !ok_defer {
                    return err_defer, false
                }
            }
            if binding.err_deferred_delete {
                err_defer, ok_defer := emit_binding_err_deferred_delete(e, binding)
                if !ok_defer {
                    return err_defer, false
                }
            }
            bind_obvious_binding_types(e, binding)
        }
        err_body, ok_body := emit_body_forms(e, body[:], returns_when_final(last_in_proc, returns))
        if !ok_body {
            return err_body, false
        }
        if scoped {
            e.indent -= 1
            emit_line(e, "}")
        }
        return {}, true
    case "do", "block":
        emit_line(e, "{")
        e.indent += 1
        push_local_type_scope(e)
        body: [dynamic]CST_Form
        for item in form.items[1:] {
            append(&body, item)
        }
        err_body, ok_body := emit_body_forms(e, body[:], returns_when_final(last_in_proc, returns))
        pop_local_type_scope(e)
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "if":
        return emit_if_like(e, "if", form, last_in_proc, returns)
    case "type-case":
        return emit_case_stmt(e, form, last_in_proc, returns)
    case "match":
        return emit_match_stmt(e, form, last_in_proc, returns)
    case "switch":
        return Compile_Error{message = "`switch` has been removed; use `case` for subject dispatch or `cond` for predicate branches", span = head.span}, false
    case "return":
        return_context := returns
        if return_context.kind == .None {
            return_context = e.current_proc_returns
        }
        if len(form.items) == 1 {
            emit_line(e, "return")
            return {}, true
        }
        if len(form.items) == 2 {
            err_owned, bad_owned := owned_result_usage_error(form.items[1], true, e)
            if bad_owned {
                return err_owned, false
            }
            value: string
            err_value: Compile_Error
            ok_value: bool
            if form_has_nested_owned_value(form.items[1], e) {
                value, err_value, ok_value = emit_expr_with_owned_nested_temps(e, form.items[1])
            } else if return_context.kind == .Single {
                value, err_value, ok_value = emit_expr_for_expected_type(e, form.items[1], return_context.single_ty)
            } else {
                value, err_value, ok_value = emit_expr(e, form.items[1])
            }
            if !ok_value {
                return err_value, false
            }
            value = managed_return_value_text(e, form.items[1], value, return_context)
            emit_prefixed_expr_mapped(e, "return ", value, form.items[1].span)
            return {}, true
        }
        line_builder := strings.builder_make()
        defer strings.builder_destroy(&line_builder)
        strings.write_string(&line_builder, "return ")
        for item, idx in form.items[1:] {
            if idx > 0 {
                strings.write_string(&line_builder, ", ")
            }
            err_owned, bad_owned := owned_result_usage_error(item, true, e)
            if bad_owned {
                return err_owned, false
            }
            value: string
            err_value: Compile_Error
            ok_value: bool
            if return_context.kind == .Named && idx < len(return_context.named) {
                value, err_value, ok_value = emit_expr_for_expected_type(e, item, return_context.named[idx].ty)
            } else {
                value, err_value, ok_value = emit_expr(e, item)
            }
            if !ok_value {
                return err_value, false
            }
            if return_context.kind == .Named && idx < len(return_context.named) {
                value = managed_return_value_text_for_type(e, item, value, return_context.named[idx].ty)
            }
            strings.write_string(&line_builder, value)
        }
        emit_line_mapped(e, strings.clone(strings.to_string(line_builder)), form.items[1].span)
        return {}, true
    case "discard":
        if len(form.items) < 2 {
            return Compile_Error{message = "discard expects at least one expression", span = form.span}, false
        }
        for item in form.items[1:] {
            if !form_produces_owned_value(item, e) {
                err_owned, bad_owned := owned_result_usage_error(item, false, e)
                if bad_owned {
                    return err_owned, false
                }
            }
            expr, err_expr, ok_expr := emit_expr(e, item)
            if !ok_expr {
                return err_expr, false
            }
            emit_discarded_expr(e, item, expr)
        }
        return {}, true
    case "break":
        if len(form.items) != 1 {
            return Compile_Error{message = "break does not take arguments", span = form.span}, false
        }
        emit_line(e, "break")
        return {}, true
    case "continue":
        if len(form.items) != 1 {
            return Compile_Error{message = "continue does not take arguments", span = form.span}, false
        }
        emit_line(e, "continue")
        return {}, true
    case "defer":
        if len(form.items) < 2 {
            return Compile_Error{message = "defer expects a body", span = form.span}, false
        }
        if len(form.items) == 2 {
            deferred := form.items[1]
            if deferred.kind == .List && len(deferred.items) > 0 && deferred.items[0].kind == .Symbol {
                switch deferred.items[0].text {
                case "if", "cond", "type-case", "let", "do":
                case:
                    expr, err_expr, ok_expr := emit_expr(e, deferred)
                    if !ok_expr {
                        return err_expr, false
                    }
                    emit_prefixed_expr_mapped(e, "defer ", expr, deferred.span)
                    return {}, true
                }
            } else {
                expr, err_expr, ok_expr := emit_expr(e, deferred)
                if !ok_expr {
                    return err_expr, false
                }
                emit_prefixed_expr_mapped(e, "defer ", expr, deferred.span)
                return {}, true
            }
        }
        emit_line(e, "defer {")
        e.indent += 1
        body: [dynamic]CST_Form
        for item in form.items[1:] {
            append(&body, item)
        }
        err_body, ok_body := emit_body_forms(e, body[:], Return_Spec{kind = .None})
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "set!":
        if len(form.items) != 3 {
            return Compile_Error{message = "set! expects place and value", span = form.span}, false
        }
        if !form_is_assignable_place(form.items[1]) {
            return Compile_Error{message = "set! expects an assignable place", span = form.items[1].span}, false
        }
        if err_immutable, immutable := immutable_def_mutation_error(e, form.items[1]); immutable {
            return err_immutable, false
        }
        lhs, err_lhs, ok_lhs := emit_expr(e, form.items[1])
        if !ok_lhs {
            return err_lhs, false
        }
        err_owned, bad_owned := owned_result_usage_error(form.items[2], true, e)
        if bad_owned {
            return err_owned, false
        }
        rhs: string
        err_rhs: Compile_Error
        ok_rhs: bool
        if form_has_nested_owned_value(form.items[2], e) {
            rhs, err_rhs, ok_rhs = emit_expr_with_owned_nested_temps(e, form.items[2])
        } else {
            rhs, err_rhs, ok_rhs = emit_expr(e, form.items[2])
        }
        if !ok_rhs {
            return err_rhs, false
        }
        if assignment, managed := managed_assignment_text(e, form.items[1], form.items[2], lhs, rhs); managed {
            emit_prefixed_expr_mapped(e, "", assignment, form.span)
            return {}, true
        }
        emit_indent(e)
        strings.write_string(&e.builder, lhs)
        record_current_line_fragment_map(e, 0, lhs, form.items[1].span)
        strings.write_string(&e.builder, " = ")
        strings.write_string(&e.builder, rhs)
        record_current_line_fragment_map(e, len(lhs) + len(" = "), rhs, form.items[2].span)
        emit_raw_newline(e)
        return {}, true
    case "loop":
        return Compile_Error{message = "`loop` has been removed; use `for` for collection iteration or `while` for condition loops", span = form.span}, false
    case "each":
        return Compile_Error{message = "`each` has been removed; use `for` for collection iteration", span = form.span}, false
    case "for":
        if len(form.items) >= 3 && form.items[1].kind == .Vector {
            binding := form.items[1]
            body_start := 2
            if len(binding.items) == 2 &&
               (binding.items[0].kind == .Vector || binding.items[0].kind == .Brace) {
                body: [dynamic]CST_Form
                for item in form.items[body_start:] {
                    append(&body, item)
                }
                return emit_for_data_pattern_loop(e, binding.items[0], binding.items[1], body[:])
            }
            if len(binding.items) == 3 &&
               binding.items[0].kind == .Symbol &&
               (binding.items[1].kind == .Vector || binding.items[1].kind == .Brace) {
                body: [dynamic]CST_Form
                for item in form.items[body_start:] {
                    append(&body, item)
                }
                return emit_for_data_pattern_loop(
                    e,
                    binding.items[1],
                    binding.items[2],
                    body[:],
                    map_name(binding.items[0].text),
                )
            }
            if len(binding.items) == 4 &&
               binding.items[0].kind == .Symbol &&
               binding.items[2].kind == .Keyword &&
               binding.items[2].text == ":transform" {
                value_name := map_name(binding.items[0].text)
                coll_form := binding.items[1]
                transform_form := binding.items[3]
                body: [dynamic]CST_Form
                for item in form.items[body_start:] {
                    append(&body, item)
                }
                if source, ok_source_call := source_call_decl(e, coll_form); ok_source_call {
                    return emit_transform_for_source_loop(e, coll_form, source, "", value_name, transform_form, body[:])
                }
                return emit_transform_for_collection_loop(e, coll_form, "", value_name, transform_form, body[:])
            }
            if len(binding.items) == 5 &&
               binding.items[0].kind == .Symbol &&
               binding.items[1].kind == .Symbol &&
               binding.items[3].kind == .Keyword &&
               binding.items[3].text == ":transform" {
                index_name := map_name(binding.items[0].text)
                value_name := map_name(binding.items[1].text)
                coll_form := binding.items[2]
                transform_form := binding.items[4]
                body: [dynamic]CST_Form
                for item in form.items[body_start:] {
                    append(&body, item)
                }
                if source, ok_source_call := source_call_decl(e, coll_form); ok_source_call {
                    return emit_transform_for_source_loop(e, coll_form, source, index_name, value_name, transform_form, body[:])
                }
                return emit_transform_for_collection_loop(e, coll_form, index_name, value_name, transform_form, body[:])
            }
            if len(binding.items) == 2 && binding.items[0].kind == .Symbol {
                value_name := map_name(binding.items[0].text)
                coll_form := binding.items[1]
                body: [dynamic]CST_Form
                for item in form.items[body_start:] {
                    append(&body, item)
                }
                if coll_ty, ok_coll_ty := obvious_form_type(e, coll_form); ok_coll_ty && coll_ty == "Data" {
                    return emit_for_data_pattern_loop(e, binding.items[0], coll_form, body[:])
                }
                if source, ok_source_call := source_call_decl(e, coll_form); ok_source_call {
                    return emit_source_each_loop(e, coll_form, source, value_name, "", body[:])
                }
                return emit_for_in_loop(e, coll_form, value_name, "", body[:])
            }
            if len(binding.items) == 3 && binding.items[0].kind == .Symbol && binding.items[1].kind == .Symbol {
                first_name := map_name(binding.items[0].text)
                second_name := map_name(binding.items[1].text)
                coll_form := binding.items[2]
                body: [dynamic]CST_Form
                for item in form.items[body_start:] {
                    append(&body, item)
                }
                if source, ok_source_call := source_call_decl(e, coll_form); ok_source_call {
                    return emit_source_each_loop(e, coll_form, source, first_name, second_name, body[:])
                }
                return emit_for_in_loop(e, coll_form, first_name, second_name, body[:])
            }
            return Compile_Error{message = fmt.tprintf("%s expects [value collection], [value collection :transform transform], [index value collection :transform transform], or [first second collection]", canonical_head_text), span = form.span}, false
        }
        return Compile_Error{message = "for expects [value collection], [value collection :transform transform], [index value collection :transform transform], or [first second collection] and body", span = form.span}, false
    case "while":
        if len(form.items) < 3 {
            return Compile_Error{message = "while expects condition and body", span = form.span}, false
        }
        cond, err_cond, ok_cond := emit_expr(e, form.items[1])
        if !ok_cond {
            return err_cond, false
        }
        emit_indent(e)
        strings.write_string(&e.builder, "for ")
        strings.write_string(&e.builder, cond)
        record_current_line_fragment_map(e, len("for "), cond, form.items[1].span)
        strings.write_string(&e.builder, " {")
        emit_raw_newline(e)
        e.indent += 1
        push_local_type_scope(e)
        body: [dynamic]CST_Form
        for item in form.items[2:] {
            append(&body, item)
        }
        err_body, ok_body := emit_body_forms(e, body[:], Return_Spec{kind = .None})
        pop_local_type_scope(e)
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "odin":
        raw, err_raw, ok_raw := emit_expr(e, form)
        if !ok_raw {
            return err_raw, false
        }
        emit_prefixed_expr(e, "", raw)
        return {}, true
    case:
        allow_root_owned := last_in_proc && returns.kind != .None
        if last_in_proc && returns.kind != .None && form_is_borrowed_view_result(form, e) && form_has_nested_owned_value(form, e) {
            return Compile_Error{
                message = "cannot return a borrowed view that depends on an owned intermediate; bind the pipeline locally or return an owned result",
                span = form.span,
            }, false
        }
        if !(form_produces_owned_value(form, e) && !allow_root_owned) {
            err_owned, bad_owned := owned_result_usage_error(form, allow_root_owned, e)
            if bad_owned {
                return err_owned, false
            }
        }
        expr: string
        err_expr: Compile_Error
        ok_expr: bool
        if form_has_nested_owned_value(form, e) {
            expr, err_expr, ok_expr = emit_expr_with_owned_nested_temps(e, form)
        } else if last_in_proc && returns.kind == .Single {
            expr, err_expr, ok_expr = emit_expr_for_expected_type(e, form, returns.single_ty)
        } else {
            expr, err_expr, ok_expr = emit_expr(e, form)
        }
        if !ok_expr {
            return err_expr, false
        }
        if last_in_proc && returns.kind != .None {
            expr = managed_return_value_text(e, form, expr, returns)
            emit_prefixed_expr_mapped(e, "return ", expr, form.span)
        } else if form_is_owned_allocation_result(form) || form_is_owned_constructor_result(form) {
            emit_discarded_expr(e, form, expr)
        } else {
            emit_prefixed_expr_mapped(e, "", expr, form.span)
        }
        return {}, true
    }
}

emit_eval_print_expr :: proc(e: ^Emitter, form: CST_Form) -> (Compile_Error, bool) {
    if form_is_owned_result(form, e) || form_is_owned_allocation_result(form) {
        value, err_value, ok_value := emit_expr(e, form)
        if !ok_value {
            return err_value, false
        }
        temp := eval_temp_name(e)
        emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), value, form.span)
        emit_line(e, fmt.tprintf("defer delete(%s)", temp))
        emit_line_mapped(e, fmt.tprintf("fmt.println(%s)", temp), form.span)
        return {}, true
    }

    value, err_value, ok_value := emit_expr(e, form)
    if !ok_value {
        return err_value, false
    }
    emit_line_mapped(e, fmt.tprintf("fmt.println(%s)", value), form.span)
    return {}, true
}

emit_eval_print_body :: proc(e: ^Emitter, body: []CST_Form) -> (Compile_Error, bool) {
    if len(body) == 0 {
        return Compile_Error{message = "eval print body is empty"}, false
    }
    for form, idx in body {
        last := idx == len(body)-1
        if last {
            return emit_eval_print_stmt(e, form)
        }
        err_stmt, ok_stmt := emit_stmt(e, form, false, Return_Spec{kind = .None})
        if !ok_stmt {
            return err_stmt, false
        }
    }
    return {}, true
}

emit_eval_print_stmt :: proc(e: ^Emitter, form: CST_Form) -> (Compile_Error, bool) {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return emit_eval_print_expr(e, form)
    }

    head := form.items[0].text
    switch head {
    case "let":
        if len(form.items) < 3 {
            return Compile_Error{message = "let expects bindings and body", span = form.span}, false
        }
        bindings, err_bind, ok_bind := parse_let_bindings(form.items[1])
        if !ok_bind {
            return err_bind, false
        }
        err_tail, bad_tail := let_errdefer_tail_error(bindings[:], false)
        if bad_tail {
            return err_tail, false
        }

        emit_line(e, "{")
        e.indent += 1
        push_local_type_scope(e)
        defer pop_local_type_scope(e)
        for binding in bindings {
            if binding_is_data_destructure(e, binding) {
                err_data, ok_data := emit_data_let_binding(e, binding)
                if !ok_data {
                    return err_data, false
                }
            } else if binding_value_is_let(binding) {
                err_flat, ok_flat := emit_let_value_binding_assignment(e, binding)
                if !ok_flat {
                    return err_flat, false
                }
            } else {
                value: string
                err_value: Compile_Error
                ok_value: bool
                if form_has_nested_owned_value(binding.value, e) {
                    value, err_value, ok_value = emit_expr_with_owned_nested_temps(e, binding.value)
                } else {
                    err_owned, bad_owned := owned_result_usage_error(binding.value, true, e)
                    if bad_owned {
                        return err_owned, false
                    }
                    value, err_value, ok_value = emit_expr_for_expected_type(e, binding.value, binding.ty)
                }
                if !ok_value {
                    return err_value, false
                }
                emit_binding_assignment(e, binding, value)
            }
            bind_obvious_binding_types(e, binding)
        }
        err_body, ok_body := emit_eval_print_body(e, form.items[2:])
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "do":
        if len(form.items) < 2 {
            return Compile_Error{message = "do expects a body", span = form.span}, false
        }
        emit_line(e, "{")
        e.indent += 1
        err_body, ok_body := emit_eval_print_body(e, form.items[1:])
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "if":
        if len(form.items) < 3 || len(form.items) > 4 {
            return Compile_Error{message = "if expects test, then, and optional else", span = form.span}, false
        }
        test, err_test, ok_test := emit_expr(e, form.items[1])
        if !ok_test {
            return err_test, false
        }
        emit_indent(e)
        strings.write_string(&e.builder, "if ")
        strings.write_string(&e.builder, test)
        strings.write_string(&e.builder, " {")
        emit_raw_newline(e)
        e.indent += 1
        err_then, ok_then := emit_eval_print_stmt(e, form.items[2])
        if !ok_then {
            return err_then, false
        }
        e.indent -= 1
        emit_line(e, "}")
        if len(form.items) == 4 {
            emit_indent(e)
            strings.write_string(&e.builder, "else {")
            emit_raw_newline(e)
            e.indent += 1
            err_else, ok_else := emit_eval_print_stmt(e, form.items[3])
            if !ok_else {
                return err_else, false
            }
            e.indent -= 1
            emit_line(e, "}")
        }
        return {}, true
    }

    return emit_eval_print_expr(e, form)
}

emit_return_spec :: proc(e: ^Emitter, returns: Return_Spec) {
    #partial switch returns.kind {
    case .None:
        return
    case .Single:
        fmt.sbprintf(&e.builder, " -> %s", returns.single_ty)
    case .Named:
        strings.write_string(&e.builder, " -> (")
        for field, idx in returns.named {
            if idx > 0 {
                strings.write_string(&e.builder, ", ")
            }
            fmt.sbprintf(&e.builder, "%s: %s", field.name, field.ty)
        }
        strings.write_byte(&e.builder, ')')
    }
}

emit_proc_directives :: proc(e: ^Emitter, directives: []string) {
    for directive in directives {
        strings.write_string(&e.builder, directive)
        strings.write_byte(&e.builder, ' ')
    }
}

emit_proc_suffix_directives :: proc(e: ^Emitter, directives: []string) {
    for directive in directives {
        strings.write_byte(&e.builder, ' ')
        strings.write_string(&e.builder, directive)
    }
}

emit_proc_where_constraints :: proc(e: ^Emitter, constraints: []CST_Form) -> (Compile_Error, bool) {
    if len(constraints) == 0 {
        return {}, true
    }
    strings.write_string(&e.builder, " where ")
    for constraint, idx in constraints {
        if idx > 0 {
            strings.write_string(&e.builder, " && ")
        }
        text, err_text, ok_text := emit_expr(e, constraint)
        if !ok_text {
            return err_text, false
        }
        strings.write_string(&e.builder, text)
    }
    return {}, true
}

known_decl_type_with_suffix :: proc(e: ^Emitter, owner, token: string) -> (string, bool) {
    suffix := fmt.tprintf("__%s", token)
    selected := ""
    for decl in e.decls {
        name := ""
        #partial switch decl.kind {
        case .Struct:
            name = decl.struct_decl.name
        case .Union:
            name = decl.union_decl.name
        case .Enum:
            name = decl.enum_decl.name
        }
        if name == "" ||
           !strings.has_suffix(name, suffix) ||
           len(name) <= len(suffix) {
            continue
        }
        prefix := name[:len(name)-len(suffix)]
        if !strings.has_prefix(owner, prefix) ||
           len(owner) <= len(prefix)+1 ||
           owner[len(prefix)] != '_' ||
           owner[len(prefix)+1] != '_' {
            continue
        }
        if selected != "" && selected != name {
            return "", false
        }
        selected = name
    }
    if selected == "" {
        return "", false
    }
    return strings.clone(selected), true
}

type_identifier_start :: proc(ch: u8) -> bool {
    return (ch >= 'A' && ch <= 'Z') ||
           (ch >= 'a' && ch <= 'z') ||
           ch == '_'
}

type_identifier_continue :: proc(ch: u8) -> bool {
    return type_identifier_start(ch) || (ch >= '0' && ch <= '9')
}

qualify_flattened_decl_type :: proc(e: ^Emitter, owner, text: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    i := 0
    for i < len(text) {
        if !type_identifier_start(text[i]) {
            strings.write_byte(&builder, text[i])
            i += 1
            continue
        }
        start := i
        i += 1
        for i < len(text) && type_identifier_continue(text[i]) {
            i += 1
        }
        token := text[start:i]
        if qualified, ok_qualified := known_decl_type_with_suffix(e, owner, token); ok_qualified {
            strings.write_string(&builder, qualified)
            delete(qualified)
        } else {
            strings.write_string(&builder, token)
        }
    }
    return strings.clone(strings.to_string(builder))
}

emit_decl :: proc(e: ^Emitter, decl: IR_Decl) -> (Compile_Error, bool) {
    mark_decl_keyword_usage(e, decl)
    for line in decl.doc_lines {
        emit_line(e, line)
    }
    has_pending_proc_directives := len(e.pending_prefix_directives) > 0 || len(e.pending_suffix_directives) > 0
    if has_pending_proc_directives && decl.kind != .Proc && decl.kind != .Raw {
        return Compile_Error{message = "procedure directive must be followed by a proc declaration", span = decl.span}, false
    }
    #partial switch decl.kind {
    case .Package:
        emit_line(e, fmt.tprintf("package %s", decl.package_name))
    case .Import:
        if decl.import_decl.has_refer {
            return Compile_Error{message = "import :refer is only supported for Kvist source package imports", span = decl.span}, false
        }
        if decl_is_kvist_import(decl) {
            return Compile_Error{}, true
        }
        if decl.import_decl.has_alias {
            emit_line(e, fmt.tprintf("import %s %s", decl.import_decl.alias, decl.import_decl.path))
        } else {
            emit_line(e, fmt.tprintf("import %s", decl.import_decl.path))
        }
    case .Const:
        if decl.const_decl.is_overload {
            emit_indent(e)
            strings.write_string(&e.builder, decl.const_decl.name)
            strings.write_string(&e.builder, " :: proc{")
            for member, idx in decl.const_decl.overload_members {
                if idx > 0 {
                    strings.write_string(&e.builder, ", ")
                }
                strings.write_string(&e.builder, member)
            }
            strings.write_string(&e.builder, "}")
            emit_raw_newline(e)
            return Compile_Error{}, true
        }
        if decl.const_decl.is_type_alias {
            emit_line(e, fmt.tprintf("%s :: %s", decl.const_decl.name, decl.const_decl.type_alias))
            return Compile_Error{}, true
        }
        if decl.const_decl.value.kind == .List &&
           len(decl.const_decl.value.items) == 2 &&
           is_symbol(decl.const_decl.value.items[0], "quote") {
            value, err_value, ok_value := emit_data_value_literal(e, decl.const_decl.value.items[1])
            if !ok_value {
                return err_value, false
            }
            emit_line(e, fmt.tprintf("%s: Data = %s", decl.const_decl.name, value))
            return Compile_Error{}, true
        }
        if decl.const_decl.init_kind == .Runtime {
            emit_line(e, fmt.tprintf("%s: %s", decl.const_decl.name, decl.const_decl.ty))
            return Compile_Error{}, true
        }
        expected_type := ""
        if decl.const_decl.has_ty {
            expected_type = decl.const_decl.ty
        }
        value, err_value, ok_value := emit_expr_for_expected_type(e, decl.const_decl.value, expected_type)
        if !ok_value {
            return err_value, false
        }
        if decl.const_decl.has_ty {
            emit_line(e, fmt.tprintf("%s: %s : %s", decl.const_decl.name, decl.const_decl.ty, value))
        } else {
            emit_line(e, fmt.tprintf("%s :: %s", decl.const_decl.name, value))
        }
    case .Var:
        if !decl.var_decl.has_value {
            if !decl.var_decl.has_ty {
                return Compile_Error{message = "defvar without a value requires an explicit type", span = decl.span}, false
            }
            emit_line(e, fmt.tprintf("%s: %s", decl.var_decl.name, decl.var_decl.ty))
            return {}, true
        }
        expected_type := ""
        if decl.var_decl.has_ty {
            expected_type = decl.var_decl.ty
        }
        value, err_value, ok_value := emit_expr_for_expected_type(e, decl.var_decl.value, expected_type)
        if !ok_value {
            return err_value, false
        }
        if decl.var_decl.has_ty {
            emit_line(e, fmt.tprintf("%s: %s = %s", decl.var_decl.name, decl.var_decl.ty, value))
        } else {
            emit_line(e, fmt.tprintf("%s := %s", decl.var_decl.name, value))
        }
    case .Struct:
        for field in decl.struct_decl.fields {
            if field.has_default &&
               !literal_matches_struct_field_type(e, field.ty, field.default_value) {
                return Compile_Error{
                    message = fmt.tprintf(
                        "struct field default type mismatch for %s:",
                        field.source_name,
                    ),
                    span = field.default_value.span,
                }, false
            }
        }
        emit_indent(e)
        strings.write_string(&e.builder, decl.struct_decl.name)
        strings.write_string(&e.builder, " :: struct {")
        emit_raw_newline(e)
        e.indent += 1
        for field in decl.struct_decl.fields {
            prefix := ""
            if field.is_using {
                prefix = "using "
            }
            field_ty := qualify_flattened_decl_type(e, decl.struct_decl.name, field.ty)
            emit_line(e, fmt.tprintf("%s%s: %s,", prefix, field.name, field_ty))
            delete(field_ty)
        }
        e.indent -= 1
        emit_line(e, "}")
        emit_managed_struct_helpers(e, decl.struct_decl)
    case .Enum:
        emit_indent(e)
        strings.write_string(&e.builder, decl.enum_decl.name)
        strings.write_string(&e.builder, " :: enum {")
        emit_raw_newline(e)
        e.indent += 1
        for variant in decl.enum_decl.variants {
            if variant.has_value {
                value, err_value, ok_value := emit_expr(e, variant.value)
                if !ok_value {
                    return err_value, false
                }
                emit_line(e, fmt.tprintf("%s = %s,", variant.name, value))
            } else {
                emit_line(e, fmt.tprintf("%s,", variant.name))
            }
        }
        e.indent -= 1
        emit_line(e, "}")
    case .Union:
        emit_indent(e)
        strings.write_string(&e.builder, decl.union_decl.name)
        strings.write_string(&e.builder, " :: union {")
        emit_raw_newline(e)
        e.indent += 1
        for variant in decl.union_decl.variants {
            emit_line(e, fmt.tprintf("%s,", variant.ty))
        }
        e.indent -= 1
        emit_line(e, "}")
    case .Proc:
        proc_live: [dynamic]Owned_Local
        proc_borrowed: [dynamic]Borrowed_Local
        analyze_owned_scope_body(e, decl.proc_decl.body[:], decl.proc_decl.returns.kind != .None, &proc_live, &proc_borrowed)
        delete(proc_live)
        delete(proc_borrowed)
        lint_defer_in_loop_body(e, decl.proc_decl.body[:], false)
        push_local_type_scope(e)
        defer pop_local_type_scope(e)
        for param in decl.proc_decl.params {
            bind_local_type(e, param.name, param.ty)
        }
        emit_indent(e)
        fmt.sbprintf(&e.builder, "%s :: ", decl.proc_decl.name)
        emit_proc_directives(e, e.pending_prefix_directives[:])
        emit_proc_directives(e, decl.proc_decl.prefix_directives[:])
        if decl.proc_decl.calling_convention != "" {
            fmt.sbprintf(&e.builder, "proc %q (", decl.proc_decl.calling_convention)
        } else {
            strings.write_string(&e.builder, "proc(")
        }
        idx := 0
        for idx < len(decl.proc_decl.params) {
            if idx > 0 {
                strings.write_string(&e.builder, ", ")
            }
            if decl.proc_decl.params[idx].has_default &&
               default_is_odin_caller_intrinsic(decl.proc_decl.params[idx].default_value) {
                default_text, err_default, ok_default := emit_expr(e, decl.proc_decl.params[idx].default_value)
                if !ok_default {
                    return err_default, false
                }
                fmt.sbprintf(
                    &e.builder,
                    "%s: %s = %s",
                    decl.proc_decl.params[idx].name,
                    decl.proc_decl.params[idx].ty,
                    default_text,
                )
                idx += 1
                continue
            }
            ty := decl.proc_decl.params[idx].ty
            fmt.sbprintf(&e.builder, "%s", decl.proc_decl.params[idx].name)
            next_idx := idx + 1
            for next_idx < len(decl.proc_decl.params) &&
                decl.proc_decl.params[next_idx].ty == ty &&
                !(decl.proc_decl.params[next_idx].has_default &&
                  default_is_odin_caller_intrinsic(decl.proc_decl.params[next_idx].default_value)) {
                fmt.sbprintf(&e.builder, ", %s", decl.proc_decl.params[next_idx].name)
                next_idx += 1
            }
            fmt.sbprintf(&e.builder, ": %s", ty)
            idx = next_idx
        }
        strings.write_byte(&e.builder, ')')
        emit_return_spec(e, decl.proc_decl.returns)
        emit_proc_suffix_directives(e, e.pending_suffix_directives[:])
        emit_proc_suffix_directives(e, decl.proc_decl.suffix_directives[:])
        err_where, ok_where := emit_proc_where_constraints(e, decl.proc_decl.where_constraints[:])
        if !ok_where {
            return err_where, false
        }
        clear(&e.pending_prefix_directives)
        clear(&e.pending_suffix_directives)
        strings.write_string(&e.builder, " {")
        emit_raw_newline(e)
        e.indent += 1
        previous_owns_managed_result := e.current_proc_owns_managed_result
        previous_borrows_managed_result := e.current_proc_borrows_managed_result
        previous_proc_returns := e.current_proc_returns
        e.current_proc_owns_managed_result = decl.proc_decl.owns_result
        e.current_proc_borrows_managed_result = decl.proc_decl.borrows_result
        e.current_proc_returns = decl.proc_decl.returns
        err_body, ok_body := emit_body_forms(e, decl.proc_decl.body[:], decl.proc_decl.returns)
        e.current_proc_owns_managed_result = previous_owns_managed_result
        e.current_proc_borrows_managed_result = previous_borrows_managed_result
        e.current_proc_returns = previous_proc_returns
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
    case .Transform:
        // Compile-time declaration only; emitted through into/transduce use sites.
        return {}, true
    case .Source:
        source_decl := decl.source_decl
        state_ty := source_decl.state_ty
        push_local_type_scope(e)
        defer pop_local_type_scope(e)
        for param in source_decl.params {
            bind_local_type(e, param.name, param.ty)
        }
        err_protocol, ok_protocol := validate_source_protocol(e, &source_decl, state_ty, decl.span)
        if !ok_protocol {
            return err_protocol, false
        }
        emit_indent(e)
        fmt.sbprintf(&e.builder, "%s :: proc(", source_decl.name)
        for param, idx in source_decl.params {
            if idx > 0 {
                strings.write_string(&e.builder, ", ")
            }
            fmt.sbprintf(&e.builder, "%s: %s", param.name, param.ty)
        }
        fmt.sbprintf(&e.builder, ") -> %s %s", state_ty, "{")
        emit_raw_newline(e)
        e.indent += 1
        err_body, ok_body := emit_body_forms(e, source_decl.body[:], Return_Spec{kind = .Single, single_ty = state_ty})
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
    case .Raw:
        if raw_is_proc_directive(decl.raw_text) {
            if is_proc_prefix_directive(decl.raw_text) {
                append(&e.pending_prefix_directives, decl.raw_text)
            } else {
                append(&e.pending_suffix_directives, decl.raw_text)
            }
            return {}, true
        }
        if has_pending_proc_directives && !raw_attaches_to_next_decl(decl.raw_text) {
            return Compile_Error{message = "procedure directive must be followed by a proc declaration", span = decl.span}, false
        }
        if raw_attaches_to_next_decl(decl.raw_text) {
            e.attach_next_decl = true
        } else if contains_text(e.emitted_raw_decls[:], decl.raw_text) {
            return {}, true
        } else {
            append(&e.emitted_raw_decls, decl.raw_text)
        }
        emit_prefixed_expr(e, "", decl.raw_text)
    case:
        return Compile_Error{message = "unsupported declaration kind", span = decl.span}, false
    }
    return {}, true
}

emit_captured_proc_specialization :: proc(e: ^Emitter, spec: Captured_Proc_Specialization) -> (Compile_Error, bool) {
    proc_decl, ok_proc := find_proc_decl(e, spec.original_name)
    if !ok_proc {
        return Compile_Error{message = fmt.tprintf("internal error: missing proc for callback specialization %s", spec.original_name)}, false
    }
    has_field_callbacks := len(spec.field_callbacks) > 0
    if spec.callback_param_index < 0 || spec.callback_param_index >= len(proc_decl.params) {
        if !has_field_callbacks {
            return Compile_Error{message = "internal error: invalid callback specialization parameter index"}, false
        }
    }

    callback_param: Param
    callback_ty := ""
    if !has_field_callbacks {
        callback_param = proc_decl.params[spec.callback_param_index]
        callback_ty = callback_param.ty
    }
    if !has_field_callbacks && spec.field_selector == "" {
        inserted_ty, ok_callback_ty := proc_type_insert_capture_params_text(callback_param.ty, spec.capture_count)
        if !ok_callback_ty {
            return Compile_Error{message = fmt.tprintf("internal error: callback parameter %s is not a proc type", callback_param.name)}, false
        }
        callback_ty = inserted_ty
        defer delete(callback_ty)
    }

    emit_indent(e)
    fmt.sbprintf(&e.builder, "%s :: proc(", proc_specialization_name(spec))
    first := true
    if has_field_callbacks {
        generic_params: [dynamic]string
        for field_callback in spec.field_callbacks {
            if field_callback.callback_param_index < 0 || field_callback.callback_param_index >= len(proc_decl.params) {
                return Compile_Error{message = "internal error: invalid field callback specialization parameter index"}, false
            }
            for generic_param in generic_type_params_in_text(proc_decl.params[field_callback.callback_param_index].ty) {
                append_unique_string(&generic_params, generic_param)
            }
        }
        for generic_param in generic_params {
            if !first {
                strings.write_string(&e.builder, ", ")
            }
            first = false
            fmt.sbprintf(&e.builder, "$%s: typeid", generic_param)
        }
    } else if spec.field_selector != "" {
        generic_params := generic_type_params_in_text(callback_param.ty)
        for generic_param in generic_params {
            if !first {
                strings.write_string(&e.builder, ", ")
            }
            first = false
            fmt.sbprintf(&e.builder, "$%s: typeid", generic_param)
        }
    }
    for param, idx in proc_decl.params {
        if has_field_callbacks {
            if _, ok_field := field_callback_for_param(spec.field_callbacks[:], idx); ok_field {
                continue
            }
        } else if spec.field_selector != "" && idx == spec.callback_param_index {
            continue
        }
        if !first {
            strings.write_string(&e.builder, ", ")
        }
        first = false
        if idx == spec.callback_param_index {
            fmt.sbprintf(&e.builder, "%s: %s", param.name, callback_ty)
            for capture_idx in 0..<spec.capture_count {
                fmt.sbprintf(&e.builder, ", kvist_capture_%d: C%d", capture_idx+1, capture_idx+1)
            }
        } else {
            fmt.sbprintf(&e.builder, "%s: %s", param.name, param.ty)
        }
    }
    strings.write_byte(&e.builder, ')')
    emit_return_spec(e, proc_decl.returns)
    strings.write_string(&e.builder, " {")
    emit_raw_newline(e)

    e.indent += 1
    push_local_type_scope(e)
    for param, idx in proc_decl.params {
        if has_field_callbacks {
            if _, ok_field := field_callback_for_param(spec.field_callbacks[:], idx); ok_field {
                continue
            }
        } else if param.name == callback_param.name && spec.field_selector != "" {
            continue
        } else if param.name == callback_param.name {
            bind_local_type(e, param.name, callback_ty)
        } else {
            bind_local_type(e, param.name, param.ty)
        }
    }
    if has_field_callbacks {
        for field_callback in spec.field_callbacks {
            bind_field_callback_context(e, proc_decl.params[field_callback.callback_param_index].name, field_callback.field_selector)
        }
    } else if spec.field_selector != "" {
        bind_field_callback_context(e, callback_param.name, spec.field_selector)
    } else {
        capture_names: [dynamic]string
        for capture_idx in 0..<spec.capture_count {
            capture_name := fmt.tprintf("kvist_capture_%d", capture_idx+1)
            append(&capture_names, capture_name)
            bind_local_type(e, capture_name, fmt.tprintf("C%d", capture_idx+1))
        }
        bind_callback_context(e, callback_param.name, capture_names[:])
    }
    err_body, ok_body := emit_body_forms(e, proc_decl.body[:], proc_decl.returns)
    pop_local_type_scope(e)
    if !ok_body {
        return err_body, false
    }
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

emit_captured_proc_specializations :: proc(e: ^Emitter) -> (Compile_Error, bool) {
    if e.captured_proc_specializations == nil {
        return Compile_Error{}, true
    }
    emitted_any := false
    idx := 0
    for idx < len(e.captured_proc_specializations^) {
        if emitted_any || e.line > 1 {
            strings.write_byte(&e.builder, '\n')
            e.line += 1
        }
        err_spec, ok_spec := emit_captured_proc_specialization(e, e.captured_proc_specializations^[idx])
        if !ok_spec {
            return err_spec, false
        }
        emitted_any = true
        idx += 1
    }
    return Compile_Error{}, true
}

parallel_param_list_text :: proc(params: []Param) -> string {
    if len(params) == 0 {
        return strings.clone("")
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for param, idx in params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "%s: %s", param.name, param.ty)
    }
    return strings.clone(strings.to_string(builder))
}

parallel_data_arg_list_text :: proc(params: []Param) -> string {
    if len(params) == 0 {
        return strings.clone("")
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for param, idx in params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "data.%s", param.name)
    }
    return strings.clone(strings.to_string(builder))
}

parallel_generic_params :: proc(params: []Param, result_ty := "") -> (values: [dynamic]string) {
    for param in params {
        append_proc_generic_candidates(&values, param.ty)
    }
    if result_ty != "" {
        append_proc_generic_candidates(&values, result_ty)
    }
    return values
}

parallel_generic_decl_suffix :: proc(params: []string) -> string {
    if len(params) == 0 {
        return strings.clone("")
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_byte(&builder, '(')
    for param, idx in params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "$%s: typeid", param)
    }
    strings.write_byte(&builder, ')')
    return strings.clone(strings.to_string(builder))
}

parallel_generic_type_args :: proc(params: []string, introduce := false) -> string {
    if len(params) == 0 {
        return strings.clone("")
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_byte(&builder, '(')
    for param, idx in params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        if introduce {
            strings.write_byte(&builder, '$')
        }
        strings.write_string(&builder, param)
    }
    strings.write_byte(&builder, ')')
    return strings.clone(strings.to_string(builder))
}

parallel_data_type_text :: proc(data_name: string, generic_params: []string, introduce := false) -> string {
    if len(generic_params) == 0 {
        return strings.clone(data_name)
    }
    args := parallel_generic_type_args(generic_params, introduce)
    defer delete(args)
    return fmt.tprintf("%s%s", data_name, args)
}

parallel_field_type_text :: proc(ty: string, generic_params: []string) -> string {
    if len(generic_params) == 0 {
        return strings.clone(ty)
    }
    return substitute_type_names(ty, generic_params, generic_params)
}

emit_parallel_task_data_fields :: proc(e: ^Emitter, params: []Param, generic_params: []string = nil) {
    for param in params {
        ty := parallel_field_type_text(param.ty, generic_params)
        defer delete(ty)
        emit_line(e, fmt.tprintf("%s: %s,", param.name, ty))
    }
}

emit_parallel_task_data_assignments :: proc(e: ^Emitter, params: []Param) {
    for param in params {
        emit_line(e, fmt.tprintf("data.%s = %s", param.name, param.name))
    }
}

emit_thread_start_helper :: proc(e: ^Emitter, spec: Thread_Start_Spec) {
    data_name := thread_start_data_name(spec)
    worker_name := thread_start_worker_name(spec)
    start_name := thread_start_helper_name(spec)
    callback_name := thread_start_callback_name(spec)
    task_ty := thread_task_type(spec)
    helper_params: [dynamic]Param
    for capture in spec.captures {
        append(&helper_params, capture)
    }
    for param in spec.params {
        append(&helper_params, param)
    }
    params_text := parallel_param_list_text(helper_params[:])
    data_args_text := parallel_data_arg_list_text(helper_params[:])
    generic_params := parallel_generic_params(helper_params[:], spec.result_ty)
    data_decl_suffix := parallel_generic_decl_suffix(generic_params[:])
    worker_data_ty := parallel_data_type_text(data_name, generic_params[:], true)
    helper_data_ty := parallel_data_type_text(data_name, generic_params[:], false)
    defer delete(data_name)
    defer delete(worker_name)
    defer delete(start_name)
    defer delete(callback_name)
    defer delete(task_ty)
    defer delete(params_text)
    defer delete(data_args_text)
    defer delete(generic_params)
    defer delete(data_decl_suffix)
    defer delete(worker_data_ty)
    defer delete(helper_data_ty)

    if spec.callback_proc != "" {
        emit_named_proc_text(e, callback_name, spec.callback_proc)
        emit_raw_newline(e)
    }

    emit_line(e, fmt.tprintf("%s :: struct%s %s", data_name, data_decl_suffix, "{"))
    e.indent += 1
    result_ty := parallel_field_type_text(spec.result_ty, generic_params[:])
    emit_line(e, fmt.tprintf("result: chan.Chan(%s),", result_ty))
    delete(result_ty)
    emit_parallel_task_data_fields(e, spec.captures, generic_params[:])
    emit_parallel_task_data_fields(e, spec.params, generic_params[:])
    e.indent -= 1
    emit_line(e, "}")
    emit_raw_newline(e)

    emit_line(e, fmt.tprintf("%s :: proc(data: ^%s) %s", worker_name, worker_data_ty, "{"))
    e.indent += 1
    call_name := spec.worker
    if spec.callback_proc != "" {
        call_name = callback_name
    }
    emit_line(e, fmt.tprintf("chan.send(data.result, %s(%s))", call_name, data_args_text))
    e.indent -= 1
    emit_line(e, "}")
    emit_raw_newline(e)

    emit_line(e, fmt.tprintf("%s :: proc(%s) -> %s %s", start_name, params_text, task_ty, "{"))
    e.indent += 1
    emit_line(e, fmt.tprintf("result, err := chan.create(chan.Chan(%s), 1, context.allocator)", spec.result_ty))
    emit_line(e, "assert(err == .None, \"thread-start could not create result channel\")")
    emit_line(e, fmt.tprintf("data := new(%s)", helper_data_ty))
    emit_line(e, "data.result = result")
    emit_parallel_task_data_assignments(e, spec.captures)
    emit_parallel_task_data_assignments(e, spec.params)
    emit_line(e, fmt.tprintf("task_thread := thread.create_and_start_with_poly_data(data, %s)", worker_name))
    emit_line(e, "assert(task_thread != nil, \"thread-start could not start worker thread\")")
    emit_line(e, fmt.tprintf("return %s%sresult = result, thread = task_thread, data = data}", task_ty, "{"))
    e.indent -= 1
    emit_line(e, "}")
}

emit_thread_detach_helper :: proc(e: ^Emitter, spec: Thread_Detach_Spec) {
    data_name := thread_detach_data_name(spec)
    worker_name := thread_detach_worker_name(spec)
    detach_name := thread_detach_helper_name(spec)
    callback_name := thread_detach_callback_name(spec)
    helper_params: [dynamic]Param
    for capture in spec.captures {
        append(&helper_params, capture)
    }
    for param in spec.params {
        append(&helper_params, param)
    }
    params_text := parallel_param_list_text(helper_params[:])
    data_args_text := parallel_data_arg_list_text(helper_params[:])
    defer delete(data_name)
    defer delete(worker_name)
    defer delete(detach_name)
    defer delete(callback_name)
    defer delete(params_text)
    defer delete(data_args_text)

    if spec.callback_proc != "" {
        emit_named_proc_text(e, callback_name, spec.callback_proc)
        emit_raw_newline(e)
    }

    emit_line(e, fmt.tprintf("%s :: struct %s", data_name, "{"))
    e.indent += 1
    emit_parallel_task_data_fields(e, spec.captures)
    emit_parallel_task_data_fields(e, spec.params)
    e.indent -= 1
    emit_line(e, "}")
    emit_raw_newline(e)

    emit_line(e, fmt.tprintf("%s :: proc(data: ^%s) %s", worker_name, data_name, "{"))
    e.indent += 1
    call_name := spec.worker
    if spec.callback_proc != "" {
        call_name = callback_name
    }
    emit_line(e, fmt.tprintf("%s(%s)", call_name, data_args_text))
    emit_line(e, "free(data)")
    e.indent -= 1
    emit_line(e, "}")
    emit_raw_newline(e)

    emit_line(e, fmt.tprintf("%s :: proc(%s) %s", detach_name, params_text, "{"))
    e.indent += 1
    emit_line(e, fmt.tprintf("data := new(%s)", data_name))
    emit_parallel_task_data_assignments(e, spec.captures)
    emit_parallel_task_data_assignments(e, spec.params)
    emit_line(e, fmt.tprintf("task_thread := thread.create_and_start_with_poly_data(data, %s, nil, .Normal, true)", worker_name))
    emit_line(e, "if task_thread == nil {")
    e.indent += 1
    emit_line(e, "free(data)")
    emit_line(e, "assert(false, \"thread-detach could not start worker thread\")")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
}

emit_named_proc_text :: proc(e: ^Emitter, name, proc_text: string) {
    emit_indent(e)
    strings.write_string(&e.builder, name)
    strings.write_string(&e.builder, " :: ")
    strings.write_string(&e.builder, proc_text)
    strings.write_byte(&e.builder, '\n')
    e.line += 1
    for ch in proc_text {
        if ch == '\n' {
            e.line += 1
        }
    }
}

parallel_helpers_needed :: proc(features: Emitter_Features) -> bool {
    return len(features.thread_starts) > 0 ||
           len(features.thread_detaches) > 0
}

emit_parallel_helpers :: proc(e: ^Emitter, features: Emitter_Features, emitted: ^bool) {
    if !parallel_helpers_needed(features) {
        return
    }

    for spec in features.thread_starts {
        emit_core_helper_separator(e, emitted)
        emit_thread_start_helper(e, spec)
    }

    for spec in features.thread_detaches {
        emit_core_helper_separator(e, emitted)
        emit_thread_detach_helper(e, spec)
    }

}

emit_keyword_type_helper :: proc(e: ^Emitter) {
    emit_line(e, "keyword :: distinct string")
}

emit_data_type_helper :: proc(e: ^Emitter) {
    emit_line(e, "Data_Kind :: enum { Nil, Bool, Int, Float, String, Symbol, Keyword, List, Vector, Map, Set, Tagged }")
    emit_line(e, "Data_Entry :: struct { key, value: Data }")
    emit_line(e, "Data_Node :: struct {")
    e.indent += 1
    emit_line(e, "refs: int,")
    emit_line(e, "allocator: kvist_runtime.Allocator,")
    emit_line(e, "text: string,")
    emit_line(e, "items: [dynamic]Data,")
    emit_line(e, "entries: [dynamic]Data_Entry,")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "Data_Payload :: struct #raw_union {")
    e.indent += 1
    emit_line(e, "bool_value: bool,")
    emit_line(e, "int_value: i64,")
    emit_line(e, "float_value: f64,")
    emit_line(e, "text: string,")
    emit_line(e, "items: []Data,")
    emit_line(e, "entries: []Data_Entry,")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "Data :: struct {")
    e.indent += 1
    emit_line(e, "kind: Data_Kind,")
    emit_line(e, "payload: Data_Payload,")
    emit_line(e, "node: ^Data_Node,")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "Data_Piece :: struct { value: Data, splice: bool }")
    emit_raw_newline(e)
    emit_line(e, "kvist_data_retain :: proc(value: Data) -> Data {")
    e.indent += 1
    emit_line(e, "if value.node != nil { kvist_sync.atomic_add(&value.node.refs, 1) }")
    emit_line(e, "return value")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_append_retained :: proc(values: ^[dynamic]Data, value: Data) { append(values, kvist_data_retain(value)) }")
    emit_line(e, "kvist_data_release :: proc(value: Data) {")
    e.indent += 1
    emit_line(e, "if value.node == nil || kvist_sync.atomic_sub(&value.node.refs, 1) != 1 { return }")
    emit_line(e, "for item in value.node.items { kvist_data_release(item) }")
    emit_line(e, "for entry in value.node.entries { kvist_data_release(entry.key); kvist_data_release(entry.value) }")
    emit_line(e, "delete(value.node.text, value.node.allocator)")
    emit_line(e, "delete(value.node.items)")
    emit_line(e, "delete(value.node.entries)")
    emit_line(e, "free(value.node, value.node.allocator)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_assign :: proc(place: ^Data, value: Data) {")
    e.indent += 1
    emit_line(e, "replacement := kvist_data_retain(value)")
    emit_line(e, "previous := place^")
    emit_line(e, "place^ = replacement")
    emit_line(e, "kvist_data_release(previous)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_move_assign :: proc(place: ^Data, value: Data) {")
    e.indent += 1
    emit_line(e, "previous := place^")
    emit_line(e, "place^ = value")
    emit_line(e, "kvist_data_release(previous)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_new_node :: proc(allocator: kvist_runtime.Allocator = context.allocator) -> ^Data_Node {")
    e.indent += 1
    emit_line(e, "node := new(Data_Node, allocator)")
    emit_line(e, "node^ = Data_Node{refs = 1, allocator = allocator}")
    emit_line(e, "return node")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_make_nil :: proc() -> Data { return Data{} }")
    emit_line(e, "kvist_data_make_bool :: proc(value: bool) -> Data { return Data{kind = .Bool, payload = {bool_value = value}} }")
    emit_line(e, "kvist_data_make_int :: proc(value: i64) -> Data { return Data{kind = .Int, payload = {int_value = value}} }")
    emit_line(e, "kvist_data_make_float :: proc(value: f64) -> Data { return Data{kind = .Float, payload = {float_value = value}} }")
    emit_line(e, "kvist_data_make_text :: proc(kind: Data_Kind, value: string, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(kind == .String || kind == .Symbol || kind == .Keyword)")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.text = strings.clone(value, allocator)")
    emit_line(e, "return Data{kind = kind, payload = {text = node.text}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_lift_data :: proc(value: Data) -> Data { return kvist_data_retain(value) }")
    emit_line(e, "kvist_data_lift_bool :: proc(value: bool) -> Data { return kvist_data_make_bool(value) }")
    emit_line(e, "kvist_data_lift_int :: proc(value: int) -> Data { return kvist_data_make_int(i64(value)) }")
    emit_line(e, "kvist_data_lift_i8 :: proc(value: i8) -> Data { return kvist_data_make_int(i64(value)) }")
    emit_line(e, "kvist_data_lift_i16 :: proc(value: i16) -> Data { return kvist_data_make_int(i64(value)) }")
    emit_line(e, "kvist_data_lift_i32 :: proc(value: i32) -> Data { return kvist_data_make_int(i64(value)) }")
    emit_line(e, "kvist_data_lift_i64 :: proc(value: i64) -> Data { return kvist_data_make_int(i64(value)) }")
    emit_line(e, "kvist_data_lift_u8 :: proc(value: u8) -> Data { return kvist_data_make_int(i64(value)) }")
    emit_line(e, "kvist_data_lift_u16 :: proc(value: u16) -> Data { return kvist_data_make_int(i64(value)) }")
    emit_line(e, "kvist_data_lift_u32 :: proc(value: u32) -> Data { return kvist_data_make_int(i64(value)) }")
    emit_line(e, "kvist_data_lift_u64 :: proc(value: u64) -> Data { return kvist_data_make_int(i64(value)) }")
    emit_line(e, "kvist_data_lift_f32 :: proc(value: f32) -> Data { return kvist_data_make_float(f64(value)) }")
    emit_line(e, "kvist_data_lift_f64 :: proc(value: f64) -> Data { return kvist_data_make_float(f64(value)) }")
    emit_line(e, "kvist_data_lift_string :: proc(value: string) -> Data { return kvist_data_make_text(.String, value) }")
    emit_line(e, "kvist_data_lift_keyword :: proc(value: keyword) -> Data { return kvist_data_make_text(.Keyword, string(value)) }")
    emit_line(e, "kvist_data_lift :: proc{kvist_data_lift_data, kvist_data_lift_bool, kvist_data_lift_int, kvist_data_lift_i8, kvist_data_lift_i16, kvist_data_lift_i32, kvist_data_lift_i64, kvist_data_lift_u8, kvist_data_lift_u16, kvist_data_lift_u32, kvist_data_lift_u64, kvist_data_lift_f32, kvist_data_lift_f64, kvist_data_lift_string, kvist_data_lift_keyword}")
    emit_line(e, "kvist_data_make_tagged :: proc(tag: string, value: Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(len(tag) > 0, \"Data tag must not be empty\")")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.text = strings.clone(tag, allocator)")
    emit_line(e, "node.items = make([dynamic]Data, 0, 1, allocator)")
    emit_line(e, "append(&node.items, kvist_data_retain(value))")
    emit_line(e, "return Data{kind = .Tagged, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_make_items :: proc(kind: Data_Kind, values: []Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(kind == .List || kind == .Vector || kind == .Set)")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.items = make([dynamic]Data, 0, len(values), allocator)")
    emit_line(e, "for value in values {")
    e.indent += 1
    emit_line(e, "if kind == .Set { found := false; for item in node.items { if kvist_data_equal(item, value) { found = true; break } }; if found { continue } }")
    emit_line(e, "append(&node.items, kvist_data_retain(value))")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return Data{kind = kind, payload = {items = node.items[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_freeze_items :: proc(kind: Data_Kind, values: ^[dynamic]Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(kind == .List || kind == .Vector || kind == .Set)")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.items = values^")
    emit_line(e, "values^ = nil")
    emit_line(e, "return Data{kind = kind, payload = {items = node.items[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_make_items_spliced :: proc(kind: Data_Kind, pieces: []Data_Piece, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(kind == .List || kind == .Vector || kind == .Set)")
    emit_line(e, "capacity := 0")
    emit_line(e, "for piece in pieces { if piece.splice { assert(piece.value.kind == .List || piece.value.kind == .Vector || piece.value.kind == .Set, \"Data splice expects a list, vector, or set\"); capacity += len(piece.value.payload.items) } else { capacity += 1 } }")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.items = make([dynamic]Data, 0, capacity, allocator)")
    emit_line(e, "for piece in pieces {")
    e.indent += 1
    emit_line(e, "values := []Data{piece.value}")
    emit_line(e, "if piece.splice { values = piece.value.payload.items }")
    emit_line(e, "for value in values {")
    e.indent += 1
    emit_line(e, "if kind == .Set { found := false; for item in node.items { if kvist_data_equal(item, value) { found = true; break } }; if found { continue } }")
    emit_line(e, "append(&node.items, kvist_data_retain(value))")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return Data{kind = kind, payload = {items = node.items[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_make_map :: proc(values: []Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(len(values)%2 == 0, \"Data map expects alternating keys and values\")")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.entries = make([dynamic]Data_Entry, 0, len(values)/2, allocator)")
    emit_line(e, "for i := 0; i < len(values); i += 2 {")
    e.indent += 1
    emit_line(e, "replaced := false")
    emit_line(e, "for &entry in node.entries { if kvist_data_equal(entry.key, values[i]) { kvist_data_assign(&entry.value, values[i+1]); replaced = true; break } }")
    emit_line(e, "if !replaced { append(&node.entries, Data_Entry{key = kvist_data_retain(values[i]), value = kvist_data_retain(values[i+1])}) }")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return Data{kind = .Map, payload = {entries = node.entries[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_freeze_map :: proc(values: ^[dynamic]Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(len(values^)%2 == 0, \"Data map builder expects alternating keys and values\")")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.entries = make([dynamic]Data_Entry, 0, len(values^)/2, allocator)")
    emit_line(e, "for i := 0; i < len(values^); i += 2 {")
    e.indent += 1
    emit_line(e, "replaced := false")
    emit_line(e, "for &entry in node.entries { if kvist_data_equal(entry.key, values^[i]) { kvist_data_release(values^[i]); kvist_data_release(entry.value); entry.value = values^[i+1]; replaced = true; break } }")
    emit_line(e, "if !replaced { append(&node.entries, Data_Entry{key = values^[i], value = values^[i+1]}) }")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "delete(values^)")
    emit_line(e, "values^ = nil")
    emit_line(e, "return Data{kind = .Map, payload = {entries = node.entries[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_empty_map :: proc(allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.entries = make([dynamic]Data_Entry, allocator)")
    emit_line(e, "return Data{kind = .Map, payload = {entries = node.entries[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_raw_newline(e)
    emit_line(e, "kvist_data_equal :: proc(a, b: Data) -> bool {")
    e.indent += 1
    emit_line(e, "if a.kind != b.kind { return false }")
    emit_line(e, "switch a.kind {")
    e.indent += 1
    emit_line(e, "case .Nil: return true")
    emit_line(e, "case .Bool: return a.payload.bool_value == b.payload.bool_value")
    emit_line(e, "case .Int: return a.payload.int_value == b.payload.int_value")
    emit_line(e, "case .Float: return a.payload.float_value == b.payload.float_value")
    emit_line(e, "case .String, .Symbol, .Keyword: return a.payload.text == b.payload.text")
    emit_line(e, "case .Tagged: return a.node.text == b.node.text && kvist_data_equal(a.node.items[0], b.node.items[0])")
    emit_line(e, "case .List, .Vector:")
    e.indent += 1
    emit_line(e, "if len(a.payload.items) != len(b.payload.items) { return false }")
    emit_line(e, "for value, i in a.payload.items { if !kvist_data_equal(value, b.payload.items[i]) { return false } }")
    emit_line(e, "return true")
    e.indent -= 1
    emit_line(e, "case .Set:")
    e.indent += 1
    emit_line(e, "if len(a.payload.items) != len(b.payload.items) { return false }")
    emit_line(e, "for value in a.payload.items { found := false; for other in b.payload.items { if kvist_data_equal(value, other) { found = true; break } }; if !found { return false } }")
    emit_line(e, "return true")
    e.indent -= 1
    emit_line(e, "case .Map:")
    e.indent += 1
    emit_line(e, "if len(a.payload.entries) != len(b.payload.entries) { return false }")
    emit_line(e, "for entry in a.payload.entries {")
    e.indent += 1
    emit_line(e, "found := false")
    emit_line(e, "for other in b.payload.entries { if kvist_data_equal(entry.key, other.key) && kvist_data_equal(entry.value, other.value) { found = true; break } }")
    emit_line(e, "if !found { return false }")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return true")
    e.indent -= 1
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return false")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_assoc :: proc(collection, key, value: Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "if collection.kind == .Map {")
    e.indent += 1
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.entries = make([dynamic]Data_Entry, 0, len(collection.payload.entries)+1, allocator)")
    emit_line(e, "found := false")
    emit_line(e, "for entry in collection.payload.entries { if kvist_data_equal(entry.key, key) { append(&node.entries, Data_Entry{key = kvist_data_retain(entry.key), value = kvist_data_retain(value)}); found = true } else { append(&node.entries, Data_Entry{key = kvist_data_retain(entry.key), value = kvist_data_retain(entry.value)}) } }")
    emit_line(e, "if !found { append(&node.entries, Data_Entry{key = kvist_data_retain(key), value = kvist_data_retain(value)}) }")
    emit_line(e, "return Data{kind = .Map, payload = {entries = node.entries[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "if collection.kind == .Vector && key.kind == .Int && key.payload.int_value >= 0 && key.payload.int_value < i64(len(collection.payload.items)) {")
    e.indent += 1
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.items = make([dynamic]Data, 0, len(collection.payload.items), allocator)")
    emit_line(e, "for item, i in collection.payload.items { if i64(i) == key.payload.int_value { append(&node.items, kvist_data_retain(value)) } else { append(&node.items, kvist_data_retain(item)) } }")
    emit_line(e, "return Data{kind = .Vector, payload = {items = node.items[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "assert(false, \"Data assoc expects a map or an in-range vector index\")")
    emit_line(e, "return Data{}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_dissoc :: proc(collection, key: Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(collection.kind == .Map, \"Data dissoc expects a map\")")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.entries = make([dynamic]Data_Entry, 0, len(collection.payload.entries), allocator)")
    emit_line(e, "for entry in collection.payload.entries { if !kvist_data_equal(entry.key, key) { append(&node.entries, Data_Entry{key = kvist_data_retain(entry.key), value = kvist_data_retain(entry.value)}) } }")
    emit_line(e, "return Data{kind = .Map, payload = {entries = node.entries[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_dissoc_in :: proc(collection, path: Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(collection.kind == .Map, \"Data dissoc-in expects a map\")")
    emit_line(e, "assert(path.kind == .List || path.kind == .Vector, \"Data dissoc-in expects a list or vector path\")")
    emit_line(e, "if len(path.payload.items) == 0 { return kvist_data_retain(collection) }")
    emit_line(e, "key := path.payload.items[0]")
    emit_line(e, "if len(path.payload.items) == 1 { return kvist_data_dissoc(collection, key, allocator) }")
    emit_line(e, "child := kvist_data_get(collection, key)")
    emit_line(e, "if child.kind != .Map { return kvist_data_retain(collection) }")
    emit_line(e, "tail := Data{kind = path.kind, payload = {items = path.payload.items[1:]}, node = path.node}")
    emit_line(e, "updated := kvist_data_dissoc_in(child, tail, allocator)")
    emit_line(e, "defer kvist_data_release(updated)")
    emit_line(e, "return kvist_data_assoc(collection, key, updated, allocator)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_conj :: proc(collection, value: Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(collection.kind == .List || collection.kind == .Vector || collection.kind == .Set, \"Data conj expects a list, vector, or set\")")
    emit_line(e, "if collection.kind == .Set { for item in collection.payload.items { if kvist_data_equal(item, value) { return kvist_data_retain(collection) } } }")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.items = make([dynamic]Data, 0, len(collection.payload.items)+1, allocator)")
    emit_line(e, "if collection.kind == .List { append(&node.items, kvist_data_retain(value)) }")
    emit_line(e, "for item in collection.payload.items { append(&node.items, kvist_data_retain(item)) }")
    emit_line(e, "if collection.kind != .List { append(&node.items, kvist_data_retain(value)) }")
    emit_line(e, "return Data{kind = collection.kind, payload = {items = node.items[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_append :: proc(collection, value: Data, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "assert(collection.kind == .List || collection.kind == .Vector || collection.kind == .Set, \"Data append expects a list, vector, or set\")")
    emit_line(e, "if collection.kind == .Set { for item in collection.payload.items { if kvist_data_equal(item, value) { return kvist_data_retain(collection) } } }")
    emit_line(e, "node := kvist_data_new_node(allocator)")
    emit_line(e, "node.items = make([dynamic]Data, 0, len(collection.payload.items)+1, allocator)")
    emit_line(e, "for item in collection.payload.items { append(&node.items, kvist_data_retain(item)) }")
    emit_line(e, "append(&node.items, kvist_data_retain(value))")
    emit_line(e, "return Data{kind = collection.kind, payload = {items = node.items[:]}, node = node}")
    e.indent -= 1
    emit_line(e, "}")
    emit_raw_newline(e)
    emit_line(e, "kvist_data_get :: proc(value, key: Data) -> Data {")
    e.indent += 1
    emit_line(e, "if value.kind == .Map { for entry in value.payload.entries { if kvist_data_equal(entry.key, key) { return entry.value } } }")
    emit_line(e, "if (value.kind == .List || value.kind == .Vector) && key.kind == .Int && key.payload.int_value >= 0 && key.payload.int_value < i64(len(value.payload.items)) { return value.payload.items[int(key.payload.int_value)] }")
    emit_line(e, "return Data{}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_get_present :: proc(value, key: Data) -> (result: Data, present: bool) {")
    e.indent += 1
    emit_line(e, "if value.kind != .Map { return Data{}, false }")
    emit_line(e, "for entry in value.payload.entries { if kvist_data_equal(entry.key, key) { return entry.value, true } }")
    emit_line(e, "return Data{}, false")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_nth_or_nil :: proc(value: Data, index: int) -> Data {")
    e.indent += 1
    emit_line(e, "if (value.kind == .List || value.kind == .Vector) && index >= 0 && index < len(value.payload.items) { return value.payload.items[index] }")
    emit_line(e, "return Data{}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_rest_from :: proc(value: Data, index: int, allocator: kvist_runtime.Allocator = context.allocator) -> Data {")
    e.indent += 1
    emit_line(e, "if (value.kind != .List && value.kind != .Vector) || index >= len(value.payload.items) { return Data{} }")
    emit_line(e, "return kvist_data_make_items(value.kind, value.payload.items[index:], allocator)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_or :: proc(value, fallback: Data) -> Data { if value.kind == .Nil { return fallback }; return value }")
    emit_line(e, "kvist_data_get_or :: proc(value, key, fallback: Data) -> Data {")
    e.indent += 1
    emit_line(e, "if value.kind == .Map { for entry in value.payload.entries { if kvist_data_equal(entry.key, key) { return entry.value } }; return fallback }")
    emit_line(e, "if (value.kind == .List || value.kind == .Vector) && key.kind == .Int && key.payload.int_value >= 0 && key.payload.int_value < i64(len(value.payload.items)) { return value.payload.items[int(key.payload.int_value)] }")
    emit_line(e, "return fallback")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_contains :: proc(value, key: Data) -> bool {")
    e.indent += 1
    emit_line(e, "if value.kind == .Map { for entry in value.payload.entries { if kvist_data_equal(entry.key, key) { return true } }; return false }")
    emit_line(e, "if value.kind == .Set { for item in value.payload.items { if kvist_data_equal(item, key) { return true } } }")
    emit_line(e, "return false")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "kvist_data_int :: proc(value: Data) -> i64 { assert(value.kind == .Int, \"expected Data int\"); return value.payload.int_value }")
    emit_line(e, "kvist_data_float :: proc(value: Data) -> f64 { assert(value.kind == .Float, \"expected Data float\"); return value.payload.float_value }")
    emit_line(e, "kvist_data_bool :: proc(value: Data) -> bool { assert(value.kind == .Bool, \"expected Data bool\"); return value.payload.bool_value }")
    emit_line(e, "kvist_data_string :: proc(value: Data) -> string { assert(value.kind == .String, \"expected Data string\"); return value.payload.text }")
    emit_line(e, "kvist_data_keyword :: proc(value: Data) -> string { assert(value.kind == .Keyword, \"expected Data keyword\"); return value.payload.text }")
    emit_line(e, "kvist_data_symbol :: proc(value: Data) -> string { assert(value.kind == .Symbol, \"expected Data symbol\"); return value.payload.text }")
    emit_line(e, "kvist_data_text :: proc(value: Data) -> string { assert(value.kind == .String || value.kind == .Symbol || value.kind == .Keyword, \"expected textual Data\"); return value.payload.text }")
    emit_line(e, "kvist_data_tag :: proc(value: Data) -> string { assert(value.kind == .Tagged, \"expected tagged Data\"); return value.node.text }")
    emit_line(e, "kvist_data_tagged_value :: proc(value: Data) -> Data { assert(value.kind == .Tagged, \"expected tagged Data\"); return value.node.items[0] }")
    emit_line(e, "kvist_data_count :: proc(value: Data) -> int { if value.kind == .Nil { return 0 }; if value.kind == .Map { return len(value.payload.entries) }; if value.kind == .List || value.kind == .Vector || value.kind == .Set { return len(value.payload.items) }; if value.kind == .String { return len(value.payload.text) }; assert(false, \"count expects collection, string, or nil Data\"); return 0 }")
    emit_line(e, "kvist_data_kind :: proc(value: Data) -> Data_Kind { return value.kind }")
    emit_line(e, "kvist_data_nil_p :: proc(value: Data) -> bool { return value.kind == .Nil }")
    emit_line(e, "kvist_data_bool_p :: proc(value: Data) -> bool { return value.kind == .Bool }")
    emit_line(e, "kvist_data_int_p :: proc(value: Data) -> bool { return value.kind == .Int }")
    emit_line(e, "kvist_data_float_p :: proc(value: Data) -> bool { return value.kind == .Float }")
    emit_line(e, "kvist_data_string_p :: proc(value: Data) -> bool { return value.kind == .String }")
    emit_line(e, "kvist_data_symbol_p :: proc(value: Data) -> bool { return value.kind == .Symbol }")
    emit_line(e, "kvist_data_keyword_p :: proc(value: Data) -> bool { return value.kind == .Keyword }")
    emit_line(e, "kvist_data_list_p :: proc(value: Data) -> bool { return value.kind == .List }")
    emit_line(e, "kvist_data_vector_p :: proc(value: Data) -> bool { return value.kind == .Vector }")
    emit_line(e, "kvist_data_map_p :: proc(value: Data) -> bool { return value.kind == .Map }")
    emit_line(e, "kvist_data_set_p :: proc(value: Data) -> bool { return value.kind == .Set }")
    emit_line(e, "kvist_data_tagged_p :: proc(value: Data) -> bool { return value.kind == .Tagged }")
    emit_line(e, "kvist_data_item_at :: proc(value: Data, index: int) -> Data { assert((value.kind == .List || value.kind == .Vector || value.kind == .Set) && index >= 0 && index < len(value.payload.items), \"Data collection index out of bounds\"); return value.payload.items[index] }")
    emit_line(e, "kvist_data_key_at :: proc(value: Data, index: int) -> Data { assert(value.kind == .Map && index >= 0 && index < len(value.payload.entries), \"Data map index out of bounds\"); return value.payload.entries[index].key }")
    emit_line(e, "kvist_data_value_at :: proc(value: Data, index: int) -> Data { assert(value.kind == .Map && index >= 0 && index < len(value.payload.entries), \"Data map index out of bounds\"); return value.payload.entries[index].value }")
}

emit_data_literals :: proc(e: ^Emitter, literals: []Data_Literal) {
    for literal in literals {
        emit_raw_newline(e)
        emit_line(e, fmt.tprintf("%s: Data = %s", literal.name, literal.value))
    }
}

emit_core_get_or_default_helper :: proc(e: ^Emitter) {
    emit_line(e, "kvist_get_or_default :: proc(m: map[$K]$V, key: K, default: V) -> V {")
    e.indent += 1
    emit_line(e, "value, ok := m[key]")
    emit_line(e, "if ok {")
    e.indent += 1
    emit_line(e, "return value")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return default")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_contains_value_helper :: proc(e: ^Emitter) {
    emit_line(e, "kvist_contains_value :: #force_inline proc(xs: []$T, value: T) -> bool {")
    e.indent += 1
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "if x == value {")
    e.indent += 1
    emit_line(e, "return true")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return false")
    e.indent -= 1
    emit_line(e, "}")
}

core_helpers_needed :: proc(features: Emitter_Features) -> bool {
    return features.keyword_type ||
           features.data_type ||
           features.core_get_or_default ||
           features.core_contains_value ||
           parallel_helpers_needed(features)
}

emit_core_helper_separator :: proc(e: ^Emitter, emitted: ^bool) {
    if emitted^ {
        emit_raw_newline(e)
    }
    emitted^ = true
}

emit_core_helpers :: proc(e: ^Emitter, features: Emitter_Features) {
    if !core_helpers_needed(features) {
        return
    }

    emit_raw_newline(e)
    emitted := false
    if features.keyword_type {
        emit_core_helper_separator(e, &emitted)
        emit_keyword_type_helper(e)
    }
    if features.data_type {
        emit_core_helper_separator(e, &emitted)
        emit_data_type_helper(e)
        emit_data_literals(e, features.data_literals[:])
    }
    if features.core_get_or_default {
        emit_core_helper_separator(e, &emitted)
        emit_core_get_or_default_helper(e)
    }
    if features.core_contains_value {
        emit_core_helper_separator(e, &emitted)
        emit_core_contains_value_helper(e)
    }
    emit_parallel_helpers(e, features, &emitted)
}

emit_decls :: proc(decls: []IR_Decl) -> (string, Compile_Error, bool) {
    result, err, ok := emit_decls_with_source_map(decls)
    return result.output, err, ok
}

form_uses_core_strings :: proc(form: CST_Form) -> bool {
    if form.kind == .Symbol {
        return strings.has_prefix(form.text, "strings.") || strings.has_prefix(form.text, "strings/")
    }
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if strings.has_prefix(form.items[0].text, "strings.") ||
           strings.has_prefix(form.items[0].text, "strings/") {
            return true
        }
    }
    for item in form.items {
        if form_uses_core_strings(item) {
            return true
        }
    }
    return false
}

form_uses_core_fmt :: proc(form: CST_Form) -> bool {
    if form.kind == .Symbol {
        return strings.has_prefix(form.text, "fmt.") || strings.has_prefix(form.text, "fmt/")
    }
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if strings.has_prefix(form.items[0].text, "fmt.") ||
           strings.has_prefix(form.items[0].text, "fmt/") {
            return true
        }
    }
    for item in form.items {
        if form_uses_core_fmt(item) {
            return true
        }
    }
    return false
}

decls_need_core_strings_import :: proc(decls: []IR_Decl) -> bool {
    for decl in decls {
        if decl.kind == .Import {
            if (!decl.import_decl.has_alias && decl.import_decl.path == "\"core:strings\"") ||
               (decl.import_decl.has_alias && decl.import_decl.alias == "strings" && decl.import_decl.path == "\"core:strings\"") {
                return false
            }
        }
    }
    for decl in decls {
        #partial switch decl.kind {
        case .Const:
            if form_uses_core_strings(decl.const_decl.value) {
                return true
            }
        case .Var:
            if form_uses_core_strings(decl.var_decl.value) {
                return true
            }
        case .Enum:
            for variant in decl.enum_decl.variants {
                if variant.has_value && form_uses_core_strings(variant.value) {
                    return true
                }
            }
        case .Proc:
            for form in decl.proc_decl.body {
                if form_uses_core_strings(form) {
                    return true
                }
            }
        }
    }
    return false
}

decls_need_core_fmt_import :: proc(decls: []IR_Decl) -> bool {
    if decls_have_core_fmt_import(decls) {
        return false
    }
    for decl in decls {
        #partial switch decl.kind {
        case .Const:
            if form_uses_core_fmt(decl.const_decl.value) {
                return true
            }
        case .Var:
            if form_uses_core_fmt(decl.var_decl.value) {
                return true
            }
        case .Enum:
            for variant in decl.enum_decl.variants {
                if variant.has_value && form_uses_core_fmt(variant.value) {
                    return true
                }
            }
        case .Proc:
            for form in decl.proc_decl.body {
                if form_uses_core_fmt(form) {
                    return true
                }
            }
        }
    }
    return false
}

decls_have_core_fmt_import :: proc(decls: []IR_Decl) -> bool {
    for decl in decls {
        if decl.kind == .Import {
            if (!decl.import_decl.has_alias && decl.import_decl.path == "\"core:fmt\"") ||
               (decl.import_decl.has_alias && decl.import_decl.alias == "fmt" && decl.import_decl.path == "\"core:fmt\"") {
                return true
            }
        }
    }
    return false
}

emit_core_strings_import :: proc(e: ^Emitter, emitted: ^bool, needed: bool) {
    if !needed || emitted^ {
        return
    }
    emit_line(e, "import strings \"core:strings\"")
    strings.write_byte(&e.builder, '\n')
    e.line += 1
    emitted^ = true
}

emit_core_fmt_import :: proc(e: ^Emitter, emitted: ^bool, needed: bool) {
    if !needed || emitted^ {
        return
    }
    emit_line(e, "import \"core:fmt\"")
    strings.write_byte(&e.builder, '\n')
    e.line += 1
    emitted^ = true
}

output_needs_core_slice_import :: proc(output: string, features: Emitter_Features) -> bool {
    return strings.contains(output, "kvist_slice.")
}

features_need_core_strings_import :: proc(features: Emitter_Features) -> bool {
    return features.core_strings
}

features_need_core_fmt_import :: proc(features: Emitter_Features) -> bool {
    return features.core_fmt
}

features_need_core_thread_import :: proc(features: Emitter_Features) -> bool {
    return len(features.thread_detaches) > 0 ||
           len(features.thread_starts) > 0
}

features_need_core_chan_import :: proc(features: Emitter_Features) -> bool {
    return len(features.thread_starts) > 0
}

features_need_core_os_import :: proc(features: Emitter_Features) -> bool {
    return false
}

features_need_data_runtime_imports :: proc(features: Emitter_Features) -> bool {
    return features.data_type
}

features_need_base_runtime_import :: proc(features: Emitter_Features) -> bool {
    return features.data_type || features.runtime_defs
}

output_has_import_line :: proc(output, line: string) -> bool {
    start := 0
    for start <= len(output) {
        found := strings.index(output[start:], line)
        if found < 0 {
            return false
        }
        at := start + found
        before_ok := at == 0 || output[at-1] == '\n'
        after_at := at + len(line)
        after_ok := after_at == len(output) || output[after_at] == '\n'
        if before_ok && after_ok {
            return true
        }
        start = at + len(line)
    }
    return false
}

output_has_import_path :: proc(output, path: string) -> bool {
    start := 0
    needle := strings.concatenate({"\"", path, "\""}, context.temp_allocator)
    defer delete(needle)
    for start <= len(output) {
        found := strings.index(output[start:], "import ")
        if found < 0 {
            return false
        }
        at := start + found
        line_end := strings.index(output[at:], "\n")
        if line_end < 0 {
            line_end = len(output) - at
        }
        line_text := output[at : at+line_end]
        if strings.contains(line_text, needle) {
            return true
        }
        start = at + line_end
        if start < len(output) && output[start] == '\n' {
            start += 1
        }
    }
    return false
}

inject_imports_into_output_header :: proc(output: string, imports: []string) -> (string, int) {
    if len(imports) == 0 {
        return strings.clone(output), 0
    }

    insert_at := 0
    offset := 0
    saw_package := false

    for offset < len(output) {
        line_end := strings.index(output[offset:], "\n")
        if line_end < 0 {
            line_end = len(output) - offset
        }
        line_text := output[offset : offset+line_end]
        trimmed := strings.trim_space(line_text)
        next_offset := offset + line_end
        if next_offset < len(output) && output[next_offset] == '\n' {
            next_offset += 1
        }

        if !saw_package {
            if strings.has_prefix(trimmed, "package ") {
                saw_package = true
                insert_at = next_offset
                offset = next_offset
                continue
            }
            if trimmed == "" || strings.has_prefix(trimmed, "#+") || strings.has_prefix(trimmed, "//") {
                offset = next_offset
                continue
            }
            break
        }

        if trimmed == "" || strings.has_prefix(trimmed, "import ") {
            insert_at = next_offset
            offset = next_offset
            continue
        }
        break
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, output[:insert_at])
    for import_line in imports {
        strings.write_string(&builder, import_line)
        strings.write_byte(&builder, '\n')
    }
    strings.write_string(&builder, output[insert_at:])
    return strings.clone(strings.to_string(builder)), len(imports)
}

shift_source_map_lines :: proc(entries: ^[dynamic]Source_Map_Entry, delta: int) {
    if delta == 0 {
        return
    }
    for &entry in entries {
        entry.generated_start_line += delta
        entry.generated_end_line += delta
    }
}

emit_runtime_def_lifecycle :: proc(e: ^Emitter) -> (Compile_Error, bool) {
    runtime_count := 0
    managed_count := 0
    for decl in e.decls {
        if decl.kind == .Const && decl.const_decl.init_kind == .Runtime {
            runtime_count += 1
            if type_text_is_managed_value(decl.const_decl.ty) {
                managed_count += 1
            }
        }
    }
    if runtime_count == 0 {
        return {}, true
    }
    e.features.runtime_defs = true

    emit_raw_newline(e)
    emit_line(e, "@(init)")
    emit_line(e, "__kvist_runtime_defs_init :: proc \"contextless\" () {")
    e.indent += 1
    emit_line(e, "context = kvist_runtime.default_context()")
    for decl in e.decls {
        if decl.kind != .Const || decl.const_decl.init_kind != .Runtime {
            continue
        }
        value, err_value, ok_value := emit_expr_for_expected_type(e, decl.const_decl.value, decl.const_decl.ty)
        if !ok_value {
            return err_value, false
        }
        if type_text_is_managed_value(decl.const_decl.ty) {
            mark_data_type(e)
            if !form_produces_owned_managed_type(e, decl.const_decl.value, decl.const_decl.ty) {
                retained := emit_call_text("kvist_data_retain", []string{value})
                delete(value)
                value = retained
            }
        }
        emit_prefixed_expr_mapped(e, fmt.tprintf("%s = ", decl.const_decl.name), value, decl.const_decl.value.span)
        delete(value)
    }
    e.indent -= 1
    emit_line(e, "}")

    if managed_count > 0 {
        emit_raw_newline(e)
        emit_line(e, "@(fini)")
        emit_line(e, "__kvist_runtime_defs_fini :: proc \"contextless\" () {")
        e.indent += 1
        emit_line(e, "context = kvist_runtime.default_context()")
        for offset in 0..<len(e.decls) {
            decl := e.decls[len(e.decls)-1-offset]
            if decl.kind == .Const &&
               decl.const_decl.init_kind == .Runtime &&
               type_text_is_managed_value(decl.const_decl.ty) {
                emit_line_mapped(e, fmt.tprintf("kvist_data_release(%s)", decl.const_decl.name), decl.span)
            }
        }
        e.indent -= 1
        emit_line(e, "}")
    }
    return {}, true
}

emit_decls_with_source_map :: proc(decls: []IR_Decl) -> (Emit_Result, Compile_Error, bool) {
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
    err_classify, ok_classify := classify_def_initializers(&e)
    if !ok_classify {
        return result, err_classify, false
    }
    for decl in decls {
        if decl.kind == .Struct {
            append(&e.structs, decl.struct_decl)
        }
        if decl.kind == .Union {
            append(&e.unions, decl.union_decl)
        }
    }
    needs_core_strings_import := decls_need_core_strings_import(decls)
    needs_core_fmt_import := decls_need_core_fmt_import(decls)
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
    err_runtime_defs, ok_runtime_defs := emit_runtime_def_lifecycle(&e)
    if !ok_runtime_defs {
        return result, err_runtime_defs, false
    }
    emit_core_strings_import(&e, &emitted_core_strings_import, needs_core_strings_import)
    emit_core_fmt_import(&e, &emitted_core_fmt_import, needs_core_fmt_import)
    err_specializations, ok_specializations := emit_captured_proc_specializations(&e)
    if !ok_specializations {
        return result, err_specializations, false
    }
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
    err_classify, ok_classify := classify_def_initializers(&e)
    if !ok_classify {
        return result, err_classify, false
    }
    for decl in decls {
        if decl.kind == .Struct {
            append(&e.structs, decl.struct_decl)
        }
        if decl.kind == .Union {
            append(&e.unions, decl.union_decl)
        }
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

emit_ir_program_with_source_map :: proc(program: IR_Program) -> (Emit_Result, Compile_Error, bool) {
    return emit_decls_with_source_map(program.decls[:])
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
    defer delete(result.source_map)
    return result.output, {}, true
}
