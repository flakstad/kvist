// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:sort"
import "core:strings"
import "core:time"
import "base:runtime"

resolve_kvist_source_package_from_root :: proc(root, package_name: string) -> (string, bool) {
    if root == "" || package_name == "" {
        return "", false
    }
    candidate, join_err := os.join_path({root, package_name}, context.allocator)
    if join_err != nil {
        return "", false
    }
    if os.exists(candidate) && os.is_dir(candidate) && directory_has_kvist_files(candidate) {
        return candidate, true
    }
    delete(candidate)
    return "", false
}

resolve_kvist_source_package_from_installed :: proc(anchor_path, package_name: string) -> (string, bool) {
    roots := kvist_source_package_roots(anchor_path)
    defer delete_string_slice(&roots)
    for root in roots {
        if candidate, ok := resolve_kvist_source_package_from_root(root, package_name); ok {
            return candidate, true
        }
    }
    return "", false
}

is_source_import_path :: proc(path: string) -> bool {
    return is_source_import_path_from(".", path)
}

directory_has_kvist_files :: proc(dir: string) -> bool {
    entries, err := os.read_directory_by_path(dir, -1, context.allocator)
    if err != nil {
        return false
    }
    defer os.file_info_slice_delete(entries, context.allocator)

    for entry in entries {
        if entry.type == .Regular && strings.has_suffix(entry.name, ".kvist") {
            return true
        }
    }
    return false
}

resolve_import_base_path :: proc(importer_path, import_path: string) -> (base: string, owned: bool) {
    if os.is_absolute_path(import_path) {
        return import_path, false
    }
    base_dir, _ := os.split_path(importer_path)
    if base_dir == "" {
        return import_path, false
    }
    joined, join_err := os.join_path({base_dir, import_path}, context.allocator)
    if join_err != nil {
        return import_path, false
    }
    return joined, true
}

is_source_import_path_from :: proc(importer_path, path: string) -> bool {
    if strings.has_prefix(path, "kvist:") {
        return true
    }
    for ch in path {
        if ch == ':' {
            return false
        }
    }

    base, base_owned := resolve_import_base_path(importer_path, path)
    defer if base_owned { delete(base) }
    if os.exists(base) {
        if os.is_dir(base) {
            return directory_has_kvist_files(base)
        }
        return strings.has_suffix(base, ".kvist")
    }

    file_path := fmt.tprintf("%s.kvist", base)
    return os.exists(file_path) && !os.is_dir(file_path)
}

is_relative_odin_import_path :: proc(path: string) -> bool {
    if path == "" || os.is_absolute_path(path) || strings.contains(path, ":") {
        return false
    }
    return true
}

is_package_anchor_filename :: proc(dir_path, file_name: string) -> bool {
    if file_name == "main.kvist" {
        return true
    }
    if !strings.has_suffix(file_name, ".kvist") {
        return false
    }
    _, dir_name := os.split_path(dir_path)
    if dir_name == "" {
        return false
    }
    suffix := ".kvist"
    return len(file_name) == len(dir_name)+len(suffix) &&
           strings.has_prefix(file_name, dir_name) &&
           strings.has_suffix(file_name, suffix)
}

resolve_kvist_source_import_path :: proc(importer_path, import_path: string) -> (string, Compile_Error, bool) {
    if !strings.has_prefix(import_path, "kvist:") {
        return "", Compile_Error{}, false
    }
    package_name := import_path[len("kvist:"):]
    if package_name == "" {
        return "", Compile_Error{message = fmt.tprintf("could not resolve source package import: %s", import_path)}, false
    }
    if candidate, ok := resolve_kvist_source_package_from_installed(importer_path, package_name); ok {
        return candidate, Compile_Error{}, true
    }
    return "", Compile_Error{message = fmt.tprintf("could not resolve source package import: %s", import_path)}, false
}

resolve_source_import_path :: proc(importer_path, import_path: string) -> (string, Compile_Error, bool) {
    package_path, err_package, ok_package := resolve_kvist_source_import_path(importer_path, import_path)
    if ok_package || err_package.message != "" {
        return package_path, err_package, ok_package
    }
    base_dir, _ := os.split_path(importer_path)
    base := import_path
    base_owned := false
    if base_dir != "" && !os.is_absolute_path(import_path) {
        joined, join_err := os.join_path({base_dir, import_path}, context.allocator)
        if join_err != nil {
            return "", Compile_Error{message = fmt.tprintf("could not resolve source import: %s", import_path)}, false
        }
        base = joined
        base_owned = true
    }
    defer if base_owned { delete(base) }

    if os.exists(base) && os.is_dir(base) {
        return strings.clone(base), Compile_Error{}, true
    }

    file_path := fmt.tprintf("%s.kvist", base)
    if os.exists(file_path) && !os.is_dir(file_path) {
        return strings.clone(file_path), Compile_Error{}, true
    }
    if os.exists(base) && !os.is_dir(base) {
        return strings.clone(base), Compile_Error{}, true
    }
    return "", Compile_Error{message = fmt.tprintf("could not resolve source import: %s", import_path)}, false
}
