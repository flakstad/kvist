// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import kvist "../../odin/kvist"

DEPENDENCY_FINGERPRINT_VERSION :: 1

Dependency_File_Fingerprint :: struct {
    path:                 string,
    size:                 i64,
    modification_time_ns: i64,
    content_hash:         u64,
}

Dependency_Directory_Fingerprint :: struct {
    path:                 string,
    modification_time_ns: i64,
}

Dependency_Fingerprint_Manifest :: struct {
    version:     int,
    input:       string,
    compiler:    Dependency_File_Fingerprint,
    files:       [dynamic]Dependency_File_Fingerprint,
    directories: [dynamic]Dependency_Directory_Fingerprint,
}

delete_dependency_file_fingerprint :: proc(record: ^Dependency_File_Fingerprint) {
    if record.path != "" {
        delete(record.path)
    }
    record^ = {}
}

delete_dependency_fingerprint_manifest :: proc(manifest: ^Dependency_Fingerprint_Manifest) {
    if manifest.input != "" {
        delete(manifest.input)
    }
    delete_dependency_file_fingerprint(&manifest.compiler)
    for &record in manifest.files {
        delete_dependency_file_fingerprint(&record)
    }
    delete(manifest.files)
    for record in manifest.directories {
        if record.path != "" {
            delete(record.path)
        }
    }
    delete(manifest.directories)
    manifest^ = {}
}

file_metadata :: proc(path: string) -> (size, modification_time_ns: i64, ok: bool) {
    info, stat_err := os.stat(path, context.allocator)
    if stat_err != nil {
        return 0, 0, false
    }
    defer os.file_info_delete(info, context.allocator)
    return info.size, time.time_to_unix_nano(info.modification_time), true
}

directory_metadata :: proc(path: string) -> (modification_time_ns: i64, ok: bool) {
    info, stat_err := os.stat(path, context.allocator)
    if stat_err != nil || info.type != .Directory {
        if stat_err == nil {
            os.file_info_delete(info, context.allocator)
        }
        return 0, false
    }
    defer os.file_info_delete(info, context.allocator)
    return time.time_to_unix_nano(info.modification_time), true
}

hash_file_content :: proc(path: string) -> (hash: u64, ok: bool) {
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        return 0, false
    }
    defer delete(data)
    return fnv1a_update(14695981039346656037, data), true
}

fingerprint_file :: proc(path: string) -> (record: Dependency_File_Fingerprint, ok: bool) {
    size, modification_time_ns, metadata_ok := file_metadata(path)
    if !metadata_ok {
        return {}, false
    }
    content_hash, hash_ok := hash_file_content(path)
    if !hash_ok {
        return {}, false
    }
    return Dependency_File_Fingerprint{
        path = strings.clone(path),
        size = size,
        modification_time_ns = modification_time_ns,
        content_hash = content_hash,
    }, true
}

clone_dependency_file_fingerprint :: proc(record: Dependency_File_Fingerprint) -> Dependency_File_Fingerprint {
    cloned := record
    cloned.path = strings.clone(record.path)
    return cloned
}

file_fingerprint_matches_metadata :: proc(record: Dependency_File_Fingerprint) -> bool {
    size, modification_time_ns, ok := file_metadata(record.path)
    return ok &&
           size == record.size &&
           modification_time_ns == record.modification_time_ns
}

reusable_file_fingerprint :: proc(
    manifest: ^Dependency_Fingerprint_Manifest,
    path: string,
) -> (Dependency_File_Fingerprint, bool) {
    if manifest == nil {
        return {}, false
    }
    if manifest.compiler.path == path && file_fingerprint_matches_metadata(manifest.compiler) {
        return clone_dependency_file_fingerprint(manifest.compiler), true
    }
    for record in manifest.files {
        if record.path == path && file_fingerprint_matches_metadata(record) {
            return clone_dependency_file_fingerprint(record), true
        }
    }
    return {}, false
}

directory_fingerprint_matches_metadata :: proc(record: Dependency_Directory_Fingerprint) -> bool {
    modification_time_ns, ok := directory_metadata(record.path)
    return ok && modification_time_ns == record.modification_time_ns
}

append_fingerprint_hash :: proc(hash: u64, value: u64) -> u64 {
    text := fmt.tprintf("%016x", value)
    return fnv1a_update(hash, transmute([]byte)text)
}

compile_key_from_manifest :: proc(manifest: Dependency_Fingerprint_Manifest) -> string {
    hash: u64 = 14695981039346656037
    hash = fnv1a_update(hash, transmute([]byte)string(COMPILE_CACHE_VERSION))
    hash = fnv1a_update(hash, transmute([]byte)manifest.input)
    hash = fnv1a_update(hash, []byte{0})
    hash = append_fingerprint_hash(hash, manifest.compiler.content_hash)
    hash = fnv1a_update(hash, []byte{254})
    for record in manifest.files {
        hash = fnv1a_update(hash, transmute([]byte)record.path)
        hash = fnv1a_update(hash, []byte{0})
        hash = append_fingerprint_hash(hash, record.content_hash)
        hash = fnv1a_update(hash, []byte{255})
    }
    return strings.clone(fmt.tprintf("%016x", hash))
}

fingerprint_manifest_path :: proc(canonical_input: string) -> (path: string, ok: bool) {
    base := cache_dir_or_exit()
    defer delete(base)
    dir, dir_err := os.join_path({base, "fingerprints"}, context.allocator)
    if dir_err != nil {
        return "", false
    }
    defer delete(dir)
    if !os.exists(dir) && os.make_directory_all(dir) != nil {
        return "", false
    }
    input_hash := fnv1a_update(14695981039346656037, transmute([]byte)canonical_input)
    name := fmt.tprintf("%016x.json", input_hash)
    path_err: os.Error
    path, path_err = os.join_path({dir, name}, context.allocator)
    return path, path_err == nil
}

load_dependency_fingerprint_manifest :: proc(path: string) -> (manifest: Dependency_Fingerprint_Manifest, ok: bool) {
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        return {}, false
    }
    defer delete(data)
    if json.unmarshal(data, &manifest) != nil {
        delete_dependency_fingerprint_manifest(&manifest)
        return {}, false
    }
    return manifest, true
}

dependency_fingerprint_manifest_valid :: proc(
    manifest: Dependency_Fingerprint_Manifest,
    canonical_input, compiler_path: string,
) -> bool {
    if manifest.version != DEPENDENCY_FINGERPRINT_VERSION ||
       manifest.input != canonical_input ||
       manifest.compiler.path != compiler_path ||
       len(manifest.files) == 0 {
        return false
    }
    if !file_fingerprint_matches_metadata(manifest.compiler) {
        return false
    }
    for record in manifest.files {
        if !file_fingerprint_matches_metadata(record) {
            return false
        }
    }
    for record in manifest.directories {
        if !directory_fingerprint_matches_metadata(record) {
            return false
        }
    }
    return true
}

publish_dependency_fingerprint_manifest :: proc(path: string, manifest: Dependency_Fingerprint_Manifest) {
    parent, _ := os.split_path(path)
    if parent == "" {
        return
    }
    temp_dir, temp_err := os.make_directory_temp(parent, ".kvist-fingerprint-*", context.allocator)
    if temp_err != nil {
        return
    }
    defer {
        _ = os.remove_all(temp_dir)
        delete(temp_dir)
    }
    temp_path, join_err := os.join_path({temp_dir, "manifest.json"}, context.allocator)
    if join_err != nil {
        return
    }
    defer delete(temp_path)
    bytes, marshal_err := json.marshal(manifest)
    if marshal_err != nil {
        return
    }
    defer delete(bytes)
    if os.write_entire_file(temp_path, bytes) == nil {
        _ = os.rename(temp_path, path)
        prune_cache_entries(parent, FINGERPRINT_CACHE_LIMIT, ".kvist-fingerprint-")
    }
}

sorted_dependency_directories :: proc(paths: []string) -> [dynamic]string {
    directories: [dynamic]string
    for path in paths {
        dir, _ := os.split_path(path)
        if dir == "" {
            dir = "."
        }
        absolute, absolute_err := os.get_absolute_path(dir, context.allocator)
        if absolute_err != nil {
            continue
        }
        found := false
        for existing in directories {
            if existing == absolute {
                found = true
                break
            }
        }
        if found {
            delete(absolute)
        } else {
            append(&directories, absolute)
        }
    }
    slice.sort_by(directories[:], proc(a, b: string) -> bool {
        return a < b
    })
    return directories
}

build_dependency_fingerprint_manifest :: proc(
    canonical_input, compiler_path: string,
    previous: ^Dependency_Fingerprint_Manifest = nil,
) -> (manifest: Dependency_Fingerprint_Manifest, ok: bool) {
    manifest.version = DEPENDENCY_FINGERPRINT_VERSION
    manifest.input = strings.clone(canonical_input)

    compiler, compiler_reused := reusable_file_fingerprint(previous, compiler_path)
    compiler_ok := compiler_reused
    if !compiler_reused {
        compiler, compiler_ok = fingerprint_file(compiler_path)
    }
    if !compiler_ok {
        delete_dependency_fingerprint_manifest(&manifest)
        return {}, false
    }
    manifest.compiler = compiler

    discovery_start := timing_phase_start()
    dependencies, dependency_err, dependencies_ok := kvist.source_dependency_paths(canonical_input)
    if timing_started {
        timing_report.dependency_discovery_ms += duration_ms(discovery_start)
    }
    if !dependencies_ok {
        _ = dependency_err
        delete_dependency_fingerprint_manifest(&manifest)
        return {}, false
    }
    defer kvist.delete_string_slice(&dependencies)

    for path in dependencies {
        record, record_reused := reusable_file_fingerprint(previous, path)
        record_ok := record_reused
        if !record_reused {
            record, record_ok = fingerprint_file(path)
        }
        if !record_ok {
            delete_dependency_fingerprint_manifest(&manifest)
            return {}, false
        }
        append(&manifest.files, record)
        if timing_started {
            if record_reused {
                timing_report.fingerprint_files_reused += 1
            } else {
                timing_report.fingerprint_files_hashed += 1
            }
        }
    }

    directories := sorted_dependency_directories(dependencies[:])
    defer kvist.delete_string_slice(&directories)
    for dir in directories {
        modification_time_ns, metadata_ok := directory_metadata(dir)
        if !metadata_ok {
            delete_dependency_fingerprint_manifest(&manifest)
            return {}, false
        }
        append(&manifest.directories, Dependency_Directory_Fingerprint{
            path = strings.clone(dir),
            modification_time_ns = modification_time_ns,
        })
    }
    return manifest, true
}

cached_compile_cache_key :: proc(input: string) -> (key: string, ok: bool) {
    fingerprint_start := timing_phase_start()
    dependency_discovery_before := timing_report.dependency_discovery_ms
    defer if timing_started {
        fingerprint_ms := duration_ms(fingerprint_start) -
                          (timing_report.dependency_discovery_ms - dependency_discovery_before)
        if fingerprint_ms > 0 {
            timing_report.cache_fingerprint_ms += fingerprint_ms
        }
    }

    canonical_input, canonical_err := os.get_absolute_path(input, context.allocator)
    if canonical_err != nil {
        return "", false
    }
    defer delete(canonical_input)
    compiler_path, compiler_err := os.get_executable_path(context.allocator)
    if compiler_err != nil {
        return "", false
    }
    defer delete(compiler_path)
    manifest_path, path_ok := fingerprint_manifest_path(canonical_input)
    if !path_ok {
        return "", false
    }
    defer delete(manifest_path)

    previous: Dependency_Fingerprint_Manifest
    previous_loaded := false
    loaded_manifest, loaded := load_dependency_fingerprint_manifest(manifest_path)
    if loaded {
        previous = loaded_manifest
        previous_loaded = true
    }
    defer if previous_loaded {
        delete_dependency_fingerprint_manifest(&previous)
    }
    if previous_loaded &&
       dependency_fingerprint_manifest_valid(previous, canonical_input, compiler_path) {
        now := time.now()
        _ = os.change_times(manifest_path, now, now)
        if timing_started {
            timing_report.fingerprint_cache_status = "hit"
            timing_report.fingerprint_files_reused = len(previous.files)
        }
        return compile_key_from_manifest(previous), true
    }

    if timing_started {
        timing_report.fingerprint_cache_status = "miss"
    }
    reusable_previous: ^Dependency_Fingerprint_Manifest
    if previous_loaded &&
       previous.version == DEPENDENCY_FINGERPRINT_VERSION &&
       previous.input == canonical_input {
        reusable_previous = &previous
    }
    manifest, built := build_dependency_fingerprint_manifest(
        canonical_input,
        compiler_path,
        reusable_previous,
    )
    if !built {
        return "", false
    }
    defer delete_dependency_fingerprint_manifest(&manifest)
    publish_dependency_fingerprint_manifest(manifest_path, manifest)
    return compile_key_from_manifest(manifest), true
}
