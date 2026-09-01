package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"
import kvist "../../odin/kvist"

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
            repl_native_dir, repl_native_dir_err := os.join_path(
                {base, "repl-native"},
                context.allocator,
            )
            if repl_native_dir_err == nil {
                defer delete(repl_native_dir)
                _ = os.remove_all(repl_native_dir)
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
