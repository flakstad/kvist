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

parse_generated_location :: proc(line, generated_path: string) -> (line_no, column_no, close_index: int, ok: bool) {
    open_index := strings.index(line, "(")
    if open_index < 0 {
        return 0, 0, 0, false
    }

    file_text := line[:open_index]
    if strings.has_prefix(generated_path, "kvp_") {
        artifact_marker := fmt.tprintf("/%s/package.odin", generated_path)
        if !strings.contains(file_text, artifact_marker) {
            return 0, 0, 0, false
        }
    }
    _, generated_file := os.split_path(generated_path)
    _, diagnostic_file := os.split_path(file_text)
    if !strings.has_prefix(generated_path, "kvp_") &&
       file_text != generated_path &&
       diagnostic_file != generated_file {
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
                    mapped_path := source_path
                    mapped_source := source
                    mapped_source_bytes: []byte
                    if entry.source_path != "" {
                        mapped_path = entry.source_path
                    } else if enclosing_path, found_path := kvist.source_map_path_for_generated_location(
                        source_map,
                        generated_line,
                        generated_column,
                    ); found_path {
                        mapped_path = enclosing_path
                    }
                    if mapped_path != source_path {
                        imported_source, read_err := os.read_entire_file_from_path(mapped_path, context.allocator)
                        if read_err == nil {
                            mapped_source_bytes = imported_source
                            mapped_source = string(imported_source)
                        }
                    }
                    source_line, source_column, _, _ := kvist.source_position(mapped_source, entry.source_span.start)
                    fmt.sbprintf(&builder, "%s:%d:%d", mapped_path, source_line, source_column)
                    if mapped_source_bytes != nil {
                        delete(mapped_source_bytes)
                    }
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

cleanup_odin_output_arg :: proc(out_path, out_arg: string, remove_output := true) {
    if out_path != "" {
        if remove_output {
            _ = os.remove(out_path)
        }
        delete(out_path)
    }
    if out_arg != "" {
        delete(out_arg)
    }
}

odin_output_executable_path :: proc(generated_abs: string) -> string {
    suffix := ".bin"
    when ODIN_OS == .Windows {
        suffix = ".exe"
    }
    return strings.clone(fmt.tprintf("%s%s", generated_abs, suffix))
}

windows_import_collection_args :: proc(generated_path: string) -> [dynamic]string {
    args: [dynamic]string
    when ODIN_OS != .Windows {
        return args
    }

    data, read_err := os.read_entire_file_from_path(generated_path, context.allocator)
    if read_err != nil {
        return args
    }
    defer delete(data)

    seen: [26]bool
    source := string(data)
    line_start := 0
    for i := 0; i <= len(source); i += 1 {
        if i < len(source) && source[i] != '\n' {
            continue
        }
        line := source[line_start:i]
        line_start = i + 1
        if !strings.has_prefix(line, "import ") {
            continue
        }
        quote := strings.index(line, `"`)
        if quote < 0 || quote+3 >= len(line) {
            continue
        }
        drive := line[quote+1]
        if drive >= 'a' && drive <= 'z' {
            drive -= 'a'-'A'
        }
        if drive < 'A' || drive > 'Z' ||
           line[quote+2] != ':' ||
           (line[quote+3] != '/' && line[quote+3] != '\\') {
            continue
        }
        drive_index := int(drive-'A')
        if seen[drive_index] {
            continue
        }
        seen[drive_index] = true
        append(&args, strings.clone(fmt.tprintf("-collection:%c=%c:/", drive, drive)))
    }
    return args
}

print_compile_warnings :: proc(path, source, eval_source: string, warnings: []kvist.Compile_Warning) {
    for warning, idx in warnings {
        if warning.confidence == .Conservative && !ownership_audit_enabled {
            continue
        }
        duplicate := false
        for previous in warnings[:idx] {
            if previous.confidence == .Conservative && !ownership_audit_enabled {
                continue
            }
            if previous.code == warning.code &&
               previous.source_path == warning.source_path &&
               previous.line == warning.line &&
               previous.column == warning.column &&
               previous.message == warning.message {
                duplicate = true
                break
            }
        }
        if duplicate {
            continue
        }
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

ensure_output_parent_dir :: proc(path: string) -> bool {
    dir, _ := os.split_path(path)
    if dir == "" {
        return true
    }
    err := os.make_directory_all(dir)
    if err != nil && err != .Exist {
        fmt.eprintln("failed to create output directory: ", dir)
        return false
    }
    return true
}

absolute_output_path :: proc(path: string) -> (string, bool) {
    if os.is_absolute_path(path) {
        return strings.clone(path), true
    }
    cwd, cwd_err := os.get_absolute_path(".", context.allocator)
    if cwd_err != nil {
        return "", false
    }
    defer delete(cwd)
    joined, join_err := os.join_path({cwd, path}, context.allocator)
    if join_err != nil {
        return "", false
    }
    return joined, true
}

parse_odin_timing_csv :: proc(path: string) {
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        return
    }
    defer delete(data)
    lines := strings.split_lines(string(data), context.allocator)
    defer delete(lines)
    parsed_any := false
    for line in lines {
        if len(line) < 4 || line[0] != '"' {
            continue
        }
        quote_end_offset := strings.index(line[1:], "\"")
        if quote_end_offset < 0 {
            continue
        }
        quote_end := quote_end_offset + 1
        comma := strings.index(line[quote_end+1:], ",")
        if comma < 0 {
            continue
        }
        value_text := strings.trim_space(line[quote_end+1+comma+1:])
        value, ok_value := strconv.parse_f64(value_text)
        if !ok_value {
            continue
        }
        name := line[1:quote_end]
        append(&timing_report.odin.raw, Timing_Phase{name = strings.clone(name), duration_ms = value})
        parsed_any = true
        if name == "Total Time" {
            timing_report.odin.reported_total_ms = value
        } else if name == "initialization" {
            timing_report.odin.initialization_ms += value
        } else if name == "parse files" {
            timing_report.odin.parse_ms += value
        } else if name == "type check" {
            timing_report.odin.type_check_ms += value
        } else if strings.contains(name, "Code Gen") || strings.contains(name, "code gen") {
            timing_report.odin.codegen_ms += value
        } else if strings.contains(name, "link") || strings.contains(name, "Link") {
            timing_report.odin.link_ms += value
        }
    }
    timing_report.odin.detail_available = parsed_any
    known := timing_report.odin.initialization_ms +
             timing_report.odin.parse_ms +
             timing_report.odin.type_check_ms +
             timing_report.odin.codegen_ms +
             timing_report.odin.link_ms
    if timing_report.odin.reported_total_ms > known {
        timing_report.odin.other_ms = timing_report.odin.reported_total_ms - known
    }
}

filter_odin_timing_output :: proc(output: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)
    pending_blank_lines := 0
    last_nonblank_was_timing := false
    for line in lines {
        trimmed := strings.trim_space(line)
        if trimmed == "" {
            pending_blank_lines += 1
            continue
        }
        if strings.has_prefix(trimmed, "Exporting timings to '") ||
           (strings.contains(trimmed, " ms - ") && strings.has_suffix(trimmed, "%")) {
            pending_blank_lines = 0
            last_nonblank_was_timing = true
            continue
        }
        for _ in 0..<pending_blank_lines {
            strings.write_byte(&builder, '\n')
        }
        pending_blank_lines = 0
        last_nonblank_was_timing = false
        strings.write_string(&builder, line)
        strings.write_byte(&builder, '\n')
    }
    if !last_nonblank_was_timing {
        for _ in 1..<pending_blank_lines {
            strings.write_byte(&builder, '\n')
        }
    }
    return strings.clone(strings.to_string(builder))
}

odin_supports_timing_export :: proc() -> bool {
    if odin_timing_support_checked {
        return odin_timing_support_available
    }
    odin_timing_support_checked = true
    state, stdout, stderr, err := os.process_exec(
        os.Process_Desc{command = {"odin", "check", "-help"}},
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)
    if err != nil || !state.exited || state.exit_code != 0 {
        return false
    }
    help := string(stdout)
    if !strings.contains(help, "-export-timings") {
        help = string(stderr)
    }
    odin_timing_support_available = strings.contains(help, "-export-timings") &&
                                    strings.contains(help, "-export-timings-file")
    return odin_timing_support_available
}

run_odin_file :: proc(command, generated_path, source_path, source, eval_source, save_name: string, source_map: []kvist.Source_Map_Entry, extra_args: []string = nil, package_dir := "", binary_output_path := "", artifacts: []kvist.Generated_Package_Artifact = nil) -> int {
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
    collection_args := windows_import_collection_args(generated_abs)
    defer kvist.delete_string_slice(&collection_args)
    for arg in collection_args {
        append(&args, arg)
    }
    for arg in extra_args {
        append(&args, arg)
    }
    timing_temp_dir := ""
    timing_csv_path := ""
    timing_export_arg := ""
    defer {
        if timing_export_arg != "" {
            delete(timing_export_arg)
        }
        if timing_csv_path != "" {
            delete(timing_csv_path)
        }
        if timing_temp_dir != "" {
            _ = os.remove_all(timing_temp_dir)
            delete(timing_temp_dir)
        }
    }
    if timing_started && odin_supports_timing_export() {
        temp_dir, temp_err := os.make_directory_temp("", "kvist-odin-timings-*", context.allocator)
        if temp_err == nil {
            timing_temp_dir = temp_dir
            csv_path, csv_err := os.join_path({temp_dir, "timings.csv"}, context.allocator)
            if csv_err == nil {
                timing_csv_path = csv_path
                timing_export_arg = strings.clone(fmt.tprintf("-export-timings-file:%s", csv_path))
                append(&args, "-show-timings", "-export-timings:csv", timing_export_arg)
            }
        }
    }
    out_path := ""
    out_arg := ""
    remove_out_path := true
    if command == "build" || command == "run" || command == "test" {
        if binary_output_path != "" {
            requested_out_abs, out_abs_ok := absolute_output_path(binary_output_path)
            if !out_abs_ok {
                fmt.eprintln("failed to resolve output path: ", binary_output_path)
                return 1
            }
            if !ensure_output_parent_dir(requested_out_abs) {
                delete(requested_out_abs)
                return 1
            }
            out_path = requested_out_abs
            remove_out_path = false
        } else {
            out_path = odin_output_executable_path(generated_abs)
        }
        out_arg = strings.clone(fmt.tprintf("-out:%s", out_path))
        append(&args, out_arg)
    }
    defer cleanup_odin_output_arg(out_path, out_arg, remove_out_path)
    odin_start := timing_phase_start()
    state, stdout, stderr, err := os.process_exec(
        os.Process_Desc{command = args[:], working_dir = working_dir},
        context.allocator,
    )
    defer delete(stdout)
    defer delete(stderr)
    if timing_started {
        timing_report.odin.process_ms += duration_ms(odin_start)
        if timing_csv_path != "" {
            parse_odin_timing_csv(timing_csv_path)
        }
    }

    if len(stdout) > 0 {
        if timing_started {
            filtered_stdout := filter_odin_timing_output(string(stdout))
            fmt.print(filtered_stdout)
            delete(filtered_stdout)
        } else {
            fmt.print(string(stdout))
        }
    }
    diagnostic_maps := kvist.Package_Emit_Result{}
    diagnostic_maps_loaded := false
    if len(stderr) > 0 && len(source_map) == 0 && deferred_package_maps_path != "" {
        diagnostic_maps, diagnostic_maps_loaded = load_package_compile_cache_maps(
            deferred_package_maps_path,
        )
    }
    defer if diagnostic_maps_loaded {
        kvist.package_emit_result_delete(&diagnostic_maps)
    }
    if len(stderr) > 0 {
        odin_stderr := string(stderr)
        filtered_stderr := ""
        if timing_started {
            filtered_stderr = filter_odin_timing_output(odin_stderr)
            odin_stderr = filtered_stderr
        }
        defer if filtered_stderr != "" {
            delete(filtered_stderr)
        }
        mapped_stderr := strings.clone(odin_stderr)
        diagnostic_artifacts := artifacts
        diagnostic_source_map := source_map
        if diagnostic_maps_loaded {
            diagnostic_artifacts = diagnostic_maps.artifacts[:]
            diagnostic_source_map = diagnostic_maps.root.source_map[:]
        }
        for artifact in diagnostic_artifacts {
            next := remap_odin_output_locations(
                mapped_stderr,
                artifact.id,
                source_path,
                source,
                eval_source,
                artifact.source_map[:],
            )
            delete(mapped_stderr)
            mapped_stderr = next
        }
        root_mapped := remap_odin_output_locations(
            mapped_stderr,
            generated_abs,
            source_path,
            source,
            eval_source,
            diagnostic_source_map,
        )
        delete(mapped_stderr)
        mapped_stderr = root_mapped
        defer delete(mapped_stderr)
        fmt.eprint(mapped_stderr)
    }
    if err != nil {
        fmt.eprintln("failed to run odin ", odin_command)
        return 1
    }
    if state.exited {
        if command == "run" && state.exit_code == 0 {
            execution_start := timing_phase_start()
            run_state, run_stdout, run_stderr, run_err := os.process_exec(
                os.Process_Desc{command = {out_path}, working_dir = working_dir},
                context.allocator,
            )
            defer delete(run_stdout)
            defer delete(run_stderr)
            if timing_started {
                timing_report.execution_ms += duration_ms(execution_start)
            }

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

source_dir_has_odin_files :: proc(source_path: string) -> bool {
    source_dir, _ := os.split_path(source_path)
    if source_dir == "" {
        source_dir = "."
    }
    entries, err := os.read_directory_by_path(source_dir, -1, context.allocator)
    if err != nil {
        return false
    }
    defer os.file_info_slice_delete(entries, context.allocator)
    has_odin_file := false
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
        has_odin_file = true
    }
    return has_odin_file
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

replace_generated_package_placeholders :: proc(
    output: string,
    dependencies: []string,
    import_prefix: string,
) -> string {
    current := strings.clone(output)
    for dependency in dependencies {
        placeholder := fmt.tprintf("__KVIST_PACKAGE_%s__", dependency)
        replacement := fmt.tprintf("%s/%s", import_prefix, dependency)
        replaced, allocated := strings.replace_all(current, placeholder, replacement, context.allocator)
        if allocated {
            delete(current)
            current = replaced
        }
    }
    return current
}

write_generated_package_artifacts :: proc(
    artifacts: []kvist.Generated_Package_Artifact,
    artifact_root: string,
) -> bool {
    if len(artifacts) == 0 {
        return true
    }
    if os.make_directory_all(artifact_root) != nil && !os.exists(artifact_root) {
        return false
    }
    for artifact in artifacts {
        dir, dir_err := os.join_path({artifact_root, artifact.id}, context.allocator)
        if dir_err != nil {
            return false
        }
        if os.make_directory_all(dir) != nil && !os.exists(dir) {
            delete(dir)
            return false
        }
        artifact_path, path_err := os.join_path({dir, "package.odin"}, context.allocator)
        delete(dir)
        if path_err != nil {
            return false
        }
        qualified := replace_generated_package_placeholders(
            artifact.output,
            artifact.dependencies[:],
            "..",
        )
        rebased, rebase_err, rebase_ok := kvist.rebase_emitted_odin_imports_for_output_path(
            qualified,
            artifact_path,
        )
        delete(qualified)
        if !rebase_ok {
            fmt.eprintln(rebase_err.message)
            delete(artifact_path)
            return false
        }
        write_ok := os.write_entire_file_from_string(artifact_path, rebased) == nil
        delete(rebased)
        delete(artifact_path)
        if !write_ok {
            return false
        }
    }
    return true
}

write_generated_for_execution :: proc(
    output, requested_path, source_path: string,
    artifacts: []kvist.Generated_Package_Artifact = nil,
) -> (path, temp_dir, package_dir: string, ok: bool) {
    if requested_path != "" {
        requested_dir, requested_name := os.split_path(requested_path)
        if requested_dir == "" {
            requested_dir = "."
        }
        artifact_name := fmt.tprintf("%s.packages", requested_name)
        artifact_root, artifact_root_err := os.join_path(
            {requested_dir, artifact_name},
            context.allocator,
        )
        if artifact_root_err != nil ||
           !write_generated_package_artifacts(artifacts, artifact_root) {
            if artifact_root_err == nil {
                delete(artifact_root)
            }
            fmt.eprintln("failed to write generated package artifacts")
            return "", "", "", false
        }
        defer delete(artifact_root)
        dependencies: [dynamic]string
        for artifact in artifacts {
            append(&dependencies, artifact.id)
        }
        qualified := replace_generated_package_placeholders(
            output,
            dependencies[:],
            artifact_name,
        )
        delete(dependencies)
        rebased, err_rebase, ok_rebase := kvist.rebase_emitted_odin_imports_for_output_path(qualified, requested_path)
        delete(qualified)
        if !ok_rebase {
            fmt.eprintln(err_rebase.message)
            return "", "", "", false
        }
        write_output_or_exit(requested_path, rebased)
        delete(rebased)
        return requested_path, "", "", true
    }

    if source_dir_has_odin_files(source_path) {
        generated, package_build_dir, path_ok := temporary_generated_path_in_source_dir(source_path)
        if !path_ok {
            fmt.eprintln("failed to create temporary generated path in source package")
            return "", "", "", false
        }
        generated_dir, generated_name := os.split_path(generated)
        artifact_name := fmt.tprintf("%s.packages", generated_name)
        artifact_root, artifact_root_err := os.join_path(
            {generated_dir, artifact_name},
            context.allocator,
        )
        if artifact_root_err != nil ||
           !write_generated_package_artifacts(artifacts, artifact_root) {
            if artifact_root_err == nil {
                delete(artifact_root)
            }
            delete(generated)
            delete(package_build_dir)
            fmt.eprintln("failed to write generated package artifacts")
            return "", "", "", false
        }
        dependencies: [dynamic]string
        for artifact in artifacts {
            append(&dependencies, artifact.id)
        }
        qualified := replace_generated_package_placeholders(
            output,
            dependencies[:],
            artifact_name,
        )
        delete(dependencies)
        rebased, err_rebase, ok_rebase := kvist.rebase_emitted_odin_imports_for_output_path(qualified, generated)
        delete(qualified)
        if !ok_rebase {
            fmt.eprintln(err_rebase.message)
            delete(generated)
            delete(package_build_dir)
            _ = os.remove_all(artifact_root)
            delete(artifact_root)
            return "", "", "", false
        }
        write_output_or_exit(generated, rebased)
        delete(rebased)
        return generated, artifact_root, package_build_dir, true
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

    artifact_root, artifact_root_err := os.join_path({dir, "kvist-packages"}, context.allocator)
    if artifact_root_err != nil ||
       !write_generated_package_artifacts(artifacts, artifact_root) {
        if artifact_root_err == nil {
            delete(artifact_root)
        }
        _ = os.remove_all(dir)
        delete(generated)
        delete(dir)
        fmt.eprintln("failed to write generated package artifacts")
        return "", "", "", false
    }
    defer delete(artifact_root)
    dependencies: [dynamic]string
    for artifact in artifacts {
        append(&dependencies, artifact.id)
    }
    qualified := replace_generated_package_placeholders(
        output,
        dependencies[:],
        "kvist-packages",
    )
    delete(dependencies)
    rebased, err_rebase, ok_rebase := kvist.rebase_emitted_odin_imports_for_output_path(qualified, generated)
    delete(qualified)
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
            _ = os.remove_all(temp_dir)
            delete(temp_dir)
        }
    }
    if package_dir != "" {
        delete(package_dir)
    }
}
