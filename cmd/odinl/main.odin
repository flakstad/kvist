package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import odinl "../../src/odinl"

CACHE_DIR :: ".odinl-cache"

print_usage :: proc() {
    fmt.println("usage:")
    fmt.println("  odinl <input.odinl> [-o output.odin] [--map output.map] [--eval form] [--no-print]")
    fmt.println("  odinl compile <input.odinl> [-o output.odin] [--map output.map]")
    fmt.println("  odinl build <input.odinl> [--generated output.odin]")
    fmt.println("  odinl check <input.odinl> [--generated output.odin]")
    fmt.println("  odinl run <input.odinl> [--generated output.odin]")
    fmt.println("  odinl eval <input.odinl> <form> [--no-print] [--check] [--generated output.odin] [--save name]")
    fmt.println("  odinl expand <input.odinl> <form> [--no-print] [-o output.odin]")
    fmt.println("  odinl macroexpand <input.odinl> <form> [-o output.odinl] [--map output.map]")
    fmt.println("  odinl symbols <input.odinl>")
    fmt.println("  odinl cache path <name>")
    fmt.println("  odinl cache list")
    fmt.println("  odinl cache rm <name>")
}

is_command :: proc(text: string) -> bool {
    return text == "compile" || text == "build" || text == "check" || text == "run" || text == "eval" || text == "expand" || text == "macroexpand" || text == "symbols" || text == "cache"
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
    env_dir, found := os.lookup_env("ODINL_CACHE_DIR", context.allocator)
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

remap_odin_output_locations :: proc(output, generated_path, source_path, source, eval_source: string, source_map: []odinl.Source_Map_Entry) -> string {
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
            if entry, found := odinl.source_map_entry_for_generated_location(source_map, generated_line, generated_column); found {
                if entry.source_span.source == .Eval {
                    source_line, source_column, _, _ := odinl.source_position(eval_source, entry.source_span.start)
                    fmt.sbprintf(&builder, "%s:<eval>:%d:%d", source_path, source_line, source_column)
                } else {
                    source_line, source_column, _, _ := odinl.source_position(source, entry.source_span.start)
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

run_odin_file :: proc(command, generated_path, source_path, source, eval_source, save_name: string, source_map: []odinl.Source_Map_Entry) -> int {
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

    args := [?]string{"odin", command, generated_abs, "-file"}
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
        fmt.eprintln("failed to run odin ", command)
        return 1
    }
    if state.exited {
        if state.exit_code == 0 && save_name != "" {
            save_stdout_to_cache_or_exit(save_name, stdout)
        }
        return state.exit_code
    }
    return 1
}

write_generated_for_execution :: proc(output, requested_path: string) -> (path, temp_dir: string, ok: bool) {
    if requested_path != "" {
        write_output_or_exit(requested_path, output)
        return requested_path, "", true
    }

    dir, dir_err := os.make_directory_temp("", "odinl-*", context.allocator)
    if dir_err != nil {
        fmt.eprintln("failed to create temporary directory")
        return "", "", false
    }

    generated, join_err := os.join_path({dir, "generated.odin"}, context.allocator)
    if join_err != nil {
        fmt.eprintln("failed to create temporary path")
        _ = os.remove(dir)
        delete(dir)
        return "", "", false
    }

    write_output_or_exit(generated, output)
    return generated, dir, true
}

cleanup_generated :: proc(path, temp_dir, requested_path: string) {
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
}

compile_file_command :: proc(input, output_path, map_path: string) {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    result, err, ok := odinl.compile_source_with_map(data)
    if !ok {
        formatted := odinl.format_compile_error(input, data, err)
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
        map_output := odinl.format_source_map(result.source_map[:])
        write_output_or_exit(map_path, map_output)
        delete(map_output)
    }
}

compile_eval_emit_command :: proc(input, eval_source, output_path: string, no_print: bool) {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    output, err, ok := odinl.compile_eval_source(data, eval_source, no_print)
    if !ok {
        formatted := odinl.format_eval_compile_error(input, data, eval_source, err)
        fmt.eprint(formatted)
        delete(formatted)
        os.exit(1)
    }
    defer delete(output)

    if output_path != "" {
        write_output_or_exit(output_path, output)
    } else {
        fmt.print(output)
    }
}

macroexpand_command :: proc(input, eval_source, output_path, map_path: string) {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    result, err, ok := odinl.macroexpand_source_with_map(eval_source)
    if !ok {
        formatted := odinl.format_eval_compile_error(input, data, eval_source, err)
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
        map_output := odinl.format_source_map(result.source_map[:])
        write_output_or_exit(map_path, map_output)
        delete(map_output)
    }
}

symbols_command :: proc(input: string) {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    output, err, ok := odinl.symbols_source(data)
    if !ok {
        formatted := odinl.format_compile_error(input, data, err)
        fmt.eprint(formatted)
        delete(formatted)
        os.exit(1)
    }
    defer delete(output)
    fmt.print(output)
}

run_generated_command :: proc(input, generated_path, odin_command: string) -> int {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    result, err, ok := odinl.compile_source_with_map(data)
    if !ok {
        formatted := odinl.format_compile_error(input, data, err)
        fmt.eprint(formatted)
        delete(formatted)
        os.exit(1)
    }
    defer delete(result.output)
    defer delete(result.source_map)

    path, temp_dir, path_ok := write_generated_for_execution(result.output, generated_path)
    if !path_ok {
        return 1
    }
    defer cleanup_generated(path, temp_dir, generated_path)

    return run_odin_file(odin_command, path, input, data, "", "", result.source_map[:])
}

eval_command :: proc(input, eval_source, generated_path, save_name: string, no_print, check_only: bool) -> int {
    if check_only && save_name != "" {
        fmt.eprintln("--save cannot be used with --check")
        return 2
    }
    if !no_print && !check_only && strings.trim_space(eval_source) == "(main)" {
        data := read_source_or_exit(input)
        defer delete(transmute([]byte)data)

        result, err, ok := odinl.compile_source_with_map(data)
        if !ok {
            formatted := odinl.format_compile_error(input, data, err)
            fmt.eprint(formatted)
            delete(formatted)
            os.exit(1)
        }
        defer delete(result.output)
        defer delete(result.source_map)

        path, temp_dir, path_ok := write_generated_for_execution(result.output, generated_path)
        if !path_ok {
            return 1
        }
        defer cleanup_generated(path, temp_dir, generated_path)

        return run_odin_file("run", path, input, data, "", save_name, result.source_map[:])
    }

    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    result, err, ok := odinl.compile_eval_source_with_map(data, eval_source, no_print)
    if !ok {
        formatted := odinl.format_eval_compile_error(input, data, eval_source, err)
        fmt.eprint(formatted)
        delete(formatted)
        os.exit(1)
    }
    defer delete(result.output)
    defer delete(result.source_map)

    path, temp_dir, path_ok := write_generated_for_execution(result.output, generated_path)
    if !path_ok {
        return 1
    }
    defer cleanup_generated(path, temp_dir, generated_path)

    odin_command := "run"
    if check_only {
        odin_command = "check"
    }
    return run_odin_file(odin_command, path, input, data, eval_source, save_name, result.source_map[:])
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
    input := os.args[2]
    generated_path := ""

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
        case:
            print_usage()
            os.exit(2)
        }
    }

    os.exit(run_generated_command(input, generated_path, odin_command))
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
    case "compile":
        parse_compile_command()
    case "build":
        parse_run_or_check_command("build")
    case "check":
        parse_run_or_check_command("check")
    case "run":
        parse_run_or_check_command("run")
    case "eval":
        parse_eval_command()
    case "expand":
        parse_expand_command()
    case "macroexpand":
        parse_macroexpand_command()
    case "symbols":
        parse_symbols_command()
    case "cache":
        cache_command()
    }
}
