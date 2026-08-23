// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:sort"
import "core:strings"
import "base:runtime"

symbols_source_signature :: proc(name: string, decl: Source_Decl) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    fmt.sbprintf(&builder, "(%s [", name)
    for param, idx in decl.params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "%s: %s", param.name, param.ty)
    }
    fmt.sbprintf(&builder, "] -> %s :yield %s)", decl.state_ty, decl.item_ty)
    return strings.to_string(builder)
}

write_symbols_form :: proc(builder: ^strings.Builder, form: CST_Form) {
    #partial switch form.kind {
    case .List:
        strings.write_byte(builder, '(')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            write_symbols_form(builder, item)
        }
        strings.write_byte(builder, ')')
    case .Vector:
        strings.write_byte(builder, '[')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            write_symbols_form(builder, item)
        }
        strings.write_byte(builder, ']')
    case .Brace:
        strings.write_byte(builder, '{')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            write_symbols_form(builder, item)
        }
        strings.write_byte(builder, '}')
    case .Set:
        strings.write_string(builder, "#{")
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            write_symbols_form(builder, item)
        }
        strings.write_byte(builder, '}')
    case .Symbol, .Keyword, .String, .Regex, .Number, .Bool, .Nil:
        strings.write_string(builder, form.text)
    }
}

symbols_form_text :: proc(form: CST_Form) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    write_symbols_form(&builder, form)
    return strings.clone(strings.to_string(builder))
}

symbols_struct_signature :: proc(name: string, fields: []Struct_Field) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    strings.write_string(&builder, "(")
    strings.write_string(&builder, name)
    strings.write_string(&builder, " {")
    for field, idx in fields {
        if idx > 0 {
            strings.write_string(&builder, " ")
        }
        strings.write_string(&builder, field.source_name)
        strings.write_string(&builder, ":")
        strings.write_string(&builder, " ")
        strings.write_string(&builder, field.ty)
        if field.is_using {
            strings.write_string(&builder, " :using")
        }
        if field.has_default {
            default_text := symbols_form_text(field.default_value)
            strings.write_string(&builder, " :default ")
            strings.write_string(&builder, default_text)
            delete(default_text)
        }
    }
    strings.write_string(&builder, "})")
    return strings.to_string(builder)
}

symbols_doc_lines_from_string :: proc(text: string) -> (lines: [dynamic]string) {
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

symbols_append_doc_lines :: proc(base, extra: []string) -> (lines: [dynamic]string) {
    for line in base {
        append(&lines, line)
    }
    for line in extra {
        append(&lines, line)
    }
    return lines
}

symbols_write_fields :: proc(builder: ^strings.Builder, source, parent: string, fields: CST_Form) {
    if fields.kind != .Brace {
        return
    }
    i := 0
    for i < len(fields.items) {
        if i+1 >= len(fields.items) {
            return
        }
        key := fields.items[i]
        if key.kind == .Keyword && len(key.text) > 1 {
            name := fmt.tprintf("%s.%s", parent, key.text[1:])
            symbols_write_record(builder, "field", name, source, key.span, parent)
        } else if key.kind == .Symbol && len(key.text) > 1 && key.text[len(key.text)-1] == ':' {
            name := fmt.tprintf("%s.%s", parent, key.text[:len(key.text)-1])
            symbols_write_record(builder, "field", name, source, key.span, parent)
        }
        i += 2
        parsing_modifiers := true
        for parsing_modifiers && i < len(fields.items) && fields.items[i].kind == .Keyword {
            switch fields.items[i].text {
            case ":using":
                i += 1
            case ":default":
                i += 2
            case:
                parsing_modifiers = false
            }
        }
    }
}

symbols_defstruct_field_index :: proc(form: CST_Form) -> (int, bool) {
    if form.kind != .List || len(form.items) < 3 || form.items[0].kind != .Symbol {
        return -1, false
    }
    head := form.items[0].text
    if head != "defstruct" && head != "defstruct-" {
        return -1, false
    }
    if form.items[1].kind != .Symbol {
        return -1, false
    }
    field_index := 2
    if len(form.items) >= 4 && form.items[2].kind == .String {
        field_index = 3
    }
    if field_index >= len(form.items) || form.items[field_index].kind != .Brace {
        return -1, false
    }
    return field_index, true
}

symbols_struct_fields_for_type :: proc(forms: []CST_Top_Form, ty: string) -> (fields: [dynamic]Struct_Field, ok: bool) {
    normalized_ty := ty
    if strings.has_prefix(normalized_ty, "^") {
        normalized_ty = normalized_ty[1:]
    }
    for top in forms {
        form := top.form
        field_index, ok_fields_index := symbols_defstruct_field_index(form)
        if !ok_fields_index {
            continue
        }
        source_name := form.items[1].text
        mapped_name := map_name(source_name)
        if normalized_ty != source_name && normalized_ty != mapped_name {
            delete(mapped_name)
            continue
        }
        delete(mapped_name)
        parsed, err_fields, ok_fields := parse_defstruct_fields(form.items[field_index])
        if ok_fields {
            return parsed, true
        }
        _ = err_fields
    }
    return fields, false
}

symbols_local_type_lookup :: proc(bindings: []Local_Type_Binding, name: string) -> (string, bool) {
    for idx := len(bindings)-1; idx >= 0; idx -= 1 {
        if bindings[idx].name == name {
            return bindings[idx].ty, true
        }
    }
    return "", false
}

symbols_local_type_bind :: proc(bindings: ^[dynamic]Local_Type_Binding, name, ty: string) {
    if name == "" || ty == "" {
        return
    }
    append(bindings, Local_Type_Binding{name = name, ty = ty})
}

symbols_obvious_local_value_type :: proc(form: CST_Form, bindings: []Local_Type_Binding) -> (string, bool) {
    if form.kind == .Symbol {
        ty, ok := symbols_local_type_lookup(bindings, form.text)
        if ok {
            return ty, true
        }
        mapped_name := map_name(form.text)
        defer delete(mapped_name)
        return symbols_local_type_lookup(bindings, mapped_name)
    }
    if form.kind == .List && len(form.items) == 2 && form.items[0].kind == .Symbol {
        arg := form.items[1]
        if arg.kind == .Brace || arg.kind == .Vector {
            return map_name(form.items[0].text), true
        }
    }
    return "", false
}

symbols_write_editor_record :: proc(
    builder: ^strings.Builder,
    seen: ^map[string]bool,
    kind, name: string,
    source: string,
    span: Span,
    detail: string,
    file_path: string,
) {
    key := fmt.tprintf("%s\t%s", kind, name)
    if seen[key] {
        return
    }
    seen[key] = true
    line, column := 1, 1
    if source != "" {
        line, column, _, _ = source_position(source, span.start)
    }
    fmt.sbprintf(builder, "%s\t%s\t%d\t%d\t%s\t\t\t%s\n", kind, name, line, column, detail, file_path)
}

symbols_write_local_typed_fields :: proc(
    builder: ^strings.Builder,
    seen: ^map[string]bool,
    file_path, source: string,
    forms: []CST_Top_Form,
    local_name: string,
    span: Span,
    ty: string,
) {
    symbols_write_editor_record(builder, seen, "local", local_name, source, span, ty, file_path)
    fields, ok_fields := symbols_struct_fields_for_type(forms, ty)
    if !ok_fields {
        return
    }
    defer delete(fields)
    for field in fields {
        field_name := field.source_name
        if field_name == "" {
            field_name = field.name
        }
        name := fmt.tprintf("%s.%s", local_name, field_name)
        symbols_write_editor_record(builder, seen, "field", name, source, span, ty, file_path)
        delete(name)
    }
}

symbols_local_var_binding :: proc(form: CST_Form, bindings: []Local_Type_Binding) -> (name, ty: string, span: Span, ok: bool) {
    if form.kind != .List || len(form.items) < 3 || !is_symbol(form.items[0], "defvar") {
        return "", "", {}, false
    }
    target := form.items[1]
    if target.kind != .Symbol {
        return "", "", {}, false
    }
    raw_name := target.text
    value_index := 2
    if len(raw_name) > 0 && raw_name[len(raw_name)-1] == ':' {
        if len(raw_name) == 1 {
            return "", "", {}, false
        }
        parsed_ty, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], 2)
        if !ok_type || next_i >= len(form.items) {
            _ = err_type
            return "", "", {}, false
        }
        value_index = next_i
        raw_name = raw_name[:len(raw_name)-1]
        return raw_name, parsed_ty, target.span, true
    }
    if value_index >= len(form.items) {
        return "", "", {}, false
    }
    inferred_ty, ok_ty := symbols_obvious_local_value_type(form.items[value_index], bindings)
    if !ok_ty {
        return "", "", {}, false
    }
    return raw_name, inferred_ty, target.span, true
}

symbols_collect_local_field_records_for_form :: proc(
    builder: ^strings.Builder,
    seen: ^map[string]bool,
    file_path, source: string,
    top_forms: []CST_Top_Form,
    form: CST_Form,
    bindings: ^[dynamic]Local_Type_Binding,
) {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        for item in form.items {
            symbols_collect_local_field_records_for_form(builder, seen, file_path, source, top_forms, item, bindings)
        }
        return
    }

    head := form.items[0].text
    if head == "defn" || head == "defn-" {
        proc_form := form
        if len(form.items) > 3 && form.items[2].kind == .String {
            items: [dynamic]CST_Form
            defer delete(items)
            append(&items, form.items[0], form.items[1])
            for item in form.items[3:] {
                append(&items, item)
            }
            proc_form = CST_Form{kind = .List, items = items, span = form.span}
        }
        decl, err_proc, ok_proc := parse_proc_decl(proc_form)
        if ok_proc {
            local_bindings: [dynamic]Local_Type_Binding
            defer delete(local_bindings)
            for param in decl.params {
                if param.name != "" && param.ty != "" {
                    symbols_local_type_bind(&local_bindings, param.name, param.ty)
                    symbols_write_local_typed_fields(builder, seen, file_path, source, top_forms, param.name, form.span, param.ty)
                }
            }
            symbols_collect_local_field_records_for_forms(builder, seen, file_path, source, top_forms, decl.body[:], &local_bindings)
        } else {
            _ = err_proc
        }
        return
    }

    if head == "defvar" {
        name, ty, span, ok_var := symbols_local_var_binding(form, bindings[:])
        if ok_var {
            symbols_local_type_bind(bindings, name, ty)
            symbols_write_local_typed_fields(builder, seen, file_path, source, top_forms, name, span, ty)
        }
    }

    for item in form.items[1:] {
        symbols_collect_local_field_records_for_form(builder, seen, file_path, source, top_forms, item, bindings)
    }
}

symbols_collect_local_field_records_for_forms :: proc(
    builder: ^strings.Builder,
    seen: ^map[string]bool,
    file_path, source: string,
    top_forms: []CST_Top_Form,
    forms: []CST_Form,
    bindings: ^[dynamic]Local_Type_Binding,
) {
    for form in forms {
        symbols_collect_local_field_records_for_form(builder, seen, file_path, source, top_forms, form, bindings)
    }
}

symbols_append_local_field_records :: proc(builder: ^strings.Builder, seen: ^map[string]bool, file_path, source: string, forms: []CST_Top_Form) {
    bindings: [dynamic]Local_Type_Binding
    defer delete(bindings)
    for top in forms {
        symbols_collect_local_field_records_for_form(builder, seen, file_path, source, forms, top.form, &bindings)
    }
}

symbols_write_enum_variants :: proc(builder: ^strings.Builder, source, parent: string, variants: CST_Form) {
    #partial switch variants.kind {
    case .Vector:
        for item in variants.items {
            if item.kind == .Symbol {
                name := fmt.tprintf("%s.%s", parent, item.text)
                symbols_write_record(builder, "variant", name, source, item.span, parent)
            }
        }
    case .Brace:
        i := 0
        for i < len(variants.items) {
            if i+1 >= len(variants.items) {
                return
            }
            key := variants.items[i]
            if key.kind == .Keyword && len(key.text) > 1 {
                name := fmt.tprintf("%s.%s", parent, key.text[1:])
                symbols_write_record(builder, "variant", name, source, key.span, parent)
            } else if key.kind == .Symbol && len(key.text) > 1 && key.text[len(key.text)-1] == ':' {
                name := fmt.tprintf("%s.%s", parent, key.text[:len(key.text)-1])
                symbols_write_record(builder, "variant", name, source, key.span, parent)
            }
            i += 2
        }
    case:
    }
}

symbols_write_union_variants :: proc(builder: ^strings.Builder, source, parent: string, variants: CST_Form) {
    if variants.kind != .Brace {
        return
    }
    i := 0
    for i < len(variants.items) {
        if i+1 >= len(variants.items) {
            return
        }
        key := variants.items[i]
        if key.kind == .Keyword && len(key.text) > 1 {
            name := fmt.tprintf("%s.%s", parent, key.text[1:])
            symbols_write_record(builder, "variant", name, source, key.span, parent)
        } else if key.kind == .Symbol && len(key.text) > 1 && key.text[len(key.text)-1] == ':' {
            name := fmt.tprintf("%s.%s", parent, key.text[:len(key.text)-1])
            symbols_write_record(builder, "variant", name, source, key.span, parent)
        }
        i += 2
    }
}

symbols_source :: proc(source: string) -> (output: string, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

	forms, err_forms, ok_forms := read_kvist_top_forms(source)
    if !ok_forms {
        return "", clone_compile_error(err_forms, result_allocator), false
    }
    defer delete_borrowed_cst_top_form_slice(&forms)
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\n")

    for top in forms {
        form := top.form
        if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
            continue
        }
        head := form.items[0].text
        switch head {
        case "@exports":
            if len(form.items) == 2 && form.items[1].kind == .Vector {
                for item in form.items[1].items {
                    if item.kind == .Symbol {
                        symbols_write_record_doc(&builder, "macro", item.text, source, item.span, "export marker", "", top.doc_lines[:])
                    }
                }
            }
        case "import":
            if len(form.items) == 2 && form.items[1].kind == .String {
                path := import_path_text(form.items[1])
                alias := import_default_alias(path)
                if alias != "" {
                    symbols_write_record_doc(&builder, "import", alias, source, form.items[1].span, path, "", top.doc_lines[:])
                }
            } else if import_form_has_as(form) {
                as_index, _ := source_import_as_index(form)
                alias := form.items[as_index].text
                path := import_path_text(form.items[1])
                symbols_write_record_doc(&builder, "import", alias, source, form.items[as_index].span, path, "", top.doc_lines[:])
            } else if len(form.items) == 3 && form.items[1].kind == .Symbol && form.items[2].kind == .String {
                alias := form.items[1].text
                path := import_path_text(form.items[2])
                symbols_write_record_doc(&builder, "import", alias, source, form.items[1].span, path, "", top.doc_lines[:])
            }
        case "def", "def-":
            if len(form.items) >= 2 && form.items[1].kind == .Symbol {
                name := form.items[1].text
                if len(name) > 0 && name[len(name)-1] == ':' {
                    name = name[:len(name)-1]
                }
                doc_lines := top.doc_lines
                if len(form.items) > 3 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                }
                detail := ""
                if head == "def-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "const", name, source, form.items[1].span, detail, "", doc_lines[:])
            }
        case "defvar", "defvar-":
            if len(form.items) >= 2 && form.items[1].kind == .Symbol {
                name := form.items[1].text
                if len(name) > 0 && name[len(name)-1] == ':' {
                    name = name[:len(name)-1]
                }
                doc_lines := top.doc_lines
                if len(form.items) > 3 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                }
                detail := ""
                if head == "defvar-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "var", name, source, form.items[1].span, detail, "", doc_lines[:])
            }
        case "defstruct", "defstruct-":
            if (len(form.items) == 3 || len(form.items) == 4) && form.items[1].kind == .Symbol {
                name := form.items[1].text
                doc_lines := top.doc_lines
                field_index := 2
                if len(form.items) == 4 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                    field_index = 3
                }
                signature := ""
                fields_sig, err_fields, ok_fields_sig := parse_defstruct_fields(form.items[field_index])
                if ok_fields_sig {
                    signature = symbols_struct_signature(name, fields_sig[:])
                } else {
                    _ = err_fields
                }
                detail := ""
                if head == "defstruct-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "struct", name, source, form.items[1].span, detail, signature, doc_lines[:])
                symbols_write_fields(&builder, source, name, form.items[field_index])
            }
        case "defenum", "defenum-":
            if (len(form.items) == 3 || len(form.items) == 4) && form.items[1].kind == .Symbol {
                name := form.items[1].text
                doc_lines := top.doc_lines
                variant_index := 2
                if len(form.items) == 4 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                    variant_index = 3
                }
                detail := ""
                if head == "defenum-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "enum", name, source, form.items[1].span, detail, "", doc_lines[:])
                symbols_write_enum_variants(&builder, source, name, form.items[variant_index])
            }
        case "defunion", "defunion-":
            if (len(form.items) == 3 || len(form.items) == 4) && form.items[1].kind == .Symbol {
                name := form.items[1].text
                doc_lines := top.doc_lines
                variant_index := 2
                if len(form.items) == 4 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                    variant_index = 3
                }
                detail := ""
                if head == "defunion-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "union", name, source, form.items[1].span, detail, "", doc_lines[:])
                symbols_write_union_variants(&builder, source, name, form.items[variant_index])
            }
        case "defn", "defn-":
            if len(form.items) >= 2 && form.items[1].kind == .Symbol {
                doc_lines := top.doc_lines
                proc_form := form
                if len(form.items) > 3 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                    items: [dynamic]CST_Form
                    append(&items, form.items[0], form.items[1])
                    for item in form.items[3:] {
                        append(&items, item)
                    }
                    proc_form = CST_Form{kind = .List, items = items, span = form.span}
                }
                signature := ""
                lifetime_detail := ""
                proc_decl, err_proc, ok_proc := parse_proc_decl(proc_form)
                if ok_proc {
                    signature = symbols_proc_signature(form.items[1].text, proc_decl)
                    lifetime_detail = symbols_proc_lifetime_detail(&proc_decl)
                } else {
                    _ = err_proc
                }
                detail := ""
                if head == "defn-" {
                    detail = "private"
                }
                if lifetime_detail != "" {
                    if detail != "" {
                        detail = fmt.tprintf("%s;%s", detail, lifetime_detail)
                    } else {
                        detail = lifetime_detail
                    }
                }
                symbols_write_record_doc(&builder, "proc", form.items[1].text, source, form.items[1].span, detail, signature, doc_lines[:])
            }
        case "defmacro", "defmacro-":
            if len(form.items) >= 3 && form.items[1].kind == .Symbol {
                doc_lines := top.doc_lines
                if len(form.items) > 4 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                }
                signature := fmt.tprintf("(%s ...)", form.items[1].text)
                if len(form.items) >= 3 && form.items[2].kind == .Vector {
                    signature = fmt.tprintf("(%s %s)", form.items[1].text, macro_form_text(form.items[2]))
                } else if len(form.items) >= 4 && form.items[3].kind == .Vector {
                    signature = fmt.tprintf("(%s %s)", form.items[1].text, macro_form_text(form.items[3]))
                }
                detail := ""
                if head == "defmacro-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "macro", form.items[1].text, source, form.items[1].span, detail, signature, doc_lines[:])
            }
        case "defiter", "defiter-":
            if len(form.items) >= 2 && form.items[1].kind == .Symbol {
                signature := ""
                source_decl, err_source, ok_source := parse_source_decl(form)
                if ok_source {
                    signature = symbols_source_signature(form.items[1].text, source_decl)
                } else {
                    _ = err_source
                }
                detail := ""
                if head == "defiter-" {
                    detail = "private"
                }
                symbols_write_record_doc(&builder, "iterator", form.items[1].text, source, form.items[1].span, detail, signature, top.doc_lines[:])
            }
        case:
        }
    }

    context.allocator = result_allocator
    return strings.clone(strings.to_string(builder), result_allocator), {}, true
}
