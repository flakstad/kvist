package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import kvist "../../src/kvist"

CACHE_DIR :: ".kvist-cache"

print_usage :: proc() {
    fmt.println("usage:")
    fmt.println("  kvist <input.kvist> [-o output.odin] [--map output.map] [--eval form] [--no-print]")
    fmt.println("  kvist compile <input.kvist> [-o output.odin] [--map output.map]")
    fmt.println("  kvist dev --reload <input.kvist> [--rebuild] [--watch] [--generated-dir dir] [--print-paths] [--json]")
    fmt.println("  kvist build <input.kvist> [--generated output.odin] [--reload] [--generated-dir dir]")
    fmt.println("  kvist check <input.kvist> [--generated output.odin] [--reload] [--generated-dir dir]")
    fmt.println("  kvist run <input.kvist> [--generated output.odin] [--reload] [--generated-dir dir]")
    fmt.println("  kvist test <input.kvist> [--generated output.odin] [--names test1,test2]")
    fmt.println("  kvist eval <input.kvist> <form> [--no-print] [--check] [--generated output.odin] [--save name]")
    fmt.println("  kvist expand <input.kvist> <form> [--no-print] [-o output.odin]")
    fmt.println("  kvist macroexpand <input.kvist> <form> [-o output.kvist] [--map output.map]")
    fmt.println("  kvist symbols <input.kvist>")
    fmt.println("  kvist editor-symbols <input.kvist> [identifier]")
    fmt.println("  kvist lookup <input.kvist> <identifier>")
    fmt.println("  kvist complete <input.kvist> [prefix]")
    fmt.println("  kvist doc <input.kvist> <identifier>")
    fmt.println("  kvist xref <input.kvist> <identifier>")
    fmt.println("  kvist builtin-symbols")
    fmt.println("  kvist imported-symbols <input.kvist>")
    fmt.println("  kvist package-symbols <import-path> [alias]")
    fmt.println("  kvist cache path <name>")
    fmt.println("  kvist cache list")
    fmt.println("  kvist cache rm <name>")
}

is_help_arg :: proc(text: string) -> bool {
    return text == "help" || text == "--help" || text == "-h"
}

is_command :: proc(text: string) -> bool {
    return is_help_arg(text) || text == "compile" || text == "dev" || text == "build" || text == "check" || text == "run" || text == "test" || text == "eval" || text == "expand" || text == "macroexpand" || text == "symbols" || text == "editor-symbols" || text == "lookup" || text == "complete" || text == "doc" || text == "xref" || text == "builtin-symbols" || text == "imported-symbols" || text == "package-symbols" || text == "cache"
}

read_source_or_exit :: proc(path: string) -> string {
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        fmt.eprintln("could not read file: ", path)
        os.exit(1)
    }
    return string(data)
}

write_output_or_exit :: proc(path, output: string) {
    write_err := os.write_entire_file_from_string(path, output)
    if write_err != nil {
        fmt.eprintln("failed to write output: ", path)
        os.exit(1)
    }
}

cache_key_valid :: proc(name: string) -> bool {
    if name == "" || name == "." || name == ".." {
        return false
    }
    for ch in transmute([]byte)name {
        if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
           (ch >= '0' && ch <= '9') || ch == '_' || ch == '-' || ch == '.' {
            continue
        }
        return false
    }
    return true
}

cache_dir_or_exit :: proc() -> string {
    env_dir, found := os.lookup_env("KVIST_CACHE_DIR", context.allocator)
    if found {
        if env_dir != "" {
            return env_dir
        }
        delete(env_dir)
    }
    return strings.clone(CACHE_DIR)
}

cache_path_in_dir_or_exit :: proc(dir, name: string) -> string {
    if !cache_key_valid(name) {
        fmt.eprintln("invalid cache name: ", name)
        os.exit(2)
    }
    path, join_err := os.join_path({dir, name}, context.allocator)
    if join_err != nil {
        fmt.eprintln("failed to build cache path")
        os.exit(1)
    }
    return path
}

ensure_cache_dir_or_exit :: proc(dir: string) {
    err := os.make_directory_all(dir)
    if err != nil {
        fmt.eprintln("failed to create cache directory: ", dir)
        os.exit(1)
    }
}

save_stdout_to_cache_or_exit :: proc(name: string, stdout: []byte) {
    dir := cache_dir_or_exit()
    defer delete(dir)
    ensure_cache_dir_or_exit(dir)
    path := cache_path_in_dir_or_exit(dir, name)
    defer delete(path)
    write_err := os.write_entire_file(path, stdout)
    if write_err != nil {
        fmt.eprintln("failed to write cache value: ", path)
        os.exit(1)
    }
}

cache_command :: proc() {
    if len(os.args) < 3 {
        print_usage()
        os.exit(2)
    }

    switch os.args[2] {
    case "path":
        if len(os.args) != 4 {
            print_usage()
            os.exit(2)
        }
        dir := cache_dir_or_exit()
        defer delete(dir)
        path := cache_path_in_dir_or_exit(dir, os.args[3])
        defer delete(path)
        fmt.println(path)
    case "list":
        if len(os.args) != 3 {
            print_usage()
            os.exit(2)
        }
        dir := cache_dir_or_exit()
        defer delete(dir)
        if !os.exists(dir) {
            return
        }
        entries, err := os.read_directory_by_path(dir, -1, context.allocator)
        if err != nil {
            fmt.eprintln("failed to read cache directory: ", dir)
            os.exit(1)
        }
        defer os.file_info_slice_delete(entries, context.allocator)
        slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {
            return a.name < b.name
        })
        for entry in entries {
            if entry.type == .Regular {
                fmt.println(entry.name)
            }
        }
    case "rm":
        if len(os.args) != 4 {
            print_usage()
            os.exit(2)
        }
        dir := cache_dir_or_exit()
        defer delete(dir)
        path := cache_path_in_dir_or_exit(dir, os.args[3])
        defer delete(path)
        if !os.exists(path) {
            return
        }
        err := os.remove(path)
        if err != nil {
            fmt.eprintln("failed to remove cache value: ", path)
            os.exit(1)
        }
    case:
        print_usage()
        os.exit(2)
    }
}

parse_generated_location :: proc(line, generated_path: string) -> (line_no, column_no, close_index: int, ok: bool) {
    open_index := strings.index(line, "(")
    if open_index < 0 {
        return 0, 0, 0, false
    }

    file_text := line[:open_index]
    _, generated_file := os.split_path(generated_path)
    _, diagnostic_file := os.split_path(file_text)
    if file_text != generated_path && diagnostic_file != generated_file {
        return 0, 0, 0, false
    }

    location := line[open_index+1:]
    colon_index := strings.index(location, ":")
    close_offset := strings.index(location, ")")
    if colon_index < 0 || close_offset < 0 || colon_index > close_offset {
        return 0, 0, 0, false
    }

    parsed_line, ok_line := strconv.parse_int(location[:colon_index])
    if !ok_line {
        return 0, 0, 0, false
    }

    parsed_column := 0
    if colon_index+1 < close_offset {
        column_text := location[colon_index+1:close_offset]
        if second_colon := strings.index(column_text, ":"); second_colon >= 0 {
            column_text = column_text[:second_colon]
        }
        parsed, ok_column := strconv.parse_int(column_text)
        if ok_column {
            parsed_column = parsed
        }
    }

    return parsed_line, parsed_column, open_index + 1 + close_offset, true
}

remap_odin_output_locations :: proc(output, generated_path, source_path, source, eval_source: string, source_map: []kvist.Source_Map_Entry) -> string {
    if generated_path == "" || source_path == "" || len(source_map) == 0 {
        return strings.clone(output)
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    rest := output
    for len(rest) > 0 {
        line := rest
        next_start := len(rest)
        if newline := strings.index(rest, "\n"); newline >= 0 {
            line = rest[:newline+1]
            next_start = newline + 1
        }

        generated_line, generated_column, close_index, ok_location := parse_generated_location(line, generated_path)
        if ok_location {
            if entry, found := kvist.source_map_entry_for_generated_location(source_map, generated_line, generated_column); found {
                if entry.source_span.source == .Eval {
                    source_line, source_column, _, _ := kvist.source_position(eval_source, entry.source_span.start)
                    fmt.sbprintf(&builder, "%s:<eval>:%d:%d", source_path, source_line, source_column)
                } else {
                    source_line, source_column, _, _ := kvist.source_position(source, entry.source_span.start)
                    fmt.sbprintf(&builder, "%s:%d:%d", source_path, source_line, source_column)
                }
                strings.write_string(&builder, line[close_index+1:])
            } else {
                strings.write_string(&builder, line)
            }
        } else {
            strings.write_string(&builder, line)
        }

        rest = rest[next_start:]
    }

    return strings.clone(strings.to_string(builder))
}

cleanup_odin_output_arg :: proc(out_path, out_arg: string) {
    if out_path != "" {
        _ = os.remove(out_path)
        delete(out_path)
    }
    if out_arg != "" {
        delete(out_arg)
    }
}

print_compile_warnings :: proc(path, source, eval_source: string, warnings: []kvist.Compile_Warning) {
    for warning in warnings {
        formatted := ""
        if eval_source != "" {
            formatted = kvist.format_eval_compile_warning(path, source, eval_source, warning)
        } else {
            formatted = kvist.format_compile_warning(path, source, warning)
        }
        fmt.eprint(formatted)
        delete(formatted)
    }
}

run_odin_file :: proc(command, generated_path, source_path, source, eval_source, save_name: string, source_map: []kvist.Source_Map_Entry, extra_args: []string = nil, package_dir := "") -> int {
    source_dir, _ := os.split_path(source_path)
    working_dir := source_dir
    if working_dir == "" {
        working_dir = "."
    }

    generated_abs, abs_err := os.get_absolute_path(generated_path, context.allocator)
    if abs_err != nil {
        fmt.eprintln("failed to resolve generated path: ", generated_path)
        return 1
    }
    defer delete(generated_abs)

    args := make([dynamic]string, 0, 5)
    defer delete(args)
    odin_command := command
    if command == "run" {
        odin_command = "build"
    }
    package_arg := ""
    defer {
        if package_arg != "" {
            delete(package_arg)
        }
    }
    if package_dir != "" {
        package_abs, package_abs_err := os.get_absolute_path(package_dir, context.allocator)
        if package_abs_err != nil {
            fmt.eprintln("failed to resolve package path: ", package_dir)
            return 1
        }
        package_arg = package_abs
        append(&args, "odin", odin_command, package_arg)
    } else {
        append(&args, "odin", odin_command, generated_abs, "-file")
    }
    for arg in extra_args {
        append(&args, arg)
    }
    out_path := ""
    out_arg := ""
    if command == "build" || command == "run" || command == "test" {
        out_path = strings.clone(fmt.tprintf("%s.bin", generated_abs))
        out_arg = strings.clone(fmt.tprintf("-out:%s", out_path))
        append(&args, out_arg)
    }
    defer cleanup_odin_output_arg(out_path, out_arg)
    state, stdout, stderr, err := os.process_exec(
        os.Process_Desc{command = args[:], working_dir = working_dir},
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)

    if len(stdout) > 0 {
        fmt.print(string(stdout))
    }
    if len(stderr) > 0 {
        mapped_stderr := remap_odin_output_locations(string(stderr), generated_abs, source_path, source, eval_source, source_map)
        defer delete(mapped_stderr)
        fmt.eprint(mapped_stderr)
    }
    if err != nil {
        fmt.eprintln("failed to run odin ", odin_command)
        return 1
    }
    if state.exited {
        if command == "run" && state.exit_code == 0 {
            run_state, run_stdout, run_stderr, run_err := os.process_exec(
                os.Process_Desc{command = {out_path}, working_dir = working_dir},
                context.allocator,
            )
            defer delete(run_stdout)
            defer delete(run_stderr)

            if len(run_stdout) > 0 {
                fmt.print(string(run_stdout))
            }
            if len(run_stderr) > 0 {
                fmt.eprint(string(run_stderr))
            }
            if run_err != nil {
                fmt.eprintln("failed to run built program: ", out_path)
                return 1
            }
            if run_state.exited {
                if run_state.exit_code == 0 && save_name != "" {
                    save_stdout_to_cache_or_exit(save_name, run_stdout)
                }
                return run_state.exit_code
            }
            return 1
        }
        if state.exit_code == 0 && save_name != "" {
            save_stdout_to_cache_or_exit(save_name, stdout)
        }
        return state.exit_code
    }
    return 1
}

source_dir_has_odin_sidecars :: proc(source_path: string) -> bool {
    source_dir, _ := os.split_path(source_path)
    if source_dir == "" {
        source_dir = "."
    }
    entries, err := os.read_directory_by_path(source_dir, -1, context.allocator)
    if err != nil {
        return false
    }
    defer os.file_info_slice_delete(entries, context.allocator)
    has_sidecar := false
    for entry in entries {
        if entry.type != .Regular || !strings.has_suffix(entry.name, ".odin") {
            continue
        }
        if strings.has_prefix(entry.name, "kvist-generated-") {
            continue
        }
        entry_path, join_err := os.join_path({source_dir, entry.name}, context.allocator)
        if join_err != nil {
            return false
        }
        data, read_err := os.read_entire_file_from_path(entry_path, context.allocator)
        delete(entry_path)
        if read_err != nil {
            return false
        }
        defer delete(data)
        if strings.contains(string(data), "main :: proc") {
            return false
        }
        has_sidecar = true
    }
    return has_sidecar
}

temporary_generated_path_in_source_dir :: proc(source_path: string) -> (path, package_dir: string, ok: bool) {
    source_dir, _ := os.split_path(source_path)
    if source_dir == "" {
        source_dir = "."
    }
    for i in 0..<1000 {
        name := fmt.tprintf("kvist-generated-%d.odin", i)
        candidate, join_err := os.join_path({source_dir, name}, context.allocator)
        if join_err != nil {
            return "", "", false
        }
        if !os.exists(candidate) {
            return candidate, strings.clone(source_dir), true
        }
        delete(candidate)
    }
    return "", "", false
}

write_generated_for_execution :: proc(output, requested_path, source_path: string) -> (path, temp_dir, package_dir: string, ok: bool) {
    if requested_path != "" {
        rebased, err_rebase, ok_rebase := kvist.rebase_emitted_odin_imports_for_output_path(output, requested_path)
        if !ok_rebase {
            fmt.eprintln(err_rebase.message)
            return "", "", "", false
        }
        write_output_or_exit(requested_path, rebased)
        delete(rebased)
        return requested_path, "", "", true
    }

    if source_dir_has_odin_sidecars(source_path) {
        generated, package_build_dir, path_ok := temporary_generated_path_in_source_dir(source_path)
        if !path_ok {
            fmt.eprintln("failed to create temporary generated path in source package")
            return "", "", "", false
        }
        rebased, err_rebase, ok_rebase := kvist.rebase_emitted_odin_imports_for_output_path(output, generated)
        if !ok_rebase {
            fmt.eprintln(err_rebase.message)
            delete(generated)
            delete(package_build_dir)
            return "", "", "", false
        }
        write_output_or_exit(generated, rebased)
        delete(rebased)
        return generated, "", package_build_dir, true
    }

    dir, dir_err := os.make_directory_temp("", "kvist-*", context.allocator)
    if dir_err != nil {
        fmt.eprintln("failed to create temporary directory")
        return "", "", "", false
    }

    generated, join_err := os.join_path({dir, "generated.odin"}, context.allocator)
    if join_err != nil {
        fmt.eprintln("failed to create temporary path")
        _ = os.remove(dir)
        delete(dir)
        return "", "", "", false
    }

    rebased, err_rebase, ok_rebase := kvist.rebase_emitted_odin_imports_for_output_path(output, generated)
    if !ok_rebase {
        fmt.eprintln(err_rebase.message)
        _ = os.remove(generated)
        _ = os.remove(dir)
        delete(generated)
        delete(dir)
        return "", "", "", false
    }
    write_output_or_exit(generated, rebased)
    delete(rebased)
    return generated, dir, "", true
}

cleanup_generated :: proc(path, temp_dir, requested_path, package_dir: string) {
    if requested_path == "" {
        if path != "" {
            _ = os.remove(path)
            delete(path)
        }
        if temp_dir != "" {
            _ = os.remove(temp_dir)
            delete(temp_dir)
        }
    }
    if package_dir != "" {
        delete(package_dir)
    }
}

compile_file_command :: proc(input, output_path, map_path: string) {
    result, err, ok := kvist.compile_path_with_map(input)
    if !ok {
        data := read_source_or_exit(input)
        formatted := kvist.format_compile_error(input, data, err)
        fmt.eprint(formatted)
        delete(formatted)
        delete(transmute([]byte)data)
        os.exit(1)
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    if len(result.warnings) > 0 {
        data := read_source_or_exit(input)
        defer delete(transmute([]byte)data)
        print_compile_warnings(input, data, "", result.warnings[:])
    }

    if output_path != "" {
        output, err_rebase, ok_rebase := kvist.rebase_emitted_odin_imports_for_output_path(result.output, output_path)
        if !ok_rebase {
            fmt.eprintln(err_rebase.message)
            os.exit(1)
        }
        defer delete(output)
        write_output_or_exit(output_path, output)
    } else {
        fmt.print(result.output)
    }

    if map_path != "" {
        map_output := kvist.format_source_map(result.source_map[:])
        write_output_or_exit(map_path, map_output)
        delete(map_output)
    }
}

compile_eval_emit_command :: proc(input, eval_source, output_path: string, no_print: bool) {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    result, err, ok := kvist.compile_eval_path_with_map(input, eval_source, no_print)
    if !ok {
        formatted := kvist.format_eval_compile_error(input, data, eval_source, err)
        fmt.eprint(formatted)
        delete(formatted)
        os.exit(1)
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    print_compile_warnings(input, data, eval_source, result.warnings[:])

    if output_path != "" {
        output, err_rebase, ok_rebase := kvist.rebase_emitted_odin_imports_for_output_path(result.output, output_path)
        if !ok_rebase {
            fmt.eprintln(err_rebase.message)
            os.exit(1)
        }
        defer delete(output)
        write_output_or_exit(output_path, output)
    } else {
        fmt.print(result.output)
    }
}

macroexpand_command :: proc(input, eval_source, output_path, map_path: string) {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    result, err, ok := kvist.macroexpand_eval_source_with_map(data, eval_source)
    if !ok {
        formatted := kvist.format_eval_compile_error(input, data, eval_source, err)
        fmt.eprint(formatted)
        delete(formatted)
        os.exit(1)
    }
    defer delete(result.output)
    defer delete(result.source_map)

    if output_path != "" {
        write_output_or_exit(output_path, result.output)
    } else {
        fmt.print(result.output)
    }

    if map_path != "" {
        map_output := kvist.format_source_map(result.source_map[:])
        write_output_or_exit(map_path, map_output)
        delete(map_output)
    }
}

symbols_command :: proc(input: string) {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    output, err, ok := kvist.symbols_source(data)
    if !ok {
        formatted := kvist.format_compile_error(input, data, err)
        fmt.eprint(formatted)
        delete(formatted)
        os.exit(1)
    }
    defer delete(output)
    fmt.print(output)
}

editor_symbols_command :: proc(input: string, identifier := "") {
    data := read_source_or_exit(input)
    output, err, ok := kvist.editor_symbols_source(input, data)
    if !ok {
        fmt.eprintln(err.message)
        os.exit(1)
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
        os.exit(1)
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
        doc = strings.clone("") if len(fields) < 7 else strings.clone(fields[6]),
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
    output, err, ok := kvist.editor_symbols_source(input, data)
    if !ok {
        fmt.eprintln(err.message)
        os.exit(1)
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
        os.exit(1)
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
        os.exit(1)
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
        os.exit(1)
    }
}

complete_command :: proc(input: string, prefix := "") {
    data := read_source_or_exit(input)
    output, err, ok := kvist.editor_symbols_source(input, data)
    if !ok {
        fmt.eprintln(err.message)
        os.exit(1)
    }
    defer delete(output)
    filtered := filter_symbol_output_by_prefix(output, prefix)
    defer delete(filtered)
    fmt.print(filtered)
}

lookup_command :: proc(input, identifier: string) {
    data := read_source_or_exit(input)
    output, err, ok := kvist.editor_symbols_source(input, data)
    if !ok {
        fmt.eprintln(err.message)
        os.exit(1)
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
        os.exit(1)
    }
    defer delete(output)
    fmt.print(output)
}

run_generated_command :: proc(input, generated_path, odin_command: string) -> int {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    result, err, ok := kvist.compile_path_with_map(input)
    if !ok {
        formatted := kvist.format_compile_error(input, data, err)
        fmt.eprint(formatted)
        delete(formatted)
        os.exit(1)
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    print_compile_warnings(input, data, "", result.warnings[:])
    path, temp_dir, package_dir, path_ok := write_generated_for_execution(result.output, generated_path, input)
    if !path_ok {
        return 1
    }
    defer cleanup_generated(path, temp_dir, generated_path, package_dir)

    return run_odin_file(odin_command, path, input, data, "", "", result.source_map[:], package_dir = package_dir)
}

test_command :: proc(input, generated_path, test_names: string) -> int {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    result, err, ok := kvist.compile_path_with_map(input)
    if !ok {
        formatted := kvist.format_compile_error(input, data, err)
        fmt.eprint(formatted)
        delete(formatted)
        os.exit(1)
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    print_compile_warnings(input, data, "", result.warnings[:])
    path, temp_dir, package_dir, path_ok := write_generated_for_execution(result.output, generated_path, input)
    if !path_ok {
        return 1
    }
    defer cleanup_generated(path, temp_dir, generated_path, package_dir)

    extra_args := make([dynamic]string, 0, 1)
    defer delete(extra_args)
    if test_names != "" {
        normalized_test_names := normalize_test_names_arg(test_names)
        defer delete(normalized_test_names)
        append(&extra_args, fmt.tprintf("-define:ODIN_TEST_NAMES=%s", normalized_test_names))
    }

    return run_odin_file("test", path, input, data, "", "", result.source_map[:], extra_args[:], package_dir)
}

eval_command :: proc(input, eval_source, generated_path, save_name: string, no_print, check_only: bool) -> int {
    if check_only && save_name != "" {
        fmt.eprintln("--save cannot be used with --check")
        return 2
    }
    if !no_print && !check_only && strings.trim_space(eval_source) == "(main)" {
        data := read_source_or_exit(input)
        defer delete(transmute([]byte)data)

        result, err, ok := kvist.compile_path_with_map(input)
        if !ok {
            formatted := kvist.format_compile_error(input, data, err)
            fmt.eprint(formatted)
            delete(formatted)
            os.exit(1)
        }
        defer delete(result.output)
        defer delete(result.source_map)

        path, temp_dir, package_dir, path_ok := write_generated_for_execution(result.output, generated_path, input)
        if !path_ok {
            return 1
        }
        defer cleanup_generated(path, temp_dir, generated_path, package_dir)

        return run_odin_file("run", path, input, data, "", save_name, result.source_map[:], package_dir = package_dir)
    }

    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    result, err, ok := kvist.compile_eval_path_with_map(input, eval_source, no_print)
    if !ok {
        formatted := kvist.format_eval_compile_error(input, data, eval_source, err)
        fmt.eprint(formatted)
        delete(formatted)
        os.exit(1)
    }
    defer delete(result.output)
    defer delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    print_compile_warnings(input, data, eval_source, result.warnings[:])
    path, temp_dir, package_dir, path_ok := write_generated_for_execution(result.output, generated_path, input)
    if !path_ok {
        return 1
    }
    defer cleanup_generated(path, temp_dir, generated_path, package_dir)

    odin_command := "run"
    if check_only {
        odin_command = "check"
    }
    return run_odin_file(odin_command, path, input, data, eval_source, save_name, result.source_map[:], package_dir = package_dir)
}

parse_legacy_compile :: proc() {
    input := os.args[1]
    output_path := ""
    map_path := ""
    eval_source := ""
    no_print := false

    i := 2
    for i < len(os.args) {
        switch os.args[i] {
        case "-o":
            if i+1 >= len(os.args) {
                print_usage()
                os.exit(2)
            }
            output_path = os.args[i+1]
            i += 2
        case "--map":
            if i+1 >= len(os.args) {
                print_usage()
                os.exit(2)
            }
            map_path = os.args[i+1]
            i += 2
        case "--eval":
            if i+1 >= len(os.args) {
                print_usage()
                os.exit(2)
            }
            eval_source = os.args[i+1]
            i += 2
        case "--no-print":
            no_print = true
            i += 1
        case:
            print_usage()
            os.exit(2)
        }
    }

    if eval_source != "" {
        if map_path != "" {
            fmt.eprintln("--map cannot be used with --eval")
            os.exit(2)
        }
        compile_eval_emit_command(input, eval_source, output_path, no_print)
        return
    }
    compile_file_command(input, output_path, map_path)
}

parse_compile_command :: proc() {
    if len(os.args) < 3 {
        print_usage()
        os.exit(2)
    }
    input := os.args[2]
    output_path := ""
    map_path := ""

    i := 3
    for i < len(os.args) {
        switch os.args[i] {
        case "-o":
            if i+1 >= len(os.args) {
                print_usage()
                os.exit(2)
            }
            output_path = os.args[i+1]
            i += 2
        case "--map":
            if i+1 >= len(os.args) {
                print_usage()
                os.exit(2)
            }
            map_path = os.args[i+1]
            i += 2
        case:
            print_usage()
            os.exit(2)
        }
    }

    compile_file_command(input, output_path, map_path)
}

parse_run_or_check_command :: proc(odin_command: string) {
    if len(os.args) < 3 {
        print_usage()
        os.exit(2)
    }
    input := ""
    generated_path := ""
    generated_dir := ""
    reload_mode := false

    i := 2
    for i < len(os.args) {
        switch os.args[i] {
        case "--reload":
            reload_mode = true
            i += 1
        case "--generated":
            if i+1 >= len(os.args) {
                print_usage()
                os.exit(2)
            }
            generated_path = os.args[i+1]
            i += 2
        case "--generated-dir":
            if i+1 >= len(os.args) {
                print_usage()
                os.exit(2)
            }
            generated_dir = os.args[i+1]
            i += 2
        case:
            if input == "" {
                input = os.args[i]
                i += 1
            } else {
                print_usage()
                os.exit(2)
            }
        }
    }

    if input == "" {
        print_usage()
        os.exit(2)
    }

    if reload_mode {
        if generated_path != "" {
            print_usage()
            os.exit(2)
        }
        os.exit(reload_app_generate_and_execute(input, odin_command, generated_dir))
    }

    if generated_path == "" && source_declares_reload_app(input) {
        os.exit(reload_app_generate_and_execute(input, odin_command, generated_dir))
    }

    os.exit(run_generated_command(input, generated_path, odin_command))
}

parse_test_command :: proc() {
    if len(os.args) < 3 {
        print_usage()
        os.exit(2)
    }
    input := os.args[2]
    generated_path := ""
    test_names := ""

    i := 3
    for i < len(os.args) {
        switch os.args[i] {
        case "--generated":
            if i+1 >= len(os.args) {
                print_usage()
                os.exit(2)
            }
            generated_path = os.args[i+1]
            i += 2
        case "--names":
            if i+1 >= len(os.args) {
                print_usage()
                os.exit(2)
            }
            test_names = os.args[i+1]
            i += 2
        case:
            print_usage()
            os.exit(2)
        }
    }

    os.exit(test_command(input, generated_path, test_names))
}

parse_eval_command :: proc() {
    if len(os.args) < 4 {
        print_usage()
        os.exit(2)
    }
    input := os.args[2]
    eval_source := os.args[3]
    generated_path := ""
    save_name := ""
    no_print := false
    check_only := false

    i := 4
    for i < len(os.args) {
        switch os.args[i] {
        case "--generated":
            if i+1 >= len(os.args) {
                print_usage()
                os.exit(2)
            }
            generated_path = os.args[i+1]
            i += 2
        case "--no-print":
            no_print = true
            i += 1
        case "--check":
            check_only = true
            i += 1
        case "--save":
            if i+1 >= len(os.args) {
                print_usage()
                os.exit(2)
            }
            save_name = os.args[i+1]
            i += 2
        case:
            print_usage()
            os.exit(2)
        }
    }

    os.exit(eval_command(input, eval_source, generated_path, save_name, no_print, check_only))
}

parse_expand_command :: proc() {
    if len(os.args) < 4 {
        print_usage()
        os.exit(2)
    }
    input := os.args[2]
    eval_source := os.args[3]
    output_path := ""
    no_print := false

    i := 4
    for i < len(os.args) {
        switch os.args[i] {
        case "-o":
            if i+1 >= len(os.args) {
                print_usage()
                os.exit(2)
            }
            output_path = os.args[i+1]
            i += 2
        case "--no-print":
            no_print = true
            i += 1
        case:
            print_usage()
            os.exit(2)
        }
    }

    compile_eval_emit_command(input, eval_source, output_path, no_print)
}

parse_macroexpand_command :: proc() {
    if len(os.args) < 4 {
        print_usage()
        os.exit(2)
    }
    input := os.args[2]
    eval_source := os.args[3]
    output_path := ""
    map_path := ""

    i := 4
    for i < len(os.args) {
        switch os.args[i] {
        case "-o":
            if i+1 >= len(os.args) {
                print_usage()
                os.exit(2)
            }
            output_path = os.args[i+1]
            i += 2
        case "--map":
            if i+1 >= len(os.args) {
                print_usage()
                os.exit(2)
            }
            map_path = os.args[i+1]
            i += 2
        case:
            print_usage()
            os.exit(2)
        }
    }

    macroexpand_command(input, eval_source, output_path, map_path)
}

parse_symbols_command :: proc() {
    if len(os.args) != 3 {
        print_usage()
        os.exit(2)
    }
    symbols_command(os.args[2])
}

parse_editor_symbols_command :: proc() {
    if len(os.args) != 3 && len(os.args) != 4 {
        print_usage()
        os.exit(2)
    }
    identifier := ""
    if len(os.args) == 4 {
        identifier = os.args[3]
    }
    editor_symbols_command(os.args[2], identifier)
}

parse_lookup_command :: proc() {
    if len(os.args) != 4 {
        print_usage()
        os.exit(2)
    }
    lookup_command(os.args[2], os.args[3])
}

parse_complete_command :: proc() {
    if len(os.args) != 3 && len(os.args) != 4 {
        print_usage()
        os.exit(2)
    }
    prefix := ""
    if len(os.args) == 4 {
        prefix = os.args[3]
    }
    complete_command(os.args[2], prefix)
}

parse_doc_command :: proc() {
    if len(os.args) != 4 {
        print_usage()
        os.exit(2)
    }
    doc_command(os.args[2], os.args[3])
}

parse_xref_command :: proc() {
    if len(os.args) != 4 {
        print_usage()
        os.exit(2)
    }
    xref_command(os.args[2], os.args[3])
}

parse_builtin_symbols_command :: proc() {
    if len(os.args) != 2 {
        print_usage()
        os.exit(2)
    }
    builtin_symbols_command()
}

parse_imported_symbols_command :: proc() {
    if len(os.args) != 3 {
        print_usage()
        os.exit(2)
    }
    imported_symbols_command(os.args[2])
}

parse_package_symbols_command :: proc() {
    if len(os.args) != 3 && len(os.args) != 4 {
        print_usage()
        os.exit(2)
    }
    alias := ""
    if len(os.args) == 4 {
        alias = os.args[3]
    }
    package_symbols_command(os.args[2], alias)
}

main :: proc() {
    if len(os.args) < 2 {
        print_usage()
        os.exit(2)
    }

    if !is_command(os.args[1]) {
        parse_legacy_compile()
        return
    }

    switch os.args[1] {
    case "help", "--help", "-h":
        print_usage()
    case "compile":
        parse_compile_command()
    case "dev":
        parse_dev_command()
    case "build":
        parse_run_or_check_command("build")
    case "check":
        parse_run_or_check_command("check")
    case "run":
        parse_run_or_check_command("run")
    case "test":
        parse_test_command()
    case "eval":
        parse_eval_command()
    case "expand":
        parse_expand_command()
    case "macroexpand":
        parse_macroexpand_command()
    case "symbols":
        parse_symbols_command()
    case "editor-symbols":
        parse_editor_symbols_command()
    case "lookup":
        parse_lookup_command()
    case "complete":
        parse_complete_command()
    case "doc":
        parse_doc_command()
    case "xref":
        parse_xref_command()
    case "builtin-symbols":
        parse_builtin_symbols_command()
    case "imported-symbols":
        parse_imported_symbols_command()
    case "package-symbols":
        parse_package_symbols_command()
    case "cache":
        cache_command()
    }
}
