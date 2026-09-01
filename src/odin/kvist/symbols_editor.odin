package kvist

import "core:fmt"
import "core:os"
import "core:sort"
import "core:strings"
import "base:runtime"

symbols_escape_doc_text :: proc(text: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    lines := symbols_doc_lines_from_string(text)
    defer delete(lines)
    symbols_write_escaped_doc(&builder, lines[:])
    return strings.to_string(builder)
}

symbols_record_name :: proc(line: string) -> string {
    first_tab := strings.index(line, "\t")
    if first_tab < 0 {
        return ""
    }
    rest := line[first_tab+1:]
    second_tab := strings.index(rest, "\t")
    if second_tab < 0 {
        return ""
    }
    return rest[:second_tab]
}

symbols_record_key :: proc(line: string) -> string {
    fields, ok := symbols_split_record_fields(line)
    if !ok || len(fields) < 2 {
        return ""
    }
    return fmt.tprintf("%s\t%s", fields[0], fields[1])
}

symbols_record_detail :: proc(line: string) -> string {
    first_tab := strings.index(line, "\t")
    if first_tab < 0 {
        return ""
    }
    rest := line[first_tab+1:]
    for _ in 0..<3 {
        tab := strings.index(rest, "\t")
        if tab < 0 {
            return ""
        }
        rest = rest[tab+1:]
    }
    tab := strings.index(rest, "\t")
    if tab < 0 {
        return rest
    }
    return rest[:tab]
}

symbols_append_unique_records :: proc(builder: ^strings.Builder, seen: ^map[string]bool, output: string) {
    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)
    for line in lines {
        if line == "" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile" {
            continue
        }
        key := symbols_record_key(line)
        if key == "" {
            continue
        }
        if seen[key] {
            continue
        }
        seen[key] = true
        strings.write_string(builder, line)
        strings.write_byte(builder, '\n')
    }
}

symbols_append_core_helper_alias_records :: proc(builder: ^strings.Builder, seen: ^map[string]bool, output: string) {
    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)
    for line in lines {
        if line == "" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile" {
            continue
        }
        fields, ok_fields := symbols_split_record_fields(line)
        _ = ok_fields
        if len(fields) < 7 {
            delete(fields)
            continue
        }
        for len(fields) < 8 {
            append(&fields, "")
        }
        name := fields[1]
        if !strings.has_prefix(name, "core.") || len(name) <= len("core.") {
            delete(fields)
            continue
        }
        bare_name := name[len("core."):]
        key := fmt.tprintf("kvist helper\t%s", bare_name)
        if seen[key] {
            delete(key)
            delete(fields)
            continue
        }
        seen[key] = true
        fmt.sbprintf(builder, "kvist helper\t%s\t%s\t%s\tkvist:core\t%s\t%s\t%s\n", bare_name, fields[2], fields[3], fields[5], fields[6], fields[7])
        delete(fields)
    }
}

symbols_split_record_fields :: proc(line: string) -> (fields: [dynamic]string, ok: bool) {
    rest := line
    for {
        tab := strings.index(rest, "\t")
        if tab < 0 {
            append(&fields, rest)
            break
        }
        append(&fields, rest[:tab])
        rest = rest[tab+1:]
    }
    return fields, len(fields) >= 7
}

symbols_top_level_kind_exported :: proc(kind: string) -> bool {
    switch kind {
    case "const", "var", "struct", "enum", "union", "proc", "macro", "source":
        return true
    case:
        return false
    }
}

symbols_append_source_package_records :: proc(builder: ^strings.Builder, seen: ^map[string]bool, import_path, alias, package_file, output: string, package_kind: string = "") {
    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)
    for line in lines {
        if line == "" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile" {
            continue
        }
        fields, ok_fields := symbols_split_record_fields(line)
        _ = ok_fields
        if len(fields) < 4 {
            delete(fields)
            continue
        }
        for len(fields) < 7 {
            append(&fields, "")
        }
        kind := fields[0]
        name := fields[1]
        if !symbols_top_level_kind_exported(kind) {
            delete(fields)
            continue
        }
        if strings.has_prefix(symbols_record_detail(line), "private") {
            delete(fields)
            continue
        }
        line_text := fields[2]
        column_text := fields[3]
        signature := fields[5]
        doc := fields[6]
        kind_text := kind
        if package_kind != "" {
            kind_text = package_kind
        }
        dot_name := fmt.tprintf("%s.%s", alias, name)
        if !seen[dot_name] {
            seen[dot_name] = true
            fmt.sbprintf(builder, "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", kind_text, dot_name, line_text, column_text, import_path, signature, doc, package_file)
        }
        delete(fields)
    }
}

source_package_anchor_file :: proc(files: []Package_File) -> string {
    for file in files {
        _, name := os.split_path(file.path)
        dir, _ := os.split_path(file.path)
        if is_package_anchor_filename(dir, name) {
            return file.path
        }
    }
    if len(files) > 0 {
        return files[0].path
    }
    return ""
}

symbols_append_source_package_import_record :: proc(builder: ^strings.Builder, seen: ^map[string]bool, alias, import_path, file_path: string) {
    if alias == "" || file_path == "" {
        return
    }
    key := fmt.tprintf("source import\t%s", alias)
    if seen[key] {
        return
    }
    seen[key] = true
    temp := strings.builder_make()
    defer strings.builder_destroy(&temp)
    doc_lines := symbols_doc_lines_from_string(fmt.tprintf("Source package import %s.", import_path))
    defer delete(doc_lines)
    symbols_write_record_doc_file(&temp, "source import", alias, 1, 1, import_path, fmt.tprintf("(import %s \"%s\")", alias, import_path), doc_lines[:], file_path)
    strings.write_string(builder, strings.to_string(temp))
    strings.write_byte(builder, '\n')
}

symbols_append_resolved_source_import_records :: proc(
    builder: ^strings.Builder,
    seen: ^map[string]bool,
    importer_path, import_path, alias, package_kind: string,
    result_allocator: runtime.Allocator,
) -> (Compile_Error, bool) {
    resolved, err_resolve, ok_resolve := resolve_source_import_path(importer_path, import_path)
    if !ok_resolve {
        return clone_compile_error(err_resolve, result_allocator), false
    }
    defer delete(resolved)

    files, err_files, ok_files := read_package_files(resolved)
    if !ok_files {
        return clone_compile_error(err_files, result_allocator), false
    }
    defer package_file_slice_delete(files)

    _, err_package, ok_package := validate_package_files(resolved, files[:])
    if !ok_package {
        return clone_compile_error(err_package, result_allocator), false
    }

    anchor := source_package_anchor_file(files[:])
    symbols_append_source_package_import_record(builder, seen, alias, import_path, anchor)
    for file in files {
        context.allocator = result_allocator
        package_output, package_err, ok_package_output := symbols_source(file.source)
        context.allocator = context.temp_allocator
        if !ok_package_output {
            return package_err, false
        }
        symbols_append_source_package_records(builder, seen, import_path, alias, file.path, package_output, package_kind)
        context.allocator = result_allocator
        delete(package_output)
        context.allocator = context.temp_allocator
    }
    return Compile_Error{}, true
}

symbols_append_local_package_records :: proc(builder: ^strings.Builder, seen: ^map[string]bool, file_path, output: string) {
    lines := strings.split_lines(output, context.allocator)
    defer delete(lines)
    for line in lines {
        if line == "" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc" || line == "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile" {
            continue
        }
        fields, ok_fields := symbols_split_record_fields(line)
        _ = ok_fields
        if len(fields) < 4 {
            delete(fields)
            continue
        }
        for len(fields) < 7 {
            append(&fields, "")
        }
        kind := fields[0]
        name := fields[1]
        line_text := fields[2]
        column_text := fields[3]
        detail := fields[4]
        signature := fields[5]
        doc := fields[6]
        key := fmt.tprintf("%s\t%s", kind, name)
        if seen[key] {
            delete(fields)
            continue
        }
        seen[key] = true
        fmt.sbprintf(builder, "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", kind, name, line_text, column_text, detail, signature, doc, file_path)
        delete(fields)
    }
}

editor_root_package_files :: proc(path, source: string) -> ([]Package_File, bool) {
	forms, err_forms, ok_forms := read_kvist_top_forms(source)
    if !ok_forms {
        _ = err_forms
        return nil, false
    }
    package_name := ""
    for top in forms {
        if decl_head_name(top.form) == "package" && len(top.form.items) == 2 && top.form.items[1].kind == .Symbol {
            package_name = top.form.items[1].text
            break
        }
    }
    if package_name == "" {
        delete_borrowed_cst_top_form_slice(&forms)
        return nil, false
    }

    dir, file_name := os.split_path(path)
    if dir == "" {
        delete_borrowed_cst_top_form_slice(&forms)
        return nil, false
    }

    entries, dir_err := os.read_directory_by_path(dir, -1, context.allocator)
    if dir_err != nil {
        delete_borrowed_cst_top_form_slice(&forms)
        return nil, false
    }
    defer os.file_info_slice_delete(entries, context.allocator)

    has_anchor := false
    matched: [dynamic]Package_File
    for entry in entries {
        if entry.type != .Regular || !strings.has_suffix(entry.name, ".kvist") {
            continue
        }
        file_path, join_err := os.join_path({dir, entry.name}, context.allocator)
        if join_err != nil {
            return nil, false
        }
        if entry.name == file_name {
            if is_package_anchor_filename(dir, entry.name) {
                has_anchor = true
            }
            append(&matched, Package_File{path = file_path, path_owned = true, source = source, package_name = package_name, forms = forms})
            continue
        }
        data, read_err := os.read_entire_file_from_path(file_path, context.allocator)
        if read_err != nil {
            continue
        }
        file_source := string(data)
		file_forms, _, ok_file_forms := read_kvist_top_forms(file_source)
        if !ok_file_forms {
            delete(data)
            continue
        }
        file_package_name := ""
        for top in file_forms {
            if decl_head_name(top.form) == "package" && len(top.form.items) == 2 && top.form.items[1].kind == .Symbol {
                file_package_name = top.form.items[1].text
                break
            }
        }
        if file_package_name != package_name {
            delete_borrowed_cst_top_form_slice(&file_forms)
            delete(data)
            continue
        }
        if is_package_anchor_filename(dir, entry.name) {
            has_anchor = true
        }
        append(&matched, Package_File{path = file_path, path_owned = true, source = file_source, package_name = file_package_name, forms = file_forms})
    }

    if len(matched) == 0 {
        delete_borrowed_cst_top_form_slice(&forms)
        return nil, false
    }
    if !has_anchor {
        files: [dynamic]Package_File
        append(&files, Package_File{path = path, source = source, package_name = package_name, forms = forms})
        return files[:], true
    }
    return matched[:], true
}

source_package_symbols_source :: proc(importer_path, import_path: string) -> (package_file, output: string, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    resolved, err_resolve, ok_resolve := resolve_source_import_path(importer_path, import_path)
    if !ok_resolve {
        return "", "", clone_compile_error(err_resolve, result_allocator), false
    }
    defer delete(resolved)
    files, err_files, ok_files := read_package_files(resolved)
    if !ok_files {
        return "", "", clone_compile_error(err_files, result_allocator), false
    }
    defer package_file_slice_delete(files)
    _, err_package, ok_package := validate_package_files(resolved, files[:])
    if !ok_package {
        return "", "", clone_compile_error(err_package, result_allocator), false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile\n")
    seen := make(map[string]bool)
    defer delete(seen)
    for file in files {
        context.allocator = result_allocator
        package_output, package_err, ok_package_output := symbols_source(file.source)
        context.allocator = context.temp_allocator
        if !ok_package_output {
            return "", "", clone_compile_error(package_err, result_allocator), false
        }
        symbols_append_source_package_records(&builder, &seen, import_path, import_default_alias(import_path), file.path, package_output)
        context.allocator = result_allocator
        delete(package_output)
        context.allocator = context.temp_allocator
    }
    resolved_copy, _ := strings.clone(resolved, result_allocator)
    output_copy, _ := strings.clone(strings.to_string(builder), result_allocator)
    return resolved_copy, output_copy, Compile_Error{}, true
}

repo_root_for_path :: proc(path: string) -> (string, bool) {
    current := path
    owned_current := ""
    if current != "" && !os.is_absolute_path(current) {
        absolute, abs_err := os.get_absolute_path(current, context.allocator)
        if abs_err == nil {
            current = absolute
            owned_current = absolute
        }
    }
    current_end := len(current)
    for current_end > 1 && is_path_separator(current[current_end-1]) {
        current_end -= 1
    }
    current = current[:current_end]
    if current != "" && !os.is_dir(current) {
        last_slash := -1
        for i := len(current) - 1; i >= 0; i -= 1 {
            if is_path_separator(current[i]) {
                last_slash = i
                break
            }
        }
        if last_slash < 0 {
            current = ""
        } else if last_slash == 0 {
            current = current[:1]
        } else {
            current = current[:last_slash]
        }
    }
    for current != "" {
        markers := [2][3]string{
            {"src", "cli", "kvist"},
            {"cmd", "kvist", "main.odin"},
        }
        for parts, marker_index in markers {
            marker: string
            err: os.Error
            if marker_index == 0 {
                marker, err = os.join_path({current, parts[0], parts[1], parts[2], "main.odin"}, context.allocator)
            } else {
                marker, err = os.join_path({current, parts[0], parts[1], parts[2]}, context.allocator)
            }
            if err == nil {
                if os.exists(marker) {
                    delete(marker)
                    root := strings.clone(current)
                    if owned_current != "" {
                        delete(owned_current)
                    }
                    return root, true
                }
                delete(marker)
            }
        }
        trimmed_end := len(current)
        for trimmed_end > 1 && is_path_separator(current[trimmed_end-1]) {
            trimmed_end -= 1
        }
        trimmed := current[:trimmed_end]
        last_slash := -1
        for i := len(trimmed) - 1; i >= 0; i -= 1 {
            if is_path_separator(trimmed[i]) {
                last_slash = i
                break
            }
        }
        parent := ""
        if last_slash == 0 {
            parent = trimmed[:1]
        } else if last_slash > 0 {
            parent = trimmed[:last_slash]
        }
        if parent == "" || parent == current {
            break
        }
        current = parent
    }
    if owned_current != "" {
        delete(owned_current)
    }
    return "", false
}

existing_dir_clone :: proc(path: string) -> (string, bool) {
    if path != "" && os.exists(path) && os.is_dir(path) {
        return strings.clone(path), true
    }
    return "", false
}

existing_package_root_clone :: proc(path: string) -> (string, bool) {
    absolute_path, absolute_err := os.get_absolute_path(path, context.allocator)
    if absolute_err != nil {
        return "", false
    }
    defer delete(absolute_path)
    core_path, join_err := os.join_path({absolute_path, "core", "core.kvist"}, context.allocator)
    if join_err != nil {
        return "", false
    }
    defer delete(core_path)
    if !os.exists(core_path) || os.is_dir(core_path) {
        return "", false
    }
    return existing_dir_clone(absolute_path)
}

existing_joined_package_root_clone :: proc(parts: []string) -> (string, bool) {
    candidate, join_err := os.join_path(parts, context.allocator)
    if join_err != nil {
        return "", false
    }
    defer delete(candidate)
    return existing_package_root_clone(candidate)
}

kvist_source_package_roots :: proc(anchor_path: string = ".") -> (roots: [dynamic]string) {
    _ = anchor_path
    configured_root, configured := os.lookup_env("KVIST_ROOT", context.allocator)
    if configured {
        defer delete(configured_root)
        if root, ok := existing_package_root_clone(configured_root); ok {
            append(&roots, root)
        }
        return roots
    }

    executable_dir, ok_executable := kvist_executable_dir()
    if !ok_executable {
        return roots
    }
    defer delete(executable_dir)

    install_root, _ := os.split_path(executable_dir)
    if root, ok := existing_package_root_clone(install_root); ok {
        append(&roots, root)
        return roots
    }
    if root, ok := existing_joined_package_root_clone({executable_dir, "src", "kvist"}); ok {
        append(&roots, root)
    }

    return roots
}

kvist_executable_dir :: proc() -> (string, bool) {
    executable_dir, executable_err := os.get_executable_directory(context.allocator)
    if executable_err != nil {
        return "", false
    }
    return executable_dir, true
}

is_path_separator :: proc(ch: byte) -> bool {
    return ch == '/' || ch == '\\'
}

file_location_for_snippet :: proc(root, relative, snippet: string) -> (file: string, line, column: int, ok: bool) {
    path, join_err := os.join_path({root, relative}, context.allocator)
    if join_err != nil {
        return "", 0, 0, false
    }
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        delete(path)
        return "", 0, 0, false
    }
    source := string(data)
    idx := strings.index(source, snippet)
    if idx < 0 {
        delete(data)
        delete(path)
        return "", 0, 0, false
    }
    line, column, _, _ = source_position(source, idx)
    delete(data)
    return path, line, column, true
}

symbols_write_record_doc_file :: proc(builder: ^strings.Builder, kind, name: string, line, column: int, detail, signature: string, doc_lines: []string, file: string) {
    fmt.sbprintf(builder, "%s\t%s\t%d\t%d\t%s\t%s\t", kind, name, line, column, detail, signature)
    symbols_write_escaped_doc(builder, doc_lines)
    fmt.sbprintf(builder, "\t%s\n", file)
}

editor_builtin_symbols_append :: proc(builder: ^strings.Builder, seen: ^map[string]bool, repo_root: string) {
    for entry in BUILTIN_SOURCE_ENTRIES {
        temp := strings.builder_make()
        defer strings.builder_destroy(&temp)
        file, line, column, ok := file_location_for_snippet(repo_root, entry.relative, entry.snippet)
        if !ok {
            continue
        }
        switch entry.name {
        case "type":
            symbols_write_record_doc_file(&temp, "kvist form", entry.name, line, column, "", "(type value)", symbols_doc_lines_from_string("Return a comparable type descriptor. Native values report their Kvist type, concrete functions report their procedure signature, type names report typeid, and Data reports its runtime kind.")[:], file)
        case "typeid":
            symbols_write_record_doc_file(&temp, "kvist form", entry.name, line, column, "", "(typeid Head Arg...)", symbols_doc_lines_from_string("Instantiate an Odin polymorphic type constructor or pass a type value. For example, (typeid chan.Chan int) lowers to chan.Chan(int) in both type and value positions.")[:], file)
        case:
        }
        symbols_append_unique_records(builder, seen, strings.to_string(temp))
        delete(file)
    }
}

editor_language_symbols_append :: proc(builder: ^strings.Builder, seen: ^map[string]bool, repo_root: string) {
    for entry in LANGUAGE_SOURCE_ENTRIES {
        file, line, column, ok := file_location_for_snippet(repo_root, entry.relative, entry.snippet)
        if !ok {
            continue
        }
        temp := strings.builder_make()
        defer strings.builder_destroy(&temp)
        signature := language_entry_signature(entry)
        doc := language_entry_doc(entry)
        doc_lines := symbols_doc_lines_from_string(doc)
        symbols_write_record_doc_file(&temp, entry.kind, entry.name, line, column, entry.relative, signature, doc_lines[:], file)
        delete(doc_lines)
        symbols_append_unique_records(builder, seen, strings.to_string(temp))
        delete(file)
    }
}

imported_symbols_source :: proc(path, source: string) -> (output: string, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

	forms, err_forms, ok_forms := read_kvist_top_forms(source)
    if !ok_forms {
        return "", clone_compile_error(err_forms, result_allocator), false
    }
    defer delete_borrowed_cst_top_form_slice(&forms)
    odin_root, have_odin_root := odin_root_path()
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile\n")
    seen := make(map[string]bool)
    defer delete(seen)
    for top in forms {
        entry, ok_import := import_entry_from_form(top.form)
        if !ok_import {
            continue
        }
        alias, import_path, ok_source_import := source_import_alias_and_path(top.form, path)
        if ok_source_import {
            package_kind := ""
            if strings.has_prefix(import_path, "kvist:") {
                package_kind = "kvist package"
            }
            err_package, ok_package := symbols_append_resolved_source_import_records(&builder, &seen, path, import_path, alias, package_kind, result_allocator)
            if !ok_package {
                return "", err_package, false
            }
            continue
        }
        if strings.has_prefix(entry.path, "kvist:") {
            continue
        }
        if !have_odin_root {
            continue
        }
        dir, ok_dir := odin_import_dir(odin_root, entry.path)
        if !ok_dir {
            continue
        }
        imported_symbols_scan_odin_dir(&builder, entry.alias, entry.path, dir)
        delete(dir)
    }
    return strings.clone(strings.to_string(builder), result_allocator), {}, true
}

editor_core_package_symbols_append :: proc(builder: ^strings.Builder, seen: ^map[string]bool, result_allocator: runtime.Allocator) {
    context.allocator = result_allocator
    package_output, ok_package := package_symbols_source("kvist:core", "core", "kvist package")
    context.allocator = context.temp_allocator
    if !ok_package {
        return
    }
    symbols_append_unique_records(builder, seen, package_output)
    symbols_append_core_helper_alias_records(builder, seen, package_output)
    context.allocator = result_allocator
    delete(package_output)
    context.allocator = context.temp_allocator
}

editor_symbols_source :: proc(path, source: string) -> (output: string, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\tfile\n")

    seen := make(map[string]bool)
    defer delete(seen)
    repo_root, _ := repo_root_for_path(path)
    if !os.exists(path) {
        cwd_repo_root, ok_cwd_repo_root := repo_root_for_path(".")
        if ok_cwd_repo_root {
            repo_root = cwd_repo_root
        }
    }

    package_files, ok_package_files := editor_root_package_files(path, source)
    files_for_imports: [dynamic]Package_File
    defer delete(files_for_imports)
    if ok_package_files {
        for file in package_files {
            context.allocator = result_allocator
            local_output, local_err, ok_local := symbols_source(file.source)
            context.allocator = context.temp_allocator
            if !ok_local {
                return "", local_err, false
            }
            symbols_append_local_package_records(&builder, &seen, file.path, local_output)
            symbols_append_local_field_records(&builder, &seen, file.path, file.source, file.forms[:])
            context.allocator = result_allocator
            delete(local_output)
            context.allocator = context.temp_allocator
            append(&files_for_imports, file)
        }
    } else {
		forms, err_forms, ok_forms := read_kvist_top_forms(source)
        if !ok_forms {
            return "", clone_compile_error(err_forms, result_allocator), false
        }
        defer delete_borrowed_cst_top_form_slice(&forms)
        context.allocator = result_allocator
        local_output, local_err, ok_local := symbols_source(source)
        context.allocator = context.temp_allocator
        if !ok_local {
            return "", local_err, false
        }
        symbols_append_local_package_records(&builder, &seen, path, local_output)
        symbols_append_local_field_records(&builder, &seen, path, source, forms[:])
        context.allocator = result_allocator
        delete(local_output)
        context.allocator = context.temp_allocator
        append(&files_for_imports, Package_File{path = path, source = source, forms = forms})
    }

    editor_core_package_symbols_append(&builder, &seen, result_allocator)

    for import_file in files_for_imports {
        for top in import_file.forms {
            alias, import_path, ok_source_import := source_import_alias_and_path(top.form, import_file.path)
            if ok_source_import {
                package_kind := ""
                if strings.has_prefix(import_path, "kvist:") {
                    package_kind = "kvist package"
                }
                err_package, ok_package := symbols_append_resolved_source_import_records(&builder, &seen, import_file.path, import_path, alias, package_kind, result_allocator)
                if !ok_package {
                    return "", err_package, false
                }
                continue
            }
        }
    }

    for import_file in files_for_imports {
        context.allocator = result_allocator
        imported_output, imported_err, ok_imported := imported_symbols_source(import_file.path, import_file.source)
        context.allocator = context.temp_allocator
        if !ok_imported {
            return "", imported_err, false
        }
        symbols_append_unique_records(&builder, &seen, imported_output)
        context.allocator = result_allocator
        delete(imported_output)
        context.allocator = context.temp_allocator
    }

    if repo_root != "" {
        editor_builtin_symbols_append(&builder, &seen, repo_root)
        editor_language_symbols_append(&builder, &seen, repo_root)
    }
    context.allocator = result_allocator
    builtin_output := builtin_symbols_source()
    context.allocator = context.temp_allocator
    symbols_append_unique_records(&builder, &seen, builtin_output)
    context.allocator = result_allocator
    delete(builtin_output)
    context.allocator = context.temp_allocator
    context.allocator = result_allocator
    language_output := language_symbols_source()
    context.allocator = context.temp_allocator
    symbols_append_unique_records(&builder, &seen, language_output)
    context.allocator = result_allocator
    delete(language_output)
    context.allocator = context.temp_allocator
    return strings.clone(strings.to_string(builder), result_allocator), {}, true
}

package_symbols_source :: proc(import_path, alias: string, package_kind: string = "") -> (output: string, ok: bool) {
    result_allocator := context.allocator

    resolved_alias := alias
    if resolved_alias == "" {
        resolved_alias = import_default_alias(import_path)
    }
    if resolved_alias == "" {
        return "", false
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "kind\tname\tline\tcolumn\tdetail\tsignature\tdoc\n")
    resolved, err_resolve, ok_resolve := resolve_source_import_path(".", import_path)
    if !ok_resolve {
        _ = err_resolve
        return "", false
    }
    defer delete(resolved)
    files, err_files, ok_files := read_package_files(resolved)
    if !ok_files {
        _ = err_files
        return "", false
    }
    defer package_file_slice_delete(files)
    _, err_package, ok_package := validate_package_files(resolved, files[:])
    if !ok_package {
        _ = err_package
        return "", false
    }
    seen := make(map[string]bool)
    defer delete(seen)
    for file in files {
        package_output, package_err, ok_package_output := symbols_source(file.source)
        if !ok_package_output {
            _ = package_err
            return "", false
        }
        symbols_append_source_package_records(&builder, &seen, import_path, resolved_alias, file.path, package_output, package_kind)
        delete(package_output)
    }
    return strings.clone(strings.to_string(builder), result_allocator), true
}
