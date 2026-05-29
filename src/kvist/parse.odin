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
    case .Keyword:
        if len(form.text) <= 1 {
            return "", Compile_Error{message = "invalid defstruct field type metadata", span = form.span}, false
        }
        tag := form.text[1:]
        switch tag {
        case "bool":
            return "bool", {}, true
        case "int":
            return "int", {}, true
        case "float":
            return "f64", {}, true
        case "string":
            return "string", {}, true
        case "char":
            return "rune", {}, true
        case "keyword":
            return "string", {}, true
        case:
            return map_name(tag), {}, true
        }
    case .Vector:
        if len(form.items) == 0 || form.items[0].kind != .Keyword {
            return "", Compile_Error{message = "invalid defstruct field type metadata", span = form.span}, false
        }
        head := form.items[0].text
        switch head {
        case ":arr":
            if len(form.items) != 2 {
                return "", Compile_Error{message = "[:arr T] expects one element type", span = form.span}, false
            }
            elem_text, err_elem, ok_elem := parse_defstruct_type_meta(form.items[1])
            if !ok_elem {
                return "", err_elem, false
            }
            return fmt.tprintf("[dynamic]%s", elem_text), {}, true
        case ":slice":
            if len(form.items) != 2 {
                return "", Compile_Error{message = "[:slice T] expects one element type", span = form.span}, false
            }
            elem_text, err_elem, ok_elem := parse_defstruct_type_meta(form.items[1])
            if !ok_elem {
                return "", err_elem, false
            }
            return fmt.tprintf("[]%s", elem_text), {}, true
        case ":set":
            if len(form.items) != 2 {
                return "", Compile_Error{message = "[:set T] expects one element type", span = form.span}, false
            }
            elem_text, err_elem, ok_elem := parse_defstruct_type_meta(form.items[1])
            if !ok_elem {
                return "", err_elem, false
            }
            return fmt.tprintf("map[%s]bool", elem_text), {}, true
        case ":fixed-arr":
            if len(form.items) != 3 || form.items[1].kind != .Number {
                return "", Compile_Error{message = "[:fixed-arr N T] expects a numeric length and one element type", span = form.span}, false
            }
            elem_text, err_elem, ok_elem := parse_defstruct_type_meta(form.items[2])
            if !ok_elem {
                return "", err_elem, false
            }
            return fmt.tprintf("[%s]%s", form.items[1].text, elem_text), {}, true
        case:
            return "", Compile_Error{message = "invalid defstruct field type metadata", span = form.span}, false
        }
    case:
        return "", Compile_Error{message = "invalid defstruct field type metadata", span = form.span}, false
    }
}

parse_type_text :: proc(form: CST_Form) -> (text: string, err: Compile_Error, ok: bool) {
    #partial switch form.kind {
    case .Symbol:
        return map_name(form.text), {}, true
    case .List:
        if len(form.items) < 2 {
            return "", Compile_Error{message = "unsupported type form", span = form.span}, false
        }

        if is_symbol(form.items[0], "slice") {
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

        if forms[next+1].kind == .Vector {
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
    for i < len(form.items) {
        name_form := form.items[i]
        if name_form.kind != .Symbol || len(name_form.text) == 0 || name_form.text[len(name_form.text)-1] != ':' {
            return params, Compile_Error{message = "expected parameter name ending in ':'", span = name_form.span}, false
        }
        if i+1 >= len(form.items) {
            return params, Compile_Error{message = "missing parameter type", span = name_form.span}, false
        }
        type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], i+1)
        if !ok_type {
            return params, err_type, false
        }
        append(&params, Param{
            name = map_name(name_form.text[:len(name_form.text)-1]),
            ty   = type_text,
        })
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
            name = field_name,
            ty   = type_text,
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
        type_text, err_type, ok_type := parse_defstruct_type_meta(form.items[i+1])
        if !ok_type {
            return fields, err_type, false
        }
        append(&fields, Struct_Field{
            name = field_name,
            ty   = type_text,
        })
        i += 2
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
    params, err_params, ok_params := parse_param_vector(form.items[2])
    if !ok_params {
        return decl, err_params, false
    }

    body_index := 3
    returns := Return_Spec{kind = .None}
    if body_index < len(form.items) && is_symbol(form.items[body_index], "->") {
        if body_index+1 >= len(form.items) {
            return decl, Compile_Error{message = "missing return spec after '->'", span = form.items[body_index].span}, false
        }
        return_form := form.items[body_index+1]
        #partial switch return_form.kind {
        case .Symbol, .List:
            return_text, next_index, err_return, ok_return := parse_type_text_from_forms(form.items[:], body_index+1)
            if !ok_return {
                return decl, err_return, false
            }
            returns.kind = .Single
            returns.single_ty = return_text
            body_index = next_index
        case .Vector:
            named, err_named, ok_named := parse_named_returns(return_form)
            if !ok_named {
                return decl, err_named, false
            }
            returns.kind = .Named
            returns.named = named
            body_index += 2
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
        return decl, Compile_Error{message = "import expects a string path or alias plus string path", span = form.span}, false
    case "const":
        if len(form.items) < 3 {
            return decl, Compile_Error{message = "const expects a name, optional type, and value", span = form.span}, false
        }
        if form.items[1].kind != .Symbol {
            return decl, Compile_Error{message = "const expects a symbol name", span = form.items[1].span}, false
        }
        const_decl := Const_Decl{
            name = map_name(form.items[1].text),
        }
        if len(form.items) == 3 {
            const_decl.value = form.items[2]
        } else {
            type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], 2)
            if !ok_type {
                return decl, err_type, false
            }
            if next_i >= len(form.items) {
                return decl, Compile_Error{message = "typed const missing value", span = form.span}, false
            }
            if next_i+1 != len(form.items) {
                return decl, Compile_Error{message = "const expects exactly one value", span = form.items[next_i+1].span}, false
            }
            const_decl.has_ty = true
            const_decl.ty = type_text
            const_decl.value = form.items[next_i]
        }
        return AST_Decl{
            kind = .Const,
            span = form.span,
            doc_lines = top_form.doc_lines,
            const_decl = const_decl,
        }, {}, true
    case "struct":
        if len(form.items) != 3 || form.items[1].kind != .Symbol {
            return decl, Compile_Error{message = "struct expects a name and brace form", span = form.span}, false
        }
        fields, err_fields, ok_fields := parse_struct_fields(form.items[2])
        if !ok_fields {
            return decl, err_fields, false
        }
        return AST_Decl{
            kind = .Struct,
            span = form.span,
            doc_lines = top_form.doc_lines,
            struct_decl = Struct_Decl{
                name   = map_name(form.items[1].text),
                fields = fields,
            },
        }, {}, true
    case "defstruct":
        if len(form.items) != 3 && len(form.items) != 4 {
            return decl, Compile_Error{message = "defstruct expects a name, optional docstring, and brace form", span = form.span}, false
        }
        if form.items[1].kind != .Symbol {
            return decl, Compile_Error{message = "defstruct expects a symbol name", span = form.items[1].span}, false
        }
        doc_lines := top_form.doc_lines
        field_index := 2
        if len(form.items) == 4 {
            if form.items[2].kind != .String {
                return decl, Compile_Error{message = "defstruct docstring must be a string literal", span = form.items[2].span}, false
            }
            doc_lines = append_doc_lines(doc_lines[:], doc_lines_from_string(unquote_string(form.items[2].text))[:])
            field_index = 3
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
    case "enum":
        if len(form.items) != 3 || form.items[1].kind != .Symbol {
            return decl, Compile_Error{message = "enum expects a name and variant vector or brace form", span = form.span}, false
        }
        variants, err_variants, ok_variants := parse_enum_variants(form.items[2])
        if !ok_variants {
            return decl, err_variants, false
        }
        return AST_Decl{
            kind = .Enum,
            span = form.span,
            doc_lines = top_form.doc_lines,
            enum_decl = Enum_Decl{
                name = map_name(form.items[1].text),
                variants = variants,
            },
        }, {}, true
    case "union":
        if len(form.items) != 3 || form.items[1].kind != .Symbol {
            return decl, Compile_Error{message = "union expects a name and variant brace form", span = form.span}, false
        }
        variants, err_variants, ok_variants := parse_union_variants(form.items[2])
        if !ok_variants {
            return decl, err_variants, false
        }
        return AST_Decl{
            kind = .Union,
            span = form.span,
            doc_lines = top_form.doc_lines,
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
    case "proc":
        proc_decl, err_proc, ok_proc := parse_proc_decl(form)
        if !ok_proc {
            return decl, err_proc, false
        }
        return AST_Decl{
            kind = .Proc,
            span = form.span,
            doc_lines = top_form.doc_lines,
            proc_decl = proc_decl,
        }, {}, true
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
