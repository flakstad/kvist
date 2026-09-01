package kvist

import "core:fmt"
import "core:os"
import "core:sort"
import "core:strings"
import "core:time"
import "base:runtime"

decl_head_name :: proc(form: CST_Form) -> string {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return ""
    }
    return form.items[0].text
}

is_private_decl_head :: proc(head: string) -> bool {
    switch head {
    case "def-", "defvar-", "defstruct-", "defenum-", "defunion-", "defn-", "defmacro-", "deftransform-", "defiter-":
        return true
    case:
        return false
    }
}

is_top_level_decl_head :: proc(head: string) -> bool {
    switch head {
    case "def", "def-", "defvar", "defvar-", "defstruct", "defstruct-", "defenum", "defenum-", "defunion", "defunion-", "defn", "defn-", "defmacro", "defmacro-", "deftransform", "deftransform-", "defiter", "defiter-":
        return true
    case:
        return false
    }
}

is_public_decl_head :: proc(head: string) -> bool {
    return is_top_level_decl_head(head) && !is_private_decl_head(head)
}

is_macro_decl_head :: proc(head: string) -> bool {
    return head == "defmacro" || head == "defmacro-"
}

is_private_macro_decl_head :: proc(head: string) -> bool {
    return head == "defmacro-"
}

decl_symbol_name :: proc(form: CST_Form) -> (string, bool) {
    if form.kind != .List || len(form.items) < 2 || form.items[1].kind != .Symbol {
        return "", false
    }
    text := form.items[1].text
    if len(text) > 0 && text[len(text)-1] == ':' {
        text = text[:len(text)-1]
    }
    return text, true
}

collect_local_decl_names :: proc(forms: []CST_Top_Form) -> (names: [dynamic]string) {
    for top in forms {
        form := top.form
        name, ok_name := decl_symbol_name(form)
        if !ok_name {
            continue
        }
        if is_top_level_decl_head(decl_head_name(form)) {
            append(&names, name)
        }
    }
    return names
}

collect_private_macro_decl_names :: proc(forms: []CST_Top_Form) -> (names: [dynamic]string) {
    for top in forms {
        form := top.form
        name, ok_name := decl_symbol_name(form)
        if !ok_name {
            continue
        }
        if is_private_macro_decl_head(decl_head_name(form)) {
            append(&names, name)
        }
    }
    return names
}

collect_public_decl_names :: proc(forms: []CST_Top_Form) -> (names: [dynamic]string) {
    for top in forms {
        form := top.form
        if form.kind != .List || len(form.items) == 0 {
            continue
        }
        if is_symbol(form.items[0], "@exports") {
            if len(form.items) == 2 && form.items[1].kind == .Vector {
                for item in form.items[1].items {
                    if item.kind == .Symbol && !contains_text(names[:], item.text) {
                        append(&names, item.text)
                    }
                }
            }
            continue
        }
        name, ok_name := decl_symbol_name(form)
        if !ok_name {
            continue
        }
        if is_public_decl_head(decl_head_name(form)) {
            append(&names, name)
        }
    }
    return names
}

append_core_bare_symbol_alias :: proc(aliases: ^[dynamic]Alias_Prefix, anchor_path: string = ".") -> (Compile_Error, bool) {
    core_dir, err_core, ok_core := resolve_kvist_source_import_path(anchor_path, "kvist:core")
    if !ok_core {
        if err_core.message != "" {
            return err_core, false
        }
        return Compile_Error{message = "could not resolve core package for source introspection"}, false
    }
    defer delete(core_dir)

    core_files, err_files, ok_files := read_package_files(core_dir)
    if !ok_files {
        return err_files, false
    }
    defer package_file_slice_delete(core_files)

    core_forms := flatten_package_forms(core_files)
    collected_exports := collect_public_decl_names(core_forms[:])
    exports := clone_string_slice(collected_exports[:])
    delete(collected_exports)
    delete(core_forms)
    append(aliases, Alias_Prefix{
        alias = strings.clone("__kvist_core_bare"),
        exports = exports,
        preserve_qualified_calls = true,
    })
    return Compile_Error{}, true
}

directive_list_form :: proc(head: string, span: Span, rest: []CST_Form = nil) -> CST_Form {
    items: [dynamic]CST_Form
    append(&items, CST_Form{kind = .Symbol, text = head, span = span})
    for item in rest {
        append(&items, item)
    }
    return CST_Form{kind = .List, items = items, span = span}
}

normalize_top_level_directives :: proc(forms: ^[dynamic]CST_Top_Form) -> (Compile_Error, bool) {
    write := 0
    i := 0
    for i < len(forms^) {
        top := forms^[i]
        form := top.form
        if form.kind == .Symbol && form.text == "@exports" {
            if i+1 >= len(forms^) || forms^[i+1].form.kind != .Vector {
                return Compile_Error{message = "@exports expects one vector of symbol names", span = form.span}, false
            }
            vector := forms^[i+1].form
            for item in vector.items {
                if item.kind != .Symbol {
                    return Compile_Error{message = "@exports expects symbol names", span = item.span}, false
                }
            }
            rest := [?]CST_Form{vector}
            top.form = directive_list_form("@exports", form.span, rest[:])
            forms^[write] = top
            write += 1
            i += 2
            continue
        }
        forms^[write] = top
        write += 1
        i += 1
    }
    resize(forms, write)
    return Compile_Error{}, true
}

read_kvist_top_forms :: proc(source: string, source_path: string = "") -> ([dynamic]CST_Top_Form, Compile_Error, bool) {
    forms, err_forms, ok_forms := read_top_forms(source, source_path)
    if !ok_forms {
        return nil, err_forms, false
    }
    err_directives, ok_directives := normalize_top_level_directives(&forms)
    if !ok_directives {
        return nil, err_directives, false
    }
    return forms, Compile_Error{}, true
}

valid_odin_decl_name :: proc(text: string) -> bool {
    if text == "" {
        return false
    }
    for ch, idx in text {
        if idx == 0 {
            if (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch == '_' {
                continue
            }
            return false
        }
        if (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_' {
            continue
        }
        return false
    }
    return true
}

collect_raw_odin_decl_names_from_source :: proc(source: string) -> (names: [dynamic]string) {
    lines := strings.split_lines(source, context.allocator)
    defer delete(lines)
    for line in lines {
        if line == "" || strings.trim_left(line, " \t") != line {
            continue
        }
        trimmed := strings.trim_space(line)
        if trimmed == "" || strings.has_prefix(trimmed, "//") {
            continue
        }
        separator := strings.index(trimmed, "::")
        if separator < 0 {
            separator = strings.index(trimmed, ":")
        }
        if separator <= 0 {
            continue
        }
        name := strings.trim_space(trimmed[:separator])
        if valid_odin_decl_name(name) && !contains_text(names[:], name) {
            append(&names, strings.clone(name))
        }
    }
    return names
}

collect_raw_odin_decl_names_from_dir :: proc(dir: string) -> (names: [dynamic]string) {
    if !os.exists(dir) || !os.is_dir(dir) {
        return names
    }
    entries, err := os.read_directory_by_path(dir, -1, context.allocator)
    if err != nil {
        return names
    }
    defer os.file_info_slice_delete(entries, context.allocator)

    for entry in entries {
        if entry.type != .Regular || !strings.has_suffix(entry.name, ".odin") {
            continue
        }
        path, join_err := os.join_path({dir, entry.name}, context.allocator)
        if join_err != nil {
            continue
        }
        data, read_err := os.read_entire_file_from_path(path, context.allocator)
        delete(path)
        if read_err != nil {
            continue
        }
        file_names := collect_raw_odin_decl_names_from_source(string(data))
        delete(data)
        for name in file_names {
            if !contains_text(names[:], name) {
                append(&names, strings.clone(name))
            }
        }
        delete_string_slice(&file_names)
    }
    return names
}

source_package_dir :: proc(path: string) -> (string, Compile_Error, bool) {
    dir := path
    if os.exists(path) && os.is_dir(path) {
        dir = path
    } else {
        dir, _ = os.split_path(path)
    }
    if dir == "" {
        dir = "."
    }
    canonical, canonical_err := os.get_absolute_path(dir, context.allocator)
    if canonical_err != nil {
        return "", Compile_Error{message = fmt.tprintf("could not canonicalize source package directory: %s", dir)}, false
    }
    return canonical, Compile_Error{}, true
}

source_import_alias_and_path :: proc(form: CST_Form, importer_path: string = ".") -> (alias, path: string, ok: bool) {
    if form.kind != .List || len(form.items) == 0 || !is_symbol(form.items[0], "import") {
        return "", "", false
    }
    if len(form.items) == 2 && form.items[1].kind == .String {
        return "", "", false
    }
    if source_import_form_has_refer(form) {
        path = import_path_text(form.items[1])
        if !is_source_import_path_from(importer_path, path) {
            delete(path)
            return "", "", false
        }
        if as_index, has_as := source_import_as_index(form); has_as {
            return map_name(form.items[as_index].text), path, true
        }
        return import_default_alias(path), path, true
    }
    if import_form_has_as(form) {
        path = import_path_text(form.items[1])
        if !is_source_import_path_from(importer_path, path) {
            delete(path)
            return "", "", false
        }
        as_index, _ := source_import_as_index(form)
        return map_name(form.items[as_index].text), path, true
    }
    if len(form.items) == 3 && form.items[1].kind == .Symbol && form.items[2].kind == .String {
        path = import_path_text(form.items[2])
        if !is_source_import_path_from(importer_path, path) {
            delete(path)
            return "", "", false
        }
        return map_name(form.items[1].text), path, true
    }
    return "", "", false
}

rewrite_relative_odin_import_form :: proc(importer_path: string, top: CST_Top_Form) -> CST_Top_Form {
    rewritten := clone_cst_top_form(top)
    form := &rewritten.form
    if form.kind != .List || len(form.items) < 2 || !is_symbol(form.items[0], "import") {
        return rewritten
    }

    path_index := -1
    if len(form.items) == 2 && form.items[1].kind == .String {
        path_index = 1
    }
    if len(form.items) == 3 && form.items[1].kind == .Symbol && form.items[2].kind == .String {
        path_index = 2
    }
    if import_form_has_as(form^) {
        path_index = 1
    }
    if path_index < 0 {
        return rewritten
    }

    raw_path := import_path_text(form.items[path_index])
    defer delete(raw_path)
    if !is_relative_odin_import_path(raw_path) {
        return rewritten
    }
    source_alias, source_path, is_source_import := source_import_alias_and_path(top.form, importer_path)
    if is_source_import {
        delete(source_alias)
        delete(source_path)
        return rewritten
    }

    base_dir, _ := os.split_path(importer_path)
    if base_dir == "" {
        resolved, abs_err := os.get_absolute_path(raw_path, context.allocator)
        if abs_err != nil {
            return rewritten
        }
        defer delete(resolved)
        delete(form.items[path_index].text)
        form.items[path_index].text = fmt.tprintf("%q", resolved)
        return rewritten
    }
    joined, join_err := os.join_path({base_dir, raw_path}, context.allocator)
    if join_err != nil {
        return rewritten
    }
    defer delete(joined)
    if !os.exists(joined) {
        return rewritten
    }
    resolved, abs_err := os.get_absolute_path(joined, context.allocator)
    if abs_err != nil {
        return rewritten
    }
    defer delete(resolved)
    delete(form.items[path_index].text)
    form.items[path_index].text = fmt.tprintf("%q", resolved)
    return rewritten
}

collect_root_source_import_aliases :: proc(
    path: string,
    extra_imports: []CST_Top_Form = nil,
) -> ([]Alias_Prefix, Compile_Error, bool) {
    files, err_files, ok_files := read_root_package_files(path)
    if !ok_files {
        return nil, err_files, false
    }
    if len(files) > 0 && files[0].package_name != "" {
        dir, _ := os.split_path(path)
        if dir == "" {
            dir = "."
        }
        _, err_package, ok_package := validate_package_files(dir, files[:])
        if !ok_package {
            return nil, err_package, false
        }
    }
    base_aliases, err_aliases, ok_aliases :=
        collect_root_source_import_aliases_from_files(files[:])
    if !ok_aliases {
        return nil, err_aliases, false
    }
    aliases: [dynamic]Alias_Prefix
    append(&aliases, ..base_aliases)
    delete(base_aliases)
    for top in extra_imports {
        alias, import_path, ok_import := source_import_alias_and_path(top.form, path)
        if !ok_import {
            continue
        }
        resolved, err_resolve, ok_resolve := resolve_source_import_path(path, import_path)
        if !ok_resolve {
            delete(alias)
            delete(import_path)
            return nil, err_resolve, false
        }
        import_files, err_files, ok_files := read_package_files(resolved)
        if !ok_files {
            delete(alias)
            delete(import_path)
            return nil, err_files, false
        }
        _, err_package, ok_package := validate_package_files(resolved, import_files[:])
        if !ok_package {
            delete(alias)
            delete(import_path)
            return nil, err_package, false
        }
        import_forms := flatten_package_forms(import_files[:])
        exports := collect_public_decl_names(import_forms[:])
        raw_dir := repl_odin_sidecar_dir(resolved)
        raw_exports := collect_raw_odin_decl_names_from_dir(raw_dir)
        delete(raw_dir)
        append(&aliases, Alias_Prefix{
            alias = alias,
            prefix = alias,
            raw_prefix = odin_package_import_alias(alias),
            exports = exports,
            raw_exports = raw_exports,
            refer_names = source_import_refer_names(top.form),
            allow_unqualified_exports = source_import_form_has_refer(top.form),
        })
        delete(import_path)
    }
    return aliases[:], Compile_Error{}, true
}

flatten_package_forms :: proc(files: []Package_File) -> (forms: [dynamic]CST_Top_Form) {
    for file in files {
        for top in file.forms {
            append(&forms, top)
        }
    }
    return forms
}

source_package_name_hint :: proc(source: string) -> (name: string, ok: bool) {
    prefix := "(package"
    i := 0
    for i < len(source) {
        if source[i] == ';' {
            for i < len(source) && source[i] != '\n' {
                i += 1
            }
            continue
        }
        if source[i] == '/' && i+1 < len(source) && source[i+1] == '/' {
            i += 2
            for i < len(source) && source[i] != '\n' {
                i += 1
            }
            continue
        }
        if source[i] == '/' && i+1 < len(source) && source[i+1] == '*' {
            i += 2
            for i+1 < len(source) && !(source[i] == '*' && source[i+1] == '/') {
                i += 1
            }
            if i+1 >= len(source) {
                return "", false
            }
            i += 2
            continue
        }
        if source[i] == '"' {
            i += 1
            escaped := false
            for i < len(source) {
                ch := source[i]
                if escaped {
                    escaped = false
                } else if ch == '\\' {
                    escaped = true
                } else if ch == '"' {
                    i += 1
                    break
                }
                i += 1
            }
            continue
        }
        if i+len(prefix) <= len(source) && source[i:i+len(prefix)] == prefix {
            j := i + len(prefix)
            if j >= len(source) || !is_whitespace(source[j]) {
                i += 1
                continue
            }
            for j < len(source) && is_whitespace(source[j]) {
                j += 1
            }
            start := j
            for j < len(source) && !is_delimiter(source[j]) {
                j += 1
            }
            if start < j {
                return source[start:j], true
            }
            return "", false
        }
        i += 1
    }
    return "", false
}

read_root_package_files :: proc(path: string) -> ([]Package_File, Compile_Error, bool) {
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        return nil, Compile_Error{message = fmt.tprintf("could not read file: %s", path)}, false
    }
    source := string(data)
    forms, err_forms, ok_forms := read_kvist_top_forms(source, path)
    if !ok_forms {
        return nil, err_forms, false
    }

    has_package := false
    package_name := ""
    for top in forms {
        if decl_head_name(top.form) != "package" {
            continue
        }
        has_package = true
        if len(top.form.items) == 2 && top.form.items[1].kind == .Symbol {
            package_name = top.form.items[1].text
        }
        break
    }
    if !has_package {
        files: [dynamic]Package_File
        append(&files, Package_File{path = path, source = source, package_name = package_name, forms = forms})
        return files[:], Compile_Error{}, true
    }

    dir, _ := os.split_path(path)
    if dir == "" {
        dir = "."
    }
    entries, dir_err := os.read_directory_by_path(dir, -1, context.allocator)
    if dir_err != nil {
        return nil, Compile_Error{message = fmt.tprintf("could not read package directory: %s", dir)}, false
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
            return nil, Compile_Error{message = fmt.tprintf("could not read package directory: %s", dir)}, false
        }
        data, read_entry_err := os.read_entire_file_from_path(file_path, context.allocator)
        if read_entry_err != nil {
            return nil, Compile_Error{message = fmt.tprintf("could not read file: %s", file_path)}, false
        }
        file_source := string(data)
        file_package_hint, ok_package_hint := source_package_name_hint(file_source)
        if !ok_package_hint || file_package_hint != package_name {
            continue
        }
        file_forms, err_file_forms, ok_file_forms := read_kvist_top_forms(file_source, file_path)
        if !ok_file_forms {
            return nil, err_file_forms, false
        }
        file_package_name := ""
        package_count := 0
        for top in file_forms {
            if decl_head_name(top.form) != "package" {
                continue
            }
            package_count += 1
            if len(top.form.items) != 2 || top.form.items[1].kind != .Symbol {
                return nil, Compile_Error{message = "package expects one symbol name", span = top.form.span}, false
            }
            file_package_name = top.form.items[1].text
        }
        if package_count == 0 {
            continue
        }
        if package_count > 1 {
            return nil, Compile_Error{message = fmt.tprintf("source package file has duplicate package declarations: %s", file_path)}, false
        }
        if file_package_name == package_name {
            if is_package_anchor_filename(dir, entry.name) {
                has_anchor = true
            }
            append(&matched, Package_File{path = file_path, path_owned = true, source = file_source, package_name = file_package_name, forms = file_forms})
        }
    }
    if len(matched) == 0 {
        return nil, Compile_Error{message = fmt.tprintf("source package file is missing package declaration: %s", path)}, false
    }
    if !has_anchor {
        files: [dynamic]Package_File
        append(&files, Package_File{path = path, source = source, package_name = package_name, forms = forms})
        return files[:], Compile_Error{}, true
    }
    return matched[:], Compile_Error{}, true
}

collect_root_source_import_aliases_from_files :: proc(files: []Package_File) -> ([]Alias_Prefix, Compile_Error, bool) {
    aliases: [dynamic]Alias_Prefix
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
                return nil, err_resolve, false
            }
            import_files, err_files, ok_files := read_package_files(resolved)
            if !ok_files {
                delete(alias)
                delete(import_path)
                return nil, err_files, false
            }
            _, err_package, ok_package := validate_package_files(resolved, import_files[:])
            if !ok_package {
                delete(alias)
                delete(import_path)
                return nil, err_package, false
            }
            import_forms := flatten_package_forms(import_files[:])
            exports := collect_public_decl_names(import_forms[:])
            raw_dir, err_raw_dir, ok_raw_dir := source_package_dir(resolved)
            if !ok_raw_dir {
                delete(alias)
                delete(import_path)
                return nil, err_raw_dir, false
            }
            raw_exports := collect_raw_odin_decl_names_from_dir(raw_dir)
            delete(raw_dir)
            append(&aliases, Alias_Prefix{
                alias = alias,
                prefix = alias,
                raw_prefix = odin_package_import_alias(alias),
                exports = exports,
                raw_exports = raw_exports,
                refer_names = source_import_refer_names(top.form),
                allow_unqualified_exports = source_import_form_has_refer(top.form),
            })
            delete(import_path)
        }
    }
    return aliases[:], Compile_Error{}, true
}
