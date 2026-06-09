package kvist

import "core:fmt"
import "core:os"
import "core:strings"

Sum_By_Field :: struct {
    key:   string,
    value: string,
}

Captured_Proc_Specialization :: struct {
    original_name:         string,
    callback_param_index:  int,
    capture_count:         int,
}

Callback_Context :: struct {
    name:          string,
    capture_names: [dynamic]string,
}

Emitter_Features :: struct {
    dynamic_literals: bool,
    core_map:         bool,
    core_map_capture_max: int,
    core_filter:      bool,
    core_filter_capture_max: int,
    core_reduce:      bool,
    core_remove:      bool,
    core_remove_capture_max: int,
    core_keep:        bool,
    core_keep_capture_max: int,
    core_concat:      bool,
    core_get_or_default: bool,
    core_contains_value: bool,
    core_into:        bool,
    core_map_in_place: bool,
    core_map_in_place_capture_max: int,
    core_filter_in_place: bool,
    core_filter_in_place_capture_max: int,
    core_remove_in_place: bool,
    core_remove_in_place_capture_max: int,
    core_keep_in_place: bool,
    core_keep_in_place_capture_max: int,
    core_sort_by:     bool,
    core_sort_by_in_place: bool,
    core_tap:         bool,
    core_strings:     bool,
    core_fmt:         bool,
    map_fields:       [dynamic]string,
    index_by_fields:  [dynamic]string,
    group_by_fields:  [dynamic]string,
    count_by_fields:  [dynamic]string,
    sum_by_fields:    [dynamic]Sum_By_Field,
    distinct_by_fields: [dynamic]string,
    partition_by_fields: [dynamic]string,
    sort_by_fields:   [dynamic]string,
    sort_by_in_place_fields: [dynamic]string,
    sort_by_callbacks: [dynamic]string,
    sort_by_in_place_callbacks: [dynamic]string,
    filter_fields:    [dynamic]string,
    filter_in_place_fields: [dynamic]string,
    remove_fields:    [dynamic]string,
    remove_in_place_fields: [dynamic]string,
    take_while_fields: [dynamic]string,
    drop_while_fields: [dynamic]string,
    find_fields:      [dynamic]string,
    some_fields:      [dynamic]string,
    every_fields:     [dynamic]string,
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
    local_types:               [dynamic]Param,
    local_type_scope_marks:    [dynamic]int,
    local_struct_scope_marks:  [dynamic]int,
    local_union_scope_marks:   [dynamic]int,
    callback_contexts:         [dynamic]Callback_Context,
    callback_context_scope_marks: [dynamic]int,
    captured_proc_specializations: ^[dynamic]Captured_Proc_Specialization,
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

resolved_import_path_literal_for_emit :: proc(path_literal: string) -> string {
    raw := path_literal
    if len(raw) >= 2 && raw[0] == '"' && raw[len(raw)-1] == '"' {
        raw = unquote_string(raw)
    }
    if !strings.has_prefix(raw, "kvist_vendor:") {
        return path_literal
    }

    root, ok_root := repo_root_for_path(".")
    if !ok_root {
        return path_literal
    }
    defer delete(root)

    vendor_path := raw[len("kvist_vendor:"):]
    if vendor_path == "" {
        return path_literal
    }

    parts := make([dynamic]string, 0, 4)
    defer delete(parts)
    append(&parts, root, "vendor")

    switch {
    case vendor_path == "http":
        append(&parts, "odin-http")
    case strings.has_prefix(vendor_path, "http/"):
        append(&parts, "odin-http")
        append(&parts, vendor_path[len("http/"):])
    case:
        return path_literal
    }

    resolved, join_err := os.join_path(parts[:], context.allocator)
    if join_err != nil {
        return path_literal
    }
    defer delete(resolved)
    return fmt.tprintf("%q", resolved)
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
        switch alias {
        case "kvist", "core", "arr", "str", "map", "set", "soa", "io", "json", "cli":
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
    if alias == "core" || alias == "arr" || alias == "str" || alias == "map" || alias == "set" || alias == "soa" || alias == "io" || alias == "json" || alias == "cli" {
        return fmt.tprintf("%s/%s", alias, suffix), true, Compile_Error{}, true
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
    return head, false, Compile_Error{}, true
}

deprecated_builtin_collection_head :: proc(head: string) -> (canonical: string, deprecated: bool) {
    switch head {
    case "map":
        return "arr/map", true
    case "filter":
        return "arr/filter", true
    case "remove":
        return "arr/remove", true
    case "reduce":
        return "arr/reduce", true
    case "map-indexed":
        return "arr/map-indexed", true
    case "keep":
        return "arr/keep", true
    case "mapcat":
        return "arr/mapcat", true
    case "map!":
        return "arr/map!", true
    case "map-indexed!":
        return "arr/map-indexed!", true
    case "filter!":
        return "arr/filter!", true
    case "remove!":
        return "arr/remove!", true
    case "keep!":
        return "arr/keep!", true
    case "into":
        return "arr/into", true
    case "into!":
        return "arr/into!", true
    case "interpose":
        return "arr/interpose", true
    case "interleave":
        return "arr/interleave", true
    case "reverse":
        return "arr/reverse", true
    case "reverse!":
        return "arr/reverse!", true
    case "shuffle":
        return "arr/shuffle", true
    case "shuffle!":
        return "arr/shuffle!", true
    case "sort":
        return "arr/sort", true
    case "sort!":
        return "arr/sort!", true
    case "sort-by":
        return "arr/sort-by", true
    case "sort-by!":
        return "arr/sort-by!", true
    case "split-at":
        return "arr/split-at", true
    case "partition":
        return "arr/partition", true
    case "partition-all":
        return "arr/partition-all", true
    case "partition-by":
        return "arr/partition-by", true
    case "index-by":
        return "arr/index-by", true
    case "group-by":
        return "arr/group-by", true
    case "count-by":
        return "arr/count-by", true
    case "sum-by":
        return "arr/sum-by", true
    case "frequencies":
        return "arr/frequencies", true
    case "distinct":
        return "arr/distinct", true
    case "distinct-by":
        return "arr/distinct-by", true
    case "range":
        return "arr/range", true
    case "repeat":
        return "arr/repeat", true
    case "repeatedly":
        return "arr/repeatedly", true
    case "iterate":
        return "arr/iterate", true
    case "cycle":
        return "arr/cycle", true
    case "take":
        return "arr/take", true
    case "drop":
        return "arr/drop", true
    case "butlast":
        return "arr/butlast", true
    case "drop-last":
        return "arr/drop-last", true
    case "take-nth":
        return "arr/take-nth", true
    case "take-while":
        return "arr/take-while", true
    case "drop-while":
        return "arr/drop-while", true
    case "find":
        return "arr/find", true
    case "some?":
        return "arr/some?", true
    case "every?":
        return "arr/every?", true
    case "first":
        return "arr/first", true
    case "second":
        return "arr/second", true
    case "last":
        return "arr/last", true
    case "nth":
        return "arr/nth", true
    case "rest":
        return "arr/rest", true
    case "zipmap":
        return "map/zip", true
    case "keys":
        return "map/keys", true
    case "vals":
        return "map/vals", true
    case "merge":
        return "map/merge", true
    case "merge!":
        return "map/merge!", true
    case "slurp":
        return "io/read", true
    case "spit":
        return "io/write", true
    case:
        return "", false
    }
}

deprecated_builtin_collection_head_error :: proc(head: CST_Form) -> (Compile_Error, bool) {
    canonical, deprecated := deprecated_builtin_collection_head(head.text)
    if !deprecated {
        return Compile_Error{}, false
    }
    return Compile_Error{message = fmt.tprintf("`%s` is no longer a core helper; use `%s`", head.text, display_head_name(canonical)), span = head.span}, true
}

Thread_Result_Kind :: enum {
    Unknown,
    Owned,
    Owned_Borrowing,
    View,
    Scalar,
}

mark_dynamic_literals :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.dynamic_literals = true
    }
}

emit_warning :: proc(e: ^Emitter, message: string, span: Span) {
    if e.warnings == nil {
        return
    }
    append(e.warnings, Compile_Warning{message = strings.clone(message), span = span})
}

mark_core_map :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_map = true
    }
}

mark_core_map_capture :: proc(e: ^Emitter, capture_count: int) {
    if e.features != nil && capture_count > e.features.core_map_capture_max {
        e.features.core_map_capture_max = capture_count
    }
}

mark_core_filter :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_filter = true
    }
}

mark_core_filter_capture :: proc(e: ^Emitter, capture_count: int) {
    if e.features != nil && capture_count > e.features.core_filter_capture_max {
        e.features.core_filter_capture_max = capture_count
    }
}

mark_core_reduce :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_reduce = true
    }
}

mark_core_remove :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_remove = true
    }
}

mark_core_remove_capture :: proc(e: ^Emitter, capture_count: int) {
    if e.features != nil && capture_count > e.features.core_remove_capture_max {
        e.features.core_remove_capture_max = capture_count
    }
}

mark_core_keep :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_keep = true
    }
}

mark_core_keep_capture :: proc(e: ^Emitter, capture_count: int) {
    if e.features != nil && capture_count > e.features.core_keep_capture_max {
        e.features.core_keep_capture_max = capture_count
    }
}

mark_core_concat :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_concat = true
    }
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

mark_core_into :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_into = true
    }
}

mark_core_map_in_place :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_map_in_place = true
    }
}

mark_core_map_in_place_capture :: proc(e: ^Emitter, capture_count: int) {
    if e.features != nil && capture_count > e.features.core_map_in_place_capture_max {
        e.features.core_map_in_place_capture_max = capture_count
    }
}

mark_core_filter_in_place :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_filter_in_place = true
    }
}

mark_core_filter_in_place_capture :: proc(e: ^Emitter, capture_count: int) {
    if e.features != nil && capture_count > e.features.core_filter_in_place_capture_max {
        e.features.core_filter_in_place_capture_max = capture_count
    }
}

mark_core_remove_in_place :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_remove_in_place = true
    }
}

mark_core_remove_in_place_capture :: proc(e: ^Emitter, capture_count: int) {
    if e.features != nil && capture_count > e.features.core_remove_in_place_capture_max {
        e.features.core_remove_in_place_capture_max = capture_count
    }
}

mark_core_keep_in_place :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_keep_in_place = true
    }
}

mark_core_keep_in_place_capture :: proc(e: ^Emitter, capture_count: int) {
    if e.features != nil && capture_count > e.features.core_keep_in_place_capture_max {
        e.features.core_keep_in_place_capture_max = capture_count
    }
}

mark_core_sort_by :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_sort_by = true
    }
}

mark_core_sort_by_in_place :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_sort_by_in_place = true
    }
}

mark_core_tap :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_tap = true
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

append_unique_sum_by_field :: proc(items: ^[dynamic]Sum_By_Field, key, value: string) {
    for item in items^ {
        if item.key == key && item.value == value {
            return
        }
    }
    append(items, Sum_By_Field{key = key, value = value})
}

mark_core_map_field :: proc(e: ^Emitter, field: string) {
    if e.features != nil {
        append_unique_string(&e.features.map_fields, field)
    }
}

mark_core_index_by_field :: proc(e: ^Emitter, field: string) {
    if e.features != nil {
        append_unique_string(&e.features.index_by_fields, field)
    }
}

mark_core_group_by_field :: proc(e: ^Emitter, field: string) {
    if e.features != nil {
        append_unique_string(&e.features.group_by_fields, field)
    }
}

mark_core_count_by_field :: proc(e: ^Emitter, field: string) {
    if e.features != nil {
        append_unique_string(&e.features.count_by_fields, field)
    }
}

mark_core_sum_by_field :: proc(e: ^Emitter, key, value: string) {
    if e.features != nil {
        append_unique_sum_by_field(&e.features.sum_by_fields, key, value)
    }
}

mark_core_distinct_by_field :: proc(e: ^Emitter, field: string) {
    if e.features != nil {
        append_unique_string(&e.features.distinct_by_fields, field)
    }
}

mark_core_partition_by_field :: proc(e: ^Emitter, field: string) {
    if e.features != nil {
        append_unique_string(&e.features.partition_by_fields, field)
    }
}

mark_core_sort_by_field :: proc(e: ^Emitter, field: string) {
    if e.features != nil {
        append_unique_string(&e.features.sort_by_fields, field)
    }
}

mark_core_sort_by_in_place_field :: proc(e: ^Emitter, field: string) {
    if e.features != nil {
        append_unique_string(&e.features.sort_by_in_place_fields, field)
    }
}

mark_core_sort_by_callback :: proc(e: ^Emitter, callback: string) {
    if e.features != nil {
        append_unique_string(&e.features.sort_by_callbacks, callback)
    }
}

mark_core_sort_by_in_place_callback :: proc(e: ^Emitter, callback: string) {
    if e.features != nil {
        append_unique_string(&e.features.sort_by_in_place_callbacks, callback)
    }
}

mark_core_filter_field :: proc(e: ^Emitter, field: string) {
    if e.features != nil {
        append_unique_string(&e.features.filter_fields, field)
    }
}

mark_core_filter_in_place_field :: proc(e: ^Emitter, field: string) {
    if e.features != nil {
        append_unique_string(&e.features.filter_in_place_fields, field)
    }
}

mark_core_remove_field :: proc(e: ^Emitter, field: string) {
    if e.features != nil {
        append_unique_string(&e.features.remove_fields, field)
    }
}

mark_core_remove_in_place_field :: proc(e: ^Emitter, field: string) {
    if e.features != nil {
        append_unique_string(&e.features.remove_in_place_fields, field)
    }
}

mark_core_take_while_field :: proc(e: ^Emitter, field: string) {
    if e.features != nil {
        append_unique_string(&e.features.take_while_fields, field)
    }
}

mark_core_drop_while_field :: proc(e: ^Emitter, field: string) {
    if e.features != nil {
        append_unique_string(&e.features.drop_while_fields, field)
    }
}

mark_core_find_field :: proc(e: ^Emitter, field: string) {
    if e.features != nil {
        append_unique_string(&e.features.find_fields, field)
    }
}

mark_core_some_field :: proc(e: ^Emitter, field: string) {
    if e.features != nil {
        append_unique_string(&e.features.some_fields, field)
    }
}

mark_core_every_field :: proc(e: ^Emitter, field: string) {
    if e.features != nil {
        append_unique_string(&e.features.every_fields, field)
    }
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

Brace_Pair :: struct {
    key:   string,
    value: string,
}

emit_brace_pair_texts :: proc(e: ^Emitter, form: CST_Form, keyword_fields := true) -> (pairs: [dynamic]Brace_Pair, err: Compile_Error, ok: bool) {
    i := 0
    for i < len(form.items) {
        if i+1 >= len(form.items) {
            return pairs, Compile_Error{message = "missing brace-form value", span = form.span}, false
        }

        key := form.items[i]
        val := form.items[i+1]
        value_text, err_value, ok_value := emit_expr(e, val)
        if !ok_value {
            return pairs, err_value, false
        }

        #partial switch key.kind {
        case .Keyword:
            return pairs, Compile_Error{message = "keywords are syntax markers, not brace labels or map keys; use field labels like name: or ordinary key values", span = key.span}, false
        case .Symbol:
            if len(key.text) > 1 && key.text[len(key.text)-1] == ':' {
                if keyword_fields {
                    append(&pairs, Brace_Pair{key = map_name(key.text[:len(key.text)-1]), value = value_text})
                    i += 2
                    continue
                }
            }
            key_text, err_key, ok_key := emit_expr(e, key)
            if !ok_key {
                return pairs, err_key, false
            }
            append(&pairs, Brace_Pair{key = key_text, value = value_text})
        case .String:
            append(&pairs, Brace_Pair{key = key.text, value = value_text})
        case:
            key_text, err_key, ok_key := emit_expr(e, key)
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

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for pair, idx in pairs {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "%s = %s", pair.key, pair.value)
    }
    return strings.clone(strings.to_string(builder)), {}, true
}

emit_vector_item_texts :: proc(e: ^Emitter, form: CST_Form) -> (items: [dynamic]string, err: Compile_Error, ok: bool) {
    for item in form.items {
        text, err_item, ok_item := emit_expr(e, item)
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

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for text, idx in items {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        strings.write_string(&builder, text)
    }
    return strings.clone(strings.to_string(builder)), {}, true
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
    items, err_items, ok_items := emit_vector_item_texts(e, form)
    if !ok_items {
        return "", err_items, false
    }
    if !has_multiline_items(items[:]) {
        inner, err_inner, ok_inner := emit_vector_items(e, form)
        if !ok_inner {
            return "", err_inner, false
        }
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

    pairs, err_pairs, ok_pairs := emit_brace_pair_texts(e, form, keyword_fields)
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
        inner, err_inner, ok_inner := emit_brace_pairs(e, form, keyword_fields)
        if !ok_inner {
            return "", err_inner, false
        }
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
    suffix := map_name(head[slash+1:])
    package_name := fmt.tprintf("%s__%s", alias, suffix)
    found_proc, ok_proc = find_proc_decl(e, package_name)
    if ok_proc {
        return package_name, found_proc, true
    }

    transitive_suffix := fmt.tprintf("__%s", package_name)
    matched_name := ""
    matched_proc: ^Proc_Decl = nil
    matched_count := 0
    for idx in 0..<len(e.decls) {
        decl := &e.decls[idx]
        if decl.kind == .Proc && strings.has_suffix(decl.proc_decl.name, transitive_suffix) {
            matched_name = decl.proc_decl.name
            matched_proc = &decl.proc_decl
            matched_count += 1
        }
    }
    if matched_count == 1 {
        return matched_name, matched_proc, true
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
         "string", "cstring", "rawptr", "any":
        return true
    }
    return false
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

emit_named_call_with_defaults :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, form: CST_Form) -> (arg_texts: [dynamic]string, err: Compile_Error, ok: bool) {
    if form.kind != .Brace {
        return arg_texts, Compile_Error{message = "named arguments expect a brace form", span = form.span}, false
    }

    named_values := make([dynamic]Brace_Pair, 0, len(form.items)/2)
    defer delete(named_values)

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
            default_text, err_default, ok_default := emit_expr(e, param.default_value)
            if !ok_default {
                return arg_texts, err_default, false
            }
            append(&arg_texts, fmt.tprintf("%s = %s", param.name, default_text))
            continue
        }
        missing: [dynamic]string
        append(&missing, label_text(param.name))
        for later_idx := param_idx + 1; later_idx < len(proc_decl.params); later_idx += 1 {
            later := proc_decl.params[later_idx]
            if !later.has_default {
                append(&missing, label_text(later.name))
            }
        }
        message := fmt.tprintf("missing required named arguments: %s", join_strings(missing[:], ", "))
        delete_string_slice(&missing)
        return arg_texts, Compile_Error{message = named_arg_message_with_valid_keys(message, proc_decl), span = form.span}, false
    }

    return arg_texts, Compile_Error{}, true
}

emit_positional_call_with_defaults :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, args: []CST_Form, span: Span) -> (arg_texts: [dynamic]string, err: Compile_Error, ok: bool) {
    if len(args) > len(proc_decl.params) {
        return arg_texts, Compile_Error{message = fmt.tprintf("%s expects at most %d arguments", proc_decl.name, len(proc_decl.params)), span = span}, false
    }

    for arg in args {
        arg_text, err_arg, ok_arg := emit_expr(e, arg)
        if !ok_arg {
            return arg_texts, err_arg, false
        }
        append(&arg_texts, arg_text)
    }
    for idx := len(args); idx < len(proc_decl.params); idx += 1 {
        param := proc_decl.params[idx]
        if !param.has_default {
            return arg_texts, Compile_Error{message = fmt.tprintf("%s expects at least %d arguments", proc_decl.name, idx+1), span = span}, false
        }
        default_text, err_default, ok_default := emit_expr(e, param.default_value)
        if !ok_default {
            return arg_texts, err_default, false
        }
        append(&arg_texts, default_text)
    }
    return arg_texts, Compile_Error{}, true
}

emit_mixed_call_with_defaults :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, positional_args: []CST_Form, named_form: CST_Form, span: Span) -> (arg_texts: [dynamic]string, err: Compile_Error, ok: bool) {
    if len(positional_args) > len(proc_decl.params) {
        return arg_texts, Compile_Error{message = fmt.tprintf("%s expects at most %d arguments", proc_decl.name, len(proc_decl.params)), span = span}, false
    }

    named_values := make([dynamic]Brace_Pair, 0, len(named_form.items)/2)
    defer delete(named_values)

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
    }

    for arg, idx in positional_args {
        param := proc_decl.params[idx]
        arg_text, err_arg, ok_arg := emit_expr(e, arg)
        if !ok_arg {
            return arg_texts, err_arg, false
        }
        for pair in named_values {
            if pair.key == param.name {
                return arg_texts, Compile_Error{message = fmt.tprintf("named argument %s overlaps positional argument %d", label_text(param.name), idx+1), span = named_form.span}, false
            }
        }
        append(&arg_texts, arg_text)
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
            default_text, err_default, ok_default := emit_expr(e, param.default_value)
            if !ok_default {
                return arg_texts, err_default, false
            }
            append(&arg_texts, fmt.tprintf("%s = %s", param.name, default_text))
            continue
        }
        missing: [dynamic]string
        append(&missing, label_text(param.name))
        for later_idx := idx + 1; later_idx < len(proc_decl.params); later_idx += 1 {
            later := proc_decl.params[later_idx]
            if !later.has_default {
                append(&missing, label_text(later.name))
            }
        }
        message := fmt.tprintf("missing required arguments after positional prefix: %s", join_strings(missing[:], ", "))
        delete_string_slice(&missing)
        return arg_texts, Compile_Error{message = named_arg_message_with_valid_keys(message, proc_decl), span = span}, false
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

shallow_field_place_parts :: proc(place: CST_Form) -> (target: CST_Form, field: string, field_span: Span, ok: bool) {
    if place.kind == .List &&
       len(place.items) == 3 &&
       place.items[0].kind == .Symbol &&
       place.items[0].text == "__kvist_field" &&
       place.items[2].kind == .Symbol {
        return place.items[1], map_name(place.items[2].text), place.items[2].span, true
    }
    if place.kind == .Symbol {
        dot := strings.index(place.text, ".")
        if dot > 0 && dot+1 < len(place.text) {
            return CST_Form{kind = .Symbol, text = place.text[:dot], span = place.span},
                   map_name(place.text[dot+1:]),
                   place.span,
                   true
        }
    }
    return {}, "", {}, false
}

shallow_assoc_args :: proc(form: CST_Form) -> (target: CST_Form, field: string, field_span: Span, value: CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) == 3 {
        place_target, place_field, place_span, ok_place := shallow_field_place_parts(form.items[1])
        if !ok_place {
            return {}, "", {}, {}, Compile_Error{message = "core/assoc expects a shallow field place such as user.name", span = form.items[1].span}, false
        }
        return place_target, place_field, place_span, form.items[2], {}, true
    }
    if len(form.items) == 4 {
        selector_field, ok_field := field_from_selector(form.items[2])
        if !ok_field {
            return {}, "", {}, {}, Compile_Error{message = "core/assoc currently expects a shallow field selector such as .name", span = form.items[2].span}, false
        }
        return form.items[1], selector_field, form.items[2].span, form.items[3], {}, true
    }
    return {}, "", {}, {}, Compile_Error{message = "core/assoc expects place and value, or target, field selector, and value", span = form.span}, false
}

shallow_update_args :: proc(form: CST_Form) -> (target: CST_Form, field: string, field_span: Span, updater: CST_Form, extra_forms: []CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) >= 3 {
        place_target, place_field, place_span, ok_place := shallow_field_place_parts(form.items[1])
        if ok_place {
            return place_target, place_field, place_span, form.items[2], form.items[3:], {}, true
        }
    }
    if len(form.items) >= 4 {
        selector_field, ok_field := field_from_selector(form.items[2])
        if !ok_field {
            return {}, "", {}, {}, nil, Compile_Error{message = "core/update currently expects a shallow field place such as user.age, or a selector such as .age", span = form.items[2].span}, false
        }
        return form.items[1], selector_field, form.items[2].span, form.items[3], form.items[4:], {}, true
    }
    return {}, "", {}, {}, nil, Compile_Error{message = "core/update expects place, updater, and optional arguments", span = form.span}, false
}

shallow_update_return_type :: proc(e: ^Emitter, form: CST_Form) -> (string, bool) {
    if form.kind != .List || len(form.items) < 2 {
        return "", false
    }
    if place_target, _, _, ok_place := shallow_field_place_parts(form.items[1]); ok_place {
        return obvious_form_type(e, place_target)
    }
    return obvious_form_type(e, form.items[1])
}

emit_shallow_assoc_copy_expr :: proc(e: ^Emitter, target_text, target_ty, field: string, field_span: Span, value_form: CST_Form) -> (string, Compile_Error, bool) {
    field_ty, ok_field_ty := struct_field_type_for_update(e, target_ty, field)
    if !ok_field_ty {
        return "", Compile_Error{message = fmt.tprintf("core/assoc could not find field .%s on %s", field, target_ty), span = field_span}, false
    }
    value_text, err_value, ok_value := emit_expr_for_expected_type(e, value_form, field_ty)
    if !ok_value {
        return "", err_value, false
    }
    temp := shallow_update_temp_name(e)
    return fmt.tprintf("(proc(kvist_target: %s, kvist_value: %s) -> %s %s\n    %s := kvist_target\n    %s.%s = kvist_value\n    return %s\n})(%s, %s)",
                       target_ty, field_ty, target_ty, "{", temp, temp, field, temp, target_text, value_text), {}, true
}

emit_shallow_update_copy_expr :: proc(e: ^Emitter, target_text, target_ty, field: string, field_span: Span, updater_form: CST_Form, extra_forms: []CST_Form) -> (string, Compile_Error, bool) {
    if _, ok_field_ty := struct_field_type_for_update(e, target_ty, field); !ok_field_ty {
        return "", Compile_Error{message = fmt.tprintf("core/update could not find field .%s on %s", field, target_ty), span = field_span}, false
    }
    if updater_form.kind != .Symbol {
        return "", Compile_Error{message = "core/update currently expects an updater function or operator symbol", span = updater_form.span}, false
    }

    temp := shallow_update_temp_name(e)
    current := fmt.tprintf("%s.%s", temp, field)
    extra_arg_texts: [dynamic]string
    arg_texts: [dynamic]string
    param_texts: [dynamic]string
    call_arg_texts: [dynamic]string
    append(&param_texts, fmt.tprintf("kvist_target: %s", target_ty))
    append(&call_arg_texts, target_text)
    append(&arg_texts, current)
    for extra_form, idx in extra_forms {
        extra_ty, ok_extra_ty := obvious_form_type(e, extra_form)
        if !ok_extra_ty {
            return "", Compile_Error{message = "core/update extra arguments must have obvious types in shallow copy updates", span = extra_form.span}, false
        }
        extra_text, err_extra, ok_extra := emit_expr_for_expected_type(e, extra_form, extra_ty)
        if !ok_extra {
            return "", err_extra, false
        }
        arg_name := fmt.tprintf("kvist_arg_%d", idx+1)
        append(&param_texts, fmt.tprintf("%s: %s", arg_name, extra_ty))
        append(&call_arg_texts, extra_text)
        append(&extra_arg_texts, arg_name)
        append(&arg_texts, arg_name)
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    param_list := strings.join(param_texts[:], ", ", context.allocator)
    defer delete(param_list)
    call_args := strings.join(call_arg_texts[:], ", ", context.allocator)
    defer delete(call_args)
    fmt.sbprintf(&builder, "(proc(%s) -> %s %s\n", param_list, target_ty, "{")
    fmt.sbprintf(&builder, "    %s := kvist_target\n", temp)
    if compound_text, ok_compound := emit_compound_update_op(updater_form, extra_arg_texts[:]); ok_compound {
        fmt.sbprintf(&builder, "    %s.%s %s\n", temp, field, compound_text)
    } else {
        rhs, err_rhs, ok_rhs := emit_update_rhs(e, updater_form, arg_texts[:])
        if !ok_rhs {
            return "", err_rhs, false
        }
        fmt.sbprintf(&builder, "    %s.%s = %s\n", temp, field, rhs)
    }
    fmt.sbprintf(&builder, "    return %s\n", temp)
    strings.write_string(&builder, "})")
    return fmt.tprintf("%s(%s)", strings.to_string(builder), call_args), {}, true
}

emit_shallow_assoc_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    target_form, field, field_span, value_form, err_args, ok_args := shallow_assoc_args(form)
    if !ok_args {
        return "", err_args, false
    }
    target_ty, ok_ty := obvious_form_type(e, target_form)
    if !ok_ty {
        return "", Compile_Error{message = "core/assoc expects a target with an obvious struct type; bind or annotate the value first", span = target_form.span}, false
    }
    target_text, err_target, ok_target := emit_expr(e, target_form)
    if !ok_target {
        return "", err_target, false
    }
    return emit_shallow_assoc_copy_expr(e, target_text, target_ty, field, field_span, value_form)
}

emit_shallow_update_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    target_form, field, field_span, updater_form, extra_forms, err_args, ok_args := shallow_update_args(form)
    if !ok_args {
        return "", err_args, false
    }
    target_ty, ok_ty := obvious_form_type(e, target_form)
    if !ok_ty {
        return "", Compile_Error{message = "core/update expects a target with an obvious struct type; bind or annotate the value first", span = target_form.span}, false
    }
    target_text, err_target, ok_target := emit_expr(e, target_form)
    if !ok_target {
        return "", err_target, false
    }
    return emit_shallow_update_copy_expr(e, target_text, target_ty, field, field_span, updater_form, extra_forms)
}

emit_thread_shallow_assoc_expr :: proc(e: ^Emitter, current, target_ty, field: string, field_span: Span, value_form: CST_Form) -> (string, Compile_Error, bool) {
    if target_ty == "" {
        return "", Compile_Error{message = "threaded core/assoc requires an obvious struct type before the .field step; bind or annotate the value first", span = field_span}, false
    }
    return emit_shallow_assoc_copy_expr(e, current, target_ty, field, field_span, value_form)
}

emit_thread_shallow_update_expr :: proc(e: ^Emitter, current, target_ty, field: string, field_span: Span, updater_form: CST_Form, extra_forms: []CST_Form) -> (string, Compile_Error, bool) {
    if target_ty == "" {
        return "", Compile_Error{message = "threaded core/update requires an obvious struct type before the .field step; bind or annotate the value first", span = field_span}, false
    }
    return emit_shallow_update_copy_expr(e, current, target_ty, field, field_span, updater_form, extra_forms)
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

emit_compound_update_op :: proc(fn_form: CST_Form, extra_arg_texts: []string) -> (string, bool) {
    if fn_form.kind != .Symbol {
        return "", false
    }

    switch fn_form.text {
    case "inc":
        if len(extra_arg_texts) == 0 {
            return "+= 1", true
        }
    case "dec":
        if len(extra_arg_texts) == 0 {
            return "-= 1", true
        }
    case "+":
        if len(extra_arg_texts) == 1 {
            return fmt.tprintf("+= (%s)", extra_arg_texts[0]), true
        }
    case "-":
        if len(extra_arg_texts) == 1 {
            return fmt.tprintf("-= (%s)", extra_arg_texts[0]), true
        }
    case "*":
        if len(extra_arg_texts) == 1 {
            return fmt.tprintf("*= (%s)", extra_arg_texts[0]), true
        }
    case "/":
        if len(extra_arg_texts) == 1 {
            return fmt.tprintf("/= (%s)", extra_arg_texts[0]), true
        }
    }

    return "", false
}

emit_update_place_assignment_stmt :: proc(
    e: ^Emitter,
    lhs, current: string,
    place_span: Span,
    updater_form: CST_Form,
    extra_forms: []CST_Form,
) -> (Compile_Error, bool) {
    if updater_form.kind != .Symbol && updater_form.kind != .List {
        return Compile_Error{message = "core/update! expects updater function or operator", span = updater_form.span}, false
    }

    extra_arg_texts: [dynamic]string
    arg_texts: [dynamic]string
    append(&arg_texts, current)
    for extra_form in extra_forms {
        extra_text, err_extra, ok_extra := emit_expr(e, extra_form)
        if !ok_extra {
            return err_extra, false
        }
        append(&extra_arg_texts, extra_text)
        append(&arg_texts, extra_text)
    }
    if compound_text, ok_compound := emit_compound_update_op(updater_form, extra_arg_texts[:]); ok_compound {
        emit_indent(e)
        strings.write_string(&e.builder, lhs)
        record_current_line_fragment_map(e, 0, lhs, place_span)
        strings.write_string(&e.builder, " ")
        strings.write_string(&e.builder, compound_text)
        emit_raw_newline(e)
        return {}, true
    }
    rhs, err_rhs, ok_rhs := emit_update_rhs(e, updater_form, arg_texts[:])
    if !ok_rhs {
        return err_rhs, false
    }
    emit_indent(e)
    strings.write_string(&e.builder, lhs)
    record_current_line_fragment_map(e, 0, lhs, place_span)
    strings.write_string(&e.builder, " = ")
    strings.write_string(&e.builder, rhs)
    record_current_line_fragment_map(e, len(lhs) + len(" = "), rhs, updater_form.span)
    emit_raw_newline(e)
    return {}, true
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
    case "core/get", "core-get", "arr/get", "arr-get", "arr/nth":
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
    err_owned, bad_owned := owned_result_usage_error(form.items[2], true)
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
    lhs, err_lhs, ok_lhs := emit_expr(e, form.items[1])
    if !ok_lhs {
        return err_lhs, false
    }
    err_owned, bad_owned := owned_result_usage_error(form.items[3], true)
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
    return head == "assoc" || head == "core/assoc" || head == "core-assoc" ||
           source_package_surface_head(head) == "core/assoc"
}

head_is_core_update :: proc(head: string) -> bool {
    return head == "update" || head == "core/update" || head == "core-update" ||
           source_package_surface_head(head) == "core/update"
}

thread_step_is_shallow_value_update :: proc(step: CST_Form, thread_last: bool) -> bool {
    if thread_last || step.kind != .List || len(step.items) < 2 || step.items[0].kind != .Symbol {
        return false
    }
    if !head_is_core_assoc(step.items[0].text) && !head_is_core_update(step.items[0].text) {
        return false
    }
    _, ok_field := field_from_selector(step.items[1])
    return ok_field
}

emit_thread_step :: proc(e: ^Emitter, current: string, step: CST_Form, thread_last: bool, current_ty := "") -> (string, Compile_Error, bool) {
    #partial switch step.kind {
    case .Symbol:
        if field, ok_field := field_from_selector(step); ok_field {
            return fmt.tprintf("%s.%s", current, field), {}, true
        }
        step_text, _, err_head, ok_head := resolve_kvist_head(e, step.text)
        if !ok_head {
            err_head.span = step.span
            return "", err_head, false
        }
        if thread_last && step_text == "slice" {
            return "", Compile_Error{message = "`slice` has moved to `core/slice`", span = step.span}, false
        }
        if thread_last && step_text == "core/slice" {
            return slice_all_expr_text(current), {}, true
        }
        args: [dynamic]string
        append(&args, current)
        return emit_call_text(map_name(step_text), args[:]), {}, true
    case .List:
        if len(step.items) == 0 {
            return "", Compile_Error{message = "thread step cannot be an empty list", span = step.span}, false
        }
        head := step.items[0]
        if field, ok_field := field_from_selector(head); ok_field {
            if len(step.items) != 1 {
                return "", Compile_Error{message = "field selector thread step does not take arguments", span = step.span}, false
            }
            return fmt.tprintf("%s.%s", current, field), {}, true
        }
        if head.kind != .Symbol {
            return "", Compile_Error{message = "thread list step expects symbol or field selector head", span = head.span}, false
        }
        canonical_head, _, err_head, ok_head := resolve_kvist_head(e, head.text)
        if !ok_head {
            err_head.span = head.span
            return "", err_head, false
        }
        head.text = canonical_head
        err_deprecated, deprecated := deprecated_builtin_collection_head_error(head)
        if deprecated {
            return "", err_deprecated, false
        }
        surface_head := display_head_name(head.text)
        if !thread_last && head_is_core_assoc(head.text) {
            if len(step.items) != 3 {
                return "", Compile_Error{message = "core/assoc thread step expects .field and value", span = step.span}, false
            }
            field, ok_field := field_from_selector(step.items[1])
            if !ok_field {
                return "", Compile_Error{message = "core/assoc thread step expects a shallow field selector such as .name", span = step.items[1].span}, false
            }
            return emit_thread_shallow_assoc_expr(e, current, current_ty, field, step.items[1].span, step.items[2])
        }
        if !thread_last && head_is_core_update(head.text) {
            if len(step.items) < 3 {
                return "", Compile_Error{message = "core/update thread step expects .field, updater, and optional arguments", span = step.span}, false
            }
            field, ok_field := field_from_selector(step.items[1])
            if !ok_field {
                return "", Compile_Error{message = "core/update thread step expects a shallow field selector such as .age", span = step.items[1].span}, false
            }
            return emit_thread_shallow_update_expr(e, current, current_ty, field, step.items[1].span, step.items[2], step.items[3:])
        }
        if thread_last {
            switch head.text {
            case "arr__map":
                head.text = "arr/map"
            case "arr__filter":
                head.text = "arr/filter"
            case "arr__remove":
                head.text = "arr/remove"
            case "arr__map_indexed":
                head.text = "arr-map-indexed"
            case "arr__keep":
                head.text = "arr-keep"
            case "arr__mapcat":
                head.text = "arr-mapcat"
            case "arr__shuffle":
                head.text = "arr/shuffle"
            case "arr__sort":
                head.text = "arr/sort"
            case "arr__first":
                head.text = "arr/first"
            case "arr__second":
                head.text = "arr/second"
            case "arr__last":
                head.text = "arr/last"
            case "arr__rest":
                head.text = "arr/rest"
            case "arr__nth":
                head.text = "arr/nth"
            case "arr__partition_by", "arr__partition-by":
                head.text = "arr/partition-by"
            case "arr__index_by", "arr__index-by":
                head.text = "arr/index-by"
            case "arr__group_by", "arr__group-by":
                head.text = "arr/group-by"
            case "arr__count_by", "arr__count-by":
                head.text = "arr/count-by"
            case "arr__sum_by", "arr__sum-by":
                head.text = "arr/sum-by"
            }
        }
        if head.text == "tap>" || head.text == "core/tap>" || head.text == "core-tap" {
            if len(step.items) > 2 {
                return "", Compile_Error{message = "tap> thread step expects optional label", span = step.span}, false
            }
            mark_core_tap(e)
            if len(step.items) == 1 {
                return emit_call_text("kvist_tap", []string{current}), {}, true
            }
            label_form := step.items[1]
            label := ""
            if label_form.kind == .String {
                label = label_form.text
            } else {
                return "", Compile_Error{message = "tap> label must be a string literal", span = label_form.span}, false
            }
            return emit_call_text("kvist_tap_labeled", []string{label, current}), {}, true
        }
        if thread_last && head.text == "core/count" {
            if len(step.items) != 1 {
                return "", Compile_Error{message = "core/count thread step expects no extra arguments", span = step.span}, false
            }
            return fmt.tprintf("len(%s)", slice_all_expr_text(current)), {}, true
        }
        if thread_last && head.text == "core/empty?" {
            if len(step.items) != 1 {
                return "", Compile_Error{message = "core/empty? thread step expects no extra arguments", span = step.span}, false
            }
            return fmt.tprintf("len(%s) == 0", slice_all_expr_text(current)), {}, true
        }
        is_arr_map := head.text == "arr-map" || head.text == "arr/map"
        is_arr_filter := head.text == "arr-filter" || head.text == "arr/filter"
        is_arr_remove := head.text == "arr-remove" || head.text == "arr/remove"
        if thread_last && (is_arr_map || is_arr_filter || is_arr_remove) {
            if len(step.items) != 2 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects one function argument", surface_head), span = step.span}, false
            }
            collection := slice_all_expr_text(current)
            if is_arr_map {
                return emit_map_callback_call(e, step.items[1], collection)
            }
            if is_arr_remove {
                return emit_predicate_callback_call(e, "kvist_remove", step.items[1], collection, mark_core_remove, mark_core_remove_field)
            }
            return emit_predicate_callback_call(e, "kvist_filter", step.items[1], collection, mark_core_filter, mark_core_filter_field)
        }
        if thread_last && (head.text == "arr-map-indexed" || head.text == "arr/map-indexed" ||
                           head.text == "arr_map_indexed" || head.text == "arr__map_indexed") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects one function argument", surface_head), span = step.span}, false
            }
            f, err_f, ok_f := emit_expr(e, step.items[1])
            if !ok_f {
                return "", err_f, false
            }
            return emit_call_text("arr__map_indexed", []string{f, slice_all_expr_text(current)}), {}, true
        }
        is_arr_keep := head.text == "arr-keep" || head.text == "arr/keep"
        if thread_last && is_arr_keep {
            if len(step.items) != 2 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects one function argument", surface_head), span = step.span}, false
            }
            proc_text, capture_names, captured, err_capture, ok_capture := captured_unary_callback_proc(e, step.items[1], "keep", .Keep)
            if !ok_capture {
                return "", err_capture, false
            }
            if captured {
                mark_core_keep_capture(e, len(capture_names))
                return capture_helper_call_text("kvist_keep", proc_text, capture_names[:], slice_all_expr_text(current)), {}, true
            }
            f, err_f, ok_f := emit_expr(e, step.items[1])
            if !ok_f {
                return "", err_f, false
            }
            mark_core_keep(e)
            return emit_call_text("kvist_keep", []string{f, slice_all_expr_text(current)}), {}, true
        }
        if thread_last && (head.text == "arr-mapcat" || head.text == "arr/mapcat" ||
                           head.text == "arr_mapcat" || head.text == "arr__mapcat") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects one function argument", surface_head), span = step.span}, false
            }
            f, err_f, ok_f := emit_expr(e, step.items[1])
            if !ok_f {
                return "", err_f, false
            }
            return emit_call_text("arr__mapcat_impl", []string{f, slice_all_expr_text(current)}), {}, true
        }
        if thread_last && head.text == "concat" {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "concat thread step expects one collection argument", span = step.span}, false
            }
            rhs, err_rhs, ok_rhs := emit_expr(e, step.items[1])
            if !ok_rhs {
                return "", err_rhs, false
            }
            mark_core_concat(e)
            return emit_call_text("kvist_concat", []string{slice_all_expr_text(current), slice_all_expr_text(rhs)}), {}, true
        }
        if thread_last && (head.text == "arr-into" || head.text == "arr/into") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "into thread step expects one dynamic array type argument", span = step.span}, false
            }
            type_text, err_type, ok_type := parse_type_text(step.items[1])
            if !ok_type {
                return "", err_type, false
            }
            if !type_text_is_dynamic_array(type_text) {
                return "", Compile_Error{message = "into currently expects a dynamic array type", span = step.items[1].span}, false
            }
            mark_core_into(e)
            return emit_call_text("kvist_into", []string{type_text, slice_all_expr_text(current)}), {}, true
        }
        if thread_last && (head.text == "arr-shuffle" || head.text == "arr/shuffle") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "shuffle thread step expects one picker function argument", span = step.span}, false
            }
            pick, err_pick, ok_pick := emit_expr(e, step.items[1])
            if !ok_pick {
                return "", err_pick, false
            }
            call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/shuffle-impl")
            if !ok_resolve {
                call_name = "arr__shuffle_impl"
            }
            return emit_call_text(call_name, []string{pick, slice_all_expr_text(current)}), {}, true
        }
        if thread_last && (head.text == "arr-sort" || head.text == "arr/sort") {
            if len(step.items) != 1 {
                return "", Compile_Error{message = "sort thread step expects no arguments", span = step.span}, false
            }
            call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/sort-impl")
            if !ok_resolve {
                call_name = "arr__sort_impl"
            }
            return emit_call_text(call_name, []string{slice_all_expr_text(current)}), {}, true
        }
        if thread_last && (head.text == "arr-sort-by" || head.text == "arr/sort-by") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "sort-by thread step expects one key function argument", span = step.span}, false
            }
            return emit_sort_by_callback_call(e, step.items[1], slice_all_expr_text(current))
        }
        is_arr_partition := head.text == "arr-partition" || head.text == "arr/partition" ||
                            head.text == "arr_partition" || head.text == "arr__partition"
        is_arr_partition_all := head.text == "arr-partition-all" || head.text == "arr/partition-all" ||
                                head.text == "arr_partition_all" || head.text == "arr__partition_all"
        if thread_last && (head.text == "arr-split-at" || head.text == "arr/split-at" ||
                           head.text == "arr_split_at" || head.text == "arr__split_at") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects one count argument", surface_head), span = step.span}, false
            }
            count, err_count, ok_count := emit_expr(e, step.items[1])
            if !ok_count {
                return "", err_count, false
            }
            return emit_call_text("arr__split_at", []string{count, slice_all_expr_text(current)}), {}, true
        }
        if thread_last && (is_arr_partition || is_arr_partition_all) {
            if len(step.items) != 2 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects one count argument", surface_head), span = step.span}, false
            }
            count, err_count, ok_count := emit_expr(e, step.items[1])
            if !ok_count {
                return "", err_count, false
            }
            if is_arr_partition {
                return emit_call_text("arr__partition", []string{count, slice_all_expr_text(current)}), {}, true
            }
            return emit_call_text("arr__partition_all", []string{count, slice_all_expr_text(current)}), {}, true
        }
        if thread_last && (head.text == "arr-partition-by" || head.text == "arr/partition-by" ||
                           head.text == "arr_partition_by" || head.text == "arr__partition_by") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "partition-by thread step expects one key function argument", span = step.span}, false
            }
            return emit_partition_by_callback_call(e, step.items[1], slice_all_expr_text(current))
        }
        if thread_last && head.text == "map/zip" {
            if len(step.items) != 2 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects one key collection argument", surface_head), span = step.span}, false
            }
            keys, err_keys, ok_keys := emit_expr(e, step.items[1])
            if !ok_keys {
                return "", err_keys, false
            }
            return emit_call_text("map__zip", []string{slice_all_expr_text(keys), slice_all_expr_text(current)}), {}, true
        }
        if thread_last && (head.text == "arr-index-by" || head.text == "arr/index-by" ||
                           head.text == "arr_index_by" || head.text == "arr__index_by") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "index-by thread step expects one key function argument", span = step.span}, false
            }
            return emit_index_by_callback_call(e, step.items[1], slice_all_expr_text(current))
        }
        if thread_last && (head.text == "arr-group-by" || head.text == "arr/group-by" ||
                           head.text == "arr_group_by" || head.text == "arr__group_by") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "group-by thread step expects one key function argument", span = step.span}, false
            }
            return emit_group_by_callback_call(e, step.items[1], slice_all_expr_text(current))
        }
        if thread_last && (head.text == "arr-count-by" || head.text == "arr/count-by" ||
                           head.text == "arr_count_by" || head.text == "arr__count_by") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "count-by thread step expects one key function argument", span = step.span}, false
            }
            return emit_count_by_callback_call(e, step.items[1], slice_all_expr_text(current))
        }
        if thread_last && (head.text == "arr-sum-by" || head.text == "arr/sum-by" ||
                           head.text == "arr_sum_by" || head.text == "arr__sum_by") {
            if len(step.items) != 3 {
                return "", Compile_Error{message = "sum-by thread step expects key and value function arguments", span = step.span}, false
            }
            return emit_sum_by_callback_call(e, step.items[1], step.items[2], slice_all_expr_text(current))
        }
        if thread_last && (head.text == "arr-frequencies" || head.text == "arr/frequencies" ||
                           head.text == "arr_frequencies" || head.text == "arr__frequencies") {
            if len(step.items) != 1 {
                return "", Compile_Error{message = "frequencies thread step expects no arguments", span = step.span}, false
            }
            call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/frequencies-impl")
            if !ok_resolve {
                call_name = "arr__frequencies_impl"
            }
            return emit_call_text(call_name, []string{slice_all_expr_text(current)}), {}, true
        }
        if thread_last && (head.text == "arr-distinct" || head.text == "arr/distinct" ||
                           head.text == "arr_distinct" || head.text == "arr__distinct") {
            if len(step.items) != 1 {
                return "", Compile_Error{message = "distinct thread step expects no arguments", span = step.span}, false
            }
            call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/distinct-impl")
            if !ok_resolve {
                call_name = "arr__distinct_impl"
            }
            return emit_call_text(call_name, []string{slice_all_expr_text(current)}), {}, true
        }
        if thread_last && (head.text == "arr-distinct-by" || head.text == "arr/distinct-by") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "distinct-by thread step expects one key function argument", span = step.span}, false
            }
            return emit_distinct_by_callback_call(e, step.items[1], slice_all_expr_text(current))
        }
        if thread_last && source_package_surface_head(head.text) == "arr/reduce" {
            if len(step.items) != 3 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects function and initial value", surface_head), span = step.span}, false
            }
            f, err_f, ok_f := emit_expr(e, step.items[1])
            if !ok_f {
                return "", err_f, false
            }
            init, err_init, ok_init := emit_expr(e, step.items[2])
            if !ok_init {
                return "", err_init, false
            }
            mark_core_reduce(e)
            return emit_call_text("kvist_reduce", []string{f, init, slice_all_expr_text(current)}), {}, true
        }
        if thread_last && (head.text == "arr/take" || head.text == "arr-take" || head.text == "arr__take" ||
                           head.text == "arr/drop" || head.text == "arr-drop" || head.text == "arr__drop") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects one count argument", surface_head), span = step.span}, false
            }
            count, err_count, ok_count := emit_expr(e, step.items[1])
            if !ok_count {
                return "", err_count, false
            }
            if head.text == "arr/take" || head.text == "arr-take" || head.text == "arr__take" {
                return emit_call_text("arr__take", []string{count, slice_all_expr_text(current)}), {}, true
            } else {
                return emit_call_text("arr__drop", []string{count, slice_all_expr_text(current)}), {}, true
            }
        }
        if thread_last && (head.text == "arr/drop-last" || head.text == "arr-drop-last" || head.text == "arr__drop_last") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "drop-last thread step expects one count argument", span = step.span}, false
            }
            count, err_count, ok_count := emit_expr(e, step.items[1])
            if !ok_count {
                return "", err_count, false
            }
            return emit_call_text("arr__drop_last", []string{count, slice_all_expr_text(current)}), {}, true
        }
        if thread_last && (head.text == "arr/butlast" || head.text == "arr-butlast" || head.text == "arr__butlast") {
            if len(step.items) != 1 {
                return "", Compile_Error{message = "butlast thread step expects no arguments", span = step.span}, false
            }
            return emit_call_text("arr__butlast", []string{slice_all_expr_text(current)}), {}, true
        }
        is_arr_take_while := head.text == "arr-take-while" || head.text == "arr/take-while"
        is_arr_drop_while := head.text == "arr-drop-while" || head.text == "arr/drop-while"
        is_arr_find := head.text == "arr-find" || head.text == "arr/find"
        is_arr_some := head.text == "arr-some?" || head.text == "arr/some?"
        is_arr_every := head.text == "arr-every?" || head.text == "arr/every?"
        if thread_last && (is_arr_take_while || is_arr_drop_while || is_arr_find || is_arr_some || is_arr_every) {
            if len(step.items) != 2 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects one predicate argument", surface_head), span = step.span}, false
            }
            collection := slice_all_expr_text(current)
            if field, ok_field := field_from_selector(step.items[1]); ok_field {
                if is_arr_take_while {
                    mark_core_take_while_field(e, field)
                    return emit_call_text(fmt.tprintf("kvist_take_while_field_%s", field), []string{collection}), {}, true
                }
                if is_arr_drop_while {
                    mark_core_drop_while_field(e, field)
                    return emit_call_text(fmt.tprintf("kvist_drop_while_field_%s", field), []string{collection}), {}, true
                }
                if is_arr_find {
                    mark_core_find_field(e, field)
                    return emit_call_text(fmt.tprintf("kvist_find_field_%s", field), []string{collection}), {}, true
                }
                if is_arr_some {
                    mark_core_some_field(e, field)
                    return emit_call_text(fmt.tprintf("kvist_some_p_field_%s", field), []string{collection}), {}, true
                }
                mark_core_every_field(e, field)
                return emit_call_text(fmt.tprintf("kvist_every_p_field_%s", field), []string{collection}), {}, true
            }
            pred, err_pred, ok_pred := emit_expr(e, step.items[1])
            if !ok_pred {
                return "", err_pred, false
            }
            if is_arr_take_while {
                call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/take-while-impl")
                if !ok_resolve {
                    call_name = "arr__take_while_impl"
                }
                return emit_call_text(call_name, []string{pred, collection}), {}, true
            }
            if is_arr_drop_while {
                call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/drop-while-impl")
                if !ok_resolve {
                    call_name = "arr__drop_while_impl"
                }
                return emit_call_text(call_name, []string{pred, collection}), {}, true
            }
            if is_arr_find {
                call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/find-impl")
                if !ok_resolve {
                    call_name = "arr__find_impl"
                }
                return emit_call_text(call_name, []string{pred, collection}), {}, true
            }
            if is_arr_some {
                call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/some-impl")
                if !ok_resolve {
                    call_name = "arr__some_impl"
                }
                return emit_call_text(call_name, []string{pred, collection}), {}, true
            }
            call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/every-impl")
            if !ok_resolve {
                call_name = "arr__every_impl"
            }
            return emit_call_text(call_name, []string{pred, collection}), {}, true
        }
        if thread_last && (head.text == "core/slice" || head.text == "arr/slice") {
            if len(step.items) > 3 {
                return "", Compile_Error{message = "slice thread step expects optional start and end", span = step.span}, false
            }
            if len(step.items) == 1 {
                return slice_all_expr_text(current), {}, true
            }
            start, err_start, ok_start := emit_expr(e, step.items[1])
            if !ok_start {
                return "", err_start, false
            }
            if len(step.items) == 2 {
                return fmt.tprintf("(%s)[%s:]", current, start), {}, true
            }
            end, err_end, ok_end := emit_expr(e, step.items[2])
            if !ok_end {
                return "", err_end, false
            }
            return fmt.tprintf("(%s)[%s:%s]", current, start, end), {}, true
        }
        if thread_last && (head.text == "arr/first" ||
                           head.text == "arr/second" || head.text == "arr/last" ||
                           head.text == "arr/rest" ||
                           head.text == "empty?" || head.text == "count") {
            if len(step.items) != 1 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects no arguments", surface_head), span = step.span}, false
            }
            collection := slice_all_expr_text(current)
            if head.text == "count" {
                return fmt.tprintf("len(%s)", collection), {}, true
            }
            if head.text == "arr/first" {
                return fmt.tprintf("(%s)[0]", collection), {}, true
            }
            if head.text == "arr/second" {
                return fmt.tprintf("(%s)[1]", collection), {}, true
            }
            if head.text == "arr/last" {
                return fmt.tprintf("(%s)[len(%s)-1]", collection, collection), {}, true
            }
            if head.text == "empty?" {
                return fmt.tprintf("len(%s) == 0", collection), {}, true
            }
            return fmt.tprintf("(%s)[1:]", collection), {}, true
        }
        if thread_last && head.text == "arr/nth" {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "nth thread step expects one index argument", span = step.span}, false
            }
            index, err_index, ok_index := emit_expr(e, step.items[1])
            if !ok_index {
                return "", err_index, false
            }
            return fmt.tprintf("(%s)[%s]", slice_all_expr_text(current), index), {}, true
        }
        args: [dynamic]string
        if !thread_last {
            append(&args, current)
        }
        for arg in step.items[1:] {
            arg_text, err_arg, ok_arg := emit_expr(e, arg)
            if !ok_arg {
                return "", err_arg, false
            }
            append(&args, arg_text)
        }
        if thread_last {
            append(&args, current)
        }
        return emit_call_text(map_name(head.text), args[:]), {}, true
    case:
        return "", Compile_Error{message = "unsupported thread step", span = step.span}, false
    }
    return "", Compile_Error{message = "unsupported thread step", span = step.span}, false
}

thread_temp_name :: proc(e: ^Emitter) -> string {
    e.temp_counter += 1
    return fmt.tprintf("kvist_thread_%d", e.temp_counter)
}

eval_temp_name :: proc(e: ^Emitter) -> string {
    e.temp_counter += 1
    return fmt.tprintf("kvist_eval_%d", e.temp_counter)
}

is_tap_thread_step :: proc(step: CST_Form) -> bool {
    return step.kind == .List && len(step.items) > 0 &&
           step.items[0].kind == .Symbol && step.items[0].text == "tap>"
}

is_thread_form_head :: proc(head: string, thread_last: bool) -> bool {
    if thread_last {
        return head == "core-thread-last"
    }
    return head == "core-thread-first"
}

thread_surface_name :: proc(thread_last: bool) -> string {
    if thread_last {
        return "core.->>"
    }
    return "core.->"
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
    if sep <= 0 {
        return head_name
    }
    pkg := head_name[:sep]
    member := head_name[sep+2:]
    if source_package_prefix_text(pkg) {
        return fmt.tprintf("%s/%s", pkg, member)
    }
    return head_name
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

thread_owned_result_head :: proc(head_name: string) -> bool {
    head := source_package_surface_head(head_name)
    switch head {
    case "arr/map", "arr-map",
         "arr/filter", "arr-filter",
         "arr/remove", "arr-remove",
         "arr/map-indexed", "arr-map-indexed", "arr_map_indexed", "arr__map_indexed",
         "arr/keep", "arr-keep",
         "arr/mapcat", "arr-mapcat", "arr_mapcat", "arr__mapcat",
         "concat",
         "arr/into", "arr-into",
         "arr/interpose",
         "arr/interleave",
         "arr/reverse",
         "arr/shuffle", "arr-shuffle", "arr__shuffle",
         "arr/sort", "arr-sort", "arr__sort",
         "arr/sort-by", "arr-sort-by",
         "map/zip",
         "arr/index-by", "arr-index-by",
         "arr/group-by", "arr-group-by",
         "arr/count-by", "arr-count-by",
         "arr/sum-by", "arr-sum-by",
         "arr/frequencies", "arr-frequencies",
         "map/keys",
         "map/vals",
         "set/union",
         "set/intersection",
         "set/difference",
         "set/add",
         "set/remove",
         "arr/distinct", "arr-distinct",
         "arr/distinct-by", "arr-distinct-by",
         "arr/cycle",
         "str/split", "str-split",
         "str/join", "str-join",
         "str/replace", "str-replace",
         "str/lower",
         "str/upper",
         "arr/take-nth":
        return true
    }
    return false
}

thread_owned_borrowing_result_head :: proc(head_name: string) -> bool {
    head := source_package_surface_head(head_name)
    switch head {
    case "arr/partition", "arr-partition",
         "arr/partition-all", "arr-partition-all",
         "arr/partition-by", "arr-partition-by":
        return true
    }
    return false
}

thread_view_result_head :: proc(head_name: string) -> bool {
    head := source_package_surface_head(head_name)
    switch head {
    case "arr/take", "arr-take", "arr__take",
         "arr/drop", "arr-drop", "arr__drop",
         "arr/drop-last", "arr-drop-last", "arr__drop_last",
         "arr/butlast", "arr-butlast", "arr__butlast",
         "arr/take-while", "arr-take-while",
         "arr/drop-while", "arr-drop-while",
         "core/slice",
         "arr/slice",
         "arr/rest",
         "arr/split-at", "arr-split-at":
        return true
    }
    return false
}

thread_scalar_result_head :: proc(head_name: string) -> bool {
    head := source_package_surface_head(head_name)
    switch head {
    case "arr/find", "arr-find",
         "arr/reduce",
         "arr/some?", "arr-some?",
         "arr/every?", "arr-every?",
         "arr/first",
         "arr/second",
         "arr/last",
         "arr/nth",
         "str/starts-with?",
         "str/ends-with?",
         "str/index-of",
         "str/last-index-of",
         "set/subset?",
         "set/superset?",
         "set/disjoint?",
         "core/empty?",
         "core/count":
        return true
    }
    return false
}

thread_step_result_kind :: proc(e: ^Emitter, step: CST_Form, thread_last: bool) -> Thread_Result_Kind {
    #partial switch step.kind {
    case .Symbol:
        if _, ok_field := field_from_selector(step); ok_field {
            return .Scalar
        }
        if thread_last && step.text == "slice" {
            return .View
        }
        return .Unknown
    case .List:
        if len(step.items) == 0 {
            return .Unknown
        }
        head := step.items[0]
        if _, ok_field := field_from_selector(head); ok_field {
            return .Scalar
        }
        if head.kind != .Symbol {
            return .Unknown
        }
        head_name := head.text
        if head_name == "map/merge" {
            return .Owned
        }
        if thread_last && thread_owned_result_head(head_name) {
            return .Owned
        }
        if thread_last && thread_owned_borrowing_result_head(head_name) {
            return .Owned_Borrowing
        }
        if thread_last && thread_view_result_head(head_name) {
            return .View
        }
        if thread_last && thread_scalar_result_head(head_name) {
            return .Scalar
        }
        if e != nil {
            proc_name := map_name(head.text)
            if proc_decl, ok_proc := find_proc_decl(e, proc_name); ok_proc &&
               return_spec_is_owned_result(proc_decl.returns) {
                return .Owned
            }
        }
    }
    return .Unknown
}

thread_steps_after_include_non_tap :: proc(steps: []CST_Form, idx: int) -> bool {
    for step in steps[idx+1:] {
        if !is_tap_thread_step(step) {
            return true
        }
    }
    return false
}

is_thread_form :: proc(form: CST_Form, thread_last: bool) -> bool {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    return is_thread_form_head(form.items[0].text, thread_last)
}

thread_form_has_allocating_intermediate :: proc(e: ^Emitter, form: CST_Form, thread_last: bool) -> bool {
    if !is_thread_form(form, thread_last) || len(form.items) < 3 {
        return false
    }
    steps := form.items[2:]
    current_kind := Thread_Result_Kind.Unknown
    for step, idx in steps {
        kind := thread_step_result_kind(e, step, thread_last)
        if is_tap_thread_step(step) {
            kind = current_kind
        }
        if (kind == .Owned || kind == .Owned_Borrowing) && thread_steps_after_include_non_tap(steps, idx) {
            return true
        }
        current_kind = kind
    }
    return false
}

thread_form_final_kind :: proc(e: ^Emitter, form: CST_Form, thread_last: bool) -> Thread_Result_Kind {
    if !is_thread_form(form, thread_last) || len(form.items) < 3 {
        return .Unknown
    }
    current_kind := Thread_Result_Kind.Unknown
    for step in form.items[2:] {
        if is_tap_thread_step(step) {
            continue
        }
        current_kind = thread_step_result_kind(e, step, thread_last)
    }
    return current_kind
}

thread_form_final_view_borrows_owned_intermediate :: proc(e: ^Emitter, form: CST_Form, thread_last: bool) -> bool {
    if !is_thread_form(form, thread_last) || len(form.items) < 3 {
        return false
    }
    final_kind := thread_form_final_kind(e, form, thread_last)
    if final_kind != .View && final_kind != .Owned_Borrowing {
        return false
    }
    for step in form.items[2:len(form.items)-1] {
        if is_tap_thread_step(step) {
            continue
        }
        kind := thread_step_result_kind(e, step, thread_last)
        if kind == .Owned || kind == .Owned_Borrowing {
            return true
        }
    }
    return false
}

thread_return_error :: proc(e: ^Emitter, form: CST_Form) -> (Compile_Error, bool) {
    if thread_form_has_allocating_intermediate(e, form, true) || thread_form_has_allocating_intermediate(e, form, false) {
        return Compile_Error{
            message = "threaded return has an allocating intermediate; bind the pipeline with let so Kvist can emit cleanup",
            span = form.span,
        }, true
    }
    return {}, false
}

owned_result_head :: proc(name: string) -> bool {
    normalized := source_package_surface_head(name)
    if thread_owned_result_head(normalized) || thread_owned_borrowing_result_head(normalized) {
        return true
    }
    switch normalized {
    case "map/merge",
         "arr/range", "arr/repeat", "arr/repeatedly", "arr/iterate",
         "io/read":
        return true
    }
    return false
}

form_is_owned_result :: proc(form: CST_Form) -> bool {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    if form.items[0].text == "tap>" && (len(form.items) == 2 || len(form.items) == 3) {
        return form_is_owned_result(form.items[len(form.items)-1])
    }
    if owned_result_head(form.items[0].text) {
        return true
    }
    if is_thread_form(form, true) || is_thread_form(form, false) {
        kind := thread_form_final_kind(nil, form, is_thread_form_head(form.items[0].text, true))
        return kind == .Owned || kind == .Owned_Borrowing
    }
    return false
}

owned_result_usage_error :: proc(form: CST_Form, allow_root_owned: bool) -> (Compile_Error, bool) {
    if form.kind == .List && len(form.items) > 0 &&
       form.items[0].kind == .Symbol && form.items[0].text == "tap>" &&
       (len(form.items) == 2 || len(form.items) == 3) &&
       form_is_owned_result(form) {
        if !allow_root_owned {
            return Compile_Error{
                message = nested_owned_result_error_message(form.items[len(form.items)-1]),
                span = form.span,
            }, true
        }
        return owned_result_usage_error(form.items[len(form.items)-1], true)
    }

    if form_is_owned_result(form) {
        if !allow_root_owned {
            return Compile_Error{
                message = nested_owned_result_error_message(form),
                span = form.span,
            }, true
        }
        if (is_thread_form(form, true) && thread_form_has_allocating_intermediate(nil, form, true)) ||
           (is_thread_form(form, false) && thread_form_has_allocating_intermediate(nil, form, false)) {
            return Compile_Error{
                message = "threaded expression has an allocating intermediate; bind the pipeline with let so Kvist can emit cleanup",
                span = form.span,
            }, true
        }
    }

    #partial switch form.kind {
    case .List, .Vector, .Brace, .Set:
        start := 0
        if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
            head := form.items[0].text
            if head == "make" {
                start = 2
            } else if allow_root_owned && form_is_owned_result(form) {
                start = 1
            }
        }
        if start > len(form.items) {
            start = len(form.items)
        }
        for item in form.items[start:] {
            err_item, bad_item := owned_result_usage_error(item, false)
            if bad_item {
                return err_item, true
            }
        }
    }
    return {}, false
}

emit_expr_for_expected_type :: proc(e: ^Emitter, form: CST_Form, expected_type := "") -> (string, Compile_Error, bool) {
    if expected_type != "" && (form.kind == .Vector || form.kind == .Brace || form.kind == .Set) {
        return emit_inferred_literal(e, form, expected_type)
    }
    return emit_expr(e, form)
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

let_return_error :: proc(bindings: []Binding, body: []CST_Form) -> (Compile_Error, bool) {
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
        if thread_form_final_view_borrows_owned_intermediate(nil, binding.value, true) ||
           thread_form_final_view_borrows_owned_intermediate(nil, binding.value, false) {
            return Compile_Error{
                message = "cannot return a threaded slice view that borrows from an owned intermediate; return an owned result or keep the pipeline local",
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

    #partial switch form.kind {
    case .Symbol:
        return form.span, true
    case .Vector, .Brace, .Set:
        return form.span, true
    case .List:
        if len(form.items) == 0 || form.items[0].kind != .Symbol {
            if !return_spec_is_non_owned_scalar(returns) {
                return form.span, true
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
        case "if", "when":
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
        case "cond":
            if len(form.items) >= 3 {
                i := 2
                for i < len(form.items) {
                    if span, ok := form_escape_deferred_binding_span_names(form.items[i], names, returns); ok {
                        return span, true
                    }
                    i += 2
                }
            }
            return {}, false
        case "switch", "core-switch":
            return switch_escape_deferred_binding_span_names(form, names, returns)
        case "with-allocator", "with-temp-allocator":
            if len(form.items) >= 3 {
                return body_escape_deferred_binding_span_names(form.items[2:], names, returns)
            }
            return {}, false
        case:
            if !return_spec_is_non_owned_scalar(returns) {
                return form.span, true
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

body_escape_owned_temp_result_span_names :: proc(forms: []CST_Form, names: []string, returns: Return_Spec) -> (Span, bool) {
    scoped_names := make([dynamic]string, len(names))
    defer delete(scoped_names)
    copy(scoped_names[:], names)

    for form in forms {
        if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol && form.items[0].text == "return" {
            if span, ok := form_escape_owned_temp_result_span_names(form, scoped_names[:], returns); ok {
                return span, true
            }
        }
        if assigned_name, ok_assigned := set_bang_assigned_name(form); ok_assigned &&
           form_may_escape_owned_temp_result_names(form.items[2], scoped_names[:], returns) {
            binding_names_append_unique(&scoped_names, assigned_name)
        }
    }
    if returns.kind != .None && len(forms) > 0 {
        return form_escape_owned_temp_result_span_names(forms[len(forms)-1], scoped_names[:], returns)
    }
    return {}, false
}

body_may_escape_owned_temp_result_names :: proc(forms: []CST_Form, names: []string, returns: Return_Spec) -> bool {
    _, ok := body_escape_owned_temp_result_span_names(forms, names, returns)
    return ok
}

body_may_escape_owned_temp_result :: proc(forms: []CST_Form, returns: Return_Spec) -> bool {
    return body_may_escape_owned_temp_result_names(forms, nil, returns)
}

switch_escape_owned_temp_result_span_names :: proc(form: CST_Form, names: []string, returns: Return_Spec) -> (Span, bool) {
    if len(form.items) < 4 {
        return {}, false
    }
    i := 2
    for i < len(form.items) {
        if i+1 >= len(form.items) {
            return {}, false
        }
        if span, ok := form_escape_owned_temp_result_span_names(form.items[i+1], names, returns); ok {
            return span, true
        }
        i += 2
    }
    return {}, false
}

switch_may_escape_owned_temp_result_names :: proc(form: CST_Form, names: []string, returns: Return_Spec) -> bool {
    _, ok := switch_escape_owned_temp_result_span_names(form, names, returns)
    return ok
}

switch_may_escape_owned_temp_result :: proc(form: CST_Form, returns: Return_Spec) -> bool {
    return switch_may_escape_owned_temp_result_names(form, nil, returns)
}

form_escape_owned_temp_result_span_names :: proc(form: CST_Form, names: []string, returns: Return_Spec) -> (Span, bool) {
    if form_is_owned_temp_escape_result(form) {
        return form.span, true
    }

    #partial switch form.kind {
    case .Symbol:
        if binding_names_contain(names, map_name(form.text)) {
            return form.span, true
        }
        return {}, false
    case .Vector, .Brace, .Set:
        for item in form.items {
            if span, ok := form_escape_owned_temp_result_span_names(item, names, returns); ok {
                return span, true
            }
        }
        return {}, false
    case .List:
        if len(form.items) == 0 || form.items[0].kind != .Symbol {
            if !return_spec_is_non_owned_scalar(returns) {
                return form.span, true
            }
            return {}, false
        }
        switch form.items[0].text {
        case "return":
            for returned in form.items[1:] {
                if span, ok := form_escape_owned_temp_result_span_names(returned, names, returns); ok {
                    return span, true
                }
            }
            return {}, false
        case "let":
            bindings, _, ok_bind := parse_let_bindings(form.items[1])
            if !ok_bind {
                if len(form.items) >= 3 {
                    return body_escape_owned_temp_result_span_names(form.items[2:], names, returns)
                }
                return {}, false
            }
            scoped_names := make([dynamic]string, len(names))
            defer delete(scoped_names)
            copy(scoped_names[:], names)
            for binding in bindings {
                if binding.name != "" && form_may_escape_owned_temp_result_names(binding.value, scoped_names[:], returns) {
                    binding_names_append_unique(&scoped_names, binding.name)
                }
            }
            if len(form.items) >= 3 {
                return body_escape_owned_temp_result_span_names(form.items[2:], scoped_names[:], returns)
            }
            return {}, false
        case "do":
            if len(form.items) >= 2 {
                return body_escape_owned_temp_result_span_names(form.items[1:], names, returns)
            }
            return {}, false
        case "if", "when":
            if len(form.items) >= 3 {
                if span, ok := form_escape_owned_temp_result_span_names(form.items[2], names, returns); ok {
                    return span, true
                }
            }
            if len(form.items) >= 4 {
                if span, ok := form_escape_owned_temp_result_span_names(form.items[3], names, returns); ok {
                    return span, true
                }
            }
            return {}, false
        case "cond":
            if len(form.items) >= 3 {
                i := 2
                for i < len(form.items) {
                    if span, ok := form_escape_owned_temp_result_span_names(form.items[i], names, returns); ok {
                        return span, true
                    }
                    i += 2
                }
            }
            return {}, false
        case "switch", "core-switch":
            return switch_escape_owned_temp_result_span_names(form, names, returns)
        case "with-allocator", "with-temp-allocator":
            if len(form.items) >= 3 {
                return body_escape_owned_temp_result_span_names(form.items[2:], names, returns)
            }
            return {}, false
        case:
            if !return_spec_is_non_owned_scalar(returns) {
                return form.span, true
            }
            return {}, false
        }
    }
    return {}, false
}

form_may_escape_owned_temp_result_names :: proc(form: CST_Form, names: []string, returns: Return_Spec) -> bool {
    _, ok := form_escape_owned_temp_result_span_names(form, names, returns)
    return ok
}

form_may_escape_owned_temp_result :: proc(form: CST_Form, returns: Return_Spec) -> bool {
    return form_may_escape_owned_temp_result_names(form, nil, returns)
}

let_defer_return_error :: proc(bindings: []Binding, body: []CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    for binding in bindings {
        if !binding.deferred_delete {
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
            return Compile_Error{
                message = "defer-marked binding cannot be returned; remove defer or transfer ownership explicitly",
                span = err_span,
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
            strings.write_string(&line_builder, name)
        }
        fmt.sbprintf(&line_builder, " := %s", value)
        emit_prefixed_expr_mapped(e, "", strings.clone(strings.to_string(line_builder)), binding.value.span)
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
        return binding.pattern[0], true
    }
    return "", false
}

named_returns_match_binding_pattern :: proc(returns: Return_Spec, pattern: []string) -> bool {
    if returns.kind != .Named || len(returns.named) != len(pattern) {
        return false
    }
    for item, idx in pattern {
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
                message = "or-return currently requires proc named returns matching the binding names exactly",
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

emit_thread_binding_assignment :: proc(e: ^Emitter, binding: Binding, thread_last: bool) -> (Compile_Error, bool) {
    form := binding.value
    if len(form.items) < 3 {
        return Compile_Error{message = fmt.tprintf("%s expects an initial expression and at least one step", form.items[0].text), span = form.span}, false
    }

    current, err_current, ok_current := emit_expr(e, form.items[1])
    if !ok_current {
        return err_current, false
    }
    current_ty := ""
    if ty, ok_ty := obvious_form_type(e, form.items[1]); ok_ty {
        current_ty = ty
    }

    steps := form.items[2:]
    current_kind := Thread_Result_Kind.Unknown
    for step, idx in steps {
        next, err_step, ok_step := emit_thread_step(e, current, step, thread_last, current_ty)
        if !ok_step {
            return err_step, false
        }

        kind := thread_step_result_kind(e, step, thread_last)
        tap_step := is_tap_thread_step(step)
        if tap_step {
            kind = current_kind
        }
        if !tap_step && (kind == .Owned || kind == .Owned_Borrowing) &&
           thread_steps_after_include_non_tap(steps, idx) {
            temp := thread_temp_name(e)
            emit_prefixed_expr(e, fmt.tprintf("%s := ", temp), next)
            emit_line(e, fmt.tprintf("defer delete(%s)", temp))
            current = temp
        } else {
            current = next
        }
        if !thread_step_is_shallow_value_update(step, thread_last) {
            current_ty = ""
        }
        current_kind = kind
    }

    emit_binding_assignment(e, binding, current)
    return {}, true
}

emit_thread_expr :: proc(e: ^Emitter, form: CST_Form, thread_last: bool = false) -> (string, Compile_Error, bool) {
    if len(form.items) < 3 {
        return "", Compile_Error{message = fmt.tprintf("%s expects an initial expression and at least one step", thread_surface_name(thread_last)), span = form.span}, false
    }

    current, err_current, ok_current := emit_expr(e, form.items[1])
    if !ok_current {
        return "", err_current, false
    }
    current_ty := ""
    if ty, ok_ty := obvious_form_type(e, form.items[1]); ok_ty {
        current_ty = ty
    }

    for step in form.items[2:] {
        next, err_step, ok_step := emit_thread_step(e, current, step, thread_last, current_ty)
        if !ok_step {
            return "", err_step, false
        }
        current = next
        if !thread_step_is_shallow_value_update(step, thread_last) {
            current_ty = ""
        }
    }
    return current, {}, true
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

type_text_is_slice_or_fixed_array :: proc(text: string) -> bool {
    return len(text) >= 2 && text[0] == '[' && !type_text_is_dynamic_array(text) ||
           type_text_is_soa(text) && !type_text_is_dynamic_soa(text)
}

type_text_is_map :: proc(text: string) -> bool {
    return len(text) >= 4 && text[:4] == "map["
}

type_text_is_set :: proc(text: string) -> bool {
    return len(text) >= 4 && text[:4] == "set["
}

type_text_is_owned_result :: proc(text: string) -> bool {
    return type_text_is_dynamic_array(text) || type_text_is_dynamic_soa(text) || type_text_is_map(text) || type_text_is_set(text)
}

return_spec_is_owned_result :: proc(returns: Return_Spec) -> bool {
    return returns.kind == .Single && type_text_is_owned_result(returns.single_ty)
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
    case .String:
        return "string", Compile_Error{}, true
    case .Bool:
        return "bool", Compile_Error{}, true
    case .Keyword:
        return "", Compile_Error{message = "keywords are syntax markers, not values; use a string, enum value, field label, or field selector", span = form.span}, false
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

obvious_form_type :: proc(e: ^Emitter, form: CST_Form) -> (string, bool) {
    if form.kind == .Symbol {
        return lookup_local_type(e, map_name(form.text))
    }
    if form.kind == .Number || form.kind == .String || form.kind == .Bool {
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
        head_name := map_name(form.items[0].text)
        surface_head := source_package_surface_head(form.items[0].text)
        if (form.items[0].text == "assoc" || surface_head == "core/assoc" || form.items[0].text == "core-assoc" ||
            form.items[0].text == "update" || surface_head == "core/update" || form.items[0].text == "core-update") &&
           len(form.items) >= 2 {
            return shallow_update_return_type(e, form)
        }
        if proc_decl, ok := find_proc_decl(e, head_name); ok && proc_decl.returns.kind == .Single {
            return proc_decl.returns.single_ty, true
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
    values, err_values, ok_values := emit_vector_item_texts(e, form)
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
            key_ty, value_ty, ok_map := map_type_parts(expected_type)
            if !ok_map || value_ty != "struct{}" {
                return "", Compile_Error{message = fmt.tprintf("set literal does not match expected type %s", expected_type), span = form.span}, false
            }
            elem_ty = key_ty
        } else {
            inferred, err_inferred, ok_inferred := infer_literal_value_type(e, form)
            if !ok_inferred {
                return "", err_inferred, false
            }
            key_ty, value_ty, ok_map := map_type_parts(inferred)
            if !ok_map || value_ty != "struct{}" {
                return "", Compile_Error{message = "internal error inferring set literal type", span = form.span}, false
            }
            elem_ty = key_ty
        }
        mark_dynamic_literals(e)
        return emit_set_literal(e, elem_ty, form)
    }
    return "", Compile_Error{message = "internal error: expected literal form", span = form.span}, false
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
        return lookup_local_type(e, map_name(binding.value.text))
    }
    if binding.value.kind == .Number || binding.value.kind == .String || binding.value.kind == .Bool {
        if ty, _, ok := infer_literal_value_type(e, binding.value); ok {
            return ty, true
        }
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
        surface_head := source_package_surface_head(head)
        if (head == "assoc" || surface_head == "core/assoc" || head == "core-assoc" ||
            head == "update" || surface_head == "core/update" || head == "core-update") &&
           len(binding.value.items) >= 2 {
            return shallow_update_return_type(e, binding.value)
        }
        head_name := map_name(binding.value.items[0].text)
        if proc_decl, ok := find_proc_decl(e, head_name); ok && proc_decl.returns.kind == .Single {
            return proc_decl.returns.single_ty, true
        }
    }
    if binding.value.kind == .Vector || binding.value.kind == .Brace || binding.value.kind == .Set {
        if ty, _, ok := infer_literal_value_type(e, binding.value); ok {
            return ty, true
        }
    }
    return "", false
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
    body := let_form.items[2:]
    if len(body) == 0 {
        return Compile_Error{message = "let expects bindings and body", span = let_form.span}, false
    }

    for inner in inner_bindings {
        if binding_value_is_let(inner) {
            err_inner, ok_inner := emit_let_value_binding_assignment(e, inner)
            if !ok_inner {
                return err_inner, false
            }
        } else if is_thread_form(inner.value, true) {
            err_thread, ok_thread := emit_thread_binding_assignment(e, inner, true)
            if !ok_thread {
                return err_thread, false
            }
        } else if is_thread_form(inner.value, false) {
            err_thread, ok_thread := emit_thread_binding_assignment(e, inner, false)
            if !ok_thread {
                return err_thread, false
            }
        } else {
            err_owned, bad_owned := owned_result_usage_error(inner.value, true)
            if bad_owned {
                return err_owned, false
            }
            value, err_value, ok_value := emit_expr_for_expected_type(e, inner.value, inner.ty)
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
            delete_name, ok_delete_name := binding_delete_target_name(inner)
            if !ok_delete_name {
                return Compile_Error{message = "defer binding marker is only supported on delete-able local bindings", span = inner.value.span}, false
            }
            emit_line(e, fmt.tprintf("defer delete(%s)", delete_name))
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
        strings.write_string(&line_builder, name)
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
    if form.items[0].kind == .Symbol {
        switch form.items[0].text {
        case "arr/empty", "arr-empty", "arr/dynamic", "arr-dynamic", "map/empty", "map-empty", "map/of", "map-of", "set/empty", "set-empty", "set/of", "set-of":
            return true
        }
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

form_produces_owned_value :: proc(form: CST_Form) -> bool {
    return form_is_owned_result(form) || form_is_owned_allocation_result(form) || form_is_owned_constructor_result(form)
}

binding_value_produces_owned_value :: proc(binding: Binding) -> bool {
    if binding.is_typed &&
       (binding.value.kind == .Vector || binding.value.kind == .Brace || binding.value.kind == .Set) {
        return type_text_is_owned_result(binding.ty)
    }
    return form_produces_owned_value(binding.value)
}

form_is_owned_temp_escape_result :: proc(form: CST_Form) -> bool {
    return form_produces_owned_value(form)
}

with_temp_allocator_escape_error :: proc(body: []CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    if err_span, ok := body_escape_owned_temp_result_span_names(body, nil, returns); ok {
        return Compile_Error{
            message = "owned value cannot escape with-temp-allocator; allocate it outside the temp scope or copy it before returning",
            span = err_span,
        }, true
    }
    return {}, false
}

loop_collection_needs_temp_binding :: proc(form: CST_Form) -> bool {
    return form_is_owned_result(form) || form_is_owned_allocation_result(form) || form_is_owned_constructor_result(form)
}

Owned_Local :: struct {
    name: string,
    span: Span,
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

owned_locals_remove_last :: proc(live: ^[dynamic]Owned_Local, name: string) -> bool {
    idx := owned_locals_find_last(live[:], name)
    if idx < 0 {
        return false
    }
    ordered_remove(live, idx)
    return true
}

form_head_symbol_text :: proc(form: CST_Form) -> (string, bool) {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return "", false
    }
    return form.items[0].text, true
}

form_is_delete_of_name :: proc(form: CST_Form, name: string) -> bool {
    head, ok := form_head_symbol_text(form)
    if !ok {
        return false
    }
    if head == "delete" && len(form.items) == 2 && form.items[1].kind == .Symbol {
        return map_name(form.items[1].text) == name
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

    if ok && head == "cond" {
        if len(form.items) < 4 || len(form.items)%2 != 0 {
            return false
        }
        i := 2
        any_branch := false
        for i < len(form.items) {
            any_branch = true
            if !form_transfers_owned_name(form.items[i], name, can_transfer_final) {
                return false
            }
            i += 2
        }
        return any_branch
    }

    if ok && head == "switch" {
        return switch_transfers_owned_name(form, name, can_transfer_final)
    }

    if can_transfer_final && form.kind == .Symbol && map_name(form.text) == name {
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

analyze_owned_scope_body :: proc(e: ^Emitter, forms: []CST_Form, can_transfer_final: bool, live: ^[dynamic]Owned_Local) {
    for form, idx in forms {
        final_in_scope := idx == len(forms)-1

        if form.kind == .Symbol && final_in_scope && can_transfer_final {
            _ = owned_locals_remove_last(live, map_name(form.text))
            continue
        }

        head, ok := form_head_symbol_text(form)
        if !ok {
            if form_produces_owned_value(form) && !(final_in_scope && can_transfer_final) {
                emit_warning(e, discarded_owned_warning_message(form), form.span)
            }
            continue
        }

        switch head {
        case "return":
            for item in form.items[1:] {
                if item.kind == .Symbol {
                    _ = owned_locals_remove_last(live, map_name(item.text))
                }
            }
        case "set!":
            if len(form.items) == 3 && form.items[1].kind == .Symbol {
                name := map_name(form.items[1].text)
                if owned_locals_find_last(live[:], name) >= 0 {
                    emit_warning(e, fmt.tprintf("owned local %s is overwritten before cleanup; delete it or return it before set!", name), form.items[1].span)
                    _ = owned_locals_remove_last(live, name)
                }
                if form_produces_owned_value(form.items[2]) {
                    append(live, Owned_Local{name = name, span = form.items[1].span})
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
            for binding in bindings {
                delete_name, has_delete_name := binding_delete_target_name(binding)
                if binding.is_destructure || (!has_delete_name && binding.name == "") {
                    continue
                }
                if binding_value_produces_owned_value(binding) || binding.deferred_delete {
                    owned_name := binding.name
                    if owned_name == "" {
                        owned_name = delete_name
                    }
                    append(live, Owned_Local{name = owned_name, span = form.items[0].span})
                }
            }
            analyze_owned_scope_body(e, form.items[2:], final_in_scope && can_transfer_final, live)
            for i := start; i < len(live); i += 1 {
                skip_warning := false
                for binding in bindings {
                    delete_name, ok_delete_name := binding_delete_target_name(binding)
                    if ok_delete_name && delete_name == live[i].name && binding.deferred_delete {
                        skip_warning = true
                        break
                    }
                }
                if !skip_warning && !body_deletes_or_returns_name(form.items[2:], live[i].name, final_in_scope && can_transfer_final) {
                    emit_warning(e, fmt.tprintf("owned local %s is never deleted or returned; add (defer (delete %s)) or return it", live[i].name, live[i].name), live[i].span)
                }
            }
            resize(live, start)
        case "do":
            analyze_owned_scope_body(e, form.items[1:], final_in_scope && can_transfer_final, live)
        case:
            if form_produces_owned_value(form) && !(final_in_scope && can_transfer_final) {
                emit_warning(e, discarded_owned_warning_message(form), form.span)
            }
        }
    }
}

emit_for_in_loop_body :: proc(e: ^Emitter, coll_form: CST_Form, coll_text, first_name, second_name: string, body: []CST_Form) -> (Compile_Error, bool) {
    emit_indent(e)
    strings.write_string(&e.builder, "for ")
    strings.write_string(&e.builder, first_name)
    prefix_len := len("for ") + len(first_name)
    if second_name != "" {
        strings.write_string(&e.builder, ", ")
        strings.write_string(&e.builder, second_name)
        prefix_len += len(", ") + len(second_name)
    }
    strings.write_string(&e.builder, " in ")
    prefix_len += len(" in ")
    strings.write_string(&e.builder, coll_text)
    record_current_line_fragment_map(e, prefix_len, coll_text, coll_form.span)
    strings.write_string(&e.builder, " {")
    emit_raw_newline(e)
    e.indent += 1
    push_local_type_scope(e)
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
    if !loop_collection_needs_temp_binding(coll_form) {
        err_owned, bad_owned := owned_result_usage_error(coll_form, false)
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

emit_map_callback_call :: proc(e: ^Emitter, callback: CST_Form, collection: string) -> (string, Compile_Error, bool) {
    if field, ok_field := field_from_selector(callback); ok_field {
        mark_core_map_field(e, field)
        return emit_call_text(
            fmt.tprintf("kvist_map_field_%s", field),
            []string{field_type_expr_text(collection, field), collection},
        ), {}, true
    }

    if callback.kind == .Symbol {
        if ctx, ok_context := lookup_callback_context(e, map_name(callback.text)); ok_context {
            mark_core_map_capture(e, len(ctx.capture_names))
            return capture_helper_call_text("kvist_map", map_name(callback.text), ctx.capture_names[:], collection), {}, true
        }
    }

    proc_text, capture_names, captured, err_capture, ok_capture := captured_unary_callback_proc(e, callback, "map", .Value)
    if !ok_capture {
        return "", err_capture, false
    }
    if captured {
        mark_core_map_capture(e, len(capture_names))
        return capture_helper_call_text("kvist_map", proc_text, capture_names[:], collection), {}, true
    }

    f, err_f, ok_f := emit_expr(e, callback)
    if !ok_f {
        return "", err_f, false
    }
    mark_core_map(e)
    return emit_call_text("kvist_map", []string{f, collection}), {}, true
}

emit_index_by_callback_call :: proc(e: ^Emitter, callback: CST_Form, collection: string) -> (string, Compile_Error, bool) {
    if field, ok_field := field_from_selector(callback); ok_field {
        mark_core_index_by_field(e, field)
        return emit_call_text(
            fmt.tprintf("kvist_index_by_field_%s", field),
            []string{field_type_expr_text(collection, field), collection},
        ), {}, true
    }

    f, err_f, ok_f := emit_expr(e, callback)
    if !ok_f {
        return "", err_f, false
    }
    call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/index-by-impl")
    if !ok_resolve {
        call_name = "arr__index_by_impl"
    }
    return emit_call_text(call_name, []string{f, collection}), {}, true
}

emit_group_by_callback_call :: proc(e: ^Emitter, callback: CST_Form, collection: string) -> (string, Compile_Error, bool) {
    if field, ok_field := field_from_selector(callback); ok_field {
        mark_core_group_by_field(e, field)
        return emit_call_text(
            fmt.tprintf("kvist_group_by_field_%s", field),
            []string{field_type_expr_text(collection, field), collection},
        ), {}, true
    }

    f, err_f, ok_f := emit_expr(e, callback)
    if !ok_f {
        return "", err_f, false
    }
    call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/group-by-impl")
    if !ok_resolve {
        call_name = "arr__group_by_impl"
    }
    return emit_call_text(call_name, []string{f, collection}), {}, true
}

emit_count_by_callback_call :: proc(e: ^Emitter, callback: CST_Form, collection: string) -> (string, Compile_Error, bool) {
    if field, ok_field := field_from_selector(callback); ok_field {
        mark_core_count_by_field(e, field)
        return emit_call_text(
            fmt.tprintf("kvist_count_by_field_%s", field),
            []string{field_type_expr_text(collection, field), collection},
        ), {}, true
    }

    f, err_f, ok_f := emit_expr(e, callback)
    if !ok_f {
        return "", err_f, false
    }
    call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/count-by-impl")
    if !ok_resolve {
        call_name = "arr__count_by_impl"
    }
    return emit_call_text(call_name, []string{f, collection}), {}, true
}

emit_sum_by_callback_call :: proc(e: ^Emitter, key_callback, value_callback: CST_Form, collection: string) -> (string, Compile_Error, bool) {
    if key_field, ok_key_field := field_from_selector(key_callback); ok_key_field {
        if value_field, ok_value_field := field_from_selector(value_callback); ok_value_field {
            mark_core_sum_by_field(e, key_field, value_field)
            return emit_call_text(
                fmt.tprintf("kvist_sum_by_fields_%s_%s", key_field, value_field),
                []string{
                    field_type_expr_text(collection, key_field),
                    field_type_expr_text(collection, value_field),
                    collection,
                },
            ), {}, true
        }
    }

    key_f, err_key_f, ok_key_f := emit_expr(e, key_callback)
    if !ok_key_f {
        return "", err_key_f, false
    }
    value_f, err_value_f, ok_value_f := emit_expr(e, value_callback)
    if !ok_value_f {
        return "", err_value_f, false
    }
    call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/sum-by-impl")
    if !ok_resolve {
        call_name = "arr__sum_by_impl"
    }
    return emit_call_text(call_name, []string{key_f, value_f, collection}), {}, true
}

emit_distinct_by_callback_call :: proc(e: ^Emitter, callback: CST_Form, collection: string) -> (string, Compile_Error, bool) {
    if field, ok_field := field_from_selector(callback); ok_field {
        mark_core_distinct_by_field(e, field)
        return emit_call_text(
            fmt.tprintf("kvist_distinct_by_field_%s", field),
            []string{field_type_expr_text(collection, field), collection},
        ), {}, true
    }
    f, err_f, ok_f := emit_expr(e, callback)
    if !ok_f {
        return "", err_f, false
    }
    call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/distinct-by-impl")
    if !ok_resolve {
        call_name = "arr__distinct_by_impl"
    }
    return emit_call_text(call_name, []string{f, collection}), {}, true
}

emit_partition_by_callback_call :: proc(e: ^Emitter, callback: CST_Form, collection: string) -> (string, Compile_Error, bool) {
    if field, ok_field := field_from_selector(callback); ok_field {
        mark_core_partition_by_field(e, field)
        return emit_call_text(
            fmt.tprintf("kvist_partition_by_field_%s", field),
            []string{field_type_expr_text(collection, field), collection},
        ), {}, true
    }

    f, err_f, ok_f := emit_expr(e, callback)
    if !ok_f {
        return "", err_f, false
    }
    call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/partition-by-impl")
    if !ok_resolve {
        call_name = "arr__partition_by_impl"
    }
    return emit_call_text(call_name, []string{f, collection}), {}, true
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

plain_symbol_callback :: proc(callback: CST_Form) -> (string, bool) {
    if callback.kind != .Symbol || !is_plain_identifier_text(callback.text) {
        return "", false
    }
    return callback.text, true
}

sort_by_callback_helper_name :: proc(callback: string, in_place: bool = false) -> string {
    if in_place {
        return fmt.tprintf("kvist_sort_by_in_place_callback_%s", callback)
    }
    return fmt.tprintf("kvist_sort_by_callback_%s", callback)
}

emit_sort_by_callback_call :: proc(e: ^Emitter, callback: CST_Form, collection: string) -> (string, Compile_Error, bool) {
    if field, ok_field := field_from_selector(callback); ok_field {
        mark_core_sort_by_field(e, field)
        return emit_call_text(
            fmt.tprintf("kvist_sort_by_field_%s", field),
            []string{field_type_expr_text(collection, field), collection},
        ), {}, true
    }

    if callback_name, ok_callback := plain_symbol_callback(callback); ok_callback {
        mark_core_sort_by_callback(e, callback_name)
        return emit_call_text(sort_by_callback_helper_name(callback_name), []string{collection}), {}, true
    }

    f, err_f, ok_f := emit_expr(e, callback)
    if !ok_f {
        return "", err_f, false
    }
    mark_core_sort_by(e)
    return emit_call_text("kvist_sort_by", []string{f, collection}), {}, true
}

emit_sort_by_in_place_callback_call :: proc(e: ^Emitter, callback: CST_Form, collection: string) -> (string, Compile_Error, bool) {
    if field, ok_field := field_from_selector(callback); ok_field {
        mark_core_sort_by_in_place_field(e, field)
        return emit_call_text(fmt.tprintf("kvist_sort_by_in_place_field_%s", field), []string{collection}), {}, true
    }

    if callback_name, ok_callback := plain_symbol_callback(callback); ok_callback {
        mark_core_sort_by_in_place_callback(e, callback_name)
        return emit_call_text(sort_by_callback_helper_name(callback_name, true), []string{collection}), {}, true
    }

    f, err_f, ok_f := emit_expr(e, callback)
    if !ok_f {
        return "", err_f, false
    }
    mark_core_sort_by_in_place(e)
    return emit_call_text("kvist_sort_by_in_place", []string{f, collection}), {}, true
}

emit_dynamic_predicate_in_place_callback_call :: proc(e: ^Emitter, helper_name: string, callback: CST_Form, collection: string, mark_helper: proc(^Emitter), mark_field: proc(^Emitter, string)) -> (string, Compile_Error, bool) {
    collection_ptr := address_of_expr_text(collection)
    if field, ok_field := field_from_selector(callback); ok_field {
        mark_field(e, field)
        return emit_call_text(fmt.tprintf("%s_field_%s", helper_name, field), []string{collection_ptr}), {}, true
    }

    if callback.kind == .Symbol {
        if ctx, ok_context := lookup_callback_context(e, map_name(callback.text)); ok_context {
            switch helper_name {
            case "kvist_filter_in_place":
                mark_core_filter_in_place_capture(e, len(ctx.capture_names))
            case "kvist_remove_in_place":
                mark_core_remove_in_place_capture(e, len(ctx.capture_names))
            }
            return capture_helper_call_text(helper_name, map_name(callback.text), ctx.capture_names[:], collection_ptr), {}, true
        }
    }

    proc_text, capture_names, captured, err_capture, ok_capture := captured_unary_callback_proc(e, callback, helper_name, .Predicate)
    if !ok_capture {
        return "", err_capture, false
    }
    if captured {
        switch helper_name {
        case "kvist_filter_in_place":
            mark_core_filter_in_place_capture(e, len(capture_names))
        case "kvist_remove_in_place":
            mark_core_remove_in_place_capture(e, len(capture_names))
        }
        return capture_helper_call_text(helper_name, proc_text, capture_names[:], collection_ptr), {}, true
    }

    pred, err_pred, ok_pred := emit_expr(e, callback)
    if !ok_pred {
        return "", err_pred, false
    }
    mark_helper(e)
    return emit_call_text(helper_name, []string{pred, collection_ptr}), {}, true
}

emit_predicate_callback_call :: proc(e: ^Emitter, helper_name: string, callback: CST_Form, collection: string, mark_helper: proc(^Emitter), mark_field: proc(^Emitter, string)) -> (string, Compile_Error, bool) {
    if field, ok_field := field_from_selector(callback); ok_field {
        mark_field(e, field)
        return emit_call_text(fmt.tprintf("%s_field_%s", helper_name, field), []string{collection}), {}, true
    }

    if callback.kind == .Symbol {
        if ctx, ok_context := lookup_callback_context(e, map_name(callback.text)); ok_context {
            switch helper_name {
            case "kvist_filter":
                mark_core_filter_capture(e, len(ctx.capture_names))
            case "kvist_remove":
                mark_core_remove_capture(e, len(ctx.capture_names))
            }
            return capture_helper_call_text(helper_name, map_name(callback.text), ctx.capture_names[:], collection), {}, true
        }
    }

    proc_text, capture_names, captured, err_capture, ok_capture := captured_unary_callback_proc(e, callback, helper_name, .Predicate)
    if !ok_capture {
        return "", err_capture, false
    }
    if captured {
        switch helper_name {
        case "kvist_filter":
            mark_core_filter_capture(e, len(capture_names))
        case "kvist_remove":
            mark_core_remove_capture(e, len(capture_names))
        }
        return capture_helper_call_text(helper_name, proc_text, capture_names[:], collection), {}, true
    }

    pred, err_pred, ok_pred := emit_expr(e, callback)
    if !ok_pred {
        return "", err_pred, false
    }
    mark_helper(e)
    return emit_call_text(helper_name, []string{pred, collection}), {}, true
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
        }
    case .List:
        if len(form.items) > 0 && is_symbol(form.items[0], "fn") {
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

capture_helper_name :: proc(base: string, capture_count: int) -> string {
    return fmt.tprintf("%s_%d", base, capture_count)
}

capture_proc_param_text :: proc(capture_count: int, item_name, item_ty, return_text: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "f: proc(")
    for idx in 0..<capture_count {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "c%d: $C%d", idx+1, idx+1)
    }
    if capture_count > 0 {
        strings.write_string(&builder, ", ")
    }
    fmt.sbprintf(&builder, "%s: %s) -> %s", item_name, item_ty, return_text)
    for idx in 0..<capture_count {
        fmt.sbprintf(&builder, ", c%d: C%d", idx+1, idx+1)
    }
    return strings.clone(strings.to_string(builder))
}

capture_call_arg_text :: proc(capture_count: int, item: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for idx in 0..<capture_count {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "c%d", idx+1)
    }
    if capture_count > 0 {
        strings.write_string(&builder, ", ")
    }
    strings.write_string(&builder, item)
    return strings.clone(strings.to_string(builder))
}

capture_helper_call_text :: proc(base, proc_text: string, capture_names: []string, final_arg: string) -> string {
    args: [dynamic]string
    defer delete(args)
    append(&args, proc_text)
    for capture_name in capture_names {
        append(&args, capture_name)
    }
    append(&args, final_arg)
    return emit_call_text(capture_helper_name(base, len(capture_names)), args[:])
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

known_non_escaping_callback_helper_head :: proc(head: string) -> (callback_index: int, ok: bool) {
    switch head {
    case "arr-map", "arr/map", "arr-filter", "arr/filter", "arr-remove", "arr/remove",
         "arr-map!", "arr/map!", "arr-filter!", "arr/filter!", "arr-remove!", "arr/remove!",
         "arr-keep", "arr/keep", "arr-keep!", "arr/keep!",
         "arr-sort-by", "arr/sort-by", "arr-sort-by!", "arr/sort-by!",
         "arr-partition-by", "arr/partition-by", "arr-index-by", "arr/index-by",
         "arr-group-by", "arr/group-by", "arr-count-by", "arr/count-by",
         "arr-distinct-by", "arr/distinct-by",
         "arr-take-while", "arr/take-while", "arr-drop-while", "arr/drop-while",
         "arr-find", "arr/find", "arr-some?", "arr/some?", "arr-every?", "arr/every?":
        return 1, true
    case "arr-reduce", "arr/reduce":
        return 1, true
    case "arr-sum-by", "arr/sum-by":
        return 1, true
    case:
        return 0, false
    }
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
            if cb_idx, ok_helper := known_non_escaping_callback_helper_head(head); ok_helper {
                for item, idx in form.items {
                    if idx == cb_idx && item.kind == .Symbol && map_name(item.text) == callback_name {
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
                    if idx < len(callee.params) &&
                       item.kind == .Symbol &&
                       map_name(item.text) == callback_name &&
                       type_text_is_proc(callee.params[idx].ty) &&
                       proc_callback_param_non_escaping_depth(e, callee, idx, depth+1) {
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

mark_captured_proc_specialization :: proc(e: ^Emitter, proc_name: string, callback_param_index, capture_count: int) {
    if e.captured_proc_specializations == nil {
        return
    }
    for spec in e.captured_proc_specializations^ {
        if spec.original_name == proc_name &&
           spec.callback_param_index == callback_param_index &&
           spec.capture_count == capture_count {
            return
        }
    }
    append(e.captured_proc_specializations, Captured_Proc_Specialization{
        original_name = proc_name,
        callback_param_index = callback_param_index,
        capture_count = capture_count,
    })
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

    if op == "contains?" {
        return "", Compile_Error{message = "`contains?` has moved to `core/contains?`", span = form.items[0].span}, false
    }

    if op == "in?" {
        return "", Compile_Error{message = "`in?` has moved to `core/contains?`", span = form.items[0].span}, false
    }

    if op == "core-contains?" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects exactly two arguments", op), span = form.span}, false
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
            if ty == "string" {
                key_ty, ok_key_ty := obvious_form_type(e, form.items[2])
                if ok_key_ty && key_ty == "string" {
                    mark_core_strings(e)
                    return emit_call_text("strings.contains", []string{collection, key}), {}, true
                }
                return "", Compile_Error{message = "core/contains? on strings expects a string needle", span = form.items[2].span}, false
            }
            if strings.has_prefix(ty, "map[") {
                return fmt.tprintf("(%s) in (%s)", key, collection), {}, true
            }
            if strings.has_prefix(ty, "[]") || strings.has_prefix(ty, "[dynamic]") || (len(ty) > 1 && ty[0] == '[') {
                mark_core_contains_value(e)
                return emit_call_text("kvist_contains_value", []string{fmt.tprintf("(%s)[:]", collection), key}), {}, true
            }
        }
        return fmt.tprintf("(%s) in (%s)", key, collection), {}, true
    }

    if op == "in" {
        return "", Compile_Error{message = "`in` has moved to `core/in`", span = form.items[0].span}, false
    }

    if op == "not-in" {
        return "", Compile_Error{message = "`not-in` has moved to `core/not-in`", span = form.items[0].span}, false
    }

    if op == "core/in" || op == "core-in" || op == "core/not-in" || op == "core-not-in" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects exactly two arguments", op), span = form.span}, false
        }
        lhs, err_lhs, ok_lhs := emit_expr(e, form.items[1])
        if !ok_lhs {
            return "", err_lhs, false
        }
        rhs, err_rhs, ok_rhs := emit_expr(e, form.items[2])
        if !ok_rhs {
            return "", err_rhs, false
        }
        if op == "core/not-in" || op == "core-not-in" {
            return fmt.tprintf("!((%s) in (%s))", lhs, rhs), {}, true
        }
        return fmt.tprintf("(%s) in (%s)", lhs, rhs), {}, true
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
    if form.kind != .Symbol || len(form.text) < 2 || form.text[0] != '\'' {
        return "", false
    }
    return map_name(form.text[1:]), true
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
        key_end := strings.index(ty, "]")
        if key_end > 4 {
            key := ty[4:key_end]
            return fmt.tprintf("set[%s]", surface_type_text(key))
        }
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
        if value.kind == .String {
            return true
        }
        return value.kind != .Number && value.kind != .Bool
    case "int":
        if value.kind == .Number {
            return !number_looks_float(value.text)
        }
        return value.kind != .String && value.kind != .Bool
    case "f64":
        if value.kind == .Number {
            return true
        }
        return value.kind != .String && value.kind != .Bool
    case "bool":
        if value.kind == .Bool {
            return true
        }
        return value.kind != .String && value.kind != .Number
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

captured_callback_arg_context :: proc(e: ^Emitter, arg: CST_Form) -> (proc_text: string, capture_names: [dynamic]string, captured: bool, err: Compile_Error, ok: bool) {
    if arg.kind == .Symbol {
        name := map_name(arg.text)
        if ctx, ok_context := lookup_callback_context(e, name); ok_context {
            for capture_name in ctx.capture_names {
                append(&capture_names, capture_name)
            }
            return name, capture_names, true, Compile_Error{}, true
        }
        return "", capture_names, false, Compile_Error{}, true
    }

    proc_text_value, capture_names_value, _, captured_value, err_value, ok_value := captured_proc_literal_for_param(e, arg)
    return proc_text_value, capture_names_value, captured_value, err_value, ok_value
}

emit_specialized_proc_call_if_needed :: proc(e: ^Emitter, call_name: string, proc_decl: ^Proc_Decl, args: []CST_Form, span: Span) -> (text: string, handled: bool, err: Compile_Error, ok: bool) {
    captured_index := -1
    proc_text := ""
    capture_names: [dynamic]string

    for arg, idx in args {
        if idx >= len(proc_decl.params) || !type_text_is_proc(proc_decl.params[idx].ty) {
            continue
        }
        candidate_proc_text, candidate_capture_names, captured, err_candidate, ok_candidate := captured_callback_arg_context(e, arg)
        if !ok_candidate {
            return "", true, err_candidate, false
        }
        if !captured {
            continue
        }
        if captured_index >= 0 {
            return "", true, Compile_Error{message = "captured callback specialization currently supports one captured callback argument per call", span = arg.span}, false
        }
        captured_index = idx
        proc_text = candidate_proc_text
        capture_names = candidate_capture_names
    }

    if captured_index < 0 {
        return "", false, Compile_Error{}, true
    }

    if len(args) != len(proc_decl.params) {
        return "", true, Compile_Error{message = "captured callback specialization currently requires explicit positional arguments", span = span}, false
    }
    if !proc_callback_param_non_escaping(e, proc_decl, captured_index) {
        return "", true, Compile_Error{message = fmt.tprintf("captured callback cannot be passed to %s because callback parameter %s may escape", call_name, proc_decl.params[captured_index].name), span = args[captured_index].span}, false
    }

    mark_captured_proc_specialization(e, proc_decl.name, captured_index, len(capture_names))
    specialized_name := captured_specialization_name(proc_decl.name, captured_index, len(capture_names))

    arg_texts: [dynamic]string
    defer delete(arg_texts)
    for arg, idx in args {
        if idx == captured_index {
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

emit_call_like :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    head := form.items[0]
    if head.kind != .Symbol {
        return "", Compile_Error{message = "unsupported call head", span = head.span}, false
    }

    canonical_head, _, err_head, ok_head := resolve_kvist_head(e, head.text)
    if !ok_head {
        err_head.span = head.span
        return "", err_head, false
    }
    head.text = canonical_head
    err_deprecated, deprecated := deprecated_builtin_collection_head_error(head)
    if deprecated {
        return "", err_deprecated, false
    }
    surface_head := display_head_name(head.text)

    if ctx, ok_context := lookup_callback_context(e, map_name(head.text)); ok_context {
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

    if head.text == "get" {
        return "", Compile_Error{message = "`get` has moved to `core/get`", span = form.items[0].span}, false
    }

    if head.text == "count" {
        return "", Compile_Error{message = "`count` has moved to `core/count`", span = form.items[0].span}, false
    }

    if head.text == "empty?" {
        return "", Compile_Error{message = "`empty?` has moved to `core/empty?`", span = form.items[0].span}, false
    }

    if head.text == "new" {
        return "", Compile_Error{message = "`new` has been removed; use type-call syntax like (T literal)", span = form.items[0].span}, false
    }

    if head.text == "as" {
        return "", Compile_Error{message = "`as` has been removed; use type-call syntax like (T x)", span = form.items[0].span}, false
    }

    if head.text == "core-get" {
        if len(form.items) != 3 && len(form.items) != 4 {
            return "", Compile_Error{message = "get expects collection, key, and optional default", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        if field, ok_field := selector_accesses_field(e, form.items[1], form.items[2]); ok_field {
            if len(form.items) == 4 {
                return "", Compile_Error{message = "get field access does not support a default value", span = form.items[2].span}, false
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
            return emit_call_text("kvist_get_or_default", []string{target, key, default_value}), {}, true
        }
        return fmt.tprintf("%s[%s]", target, key), {}, true
    }

    if head.text == "arr/count" || head.text == "str/count" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = fmt.tprintf("%s expects one collection", head.text), span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        return fmt.tprintf("len(%s)", target), {}, true
    }

    if head.text == "arr-empty" || head.text == "arr/empty" {
        if len(form.items) != 2 && len(form.items) != 3 {
            return "", Compile_Error{message = "arr/empty expects element type and optional capacity", span = form.span}, false
        }
        elem_text, err_elem, ok_elem := parse_type_text(form.items[1])
        if !ok_elem {
            return "", err_elem, false
        }
        if len(form.items) == 2 {
            return fmt.tprintf("make([dynamic]%s)", elem_text), {}, true
        }
        capacity, err_capacity, ok_capacity := emit_expr(e, form.items[2])
        if !ok_capacity {
            return "", err_capacity, false
        }
        return fmt.tprintf("make([dynamic]%s, 0, %s)", elem_text, capacity), {}, true
    }

    if head.text == "arr-dynamic" || head.text == "arr/dynamic" {
        if len(form.items) != 3 || form.items[2].kind != .Vector {
            return "", Compile_Error{message = "arr/dynamic expects element type and vector literal", span = form.span}, false
        }
        elem_text, err_elem, ok_elem := parse_type_text(form.items[1])
        if !ok_elem {
            return "", err_elem, false
        }
        mark_dynamic_literals(e)
        return emit_vector_literal(e, fmt.tprintf("[dynamic]%s", elem_text), form.items[2])
    }

    if head.text == "arr-fixed" || head.text == "arr/fixed" {
        if len(form.items) != 3 || form.items[2].kind != .Vector {
            return "", Compile_Error{message = "arr/fixed expects element type and vector literal", span = form.span}, false
        }
        elem_text, err_elem, ok_elem := parse_type_text(form.items[1])
        if !ok_elem {
            return "", err_elem, false
        }
        length := len(form.items[2].items)
        return emit_vector_literal(e, fmt.tprintf("[%d]%s", length, elem_text), form.items[2])
    }

    if head.text == "map-empty" || head.text == "map/empty" {
        if len(form.items) != 3 && len(form.items) != 4 {
            return "", Compile_Error{message = "map/empty expects key type, value type, and optional capacity", span = form.span}, false
        }
        key_text, err_key, ok_key := parse_type_text(form.items[1])
        if !ok_key {
            return "", err_key, false
        }
        value_text, err_value, ok_value := parse_type_text(form.items[2])
        if !ok_value {
            return "", err_value, false
        }
        if len(form.items) == 3 {
            return fmt.tprintf("make(map[%s]%s)", key_text, value_text), {}, true
        }
        capacity, err_capacity, ok_capacity := emit_expr(e, form.items[3])
        if !ok_capacity {
            return "", err_capacity, false
        }
        return fmt.tprintf("make(map[%s]%s, %s)", key_text, value_text, capacity), {}, true
    }

    if head.text == "map-of" || head.text == "map/of" {
        if len(form.items) != 4 || form.items[3].kind != .Brace {
            return "", Compile_Error{message = "map/of expects key type, value type, and brace literal", span = form.span}, false
        }
        key_text, err_key, ok_key := parse_type_text(form.items[1])
        if !ok_key {
            return "", err_key, false
        }
        value_text, err_value, ok_value := parse_type_text(form.items[2])
        if !ok_value {
            return "", err_value, false
        }
        return emit_brace_literal(e, fmt.tprintf("map[%s]%s", key_text, value_text), form.items[3])
    }

    if head.text == "set-empty" || head.text == "set/empty" {
        if len(form.items) != 2 && len(form.items) != 3 {
            return "", Compile_Error{message = "set/empty expects element type and optional capacity", span = form.span}, false
        }
        elem_text, err_elem, ok_elem := parse_type_text(form.items[1])
        if !ok_elem {
            return "", err_elem, false
        }
        if len(form.items) == 2 {
            return fmt.tprintf("make(map[%s]struct{{}})", elem_text), {}, true
        }
        capacity, err_capacity, ok_capacity := emit_expr(e, form.items[2])
        if !ok_capacity {
            return "", err_capacity, false
        }
        return fmt.tprintf("make(map[%s]struct{{}}, %s)", elem_text, capacity), {}, true
    }

    if head.text == "set-of" || head.text == "set/of" {
        if len(form.items) != 3 || form.items[2].kind != .Vector {
            return "", Compile_Error{message = "set/of expects element type and vector literal", span = form.span}, false
        }
        elem_text, err_elem, ok_elem := parse_type_text(form.items[1])
        if !ok_elem {
            return "", err_elem, false
        }
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        strings.write_string(&builder, "map[")
        strings.write_string(&builder, elem_text)
        strings.write_string(&builder, "]struct{}{")
        values, err_values, ok_values := emit_vector_item_texts(e, form.items[2])
        if !ok_values {
            return "", err_values, false
        }
        for value, idx in values {
            if idx > 0 {
                strings.write_string(&builder, ", ")
            }
            strings.write_string(&builder, value)
            strings.write_string(&builder, " = {}")
        }
        strings.write_byte(&builder, '}')
        return strings.clone(strings.to_string(builder)), {}, true
    }

    if head.text == "arr/get" || head.text == "str/get" || head.text == "map/get" {
        if len(form.items) != 3 && len(form.items) != 4 {
            return "", Compile_Error{message = fmt.tprintf("%s expects collection, key, and optional default", head.text), span = form.span}, false
        }
        rewritten := form
        rewritten.items[0].text = "core-get"
        return emit_call_like(e, rewritten)
    }

    if head.text == "arr/slice" || head.text == "str/slice" {
        if len(form.items) != 3 && len(form.items) != 4 {
            return "", Compile_Error{message = fmt.tprintf("%s expects collection, optional start, and end", head.text), span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
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

    if head.text == "arr-push!" || head.text == "arr/push!" {
        if len(form.items) < 3 {
            return "", Compile_Error{message = "arr/push! expects dynamic array and at least one value", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        target_ty, known_target_ty := known_form_type(e, form.items[1])
        arg_texts: [dynamic]string
        call_name := "append"
        if known_target_ty && type_text_is_dynamic_soa(target_ty) {
            call_name = "append_soa"
            append(&arg_texts, address_of_expr_text(target))
        } else if known_target_ty && type_text_is_pointer_to_dynamic_soa(target_ty) {
            call_name = "append_soa"
            append(&arg_texts, target)
        } else {
            append(&arg_texts, fmt.tprintf("&(%s)", target))
        }
        for arg in form.items[2:] {
            arg_text, err_arg, ok_arg := emit_expr(e, arg)
            if !ok_arg {
                return "", err_arg, false
            }
            append(&arg_texts, arg_text)
        }
        return emit_call_text(call_name, arg_texts[:]), {}, true
    }

    if head.text == "map/contains?" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "map/contains? expects collection and key", span = form.span}, false
        }
        rewritten := form
        rewritten.items[0].text = "core-contains?"
        return emit_call_like(e, rewritten)
    }

    if head.text == "println" {
        return "", Compile_Error{message = "`println` has moved to `core/println`", span = form.items[0].span}, false
    }

    if head.text == "core/println" || head.text == "core-println" {
        arg_texts: [dynamic]string
        for arg in form.items[1:] {
            arg_text, err_arg, ok_arg := emit_expr(e, arg)
            if !ok_arg {
                return "", err_arg, false
            }
            append(&arg_texts, arg_text)
        }
        return emit_call_text("fmt.println", arg_texts[:]), {}, true
    }

    is_struct_fields := head.text == "struct-fields" || head.text == "struct/fields" || head.text == "soa/fields"
    is_struct_types := head.text == "struct-types" || head.text == "struct/types" || head.text == "soa/types"
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

    if head.text == "nil?" {
        return "", Compile_Error{message = "`nil?` has moved to `core/nil?`", span = form.items[0].span}, false
    }

    if head.text == "core/nil?" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "core/nil? expects one expression", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        return fmt.tprintf("(%s) == nil", target), {}, true
    }

    if head.text == "tap>" {
        return "", Compile_Error{message = "`tap>` has moved to `core/tap>`", span = form.items[0].span}, false
    }

    if head.text == "core/tap>" || head.text == "core-tap" {
        if len(form.items) != 2 && len(form.items) != 3 {
            return "", Compile_Error{message = "core/tap> expects value or label and value", span = form.span}, false
        }
        mark_core_tap(e)
        if len(form.items) == 2 {
            value, err_value, ok_value := emit_expr(e, form.items[1])
            if !ok_value {
                return "", err_value, false
            }
            return emit_call_text("kvist_tap", []string{value}), {}, true
        }

        label_form := form.items[1]
        label: string
        if label_form.kind == .String {
            label = label_form.text
        } else {
            return "", Compile_Error{message = "core/tap> label must be a string literal", span = label_form.span}, false
        }
        value, err_value, ok_value := emit_expr(e, form.items[2])
        if !ok_value {
            return "", err_value, false
        }
        return emit_call_text("kvist_tap_labeled", []string{label, value}), {}, true
    }

    is_arr_map := head.text == "arr-map" || head.text == "arr/map"
    is_arr_filter := head.text == "arr-filter" || head.text == "arr/filter"
    is_arr_remove := head.text == "arr-remove" || head.text == "arr/remove"
    if is_arr_map || is_arr_filter || is_arr_remove {
        if len(form.items) != 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects function and collection", surface_head), span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        collection = slice_all_expr_text(collection)
        if is_arr_map {
            return emit_map_callback_call(e, form.items[1], collection)
        }
        if is_arr_remove {
            return emit_predicate_callback_call(e, "kvist_remove", form.items[1], collection, mark_core_remove, mark_core_remove_field)
        }
        return emit_predicate_callback_call(e, "kvist_filter", form.items[1], collection, mark_core_filter, mark_core_filter_field)
    }

    if head.text == "arr-map!" || head.text == "arr/map!" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "map! expects function and collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        callback := form.items[1]
        proc_text, capture_names, captured, err_capture, ok_capture := captured_unary_callback_proc(e, callback, "map!", .Value)
        if !ok_capture {
            return "", err_capture, false
        }
        if captured {
            mark_core_map_in_place_capture(e, len(capture_names))
            return capture_helper_call_text("kvist_map_in_place", proc_text, capture_names[:], slice_all_expr_text(collection)), {}, true
        }
        f, err_f, ok_f := emit_expr(e, callback)
        if !ok_f {
            return "", err_f, false
        }
        mark_core_map_in_place(e)
        return emit_call_text("kvist_map_in_place", []string{f, slice_all_expr_text(collection)}), {}, true
    }

    is_arr_filter_in_place := head.text == "arr-filter!" || head.text == "arr/filter!"
    is_arr_remove_in_place := head.text == "arr-remove!" || head.text == "arr/remove!"
    if is_arr_filter_in_place || is_arr_remove_in_place {
        if len(form.items) != 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects predicate and dynamic array", surface_head), span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        if is_arr_remove_in_place {
            return emit_dynamic_predicate_in_place_callback_call(e, "kvist_remove_in_place", form.items[1], collection, mark_core_remove_in_place, mark_core_remove_in_place_field)
        }
        return emit_dynamic_predicate_in_place_callback_call(e, "kvist_filter_in_place", form.items[1], collection, mark_core_filter_in_place, mark_core_filter_in_place_field)
    }

    is_arr_keep := head.text == "arr-keep" || head.text == "arr/keep"
    if is_arr_keep {
        if len(form.items) != 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects function and collection", surface_head), span = form.span}, false
        }
        callback := form.items[1]
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        collection = slice_all_expr_text(collection)
        proc_text, capture_names, captured, err_capture, ok_capture := captured_unary_callback_proc(e, callback, "keep", .Keep)
        if !ok_capture {
            return "", err_capture, false
        }
        if captured {
            mark_core_keep_capture(e, len(capture_names))
            return capture_helper_call_text("kvist_keep", proc_text, capture_names[:], collection), {}, true
        }
        if callback.kind == .Symbol {
            if ctx, ok_context := lookup_callback_context(e, map_name(callback.text)); ok_context {
                mark_core_keep_capture(e, len(ctx.capture_names))
                return capture_helper_call_text("kvist_keep", map_name(callback.text), ctx.capture_names[:], collection), {}, true
            }
        }
        f, err_f, ok_f := emit_expr(e, callback)
        if !ok_f {
            return "", err_f, false
        }
        mark_core_keep(e)
        return emit_call_text("kvist_keep", []string{f, collection}), {}, true
    }

    if head.text == "arr-keep!" || head.text == "arr/keep!" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "keep! expects function and dynamic array", span = form.span}, false
        }
        callback := form.items[1]
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        proc_text, capture_names, captured, err_capture, ok_capture := captured_unary_callback_proc(e, callback, "keep!", .Keep)
        if !ok_capture {
            return "", err_capture, false
        }
        if captured {
            mark_core_keep_in_place_capture(e, len(capture_names))
            return capture_helper_call_text("kvist_keep_in_place", proc_text, capture_names[:], address_of_expr_text(collection)), {}, true
        }
        if callback.kind == .Symbol {
            if ctx, ok_context := lookup_callback_context(e, map_name(callback.text)); ok_context {
                mark_core_keep_in_place_capture(e, len(ctx.capture_names))
                return capture_helper_call_text("kvist_keep_in_place", map_name(callback.text), ctx.capture_names[:], address_of_expr_text(collection)), {}, true
            }
        }
        f, err_f, ok_f := emit_expr(e, callback)
        if !ok_f {
            return "", err_f, false
        }
        mark_core_keep_in_place(e)
        return emit_call_text("kvist_keep_in_place", []string{f, address_of_expr_text(collection)}), {}, true
    }

    if head.text == "arr-into!" || head.text == "arr/into!" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "into! expects target and collection", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        return emit_call_text("append", []string{address_of_expr_text(target), fmt.tprintf("..%s", slice_all_expr_text(collection))}), {}, true
    }

    if head.text == "map-dissoc!" || head.text == "map/dissoc!" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects target map and key", surface_head), span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        key, err_key, ok_key := emit_expr(e, form.items[2])
        if !ok_key {
            return "", err_key, false
        }
        return emit_call_text("delete_key", []string{address_of_expr_text(target), key}), {}, true
    }

    if head.text == "arr-into" || head.text == "arr/into" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "into expects dynamic array type and collection", span = form.span}, false
        }
        type_text, err_type, ok_type := parse_type_text(form.items[1])
        if !ok_type {
            return "", err_type, false
        }
        if !type_text_is_dynamic_array(type_text) {
            return "", Compile_Error{message = "into currently expects a dynamic array type", span = form.items[1].span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        mark_core_into(e)
        return emit_call_text("kvist_into", []string{type_text, slice_all_expr_text(collection)}), {}, true
    }

    if head.text == "concat" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "concat expects two collections", span = form.span}, false
        }
        lhs, err_lhs, ok_lhs := emit_expr(e, form.items[1])
        if !ok_lhs {
            return "", err_lhs, false
        }
        rhs, err_rhs, ok_rhs := emit_expr(e, form.items[2])
        if !ok_rhs {
            return "", err_rhs, false
        }
        mark_core_concat(e)
        return emit_call_text("kvist_concat", []string{slice_all_expr_text(lhs), slice_all_expr_text(rhs)}), {}, true
    }

    if head.text == "arr-sort-by" || head.text == "arr/sort-by" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "sort-by expects key function and collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        return emit_sort_by_callback_call(e, form.items[1], slice_all_expr_text(collection))
    }

    if head.text == "arr-sort-by!" || head.text == "arr/sort-by!" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "sort-by! expects key function and collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        return emit_sort_by_in_place_callback_call(e, form.items[1], slice_all_expr_text(collection))
    }

    if head.text == "arr-partition-by" || head.text == "arr/partition-by" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "partition-by expects key function and collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        return emit_partition_by_callback_call(e, form.items[1], slice_all_expr_text(collection))
    }

    if head.text == "map/zip" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects key and value collections", surface_head), span = form.span}, false
        }
        keys, err_keys, ok_keys := emit_expr(e, form.items[1])
        if !ok_keys {
            return "", err_keys, false
        }
        values, err_values, ok_values := emit_expr(e, form.items[2])
        if !ok_values {
            return "", err_values, false
        }
        return emit_call_text("map__zip", []string{slice_all_expr_text(keys), slice_all_expr_text(values)}), {}, true
    }

    if head.text == "arr-index-by" || head.text == "arr/index-by" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "index-by expects key function and collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        return emit_index_by_callback_call(e, form.items[1], slice_all_expr_text(collection))
    }

    if head.text == "arr-group-by" || head.text == "arr/group-by" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "group-by expects key function and collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        return emit_group_by_callback_call(e, form.items[1], slice_all_expr_text(collection))
    }

    if head.text == "arr-count-by" || head.text == "arr/count-by" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "count-by expects key function and collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        return emit_count_by_callback_call(e, form.items[1], slice_all_expr_text(collection))
    }

    if head.text == "arr-sum-by" || head.text == "arr/sum-by" {
        if len(form.items) != 4 {
            return "", Compile_Error{message = "sum-by expects key function, value function, and collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[3])
        if !ok_collection {
            return "", err_collection, false
        }
        return emit_sum_by_callback_call(e, form.items[1], form.items[2], slice_all_expr_text(collection))
    }

    if head.text == "arr-distinct-by" || head.text == "arr/distinct-by" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "distinct-by expects key function and collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        return emit_distinct_by_callback_call(e, form.items[1], slice_all_expr_text(collection))
    }

    if head.text == "or-else" {
        return "", Compile_Error{message = "`or-else` has moved to `core/or-else`", span = form.items[0].span}, false
    }

    if head.text == "core/or-else" || head.text == "core-or-else" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "core/or-else expects optional-ok expression and fallback", span = form.span}, false
        }
        optional_text, err_optional, ok_optional := emit_expr(e, form.items[1])
        if !ok_optional {
            return "", err_optional, false
        }
        fallback_text, err_fallback, ok_fallback := emit_expr(e, form.items[2])
        if !ok_fallback {
            return "", err_fallback, false
        }
        return fmt.tprintf("%s or_else %s", optional_text, fallback_text), {}, true
    }

    if head.text == "arr/reduce" {
        if len(form.items) != 4 {
            return "", Compile_Error{message = fmt.tprintf("%s expects function, initial value, and collection", surface_head), span = form.span}, false
        }
        f, err_f, ok_f := emit_expr(e, form.items[1])
        if !ok_f {
            return "", err_f, false
        }
        init, err_init, ok_init := emit_expr(e, form.items[2])
        if !ok_init {
            return "", err_init, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[3])
        if !ok_collection {
            return "", err_collection, false
        }
        collection = slice_all_expr_text(collection)
        mark_core_reduce(e)
        return emit_call_text("kvist_reduce", []string{f, init, collection}), {}, true
    }

    is_arr_take_while := head.text == "arr-take-while" || head.text == "arr/take-while"
    is_arr_drop_while := head.text == "arr-drop-while" || head.text == "arr/drop-while"
    is_arr_find := head.text == "arr-find" || head.text == "arr/find"
    is_arr_some := head.text == "arr-some?" || head.text == "arr/some?"
    is_arr_every := head.text == "arr-every?" || head.text == "arr/every?"
    if is_arr_take_while || is_arr_drop_while || is_arr_find || is_arr_some || is_arr_every {
        if len(form.items) != 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects predicate and collection", surface_head), span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        collection = slice_all_expr_text(collection)
        if field, ok_field := field_from_selector(form.items[1]); ok_field {
            if is_arr_take_while {
                mark_core_take_while_field(e, field)
                return emit_call_text(fmt.tprintf("kvist_take_while_field_%s", field), []string{collection}), {}, true
            }
            if is_arr_drop_while {
                mark_core_drop_while_field(e, field)
                return emit_call_text(fmt.tprintf("kvist_drop_while_field_%s", field), []string{collection}), {}, true
            }
            if is_arr_find {
                mark_core_find_field(e, field)
                return emit_call_text(fmt.tprintf("kvist_find_field_%s", field), []string{collection}), {}, true
            }
            if is_arr_some {
                mark_core_some_field(e, field)
                return emit_call_text(fmt.tprintf("kvist_some_p_field_%s", field), []string{collection}), {}, true
            }
            mark_core_every_field(e, field)
            return emit_call_text(fmt.tprintf("kvist_every_p_field_%s", field), []string{collection}), {}, true
        }
        pred, err_pred, ok_pred := emit_expr(e, form.items[1])
        if !ok_pred {
            return "", err_pred, false
        }
        if is_arr_take_while {
            call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/take-while-impl")
            if !ok_resolve {
                call_name = "arr__take_while_impl"
            }
            return emit_call_text(call_name, []string{pred, collection}), {}, true
        }
        if is_arr_drop_while {
            call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/drop-while-impl")
            if !ok_resolve {
                call_name = "arr__drop_while_impl"
            }
            return emit_call_text(call_name, []string{pred, collection}), {}, true
        }
        if is_arr_find {
            call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/find-impl")
            if !ok_resolve {
                call_name = "arr__find_impl"
            }
            return emit_call_text(call_name, []string{pred, collection}), {}, true
        }
        if is_arr_some {
            call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/some-impl")
            if !ok_resolve {
                call_name = "arr__some_impl"
            }
            return emit_call_text(call_name, []string{pred, collection}), {}, true
        }
        call_name, _, ok_resolve := resolve_proc_call_decl(e, "arr/every-impl")
        if !ok_resolve {
            call_name = "arr__every_impl"
        }
        return emit_call_text(call_name, []string{pred, collection}), {}, true
    }

    if head.text == "arr/first" ||
       head.text == "arr/second" || head.text == "arr/last" ||
       head.text == "arr/rest" ||
       head.text == "core-empty?" || head.text == "core-count" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = fmt.tprintf("%s expects collection", surface_head), span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[1])
        if !ok_collection {
            return "", err_collection, false
        }
        collection_ty, _ := obvious_form_type(e, form.items[1])
        if !strings.has_prefix(collection_ty, "map[") && collection_ty != "string" && collection_ty != "cstring" {
            collection = slice_all_expr_text(collection)
        }
        if head.text == "core-count" {
            return fmt.tprintf("len(%s)", collection), {}, true
        }
        if head.text == "arr/first" {
            return fmt.tprintf("(%s)[0]", collection), {}, true
        }
        if head.text == "arr/second" {
            return fmt.tprintf("(%s)[1]", collection), {}, true
        }
        if head.text == "arr/last" {
            return fmt.tprintf("(%s)[len(%s)-1]", collection, collection), {}, true
        }
        if head.text == "core-empty?" {
            return fmt.tprintf("len(%s) == 0", collection), {}, true
        }
        return fmt.tprintf("(%s)[1:]", collection), {}, true
    }

    if head.text == "arr/nth" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "nth expects collection and index", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[1])
        if !ok_collection {
            return "", err_collection, false
        }
        index, err_index, ok_index := emit_expr(e, form.items[2])
        if !ok_index {
            return "", err_index, false
        }
        return fmt.tprintf("(%s)[%s]", slice_all_expr_text(collection), index), {}, true
    }

    if head.text == "slice" {
        return "", Compile_Error{message = "`slice` has moved to `core/slice`", span = form.items[0].span}, false
    }

    if head.text == "core-slice" || head.text == "arr/slice" {
        if len(form.items) < 2 || len(form.items) > 4 {
            return "", Compile_Error{message = "slice expects collection, optional start, and optional end", span = form.span}, false
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

    if head.text == "&" || head.text == "addr" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = fmt.tprintf("%s expects one addressable expression", head.text), span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        return addr_expr_text(target), {}, true
    }

    update_head := source_package_surface_head(head.text)
    if head.text == "assoc" || update_head == "core/assoc" || head.text == "core-assoc" {
        return emit_shallow_assoc_expr(e, form)
    }

    if head.text == "update" || update_head == "core/update" || head.text == "core-update" {
        return emit_shallow_update_expr(e, form)
    }

    if head.text == "->" {
        return "", Compile_Error{message = "`->` has moved to `core/->`", span = form.items[0].span}, false
    }

    if head.text == "->>" {
        return "", Compile_Error{message = "`->>` has moved to `core/->>`", span = form.items[0].span}, false
    }

    if head.text == "core-thread-first" {
        return emit_thread_expr(e, form)
    }

    if head.text == "core-thread-last" {
        return emit_thread_expr(e, form, true)
    }

    if head.text == "soa-make-raw" {
        if len(form.items) != 2 && len(form.items) != 3 {
            return "", Compile_Error{message = "soa/make expects elem-type and optional capacity", span = form.span}, false
        }
        type_text, err_type, ok_type := parse_type_text(form.items[1])
        if !ok_type {
            return "", err_type, false
        }
        if len(form.items) == 2 {
            return fmt.tprintf("make(%s)", type_text), {}, true
        }
        capacity, err_capacity, ok_capacity := emit_expr(e, form.items[2])
        if !ok_capacity {
            return "", err_capacity, false
        }
        return fmt.tprintf("make(%s, 0, %s)", type_text, capacity), {}, true
    }

    if head.text == "make" {
        if len(form.items) < 2 {
            return "", Compile_Error{message = "make expects a type and optional arguments", span = form.span}, false
        }
        type_text, err_type, ok_type := parse_type_text(form.items[1])
        if !ok_type {
            return "", err_type, false
        }
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        fmt.sbprintf(&builder, "make(%s", type_text)
        for arg in form.items[2:] {
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

    if len(form.items) == 2 && form.items[1].kind == .Vector {
        if head.text == "quaternion" {
            return emit_quaternion_vector_constructor(e, form.items[1])
        }
        head_name := map_name(head.text)
        if !strings.contains(head_name, ".") {
            if _, _, ok_proc := resolve_proc_call_decl(e, head.text); ok_proc {
                // Let the normal call path handle declared procedures with vector arguments.
            } else {
                type_text, err_type, ok_type := parse_type_text(head)
                if !ok_type {
                    return "", err_type, false
                }
                if type_form_needs_dynamic_literals(head) {
                    mark_dynamic_literals(e)
                }
                if type_text_is_dynamic_soa(type_text) {
                    return emit_dynamic_soa_vector_literal(e, type_text, form.items[1])
                }
                return emit_vector_literal(e, type_text, form.items[1])
            }
        } else {
            imported_fields, ok_imported_type := imported_odin_type_fields(e, head_name)
            if ok_imported_type {
                defer delete_struct_field_slice(&imported_fields)
                type_text, err_type, ok_type := parse_type_text(head)
                if !ok_type {
                    return "", err_type, false
                }
                if type_form_needs_dynamic_literals(head) {
                    mark_dynamic_literals(e)
                }
                return emit_vector_literal(e, type_text, form.items[1])
            }
            if _, ok_expected := imported_odin_proc_arg_type(e, head_name, 0); !ok_expected {
                type_text, err_type, ok_type := parse_type_text(head)
                if !ok_type {
                    return "", err_type, false
                }
                if type_form_needs_dynamic_literals(head) {
                    mark_dynamic_literals(e)
                }
                if type_text_is_dynamic_soa(type_text) {
                    return emit_dynamic_soa_vector_literal(e, type_text, form.items[1])
                }
                return emit_vector_literal(e, type_text, form.items[1])
            }
        }
    }

    if head.text == "quaternion" {
        return emit_quaternion_arg_constructor(e, form.items[1:], form.span)
    }

    if len(form.items) == 2 && form.items[1].kind == .Brace {
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
        if !strings.contains(head_name, ".") {
            if call_name, proc_decl, ok_proc := resolve_proc_call_decl(e, head.text); ok_proc {
                named_arg_texts, err_named, ok_named := emit_named_call_with_defaults(e, proc_decl, form.items[1])
                if !ok_named {
                    return "", err_named, false
                }
                return emit_call_text(call_name, named_arg_texts[:]), {}, true
            }
            named_arg_texts, err_named, ok_named := emit_named_call_arg_texts(e, form.items[1])
            if ok_named {
                return emit_call_text(head_name, named_arg_texts[:]), {}, true
            }
            if err_named.message != "" && err_named.message != "named arguments expect field: labels" {
                return "", err_named, false
            }
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
        value_text, err_value, ok_value := emit_expr(e, form.items[1])
        if !ok_value {
            return "", err_value, false
        }
        return emit_type_conversion_text(type_text, value_text), {}, true
    }
    for arg, arg_idx in form.items[1:] {
        arg_text := ""
        err_arg: Compile_Error
        ok_arg := false
        if expected_type, ok_expected := imported_odin_proc_arg_type(e, head_name, arg_idx); ok_expected {
            arg_text, err_arg, ok_arg = emit_expr_for_expected_type(e, arg, expected_type)
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

    value := args[0]
    #partial switch value.kind {
    case .Vector:
        if type_form_needs_dynamic_literals(type_form) {
            mark_dynamic_literals(e)
        }
        if type_text_is_dynamic_soa(type_text) {
            return emit_dynamic_soa_vector_literal(e, type_text, value)
        }
        return emit_vector_literal(e, type_text, value)
    case .Brace:
        struct_decl, ok_struct := find_struct_decl(e, type_text)
        if ok_struct {
            err_struct, ok_struct_ctor := validate_struct_constructor(e, struct_decl, value)
            if !ok_struct_ctor {
                return "", err_struct, false
            }
            return emit_struct_brace_literal(e, struct_decl, value)
        }
        return emit_inferred_literal(e, value, type_text)
    case:
        value_text, err_value, ok_value := emit_expr(e, value)
        if !ok_value {
            return "", err_value, false
        }
        return emit_type_conversion_text(type_text, value_text), {}, true
    }
}

parse_for_comprehension_clauses :: proc(bindings: CST_Form) -> (clauses: [dynamic]For_Comprehension_Clause, err: Compile_Error, ok: bool) {
    if bindings.kind != .Vector {
        return clauses, Compile_Error{message = "for comprehension expects a binding vector", span = bindings.span}, false
    }
    i := 0
    for i < len(bindings.items) {
        item := bindings.items[i]
        if item.kind == .Keyword {
            switch item.text {
            case ":when":
                if i+1 >= len(bindings.items) {
                    return clauses, Compile_Error{message = ":when expects a predicate expression", span = item.span}, false
                }
                append(&clauses, For_Comprehension_Clause{
                    kind      = .When,
                    predicate = bindings.items[i+1],
                })
                i += 2
                continue
            case ":while":
                if i+1 >= len(bindings.items) {
                    return clauses, Compile_Error{message = ":while expects a predicate expression", span = item.span}, false
                }
                append(&clauses, For_Comprehension_Clause{
                    kind      = .While,
                    predicate = bindings.items[i+1],
                })
                i += 2
                continue
            case ":let":
                if i+1 >= len(bindings.items) {
                    return clauses, Compile_Error{message = ":let expects a binding vector", span = item.span}, false
                }
                let_bindings := bindings.items[i+1]
                if let_bindings.kind != .Vector {
                    return clauses, Compile_Error{message = ":let expects a binding vector", span = let_bindings.span}, false
                }
                if len(let_bindings.items) == 0 {
                    return clauses, Compile_Error{message = ":let expects at least one binding", span = let_bindings.span}, false
                }
                if len(let_bindings.items)%2 != 0 {
                    return clauses, Compile_Error{message = ":let expects name/value pairs", span = let_bindings.span}, false
                }
                for j := 0; j < len(let_bindings.items); j += 2 {
                    if let_bindings.items[j].kind != .Symbol {
                        return clauses, Compile_Error{message = ":let binding expects a symbol", span = let_bindings.items[j].span}, false
                    }
                }
                append(&clauses, For_Comprehension_Clause{
                    kind     = .Let,
                    bindings = let_bindings,
                })
                i += 2
                continue
            case:
                return clauses, Compile_Error{message = fmt.tprintf("unsupported for comprehension clause %s", item.text), span = item.span}, false
            }
        }
        if item.kind != .Symbol {
            return clauses, Compile_Error{message = "for comprehension binding expects a symbol", span = item.span}, false
        }
        if i+1 >= len(bindings.items) {
            return clauses, Compile_Error{message = "for comprehension binding expects a collection expression", span = item.span}, false
        }
        append(&clauses, For_Comprehension_Clause{
            kind       = .Binding,
            name       = map_name(item.text),
            collection = bindings.items[i+1],
        })
        i += 2
    }
    if len(clauses) == 0 {
        return clauses, Compile_Error{message = "for comprehension expects at least one binding", span = bindings.span}, false
    }
    return clauses, {}, true
}

bind_for_comprehension_clause_types :: proc(e: ^Emitter, clauses: []For_Comprehension_Clause) {
    for clause in clauses {
        switch clause.kind {
        case .Binding:
            coll_ty, ok_coll_ty := obvious_form_type(e, clause.collection)
            if !ok_coll_ty {
                continue
            }
            elem_ty, ok_elem_ty := collection_element_type(coll_ty)
            if ok_elem_ty {
                bind_local_type(e, clause.name, elem_ty)
            }
        case .Let:
            for i := 0; i < len(clause.bindings.items); i += 2 {
                name_form := clause.bindings.items[i]
                value_form := clause.bindings.items[i+1]
                if ty, ok_ty := obvious_form_type(e, value_form); ok_ty {
                    bind_local_type(e, map_name(name_form.text), ty)
                }
            }
        case .When, .While:
            continue
        }
    }
}

for_comprehension_output_kind :: proc(type_text: string) -> (kind: For_Comprehension_Output_Kind, key_ty, value_ty: string, ok: bool) {
    if elem, ok_elem := dynamic_array_element_type(type_text); ok_elem {
        return .Dynamic_Array, "", elem, true
    }
    if key, value, ok_map := map_type_parts(type_text); ok_map {
        if value == "struct{}" {
            return .Set, key, value, true
        }
        return .Map, key, value, true
    }
    return .Dynamic_Array, "", "", false
}

collect_for_comprehension_captures :: proc(e: ^Emitter, clauses: []For_Comprehension_Clause, yield_form: CST_Form) -> (captures: [dynamic]Param) {
    bound_names: [dynamic]string
    for clause in clauses {
        switch clause.kind {
        case .Binding:
            collect_proc_literal_captures_from_form(e, clause.collection, bound_names[:], &captures)
            append(&bound_names, clause.name)
        case .When, .While:
            collect_proc_literal_captures_from_form(e, clause.predicate, bound_names[:], &captures)
        case .Let:
            for i := 0; i < len(clause.bindings.items); i += 2 {
                name_form := clause.bindings.items[i]
                value_form := clause.bindings.items[i+1]
                collect_proc_literal_captures_from_form(e, value_form, bound_names[:], &captures)
                append(&bound_names, map_name(name_form.text))
            }
        }
    }
    collect_proc_literal_captures_from_form(e, yield_form, bound_names[:], &captures)
    return captures
}

emit_for_comprehension_proc_params :: proc(captures: []Param) -> string {
    if len(captures) == 0 {
        return ""
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for capture, idx in captures {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        strings.write_string(&builder, capture.name)
        strings.write_string(&builder, ": ")
        strings.write_string(&builder, capture.ty)
    }
    return strings.clone(strings.to_string(builder))
}

emit_for_comprehension_call_args :: proc(captures: []Param) -> string {
    if len(captures) == 0 {
        return ""
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for capture, idx in captures {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        strings.write_string(&builder, capture.name)
    }
    return strings.clone(strings.to_string(builder))
}

emit_for_comprehension_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) < 3 || form.items[1].kind != .Vector {
        return "", Compile_Error{message = "for comprehension expects bindings and one yield expression", span = form.span}, false
    }

    clauses, err_clauses, ok_clauses := parse_for_comprehension_clauses(form.items[1])
    if !ok_clauses {
        return "", err_clauses, false
    }

    body_index := 2
    out_type := ""
    if body_index < len(form.items) && form.items[body_index].kind == .Keyword && form.items[body_index].text == ":into" {
        if body_index+1 >= len(form.items) {
            return "", Compile_Error{message = ":into expects a dynamic array type", span = form.items[body_index].span}, false
        }
        type_text, err_type, ok_type := parse_type_text(form.items[body_index+1])
        if !ok_type {
            return "", err_type, false
        }
        out_type = type_text
        body_index += 2
    }
    if len(form.items)-body_index != 1 {
        return "", Compile_Error{message = "for comprehension expects exactly one yield expression", span = form.span}, false
    }

    yield_form := form.items[body_index]
    push_local_type_scope(e)
    bind_for_comprehension_clause_types(e, clauses[:])
    if out_type == "" {
        yield_ty, err_yield_ty, ok_yield_ty := infer_literal_value_type(e, yield_form)
        if !ok_yield_ty {
            pop_local_type_scope(e)
            return "", Compile_Error{
                message = fmt.tprintf("cannot infer for comprehension output type: %s; add :into [dynamic]T", err_yield_ty.message),
                span = yield_form.span,
            }, false
        }
        out_type = fmt.tprintf("[dynamic]%s", yield_ty)
    }
    output_kind, output_key_ty, output_value_ty, ok_output := for_comprehension_output_kind(out_type)
    if !ok_output {
        pop_local_type_scope(e)
        return "", Compile_Error{message = "for comprehension :into expects [dynamic]T, map[K]V, or set[T]", span = form.span}, false
    }

    collection_texts: [dynamic]string
    collection_owned: [dynamic]bool
    predicate_texts: [dynamic]string
    let_value_texts: [dynamic]string
    for clause in clauses {
        switch clause.kind {
        case .Binding:
            coll_text, err_coll, ok_coll := emit_expr(e, clause.collection)
            if !ok_coll {
                pop_local_type_scope(e)
                return "", err_coll, false
            }
            append(&collection_texts, coll_text)
            append(&collection_owned, loop_collection_needs_temp_binding(clause.collection))
        case .When, .While:
            pred_text, err_pred, ok_pred := emit_expr(e, clause.predicate)
            if !ok_pred {
                pop_local_type_scope(e)
                return "", err_pred, false
            }
            append(&predicate_texts, pred_text)
        case .Let:
            for i := 0; i < len(clause.bindings.items); i += 2 {
                value_text, err_value, ok_value := emit_expr(e, clause.bindings.items[i+1])
                if !ok_value {
                    pop_local_type_scope(e)
                    return "", err_value, false
                }
                append(&let_value_texts, value_text)
            }
        }
    }

    captures := collect_for_comprehension_captures(e, clauses[:], yield_form)
    proc_params := emit_for_comprehension_proc_params(captures[:])
    proc_args := emit_for_comprehension_call_args(captures[:])

    yield_text := ""
    map_key_text := ""
    map_value_text := ""
    set_value_text := ""
    switch output_kind {
    case .Dynamic_Array:
        yield, err_yield, ok_yield := emit_expr_for_expected_type(e, yield_form, output_value_ty)
        if !ok_yield {
            pop_local_type_scope(e)
            return "", err_yield, false
        }
        yield_text = yield
    case .Map:
        if yield_form.kind != .Vector || len(yield_form.items) != 2 {
            pop_local_type_scope(e)
            return "", Compile_Error{message = "for comprehension map output expects yielded [key value]", span = yield_form.span}, false
        }
        key_text, err_key, ok_key := emit_expr_for_expected_type(e, yield_form.items[0], output_key_ty)
        if !ok_key {
            pop_local_type_scope(e)
            return "", err_key, false
        }
        value_text, err_value, ok_value := emit_expr_for_expected_type(e, yield_form.items[1], output_value_ty)
        if !ok_value {
            pop_local_type_scope(e)
            return "", err_value, false
        }
        map_key_text = key_text
        map_value_text = value_text
    case .Set:
        value_text, err_value, ok_value := emit_expr_for_expected_type(e, yield_form, output_key_ty)
        if !ok_value {
            pop_local_type_scope(e)
            return "", err_value, false
        }
        set_value_text = value_text
    }
    pop_local_type_scope(e)

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "(proc(")
    strings.write_string(&builder, proc_params)
    strings.write_string(&builder, ") -> ")
    strings.write_string(&builder, out_type)
    strings.write_string(&builder, " {\n")
    strings.write_string(&builder, "    out := make(")
    strings.write_string(&builder, out_type)
    strings.write_string(&builder, ")\n")

    depth := 1
    coll_idx := 0
    pred_idx := 0
    let_idx := 0
    for clause in clauses {
        switch clause.kind {
        case .Binding:
            coll_text := collection_texts[coll_idx]
            if collection_owned[coll_idx] {
                e.temp_counter += 1
                temp := fmt.tprintf("kvist_for_%d", e.temp_counter)
                append_indent(&builder, depth)
                strings.write_string(&builder, temp)
                strings.write_string(&builder, " := ")
                strings.write_string(&builder, coll_text)
                strings.write_byte(&builder, '\n')
                append_indent(&builder, depth)
                strings.write_string(&builder, "defer delete(")
                strings.write_string(&builder, temp)
                strings.write_string(&builder, ")\n")
                coll_text = temp
            }
            append_indent(&builder, depth)
            strings.write_string(&builder, "for ")
            strings.write_string(&builder, clause.name)
            strings.write_string(&builder, " in ")
            strings.write_string(&builder, coll_text)
            strings.write_string(&builder, " {\n")
            depth += 1
            coll_idx += 1
        case .When:
            append_indent(&builder, depth)
            strings.write_string(&builder, "if !(")
            strings.write_string(&builder, predicate_texts[pred_idx])
            strings.write_string(&builder, ") {\n")
            append_indent(&builder, depth+1)
            strings.write_string(&builder, "continue\n")
            append_indent(&builder, depth)
            strings.write_string(&builder, "}\n")
            pred_idx += 1
        case .While:
            append_indent(&builder, depth)
            strings.write_string(&builder, "if !(")
            strings.write_string(&builder, predicate_texts[pred_idx])
            strings.write_string(&builder, ") {\n")
            append_indent(&builder, depth+1)
            strings.write_string(&builder, "break\n")
            append_indent(&builder, depth)
            strings.write_string(&builder, "}\n")
            pred_idx += 1
        case .Let:
            for i := 0; i < len(clause.bindings.items); i += 2 {
                name := map_name(clause.bindings.items[i].text)
                append_indent(&builder, depth)
                strings.write_string(&builder, name)
                strings.write_string(&builder, " := ")
                strings.write_string(&builder, let_value_texts[let_idx])
                strings.write_byte(&builder, '\n')
                let_idx += 1
            }
        }
    }

    append_indent(&builder, depth)
    switch output_kind {
    case .Dynamic_Array:
        append_indented_multiline(&builder, emit_call_text("append", []string{"&out", yield_text}), "", "")
    case .Map:
        strings.write_string(&builder, "out[")
        strings.write_string(&builder, map_key_text)
        strings.write_string(&builder, "] = ")
        strings.write_string(&builder, map_value_text)
    case .Set:
        strings.write_string(&builder, "out[")
        strings.write_string(&builder, set_value_text)
        strings.write_string(&builder, "] = {}")
    }
    strings.write_byte(&builder, '\n')
    for depth > 1 {
        depth -= 1
        append_indent(&builder, depth)
        strings.write_string(&builder, "}\n")
    }
    strings.write_string(&builder, "    return out\n")
    strings.write_string(&builder, "})(")
    strings.write_string(&builder, proc_args)
    strings.write_string(&builder, ")")
    return strings.clone(strings.to_string(builder)), {}, true
}

emit_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    #partial switch form.kind {
    case .String:
        return form.text, {}, true
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
        return "", Compile_Error{message = "keywords are syntax markers, not values; use a string, enum value, field label, or field selector", span = form.span}, false
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
        if is_symbol(form.items[0], "for") {
            return emit_for_comprehension_expr(e, form)
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

For_Comprehension_Clause_Kind :: enum {
    Binding,
    When,
    While,
    Let,
}

For_Comprehension_Clause :: struct {
    kind:       For_Comprehension_Clause_Kind,
    name:       string,
    collection: CST_Form,
    predicate:  CST_Form,
    bindings:   CST_Form,
}

For_Comprehension_Output_Kind :: enum {
    Dynamic_Array,
    Map,
    Set,
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

dynamic_array_element_type :: proc(type_text: string) -> (string, bool) {
    if !type_text_is_dynamic_array(type_text) {
        return "", false
    }
    return type_text[len("[dynamic]"):], true
}

append_indent :: proc(builder: ^strings.Builder, depth: int) {
    for _ in 0..<depth {
        strings.write_string(builder, "    ")
    }
}

Binding :: struct {
    is_destructure: bool,
    is_result_binding: bool,
    name:           string,
    pattern:        [dynamic]string,
    is_typed:       bool,
    ty:             string,
    deferred_delete: bool,
    or_modifier:    string,
    target_span:    Span,
    value:          CST_Form,
}

let_binding_has_defer_marker :: proc(items: []CST_Form, idx: int) -> bool {
    return idx < len(items) &&
        items[idx].kind == .Symbol &&
        items[idx].text == "defer"
}

let_binding_or_modifier :: proc(items: []CST_Form, idx: int) -> (string, bool) {
    if idx >= len(items) || items[idx].kind != .Symbol {
        return "", false
    }
    switch items[idx].text {
    case "or-return", "or-break", "or-continue":
        return items[idx].text, true
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
            for part in target.items {
                if part.kind != .Symbol {
                    return bindings, Compile_Error{message = "multi-return binding expects symbols", span = part.span}, false
                }
                append(&names, map_name(part.text))
            }
            or_modifier, has_or_modifier := let_binding_or_modifier(form.items[:], i+2)
            deferred_delete := false
            next_i := i + 2
            if has_or_modifier {
                if len(names) != 2 {
                    return bindings, Compile_Error{message = "or-* let binding expects exactly two names", span = target.span}, false
                }
                if names[1] != "ok" && names[1] != "err" {
                    return bindings, Compile_Error{message = "or-* let binding requires [value ok] or [value err]", span = target.span}, false
                }
                next_i += 1
                deferred_delete = let_binding_has_defer_marker(form.items[:], next_i)
                if deferred_delete {
                    next_i += 1
                }
            } else if let_binding_has_defer_marker(form.items[:], i+2) {
                return bindings, Compile_Error{message = "defer binding marker is only supported on named local bindings or [value ok/err] or-* bindings", span = form.items[i+2].span}, false
            }
            append(&bindings, Binding{
                is_destructure = !has_or_modifier,
                is_result_binding = has_or_modifier,
                pattern = names,
                deferred_delete = deferred_delete,
                or_modifier = or_modifier,
                target_span = target.span,
                value = form.items[i+1],
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
                deferred_delete := let_binding_has_defer_marker(form.items[:], next_i+1)
                append(&bindings, Binding{
                    name = map_name(target.text[:len(target.text)-1]),
                    is_typed = true,
                    ty = type_text,
                    deferred_delete = deferred_delete,
                    target_span = target.span,
                    value = form.items[next_i],
                })
                i = next_i + 1
                if deferred_delete {
                    i += 1
                }
            } else {
                if i+1 >= len(form.items) {
                    return bindings, Compile_Error{message = "binding missing value", span = target.span}, false
                }
                deferred_delete := let_binding_has_defer_marker(form.items[:], i+2)
                append(&bindings, Binding{
                    name = map_name(target.text),
                    deferred_delete = deferred_delete,
                    target_span = target.span,
                    value = form.items[i+1],
                })
                i += 2
                if deferred_delete {
                    i += 1
                }
            }
        case .Brace:
            return bindings, Compile_Error{message = "field destructuring has been removed; use dot access or explicit local bindings", span = target.span}, false
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
            return Compile_Error{message = "typed defvar missing value", span = target.span}, false
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
    err_owned, bad_owned := owned_result_usage_error(value_form, true)
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

emit_cond_stmt :: proc(e: ^Emitter, form: CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    if len(form.items) < 3 {
        return Compile_Error{message = "cond expects at least one clause", span = form.span}, false
    }
    if (len(form.items)-1)%2 != 0 {
        return Compile_Error{message = "cond expects test/body pairs", span = form.span}, false
    }

    branch_returns := returns_when_final(last_in_proc, returns)
    i := 1
    for i < len(form.items) {
        test_form := form.items[i]
        body_form := form.items[i+1]
        is_else := is_else_keyword(test_form)

        if is_else && i+2 < len(form.items) {
            return Compile_Error{message = "cond :else must be the final clause", span = test_form.span}, false
        }

        if is_else {
            emit_indent(e)
            strings.write_string(&e.builder, "else {")
            emit_raw_newline(e)
        } else {
            test, err_test, ok_test := emit_expr(e, test_form)
            if !ok_test {
                return err_test, false
            }
            emit_indent(e)
            if i == 1 {
                strings.write_string(&e.builder, "if ")
                record_current_line_fragment_map(e, len("if "), test, test_form.span)
            } else {
                strings.write_string(&e.builder, "else if ")
                record_current_line_fragment_map(e, len("else if "), test, test_form.span)
            }
            strings.write_string(&e.builder, test)
            strings.write_string(&e.builder, " {")
            emit_raw_newline(e)
        }

        e.indent += 1
        push_local_type_scope(e)
        err_body, ok_body := emit_stmt(e, body_form, last_in_proc, branch_returns)
        pop_local_type_scope(e)
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")

        i += 2
    }

    return {}, true
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
    err_escape, bad_escape := with_temp_allocator_escape_error(body[:], last_in_proc, returns)
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

is_type_switch_subject :: proc(form: CST_Form) -> bool {
    return form.kind == .Vector && len(form.items) == 2 && form.items[0].kind == .Symbol
}

switch_has_else_clause :: proc(form: CST_Form) -> bool {
    i := 2
    for i < len(form.items) {
        if is_else_keyword(form.items[i]) {
            return true
        }
        i += 2
    }
    return false
}

emit_switch_case_label :: proc(e: ^Emitter, clause: CST_Form, type_switch: bool) -> (string, Compile_Error, bool) {
    if is_else_keyword(clause) {
        return "case:", {}, true
    }

    if type_switch {
        if clause.kind == .Symbol {
            return fmt.tprintf("case %s:", map_name(clause.text)), {}, true
        }
        if clause.kind == .Vector {
            builder := strings.builder_make()
            defer strings.builder_destroy(&builder)
            strings.write_string(&builder, "case ")
            for item, idx in clause.items {
                if item.kind != .Symbol {
                    return "", Compile_Error{message = "type-switch case vector expects symbols", span = item.span}, false
                }
                if idx > 0 {
                    strings.write_string(&builder, ", ")
                }
                strings.write_string(&builder, map_name(item.text))
            }
            strings.write_string(&builder, ":")
            return strings.clone(strings.to_string(builder)), {}, true
        }
        return "", Compile_Error{message = "type-switch case expects a type symbol or vector of types", span = clause.span}, false
    }

    if clause.kind == .Vector {
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        strings.write_string(&builder, "case ")
        for item, idx in clause.items {
            item_text, err_item, ok_item := emit_expr(e, item)
            if !ok_item {
                return "", err_item, false
            }
            if idx > 0 {
                strings.write_string(&builder, ", ")
            }
            strings.write_string(&builder, item_text)
        }
        strings.write_string(&builder, ":")
        return strings.clone(strings.to_string(builder)), {}, true
    }

    clause_text, err_clause, ok_clause := emit_expr(e, clause)
    if !ok_clause {
        return "", err_clause, false
    }
    return fmt.tprintf("case %s:", clause_text), {}, true
}

emit_switch_stmt :: proc(e: ^Emitter, form: CST_Form, last_in_proc: bool, returns: Return_Spec, force_partial: bool = false) -> (Compile_Error, bool) {
    if len(form.items) < 4 {
        return Compile_Error{message = "switch expects subject and at least one clause", span = form.span}, false
    }

    type_switch := is_type_switch_subject(form.items[1])
    emit_indent(e)
    if !type_switch && (force_partial || switch_has_else_clause(form)) {
        strings.write_string(&e.builder, "#partial ")
    }
    strings.write_string(&e.builder, "switch ")
    if type_switch {
        binding_name := map_name(form.items[1].items[0].text)
        subject, err_subject, ok_subject := emit_expr(e, form.items[1].items[1])
        if !ok_subject {
            return err_subject, false
        }
        strings.write_string(&e.builder, binding_name)
        strings.write_string(&e.builder, " in ")
        strings.write_string(&e.builder, subject)
        record_current_line_fragment_map(e, len("switch ") + len(binding_name) + len(" in "), subject, form.items[1].items[1].span)
    } else {
        subject, err_subject, ok_subject := emit_expr(e, form.items[1])
        if !ok_subject {
            return err_subject, false
        }
        strings.write_string(&e.builder, subject)
        prefix_len := len("switch ")
        if !type_switch && (force_partial || switch_has_else_clause(form)) {
            prefix_len = len("#partial switch ")
        }
        record_current_line_fragment_map(e, prefix_len, subject, form.items[1].span)
    }
    strings.write_string(&e.builder, " {")
    emit_raw_newline(e)

    branch_returns := returns_when_final(last_in_proc, returns)
    i := 2
    saw_else := false
    for i < len(form.items) {
        if i+1 >= len(form.items) {
            return Compile_Error{message = "switch clause missing body", span = form.span}, false
        }

        clause := form.items[i]
        body := form.items[i+1]

        if is_else_keyword(clause) {
            if i+2 < len(form.items) {
                return Compile_Error{message = "switch :else must be the final clause", span = clause.span}, false
            }
            saw_else = true
        } else if saw_else {
            return Compile_Error{message = "switch cannot have clauses after :else", span = clause.span}, false
        }

        label, err_label, ok_label := emit_switch_case_label(e, clause, type_switch)
        if !ok_label {
            return err_label, false
        } else {
            emit_line_mapped(e, label, clause.span)
        }

        e.indent += 1
        err_body, ok_body := emit_stmt(e, body, last_in_proc, branch_returns)
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1

        i += 2
    }

    emit_line(e, "}")
    return {}, true
}

emit_stmt :: proc(e: ^Emitter, form: CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    if form.kind != .List {
        expr, err_expr, ok_expr := emit_expr(e, form)
        if !ok_expr {
            return err_expr, false
        }
        if last_in_proc && returns.kind != .None {
            emit_prefixed_expr_mapped(e, "return ", expr, form.span)
        } else if form_is_owned_allocation_result(form) || form_is_owned_constructor_result(form) {
            emit_prefixed_expr_mapped(e, "_ = ", expr, form.span)
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
        expr, err_expr, ok_expr := emit_expr(e, form)
        if !ok_expr {
            return err_expr, false
        }
        if last_in_proc && returns.kind != .None {
            emit_prefixed_expr_mapped(e, "return ", expr, form.span)
        } else if form_is_owned_allocation_result(form) || form_is_owned_constructor_result(form) {
            emit_prefixed_expr_mapped(e, "_ = ", expr, form.span)
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

    if last_in_proc && returns.kind != .None {
        err_thread_return, bad_thread_return := thread_return_error(e, form)
        if bad_thread_return {
            return err_thread_return, false
        }
    }

    switch builtin_macro_kind(head.text) {
    case .With_Allocator:
        return emit_with_allocator_stmt(e, form, last_in_proc, returns)
    case .With_Temp_Allocator:
        return emit_with_temp_allocator_stmt(e, form, last_in_proc, returns)
    case .When:
    case .Thread_First, .Thread_Last:
    case .When_Let, .If_Let, .When_Ok, .If_Ok:
    case .None:
    }

    switch head.text {
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
    case "comment":
        return Compile_Error{message = "`comment` has moved to `core/comment`", span = form.items[0].span}, false
    case "core/comment":
        return {}, true
    case "#partial":
        if len(form.items) < 2 || !is_symbol(form.items[1], "switch") {
            return Compile_Error{message = "#partial currently expects a switch form", span = form.span}, false
        }
        switch_items: [dynamic]CST_Form
        for item in form.items[1:] {
            append(&switch_items, item)
        }
        switch_form := CST_Form{
            kind  = .List,
            items = switch_items,
            span  = form.span,
        }
        return emit_switch_stmt(e, switch_form, last_in_proc, returns, true)
    case "let":
        if len(form.items) < 3 {
            return Compile_Error{message = "let expects bindings and body", span = form.span}, false
        }
        bindings, err_bind, ok_bind := parse_let_bindings(form.items[1])
        if !ok_bind {
            return err_bind, false
        }
        body: [dynamic]CST_Form
        for item in form.items[2:] {
            append(&body, item)
        }
        if last_in_proc && returns.kind != .None {
            err_let_return, bad_let_return := let_return_error(bindings[:], body[:])
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
            if binding_value_is_let(binding) {
                err_flat, ok_flat := emit_let_value_binding_assignment(e, binding)
                if !ok_flat {
                    return err_flat, false
                }
            } else if is_thread_form(binding.value, true) {
                err_thread, ok_thread := emit_thread_binding_assignment(e, binding, true)
                if !ok_thread {
                    return err_thread, false
                }
            } else if is_thread_form(binding.value, false) {
                err_thread, ok_thread := emit_thread_binding_assignment(e, binding, false)
                if !ok_thread {
                    return err_thread, false
                }
            } else {
                err_owned, bad_owned := owned_result_usage_error(binding.value, true)
                if bad_owned {
                    return err_owned, false
                }
                value, err_value, ok_value := emit_expr_for_expected_type(e, binding.value, binding.ty)
                if !ok_value {
                    return err_value, false
                }
                if binding.is_result_binding && binding.or_modifier == "or-return" {
                    if !named_returns_match_binding_pattern(returns, binding.pattern[:]) {
                        return Compile_Error{
                            message = "or-return currently requires proc named returns matching the binding names exactly",
                            span = binding.value.span,
                        }, false
                    }
                    emit_result_binding_named_return_assignment(e, binding, value)
                } else {
                    emit_binding_assignment(e, binding, value)
                }
            }
            err_guard, ok_guard := emit_result_binding_guard(e, binding, returns)
            if !ok_guard {
                return err_guard, false
            }
            if binding.deferred_delete {
                delete_name, ok_delete_name := binding_delete_target_name(binding)
                if !ok_delete_name {
                    return Compile_Error{message = "defer binding marker is only supported on delete-able local bindings", span = binding.value.span}, false
                }
                emit_line(e, fmt.tprintf("defer delete(%s)", delete_name))
            }
            if ty, ok_ty := obvious_binding_type(e, binding); ok_ty {
                bind_local_type(e, binding.name, ty)
            }
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
    case "when":
        return Compile_Error{message = "`when` has moved to `core/when`", span = form.items[0].span}, false
    case "cond":
        return Compile_Error{message = "`cond` has moved to `core/cond`", span = form.items[0].span}, false
    case "if":
        return emit_if_like(e, "if", form, last_in_proc, returns)
    case "switch":
        return Compile_Error{message = "`switch` has moved to `core/switch`", span = form.items[0].span}, false
    case "core-switch":
        return emit_switch_stmt(e, form, last_in_proc, returns)
    case "return":
        if len(form.items) == 1 {
            emit_line(e, "return")
            return {}, true
        }
        if len(form.items) == 2 {
            err_thread_return, bad_thread_return := thread_return_error(e, form.items[1])
            if bad_thread_return {
                return err_thread_return, false
            }
            err_owned, bad_owned := owned_result_usage_error(form.items[1], true)
            if bad_owned {
                return err_owned, false
            }
            value, err_value, ok_value := emit_expr(e, form.items[1])
            if !ok_value {
                return err_value, false
            }
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
            err_owned, bad_owned := owned_result_usage_error(item, true)
            if bad_owned {
                return err_owned, false
            }
            value, err_value, ok_value := emit_expr(e, item)
            if !ok_value {
                return err_value, false
            }
            strings.write_string(&line_builder, value)
        }
        emit_line_mapped(e, strings.clone(strings.to_string(line_builder)), form.items[1].span)
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
                case "if", "when", "cond", "switch", "core-switch", "let", "do":
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
        lhs, err_lhs, ok_lhs := emit_expr(e, form.items[1])
        if !ok_lhs {
            return err_lhs, false
        }
        err_owned, bad_owned := owned_result_usage_error(form.items[2], true)
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
        strings.write_string(&e.builder, " = ")
        strings.write_string(&e.builder, rhs)
        record_current_line_fragment_map(e, len(lhs) + len(" = "), rhs, form.items[2].span)
        emit_raw_newline(e)
        return {}, true
    case "update!":
        return Compile_Error{message = "`update!` has moved to `core/update!`", span = form.items[0].span}, false
    case "core/update!", "core-update!":
        if len(form.items) < 3 {
            return Compile_Error{message = "core/update! expects place, updater, and optional arguments", span = form.span}, false
        }
        if !form_is_assignable_place(form.items[1]) {
            return Compile_Error{message = "core/update! expects an assignable place", span = form.items[1].span}, false
        }
        lhs, err_lhs, ok_lhs := emit_expr(e, form.items[1])
        if !ok_lhs {
            return err_lhs, false
        }
        return emit_update_place_assignment_stmt(e, lhs, lhs, form.items[1].span, form.items[2], form.items[3:])
    case "core/delete!", "core-delete!":
        if len(form.items) != 3 {
            return Compile_Error{message = "core/delete! expects target and key", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return err_target, false
        }
        key, err_key, ok_key := emit_expr(e, form.items[2])
        if !ok_key {
            return err_key, false
        }
        emit_line(e, emit_call_text("delete_key", []string{address_of_expr_text(target), key}))
        return {}, true
    case "doc":
        return Compile_Error{message = "`doc` has moved to `core/doc`", span = form.items[0].span}, false
    case "core/doc", "core-doc":
        if len(form.items) != 2 {
            return Compile_Error{message = "core/doc expects a quoted declaration name", span = form.span}, false
        }
        mark_core_fmt(e)
        name, ok_name := quoted_symbol_name(form.items[1])
        if !ok_name {
            return Compile_Error{message = "core/doc currently expects a quoted declaration name", span = form.items[1].span}, false
        }
        text, ok_doc := find_decl_doc_text(e, name)
        if !ok_doc {
            return Compile_Error{message = fmt.tprintf("unknown declaration: %s", name), span = form.items[1].span}, false
        }
        emit_line(e, fmt.tprintf("fmt.println(%q)", text))
        return {}, true
    case "loop":
        return Compile_Error{message = "`loop` has been removed; use `each` for collection iteration or `while` for condition loops", span = form.span}, false
    case "for":
        if last_in_proc && returns.kind != .None {
            expr, err_expr, ok_expr := emit_expr(e, form)
            if !ok_expr {
                return err_expr, false
            }
            emit_prefixed_expr_mapped(e, "return ", expr, form.span)
            return {}, true
        }
        return Compile_Error{message = "`for` is a comprehension; use `each` for collection loops or `while` for condition loops", span = form.span}, false
    case "each":
        if len(form.items) >= 3 && form.items[1].kind == .Vector {
            binding := form.items[1]
            body_start := 2
            if len(binding.items) == 2 && binding.items[0].kind == .Symbol {
                value_name := map_name(binding.items[0].text)
                coll_form := binding.items[1]
                body: [dynamic]CST_Form
                for item in form.items[body_start:] {
                    append(&body, item)
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
                return emit_for_in_loop(e, coll_form, first_name, second_name, body[:])
            }
            return Compile_Error{message = fmt.tprintf("%s expects [value collection] or [first second collection]", canonical_head_text), span = form.span}, false
        }
        return Compile_Error{message = "each expects [value collection] or [first second collection] and body", span = form.span}, false
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
        if !(form_produces_owned_value(form) && !allow_root_owned) {
            err_owned, bad_owned := owned_result_usage_error(form, allow_root_owned)
            if bad_owned {
                return err_owned, false
            }
        }
        expr, err_expr, ok_expr := emit_expr(e, form)
        if !ok_expr {
            return err_expr, false
        }
        if last_in_proc && returns.kind != .None {
            emit_prefixed_expr_mapped(e, "return ", expr, form.span)
        } else if form_is_owned_allocation_result(form) || form_is_owned_constructor_result(form) {
            emit_prefixed_expr_mapped(e, "_ = ", expr, form.span)
        } else {
            emit_prefixed_expr_mapped(e, "", expr, form.span)
        }
        return {}, true
    }
}

emit_eval_print_expr :: proc(e: ^Emitter, form: CST_Form) -> (Compile_Error, bool) {
    if form_is_owned_result(form) || form_is_owned_allocation_result(form) {
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

        emit_line(e, "{")
        e.indent += 1
        for binding in bindings {
            if binding_value_is_let(binding) {
                err_flat, ok_flat := emit_let_value_binding_assignment(e, binding)
                if !ok_flat {
                    return err_flat, false
                }
            } else if is_thread_form(binding.value, true) {
                err_thread, ok_thread := emit_thread_binding_assignment(e, binding, true)
                if !ok_thread {
                    return err_thread, false
                }
            } else if is_thread_form(binding.value, false) {
                err_thread, ok_thread := emit_thread_binding_assignment(e, binding, false)
                if !ok_thread {
                    return err_thread, false
                }
            } else {
                err_owned, bad_owned := owned_result_usage_error(binding.value, true)
                if bad_owned {
                    return err_owned, false
                }
                value, err_value, ok_value := emit_expr_for_expected_type(e, binding.value, binding.ty)
                if !ok_value {
                    return err_value, false
                }
                emit_binding_assignment(e, binding, value)
            }
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

emit_decl :: proc(e: ^Emitter, decl: IR_Decl) -> (Compile_Error, bool) {
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
        if decl_is_kvist_import(decl) {
            return Compile_Error{}, true
        }
        path_literal := resolved_import_path_literal_for_emit(decl.import_decl.path)
        if decl.import_decl.has_alias {
            emit_line(e, fmt.tprintf("import %s %s", decl.import_decl.alias, path_literal))
        } else {
            emit_line(e, fmt.tprintf("import %s", path_literal))
        }
    case .Const:
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
        emit_indent(e)
        strings.write_string(&e.builder, decl.struct_decl.name)
        strings.write_string(&e.builder, " :: struct {")
        emit_raw_newline(e)
        e.indent += 1
        for field in decl.struct_decl.fields {
            emit_line(e, fmt.tprintf("%s: %s,", field.name, field.ty))
        }
        e.indent -= 1
        emit_line(e, "}")
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
        analyze_owned_scope_body(e, decl.proc_decl.body[:], decl.proc_decl.returns.kind != .None, &proc_live)
        delete(proc_live)
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
            ty := decl.proc_decl.params[idx].ty
            fmt.sbprintf(&e.builder, "%s", decl.proc_decl.params[idx].name)
            next_idx := idx + 1
            for next_idx < len(decl.proc_decl.params) && decl.proc_decl.params[next_idx].ty == ty {
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
        clear(&e.pending_prefix_directives)
        clear(&e.pending_suffix_directives)
        strings.write_string(&e.builder, " {")
        emit_raw_newline(e)
        e.indent += 1
        err_body, ok_body := emit_body_forms(e, decl.proc_decl.body[:], decl.proc_decl.returns)
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
        return Compile_Error{message = fmt.tprintf("internal error: missing proc for captured callback specialization %s", spec.original_name)}, false
    }
    if spec.callback_param_index < 0 || spec.callback_param_index >= len(proc_decl.params) {
        return Compile_Error{message = "internal error: invalid callback specialization parameter index"}, false
    }

    callback_param := proc_decl.params[spec.callback_param_index]
    callback_ty, ok_callback_ty := proc_type_insert_capture_params_text(callback_param.ty, spec.capture_count)
    if !ok_callback_ty {
        return Compile_Error{message = fmt.tprintf("internal error: callback parameter %s is not a proc type", callback_param.name)}, false
    }
    defer delete(callback_ty)

    emit_indent(e)
    fmt.sbprintf(&e.builder, "%s :: proc(", captured_specialization_name(proc_decl.name, spec.callback_param_index, spec.capture_count))
    first := true
    for param, idx in proc_decl.params {
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
    for param in proc_decl.params {
        if param.name == callback_param.name {
            bind_local_type(e, param.name, callback_ty)
        } else {
            bind_local_type(e, param.name, param.ty)
        }
    }
    capture_names: [dynamic]string
    for capture_idx in 0..<spec.capture_count {
        append(&capture_names, fmt.tprintf("kvist_capture_%d", capture_idx+1))
    }
    bind_callback_context(e, callback_param.name, capture_names[:])
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

emit_core_map_helper :: proc(e: ^Emitter) {
    emit_line(e, "kvist_map :: proc(f: proc(x: $T) -> $U, xs: []T) -> [dynamic]U {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]U, 0, len(xs))")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "append(&out, f(x))")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_map_capture_helper :: proc(e: ^Emitter, capture_count: int) {
    params := capture_proc_param_text(capture_count, "x", "$T", "$U")
    defer delete(params)
    call_args := capture_call_arg_text(capture_count, "x")
    defer delete(call_args)
    emit_line(e, fmt.tprintf("%s :: proc(%s, xs: []T) -> [dynamic]U %s", capture_helper_name("kvist_map", capture_count), params, "{"))
    e.indent += 1
    emit_line(e, "out := make([dynamic]U, 0, len(xs))")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, fmt.tprintf("append(&out, f(%s))", call_args))
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_map_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("kvist_map_field_%s :: proc($Field_Type: typeid, xs: []$T) -> [dynamic]Field_Type %s", field, "{"))
    e.indent += 1
    emit_line(e, "out := make([dynamic]Field_Type, 0, len(xs))")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, fmt.tprintf("append(&out, x.%s)", field))
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_filter_helper :: proc(e: ^Emitter) {
    emit_line(e, "kvist_filter :: proc(pred: proc(x: $T) -> bool, xs: []T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T, 0, len(xs))")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "if pred(x) {")
    e.indent += 1
    emit_line(e, "append(&out, x)")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_filter_capture_helper :: proc(e: ^Emitter, capture_count: int) {
    params := capture_proc_param_text(capture_count, "x", "$T", "bool")
    defer delete(params)
    call_args := capture_call_arg_text(capture_count, "x")
    defer delete(call_args)
    emit_line(e, fmt.tprintf("%s :: proc(%s, xs: []T) -> [dynamic]T %s", capture_helper_name("kvist_filter", capture_count), params, "{"))
    e.indent += 1
    emit_line(e, "out := make([dynamic]T, 0, len(xs))")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, fmt.tprintf("if f(%s) %s", call_args, "{"))
    e.indent += 1
    emit_line(e, "append(&out, x)")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_filter_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("kvist_filter_field_%s :: proc(xs: []$T) -> [dynamic]T %s", field, "{"))
    e.indent += 1
    emit_line(e, "out := make([dynamic]T, 0, len(xs))")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, fmt.tprintf("if x.%s %s", field, "{"))
    e.indent += 1
    emit_line(e, "append(&out, x)")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_filter_in_place_helper :: proc(e: ^Emitter) {
    emit_line(e, "kvist_filter_in_place :: proc(pred: proc(x: $T) -> bool, xs: ^[dynamic]T) {")
    e.indent += 1
    emit_line(e, "data := xs^")
    emit_line(e, "write := 0")
    emit_line(e, "for x in data {")
    e.indent += 1
    emit_line(e, "if pred(x) {")
    e.indent += 1
    emit_line(e, "data[write] = x")
    emit_line(e, "write += 1")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "resize(xs, write)")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_filter_in_place_capture_helper :: proc(e: ^Emitter, capture_count: int) {
    params := capture_proc_param_text(capture_count, "x", "$T", "bool")
    defer delete(params)
    call_args := capture_call_arg_text(capture_count, "x")
    defer delete(call_args)
    emit_line(e, fmt.tprintf("%s :: proc(%s, xs: ^[dynamic]T) %s", capture_helper_name("kvist_filter_in_place", capture_count), params, "{"))
    e.indent += 1
    emit_line(e, "data := xs^")
    emit_line(e, "write := 0")
    emit_line(e, "for x in data {")
    e.indent += 1
    emit_line(e, fmt.tprintf("if f(%s) %s", call_args, "{"))
    e.indent += 1
    emit_line(e, "data[write] = x")
    emit_line(e, "write += 1")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "resize(xs, write)")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_filter_in_place_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("kvist_filter_in_place_field_%s :: proc(xs: ^[dynamic]$T) %s", field, "{"))
    e.indent += 1
    emit_line(e, "data := xs^")
    emit_line(e, "write := 0")
    emit_line(e, "for x in data {")
    e.indent += 1
    emit_line(e, fmt.tprintf("if x.%s %s", field, "{"))
    e.indent += 1
    emit_line(e, "data[write] = x")
    emit_line(e, "write += 1")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "resize(xs, write)")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_remove_helper :: proc(e: ^Emitter) {
    emit_line(e, "kvist_remove :: proc(pred: proc(x: $T) -> bool, xs: []T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T, 0, len(xs))")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "if !pred(x) {")
    e.indent += 1
    emit_line(e, "append(&out, x)")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_remove_capture_helper :: proc(e: ^Emitter, capture_count: int) {
    params := capture_proc_param_text(capture_count, "x", "$T", "bool")
    defer delete(params)
    call_args := capture_call_arg_text(capture_count, "x")
    defer delete(call_args)
    emit_line(e, fmt.tprintf("%s :: proc(%s, xs: []T) -> [dynamic]T %s", capture_helper_name("kvist_remove", capture_count), params, "{"))
    e.indent += 1
    emit_line(e, "out := make([dynamic]T, 0, len(xs))")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, fmt.tprintf("if !f(%s) %s", call_args, "{"))
    e.indent += 1
    emit_line(e, "append(&out, x)")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_remove_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("kvist_remove_field_%s :: proc(xs: []$T) -> [dynamic]T %s", field, "{"))
    e.indent += 1
    emit_line(e, "out := make([dynamic]T, 0, len(xs))")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, fmt.tprintf("if !x.%s %s", field, "{"))
    e.indent += 1
    emit_line(e, "append(&out, x)")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_remove_in_place_helper :: proc(e: ^Emitter) {
    emit_line(e, "kvist_remove_in_place :: proc(pred: proc(x: $T) -> bool, xs: ^[dynamic]T) {")
    e.indent += 1
    emit_line(e, "data := xs^")
    emit_line(e, "write := 0")
    emit_line(e, "for x in data {")
    e.indent += 1
    emit_line(e, "if !pred(x) {")
    e.indent += 1
    emit_line(e, "data[write] = x")
    emit_line(e, "write += 1")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "resize(xs, write)")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_remove_in_place_capture_helper :: proc(e: ^Emitter, capture_count: int) {
    params := capture_proc_param_text(capture_count, "x", "$T", "bool")
    defer delete(params)
    call_args := capture_call_arg_text(capture_count, "x")
    defer delete(call_args)
    emit_line(e, fmt.tprintf("%s :: proc(%s, xs: ^[dynamic]T) %s", capture_helper_name("kvist_remove_in_place", capture_count), params, "{"))
    e.indent += 1
    emit_line(e, "data := xs^")
    emit_line(e, "write := 0")
    emit_line(e, "for x in data {")
    e.indent += 1
    emit_line(e, fmt.tprintf("if !f(%s) %s", call_args, "{"))
    e.indent += 1
    emit_line(e, "data[write] = x")
    emit_line(e, "write += 1")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "resize(xs, write)")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_remove_in_place_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("kvist_remove_in_place_field_%s :: proc(xs: ^[dynamic]$T) %s", field, "{"))
    e.indent += 1
    emit_line(e, "data := xs^")
    emit_line(e, "write := 0")
    emit_line(e, "for x in data {")
    e.indent += 1
    emit_line(e, fmt.tprintf("if !x.%s %s", field, "{"))
    e.indent += 1
    emit_line(e, "data[write] = x")
    emit_line(e, "write += 1")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "resize(xs, write)")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_map_in_place_helper :: proc(e: ^Emitter) {
    emit_line(e, "kvist_map_in_place :: proc(f: proc(x: $T) -> T, xs: []T) {")
    e.indent += 1
    emit_line(e, "for i in 0..<len(xs) {")
    e.indent += 1
    emit_line(e, "xs[i] = f(xs[i])")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_map_in_place_capture_helper :: proc(e: ^Emitter, capture_count: int) {
    params := capture_proc_param_text(capture_count, "x", "$T", "T")
    defer delete(params)
    call_args := capture_call_arg_text(capture_count, "xs[i]")
    defer delete(call_args)
    emit_line(e, fmt.tprintf("%s :: proc(%s, xs: []T) %s", capture_helper_name("kvist_map_in_place", capture_count), params, "{"))
    e.indent += 1
    emit_line(e, "for i in 0..<len(xs) {")
    e.indent += 1
    emit_line(e, fmt.tprintf("xs[i] = f(%s)", call_args))
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_keep_helper :: proc(e: ^Emitter) {
    emit_line(e, "kvist_keep :: proc(f: proc(x: $T) -> ($U, bool), xs: []T) -> [dynamic]U {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]U, 0, len(xs))")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "value, ok := f(x)")
    emit_line(e, "if ok {")
    e.indent += 1
    emit_line(e, "append(&out, value)")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_keep_capture_helper :: proc(e: ^Emitter, capture_count: int) {
    params := capture_proc_param_text(capture_count, "x", "$T", "($U, bool)")
    defer delete(params)
    call_args := capture_call_arg_text(capture_count, "x")
    defer delete(call_args)
    emit_line(e, fmt.tprintf("%s :: proc(%s, xs: []T) -> [dynamic]U %s", capture_helper_name("kvist_keep", capture_count), params, "{"))
    e.indent += 1
    emit_line(e, "out := make([dynamic]U, 0, len(xs))")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, fmt.tprintf("value, ok := f(%s)", call_args))
    emit_line(e, "if ok {")
    e.indent += 1
    emit_line(e, "append(&out, value)")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_keep_in_place_helper :: proc(e: ^Emitter) {
    emit_line(e, "kvist_keep_in_place :: proc(f: proc(x: $T) -> (T, bool), xs: ^[dynamic]T) {")
    e.indent += 1
    emit_line(e, "data := xs^")
    emit_line(e, "write := 0")
    emit_line(e, "for x in data {")
    e.indent += 1
    emit_line(e, "value, ok := f(x)")
    emit_line(e, "if ok {")
    e.indent += 1
    emit_line(e, "data[write] = value")
    emit_line(e, "write += 1")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "resize(xs, write)")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_keep_in_place_capture_helper :: proc(e: ^Emitter, capture_count: int) {
    params := capture_proc_param_text(capture_count, "x", "$T", "(T, bool)")
    defer delete(params)
    call_args := capture_call_arg_text(capture_count, "x")
    defer delete(call_args)
    emit_line(e, fmt.tprintf("%s :: proc(%s, xs: ^[dynamic]T) %s", capture_helper_name("kvist_keep_in_place", capture_count), params, "{"))
    e.indent += 1
    emit_line(e, "data := xs^")
    emit_line(e, "write := 0")
    emit_line(e, "for x in data {")
    e.indent += 1
    emit_line(e, fmt.tprintf("value, ok := f(%s)", call_args))
    emit_line(e, "if ok {")
    e.indent += 1
    emit_line(e, "data[write] = value")
    emit_line(e, "write += 1")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "resize(xs, write)")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_concat_helper :: proc(e: ^Emitter) {
    emit_line(e, "kvist_concat :: proc(xs, ys: []$T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T, 0, len(xs)+len(ys))")
    emit_line(e, "append(&out, ..xs)")
    emit_line(e, "append(&out, ..ys)")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
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

emit_core_into_helper :: proc(e: ^Emitter) {
    emit_line(e, "kvist_into :: proc($Out: typeid, xs: []$T) -> Out {")
    e.indent += 1
    emit_line(e, "out := make(Out, 0, len(xs))")
    emit_line(e, "append(&out, ..xs)")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_sort_by_helper :: proc(e: ^Emitter) {
    emit_line(e, "kvist_sort_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T, 0, len(xs))")
    emit_line(e, "append(&out, ..xs)")
    emit_line(e, "kvist_slice.sort_by_with_data(out[:], proc(a, b: T, user_data: rawptr) -> bool {")
    e.indent += 1
    emit_line(e, "key := (proc(x: T) -> K)(user_data)")
    emit_line(e, "return key(a) < key(b)")
    e.indent -= 1
    emit_line(e, "}, rawptr(f))")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_sort_by_in_place_helper :: proc(e: ^Emitter) {
    emit_line(e, "kvist_sort_by_in_place :: proc(f: proc(x: $T) -> $K, xs: []T) {")
    e.indent += 1
    emit_line(e, "kvist_slice.sort_by_with_data(xs, proc(a, b: T, user_data: rawptr) -> bool {")
    e.indent += 1
    emit_line(e, "key := (proc(x: T) -> K)(user_data)")
    emit_line(e, "return key(a) < key(b)")
    e.indent -= 1
    emit_line(e, "}, rawptr(f))")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_sort_by_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("kvist_sort_by_field_%s :: proc($Key: typeid, xs: []$T) -> [dynamic]T %s", field, "{"))
    e.indent += 1
    emit_line(e, "out := make([dynamic]T, 0, len(xs))")
    emit_line(e, "append(&out, ..xs)")
    emit_line(e, "kvist_slice.sort_by(out[:], proc(a, b: T) -> bool {")
    e.indent += 1
    emit_line(e, fmt.tprintf("return a.%s < b.%s", field, field))
    e.indent -= 1
    emit_line(e, "})")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_sort_by_in_place_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("kvist_sort_by_in_place_field_%s :: proc(xs: []$T) %s", field, "{"))
    e.indent += 1
    emit_line(e, "kvist_slice.sort_by(xs, proc(a, b: T) -> bool {")
    e.indent += 1
    emit_line(e, fmt.tprintf("return a.%s < b.%s", field, field))
    e.indent -= 1
    emit_line(e, "})")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_sort_by_callback_helper :: proc(e: ^Emitter, callback: string) {
    emit_line(e, fmt.tprintf("%s :: proc(xs: []$T) -> [dynamic]T %s", sort_by_callback_helper_name(callback), "{"))
    e.indent += 1
    emit_line(e, "out := make([dynamic]T, 0, len(xs))")
    emit_line(e, "append(&out, ..xs)")
    emit_line(e, "kvist_slice.sort_by(out[:], proc(a, b: T) -> bool {")
    e.indent += 1
    emit_line(e, fmt.tprintf("return %s(a) < %s(b)", callback, callback))
    e.indent -= 1
    emit_line(e, "})")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_sort_by_in_place_callback_helper :: proc(e: ^Emitter, callback: string) {
    emit_line(e, fmt.tprintf("%s :: proc(xs: []$T) %s", sort_by_callback_helper_name(callback, true), "{"))
    e.indent += 1
    emit_line(e, "kvist_slice.sort_by(xs, proc(a, b: T) -> bool {")
    e.indent += 1
    emit_line(e, fmt.tprintf("return %s(a) < %s(b)", callback, callback))
    e.indent -= 1
    emit_line(e, "})")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_partition_by_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("kvist_partition_by_field_%s :: proc($Key: typeid, xs: []$T) -> [dynamic][]T %s", field, "{"))
    e.indent += 1
    emit_line(e, "if len(xs) == 0 {")
    e.indent += 1
    emit_line(e, "return make([dynamic][]T)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "out := make([dynamic][]T, 0, len(xs))")
    emit_line(e, "start := 0")
    emit_line(e, fmt.tprintf("last_key := xs[0].%s", field))
    emit_line(e, "for i := 1; i < len(xs); i += 1 {")
    e.indent += 1
    emit_line(e, fmt.tprintf("key := xs[i].%s", field))
    emit_line(e, "if key != last_key {")
    e.indent += 1
    emit_line(e, "append(&out, xs[start:i])")
    emit_line(e, "start = i")
    emit_line(e, "last_key = key")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "append(&out, xs[start:])")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_index_by_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("kvist_index_by_field_%s :: proc($Key: typeid, xs: []$T) -> map[Key]T %s", field, "{"))
    e.indent += 1
    emit_line(e, "out := make(map[Key]T, len(xs))")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, fmt.tprintf("out[x.%s] = x", field))
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_group_by_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("kvist_group_by_field_%s :: proc($Key: typeid, xs: []$T) -> map[Key][dynamic]T %s", field, "{"))
    e.indent += 1
    emit_line(e, "out := make(map[Key][dynamic]T)")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, fmt.tprintf("key := x.%s", field))
    emit_line(e, "group := out[key]")
    emit_line(e, "append(&group, x)")
    emit_line(e, "if len(group) == 8 {")
    e.indent += 1
    emit_line(e, "reserve(&group, 64)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "out[key] = group")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_count_by_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("kvist_count_by_field_%s :: proc($Key: typeid, xs: []$T) -> map[Key]int %s", field, "{"))
    e.indent += 1
    emit_line(e, "out := make(map[Key]int)")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, fmt.tprintf("out[x.%s] += 1", field))
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_sum_by_field_helper :: proc(e: ^Emitter, fields: Sum_By_Field) {
    emit_line(e, fmt.tprintf("kvist_sum_by_fields_%s_%s :: proc($Key: typeid, $Value: typeid, xs: []$T) -> map[Key]Value %s", fields.key, fields.value, "{"))
    e.indent += 1
    emit_line(e, "out := make(map[Key]Value)")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, fmt.tprintf("out[x.%s] += x.%s", fields.key, fields.value))
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_distinct_by_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("kvist_distinct_by_field_%s :: proc($Key: typeid, xs: []$T) -> [dynamic]T %s", field, "{"))
    e.indent += 1
    emit_line(e, "out := make([dynamic]T, 0, len(xs))")
    emit_line(e, "seen := make(map[Key]bool, len(xs))")
    emit_line(e, "defer delete(seen)")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, fmt.tprintf("key := x.%s", field))
    emit_line(e, "if seen[key] {")
    e.indent += 1
    emit_line(e, "continue")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "seen[key] = true")
    emit_line(e, "append(&out, x)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_tap_helper :: proc(e: ^Emitter) {
    emit_line(e, "kvist_tap :: proc(value: $T) -> T {")
    e.indent += 1
    emit_line(e, "fmt.println(value)")
    emit_line(e, "return value")
    e.indent -= 1
    emit_line(e, "}")
    emit_raw_newline(e)
    emit_line(e, "kvist_tap_labeled :: proc(label: string, value: $T) -> T {")
    e.indent += 1
    emit_line(e, "fmt.print(label)")
    emit_line(e, "fmt.print(\": \")")
    emit_line(e, "fmt.println(value)")
    emit_line(e, "return value")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_reduce_helper :: proc(e: ^Emitter) {
    emit_line(e, "kvist_reduce :: proc(f: proc(acc: $U, x: $T) -> U, init: U, xs: []T) -> U {")
    e.indent += 1
    emit_line(e, "acc := init")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "acc = f(acc, x)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return acc")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_take_while_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("kvist_take_while_field_%s :: proc(xs: []$T) -> []T %s", field, "{"))
    e.indent += 1
    emit_line(e, "for i in 0..<len(xs) {")
    e.indent += 1
    emit_line(e, fmt.tprintf("if !xs[i].%s %s", field, "{"))
    e.indent += 1
    emit_line(e, "return xs[:i]")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return xs")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_drop_while_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("kvist_drop_while_field_%s :: proc(xs: []$T) -> []T %s", field, "{"))
    e.indent += 1
    emit_line(e, "for i in 0..<len(xs) {")
    e.indent += 1
    emit_line(e, fmt.tprintf("if !xs[i].%s %s", field, "{"))
    e.indent += 1
    emit_line(e, "return xs[i:]")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return xs[len(xs):]")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_find_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("kvist_find_field_%s :: proc(xs: []$T) -> (value: T, ok: bool) %s", field, "{"))
    e.indent += 1
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, fmt.tprintf("if x.%s %s", field, "{"))
    e.indent += 1
    emit_line(e, "return x, true")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return {}, false")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_some_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("kvist_some_p_field_%s :: proc(xs: []$T) -> bool %s", field, "{"))
    e.indent += 1
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, fmt.tprintf("if x.%s %s", field, "{"))
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

emit_core_every_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("kvist_every_p_field_%s :: proc(xs: []$T) -> bool %s", field, "{"))
    e.indent += 1
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, fmt.tprintf("if !x.%s %s", field, "{"))
    e.indent += 1
    emit_line(e, "return false")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return true")
    e.indent -= 1
    emit_line(e, "}")
}

core_helpers_needed :: proc(features: Emitter_Features) -> bool {
    return features.core_map || features.core_map_capture_max > 0 || features.core_filter || features.core_filter_capture_max > 0 || features.core_reduce ||
           features.core_remove || features.core_remove_capture_max > 0 || features.core_keep || features.core_keep_capture_max > 0 ||
           features.core_concat ||
           features.core_get_or_default ||
           features.core_contains_value ||
           features.core_into ||
           features.core_map_in_place || features.core_map_in_place_capture_max > 0 ||
           features.core_filter_in_place || features.core_filter_in_place_capture_max > 0 ||
           features.core_remove_in_place || features.core_remove_in_place_capture_max > 0 ||
           features.core_keep_in_place || features.core_keep_in_place_capture_max > 0 ||
           features.core_sort_by ||
           features.core_sort_by_in_place ||
           features.core_tap ||
           len(features.map_fields) > 0 || len(features.index_by_fields) > 0 ||
           len(features.group_by_fields) > 0 ||
           len(features.count_by_fields) > 0 ||
           len(features.sum_by_fields) > 0 ||
           len(features.distinct_by_fields) > 0 ||
           len(features.partition_by_fields) > 0 ||
           len(features.sort_by_fields) > 0 ||
           len(features.sort_by_in_place_fields) > 0 ||
           len(features.sort_by_callbacks) > 0 ||
           len(features.sort_by_in_place_callbacks) > 0 ||
           len(features.filter_fields) > 0 ||
           len(features.filter_in_place_fields) > 0 ||
           len(features.remove_fields) > 0 ||
           len(features.remove_in_place_fields) > 0 ||
           len(features.take_while_fields) > 0 || len(features.drop_while_fields) > 0 ||
           len(features.find_fields) > 0 || len(features.some_fields) > 0 ||
           len(features.every_fields) > 0
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
    if features.core_map {
        emit_core_helper_separator(e, &emitted)
        emit_core_map_helper(e)
    }
    for capture_count in 1..=features.core_map_capture_max {
        emit_core_helper_separator(e, &emitted)
        emit_core_map_capture_helper(e, capture_count)
    }
    for field in features.map_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_map_field_helper(e, field)
    }
    if features.core_filter {
        emit_core_helper_separator(e, &emitted)
        emit_core_filter_helper(e)
    }
    for capture_count in 1..=features.core_filter_capture_max {
        emit_core_helper_separator(e, &emitted)
        emit_core_filter_capture_helper(e, capture_count)
    }
    for field in features.filter_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_filter_field_helper(e, field)
    }
    if features.core_filter_in_place {
        emit_core_helper_separator(e, &emitted)
        emit_core_filter_in_place_helper(e)
    }
    for capture_count in 1..=features.core_filter_in_place_capture_max {
        emit_core_helper_separator(e, &emitted)
        emit_core_filter_in_place_capture_helper(e, capture_count)
    }
    for field in features.filter_in_place_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_filter_in_place_field_helper(e, field)
    }
    if features.core_remove {
        emit_core_helper_separator(e, &emitted)
        emit_core_remove_helper(e)
    }
    for capture_count in 1..=features.core_remove_capture_max {
        emit_core_helper_separator(e, &emitted)
        emit_core_remove_capture_helper(e, capture_count)
    }
    for field in features.remove_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_remove_field_helper(e, field)
    }
    if features.core_remove_in_place {
        emit_core_helper_separator(e, &emitted)
        emit_core_remove_in_place_helper(e)
    }
    for capture_count in 1..=features.core_remove_in_place_capture_max {
        emit_core_helper_separator(e, &emitted)
        emit_core_remove_in_place_capture_helper(e, capture_count)
    }
    for field in features.remove_in_place_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_remove_in_place_field_helper(e, field)
    }
    if features.core_map_in_place {
        emit_core_helper_separator(e, &emitted)
        emit_core_map_in_place_helper(e)
    }
    for capture_count in 1..=features.core_map_in_place_capture_max {
        emit_core_helper_separator(e, &emitted)
        emit_core_map_in_place_capture_helper(e, capture_count)
    }
    if features.core_keep {
        emit_core_helper_separator(e, &emitted)
        emit_core_keep_helper(e)
    }
    for capture_count in 1..=features.core_keep_capture_max {
        emit_core_helper_separator(e, &emitted)
        emit_core_keep_capture_helper(e, capture_count)
    }
    if features.core_keep_in_place {
        emit_core_helper_separator(e, &emitted)
        emit_core_keep_in_place_helper(e)
    }
    for capture_count in 1..=features.core_keep_in_place_capture_max {
        emit_core_helper_separator(e, &emitted)
        emit_core_keep_in_place_capture_helper(e, capture_count)
    }
    if features.core_concat {
        emit_core_helper_separator(e, &emitted)
        emit_core_concat_helper(e)
    }
    if features.core_get_or_default {
        emit_core_helper_separator(e, &emitted)
        emit_core_get_or_default_helper(e)
    }
    if features.core_contains_value {
        emit_core_helper_separator(e, &emitted)
        emit_core_contains_value_helper(e)
    }
    if features.core_into {
        emit_core_helper_separator(e, &emitted)
        emit_core_into_helper(e)
    }
    if features.core_sort_by {
        emit_core_helper_separator(e, &emitted)
        emit_core_sort_by_helper(e)
    }
    if features.core_sort_by_in_place {
        emit_core_helper_separator(e, &emitted)
        emit_core_sort_by_in_place_helper(e)
    }
    for callback in features.sort_by_callbacks {
        emit_core_helper_separator(e, &emitted)
        emit_core_sort_by_callback_helper(e, callback)
    }
    for callback in features.sort_by_in_place_callbacks {
        emit_core_helper_separator(e, &emitted)
        emit_core_sort_by_in_place_callback_helper(e, callback)
    }
    for field in features.sort_by_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_sort_by_field_helper(e, field)
    }
    for field in features.sort_by_in_place_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_sort_by_in_place_field_helper(e, field)
    }
    for field in features.partition_by_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_partition_by_field_helper(e, field)
    }
    for field in features.index_by_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_index_by_field_helper(e, field)
    }
    for field in features.group_by_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_group_by_field_helper(e, field)
    }
    for field in features.count_by_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_count_by_field_helper(e, field)
    }
    for fields in features.sum_by_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_sum_by_field_helper(e, fields)
    }
    for field in features.distinct_by_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_distinct_by_field_helper(e, field)
    }
    if features.core_tap {
        emit_core_helper_separator(e, &emitted)
        emit_core_tap_helper(e)
    }
    if features.core_reduce {
        emit_core_helper_separator(e, &emitted)
        emit_core_reduce_helper(e)
    }
    for field in features.take_while_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_take_while_field_helper(e, field)
    }
    for field in features.drop_while_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_drop_while_field_helper(e, field)
    }
    for field in features.find_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_find_field_helper(e, field)
    }
    for field in features.some_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_some_field_helper(e, field)
    }
    for field in features.every_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_every_field_helper(e, field)
    }
}

emit_decls :: proc(decls: []IR_Decl) -> (string, Compile_Error, bool) {
    result, err, ok := emit_decls_with_source_map(decls)
    return result.output, err, ok
}

form_uses_core_slice_sort :: proc(form: CST_Form) -> bool {
    if form.kind == .List && len(form.items) > 0 {
        head := form.items[0]
        if head.kind == .Symbol {
            switch head.text {
            case "arr/sort", "arr/sort!", "arr/sort-by", "arr/sort-by!":
                return true
            }
        }
    }
    for item in form.items {
        if form_uses_core_slice_sort(item) {
            return true
        }
    }
    return false
}

decl_uses_core_slice_sort :: proc(decl: IR_Decl) -> bool {
    #partial switch decl.kind {
    case .Const:
        return form_uses_core_slice_sort(decl.const_decl.value)
    case .Var:
        return form_uses_core_slice_sort(decl.var_decl.value)
    case .Enum:
        for variant in decl.enum_decl.variants {
            if variant.has_value && form_uses_core_slice_sort(variant.value) {
                return true
            }
        }
    case .Proc:
        for form in decl.proc_decl.body {
            if form_uses_core_slice_sort(form) {
                return true
            }
        }
    }
    return false
}

decls_need_core_slice_sort_import :: proc(decls: []IR_Decl) -> bool {
    for decl in decls {
        if decl.kind == .Import &&
           decl.import_decl.has_alias &&
           decl.import_decl.alias == "kvist_slice" &&
           decl.import_decl.path == "\"core:slice\"" {
            return false
        }
    }
    for decl in decls {
        if decl_uses_core_slice_sort(decl) {
            return true
        }
    }
    return false
}

form_uses_core_strings :: proc(form: CST_Form) -> bool {
    if form.kind == .Symbol {
        return strings.has_prefix(form.text, "strings.") || strings.has_prefix(form.text, "strings/")
    }
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if form.items[0].text == "str/contains?" ||
           form.items[0].text == "str/split" ||
           form.items[0].text == "str-split" ||
           form.items[0].text == "str/join" ||
           form.items[0].text == "str-join" ||
           form.items[0].text == "str/trim" ||
           form.items[0].text == "str/trim-prefix" ||
           form.items[0].text == "str/trim-suffix" ||
           form.items[0].text == "str/starts-with?" ||
           form.items[0].text == "str/ends-with?" ||
           form.items[0].text == "str/index-of" ||
           form.items[0].text == "str/last-index-of" ||
           form.items[0].text == "str/replace" ||
           form.items[0].text == "str-replace" ||
           form.items[0].text == "str/lower" ||
           form.items[0].text == "str/upper" ||
           strings.has_prefix(form.items[0].text, "strings.") ||
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
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if form.items[0].text == "core/println" ||
           form.items[0].text == "core-println" ||
           form.items[0].text == "core/doc" ||
           form.items[0].text == "core-doc" {
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
    for decl in decls {
        if decl.kind == .Import {
            if (!decl.import_decl.has_alias && decl.import_decl.path == "\"core:fmt\"") ||
               (decl.import_decl.has_alias && decl.import_decl.alias == "fmt" && decl.import_decl.path == "\"core:fmt\"") {
                return false
            }
        }
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

emit_core_slice_sort_import :: proc(e: ^Emitter, emitted: ^bool, needed: bool) {
    if !needed || emitted^ {
        return
    }
    emit_line(e, "import kvist_slice \"core:slice\"")
    strings.write_byte(&e.builder, '\n')
    e.line += 1
    emitted^ = true
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

features_need_core_slice_sort_import :: proc(features: Emitter_Features) -> bool {
    return features.core_sort_by ||
           features.core_sort_by_in_place ||
           len(features.sort_by_fields) > 0 ||
           len(features.sort_by_in_place_fields) > 0 ||
           len(features.sort_by_callbacks) > 0 ||
           len(features.sort_by_in_place_callbacks) > 0
}

features_need_core_strings_import :: proc(features: Emitter_Features) -> bool {
    return features.core_strings
}

features_need_core_fmt_import :: proc(features: Emitter_Features) -> bool {
    return features.core_fmt
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
    for decl in decls {
        if decl.kind == .Struct {
            append(&e.structs, decl.struct_decl)
        }
        if decl.kind == .Union {
            append(&e.unions, decl.union_decl)
        }
    }
    needs_core_slice_import := decls_need_core_slice_sort_import(decls)
    needs_core_strings_import := decls_need_core_strings_import(decls)
    needs_core_fmt_import := decls_need_core_fmt_import(decls)
    emitted_core_slice_import := false
    emitted_core_strings_import := false
    emitted_core_fmt_import := false
    for decl, idx in decls {
        if decl.kind != .Package && decl.kind != .Import {
            emit_core_slice_sort_import(&e, &emitted_core_slice_import, needs_core_slice_import)
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
    emit_core_slice_sort_import(&e, &emitted_core_slice_import, needs_core_slice_import)
    emit_core_strings_import(&e, &emitted_core_strings_import, needs_core_strings_import)
    emit_core_fmt_import(&e, &emitted_core_fmt_import, needs_core_fmt_import)
    err_specializations, ok_specializations := emit_captured_proc_specializations(&e)
    if !ok_specializations {
        return result, err_specializations, false
    }
    emit_core_helpers(&e, features)
    output := strings.clone(strings.to_string(e.builder))
    late_imports: [dynamic]string
    if !emitted_core_slice_import && features_need_core_slice_sort_import(features) &&
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
    for decl in decls {
        if decl.kind == .Struct {
            append(&e.structs, decl.struct_decl)
        }
        if decl.kind == .Union {
            append(&e.unions, decl.union_decl)
        }
    }
    needs_core_slice_import := decls_need_core_slice_sort_import(decls) ||
                             form_uses_core_slice_sort(eval_form)
    needs_core_strings_import := decls_need_core_strings_import(decls) ||
                                 form_uses_core_strings(eval_form)
    needs_core_fmt_import := decls_need_core_fmt_import(decls) ||
                             form_uses_core_fmt(eval_form)
    emitted_core_slice_import := false
    emitted_core_strings_import := false
    emitted_core_fmt_import := false
    for decl, idx in decls {
        if decl.kind != .Package && decl.kind != .Import {
            emit_core_slice_sort_import(&e, &emitted_core_slice_import, needs_core_slice_import)
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
    emit_core_slice_sort_import(&e, &emitted_core_slice_import, needs_core_slice_import)
    emit_core_strings_import(&e, &emitted_core_strings_import, needs_core_strings_import)
    emit_core_fmt_import(&e, &emitted_core_fmt_import, needs_core_fmt_import)

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
    if !emitted_core_slice_import && features_need_core_slice_sort_import(features) &&
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
               a.import_decl.has_alias == b.import_decl.has_alias
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
