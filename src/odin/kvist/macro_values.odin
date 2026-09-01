package kvist

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "base:runtime"

Macro_Expander :: struct {
    builder:    strings.Builder,
    line:       int,
    source_map: ^[dynamic]Source_Map_Entry,
}

Macro_Param_Spec :: struct {
    names:      [dynamic]string,
    form_params: [dynamic]bool,
    has_rest:   bool,
    rest_name:  string,
}

clone_bool_slice :: proc(values: []bool) -> [dynamic]bool {
    out: [dynamic]bool
    for value in values {
        append(&out, value)
    }
    return out
}

User_Macro :: struct {
    name:      string,
    doc_lines: [dynamic]string,
    params:    Macro_Param_Spec,
    body:      [dynamic]CST_Form,
    span:      Span,
}

delete_user_macro :: proc(macro_decl: ^User_Macro) {
    if macro_decl.name != "" {
        delete(macro_decl.name)
    }
    delete_string_slice(&macro_decl.doc_lines)
    delete_string_slice(&macro_decl.params.names)
    delete(macro_decl.params.form_params)
    if macro_decl.params.rest_name != "" {
        delete(macro_decl.params.rest_name)
    }
    delete_cst_form_slice(&macro_decl.body)
    macro_decl^ = User_Macro{}
}

delete_user_macro_slice :: proc(macros: ^[dynamic]User_Macro) {
    for i in 0 ..< len(macros^) {
        delete_user_macro(&macros^[i])
    }
    delete(macros^)
    macros^ = nil
}

clone_user_macro :: proc(macro_decl: User_Macro) -> User_Macro {
    return User_Macro{
        name = strings.clone(macro_decl.name),
        doc_lines = clone_string_slice(macro_decl.doc_lines[:]),
        params = Macro_Param_Spec{
            names       = clone_string_slice(macro_decl.params.names[:]),
            form_params = clone_bool_slice(macro_decl.params.form_params[:]),
            has_rest    = macro_decl.params.has_rest,
            rest_name   = strings.clone(macro_decl.params.rest_name),
        },
        body = clone_cst_form_slice(macro_decl.body[:]),
        span = macro_decl.span,
    }
}

Macro_Value_Kind :: enum {
    Nil,
    Bool,
    Int,
    Float,
    String,
    Form,
    Forms,
}

Macro_Value :: struct {
    kind:         Macro_Value_Kind,
    bool_value:   bool,
    int_value:    int,
    float_value:  f64,
    string_value: string,
    owns_string:  bool,
    form:         CST_Form,
    owns_form:    bool,
    forms:        [dynamic]CST_Form,
    owns_forms:   bool,
    owns_form_contents: bool,
}

Macro_Binding :: struct {
    name:  string,
    value: Macro_Value,
}

macro_gensym_counter: int

@(thread_local)
macro_eval_anchor_path: string

macro_eval_set_anchor :: proc(anchor_path: string) -> string {
    previous := macro_eval_anchor_path
    macro_eval_anchor_path = anchor_path
    return previous
}

macro_eval_restore_anchor :: proc(previous: string) {
    macro_eval_anchor_path = previous
}

macro_eval_read_file_path :: proc(raw_path: string, span: Span) -> (path: string, err: Compile_Error, ok: bool) {
    if raw_path == "" {
        return "", Compile_Error{message = "read-file path must not be empty", span = span}, false
    }
    if os.is_absolute_path(raw_path) {
        return strings.clone(raw_path), Compile_Error{}, true
    }

    base := macro_eval_anchor_path
    if base == "" {
        base = "."
    }
    if strings.has_suffix(base, ".kvist") {
        dir, _ := os.split_path(base)
        if dir == "" {
            base = "."
        } else {
            base = dir
        }
    }

    resolved, join_err := os.join_path({base, raw_path}, context.allocator)
    if join_err != nil {
        return "", Compile_Error{message = fmt.tprintf("could not resolve compile-time read-file path: %s", raw_path), span = span}, false
    }
    return resolved, Compile_Error{}, true
}

macro_source_symbol_text :: proc(form: CST_Form) -> string {
    if form.source_text != "" && strings.contains(form.source_text, ".") {
        return form.source_text
    }
    return form.text
}

macro_unqualified_symbol_name :: proc(text: string) -> string {
    name := text
    if len(name) > 1 && name[0] == '.' {
        name = name[1:]
    }
    if len(name) > 1 && name[len(name)-1] == ':' {
        name = name[:len(name)-1]
    }
    dot := -1
    for ch, idx in name {
        if ch == '.' {
            dot = idx
        }
    }
    if dot >= 0 && dot+1 < len(name) {
        name = name[dot+1:]
    }
    return name
}

macro_quote_string :: proc(text: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_byte(&builder, '"')
    for ch in text {
        switch ch {
        case '\\':
            strings.write_string(&builder, "\\\\")
        case '"':
            strings.write_string(&builder, "\\\"")
        case '\n':
            strings.write_string(&builder, "\\n")
        case '\r':
            strings.write_string(&builder, "\\r")
        case '\t':
            strings.write_string(&builder, "\\t")
        case:
            strings.write_byte(&builder, byte(ch))
        }
    }
    strings.write_byte(&builder, '"')
    return strings.clone(strings.to_string(builder))
}

macro_int_text :: proc(value: int) -> string {
    return fmt.tprintf("%d", value)
}

macro_float_text :: proc(value: f64) -> string {
    return fmt.tprintf("%g", value)
}

macro_nil_value :: proc() -> Macro_Value {
    return Macro_Value{kind = .Nil}
}

macro_bool_value :: proc(value: bool) -> Macro_Value {
    return Macro_Value{kind = .Bool, bool_value = value}
}

macro_int_value :: proc(value: int) -> Macro_Value {
    return Macro_Value{kind = .Int, int_value = value}
}

macro_float_value :: proc(value: f64) -> Macro_Value {
    return Macro_Value{kind = .Float, float_value = value}
}

macro_string_value :: proc(value: string) -> Macro_Value {
    return Macro_Value{kind = .String, string_value = value}
}

macro_owned_string_value :: proc(value: string) -> Macro_Value {
    return Macro_Value{kind = .String, string_value = value, owns_string = true}
}

macro_form_value :: proc(form: CST_Form) -> Macro_Value {
    return Macro_Value{kind = .Form, form = form}
}

macro_owned_form_value :: proc(form: CST_Form) -> Macro_Value {
    return Macro_Value{kind = .Form, form = form, owns_form = true}
}

macro_forms_value :: proc(forms: []CST_Form) -> Macro_Value {
    out: [dynamic]CST_Form
    for form in forms {
        append(&out, form)
    }
    return Macro_Value{kind = .Forms, forms = out, owns_forms = true}
}

macro_owned_forms_value :: proc(forms: []CST_Form) -> Macro_Value {
    out: [dynamic]CST_Form
    for form in forms {
        append(&out, form)
    }
    return Macro_Value{kind = .Forms, forms = out, owns_forms = true, owns_form_contents = true}
}

macro_value_clone_backing :: proc(value: Macro_Value) -> Macro_Value {
    #partial switch value.kind {
    case .String:
        if value.owns_string {
            return macro_owned_string_value(strings.clone(value.string_value))
        }
        return value
    case .Form:
        if value.owns_form {
            return macro_owned_form_value(clone_cst_form(value.form))
        }
        return value
    case .Forms:
        if value.owns_form_contents {
            cloned := clone_cst_form_slice(value.forms[:])
            result := macro_owned_forms_value(cloned[:])
            delete(cloned)
            return result
        }
        return macro_forms_value(value.forms[:])
    case:
        return value
    }
}

macro_value_delete_backing :: proc(value: ^Macro_Value) {
    #partial switch value.kind {
    case .String:
        if value.owns_string && value.string_value != "" {
            delete(value.string_value)
        }
    case .Form:
        if value.owns_form {
            delete_cst_form(&value.form)
        }
    case .Forms:
        if value.owns_forms {
            if value.owns_form_contents {
                for i in 0 ..< len(value.forms) {
                    delete_cst_form(&value.forms[i])
                }
            }
            delete(value.forms)
        }
    }
    value^ = Macro_Value{}
}

macro_value_borrow :: proc(value: Macro_Value) -> Macro_Value {
    borrowed := value
    borrowed.owns_string = false
    borrowed.owns_form = false
    borrowed.owns_forms = false
    borrowed.owns_form_contents = false
    return borrowed
}

macro_binding_slice_delete_backing :: proc(bindings: ^[]Macro_Binding) {
    for i in 0 ..< len(bindings^) {
        macro_value_delete_backing(&bindings^[i].value)
    }
    delete(bindings^)
    bindings^ = nil
}

macro_truthy :: proc(value: Macro_Value) -> bool {
    #partial switch value.kind {
    case .Nil:
        return false
    case .Bool:
        return value.bool_value
    case:
        return true
    }
}

macro_scalar_form_equal_value :: proc(form: CST_Form, value: Macro_Value) -> bool {
    #partial switch form.kind {
    case .Nil:
        return value.kind == .Nil
    case .Bool:
        return value.kind == .Bool && (form.text == "true") == value.bool_value
    case .Number:
        if int_value, ok := strconv.parse_int(form.text); ok {
            if value.kind == .Int {
                return int_value == value.int_value
            }
            if value.kind == .Float {
                return f64(int_value) == value.float_value
            }
            return false
        }
        if float_value, ok := strconv.parse_f64(form.text); ok {
            if value.kind == .Float {
                return float_value == value.float_value
            }
            if value.kind == .Int {
                return float_value == f64(value.int_value)
            }
        }
        return false
    case .String:
        if value.kind != .String {
            return false
        }
        text := unquote_string(form.text)
        defer delete(text)
        return text == value.string_value
    }
    return false
}

macro_value_equal :: proc(a, b: Macro_Value) -> bool {
    if a.kind != b.kind {
        if a.kind == .Form && macro_scalar_form_equal_value(a.form, b) {
            return true
        }
        if b.kind == .Form && macro_scalar_form_equal_value(b.form, a) {
            return true
        }
        if a.kind == .Int && b.kind == .Float {
            return f64(a.int_value) == b.float_value
        }
        if a.kind == .Float && b.kind == .Int {
            return a.float_value == f64(b.int_value)
        }
        return false
    }
    switch a.kind {
    case .Nil:
        return true
    case .Bool:
        return a.bool_value == b.bool_value
    case .Int:
        return a.int_value == b.int_value
    case .Float:
        return a.float_value == b.float_value
    case .String:
        return a.string_value == b.string_value
    case .Form:
        a_text := macro_form_text(a.form)
        defer delete(a_text)
        b_text := macro_form_text(b.form)
        defer delete(b_text)
        return a_text == b_text
    case .Forms:
        if len(a.forms) != len(b.forms) {
            return false
        }
        for form, idx in a.forms {
            a_text := macro_form_text(form)
            defer delete(a_text)
            b_text := macro_form_text(b.forms[idx])
            defer delete(b_text)
            if a_text != b_text {
                return false
            }
        }
        return true
    }
    return false
}

macro_value_number :: proc(value: Macro_Value) -> (f64, bool) {
    #partial switch value.kind {
    case .Int:
        return f64(value.int_value), true
    case .Float:
        return value.float_value, true
    case .Form:
        if value.form.kind == .Number {
            parsed_int, ok_int := strconv.parse_int(value.form.text)
            if ok_int {
                return f64(parsed_int), true
            }
            parsed_float, ok_float := strconv.parse_f64(value.form.text)
            return parsed_float, ok_float
        }
    case:
    }
    return 0, false
}

macro_value_to_form :: proc(value: Macro_Value, span: Span) -> (CST_Form, Compile_Error, bool) {
    switch value.kind {
    case .Form:
        if value.owns_form {
            return clone_cst_form(value.form), Compile_Error{}, true
        }
        return value.form, Compile_Error{}, true
    case .Nil:
        return CST_Form{kind = .Nil, text = strings.clone("nil"), span = span}, Compile_Error{}, true
    case .Bool:
        if value.bool_value {
            return CST_Form{kind = .Bool, text = strings.clone("true"), span = span}, Compile_Error{}, true
        }
        return CST_Form{kind = .Bool, text = strings.clone("false"), span = span}, Compile_Error{}, true
    case .Int:
        return CST_Form{kind = .Number, text = strings.clone(macro_int_text(value.int_value)), span = span}, Compile_Error{}, true
    case .Float:
        return CST_Form{kind = .Number, text = strings.clone(macro_float_text(value.float_value)), span = span}, Compile_Error{}, true
    case .String:
        return CST_Form{kind = .String, text = macro_quote_string(value.string_value), span = span}, Compile_Error{}, true
    case .Forms:
        return CST_Form{}, Compile_Error{message = "expected single macro form value", span = span}, false
    }
    return CST_Form{}, Compile_Error{message = "unsupported macro value", span = span}, false
}

macro_value_to_forms :: proc(value: Macro_Value, span: Span) -> ([]CST_Form, Compile_Error, bool) {
    #partial switch value.kind {
    case .Forms:
        out: [dynamic]CST_Form
        for form in value.forms {
            append(&out, clone_cst_form(form))
        }
        return out[:], Compile_Error{}, true
    case:
        form, err, ok := macro_value_to_form(value, span)
        if !ok {
            return nil, err, false
        }
        out: [dynamic]CST_Form
        append(&out, form)
        return out[:], Compile_Error{}, true
    }
}

macro_value_to_owned_form :: proc(value: Macro_Value, span: Span) -> (CST_Form, Compile_Error, bool) {
    switch value.kind {
    case .Form:
        return clone_cst_form(value.form), Compile_Error{}, true
    case .Nil:
        return CST_Form{kind = .Nil, text = strings.clone("nil"), span = span}, Compile_Error{}, true
    case .Bool:
        if value.bool_value {
            return CST_Form{kind = .Bool, text = strings.clone("true"), span = span}, Compile_Error{}, true
        }
        return CST_Form{kind = .Bool, text = strings.clone("false"), span = span}, Compile_Error{}, true
    case .Int:
        text := macro_int_text(value.int_value)
        result := CST_Form{kind = .Number, text = strings.clone(text), span = span}
        return result, Compile_Error{}, true
    case .Float:
        text := macro_float_text(value.float_value)
        result := CST_Form{kind = .Number, text = strings.clone(text), span = span}
        return result, Compile_Error{}, true
    case .String:
        return CST_Form{kind = .String, text = macro_quote_string(value.string_value), span = span}, Compile_Error{}, true
    case .Forms:
        return CST_Form{}, Compile_Error{message = "expected single macro form value", span = span}, false
    }
    return CST_Form{}, Compile_Error{message = "unsupported macro value", span = span}, false
}

macro_value_to_owned_forms :: proc(value: Macro_Value, span: Span) -> ([]CST_Form, Compile_Error, bool) {
    #partial switch value.kind {
    case .Forms:
        out: [dynamic]CST_Form
        for form in value.forms {
            append(&out, clone_cst_form(form))
        }
        return out[:], Compile_Error{}, true
    case:
        form, err, ok := macro_value_to_owned_form(value, span)
        if !ok {
            return nil, err, false
        }
        out: [dynamic]CST_Form
        append(&out, form)
        return out[:], Compile_Error{}, true
    }
}

macro_value_to_string :: proc(value: Macro_Value, span: Span) -> (string, Compile_Error, bool) {
    switch value.kind {
    case .String:
        return strings.clone(value.string_value), Compile_Error{}, true
    case .Form:
        #partial switch value.form.kind {
        case .Symbol:
            return strings.clone(value.form.text), Compile_Error{}, true
        case .Keyword:
            if len(value.form.text) > 0 && value.form.text[0] == ':' {
                return strings.clone(value.form.text[1:]), Compile_Error{}, true
            }
            return strings.clone(value.form.text), Compile_Error{}, true
        case .String:
            return unquote_string(value.form.text), Compile_Error{}, true
        case .Regex:
            return unquote_regex_literal(value.form.text), Compile_Error{}, true
        case:
            return "", Compile_Error{message = "expected string-like macro value", span = span}, false
        }
    case .Nil:
        return strings.clone(""), Compile_Error{}, true
    case .Int:
        return strings.clone(macro_int_text(value.int_value)), Compile_Error{}, true
    case .Float:
        return strings.clone(macro_float_text(value.float_value)), Compile_Error{}, true
    case .Bool:
        if value.bool_value {
            return strings.clone("true"), Compile_Error{}, true
        }
        return strings.clone("false"), Compile_Error{}, true
    case .Forms:
        return "", Compile_Error{message = "expected string-like macro value", span = span}, false
    }
    return "", Compile_Error{message = "expected string-like macro value", span = span}, false
}

macro_lookup_binding :: proc(bindings: []Macro_Binding, name: string) -> (Macro_Value, bool) {
    for i := len(bindings) - 1; i >= 0; i -= 1 {
        if bindings[i].name == name {
            return macro_value_clone_backing(bindings[i].value), true
        }
    }
    return Macro_Value{}, false
}

is_defmacro_form :: proc(form: CST_Form) -> bool {
    return form.kind == .List && len(form.items) > 0 &&
        form.items[0].kind == .Symbol &&
        (form.items[0].text == "defmacro" || form.items[0].text == "defmacro-")
}

core_package_local_macros :: proc(anchor_path: string = ".") -> ([]User_Macro, Compile_Error, bool) {
    core_dir, err_core, ok_core := resolve_kvist_source_import_path(anchor_path, "kvist:core")
    if !ok_core {
        if err_core.message != "" {
            return nil, err_core, false
        }
        return nil, Compile_Error{message = "could not resolve core package for macro loading"}, false
    }
    defer delete(core_dir)

    files, err_files, ok_files := read_package_files(core_dir)
    if !ok_files {
        return nil, err_files, false
    }
    defer package_file_slice_delete(files)

    macros: [dynamic]User_Macro
    for file in files {
        forms, err_forms, ok_forms := read_top_forms(file.source)
        if !ok_forms {
            return nil, err_forms, false
        }
        defer delete_borrowed_cst_top_form_slice(&forms)

        for top in forms {
            if !is_defmacro_form(top.form) {
                continue
            }
            macro_decl, err_macro, ok_macro := parse_user_macro_decl(top)
            if !ok_macro {
                return nil, err_macro, false
            }
            append(&macros, macro_decl)
        }
    }
    return macros[:], Compile_Error{}, true
}
