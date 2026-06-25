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
    refer_names: [dynamic]string,
    preserve_qualified_calls: bool,
    allow_unqualified_exports: bool,
}

Loaded_Forms :: struct {
    has_package: bool,
    package_decl: CST_Top_Form,
    imports: [dynamic]CST_Top_Form,
    decls: [dynamic]CST_Top_Form,
    exports: [dynamic]string,
    raw_exports: [dynamic]string,
    source_aliases: [dynamic]string,
}

loaded_forms_delete :: proc(forms: ^Loaded_Forms) {
    delete_borrowed_cst_top_form_slice(&forms.imports)
    delete_borrowed_cst_top_form_slice(&forms.decls)
    delete_string_slice(&forms.exports)
    delete_string_slice(&forms.raw_exports)
    delete_string_slice(&forms.source_aliases)
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
        delete_string_slice(&aliases^[i].refer_names)
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

canonical_surface_head_for_internal_name :: proc(head: string) -> (canonical: string, ok: bool) {
    switch head {
    case "core-count":
        return "count", true
    case "core-empty?":
        return "empty?", true
    case "core-get":
        return "get", true
    case "core-slice":
        return "slice", true
    case "core-contains?":
        return "contains?", true
    case "core-or-else":
        return "or-else", true
    case "core-println":
        return "println", true
    case "core-tap":
        return "tap>", true
    case "core-doc":
        return "doc", true
    case "core-thread-first":
        return "->", true
    case "core-thread-last":
        return "->>", true
    case "core-update!":
        return "update!", true
    case "core-delete!":
        return "delete!", true
    case "core-update":
        return "update", true
    case "arr-map":
        return "arr.map", true
    case "arr-filter":
        return "arr.filter", true
    case "arr-remove":
        return "arr.remove", true
    case "arr-reduce":
        return "arr.reduce", true
    case "arr-map-indexed":
        return "arr.map-indexed", true
    case "arr-reduce-indexed":
        return "arr.reduce-indexed", true
    case "arr-keep":
        return "arr.keep", true
    case "arr-mapcat":
        return "arr.mapcat", true
    case "arr-map!":
        return "arr.map!", true
    case "arr-map-indexed!":
        return "arr.map-indexed!", true
    case "arr-filter!":
        return "arr.filter!", true
    case "arr-remove!":
        return "arr.remove!", true
    case "arr-remove-ordered-at":
        return "arr.remove-ordered-at", true
    case "arr-remove-ordered-at!":
        return "arr.remove-ordered-at!", true
    case "arr-remove-unordered-at":
        return "arr.remove-unordered-at", true
    case "arr-remove-unordered-at!":
        return "arr.remove-unordered-at!", true
    case "arr-keep!":
        return "arr.keep!", true
    case "arr-into":
        return "arr.into", true
    case "arr-into!":
        return "arr.into!", true
    case "arr-interpose":
        return "arr.interpose", true
    case "arr-interleave":
        return "arr.interleave", true
    case "arr-reverse":
        return "arr.reverse", true
    case "arr-reverse!":
        return "arr.reverse!", true
    case "arr-empty":
        return "arr.empty", true
    case "arr-dynamic":
        return "arr.dynamic", true
    case "arr-fixed":
        return "arr.fixed", true
    case "arr-push!":
        return "arr.push!", true
    case "arr-shuffle":
        return "arr.shuffle", true
    case "arr-shuffle!":
        return "arr.shuffle!", true
    case "arr-sort":
        return "arr.sort", true
    case "arr-sort!":
        return "arr.sort!", true
    case "arr-sort-by":
        return "arr.sort-by", true
    case "arr-sort-by!":
        return "arr.sort-by!", true
    case "arr-partition":
        return "arr.partition", true
    case "arr-partition-all":
        return "arr.partition-all", true
    case "arr-partition-by":
        return "arr.partition-by", true
    case "arr-index-by":
        return "arr.index-by", true
    case "arr-group-by":
        return "arr.group-by", true
    case "arr-count-by":
        return "arr.count-by", true
    case "arr-sum-by":
        return "arr.sum-by", true
    case "arr-frequencies":
        return "arr.frequencies", true
    case "arr-distinct":
        return "arr.distinct", true
    case "arr-distinct-by":
        return "arr.distinct-by", true
    case "arr-range":
        return "arr.range", true
    case "arr-repeat":
        return "arr.repeat", true
    case "arr-repeatedly":
        return "arr.repeatedly", true
    case "arr-iterate":
        return "arr.iterate", true
    case "arr-cycle":
        return "arr.cycle", true
    case "arr-take":
        return "arr.take", true
    case "arr-drop":
        return "arr.drop", true
    case "arr-drop-last":
        return "arr.drop-last", true
    case "arr-butlast":
        return "arr.butlast", true
    case "arr-split-at":
        return "arr.split-at", true
    case "arr-take-while":
        return "arr.take-while", true
    case "arr-drop-while":
        return "arr.drop-while", true
    case "arr-find":
        return "arr.find", true
    case "arr-some?":
        return "arr.some?", true
    case "arr-every?":
        return "arr.every?", true
    case "arr-find-indexed":
        return "arr.find-indexed", true
    case "arr-min-by":
        return "arr.min-by", true
    case "arr-max-by":
        return "arr.max-by", true
    case "arr-slice":
        return "arr.slice", true
    case "arr-first":
        return "arr.first", true
    case "arr-second":
        return "arr.second", true
    case "arr-nth":
        return "arr.nth", true
    case "arr-last":
        return "arr.last", true
    case "arr-rest":
        return "arr.rest", true
    case "arr-get":
        return "arr.get", true
    case "map-empty":
        return "map.empty", true
    case "map-of":
        return "map.of", true
    case "map-get":
        return "map.get", true
    case "map-contains?":
        return "map.contains?", true
    case "map-assoc":
        return "map.assoc", true
    case "map-assoc!":
        return "map.assoc!", true
    case "map-dissoc":
        return "map.dissoc", true
    case "map-dissoc!":
        return "map.dissoc!", true
    case "map-merge":
        return "map.merge", true
    case "map-merge!":
        return "map.merge!", true
    case "map-keys":
        return "map.keys", true
    case "map-vals":
        return "map.vals", true
    case "map-zip":
        return "map.zip", true
    case "set-empty":
        return "set.empty", true
    case "set-of":
        return "set.of", true
    case "set-add":
        return "set.add", true
    case "set-add!":
        return "set.add!", true
    case "set-remove":
        return "set.remove", true
    case "set-remove!":
        return "set.remove!", true
    case "set-union":
        return "set.union", true
    case "set-union!":
        return "set.union!", true
    case "set-intersection":
        return "set.intersection", true
    case "set-intersection!":
        return "set.intersection!", true
    case "set-difference":
        return "set.difference", true
    case "set-difference!":
        return "set.difference!", true
    case "set-contains?":
        return "set.contains?", true
    case "set-subset?":
        return "set.subset?", true
    case "set-superset?":
        return "set.superset?", true
    case "set-disjoint?":
        return "set.disjoint?", true
    case "str-slice":
        return "str.slice", true
    case "str-get":
        return "str.get", true
    case "str-split":
        return "str.split", true
    case "str-join":
        return "str.join", true
    case "str-replace":
        return "str.replace", true
    case "str-count":
        return "str.count", true
    case "str-contains?":
        return "str.contains?", true
    case "str-trim":
        return "str.trim", true
    case "str-trim-prefix":
        return "str.trim-prefix", true
    case "str-trim-suffix":
        return "str.trim-suffix", true
    case "str-starts-with?":
        return "str.starts-with?", true
    case "str-ends-with?":
        return "str.ends-with?", true
    case "str-index-of":
        return "str.index-of", true
    case "str-last-index-of":
        return "str.last-index-of", true
    case "str-lower":
        return "str.lower", true
    case "str-upper":
        return "str.upper", true
    case "io-read":
        return "io.read", true
    case "io-write":
        return "io.write", true
    case "json-write":
        return "json.write", true
    case "json-read-as":
        return "json.read-as", true
    case "cli-flag":
        return "cli.flag", true
    case "cli-option":
        return "cli.option", true
    case "cli-int-option":
        return "cli.int-option", true
    case "cli-command":
        return "cli.command", true
    case "cli-env":
        return "cli.env", true
    case "cli-env?":
        return "cli.env?", true
    case "cli-env-int":
        return "cli.env-int", true
    case "cli-terminal-size":
        return "cli.terminal-size", true
    case "cli-stdout-tty?":
        return "cli.stdout-tty?", true
    case "cli-stderr-tty?":
        return "cli.stderr-tty?", true
    case "cli-exit!":
        return "cli.exit!", true
    case "cli-print":
        return "cli.print", true
    case "cli-println":
        return "cli.println", true
    case "cli-printf":
        return "cli.printf", true
    case "cli-eprint":
        return "cli.eprint", true
    case "cli-eprintln":
        return "cli.eprintln", true
    case "cli-eprintf":
        return "cli.eprintf", true
    }
    return "", false
}

validate_surface_internal_call_names_form :: proc(form: CST_Form) -> (Compile_Error, bool) {
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        head := form.items[0]
        canonical, deprecated := canonical_surface_head_for_internal_name(head.text)
        if deprecated {
            return Compile_Error{
                message = fmt.tprintf("`%s` is an internal lowering name; use `%s`", head.text, canonical),
                span = head.span,
            }, false
        }
    }
    #partial switch form.kind {
    case .List, .Vector, .Brace, .Set:
        for item in form.items {
            err_item, ok_item := validate_surface_internal_call_names_form(item)
            if !ok_item {
                return err_item, false
            }
        }
    }
    return Compile_Error{}, true
}

validate_surface_internal_call_names :: proc(forms: []CST_Top_Form) -> (Compile_Error, bool) {
    for top in forms {
        err_form, ok_form := validate_surface_internal_call_names_form(top.form)
        if !ok_form {
            return err_form, false
        }
    }
    return Compile_Error{}, true
}

slash_package_access_message :: proc(text: string, aliases: []string = nil) -> (message: string, ok: bool) {
    slash := strings.index(text, "/")
    if slash <= 0 || slash+1 >= len(text) {
        return "", false
    }
    alias := text[:slash]
    switch alias {
    case "kvist", "core", "arr", "str", "map", "set", "soa", "io", "json", "cli":
        member := text[slash+1:]
        return fmt.tprintf("use `%s.%s` for package access", alias, member), true
    }
    if contains_text(aliases, alias) {
        member := text[slash+1:]
        return fmt.tprintf("use `%s.%s` for package access", alias, member), true
    }
    return "", false
}

validate_surface_package_slash_access_form :: proc(form: CST_Form, aliases: []string = nil) -> (Compile_Error, bool) {
    if form.kind == .Symbol {
        message, bad := slash_package_access_message(form.text, aliases)
        if bad {
            return Compile_Error{message = message, span = form.span}, false
        }
    }
    #partial switch form.kind {
    case .List, .Vector, .Brace, .Set:
        for item in form.items {
            err_item, ok_item := validate_surface_package_slash_access_form(item, aliases)
            if !ok_item {
                return err_item, false
            }
        }
    }
    return Compile_Error{}, true
}

validate_surface_package_slash_access :: proc(forms: []CST_Top_Form, aliases: []string = nil) -> (Compile_Error, bool) {
    for top in forms {
        err_form, ok_form := validate_surface_package_slash_access_form(top.form, aliases)
        if !ok_form {
            return err_form, false
        }
    }
    return Compile_Error{}, true
}

validate_package_files_surface_internal_call_names :: proc(files: []Package_File) -> (Compile_Error, bool) {
    for file in files {
        err_file, ok_file := validate_surface_internal_call_names(file.forms[:])
        if !ok_file {
            return err_file, false
        }
        err_slash, ok_slash := validate_surface_package_slash_access(file.forms[:])
        if !ok_slash {
            return err_slash, false
        }
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

append_unique_string_clone :: proc(values: ^[dynamic]string, value: string) {
    if value == "" || contains_text(values^[:], value) {
        return
    }
    append(values, strings.clone(value))
}

alias_prefix_names :: proc(aliases: []Alias_Prefix) -> (names: [dynamic]string) {
    for alias in aliases {
        append(&names, alias.alias)
    }
    return names
}

source_import_form_has_refer :: proc(form: CST_Form) -> bool {
    return form.kind == .List &&
           len(form.items) == 4 &&
           is_symbol(form.items[0], "import") &&
           form.items[1].kind == .String &&
           form.items[2].kind == .Keyword &&
           form.items[2].text == ":refer" &&
           form.items[3].kind == .Vector
}

source_import_refer_names :: proc(form: CST_Form) -> (names: [dynamic]string) {
    if !source_import_form_has_refer(form) {
        return names
    }
    for item in form.items[3].items {
        if item.kind == .Symbol && !contains_text(names[:], item.text) {
            append(&names, strings.clone(item.text))
        }
    }
    return names
}

core_bare_symbol :: proc(text: string) -> bool {
    switch text {
    case "count", "empty?", "get", "slice", "contains?", "or-else",
         "println", "tap>", "doc", "->", "->>", "update!", "delete!",
         "update":
        return true
    }
    return false
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
        } else if source_import_form_has_refer(form.form) {
            path := import_path_text(form.form.items[1])
            key = fmt.tprintf("%s|%s", import_default_alias(path), path)
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
    packages_dir, ok_packages := kvist_packages_dir(".")
    if !ok_packages {
        return false
    }
    defer delete(packages_dir)
    package_name := path[len("kvist:"):]
    candidate, join_err := os.join_path({packages_dir, package_name}, context.allocator)
    if join_err != nil {
        return false
    }
    defer delete(candidate)
    return os.exists(candidate) && os.is_dir(candidate)
}

is_shipped_package_filesystem_path :: proc(path: string) -> bool {
    packages_dir, ok_packages := kvist_packages_dir(path)
    if !ok_packages {
        return false
    }
    defer delete(packages_dir)

    abs_packages, packages_err := os.get_absolute_path(packages_dir, context.allocator)
    if packages_err != nil {
        return false
    }
    defer delete(abs_packages)

    abs_path, path_err := os.get_absolute_path(path, context.allocator)
    if path_err != nil {
        return false
    }
    defer delete(abs_path)

    slash_prefix := fmt.tprintf("%s/", abs_packages)
    defer delete(slash_prefix)
    backslash_prefix := fmt.tprintf("%s\\", abs_packages)
    defer delete(backslash_prefix)
    return abs_path == abs_packages ||
           strings.has_prefix(abs_path, slash_prefix) ||
           strings.has_prefix(abs_path, backslash_prefix)
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
    packages_dir, ok_packages := kvist_packages_dir(importer_path)
    if !ok_packages {
        return "", Compile_Error{message = fmt.tprintf("could not resolve shipped source import: %s", import_path)}, false
    }
    defer delete(packages_dir)
    candidate, join_err := os.join_path({packages_dir, package_name}, context.allocator)
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

read_kvist_top_forms :: proc(source: string) -> ([dynamic]CST_Top_Form, Compile_Error, bool) {
    forms, err_forms, ok_forms := read_top_forms(source)
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
    if import_path == "kvist:map" && !contains_text(names^[:], "entry") {
        append(names, "entry")
    }
}

source_import_alias_and_path :: proc(form: CST_Form, importer_path: string = ".") -> (alias, path: string, ok: bool) {
    if form.kind != .List || len(form.items) == 0 || !is_symbol(form.items[0], "import") {
        return "", "", false
    }
    if len(form.items) == 2 && form.items[1].kind == .String {
        return "", "", false
    }
    if len(form.items) == 4 &&
       form.items[1].kind == .String &&
       form.items[2].kind == .Keyword &&
       form.items[2].text == ":refer" &&
       form.items[3].kind == .Vector {
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
        resolved, abs_err := os.get_absolute_path(raw_path, context.allocator)
        if abs_err != nil {
            return rewritten
        }
        defer delete(resolved)
        delete(form.items[path_index].text)
        form.items[path_index].text = fmt.tprintf("%q", resolved)
        return rewritten
    }
    resolved, join_err := os.join_path({base_dir, raw_path}, context.allocator)
    if join_err != nil {
        return rewritten
    }
    if !os.exists(resolved) {
        delete(resolved)
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
            dir = "."
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
    forms, err_forms, ok_forms := read_kvist_top_forms(source)
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
        file_forms, err_file_forms, ok_file_forms := read_kvist_top_forms(file_source)
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
                refer_names = source_import_refer_names(top.form),
                allow_unqualified_exports = source_import_form_has_refer(top.form),
            })
            delete(import_path)
        }
    }
    return aliases[:], Compile_Error{}, true
}

bare_source_import_symbol_text :: proc(body: string, aliases: []Alias_Prefix, span: Span) -> (text: string, matched: bool, err: Compile_Error, ok: bool) {
    if core_bare_symbol(body) {
        return "", false, Compile_Error{}, true
    }
    matched_alias := ""
    matched_prefix := ""
    for alias_map in aliases {
        if !alias_map.allow_unqualified_exports {
            continue
        }
        if !contains_text(alias_map.refer_names[:], body) {
            continue
        }
        if !contains_text(alias_map.exports[:], body) {
            continue
        }
        if matched {
            return "", false, Compile_Error{message = fmt.tprintf("ambiguous bare source package member `%s`; use `%s.%s` or `%s.%s`", body, matched_alias, body, alias_map.alias, body), span = span}, false
        }
        matched = true
        matched_alias = alias_map.alias
        matched_prefix = alias_map.prefix
    }
    if !matched {
        return "", false, Compile_Error{}, true
    }
    return fmt.tprintf("%s__%s", matched_prefix, body), true, Compile_Error{}, true
}

rewrite_symbol_text :: proc(text: string, locals: []string, aliases: []Alias_Prefix, prefix: string, span: Span = {}, allow_bare_import: bool = false) -> (string, Compile_Error, bool) {
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
    if allow_bare_import && quote_prefix == "" && operator_prefix == "" && !strings.contains_any(body, "./") {
        bare_text, matched_bare, err_bare, ok_bare := bare_source_import_symbol_text(body, aliases, span)
        if !ok_bare {
            return "", err_bare, false
        }
        if matched_bare {
            return bare_text, Compile_Error{}, true
        }
    }
    if len(body) > 0 && body[0] == '[' {
        close := -1
        for ch, i in body {
            if ch == ']' {
                close = i
                break
            }
        }
        if close >= 0 && close+1 < len(body) {
            suffix := body[close+1:]
            rewritten_suffix, err_suffix, ok_suffix := rewrite_symbol_text(suffix, locals, aliases, prefix, span)
            if !ok_suffix {
                return "", err_suffix, false
            }
            if rewritten_suffix != suffix {
                return fmt.tprintf("%s%s%s%s", quote_prefix, operator_prefix, body[:close+1], rewritten_suffix), Compile_Error{}, true
            }
        }
    }
    return text, Compile_Error{}, true
}

rewrite_form_symbols :: proc(form: CST_Form, locals: []string, aliases: []Alias_Prefix, prefix: string, allow_bare_import: bool = false) -> (CST_Form, Compile_Error, bool) {
    rewritten := form
    #partial switch form.kind {
    case .Symbol:
        text, err_text, ok_text := rewrite_symbol_text(form.text, locals, aliases, prefix, form.span, allow_bare_import)
        if !ok_text {
            return CST_Form{}, err_text, false
        }
        rewritten.text = text
        return rewritten, Compile_Error{}, true
    case .List, .Vector, .Brace:
        if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
            head := form.items[0].text
            if head == "make" || head == "alloc" || head == "zero" || head == "transmute" || head == "type-assert" {
                rewritten.items = nil
                append(&rewritten.items, form.items[0])
                type_start := 1
                if head == "type-assert" {
                    if len(form.items) > 1 {
                        value, err_value, ok_value := rewrite_form_symbols(form.items[1], locals, aliases, prefix)
                        if !ok_value {
                            return CST_Form{}, err_value, false
                        }
                        append(&rewritten.items, value)
                    }
                    type_start = 2
                }
                if type_start < len(form.items) {
                    _, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], type_start)
                    if !ok_type {
                        return CST_Form{}, err_type, false
                    }
                    for type_item in form.items[type_start:next_i] {
                        rewritten_type_item, err_type_item, ok_type_item := rewrite_type_form_symbols(type_item, locals, aliases, prefix)
                        if !ok_type_item {
                            return CST_Form{}, err_type_item, false
                        }
                        append(&rewritten.items, rewritten_type_item)
                    }
                    for item in form.items[next_i:] {
                        child, err_child, ok_child := rewrite_form_symbols(item, locals, aliases, prefix)
                        if !ok_child {
                            return CST_Form{}, err_child, false
                        }
                        append(&rewritten.items, child)
                    }
                }
                return rewritten, Compile_Error{}, true
            }
        }
        rewritten.items = nil
        for item, idx in form.items {
            child, err_child, ok_child := rewrite_form_symbols(item, locals, aliases, prefix, form.kind == .List && idx == 0)
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
    case "def", "def-", "defvar", "defvar-", "defstruct", "defstruct-", "defenum", "defenum-", "defunion", "defunion-", "defn", "defn-", "defmacro", "defmacro-", "deftransform", "deftransform-", "defiter", "defiter-":
        form^.items[1].text = fmt.tprintf("%s__%s", prefix, form^.items[1].text)
    }
}

type_constructor_symbol :: proc(text: string) -> bool {
    switch text {
    case "slice", "dynamic", "array", "map", "set", "matrix", "ptr", "distinct", "fn", "type":
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

param_names_from_signature_vector :: proc(form: CST_Form) -> (names: [dynamic]string, err: Compile_Error, ok: bool) {
    if form.kind != .Vector {
        return names, Compile_Error{}, true
    }
    i := 0
    for i < len(form.items) {
        target := form.items[i]
        if target.kind != .Symbol || len(target.text) == 0 || target.text[len(target.text)-1] != ':' {
            i += 1
            continue
        }
        append(&names, target.text[:len(target.text)-1])
        _, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], i+1)
        if !ok_type {
            return names, err_type, false
        }
        i = next_i
        if i < len(form.items) && is_symbol(form.items[i], "=") {
            i += 2
        }
    }
    return names, Compile_Error{}, true
}

locals_without_shadowed_names :: proc(locals: []string, shadowed: []string) -> (out: [dynamic]string) {
    for local in locals {
        if contains_text(shadowed, local) {
            continue
        }
        append(&out, local)
    }
    return out
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

    body_locals := locals
    shadowed_params: [dynamic]string
    filtered_locals: [dynamic]string
    if params_index < len(form.items) && form.items[params_index].kind == .Vector {
        param_names, err_param_names, ok_param_names := param_names_from_signature_vector(form.items[params_index])
        if !ok_param_names {
            return CST_Top_Form{}, err_param_names, false
        }
        shadowed_params = param_names
        defer delete(shadowed_params)
        filtered_locals = locals_without_shadowed_names(locals, shadowed_params[:])
        defer delete(filtered_locals)
        body_locals = filtered_locals[:]
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
            if (decl_head_name(form) == "defiter" || decl_head_name(form) == "defiter-") &&
               next_i < len(form.items) && is_symbol(form.items[next_i], "yields") {
                append(&rewritten.form.items, form.items[next_i])
                if next_i+1 >= len(form.items) {
                    return CST_Top_Form{}, Compile_Error{message = "missing item type after 'yields'", span = form.items[next_i].span}, false
                }
                _, next_item_i, err_item_type, ok_item_type := parse_type_text_from_forms(form.items[:], next_i+1)
                if !ok_item_type {
                    return CST_Top_Form{}, err_item_type, false
                }
                for type_item in form.items[next_i+1:next_item_i] {
                    rewritten_type_item, err_type_item, ok_type_item := rewrite_type_form_symbols(type_item, locals, aliases, prefix)
                    if !ok_type_item {
                        return CST_Top_Form{}, err_type_item, false
                    }
                    append(&rewritten.form.items, rewritten_type_item)
                }
                i = next_item_i
                continue
            }
            i = next_i
            continue
        }

        child, err_child, ok_child := rewrite_form_symbols(item, body_locals, aliases, prefix)
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
        if head == "defn" || head == "defn-" || head == "defiter" || head == "defiter-" {
            return rewrite_proc_like_top_form(top, locals, aliases, prefix)
        }
        if is_top_level_decl_head(head) {
            if head == "defenum" || head == "defenum-" {
                renamed := top
                renamed.form = top.form
                renamed.form.items = nil
                for item, idx in top.form.items {
                    if idx == 1 {
                        name := item
                        name.text = fmt.tprintf("%s__%s", prefix, item.text)
                        append(&renamed.form.items, name)
                    } else {
                        append(&renamed.form.items, clone_cst_form(item))
                    }
                }
                return renamed, Compile_Error{}, true
            }
            if head == "def" || head == "def-" {
                value_index := 2
                if len(top.form.items) > 3 && top.form.items[2].kind == .String {
                    value_index = 3
                }
                if value_index < len(top.form.items) &&
                   top.form.items[value_index].kind == .List &&
                   len(top.form.items[value_index].items) > 0 &&
                   is_symbol(top.form.items[value_index].items[0], "overload") {
                    rewritten.form = top.form
                    rewritten.form.items = nil
                    for item, idx in top.form.items {
                        if idx == 1 {
                            renamed := item
                            renamed.text = fmt.tprintf("%s__%s", prefix, item.text)
                            append(&rewritten.form.items, renamed)
                            continue
                        }
                        if idx == value_index {
                            overload_form := item
                            overload_form.items = nil
                            append(&overload_form.items, item.items[0])
                            for member in item.items[1:] {
                                child, err_child, ok_child := rewrite_form_symbols(member, locals, aliases, prefix)
                                if !ok_child {
                                    return CST_Top_Form{}, err_child, false
                                }
                                append(&overload_form.items, child)
                            }
                            append(&rewritten.form.items, overload_form)
                            continue
                        }
                        append(&rewritten.form.items, item)
                    }
                    return rewritten, Compile_Error{}, true
                }
                if type_alias_candidate_from_forms(top.form.items[:], value_index) {
                    _, next_type, _, ok_type := parse_type_text_from_forms(top.form.items[:], value_index)
                    if ok_type && next_type == len(top.form.items) {
                        rewritten.form = top.form
                        rewritten.form.items = nil
                        for item, idx in top.form.items {
                            if idx == 1 {
                                renamed := item
                                renamed.text = fmt.tprintf("%s__%s", prefix, item.text)
                                append(&rewritten.form.items, renamed)
                                continue
                            }
                            if idx >= value_index {
                                child, err_child, ok_child := rewrite_type_form_symbols(item, locals, aliases, prefix)
                                if !ok_child {
                                    return CST_Top_Form{}, err_child, false
                                }
                                append(&rewritten.form.items, child)
                                continue
                            }
                            append(&rewritten.form.items, item)
                        }
                        return rewritten, Compile_Error{}, true
                    }
                }
            }
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
        forms, err_forms, ok_forms := read_kvist_top_forms(source)
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
        append_unique_string_clone(&result.source_aliases, package_name)
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
    if !is_shipped_package_filesystem_path(path) {
        err_surface, ok_surface := validate_package_files_surface_internal_call_names(files[:])
        if !ok_surface {
            return Loaded_Forms{}, err_surface, false
        }
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
    err_expanded_slash, ok_expanded_slash := validate_surface_package_slash_access(expanded_forms[:], loaded.source_aliases[:])
    if !ok_expanded_slash {
        return expanded, macros, err_expanded_slash, false
    }
    aliases, err_aliases, ok_aliases := collect_root_source_import_aliases(path)
    if !ok_aliases {
        return expanded, macros, err_aliases, false
    }
    for &alias in aliases {
        alias.allow_unqualified_exports = false
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

    forms, err_forms, ok_forms := read_kvist_top_forms(source)
    if !ok_forms {
        return result, clone_compile_error(err_forms, result_allocator), false
    }
    err_order, ok_order := validate_surface_top_level_order(forms[:])
    if !ok_order {
        return result, clone_compile_error(err_order, result_allocator), false
    }
    err_surface, ok_surface := validate_surface_internal_call_names(forms[:])
    if !ok_surface {
        return result, clone_compile_error(err_surface, result_allocator), false
    }
    err_slash, ok_slash := validate_surface_package_slash_access(forms[:])
    if !ok_slash {
        return result, clone_compile_error(err_slash, result_allocator), false
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
    err_expanded_slash, ok_expanded_slash := validate_surface_package_slash_access(expanded[:], loaded.source_aliases[:])
    if !ok_expanded_slash {
        return result, clone_compile_error(err_expanded_slash, result_allocator), false
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
    err_surface, ok_surface := validate_surface_internal_call_names(forms[:])
    if !ok_surface {
        return form, err_surface, false
    }
    err_slash, ok_slash := validate_surface_package_slash_access(forms[:])
    if !ok_slash {
        return form, err_slash, false
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
    case "comment", "core.comment", "package", "import", "foreign-import", "def", "def-", "defvar", "defvar-", "defstruct", "defstruct-", "defenum", "defenum-", "defunion", "defunion-", "odin", "@exports", "defn", "defn-", "deftransform", "deftransform-", "defiter", "defiter-":
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

    forms, err_forms, ok_forms := read_kvist_top_forms(source)
    if !ok_forms {
        return result, clone_compile_error(err_forms, result_allocator), false
    }
    err_order, ok_order := validate_surface_top_level_order(forms[:])
    if !ok_order {
        return result, clone_compile_error(err_order, result_allocator), false
    }
    err_surface, ok_surface := validate_surface_internal_call_names(forms[:])
    if !ok_surface {
        return result, clone_compile_error(err_surface, result_allocator), false
    }
    err_slash, ok_slash := validate_surface_package_slash_access(forms[:])
    if !ok_slash {
        return result, clone_compile_error(err_slash, result_allocator), false
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
    err_expanded_slash, ok_expanded_slash := validate_surface_package_slash_access(expanded[:], loaded.source_aliases[:])
    if !ok_expanded_slash {
        return result, clone_compile_error(err_expanded_slash, result_allocator), false
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
    err_eval_slash, ok_eval_slash := validate_surface_package_slash_access_form(expanded_eval_form, loaded.source_aliases[:])
    if !ok_eval_slash {
        return result, clone_compile_error(err_eval_slash, result_allocator), false
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
    source_dir, _ := os.split_path(path)
    if source_dir == "" {
        source_dir = "."
    }
    rebased, err_rebase, ok_rebase := rebase_emitted_odin_imports(result.output, source_dir)
    delete(result.output)
    if !ok_rebase {
        return "", err_rebase, false
    }
    result.output = rebased
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
    err_compile: Compile_Error
    ok_compile: bool
    result, err_compile, ok_compile = compile_program_with_map(program)
    if !ok_compile {
        return result, err_compile, false
    }
    return result, {}, true
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
                            strings.write_string(&builder, rewritten)
                            if i < len(source) {
                                strings.write_byte(&builder, '\n')
                            }
                            line_start = i + 1
                            continue
                        }
                        relative_path, rel_err := os.get_relative_path(canonical_output_dir, canonical_import_path, context.allocator)
                        delete(canonical_import_path)
                        import_path_for_output := ""
                        if rel_err == nil {
                            import_path_for_output = relative_path
                        } else {
                            import_path_for_output = import_path
                        }
                        import_relative_path := forward_slash_path(import_path_for_output)
                        if rel_err == nil {
                            delete(relative_path)
                        }
                        rewritten = fmt.tprintf("%s%q%s", line[:first_quote], import_relative_path, rest[second_quote+1:])
                        delete(import_relative_path)
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

forward_slash_path :: proc(path: string) -> string {
    normalized, allocated := strings.replace_all(path, "\\", "/", context.allocator)
    if allocated {
        return normalized
    }
    return strings.clone(path)
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
    alias_names := alias_prefix_names(aliases)
    defer delete(alias_names)
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
    err_eval_slash, ok_eval_slash := validate_surface_package_slash_access_form(expanded_eval_form, alias_names[:])
    if !ok_eval_slash {
        context.allocator = old_allocator
        return result, clone_compile_error(err_eval_slash, result_allocator), false
    }
    context.allocator = old_allocator
    return compile_program_eval_form_with_map(program, expanded_eval_form, no_print)
}
