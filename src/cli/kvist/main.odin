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

CACHE_DIR :: ".kvist-cache"
COMPILE_CACHE_VERSION :: "kvist-compile-cache-v5"

ownership_audit_enabled: bool
explain_cache_enabled: bool

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

print_usage :: proc() {
    fmt.println("usage:")
    fmt.println("  kvist <input.kvist> [-o output.odin] [--map output.map] [--eval form] [--no-print] [--timings] [--timings-json path]")
    fmt.println("  kvist compile <input.kvist> [-o output.odin] [--map output.map] [--packages] [--ownership-audit] [--timings] [--timings-json path]")
    fmt.println("  kvist dev --reload <input.kvist> [--rebuild] [--watch] [--generated-dir dir] [--print-paths] [--json]")
    fmt.println("  kvist build <input.kvist> [--out output-binary] [--generated output.odin] [--reload] [--generated-dir dir] [--ownership-audit] [--explain-cache] [--timings] [--timings-json path]")
    fmt.println("  kvist check <input.kvist> [--generated output.odin] [--reload] [--generated-dir dir] [--ownership-audit] [--explain-cache] [--timings] [--timings-json path]")
    fmt.println("  kvist frontend-check <input.kvist> [--ownership-audit] [--explain-cache] [--timings] [--timings-json path]")
    fmt.println("  kvist run <input.kvist> [--generated output.odin] [--reload] [--generated-dir dir] [--ownership-audit] [--explain-cache] [--timings] [--timings-json path]")
    fmt.println("  kvist test <input.kvist> [--generated output.odin] [--names test1,test2] [--track-memory] [--ownership-audit] [--explain-cache] [--timings] [--timings-json path]")
    fmt.println("  kvist eval <input.kvist> <form> [--no-print] [--check] [--generated output.odin] [--save name] [--ownership-audit] [--timings] [--timings-json path]")
    fmt.println("  kvist expand <input.kvist> <form> [--no-print] [-o output.odin]")
    fmt.println("  kvist macroexpand <input.kvist> <form> [-o output.kvist] [--map output.map]")
    fmt.println("  kvist symbols <input.kvist>")
    fmt.println("  kvist lifetimes <input.kvist>")
    fmt.println("  kvist editor-symbols <input.kvist> [identifier]")
    fmt.println("  kvist lookup <input.kvist> <identifier>")
    fmt.println("  kvist complete <input.kvist> [prefix]")
    fmt.println("  kvist doc <input.kvist> <identifier>")
    fmt.println("  kvist xref <input.kvist> <identifier>")
    fmt.println("  kvist builtin-symbols")
    fmt.println("  kvist imported-symbols <input.kvist>")
    fmt.println("  kvist package-symbols <import-path> [alias]")
    fmt.println("  kvist root")
    fmt.println("  kvist cache path <name>")
    fmt.println("  kvist cache list")
    fmt.println("  kvist cache rm <name>")
    fmt.println("  kvist cache inspect")
    fmt.println("  kvist cache clear [input.kvist]")
}

is_help_arg :: proc(text: string) -> bool {
    return text == "help" || text == "--help" || text == "-h"
}

is_command :: proc(text: string) -> bool {
    return is_help_arg(text) || text == "compile" || text == "dev" || text == "build" || text == "check" || text == "frontend-check" || text == "run" || text == "test" || text == "eval" || text == "expand" || text == "macroexpand" || text == "symbols" || text == "lifetimes" || text == "editor-symbols" || text == "lookup" || text == "complete" || text == "doc" || text == "xref" || text == "builtin-symbols" || text == "imported-symbols" || text == "package-symbols" || text == "root" || text == "cache"
}

root_command :: proc() {
    if len(os.args) != 2 {
        fmt.eprintln("usage: kvist root")
        exit_with_timing(2)
    }
    roots := kvist.kvist_source_package_roots()
    defer kvist.delete_string_slice(&roots)
    if len(roots) == 0 {
        fmt.eprintln("could not resolve Kvist package root")
        exit_with_timing(1)
    }
    fmt.println(roots[0])
}

read_source_or_exit :: proc(path: string) -> string {
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        fmt.eprintln("could not read file: ", path)
        exit_with_timing(1)
    }
    return string(data)
}

write_output_or_exit :: proc(path, output: string) {
    write_err := os.write_entire_file_from_string(path, output)
    if write_err != nil {
        fmt.eprintln("failed to write output: ", path)
        exit_with_timing(1)
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
        exit_with_timing(2)
    }
    path, join_err := os.join_path({dir, name}, context.allocator)
    if join_err != nil {
        fmt.eprintln("failed to build cache path")
        exit_with_timing(1)
    }
    return path
}

ensure_cache_dir_or_exit :: proc(dir: string) {
    err := os.make_directory_all(dir)
    if err != nil {
        fmt.eprintln("failed to create cache directory: ", dir)
        exit_with_timing(1)
    }
}

fnv1a_update :: proc(hash: u64, bytes: []byte) -> u64 {
    out := hash
    for value in bytes {
        out = (out ~ u64(value)) * 1099511628211
    }
    return out
}

compile_cache_disabled :: proc() -> bool {
    value, found := os.lookup_env("KVIST_NO_COMPILE_CACHE", context.allocator)
    if !found {
        return false
    }
    defer delete(value)
    return value != "" && value != "0" && value != "false"
}

explain_compile_cache :: proc(input, key, output_path, status: string) {
    if !explain_cache_enabled {
        return
    }
    fmt.eprintf("cache: %s\n  key: %s\n  entry: %s\n  input: %s\n", status, key, output_path, input)
    dependencies, _, dependencies_ok := kvist.source_dependency_paths(input)
    if dependencies_ok {
        defer kvist.delete_string_slice(&dependencies)
        fmt.eprintln("  inputs:")
        for dependency in dependencies {
            fmt.eprintln("    ", dependency)
        }
    }
}

compile_cache_key :: proc(input: string) -> (key: string, ok: bool) {
    return cached_compile_cache_key(input)
}

compile_path_for_command :: proc(input: string) -> (result: kvist.Emit_Result, err: kvist.Compile_Error, ok: bool) {
    if !timing_started {
        return kvist.compile_path_with_map(input)
    }
    start := time.tick_now()
    result, err, ok = kvist.compile_path_with_map(input, &timing_compile_profile)
    timing_report.frontend_ms += duration_ms(start)
    return
}

package_frontend_cache_dir :: proc() -> string {
    base := cache_dir_or_exit()
    defer delete(base)
    executable, executable_err := os.get_executable_path(context.allocator)
    if executable_err != nil {
        return ""
    }
    defer delete(executable)
    content_hash, hash_ok := hash_file_content(executable)
    if !hash_ok {
        return ""
    }
    compiler_name := fmt.tprintf("%016x", content_hash)
    parent, parent_err := os.join_path(
        {base, "package-frontend"},
        context.allocator,
    )
    if parent_err != nil {
        return ""
    }
    defer delete(parent)
    if !os.exists(parent) && os.make_directory_all(parent) != nil {
        return ""
    }
    dir, dir_err := os.join_path(
        {parent, compiler_name},
        context.allocator,
    )
    if dir_err != nil {
        return ""
    }
    if !os.exists(dir) && os.make_directory_all(dir) != nil {
        delete(dir)
        return ""
    }
    now := time.now()
    _ = os.change_times(dir, now, now)
    prune_cache_entries(parent, PACKAGE_FRONTEND_COMPILER_LIMIT, ".kvist-package-")
    return dir
}

compile_package_path_for_command :: proc(input: string) -> (result: kvist.Package_Emit_Result, err: kvist.Compile_Error, ok: bool) {
    artifact_cache_dir := ""
    if !compile_cache_disabled() {
        artifact_cache_dir = package_frontend_cache_dir()
    }
    defer if artifact_cache_dir != "" {
        delete(artifact_cache_dir)
    }
    if !timing_started {
        result, err, ok = kvist.compile_path_with_package_artifacts(
            input,
            cache_dir = artifact_cache_dir,
        )
    } else {
        start := time.tick_now()
        result, err, ok = kvist.compile_path_with_package_artifacts(
            input,
            &timing_compile_profile,
            artifact_cache_dir,
        )
        timing_report.frontend_ms += duration_ms(start)
        timing_report.packages_reused += result.packages_reused
        timing_report.packages_emitted += result.packages_emitted
    }
    if artifact_cache_dir != "" {
        prune_cache_entries(
            artifact_cache_dir,
            PACKAGE_FRONTEND_ENTRY_LIMIT,
            ".kvist-package-",
        )
    }
    return
}

compile_eval_path_for_command :: proc(input, eval_source: string, no_print: bool) -> (result: kvist.Emit_Result, err: kvist.Compile_Error, ok: bool) {
    if !timing_started {
        return kvist.compile_eval_path_with_map(input, eval_source, no_print)
    }
    start := time.tick_now()
    result, err, ok = kvist.compile_eval_path_with_map(input, eval_source, no_print, &timing_compile_profile)
    timing_report.frontend_ms += duration_ms(start)
    return
}

Compile_Cache_Metadata :: struct {
    source_map: [dynamic]kvist.Source_Map_Entry,
    warnings:   [dynamic]kvist.Compile_Warning,
}

compile_cache_paths :: proc(key: string) -> (output_path, metadata_path: string, ok: bool) {
    base := cache_dir_or_exit()
    defer delete(base)
    dir, dir_err := os.join_path({base, "compile"}, context.allocator)
    if dir_err != nil {
        return "", "", false
    }
    defer delete(dir)
    if !os.exists(dir) {
        if os.make_directory_all(dir) != nil {
            return "", "", false
        }
    }
    name := fmt.tprintf("%s.odin", key)
    path_err: os.Error
    output_path, path_err = os.join_path({dir, name}, context.allocator)
    if path_err != nil {
        return "", "", false
    }
    metadata_name := fmt.tprintf("%s.json", key)
    metadata_err: os.Error
    metadata_path, metadata_err = os.join_path({dir, metadata_name}, context.allocator)
    if metadata_err != nil {
        delete(output_path)
        return "", "", false
    }
    return output_path, metadata_path, true
}

delete_compile_cache_metadata :: proc(metadata: ^Compile_Cache_Metadata) {
    kvist.source_map_slice_delete(metadata.source_map)
    kvist.compile_warning_slice_delete(metadata.warnings)
    metadata^ = {}
}

publish_compile_cache_result :: proc(output_path, metadata_path: string, result: kvist.Emit_Result) {
    dir, _ := os.split_path(output_path)
    temp_dir, temp_err := os.make_directory_temp(dir, ".kvist-compile-*", context.allocator)
    if temp_err != nil {
        return
    }
    defer {
        _ = os.remove_all(temp_dir)
        delete(temp_dir)
    }
    temp_output_path, output_join_err := os.join_path({temp_dir, "output.odin"}, context.allocator)
    if output_join_err != nil {
        return
    }
    defer delete(temp_output_path)
    temp_metadata_path, metadata_join_err := os.join_path({temp_dir, "metadata.json"}, context.allocator)
    if metadata_join_err != nil {
        return
    }
    defer delete(temp_metadata_path)
    metadata := Compile_Cache_Metadata{
        source_map = result.source_map,
        warnings = result.warnings,
    }
    metadata_bytes, marshal_err := json.marshal(metadata)
    if marshal_err != nil {
        return
    }
    defer delete(metadata_bytes)
    if os.write_entire_file_from_string(temp_output_path, result.output) != nil ||
       os.write_entire_file(temp_metadata_path, metadata_bytes) != nil {
        return
    }
    // Metadata is published first and output last. The output is the
    // completion marker, so readers never accept a partially published entry.
    // Concurrent compilers may race, but content-addressed entries are equal.
    _ = os.rename(temp_metadata_path, metadata_path)
    _ = os.rename(temp_output_path, output_path)
}

compile_path_with_execution_cache :: proc(input: string) -> (result: kvist.Emit_Result, err: kvist.Compile_Error, ok: bool) {
    if compile_cache_disabled() {
        timing_report.cache_status = "disabled"
        if explain_cache_enabled {
            fmt.eprintln("cache: disabled by KVIST_NO_COMPILE_CACHE")
        }
        return compile_path_for_command(input)
    }
    key, key_ok := compile_cache_key(input)
    if !key_ok {
        timing_report.cache_status = "bypassed"
        if explain_cache_enabled {
            fmt.eprintln("cache: bypassed because the key or dependency graph could not be computed")
        }
        return compile_path_for_command(input)
    }
    defer delete(key)
    cache_path, metadata_path, path_ok := compile_cache_paths(key)
    if !path_ok {
        return kvist.compile_path_with_map(input)
    }
    defer delete(cache_path)
    defer delete(metadata_path)
    cache_io_start := timing_phase_start()
    if os.exists(cache_path) && os.exists(metadata_path) {
        cached, read_err := os.read_entire_file_from_path(cache_path, context.allocator)
        metadata_bytes, metadata_read_err := os.read_entire_file_from_path(metadata_path, context.allocator)
        if read_err == nil && metadata_read_err == nil {
            metadata := Compile_Cache_Metadata{}
            unmarshal_err := json.unmarshal(metadata_bytes, &metadata)
            delete(metadata_bytes)
            if unmarshal_err == nil {
                if timing_started {
                    timing_report.cache_io_ms += duration_ms(cache_io_start)
                    timing_report.cache_status = "hit"
                }
                explain_compile_cache(input, key, cache_path, "hit")
                return kvist.Emit_Result{
                    output = string(cached),
                    source_map = metadata.source_map,
                    warnings = metadata.warnings,
                }, kvist.Compile_Error{}, true
            }
            delete_compile_cache_metadata(&metadata)
        } else {
            if read_err == nil {
                delete(cached)
            }
            if metadata_read_err == nil {
                delete(metadata_bytes)
            }
        }
    }
    if timing_started {
        timing_report.cache_io_ms += duration_ms(cache_io_start)
        timing_report.cache_status = "miss"
    }
    reason := "miss: output absent"
    if os.exists(cache_path) && !os.exists(metadata_path) {
        reason = "miss: metadata absent"
    } else if os.exists(cache_path) && os.exists(metadata_path) {
        reason = "miss: cached metadata invalid"
    }
    explain_compile_cache(input, key, cache_path, reason)
    result, err, ok = compile_path_for_command(input)
    if ok {
        publish_start := timing_phase_start()
        publish_compile_cache_result(cache_path, metadata_path, result)
        if timing_started {
            timing_report.cache_publish_ms += duration_ms(publish_start)
        }
    }
    return result, err, ok
}

Compact_Source_Map :: struct {
    paths:  [dynamic]string,
    values: [dynamic]i64,
}

Package_Cache_Artifact_Metadata :: struct {
    id:           string,
    source_root:  string,
    source_map:   Compact_Source_Map,
    warnings:     [dynamic]kvist.Compile_Warning,
    dependencies: [dynamic]string,
}

Package_Cache_Metadata :: struct {
    source_map: Compact_Source_Map,
    warnings:   [dynamic]kvist.Compile_Warning,
    artifacts:  [dynamic]Package_Cache_Artifact_Metadata,
}

Package_Cache_Index_Artifact :: struct {
    id:           string,
    source_root:  string,
    warnings:     [dynamic]kvist.Compile_Warning,
    dependencies: [dynamic]string,
}

Package_Cache_Index :: struct {
    warnings:  [dynamic]kvist.Compile_Warning,
    artifacts: [dynamic]Package_Cache_Index_Artifact,
}

PACKAGE_GRAPH_CACHE_LIMIT       :: 64
PACKAGE_FRONTEND_COMPILER_LIMIT :: 4
PACKAGE_FRONTEND_ENTRY_LIMIT    :: 512
FINGERPRINT_CACHE_LIMIT         :: 256

delete_compact_source_map :: proc(source_map: ^Compact_Source_Map) {
    kvist.delete_string_slice(&source_map.paths)
    delete(source_map.values)
    source_map^ = {}
}

compact_source_map :: proc(entries: []kvist.Source_Map_Entry) -> Compact_Source_Map {
    compact := Compact_Source_Map{}
    for entry in entries {
        path_index := -1
        for path, idx in compact.paths {
            if path == entry.source_path {
                path_index = idx
                break
            }
        }
        if path_index < 0 {
            path_index = len(compact.paths)
            append(&compact.paths, strings.clone(entry.source_path))
        }
        append(
            &compact.values,
            i64(entry.generated_start_line),
            i64(entry.generated_end_line),
            i64(entry.generated_start_column),
            i64(entry.generated_end_column),
            i64(entry.source_span.source),
            i64(entry.source_span.start),
            i64(entry.source_span.end),
            i64(path_index),
        )
    }
    return compact
}

expand_compact_source_map :: proc(
    compact: Compact_Source_Map,
) -> [dynamic]kvist.Source_Map_Entry {
    entries: [dynamic]kvist.Source_Map_Entry
    if len(compact.values)%8 != 0 {
        return entries
    }
    for offset := 0; offset < len(compact.values); offset += 8 {
        path_index := int(compact.values[offset+7])
        if path_index < 0 || path_index >= len(compact.paths) {
            kvist.source_map_slice_delete(entries)
            return nil
        }
        append(&entries, kvist.Source_Map_Entry{
            generated_start_line = int(compact.values[offset]),
            generated_end_line = int(compact.values[offset+1]),
            generated_start_column = int(compact.values[offset+2]),
            generated_end_column = int(compact.values[offset+3]),
            source_span = kvist.Span{
                source = kvist.Source_Kind(compact.values[offset+4]),
                start = int(compact.values[offset+5]),
                end = int(compact.values[offset+6]),
            },
            source_path = strings.clone(compact.paths[path_index]),
        })
    }
    return entries
}

delete_package_cache_metadata :: proc(metadata: ^Package_Cache_Metadata) {
    delete_compact_source_map(&metadata.source_map)
    kvist.compile_warning_slice_delete(metadata.warnings)
    for &artifact in metadata.artifacts {
        delete(artifact.id)
        delete(artifact.source_root)
        delete_compact_source_map(&artifact.source_map)
        kvist.compile_warning_slice_delete(artifact.warnings)
        kvist.delete_string_slice(&artifact.dependencies)
    }
    delete(metadata.artifacts)
    metadata^ = {}
}

delete_package_cache_index :: proc(index: ^Package_Cache_Index) {
    kvist.compile_warning_slice_delete(index.warnings)
    for &artifact in index.artifacts {
        delete(artifact.id)
        delete(artifact.source_root)
        kvist.compile_warning_slice_delete(artifact.warnings)
        kvist.delete_string_slice(&artifact.dependencies)
    }
    delete(index.artifacts)
    index^ = {}
}

set_deferred_package_maps_path :: proc(path: string) {
    if deferred_package_maps_path != "" {
        delete(deferred_package_maps_path)
        deferred_package_maps_path = ""
    }
    if path != "" {
        deferred_package_maps_path = strings.clone(path)
    }
}

package_compile_cache_path :: proc(key: string) -> (path: string, ok: bool) {
    base := cache_dir_or_exit()
    defer delete(base)
    dir, dir_err := os.join_path({base, "compile-packages"}, context.allocator)
    if dir_err != nil {
        return "", false
    }
    defer delete(dir)
    if !os.exists(dir) && os.make_directory_all(dir) != nil {
        return "", false
    }
    path_err: os.Error
    path, path_err = os.join_path({dir, key}, context.allocator)
    return path, path_err == nil
}

prune_cache_entries :: proc(dir: string, limit: int, temporary_prefix := "") {
    entries, read_err := os.read_directory_by_path(dir, -1, context.allocator)
    if read_err != nil {
        return
    }
    defer os.file_info_slice_delete(entries, context.allocator)
    candidates: [dynamic]os.File_Info
    defer delete(candidates)
    for entry in entries {
        if (entry.type == .Directory || entry.type == .Regular) &&
           (temporary_prefix == "" || !strings.has_prefix(entry.name, temporary_prefix)) {
            append(&candidates, entry)
        }
    }
    if len(candidates) <= limit {
        return
    }
    slice.sort_by(candidates[:], proc(a, b: os.File_Info) -> bool {
        return time.time_to_unix_nano(a.modification_time) <
               time.time_to_unix_nano(b.modification_time)
    })
    remove_count := len(candidates) - limit
    for entry in candidates[:remove_count] {
        stale_path, join_err := os.join_path({dir, entry.name}, context.allocator)
        if join_err == nil {
            if entry.type == .Directory {
                _ = os.remove_all(stale_path)
            } else {
                _ = os.remove(stale_path)
            }
            delete(stale_path)
        }
    }
}

publish_package_compile_cache_result :: proc(path: string, result: kvist.Package_Emit_Result) {
    parent, _ := os.split_path(path)
    temp_dir, temp_err := os.make_directory_temp(parent, ".kvist-packages-*", context.allocator)
    if temp_err != nil {
        return
    }
    defer {
        _ = os.remove_all(temp_dir)
        delete(temp_dir)
    }
    root_path, root_join_err := os.join_path({temp_dir, "root.odin"}, context.allocator)
    if root_join_err != nil {
        return
    }
    defer delete(root_path)
    if os.write_entire_file_from_string(root_path, result.root.output) != nil {
        return
    }
    artifacts_dir, artifacts_join_err := os.join_path({temp_dir, "artifacts"}, context.allocator)
    if artifacts_join_err != nil || os.make_directory_all(artifacts_dir) != nil {
        if artifacts_join_err == nil {
            delete(artifacts_dir)
        }
        return
    }
    defer delete(artifacts_dir)
    metadata := Package_Cache_Metadata{
        source_map = compact_source_map(result.root.source_map[:]),
    }
    index := Package_Cache_Index{warnings = result.root.warnings}
    defer {
        delete_compact_source_map(&metadata.source_map)
        for &artifact in metadata.artifacts {
            delete_compact_source_map(&artifact.source_map)
        }
        delete(metadata.artifacts)
        delete(index.artifacts)
    }
    for artifact in result.artifacts {
        artifact_path, artifact_path_err := os.join_path(
            {artifacts_dir, fmt.tprintf("%s.odin", artifact.id)},
            context.allocator,
        )
        if artifact_path_err != nil {
            return
        }
        write_err := os.write_entire_file_from_string(artifact_path, artifact.output)
        delete(artifact_path)
        if write_err != nil {
            return
        }
        append(&metadata.artifacts, Package_Cache_Artifact_Metadata{
            id = artifact.id,
            source_map = compact_source_map(artifact.source_map[:]),
        })
        append(&index.artifacts, Package_Cache_Index_Artifact{
            id = artifact.id,
            source_root = artifact.source_root,
            warnings = artifact.warnings,
            dependencies = artifact.dependencies,
        })
    }
    bytes, marshal_err := json.marshal(index)
    if marshal_err != nil {
        return
    }
    defer delete(bytes)
    manifest_path, manifest_join_err := os.join_path(
        {temp_dir, "manifest.json"},
        context.allocator,
    )
    if manifest_join_err != nil {
        return
    }
    defer delete(manifest_path)
    if os.write_entire_file(manifest_path, bytes) != nil {
        return
    }
    map_bytes, map_marshal_err := json.marshal(metadata)
    if map_marshal_err != nil {
        return
    }
    defer delete(map_bytes)
    maps_path, maps_join_err := os.join_path(
        {temp_dir, "maps.json"},
        context.allocator,
    )
    if maps_join_err != nil {
        return
    }
    defer delete(maps_path)
    if os.write_entire_file(maps_path, map_bytes) == nil {
        _ = os.rename(temp_dir, path)
        prune_cache_entries(parent, PACKAGE_GRAPH_CACHE_LIMIT, ".kvist-packages-")
    }
}

load_package_compile_cache_result :: proc(
    path: string,
) -> (result: kvist.Package_Emit_Result, ok: bool) {
    manifest_path, manifest_join_err := os.join_path(
        {path, "manifest.json"},
        context.allocator,
    )
    if manifest_join_err != nil {
        return result, false
    }
    defer delete(manifest_path)
    metadata_bytes, metadata_read_err := os.read_entire_file_from_path(
        manifest_path,
        context.allocator,
    )
    if metadata_read_err != nil {
        return result, false
    }
    defer delete(metadata_bytes)
    index := Package_Cache_Index{}
    if json.unmarshal(metadata_bytes, &index) != nil {
        delete_package_cache_index(&index)
        return result, false
    }
    root_path, root_join_err := os.join_path({path, "root.odin"}, context.allocator)
    if root_join_err != nil {
        delete_package_cache_index(&index)
        return result, false
    }
    root_bytes, root_read_err := os.read_entire_file_from_path(
        root_path,
        context.allocator,
    )
    delete(root_path)
    if root_read_err != nil {
        delete_package_cache_index(&index)
        return result, false
    }
    result.root = kvist.Emit_Result{
        output = string(root_bytes),
        warnings = index.warnings,
    }
    index.warnings = nil
    artifacts_dir, artifacts_join_err := os.join_path(
        {path, "artifacts"},
        context.allocator,
    )
    if artifacts_join_err != nil {
        delete_package_cache_index(&index)
        kvist.package_emit_result_delete(&result)
        return result, false
    }
    defer delete(artifacts_dir)
    for &cached in index.artifacts {
        artifact_path, artifact_path_err := os.join_path(
            {artifacts_dir, fmt.tprintf("%s.odin", cached.id)},
            context.allocator,
        )
        if artifact_path_err != nil {
            delete_package_cache_index(&index)
            kvist.package_emit_result_delete(&result)
            return result, false
        }
        output_bytes, output_read_err := os.read_entire_file_from_path(
            artifact_path,
            context.allocator,
        )
        delete(artifact_path)
        if output_read_err != nil {
            delete_package_cache_index(&index)
            kvist.package_emit_result_delete(&result)
            return result, false
        }
        append(&result.artifacts, kvist.Generated_Package_Artifact{
            id = cached.id,
            source_root = cached.source_root,
            output = string(output_bytes),
            warnings = cached.warnings,
            dependencies = cached.dependencies,
        })
        cached = {}
    }
    delete_package_cache_index(&index)
    return result, true
}

load_package_compile_cache_maps :: proc(
    path: string,
) -> (result: kvist.Package_Emit_Result, ok: bool) {
    maps_path, maps_join_err := os.join_path(
        {path, "maps.json"},
        context.allocator,
    )
    if maps_join_err != nil {
        return result, false
    }
    defer delete(maps_path)
    metadata_bytes, metadata_read_err := os.read_entire_file_from_path(
        maps_path,
        context.allocator,
    )
    if metadata_read_err != nil {
        return result, false
    }
    defer delete(metadata_bytes)
    metadata := Package_Cache_Metadata{}
    defer delete_package_cache_metadata(&metadata)
    if json.unmarshal(metadata_bytes, &metadata) != nil {
        return result, false
    }
    result.root.source_map = expand_compact_source_map(metadata.source_map)
    for artifact in metadata.artifacts {
        append(&result.artifacts, kvist.Generated_Package_Artifact{
            id = strings.clone(artifact.id),
            source_map = expand_compact_source_map(artifact.source_map),
        })
    }
    return result, true
}

compile_package_path_with_execution_cache :: proc(input: string) -> (result: kvist.Package_Emit_Result, err: kvist.Compile_Error, ok: bool) {
    set_deferred_package_maps_path("")
    if compile_cache_disabled() {
        timing_report.cache_status = "disabled"
        return compile_package_path_for_command(input)
    }
    key, key_ok := compile_cache_key(input)
    if !key_ok {
        timing_report.cache_status = "bypassed"
        return compile_package_path_for_command(input)
    }
    defer delete(key)
    cache_path, path_ok := package_compile_cache_path(key)
    if !path_ok {
        timing_report.cache_status = "bypassed"
        return compile_package_path_for_command(input)
    }
    defer delete(cache_path)
    cache_start := timing_phase_start()
    if os.exists(cache_path) {
        cached, cached_ok := load_package_compile_cache_result(cache_path)
        if cached_ok {
            result = cached
            now := time.now()
            _ = os.change_times(cache_path, now, now)
            result.packages_reused = len(result.artifacts) + 1
            result.packages_emitted = 0
            if timing_started {
                timing_report.cache_io_ms += duration_ms(cache_start)
                timing_report.cache_status = "hit"
                timing_report.packages_reused += result.packages_reused
            }
            explain_compile_cache(input, key, cache_path, "hit: generated package graph")
            set_deferred_package_maps_path(cache_path)
            return result, {}, true
        }
    }
    if timing_started {
        timing_report.cache_io_ms += duration_ms(cache_start)
        timing_report.cache_status = "miss"
    }
    explain_compile_cache(input, key, cache_path, "miss: generated package graph absent")
    result, err, ok = compile_package_path_for_command(input)
    if ok {
        publish_start := timing_phase_start()
        publish_package_compile_cache_result(cache_path, result)
        if timing_started {
            timing_report.cache_publish_ms += duration_ms(publish_start)
        }
    }
    return result, err, ok
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
        exit_with_timing(1)
    }
}

cache_command :: proc() {
    if len(os.args) < 3 {
        print_usage()
        exit_with_timing(2)
    }

    switch os.args[2] {
    case "path":
        if len(os.args) != 4 {
            print_usage()
            exit_with_timing(2)
        }
        dir := cache_dir_or_exit()
        defer delete(dir)
        path := cache_path_in_dir_or_exit(dir, os.args[3])
        defer delete(path)
        fmt.println(path)
    case "list":
        if len(os.args) != 3 {
            print_usage()
            exit_with_timing(2)
        }
        dir := cache_dir_or_exit()
        defer delete(dir)
        if !os.exists(dir) {
            return
        }
        entries, err := os.read_directory_by_path(dir, -1, context.allocator)
        if err != nil {
            fmt.eprintln("failed to read cache directory: ", dir)
            exit_with_timing(1)
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
            exit_with_timing(2)
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
            exit_with_timing(1)
        }
    case "inspect":
        if len(os.args) != 3 {
            print_usage()
            exit_with_timing(2)
        }
        base := cache_dir_or_exit()
        defer delete(base)
        dir, dir_err := os.join_path({base, "compile"}, context.allocator)
        if dir_err != nil || !os.exists(dir) {
            if dir_err == nil {
                delete(dir)
            }
            return
        }
        defer delete(dir)
        entries, read_err := os.read_directory_by_path(dir, -1, context.allocator)
        if read_err != nil {
            fmt.eprintln("failed to inspect compile cache: ", dir)
            exit_with_timing(1)
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
    case "clear":
        if len(os.args) != 3 && len(os.args) != 4 {
            print_usage()
            exit_with_timing(2)
        }
        base := cache_dir_or_exit()
        defer delete(base)
        if len(os.args) == 3 {
            dir, dir_err := os.join_path({base, "compile"}, context.allocator)
            if dir_err == nil {
                defer delete(dir)
                _ = os.remove_all(dir)
            }
            fingerprint_dir, fingerprint_dir_err := os.join_path({base, "fingerprints"}, context.allocator)
            if fingerprint_dir_err == nil {
                defer delete(fingerprint_dir)
                _ = os.remove_all(fingerprint_dir)
            }
            return
        }
        key, key_ok := compile_cache_key(os.args[3])
        if !key_ok {
            fmt.eprintln("could not compute compile cache key for: ", os.args[3])
            exit_with_timing(1)
        }
        defer delete(key)
        output_path, metadata_path, paths_ok := compile_cache_paths(key)
        if paths_ok {
            defer delete(output_path)
            defer delete(metadata_path)
            _ = os.remove(output_path)
            _ = os.remove(metadata_path)
        }
    case:
        print_usage()
        exit_with_timing(2)
    }
}

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

    if source_dir_has_odin_sidecars(source_path) {
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
                exit_with_timing(2)
            }
            output_path = os.args[i+1]
            i += 2
        case "--map":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            map_path = os.args[i+1]
            i += 2
        case "--ownership-audit":
            ownership_audit_enabled = true
            i += 1
        case "--eval":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            eval_source = os.args[i+1]
            i += 2
        case "--no-print":
            no_print = true
            i += 1
        case:
            if parse_timing_arg(&i) {
                continue
            }
            print_usage()
            exit_with_timing(2)
        }
    }

    timing_begin("eval" if eval_source != "" else "compile", input)
    if eval_source != "" {
        if map_path != "" {
            fmt.eprintln("--map cannot be used with --eval")
            exit_with_timing(2)
        }
        compile_eval_emit_command(input, eval_source, output_path, no_print)
        return
    }
    compile_file_command(input, output_path, map_path)
}

parse_compile_command :: proc() {
    if len(os.args) < 3 {
        print_usage()
        exit_with_timing(2)
    }
    input := os.args[2]
    output_path := ""
    map_path := ""
    package_output := false

    i := 3
    for i < len(os.args) {
        switch os.args[i] {
        case "-o":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            output_path = os.args[i+1]
            i += 2
        case "--map":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            map_path = os.args[i+1]
            i += 2
        case "--ownership-audit":
            ownership_audit_enabled = true
            i += 1
        case "--packages":
            package_output = true
            i += 1
        case:
            if parse_timing_arg(&i) {
                continue
            }
            print_usage()
            exit_with_timing(2)
        }
    }

    timing_begin("compile", input)
    if package_output {
        compile_package_file_command(input, output_path, map_path)
    } else {
        compile_file_command(input, output_path, map_path)
    }
}

parse_run_or_check_command :: proc(odin_command: string) {
    if len(os.args) < 3 {
        print_usage()
        exit_with_timing(2)
    }
    input := ""
    generated_path := ""
    generated_dir := ""
    binary_output_path := ""
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
                exit_with_timing(2)
            }
            generated_path = os.args[i+1]
            i += 2
        case "--generated-dir":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            generated_dir = os.args[i+1]
            i += 2
        case "--out":
            if odin_command != "build" || i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            binary_output_path = os.args[i+1]
            i += 2
        case "--ownership-audit":
            ownership_audit_enabled = true
            i += 1
        case "--explain-cache":
            explain_cache_enabled = true
            i += 1
        case:
            if parse_timing_arg(&i) {
                continue
            }
            if input == "" {
                input = os.args[i]
                i += 1
            } else {
                print_usage()
                exit_with_timing(2)
            }
        }
    }

    if input == "" {
        print_usage()
        exit_with_timing(2)
    }

    timing_begin(odin_command, input)
    if reload_mode {
        if timings_enabled() {
            fmt.eprintln("timings are not supported with reload mode")
            exit_with_timing(2)
        }
        if generated_path != "" || binary_output_path != "" {
            print_usage()
            exit_with_timing(2)
        }
        exit_with_timing(reload_app_generate_and_execute(input, odin_command, generated_dir))
    }

    if generated_path == "" && source_declares_reload_app(input) {
        if timings_enabled() {
            fmt.eprintln("timings are not supported with reload applications")
            exit_with_timing(2)
        }
        if binary_output_path != "" {
            print_usage()
            exit_with_timing(2)
        }
        exit_with_timing(reload_app_generate_and_execute(input, odin_command, generated_dir))
    }

    exit_with_timing(run_generated_command(input, generated_path, odin_command, binary_output_path))
}

parse_frontend_check_command :: proc() {
    if len(os.args) < 3 {
        print_usage()
        exit_with_timing(2)
    }
    input := os.args[2]
    i := 3
    for i < len(os.args) {
        switch os.args[i] {
        case "--ownership-audit":
            ownership_audit_enabled = true
            i += 1
        case "--explain-cache":
            explain_cache_enabled = true
            i += 1
        case:
            if parse_timing_arg(&i) {
                continue
            }
            print_usage()
            exit_with_timing(2)
        }
    }
    timing_begin("frontend-check", input)
    exit_with_timing(frontend_check_command(input))
}

parse_test_command :: proc() {
    if len(os.args) < 3 {
        print_usage()
        exit_with_timing(2)
    }
    input := os.args[2]
    generated_path := ""
    test_names := ""
    track_memory := false

    i := 3
    for i < len(os.args) {
        switch os.args[i] {
        case "--generated":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            generated_path = os.args[i+1]
            i += 2
        case "--names":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            test_names = os.args[i+1]
            i += 2
        case "--track-memory":
            track_memory = true
            i += 1
        case "--ownership-audit":
            ownership_audit_enabled = true
            i += 1
        case "--explain-cache":
            explain_cache_enabled = true
            i += 1
        case:
            if parse_timing_arg(&i) {
                continue
            }
            print_usage()
            exit_with_timing(2)
        }
    }

    timing_begin("test", input)
    exit_with_timing(test_command(input, generated_path, test_names, track_memory))
}

parse_eval_command :: proc() {
    if len(os.args) < 4 {
        print_usage()
        exit_with_timing(2)
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
                exit_with_timing(2)
            }
            generated_path = os.args[i+1]
            i += 2
        case "--no-print":
            no_print = true
            i += 1
        case "--check":
            check_only = true
            i += 1
        case "--ownership-audit":
            ownership_audit_enabled = true
            i += 1
        case "--save":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            save_name = os.args[i+1]
            i += 2
        case:
            if parse_timing_arg(&i) {
                continue
            }
            print_usage()
            exit_with_timing(2)
        }
    }

    timing_begin("eval", input)
    exit_with_timing(eval_command(input, eval_source, generated_path, save_name, no_print, check_only))
}

parse_expand_command :: proc() {
    if len(os.args) < 4 {
        print_usage()
        exit_with_timing(2)
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
                exit_with_timing(2)
            }
            output_path = os.args[i+1]
            i += 2
        case "--no-print":
            no_print = true
            i += 1
        case:
            print_usage()
            exit_with_timing(2)
        }
    }

    compile_eval_emit_command(input, eval_source, output_path, no_print)
}

parse_macroexpand_command :: proc() {
    if len(os.args) < 4 {
        print_usage()
        exit_with_timing(2)
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
                exit_with_timing(2)
            }
            output_path = os.args[i+1]
            i += 2
        case "--map":
            if i+1 >= len(os.args) {
                print_usage()
                exit_with_timing(2)
            }
            map_path = os.args[i+1]
            i += 2
        case:
            print_usage()
            exit_with_timing(2)
        }
    }

    macroexpand_command(input, eval_source, output_path, map_path)
}

parse_symbols_command :: proc() {
    if len(os.args) != 3 {
        print_usage()
        exit_with_timing(2)
    }
    symbols_command(os.args[2])
}

parse_lifetimes_command :: proc() {
    if len(os.args) != 3 {
        print_usage()
        exit_with_timing(2)
    }
    lifetimes_command(os.args[2])
}

parse_editor_symbols_command :: proc() {
    if len(os.args) != 3 && len(os.args) != 4 {
        print_usage()
        exit_with_timing(2)
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
        exit_with_timing(2)
    }
    lookup_command(os.args[2], os.args[3])
}

parse_complete_command :: proc() {
    if len(os.args) != 3 && len(os.args) != 4 {
        print_usage()
        exit_with_timing(2)
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
        exit_with_timing(2)
    }
    doc_command(os.args[2], os.args[3])
}

parse_xref_command :: proc() {
    if len(os.args) != 4 {
        print_usage()
        exit_with_timing(2)
    }
    xref_command(os.args[2], os.args[3])
}

parse_builtin_symbols_command :: proc() {
    if len(os.args) != 2 {
        print_usage()
        exit_with_timing(2)
    }
    builtin_symbols_command()
}

parse_imported_symbols_command :: proc() {
    if len(os.args) != 3 {
        print_usage()
        exit_with_timing(2)
    }
    imported_symbols_command(os.args[2])
}

parse_package_symbols_command :: proc() {
    if len(os.args) != 3 && len(os.args) != 4 {
        print_usage()
        exit_with_timing(2)
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
        exit_with_timing(2)
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
    case "frontend-check":
        parse_frontend_check_command()
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
    case "lifetimes":
        parse_lifetimes_command()
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
    case "root":
        root_command()
    case "cache":
        cache_command()
    }
    final_status := timing_finish(0)
    if final_status != 0 {
        os.exit(final_status)
    }
}
