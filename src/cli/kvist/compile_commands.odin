package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"
import kvist "../../odin/kvist"

compile_file_command :: proc(input, output_path, map_path: string) {
    // `compile` exposes warnings and source maps, so preserve the complete
    // compiler result. The execution cache intentionally stores only emitted
    // Odin and is reserved for build/check/run/test commands.
    result, err, ok := compile_path_for_command(input)
    if !ok {
        data := read_source_or_exit(input)
        formatted := kvist.format_compile_error(input, data, err)
        fmt.eprint(formatted)
        delete(formatted)
        delete(transmute([]byte)data)
        exit_with_timing(1)
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    if len(result.warnings) > 0 {
        data := read_source_or_exit(input)
        defer delete(transmute([]byte)data)
        print_compile_warnings(input, data, "", result.warnings[:])
    }

    generated_start := timing_phase_start()
    defer if timing_started {
        timing_report.generated_output_ms += duration_ms(generated_start)
    }
    if output_path != "" {
        output, err_rebase, ok_rebase := kvist.rebase_emitted_odin_imports_for_output_path(result.output, output_path)
        if !ok_rebase {
            fmt.eprintln(err_rebase.message)
            exit_with_timing(1)
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

compile_package_file_command :: proc(input, output_path, map_path: string) {
    if output_path == "" {
        fmt.eprintln("--packages requires -o because package artifacts cannot be written to stdout")
        exit_with_timing(2)
    }
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)
    result, err, ok := compile_package_path_for_command(input)
    if !ok {
        formatted := kvist.format_compile_error(input, data, err)
        fmt.eprint(formatted)
        delete(formatted)
        exit_with_timing(1)
    }
    defer kvist.package_emit_result_delete(&result)
    print_compile_warnings(input, data, "", result.root.warnings[:])
    for artifact in result.artifacts {
        print_compile_warnings(input, data, "", artifact.warnings[:])
    }
    generated_start := timing_phase_start()
    defer if timing_started {
        timing_report.generated_output_ms += duration_ms(generated_start)
    }
    _, _, _, write_ok := write_generated_for_execution(
        result.root.output,
        output_path,
        input,
        result.artifacts[:],
    )
    if !write_ok {
        exit_with_timing(1)
    }
    if map_path == "" {
        return
    }
    root_map := kvist.format_source_map(result.root.source_map[:])
    write_output_or_exit(map_path, root_map)
    delete(root_map)
    map_artifact_dir := fmt.tprintf("%s.packages", map_path)
    if os.make_directory_all(map_artifact_dir) != nil && !os.exists(map_artifact_dir) {
        fmt.eprintln("failed to create package source-map directory: ", map_artifact_dir)
        exit_with_timing(1)
    }
    for artifact in result.artifacts {
        artifact_map_path, join_err := os.join_path(
            {map_artifact_dir, fmt.tprintf("%s.map", artifact.id)},
            context.allocator,
        )
        if join_err != nil {
            fmt.eprintln("failed to create package source-map path")
            exit_with_timing(1)
        }
        artifact_map := kvist.format_source_map(artifact.source_map[:])
        write_output_or_exit(artifact_map_path, artifact_map)
        delete(artifact_map)
        delete(artifact_map_path)
    }
}

compile_eval_emit_command :: proc(input, eval_source, output_path: string, no_print: bool) {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    result, err, ok := compile_eval_path_for_command(input, eval_source, no_print)
    if !ok {
        formatted := kvist.format_eval_compile_error(input, data, eval_source, err)
        fmt.eprint(formatted)
        delete(formatted)
        exit_with_timing(1)
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    print_compile_warnings(input, data, eval_source, result.warnings[:])

    generated_start := timing_phase_start()
    defer if timing_started {
        timing_report.generated_output_ms += duration_ms(generated_start)
    }
    if output_path != "" {
        output, err_rebase, ok_rebase := kvist.rebase_emitted_odin_imports_for_output_path(result.output, output_path)
        if !ok_rebase {
            fmt.eprintln(err_rebase.message)
            exit_with_timing(1)
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
        exit_with_timing(1)
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)

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

run_generated_command :: proc(input, generated_path, odin_command: string, binary_output_path := "") -> int {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    result, err, ok := compile_package_path_with_execution_cache(input)
    if !ok {
        formatted := kvist.format_compile_error(input, data, err)
        fmt.eprint(formatted)
        delete(formatted)
        exit_with_timing(1)
    }
    defer kvist.package_emit_result_delete(&result)

    print_compile_warnings(input, data, "", result.root.warnings[:])
    for artifact in result.artifacts {
        print_compile_warnings(input, data, "", artifact.warnings[:])
    }
    generated_start := timing_phase_start()
    path, temp_dir, package_dir, path_ok := write_generated_for_execution(
        result.root.output,
        generated_path,
        input,
        result.artifacts[:],
    )
    if timing_started {
        timing_report.generated_output_ms += duration_ms(generated_start)
    }
    if !path_ok {
        return 1
    }
    defer cleanup_generated(path, temp_dir, generated_path, package_dir)

    return run_odin_file(
        odin_command,
        path,
        input,
        data,
        "",
        "",
        result.root.source_map[:],
        package_dir = package_dir,
        binary_output_path = binary_output_path,
        artifacts = result.artifacts[:],
    )
}

frontend_check_command :: proc(input: string) -> int {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    result, err, ok := compile_path_with_execution_cache(input)
    if !ok {
        formatted := kvist.format_compile_error(input, data, err)
        defer delete(formatted)
        fmt.eprint(formatted)
        return 1
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)
    print_compile_warnings(input, data, "", result.warnings[:])
    return 0
}

test_command :: proc(input, generated_path, test_names: string, track_memory: bool) -> int {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    result, err, ok := compile_package_path_with_execution_cache(input)
    if !ok {
        formatted := kvist.format_compile_error(input, data, err)
        fmt.eprint(formatted)
        delete(formatted)
        exit_with_timing(1)
    }
    defer kvist.package_emit_result_delete(&result)

    print_compile_warnings(input, data, "", result.root.warnings[:])
    for artifact in result.artifacts {
        print_compile_warnings(input, data, "", artifact.warnings[:])
    }
    generated_start := timing_phase_start()
    path, temp_dir, package_dir, path_ok := write_generated_for_execution(
        result.root.output,
        generated_path,
        input,
        result.artifacts[:],
    )
    if timing_started {
        timing_report.generated_output_ms += duration_ms(generated_start)
    }
    if !path_ok {
        return 1
    }
    defer cleanup_generated(path, temp_dir, generated_path, package_dir)

    extra_args := make([dynamic]string, 0, 4)
    defer delete(extra_args)
    // Odin's threaded checker still intermittently asserts while
    // instantiating generic queues in otherwise valid generated test
    // programs. A test command must be deterministic; compilation speed is
    // secondary to running the requested suite reliably.
    append(&extra_args, "-no-threaded-checker")
    append(&extra_args, "-define:ODIN_TEST_THREADS=1")
    append(&extra_args, fmt.tprintf("-define:ODIN_TEST_TRACK_MEMORY=%s", "true" if track_memory else "false"))
    append(&extra_args, fmt.tprintf("-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=%s", "true" if track_memory else "false"))
    if test_names != "" {
        normalized_test_names := normalize_test_names_arg(test_names)
        defer delete(normalized_test_names)
        append(&extra_args, fmt.tprintf("-define:ODIN_TEST_NAMES=%s", normalized_test_names))
    }

    return run_odin_file(
        "test",
        path,
        input,
        data,
        "",
        "",
        result.root.source_map[:],
        extra_args[:],
        package_dir,
        artifacts = result.artifacts[:],
    )
}

eval_command :: proc(input, eval_source, generated_path, save_name: string, no_print, check_only: bool) -> int {
    if check_only && save_name != "" {
        fmt.eprintln("--save cannot be used with --check")
        return 2
    }
    if !no_print && !check_only && strings.trim_space(eval_source) == "(main)" {
        data := read_source_or_exit(input)
        defer delete(transmute([]byte)data)

        result, err, ok := compile_path_for_command(input)
        if !ok {
            formatted := kvist.format_compile_error(input, data, err)
            fmt.eprint(formatted)
            delete(formatted)
            exit_with_timing(1)
        }
        defer delete(result.output)
        defer kvist.source_map_slice_delete(result.source_map)

        generated_start := timing_phase_start()
        path, temp_dir, package_dir, path_ok := write_generated_for_execution(result.output, generated_path, input)
        if timing_started {
            timing_report.generated_output_ms += duration_ms(generated_start)
        }
        if !path_ok {
            return 1
        }
        defer cleanup_generated(path, temp_dir, generated_path, package_dir)

        return run_odin_file("run", path, input, data, "", save_name, result.source_map[:], package_dir = package_dir)
    }

    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    result, err, ok := compile_eval_path_for_command(input, eval_source, no_print)
    if !ok {
        formatted := kvist.format_eval_compile_error(input, data, eval_source, err)
        fmt.eprint(formatted)
        delete(formatted)
        exit_with_timing(1)
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    print_compile_warnings(input, data, eval_source, result.warnings[:])
    generated_start := timing_phase_start()
    path, temp_dir, package_dir, path_ok := write_generated_for_execution(result.output, generated_path, input)
    if timing_started {
        timing_report.generated_output_ms += duration_ms(generated_start)
    }
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
