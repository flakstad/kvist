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
    allow_fallback: bool,
    preserve_qualified_calls: bool,
}

Loaded_Forms :: struct {
    has_package: bool,
    package_decl: CST_Top_Form,
    imports: [dynamic]CST_Top_Form,
    decls: [dynamic]CST_Top_Form,
    exports: [dynamic]string,
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
    cloned.text = strings.clone(form.text)
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

is_builtin_kvist_import_path :: proc(path: string) -> bool {
    switch path {
    case "kvist:core", "kvist:arr", "kvist:str", "kvist:map", "kvist:set", "kvist:struct", "kvist:io", "kvist:json", "kvist:http", "kvist:http/client", "kvist:http/session", "kvist:http/sse", "kvist:http/datastar":
        return true
    case:
        return false
    }
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
    if strings.has_prefix(path, "kvist:") {
        return is_shipped_source_import_path(path) || !is_builtin_kvist_import_path(path)
    }
    for ch in path {
        if ch == ':' {
            return false
        }
    }
    return true
}

is_builtin_kvist_package_path :: proc(path: string) -> bool {
    switch path {
    case "kvist:core", "kvist:arr", "kvist:str", "kvist:map", "kvist:set", "kvist:struct", "kvist:io", "kvist:json", "kvist:hiccup", "kvist:http", "kvist:http/client", "kvist:http/session", "kvist:http/sse", "kvist:http/datastar", "kvist:hot", "kvist:live", "kvist:reload", "kvist:test":
        return true
    }
    return false
}

shipped_source_import_allows_builtin_fallback :: proc(import_path: string) -> bool {
    return is_builtin_kvist_package_path(import_path)
}

is_package_anchor_filename :: proc(dir_path, file_name: string) -> bool {
    if file_name == "main.kvist" || file_name == "package.kvist" {
        return true
    }
    if !strings.has_suffix(file_name, ".kvist") {
        return false
    }
    _, dir_name := os.split_path(dir_path)
    if dir_name == "" {
        return false
    }
    return file_name == fmt.tprintf("%s.kvist", dir_name)
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
    }

    if os.exists(base) && os.is_dir(base) {
        return strings.clone(base), Compile_Error{}, true
    }

    file_path := fmt.tprintf("%s.kvist", base)
    if os.exists(file_path) && !os.is_dir(file_path) {
        return strings.clone(file_path), Compile_Error{}, true
    }
    if os.exists(base) && !os.is_dir(base) {
        return base, Compile_Error{}, true
    }

    kvist_file := fmt.tprintf("%s.kvist", base)
    if os.exists(kvist_file) && !os.is_dir(kvist_file) {
        return kvist_file, Compile_Error{}, true
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
    case "defconst-", "defvar-", "defstruct-", "defenum-", "defunion-", "defn-", "defmacro-":
        return true
    case:
        return false
    }
}

is_top_level_decl_head :: proc(head: string) -> bool {
    switch head {
    case "defconst", "defconst-", "defvar", "defvar-", "defstruct", "defstruct-", "defenum", "defenum-", "defunion", "defunion-", "defn", "defn-", "defmacro", "defmacro-", "proc":
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

source_import_alias_and_path :: proc(form: CST_Form) -> (alias, path: string, ok: bool) {
    if form.kind != .List || len(form.items) == 0 || !is_symbol(form.items[0], "import") {
        return "", "", false
    }
    if len(form.items) >= 3 {
        if form.items[1].kind == .Keyword && form.items[1].text == ":odin" {
            return "", "", false
        }
        if len(form.items) >= 4 && form.items[2].kind == .Keyword && form.items[2].text == ":odin" {
            return "", "", false
        }
    }
    if len(form.items) == 2 && form.items[1].kind == .String {
        path = import_path_text(form.items[1])
        if !is_source_import_path(path) {
            return "", "", false
        }
        return import_default_alias(path), path, true
    }
    if len(form.items) == 3 && form.items[1].kind == .Symbol && form.items[2].kind == .String {
        path = import_path_text(form.items[2])
        if !is_source_import_path(path) {
            return "", "", false
        }
        return map_name(form.items[1].text), path, true
    }
    return "", "", false
}

rewrite_force_odin_import_form :: proc(importer_path: string, top: CST_Top_Form) -> CST_Top_Form {
    rewritten := clone_cst_top_form(top)
    form := &rewritten.form
    if form.kind != .List || len(form.items) < 3 || !is_symbol(form.items[0], "import") {
        return rewritten
    }

    path_index := -1
    if len(form.items) == 3 &&
       form.items[1].kind == .Keyword &&
       form.items[1].text == ":odin" &&
       form.items[2].kind == .String {
        path_index = 2
    }
    if len(form.items) == 4 &&
       form.items[1].kind == .Symbol &&
       form.items[2].kind == .Keyword &&
       form.items[2].text == ":odin" &&
       form.items[3].kind == .String {
        path_index = 3
    }
    if path_index < 0 {
        return rewritten
    }

    raw_path := import_path_text(form.items[path_index])
    if raw_path == "" || os.is_absolute_path(raw_path) || strings.contains(raw_path, ":") {
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
    defer delete(entries)

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
            append(&matched, Package_File{path = file_path, source = file_source, package_name = file_package_name, forms = file_forms})
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
            alias, _, ok_import := source_import_alias_and_path(top.form)
            if !ok_import {
                continue
            }
            _, import_path, _ := source_import_alias_and_path(top.form)
            resolved, err_resolve, ok_resolve := resolve_source_import_path(file.path, import_path)
            if !ok_resolve {
                return nil, err_resolve, false
            }
            import_files, err_files, ok_files := read_package_files(resolved)
            if !ok_files {
                return nil, err_files, false
            }
            _, err_package, ok_package := validate_package_files(resolved, import_files[:])
            if !ok_package {
                return nil, err_package, false
            }
            import_forms := flatten_package_forms(import_files[:])
            append(&aliases, Alias_Prefix{
                alias = alias,
                prefix = alias,
                exports = collect_public_decl_names(import_forms[:]),
                allow_fallback = shipped_source_import_allows_builtin_fallback(import_path),
                preserve_qualified_calls = import_path == "kvist:core",
            })
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
    for alias_map in aliases {
        prefix_text := fmt.tprintf("%s/", alias_map.alias)
        if len(body) > len(prefix_text) && body[:len(prefix_text)] == prefix_text {
            member := body[len(prefix_text):]
            if alias_map.preserve_qualified_calls {
                return text, Compile_Error{}, true
            }
            if len(alias_map.exports) > 0 && !contains_text(alias_map.exports[:], member) {
                if alias_map.allow_fallback {
                    return text, Compile_Error{}, true
                }
                return "", Compile_Error{message = fmt.tprintf("source package member is private or undefined: %s/%s", alias_map.alias, member), span = span}, false
            }
            return fmt.tprintf("%s%s__%s", quote_prefix, alias_map.prefix, member), Compile_Error{}, true
        }
    }
    if prefix != "" && contains_text(locals, body) {
        return fmt.tprintf("%s%s__%s", quote_prefix, prefix, body), Compile_Error{}, true
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
    case "defconst", "defconst-", "defvar", "defvar-", "defstruct", "defstruct-", "defenum", "defenum-", "defunion", "defunion-", "defn", "defn-", "defmacro", "defmacro-", "proc":
        form^.items[1].text = fmt.tprintf("%s__%s", prefix, form^.items[1].text)
    }
}

rewrite_top_form :: proc(top: CST_Top_Form, locals: []string, aliases: []Alias_Prefix, prefix: string) -> (CST_Top_Form, Compile_Error, bool) {
    rewritten := top
    if prefix != "" &&
       top.form.kind == .List &&
       len(top.form.items) >= 2 &&
       top.form.items[1].kind == .Symbol {
        head := decl_head_name(top.form)
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
    source:       string,
    package_name: string,
    forms:        [dynamic]CST_Top_Form,
}

read_package_files :: proc(dir: string) -> ([]Package_File, Compile_Error, bool) {
    if strings.has_suffix(dir, ".kvist") {
        return read_root_package_files(dir)
    }

    entries, err := os.read_directory_by_path(dir, -1, context.allocator)
    if err != nil {
        return nil, Compile_Error{message = fmt.tprintf("could not read package directory: %s", dir)}, false
    }
    defer delete(entries)

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
        append(&files, Package_File{path = path, source = source, package_name = package_name, forms = forms})
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
            alias, path, ok_import := source_import_alias_and_path(top.form)
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
            _, path, is_source_import := source_import_alias_and_path(form)
            if is_source_import {
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
    aliases, _, err_aliases, ok_aliases := collect_package_import_aliases(files)
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
    package_name, err_package, ok_package := validate_package_files(dir, files[:])
    if !ok_package {
        return Loaded_Forms{}, err_package, false
    }
    err_conflicts, ok_conflicts := validate_package_conflicts(files[:])
    if !ok_conflicts {
        return Loaded_Forms{}, err_conflicts, false
    }
    all_forms: [dynamic]CST_Top_Form
    for file in files {
        for top in file.forms {
            append(&all_forms, top)
        }
    }
    locals := collect_local_decl_names(all_forms[:])
    exported := collect_public_decl_names(all_forms[:])
    aliases: [dynamic]Alias_Prefix
    result := Loaded_Forms{}
    for name in exported {
        append(&result.exports, name)
    }
    if package_name != "" {
        self_prefix := prefix
        if self_prefix == "" {
            self_prefix = package_name
        }
        append(&aliases, Alias_Prefix{
            alias = package_name,
            prefix = self_prefix,
            exports = exported,
        })
    }

    for file in files {
        for top in file.forms {
            alias, import_path, ok_import := source_import_alias_and_path(top.form)
            if !ok_import {
                continue
            }
            resolved, err_resolve, ok_resolve := resolve_source_import_path(file.path, import_path)
            if !ok_resolve {
                return result, err_resolve, false
            }
            nested_prefix := alias
            if prefix != "" {
                nested_prefix = fmt.tprintf("%s__%s", prefix, alias)
            }
            nested, err_nested, ok_nested := load_source_forms(resolved, nested_prefix, loaded_keys, import_keys, visiting)
            if !ok_nested {
                return result, err_nested, false
            }
            append(&aliases, Alias_Prefix{
                alias = alias,
                prefix = nested_prefix,
                exports = nested.exports,
                allow_fallback = shipped_source_import_allows_builtin_fallback(import_path),
                preserve_qualified_calls = import_path == "kvist:core",
            })
            for form in nested.imports {
                append_import_form_unique(&result.imports, import_keys, clone_cst_top_form(form))
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
                if prefix == "" {
                    result.has_package = true
                    result.package_decl = synthetic_package_decl(package_name)
                }
                continue
            }
            _, _, is_source_import := source_import_alias_and_path(form)
            if is_source_import {
                _, import_path, _ := source_import_alias_and_path(form)
                if shipped_source_import_allows_builtin_fallback(import_path) {
                    append_import_form_unique(&result.imports, import_keys, top)
                }
                continue
            }
            if head == "import" {
                append_import_form_unique(&result.imports, import_keys, rewrite_force_odin_import_form(file.path, top))
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
            alias, import_path, ok_import := source_import_alias_and_path(top.form)
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
            append(&aliases, Alias_Prefix{
                alias = alias,
                prefix = alias,
                exports = nested.exports,
                allow_fallback = shipped_source_import_allows_builtin_fallback(import_path),
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
            _, _, is_source_import := source_import_alias_and_path(form)
            if is_source_import {
                _, import_path, _ := source_import_alias_and_path(form)
                if shipped_source_import_allows_builtin_fallback(import_path) {
                    append_import_form_unique(&result.imports, &import_keys, top)
                }
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
    expanded, _, err_expand, ok_expand := macroexpand_top_forms(forms[:], true)
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
    case "core/comment", "kvist/core-comment", "package", "import", "defconst", "defvar", "defstruct", "defenum", "defunion", "odin", "proc", "defn":
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
    expanded, macros, err_expand, ok_expand := macroexpand_top_forms(forms[:], true)
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
    expanded_eval_form, err_eval_expand, ok_eval_expand := macroexpand_cst_form_with_macros(eval_form, macros[:])
    if !ok_eval_expand {
        return result, clone_compile_error(err_eval_expand, result_allocator), false
    }

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
    expanded_eval_form, err_eval_expand, ok_eval_expand := macroexpand_cst_form_with_macros(eval_form, macros[:])
    if !ok_eval_expand {
        context.allocator = old_allocator
        return result, clone_compile_error(err_eval_expand, result_allocator), false
    }
    context.allocator = old_allocator
    return compile_program_eval_form_with_map(program, expanded_eval_form, no_print)
}
