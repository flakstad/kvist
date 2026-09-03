package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

Keyword_Args_Call_Mode :: enum {
    Positional,
    Named,
    Ambiguous,
}

Keyword_Args_Call_Resolution :: struct {
    mode:  Keyword_Args_Call_Mode,
    split: int,
}

keyword_arg_tail_is_syntax :: proc(args: []CST_Form, start: int) -> bool {
    if start < 0 || start >= len(args) || (len(args)-start)%2 != 0 {
        return false
    }
    for i := start; i < len(args); i += 2 {
        if args[i].kind != .Keyword || len(args[i].text) <= 1 {
            return false
        }
    }
    return true
}

first_keyword_arg_tail_start :: proc(args: []CST_Form) -> int {
    for start in 0..<len(args) {
        if keyword_arg_tail_is_syntax(args, start) {
            return start
        }
    }
    return -1
}

form_obviously_matches_expected_type :: proc(e: ^Emitter, form: CST_Form, expected_type: string) -> bool {
    if strings.contains(expected_type, "$") || type_text_is_managed_value(e, expected_type) {
        return true
    }
    #partial switch form.kind {
    case .String, .Regex:
        return expected_type == "string"
    case .Bool:
        return expected_type == "bool"
    case .Keyword:
        return expected_type == "keyword"
    case .Number:
        return is_numeric_scalar_type(expected_type)
    case .Brace:
        return type_text_is_map(expected_type)
    case .Vector:
        if _, ok_collection := collection_element_type(expected_type); ok_collection {
            return !type_text_is_map(expected_type)
        }
        return false
    case .Set:
        _, ok_set := set_element_type(expected_type)
        return ok_set
    case:
        return true
    }
}

proc_positional_call_is_viable :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, args: []CST_Form) -> bool {
    if !proc_accepts_positional_arg_count(proc_decl, len(args)) {
        return false
    }
    for arg, idx in args {
        if idx >= len(proc_decl.params) || !form_obviously_matches_expected_type(e, arg, proc_decl.params[idx].ty) {
            return false
        }
    }
    return true
}

proc_named_call_is_viable :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, positional_args, named_args: []CST_Form) -> bool {
    if len(positional_args) > len(proc_decl.params) || len(named_args) == 0 || len(named_args)%2 != 0 {
        return false
    }
    provided := make([]bool, len(proc_decl.params))
    defer delete(provided)
    for idx in 0..<len(positional_args) {
        if !form_obviously_matches_expected_type(e, positional_args[idx], proc_decl.params[idx].ty) {
            return false
        }
        provided[idx] = true
    }
    for i := 0; i < len(named_args); i += 2 {
        field_name, ok_key := brace_key_name(named_args[i])
        if !ok_key {
            return false
        }
        param_idx := -1
        for param, idx in proc_decl.params {
            if param.name == field_name {
                param_idx = idx
                break
            }
        }
        if param_idx < 0 || provided[param_idx] ||
           !form_obviously_matches_expected_type(e, named_args[i+1], proc_decl.params[param_idx].ty) {
            return false
        }
        provided[param_idx] = true
    }
    for param, idx in proc_decl.params {
        if !provided[idx] && !param.has_default {
            return false
        }
    }
    return true
}

keyword_args_call_resolution :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, args: []CST_Form) -> Keyword_Args_Call_Resolution {
    positional_ok := proc_positional_call_is_viable(e, proc_decl, args)
    viable_split := -1
    viable_count := 0
    diagnostic_split := -1

    for start in 0..<len(args) {
        if !keyword_arg_tail_is_syntax(args, start) {
            continue
        }
        first_name, ok_first := brace_key_name(args[start])
        if ok_first {
            if _, ok_param := find_proc_param(proc_decl, first_name); ok_param && diagnostic_split < 0 {
                diagnostic_split = start
            }
        }
        if proc_named_call_is_viable(e, proc_decl, args[:start], args[start:]) {
            viable_split = start
            viable_count += 1
        }
    }

    if viable_count > 1 || (viable_count == 1 && positional_ok) {
        return Keyword_Args_Call_Resolution{mode = .Ambiguous, split = viable_split}
    }
    if viable_count == 1 {
        return Keyword_Args_Call_Resolution{mode = .Named, split = viable_split}
    }
    if positional_ok {
        return Keyword_Args_Call_Resolution{mode = .Positional, split = -1}
    }
    if diagnostic_split >= 0 {
        return Keyword_Args_Call_Resolution{mode = .Named, split = diagnostic_split}
    }
    return Keyword_Args_Call_Resolution{mode = .Positional, split = -1}
}

ambiguous_keyword_args_call_error :: proc(span: Span) -> Compile_Error {
    return Compile_Error{
        message = "keyword arguments are ambiguous with positional keyword values; use (keyword :name) to make a positional keyword value explicit",
        span = span,
    }
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
        if field.has_default {
            value := field.default_value
            delete_cst_form(&value)
        }
    }
    delete(fields^)
}

clone_struct_field_slice :: proc(fields: []Struct_Field) -> (cloned: [dynamic]Struct_Field) {
    for field in fields {
        item := field
        item.name = strings.clone(field.name)
        item.source_name = strings.clone(field.source_name)
        item.ty = strings.clone(field.ty)
        if field.has_default {
            item.default_value = clone_cst_form(field.default_value)
        }
        append(&cloned, item)
    }
    return cloned
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

odin_import_type_is_vector_alias_from_dir :: proc(alias, dir, type_name: string) -> bool {
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
            vector_fields, ok_vector := odin_vector_alias_fields(alias, rhs)
            delete_struct_field_slice(&vector_fields)
            delete(lines)
            delete(data)
            return ok_vector
        }
        delete(lines)
        delete(data)
    }
    return false
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

odin_import_proc_param_types_from_dir :: proc(
    dir, proc_name: string,
) -> (param_types: [dynamic]string, ok: bool) {
    if !os.exists(dir) {
        return param_types, false
    }
    entries, err := os.read_directory_by_path(dir, -1, context.allocator)
    if err != nil {
        return param_types, false
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
            param_types = odin_proc_param_types_from_text(params_text)
            delete(params_text)
            delete(lines)
            delete(data)
            return param_types, true
        }
        delete(lines)
        delete(data)
    }
    return param_types, false
}

imported_odin_proc_arg_type :: proc(e: ^Emitter, head_name: string, arg_idx: int) -> (string, bool) {
    alias, member, ok_parts := imported_call_parts(head_name)
    if !ok_parts {
        return "", false
    }
    ensure_emitter_indexes(e)
    raw, found_import := e.odin_import_paths[alias]
    if !found_import {
        return "", false
    }
    cache_key := emitter_import_cache_key(e, head_name, raw, alias, member)
    if e.import_cache != nil && e.import_cache.proc_params_known[cache_key] {
        if cached, found := e.import_cache.proc_param_types[cache_key];
           found && arg_idx < len(cached) {
            return strings.clone(cached[arg_idx]), true
        }
        return "", false
    }
    if e.import_cache != nil {
        e.import_cache.proc_params_known[cache_key] = true
    }
    odin_root, ok_root := emitter_odin_root(e)
    if !ok_root {
        return "", false
    }
    defer if e.import_cache == nil { delete(odin_root) }
    dir, ok_dir := odin_import_dir(odin_root, raw)
    if !ok_dir {
        return "", false
    }
    defer delete(dir)
    raw_types, ok_types := odin_import_proc_param_types_from_dir(dir, member)
    if !ok_types {
        return "", false
    }
    defer delete_string_slice(&raw_types)
    qualified_types: [dynamic]string
    for raw_type in raw_types {
        append(&qualified_types, qualify_imported_odin_type(alias, raw_type))
    }
    if e.import_cache != nil {
        e.import_cache.proc_param_types[cache_key] = qualified_types
    } else {
        defer delete_string_slice(&qualified_types)
    }
    if arg_idx >= len(qualified_types) {
        return "", false
    }
    return strings.clone(qualified_types[arg_idx]), true
}

imported_odin_type_fields :: proc(e: ^Emitter, type_text: string) -> (fields: [dynamic]Struct_Field, ok: bool) {
    alias, member, ok_parts := imported_odin_type_parts(type_text)
    if !ok_parts {
        return fields, false
    }
    ensure_emitter_indexes(e)
    raw, found_import := e.odin_import_paths[alias]
    if !found_import {
        return fields, false
    }
    cache_key := emitter_import_cache_key(e, type_text, raw, alias, member)
    if e.import_cache != nil && e.import_cache.type_fields_known[cache_key] {
        if cached, found := e.import_cache.type_fields[cache_key]; found {
            return clone_struct_field_slice(cached[:]), true
        }
        return fields, false
    }
    if e.import_cache != nil {
        e.import_cache.type_fields_known[cache_key] = true
    }
    odin_root, ok_root := emitter_odin_root(e)
    if !ok_root {
        return fields, false
    }
    defer if e.import_cache == nil { delete(odin_root) }
    dir, ok_dir := odin_import_dir(odin_root, raw)
    if !ok_dir {
        return fields, false
    }
    defer delete(dir)
    fields, ok = odin_import_type_fields_from_dir(alias, dir, member)
    if ok && e.import_cache != nil {
        e.import_cache.type_fields[cache_key] = clone_struct_field_slice(fields[:])
    }
    return fields, ok
}

imported_odin_type_is_vector_alias :: proc(e: ^Emitter, type_text: string) -> bool {
    alias, member, ok_parts := imported_odin_type_parts(type_text)
    if !ok_parts {
        return false
    }
    ensure_emitter_indexes(e)
    raw, found_import := e.odin_import_paths[alias]
    if !found_import {
        return false
    }
    cache_key := emitter_import_cache_key(e, type_text, raw, alias, member)
    if e.import_cache != nil && e.import_cache.type_vector_alias_known[cache_key] {
        return e.import_cache.type_vector_alias[cache_key]
    }
    if e.import_cache != nil {
        e.import_cache.type_vector_alias_known[cache_key] = true
    }
    odin_root, ok_root := emitter_odin_root(e)
    if !ok_root {
        return false
    }
    defer if e.import_cache == nil { delete(odin_root) }
    dir, ok_dir := odin_import_dir(odin_root, raw)
    if !ok_dir {
        return false
    }
    defer delete(dir)
    is_vector_alias := odin_import_type_is_vector_alias_from_dir(alias, dir, member)
    if e.import_cache != nil {
        e.import_cache.type_vector_alias[cache_key] = is_vector_alias
    }
    return is_vector_alias
}

imported_odin_enum_type_exists :: proc(e: ^Emitter, type_text: string) -> bool {
    alias, member, ok_parts := imported_odin_type_parts(type_text)
    if !ok_parts {
        return false
    }

    ensure_emitter_indexes(e)
    raw, found_import := e.odin_import_paths[alias]
    if !found_import {
        return false
    }
    cache_key := emitter_import_cache_key(e, type_text, raw, alias, member)
    if e.import_cache != nil && e.import_cache.enum_known[cache_key] {
        return e.import_cache.enum_exists[cache_key]
    }
    found_enum := false
    odin_root, ok_root := emitter_odin_root(e)
    defer if e.import_cache == nil { delete(odin_root) }
    if ok_root {
        if dir, ok_dir := odin_import_dir(odin_root, raw); ok_dir {
            defer delete(dir)
            found_enum = odin_import_enum_exists_from_dir(dir, member)
        }
    }
    if e.import_cache != nil {
        e.import_cache.enum_known[cache_key] = true
        e.import_cache.enum_exists[cache_key] = found_enum
    }
    return found_enum
}

proc_param_keyword_names :: proc(proc_decl: ^Proc_Decl) -> (names: [dynamic]string) {
    for param, param_idx in proc_decl.params {
        append(&names, label_text(param.name))
    }
    return names
}

label_text :: proc(name: string) -> string {
    return fmt.tprintf(":%s", name)
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

resolved_zero_type_text :: proc(e: ^Emitter, ty: string, depth := 0) -> string {
    trimmed := strings.trim_space(ty)
    if e == nil || depth > 16 || trimmed == "" {
        return trimmed
    }
    if strings.has_prefix(trimmed, "distinct ") {
        return resolved_zero_type_text(
            e,
            strings.trim_space(trimmed[len("distinct "):]),
            depth+1,
        )
    }
    ensure_emitter_indexes(e)
    if idx, found := e.const_indices[trimmed]; found {
        decl := &e.decls[idx]
        if decl.const_decl.is_type_alias {
            return resolved_zero_type_text(
                e,
                decl.const_decl.type_alias,
                depth+1,
            )
        }
    }
    return trimmed
}

type_text_has_nil_zero :: proc(e: ^Emitter, ty: string) -> bool {
    resolved := resolved_zero_type_text(e, ty)
    return strings.has_prefix(resolved, "^") ||
           strings.has_prefix(resolved, "[^") ||
           strings.has_prefix(resolved, "[]") ||
           strings.has_prefix(resolved, "[dynamic]") ||
           strings.has_prefix(resolved, "#soa[dynamic]") ||
           strings.has_prefix(resolved, "map[") ||
           strings.has_prefix(resolved, "proc(") ||
           resolved == "rawptr" ||
           resolved == "cstring" ||
           resolved == "any"
}

zero_value_for_type_text :: proc(e: ^Emitter, ty: string) -> string {
    if type_text_has_nil_zero(e, ty) {
        return strings.clone("nil")
    }
    return fmt.tprintf("%s{{}}", strings.trim_space(ty))
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

emit_named_call_with_defaults :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, named_args: []CST_Form, span: Span) -> (arg_texts: [dynamic]string, err: Compile_Error, ok: bool) {
    if len(named_args) == 0 || len(named_args)%2 != 0 {
        return arg_texts, Compile_Error{message = "named arguments use alternating :name value pairs", span = span}, false
    }

    named_values := make([dynamic]Brace_Pair, 0, len(named_args)/2)
    defer delete(named_values)
    provided_names := make([dynamic]string, 0, len(named_args)/2)
    defer delete(provided_names)
    provided_forms := make([dynamic]CST_Form, 0, len(named_args)/2)
    defer delete(provided_forms)

    seen: [dynamic]string
    for i := 0; i < len(named_args); i += 2 {
        if i+1 >= len(named_args) {
            return arg_texts, Compile_Error{message = "missing named argument value", span = span}, false
        }
        key := named_args[i]
        value := named_args[i+1]
        field_name, ok_key := brace_key_name(key)
        if !ok_key {
            return arg_texts, keyword_key_error(key, "named arguments use alternating keyword/value pairs such as :name value"), false
        }
        for existing in seen {
            if existing == field_name {
                return arg_texts, Compile_Error{message = fmt.tprintf("duplicate named argument %s", key.text), span = key.span}, false
            }
        }
        append(&seen, field_name)
        param, ok_param := find_proc_param(proc_decl, field_name)
        if !ok_param {
            message := fmt.tprintf("unknown named argument %s", key.text)
            if closest, ok_closest := closest_proc_param_keyword(proc_decl, field_name); ok_closest {
                message = fmt.tprintf("%s; did you mean %s", message, label_text(closest))
            }
            return arg_texts, Compile_Error{message = named_arg_message_with_valid_keys(message, proc_decl), span = key.span}, false
        }
        value_text, err_value, ok_value := emit_call_arg_for_expected_type(
            e,
            value,
            param.ty,
            param.ownership,
        )
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
        return arg_texts, missing_required_arg_error(proc_decl.name, param.name, span), false
    }

    return arg_texts, Compile_Error{}, true
}

emit_call_arg_for_expected_type :: proc(
    e: ^Emitter,
    arg: CST_Form,
    expected_type: string,
    ownership: Ownership_Mode = .Default,
) -> (string, Compile_Error, bool) {
    value, err_value, ok_value := emit_expr_for_expected_type(e, arg, expected_type)
    if !ok_value {
        return "", err_value, false
    }
    if ownership == .Owned && arg.kind == .Symbol {
        name := map_name(arg.text)
        defer delete(name)
        if owner_flag, ok_owner := lookup_managed_local_owner(e, name); ok_owner {
            return managed_move_local_value_text(e, expected_type, value, owner_flag), {}, true
        }
    }
    if type_text_is_managed_value(e, expected_type) &&
       ((arg.kind == .Vector || arg.kind == .Brace || arg.kind == .Set) ||
        form_produces_owned_managed_type(e, arg, expected_type)) {
        temp := thread_temp_name(e)
        emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", temp), value, arg.span)
        if ownership != .Owned {
            emit_line_mapped(e, fmt.tprintf("defer kvist_data_release(%s)", temp), arg.span)
        }
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
        arg_text, err_arg, ok_arg := emit_call_arg_for_expected_type(
            e,
            arg,
            params[arg_idx].ty,
            params[arg_idx].ownership,
        )
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

emit_general_mixed_call_arg_texts :: proc(e: ^Emitter, head_name: string, positional_args, named_args: []CST_Form, span: Span) -> (arg_texts: [dynamic]string, err: Compile_Error, ok: bool) {
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

    named_arg_texts, err_named, ok_named := emit_named_call_arg_texts(e, named_args, span)
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

emit_mixed_call_with_defaults :: proc(e: ^Emitter, proc_decl: ^Proc_Decl, positional_args, named_args: []CST_Form, span: Span) -> (arg_texts: [dynamic]string, err: Compile_Error, ok: bool) {
    if len(positional_args) > len(proc_decl.params) {
        return arg_texts, Compile_Error{message = fmt.tprintf("%s expects at most %d arguments", proc_decl.name, len(proc_decl.params)), span = span}, false
    }

    named_values := make([dynamic]Brace_Pair, 0, len(named_args)/2)
    defer delete(named_values)
    provided_names := make([dynamic]string, 0, len(positional_args)+len(named_args)/2)
    defer delete(provided_names)
    provided_forms := make([dynamic]CST_Form, 0, len(positional_args)+len(named_args)/2)
    defer delete(provided_forms)

    seen: [dynamic]string
    for i := 0; i < len(named_args); i += 2 {
        if i+1 >= len(named_args) {
            return arg_texts, Compile_Error{message = "missing named argument value", span = span}, false
        }
        key := named_args[i]
        value := named_args[i+1]
        field_name, ok_key := brace_key_name(key)
        if !ok_key {
            return arg_texts, Compile_Error{message = "named arguments use alternating keyword/value pairs such as :name value", span = key.span}, false
        }
        for existing in seen {
            if existing == field_name {
                return arg_texts, Compile_Error{message = fmt.tprintf("duplicate named argument %s", key.text), span = key.span}, false
            }
        }
        append(&seen, field_name)
        param, ok_param := find_proc_param(proc_decl, field_name)
        if !ok_param {
            message := fmt.tprintf("unknown named argument %s", key.text)
            if closest, ok_closest := closest_proc_param_keyword(proc_decl, field_name); ok_closest {
                message = fmt.tprintf("%s; did you mean %s", message, label_text(closest))
            }
            return arg_texts, Compile_Error{message = named_arg_message_with_valid_keys(message, proc_decl), span = key.span}, false
        }
        value_text, err_value, ok_value := emit_call_arg_for_expected_type(
            e,
            value,
            param.ty,
            param.ownership,
        )
        if !ok_value {
            return arg_texts, err_value, false
        }
        append(&named_values, Brace_Pair{key = field_name, value = value_text})
        append(&provided_names, field_name)
        append(&provided_forms, value)
    }

    for arg, idx in positional_args {
        param := proc_decl.params[idx]
        arg_text, err_arg, ok_arg := emit_call_arg_for_expected_type(e, arg, param.ty, param.ownership)
        if !ok_arg {
            return arg_texts, err_arg, false
        }
        for pair in named_values {
            if pair.key == param.name {
                return arg_texts, Compile_Error{message = fmt.tprintf("named argument %s overlaps positional argument %d", label_text(param.name), idx+1), span = span}, false
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
        return arg_texts, missing_required_arg_error(proc_decl.name, param.name, span), false
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
