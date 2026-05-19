package odinl

import "core:fmt"
import "core:strings"
import "base:runtime"

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

macro_form_text :: proc(form: CST_Form) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    write_macro_form(&builder, form)
    return strings.clone(strings.to_string(builder))
}

macroexpand_with_allocator :: proc(form: CST_Form) -> (output: string, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 || form.items[1].kind != .Vector {
        return "", Compile_Error{message = "with-allocator expects binding vector and body", span = form.span}, false
    }
    binding := form.items[1]
    if len(binding.items) != 2 || binding.items[0].kind != .Symbol {
        return "", Compile_Error{message = "with-allocator expects [name allocator] binding", span = binding.span}, false
    }

    allocator_name := binding.items[0].text
    allocator_expr := macro_form_text(binding.items[1])
    defer delete(allocator_expr)

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    fmt.sbprintf(&builder, "(do\n")
    fmt.sbprintf(&builder, "  (let [%s %s\n", allocator_name, allocator_expr)
    fmt.sbprintf(&builder, "        odinl-old-allocator-1 context.allocator]\n")
    fmt.sbprintf(&builder, "    (set! context.allocator %s)\n", allocator_name)
    fmt.sbprintf(&builder, "    (defer (do\n")
    fmt.sbprintf(&builder, "      (set! context.allocator odinl-old-allocator-1)))")
    for item in form.items[2:] {
        item_text := macro_form_text(item)
        defer delete(item_text)
        fmt.sbprintf(&builder, "\n    %s", item_text)
    }
    fmt.sbprintf(&builder, "))\n")

    return strings.clone(strings.to_string(builder)), {}, true
}

macroexpand_with_temp_allocator :: proc(form: CST_Form) -> (output: string, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 || form.items[1].kind != .Vector {
        return "", Compile_Error{message = "with-temp-allocator expects binding vector and body", span = form.span}, false
    }
    binding := form.items[1]
    if len(binding.items) != 1 || binding.items[0].kind != .Symbol {
        return "", Compile_Error{message = "with-temp-allocator expects [name] binding", span = binding.span}, false
    }

    allocator_name := binding.items[0].text

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    fmt.sbprintf(&builder, "(do\n")
    fmt.sbprintf(&builder, "  (let [odinl-temp-scope-1 (runtime.default-temp-allocator-temp-begin)\n")
    fmt.sbprintf(&builder, "        %s context.temp-allocator\n", allocator_name)
    fmt.sbprintf(&builder, "        odinl-old-allocator-1 context.allocator]\n")
    fmt.sbprintf(&builder, "    (set! context.allocator %s)\n", allocator_name)
    fmt.sbprintf(&builder, "    (defer (do\n")
    fmt.sbprintf(&builder, "      (set! context.allocator odinl-old-allocator-1)\n")
    fmt.sbprintf(&builder, "      (runtime.default-temp-allocator-temp-end odinl-temp-scope-1)))")
    for item in form.items[2:] {
        item_text := macro_form_text(item)
        defer delete(item_text)
        fmt.sbprintf(&builder, "\n    %s", item_text)
    }
    fmt.sbprintf(&builder, "))\n")

    return strings.clone(strings.to_string(builder)), {}, true
}

macroexpand_with_delete :: proc(form: CST_Form) -> (output: string, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 || form.items[1].kind != .Vector {
        return "", Compile_Error{message = "with-delete expects binding vector and body", span = form.span}, false
    }
    binding := form.items[1]
    if len(binding.items) < 2 || len(binding.items)%2 != 0 {
        return "", Compile_Error{message = "with-delete expects [name value ...] bindings", span = binding.span}, false
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    fmt.sbprintf(&builder, "(do\n")
    fmt.sbprintf(&builder, "  (let [")
    i := 0
    for i < len(binding.items) {
        if binding.items[i].kind != .Symbol {
            return "", Compile_Error{message = "with-delete binding name must be a symbol", span = binding.items[i].span}, false
        }
        binding_name := binding.items[i].text
        value_expr := macro_form_text(binding.items[i+1])
        defer delete(value_expr)
        if i == 0 {
            fmt.sbprintf(&builder, "%s %s", binding_name, value_expr)
        } else {
            fmt.sbprintf(&builder, "\n        %s %s", binding_name, value_expr)
        }
        i += 2
    }
    fmt.sbprintf(&builder, "]")
    i = 0
    for i < len(binding.items) {
        binding_name := binding.items[i].text
        fmt.sbprintf(&builder, "\n    (defer (delete %s))", binding_name)
        i += 2
    }
    for item in form.items[2:] {
        item_text := macro_form_text(item)
        defer delete(item_text)
        fmt.sbprintf(&builder, "\n    %s", item_text)
    }
    fmt.sbprintf(&builder, "))\n")

    return strings.clone(strings.to_string(builder)), {}, true
}

macroexpand_form :: proc(form: CST_Form) -> (output: string, err: Compile_Error, ok: bool) {
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        switch form.items[0].text {
        case "with-allocator":
            return macroexpand_with_allocator(form)
        case "with-temp-allocator":
            return macroexpand_with_temp_allocator(form)
        case "with-delete":
            return macroexpand_with_delete(form)
        }
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    write_macro_form(&builder, form)
    strings.write_byte(&builder, '\n')
    return strings.clone(strings.to_string(builder)), {}, true
}

macroexpand_source :: proc(source: string) -> (output: string, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    form, err_form, ok_form := read_single_eval_form(source)
    if !ok_form {
        return "", clone_compile_error(err_form, result_allocator), false
    }
    temp_output, err_expand, ok_expand := macroexpand_form(form)
    if !ok_expand {
        return "", clone_compile_error(err_expand, result_allocator), false
    }
    return strings.clone(temp_output, result_allocator), {}, true
}
