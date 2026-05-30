package kvist

import "core:fmt"
import "core:strings"
import "base:runtime"

import_path_text :: proc(form: CST_Form) -> string {
    if form.kind != .String {
        return ""
    }
    return unquote_string(form.text)
}

package_symbols_write_entry :: proc(builder: ^strings.Builder, alias, import_path, member, signature, doc: string) {
    symbols_write_record_doc(builder, "kvist package", fmt.tprintf("%s/%s", alias, member), "", Span{start = 0, end = 0, source = .File}, import_path, signature, symbols_doc_lines_from_string(doc)[:])
    symbols_write_record_doc(builder, "kvist package", fmt.tprintf("%s.%s", alias, member), "", Span{start = 0, end = 0, source = .File}, import_path, signature, symbols_doc_lines_from_string(doc)[:])
}

package_symbols_append :: proc(builder: ^strings.Builder, import_path, alias: string) -> bool {
    switch import_path {
    case "kvist:arr":
        package_symbols_write_entry(builder, alias, import_path, "count", "(arr/count xs)", "Count elements in an array, fixed array, or slice.")
        package_symbols_write_entry(builder, alias, import_path, "empty", "(arr/empty T [capacity])", "Construct an empty dynamic array, optionally with capacity.")
        package_symbols_write_entry(builder, alias, import_path, "dynamic", "(arr/dynamic T [v1 v2 ...])", "Construct a dynamic array from a vector literal.")
        package_symbols_write_entry(builder, alias, import_path, "fixed", "(arr/fixed T [v1 v2 ...])", "Construct a fixed array from a vector literal.")
        package_symbols_write_entry(builder, alias, import_path, "get", "(arr/get xs index)", "Index into an array-family value.")
        package_symbols_write_entry(builder, alias, import_path, "slice", "(arr/slice xs start [end])", "Take a slice view over an array-family value.")
        package_symbols_write_entry(builder, alias, import_path, "push!", "(arr/push! xs value...)", "Append one or more values to a dynamic array.")
        package_symbols_write_entry(builder, alias, import_path, "map", "(arr/map f xs)", "Map over an array-family input and return an owned dynamic array.")
        package_symbols_write_entry(builder, alias, import_path, "filter", "(arr/filter pred xs)", "Filter an array-family input and return an owned dynamic array.")
        package_symbols_write_entry(builder, alias, import_path, "map!", "(arr/map! f xs)", "Map in place over a dynamic array.")
        package_symbols_write_entry(builder, alias, import_path, "filter!", "(arr/filter! pred xs)", "Filter in place over a dynamic array.")
        package_symbols_write_entry(builder, alias, import_path, "take", "(arr/take n xs)", "Take a leading slice or owned result from an array-family input.")
        package_symbols_write_entry(builder, alias, import_path, "drop", "(arr/drop n xs)", "Drop a leading prefix from an array-family input.")
        package_symbols_write_entry(builder, alias, import_path, "sort", "(arr/sort xs)", "Return a sorted owned array.")
        package_symbols_write_entry(builder, alias, import_path, "sort!", "(arr/sort! xs)", "Sort a dynamic array in place.")
        return true
    case "kvist:str":
        package_symbols_write_entry(builder, alias, import_path, "count", "(str/count s)", "Count characters or bytes in a string.")
        package_symbols_write_entry(builder, alias, import_path, "get", "(str/get s index)", "Index into a string.")
        package_symbols_write_entry(builder, alias, import_path, "slice", "(str/slice s start [end])", "Take a string slice.")
        package_symbols_write_entry(builder, alias, import_path, "contains?", "(str/contains? s needle)", "Return true when the string contains the needle.")
        return true
    case "kvist:map":
        package_symbols_write_entry(builder, alias, import_path, "empty", "(map/empty K V [capacity])", "Construct an empty map, optionally with capacity.")
        package_symbols_write_entry(builder, alias, import_path, "of", "(map/of K V {k1 v1 ...})", "Construct a map from a brace literal.")
        package_symbols_write_entry(builder, alias, import_path, "get", "(map/get m key [default])", "Look up a key in a map, optionally with a default.")
        package_symbols_write_entry(builder, alias, import_path, "contains?", "(map/contains? m key)", "Return true when the map contains the key.")
        return true
    case "kvist:set":
        package_symbols_write_entry(builder, alias, import_path, "empty", "(set/empty T [capacity])", "Construct an empty set, optionally with capacity.")
        package_symbols_write_entry(builder, alias, import_path, "of", "(set/of T [v1 v2 ...])", "Construct a set from a vector literal.")
        package_symbols_write_entry(builder, alias, import_path, "contains?", "(set/contains? s value)", "Return true when the set contains the value.")
        package_symbols_write_entry(builder, alias, import_path, "add!", "(set/add! s value)", "Insert a value into a set.")
        return true
    case "kvist:struct":
        package_symbols_write_entry(builder, alias, import_path, "fields", "(struct/fields target)", "Return source-level field names for a struct type or value.")
        package_symbols_write_entry(builder, alias, import_path, "types", "(struct/types target)", "Return source-level field types for a struct type or value.")
        return true
    case:
        return false
    }
}

package_symbols_source :: proc(import_path, alias: string) -> (output: string, ok: bool) {
    resolved_alias := alias
    if resolved_alias == "" {
        resolved_alias = import_default_alias(import_path)
    }
    if resolved_alias == "" {
        return "", false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\n")
    if !package_symbols_append(&builder, import_path, resolved_alias) {
        return "", false
    }
    return strings.to_string(builder), true
}

import_default_alias :: proc(path: string) -> string {
    end := len(path)
    for end > 0 && path[end-1] == '/' {
        end -= 1
    }
    start := end
    for start > 0 {
        ch := path[start-1]
        if ch == '/' || ch == ':' {
            break
        }
        start -= 1
    }
    if start >= end {
        return ""
    }
    return map_name(path[start:end])
}

symbols_write_record :: proc(builder: ^strings.Builder, kind, name: string, source: string, span: Span, detail: string = "") {
    line, column := 1, 1
    if source != "" {
        line, column, _, _ = source_position(source, span.start)
    }
    fmt.sbprintf(builder, "%s\t%s\t%d\t%d\t%s\t\t\n", kind, name, line, column, detail)
}

symbols_clean_doc_line :: proc(line: string) -> string {
    text := line
    if len(text) >= 2 && text[0] == '/' && text[1] == '/' {
        text = text[2:]
    }
    if len(text) > 0 && text[0] == ' ' {
        text = text[1:]
    }
    return text
}

symbols_write_escaped_doc :: proc(builder: ^strings.Builder, doc_lines: []string) {
    for line, i in doc_lines {
        if i > 0 {
            strings.write_string(builder, "\\n")
        }
        text := symbols_clean_doc_line(line)
        for ch in text {
            switch ch {
            case '\\':
                strings.write_string(builder, "\\\\")
            case '\t':
                strings.write_string(builder, "\\t")
            case '\r':
                strings.write_string(builder, "\\r")
            case '\n':
                strings.write_string(builder, "\\n")
            case:
                strings.write_rune(builder, ch)
            }
        }
    }
}

symbols_write_record_doc :: proc(builder: ^strings.Builder, kind, name: string, source: string, span: Span, detail: string, signature: string, doc_lines: []string) {
    line, column := 1, 1
    if source != "" {
        line, column, _, _ = source_position(source, span.start)
    }
    fmt.sbprintf(builder, "%s\t%s\t%d\t%d\t%s\t%s\t", kind, name, line, column, detail, signature)
    symbols_write_escaped_doc(builder, doc_lines)
    strings.write_byte(builder, '\n')
}

symbols_proc_signature :: proc(name: string, decl: Proc_Decl) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    fmt.sbprintf(&builder, "(%s [", name)
    for param, idx in decl.params {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "%s: %s", param.name, param.ty)
    }
    strings.write_string(&builder, "]")

    #partial switch decl.returns.kind {
    case .Single:
        fmt.sbprintf(&builder, " -> %s", decl.returns.single_ty)
    case .Named:
        strings.write_string(&builder, " -> [")
        for field, idx in decl.returns.named {
            if idx > 0 {
                strings.write_string(&builder, ", ")
            }
            fmt.sbprintf(&builder, "%s: %s", field.name, field.ty)
        }
        strings.write_string(&builder, "]")
    case:
    }

    strings.write_string(&builder, ")")
    return strings.to_string(builder)
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
        strings.write_string(&builder, ":")
        strings.write_string(&builder, field.source_name)
        strings.write_string(&builder, " ")
        strings.write_string(&builder, field.ty)
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
        }
        i += 2
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

    forms, err_forms, ok_forms := read_top_forms(source)
    if !ok_forms {
        return "", clone_compile_error(err_forms, result_allocator), false
    }
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
        case "import":
            if len(form.items) == 2 && form.items[1].kind == .String {
                path := import_path_text(form.items[1])
                alias := import_default_alias(path)
                if alias != "" {
                    symbols_write_record_doc(&builder, "import", alias, source, form.items[1].span, path, "", top.doc_lines[:])
                }
            } else if len(form.items) == 3 && form.items[1].kind == .Symbol && form.items[2].kind == .String {
                alias := form.items[1].text
                path := import_path_text(form.items[2])
                symbols_write_record_doc(&builder, "import", alias, source, form.items[1].span, path, "", top.doc_lines[:])
            }
        case "const", "defconst":
            if len(form.items) >= 2 && form.items[1].kind == .Symbol {
                doc_lines := top.doc_lines
                if len(form.items) > 3 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                }
                symbols_write_record_doc(&builder, "const", form.items[1].text, source, form.items[1].span, "", "", doc_lines[:])
            }
        case "defvar":
            if len(form.items) >= 2 && form.items[1].kind == .Symbol {
                doc_lines := top.doc_lines
                if len(form.items) > 3 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                }
                symbols_write_record_doc(&builder, "var", form.items[1].text, source, form.items[1].span, "", "", doc_lines[:])
            }
        case "struct":
            if len(form.items) == 3 && form.items[1].kind == .Symbol {
                name := form.items[1].text
                signature := ""
                fields, err_fields, ok_fields := parse_struct_fields(form.items[2])
                if ok_fields {
                    signature = symbols_struct_signature(name, fields[:])
                } else {
                    _ = err_fields
                }
                symbols_write_record_doc(&builder, "struct", name, source, form.items[1].span, "", signature, top.doc_lines[:])
                symbols_write_fields(&builder, source, name, form.items[2])
            }
        case "defstruct":
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
                symbols_write_record_doc(&builder, "struct", name, source, form.items[1].span, "", signature, doc_lines[:])
                symbols_write_fields(&builder, source, name, form.items[field_index])
            }
        case "enum":
            if len(form.items) == 3 && form.items[1].kind == .Symbol {
                name := form.items[1].text
                symbols_write_record_doc(&builder, "enum", name, source, form.items[1].span, "", "", top.doc_lines[:])
                symbols_write_enum_variants(&builder, source, name, form.items[2])
            }
        case "union":
            if len(form.items) == 3 && form.items[1].kind == .Symbol {
                name := form.items[1].text
                symbols_write_record_doc(&builder, "union", name, source, form.items[1].span, "", "", top.doc_lines[:])
                symbols_write_union_variants(&builder, source, name, form.items[2])
            }
        case "proc", "defn":
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
                proc_decl, err_proc, ok_proc := parse_proc_decl(proc_form)
                if ok_proc {
                    signature = symbols_proc_signature(form.items[1].text, proc_decl)
                } else {
                    _ = err_proc
                }
                symbols_write_record_doc(&builder, "proc", form.items[1].text, source, form.items[1].span, "", signature, doc_lines[:])
            }
        case "defmacro":
            if len(form.items) >= 3 && form.items[1].kind == .Symbol {
                doc_lines := top.doc_lines
                if len(form.items) > 4 && form.items[2].kind == .String {
                    doc_lines = symbols_append_doc_lines(doc_lines[:], symbols_doc_lines_from_string(unquote_string(form.items[2].text))[:])
                }
                signature := fmt.tprintf("(%s ...)", form.items[1].text)
                if len(form.items) >= 3 && form.items[2].kind == .Vector {
                    signature = fmt.tprintf("(%s %s)", form.items[1].text, form.items[2].text)
                } else if len(form.items) >= 4 && form.items[3].kind == .Vector {
                    signature = fmt.tprintf("(%s %s)", form.items[1].text, form.items[3].text)
                }
                symbols_write_record_doc(&builder, "macro", form.items[1].text, source, form.items[1].span, "", signature, doc_lines[:])
            }
        case:
        }
    }

    context.allocator = result_allocator
    return strings.clone(strings.to_string(builder), result_allocator), {}, true
}
