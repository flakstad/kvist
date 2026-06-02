package kvist

import "core:fmt"
import "core:strings"

is_symbol :: proc(form: CST_Form, name: string) -> bool {
    return form.kind == .Symbol && form.text == name
}

is_proc_directive_symbol :: proc(form: CST_Form) -> bool {
    return form.kind == .Symbol && len(form.text) > 1 && form.text[0] == '#'
}

is_proc_prefix_directive :: proc(text: string) -> bool {
    return text == "#force_inline"
}

normalize_scalar_type_name :: proc(text: string) -> string {
    switch text {
    case "bool":
        return "bool"
    case "int":
        return "int"
    case "float":
        return "f64"
    case "string":
        return "string"
    case "char":
        return "rune"
    case "keyword":
        return "string"
    case:
        return map_name(text)
    }
}

normalize_surface_type_symbol :: proc(text: string) -> string {
    if len(text) == 0 {
        return text
    }
    if text[0] == '^' {
        return fmt.tprintf("^%s", normalize_surface_type_symbol(text[1:]))
    }
    if strings.has_prefix(text, "#soa[") {
        closing := strings.index(text, "]")
        if closing > len("#soa[") {
            length := text[len("#soa["):closing]
            elem_text := text[closing+1:]
            return fmt.tprintf("#soa[%s]%s", length, normalize_surface_type_symbol(elem_text))
        }
    }
    if strings.has_prefix(text, "[]") {
        return fmt.tprintf("[]%s", normalize_surface_type_symbol(text[2:]))
    }
    if strings.has_prefix(text, "[dynamic]") {
        return fmt.tprintf("[dynamic]%s", normalize_surface_type_symbol(text[len("[dynamic]"):]))
    }
    if strings.has_prefix(text, "map[") {
        closing := strings.index(text, "]")
        if closing > 4 {
            key_text := text[4:closing]
            value_text := text[closing+1:]
            return fmt.tprintf("map[%s]%s", normalize_surface_type_symbol(key_text), normalize_surface_type_symbol(value_text))
        }
    }
    if strings.has_prefix(text, "set[") {
        closing := strings.index(text, "]")
        if closing > 4 {
            elem_text := text[4:closing]
            if closing == len(text)-1 {
                return fmt.tprintf("map[%s]bool", normalize_surface_type_symbol(elem_text))
            }
        }
    }
    if len(text) > 2 && text[0] == '[' {
        closing := strings.index(text, "]")
        if closing > 1 {
            length := text[1:closing]
            elem_text := text[closing+1:]
            return fmt.tprintf("[%s]%s", length, normalize_surface_type_symbol(elem_text))
        }
    }
    return normalize_scalar_type_name(text)
}

doc_lines_from_string :: proc(text: string) -> (lines: [dynamic]string) {
    start := 0
    for i := 0; i <= len(text); i += 1 {
        if i == len(text) || text[i] == '\n' {
            line := text[start:i]
            append(&lines, fmt.tprintf("// %s", line))
            start = i + 1
        }
    }
    if len(lines) == 0 {
        append(&lines, "// ")
    }
    return lines
}

append_doc_lines :: proc(base, extra: []string) -> (lines: [dynamic]string) {
    for line in base {
        append(&lines, line)
    }
    for line in extra {
        append(&lines, line)
    }
    return lines
}

struct_field_exists :: proc(fields: []Struct_Field, name: string) -> bool {
    for field in fields {
        if field.name == name {
            return true
        }
    }
    return false
}

parse_defstruct_type_meta :: proc(form: CST_Form) -> (text: string, err: Compile_Error, ok: bool) {
    #partial switch form.kind {
    case .Keyword, .Symbol:
        tag := form.text
        if form.kind == .Keyword {
            if len(form.text) <= 1 {
                return "", Compile_Error{message = "invalid defstruct field type metadata", span = form.span}, false
            }
            tag = form.text[1:]
        }
        return normalize_surface_type_symbol(tag), {}, true
    case .Vector:
        if len(form.items) == 0 || (form.items[0].kind != .Keyword && form.items[0].kind != .Symbol) {
            return "", Compile_Error{message = "invalid defstruct field type metadata", span = form.span}, false
        }
        head := form.items[0].text
        if form.items[0].kind == .Keyword {
            head = head[1:]
        }
        switch head {
        case "arr":
            if len(form.items) != 2 {
                return "", Compile_Error{message = "[arr T] expects one element type", span = form.span}, false
            }
            elem_text, err_elem, ok_elem := parse_defstruct_type_meta(form.items[1])
            if !ok_elem {
                return "", err_elem, false
            }
            return fmt.tprintf("[dynamic]%s", elem_text), {}, true
        case "slice":
            if len(form.items) != 2 {
                return "", Compile_Error{message = "[slice T] expects one element type", span = form.span}, false
            }
            elem_text, err_elem, ok_elem := parse_defstruct_type_meta(form.items[1])
            if !ok_elem {
                return "", err_elem, false
            }
            return fmt.tprintf("[]%s", elem_text), {}, true
        case "set":
            if len(form.items) != 2 {
                return "", Compile_Error{message = "[set T] expects one element type", span = form.span}, false
            }
            elem_text, err_elem, ok_elem := parse_defstruct_type_meta(form.items[1])
            if !ok_elem {
                return "", err_elem, false
            }
            return fmt.tprintf("map[%s]bool", elem_text), {}, true
        case "fixed-arr":
            if len(form.items) != 3 || form.items[1].kind != .Number {
                return "", Compile_Error{message = "[fixed-arr N T] expects a numeric length and one element type", span = form.span}, false
            }
            elem_text, err_elem, ok_elem := parse_defstruct_type_meta(form.items[2])
            if !ok_elem {
                return "", err_elem, false
            }
            return fmt.tprintf("[%s]%s", form.items[1].text, elem_text), {}, true
        case:
            return "", Compile_Error{message = "invalid defstruct field type metadata", span = form.span}, false
        }
    case .List:
        return parse_type_text(form)
    case:
        return "", Compile_Error{message = "invalid defstruct field type metadata", span = form.span}, false
    }
}

parse_type_text :: proc(form: CST_Form) -> (text: string, err: Compile_Error, ok: bool) {
    #partial switch form.kind {
    case .Keyword, .Vector:
        return parse_defstruct_type_meta(form)
    case .Symbol:
        return normalize_surface_type_symbol(form.text), {}, true
    case .List:
        if len(form.items) < 2 {
            return "", Compile_Error{message = "unsupported type form", span = form.span}, false
        }

        if is_symbol(form.items[0], "slice") || is_symbol(form.items[0], "core/slice") || is_symbol(form.items[0], "kvist/core/slice") {
            if len(form.items) != 2 {
                return "", Compile_Error{message = "slice type expects one element type", span = form.span}, false
            }
            elem_text, err_elem, ok_elem := parse_type_text(form.items[1])
            if !ok_elem {
                return "", err_elem, false
            }
            return fmt.tprintf("[]%s", elem_text), {}, true
        }

        if is_symbol(form.items[0], "dynamic") {
            if len(form.items) != 2 {
                return "", Compile_Error{message = "dynamic type expects one element type", span = form.span}, false
            }
            elem_text, err_elem, ok_elem := parse_type_text(form.items[1])
            if !ok_elem {
                return "", err_elem, false
            }
            return fmt.tprintf("[dynamic]%s", elem_text), {}, true
        }

        if is_symbol(form.items[0], "array") {
            if len(form.items) != 3 || !(form.items[1].kind == .Symbol || form.items[1].kind == .Number) {
                return "", Compile_Error{message = "array type expects length symbol and element type", span = form.span}, false
            }
            elem_text, err_elem, ok_elem := parse_type_text(form.items[2])
            if !ok_elem {
                return "", err_elem, false
            }
            return fmt.tprintf("[%s]%s", form.items[1].text, elem_text), {}, true
        }

        if is_symbol(form.items[0], "map") {
            if len(form.items) != 3 {
                return "", Compile_Error{message = "map type expects key and value types", span = form.span}, false
            }
            key_text, err_key, ok_key := parse_type_text(form.items[1])
            if !ok_key {
                return "", err_key, false
            }
            value_text, err_value, ok_value := parse_type_text(form.items[2])
            if !ok_value {
                return "", err_value, false
            }
            return fmt.tprintf("map[%s]%s", key_text, value_text), {}, true
        }

        if is_symbol(form.items[0], "ptr") {
            if len(form.items) != 2 {
                return "", Compile_Error{message = "ptr type expects one pointee type", span = form.span}, false
            }
            pointee_text, err_pointee, ok_pointee := parse_type_text(form.items[1])
            if !ok_pointee {
                return "", err_pointee, false
            }
            return fmt.tprintf("^%s", pointee_text), {}, true
        }

        if is_symbol(form.items[0], "type") {
            if len(form.items) < 3 {
                return "", Compile_Error{message = "type form expects a type constructor and at least one argument", span = form.span}, false
            }
            constructor_text, err_constructor, ok_constructor := parse_type_text(form.items[1])
            if !ok_constructor {
                return "", err_constructor, false
            }

            builder := strings.builder_make()
            defer strings.builder_destroy(&builder)
            strings.write_string(&builder, constructor_text)
            strings.write_byte(&builder, '(')
            for arg, idx in form.items[2:] {
                arg_text, err_arg, ok_arg := parse_type_text(arg)
                if !ok_arg {
                    return "", err_arg, false
                }
                if idx > 0 {
                    strings.write_string(&builder, ", ")
                }
                strings.write_string(&builder, arg_text)
            }
            strings.write_byte(&builder, ')')
            return strings.clone(strings.to_string(builder)), {}, true
        }

        if !is_symbol(form.items[0], "proc") {
            return "", Compile_Error{message = "unsupported type form", span = form.span}, false
        }
        proc_text, next_index, err_proc, ok_proc := parse_proc_type_text_from_parts(form.items[:], 0)
        if !ok_proc {
            return "", err_proc, false
        }
        if next_index != len(form.items) {
            return "", Compile_Error{message = "proc type form cannot contain a body", span = form.span}, false
        }
        return proc_text, {}, true
    case:
        return "", Compile_Error{message = "unsupported type form", span = form.span}, false
    }
}

vector_is_named_returns :: proc(form: CST_Form) -> bool {
    if form.kind != .Vector || len(form.items) == 0 {
        return false
    }
    item := form.items[0]
    return item.kind == .Symbol && len(item.text) > 0 && item.text[len(item.text)-1] == ':'
}

parse_proc_type_text_from_parts :: proc(forms: []CST_Form, start: int) -> (text: string, next: int, err: Compile_Error, ok: bool) {
    if start+1 >= len(forms) || forms[start+1].kind != .Vector {
        return "", start, Compile_Error{message = "proc type expects a parameter vector", span = forms[start].span}, false
    }

    params, err_params, ok_params := parse_param_vector(forms[start+1])
    if !ok_params {
        return "", start, err_params, false
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "proc(")
    for param, idx in params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "%s: %s", param.name, param.ty)
    }
    strings.write_byte(&builder, ')')

    next = start + 2
    if next < len(forms) && is_symbol(forms[next], "->") {
        if next+1 >= len(forms) {
            return "", start, Compile_Error{message = "missing proc type return spec", span = forms[next].span}, false
        }

        if vector_is_named_returns(forms[next+1]) {
            named, err_named, ok_named := parse_named_returns(forms[next+1])
            if !ok_named {
                return "", start, err_named, false
            }
            strings.write_string(&builder, " -> (")
            for field, idx in named {
                if idx > 0 {
                    strings.write_string(&builder, ", ")
                }
                fmt.sbprintf(&builder, "%s: %s", field.name, field.ty)
            }
            strings.write_byte(&builder, ')')
            next += 2
        } else {
            return_text, next_after_return, err_return, ok_return := parse_type_text_from_forms(forms, next+1)
            if !ok_return {
                return "", start, err_return, false
            }
            fmt.sbprintf(&builder, " -> %s", return_text)
            next = next_after_return
        }
    }

    return strings.clone(strings.to_string(builder)), next, {}, true
}

parse_type_text_from_forms :: proc(forms: []CST_Form, start: int) -> (text: string, next: int, err: Compile_Error, ok: bool) {
    if start >= len(forms) {
        return "", start, Compile_Error{message = "missing type"}, false
    }
    if is_symbol(forms[start], "proc") {
        return parse_proc_type_text_from_parts(forms, start)
    }
    text, err, ok = parse_type_text(forms[start])
    if !ok {
        return "", start, err, false
    }
    return text, start+1, {}, true
}

expect_kind :: proc(form: CST_Form, kind: CST_Form_Kind, message: string) -> (Compile_Error, bool) {
    if form.kind != kind {
        return Compile_Error{message = message, span = form.span}, false
    }
    return {}, true
}

parse_param_vector :: proc(form: CST_Form) -> (params: [dynamic]Param, err: Compile_Error, ok: bool) {
    if form.kind != .Vector {
        return params, Compile_Error{message = "expected parameter vector", span = form.span}, false
    }
    i := 0
    saw_default := false
    for i < len(form.items) {
        target := form.items[i]
        param := Param{}
        next_i := 0
        #partial switch target.kind {
        case .Symbol:
            if len(target.text) == 0 {
                return params, Compile_Error{message = "expected parameter name", span = target.span}, false
            }
            if target.text[len(target.text)-1] != ':' {
                return params, Compile_Error{message = "expected parameter name ending in ':'", span = target.span}, false
            }
            if i+1 >= len(form.items) {
                return params, Compile_Error{message = "missing parameter type", span = target.span}, false
            }
            type_text, parsed_next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], i+1)
            if !ok_type {
                return params, err_type, false
            }
            param = Param{
                name = map_name(target.text[:len(target.text)-1]),
                ty   = type_text,
            }
            next_i = parsed_next_i
        case .Brace:
            if i+2 >= len(form.items) {
                return params, Compile_Error{message = "destructured parameter missing : and type", span = target.span}, false
            }
            separator := form.items[i+1]
            if separator.kind != .Keyword || separator.text != ":" {
                return params, Compile_Error{message = "destructured parameter expects {:keys [...] :as name}: Type", span = separator.span}, false
            }

            fields: [dynamic]Struct_Field
            as_name := ""
            saw_keys := false
            j := 0
            for j < len(target.items) {
                if target.items[j].kind != .Keyword {
                    return params, Compile_Error{message = "destructured parameter expects keyword entries", span = target.items[j].span}, false
                }
                key := target.items[j].text
                switch key {
                case ":keys":
                    if saw_keys || j+1 >= len(target.items) || target.items[j+1].kind != .Vector {
                        return params, Compile_Error{message = "destructured parameter expects one :keys vector", span = target.items[j].span}, false
                    }
                    for item in target.items[j+1].items {
                        if item.kind != .Symbol {
                            return params, Compile_Error{message = ":keys parameter destructuring expects symbols", span = item.span}, false
                        }
                        name := map_name(item.text)
                        if struct_field_exists(fields[:], name) {
                            return params, Compile_Error{message = fmt.tprintf("duplicate field :%s in parameter destructuring", name), span = item.span}, false
                        }
                        append(&fields, Struct_Field{name = name, source_name = name})
                    }
                    saw_keys = true
                    j += 2
                case ":as":
                    if as_name != "" || j+1 >= len(target.items) || target.items[j+1].kind != .Symbol {
                        return params, Compile_Error{message = "destructured parameter expects one :as symbol", span = target.items[j].span}, false
                    }
                    as_name = map_name(target.items[j+1].text)
                    j += 2
                case:
                    return params, Compile_Error{message = "destructured parameter only supports :keys and :as", span = target.items[j].span}, false
                }
            }
            if !saw_keys || len(fields) == 0 {
                return params, Compile_Error{message = "destructured parameter expects :keys with at least one field", span = target.span}, false
            }
            if as_name == "" {
                return params, Compile_Error{message = "destructured parameter currently requires :as", span = target.span}, false
            }
            type_text, parsed_next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], i+2)
            if !ok_type {
                return params, err_type, false
            }
            param = Param{
                name                 = as_name,
                ty                   = type_text,
                is_field_destructure = true,
                destructure_fields   = fields,
            }
            next_i = parsed_next_i
        case:
            return params, Compile_Error{message = "expected parameter name or destructuring form", span = target.span}, false
        }
        if next_i < len(form.items) && is_symbol(form.items[next_i], "=") {
            if next_i+1 >= len(form.items) {
                return params, Compile_Error{message = "missing default parameter value", span = form.items[next_i].span}, false
            }
            param.has_default = true
            param.default_value = form.items[next_i+1]
            next_i += 2
            saw_default = true
        } else if saw_default {
            return params, Compile_Error{message = "parameters with defaults must trail required parameters", span = target.span}, false
        }
        append(&params, param)
        i = next_i
    }
    return params, {}, true
}

parse_named_returns :: proc(form: CST_Form) -> (fields: [dynamic]Named_Return, err: Compile_Error, ok: bool) {
    if form.kind != .Vector {
        return fields, Compile_Error{message = "expected return vector", span = form.span}, false
    }
    i := 0
    for i < len(form.items) {
        name_form := form.items[i]
        if name_form.kind != .Symbol || len(name_form.text) == 0 || name_form.text[len(name_form.text)-1] != ':' {
            return fields, Compile_Error{message = "expected named return ending in ':'", span = name_form.span}, false
        }
        if i+1 >= len(form.items) {
            return fields, Compile_Error{message = "missing named return type", span = name_form.span}, false
        }
        type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], i+1)
        if !ok_type {
            return fields, err_type, false
        }
        append(&fields, Named_Return{
            name = map_name(name_form.text[:len(name_form.text)-1]),
            ty   = type_text,
        })
        i = next_i
    }
    return fields, {}, true
}

parse_struct_fields :: proc(form: CST_Form) -> (fields: [dynamic]Struct_Field, err: Compile_Error, ok: bool) {
    if form.kind != .Brace {
        return fields, Compile_Error{message = "expected struct field brace form", span = form.span}, false
    }
    i := 0
    for i < len(form.items) {
        if i+1 >= len(form.items) {
            return fields, Compile_Error{message = "missing struct field type", span = form.span}, false
        }
        key := form.items[i]
        if key.kind != .Keyword {
            return fields, Compile_Error{message = "expected struct field keyword", span = key.span}, false
        }
        field_name := map_name(key.text[1:])
        if struct_field_exists(fields[:], field_name) {
            return fields, Compile_Error{message = fmt.tprintf("duplicate struct field %s", key.text), span = key.span}, false
        }
        type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], i+1)
        if !ok_type {
            return fields, err_type, false
        }
        append(&fields, Struct_Field{
            name        = field_name,
            source_name = key.text[1:],
            ty          = type_text,
        })
        i = next_i
    }
    return fields, {}, true
}

parse_defstruct_fields :: proc(form: CST_Form) -> (fields: [dynamic]Struct_Field, err: Compile_Error, ok: bool) {
    if form.kind != .Brace {
        return fields, Compile_Error{message = "expected defstruct field brace form", span = form.span}, false
    }
    i := 0
    for i < len(form.items) {
        if i+1 >= len(form.items) {
            return fields, Compile_Error{message = "missing defstruct field type metadata", span = form.span}, false
        }
        key := form.items[i]
        if key.kind != .Keyword {
            return fields, Compile_Error{message = "expected defstruct field keyword", span = key.span}, false
        }
        field_name := map_name(key.text[1:])
        if struct_field_exists(fields[:], field_name) {
            return fields, Compile_Error{message = fmt.tprintf("duplicate defstruct field %s", key.text), span = key.span}, false
        }
        type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], i+1)
        if !ok_type {
            return fields, err_type, false
        }
        append(&fields, Struct_Field{
            name        = field_name,
            source_name = key.text[1:],
            ty          = type_text,
        })
        i = next_i
    }
    return fields, {}, true
}

parse_union_variants :: proc(form: CST_Form) -> (variants: [dynamic]Union_Variant, err: Compile_Error, ok: bool) {
    if form.kind != .Brace {
        return variants, Compile_Error{message = "expected union variant brace form", span = form.span}, false
    }
    i := 0
    for i < len(form.items) {
        if i+1 >= len(form.items) {
            return variants, Compile_Error{message = "missing union variant type", span = form.span}, false
        }
        key := form.items[i]
        if key.kind != .Keyword {
            return variants, Compile_Error{message = "expected union variant keyword", span = key.span}, false
        }
        type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], i+1)
        if !ok_type {
            return variants, err_type, false
        }
        append(&variants, Union_Variant{
            name = map_name(key.text[1:]),
            ty   = type_text,
        })
        i = next_i
    }
    return variants, {}, true
}

parse_enum_variants :: proc(form: CST_Form) -> (variants: [dynamic]Enum_Variant, err: Compile_Error, ok: bool) {
    #partial switch form.kind {
    case .Vector:
        for item in form.items {
            if item.kind != .Symbol {
                return variants, Compile_Error{message = "expected enum variant symbol", span = item.span}, false
            }
            append(&variants, Enum_Variant{name = map_name(item.text)})
        }
        return variants, {}, true
    case .Brace:
        i := 0
        for i < len(form.items) {
            if i+1 >= len(form.items) {
                return variants, Compile_Error{message = "missing enum variant value", span = form.span}, false
            }
            key := form.items[i]
            if key.kind != .Keyword {
                return variants, Compile_Error{message = "expected enum variant keyword", span = key.span}, false
            }
            append(&variants, Enum_Variant{
                name = map_name(key.text[1:]),
                has_value = true,
                value = form.items[i+1],
            })
            i += 2
        }
        return variants, {}, true
    case .Set:
        return variants, Compile_Error{message = "expected enum variant vector or brace form", span = form.span}, false
    case:
        return variants, Compile_Error{message = "expected enum variant vector or brace form", span = form.span}, false
    }
    return variants, Compile_Error{message = "expected enum variant vector or brace form", span = form.span}, false
}

parse_proc_decl :: proc(form: CST_Form) -> (decl: Proc_Decl, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 {
        return decl, Compile_Error{message = "proc requires name, params, and body", span = form.span}, false
    }
    name_form := form.items[1]
    if name_form.kind != .Symbol {
        return decl, Compile_Error{message = "expected proc name", span = name_form.span}, false
    }
    params_index := 2
    calling_convention := ""
    if params_index+1 < len(form.items) &&
       form.items[params_index].kind == .Keyword &&
       form.items[params_index].text == ":abi" {
        if form.items[params_index+1].kind != .String {
            return decl, Compile_Error{message = ":abi expects a string literal", span = form.items[params_index+1].span}, false
        }
        calling_convention = unquote_string(form.items[params_index+1].text)
        params_index += 2
    }
    if params_index >= len(form.items) {
        return decl, Compile_Error{message = "proc requires a parameter vector", span = form.span}, false
    }
    params, err_params, ok_params := parse_param_vector(form.items[params_index])
    if !ok_params {
        return decl, err_params, false
    }

    body_index := params_index + 1
    returns := Return_Spec{kind = .None}
    if body_index < len(form.items) && is_symbol(form.items[body_index], "->") {
        if body_index+1 >= len(form.items) {
            return decl, Compile_Error{message = "missing return spec after '->'", span = form.items[body_index].span}, false
        }
        return_form := form.items[body_index+1]
        #partial switch return_form.kind {
        case .Symbol, .List, .Keyword:
            return_text, next_index, err_return, ok_return := parse_type_text_from_forms(form.items[:], body_index+1)
            if !ok_return {
                return decl, err_return, false
            }
            returns.kind = .Single
            returns.single_ty = return_text
            body_index = next_index
        case .Vector:
            if vector_is_named_returns(return_form) {
                named, err_named, ok_named := parse_named_returns(return_form)
                if !ok_named {
                    return decl, err_named, false
                }
                returns.kind = .Named
                returns.named = named
                body_index += 2
            } else {
                return_text, next_index, err_return, ok_return := parse_type_text_from_forms(form.items[:], body_index+1)
                if !ok_return {
                    return decl, err_return, false
                }
                returns.kind = .Single
                returns.single_ty = return_text
                body_index = next_index
            }
        case:
            return decl, Compile_Error{message = "unsupported return spec", span = return_form.span}, false
        }
    }
    if body_index >= len(form.items) {
        return decl, Compile_Error{message = "proc body is empty", span = form.span}, false
    }
    prefix_directives: [dynamic]string
    suffix_directives: [dynamic]string
    for body_index < len(form.items) && is_proc_directive_symbol(form.items[body_index]) {
        directive := form.items[body_index].text
        if is_proc_prefix_directive(directive) {
            append(&prefix_directives, directive)
        } else {
            append(&suffix_directives, directive)
        }
        body_index += 1
    }
    if body_index >= len(form.items) {
        return decl, Compile_Error{message = "proc body is empty", span = form.span}, false
    }
    body: [dynamic]CST_Form
    for item in form.items[body_index:] {
        append(&body, item)
    }
    return Proc_Decl{
        name              = map_name(name_form.text),
        calling_convention = calling_convention,
        params            = params,
        returns           = returns,
        prefix_directives = prefix_directives,
        suffix_directives = suffix_directives,
        body              = body,
    }, {}, true
}

parse_decl :: proc(top_form: CST_Top_Form) -> (decl: AST_Decl, err: Compile_Error, ok: bool) {
    form := top_form.form
    if form.kind != .List || len(form.items) == 0 {
        return decl, Compile_Error{message = "expected top-level list form", span = form.span}, false
    }
    head := form.items[0]
    if head.kind != .Symbol {
        return decl, Compile_Error{message = "expected top-level symbol head", span = head.span}, false
    }

    switch head.text {
    case "comment":
        return AST_Decl{}, Compile_Error{message = "`comment` has moved to `core/comment`", span = form.span}, false
    case "core/comment":
        return AST_Decl{kind = .Ignored, span = form.span}, {}, true
    case "package":
        if len(form.items) != 2 || form.items[1].kind != .Symbol {
            return decl, Compile_Error{message = "package expects one symbol", span = form.span}, false
        }
        return AST_Decl{
            kind = .Package,
            span = form.span,
            doc_lines = top_form.doc_lines,
            package_name = map_name(form.items[1].text),
        }, {}, true
    case "import":
        if len(form.items) == 2 && form.items[1].kind == .String {
            return AST_Decl{
                kind = .Import,
                span = form.span,
                doc_lines = top_form.doc_lines,
                import_decl = Import_Decl{path = form.items[1].text},
            }, {}, true
        }
        if len(form.items) == 3 && form.items[1].kind == .Symbol && form.items[2].kind == .String {
            return AST_Decl{
                kind = .Import,
                span = form.span,
                doc_lines = top_form.doc_lines,
                import_decl = Import_Decl{
                    alias     = map_name(form.items[1].text),
                    path      = form.items[2].text,
                    has_alias = true,
                },
            }, {}, true
        }
        if len(form.items) == 3 &&
           form.items[1].kind == .Keyword &&
           form.items[1].text == ":odin" &&
           form.items[2].kind == .String {
            return AST_Decl{
                kind = .Import,
                span = form.span,
                doc_lines = top_form.doc_lines,
                import_decl = Import_Decl{
                    path = form.items[2].text,
                    force_odin = true,
                },
            }, {}, true
        }
        if len(form.items) == 4 &&
           form.items[1].kind == .Symbol &&
           form.items[2].kind == .Keyword &&
           form.items[2].text == ":odin" &&
           form.items[3].kind == .String {
            return AST_Decl{
                kind = .Import,
                span = form.span,
                doc_lines = top_form.doc_lines,
                import_decl = Import_Decl{
                    alias = map_name(form.items[1].text),
                    path = form.items[3].text,
                    has_alias = true,
                    force_odin = true,
                },
            }, {}, true
        }
        return decl, Compile_Error{message = "import expects a string path, alias plus string path, :odin plus string path, or alias plus :odin plus string path", span = form.span}, false
    case "defconst", "defconst-":
        if len(form.items) < 3 {
            return decl, Compile_Error{message = "defconst expects a name, optional type, and value", span = form.span}, false
        }
        if form.items[1].kind != .Symbol {
            return decl, Compile_Error{message = "defconst expects a symbol name", span = form.items[1].span}, false
        }
        doc_lines := top_form.doc_lines
        value_index := 2
        if len(form.items) > 3 && form.items[2].kind == .String {
            doc_lines = append_doc_lines(doc_lines[:], doc_lines_from_string(unquote_string(form.items[2].text))[:])
            value_index = 3
        }
        const_decl := Const_Decl{
            name = map_name(form.items[1].text),
        }
        if len(form.items) == value_index+1 {
            const_decl.value = form.items[value_index]
        } else {
            type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], value_index)
            if !ok_type {
                return decl, err_type, false
            }
            if next_i >= len(form.items) {
                return decl, Compile_Error{message = "typed defconst missing value", span = form.span}, false
            }
            if next_i+1 != len(form.items) {
                return decl, Compile_Error{message = "defconst expects exactly one value", span = form.items[next_i+1].span}, false
            }
            const_decl.has_ty = true
            const_decl.ty = type_text
            const_decl.value = form.items[next_i]
        }
        return AST_Decl{
            kind = .Const,
            span = form.span,
            doc_lines = doc_lines,
            const_decl = const_decl,
        }, {}, true
    case "defvar", "defvar-":
        if len(form.items) < 3 {
            return decl, Compile_Error{message = "defvar expects a name, optional type, and value", span = form.span}, false
        }
        if form.items[1].kind != .Symbol {
            return decl, Compile_Error{message = "defvar expects a symbol name", span = form.items[1].span}, false
        }
        doc_lines := top_form.doc_lines
        value_index := 2
        if len(form.items) > 3 && form.items[2].kind == .String {
            doc_lines = append_doc_lines(doc_lines[:], doc_lines_from_string(unquote_string(form.items[2].text))[:])
            value_index = 3
        }
        var_decl := Var_Decl{name = map_name(form.items[1].text)}
        if len(form.items) == value_index+1 {
            var_decl.value = form.items[value_index]
        } else {
            type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], value_index)
            if !ok_type {
                return decl, err_type, false
            }
            if next_i >= len(form.items) {
                return decl, Compile_Error{message = "typed defvar missing value", span = form.span}, false
            }
            if next_i+1 != len(form.items) {
                return decl, Compile_Error{message = "defvar expects exactly one value", span = form.items[next_i+1].span}, false
            }
            var_decl.has_ty = true
            var_decl.ty = type_text
            var_decl.value = form.items[next_i]
        }
        return AST_Decl{
            kind = .Var,
            span = form.span,
            doc_lines = doc_lines,
            var_decl = var_decl,
        }, {}, true
    case "defstruct", "defstruct-", "defstate":
        if len(form.items) != 3 && len(form.items) != 4 && len(form.items) != 5 {
            return decl, Compile_Error{message = fmt.tprintf("%s expects a name, optional docstring, a brace field form, and optional brace metadata form", head.text), span = form.span}, false
        }
        if form.items[1].kind != .Symbol {
            return decl, Compile_Error{message = fmt.tprintf("%s expects a symbol name", head.text), span = form.items[1].span}, false
        }
        doc_lines := top_form.doc_lines
        field_index := 2
        meta_index := -1
        if len(form.items) >= 4 && form.items[2].kind == .String {
            if form.items[2].kind != .String {
                return decl, Compile_Error{message = fmt.tprintf("%s docstring must be a string literal", head.text), span = form.items[2].span}, false
            }
            doc_lines = append_doc_lines(doc_lines[:], doc_lines_from_string(unquote_string(form.items[2].text))[:])
            field_index = 3
            if len(form.items) == 5 {
                meta_index = 4
            }
        } else if len(form.items) == 4 {
            meta_index = 3
        }
        if form.items[field_index].kind != .Brace {
            return decl, Compile_Error{message = fmt.tprintf("%s expects a brace field form", head.text), span = form.items[field_index].span}, false
        }
        if meta_index >= 0 && form.items[meta_index].kind != .Brace {
            return decl, Compile_Error{message = fmt.tprintf("%s metadata must be a brace form", head.text), span = form.items[meta_index].span}, false
        }
        fields, err_fields, ok_fields := parse_defstruct_fields(form.items[field_index])
        if !ok_fields {
            return decl, err_fields, false
        }
        return AST_Decl{
            kind = .Struct,
            span = form.span,
            doc_lines = doc_lines,
            struct_decl = Struct_Decl{
                name   = map_name(form.items[1].text),
                fields = fields,
            },
        }, {}, true
    case "defenum", "defenum-":
        if len(form.items) < 3 || form.items[1].kind != .Symbol {
            return decl, Compile_Error{message = "defenum expects a name and variant vector or brace form", span = form.span}, false
        }
        doc_lines := top_form.doc_lines
        variant_index := 2
        if len(form.items) > 3 && form.items[2].kind == .String {
            doc_lines = append_doc_lines(doc_lines[:], doc_lines_from_string(unquote_string(form.items[2].text))[:])
            variant_index = 3
        }
        if len(form.items) != variant_index+1 {
            return decl, Compile_Error{message = "defenum expects a name and variant vector or brace form", span = form.span}, false
        }
        variants, err_variants, ok_variants := parse_enum_variants(form.items[variant_index])
        if !ok_variants {
            return decl, err_variants, false
        }
        return AST_Decl{
            kind = .Enum,
            span = form.span,
            doc_lines = doc_lines,
            enum_decl = Enum_Decl{
                name = map_name(form.items[1].text),
                variants = variants,
            },
        }, {}, true
    case "defunion", "defunion-":
        if len(form.items) < 3 || form.items[1].kind != .Symbol {
            return decl, Compile_Error{message = "defunion expects a name and variant brace form", span = form.span}, false
        }
        doc_lines := top_form.doc_lines
        variant_index := 2
        if len(form.items) > 3 && form.items[2].kind == .String {
            doc_lines = append_doc_lines(doc_lines[:], doc_lines_from_string(unquote_string(form.items[2].text))[:])
            variant_index = 3
        }
        if len(form.items) != variant_index+1 {
            return decl, Compile_Error{message = "defunion expects a name and variant brace form", span = form.span}, false
        }
        variants, err_variants, ok_variants := parse_union_variants(form.items[variant_index])
        if !ok_variants {
            return decl, err_variants, false
        }
        return AST_Decl{
            kind = .Union,
            span = form.span,
            doc_lines = doc_lines,
            union_decl = Union_Decl{
                name     = map_name(form.items[1].text),
                variants = variants,
            },
        }, {}, true
    case "odin":
        if len(form.items) != 2 || form.items[1].kind != .String {
            return decl, Compile_Error{message = "odin expects one string literal", span = form.span}, false
        }
        return AST_Decl{
            kind = .Raw,
            span = form.span,
            doc_lines = top_form.doc_lines,
            raw_text = unquote_string(form.items[1].text),
        }, {}, true
    case "export":
        if len(form.items) != 1 {
            return decl, Compile_Error{message = "export does not take arguments", span = form.span}, false
        }
        return AST_Decl{
            kind = .Raw,
            span = form.span,
            doc_lines = top_form.doc_lines,
            raw_text = "@(export)",
        }, {}, true
    case "exports":
        if len(form.items) != 2 || form.items[1].kind != .Vector {
            return decl, Compile_Error{message = "exports expects one vector of symbol names", span = form.span}, false
        }
        for item in form.items[1].items {
            if item.kind != .Symbol {
                return decl, Compile_Error{message = "exports expects symbol names", span = item.span}, false
            }
        }
        return AST_Decl{kind = .Ignored, span = form.span}, {}, true
    case "proc", "defn", "defn-":
        doc_lines := top_form.doc_lines
        proc_form := form
        doc_index := 2
        if len(form.items) > 4 &&
           form.items[2].kind == .Keyword &&
           form.items[2].text == ":abi" &&
           form.items[3].kind == .String {
            doc_index = 4
        }
        if len(form.items) > doc_index+1 && form.items[doc_index].kind == .String {
            doc_lines = append_doc_lines(doc_lines[:], doc_lines_from_string(unquote_string(form.items[doc_index].text))[:])
            items: [dynamic]CST_Form
            for item, idx in form.items {
                if idx == doc_index {
                    continue
                }
                append(&items, item)
            }
            proc_form = CST_Form{kind = .List, items = items, span = form.span}
        }
        proc_decl, err_proc, ok_proc := parse_proc_decl(proc_form)
        if !ok_proc {
            return decl, err_proc, false
        }
        return AST_Decl{
            kind = .Proc,
            span = form.span,
            doc_lines = doc_lines,
            proc_decl = proc_decl,
        }, {}, true
    case "defmacro", "defmacro-":
        return AST_Decl{kind = .Ignored, span = form.span}, {}, true
        case:
            return decl, Compile_Error{message = fmt.tprintf("unsupported top-level form: %s", head.text), span = head.span}, false
        }
    }

parse_decls :: proc(forms: []CST_Top_Form) -> (decls: [dynamic]AST_Decl, err: Compile_Error, ok: bool) {
    for form in forms {
        decl, err_decl, ok_decl := parse_decl(form)
        if !ok_decl {
            return decls, err_decl, false
        }
        if decl.kind != .Ignored {
            append(&decls, decl)
        }
    }
    return decls, {}, true
}

parse_program :: proc(forms: []CST_Top_Form) -> (program: AST_Program, err: Compile_Error, ok: bool) {
    decls, err_decls, ok_decls := parse_decls(forms)
    if !ok_decls {
        return program, err_decls, false
    }
    program.decls = decls
    return program, {}, true
}
