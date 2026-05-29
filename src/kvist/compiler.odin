package kvist

import "core:fmt"
import "core:os"
import "core:strings"
import "base:runtime"

Alias_Prefix :: struct {
    alias:  string,
    prefix: string,
}

Loaded_Forms :: struct {
    has_package: bool,
    package_decl: CST_Top_Form,
    imports: [dynamic]CST_Top_Form,
    decls: [dynamic]CST_Top_Form,
}

synthetic_package_decl :: proc(name: string) -> CST_Top_Form {
    package_symbol := CST_Form{
        kind = .Symbol,
        text = "package",
        span = Span{source = .File},
    }
    name_symbol := CST_Form{
        kind = .Symbol,
        text = name,
        span = Span{source = .File},
    }
    package_form := CST_Form{
        kind = .List,
        span = Span{source = .File},
    }
    append(&package_form.items, package_symbol, name_symbol)
    return CST_Top_Form{
        form = package_form,
        source = fmt.tprintf("(package %s)", name),
    }
}

contains_text :: proc(items: []string, value: string) -> bool {
    for item in items {
        if item == value {
            return true
        }
    }
    return false
}

append_import_form_unique :: proc(forms: ^[dynamic]CST_Top_Form, seen: ^[dynamic]string, form: CST_Top_Form) {
    key := form.source
    if contains_text(seen[:], key) {
        return
    }
    append(seen, key)
    append(forms, form)
}

is_source_import_path :: proc(path: string) -> bool {
    for ch in path {
        if ch == ':' {
            return false
        }
    }
    return true
}

resolve_source_import_path :: proc(importer_path, import_path: string) -> (string, Compile_Error, bool) {
    base_dir, _ := os.split_path(importer_path)
    base := import_path
    if base_dir != "" {
        joined, join_err := os.join_path({base_dir, import_path}, context.allocator)
        if join_err != nil {
            return "", Compile_Error{message = fmt.tprintf("could not resolve source import: %s", import_path)}, false
        }
        base = joined
    }

    candidates := [3]string{fmt.tprintf("%s.kvist", base), fmt.tprintf("%s/package.kvist", base), base}
    for candidate in candidates {
        if os.exists(candidate) {
            return candidate, Compile_Error{}, true
        }
    }
    return "", Compile_Error{message = fmt.tprintf("could not resolve source import: %s", import_path)}, false
}

decl_head_name :: proc(form: CST_Form) -> string {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return ""
    }
    return form.items[0].text
}

collect_local_decl_names :: proc(forms: []CST_Top_Form) -> (names: [dynamic]string) {
    for top in forms {
        form := top.form
        if form.kind != .List || len(form.items) < 2 || form.items[1].kind != .Symbol {
            continue
        }
        switch decl_head_name(form) {
        case "const", "defconst", "defvar", "struct", "defstruct", "enum", "defenum", "union", "defunion", "proc", "defn":
            append(&names, form.items[1].text)
        }
    }
    return names
}

source_import_alias_and_path :: proc(form: CST_Form) -> (alias, path: string, ok: bool) {
    if form.kind != .List || len(form.items) == 0 || !is_symbol(form.items[0], "import") {
        return "", "", false
    }
    if len(form.items) == 2 && form.items[1].kind == .String {
        path = import_path_text(form.items[1])
        if !is_source_import_path(path) {
            return "", "", false
        }
        return import_default_alias(path), path, true
    }
    if len(form.items) == 3 && form.items[1].kind == .Symbol && form.items[2].kind == .String {
        path = import_path_text(form.items[2])
        if !is_source_import_path(path) {
            return "", "", false
        }
        return map_name(form.items[1].text), path, true
    }
    return "", "", false
}

collect_root_source_import_aliases :: proc(path: string) -> ([]Alias_Prefix, Compile_Error, bool) {
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        return nil, Compile_Error{message = fmt.tprintf("could not read file: %s", path)}, false
    }
    defer delete(data)
    source := string(data)

    forms, err_forms, ok_forms := read_top_forms(source)
    if !ok_forms {
        return nil, err_forms, false
    }

    aliases: [dynamic]Alias_Prefix
    for top in forms {
        alias, _, ok_import := source_import_alias_and_path(top.form)
        if !ok_import {
            continue
        }
        append(&aliases, Alias_Prefix{alias = alias, prefix = alias})
    }
    return aliases[:], Compile_Error{}, true
}

rewrite_symbol_text :: proc(text: string, locals: []string, aliases: []Alias_Prefix, prefix: string) -> string {
    quote_prefix := ""
    body := text
    if len(body) > 0 && body[0] == '\'' {
        quote_prefix = "'"
        body = body[1:]
    }
    for alias_map in aliases {
        prefix_text := fmt.tprintf("%s/", alias_map.alias)
        if len(body) > len(prefix_text) && body[:len(prefix_text)] == prefix_text {
            return fmt.tprintf("%s%s__%s", quote_prefix, alias_map.prefix, body[len(prefix_text):])
        }
    }
    if prefix != "" && contains_text(locals, body) {
        return fmt.tprintf("%s%s__%s", quote_prefix, prefix, body)
    }
    return text
}

rewrite_form_symbols :: proc(form: CST_Form, locals: []string, aliases: []Alias_Prefix, prefix: string) -> CST_Form {
    rewritten := form
    #partial switch form.kind {
    case .Symbol:
        rewritten.text = rewrite_symbol_text(form.text, locals, aliases, prefix)
        return rewritten
    case .List, .Vector, .Brace:
        rewritten.items = nil
        for item in form.items {
            append(&rewritten.items, rewrite_form_symbols(item, locals, aliases, prefix))
        }
    }
    return rewritten
}

rewrite_decl_name :: proc(form: ^CST_Form, prefix: string) {
    if prefix == "" || form^.kind != .List || len(form^.items) < 2 || form^.items[1].kind != .Symbol {
        return
    }
    switch decl_head_name(form^) {
    case "const", "defconst", "defvar", "struct", "defstruct", "enum", "defenum", "union", "defunion", "proc", "defn":
        form^.items[1].text = fmt.tprintf("%s__%s", prefix, form^.items[1].text)
    }
}

rewrite_top_form :: proc(top: CST_Top_Form, locals: []string, aliases: []Alias_Prefix, prefix: string) -> CST_Top_Form {
    rewritten := top
    if prefix != "" &&
       top.form.kind == .List &&
       len(top.form.items) >= 2 &&
       top.form.items[1].kind == .Symbol {
        head := decl_head_name(top.form)
        switch head {
        case "const", "defconst", "defvar", "struct", "defstruct", "enum", "defenum", "union", "defunion", "proc", "defn":
            rewritten.form = top.form
            rewritten.form.items = nil
            for item, idx in top.form.items {
                if idx == 1 {
                    renamed := item
                    renamed.text = fmt.tprintf("%s__%s", prefix, item.text)
                    append(&rewritten.form.items, renamed)
                } else {
                    append(&rewritten.form.items, rewrite_form_symbols(item, locals, aliases, prefix))
                }
            }
            return rewritten
        }
    }
    rewritten.form = rewrite_form_symbols(top.form, locals, aliases, prefix)
    rewrite_decl_name(&rewritten.form, prefix)
    return rewritten
}

load_source_forms :: proc(path, prefix: string, loaded_keys, import_keys: ^[dynamic]string, visiting: ^[dynamic]string) -> (Loaded_Forms, Compile_Error, bool) {
    key := fmt.tprintf("%s|%s", path, prefix)
    if contains_text(loaded_keys[:], key) {
        return Loaded_Forms{}, Compile_Error{}, true
    }
    if contains_text(visiting[:], key) {
        return Loaded_Forms{}, Compile_Error{message = fmt.tprintf("cyclic source import: %s", path)}, false
    }
    append(visiting, key)

    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        return Loaded_Forms{}, Compile_Error{message = fmt.tprintf("could not read file: %s", path)}, false
    }
    defer delete(data)
    source := string(data)

    forms, err_forms, ok_forms := read_top_forms(source)
    if !ok_forms {
        return Loaded_Forms{}, err_forms, false
    }

    locals := collect_local_decl_names(forms[:])
    aliases: [dynamic]Alias_Prefix
    result := Loaded_Forms{}

    for top in forms {
        alias, import_path, ok_import := source_import_alias_and_path(top.form)
        if !ok_import {
            continue
        }
        resolved, err_resolve, ok_resolve := resolve_source_import_path(path, import_path)
        if !ok_resolve {
            return result, err_resolve, false
        }
        nested_prefix := alias
        if prefix != "" {
            nested_prefix = fmt.tprintf("%s__%s", prefix, alias)
        }
        append(&aliases, Alias_Prefix{alias = alias, prefix = nested_prefix})
        nested, err_nested, ok_nested := load_source_forms(resolved, nested_prefix, loaded_keys, import_keys, visiting)
        if !ok_nested {
            return result, err_nested, false
        }
        for form in nested.imports {
            append_import_form_unique(&result.imports, import_keys, form)
        }
        for form in nested.decls {
            append(&result.decls, form)
        }
    }

    for top in forms {
        form := top.form
        head := decl_head_name(form)
        if head == "package" {
            if prefix == "" {
                result.has_package = true
                result.package_decl = top
            }
            continue
        }
        _, _, is_source_import := source_import_alias_and_path(form)
        if is_source_import {
            continue
        }
        if head == "import" {
            append_import_form_unique(&result.imports, import_keys, top)
            continue
        }
        append(&result.decls, rewrite_top_form(top, locals[:], aliases[:], prefix))
    }

    append(loaded_keys, key)
    return result, Compile_Error{}, true
}

load_path_program :: proc(path: string) -> (AST_Program, Compile_Error, bool) {
    loaded_keys: [dynamic]string
    import_keys: [dynamic]string
    visiting: [dynamic]string
    loaded, err_load, ok_load := load_source_forms(path, "", &loaded_keys, &import_keys, &visiting)
    if !ok_load {
        return AST_Program{}, err_load, false
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
    return parse_program(combined[:])
}

compile_program_with_map :: proc(program: AST_Program) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

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
        append(&result.source_map, entry)
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

compile_program_eval_form_with_map :: proc(program: AST_Program, eval_form: CST_Form, no_print: bool = false) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    lowered, err_lower, ok_lower := lower_program(program)
    if !ok_lower {
        return result, clone_compile_error(err_lower, result_allocator), false
    }

    temp_result: Emit_Result
    err_emit: Compile_Error
    ok_emit: bool
    eval_head := eval_form_head(eval_form)
    if eval_head_is_decl(eval_head) {
        eval_decl, err_decl, ok_decl := parse_decl(CST_Top_Form{form = eval_form})
        if !ok_decl {
            return result, clone_compile_error(err_decl, result_allocator), false
        }
        temp_result, err_emit, ok_emit = emit_eval_decl_program_with_source_map(lowered, IR_Decl(eval_decl))
    } else {
        temp_result, err_emit, ok_emit = emit_eval_program_with_source_map(lowered, eval_form, no_print)
    }
    if !ok_emit {
        return result, clone_compile_error(err_emit, result_allocator), false
    }
    result.output = strings.clone(temp_result.output, result_allocator)
    context.allocator = result_allocator
    for entry in temp_result.source_map {
        append(&result.source_map, entry)
    }
    for warning in temp_result.warnings {
        append(&result.warnings, clone_compile_warning(warning, result_allocator))
    }
    return result, Compile_Error{}, true
}

source_position :: proc(source: string, pos: int) -> (line, column, line_start, line_end: int) {
    clamped_pos := pos
    if clamped_pos < 0 {
        clamped_pos = 0
    }
    if clamped_pos > len(source) {
        clamped_pos = len(source)
    }

    line = 1
    column = 1
    line_start = 0
    i := 0
    for i < clamped_pos {
        if source[i] == '\n' {
            line += 1
            column = 1
            line_start = i + 1
        } else {
            column += 1
        }
        i += 1
    }

    line_end = clamped_pos
    for line_end < len(source) && source[line_end] != '\n' {
        line_end += 1
    }
    return
}

format_compile_error :: proc(path, source: string, err: Compile_Error) -> string {
    label := path
    if label == "" {
        label = "<source>"
    }
    message := err.message
    if message == "" {
        message = "compile error"
    }

    line, column, line_start, line_end := source_position(source, err.span.start)
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    fmt.sbprintf(&builder, "%s:%d:%d: %s\n", label, line, column, message)
    if line_start <= line_end && line_end <= len(source) {
        fmt.sbprintf(&builder, "  %s\n  ", source[line_start:line_end])
        i := 1
        for i < column {
            strings.write_byte(&builder, ' ')
            i += 1
        }
        strings.write_string(&builder, "^\n")
    }
    return strings.clone(strings.to_string(builder))
}

format_eval_compile_error :: proc(path, source, eval_source: string, err: Compile_Error) -> string {
    if err.span.source == .Eval {
        label := "<eval>"
        if path != "" {
            label = fmt.tprintf("%s:<eval>", path)
        }
        return format_compile_error(label, eval_source, err)
    }
    return format_compile_error(path, source, err)
}

format_compile_warning :: proc(path, source: string, warning: Compile_Warning) -> string {
    label := path
    if label == "" {
        label = "<source>"
    }
    message := warning.message
    if message == "" {
        message = "warning"
    }
    line, column, _, _ := source_position(source, warning.span.start)
    return strings.clone(fmt.tprintf("%s:%d:%d: warning: %s\n", label, line, column, message))
}

format_eval_compile_warning :: proc(path, source, eval_source: string, warning: Compile_Warning) -> string {
    if warning.span.source == .Eval {
        label := "<eval>"
        if path != "" {
            label = fmt.tprintf("%s:<eval>", path)
        }
        return format_compile_warning(label, eval_source, warning)
    }
    return format_compile_warning(path, source, warning)
}

clone_compile_error :: proc(err: Compile_Error, allocator := context.allocator) -> Compile_Error {
    cloned := err
    if cloned.message != "" {
        cloned.message = strings.clone(cloned.message, allocator)
    }
    return cloned
}

clone_compile_warning :: proc(warning: Compile_Warning, allocator := context.allocator) -> Compile_Warning {
    cloned := warning
    if cloned.message != "" {
        cloned.message = strings.clone(cloned.message, allocator)
    }
    return cloned
}

compile_warning_slice_delete :: proc(warnings: [dynamic]Compile_Warning, allocator := context.allocator) {
    for warning in warnings {
        if warning.message != "" {
            delete(warning.message, allocator)
        }
    }
    delete(warnings)
}

format_source_map :: proc(entries: []Source_Map_Entry) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "generated_start generated_end source_start source_end\n")
    for entry in entries {
        fmt.sbprintf(
            &builder,
            "%d %d %d %d\n",
            entry.generated_start_line,
            entry.generated_end_line,
            entry.source_span.start,
            entry.source_span.end,
        )
    }
    return strings.clone(strings.to_string(builder))
}

source_map_entry_for_generated_line :: proc(entries: []Source_Map_Entry, line: int) -> (Source_Map_Entry, bool) {
    return source_map_entry_for_generated_location(entries, line, 0)
}

source_map_entry_for_generated_location :: proc(entries: []Source_Map_Entry, line, column: int) -> (Source_Map_Entry, bool) {
    best: Source_Map_Entry
    found := false
    best_column_constrained := false
    best_generated_width := 0
    best_column_width := 0
    best_source_width := 0
    for entry in entries {
        if line < entry.generated_start_line || line > entry.generated_end_line {
            continue
        }
        column_constrained := column > 0 && entry.generated_start_column > 0
        if column_constrained {
            if column < entry.generated_start_column {
                continue
            }
            if entry.generated_end_column > 0 && column > entry.generated_end_column {
                continue
            }
        }
        generated_width := entry.generated_end_line - entry.generated_start_line
        column_width := 0
        if entry.generated_start_column > 0 && entry.generated_end_column > 0 {
            column_width = entry.generated_end_column - entry.generated_start_column
        }
        source_width := entry.source_span.end - entry.source_span.start
        if !found ||
           (column_constrained && !best_column_constrained) ||
           (column_constrained == best_column_constrained &&
            column_constrained && column_width < best_column_width) ||
           (column_constrained == best_column_constrained &&
            column_width == best_column_width &&
            generated_width < best_generated_width) ||
           (column_constrained == best_column_constrained &&
            column_width == best_column_width &&
            generated_width == best_generated_width &&
            source_width < best_source_width) ||
           (!column_constrained && !best_column_constrained &&
            generated_width < best_generated_width) ||
           (!column_constrained && !best_column_constrained &&
            generated_width == best_generated_width &&
            source_width < best_source_width) {
            best = entry
            found = true
            best_column_constrained = column_constrained
            best_generated_width = generated_width
            best_column_width = column_width
            best_source_width = source_width
        }
    }
    return best, found
}

compile_source :: proc(source: string) -> (output: string, err: Compile_Error, ok: bool) {
    result, err_result, ok_result := compile_source_with_map(source)
    if !ok_result {
        return "", err_result, false
    }
    defer delete(result.source_map)
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

    forms, err_forms, ok_forms := read_top_forms(source)
    if !ok_forms {
        return result, clone_compile_error(err_forms, result_allocator), false
    }
    program, err_program, ok_program := parse_program(forms[:])
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
        append(&result.source_map, entry)
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
    if len(forms) != 1 {
        return form, Compile_Error{message = "eval expects exactly one form", span = Span{source = .Eval}}, false
    }
    return forms[0].form, {}, true
}

eval_form_head :: proc(form: CST_Form) -> string {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return ""
    }
    return form.items[0].text
}

eval_head_is_decl :: proc(head: string) -> bool {
    switch head {
    case "comment", "package", "import", "const", "defconst", "defvar", "struct", "defstruct", "enum", "union", "odin", "proc", "defn":
        return true
    }
    return false
}

compile_eval_source :: proc(source, eval_source: string, no_print: bool = false) -> (output: string, err: Compile_Error, ok: bool) {
    result, err_result, ok_result := compile_eval_source_with_map(source, eval_source, no_print)
    if !ok_result {
        return "", err_result, false
    }
    defer delete(result.source_map)
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

    forms, err_forms, ok_forms := read_top_forms(source)
    if !ok_forms {
        return result, clone_compile_error(err_forms, result_allocator), false
    }
    program, err_program, ok_program := parse_program(forms[:])
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

    temp_result: Emit_Result
    err_emit: Compile_Error
    ok_emit: bool

    eval_head := eval_form_head(eval_form)
    if eval_head_is_decl(eval_head) {
        eval_decl, err_decl, ok_decl := parse_decl(CST_Top_Form{form = eval_form})
        if !ok_decl {
            return result, clone_compile_error(err_decl, result_allocator), false
        }
        temp_result, err_emit, ok_emit = emit_eval_decl_program_with_source_map(lowered, IR_Decl(eval_decl))
    } else {
        temp_result, err_emit, ok_emit = emit_eval_program_with_source_map(lowered, eval_form, no_print)
    }
    if !ok_emit {
        return result, clone_compile_error(err_emit, result_allocator), false
    }
    result.output = strings.clone(temp_result.output, result_allocator)
    context.allocator = result_allocator
    for entry in temp_result.source_map {
        append(&result.source_map, entry)
    }
    for warning in temp_result.warnings {
        append(&result.warnings, clone_compile_warning(warning, result_allocator))
    }
    return result, {}, true
}

compile_path :: proc(path: string) -> (output: string, err: Compile_Error, ok: bool) {
    result, err_result, ok_result := compile_path_with_map(path)
    if !ok_result {
        return "", err_result, false
    }
    defer delete(result.source_map)
    defer compile_warning_slice_delete(result.warnings)
    return result.output, {}, true
}

compile_path_with_map :: proc(path: string) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := result_allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator

    program, err_program, ok_program := load_path_program(path)
    if !ok_program {
        context.allocator = old_allocator
        return result, clone_compile_error(err_program, result_allocator), false
    }
    context.allocator = old_allocator
    return compile_program_with_map(program)
}

compile_eval_path :: proc(path, eval_source: string, no_print: bool = false) -> (output: string, err: Compile_Error, ok: bool) {
    result, err_result, ok_result := compile_eval_path_with_map(path, eval_source, no_print)
    if !ok_result {
        return "", err_result, false
    }
    defer delete(result.source_map)
    defer compile_warning_slice_delete(result.warnings)
    return result.output, {}, true
}

compile_eval_path_with_map :: proc(path, eval_source: string, no_print: bool = false) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := result_allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator

    program, err_program, ok_program := load_path_program(path)
    if !ok_program {
        context.allocator = old_allocator
        return result, clone_compile_error(err_program, result_allocator), false
    }
    aliases, err_aliases, ok_aliases := collect_root_source_import_aliases(path)
    if !ok_aliases {
        context.allocator = old_allocator
        return result, clone_compile_error(err_aliases, result_allocator), false
    }
    eval_form, err_eval, ok_eval := read_single_eval_form(eval_source)
    if !ok_eval {
        context.allocator = old_allocator
        return result, clone_compile_error(err_eval, result_allocator), false
    }
    eval_form = rewrite_form_symbols(eval_form, nil, aliases, "")
    context.allocator = old_allocator
    return compile_program_eval_form_with_map(program, eval_form, no_print)
}
