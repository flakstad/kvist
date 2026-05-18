package odinl

import "core:fmt"
import "core:os"
import "core:strings"
import "base:runtime"

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

clone_compile_error :: proc(err: Compile_Error, allocator := context.allocator) -> Compile_Error {
    cloned := err
    if cloned.message != "" {
        cloned.message = strings.clone(cloned.message, allocator)
    }
    return cloned
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
    for entry in entries {
        if line >= entry.generated_start_line && line <= entry.generated_end_line {
            return entry, true
        }
    }
    return {}, false
}

compile_source :: proc(source: string) -> (output: string, err: Compile_Error, ok: bool) {
    result, err_result, ok_result := compile_source_with_map(source)
    if !ok_result {
        return "", err_result, false
    }
    defer delete(result.source_map)
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
    case "comment", "package", "import", "const", "struct", "enum", "union", "odin", "proc":
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
    return result, {}, true
}

compile_path :: proc(path: string) -> (output: string, err: Compile_Error, ok: bool) {
    result, err_result, ok_result := compile_path_with_map(path)
    if !ok_result {
        return "", err_result, false
    }
    defer delete(result.source_map)
    return result.output, {}, true
}

compile_path_with_map :: proc(path: string) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        return result, Compile_Error{message = fmt.tprintf("could not read file: %s", path)}, false
    }
    defer delete(data)
    source := string(data)
    return compile_source_with_map(source)
}

compile_eval_path :: proc(path, eval_source: string, no_print: bool = false) -> (output: string, err: Compile_Error, ok: bool) {
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        return "", Compile_Error{message = fmt.tprintf("could not read file: %s", path)}, false
    }
    defer delete(data)
    source := string(data)
    return compile_eval_source(source, eval_source, no_print)
}
