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

Timing_Phase :: struct {
    name:        string,
    duration_ms: f64,
}

Odin_Timing_Report :: struct {
    detail_available: bool,
    process_ms:       f64,
    reported_total_ms: f64,
    initialization_ms: f64,
    parse_ms:          f64,
    type_check_ms:     f64,
    codegen_ms:        f64,
    link_ms:           f64,
    other_ms:          f64,
    raw:               [dynamic]Timing_Phase,
}

Timing_Report :: struct {
    schema_version:           int,
    command:                  string,
    input:                    string,
    success:                  bool,
    total_ms:                 f64,
    cache_status:             string,
    fingerprint_cache_status: string,
    fingerprint_files_reused: int,
    fingerprint_files_hashed: int,
    packages_reused:          int,
    packages_emitted:         int,
    dependency_discovery_ms:  f64,
    cache_fingerprint_ms:     f64,
    cache_io_ms:              f64,
    cache_publish_ms:         f64,
    frontend_ms:              f64,
    frontend:                 [dynamic]Timing_Phase `json:",omitempty"`,
    generated_output_ms:      f64,
    odin:                     Odin_Timing_Report,
    execution_ms:             f64,
}

timings_human_enabled: bool
timings_json_path: string
timing_started: bool
timing_reported: bool
timing_start: time.Tick
timing_report: Timing_Report
timing_compile_profile: kvist.Compile_Profile
odin_timing_support_checked: bool
odin_timing_support_available: bool
deferred_package_maps_path: string

duration_ms :: proc(start: time.Tick) -> f64 {
    return f64(time.duration_nanoseconds(time.tick_since(start))) / 1_000_000.0
}

timing_phase_start :: proc() -> time.Tick {
    if timing_started {
        return time.tick_now()
    }
    return {}
}

ns_ms :: proc(value: i64) -> f64 {
    return f64(value) / 1_000_000.0
}

timings_enabled :: proc() -> bool {
    return timings_human_enabled || timings_json_path != ""
}

timing_begin :: proc(command, input: string) {
    if !timings_enabled() || timing_started {
        return
    }
    timing_started = true
    timing_start = time.tick_now()
    timing_report = Timing_Report{
        schema_version = 1,
        command = command,
        input = input,
        cache_status = "not-used",
    }
}

print_timing_line :: proc(label: string, millis: f64) {
    if millis > 0 {
        fmt.eprintf("  %-30s %.3f ms\n", label, millis)
    }
}

write_timing_json :: proc(path: string, report: Timing_Report) -> bool {
    bytes, marshal_err := json.marshal(report)
    if marshal_err != nil {
        fmt.eprintln("failed to encode timing JSON")
        return false
    }
    defer delete(bytes)
    parent, _ := os.split_path(path)
    if parent == "" {
        parent = "."
    }
    temp_dir, temp_err := os.make_directory_temp(parent, ".kvist-timings-*", context.allocator)
    if temp_err != nil {
        fmt.eprintln("failed to create timing JSON temporary directory")
        return false
    }
    defer {
        _ = os.remove_all(temp_dir)
        delete(temp_dir)
    }
    temp_path, join_err := os.join_path({temp_dir, "timings.json"}, context.allocator)
    if join_err != nil {
        fmt.eprintln("failed to create timing JSON temporary path")
        return false
    }
    defer delete(temp_path)
    if os.write_entire_file(temp_path, bytes) != nil || os.rename(temp_path, path) != nil {
        fmt.eprintln("failed to write timing JSON: ", path)
        return false
    }
    return true
}

timing_finish :: proc(status: int) -> int {
    if !timing_started || timing_reported {
        return status
    }
    timing_reported = true
    timing_report.success = status == 0
    timing_report.total_ms = duration_ms(timing_start)
    if timing_report.frontend_ms > 0 {
        append(&timing_report.frontend, Timing_Phase{name = "reading_and_resolution", duration_ms = ns_ms(timing_compile_profile.load_and_resolve_ns)})
        append(&timing_report.frontend, Timing_Phase{name = "macro_expansion", duration_ms = ns_ms(timing_compile_profile.macro_expansion_ns)})
        append(&timing_report.frontend, Timing_Phase{name = "post_expand_resolution", duration_ms = ns_ms(timing_compile_profile.post_expand_resolution_ns)})
        append(&timing_report.frontend, Timing_Phase{name = "ast_parse", duration_ms = ns_ms(timing_compile_profile.ast_parse_ns)})
        append(&timing_report.frontend, Timing_Phase{name = "lowering", duration_ms = ns_ms(timing_compile_profile.lowering_ns)})
        append(&timing_report.frontend, Timing_Phase{name = "analysis", duration_ms = ns_ms(timing_compile_profile.analysis_ns)})
        append(&timing_report.frontend, Timing_Phase{name = "emission", duration_ms = ns_ms(timing_compile_profile.emission_ns + timing_compile_profile.analysis_and_emission_ns)})
        append(&timing_report.frontend, Timing_Phase{name = "source_map", duration_ms = ns_ms(timing_compile_profile.source_map_ns)})
    }
    if timings_human_enabled {
        fmt.eprintf("Kvist timings (%s, %s)\n", timing_report.command, "success" if status == 0 else "failure")
        print_timing_line("dependency discovery", timing_report.dependency_discovery_ms)
        print_timing_line("cache fingerprint", timing_report.cache_fingerprint_ms)
        print_timing_line("cache I/O", timing_report.cache_io_ms)
        print_timing_line("cache publish", timing_report.cache_publish_ms)
        fmt.eprintf(
            "  generated packages: %d reused, %d emitted\n",
            timing_report.packages_reused,
            timing_report.packages_emitted,
        )
        print_timing_line("frontend total", timing_report.frontend_ms)
        print_timing_line("  reading + resolution", ns_ms(timing_compile_profile.load_and_resolve_ns))
        print_timing_line("  macro expansion", ns_ms(timing_compile_profile.macro_expansion_ns))
        print_timing_line("  post-expand resolution", ns_ms(timing_compile_profile.post_expand_resolution_ns))
        print_timing_line("  AST parse", ns_ms(timing_compile_profile.ast_parse_ns))
        print_timing_line("  lowering", ns_ms(timing_compile_profile.lowering_ns))
        print_timing_line("  analysis", ns_ms(timing_compile_profile.analysis_ns))
        print_timing_line("  emission", ns_ms(timing_compile_profile.emission_ns + timing_compile_profile.analysis_and_emission_ns))
        print_timing_line("  source maps", ns_ms(timing_compile_profile.source_map_ns))
        print_timing_line("generated output", timing_report.generated_output_ms)
        print_timing_line("Odin process", timing_report.odin.process_ms)
        if timing_report.odin.detail_available {
            print_timing_line("  Odin initialization", timing_report.odin.initialization_ms)
            print_timing_line("  Odin parse", timing_report.odin.parse_ms)
            print_timing_line("  Odin type check", timing_report.odin.type_check_ms)
            print_timing_line("  Odin codegen", timing_report.odin.codegen_ms)
            print_timing_line("  Odin link", timing_report.odin.link_ms)
            print_timing_line("  Odin other", timing_report.odin.other_ms)
        }
        print_timing_line("program execution", timing_report.execution_ms)
        fmt.eprintf("  %-30s %.3f ms\n", "total", timing_report.total_ms)
        fmt.eprintln("  cache status: ", timing_report.cache_status)
        if timing_report.fingerprint_cache_status != "" {
            fmt.eprintf(
                "  fingerprint cache: %s (%d reused, %d hashed)\n",
                timing_report.fingerprint_cache_status,
                timing_report.fingerprint_files_reused,
                timing_report.fingerprint_files_hashed,
            )
        }
    }
    if timings_json_path != "" && !write_timing_json(timings_json_path, timing_report) && status == 0 {
        return 1
    }
    return status
}

exit_with_timing :: proc(code: int) {
    os.exit(timing_finish(code))
}

parse_timing_arg :: proc(i: ^int) -> bool {
    if os.args[i^] == "--timings" {
        timings_human_enabled = true
        i^ += 1
        return true
    }
    if os.args[i^] == "--timings-json" {
        if i^+1 >= len(os.args) {
            print_usage()
            exit_with_timing(2)
        }
        timings_json_path = os.args[i^+1]
        i^ += 2
        return true
    }
    return false
}
