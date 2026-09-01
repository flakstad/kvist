// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist

import "core:fmt"
import "core:os"
import "core:sort"
import "core:strings"
import "core:time"
import "base:runtime"

Package_File :: struct {
    path:         string,
    path_owned:   bool,
    source:       string,
    package_name: string,
    forms:        [dynamic]CST_Top_Form,
}

package_file_slice_delete :: proc(files: []Package_File) {
    for i in 0 ..< len(files) {
        if files[i].path_owned && files[i].path != "" {
            delete(files[i].path)
        }
        if files[i].source != "" {
            delete(files[i].source)
        }
        delete_borrowed_cst_top_form_slice(&files[i].forms)
    }
    delete(files)
}

read_package_files :: proc(dir: string) -> ([]Package_File, Compile_Error, bool) {
    if strings.has_suffix(dir, ".kvist") {
        return read_root_package_files(dir)
    }

    entries, err := os.read_directory_by_path(dir, -1, context.allocator)
    if err != nil {
        return nil, Compile_Error{message = fmt.tprintf("could not read package directory: %s", dir)}, false
    }
    defer os.file_info_slice_delete(entries, context.allocator)

    paths: [dynamic]string
    for entry in entries {
        if entry.type != .Regular {
            continue
        }
        if !strings.has_suffix(entry.name, ".kvist") {
            continue
        }
        path, join_err := os.join_path({dir, entry.name}, context.allocator)
        if join_err != nil {
            return nil, Compile_Error{message = fmt.tprintf("could not read package directory: %s", dir)}, false
        }
        append(&paths, path)
    }
    if len(paths) == 0 {
        return nil, Compile_Error{message = fmt.tprintf("source package directory contains no .kvist files: %s", dir)}, false
    }
    sorted := sorted_unique_texts(paths[:])
    defer delete(paths)
    defer delete(sorted)

    files: [dynamic]Package_File
    for path in sorted {
        data, read_err := os.read_entire_file_from_path(path, context.allocator)
        if read_err != nil {
            return nil, Compile_Error{message = fmt.tprintf("could not read file: %s", path)}, false
        }
        source := string(data)
        forms, err_forms, ok_forms := read_kvist_top_forms(source, path)
        if !ok_forms {
            return nil, err_forms, false
        }
        package_name := ""
        package_count := 0
        for top in forms {
            if decl_head_name(top.form) != "package" {
                continue
            }
            package_count += 1
            if len(top.form.items) != 2 || top.form.items[1].kind != .Symbol {
                return nil, Compile_Error{message = "package expects one symbol name", span = top.form.span}, false
            }
            package_name = top.form.items[1].text
        }
        if package_count == 0 {
            return nil, Compile_Error{message = fmt.tprintf("source package file is missing package declaration: %s", path)}, false
        }
        if package_count > 1 {
            return nil, Compile_Error{message = fmt.tprintf("source package file has duplicate package declarations: %s", path)}, false
        }
        append(&files, Package_File{path = path, path_owned = true, source = source, package_name = package_name, forms = forms})
    }
    return files[:], Compile_Error{}, true
}

append_source_dependency_path :: proc(paths: ^[dynamic]string, seen: ^map[string]bool, path: string) -> bool {
    absolute, absolute_err := os.get_absolute_path(path, context.allocator)
    if absolute_err != nil {
        return false
    }
    if seen[absolute] {
        delete(absolute)
        return true
    }
    seen[absolute] = true
    append(paths, strings.clone(absolute))
    return true
}

collect_source_dependency_paths_recursive :: proc(
    package_path: string,
    visited_packages: ^map[string]bool,
    seen_paths: ^map[string]bool,
    paths: ^[dynamic]string,
) -> (Compile_Error, bool) {
    canonical, canonical_err := os.get_absolute_path(package_path, context.allocator)
    if canonical_err != nil {
        return Compile_Error{message = fmt.tprintf("could not resolve source dependency: %s", package_path)}, false
    }
    if visited_packages[canonical] {
        delete(canonical)
        return Compile_Error{}, true
    }
    visited_packages[canonical] = true

    package_files: [dynamic]string
    defer delete_string_slice(&package_files)
    package_dir := canonical
    if !os.is_dir(canonical) {
        package_dir, _ = os.split_path(canonical)
        if package_dir == "" {
            package_dir = "."
        }
    }
    entries, entries_err := os.read_directory_by_path(package_dir, -1, context.allocator)
    if entries_err != nil {
        return Compile_Error{message = fmt.tprintf("could not read source dependency directory: %s", package_dir)}, false
    }
    defer os.file_info_slice_delete(entries, context.allocator)
    for entry in entries {
        if entry.type != .Regular || !strings.has_suffix(entry.name, ".kvist") {
            continue
        }
        file_path, join_err := os.join_path({package_dir, entry.name}, context.allocator)
        if join_err == nil {
            append(&package_files, file_path)
        }
    }
    if len(package_files) == 0 {
        return Compile_Error{message = fmt.tprintf("source dependency directory contains no .kvist files: %s", package_dir)}, false
    }

    odin_source_dirs: [dynamic]string
    defer {
        for dir in odin_source_dirs {
            delete(dir)
        }
        delete(odin_source_dirs)
    }
    for file_path in package_files {
        if !append_source_dependency_path(paths, seen_paths, file_path) {
            return Compile_Error{message = fmt.tprintf("could not resolve source dependency: %s", file_path)}, false
        }
        odin_source_dir, _ := os.split_path(file_path)
        if odin_source_dir == "" {
            odin_source_dir = "."
        }
        odin_source_abs, odin_source_err := os.get_absolute_path(odin_source_dir, context.allocator)
        if odin_source_err == nil && !contains_text(odin_source_dirs[:], odin_source_abs) {
            append(&odin_source_dirs, odin_source_abs)
        } else if odin_source_err == nil {
            delete(odin_source_abs)
        }

        source_data, read_err := os.read_entire_file_from_path(file_path, context.allocator)
        if read_err != nil {
            return Compile_Error{message = fmt.tprintf("could not read source dependency: %s", file_path)}, false
        }
        source := string(source_data)
        cursor := 0
        for cursor < len(source) {
            import_offset := strings.index(source[cursor:], "(import")
            if import_offset < 0 {
                break
            }
            import_start := cursor + import_offset
            after_head := import_start + len("(import")
            if after_head >= len(source) || !is_whitespace(source[after_head]) {
                cursor = after_head
                continue
            }
            quote_offset := strings.index(source[after_head:], "\"")
            if quote_offset < 0 {
                break
            }
            quote_start := after_head + quote_offset
            quote_end := quote_start + 1
            escaped := false
            for quote_end < len(source) {
                if escaped {
                    escaped = false
                } else if source[quote_end] == '\\' {
                    escaped = true
                } else if source[quote_end] == '"' {
                    break
                }
                quote_end += 1
            }
            if quote_end >= len(source) {
                break
            }
            import_path := unquote_string(source[quote_start:quote_end+1])
            if import_path != "" && is_source_import_path_from(file_path, import_path) {
                resolved, resolve_err, resolve_ok := resolve_source_import_path(file_path, import_path)
                if !resolve_ok {
                    delete(import_path)
                    delete(source_data)
                    return resolve_err, false
                }
                dependency_err, dependency_ok := collect_source_dependency_paths_recursive(
                    resolved,
                    visited_packages,
                    seen_paths,
                    paths,
                )
                delete(resolved)
                if !dependency_ok {
                    delete(import_path)
                    delete(source_data)
                    return dependency_err, false
                }
            } else if import_path != "" &&
                      (os.is_absolute_path(import_path) ||
                       is_relative_odin_import_path(import_path)) {
                odin_dir := import_path
                odin_dir_owned := false
                if !os.is_absolute_path(import_path) {
                    source_dir, _ := os.split_path(file_path)
                    if source_dir == "" {
                        source_dir = "."
                    }
                    joined, join_err := os.join_path(
                        {source_dir, import_path},
                        context.allocator,
                    )
                    if join_err == nil {
                        odin_dir = joined
                        odin_dir_owned = true
                    }
                }
                if os.exists(odin_dir) && os.is_dir(odin_dir) {
                    odin_source_abs, odin_source_err := os.get_absolute_path(
                        odin_dir,
                        context.allocator,
                    )
                    if odin_source_err == nil &&
                       !contains_text(odin_source_dirs[:], odin_source_abs) {
                        append(&odin_source_dirs, odin_source_abs)
                    } else if odin_source_err == nil {
                        delete(odin_source_abs)
                    }
                }
                if odin_dir_owned {
                    delete(odin_dir)
                }
            }
            if import_path != "" {
                delete(import_path)
            }
            cursor = quote_end + 1
        }
        delete(source_data)
    }

    for dir in odin_source_dirs {
        entries, entries_err := os.read_directory_by_path(dir, -1, context.allocator)
        if entries_err != nil {
            continue
        }
        for entry in entries {
            if entry.type != .Regular || !strings.has_suffix(entry.name, ".odin") {
                continue
            }
            odin_path, join_err := os.join_path({dir, entry.name}, context.allocator)
            if join_err == nil {
                _ = append_source_dependency_path(paths, seen_paths, odin_path)
                delete(odin_path)
            }
        }
        os.file_info_slice_delete(entries, context.allocator)
    }
    return Compile_Error{}, true
}

source_dependency_paths :: proc(path: string) -> (paths: [dynamic]string, err: Compile_Error, ok: bool) {
    visited_packages := make(map[string]bool)
    seen_paths := make(map[string]bool)
    defer {
        for key in visited_packages {
            delete(key)
        }
        delete(visited_packages)
        for key in seen_paths {
            delete(key)
        }
        delete(seen_paths)
    }
    err, ok = collect_source_dependency_paths_recursive(path, &visited_packages, &seen_paths, &paths)
    if !ok {
        delete_string_slice(&paths)
        return nil, err, false
    }
    sorted := sorted_unique_texts(paths[:])
    delete(paths)
    return sorted, Compile_Error{}, true
}

validate_package_files :: proc(dir: string, files: []Package_File) -> (package_name: string, err: Compile_Error, ok: bool) {
    package_name = files[0].package_name
    for file in files[1:] {
        if file.package_name != package_name {
            return "", Compile_Error{message = fmt.tprintf("source package files must declare the same package in %s", dir)}, false
        }
    }
    return package_name, Compile_Error{}, true
}

collect_package_import_aliases :: proc(files: []Package_File) -> (aliases: [dynamic]string, paths: [dynamic]string, err: Compile_Error, ok: bool) {
    for file in files {
        for top in file.forms {
            alias, path, ok_import := source_import_alias_and_path(top.form, file.path)
            if !ok_import {
                continue
            }
            if index, found := text_index(aliases[:], alias); found {
                if paths[index] == path {
                    delete(alias)
                    delete(path)
                    continue
                }
                return nil, nil, Compile_Error{message = fmt.tprintf("import alias refers to different paths in package: %s", alias), span = top.form.span}, false
            }
            append(&aliases, alias)
            append(&paths, path)
        }
        for top in file.forms {
            form := top.form
            if decl_head_name(form) != "import" {
                continue
            }
            source_alias, path, is_source_import := source_import_alias_and_path(form, file.path)
            if is_source_import {
                delete(source_alias)
                delete(path)
                continue
            }
            if len(form.items) == 3 && form.items[1].kind == .Symbol {
                alias := map_name(form.items[1].text)
                import_path := import_path_text(form.items[2])
                if index, found := text_index(aliases[:], alias); found {
                    if paths[index] == import_path {
                        delete(import_path)
                        continue
                    }
                    delete(import_path)
                    return nil, nil, Compile_Error{message = fmt.tprintf("import alias refers to different paths in package: %s", alias), span = form.items[1].span}, false
                }
                append(&aliases, alias)
                append(&paths, import_path)
            }
            if len(form.items) == 2 && form.items[1].kind == .String {
                path = import_path_text(form.items[1])
                if is_source_import_path(path) {
                    delete(path)
                    continue
                }
                alias := import_default_alias(path)
                if alias != "" {
                    if index, found := text_index(aliases[:], alias); found {
                        if paths[index] == path {
                            delete(path)
                            continue
                        }
                        delete(path)
                        return nil, nil, Compile_Error{message = fmt.tprintf("import alias refers to different paths in package: %s", alias), span = form.items[1].span}, false
                    }
                    append(&aliases, alias)
                    append(&paths, path)
                } else {
                    delete(path)
                }
            }
        }
    }
    return aliases, paths, Compile_Error{}, true
}

validate_package_conflicts :: proc(files: []Package_File) -> (Compile_Error, bool) {
    names: [dynamic]string
    defer delete(names)
    for file in files {
        for top in file.forms {
            form := top.form
            if form.kind != .List || len(form.items) < 2 || form.items[1].kind != .Symbol {
                continue
            }
            head := decl_head_name(form)
            if !is_top_level_decl_head(head) {
                continue
            }
            name := form.items[1].text
            if contains_text(names[:], name) {
                return Compile_Error{message = fmt.tprintf("duplicate top-level declaration in package: %s", name), span = form.items[1].span}, false
            }
            append(&names, name)
        }
    }
    aliases, paths, err_aliases, ok_aliases := collect_package_import_aliases(files)
    defer delete_string_slice(&aliases)
    defer delete_string_slice(&paths)
    if !ok_aliases {
        return err_aliases, false
    }
    for alias in aliases {
        if contains_text(names[:], alias) {
            return Compile_Error{message = fmt.tprintf("import alias conflicts with top-level declaration in package: %s", alias)}, false
        }
    }
    return Compile_Error{}, true
}

load_source_forms :: proc(dir, prefix: string, loaded_keys, import_keys: ^[dynamic]string, visiting: ^[dynamic]string) -> (Loaded_Forms, Compile_Error, bool) {
    key := fmt.tprintf("%s|%s", dir, prefix)
    if contains_text(loaded_keys[:], key) {
        return Loaded_Forms{}, Compile_Error{}, true
    }
    if contains_text(visiting[:], dir) {
        cycle_start := 0
        for item, i in visiting[:] {
            if item == dir {
                cycle_start = i
                break
            }
        }
        chain: [dynamic]string
        for item in visiting[cycle_start:] {
            append(&chain, item)
        }
        append(&chain, dir)
        return Loaded_Forms{}, Compile_Error{message = fmt.tprintf("cyclic source import: %s", strings.join(chain[:], " -> ", context.allocator))}, false
    }
    append(visiting, dir)
    defer resize(visiting, len(visiting)-1)

    files, err_files, ok_files := read_package_files(dir)
    if !ok_files {
        return Loaded_Forms{}, err_files, false
    }
    defer package_file_slice_delete(files)
    err_surface, ok_surface := validate_package_files_surface_internal_call_names(files[:])
    if !ok_surface {
        return Loaded_Forms{}, err_surface, false
    }
    package_name, err_package, ok_package := validate_package_files(dir, files[:])
    if !ok_package {
        return Loaded_Forms{}, err_package, false
    }
    err_conflicts, ok_conflicts := validate_package_conflicts(files[:])
    if !ok_conflicts {
        return Loaded_Forms{}, err_conflicts, false
    }
    all_forms: [dynamic]CST_Top_Form
    defer delete(all_forms)
    for file in files {
        for top in file.forms {
            append(&all_forms, top)
        }
    }
    locals := collect_local_decl_names(all_forms[:])
    defer delete(locals)
    private_macros := collect_private_macro_decl_names(all_forms[:])
    defer delete(private_macros)
    exported := collect_public_decl_names(all_forms[:])
    defer delete(exported)
    raw_dir, err_raw_dir, ok_raw_dir := source_package_dir(dir)
    if !ok_raw_dir {
        return Loaded_Forms{}, err_raw_dir, false
    }
    defer delete(raw_dir)
    raw_exported := collect_raw_odin_decl_names_from_dir(raw_dir)
    defer delete_string_slice(&raw_exported)
    aliases: [dynamic]Alias_Prefix
    defer alias_prefix_slice_delete(&aliases)
    err_core_alias, ok_core_alias := append_core_bare_symbol_alias(&aliases, dir)
    if !ok_core_alias {
        return Loaded_Forms{}, err_core_alias, false
    }
    result := Loaded_Forms{}
    for name in exported {
        append(&result.exports, strings.clone(name))
    }
    for name in raw_exported {
        append(&result.raw_exports, strings.clone(name))
    }
    if package_name != "" {
        self_prefix := prefix
        if self_prefix == "" {
            self_prefix = package_name
        }
        append_unique_string_clone(&result.source_aliases, package_name)
        if len(raw_exported) > 0 {
            raw_prefix := odin_package_import_alias(self_prefix)
            append_import_form_unique(&result.imports, import_keys, synthetic_import_decl(raw_prefix, raw_dir))
        }
        alias_exports := clone_string_slice(exported[:])
        alias_raw_exports := clone_string_slice(raw_exported[:])
        append(&aliases, Alias_Prefix{
            alias = strings.clone(package_name),
            prefix = strings.clone(self_prefix),
            raw_prefix = odin_package_import_alias(self_prefix),
            exports = alias_exports,
            raw_exports = alias_raw_exports,
            allow_unqualified_exports = false,
        })
    }

    for file in files {
        for top in file.forms {
            alias, import_path, ok_import := source_import_alias_and_path(top.form, file.path)
            if !ok_import {
                continue
            }
            resolved, err_resolve, ok_resolve := resolve_source_import_path(file.path, import_path)
            if !ok_resolve {
                delete(alias)
                delete(import_path)
                return result, err_resolve, false
            }
            nested_prefix := alias
            if prefix != "" {
                nested_prefix = fmt.tprintf("%s__%s", prefix, alias)
            }
            nested_import_keys: [dynamic]string
            nested, err_nested, ok_nested := load_source_forms(resolved, nested_prefix, loaded_keys, &nested_import_keys, visiting)
            delete_string_slice(&nested_import_keys)
            delete(resolved)
            if !ok_nested {
                delete(alias)
                delete(import_path)
                return result, err_nested, false
            }
            nested_exports := clone_string_slice(nested.exports[:])
            nested_raw_exports := clone_string_slice(nested.raw_exports[:])
            append(&aliases, Alias_Prefix{
                alias = alias,
                prefix = strings.clone(nested_prefix),
                raw_prefix = odin_package_import_alias(nested_prefix),
                exports = nested_exports,
                raw_exports = nested_raw_exports,
                refer_names = source_import_refer_names(top.form),
                allow_unqualified_exports = source_import_form_has_refer(top.form),
            })
            append_unique_string_clone(&result.source_aliases, alias)
            for nested_alias in nested.source_aliases {
                append_unique_string_clone(&result.source_aliases, nested_alias)
            }
            for form in nested.imports {
                append_import_form_unique(&result.imports, import_keys, clone_cst_top_form(form))
            }
            for form in nested.decls {
                append(&result.decls, clone_cst_top_form(form))
            }
            loaded_forms_delete(&nested)
            delete(import_path)
        }
    }

    for file in files {
        for top in file.forms {
            form := top.form
            head := decl_head_name(form)
            if head == "package" {
                if prefix == "" {
                    result.has_package = true
                    result.package_decl = synthetic_package_decl(package_name)
                }
                continue
            }
            alias, import_path, is_source_import := source_import_alias_and_path(form, file.path)
            if is_source_import {
                delete(alias)
                delete(import_path)
                continue
            }
            if head == "import" {
                append_import_form_unique(&result.imports, import_keys, rewrite_relative_odin_import_form(file.path, top))
                continue
            }
            rewritten, err_rewrite, ok_rewrite := rewrite_top_form(top, locals[:], private_macros[:], aliases[:], prefix)
            if !ok_rewrite {
                return result, err_rewrite, false
            }
            append(&result.decls, rewritten)
        }
    }

    append(loaded_keys, key)
    return result, Compile_Error{}, true
}

load_root_file_forms :: proc(
    path: string,
    extra_imports: []CST_Top_Form = nil,
) -> (Loaded_Forms, Compile_Error, bool) {
    files, err_files, ok_files := read_root_package_files(path)
    if !ok_files {
        return Loaded_Forms{}, err_files, false
    }
    if len(files) == 0 {
        return Loaded_Forms{}, Compile_Error{message = fmt.tprintf("could not read file: %s", path)}, false
    }
    err_surface, ok_surface := validate_package_files_surface_internal_call_names(files[:])
    if !ok_surface {
        return Loaded_Forms{}, err_surface, false
    }

    if files[0].package_name != "" {
        dir, _ := os.split_path(path)
        if dir == "" {
            dir = "."
        }
        _, err_package, ok_package := validate_package_files(dir, files[:])
        if !ok_package {
            return Loaded_Forms{}, err_package, false
        }
        err_conflicts, ok_conflicts := validate_package_conflicts(files[:])
        if !ok_conflicts {
            return Loaded_Forms{}, err_conflicts, false
        }
    }

    aliases: [dynamic]Alias_Prefix
    import_keys: [dynamic]string
    loaded_keys: [dynamic]string
    visiting: [dynamic]string
    result := Loaded_Forms{}
    all_forms := flatten_package_forms(files[:])
    for top in extra_imports {
        append(&all_forms, top)
    }
    locals := collect_local_decl_names(all_forms[:])
    defer delete(locals)
    private_macros := collect_private_macro_decl_names(all_forms[:])
    defer delete(private_macros)
    err_core_alias, ok_core_alias := append_core_bare_symbol_alias(&aliases, path)
    if !ok_core_alias {
        return result, err_core_alias, false
    }

    for file in files {
        for top in file.forms {
            alias, import_path, ok_import := source_import_alias_and_path(top.form, file.path)
            if !ok_import {
                continue
            }
            resolved, err_resolve, ok_resolve := resolve_source_import_path(file.path, import_path)
            if !ok_resolve {
                return result, err_resolve, false
            }
            nested_import_keys: [dynamic]string
            nested, err_nested, ok_nested := load_source_forms(resolved, alias, &loaded_keys, &nested_import_keys, &visiting)
            if !ok_nested {
                return result, err_nested, false
            }
            nested_exports := nested.exports
            nested_raw_exports := nested.raw_exports
            append(&aliases, Alias_Prefix{
                alias = alias,
                prefix = alias,
                raw_prefix = odin_package_import_alias(alias),
                exports = nested_exports,
                raw_exports = nested_raw_exports,
                refer_names = source_import_refer_names(top.form),
                allow_unqualified_exports = source_import_form_has_refer(top.form),
            })
            append_unique_string_clone(&result.source_aliases, alias)
            for nested_alias in nested.source_aliases {
                append_unique_string_clone(&result.source_aliases, nested_alias)
            }
            for form in nested.imports {
                append_import_form_unique(&result.imports, &import_keys, clone_cst_top_form(form))
            }
            for form in nested.decls {
                append(&result.decls, clone_cst_top_form(form))
            }
        }
    }
    for top in extra_imports {
        alias, import_path, ok_import := source_import_alias_and_path(top.form, path)
        if !ok_import {
            continue
        }
        resolved, err_resolve, ok_resolve := resolve_source_import_path(path, import_path)
        if !ok_resolve {
            return result, err_resolve, false
        }
        nested_import_keys: [dynamic]string
        nested, err_nested, ok_nested := load_source_forms(resolved, alias, &loaded_keys, &nested_import_keys, &visiting)
        if !ok_nested {
            return result, err_nested, false
        }
        nested_exports := nested.exports
        nested_raw_exports := nested.raw_exports
        append(&aliases, Alias_Prefix{
            alias = alias,
            prefix = alias,
            raw_prefix = odin_package_import_alias(alias),
            exports = nested_exports,
            raw_exports = nested_raw_exports,
            refer_names = source_import_refer_names(top.form),
            allow_unqualified_exports = source_import_form_has_refer(top.form),
        })
        append_unique_string_clone(&result.source_aliases, alias)
        for nested_alias in nested.source_aliases {
            append_unique_string_clone(&result.source_aliases, nested_alias)
        }
        for form in nested.imports {
            append_import_form_unique(&result.imports, &import_keys, clone_cst_top_form(form))
        }
        for form in nested.decls {
            append(&result.decls, clone_cst_top_form(form))
        }
    }

    for file in files {
        for top in file.forms {
            form := top.form
            head := decl_head_name(form)
            if head == "package" {
                result.has_package = true
                result.package_decl = top
                continue
            }
            source_alias, source_path, is_source_import := source_import_alias_and_path(form, file.path)
            if is_source_import {
                delete(source_alias)
                delete(source_path)
                continue
            }
            if head == "import" {
                append_import_form_unique(&result.imports, &import_keys, rewrite_relative_odin_import_form(file.path, top))
                continue
            }
            rewritten, err_rewrite, ok_rewrite := rewrite_top_form(top, locals[:], private_macros[:], aliases[:], "")
            if !ok_rewrite {
                return result, err_rewrite, false
            }
            append(&result.decls, rewritten)
        }
    }
    for top in extra_imports {
        source_alias, source_path, is_source_import :=
            source_import_alias_and_path(top.form, path)
        if is_source_import {
            delete(source_alias)
            delete(source_path)
            continue
        }
        if decl_head_name(top.form) == "import" {
            append_import_form_unique(
                &result.imports,
                &import_keys,
                rewrite_relative_odin_import_form(path, top),
            )
        }
    }
    return result, Compile_Error{}, true
}

load_root_source_forms :: proc(forms: []CST_Top_Form) -> (Loaded_Forms, Compile_Error, bool) {
    aliases: [dynamic]Alias_Prefix
    import_keys: [dynamic]string
    loaded_keys: [dynamic]string
    visiting: [dynamic]string
    result := Loaded_Forms{}
    locals := collect_local_decl_names(forms)
    defer delete(locals)
    private_macros := collect_private_macro_decl_names(forms)
    defer delete(private_macros)
    err_core_alias, ok_core_alias := append_core_bare_symbol_alias(&aliases, ".")
    if !ok_core_alias {
        return result, err_core_alias, false
    }

    for top in forms {
        alias, import_path, ok_import := source_import_alias_and_path(top.form)
        if !ok_import {
            continue
        }
        resolved, err_resolve, ok_resolve := resolve_source_import_path(".", import_path)
        if !ok_resolve {
            return result, err_resolve, false
        }
        nested_import_keys: [dynamic]string
        nested, err_nested, ok_nested := load_source_forms(resolved, alias, &loaded_keys, &nested_import_keys, &visiting)
        if !ok_nested {
            return result, err_nested, false
        }
        nested_exports := nested.exports
        nested_raw_exports := nested.raw_exports
        append(&aliases, Alias_Prefix{
            alias = alias,
            prefix = alias,
            raw_prefix = odin_package_import_alias(alias),
            exports = nested_exports,
            raw_exports = nested_raw_exports,
            refer_names = source_import_refer_names(top.form),
            allow_unqualified_exports = source_import_form_has_refer(top.form),
        })
        append_unique_string_clone(&result.source_aliases, alias)
        for nested_alias in nested.source_aliases {
            append_unique_string_clone(&result.source_aliases, nested_alias)
        }
        for form in nested.imports {
            append_import_form_unique(&result.imports, &import_keys, clone_cst_top_form(form))
        }
        for form in nested.decls {
            append(&result.decls, clone_cst_top_form(form))
        }
    }

    for top in forms {
        form := top.form
        head := decl_head_name(form)
        if head == "package" {
            result.has_package = true
            result.package_decl = top
            continue
        }
        source_alias, source_path, is_source_import := source_import_alias_and_path(form, ".")
        if is_source_import {
            delete(source_alias)
            delete(source_path)
            continue
        }
        if head == "import" {
            append_import_form_unique(&result.imports, &import_keys, top)
            continue
        }
        rewritten, err_rewrite, ok_rewrite := rewrite_top_form(top, locals[:], private_macros[:], aliases[:], "")
        if !ok_rewrite {
            return result, err_rewrite, false
        }
        append(&result.decls, rewritten)
    }
    return result, Compile_Error{}, true
}
