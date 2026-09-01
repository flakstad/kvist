package kvist

import "core:fmt"
import "core:os"
import "core:sort"
import "core:strings"
import "core:time"
import "base:runtime"

Alias_Prefix :: struct {
    alias:   string,
    prefix:  string,
    raw_prefix: string,
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
        if aliases^[i].raw_prefix != "" {
            delete(aliases^[i].raw_prefix)
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

odin_package_import_alias :: proc(prefix: string) -> string {
    if prefix == "" {
        return strings.clone("kvist_raw")
    }
    return strings.clone(fmt.tprintf("%s__raw", prefix))
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

validate_surface_internal_call_names_form :: proc(form: CST_Form) -> (Compile_Error, bool) {
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        head := form.items[0]
        if strings.has_prefix(head.text, "kvist-prim-") || strings.has_prefix(head.text, "kvist_prim_") {
            return Compile_Error{
                message = fmt.tprintf("`%s` is an internal lowering name", head.text),
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
            err_form.source_path = top.source_path
            err_form.source_file = top.source_file
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
    if alias == "kvist" {
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
            err_form.source_path = top.source_path
            err_form.source_file = top.source_file
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

text_index :: proc(items: []string, value: string) -> (int, bool) {
    for item, index in items {
        if item == value {
            return index, true
        }
    }
    return -1, false
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
    _, ok := source_import_refer_index(form)
    return ok
}

import_form_has_as :: proc(form: CST_Form) -> bool {
    _, ok := source_import_as_index(form)
    return ok
}

source_import_refer_names :: proc(form: CST_Form) -> (names: [dynamic]string) {
    refer_index, ok_refer := source_import_refer_index(form)
    if !ok_refer {
        return names
    }
    for item in form.items[refer_index].items {
        if item.kind == .Symbol && !contains_text(names[:], item.text) {
            append(&names, strings.clone(item.text))
        }
    }
    return names
}

clone_cst_form :: proc(form: CST_Form) -> CST_Form {
    cloned := form
    if form.text != "" {
        cloned.text = strings.clone(form.text)
    }
    if form.source_text != "" {
        cloned.source_text = strings.clone(form.source_text)
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
    if form.source_text != "" {
        delete(form.source_text)
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
        form        = clone_cst_form(top.form),
        doc_lines   = clone_string_slice(top.doc_lines[:]),
        source      = strings.clone(top.source),
        source_path = top.source_path,
        source_file = top.source_file,
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
            if as_index, has_as := source_import_as_index(form.form); has_as {
                key = fmt.tprintf("%s|%s", form.form.items[as_index].text, path)
            } else {
                key = fmt.tprintf("%s|%s", import_default_alias(path), path)
            }
        } else if import_form_has_as(form.form) {
            as_index, _ := source_import_as_index(form.form)
            key = fmt.tprintf("%s|%s", form.form.items[as_index].text, import_path_text(form.form.items[1]))
        }
    }
    if contains_text(seen[:], key) {
        return
    }
    append(seen, key)
    append(forms, form)
}
