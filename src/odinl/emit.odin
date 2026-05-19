package odinl

import "core:fmt"
import "core:strings"

Emitter_Features :: struct {
    dynamic_literals: bool,
    core_map:         bool,
    core_filter:      bool,
    core_reduce:      bool,
    core_take:        bool,
    core_drop:        bool,
    core_drop_last:   bool,
    core_take_while:  bool,
    core_drop_while:  bool,
    core_find:        bool,
    core_some:        bool,
    core_every:       bool,
    core_remove:      bool,
    core_map_indexed: bool,
    core_keep:        bool,
    core_mapcat:      bool,
    core_concat:      bool,
    core_merge:       bool,
    core_merge_in_place: bool,
    core_get_or_default: bool,
    core_into:        bool,
    core_interpose:   bool,
    core_interleave:  bool,
    core_reverse:     bool,
    core_reverse_in_place: bool,
    core_shuffle:     bool,
    core_shuffle_in_place: bool,
    core_map_in_place: bool,
    core_map_indexed_in_place: bool,
    core_filter_in_place: bool,
    core_remove_in_place: bool,
    core_keep_in_place: bool,
    core_sort:        bool,
    core_sort_by:     bool,
    core_sort_in_place: bool,
    core_sort_by_in_place: bool,
    core_split_at:    bool,
    core_partition:   bool,
    core_partition_all: bool,
    core_partition_by: bool,
    core_zipmap:      bool,
    core_index_by:    bool,
    core_group_by:    bool,
    core_frequencies: bool,
    core_keys:        bool,
    core_vals:        bool,
    core_distinct:    bool,
    core_distinct_by: bool,
    core_range:       bool,
    core_repeat:      bool,
    core_repeatedly:  bool,
    core_iterate:     bool,
    core_cycle:       bool,
    core_save_json:   bool,
    core_load_json:   bool,
    core_tap:         bool,
    map_fields:       [dynamic]string,
    index_by_fields:  [dynamic]string,
    group_by_fields:  [dynamic]string,
    distinct_by_fields: [dynamic]string,
    partition_by_fields: [dynamic]string,
    sort_by_fields:   [dynamic]string,
    sort_by_in_place_fields: [dynamic]string,
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
    unions:                    [dynamic]Union_Decl,
    features:                  ^Emitter_Features,
    line:                      int,
    temp_counter:              int,
    attach_next_decl:          bool,
    pending_prefix_directives: [dynamic]string,
    pending_suffix_directives: [dynamic]string,
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

mark_core_map :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_map = true
    }
}

mark_core_filter :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_filter = true
    }
}

mark_core_reduce :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_reduce = true
    }
}

mark_core_take :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_take = true
    }
}

mark_core_drop :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_drop = true
    }
}

mark_core_drop_last :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_drop_last = true
    }
}

mark_core_take_while :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_take_while = true
    }
}

mark_core_drop_while :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_drop_while = true
    }
}

mark_core_find :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_find = true
    }
}

mark_core_some :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_some = true
    }
}

mark_core_every :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_every = true
    }
}

mark_core_remove :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_remove = true
    }
}

mark_core_map_indexed :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_map_indexed = true
    }
}

mark_core_keep :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_keep = true
    }
}

mark_core_mapcat :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_mapcat = true
    }
}

mark_core_concat :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_concat = true
    }
}

mark_core_merge :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_merge = true
    }
}

mark_core_merge_in_place :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_merge_in_place = true
    }
}

mark_core_get_or_default :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_get_or_default = true
    }
}

mark_core_into :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_into = true
    }
}

mark_core_interpose :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_interpose = true
    }
}

mark_core_interleave :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_interleave = true
    }
}

mark_core_reverse :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_reverse = true
    }
}

mark_core_reverse_in_place :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_reverse_in_place = true
    }
}

mark_core_shuffle :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_shuffle = true
    }
}

mark_core_shuffle_in_place :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_shuffle_in_place = true
    }
}

mark_core_map_in_place :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_map_in_place = true
    }
}

mark_core_map_indexed_in_place :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_map_indexed_in_place = true
    }
}

mark_core_filter_in_place :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_filter_in_place = true
    }
}

mark_core_remove_in_place :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_remove_in_place = true
    }
}

mark_core_keep_in_place :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_keep_in_place = true
    }
}

mark_core_sort :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_sort = true
    }
}

mark_core_sort_by :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_sort_by = true
    }
}

mark_core_sort_in_place :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_sort_in_place = true
    }
}

mark_core_sort_by_in_place :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_sort_by_in_place = true
    }
}

mark_core_split_at :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_split_at = true
    }
}

mark_core_partition :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_partition = true
    }
}

mark_core_partition_all :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_partition_all = true
    }
}

mark_core_partition_by :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_partition_by = true
    }
}

mark_core_zipmap :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_zipmap = true
    }
}

mark_core_index_by :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_index_by = true
    }
}

mark_core_group_by :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_group_by = true
    }
}

mark_core_frequencies :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_frequencies = true
    }
}

mark_core_keys :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_keys = true
    }
}

mark_core_vals :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_vals = true
    }
}

mark_core_distinct :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_distinct = true
    }
}

mark_core_distinct_by :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_distinct_by = true
    }
}

mark_core_range :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_range = true
    }
}

mark_core_repeat :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_repeat = true
    }
}

mark_core_repeatedly :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_repeatedly = true
    }
}

mark_core_iterate :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_iterate = true
    }
}

mark_core_cycle :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_cycle = true
    }
}

mark_core_save_json :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_save_json = true
    }
}

mark_core_load_json :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_load_json = true
    }
}

mark_core_tap :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_tap = true
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

emit_brace_pair_texts :: proc(e: ^Emitter, form: CST_Form) -> (pairs: [dynamic]Brace_Pair, err: Compile_Error, ok: bool) {
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
            append(&pairs, Brace_Pair{key = map_name(key.text[1:]), value = value_text})
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

emit_brace_pairs :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    pairs, err_pairs, ok_pairs := emit_brace_pair_texts(e, form)
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
               len(form.text) >= 9 && form.text[:9] == "[dynamic]"
    }
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    return form.items[0].text == "map" || form.items[0].text == "dynamic"
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
    pairs, err_pairs, ok_pairs := emit_brace_pair_texts(e, form)
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
        inner, err_inner, ok_inner := emit_brace_pairs(e, form)
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

emit_thread_step :: proc(e: ^Emitter, current: string, step: CST_Form, thread_last: bool) -> (string, Compile_Error, bool) {
    #partial switch step.kind {
    case .Keyword:
        return fmt.tprintf("%s.%s", current, map_name(step.text[1:])), {}, true
    case .Symbol:
        if thread_last && step.text == "slice" {
            return slice_all_expr_text(current), {}, true
        }
        args: [dynamic]string
        append(&args, current)
        return emit_call_text(map_name(step.text), args[:]), {}, true
    case .List:
        if len(step.items) == 0 {
            return "", Compile_Error{message = "thread step cannot be an empty list", span = step.span}, false
        }
        head := step.items[0]
        if head.kind == .Keyword {
            if len(step.items) != 1 {
                return "", Compile_Error{message = "keyword thread step does not take arguments", span = step.span}, false
            }
            return fmt.tprintf("%s.%s", current, map_name(head.text[1:])), {}, true
        }
        if head.kind != .Symbol {
            return "", Compile_Error{message = "thread list step expects symbol or keyword head", span = head.span}, false
        }
        if head.text == "tap>" {
            if len(step.items) > 2 {
                return "", Compile_Error{message = "tap> thread step expects optional label", span = step.span}, false
            }
            mark_core_tap(e)
            if len(step.items) == 1 {
                return emit_call_text("odinl_tap", []string{current}), {}, true
            }
            label_form := step.items[1]
            label := ""
            if label_form.kind == .Keyword {
                label = fmt.tprintf("\"%s\"", label_form.text[1:])
            } else if label_form.kind == .String {
                label = label_form.text
            } else {
                return "", Compile_Error{message = "tap> label must be a keyword or string literal", span = label_form.span}, false
            }
            return emit_call_text("odinl_tap_labeled", []string{label, current}), {}, true
        }
        if thread_last && (head.text == "map" || head.text == "filter" || head.text == "remove") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects one function argument", head.text), span = step.span}, false
            }
            collection := slice_all_expr_text(current)
            if head.text == "map" {
                return emit_map_callback_call(e, step.items[1], collection)
            }
            if head.text == "remove" {
                return emit_predicate_callback_call(e, "odinl_remove", step.items[1], collection, mark_core_remove, mark_core_remove_field)
            }
            return emit_predicate_callback_call(e, "odinl_filter", step.items[1], collection, mark_core_filter, mark_core_filter_field)
        }
        if thread_last && (head.text == "map-indexed" || head.text == "keep" || head.text == "mapcat") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects one function argument", head.text), span = step.span}, false
            }
            f, err_f, ok_f := emit_expr(e, step.items[1])
            if !ok_f {
                return "", err_f, false
            }
            if head.text == "map-indexed" {
                mark_core_map_indexed(e)
                return emit_call_text("odinl_map_indexed", []string{f, slice_all_expr_text(current)}), {}, true
            }
            if head.text == "mapcat" {
                mark_core_mapcat(e)
                return emit_call_text("odinl_mapcat", []string{f, slice_all_expr_text(current)}), {}, true
            }
            mark_core_keep(e)
            return emit_call_text("odinl_keep", []string{f, slice_all_expr_text(current)}), {}, true
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
            return emit_call_text("odinl_concat", []string{slice_all_expr_text(current), slice_all_expr_text(rhs)}), {}, true
        }
        if thread_last && head.text == "into" {
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
            return emit_call_text("odinl_into", []string{type_text, slice_all_expr_text(current)}), {}, true
        }
        if thread_last && head.text == "interpose" {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "interpose thread step expects one separator argument", span = step.span}, false
            }
            sep, err_sep, ok_sep := emit_expr(e, step.items[1])
            if !ok_sep {
                return "", err_sep, false
            }
            mark_core_interpose(e)
            return emit_call_text("odinl_interpose", []string{sep, slice_all_expr_text(current)}), {}, true
        }
        if thread_last && head.text == "interleave" {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "interleave thread step expects one collection argument", span = step.span}, false
            }
            lhs, err_lhs, ok_lhs := emit_expr(e, step.items[1])
            if !ok_lhs {
                return "", err_lhs, false
            }
            mark_core_interleave(e)
            return emit_call_text("odinl_interleave", []string{slice_all_expr_text(lhs), slice_all_expr_text(current)}), {}, true
        }
        if thread_last && head.text == "reverse" {
            if len(step.items) != 1 {
                return "", Compile_Error{message = "reverse thread step expects no arguments", span = step.span}, false
            }
            mark_core_reverse(e)
            return emit_call_text("odinl_reverse", []string{slice_all_expr_text(current)}), {}, true
        }
        if thread_last && head.text == "shuffle" {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "shuffle thread step expects one picker function argument", span = step.span}, false
            }
            pick, err_pick, ok_pick := emit_expr(e, step.items[1])
            if !ok_pick {
                return "", err_pick, false
            }
            mark_core_shuffle(e)
            return emit_call_text("odinl_shuffle", []string{pick, slice_all_expr_text(current)}), {}, true
        }
        if thread_last && head.text == "sort" {
            if len(step.items) != 1 {
                return "", Compile_Error{message = "sort thread step expects no arguments", span = step.span}, false
            }
            mark_core_sort(e)
            return emit_call_text("odinl_sort", []string{slice_all_expr_text(current)}), {}, true
        }
        if thread_last && head.text == "sort-by" {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "sort-by thread step expects one key function argument", span = step.span}, false
            }
            return emit_sort_by_callback_call(e, step.items[1], slice_all_expr_text(current))
        }
        if thread_last && (head.text == "split-at" || head.text == "partition" || head.text == "partition-all") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects one count argument", head.text), span = step.span}, false
            }
            count, err_count, ok_count := emit_expr(e, step.items[1])
            if !ok_count {
                return "", err_count, false
            }
            if head.text == "split-at" {
                mark_core_split_at(e)
                return emit_call_text("odinl_split_at", []string{count, slice_all_expr_text(current)}), {}, true
            }
            if head.text == "partition" {
                mark_core_partition(e)
                return emit_call_text("odinl_partition", []string{count, slice_all_expr_text(current)}), {}, true
            }
            mark_core_partition_all(e)
            return emit_call_text("odinl_partition_all", []string{count, slice_all_expr_text(current)}), {}, true
        }
        if thread_last && head.text == "partition-by" {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "partition-by thread step expects one key function argument", span = step.span}, false
            }
            return emit_partition_by_callback_call(e, step.items[1], slice_all_expr_text(current))
        }
        if thread_last && head.text == "zipmap" {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "zipmap thread step expects one key collection argument", span = step.span}, false
            }
            keys, err_keys, ok_keys := emit_expr(e, step.items[1])
            if !ok_keys {
                return "", err_keys, false
            }
            mark_core_zipmap(e)
            return emit_call_text("odinl_zipmap", []string{slice_all_expr_text(keys), slice_all_expr_text(current)}), {}, true
        }
        if thread_last && head.text == "index-by" {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "index-by thread step expects one key function argument", span = step.span}, false
            }
            return emit_index_by_callback_call(e, step.items[1], slice_all_expr_text(current))
        }
        if thread_last && head.text == "group-by" {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "group-by thread step expects one key function argument", span = step.span}, false
            }
            return emit_group_by_callback_call(e, step.items[1], slice_all_expr_text(current))
        }
        if thread_last && head.text == "frequencies" {
            if len(step.items) != 1 {
                return "", Compile_Error{message = "frequencies thread step expects no arguments", span = step.span}, false
            }
            mark_core_frequencies(e)
            return emit_call_text("odinl_frequencies", []string{slice_all_expr_text(current)}), {}, true
        }
        if thread_last && (head.text == "keys" || head.text == "vals") {
            if len(step.items) != 1 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects no arguments", head.text), span = step.span}, false
            }
            if head.text == "keys" {
                mark_core_keys(e)
                return emit_call_text("odinl_keys", []string{current}), {}, true
            }
            mark_core_vals(e)
            return emit_call_text("odinl_vals", []string{current}), {}, true
        }
        if thread_last && head.text == "distinct" {
            if len(step.items) != 1 {
                return "", Compile_Error{message = "distinct thread step expects no arguments", span = step.span}, false
            }
            mark_core_distinct(e)
            return emit_call_text("odinl_distinct", []string{slice_all_expr_text(current)}), {}, true
        }
        if thread_last && head.text == "distinct-by" {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "distinct-by thread step expects one key function argument", span = step.span}, false
            }
            return emit_distinct_by_callback_call(e, step.items[1], slice_all_expr_text(current))
        }
        if thread_last && head.text == "cycle" {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "cycle thread step expects one count argument", span = step.span}, false
            }
            count, err_count, ok_count := emit_expr(e, step.items[1])
            if !ok_count {
                return "", err_count, false
            }
            mark_core_cycle(e)
            return emit_call_text("odinl_cycle", []string{count, slice_all_expr_text(current)}), {}, true
        }
        if thread_last && head.text == "reduce" {
            if len(step.items) != 3 {
                return "", Compile_Error{message = "reduce thread step expects function and initial value", span = step.span}, false
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
            return emit_call_text("odinl_reduce", []string{f, init, slice_all_expr_text(current)}), {}, true
        }
        if thread_last && (head.text == "take" || head.text == "drop") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects one count argument", head.text), span = step.span}, false
            }
            count, err_count, ok_count := emit_expr(e, step.items[1])
            if !ok_count {
                return "", err_count, false
            }
            if head.text == "take" {
                mark_core_take(e)
                return emit_call_text("odinl_take", []string{count, slice_all_expr_text(current)}), {}, true
            } else {
                mark_core_drop(e)
                return emit_call_text("odinl_drop", []string{count, slice_all_expr_text(current)}), {}, true
            }
        }
        if thread_last && head.text == "drop-last" {
            if len(step.items) != 2 {
                return "", Compile_Error{message = "drop-last thread step expects one count argument", span = step.span}, false
            }
            count, err_count, ok_count := emit_expr(e, step.items[1])
            if !ok_count {
                return "", err_count, false
            }
            mark_core_drop_last(e)
            return emit_call_text("odinl_drop_last", []string{count, slice_all_expr_text(current)}), {}, true
        }
        if thread_last && head.text == "butlast" {
            if len(step.items) != 1 {
                return "", Compile_Error{message = "butlast thread step expects no arguments", span = step.span}, false
            }
            mark_core_drop_last(e)
            return emit_call_text("odinl_drop_last", []string{"1", slice_all_expr_text(current)}), {}, true
        }
        if thread_last && (head.text == "take-while" || head.text == "drop-while" || head.text == "find" || head.text == "some?" || head.text == "every?") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects one predicate argument", head.text), span = step.span}, false
            }
            collection := slice_all_expr_text(current)
            if head.text == "take-while" {
                return emit_predicate_callback_call(e, "odinl_take_while", step.items[1], collection, mark_core_take_while, mark_core_take_while_field)
            }
            if head.text == "drop-while" {
                return emit_predicate_callback_call(e, "odinl_drop_while", step.items[1], collection, mark_core_drop_while, mark_core_drop_while_field)
            }
            if head.text == "find" {
                return emit_predicate_callback_call(e, "odinl_find", step.items[1], collection, mark_core_find, mark_core_find_field)
            }
            if head.text == "some?" {
                return emit_predicate_callback_call(e, "odinl_some_p", step.items[1], collection, mark_core_some, mark_core_some_field)
            }
            return emit_predicate_callback_call(e, "odinl_every_p", step.items[1], collection, mark_core_every, mark_core_every_field)
        }
        if thread_last && head.text == "slice" {
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
        if thread_last && (head.text == "first" || head.text == "second" || head.text == "last" || head.text == "rest" || head.text == "empty?" || head.text == "count") {
            if len(step.items) != 1 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects no arguments", head.text), span = step.span}, false
            }
            collection := slice_all_expr_text(current)
            if head.text == "count" {
                return fmt.tprintf("len(%s)", collection), {}, true
            }
            if head.text == "first" {
                return fmt.tprintf("(%s)[0]", collection), {}, true
            }
            if head.text == "second" {
                return fmt.tprintf("(%s)[1]", collection), {}, true
            }
            if head.text == "last" {
                return fmt.tprintf("(%s)[len(%s)-1]", collection, collection), {}, true
            }
            if head.text == "empty?" {
                return fmt.tprintf("len(%s) == 0", collection), {}, true
            }
            return fmt.tprintf("(%s)[1:]", collection), {}, true
        }
        if thread_last && head.text == "nth" {
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
    return fmt.tprintf("odinl_thread_%d", e.temp_counter)
}

is_tap_thread_step :: proc(step: CST_Form) -> bool {
    return step.kind == .List && len(step.items) > 0 &&
           step.items[0].kind == .Symbol && step.items[0].text == "tap>"
}

thread_step_result_kind :: proc(step: CST_Form, thread_last: bool) -> Thread_Result_Kind {
    #partial switch step.kind {
    case .Keyword:
        return .Scalar
    case .Symbol:
        if thread_last && step.text == "slice" {
            return .View
        }
        return .Unknown
    case .List:
        if len(step.items) == 0 {
            return .Unknown
        }
        head := step.items[0]
        if head.kind == .Keyword {
            return .Scalar
        }
        if head.kind != .Symbol {
            return .Unknown
        }
        if head.text == "merge" {
            return .Owned
        }
        if thread_last && (head.text == "map" || head.text == "filter" ||
                           head.text == "remove" || head.text == "map-indexed" ||
                           head.text == "keep" || head.text == "mapcat" ||
                           head.text == "concat" || head.text == "into" ||
                           head.text == "interpose" ||
                           head.text == "interleave" ||
                           head.text == "reverse" || head.text == "shuffle" ||
                           head.text == "sort" ||
                           head.text == "sort-by" || head.text == "zipmap" ||
                           head.text == "index-by" || head.text == "group-by" ||
                           head.text == "frequencies" || head.text == "keys" ||
                           head.text == "vals" || head.text == "distinct" ||
                           head.text == "distinct-by" || head.text == "cycle") {
            return .Owned
        }
        if thread_last && (head.text == "partition" || head.text == "partition-all" || head.text == "partition-by") {
            return .Owned_Borrowing
        }
        if thread_last && (head.text == "take" || head.text == "drop" ||
                           head.text == "drop-last" || head.text == "butlast" ||
                           head.text == "take-while" || head.text == "drop-while" ||
                           head.text == "slice" || head.text == "rest" ||
                           head.text == "split-at") {
            return .View
        }
        if thread_last && (head.text == "reduce" || head.text == "find" ||
                           head.text == "some?" || head.text == "every?" ||
                           head.text == "first" || head.text == "second" ||
                           head.text == "last" || head.text == "nth" ||
                           head.text == "empty?" || head.text == "count") {
            return .Scalar
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
    if thread_last {
        return form.items[0].text == "->>"
    }
    return form.items[0].text == "->"
}

thread_form_has_allocating_intermediate :: proc(form: CST_Form, thread_last: bool) -> bool {
    if !is_thread_form(form, thread_last) || len(form.items) < 3 {
        return false
    }
    steps := form.items[2:]
    current_kind := Thread_Result_Kind.Unknown
    for step, idx in steps {
        kind := thread_step_result_kind(step, thread_last)
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

thread_form_final_kind :: proc(form: CST_Form, thread_last: bool) -> Thread_Result_Kind {
    if !is_thread_form(form, thread_last) || len(form.items) < 3 {
        return .Unknown
    }
    current_kind := Thread_Result_Kind.Unknown
    for step in form.items[2:] {
        if is_tap_thread_step(step) {
            continue
        }
        current_kind = thread_step_result_kind(step, thread_last)
    }
    return current_kind
}

thread_form_final_view_borrows_owned_intermediate :: proc(form: CST_Form, thread_last: bool) -> bool {
    if !is_thread_form(form, thread_last) || len(form.items) < 3 {
        return false
    }
    final_kind := thread_form_final_kind(form, thread_last)
    if final_kind != .View && final_kind != .Owned_Borrowing {
        return false
    }
    for step in form.items[2:len(form.items)-1] {
        if is_tap_thread_step(step) {
            continue
        }
        kind := thread_step_result_kind(step, thread_last)
        if kind == .Owned || kind == .Owned_Borrowing {
            return true
        }
    }
    return false
}

thread_return_error :: proc(form: CST_Form) -> (Compile_Error, bool) {
    if thread_form_has_allocating_intermediate(form, true) || thread_form_has_allocating_intermediate(form, false) {
        return Compile_Error{
            message = "threaded return has an allocating intermediate; bind the pipeline with let so OdinL can emit cleanup",
            span = form.span,
        }, true
    }
    return {}, false
}

owned_result_head :: proc(name: string) -> bool {
    switch name {
    case "map", "filter", "remove", "map-indexed", "keep", "mapcat",
         "concat", "merge", "reverse", "sort", "sort-by",
         "into", "interpose", "interleave", "shuffle",
         "partition", "partition-all", "partition-by",
         "zipmap", "index-by", "group-by", "frequencies", "keys", "vals",
         "distinct", "distinct-by",
         "range", "repeat", "repeatedly", "iterate", "cycle",
         "slurp", "load-json":
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
        kind := thread_form_final_kind(form, form.items[0].text == "->>")
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
                message = "owned result must be bound or returned; nested owned results would leak",
                span = form.span,
            }, true
        }
        return owned_result_usage_error(form.items[len(form.items)-1], true)
    }

    if form_is_owned_result(form) {
        if !allow_root_owned {
            return Compile_Error{
                message = "owned result must be bound or returned; nested owned results would leak",
                span = form.span,
            }, true
        }
        if (is_thread_form(form, true) && thread_form_has_allocating_intermediate(form, true)) ||
           (is_thread_form(form, false) && thread_form_has_allocating_intermediate(form, false)) {
            return Compile_Error{
                message = "threaded expression has an allocating intermediate; bind the pipeline with let so OdinL can emit cleanup",
                span = form.span,
            }, true
        }
    }

    #partial switch form.kind {
    case .List, .Vector, .Brace:
        start := 0
        if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
            head := form.items[0].text
            if head == "make" || head == "as" {
                start = 2
            } else if head == "new" {
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
        if thread_form_final_view_borrows_owned_intermediate(binding.value, true) ||
           thread_form_final_view_borrows_owned_intermediate(binding.value, false) {
            return Compile_Error{
                message = "cannot return a threaded slice view that borrows from an owned intermediate; return an owned result or keep the pipeline local",
                span = binding.value.span,
            }, true
        }
    }
    return {}, false
}

emit_binding_assignment :: proc(e: ^Emitter, binding: Binding, value: string) {
    if binding.is_destructure {
        line_builder := strings.builder_make()
        defer strings.builder_destroy(&line_builder)
        for name, idx in binding.pattern {
            if idx > 0 {
                strings.write_string(&line_builder, ", ")
            }
            strings.write_string(&line_builder, name)
        }
        fmt.sbprintf(&line_builder, " := %s", value)
        emit_prefixed_expr(e, "", strings.clone(strings.to_string(line_builder)))
    } else if binding.is_field_destructure {
        e.temp_counter += 1
        target := fmt.tprintf("odinl_destructure_%d", e.temp_counter)
        emit_prefixed_expr(e, fmt.tprintf("%s := ", target), value)
        for field in binding.fields {
            if field.name == "_" {
                continue
            }
            emit_prefixed_expr(e, fmt.tprintf("%s := ", field.name), fmt.tprintf("%s.%s", target, field.field))
        }
    } else if binding.is_typed {
        emit_prefixed_expr(e, fmt.tprintf("%s: %s = ", binding.name, binding.ty), value)
    } else {
        emit_prefixed_expr(e, fmt.tprintf("%s := ", binding.name), value)
    }
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

    steps := form.items[2:]
    current_kind := Thread_Result_Kind.Unknown
    for step, idx in steps {
        next, err_step, ok_step := emit_thread_step(e, current, step, thread_last)
        if !ok_step {
            return err_step, false
        }

        kind := thread_step_result_kind(step, thread_last)
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
        current_kind = kind
    }

    emit_binding_assignment(e, binding, current)
    return {}, true
}

emit_thread_expr :: proc(e: ^Emitter, form: CST_Form, thread_last: bool = false) -> (string, Compile_Error, bool) {
    if len(form.items) < 3 {
        return "", Compile_Error{message = "-> expects an initial expression and at least one step", span = form.span}, false
    }

    current, err_current, ok_current := emit_expr(e, form.items[1])
    if !ok_current {
        return "", err_current, false
    }

    for step in form.items[2:] {
        next, err_step, ok_step := emit_thread_step(e, current, step, thread_last)
        if !ok_step {
            return "", err_step, false
        }
        current = next
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

field_from_keyword :: proc(form: CST_Form) -> (field: string, ok: bool) {
    if form.kind != .Keyword || len(form.text) < 2 {
        return "", false
    }
    return map_name(form.text[1:]), true
}

field_type_expr_text :: proc(collection, field: string) -> string {
    return fmt.tprintf("type_of((%s)[0].%s)", collection, field)
}

type_text_is_dynamic_array :: proc(text: string) -> bool {
    return len(text) >= 9 && text[:9] == "[dynamic]"
}

type_text_is_map :: proc(text: string) -> bool {
    return len(text) >= 4 && text[:4] == "map["
}

form_is_owned_allocation_result :: proc(form: CST_Form) -> bool {
    if form.kind != .List || len(form.items) < 2 || form.items[0].kind != .Symbol {
        return false
    }
    head := form.items[0].text
    if head != "make" && head != "new" {
        return false
    }
    type_text, _, ok_type := parse_type_text(form.items[1])
    if !ok_type {
        return false
    }
    defer delete(type_text)
    return type_text_is_dynamic_array(type_text) || type_text_is_map(type_text)
}

form_is_owned_temp_escape_result :: proc(form: CST_Form) -> bool {
    return form_is_owned_result(form) || form_is_owned_allocation_result(form)
}

with_temp_allocator_escape_error :: proc(body: []CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    for item in body {
        if item.kind == .List && len(item.items) > 0 && item.items[0].kind == .Symbol && item.items[0].text == "return" {
            for returned in item.items[1:] {
                if form_is_owned_temp_escape_result(returned) {
                    return Compile_Error{
                        message = "owned value cannot escape with-temp-allocator; allocate it outside the temp scope or copy it before returning",
                        span = returned.span,
                    }, true
                }
            }
        }
    }

    if last_in_proc && returns.kind != .None && len(body) > 0 {
        final_form := body[len(body)-1]
        if form_is_owned_temp_escape_result(final_form) {
            return Compile_Error{
                message = "owned value cannot escape with-temp-allocator; allocate it outside the temp scope or copy it before returning",
                span = final_form.span,
            }, true
        }
    }
    return {}, false
}

emit_map_callback_call :: proc(e: ^Emitter, callback: CST_Form, collection: string) -> (string, Compile_Error, bool) {
    if field, ok_field := field_from_keyword(callback); ok_field {
        mark_core_map_field(e, field)
        return emit_call_text(
            fmt.tprintf("odinl_map_field_%s", field),
            []string{field_type_expr_text(collection, field), collection},
        ), {}, true
    }

    f, err_f, ok_f := emit_expr(e, callback)
    if !ok_f {
        return "", err_f, false
    }
    mark_core_map(e)
    return emit_call_text("odinl_map", []string{f, collection}), {}, true
}

emit_index_by_callback_call :: proc(e: ^Emitter, callback: CST_Form, collection: string) -> (string, Compile_Error, bool) {
    if field, ok_field := field_from_keyword(callback); ok_field {
        mark_core_index_by_field(e, field)
        return emit_call_text(
            fmt.tprintf("odinl_index_by_field_%s", field),
            []string{field_type_expr_text(collection, field), collection},
        ), {}, true
    }

    f, err_f, ok_f := emit_expr(e, callback)
    if !ok_f {
        return "", err_f, false
    }
    mark_core_index_by(e)
    return emit_call_text("odinl_index_by", []string{f, collection}), {}, true
}

emit_group_by_callback_call :: proc(e: ^Emitter, callback: CST_Form, collection: string) -> (string, Compile_Error, bool) {
    if field, ok_field := field_from_keyword(callback); ok_field {
        mark_core_group_by_field(e, field)
        return emit_call_text(
            fmt.tprintf("odinl_group_by_field_%s", field),
            []string{field_type_expr_text(collection, field), collection},
        ), {}, true
    }

    f, err_f, ok_f := emit_expr(e, callback)
    if !ok_f {
        return "", err_f, false
    }
    mark_core_group_by(e)
    return emit_call_text("odinl_group_by", []string{f, collection}), {}, true
}

emit_distinct_by_callback_call :: proc(e: ^Emitter, callback: CST_Form, collection: string) -> (string, Compile_Error, bool) {
    if field, ok_field := field_from_keyword(callback); ok_field {
        mark_core_distinct_by_field(e, field)
        return emit_call_text(
            fmt.tprintf("odinl_distinct_by_field_%s", field),
            []string{field_type_expr_text(collection, field), collection},
        ), {}, true
    }
    f, err_f, ok_f := emit_expr(e, callback)
    if !ok_f {
        return "", err_f, false
    }
    mark_core_distinct_by(e)
    return emit_call_text("odinl_distinct_by", []string{f, collection}), {}, true
}

emit_partition_by_callback_call :: proc(e: ^Emitter, callback: CST_Form, collection: string) -> (string, Compile_Error, bool) {
    if field, ok_field := field_from_keyword(callback); ok_field {
        mark_core_partition_by_field(e, field)
        return emit_call_text(
            fmt.tprintf("odinl_partition_by_field_%s", field),
            []string{field_type_expr_text(collection, field), collection},
        ), {}, true
    }

    f, err_f, ok_f := emit_expr(e, callback)
    if !ok_f {
        return "", err_f, false
    }
    mark_core_partition_by(e)
    return emit_call_text("odinl_partition_by", []string{f, collection}), {}, true
}

emit_sort_by_callback_call :: proc(e: ^Emitter, callback: CST_Form, collection: string) -> (string, Compile_Error, bool) {
    if field, ok_field := field_from_keyword(callback); ok_field {
        mark_core_sort_by_field(e, field)
        return emit_call_text(
            fmt.tprintf("odinl_sort_by_field_%s", field),
            []string{field_type_expr_text(collection, field), collection},
        ), {}, true
    }

    f, err_f, ok_f := emit_expr(e, callback)
    if !ok_f {
        return "", err_f, false
    }
    mark_core_sort_by(e)
    return emit_call_text("odinl_sort_by", []string{f, collection}), {}, true
}

emit_sort_by_in_place_callback_call :: proc(e: ^Emitter, callback: CST_Form, collection: string) -> (string, Compile_Error, bool) {
    if field, ok_field := field_from_keyword(callback); ok_field {
        mark_core_sort_by_in_place_field(e, field)
        return emit_call_text(fmt.tprintf("odinl_sort_by_in_place_field_%s", field), []string{collection}), {}, true
    }

    f, err_f, ok_f := emit_expr(e, callback)
    if !ok_f {
        return "", err_f, false
    }
    mark_core_sort_by_in_place(e)
    return emit_call_text("odinl_sort_by_in_place", []string{f, collection}), {}, true
}

emit_dynamic_predicate_in_place_callback_call :: proc(e: ^Emitter, helper_name: string, callback: CST_Form, collection: string, mark_helper: proc(^Emitter), mark_field: proc(^Emitter, string)) -> (string, Compile_Error, bool) {
    collection_ptr := address_of_expr_text(collection)
    if field, ok_field := field_from_keyword(callback); ok_field {
        mark_field(e, field)
        return emit_call_text(fmt.tprintf("%s_field_%s", helper_name, field), []string{collection_ptr}), {}, true
    }

    pred, err_pred, ok_pred := emit_expr(e, callback)
    if !ok_pred {
        return "", err_pred, false
    }
    mark_helper(e)
    return emit_call_text(helper_name, []string{pred, collection_ptr}), {}, true
}

emit_predicate_callback_call :: proc(e: ^Emitter, helper_name: string, callback: CST_Form, collection: string, mark_helper: proc(^Emitter), mark_field: proc(^Emitter, string)) -> (string, Compile_Error, bool) {
    if field, ok_field := field_from_keyword(callback); ok_field {
        mark_field(e, field)
        return emit_call_text(fmt.tprintf("%s_field_%s", helper_name, field), []string{collection}), {}, true
    }

    pred, err_pred, ok_pred := emit_expr(e, callback)
    if !ok_pred {
        return "", err_pred, false
    }
    mark_helper(e)
    return emit_call_text(helper_name, []string{pred, collection}), {}, true
}

emit_proc_literal_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) < 2 || !is_symbol(form.items[0], "proc") || form.items[1].kind != .Vector {
        return "", Compile_Error{message = "invalid proc literal", span = form.span}, false
    }

    params, err_params, ok_params := parse_param_vector(form.items[1])
    if !ok_params {
        return "", err_params, false
    }

    body_index := 2
    returns := Return_Spec{kind = .None}
    if body_index < len(form.items) && is_symbol(form.items[body_index], "->") {
        if body_index+1 >= len(form.items) {
            return "", Compile_Error{message = "missing proc literal return spec", span = form.items[body_index].span}, false
        }
        return_form := form.items[body_index+1]
        #partial switch return_form.kind {
        case .Vector:
            named, err_named, ok_named := parse_named_returns(return_form)
            if !ok_named {
                return "", err_named, false
            }
            returns.kind = .Named
            returns.named = named
            body_index += 2
        case .Symbol, .List:
            return_text, next_index, err_return, ok_return := parse_type_text_from_forms(form.items[:], body_index+1)
            if !ok_return {
                return "", err_return, false
            }
            returns.kind = .Single
            returns.single_ty = return_text
            body_index = next_index
        case:
            return "", Compile_Error{message = "unsupported proc literal return spec", span = return_form.span}, false
        }
    }
    if body_index >= len(form.items) {
        return "", Compile_Error{message = "proc literal body is empty", span = form.span}, false
    }

    sub := Emitter{
        builder  = strings.builder_make(),
        indent   = 1,
        unions   = e.unions,
        features = e.features,
    }
    defer strings.builder_destroy(&sub.builder)

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

    body: [dynamic]CST_Form
    for item in form.items[body_index:] {
        append(&body, item)
    }
    err_body, ok_body := emit_body_forms(&sub, body[:], returns)
    if !ok_body {
        return "", err_body, false
    }

    strings.write_string(&sub.builder, "}")
    return strings.clone(strings.to_string(sub.builder)), {}, true
}

emit_operator_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    head := form.items[0]
    if head.kind != .Symbol {
        return "", {}, false
    }

    op := head.text
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

    if op == "==" || op == "!=" || op == "<" || op == "<=" || op == ">" || op == ">=" {
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
        return fmt.tprintf("(%s) %s (%s)", lhs, op, rhs), {}, true
    }

    if op == "in?" || op == "contains?" {
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
        return fmt.tprintf("(%s) in (%s)", key, collection), {}, true
    }

    if op == "in" || op == "not-in" {
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
        if op == "not-in" {
            return fmt.tprintf("!((%s) in (%s))", lhs, rhs), {}, true
        }
        return fmt.tprintf("(%s) in (%s)", lhs, rhs), {}, true
    }

    return "", {}, false
}

find_union_decl :: proc(e: ^Emitter, name: string) -> (^Union_Decl, bool) {
    for i in 0..<len(e.unions) {
        if e.unions[i].name == name {
            return &e.unions[i], true
        }
    }
    return nil, false
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
    if key.kind != .Keyword {
        return "", Compile_Error{message = "union construction expects a keyword variant", span = key.span}, false
    }

    variant_name := map_name(key.text[1:])
    found := false
    for variant in union_decl.variants {
        if variant.name == variant_name {
            found = true
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

emit_call_like :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    head := form.items[0]
    if head.kind != .Symbol {
        return "", Compile_Error{message = "unsupported call head", span = head.span}, false
    }

    if operator_text, err_op, ok_op := emit_operator_expr(e, form); ok_op {
        return operator_text, {}, true
    } else if err_op.message != "" {
        return "", err_op, false
    }

    if head.text == "get" {
        if len(form.items) != 3 && len(form.items) != 4 {
            return "", Compile_Error{message = "get expects collection, key, and optional default", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
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
            return emit_call_text("odinl_get_or_default", []string{target, key, default_value}), {}, true
        }
        return fmt.tprintf("%s[%s]", target, key), {}, true
    }

    if head.text == "nil?" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "nil? expects one expression", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        return fmt.tprintf("(%s) == nil", target), {}, true
    }

    if head.text == "slurp" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "slurp expects path", span = form.span}, false
        }
        path, err_path, ok_path := emit_expr(e, form.items[1])
        if !ok_path {
            return "", err_path, false
        }
        return emit_call_text("os.read_entire_file", []string{path, "context.allocator"}), {}, true
    }

    if head.text == "spit" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "spit expects path and data", span = form.span}, false
        }
        path, err_path, ok_path := emit_expr(e, form.items[1])
        if !ok_path {
            return "", err_path, false
        }
        data, err_data, ok_data := emit_expr(e, form.items[2])
        if !ok_data {
            return "", err_data, false
        }
        return emit_call_text("os.write_entire_file", []string{path, data}), {}, true
    }

    if head.text == "save-json" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "save-json expects path and value", span = form.span}, false
        }
        path, err_path, ok_path := emit_expr(e, form.items[1])
        if !ok_path {
            return "", err_path, false
        }
        value, err_value, ok_value := emit_expr(e, form.items[2])
        if !ok_value {
            return "", err_value, false
        }
        mark_core_save_json(e)
        return emit_call_text("odinl_save_json", []string{path, value}), {}, true
    }

    if head.text == "load-json" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "load-json expects type and path", span = form.span}, false
        }
        type_text, err_type, ok_type := parse_type_text(form.items[1])
        if !ok_type {
            return "", err_type, false
        }
        path, err_path, ok_path := emit_expr(e, form.items[2])
        if !ok_path {
            return "", err_path, false
        }
        mark_core_load_json(e)
        return emit_call_text("odinl_load_json", []string{type_text, path}), {}, true
    }

    if head.text == "tap>" {
        if len(form.items) != 2 && len(form.items) != 3 {
            return "", Compile_Error{message = "tap> expects value or label and value", span = form.span}, false
        }
        mark_core_tap(e)
        if len(form.items) == 2 {
            value, err_value, ok_value := emit_expr(e, form.items[1])
            if !ok_value {
                return "", err_value, false
            }
            return emit_call_text("odinl_tap", []string{value}), {}, true
        }

        label_form := form.items[1]
        label: string
        if label_form.kind == .Keyword {
            label = fmt.tprintf("\"%s\"", label_form.text[1:])
        } else if label_form.kind == .String {
            label = label_form.text
        } else {
            return "", Compile_Error{message = "tap> label must be a keyword or string literal", span = label_form.span}, false
        }
        value, err_value, ok_value := emit_expr(e, form.items[2])
        if !ok_value {
            return "", err_value, false
        }
        return emit_call_text("odinl_tap_labeled", []string{label, value}), {}, true
    }

    if head.text == "map" || head.text == "filter" || head.text == "remove" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects function and collection", head.text), span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        collection = slice_all_expr_text(collection)
        if head.text == "map" {
            return emit_map_callback_call(e, form.items[1], collection)
        }
        if head.text == "remove" {
            return emit_predicate_callback_call(e, "odinl_remove", form.items[1], collection, mark_core_remove, mark_core_remove_field)
        }
        return emit_predicate_callback_call(e, "odinl_filter", form.items[1], collection, mark_core_filter, mark_core_filter_field)
    }

    if head.text == "map!" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "map! expects function and collection", span = form.span}, false
        }
        f, err_f, ok_f := emit_expr(e, form.items[1])
        if !ok_f {
            return "", err_f, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        mark_core_map_in_place(e)
        return emit_call_text("odinl_map_in_place", []string{f, slice_all_expr_text(collection)}), {}, true
    }

    if head.text == "map-indexed!" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "map-indexed! expects function and collection", span = form.span}, false
        }
        f, err_f, ok_f := emit_expr(e, form.items[1])
        if !ok_f {
            return "", err_f, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        mark_core_map_indexed_in_place(e)
        return emit_call_text("odinl_map_indexed_in_place", []string{f, slice_all_expr_text(collection)}), {}, true
    }

    if head.text == "filter!" || head.text == "remove!" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects predicate and dynamic array", head.text), span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        if head.text == "remove!" {
            return emit_dynamic_predicate_in_place_callback_call(e, "odinl_remove_in_place", form.items[1], collection, mark_core_remove_in_place, mark_core_remove_in_place_field)
        }
        return emit_dynamic_predicate_in_place_callback_call(e, "odinl_filter_in_place", form.items[1], collection, mark_core_filter_in_place, mark_core_filter_in_place_field)
    }

    if head.text == "map-indexed" || head.text == "keep" || head.text == "mapcat" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects function and collection", head.text), span = form.span}, false
        }
        f, err_f, ok_f := emit_expr(e, form.items[1])
        if !ok_f {
            return "", err_f, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        collection = slice_all_expr_text(collection)
        if head.text == "map-indexed" {
            mark_core_map_indexed(e)
            return emit_call_text("odinl_map_indexed", []string{f, collection}), {}, true
        }
        if head.text == "mapcat" {
            mark_core_mapcat(e)
            return emit_call_text("odinl_mapcat", []string{f, collection}), {}, true
        }
        mark_core_keep(e)
        return emit_call_text("odinl_keep", []string{f, collection}), {}, true
    }

    if head.text == "keep!" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "keep! expects function and dynamic array", span = form.span}, false
        }
        f, err_f, ok_f := emit_expr(e, form.items[1])
        if !ok_f {
            return "", err_f, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        mark_core_keep_in_place(e)
        return emit_call_text("odinl_keep_in_place", []string{f, address_of_expr_text(collection)}), {}, true
    }

    if head.text == "into!" {
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

    if head.text == "merge!" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "merge! expects target map and source map", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        source, err_source, ok_source := emit_expr(e, form.items[2])
        if !ok_source {
            return "", err_source, false
        }
        mark_core_merge_in_place(e)
        return emit_call_text("odinl_merge_in_place", []string{address_of_expr_text(target), source}), {}, true
    }

    if head.text == "into" {
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
        return emit_call_text("odinl_into", []string{type_text, slice_all_expr_text(collection)}), {}, true
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
        return emit_call_text("odinl_concat", []string{slice_all_expr_text(lhs), slice_all_expr_text(rhs)}), {}, true
    }

    if head.text == "merge" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "merge expects two maps", span = form.span}, false
        }
        lhs, err_lhs, ok_lhs := emit_expr(e, form.items[1])
        if !ok_lhs {
            return "", err_lhs, false
        }
        rhs, err_rhs, ok_rhs := emit_expr(e, form.items[2])
        if !ok_rhs {
            return "", err_rhs, false
        }
        mark_core_merge(e)
        return emit_call_text("odinl_merge", []string{lhs, rhs}), {}, true
    }

    if head.text == "keys" || head.text == "vals" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = fmt.tprintf("%s expects map", head.text), span = form.span}, false
        }
        source, err_source, ok_source := emit_expr(e, form.items[1])
        if !ok_source {
            return "", err_source, false
        }
        if head.text == "keys" {
            mark_core_keys(e)
            return emit_call_text("odinl_keys", []string{source}), {}, true
        }
        mark_core_vals(e)
        return emit_call_text("odinl_vals", []string{source}), {}, true
    }

    if head.text == "interpose" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "interpose expects separator and collection", span = form.span}, false
        }
        sep, err_sep, ok_sep := emit_expr(e, form.items[1])
        if !ok_sep {
            return "", err_sep, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        mark_core_interpose(e)
        return emit_call_text("odinl_interpose", []string{sep, slice_all_expr_text(collection)}), {}, true
    }

    if head.text == "interleave" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "interleave expects two collections", span = form.span}, false
        }
        lhs, err_lhs, ok_lhs := emit_expr(e, form.items[1])
        if !ok_lhs {
            return "", err_lhs, false
        }
        rhs, err_rhs, ok_rhs := emit_expr(e, form.items[2])
        if !ok_rhs {
            return "", err_rhs, false
        }
        mark_core_interleave(e)
        return emit_call_text("odinl_interleave", []string{slice_all_expr_text(lhs), slice_all_expr_text(rhs)}), {}, true
    }

    if head.text == "reverse" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "reverse expects collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[1])
        if !ok_collection {
            return "", err_collection, false
        }
        mark_core_reverse(e)
        return emit_call_text("odinl_reverse", []string{slice_all_expr_text(collection)}), {}, true
    }

    if head.text == "shuffle" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "shuffle expects picker function and collection", span = form.span}, false
        }
        pick, err_pick, ok_pick := emit_expr(e, form.items[1])
        if !ok_pick {
            return "", err_pick, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        mark_core_shuffle(e)
        return emit_call_text("odinl_shuffle", []string{pick, slice_all_expr_text(collection)}), {}, true
    }

    if head.text == "reverse!" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "reverse! expects collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[1])
        if !ok_collection {
            return "", err_collection, false
        }
        mark_core_reverse_in_place(e)
        return emit_call_text("odinl_reverse_in_place", []string{slice_all_expr_text(collection)}), {}, true
    }

    if head.text == "shuffle!" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "shuffle! expects picker function and collection", span = form.span}, false
        }
        pick, err_pick, ok_pick := emit_expr(e, form.items[1])
        if !ok_pick {
            return "", err_pick, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        mark_core_shuffle_in_place(e)
        return emit_call_text("odinl_shuffle_in_place", []string{pick, slice_all_expr_text(collection)}), {}, true
    }

    if head.text == "sort" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "sort expects collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[1])
        if !ok_collection {
            return "", err_collection, false
        }
        mark_core_sort(e)
        return emit_call_text("odinl_sort", []string{slice_all_expr_text(collection)}), {}, true
    }

    if head.text == "sort!" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "sort! expects collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[1])
        if !ok_collection {
            return "", err_collection, false
        }
        mark_core_sort_in_place(e)
        return emit_call_text("odinl_sort_in_place", []string{slice_all_expr_text(collection)}), {}, true
    }

    if head.text == "sort-by" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "sort-by expects key function and collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        return emit_sort_by_callback_call(e, form.items[1], slice_all_expr_text(collection))
    }

    if head.text == "sort-by!" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "sort-by! expects key function and collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        return emit_sort_by_in_place_callback_call(e, form.items[1], slice_all_expr_text(collection))
    }

    if head.text == "split-at" || head.text == "partition" || head.text == "partition-all" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects count and collection", head.text), span = form.span}, false
        }
        count, err_count, ok_count := emit_expr(e, form.items[1])
        if !ok_count {
            return "", err_count, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        collection = slice_all_expr_text(collection)
        if head.text == "split-at" {
            mark_core_split_at(e)
            return emit_call_text("odinl_split_at", []string{count, collection}), {}, true
        }
        if head.text == "partition" {
            mark_core_partition(e)
            return emit_call_text("odinl_partition", []string{count, collection}), {}, true
        }
        mark_core_partition_all(e)
        return emit_call_text("odinl_partition_all", []string{count, collection}), {}, true
    }

    if head.text == "partition-by" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "partition-by expects key function and collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        return emit_partition_by_callback_call(e, form.items[1], slice_all_expr_text(collection))
    }

    if head.text == "zipmap" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "zipmap expects key and value collections", span = form.span}, false
        }
        keys, err_keys, ok_keys := emit_expr(e, form.items[1])
        if !ok_keys {
            return "", err_keys, false
        }
        values, err_values, ok_values := emit_expr(e, form.items[2])
        if !ok_values {
            return "", err_values, false
        }
        mark_core_zipmap(e)
        return emit_call_text("odinl_zipmap", []string{slice_all_expr_text(keys), slice_all_expr_text(values)}), {}, true
    }

    if head.text == "index-by" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "index-by expects key function and collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        return emit_index_by_callback_call(e, form.items[1], slice_all_expr_text(collection))
    }

    if head.text == "group-by" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "group-by expects key function and collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        return emit_group_by_callback_call(e, form.items[1], slice_all_expr_text(collection))
    }

    if head.text == "frequencies" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "frequencies expects collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[1])
        if !ok_collection {
            return "", err_collection, false
        }
        mark_core_frequencies(e)
        return emit_call_text("odinl_frequencies", []string{slice_all_expr_text(collection)}), {}, true
    }

    if head.text == "distinct" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "distinct expects collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[1])
        if !ok_collection {
            return "", err_collection, false
        }
        mark_core_distinct(e)
        return emit_call_text("odinl_distinct", []string{slice_all_expr_text(collection)}), {}, true
    }

    if head.text == "distinct-by" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "distinct-by expects key function and collection", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        return emit_distinct_by_callback_call(e, form.items[1], slice_all_expr_text(collection))
    }

    if head.text == "range" {
        if len(form.items) < 2 || len(form.items) > 4 {
            return "", Compile_Error{message = "range expects end, start/end, or start/end/step", span = form.span}, false
        }
        start := "0"
        end: string
        step := "1"
        if len(form.items) == 2 {
            end_value, err_end, ok_end := emit_expr(e, form.items[1])
            if !ok_end {
                return "", err_end, false
            }
            end = end_value
        } else {
            start_value, err_start, ok_start := emit_expr(e, form.items[1])
            if !ok_start {
                return "", err_start, false
            }
            end_value, err_end, ok_end := emit_expr(e, form.items[2])
            if !ok_end {
                return "", err_end, false
            }
            start = start_value
            end = end_value
            if len(form.items) == 4 {
                step_value, err_step, ok_step := emit_expr(e, form.items[3])
                if !ok_step {
                    return "", err_step, false
                }
                step = step_value
            }
        }
        mark_core_range(e)
        return emit_call_text("odinl_range", []string{start, end, step}), {}, true
    }

    if head.text == "repeat" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "repeat expects count and value", span = form.span}, false
        }
        count, err_count, ok_count := emit_expr(e, form.items[1])
        if !ok_count {
            return "", err_count, false
        }
        value, err_value, ok_value := emit_expr(e, form.items[2])
        if !ok_value {
            return "", err_value, false
        }
        mark_core_repeat(e)
        return emit_call_text("odinl_repeat", []string{count, value}), {}, true
    }

    if head.text == "repeatedly" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "repeatedly expects count and function", span = form.span}, false
        }
        count, err_count, ok_count := emit_expr(e, form.items[1])
        if !ok_count {
            return "", err_count, false
        }
        f, err_f, ok_f := emit_expr(e, form.items[2])
        if !ok_f {
            return "", err_f, false
        }
        mark_core_repeatedly(e)
        return emit_call_text("odinl_repeatedly", []string{count, f}), {}, true
    }

    if head.text == "iterate" {
        if len(form.items) != 4 {
            return "", Compile_Error{message = "iterate expects count, function, and initial value", span = form.span}, false
        }
        count, err_count, ok_count := emit_expr(e, form.items[1])
        if !ok_count {
            return "", err_count, false
        }
        f, err_f, ok_f := emit_expr(e, form.items[2])
        if !ok_f {
            return "", err_f, false
        }
        init, err_init, ok_init := emit_expr(e, form.items[3])
        if !ok_init {
            return "", err_init, false
        }
        mark_core_iterate(e)
        return emit_call_text("odinl_iterate", []string{count, f, init}), {}, true
    }

    if head.text == "cycle" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "cycle expects count and collection", span = form.span}, false
        }
        count, err_count, ok_count := emit_expr(e, form.items[1])
        if !ok_count {
            return "", err_count, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        mark_core_cycle(e)
        return emit_call_text("odinl_cycle", []string{count, slice_all_expr_text(collection)}), {}, true
    }

    if head.text == "reduce" {
        if len(form.items) != 4 {
            return "", Compile_Error{message = "reduce expects function, initial value, and collection", span = form.span}, false
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
        return emit_call_text("odinl_reduce", []string{f, init, collection}), {}, true
    }

    if head.text == "take" || head.text == "drop" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects count and collection", head.text), span = form.span}, false
        }
        count, err_count, ok_count := emit_expr(e, form.items[1])
        if !ok_count {
            return "", err_count, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        collection = slice_all_expr_text(collection)
        if head.text == "take" {
            mark_core_take(e)
            return emit_call_text("odinl_take", []string{count, collection}), {}, true
        }
        mark_core_drop(e)
        return emit_call_text("odinl_drop", []string{count, collection}), {}, true
    }

    if head.text == "drop-last" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "drop-last expects count and collection", span = form.span}, false
        }
        count, err_count, ok_count := emit_expr(e, form.items[1])
        if !ok_count {
            return "", err_count, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        mark_core_drop_last(e)
        return emit_call_text("odinl_drop_last", []string{count, slice_all_expr_text(collection)}), {}, true
    }

    if head.text == "take-while" || head.text == "drop-while" || head.text == "find" || head.text == "some?" || head.text == "every?" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects predicate and collection", head.text), span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        collection = slice_all_expr_text(collection)
        if head.text == "take-while" {
            return emit_predicate_callback_call(e, "odinl_take_while", form.items[1], collection, mark_core_take_while, mark_core_take_while_field)
        }
        if head.text == "drop-while" {
            return emit_predicate_callback_call(e, "odinl_drop_while", form.items[1], collection, mark_core_drop_while, mark_core_drop_while_field)
        }
        if head.text == "find" {
            return emit_predicate_callback_call(e, "odinl_find", form.items[1], collection, mark_core_find, mark_core_find_field)
        }
        if head.text == "some?" {
            return emit_predicate_callback_call(e, "odinl_some_p", form.items[1], collection, mark_core_some, mark_core_some_field)
        }
        return emit_predicate_callback_call(e, "odinl_every_p", form.items[1], collection, mark_core_every, mark_core_every_field)
    }

    if head.text == "first" || head.text == "second" || head.text == "last" ||
       head.text == "rest" || head.text == "butlast" ||
       head.text == "empty?" || head.text == "count" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = fmt.tprintf("%s expects collection", head.text), span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[1])
        if !ok_collection {
            return "", err_collection, false
        }
        collection = slice_all_expr_text(collection)
        if head.text == "count" {
            return fmt.tprintf("len(%s)", collection), {}, true
        }
        if head.text == "first" {
            return fmt.tprintf("(%s)[0]", collection), {}, true
        }
        if head.text == "second" {
            return fmt.tprintf("(%s)[1]", collection), {}, true
        }
        if head.text == "last" {
            return fmt.tprintf("(%s)[len(%s)-1]", collection, collection), {}, true
        }
        if head.text == "empty?" {
            return fmt.tprintf("len(%s) == 0", collection), {}, true
        }
        if head.text == "butlast" {
            mark_core_drop_last(e)
            return emit_call_text("odinl_drop_last", []string{"1", collection}), {}, true
        }
        return fmt.tprintf("(%s)[1:]", collection), {}, true
    }

    if head.text == "nth" {
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

    if head.text == "^" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "^ expects one pointer expression", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        return fmt.tprintf("(%s)^", target), {}, true
    }

    if head.text == "&" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "& expects one addressable expression", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        return fmt.tprintf("&(%s)", target), {}, true
    }

    if head.text == "->" {
        return emit_thread_expr(e, form)
    }

    if head.text == "->>" {
        return emit_thread_expr(e, form, true)
    }

    if head.text == "new" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "new expects type and literal", span = form.span}, false
        }
        type_form := form.items[1]
        type_text, err_type, ok_type := parse_type_text(type_form)
        if !ok_type {
            return "", err_type, false
        }
        if type_form_needs_dynamic_literals(type_form) {
            mark_dynamic_literals(e)
        }
        #partial switch form.items[2].kind {
        case .Vector:
            return emit_vector_literal(e, type_text, form.items[2])
        case .Brace:
            return emit_brace_literal(e, type_text, form.items[2])
        case:
            return "", Compile_Error{message = "new expects vector or brace literal", span = form.items[2].span}, false
        }
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

    if len(form.items) == 2 && form.items[1].kind == .Brace {
        union_decl, ok_union := find_union_decl(e, map_name(head.text))
        if ok_union {
            return emit_union_constructor(e, union_decl, form.items[1])
        }
        return emit_brace_literal(e, map_name(head.text), form.items[1])
    }

    arg_texts: [dynamic]string
    for arg in form.items[1:] {
        arg_text, err_arg, ok_arg := emit_expr(e, arg)
        if !ok_arg {
            return "", err_arg, false
        }
        append(&arg_texts, arg_text)
    }
    return emit_call_text(map_name(head.text), arg_texts[:]), {}, true
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
        return map_name(form.text), {}, true
    case .Keyword:
        return map_name(form.text[1:]), {}, true
    case .List:
        if len(form.items) == 0 {
            return "", Compile_Error{message = "empty list expression", span = form.span}, false
        }
        if form.items[0].kind == .Symbol && len(form.items[0].text) > 0 && form.items[0].text[0] == '#' {
            return emit_directive_expr(e, form)
        }
        if is_symbol(form.items[0], "proc") {
            return emit_proc_literal_expr(e, form)
        }
        if form.items[0].kind == .Keyword {
            if len(form.items) != 2 {
                return "", Compile_Error{message = "field access expects one receiver", span = form.span}, false
            }
            receiver, err_receiver, ok_receiver := emit_expr(e, form.items[1])
            if !ok_receiver {
                return "", err_receiver, false
            }
            return fmt.tprintf("%s.%s", receiver, map_name(form.items[0].text[1:])), {}, true
        }
        if is_symbol(form.items[0], "odin") {
            if len(form.items) != 2 || form.items[1].kind != .String {
                return "", Compile_Error{message = "odin expects one string literal", span = form.span}, false
            }
            return unquote_string(form.items[1].text), {}, true
        }
        return emit_call_like(e, form)
    case .Vector:
        return emit_vector_literal(e, "", form)
    case .Brace:
        return emit_brace_literal(e, "", form)
    }
    return "", Compile_Error{message = "unsupported expression", span = form.span}, false
}

Binding_Field :: struct {
    field: string,
    name:  string,
}

Binding :: struct {
    is_destructure: bool,
    is_field_destructure: bool,
    name:           string,
    pattern:        [dynamic]string,
    fields:         [dynamic]Binding_Field,
    is_typed:       bool,
    ty:             string,
    value:          CST_Form,
}

parse_field_destructure_binding :: proc(form: CST_Form) -> (fields: [dynamic]Binding_Field, err: Compile_Error, ok: bool) {
    if len(form.items) == 0 {
        return fields, Compile_Error{message = "field destructuring expects at least one field", span = form.span}, false
    }

    all_keywords := true
    for item in form.items {
        if item.kind != .Keyword {
            all_keywords = false
            break
        }
    }
    if all_keywords {
        for item in form.items {
            name := map_name(item.text[1:])
            append(&fields, Binding_Field{field = name, name = name})
        }
        return fields, {}, true
    }

    if len(form.items)%2 != 0 {
        return fields, Compile_Error{message = "field destructuring expects field/local pairs", span = form.span}, false
    }
    i := 0
    for i < len(form.items) {
        key := form.items[i]
        local := form.items[i+1]
        if key.kind != .Keyword {
            return fields, Compile_Error{message = "field destructuring expects keyword fields", span = key.span}, false
        }
        if local.kind != .Symbol {
            return fields, Compile_Error{message = "field destructuring expects symbol locals", span = local.span}, false
        }
        append(&fields, Binding_Field{
            field = map_name(key.text[1:]),
            name = map_name(local.text),
        })
        i += 2
    }
    return fields, {}, true
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
                return bindings, Compile_Error{message = "destructuring binding missing value", span = target.span}, false
            }
            names: [dynamic]string
            for part in target.items {
                if part.kind != .Symbol {
                    return bindings, Compile_Error{message = "destructuring expects symbols", span = part.span}, false
                }
                append(&names, map_name(part.text))
            }
            append(&bindings, Binding{
                is_destructure = true,
                pattern = names,
                value = form.items[i+1],
            })
            i += 2
        case .Brace:
            if i+1 >= len(form.items) {
                return bindings, Compile_Error{message = "field destructuring binding missing value", span = target.span}, false
            }
            fields, err_fields, ok_fields := parse_field_destructure_binding(target)
            if !ok_fields {
                return bindings, err_fields, false
            }
            append(&bindings, Binding{
                is_field_destructure = true,
                fields = fields,
                value = form.items[i+1],
            })
            i += 2
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
                append(&bindings, Binding{
                    name = map_name(target.text[:len(target.text)-1]),
                    is_typed = true,
                    ty = type_text,
                    value = form.items[next_i],
                })
                i = next_i + 1
            } else {
                if i+1 >= len(form.items) {
                    return bindings, Compile_Error{message = "binding missing value", span = target.span}, false
                }
                append(&bindings, Binding{
                    name = map_name(target.text),
                    value = form.items[i+1],
                })
                i += 2
            }
        case:
            return bindings, Compile_Error{message = "unsupported binding target", span = target.span}, false
        }
    }
    return bindings, {}, true
}

emit_body_forms :: proc(e: ^Emitter, body: []CST_Form, returns: Return_Spec) -> (Compile_Error, bool) {
    for form, idx in body {
        last := idx == len(body)-1
        err_stmt, ok_stmt := emit_stmt(e, form, last, returns)
        if !ok_stmt {
            return err_stmt, false
        }
    }
    return {}, true
}

returns_when_final :: proc(last_in_proc: bool, returns: Return_Spec) -> Return_Spec {
    if last_in_proc {
        return returns
    }
    return Return_Spec{kind = .None}
}

emit_if_like :: proc(e: ^Emitter, head: string, form: CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    if len(form.items) < 3 || len(form.items) > 4 {
        return Compile_Error{message = fmt.tprintf("%s expects test, then, and optional else", head), span = form.span}, false
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
    branch_returns := returns_when_final(last_in_proc, returns)
    err_then, ok_then := emit_stmt(e, form.items[2], last_in_proc, branch_returns)
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
        err_else, ok_else := emit_stmt(e, form.items[3], last_in_proc, branch_returns)
        if !ok_else {
            return err_else, false
        }
        e.indent -= 1
        emit_line(e, "}")
    }
    return {}, true
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
            } else {
                strings.write_string(&e.builder, "else if ")
            }
            strings.write_string(&e.builder, test)
            strings.write_string(&e.builder, " {")
            emit_raw_newline(e)
        }

        e.indent += 1
        err_body, ok_body := emit_stmt(e, body_form, last_in_proc, branch_returns)
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
    old_allocator := fmt.tprintf("odinl_old_allocator_%d", e.temp_counter)
    emit_line(e, "{")
    e.indent += 1
    emit_prefixed_expr(e, fmt.tprintf("%s := ", allocator_name), allocator_expr)
    emit_line(e, fmt.tprintf("%s := context.allocator", old_allocator))
    emit_line(e, fmt.tprintf("context.allocator = %s", allocator_name))
    emit_line(e, fmt.tprintf("defer context.allocator = %s", old_allocator))

    body: [dynamic]CST_Form
    for item in form.items[2:] {
        append(&body, item)
    }
    err_body, ok_body := emit_body_forms(e, body[:], returns_when_final(last_in_proc, returns))
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
    temp_scope := fmt.tprintf("odinl_temp_scope_%d", e.temp_counter)
    e.temp_counter += 1
    old_allocator := fmt.tprintf("odinl_old_allocator_%d", e.temp_counter)

    emit_line(e, "{")
    e.indent += 1
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
    if !ok_body {
        return err_body, false
    }

    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

with_delete_names_contains :: proc(binding_names: []string, name: string) -> bool {
    for binding_name in binding_names {
        if binding_name == name {
            return true
        }
    }
    return false
}

with_delete_return_error :: proc(body: []CST_Form, binding_names: []string, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    for item in body {
        if item.kind != .List || len(item.items) == 0 || item.items[0].kind != .Symbol || item.items[0].text != "return" {
            continue
        }
        for returned in item.items[1:] {
            if returned.kind == .Symbol && with_delete_names_contains(binding_names, map_name(returned.text)) {
                return Compile_Error{
                    message = "with-delete binding cannot be returned; return it without with-delete or copy it before returning",
                    span = returned.span,
                }, true
            }
        }
    }
    if last_in_proc && returns.kind != .None && len(body) > 0 {
        final_form := body[len(body)-1]
        if final_form.kind == .Symbol && with_delete_names_contains(binding_names, map_name(final_form.text)) {
            return Compile_Error{
                message = "with-delete binding cannot be returned; return it without with-delete or copy it before returning",
                span = final_form.span,
            }, true
        }
    }
    return {}, false
}

emit_with_delete_stmt :: proc(e: ^Emitter, form: CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    if len(form.items) < 3 {
        return Compile_Error{message = "with-delete expects binding vector and body", span = form.span}, false
    }
    binding := form.items[1]
    if binding.kind != .Vector || len(binding.items) < 2 || len(binding.items)%2 != 0 {
        return Compile_Error{message = "with-delete expects [name value ...] bindings", span = binding.span}, false
    }

    binding_names: [dynamic]string
    i := 0
    for i < len(binding.items) {
        if binding.items[i].kind != .Symbol {
            return Compile_Error{message = "with-delete binding name must be a symbol", span = binding.items[i].span}, false
        }
        append(&binding_names, map_name(binding.items[i].text))
        i += 2
    }

    body: [dynamic]CST_Form
    for item in form.items[2:] {
        append(&body, item)
    }
    err_return, bad_return := with_delete_return_error(body[:], binding_names[:], last_in_proc, returns)
    if bad_return {
        return err_return, false
    }

    emit_line(e, "{")
    e.indent += 1
    i = 0
    for i < len(binding.items) {
        binding_name := binding_names[i/2]
        value_form := binding.items[i+1]
        err_owned, bad_owned := owned_result_usage_error(value_form, true)
        if bad_owned {
            return err_owned, false
        }
        value, err_value, ok_value := emit_expr(e, value_form)
        if !ok_value {
            return err_value, false
        }
        emit_prefixed_expr(e, fmt.tprintf("%s := ", binding_name), value)
        emit_line(e, fmt.tprintf("defer delete(%s)", binding_name))
        i += 2
    }

    err_body, ok_body := emit_body_forms(e, body[:], returns_when_final(last_in_proc, returns))
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
    } else {
        subject, err_subject, ok_subject := emit_expr(e, form.items[1])
        if !ok_subject {
            return err_subject, false
        }
        strings.write_string(&e.builder, subject)
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
            emit_line(e, label)
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
            emit_prefixed_expr(e, "return ", expr)
        } else {
            emit_prefixed_expr(e, "", expr)
        }
        return {}, true
    }

    if len(form.items) == 0 {
        return Compile_Error{message = "empty list statement", span = form.span}, false
    }

    if form.items[0].kind == .Keyword {
        expr, err_expr, ok_expr := emit_expr(e, form)
        if !ok_expr {
            return err_expr, false
        }
        if last_in_proc && returns.kind != .None {
            emit_prefixed_expr(e, "return ", expr)
        } else {
            emit_prefixed_expr(e, "", expr)
        }
        return {}, true
    }

    head := form.items[0]
    if head.kind != .Symbol {
        return Compile_Error{message = "unsupported statement head", span = head.span}, false
    }

    if last_in_proc && returns.kind != .None {
        err_thread_return, bad_thread_return := thread_return_error(form)
        if bad_thread_return {
            return err_thread_return, false
        }
    }

    switch head.text {
    case "comment":
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
        }
        scoped := !last_in_proc
        if scoped {
            emit_line(e, "{")
            e.indent += 1
        }
        for binding in bindings {
            if is_thread_form(binding.value, true) {
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
                value, err_value, ok_value := emit_expr(e, binding.value)
                if !ok_value {
                    return err_value, false
                }
                emit_binding_assignment(e, binding, value)
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
    case "do":
        emit_line(e, "{")
        e.indent += 1
        body: [dynamic]CST_Form
        for item in form.items[1:] {
            append(&body, item)
        }
        err_body, ok_body := emit_body_forms(e, body[:], returns_when_final(last_in_proc, returns))
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "when":
        if len(form.items) < 3 {
            return Compile_Error{message = "when expects test and body", span = form.span}, false
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
        body: [dynamic]CST_Form
        for item in form.items[2:] {
            append(&body, item)
        }
        err_body, ok_body := emit_body_forms(e, body[:], returns_when_final(last_in_proc, returns))
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "if":
        return emit_if_like(e, "if", form, last_in_proc, returns)
    case "cond":
        return emit_cond_stmt(e, form, last_in_proc, returns)
    case "with-allocator":
        return emit_with_allocator_stmt(e, form, last_in_proc, returns)
    case "with-temp-allocator":
        return emit_with_temp_allocator_stmt(e, form, last_in_proc, returns)
    case "with-delete":
        return emit_with_delete_stmt(e, form, last_in_proc, returns)
    case "switch":
        return emit_switch_stmt(e, form, last_in_proc, returns)
    case "return":
        if len(form.items) == 1 {
            emit_line(e, "return")
            return {}, true
        }
        if len(form.items) == 2 {
            err_thread_return, bad_thread_return := thread_return_error(form.items[1])
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
            emit_prefixed_expr(e, "return ", value)
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
        emit_line(e, strings.clone(strings.to_string(line_builder)))
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
                case "if", "when", "cond", "switch", "let", "do":
                case:
                    expr, err_expr, ok_expr := emit_expr(e, deferred)
                    if !ok_expr {
                        return err_expr, false
                    }
                    emit_line(e, fmt.tprintf("defer %s", expr))
                    return {}, true
                }
            } else {
                expr, err_expr, ok_expr := emit_expr(e, deferred)
                if !ok_expr {
                    return err_expr, false
                }
                emit_line(e, fmt.tprintf("defer %s", expr))
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
        emit_line(e, fmt.tprintf("%s = %s", lhs, rhs))
        return {}, true
    case "each":
        body_start := 3
        name_form: CST_Form
        value_form: CST_Form
        coll_form: CST_Form
        has_value := false
        if len(form.items) >= 4 && form.items[1].kind == .Symbol {
            name_form = form.items[1]
            coll_form = form.items[2]
        } else if len(form.items) >= 3 && form.items[1].kind == .Vector && len(form.items[1].items) == 2 && form.items[1].items[0].kind == .Symbol {
            name_form = form.items[1].items[0]
            coll_form = form.items[1].items[1]
            body_start = 2
        } else if len(form.items) >= 3 && form.items[1].kind == .Vector && len(form.items[1].items) == 3 &&
                  form.items[1].items[0].kind == .Symbol && form.items[1].items[1].kind == .Symbol {
            name_form = form.items[1].items[0]
            value_form = form.items[1].items[1]
            coll_form = form.items[1].items[2]
            has_value = true
            body_start = 2
        } else {
            return Compile_Error{message = "each expects [name collection] or [key value collection] and body", span = form.span}, false
        }
        name := map_name(name_form.text)
        value := map_name(value_form.text)
        err_owned, bad_owned := owned_result_usage_error(coll_form, false)
        if bad_owned {
            return err_owned, false
        }
        coll, err_coll, ok_coll := emit_expr(e, coll_form)
        if !ok_coll {
            return err_coll, false
        }
        emit_indent(e)
        strings.write_string(&e.builder, "for ")
        strings.write_string(&e.builder, name)
        if has_value {
            strings.write_string(&e.builder, ", ")
            strings.write_string(&e.builder, value)
        }
        strings.write_string(&e.builder, " in ")
        strings.write_string(&e.builder, coll)
        strings.write_string(&e.builder, " {")
        emit_raw_newline(e)
        e.indent += 1
        body: [dynamic]CST_Form
        for item in form.items[body_start:] {
            append(&body, item)
        }
        err_body, ok_body := emit_body_forms(e, body[:], Return_Spec{kind = .None})
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "for":
        if len(form.items) < 3 {
            return Compile_Error{message = "for expects condition and body", span = form.span}, false
        }
        cond, err_cond, ok_cond := emit_expr(e, form.items[1])
        if !ok_cond {
            return err_cond, false
        }
        emit_indent(e)
        strings.write_string(&e.builder, "for ")
        strings.write_string(&e.builder, cond)
        strings.write_string(&e.builder, " {")
        emit_raw_newline(e)
        e.indent += 1
        body: [dynamic]CST_Form
        for item in form.items[2:] {
            append(&body, item)
        }
        err_body, ok_body := emit_body_forms(e, body[:], Return_Spec{kind = .None})
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
        err_owned, bad_owned := owned_result_usage_error(form, allow_root_owned)
        if bad_owned {
            return err_owned, false
        }
        expr, err_expr, ok_expr := emit_expr(e, form)
        if !ok_expr {
            return err_expr, false
        }
        if last_in_proc && returns.kind != .None {
            emit_prefixed_expr(e, "return ", expr)
        } else {
            emit_prefixed_expr(e, "", expr)
        }
        return {}, true
    }
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
        if decl.import_decl.has_alias {
            emit_line(e, fmt.tprintf("import %s %s", decl.import_decl.alias, decl.import_decl.path))
        } else {
            emit_line(e, fmt.tprintf("import %s", decl.import_decl.path))
        }
    case .Const:
        value, err_value, ok_value := emit_expr(e, decl.const_decl.value)
        if !ok_value {
            return err_value, false
        }
        if decl.const_decl.has_ty {
            emit_line(e, fmt.tprintf("%s: %s : %s", decl.const_decl.name, decl.const_decl.ty, value))
        } else {
            emit_line(e, fmt.tprintf("%s :: %s", decl.const_decl.name, value))
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
        emit_indent(e)
        fmt.sbprintf(&e.builder, "%s :: ", decl.proc_decl.name)
        emit_proc_directives(e, e.pending_prefix_directives[:])
        emit_proc_directives(e, decl.proc_decl.prefix_directives[:])
        strings.write_string(&e.builder, "proc(")
        for param, idx in decl.proc_decl.params {
            if idx > 0 {
                strings.write_string(&e.builder, ", ")
            }
            fmt.sbprintf(&e.builder, "%s: %s", param.name, param.ty)
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

emit_core_map_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_map :: proc(f: proc(x: $T) -> $U, xs: []T) -> [dynamic]U {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]U)")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "append(&out, f(x))")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_map_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("odinl_map_field_%s :: proc($Field_Type: typeid, xs: []$T) -> [dynamic]Field_Type %s", field, "{"))
    e.indent += 1
    emit_line(e, "out := make([dynamic]Field_Type)")
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
    emit_line(e, "odinl_filter :: proc(pred: proc(x: $T) -> bool, xs: []T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T)")
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

emit_core_filter_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("odinl_filter_field_%s :: proc(xs: []$T) -> [dynamic]T %s", field, "{"))
    e.indent += 1
    emit_line(e, "out := make([dynamic]T)")
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
    emit_line(e, "odinl_filter_in_place :: proc(pred: proc(x: $T) -> bool, xs: ^[dynamic]T) {")
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

emit_core_filter_in_place_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("odinl_filter_in_place_field_%s :: proc(xs: ^[dynamic]$T) %s", field, "{"))
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
    emit_line(e, "odinl_remove :: proc(pred: proc(x: $T) -> bool, xs: []T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T)")
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

emit_core_remove_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("odinl_remove_field_%s :: proc(xs: []$T) -> [dynamic]T %s", field, "{"))
    e.indent += 1
    emit_line(e, "out := make([dynamic]T)")
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
    emit_line(e, "odinl_remove_in_place :: proc(pred: proc(x: $T) -> bool, xs: ^[dynamic]T) {")
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

emit_core_remove_in_place_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("odinl_remove_in_place_field_%s :: proc(xs: ^[dynamic]$T) %s", field, "{"))
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

emit_core_map_indexed_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_map_indexed :: proc(f: proc(i: int, x: $T) -> $U, xs: []T) -> [dynamic]U {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]U)")
    emit_line(e, "for x, i in xs {")
    e.indent += 1
    emit_line(e, "append(&out, f(i, x))")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_map_in_place_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_map_in_place :: proc(f: proc(x: $T) -> T, xs: []T) {")
    e.indent += 1
    emit_line(e, "for i in 0..<len(xs) {")
    e.indent += 1
    emit_line(e, "xs[i] = f(xs[i])")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_map_indexed_in_place_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_map_indexed_in_place :: proc(f: proc(i: int, x: $T) -> T, xs: []T) {")
    e.indent += 1
    emit_line(e, "for i in 0..<len(xs) {")
    e.indent += 1
    emit_line(e, "xs[i] = f(i, xs[i])")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_keep_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_keep :: proc(f: proc(x: $T) -> ($U, bool), xs: []T) -> [dynamic]U {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]U)")
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

emit_core_keep_in_place_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_keep_in_place :: proc(f: proc(x: $T) -> (T, bool), xs: ^[dynamic]T) {")
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

emit_core_mapcat_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_mapcat :: proc(f: proc(x: $T) -> []$U, xs: []T) -> [dynamic]U {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]U)")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "append(&out, ..f(x))")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_concat_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_concat :: proc(xs, ys: []$T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T, 0, len(xs)+len(ys))")
    emit_line(e, "append(&out, ..xs)")
    emit_line(e, "append(&out, ..ys)")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_merge_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_merge :: proc(lhs, rhs: map[$K]$V) -> map[K]V {")
    e.indent += 1
    emit_line(e, "out := make(map[K]V)")
    emit_line(e, "for key, value in lhs {")
    e.indent += 1
    emit_line(e, "out[key] = value")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "for key, value in rhs {")
    e.indent += 1
    emit_line(e, "out[key] = value")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_merge_in_place_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_merge_in_place :: proc(target: ^map[$K]$V, source: map[K]V) {")
    e.indent += 1
    emit_line(e, "for key, value in source {")
    e.indent += 1
    emit_line(e, "target^[key] = value")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_get_or_default_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_get_or_default :: proc(m: map[$K]$V, key: K, default: V) -> V {")
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

emit_core_into_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_into :: proc($Out: typeid, xs: []$T) -> Out {")
    e.indent += 1
    emit_line(e, "out := make(Out, 0, len(xs))")
    emit_line(e, "append(&out, ..xs)")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_interpose_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_interpose :: proc(sep: $T, xs: []T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T)")
    emit_line(e, "if len(xs) == 0 {")
    e.indent += 1
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "append(&out, xs[0])")
    emit_line(e, "for x in xs[1:] {")
    e.indent += 1
    emit_line(e, "append(&out, sep)")
    emit_line(e, "append(&out, x)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_interleave_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_interleave :: proc(xs, ys: []$T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "n := len(xs)")
    emit_line(e, "if len(ys) < n {")
    e.indent += 1
    emit_line(e, "n = len(ys)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "out := make([dynamic]T, 0, n*2)")
    emit_line(e, "for i := 0; i < n; i += 1 {")
    e.indent += 1
    emit_line(e, "append(&out, xs[i])")
    emit_line(e, "append(&out, ys[i])")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_reverse_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_reverse :: proc(xs: []$T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T, 0, len(xs))")
    emit_line(e, "for i := len(xs)-1; i >= 0; i -= 1 {")
    e.indent += 1
    emit_line(e, "append(&out, xs[i])")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_reverse_in_place_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_reverse_in_place :: proc(xs: []$T) {")
    e.indent += 1
    emit_line(e, "for i := 0; i < len(xs)/2; i += 1 {")
    e.indent += 1
    emit_line(e, "j := len(xs)-1-i")
    emit_line(e, "xs[i], xs[j] = xs[j], xs[i]")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_shuffle_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_shuffle :: proc(pick: proc(n: int) -> int, xs: []$T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T, 0, len(xs))")
    emit_line(e, "append(&out, ..xs)")
    emit_line(e, "for i := len(out)-1; i > 0; i -= 1 {")
    e.indent += 1
    emit_line(e, "j := pick(i+1)")
    emit_line(e, "out[i], out[j] = out[j], out[i]")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_shuffle_in_place_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_shuffle_in_place :: proc(pick: proc(n: int) -> int, xs: []$T) {")
    e.indent += 1
    emit_line(e, "for i := len(xs)-1; i > 0; i -= 1 {")
    e.indent += 1
    emit_line(e, "j := pick(i+1)")
    emit_line(e, "xs[i], xs[j] = xs[j], xs[i]")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_sort_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_sort :: proc(xs: []$T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T, 0, len(xs))")
    emit_line(e, "append(&out, ..xs)")
    emit_line(e, "for i := 1; i < len(out); i += 1 {")
    e.indent += 1
    emit_line(e, "for j := i; j > 0 && out[j] < out[j-1]; j -= 1 {")
    e.indent += 1
    emit_line(e, "out[j], out[j-1] = out[j-1], out[j]")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_sort_in_place_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_sort_in_place :: proc(xs: []$T) {")
    e.indent += 1
    emit_line(e, "for i := 1; i < len(xs); i += 1 {")
    e.indent += 1
    emit_line(e, "for j := i; j > 0 && xs[j] < xs[j-1]; j -= 1 {")
    e.indent += 1
    emit_line(e, "xs[j], xs[j-1] = xs[j-1], xs[j]")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_sort_by_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_sort_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T, 0, len(xs))")
    emit_line(e, "append(&out, ..xs)")
    emit_line(e, "for i := 1; i < len(out); i += 1 {")
    e.indent += 1
    emit_line(e, "for j := i; j > 0 && f(out[j]) < f(out[j-1]); j -= 1 {")
    e.indent += 1
    emit_line(e, "out[j], out[j-1] = out[j-1], out[j]")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_sort_by_in_place_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_sort_by_in_place :: proc(f: proc(x: $T) -> $K, xs: []T) {")
    e.indent += 1
    emit_line(e, "for i := 1; i < len(xs); i += 1 {")
    e.indent += 1
    emit_line(e, "for j := i; j > 0 && f(xs[j]) < f(xs[j-1]); j -= 1 {")
    e.indent += 1
    emit_line(e, "xs[j], xs[j-1] = xs[j-1], xs[j]")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_sort_by_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("odinl_sort_by_field_%s :: proc($Key: typeid, xs: []$T) -> [dynamic]T %s", field, "{"))
    e.indent += 1
    emit_line(e, "out := make([dynamic]T, 0, len(xs))")
    emit_line(e, "append(&out, ..xs)")
    emit_line(e, "for i := 1; i < len(out); i += 1 {")
    e.indent += 1
    emit_line(e, fmt.tprintf("for j := i; j > 0 && out[j].%s < out[j-1].%s; j -= 1 %s", field, field, "{"))
    e.indent += 1
    emit_line(e, "out[j], out[j-1] = out[j-1], out[j]")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_sort_by_in_place_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("odinl_sort_by_in_place_field_%s :: proc(xs: []$T) %s", field, "{"))
    e.indent += 1
    emit_line(e, "for i := 1; i < len(xs); i += 1 {")
    e.indent += 1
    emit_line(e, fmt.tprintf("for j := i; j > 0 && xs[j].%s < xs[j-1].%s; j -= 1 %s", field, field, "{"))
    e.indent += 1
    emit_line(e, "xs[j], xs[j-1] = xs[j-1], xs[j]")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_split_at_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_split_at :: proc(n: int, xs: []$T) -> (left: []T, right: []T) {")
    e.indent += 1
    emit_line(e, "mid := n")
    emit_line(e, "if mid < 0 {")
    e.indent += 1
    emit_line(e, "mid = 0")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "if mid > len(xs) {")
    e.indent += 1
    emit_line(e, "mid = len(xs)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return xs[:mid], xs[mid:]")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_partition_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_partition :: proc(n: int, xs: []$T) -> [dynamic][]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic][]T)")
    emit_line(e, "if n <= 0 {")
    e.indent += 1
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "for start := 0; start+n <= len(xs); start += n {")
    e.indent += 1
    emit_line(e, "append(&out, xs[start:start+n])")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_partition_all_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_partition_all :: proc(n: int, xs: []$T) -> [dynamic][]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic][]T)")
    emit_line(e, "if n <= 0 {")
    e.indent += 1
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "for start := 0; start < len(xs); start += n {")
    e.indent += 1
    emit_line(e, "end := start+n")
    emit_line(e, "if end > len(xs) {")
    e.indent += 1
    emit_line(e, "end = len(xs)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "append(&out, xs[start:end])")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_partition_by_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_partition_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> [dynamic][]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic][]T)")
    emit_line(e, "if len(xs) == 0 {")
    e.indent += 1
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "start := 0")
    emit_line(e, "last_key := f(xs[0])")
    emit_line(e, "for i := 1; i < len(xs); i += 1 {")
    e.indent += 1
    emit_line(e, "key := f(xs[i])")
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

emit_core_partition_by_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("odinl_partition_by_field_%s :: proc($Key: typeid, xs: []$T) -> [dynamic][]T %s", field, "{"))
    e.indent += 1
    emit_line(e, "out := make([dynamic][]T)")
    emit_line(e, "if len(xs) == 0 {")
    e.indent += 1
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
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

emit_core_zipmap_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_zipmap :: proc(keys: []$K, values: []$V) -> map[K]V {")
    e.indent += 1
    emit_line(e, "out := make(map[K]V)")
    emit_line(e, "limit := len(keys)")
    emit_line(e, "if limit > len(values) {")
    e.indent += 1
    emit_line(e, "limit = len(values)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "for i in 0..<limit {")
    e.indent += 1
    emit_line(e, "out[keys[i]] = values[i]")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_index_by_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_index_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> map[K]T {")
    e.indent += 1
    emit_line(e, "out := make(map[K]T)")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "out[f(x)] = x")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_index_by_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("odinl_index_by_field_%s :: proc($Key: typeid, xs: []$T) -> map[Key]T %s", field, "{"))
    e.indent += 1
    emit_line(e, "out := make(map[Key]T)")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, fmt.tprintf("out[x.%s] = x", field))
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_group_by_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_group_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> map[K][dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make(map[K][dynamic]T)")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "key := f(x)")
    emit_line(e, "group := out[key]")
    emit_line(e, "append(&group, x)")
    emit_line(e, "out[key] = group")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_group_by_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("odinl_group_by_field_%s :: proc($Key: typeid, xs: []$T) -> map[Key][dynamic]T %s", field, "{"))
    e.indent += 1
    emit_line(e, "out := make(map[Key][dynamic]T)")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, fmt.tprintf("key := x.%s", field))
    emit_line(e, "group := out[key]")
    emit_line(e, "append(&group, x)")
    emit_line(e, "out[key] = group")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_frequencies_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_frequencies :: proc(xs: []$T) -> map[T]int {")
    e.indent += 1
    emit_line(e, "out := make(map[T]int)")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "out[x] += 1")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_distinct_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_distinct :: proc(xs: []$T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T)")
    emit_line(e, "seen := make(map[T]bool)")
    emit_line(e, "defer delete(seen)")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "if seen[x] {")
    e.indent += 1
    emit_line(e, "continue")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "seen[x] = true")
    emit_line(e, "append(&out, x)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_distinct_by_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_distinct_by :: proc(f: proc(x: $T) -> $K, xs: []T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T)")
    emit_line(e, "seen := make(map[K]bool)")
    emit_line(e, "defer delete(seen)")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "key := f(x)")
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

emit_core_distinct_by_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("odinl_distinct_by_field_%s :: proc($Key: typeid, xs: []$T) -> [dynamic]T %s", field, "{"))
    e.indent += 1
    emit_line(e, "out := make([dynamic]T)")
    emit_line(e, "seen := make(map[Key]bool)")
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

emit_core_keys_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_keys :: proc(m: map[$K]$V) -> [dynamic]K {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]K, 0, len(m))")
    emit_line(e, "for k in m {")
    e.indent += 1
    emit_line(e, "append(&out, k)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_vals_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_vals :: proc(m: map[$K]$V) -> [dynamic]V {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]V, 0, len(m))")
    emit_line(e, "for _, v in m {")
    e.indent += 1
    emit_line(e, "append(&out, v)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_range_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_range :: proc(start, end, step: int) -> [dynamic]int {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]int)")
    emit_line(e, "if step == 0 {")
    e.indent += 1
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "if step > 0 {")
    e.indent += 1
    emit_line(e, "for i := start; i < end; i += step {")
    e.indent += 1
    emit_line(e, "append(&out, i)")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "} else {")
    e.indent += 1
    emit_line(e, "for i := start; i > end; i += step {")
    e.indent += 1
    emit_line(e, "append(&out, i)")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_repeat_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_repeat :: proc(n: int, value: $T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T)")
    emit_line(e, "if n <= 0 {")
    e.indent += 1
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "for i in 0..<n {")
    e.indent += 1
    emit_line(e, "append(&out, value)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_repeatedly_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_repeatedly :: proc(n: int, f: proc() -> $T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T)")
    emit_line(e, "if n <= 0 {")
    e.indent += 1
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "for i in 0..<n {")
    e.indent += 1
    emit_line(e, "append(&out, f())")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_iterate_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_iterate :: proc(n: int, f: proc(x: $T) -> T, init: T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T)")
    emit_line(e, "if n <= 0 {")
    e.indent += 1
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "value := init")
    emit_line(e, "for i in 0..<n {")
    e.indent += 1
    emit_line(e, "append(&out, value)")
    emit_line(e, "value = f(value)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_cycle_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_cycle :: proc(n: int, xs: []$T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T)")
    emit_line(e, "if n <= 0 || len(xs) == 0 {")
    e.indent += 1
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "for i in 0..<n {")
    e.indent += 1
    emit_line(e, "append(&out, xs[i%len(xs)])")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_save_json_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_save_json :: proc(path: string, value: $T) -> (marshal_err: json.Marshal_Error, write_err: os.Error) {")
    e.indent += 1
    emit_line(e, "data: []byte")
    emit_line(e, "data, marshal_err = json.marshal(value)")
    emit_line(e, "if marshal_err != nil {")
    e.indent += 1
    emit_line(e, "return")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "defer delete(data)")
    emit_line(e, "write_err = os.write_entire_file(path, data)")
    emit_line(e, "return")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_load_json_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_load_json :: proc($T: typeid, path: string) -> (value: T, read_err: os.Error, unmarshal_err: json.Unmarshal_Error) {")
    e.indent += 1
    emit_line(e, "data: []byte")
    emit_line(e, "data, read_err = os.read_entire_file(path, context.allocator)")
    emit_line(e, "if read_err != nil {")
    e.indent += 1
    emit_line(e, "return")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "defer delete(data)")
    emit_line(e, "unmarshal_err = json.unmarshal(data, &value)")
    emit_line(e, "return")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_tap_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_tap :: proc(value: $T) -> T {")
    e.indent += 1
    emit_line(e, "fmt.println(value)")
    emit_line(e, "return value")
    e.indent -= 1
    emit_line(e, "}")
    emit_raw_newline(e)
    emit_line(e, "odinl_tap_labeled :: proc(label: string, value: $T) -> T {")
    e.indent += 1
    emit_line(e, "fmt.print(label)")
    emit_line(e, "fmt.print(\": \")")
    emit_line(e, "fmt.println(value)")
    emit_line(e, "return value")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_reduce_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_reduce :: proc(f: proc(acc: $U, x: $T) -> U, init: U, xs: []T) -> U {")
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

emit_core_take_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_take :: proc(n: int, xs: []$T) -> []T {")
    e.indent += 1
    emit_line(e, "limit := n")
    emit_line(e, "if limit < 0 {")
    e.indent += 1
    emit_line(e, "limit = 0")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "if limit > len(xs) {")
    e.indent += 1
    emit_line(e, "limit = len(xs)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return xs[:limit]")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_drop_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_drop :: proc(n: int, xs: []$T) -> []T {")
    e.indent += 1
    emit_line(e, "start := n")
    emit_line(e, "if start < 0 {")
    e.indent += 1
    emit_line(e, "start = 0")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "if start > len(xs) {")
    e.indent += 1
    emit_line(e, "start = len(xs)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return xs[start:]")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_drop_last_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_drop_last :: proc(n: int, xs: []$T) -> []T {")
    e.indent += 1
    emit_line(e, "end := len(xs) - n")
    emit_line(e, "if end < 0 {")
    e.indent += 1
    emit_line(e, "end = 0")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "if end > len(xs) {")
    e.indent += 1
    emit_line(e, "end = len(xs)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return xs[:end]")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_take_while_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_take_while :: proc(pred: proc(x: $T) -> bool, xs: []T) -> []T {")
    e.indent += 1
    emit_line(e, "for i in 0..<len(xs) {")
    e.indent += 1
    emit_line(e, "if !pred(xs[i]) {")
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

emit_core_take_while_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("odinl_take_while_field_%s :: proc(xs: []$T) -> []T %s", field, "{"))
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

emit_core_drop_while_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_drop_while :: proc(pred: proc(x: $T) -> bool, xs: []T) -> []T {")
    e.indent += 1
    emit_line(e, "for i in 0..<len(xs) {")
    e.indent += 1
    emit_line(e, "if !pred(xs[i]) {")
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

emit_core_drop_while_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("odinl_drop_while_field_%s :: proc(xs: []$T) -> []T %s", field, "{"))
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

emit_core_find_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_find :: proc(pred: proc(x: $T) -> bool, xs: []T) -> (value: T, ok: bool) {")
    e.indent += 1
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "if pred(x) {")
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

emit_core_find_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("odinl_find_field_%s :: proc(xs: []$T) -> (value: T, ok: bool) %s", field, "{"))
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

emit_core_some_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_some_p :: proc(pred: proc(x: $T) -> bool, xs: []T) -> bool {")
    e.indent += 1
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "if pred(x) {")
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

emit_core_some_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("odinl_some_p_field_%s :: proc(xs: []$T) -> bool %s", field, "{"))
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

emit_core_every_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_every_p :: proc(pred: proc(x: $T) -> bool, xs: []T) -> bool {")
    e.indent += 1
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "if !pred(x) {")
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

emit_core_every_field_helper :: proc(e: ^Emitter, field: string) {
    emit_line(e, fmt.tprintf("odinl_every_p_field_%s :: proc(xs: []$T) -> bool %s", field, "{"))
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
    return features.core_map || features.core_filter || features.core_reduce ||
           features.core_take || features.core_drop ||
           features.core_drop_last ||
           features.core_take_while || features.core_drop_while ||
           features.core_find || features.core_some || features.core_every ||
           features.core_remove || features.core_map_indexed || features.core_keep ||
           features.core_mapcat || features.core_concat ||
           features.core_merge || features.core_merge_in_place ||
           features.core_get_or_default ||
           features.core_into ||
           features.core_interpose || features.core_interleave ||
           features.core_reverse || features.core_reverse_in_place ||
           features.core_shuffle || features.core_shuffle_in_place ||
           features.core_map_in_place || features.core_map_indexed_in_place ||
           features.core_filter_in_place || features.core_remove_in_place ||
           features.core_keep_in_place ||
           features.core_sort || features.core_sort_by ||
           features.core_sort_in_place || features.core_sort_by_in_place ||
           features.core_split_at || features.core_partition ||
           features.core_partition_all || features.core_partition_by ||
           features.core_zipmap ||
           features.core_index_by || features.core_group_by ||
           features.core_frequencies ||
           features.core_keys || features.core_vals ||
           features.core_distinct || features.core_distinct_by ||
           features.core_range || features.core_repeat ||
           features.core_repeatedly || features.core_iterate ||
           features.core_cycle || features.core_save_json || features.core_load_json ||
           features.core_tap ||
           len(features.map_fields) > 0 || len(features.index_by_fields) > 0 ||
           len(features.group_by_fields) > 0 ||
           len(features.distinct_by_fields) > 0 ||
           len(features.partition_by_fields) > 0 ||
           len(features.sort_by_fields) > 0 ||
           len(features.sort_by_in_place_fields) > 0 ||
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
    for field in features.map_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_map_field_helper(e, field)
    }
    if features.core_filter {
        emit_core_helper_separator(e, &emitted)
        emit_core_filter_helper(e)
    }
    for field in features.filter_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_filter_field_helper(e, field)
    }
    if features.core_filter_in_place {
        emit_core_helper_separator(e, &emitted)
        emit_core_filter_in_place_helper(e)
    }
    for field in features.filter_in_place_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_filter_in_place_field_helper(e, field)
    }
    if features.core_remove {
        emit_core_helper_separator(e, &emitted)
        emit_core_remove_helper(e)
    }
    for field in features.remove_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_remove_field_helper(e, field)
    }
    if features.core_remove_in_place {
        emit_core_helper_separator(e, &emitted)
        emit_core_remove_in_place_helper(e)
    }
    for field in features.remove_in_place_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_remove_in_place_field_helper(e, field)
    }
    if features.core_map_indexed {
        emit_core_helper_separator(e, &emitted)
        emit_core_map_indexed_helper(e)
    }
    if features.core_map_in_place {
        emit_core_helper_separator(e, &emitted)
        emit_core_map_in_place_helper(e)
    }
    if features.core_map_indexed_in_place {
        emit_core_helper_separator(e, &emitted)
        emit_core_map_indexed_in_place_helper(e)
    }
    if features.core_keep {
        emit_core_helper_separator(e, &emitted)
        emit_core_keep_helper(e)
    }
    if features.core_keep_in_place {
        emit_core_helper_separator(e, &emitted)
        emit_core_keep_in_place_helper(e)
    }
    if features.core_mapcat {
        emit_core_helper_separator(e, &emitted)
        emit_core_mapcat_helper(e)
    }
    if features.core_concat {
        emit_core_helper_separator(e, &emitted)
        emit_core_concat_helper(e)
    }
    if features.core_merge {
        emit_core_helper_separator(e, &emitted)
        emit_core_merge_helper(e)
    }
    if features.core_merge_in_place {
        emit_core_helper_separator(e, &emitted)
        emit_core_merge_in_place_helper(e)
    }
    if features.core_get_or_default {
        emit_core_helper_separator(e, &emitted)
        emit_core_get_or_default_helper(e)
    }
    if features.core_into {
        emit_core_helper_separator(e, &emitted)
        emit_core_into_helper(e)
    }
    if features.core_interpose {
        emit_core_helper_separator(e, &emitted)
        emit_core_interpose_helper(e)
    }
    if features.core_interleave {
        emit_core_helper_separator(e, &emitted)
        emit_core_interleave_helper(e)
    }
    if features.core_reverse {
        emit_core_helper_separator(e, &emitted)
        emit_core_reverse_helper(e)
    }
    if features.core_reverse_in_place {
        emit_core_helper_separator(e, &emitted)
        emit_core_reverse_in_place_helper(e)
    }
    if features.core_shuffle {
        emit_core_helper_separator(e, &emitted)
        emit_core_shuffle_helper(e)
    }
    if features.core_shuffle_in_place {
        emit_core_helper_separator(e, &emitted)
        emit_core_shuffle_in_place_helper(e)
    }
    if features.core_sort {
        emit_core_helper_separator(e, &emitted)
        emit_core_sort_helper(e)
    }
    if features.core_sort_by {
        emit_core_helper_separator(e, &emitted)
        emit_core_sort_by_helper(e)
    }
    if features.core_sort_in_place {
        emit_core_helper_separator(e, &emitted)
        emit_core_sort_in_place_helper(e)
    }
    if features.core_sort_by_in_place {
        emit_core_helper_separator(e, &emitted)
        emit_core_sort_by_in_place_helper(e)
    }
    for field in features.sort_by_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_sort_by_field_helper(e, field)
    }
    for field in features.sort_by_in_place_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_sort_by_in_place_field_helper(e, field)
    }
    if features.core_split_at {
        emit_core_helper_separator(e, &emitted)
        emit_core_split_at_helper(e)
    }
    if features.core_partition {
        emit_core_helper_separator(e, &emitted)
        emit_core_partition_helper(e)
    }
    if features.core_partition_all {
        emit_core_helper_separator(e, &emitted)
        emit_core_partition_all_helper(e)
    }
    if features.core_partition_by {
        emit_core_helper_separator(e, &emitted)
        emit_core_partition_by_helper(e)
    }
    for field in features.partition_by_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_partition_by_field_helper(e, field)
    }
    if features.core_zipmap {
        emit_core_helper_separator(e, &emitted)
        emit_core_zipmap_helper(e)
    }
    if features.core_index_by {
        emit_core_helper_separator(e, &emitted)
        emit_core_index_by_helper(e)
    }
    for field in features.index_by_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_index_by_field_helper(e, field)
    }
    if features.core_group_by {
        emit_core_helper_separator(e, &emitted)
        emit_core_group_by_helper(e)
    }
    for field in features.group_by_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_group_by_field_helper(e, field)
    }
    if features.core_frequencies {
        emit_core_helper_separator(e, &emitted)
        emit_core_frequencies_helper(e)
    }
    if features.core_keys {
        emit_core_helper_separator(e, &emitted)
        emit_core_keys_helper(e)
    }
    if features.core_vals {
        emit_core_helper_separator(e, &emitted)
        emit_core_vals_helper(e)
    }
    if features.core_distinct {
        emit_core_helper_separator(e, &emitted)
        emit_core_distinct_helper(e)
    }
    if features.core_distinct_by {
        emit_core_helper_separator(e, &emitted)
        emit_core_distinct_by_helper(e)
    }
    for field in features.distinct_by_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_distinct_by_field_helper(e, field)
    }
    if features.core_range {
        emit_core_helper_separator(e, &emitted)
        emit_core_range_helper(e)
    }
    if features.core_repeat {
        emit_core_helper_separator(e, &emitted)
        emit_core_repeat_helper(e)
    }
    if features.core_repeatedly {
        emit_core_helper_separator(e, &emitted)
        emit_core_repeatedly_helper(e)
    }
    if features.core_iterate {
        emit_core_helper_separator(e, &emitted)
        emit_core_iterate_helper(e)
    }
    if features.core_cycle {
        emit_core_helper_separator(e, &emitted)
        emit_core_cycle_helper(e)
    }
    if features.core_save_json {
        emit_core_helper_separator(e, &emitted)
        emit_core_save_json_helper(e)
    }
    if features.core_load_json {
        emit_core_helper_separator(e, &emitted)
        emit_core_load_json_helper(e)
    }
    if features.core_tap {
        emit_core_helper_separator(e, &emitted)
        emit_core_tap_helper(e)
    }
    if features.core_reduce {
        emit_core_helper_separator(e, &emitted)
        emit_core_reduce_helper(e)
    }
    if features.core_take {
        emit_core_helper_separator(e, &emitted)
        emit_core_take_helper(e)
    }
    if features.core_drop {
        emit_core_helper_separator(e, &emitted)
        emit_core_drop_helper(e)
    }
    if features.core_drop_last {
        emit_core_helper_separator(e, &emitted)
        emit_core_drop_last_helper(e)
    }
    if features.core_take_while {
        emit_core_helper_separator(e, &emitted)
        emit_core_take_while_helper(e)
    }
    for field in features.take_while_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_take_while_field_helper(e, field)
    }
    if features.core_drop_while {
        emit_core_helper_separator(e, &emitted)
        emit_core_drop_while_helper(e)
    }
    for field in features.drop_while_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_drop_while_field_helper(e, field)
    }
    if features.core_find {
        emit_core_helper_separator(e, &emitted)
        emit_core_find_helper(e)
    }
    for field in features.find_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_find_field_helper(e, field)
    }
    if features.core_some {
        emit_core_helper_separator(e, &emitted)
        emit_core_some_helper(e)
    }
    for field in features.some_fields {
        emit_core_helper_separator(e, &emitted)
        emit_core_some_field_helper(e, field)
    }
    if features.core_every {
        emit_core_helper_separator(e, &emitted)
        emit_core_every_helper(e)
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

emit_decls_with_source_map :: proc(decls: []IR_Decl) -> (Emit_Result, Compile_Error, bool) {
    result := Emit_Result{}
    features := Emitter_Features{}
    e := Emitter{
        builder  = strings.builder_make(),
        features = &features,
        line     = 1,
    }
    defer strings.builder_destroy(&e.builder)
    for decl in decls {
        if decl.kind == .Union {
            append(&e.unions, decl.union_decl)
        }
    }
    for decl, idx in decls {
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
    emit_core_helpers(&e, features)
    if features.dynamic_literals {
        output_builder := strings.builder_make()
        defer strings.builder_destroy(&output_builder)
        strings.write_string(&output_builder, "#+feature dynamic-literals\n")
        strings.write_string(&output_builder, strings.to_string(e.builder))
        for &entry in result.source_map {
            entry.generated_start_line += 1
            entry.generated_end_line += 1
        }
        result.output = strings.clone(strings.to_string(output_builder))
        return result, {}, true
    }
    result.output = strings.clone(strings.to_string(e.builder))
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

    body: [dynamic]CST_Form
    if no_print {
        append(&body, eval_form)
    } else {
        append(&body, make_println_form(eval_form))
    }

    append(&decls, IR_Decl{
        kind = .Proc,
        span = eval_form.span,
        proc_decl = Proc_Decl{
            name = "main",
            body = body,
        },
    })

    return emit_decls_with_source_map(decls[:])
}

decl_name :: proc(decl: IR_Decl) -> string {
    #partial switch decl.kind {
    case .Const:
        return decl.const_decl.name
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
