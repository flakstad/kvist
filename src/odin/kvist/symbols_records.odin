// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:sort"
import "core:strings"
import "base:runtime"

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
        if param.has_default {
            strings.write_string(&builder, " = ")
            strings.write_string(&builder, symbols_form_text(param.default_value))
        }
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
