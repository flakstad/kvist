package odinl

import "core:fmt"
import "core:strings"
import "base:runtime"

Macro_Expander :: struct {
    builder:    strings.Builder,
    line:       int,
    source_map: ^[dynamic]Source_Map_Entry,
}

builtin_macro_kind :: proc(head: string) -> Builtin_Macro_Kind {
    switch head {
    case "with-allocator":
        return .With_Allocator
    case "with-temp-allocator":
        return .With_Temp_Allocator
    case "with-delete":
        return .With_Delete
    case "when-let":
        return .When_Let
    case "if-let":
        return .If_Let
    case "when-ok":
        return .When_Ok
    case "if-ok":
        return .If_Ok
    }
    return .None
}

builtin_macro_form_kind :: proc(form: CST_Form) -> Builtin_Macro_Kind {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return .None
    }
    return builtin_macro_kind(form.items[0].text)
}

macro_record_source_map :: proc(e: ^Macro_Expander, start_line, end_line: int, span: Span) {
    if e.source_map == nil || end_line < start_line {
        return
    }
    append(e.source_map, Source_Map_Entry{
        generated_start_line = start_line,
        generated_end_line   = end_line,
        source_span          = span,
    })
}

macro_emit_line :: proc(e: ^Macro_Expander, text: string, span: Span) {
    strings.write_string(&e.builder, text)
    strings.write_byte(&e.builder, '\n')
    macro_record_source_map(e, e.line, e.line, span)
    e.line += 1
}

macro_symbol :: proc(text: string, span: Span) -> CST_Form {
    return CST_Form{kind = .Symbol, text = text, span = span}
}

macro_empty_brace :: proc(span: Span) -> CST_Form {
    return CST_Form{kind = .Brace, span = span}
}

macro_error_success_condition :: proc(condition: CST_Form) -> CST_Form {
    test := CST_Form{kind = .List, span = condition.span}
    append(&test.items, macro_symbol("==", condition.span))
    append(&test.items, condition)
    append(&test.items, macro_empty_brace(condition.span))
    return test
}

parse_binding_condition_macro :: proc(form: CST_Form, name, binding_label: string) -> (bindings: CST_Form, condition: CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 || form.items[1].kind != .Vector {
        return bindings, condition, Compile_Error{message = fmt.tprintf("%s expects %s binding and body", name, binding_label), span = form.span}, false
    }
    binding := form.items[1]
    if len(binding.items) != 3 || binding.items[0].kind != .Symbol || binding.items[1].kind != .Symbol {
        return bindings, condition, Compile_Error{message = fmt.tprintf("%s expects %s binding", name, binding_label), span = binding.span}, false
    }

    destructure := CST_Form{kind = .Vector, span = binding.span}
    append(&destructure.items, binding.items[0])
    append(&destructure.items, binding.items[1])

    bindings = CST_Form{kind = .Vector, span = binding.span}
    append(&bindings.items, destructure)
    append(&bindings.items, binding.items[2])
    condition = binding.items[1]
    return bindings, condition, {}, true
}

expand_when_let_form :: proc(form: CST_Form) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    bindings, condition, err_bind, ok_bind := parse_binding_condition_macro(form, "when-let", "[value bool expr]")
    if !ok_bind {
        return expanded, err_bind, false
    }
    when_form := CST_Form{kind = .List, span = form.span}
    append(&when_form.items, macro_symbol("when", form.items[0].span))
    append(&when_form.items, condition)
    for item in form.items[2:] {
        append(&when_form.items, item)
    }

    expanded = CST_Form{kind = .List, span = form.span}
    append(&expanded.items, macro_symbol("let", form.items[0].span))
    append(&expanded.items, bindings)
    append(&expanded.items, when_form)
    return expanded, {}, true
}

expand_if_let_form :: proc(form: CST_Form) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) != 4 {
        return expanded, Compile_Error{message = "if-let expects [value bool expr], then, and else", span = form.span}, false
    }
    bindings, condition, err_bind, ok_bind := parse_binding_condition_macro(form, "if-let", "[value bool expr]")
    if !ok_bind {
        return expanded, err_bind, false
    }

    if_form := CST_Form{kind = .List, span = form.span}
    append(&if_form.items, macro_symbol("if", form.items[0].span))
    append(&if_form.items, condition)
    append(&if_form.items, form.items[2])
    append(&if_form.items, form.items[3])

    expanded = CST_Form{kind = .List, span = form.span}
    append(&expanded.items, macro_symbol("let", form.items[0].span))
    append(&expanded.items, bindings)
    append(&expanded.items, if_form)
    return expanded, {}, true
}

expand_when_ok_form :: proc(form: CST_Form) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    bindings, condition, err_bind, ok_bind := parse_binding_condition_macro(form, "when-ok", "[value err expr]")
    if !ok_bind {
        return expanded, err_bind, false
    }

    when_form := CST_Form{kind = .List, span = form.span}
    append(&when_form.items, macro_symbol("when", form.items[0].span))
    append(&when_form.items, macro_error_success_condition(condition))
    for item in form.items[2:] {
        append(&when_form.items, item)
    }

    expanded = CST_Form{kind = .List, span = form.span}
    append(&expanded.items, macro_symbol("let", form.items[0].span))
    append(&expanded.items, bindings)
    append(&expanded.items, when_form)
    return expanded, {}, true
}

expand_if_ok_form :: proc(form: CST_Form) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) != 4 {
        return expanded, Compile_Error{message = "if-ok expects [value err expr], then, and else", span = form.span}, false
    }
    bindings, condition, err_bind, ok_bind := parse_binding_condition_macro(form, "if-ok", "[value err expr]")
    if !ok_bind {
        return expanded, err_bind, false
    }

    if_form := CST_Form{kind = .List, span = form.span}
    append(&if_form.items, macro_symbol("if", form.items[0].span))
    append(&if_form.items, macro_error_success_condition(condition))
    append(&if_form.items, form.items[2])
    append(&if_form.items, form.items[3])

    expanded = CST_Form{kind = .List, span = form.span}
    append(&expanded.items, macro_symbol("let", form.items[0].span))
    append(&expanded.items, bindings)
    append(&expanded.items, if_form)
    return expanded, {}, true
}

macro_emit_expanded_form :: proc(e: ^Macro_Expander, indent: string, form: CST_Form, suffix: string = "") -> (Compile_Error, bool) {
    expanded, err_expand, ok_expand := macroexpand_form(form)
    if !ok_expand {
        return err_expand, false
    }
    defer delete(expanded.output)
    defer delete(expanded.source_map)

    start_line := e.line
    text_end := len(expanded.output)
    if text_end > 0 && expanded.output[text_end-1] == '\n' {
        text_end -= 1
    }

    start := 0
    i := 0
    for i < text_end {
        if expanded.output[i] == '\n' {
            strings.write_string(&e.builder, indent)
            strings.write_string(&e.builder, expanded.output[start:i])
            strings.write_byte(&e.builder, '\n')
            e.line += 1
            start = i + 1
        }
        i += 1
    }
    strings.write_string(&e.builder, indent)
    strings.write_string(&e.builder, expanded.output[start:text_end])
    strings.write_string(&e.builder, suffix)
    strings.write_byte(&e.builder, '\n')
    e.line += 1

    if len(expanded.source_map) == 0 {
        macro_record_source_map(e, start_line, e.line-1, form.span)
        return {}, true
    }

    for entry in expanded.source_map {
        adjusted := entry
        adjusted.generated_start_line = start_line + entry.generated_start_line - 1
        adjusted.generated_end_line = start_line + entry.generated_end_line - 1
        append(e.source_map, adjusted)
    }
    return {}, true
}

macro_emit_body_form :: proc(e: ^Macro_Expander, item: CST_Form, suffix: string) -> (Compile_Error, bool) {
    if builtin_macro_form_kind(item) != .None {
        return macro_emit_expanded_form(e, "    ", item, suffix)
    }

    item_text := macro_form_text(item)
    defer delete(item_text)
    macro_emit_line(e, fmt.tprintf("    %s%s", item_text, suffix), item.span)
    return {}, true
}

write_macro_form :: proc(builder: ^strings.Builder, form: CST_Form) {
    #partial switch form.kind {
    case .List:
        strings.write_byte(builder, '(')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            write_macro_form(builder, item)
        }
        strings.write_byte(builder, ')')
    case .Vector:
        strings.write_byte(builder, '[')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            write_macro_form(builder, item)
        }
        strings.write_byte(builder, ']')
    case .Brace:
        strings.write_byte(builder, '{')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            write_macro_form(builder, item)
        }
        strings.write_byte(builder, '}')
    case .Symbol, .Keyword, .String, .Number, .Bool, .Nil:
        strings.write_string(builder, form.text)
    }
}

write_macro_expanded_output :: proc(builder: ^strings.Builder, output: string) {
    text_end := len(output)
    if text_end > 0 && output[text_end-1] == '\n' {
        text_end -= 1
    }
    strings.write_string(builder, output[:text_end])
}

write_macro_form_expanded :: proc(builder: ^strings.Builder, form: CST_Form) -> (Compile_Error, bool) {
    if builtin_macro_form_kind(form) != .None {
        expanded, err_expand, ok_expand := macroexpand_form(form)
        if !ok_expand {
            return err_expand, false
        }
        defer delete(expanded.output)
        defer delete(expanded.source_map)
        write_macro_expanded_output(builder, expanded.output)
        return {}, true
    }

    #partial switch form.kind {
    case .List:
        strings.write_byte(builder, '(')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            err_item, ok_item := write_macro_form_expanded(builder, item)
            if !ok_item {
                return err_item, false
            }
        }
        strings.write_byte(builder, ')')
    case .Vector:
        strings.write_byte(builder, '[')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            err_item, ok_item := write_macro_form_expanded(builder, item)
            if !ok_item {
                return err_item, false
            }
        }
        strings.write_byte(builder, ']')
    case .Brace:
        strings.write_byte(builder, '{')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            err_item, ok_item := write_macro_form_expanded(builder, item)
            if !ok_item {
                return err_item, false
            }
        }
        strings.write_byte(builder, '}')
    case .Symbol, .Keyword, .String, .Number, .Bool, .Nil:
        strings.write_string(builder, form.text)
    }
    return {}, true
}

macro_form_text :: proc(form: CST_Form) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    write_macro_form(&builder, form)
    return strings.clone(strings.to_string(builder))
}

macro_output_line_count :: proc(output: string) -> int {
    if len(output) == 0 {
        return 1
    }
    lines := 1
    for ch in output {
        if ch == '\n' {
            lines += 1
        }
    }
    if output[len(output)-1] == '\n' {
        lines -= 1
    }
    if lines < 1 {
        return 1
    }
    return lines
}

macroexpand_with_allocator :: proc(form: CST_Form) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 || form.items[1].kind != .Vector {
        return result, Compile_Error{message = "with-allocator expects binding vector and body", span = form.span}, false
    }
    binding := form.items[1]
    if len(binding.items) != 2 || binding.items[0].kind != .Symbol {
        return result, Compile_Error{message = "with-allocator expects [name allocator] binding", span = binding.span}, false
    }

    allocator_name := binding.items[0].text
    allocator_expr := macro_form_text(binding.items[1])
    defer delete(allocator_expr)

    e := Macro_Expander{builder = strings.builder_make(), line = 1, source_map = &result.source_map}
    defer strings.builder_destroy(&e.builder)

    macro_emit_line(&e, "(do", form.span)
    macro_emit_line(&e, fmt.tprintf("  (let [%s %s", allocator_name, allocator_expr), binding.items[1].span)
    macro_emit_line(&e, "        odinl-old-allocator-1 context.allocator]", form.span)
    macro_emit_line(&e, fmt.tprintf("    (set! context.allocator %s)", allocator_name), form.span)
    macro_emit_line(&e, "    (defer (do", form.span)
    macro_emit_line(&e, "      (set! context.allocator odinl-old-allocator-1)))", form.span)
    body := form.items[2:]
    for item, idx in body {
        suffix := ""
        if idx == len(body)-1 {
            suffix = "))"
        }
        err_body, ok_body := macro_emit_body_form(&e, item, suffix)
        if !ok_body {
            return result, err_body, false
        }
    }

    result.output = strings.clone(strings.to_string(e.builder))
    return result, {}, true
}

macroexpand_with_temp_allocator :: proc(form: CST_Form) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 || form.items[1].kind != .Vector {
        return result, Compile_Error{message = "with-temp-allocator expects binding vector and body", span = form.span}, false
    }
    binding := form.items[1]
    if len(binding.items) != 1 || binding.items[0].kind != .Symbol {
        return result, Compile_Error{message = "with-temp-allocator expects [name] binding", span = binding.span}, false
    }

    allocator_name := binding.items[0].text

    e := Macro_Expander{builder = strings.builder_make(), line = 1, source_map = &result.source_map}
    defer strings.builder_destroy(&e.builder)

    macro_emit_line(&e, "(do", form.span)
    macro_emit_line(&e, "  (let [odinl-temp-scope-1 (runtime.default-temp-allocator-temp-begin)", form.span)
    macro_emit_line(&e, fmt.tprintf("        %s context.temp-allocator", allocator_name), form.span)
    macro_emit_line(&e, "        odinl-old-allocator-1 context.allocator]", form.span)
    macro_emit_line(&e, fmt.tprintf("    (set! context.allocator %s)", allocator_name), form.span)
    macro_emit_line(&e, "    (defer (do", form.span)
    macro_emit_line(&e, "      (set! context.allocator odinl-old-allocator-1)", form.span)
    macro_emit_line(&e, "      (runtime.default-temp-allocator-temp-end odinl-temp-scope-1)))", form.span)
    body := form.items[2:]
    for item, idx in body {
        suffix := ""
        if idx == len(body)-1 {
            suffix = "))"
        }
        err_body, ok_body := macro_emit_body_form(&e, item, suffix)
        if !ok_body {
            return result, err_body, false
        }
    }

    result.output = strings.clone(strings.to_string(e.builder))
    return result, {}, true
}

macroexpand_with_delete :: proc(form: CST_Form) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 || form.items[1].kind != .Vector {
        return result, Compile_Error{message = "with-delete expects binding vector and body", span = form.span}, false
    }
    binding := form.items[1]
    if len(binding.items) < 2 || len(binding.items)%2 != 0 {
        return result, Compile_Error{message = "with-delete expects [name value ...] bindings", span = binding.span}, false
    }

    e := Macro_Expander{builder = strings.builder_make(), line = 1, source_map = &result.source_map}
    defer strings.builder_destroy(&e.builder)

    macro_emit_line(&e, "(do", form.span)
    i := 0
    for i < len(binding.items) {
        if binding.items[i].kind != .Symbol {
            return result, Compile_Error{message = "with-delete binding name must be a symbol", span = binding.items[i].span}, false
        }
        binding_name := binding.items[i].text
        value_expr := macro_form_text(binding.items[i+1])
        defer delete(value_expr)
        suffix := ""
        if i+2 >= len(binding.items) {
            suffix = "]"
        }
        if i == 0 {
            macro_emit_line(&e, fmt.tprintf("  (let [%s %s%s", binding_name, value_expr, suffix), binding.items[i+1].span)
        } else {
            macro_emit_line(&e, fmt.tprintf("        %s %s%s", binding_name, value_expr, suffix), binding.items[i+1].span)
        }
        i += 2
    }
    i = 0
    for i < len(binding.items) {
        binding_name := binding.items[i].text
        macro_emit_line(&e, fmt.tprintf("    (defer (delete %s))", binding_name), binding.items[i].span)
        i += 2
    }
    body := form.items[2:]
    for item, idx in body {
        suffix := ""
        if idx == len(body)-1 {
            suffix = "))"
        }
        err_body, ok_body := macro_emit_body_form(&e, item, suffix)
        if !ok_body {
            return result, err_body, false
        }
    }

    result.output = strings.clone(strings.to_string(e.builder))
    return result, {}, true
}

macroexpand_when_let :: proc(form: CST_Form) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    expanded, err_expand, ok_expand := expand_when_let_form(form)
    if !ok_expand {
        return result, err_expand, false
    }
    return macroexpand_form(expanded)
}

macroexpand_if_let :: proc(form: CST_Form) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    expanded, err_expand, ok_expand := expand_if_let_form(form)
    if !ok_expand {
        return result, err_expand, false
    }
    return macroexpand_form(expanded)
}

macroexpand_when_ok :: proc(form: CST_Form) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    expanded, err_expand, ok_expand := expand_when_ok_form(form)
    if !ok_expand {
        return result, err_expand, false
    }
    return macroexpand_form(expanded)
}

macroexpand_if_ok :: proc(form: CST_Form) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    expanded, err_expand, ok_expand := expand_if_ok_form(form)
    if !ok_expand {
        return result, err_expand, false
    }
    return macroexpand_form(expanded)
}

macroexpand_form :: proc(form: CST_Form) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    switch builtin_macro_form_kind(form) {
    case .With_Allocator:
        return macroexpand_with_allocator(form)
    case .With_Temp_Allocator:
        return macroexpand_with_temp_allocator(form)
    case .With_Delete:
        return macroexpand_with_delete(form)
    case .When_Let:
        return macroexpand_when_let(form)
    case .If_Let:
        return macroexpand_if_let(form)
    case .When_Ok:
        return macroexpand_when_ok(form)
    case .If_Ok:
        return macroexpand_if_ok(form)
    case .None:
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    err_write, ok_write := write_macro_form_expanded(&builder, form)
    if !ok_write {
        return result, err_write, false
    }
    strings.write_byte(&builder, '\n')
    result.output = strings.clone(strings.to_string(builder))
    append(&result.source_map, Source_Map_Entry{
        generated_start_line = 1,
        generated_end_line = macro_output_line_count(result.output),
        source_span = form.span,
    })
    return result, {}, true
}

macroexpand_source :: proc(source: string) -> (output: string, err: Compile_Error, ok: bool) {
    result, err_result, ok_result := macroexpand_source_with_map(source)
    if !ok_result {
        return "", err_result, false
    }
    defer delete(result.source_map)
    return result.output, {}, true
}

macroexpand_source_with_map :: proc(source: string) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    form, err_form, ok_form := read_single_eval_form(source)
    if !ok_form {
        return result, clone_compile_error(err_form, result_allocator), false
    }
    temp_result, err_expand, ok_expand := macroexpand_form(form)
    if !ok_expand {
        return result, clone_compile_error(err_expand, result_allocator), false
    }
    result.output = strings.clone(temp_result.output, result_allocator)
    context.allocator = result_allocator
    for entry in temp_result.source_map {
        append(&result.source_map, entry)
    }
    return result, {}, true
}
