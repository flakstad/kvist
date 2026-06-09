package kvist

import "core:fmt"
import "core:os"
import "core:sort"
import "core:strings"
import "base:runtime"

Alias_Prefix :: struct {
    alias:   string,
    prefix:  string,
    exports: [dynamic]string,
    raw_exports: [dynamic]string,
    preserve_qualified_calls: bool,
}

Loaded_Forms :: struct {
    has_package: bool,
    package_decl: CST_Top_Form,
    imports: [dynamic]CST_Top_Form,
    decls: [dynamic]CST_Top_Form,
    exports: [dynamic]string,
    raw_exports: [dynamic]string,
}

loaded_forms_delete :: proc(forms: ^Loaded_Forms) {
    delete_borrowed_cst_top_form_slice(&forms.imports)
    delete_borrowed_cst_top_form_slice(&forms.decls)
    delete_string_slice(&forms.exports)
    delete_string_slice(&forms.raw_exports)
    forms^ = Loaded_Forms{}
}

alias_prefix_slice_delete :: proc(aliases: ^[dynamic]Alias_Prefix) {
    for i in 0 ..< len(aliases^) {
        if aliases^[i].alias != "" {
            delete(aliases^[i].alias)
        }
        if aliases^[i].prefix != "" {
            delete(aliases^[i].prefix)
        }
        delete_string_slice(&aliases^[i].exports)
        delete_string_slice(&aliases^[i].raw_exports)
    }
    delete(aliases^)
    aliases^ = nil
}

synthetic_package_decl :: proc(name: string) -> CST_Top_Form {
    package_symbol := CST_Form{
        kind = .Symbol,
        text = "package",
        span = Span{source = .File},
    }
    name_symbol := CST_Form{
        kind = .Symbol,
        text = name,
        span = Span{source = .File},
    }
    package_form := CST_Form{
        kind = .List,
        span = Span{source = .File},
    }
    append(&package_form.items, package_symbol, name_symbol)
    return CST_Top_Form{
        form = package_form,
        source = fmt.tprintf("(package %s)", name),
    }
}

synthetic_import_decl :: proc(alias, path: string) -> CST_Top_Form {
    import_symbol := CST_Form{
        kind = .Symbol,
        text = "import",
        span = Span{source = .File},
    }
    alias_symbol := CST_Form{
        kind = .Symbol,
        text = alias,
        span = Span{source = .File},
    }
    path_string := CST_Form{
        kind = .String,
        text = fmt.tprintf("%q", path),
        span = Span{source = .File},
    }
    import_form := CST_Form{
        kind = .List,
        span = Span{source = .File},
    }
    append(&import_form.items, import_symbol, alias_symbol, path_string)
    return CST_Top_Form{
        form = import_form,
        source = fmt.tprintf("(import %s %q)", alias, path),
    }
}

normalize_expanded_top_forms :: proc(forms: []CST_Top_Form) -> (out: [dynamic]CST_Top_Form) {
    seen_imports: [dynamic]string
    defer delete(seen_imports)
    for top in forms {
        if decl_head_name(top.form) == "package" {
            append(&out, top)
            break
        }
    }
    for top in forms {
        if decl_head_name(top.form) == "import" {
            append_import_form_unique(&out, &seen_imports, top)
        }
    }
    for top in forms {
        head := decl_head_name(top.form)
        if head == "package" || head == "import" {
            continue
        }
        append(&out, top)
    }
    return out
}

validate_surface_top_level_order :: proc(forms: []CST_Top_Form) -> (Compile_Error, bool) {
    seen_package := false
    seen_non_import_decl := false

    for top in forms {
        head := decl_head_name(top.form)
        switch head {
        case "":
            continue
        case "package":
            if seen_package {
                return Compile_Error{message = "package declaration must appear exactly once", span = top.form.span}, false
            }
            if seen_non_import_decl {
                return Compile_Error{message = "package declaration must be the first declaration", span = top.form.span}, false
            }
            seen_package = true
        case "import":
            if !seen_package {
                return Compile_Error{message = "import requires a preceding package declaration", span = top.form.span}, false
            }
            if seen_non_import_decl {
                return Compile_Error{message = "import declarations must appear before other declarations", span = top.form.span}, false
            }
        case:
            if !seen_package {
                return Compile_Error{message = "missing package declaration", span = top.form.span}, false
            }
            seen_non_import_decl = true
        }
    }

    if !seen_package {
        return Compile_Error{message = "missing package declaration"}, false
    }
    return Compile_Error{}, true
}

contains_text :: proc(items: []string, value: string) -> bool {
    for item in items {
        if item == value {
            return true
        }
    }
    return false
}

sorted_unique_texts :: proc(items: []string) -> (out: [dynamic]string) {
    for item in items {
        if !contains_text(out[:], item) {
            append(&out, item)
        }
    }
    sort.sort(sort.Interface{
        collection = rawptr(&out),
        len = proc(it: sort.Interface) -> int {
            values := (^([dynamic]string))(it.collection)
            return len(values^)
        },
        less = proc(it: sort.Interface, i, j: int) -> bool {
            values := (^([dynamic]string))(it.collection)
            return values[i] < values[j]
        },
        swap = proc(it: sort.Interface, i, j: int) {
            values := (^([dynamic]string))(it.collection)
            values[i], values[j] = values[j], values[i]
        },
    })
    return out
}
clone_string_slice :: proc(values: []string) -> (out: [dynamic]string) {
    for value in values {
        append(&out, strings.clone(value))
    }
    return out
}

delete_string_slice :: proc(values: ^[dynamic]string) {
    for i in 0 ..< len(values^) {
        if values^[i] != "" {
            delete(values^[i])
        }
    }
    delete(values^)
    values^ = nil
}

clone_cst_form :: proc(form: CST_Form) -> CST_Form {
    cloned := form
    if form.text != "" {
        cloned.text = strings.clone(form.text)
    }
    cloned.items = nil
    for item in form.items {
        append(&cloned.items, clone_cst_form(item))
    }
    return cloned
}

delete_cst_form :: proc(form: ^CST_Form) {
    if form.text != "" {
        delete(form.text)
    }
    for i in 0 ..< len(form.items) {
        delete_cst_form(&form.items[i])
    }
    delete(form.items)
    form^ = CST_Form{}
}

clone_cst_form_slice :: proc(forms: []CST_Form) -> (out: [dynamic]CST_Form) {
    for form in forms {
        append(&out, clone_cst_form(form))
    }
    return out
}

delete_cst_form_slice :: proc(forms: ^[dynamic]CST_Form) {
    for i in 0 ..< len(forms^) {
        delete_cst_form(&forms^[i])
    }
    delete(forms^)
    forms^ = nil
}

clone_cst_top_form :: proc(top: CST_Top_Form) -> CST_Top_Form {
    return CST_Top_Form{
        form = clone_cst_form(top.form),
        doc_lines = clone_string_slice(top.doc_lines[:]),
        source = strings.clone(top.source),
    }
}

delete_cst_top_form :: proc(top: ^CST_Top_Form) {
    delete_cst_form(&top.form)
    delete_string_slice(&top.doc_lines)
    if top.source != "" {
        delete(top.source)
    }
    top^ = CST_Top_Form{}
}

delete_cst_top_form_slice :: proc(forms: ^[dynamic]CST_Top_Form) {
    for i in 0 ..< len(forms^) {
        delete_cst_top_form(&forms^[i])
    }
    delete(forms^)
    forms^ = nil
}

delete_borrowed_cst_form :: proc(form: ^CST_Form) {
    for i in 0 ..< len(form.items) {
        delete_borrowed_cst_form(&form.items[i])
    }
    delete(form.items)
    form^ = CST_Form{}
}

delete_borrowed_cst_form_slice :: proc(forms: ^[dynamic]CST_Form) {
    for i in 0 ..< len(forms^) {
        delete_borrowed_cst_form(&forms^[i])
    }
    delete(forms^)
    forms^ = nil
}

delete_borrowed_cst_top_form :: proc(top: ^CST_Top_Form) {
    delete_borrowed_cst_form(&top.form)
    delete_string_slice(&top.doc_lines)
    top^ = CST_Top_Form{}
}

delete_borrowed_cst_top_form_slice :: proc(forms: ^[dynamic]CST_Top_Form) {
    for i in 0 ..< len(forms^) {
        delete_borrowed_cst_top_form(&forms^[i])
    }
    delete(forms^)
    forms^ = nil
}
append_import_form_unique :: proc(forms: ^[dynamic]CST_Top_Form, seen: ^[dynamic]string, form: CST_Top_Form) {
    key := form.source
    if form.form.kind == .List && len(form.form.items) > 0 && is_symbol(form.form.items[0], "import") {
        if len(form.form.items) == 2 && form.form.items[1].kind == .String {
            path := import_path_text(form.form.items[1])
            key = fmt.tprintf("%s|%s", import_default_alias(path), path)
        } else if len(form.form.items) == 3 && form.form.items[1].kind == .Symbol && form.form.items[2].kind == .String {
            key = fmt.tprintf("%s|%s", form.form.items[1].text, import_path_text(form.form.items[2]))
        }
    }
    if contains_text(seen[:], key) {
        return
    }
    append(seen, key)
    append(forms, form)
}

is_shipped_source_import_path :: proc(path: string) -> bool {
    if !strings.has_prefix(path, "kvist:") {
        return false
    }
    root, ok_root := repo_root_for_path(".")
    if !ok_root {
        return false
    }
    defer delete(root)
    package_name := path[len("kvist:"):]
    candidate, join_err := os.join_path({root, "packages", package_name}, context.allocator)
    if join_err != nil {
        return false
    }
    defer delete(candidate)
    return os.exists(candidate) && os.is_dir(candidate)
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
    if base_owned {
        defer delete(base)
    }
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

resolve_shipped_source_import_path :: proc(importer_path, import_path: string) -> (string, Compile_Error, bool) {
    if !strings.has_prefix(import_path, "kvist:") {
        return "", Compile_Error{}, false
    }
    package_name := import_path[len("kvist:"):]
    if package_name == "" {
        return "", Compile_Error{message = fmt.tprintf("could not resolve shipped source import: %s", import_path)}, false
    }
    root, ok_root := repo_root_for_path(importer_path)
    if !ok_root {
        root, ok_root = repo_root_for_path(".")
    }
    if !ok_root {
        return "", Compile_Error{message = fmt.tprintf("could not resolve shipped source import: %s", import_path)}, false
    }
    defer delete(root)
    candidate, join_err := os.join_path({root, "packages", package_name}, context.allocator)
    if join_err != nil || !os.exists(candidate) {
        if join_err == nil {
            delete(candidate)
        }
        return "", Compile_Error{message = fmt.tprintf("could not resolve shipped source import: %s", import_path)}, false
    }
    return candidate, Compile_Error{}, true
}

resolve_source_import_path :: proc(importer_path, import_path: string) -> (string, Compile_Error, bool) {
    shipped, err_shipped, ok_shipped := resolve_shipped_source_import_path(importer_path, import_path)
    if ok_shipped || err_shipped.message != "" {
        return shipped, err_shipped, ok_shipped
    }
    base_dir, _ := os.split_path(importer_path)
    base := import_path
    if base_dir != "" {
        joined, join_err := os.join_path({base_dir, import_path}, context.allocator)
        if join_err != nil {
            return "", Compile_Error{message = fmt.tprintf("could not resolve source import: %s", import_path)}, false
        }
        base = joined
        defer delete(base)
    }

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

decl_head_name :: proc(form: CST_Form) -> string {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return ""
    }
    return form.items[0].text
}

is_private_decl_head :: proc(head: string) -> bool {
    switch head {
    case "def-", "defvar-", "defstruct-", "defenum-", "defunion-", "defn-", "defmacro-", "deftransform-", "defsource-":
        return true
    case:
        return false
    }
}

is_top_level_decl_head :: proc(head: string) -> bool {
    switch head {
    case "def", "def-", "defvar", "defvar-", "defstruct", "defstruct-", "defstate", "defenum", "defenum-", "defunion", "defunion-", "defn", "defn-", "defmacro", "defmacro-", "deftransform", "deftransform-", "defsource", "defsource-":
        return true
    case:
        return false
    }
}

is_public_decl_head :: proc(head: string) -> bool {
    return is_top_level_decl_head(head) && !is_private_decl_head(head)
}

collect_local_decl_names :: proc(forms: []CST_Top_Form) -> (names: [dynamic]string) {
    for top in forms {
        form := top.form
        if form.kind != .List || len(form.items) < 2 || form.items[1].kind != .Symbol {
            continue
        }
        if is_top_level_decl_head(decl_head_name(form)) {
            append(&names, form.items[1].text)
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
        if is_symbol(form.items[0], "exports") {
            if len(form.items) == 2 && form.items[1].kind == .Vector {
                for item in form.items[1].items {
                    if item.kind == .Symbol && !contains_text(names[:], item.text) {
                        append(&names, item.text)
                    }
                }
            }
            continue
        }
        if len(form.items) < 2 || form.items[1].kind != .Symbol {
            continue
        }
        if is_public_decl_head(decl_head_name(form)) {
            append(&names, form.items[1].text)
        }
    }
    return names
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

source_package_dir_for_raw_sidecars :: proc(path: string) -> string {
    if os.exists(path) && os.is_dir(path) {
        return strings.clone(path)
    }
    dir, _ := os.split_path(path)
    if dir == "" {
        return strings.clone(".")
    }
    return strings.clone(dir)
}

append_source_package_marker_exports :: proc(names: ^[dynamic]string, import_path: string) {
    if import_path == "kvist:html" && !contains_text(names^[:], "for") {
        append(names, "for")
    }
}

source_import_alias_and_path :: proc(form: CST_Form, importer_path: string = ".") -> (alias, path: string, ok: bool) {
    if form.kind != .List || len(form.items) == 0 || !is_symbol(form.items[0], "import") {
        return "", "", false
    }
    if len(form.items) == 2 && form.items[1].kind == .String {
        path = import_path_text(form.items[1])
        if !is_source_import_path_from(importer_path, path) {
            delete(path)
            return "", "", false
        }
        return import_default_alias(path), path, true
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
        return rewritten
    }
    resolved, join_err := os.join_path({base_dir, raw_path}, context.allocator)
    if join_err != nil {
        return rewritten
    }
    delete(form.items[path_index].text)
    form.items[path_index].text = fmt.tprintf("%q", resolved)
    return rewritten
}

collect_root_source_import_aliases :: proc(path: string) -> ([]Alias_Prefix, Compile_Error, bool) {
    files, err_files, ok_files := read_root_package_files(path)
    if !ok_files {
        return nil, err_files, false
    }
    if len(files) > 0 && files[0].package_name != "" {
        dir, _ := os.split_path(path)
        if dir == "" {
            return nil, Compile_Error{message = fmt.tprintf("could not resolve root package directory: %s", path)}, false
        }
        _, err_package, ok_package := validate_package_files(dir, files[:])
        if !ok_package {
            return nil, err_package, false
        }
    }
    return collect_root_source_import_aliases_from_files(files[:])
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
    forms, err_forms, ok_forms := read_top_forms(source)
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
        return nil, Compile_Error{message = fmt.tprintf("could not resolve root package directory: %s", path)}, false
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
        file_forms, err_file_forms, ok_file_forms := read_top_forms(file_source)
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
            raw_dir := source_package_dir_for_raw_sidecars(resolved)
            raw_exports := collect_raw_odin_decl_names_from_dir(raw_dir)
            delete(raw_dir)
            append_source_package_marker_exports(&exports, import_path)
            append(&aliases, Alias_Prefix{
                alias = alias,
                prefix = alias,
                exports = exports,
                raw_exports = raw_exports,
                preserve_qualified_calls = import_path == "kvist:core",
            })
            delete(import_path)
        }
    }
    return aliases[:], Compile_Error{}, true
}

rewrite_symbol_text :: proc(text: string, locals: []string, aliases: []Alias_Prefix, prefix: string, span: Span = {}) -> (string, Compile_Error, bool) {
    quote_prefix := ""
    body := text
    if len(body) > 0 && body[0] == '\'' {
        quote_prefix = "'"
        body = body[1:]
    }
    operator_prefix := ""
    for len(body) > 0 && (body[0] == '^' || body[0] == '&') {
        operator_prefix = fmt.tprintf("%s%c", operator_prefix, body[0])
        body = body[1:]
    }
    for alias_map in aliases {
        prefix_text := fmt.tprintf("%s.", alias_map.alias)
        if len(body) > len(prefix_text) && body[:len(prefix_text)] == prefix_text {
            member := body[len(prefix_text):]
            if alias_map.preserve_qualified_calls {
                return text, Compile_Error{}, true
            }
            raw_member := map_name(member)
            defer delete(raw_member)
            is_raw_export := contains_text(alias_map.raw_exports[:], raw_member)
            if len(alias_map.exports) > 0 && !contains_text(alias_map.exports[:], member) && !is_raw_export {
                return "", Compile_Error{message = fmt.tprintf("source package member is private or undefined: %s.%s", alias_map.alias, member), span = span}, false
            }
            if is_raw_export {
                return fmt.tprintf("%s%s%s.%s", quote_prefix, operator_prefix, alias_map.prefix, raw_member), Compile_Error{}, true
            }
            return fmt.tprintf("%s%s%s__%s", quote_prefix, operator_prefix, alias_map.prefix, member), Compile_Error{}, true
        }
        old_prefix_text := fmt.tprintf("%s/", alias_map.alias)
        if len(body) > len(old_prefix_text) && body[:len(old_prefix_text)] == old_prefix_text {
            member := body[len(old_prefix_text):]
            return "", Compile_Error{message = fmt.tprintf("use `%s.%s` for package access", alias_map.alias, member), span = span}, false
        }
    }
    if prefix != "" && contains_text(locals, body) {
        return fmt.tprintf("%s%s%s__%s", quote_prefix, operator_prefix, prefix, body), Compile_Error{}, true
    }
    return text, Compile_Error{}, true
}

rewrite_form_symbols :: proc(form: CST_Form, locals: []string, aliases: []Alias_Prefix, prefix: string) -> (CST_Form, Compile_Error, bool) {
    rewritten := form
    #partial switch form.kind {
    case .Symbol:
        text, err_text, ok_text := rewrite_symbol_text(form.text, locals, aliases, prefix, form.span)
        if !ok_text {
            return CST_Form{}, err_text, false
        }
        rewritten.text = text
        return rewritten, Compile_Error{}, true
    case .List, .Vector, .Brace:
        rewritten.items = nil
        for item in form.items {
            child, err_child, ok_child := rewrite_form_symbols(item, locals, aliases, prefix)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&rewritten.items, child)
        }
    }
    return rewritten, Compile_Error{}, true
}

rewrite_decl_name :: proc(form: ^CST_Form, prefix: string) {
    if prefix == "" || form^.kind != .List || len(form^.items) < 2 || form^.items[1].kind != .Symbol {
        return
    }
    switch decl_head_name(form^) {
    case "def", "def-", "defvar", "defvar-", "defstruct", "defstruct-", "defenum", "defenum-", "defunion", "defunion-", "defn", "defn-", "defmacro", "defmacro-", "deftransform", "deftransform-", "defsource", "defsource-":
        form^.items[1].text = fmt.tprintf("%s__%s", prefix, form^.items[1].text)
    }
}

type_constructor_symbol :: proc(text: string) -> bool {
    switch text {
    case "slice", "dynamic", "array", "map", "set", "matrix", "ptr", "fn":
        return true
    }
    return false
}

rewrite_type_form_symbols :: proc(form: CST_Form, locals: []string, aliases: []Alias_Prefix, prefix: string) -> (CST_Form, Compile_Error, bool) {
    rewritten := form
    #partial switch form.kind {
    case .Symbol:
        if type_constructor_symbol(form.text) {
            return rewritten, Compile_Error{}, true
        }
        text, err_text, ok_text := rewrite_symbol_text(form.text, locals, aliases, prefix, form.span)
        if !ok_text {
            return CST_Form{}, err_text, false
        }
        rewritten.text = text
        return rewritten, Compile_Error{}, true
    case .List:
        rewritten.items = nil
        for item, idx in form.items {
            if idx == 0 && item.kind == .Symbol && type_constructor_symbol(item.text) {
                append(&rewritten.items, item)
                continue
            }
            child, err_child, ok_child := rewrite_type_form_symbols(item, locals, aliases, prefix)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&rewritten.items, child)
        }
    case .Vector:
        rewritten.items = nil
        for item, idx in form.items {
            if idx == 0 && (item.kind == .Keyword || item.kind == .Symbol) {
                head := item.text
                if item.kind == .Keyword && len(head) > 0 {
                    head = head[1:]
                }
                if type_constructor_symbol(head) || head == "arr" || head == "fixed-arr" {
                    append(&rewritten.items, item)
                    continue
                }
            }
            if item.kind == .Symbol && len(item.text) > 0 && item.text[len(item.text)-1] == ':' {
                append(&rewritten.items, item)
                continue
            }
            child, err_child, ok_child := rewrite_type_form_symbols(item, locals, aliases, prefix)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&rewritten.items, child)
        }
    }
    return rewritten, Compile_Error{}, true
}

rewrite_param_vector_signature :: proc(form: CST_Form, locals: []string, aliases: []Alias_Prefix, prefix: string) -> (CST_Form, Compile_Error, bool) {
    if form.kind != .Vector {
        return form, Compile_Error{}, true
    }
    rewritten := form
    rewritten.items = nil
    i := 0
    for i < len(form.items) {
        target := form.items[i]
        type_start := -1
        #partial switch target.kind {
        case .Symbol:
            append(&rewritten.items, target)
            if len(target.text) == 0 || target.text[len(target.text)-1] != ':' {
                i += 1
                continue
            }
            type_start = i + 1
        case .Brace:
            append(&rewritten.items, target)
            if i+1 < len(form.items) {
                append(&rewritten.items, form.items[i+1])
            }
            type_start = i + 2
        case:
            child, err_child, ok_child := rewrite_form_symbols(target, locals, aliases, prefix)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&rewritten.items, child)
            i += 1
            continue
        }

        if type_start >= len(form.items) {
            i += 1
            continue
        }
        _, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], type_start)
        if !ok_type {
            return CST_Form{}, err_type, false
        }
        for item in form.items[type_start:next_i] {
            type_item, err_type_item, ok_type_item := rewrite_type_form_symbols(item, locals, aliases, prefix)
            if !ok_type_item {
                return CST_Form{}, err_type_item, false
            }
            append(&rewritten.items, type_item)
        }
        i = next_i
        if i < len(form.items) && is_symbol(form.items[i], "=") {
            append(&rewritten.items, form.items[i])
            if i+1 >= len(form.items) {
                return CST_Form{}, Compile_Error{message = "missing default parameter value", span = form.items[i].span}, false
            }
            value, err_value, ok_value := rewrite_form_symbols(form.items[i+1], locals, aliases, prefix)
            if !ok_value {
                return CST_Form{}, err_value, false
            }
            append(&rewritten.items, value)
            i += 2
        }
    }
    return rewritten, Compile_Error{}, true
}

rewrite_proc_like_top_form :: proc(top: CST_Top_Form, locals: []string, aliases: []Alias_Prefix, prefix: string) -> (CST_Top_Form, Compile_Error, bool) {
    form := top.form
    rewritten := top
    rewritten.form = form
    rewritten.form.items = nil

    params_index := 2
    if params_index+1 < len(form.items) &&
       form.items[params_index].kind == .Keyword &&
       form.items[params_index].text == ":abi" &&
       form.items[params_index+1].kind == .String {
        params_index += 2
    }
    if params_index < len(form.items) && form.items[params_index].kind == .String {
        params_index += 1
    }

    i := 0
    for i < len(form.items) {
        item := form.items[i]
        if i == 1 && item.kind == .Symbol {
            renamed := item
            renamed.text = fmt.tprintf("%s__%s", prefix, item.text)
            append(&rewritten.form.items, renamed)
            i += 1
            continue
        }
        if i == params_index {
            params, err_params, ok_params := rewrite_param_vector_signature(item, locals, aliases, prefix)
            if !ok_params {
                return CST_Top_Form{}, err_params, false
            }
            append(&rewritten.form.items, params)
            i += 1
            continue
        }
        if i == params_index+1 && is_symbol(item, "->") {
            append(&rewritten.form.items, item)
            if i+1 >= len(form.items) {
                return CST_Top_Form{}, Compile_Error{message = "missing return spec after '->'", span = item.span}, false
            }
            if form.items[i+1].kind == .Vector && vector_is_named_returns(form.items[i+1]) {
                named, err_named, ok_named := rewrite_type_form_symbols(form.items[i+1], locals, aliases, prefix)
                if !ok_named {
                    return CST_Top_Form{}, err_named, false
                }
                append(&rewritten.form.items, named)
                i += 2
                continue
            }
            _, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], i+1)
            if !ok_type {
                return CST_Top_Form{}, err_type, false
            }
            for type_item in form.items[i+1:next_i] {
                rewritten_type_item, err_type_item, ok_type_item := rewrite_type_form_symbols(type_item, locals, aliases, prefix)
                if !ok_type_item {
                    return CST_Top_Form{}, err_type_item, false
                }
                append(&rewritten.form.items, rewritten_type_item)
            }
            i = next_i
            continue
        }

        child, err_child, ok_child := rewrite_form_symbols(item, locals, aliases, prefix)
        if !ok_child {
            return CST_Top_Form{}, err_child, false
        }
        append(&rewritten.form.items, child)
        i += 1
    }
    return rewritten, Compile_Error{}, true
}

rewrite_top_form :: proc(top: CST_Top_Form, locals: []string, aliases: []Alias_Prefix, prefix: string) -> (CST_Top_Form, Compile_Error, bool) {
    rewritten := top
    if prefix != "" &&
       top.form.kind == .List &&
       len(top.form.items) >= 2 &&
       top.form.items[1].kind == .Symbol {
        head := decl_head_name(top.form)
        if head == "defn" || head == "defn-" || head == "defsource" || head == "defsource-" {
            return rewrite_proc_like_top_form(top, locals, aliases, prefix)
        }
        if is_top_level_decl_head(head) {
            rewritten.form = top.form
            rewritten.form.items = nil
            for item, idx in top.form.items {
                if idx == 1 {
                    renamed := item
                    renamed.text = fmt.tprintf("%s__%s", prefix, item.text)
                    append(&rewritten.form.items, renamed)
                } else {
                    child, err_child, ok_child := rewrite_form_symbols(item, locals, aliases, prefix)
                    if !ok_child {
                        return CST_Top_Form{}, err_child, false
                    }
                    append(&rewritten.form.items, child)
                }
            }
            return rewritten, Compile_Error{}, true
        } 
    }
    form, err_form, ok_form := rewrite_form_symbols(top.form, locals, aliases, prefix)
    if !ok_form {
        return CST_Top_Form{}, err_form, false
    }
    rewritten.form = form
    rewrite_decl_name(&rewritten.form, prefix)
    return rewritten, Compile_Error{}, true
}

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
        forms, err_forms, ok_forms := read_top_forms(source)
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
            if contains_text(aliases[:], alias) {
                return nil, nil, Compile_Error{message = fmt.tprintf("duplicate source import alias in package: %s", alias), span = top.form.span}, false
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
                if contains_text(aliases[:], alias) {
                    return nil, nil, Compile_Error{message = fmt.tprintf("duplicate import alias in package: %s", alias), span = form.items[1].span}, false
                }
                append(&aliases, alias)
                append(&paths, "")
            }
            if len(form.items) == 2 && form.items[1].kind == .String {
                if is_source_import_path(path) {
                    continue
                }
                alias := import_default_alias(path)
                if alias != "" {
                    if contains_text(aliases[:], alias) {
                        return nil, nil, Compile_Error{message = fmt.tprintf("duplicate import alias in package: %s", alias), span = form.items[1].span}, false
                    }
                    append(&aliases, alias)
                    append(&paths, "")
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
    exported := collect_public_decl_names(all_forms[:])
    defer delete(exported)
    raw_dir := source_package_dir_for_raw_sidecars(dir)
    defer delete(raw_dir)
    raw_exported := collect_raw_odin_decl_names_from_dir(raw_dir)
    defer delete_string_slice(&raw_exported)
    aliases: [dynamic]Alias_Prefix
    defer alias_prefix_slice_delete(&aliases)
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
        if len(raw_exported) > 0 {
            append_import_form_unique(&result.imports, import_keys, synthetic_import_decl(self_prefix, raw_dir))
        }
        alias_exports := clone_string_slice(exported[:])
        alias_raw_exports := clone_string_slice(raw_exported[:])
        append(&aliases, Alias_Prefix{
            alias = strings.clone(package_name),
            prefix = strings.clone(self_prefix),
            exports = alias_exports,
            raw_exports = alias_raw_exports,
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
            nested, err_nested, ok_nested := load_source_forms(resolved, nested_prefix, loaded_keys, import_keys, visiting)
            delete(resolved)
            if !ok_nested {
                delete(alias)
                delete(import_path)
                return result, err_nested, false
            }
            nested_exports := clone_string_slice(nested.exports[:])
            nested_raw_exports := clone_string_slice(nested.raw_exports[:])
            append_source_package_marker_exports(&nested_exports, import_path)
            append(&aliases, Alias_Prefix{
                alias = alias,
                prefix = strings.clone(nested_prefix),
                exports = nested_exports,
                raw_exports = nested_raw_exports,
                preserve_qualified_calls = import_path == "kvist:core",
            })
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
            rewritten, err_rewrite, ok_rewrite := rewrite_top_form(top, locals[:], aliases[:], prefix)
            if !ok_rewrite {
                return result, err_rewrite, false
            }
            append(&result.decls, rewritten)
        }
    }

    append(loaded_keys, key)
    return result, Compile_Error{}, true
}

load_root_file_forms :: proc(path: string) -> (Loaded_Forms, Compile_Error, bool) {
    files, err_files, ok_files := read_root_package_files(path)
    if !ok_files {
        return Loaded_Forms{}, err_files, false
    }
    if len(files) == 0 {
        return Loaded_Forms{}, Compile_Error{message = fmt.tprintf("could not read file: %s", path)}, false
    }

    if files[0].package_name != "" {
        dir, _ := os.split_path(path)
        if dir == "" {
            return Loaded_Forms{}, Compile_Error{message = fmt.tprintf("could not resolve root package directory: %s", path)}, false
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
    locals := collect_local_decl_names(all_forms[:])

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
            append_source_package_marker_exports(&nested_exports, import_path)
            append(&aliases, Alias_Prefix{
                alias = alias,
                prefix = alias,
                exports = nested_exports,
                raw_exports = nested_raw_exports,
                preserve_qualified_calls = import_path == "kvist:core",
            })
            for form in nested.imports {
                append_import_form_unique(&result.imports, &import_keys, clone_cst_top_form(form))
            }
            for form in nested.decls {
                append(&result.decls, clone_cst_top_form(form))
            }
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
                append_import_form_unique(&result.imports, &import_keys, top)
                continue
            }
            rewritten, err_rewrite, ok_rewrite := rewrite_top_form(top, locals[:], aliases[:], "")
            if !ok_rewrite {
                return result, err_rewrite, false
            }
            append(&result.decls, rewritten)
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
        append_source_package_marker_exports(&nested_exports, import_path)
        append(&aliases, Alias_Prefix{
            alias = alias,
            prefix = alias,
            exports = nested_exports,
            raw_exports = nested_raw_exports,
            preserve_qualified_calls = import_path == "kvist:core",
        })
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
        rewritten, err_rewrite, ok_rewrite := rewrite_top_form(top, locals[:], aliases[:], "")
        if !ok_rewrite {
            return result, err_rewrite, false
        }
        append(&result.decls, rewritten)
    }
    return result, Compile_Error{}, true
}

load_path_expanded_forms :: proc(path: string) -> (expanded: [dynamic]CST_Top_Form, macros: [dynamic]User_Macro, err: Compile_Error, ok: bool) {
    loaded, err_load, ok_load := load_root_file_forms(path)
    if !ok_load {
        return expanded, macros, err_load, false
    }
    if !loaded.has_package {
        loaded.has_package = true
        loaded.package_decl = synthetic_package_decl("main")
    }
    combined: [dynamic]CST_Top_Form
    append(&combined, loaded.package_decl)
    for form in loaded.imports {
        append(&combined, form)
    }
    for form in loaded.decls {
        append(&combined, form)
    }
    expanded_forms, expanded_macros, err_expand, ok_expand := macroexpand_top_forms(combined[:], true, path)
    if !ok_expand {
        return expanded, macros, err_expand, false
    }
    aliases, err_aliases, ok_aliases := collect_root_source_import_aliases(path)
    if !ok_aliases {
        return expanded, macros, err_aliases, false
    }
    locals := collect_local_decl_names(expanded_forms[:])
    rewritten_expanded: [dynamic]CST_Top_Form
    for top in expanded_forms {
        rewritten, err_rewrite, ok_rewrite := rewrite_top_form(top, locals[:], aliases[:], "")
        if !ok_rewrite {
            return expanded, macros, err_rewrite, false
        }
        append(&rewritten_expanded, rewritten)
    }
    expanded = normalize_expanded_top_forms(rewritten_expanded[:])
    macros = expanded_macros
    return expanded, macros, Compile_Error{}, true
}

load_path_program :: proc(path: string) -> (AST_Program, Compile_Error, bool) {
    expanded, _, err_expand, ok_expand := load_path_expanded_forms(path)
    if !ok_expand {
        return AST_Program{}, err_expand, false
    }
    return parse_program(expanded[:])
}

compile_program_with_map :: proc(program: AST_Program) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    lowered, err_lower, ok_lower := lower_program(program)
    if !ok_lower {
        return result, clone_compile_error(err_lower, result_allocator), false
    }
    temp_result, err_emit, ok_emit := emit_ir_program_with_source_map(lowered)
    if !ok_emit {
        return result, clone_compile_error(err_emit, result_allocator), false
    }
    result.output = strings.clone(temp_result.output, result_allocator)
    context.allocator = result_allocator
    for entry in temp_result.source_map {
        append(&result.source_map, entry)
    }
    for warning in temp_result.warnings {
        append(&result.warnings, clone_compile_warning(warning, result_allocator))
    }
    return result, Compile_Error{}, true
}

compile_program_eval_with_map :: proc(program: AST_Program, eval_source: string, no_print: bool = false) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    eval_form, err_eval, ok_eval := read_single_eval_form(eval_source)
    if !ok_eval {
        return result, err_eval, false
    }
    return compile_program_eval_form_with_map(program, eval_form, no_print)
}

compile_program_eval_form_with_map :: proc(program: AST_Program, eval_form: CST_Form, no_print: bool = false) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    lowered, err_lower, ok_lower := lower_program(program)
    if !ok_lower {
        return result, clone_compile_error(err_lower, result_allocator), false
    }

    temp_result: Emit_Result
    err_emit: Compile_Error
    ok_emit: bool
    eval_head := eval_form_head(eval_form)
    if eval_head_is_decl(eval_head) {
        eval_decl, err_decl, ok_decl := parse_decl(CST_Top_Form{form = eval_form})
        if !ok_decl {
            return result, clone_compile_error(err_decl, result_allocator), false
        }
        temp_result, err_emit, ok_emit = emit_eval_decl_program_with_source_map(lowered, IR_Decl(eval_decl))
    } else {
        temp_result, err_emit, ok_emit = emit_eval_program_with_source_map(lowered, eval_form, no_print)
    }
    if !ok_emit {
        return result, clone_compile_error(err_emit, result_allocator), false
    }
    result.output = strings.clone(temp_result.output, result_allocator)
    context.allocator = result_allocator
    for entry in temp_result.source_map {
        append(&result.source_map, entry)
    }
    for warning in temp_result.warnings {
        append(&result.warnings, clone_compile_warning(warning, result_allocator))
    }
    return result, Compile_Error{}, true
}

source_position :: proc(source: string, pos: int) -> (line, column, line_start, line_end: int) {
    clamped_pos := pos
    if clamped_pos < 0 {
        clamped_pos = 0
    }
    if clamped_pos > len(source) {
        clamped_pos = len(source)
    }

    line = 1
    column = 1
    line_start = 0
    i := 0
    for i < clamped_pos {
        if source[i] == '\n' {
            line += 1
            column = 1
            line_start = i + 1
        } else {
            column += 1
        }
        i += 1
    }

    line_end = clamped_pos
    for line_end < len(source) && source[line_end] != '\n' {
        line_end += 1
    }
    return
}

format_compile_error :: proc(path, source: string, err: Compile_Error) -> string {
    label := path
    if label == "" {
        label = "<source>"
    }
    message := err.message
    if message == "" {
        message = "compile error"
    }

    line, column, line_start, line_end := source_position(source, err.span.start)
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    fmt.sbprintf(&builder, "%s:%d:%d: %s\n", label, line, column, message)
    if line_start <= line_end && line_end <= len(source) {
        fmt.sbprintf(&builder, "  %s\n  ", source[line_start:line_end])
        i := 1
        for i < column {
            strings.write_byte(&builder, ' ')
            i += 1
        }
        strings.write_string(&builder, "^\n")
    }
    return strings.clone(strings.to_string(builder))
}

format_eval_compile_error :: proc(path, source, eval_source: string, err: Compile_Error) -> string {
    if err.span.source == .Eval {
        label := "<eval>"
        if path != "" {
            label = fmt.tprintf("%s:<eval>", path)
        }
        return format_compile_error(label, eval_source, err)
    }
    return format_compile_error(path, source, err)
}

format_compile_warning :: proc(path, source: string, warning: Compile_Warning) -> string {
    label := path
    if label == "" {
        label = "<source>"
    }
    message := warning.message
    if message == "" {
        message = "warning"
    }
    line, column, _, _ := source_position(source, warning.span.start)
    return strings.clone(fmt.tprintf("%s:%d:%d: warning: %s\n", label, line, column, message))
}

format_eval_compile_warning :: proc(path, source, eval_source: string, warning: Compile_Warning) -> string {
    if warning.span.source == .Eval {
        label := "<eval>"
        if path != "" {
            label = fmt.tprintf("%s:<eval>", path)
        }
        return format_compile_warning(label, eval_source, warning)
    }
    return format_compile_warning(path, source, warning)
}

clone_compile_error :: proc(err: Compile_Error, allocator := context.allocator) -> Compile_Error {
    cloned := err
    if cloned.message != "" {
        cloned.message = strings.clone(cloned.message, allocator)
    }
    return cloned
}

clone_compile_warning :: proc(warning: Compile_Warning, allocator := context.allocator) -> Compile_Warning {
    cloned := warning
    if cloned.message != "" {
        cloned.message = strings.clone(cloned.message, allocator)
    }
    return cloned
}

compile_warning_slice_delete :: proc(warnings: [dynamic]Compile_Warning, allocator := context.allocator) {
    for warning in warnings {
        if warning.message != "" {
            delete(warning.message, allocator)
        }
    }
    delete(warnings)
}

format_source_map :: proc(entries: []Source_Map_Entry) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, "generated_start generated_end source_start source_end\n")
    for entry in entries {
        fmt.sbprintf(
            &builder,
            "%d %d %d %d\n",
            entry.generated_start_line,
            entry.generated_end_line,
            entry.source_span.start,
            entry.source_span.end,
        )
    }
    return strings.clone(strings.to_string(builder))
}

source_map_entry_for_generated_line :: proc(entries: []Source_Map_Entry, line: int) -> (Source_Map_Entry, bool) {
    return source_map_entry_for_generated_location(entries, line, 0)
}

source_map_entry_for_generated_location :: proc(entries: []Source_Map_Entry, line, column: int) -> (Source_Map_Entry, bool) {
    best: Source_Map_Entry
    found := false
    best_column_constrained := false
    best_generated_width := 0
    best_column_width := 0
    best_source_width := 0
    for entry in entries {
        if line < entry.generated_start_line || line > entry.generated_end_line {
            continue
        }
        column_constrained := column > 0 && entry.generated_start_column > 0
        if column_constrained {
            if column < entry.generated_start_column {
                continue
            }
            if entry.generated_end_column > 0 && column > entry.generated_end_column {
                continue
            }
        }
        generated_width := entry.generated_end_line - entry.generated_start_line
        column_width := 0
        if entry.generated_start_column > 0 && entry.generated_end_column > 0 {
            column_width = entry.generated_end_column - entry.generated_start_column
        }
        source_width := entry.source_span.end - entry.source_span.start
        if !found ||
           (column_constrained && !best_column_constrained) ||
           (column_constrained == best_column_constrained &&
            column_constrained && column_width < best_column_width) ||
           (column_constrained == best_column_constrained &&
            column_width == best_column_width &&
            generated_width < best_generated_width) ||
           (column_constrained == best_column_constrained &&
            column_width == best_column_width &&
            generated_width == best_generated_width &&
            source_width < best_source_width) ||
           (!column_constrained && !best_column_constrained &&
            generated_width < best_generated_width) ||
           (!column_constrained && !best_column_constrained &&
            generated_width == best_generated_width &&
            source_width < best_source_width) {
            best = entry
            found = true
            best_column_constrained = column_constrained
            best_generated_width = generated_width
            best_column_width = column_width
            best_source_width = source_width
        }
    }
    return best, found
}

compile_source :: proc(source: string) -> (output: string, err: Compile_Error, ok: bool) {
    result, err_result, ok_result := compile_source_with_map(source)
    if !ok_result {
        return "", err_result, false
    }
    defer delete(result.source_map)
    defer compile_warning_slice_delete(result.warnings)
    return result.output, {}, true
}

compile_source_with_map :: proc(source: string) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    forms, err_forms, ok_forms := read_top_forms(source)
    if !ok_forms {
        return result, clone_compile_error(err_forms, result_allocator), false
    }
    err_order, ok_order := validate_surface_top_level_order(forms[:])
    if !ok_order {
        return result, clone_compile_error(err_order, result_allocator), false
    }
    loaded, err_load, ok_load := load_root_source_forms(forms[:])
    if !ok_load {
        return result, clone_compile_error(err_load, result_allocator), false
    }
    if !loaded.has_package {
        loaded.has_package = true
        loaded.package_decl = synthetic_package_decl("main")
    }
    combined: [dynamic]CST_Top_Form
    append(&combined, loaded.package_decl)
    for form in loaded.imports {
        append(&combined, form)
    }
    for form in loaded.decls {
        append(&combined, form)
    }
    expanded, _, err_expand, ok_expand := macroexpand_top_forms(combined[:], true)
    if !ok_expand {
        return result, clone_compile_error(err_expand, result_allocator), false
    }
    normalized := normalize_expanded_top_forms(expanded[:])
    program, err_program, ok_program := parse_program(normalized[:])
    if !ok_program {
        return result, clone_compile_error(err_program, result_allocator), false
    }
    lowered, err_lower, ok_lower := lower_program(program)
    if !ok_lower {
        return result, clone_compile_error(err_lower, result_allocator), false
    }
    temp_result, err_emit, ok_emit := emit_ir_program_with_source_map(lowered)
    if !ok_emit {
        return result, clone_compile_error(err_emit, result_allocator), false
    }
    result.output = strings.clone(temp_result.output, result_allocator)
    context.allocator = result_allocator
    for entry in temp_result.source_map {
        append(&result.source_map, entry)
    }
    for warning in temp_result.warnings {
        append(&result.warnings, clone_compile_warning(warning, result_allocator))
    }
    return result, {}, true
}

read_single_eval_form :: proc(source: string) -> (form: CST_Form, err: Compile_Error, ok: bool) {
    forms, err_forms, ok_forms := read_top_forms_with_origin(source, .Eval)
    if !ok_forms {
        return form, err_forms, false
    }
    if len(forms) != 1 {
        return form, Compile_Error{message = "eval expects exactly one form", span = Span{source = .Eval}}, false
    }
    return forms[0].form, {}, true
}

eval_form_head :: proc(form: CST_Form) -> string {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return ""
    }
    return form.items[0].text
}

eval_head_is_decl :: proc(head: string) -> bool {
    switch head {
    case "comment", "core.comment", "package", "import", "def", "def-", "defvar", "defvar-", "defstruct", "defstruct-", "defenum", "defenum-", "defunion", "defunion-", "odin", "defn", "defn-", "deftransform", "deftransform-", "defsource", "defsource-":
        return true
    }
    return false
}

compile_eval_source :: proc(source, eval_source: string, no_print: bool = false) -> (output: string, err: Compile_Error, ok: bool) {
    result, err_result, ok_result := compile_eval_source_with_map(source, eval_source, no_print)
    if !ok_result {
        return "", err_result, false
    }
    defer delete(result.source_map)
    defer compile_warning_slice_delete(result.warnings)
    return result.output, {}, true
}

compile_eval_source_with_map :: proc(source, eval_source: string, no_print: bool = false) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    forms, err_forms, ok_forms := read_top_forms(source)
    if !ok_forms {
        return result, clone_compile_error(err_forms, result_allocator), false
    }
    err_order, ok_order := validate_surface_top_level_order(forms[:])
    if !ok_order {
        return result, clone_compile_error(err_order, result_allocator), false
    }
    loaded, err_load, ok_load := load_root_source_forms(forms[:])
    if !ok_load {
        return result, clone_compile_error(err_load, result_allocator), false
    }
    if !loaded.has_package {
        loaded.has_package = true
        loaded.package_decl = synthetic_package_decl("main")
    }
    combined: [dynamic]CST_Top_Form
    append(&combined, loaded.package_decl)
    for form in loaded.imports {
        append(&combined, form)
    }
    for form in loaded.decls {
        append(&combined, form)
    }
    expanded, macros, err_expand, ok_expand := macroexpand_top_forms(combined[:], true)
    if !ok_expand {
        return result, clone_compile_error(err_expand, result_allocator), false
    }
    normalized := normalize_expanded_top_forms(expanded[:])
    program, err_program, ok_program := parse_program(normalized[:])
    if !ok_program {
        return result, clone_compile_error(err_program, result_allocator), false
    }
    lowered, err_lower, ok_lower := lower_program(program)
    if !ok_lower {
        return result, clone_compile_error(err_lower, result_allocator), false
    }
    eval_form, err_eval, ok_eval := read_single_eval_form(eval_source)
    if !ok_eval {
        return result, clone_compile_error(err_eval, result_allocator), false
    }
    previous_macro_anchor := macro_eval_set_anchor(".")
    expanded_eval_form, err_eval_expand, ok_eval_expand := macroexpand_cst_form_with_macros(eval_form, macros[:])
    macro_eval_restore_anchor(previous_macro_anchor)
    if !ok_eval_expand {
        return result, clone_compile_error(err_eval_expand, result_allocator), false
    }
    defer delete_cst_form(&expanded_eval_form)

    temp_result: Emit_Result
    err_emit: Compile_Error
    ok_emit: bool

    eval_head := eval_form_head(expanded_eval_form)
    if eval_head_is_decl(eval_head) {
        eval_decl, err_decl, ok_decl := parse_decl(CST_Top_Form{form = expanded_eval_form})
        if !ok_decl {
            return result, clone_compile_error(err_decl, result_allocator), false
        }
        temp_result, err_emit, ok_emit = emit_eval_decl_program_with_source_map(lowered, IR_Decl(eval_decl))
    } else {
        temp_result, err_emit, ok_emit = emit_eval_program_with_source_map(lowered, expanded_eval_form, no_print)
    }
    if !ok_emit {
        return result, clone_compile_error(err_emit, result_allocator), false
    }
    result.output = strings.clone(temp_result.output, result_allocator)
    context.allocator = result_allocator
    for entry in temp_result.source_map {
        append(&result.source_map, entry)
    }
    for warning in temp_result.warnings {
        append(&result.warnings, clone_compile_warning(warning, result_allocator))
    }
    return result, {}, true
}

compile_path :: proc(path: string) -> (output: string, err: Compile_Error, ok: bool) {
    result, err_result, ok_result := compile_path_with_map(path)
    if !ok_result {
        return "", err_result, false
    }
    defer delete(result.source_map)
    defer compile_warning_slice_delete(result.warnings)
    return result.output, {}, true
}

compile_path_with_map :: proc(path: string) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := result_allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator

    program, err_program, ok_program := load_path_program(path)
    if !ok_program {
        context.allocator = old_allocator
        return result, clone_compile_error(err_program, result_allocator), false
    }
    context.allocator = old_allocator
    return compile_program_with_map(program)
}

rebase_emitted_odin_imports :: proc(source, output_dir: string) -> (output: string, err: Compile_Error, ok: bool) {
    canonical_output_dir, output_dir_err, output_dir_ok := canonicalize_generated_output_dir(output_dir)
    if !output_dir_ok {
        return "", output_dir_err, false
    }
    defer delete(canonical_output_dir)

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    changed := false
    line_start := 0
    for i := 0; i <= len(source); i += 1 {
        if i < len(source) && source[i] != '\n' {
            continue
        }

        line := source[line_start:i]
        rewritten := line
        if strings.has_prefix(line, "import ") {
            first_quote := strings.index(line, "\"")
            if first_quote >= 0 {
                rest := line[first_quote+1:]
                second_quote := strings.index(rest, "\"")
                if second_quote >= 0 {
                    import_path := rest[:second_quote]
                    if os.is_absolute_path(import_path) {
                        canonical_import_path, import_path_err := os.get_absolute_path(import_path, context.allocator)
                        if import_path_err != nil {
                            return "", Compile_Error{message = fmt.tprintf("could not canonicalize generated Odin import: %s", import_path)}, false
                        }
                        relative_path, rel_err := os.get_relative_path(canonical_output_dir, canonical_import_path, context.allocator)
                        delete(canonical_import_path)
                        if rel_err != nil {
                            return "", Compile_Error{message = fmt.tprintf("could not rebase generated Odin import: %s", import_path)}, false
                        }
                        rewritten = fmt.tprintf("%s%q%s", line[:first_quote], relative_path, rest[second_quote+1:])
                        delete(relative_path)
                        changed = true
                    }
                }
            }
        }
        strings.write_string(&builder, rewritten)
        if i < len(source) {
            strings.write_byte(&builder, '\n')
        }
        line_start = i + 1
    }

    if changed {
        return strings.clone(strings.to_string(builder)), Compile_Error{}, true
    }
    return strings.clone(source), Compile_Error{}, true
}

rebase_emitted_odin_imports_for_output_path :: proc(source, output_path: string) -> (output: string, err: Compile_Error, ok: bool) {
    output_dir, _ := os.split_path(output_path)
    if output_dir == "" {
        output_dir = "."
    }
    return rebase_emitted_odin_imports(source, output_dir)
}

canonicalize_generated_output_dir :: proc(path: string) -> (canonical: string, err: Compile_Error, ok: bool) {
    if path == "" || path == "." {
        canonical, canonical_err := os.get_absolute_path(".", context.allocator)
        if canonical_err != nil {
            return "", Compile_Error{message = "could not canonicalize generated Odin output directory: ."}, false
        }
        return canonical, Compile_Error{}, true
    }
    if os.exists(path) {
        canonical, canonical_err := os.get_absolute_path(path, context.allocator)
        if canonical_err != nil {
            return "", Compile_Error{message = fmt.tprintf("could not canonicalize generated Odin output directory: %s", path)}, false
        }
        return canonical, Compile_Error{}, true
    }

    parent, leaf := os.split_path(path)
    if leaf == "" {
        return "", Compile_Error{message = fmt.tprintf("could not canonicalize generated Odin output directory: %s", path)}, false
    }
    if parent == "" || parent == path {
        parent = "."
    }

    canonical_parent, parent_err, parent_ok := canonicalize_generated_output_dir(parent)
    if !parent_ok {
        return "", parent_err, false
    }
    joined, join_err := os.join_path({canonical_parent, leaf}, context.allocator)
    delete(canonical_parent)
    if join_err != nil {
        return "", Compile_Error{message = fmt.tprintf("could not canonicalize generated Odin output directory: %s", path)}, false
    }
    cleaned, clean_err := os.clean_path(joined, context.allocator)
    delete(joined)
    if clean_err != nil {
        return "", Compile_Error{message = fmt.tprintf("could not canonicalize generated Odin output directory: %s", path)}, false
    }
    return cleaned, Compile_Error{}, true
}

compile_eval_path :: proc(path, eval_source: string, no_print: bool = false) -> (output: string, err: Compile_Error, ok: bool) {
    result, err_result, ok_result := compile_eval_path_with_map(path, eval_source, no_print)
    if !ok_result {
        return "", err_result, false
    }
    defer delete(result.source_map)
    defer compile_warning_slice_delete(result.warnings)
    return result.output, {}, true
}

compile_eval_path_with_map :: proc(path, eval_source: string, no_print: bool = false) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := result_allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator

    expanded_forms, macros, err_program, ok_program := load_path_expanded_forms(path)
    if !ok_program {
        context.allocator = old_allocator
        return result, clone_compile_error(err_program, result_allocator), false
    }
    program, err_parse, ok_parse := parse_program(expanded_forms[:])
    if !ok_parse {
        context.allocator = old_allocator
        return result, clone_compile_error(err_parse, result_allocator), false
    }
    aliases, err_aliases, ok_aliases := collect_root_source_import_aliases(path)
    if !ok_aliases {
        context.allocator = old_allocator
        return result, clone_compile_error(err_aliases, result_allocator), false
    }
    eval_form, err_eval, ok_eval := read_single_eval_form(eval_source)
    if !ok_eval {
        context.allocator = old_allocator
        return result, clone_compile_error(err_eval, result_allocator), false
    }
    eval_form_rewritten, err_rewrite_eval, ok_rewrite_eval := rewrite_form_symbols(eval_form, nil, aliases, "")
    if !ok_rewrite_eval {
        context.allocator = old_allocator
        return result, clone_compile_error(err_rewrite_eval, result_allocator), false
    }
    eval_form = eval_form_rewritten
    previous_macro_anchor := macro_eval_set_anchor(path)
    expanded_eval_form, err_eval_expand, ok_eval_expand := macroexpand_cst_form_with_macros(eval_form, macros[:])
    macro_eval_restore_anchor(previous_macro_anchor)
    if !ok_eval_expand {
        context.allocator = old_allocator
        return result, clone_compile_error(err_eval_expand, result_allocator), false
    }
    context.allocator = old_allocator
    return compile_program_eval_form_with_map(program, expanded_eval_form, no_print)
}
