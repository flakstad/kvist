// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"
import kvist "../../odin/kvist"

symbols_command :: proc(input: string) {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    output, err, ok := kvist.symbols_source(data)
    if !ok {
        formatted := kvist.format_compile_error(input, data, err)
        fmt.eprint(formatted)
        delete(formatted)
        exit_with_timing(1)
    }
    defer delete(output)
    fmt.print(output)
}

lifetimes_command :: proc(input: string) {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    output, err, ok := kvist.lifetimes_path(input)
    if !ok {
        formatted := kvist.format_compile_error(input, data, err)
        fmt.eprint(formatted)
        delete(formatted)
        exit_with_timing(1)
    }
    defer delete(output)
    fmt.print(output)
}

editor_symbols_command :: proc(input: string, identifier := "") {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    output, err, ok := kvist.editor_symbols_source(input, data)
    if !ok {
        fmt.eprintln(err.message)
        exit_with_timing(1)
    }
    defer delete(output)
    filtered := filter_symbol_output(output, identifier)
    defer delete(filtered)
    fmt.print(filtered)
}

builtin_symbols_command :: proc() {
    output := kvist.builtin_symbols_source()
    defer delete(output)
    fmt.print(output)
}

imported_symbols_command :: proc(input: string) {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    output, err, ok := kvist.imported_symbols_source(input, data)
    if !ok {
        formatted := kvist.format_compile_error(input, data, err)
        fmt.eprint(formatted)
        delete(formatted)
        exit_with_timing(1)
    }
    defer delete(output)
    fmt.print(output)
}

Cli_Symbol_Row :: struct {
    kind:      string,
    name:      string,
    line:      int,
    column:    int,
    detail:    string,
    signature: string,
    doc:       string,
    file:      string,
}

normalize_qualified_identifier :: proc(identifier: string) -> string {
    slash := strings.index(identifier, "/")
    dot := strings.index(identifier, ".")
    if dot >= 0 && (slash < 0 || dot < slash) {
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        strings.write_string(&builder, identifier[:dot])
        strings.write_byte(&builder, '/')
        strings.write_string(&builder, identifier[dot+1:])
        return strings.clone(strings.to_string(builder))
    }
    return strings.clone(identifier)
}

symbol_matches_identifier :: proc(name, identifier: string) -> bool {
    normalized_name := normalize_qualified_identifier(name)
    defer delete(normalized_name)
    normalized_identifier := normalize_qualified_identifier(identifier)
    defer delete(normalized_identifier)

    if normalized_name == normalized_identifier {
        return true
    }
    if len(normalized_name) > len(identifier)+1 &&
       normalized_name[len(normalized_name)-len(identifier):] == identifier &&
       normalized_name[len(normalized_name)-len(identifier)-1] == '.' {
        return true
    }
    if len(normalized_name) > len(identifier)+1 &&
       normalized_name[len(normalized_name)-len(identifier):] == identifier &&
       normalized_name[len(normalized_name)-len(identifier)-1] == '/' {
        return true
    }
    return false
}

symbol_matches_prefix :: proc(name, prefix: string) -> bool {
    if prefix == "" {
        return true
    }

    normalized_name := normalize_qualified_identifier(name)
    defer delete(normalized_name)
    normalized_prefix := normalize_qualified_identifier(prefix)
    defer delete(normalized_prefix)

    if strings.has_prefix(name, prefix) || strings.has_prefix(normalized_name, normalized_prefix) {
        return true
    }

    if !strings.contains_any(prefix, "./") {
        bare_name := name
        if slash := strings.last_index_any(name, "./"); slash >= 0 && slash+1 < len(name) {
            bare_name = name[slash+1:]
        }
        if strings.has_prefix(bare_name, prefix) {
            return true
        }
    }
    return false
}

filter_symbol_output :: proc(output, identifier: string) -> string {
    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    seen := make(map[string]bool)
    defer delete(seen)

    if len(lines) > 0 {
        strings.write_string(&builder, lines[0])
        strings.write_byte(&builder, '\n')
    }
    for line, idx in lines {
        if idx == 0 || line == "" {
            continue
        }
        name := kvist.symbols_record_name(line)
        key := line
        if (identifier == "" || symbol_matches_identifier(name, identifier)) && !seen[key] {
            seen[key] = true
            strings.write_string(&builder, line)
            strings.write_byte(&builder, '\n')
        }
    }
    return strings.clone(strings.to_string(builder))
}

filter_symbol_output_by_prefix :: proc(output, prefix: string) -> string {
    if prefix == "" {
        return strings.clone(output)
    }

    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    seen := make(map[string]bool)
    defer delete(seen)

    if len(lines) > 0 {
        strings.write_string(&builder, lines[0])
        strings.write_byte(&builder, '\n')
    }
    for line, idx in lines {
        if idx == 0 || line == "" {
            continue
        }
        name := kvist.symbols_record_name(line)
        key := line
        if symbol_matches_prefix(name, prefix) && !seen[key] {
            seen[key] = true
            strings.write_string(&builder, line)
            strings.write_byte(&builder, '\n')
        }
    }
    return strings.clone(strings.to_string(builder))
}

parse_cli_symbol_row :: proc(line, fallback_file: string) -> (Cli_Symbol_Row, bool) {
    fields := strings.split(line, "\t", context.allocator)
    defer delete(fields)
    if len(fields) < 4 {
        return {}, false
    }
    line_no, ok_line := strconv.parse_int(fields[2])
    if !ok_line {
        return {}, false
    }
    column_no, ok_column := strconv.parse_int(fields[3])
    if !ok_column {
        return {}, false
    }

    row := Cli_Symbol_Row{
        kind = strings.clone(fields[0]),
        name = strings.clone(fields[1]),
        line = line_no,
        column = column_no,
        detail = strings.clone("") if len(fields) < 5 else strings.clone(fields[4]),
        signature = strings.clone("") if len(fields) < 6 else strings.clone(fields[5]),
        doc = strings.clone("") if len(fields) < 7 else kvist.symbols_unescape_doc_text(fields[6]),
        file = strings.clone(fallback_file) if len(fields) < 8 || fields[7] == "" else strings.clone(fields[7]),
    }
    return row, true
}

delete_cli_symbol_row :: proc(row: Cli_Symbol_Row) {
    delete(row.kind)
    delete(row.name)
    delete(row.detail)
    delete(row.signature)
    delete(row.doc)
    delete(row.file)
}

lookup_symbol_rows_or_exit :: proc(input, identifier: string) -> [dynamic]Cli_Symbol_Row {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    output, err, ok := kvist.editor_symbols_source(input, data)
    if !ok {
        fmt.eprintln(err.message)
        exit_with_timing(1)
    }
    defer delete(output)
    filtered := filter_symbol_output(output, identifier)
    defer delete(filtered)

    lines := strings.split_lines(filtered, context.allocator)
    rows: [dynamic]Cli_Symbol_Row
    for line, idx in lines {
        if idx == 0 || line == "" {
            continue
        }
        row, ok_row := parse_cli_symbol_row(line, input)
        if ok_row {
            append(&rows, row)
        }
    }
    return rows
}

normalized_symbol_name :: proc(name: string) -> string {
    slash := strings.index(name, "/")
    dot := strings.index(name, ".")
    if dot >= 0 && (slash < 0 || dot < slash) {
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        strings.write_string(&builder, name[:dot])
        strings.write_byte(&builder, '/')
        strings.write_string(&builder, name[dot+1:])
        return strings.clone(strings.to_string(builder))
    }
    return strings.clone(name)
}

normalize_test_name_component :: proc(name: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for ch in name {
        switch ch {
        case '-':
            strings.write_byte(&builder, '_')
        case '?':
            strings.write_string(&builder, "_p")
        case '!':
            strings.write_string(&builder, "_bang")
        case:
            strings.write_rune(&builder, ch)
        }
    }
    return strings.clone(strings.to_string(builder))
}

normalize_test_names_arg :: proc(text: string) -> string {
    if text == "" {
        return ""
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    parts := strings.split(text, ",", context.allocator)
    defer delete(parts)
    for part, idx in parts {
        trimmed := strings.trim_space(part)
        dot := strings.last_index(trimmed, ".")
        if idx > 0 {
            strings.write_byte(&builder, ',')
        }
        if dot >= 0 {
            strings.write_string(&builder, trimmed[:dot+1])
            normalized := normalize_test_name_component(trimmed[dot+1:])
            strings.write_string(&builder, normalized)
            delete(normalized)
        } else {
            normalized := normalize_test_name_component(trimmed)
            strings.write_string(&builder, normalized)
            delete(normalized)
        }
    }
    return strings.clone(strings.to_string(builder))
}

symbol_match_rank :: proc(row: Cli_Symbol_Row, identifier: string) -> int {
    if row.name == identifier {
        return 0
    }
    normalized_identifier := normalized_symbol_name(identifier)
    defer delete(normalized_identifier)
    normalized_name := normalized_symbol_name(row.name)
    defer delete(normalized_name)
    if normalized_name == normalized_identifier {
        return 1
    }
    return 2
}

doc_command :: proc(input, identifier: string) {
    rows := lookup_symbol_rows_or_exit(input, identifier)
    defer {
        for row in rows {
            delete_cli_symbol_row(row)
        }
        delete(rows)
    }
    if len(rows) == 0 {
        fmt.eprintln("no docs found for: ", identifier)
        exit_with_timing(1)
    }

    best_rank := 99
    for row in rows {
        rank := symbol_match_rank(row, identifier)
        if rank < best_rank {
            best_rank = rank
        }
    }

    seen := make(map[string]bool)
    defer delete(seen)
    printed := 0
    for row in rows {
        if symbol_match_rank(row, identifier) != best_rank {
            continue
        }
        normalized := normalized_symbol_name(row.name)
        key := fmt.tprintf("%s:%d:%d:%s", row.file, row.line, row.column, normalized)
        delete(normalized)
        if seen[key] {
            delete(key)
            continue
        }
        seen[key] = true
        if printed > 0 {
            fmt.println("")
        }
        fmt.printf("%s %s\n", row.kind, row.name)
        if row.signature != "" {
            fmt.println(row.signature)
        }
        if row.detail != "" {
            fmt.println(row.detail)
        }
        if row.file != "" {
            fmt.printf("%s:%d\n", row.file, row.line)
        }
        fmt.println("")
        fmt.println(row.doc)
        printed += 1
        delete(key)
    }
}

xref_command :: proc(input, identifier: string) {
    rows := lookup_symbol_rows_or_exit(input, identifier)
    defer {
        for row in rows {
            delete_cli_symbol_row(row)
        }
        delete(rows)
    }
    if len(rows) == 0 {
        fmt.eprintln("no definitions found for: ", identifier)
        exit_with_timing(1)
    }

    best_rank := 99
    for row in rows {
        rank := symbol_match_rank(row, identifier)
        if rank < best_rank {
            best_rank = rank
        }
    }

    seen := make(map[string]bool)
    defer delete(seen)
    printed := 0
    for row in rows {
        if symbol_match_rank(row, identifier) != best_rank {
            continue
        }
        switch row.kind {
        case "kvist form", "kvist helper", "kvist core", "kvist macro", "kvist package":
            continue
        case:
        }
        normalized := normalized_symbol_name(row.name)
        key := fmt.tprintf("%s:%d:%d:%s", row.file, row.line, row.column, normalized)
        delete(normalized)
        if seen[key] {
            delete(key)
            continue
        }
        seen[key] = true
        fmt.printf("%s:%d:%d\t%s\t%s\n", row.file, row.line, row.column, row.kind, row.name)
        printed += 1
        delete(key)
    }
    if printed == 0 {
        fmt.eprintln("no definitions found for: ", identifier)
        exit_with_timing(1)
    }
}

complete_command :: proc(input: string, prefix := "") {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    output, err, ok := kvist.editor_symbols_source(input, data)
    if !ok {
        fmt.eprintln(err.message)
        exit_with_timing(1)
    }
    defer delete(output)
    filtered := filter_symbol_output_by_prefix(output, prefix)
    defer delete(filtered)
    fmt.print(filtered)
}

lookup_command :: proc(input, identifier: string) {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    output, err, ok := kvist.editor_symbols_source(input, data)
    if !ok {
        fmt.eprintln(err.message)
        exit_with_timing(1)
    }
    defer delete(output)
    filtered := filter_symbol_output(output, identifier)
    defer delete(filtered)
    fmt.print(filtered)
}

package_symbols_command :: proc(import_path, alias: string) {
    output, ok := kvist.package_symbols_source(import_path, alias)
    if !ok {
        fmt.eprintln("unsupported package-symbols import path: ", import_path)
        exit_with_timing(1)
    }
    defer delete(output)
    fmt.print(output)
}
