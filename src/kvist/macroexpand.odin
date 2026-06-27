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
    names:     [dynamic]string,
    has_rest:  bool,
    rest_name: string,
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
            names = clone_string_slice(macro_decl.params.names[:]),
            has_rest = macro_decl.params.has_rest,
            rest_name = strings.clone(macro_decl.params.rest_name),
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

macro_eval_read_path :: proc(raw_path: string, span: Span) -> (path: string, err: Compile_Error, ok: bool) {
    if raw_path == "" {
        return "", Compile_Error{message = "io.read path must not be empty", span = span}, false
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
        return "", Compile_Error{message = fmt.tprintf("could not resolve compile-time io.read path: %s", raw_path), span = span}, false
    }
    return resolved, Compile_Error{}, true
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

macro_value_equal :: proc(a, b: Macro_Value) -> bool {
    if a.kind != b.kind {
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
    packages_dir, ok_packages := kvist_packages_dir(anchor_path)
    if !ok_packages {
        return nil, Compile_Error{message = "could not resolve shipped packages for core macro loading"}, false
    }
    defer delete(packages_dir)
    path, join_err := os.join_path({packages_dir, "core", "core.kvist"}, context.allocator)
    if join_err != nil {
        return nil, Compile_Error{message = "could not resolve shipped core package file"}, false
    }
    defer delete(path)
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        return nil, Compile_Error{message = fmt.tprintf("could not read shipped core package file: %s", path)}, false
    }
    defer delete(data)
    forms, err_forms, ok_forms := read_top_forms(string(data))
    if !ok_forms {
        return nil, err_forms, false
    }
    defer delete_borrowed_cst_top_form_slice(&forms)
    macros: [dynamic]User_Macro
    for top in forms {
        if !is_defmacro_form(top.form) {
            continue
        }
        macro_decl, err_macro, ok_macro := parse_user_macro_decl(top)
        if !ok_macro {
            return nil, err_macro, false
        }
        qualified := clone_user_macro(macro_decl)
        old_name := qualified.name
        qualified.name = strings.clone(fmt.tprintf("core.%s", old_name))
        delete(old_name)
        append(&macros, macro_decl)
        append(&macros, qualified)
    }
    return macros[:], Compile_Error{}, true
}

builtin_macro_kind :: proc(head: string) -> Builtin_Macro_Kind {
    switch head {
    case "when", "core/when", "core.when", "core-when":
        return .When
    case "with-allocator":
        return .With_Allocator
    case "with-temp-allocator":
        return .With_Temp_Allocator
    case "core-thread-first":
        return .Thread_First
    case "core-thread-last":
        return .Thread_Last
    case "when-let":
        return .When_Let
    case "if-let":
        return .If_Let
    case "when-ok":
        return .When_Ok
    case "if-ok":
        return .If_Ok
    }
    return .None
}

expand_when_form :: proc(form: CST_Form) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 {
        return expanded, Compile_Error{message = "when expects test and body", span = form.span}, false
    }
    expanded = CST_Form{kind = .List, span = form.span}
    append(&expanded.items, macro_symbol("if", form.span))
    append(&expanded.items, form.items[1])
    if len(form.items) == 3 {
        append(&expanded.items, form.items[2])
        return expanded, Compile_Error{}, true
    }
    body := CST_Form{kind = .List, span = form.span}
    append(&body.items, macro_symbol("do", form.span))
    for item in form.items[2:] {
        append(&body.items, item)
    }
    append(&expanded.items, body)
    return expanded, Compile_Error{}, true
}

expand_thread_step_form :: proc(current, step: CST_Form, thread_last: bool) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    #partial switch step.kind {
    case .Symbol, .Keyword:
        expanded = CST_Form{kind = .List, span = step.span}
        append(&expanded.items, step)
        append(&expanded.items, current)
        return expanded, Compile_Error{}, true
    case .List:
        if len(step.items) == 0 {
            return expanded, Compile_Error{message = "thread step cannot be an empty list", span = step.span}, false
        }
        expanded = CST_Form{kind = .List, span = step.span}
        if thread_last {
            for item in step.items {
                append(&expanded.items, item)
            }
            append(&expanded.items, current)
        } else {
            append(&expanded.items, step.items[0])
            append(&expanded.items, current)
            for item in step.items[1:] {
                append(&expanded.items, item)
            }
        }
        return expanded, Compile_Error{}, true
    case:
        return expanded, Compile_Error{message = "unsupported thread step in macroexpand", span = step.span}, false
    }
}

expand_thread_form :: proc(form: CST_Form, thread_last: bool) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) < 2 {
        return expanded, Compile_Error{message = "thread form expects an initial value", span = form.span}, false
    }
    current := form.items[1]
    for step in form.items[2:] {
        next, err_step, ok_step := expand_thread_step_form(current, step, thread_last)
        if !ok_step {
            return expanded, err_step, false
        }
        current = next
    }
    return current, Compile_Error{}, true
}

builtin_macro_form_kind :: proc(form: CST_Form) -> Builtin_Macro_Kind {
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return .None
    }
    return builtin_macro_kind(form.items[0].text)
}

macro_record_source_map :: proc(e: ^Macro_Expander, start_line, end_line: int, span: Span) {
    if e.source_map == nil || end_line < start_line {
        return
    }
    append(e.source_map, Source_Map_Entry{
        generated_start_line = start_line,
        generated_end_line   = end_line,
        source_span          = span,
    })
}

macro_emit_line :: proc(e: ^Macro_Expander, text: string, span: Span) {
    strings.write_string(&e.builder, text)
    strings.write_byte(&e.builder, '\n')
    macro_record_source_map(e, e.line, e.line, span)
    e.line += 1
}

macro_symbol :: proc(text: string, span: Span) -> CST_Form {
    return CST_Form{kind = .Symbol, text = text, span = span}
}

macro_empty_brace :: proc(span: Span) -> CST_Form {
    return CST_Form{kind = .Brace, span = span}
}

macro_error_success_condition :: proc(condition: CST_Form) -> CST_Form {
    test := CST_Form{kind = .List, span = condition.span}
    append(&test.items, macro_symbol("==", condition.span))
    append(&test.items, condition)
    append(&test.items, macro_empty_brace(condition.span))
    return test
}

parse_binding_condition_macro :: proc(form: CST_Form, name, binding_label: string) -> (bindings: CST_Form, condition: CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 || form.items[1].kind != .Vector {
        return bindings, condition, Compile_Error{message = fmt.tprintf("%s expects %s binding and body", name, binding_label), span = form.span}, false
    }
    binding := form.items[1]
    if len(binding.items) != 2 || binding.items[0].kind != .Vector {
        return bindings, condition, Compile_Error{message = fmt.tprintf("%s expects %s binding", name, binding_label), span = binding.span}, false
    }
    destructure := binding.items[0]
    if len(destructure.items) != 2 || destructure.items[0].kind != .Symbol || destructure.items[1].kind != .Symbol {
        return bindings, condition, Compile_Error{message = fmt.tprintf("%s expects %s binding", name, binding_label), span = destructure.span}, false
    }

    bindings = CST_Form{kind = .Vector, span = binding.span}
    append(&bindings.items, destructure)
    append(&bindings.items, binding.items[1])
    condition = destructure.items[1]
    return bindings, condition, {}, true
}

expand_when_let_form :: proc(form: CST_Form) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 || form.items[1].kind != .Vector {
        return expanded, Compile_Error{message = "when-let expects [[value bool] expr] binding and body", span = form.span}, false
    }
    if len(form.items[1].items) == 0 {
        return expanded, Compile_Error{message = "when-let expects [value bool] expr binding pairs", span = form.items[1].span}, false
    }
    return expand_when_guard_chain(form.items[1], 0, form.items[2:], form.span, form.items[0].span, "when-let", "[value bool]", false)
}

expand_when_guard_chain :: proc(bindings_form: CST_Form, idx: int, body: []CST_Form, span, head_span: Span, name, binding_label: string, error_guard: bool) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    if idx >= len(bindings_form.items) {
        if len(body) == 1 {
            return body[0], {}, true
        }
        do_form := CST_Form{kind = .List, span = span}
        append(&do_form.items, macro_symbol("do", head_span))
        for item in body {
            append(&do_form.items, item)
        }
        return do_form, {}, true
    }
    binding, condition, err_bind, ok_bind := guard_binding_pair(bindings_form, idx, name, binding_label)
    if !ok_bind {
        return expanded, err_bind, false
    }

    nested_body := body
    nested_form: CST_Form
    if idx+2 < len(bindings_form.items) {
        next, err_next, ok_next := expand_when_guard_chain(bindings_form, idx+2, body, span, head_span, name, binding_label, error_guard)
        if !ok_next {
            return expanded, err_next, false
        }
        nested_form = next
        nested_body = []CST_Form{nested_form}
    }

    when_form := CST_Form{kind = .List, span = span}
    append(&when_form.items, macro_symbol("when", head_span))
    if error_guard {
        append(&when_form.items, macro_error_success_condition(condition))
    } else {
        append(&when_form.items, condition)
    }
    for item in nested_body {
        append(&when_form.items, item)
    }

    expanded = CST_Form{kind = .List, span = span}
    append(&expanded.items, macro_symbol("let", head_span))
    append(&expanded.items, binding)
    append(&expanded.items, when_form)
    return expanded, {}, true
}

expand_if_let_form :: proc(form: CST_Form) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) != 4 {
        return expanded, Compile_Error{message = "if-let expects [[value bool] expr], then, and else", span = form.span}, false
    }
    if form.items[1].kind != .Vector {
        return expanded, Compile_Error{message = "if-let expects [[value bool] expr] binding", span = form.items[1].span}, false
    }
    return expand_if_guard_chain(form.items[1], 0, form.items[2], form.items[3], form.span, form.items[0].span, "if-let", "[value bool]", false)
}

expand_when_ok_form :: proc(form: CST_Form) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 || form.items[1].kind != .Vector {
        return expanded, Compile_Error{message = "when-ok expects [[value err] expr] binding and body", span = form.span}, false
    }
    if len(form.items[1].items) == 0 {
        return expanded, Compile_Error{message = "when-ok expects [value err] expr binding pairs", span = form.items[1].span}, false
    }
    return expand_when_guard_chain(form.items[1], 0, form.items[2:], form.span, form.items[0].span, "when-ok", "[value err]", true)
}

expand_if_ok_form :: proc(form: CST_Form) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) != 4 {
        return expanded, Compile_Error{message = "if-ok expects [[value err] expr], then, and else", span = form.span}, false
    }
    if form.items[1].kind != .Vector {
        return expanded, Compile_Error{message = "if-ok expects [[value err] expr] binding", span = form.items[1].span}, false
    }
    return expand_if_guard_chain(form.items[1], 0, form.items[2], form.items[3], form.span, form.items[0].span, "if-ok", "[value err]", true)
}

guard_binding_pair :: proc(bindings_form: CST_Form, idx: int, name, binding_label: string) -> (binding: CST_Form, condition: CST_Form, err: Compile_Error, ok: bool) {
    if len(bindings_form.items) == 0 || len(bindings_form.items)%2 != 0 || idx+1 >= len(bindings_form.items) {
        return binding, condition, Compile_Error{message = fmt.tprintf("%s expects %s expr binding pairs", name, binding_label), span = bindings_form.span}, false
    }
    destructure := bindings_form.items[idx]
    if destructure.kind != .Vector || len(destructure.items) != 2 || destructure.items[0].kind != .Symbol || destructure.items[1].kind != .Symbol {
        return binding, condition, Compile_Error{message = fmt.tprintf("%s expects %s expr binding pairs", name, binding_label), span = destructure.span}, false
    }

    binding = CST_Form{kind = .Vector, span = bindings_form.span}
    append(&binding.items, destructure)
    append(&binding.items, bindings_form.items[idx+1])
    condition = destructure.items[1]
    return binding, condition, {}, true
}

expand_if_guard_chain :: proc(bindings_form: CST_Form, idx: int, then_expr, else_expr: CST_Form, span, head_span: Span, name, binding_label: string, error_guard: bool) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    binding, condition, err_bind, ok_bind := guard_binding_pair(bindings_form, idx, name, binding_label)
    if !ok_bind {
        return expanded, err_bind, false
    }

    branch_then := then_expr
    if idx+2 < len(bindings_form.items) {
        nested, err_nested, ok_nested := expand_if_guard_chain(bindings_form, idx+2, then_expr, else_expr, span, head_span, name, binding_label, error_guard)
        if !ok_nested {
            return expanded, err_nested, false
        }
        branch_then = nested
    }

    if_form := CST_Form{kind = .List, span = span}
    append(&if_form.items, macro_symbol("if", head_span))
    if error_guard {
        append(&if_form.items, macro_error_success_condition(condition))
    } else {
        append(&if_form.items, condition)
    }
    append(&if_form.items, branch_then)
    append(&if_form.items, else_expr)

    expanded = CST_Form{kind = .List, span = span}
    append(&expanded.items, macro_symbol("let", head_span))
    append(&expanded.items, binding)
    append(&expanded.items, if_form)
    return expanded, {}, true
}

parse_macro_param_vector :: proc(form: CST_Form) -> (params: Macro_Param_Spec, err: Compile_Error, ok: bool) {
    if form.kind != .Vector {
        return params, Compile_Error{message = "defmacro expects a parameter vector", span = form.span}, false
    }
    i := 0
    for i < len(form.items) {
        item := form.items[i]
        if item.kind != .Symbol {
            return params, Compile_Error{message = "defmacro parameter must be a symbol", span = item.span}, false
        }
        if item.text == "&" {
            if params.has_rest || i+1 != len(form.items)-1 || form.items[i+1].kind != .Symbol {
                return params, Compile_Error{message = "defmacro rest parameters must be written as '& name' at the end", span = item.span}, false
            }
            params.has_rest = true
            params.rest_name = form.items[i+1].text
            return params, Compile_Error{}, true
        }
        append(&params.names, item.text)
        i += 1
    }
    return params, Compile_Error{}, true
}

parse_user_macro_decl :: proc(top: CST_Top_Form) -> (macro_decl: User_Macro, err: Compile_Error, ok: bool) {
    form := top.form
    if !is_defmacro_form(form) {
        return macro_decl, Compile_Error{message = "expected defmacro form", span = form.span}, false
    }
    if len(form.items) < 4 {
        return macro_decl, Compile_Error{message = "defmacro expects a name, parameter vector, and body", span = form.span}, false
    }
    if form.items[1].kind != .Symbol {
        return macro_decl, Compile_Error{message = "defmacro expects a symbol name", span = form.items[1].span}, false
    }

    params_index := 2
    doc_lines := top.doc_lines
    doc_lines_owned := false
    if len(form.items) > 4 && form.items[2].kind == .String {
        doc_text := unquote_string(form.items[2].text)
        extra_doc_lines := doc_lines_from_string(doc_text)
        doc_lines = append_doc_lines(doc_lines[:], extra_doc_lines[:])
        doc_lines_owned = true
        delete(doc_text)
        delete(extra_doc_lines)
        params_index = 3
    }
    defer if doc_lines_owned {
        delete(doc_lines)
    }
    if params_index >= len(form.items) || form.items[params_index].kind != .Vector {
        return macro_decl, Compile_Error{message = "defmacro expects a parameter vector", span = form.span}, false
    }
    params, err_params, ok_params := parse_macro_param_vector(form.items[params_index])
    if !ok_params {
        return macro_decl, err_params, false
    }
    defer delete(params.names)
    if params_index+1 >= len(form.items) {
        return macro_decl, Compile_Error{message = "defmacro body is empty", span = form.span}, false
    }
    body: [dynamic]CST_Form
    defer delete(body)
    for item in form.items[params_index+1:] {
        append(&body, item)
    }
    return User_Macro{
        name      = strings.clone(form.items[1].text),
        doc_lines = clone_string_slice(doc_lines[:]),
        params    = Macro_Param_Spec{
            names = clone_string_slice(params.names[:]),
            has_rest = params.has_rest,
            rest_name = strings.clone(params.rest_name),
        },
        body      = clone_cst_form_slice(body[:]),
        span      = form.span,
    }, Compile_Error{}, true
}

find_user_macro :: proc(macros: []User_Macro, name: string) -> (User_Macro, bool) {
    for i := len(macros) - 1; i >= 0; i -= 1 {
        if macros[i].name == name {
            return macros[i], true
        }
    }
    return User_Macro{}, false
}

macro_error_with_expansion_context :: proc(macro_decl: User_Macro, err: Compile_Error) -> Compile_Error {
    return Compile_Error{
        message = fmt.tprintf("while expanding macro %s: %s", macro_decl.name, err.message),
        span    = err.span,
    }
}

invoke_user_macro_value :: proc(macro_decl: User_Macro, call: CST_Form, macros: []User_Macro) -> (Macro_Value, Compile_Error, bool) {
    bindings, err_bindings, ok_bindings := macro_collect_call_bindings(macro_decl, call)
    if !ok_bindings {
        return Macro_Value{}, err_bindings, false
    }
    value, err, ok := macro_eval_sequence(macro_decl.body[:], macros, bindings[:])
    if !ok {
        macro_binding_slice_delete_backing(&bindings)
        return Macro_Value{}, macro_error_with_expansion_context(macro_decl, err), false
    }
    result := macro_value_clone_backing(value)
    macro_value_delete_backing(&value)
    macro_binding_slice_delete_backing(&bindings)
    return result, Compile_Error{}, true
}

macro_collect_call_bindings :: proc(macro_decl: User_Macro, call: CST_Form) -> ([]Macro_Binding, Compile_Error, bool) {
    if call.kind != .List || len(call.items) == 0 {
        return nil, Compile_Error{message = "macro call must be a list", span = call.span}, false
    }
    args := call.items[1:]
    if !macro_decl.params.has_rest && len(args) != len(macro_decl.params.names) {
        return nil, Compile_Error{message = fmt.tprintf("%s expects %d arguments", macro_decl.name, len(macro_decl.params.names)), span = call.span}, false
    }
    if macro_decl.params.has_rest && len(args) < len(macro_decl.params.names) {
        return nil, Compile_Error{message = fmt.tprintf("%s expects at least %d arguments", macro_decl.name, len(macro_decl.params.names)), span = call.span}, false
    }

    bindings: [dynamic]Macro_Binding
    for name, idx in macro_decl.params.names {
        append(&bindings, Macro_Binding{name = name, value = macro_form_value(args[idx])})
    }
    if macro_decl.params.has_rest {
        rest_args := args[len(macro_decl.params.names):]
        append(&bindings, Macro_Binding{name = macro_decl.params.rest_name, value = macro_forms_value(rest_args)})
    }
    return bindings[:], Compile_Error{}, true
}

macro_collect_eval_call_bindings :: proc(macro_decl: User_Macro, call: CST_Form, macros: []User_Macro, bindings: []Macro_Binding) -> ([]Macro_Binding, Compile_Error, bool) {
    if call.kind != .List || len(call.items) == 0 {
        return nil, Compile_Error{message = "macro call must be a list", span = call.span}, false
    }
    args := call.items[1:]
    if !macro_decl.params.has_rest && len(args) != len(macro_decl.params.names) {
        return nil, Compile_Error{message = fmt.tprintf("%s expects %d arguments", macro_decl.name, len(macro_decl.params.names)), span = call.span}, false
    }
    if macro_decl.params.has_rest && len(args) < len(macro_decl.params.names) {
        return nil, Compile_Error{message = fmt.tprintf("%s expects at least %d arguments", macro_decl.name, len(macro_decl.params.names)), span = call.span}, false
    }

    out: [dynamic]Macro_Binding
    for name, idx in macro_decl.params.names {
        value, err_value, ok_value := macro_eval_expr(args[idx], macros, bindings)
        if !ok_value {
            return nil, err_value, false
        }
        append(&out, Macro_Binding{name = name, value = value})
    }
    if macro_decl.params.has_rest {
        rest_out: [dynamic]CST_Form
        for arg in args[len(macro_decl.params.names):] {
            value, err_value, ok_value := macro_eval_expr(arg, macros, bindings)
            if !ok_value {
                return nil, err_value, false
            }
            forms, err_forms, ok_forms := macro_value_to_owned_forms(value, arg.span)
            if !ok_forms {
                macro_value_delete_backing(&value)
                return nil, err_forms, false
            }
            for item in forms {
                append(&rest_out, item)
            }
            delete(forms)
            macro_value_delete_backing(&value)
        }
        append(&out, Macro_Binding{name = macro_decl.params.rest_name, value = macro_owned_forms_value(rest_out[:])})
        delete(rest_out)
    }
    return out[:], Compile_Error{}, true
}

macro_eval_sequence :: proc(forms: []CST_Form, macros: []User_Macro, bindings: []Macro_Binding) -> (Macro_Value, Compile_Error, bool) {
    if len(forms) == 0 {
        return macro_nil_value(), Compile_Error{}, true
    }
    value := macro_nil_value()
    for form in forms {
        next_value, err_next, ok_next := macro_eval_expr(form, macros, bindings)
        if !ok_next {
            macro_value_delete_backing(&value)
            return Macro_Value{}, err_next, false
        }
        macro_value_delete_backing(&value)
        value = next_value
    }
    return value, Compile_Error{}, true
}

macro_eval_list_builder :: proc(kind: CST_Form_Kind, form: CST_Form, macros: []User_Macro, bindings: []Macro_Binding) -> (Macro_Value, Compile_Error, bool) {
    out := CST_Form{kind = kind, span = form.span}
    for arg in form.items[1:] {
        value, err_value, ok_value := macro_eval_expr(arg, macros, bindings)
        if !ok_value {
            return Macro_Value{}, err_value, false
        }
        forms, err_forms, ok_forms := macro_value_to_owned_forms(value, arg.span)
        if !ok_forms {
            macro_value_delete_backing(&value)
            return Macro_Value{}, err_forms, false
        }
        for item in forms {
            append(&out.items, item)
        }
        delete(forms)
        macro_value_delete_backing(&value)
    }
    return macro_owned_form_value(out), Compile_Error{}, true
}

macro_list_from_value :: proc(value: Macro_Value, span: Span) -> ([]CST_Form, Compile_Error, bool) {
    #partial switch value.kind {
    case .Forms:
        return value.forms[:], Compile_Error{}, true
    case .Form:
        if value.form.kind == .List || value.form.kind == .Vector || value.form.kind == .Brace {
            return value.form.items[:], Compile_Error{}, true
        }
        return nil, Compile_Error{message = "expected macro sequence value", span = span}, false
    case .Nil:
        return nil, Compile_Error{}, true
    case:
        return nil, Compile_Error{message = "expected macro sequence value", span = span}, false
    }
}

macro_slice_forms :: proc(forms: []CST_Form, start: int, end := -1) -> []CST_Form {
    from := start
    to := end
    if from < 0 {
        from = 0
    }
    if from > len(forms) {
        from = len(forms)
    }
    if to < 0 || to > len(forms) {
        to = len(forms)
    }
    if to < from {
        to = from
    }
    out: [dynamic]CST_Form
    for form in forms[from:to] {
        append(&out, form)
    }
    return out[:]
}

macro_slice_string :: proc(text: string, start: int, end := -1) -> string {
    from := start
    to := end
    if from < 0 {
        from = 0
    }
    if from > len(text) {
        from = len(text)
    }
    if to < 0 || to > len(text) {
        to = len(text)
    }
    if to < from {
        to = from
    }
    return strings.clone(text[from:to])
}

macro_name_value :: proc(value: Macro_Value, span: Span) -> (Macro_Value, Compile_Error, bool) {
    single, err_single, ok_single := macro_value_to_form(value, span)
    if !ok_single {
        return Macro_Value{}, err_single, false
    }
    #partial switch single.kind {
    case .Symbol:
        if len(single.text) > 1 && single.text[0] == '.' {
            return macro_owned_string_value(strings.clone(single.text[1:])), Compile_Error{}, true
        }
        if len(single.text) > 1 && single.text[len(single.text)-1] == ':' {
            return macro_owned_string_value(strings.clone(single.text[:len(single.text)-1])), Compile_Error{}, true
        }
        return macro_owned_string_value(strings.clone(single.text)), Compile_Error{}, true
    case .Keyword:
        if len(single.text) > 0 && single.text[0] == ':' {
            return macro_owned_string_value(strings.clone(single.text[1:])), Compile_Error{}, true
        }
        return macro_owned_string_value(strings.clone(single.text)), Compile_Error{}, true
    case:
        return Macro_Value{}, Compile_Error{message = "name expects one symbol or keyword", span = span}, false
    }
}

macro_apply_unary_function :: proc(fn_form: CST_Form, arg: Macro_Value, macros: []User_Macro, bindings: []Macro_Binding) -> (Macro_Value, Compile_Error, bool) {
    if fn_form.kind != .Symbol {
        return Macro_Value{}, Compile_Error{message = "macro sequence helper expects a unary function symbol", span = fn_form.span}, false
    }
    switch fn_form.text {
    case "form?":
        return macro_bool_value(arg.kind == .Form), Compile_Error{}, true
    case "vector?":
        return macro_bool_value(arg.kind == .Form && arg.form.kind == .Vector), Compile_Error{}, true
    case "brace?":
        return macro_bool_value(arg.kind == .Form && arg.form.kind == .Brace), Compile_Error{}, true
    case "list?":
        return macro_bool_value(arg.kind == .Form && arg.form.kind == .List), Compile_Error{}, true
    case "symbol?":
        return macro_bool_value(arg.kind == .Form && arg.form.kind == .Symbol), Compile_Error{}, true
    case "keyword?":
        return macro_bool_value(arg.kind == .Form && arg.form.kind == .Keyword), Compile_Error{}, true
    case "field-selector?":
        return macro_bool_value(arg.kind == .Form &&
                                arg.form.kind == .Symbol &&
                                len(arg.form.text) > 1 &&
                                arg.form.text[0] == '.'), Compile_Error{}, true
    case "string?":
        return macro_bool_value(arg.kind == .String || (arg.kind == .Form && arg.form.kind == .String)), Compile_Error{}, true
    case "number?":
        return macro_bool_value(arg.kind == .Int || arg.kind == .Float || (arg.kind == .Form && arg.form.kind == .Number)), Compile_Error{}, true
    case "int?":
        if arg.kind == .Int {
            return macro_bool_value(true), Compile_Error{}, true
        }
        if arg.kind != .Form || arg.form.kind != .Number {
            return macro_bool_value(false), Compile_Error{}, true
        }
        _, ok_parsed := strconv.parse_int(arg.form.text)
        return macro_bool_value(ok_parsed), Compile_Error{}, true
    case "float?":
        if arg.kind == .Float {
            return macro_bool_value(true), Compile_Error{}, true
        }
        if arg.kind != .Form || arg.form.kind != .Number {
            return macro_bool_value(false), Compile_Error{}, true
        }
        _, ok_int := strconv.parse_int(arg.form.text)
        if ok_int {
            return macro_bool_value(false), Compile_Error{}, true
        }
        _, ok_float := strconv.parse_f64(arg.form.text)
        return macro_bool_value(ok_float), Compile_Error{}, true
    case "bool?":
        return macro_bool_value(arg.kind == .Bool || (arg.kind == .Form && arg.form.kind == .Bool)), Compile_Error{}, true
    case "nil?":
        return macro_bool_value(arg.kind == .Nil || (arg.kind == .Form && arg.form.kind == .Nil)), Compile_Error{}, true
    case "source":
        single, err_single, ok_single := macro_value_to_form(arg, fn_form.span)
        if !ok_single {
            return Macro_Value{}, err_single, false
        }
        return macro_owned_string_value(macro_form_text(single)), Compile_Error{}, true
    case "name":
        return macro_name_value(arg, fn_form.span)
    case "text":
        text, err_text, ok_text := macro_value_to_string(arg, fn_form.span)
        if !ok_text {
            return Macro_Value{}, err_text, false
        }
        return macro_owned_string_value(text), Compile_Error{}, true
    case "parse-int", "str.parse-int":
        text, err_text, ok_text := macro_value_to_string(arg, fn_form.span)
        if !ok_text {
            return Macro_Value{}, err_text, false
        }
        defer delete(text)
        parsed, ok_parsed := strconv.parse_int(text)
        if !ok_parsed {
            return macro_nil_value(), Compile_Error{}, true
        }
        return macro_int_value(parsed), Compile_Error{}, true
    case "digit?", "str.digit?":
        text, err_text, ok_text := macro_value_to_string(arg, fn_form.span)
        if !ok_text {
            return Macro_Value{}, err_text, false
        }
        defer delete(text)
        return macro_bool_value(len(text) == 1 && text[0] >= '0' && text[0] <= '9'), Compile_Error{}, true
    case:
        if user_macro, ok_user := find_user_macro(macros, fn_form.text); ok_user {
            if user_macro.params.has_rest || len(user_macro.params.names) != 1 {
                return Macro_Value{}, Compile_Error{message = fmt.tprintf("%s must be unary for macro sequence helpers", user_macro.name), span = fn_form.span}, false
            }
            local: [dynamic]Macro_Binding
            defer delete(local)
            for binding in bindings {
                append(&local, binding)
            }
            append(&local, Macro_Binding{name = user_macro.params.names[0], value = macro_value_clone_backing(arg)})
            value, err_value, ok_value := macro_eval_sequence(user_macro.body[:], macros, local[:])
            macro_value_delete_backing(&local[len(local)-1].value)
            if !ok_value {
                return Macro_Value{}, macro_error_with_expansion_context(user_macro, err_value), false
            }
            result := macro_value_clone_backing(value)
            macro_value_delete_backing(&value)
            return result, Compile_Error{}, true
        }
    }
    return Macro_Value{}, Compile_Error{message = fmt.tprintf("unknown macro sequence helper function: %s", fn_form.text), span = fn_form.span}, false
}

macro_apply_user_function :: proc(fn_form: CST_Form, args: []Macro_Value, macros: []User_Macro, bindings: []Macro_Binding) -> (Macro_Value, Compile_Error, bool) {
    if fn_form.kind != .Symbol {
        fn_text := macro_form_text(fn_form)
        defer delete(fn_text)
        return Macro_Value{}, Compile_Error{message = fmt.tprintf("unsupported macro function: %s", fn_text), span = fn_form.span}, false
    }
    user_macro, ok_user := find_user_macro(macros, fn_form.text)
    if !ok_user {
        return Macro_Value{}, Compile_Error{message = fmt.tprintf("unsupported macro function: %s", fn_form.text), span = fn_form.span}, false
    }
    if user_macro.params.has_rest || len(user_macro.params.names) != len(args) {
        return Macro_Value{}, Compile_Error{message = fmt.tprintf("%s must take %d arguments for this macro helper", user_macro.name, len(args)), span = fn_form.span}, false
    }

    local: [dynamic]Macro_Binding
    defer delete(local)
    for binding in bindings {
        append(&local, binding)
    }
    local_owned_start := len(local)
    for arg, idx in args {
        append(&local, Macro_Binding{name = user_macro.params.names[idx], value = macro_value_clone_backing(arg)})
    }

    value, err_value, ok_value := macro_eval_sequence(user_macro.body[:], macros, local[:])
    for idx in local_owned_start ..< len(local) {
        macro_value_delete_backing(&local[idx].value)
    }
    if !ok_value {
        return Macro_Value{}, macro_error_with_expansion_context(user_macro, err_value), false
    }
    result := macro_value_clone_backing(value)
    macro_value_delete_backing(&value)
    return result, Compile_Error{}, true
}

macro_subst_form :: proc(form: CST_Form, names: []string, values: []CST_Form) -> CST_Form {
    if form.kind == .Symbol {
        for name, idx in names {
            if form.text == name {
                return clone_cst_form(values[idx])
            }
        }
        return clone_cst_form(form)
    }

    #partial switch form.kind {
    case .List, .Vector, .Brace:
        out := CST_Form{kind = form.kind, span = form.span}
        if form.text != "" {
            out.text = strings.clone(form.text)
        }
        for item in form.items {
            append(&out.items, macro_subst_form(item, names, values))
        }
        return out
    case:
        return clone_cst_form(form)
    }
}

macro_is_symbol_call :: proc(form: CST_Form, name: string) -> bool {
    return form.kind == .List && len(form.items) > 0 && is_symbol(form.items[0], name)
}

macro_quasiquote_form :: proc(form: CST_Form, macros: []User_Macro, bindings: []Macro_Binding, depth: int = 0) -> (CST_Form, Compile_Error, bool) {
    if macro_is_symbol_call(form, "unquote") {
        if len(form.items) != 2 {
            return CST_Form{}, Compile_Error{message = "unquote expects one form", span = form.span}, false
        }
        if depth == 0 {
            value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
            if !ok_value {
                return CST_Form{}, err_value, false
            }
            result, err_form, ok_form := macro_value_to_owned_form(value, form.items[1].span)
            macro_value_delete_backing(&value)
            return result, err_form, ok_form
        }
        inner, err_inner, ok_inner := macro_quasiquote_form(form.items[1], macros, bindings, depth-1)
        if !ok_inner {
            return CST_Form{}, err_inner, false
        }
        out := CST_Form{kind = .List, span = form.span}
        append(&out.items, clone_cst_form(form.items[0]))
        append(&out.items, inner)
        return out, Compile_Error{}, true
    }

    if macro_is_symbol_call(form, "splice") {
        if len(form.items) != 2 {
            return CST_Form{}, Compile_Error{message = "splice expects one form", span = form.span}, false
        }
        if depth == 0 {
            return CST_Form{}, Compile_Error{message = "splice is only valid inside quasiquoted list, vector, or brace items", span = form.span}, false
        }
        inner, err_inner, ok_inner := macro_quasiquote_form(form.items[1], macros, bindings, depth-1)
        if !ok_inner {
            return CST_Form{}, err_inner, false
        }
        out := CST_Form{kind = .List, span = form.span}
        append(&out.items, clone_cst_form(form.items[0]))
        append(&out.items, inner)
        return out, Compile_Error{}, true
    }

    #partial switch form.kind {
    case .List:
        if macro_is_symbol_call(form, "quasiquote") {
            if len(form.items) != 2 {
                return CST_Form{}, Compile_Error{message = "quasiquote expects one form", span = form.span}, false
            }
            inner, err_inner, ok_inner := macro_quasiquote_form(form.items[1], macros, bindings, depth+1)
            if !ok_inner {
                return CST_Form{}, err_inner, false
            }
            out := CST_Form{kind = .List, span = form.span}
            append(&out.items, clone_cst_form(form.items[0]))
            append(&out.items, inner)
            return out, Compile_Error{}, true
        }

        out := CST_Form{kind = .List, span = form.span}
        for item in form.items {
            if macro_is_symbol_call(item, "splice") && depth == 0 {
                if len(item.items) != 2 {
                    return CST_Form{}, Compile_Error{message = "splice expects one form", span = item.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(item.items[1], macros, bindings)
                if !ok_value {
                    return CST_Form{}, err_value, false
                }
                forms, err_forms, ok_forms := macro_value_to_owned_forms(value, item.items[1].span)
                if !ok_forms {
                    macro_value_delete_backing(&value)
                    return CST_Form{}, err_forms, false
                }
                for expanded in forms {
                    append(&out.items, expanded)
                }
                delete(forms)
                macro_value_delete_backing(&value)
                continue
            }
            child, err_child, ok_child := macro_quasiquote_form(item, macros, bindings, depth)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&out.items, child)
        }
        return out, Compile_Error{}, true
    case .Vector:
        out := CST_Form{kind = .Vector, span = form.span}
        for item in form.items {
            if macro_is_symbol_call(item, "splice") && depth == 0 {
                if len(item.items) != 2 {
                    return CST_Form{}, Compile_Error{message = "splice expects one form", span = item.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(item.items[1], macros, bindings)
                if !ok_value {
                    return CST_Form{}, err_value, false
                }
                forms, err_forms, ok_forms := macro_value_to_owned_forms(value, item.items[1].span)
                if !ok_forms {
                    macro_value_delete_backing(&value)
                    return CST_Form{}, err_forms, false
                }
                for expanded in forms {
                    append(&out.items, expanded)
                }
                delete(forms)
                macro_value_delete_backing(&value)
                continue
            }
            child, err_child, ok_child := macro_quasiquote_form(item, macros, bindings, depth)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&out.items, child)
        }
        return out, Compile_Error{}, true
    case .Brace:
        out := CST_Form{kind = .Brace, span = form.span}
        for item in form.items {
            if macro_is_symbol_call(item, "splice") && depth == 0 {
                if len(item.items) != 2 {
                    return CST_Form{}, Compile_Error{message = "splice expects one form", span = item.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(item.items[1], macros, bindings)
                if !ok_value {
                    return CST_Form{}, err_value, false
                }
                forms, err_forms, ok_forms := macro_value_to_owned_forms(value, item.items[1].span)
                if !ok_forms {
                    macro_value_delete_backing(&value)
                    return CST_Form{}, err_forms, false
                }
                for expanded in forms {
                    append(&out.items, expanded)
                }
                delete(forms)
                macro_value_delete_backing(&value)
                continue
            }
            child, err_child, ok_child := macro_quasiquote_form(item, macros, bindings, depth)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&out.items, child)
        }
        return out, Compile_Error{}, true
    case .Set:
        out := CST_Form{kind = .Set, span = form.span}
        for item in form.items {
            if macro_is_symbol_call(item, "splice") && depth == 0 {
                if len(item.items) != 2 {
                    return CST_Form{}, Compile_Error{message = "splice expects one form", span = item.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(item.items[1], macros, bindings)
                if !ok_value {
                    return CST_Form{}, err_value, false
                }
                forms, err_forms, ok_forms := macro_value_to_owned_forms(value, item.items[1].span)
                if !ok_forms {
                    macro_value_delete_backing(&value)
                    return CST_Form{}, err_forms, false
                }
                for expanded in forms {
                    append(&out.items, expanded)
                }
                delete(forms)
                macro_value_delete_backing(&value)
                continue
            }
            child, err_child, ok_child := macro_quasiquote_form(item, macros, bindings, depth)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&out.items, child)
        }
        return out, Compile_Error{}, true
    case:
        return clone_cst_form(form), Compile_Error{}, true
    }
}

macro_eval_contains_expr :: proc(form: CST_Form, macros: []User_Macro, bindings: []Macro_Binding) -> (Macro_Value, Compile_Error, bool) {
    if len(form.items) != 3 {
        return Macro_Value{}, Compile_Error{message = "contains? expects collection and value", span = form.span}, false
    }
    collection, err_collection, ok_collection := macro_eval_expr(form.items[1], macros, bindings)
    if !ok_collection {
        return Macro_Value{}, err_collection, false
    }
    needle, err_needle, ok_needle := macro_eval_expr(form.items[2], macros, bindings)
    if !ok_needle {
        macro_value_delete_backing(&collection)
        return Macro_Value{}, err_needle, false
    }
    defer macro_value_delete_backing(&collection)
    defer macro_value_delete_backing(&needle)
    if collection.kind == .String {
        if needle.kind != .String {
            return Macro_Value{}, Compile_Error{message = "contains? on strings expects a string needle", span = form.items[2].span}, false
        }
        return macro_bool_value(strings.contains(collection.string_value, needle.string_value)), Compile_Error{}, true
    }
    forms, err_forms, ok_forms := macro_list_from_value(collection, form.items[1].span)
    if !ok_forms {
        return Macro_Value{}, err_forms, false
    }
    for candidate_form in forms {
        candidate, _, ok_candidate := macro_eval_expr(candidate_form, macros, bindings)
        if !ok_candidate {
            candidate = macro_form_value(candidate_form)
        }
        if macro_value_equal(candidate, needle) {
            macro_value_delete_backing(&candidate)
            return macro_bool_value(true), Compile_Error{}, true
        }
        macro_value_delete_backing(&candidate)
    }
    return macro_bool_value(false), Compile_Error{}, true
}

macro_eval_string_contains_expr :: proc(form: CST_Form, macros: []User_Macro, bindings: []Macro_Binding) -> (Macro_Value, Compile_Error, bool) {
    if len(form.items) != 3 {
        return Macro_Value{}, Compile_Error{message = "str.contains? expects string and needle", span = form.span}, false
    }
    haystack, err_haystack, ok_haystack := macro_eval_expr(form.items[1], macros, bindings)
    if !ok_haystack {
        return Macro_Value{}, err_haystack, false
    }
    needle, err_needle, ok_needle := macro_eval_expr(form.items[2], macros, bindings)
    if !ok_needle {
        macro_value_delete_backing(&haystack)
        return Macro_Value{}, err_needle, false
    }
    defer macro_value_delete_backing(&haystack)
    defer macro_value_delete_backing(&needle)
    if haystack.kind != .String || needle.kind != .String {
        return Macro_Value{}, Compile_Error{message = "str.contains? expects string arguments", span = form.span}, false
    }
    return macro_bool_value(strings.contains(haystack.string_value, needle.string_value)), Compile_Error{}, true
}

macro_eval_string_affix_expr :: proc(form: CST_Form, macros: []User_Macro, bindings: []Macro_Binding, starts: bool) -> (Macro_Value, Compile_Error, bool) {
    if len(form.items) != 3 {
        return Macro_Value{}, Compile_Error{message = "string affix helper expects string and affix", span = form.span}, false
    }
    text, err_text, ok_text := macro_eval_expr(form.items[1], macros, bindings)
    if !ok_text {
        return Macro_Value{}, err_text, false
    }
    affix, err_affix, ok_affix := macro_eval_expr(form.items[2], macros, bindings)
    if !ok_affix {
        macro_value_delete_backing(&text)
        return Macro_Value{}, err_affix, false
    }
    defer macro_value_delete_backing(&text)
    defer macro_value_delete_backing(&affix)
    if text.kind != .String || affix.kind != .String {
        return Macro_Value{}, Compile_Error{message = "string affix helper expects string arguments", span = form.span}, false
    }
    if starts {
        return macro_bool_value(strings.has_prefix(text.string_value, affix.string_value)), Compile_Error{}, true
    }
    return macro_bool_value(strings.has_suffix(text.string_value, affix.string_value)), Compile_Error{}, true
}

macro_eval_parse_int_expr :: proc(form: CST_Form, macros: []User_Macro, bindings: []Macro_Binding) -> (Macro_Value, Compile_Error, bool) {
    if len(form.items) != 2 {
        return Macro_Value{}, Compile_Error{message = "parse-int expects one string", span = form.span}, false
    }
    value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
    if !ok_value {
        return Macro_Value{}, err_value, false
    }
    defer macro_value_delete_backing(&value)
    text, err_text, ok_text := macro_value_to_string(value, form.items[1].span)
    if !ok_text {
        return Macro_Value{}, err_text, false
    }
    defer delete(text)
    parsed, ok_parsed := strconv.parse_int(text)
    if !ok_parsed {
        return macro_nil_value(), Compile_Error{}, true
    }
    return macro_int_value(parsed), Compile_Error{}, true
}

macro_eval_digit_expr :: proc(form: CST_Form, macros: []User_Macro, bindings: []Macro_Binding) -> (Macro_Value, Compile_Error, bool) {
    if len(form.items) != 2 {
        return Macro_Value{}, Compile_Error{message = "digit? expects one string", span = form.span}, false
    }
    value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
    if !ok_value {
        return Macro_Value{}, err_value, false
    }
    defer macro_value_delete_backing(&value)
    text, err_text, ok_text := macro_value_to_string(value, form.items[1].span)
    if !ok_text {
        return Macro_Value{}, err_text, false
    }
    defer delete(text)
    return macro_bool_value(len(text) == 1 && text[0] >= '0' && text[0] <= '9'), Compile_Error{}, true
}

macro_eval_some_every_expr :: proc(form: CST_Form, macros: []User_Macro, bindings: []Macro_Binding, every: bool) -> (Macro_Value, Compile_Error, bool) {
    if len(form.items) != 3 {
        return Macro_Value{}, Compile_Error{message = "macro sequence predicate helper expects predicate and sequence", span = form.span}, false
    }
    seq_value, err_seq, ok_seq := macro_eval_expr(form.items[2], macros, bindings)
    if !ok_seq {
        return Macro_Value{}, err_seq, false
    }
    defer macro_value_delete_backing(&seq_value)
    forms, err_forms, ok_forms := macro_list_from_value(seq_value, form.items[2].span)
    if !ok_forms {
        return Macro_Value{}, err_forms, false
    }
    for item in forms {
        item_value := macro_form_value(item)
        result, err_result, ok_result := macro_apply_unary_function(form.items[1], item_value, macros, bindings)
        if !ok_result {
            return Macro_Value{}, err_result, false
        }
        truthy := macro_truthy(result)
        macro_value_delete_backing(&result)
        if !every && truthy {
            return macro_bool_value(true), Compile_Error{}, true
        }
        if every && !truthy {
            return macro_bool_value(false), Compile_Error{}, true
        }
    }
    return macro_bool_value(every), Compile_Error{}, true
}

macro_eval_map_expr :: proc(form: CST_Form, macros: []User_Macro, bindings: []Macro_Binding) -> (Macro_Value, Compile_Error, bool) {
    if len(form.items) != 3 {
        return Macro_Value{}, Compile_Error{message = "map expects function and sequence", span = form.span}, false
    }
    seq_value, err_seq, ok_seq := macro_eval_expr(form.items[2], macros, bindings)
    if !ok_seq {
        return Macro_Value{}, err_seq, false
    }
    defer macro_value_delete_backing(&seq_value)
    forms, err_forms, ok_forms := macro_list_from_value(seq_value, form.items[2].span)
    if !ok_forms {
        return Macro_Value{}, err_forms, false
    }
    out := CST_Form{kind = .Vector, span = form.span}
    for item in forms {
        item_value := macro_form_value(item)
        mapped, err_mapped, ok_mapped := macro_apply_unary_function(form.items[1], item_value, macros, bindings)
        if !ok_mapped {
            delete_cst_form(&out)
            return Macro_Value{}, err_mapped, false
        }
        mapped_form, err_form, ok_form := macro_value_to_owned_form(mapped, item.span)
        macro_value_delete_backing(&mapped)
        if !ok_form {
            delete_cst_form(&out)
            return Macro_Value{}, err_form, false
        }
        append(&out.items, mapped_form)
    }
    return macro_owned_form_value(out), Compile_Error{}, true
}

macro_eval_filter_expr :: proc(form: CST_Form, macros: []User_Macro, bindings: []Macro_Binding) -> (Macro_Value, Compile_Error, bool) {
    if len(form.items) != 3 {
        return Macro_Value{}, Compile_Error{message = "filter expects predicate and sequence", span = form.span}, false
    }
    seq_value, err_seq, ok_seq := macro_eval_expr(form.items[2], macros, bindings)
    if !ok_seq {
        return Macro_Value{}, err_seq, false
    }
    defer macro_value_delete_backing(&seq_value)
    forms, err_forms, ok_forms := macro_list_from_value(seq_value, form.items[2].span)
    if !ok_forms {
        return Macro_Value{}, err_forms, false
    }
    out := CST_Form{kind = .Vector, span = form.span}
    for item in forms {
        item_value := macro_form_value(item)
        keep, err_keep, ok_keep := macro_apply_unary_function(form.items[1], item_value, macros, bindings)
        if !ok_keep {
            delete_cst_form(&out)
            return Macro_Value{}, err_keep, false
        }
        truthy := macro_truthy(keep)
        macro_value_delete_backing(&keep)
        if truthy {
            append(&out.items, clone_cst_form(item))
        }
    }
    return macro_owned_form_value(out), Compile_Error{}, true
}

macro_eval_reduce_expr :: proc(form: CST_Form, macros: []User_Macro, bindings: []Macro_Binding) -> (Macro_Value, Compile_Error, bool) {
    if len(form.items) != 4 {
        return Macro_Value{}, Compile_Error{message = "reduce expects reducer, initial value, and sequence", span = form.span}, false
    }
    acc, err_acc, ok_acc := macro_eval_expr(form.items[2], macros, bindings)
    if !ok_acc {
        return Macro_Value{}, err_acc, false
    }
    seq_value, err_seq, ok_seq := macro_eval_expr(form.items[3], macros, bindings)
    if !ok_seq {
        macro_value_delete_backing(&acc)
        return Macro_Value{}, err_seq, false
    }
    defer macro_value_delete_backing(&seq_value)
    forms, err_forms, ok_forms := macro_list_from_value(seq_value, form.items[3].span)
    if !ok_forms {
        macro_value_delete_backing(&acc)
        return Macro_Value{}, err_forms, false
    }
    for item in forms {
        item_value := macro_form_value(item)
        args := [?]Macro_Value{acc, item_value}
        next_acc, err_next, ok_next := macro_apply_user_function(form.items[1], args[:], macros, bindings)
        macro_value_delete_backing(&acc)
        if !ok_next {
            return Macro_Value{}, err_next, false
        }
        acc = next_acc
    }
    return acc, Compile_Error{}, true
}

macro_eval_expr :: proc(form: CST_Form, macros: []User_Macro, bindings: []Macro_Binding) -> (Macro_Value, Compile_Error, bool) {
    #partial switch form.kind {
    case .Nil:
        return macro_nil_value(), Compile_Error{}, true
    case .Bool:
        return macro_bool_value(form.text == "true"), Compile_Error{}, true
    case .Number:
        value: int
        parsed, ok_parsed := strconv.parse_int(form.text)
        if ok_parsed {
            value = parsed
            return macro_int_value(value), Compile_Error{}, true
        }
        float_value, ok_float := strconv.parse_f64(form.text)
        if !ok_float {
            return Macro_Value{}, Compile_Error{message = "macro evaluator could not parse numeric literal", span = form.span}, false
        }
        return macro_float_value(float_value), Compile_Error{}, true
    case .String:
        return macro_owned_string_value(unquote_string(form.text)), Compile_Error{}, true
    case .Keyword:
        return macro_form_value(form), Compile_Error{}, true
    case .Symbol:
        if value, ok_lookup := macro_lookup_binding(bindings, form.text); ok_lookup {
            return value, Compile_Error{}, true
        }
        if form.text == "nil" {
            return macro_nil_value(), Compile_Error{}, true
        }
        if form.text == "true" {
            return macro_bool_value(true), Compile_Error{}, true
        }
        if form.text == "false" {
            return macro_bool_value(false), Compile_Error{}, true
        }
        return Macro_Value{}, Compile_Error{message = fmt.tprintf("unknown macro symbol: %s", form.text), span = form.span}, false
    case .Vector:
        return macro_form_value(form), Compile_Error{}, true
    case .Brace:
        return macro_form_value(form), Compile_Error{}, true
    case .Set:
        return macro_form_value(form), Compile_Error{}, true
    case .List:
        if len(form.items) == 0 {
            return macro_form_value(form), Compile_Error{}, true
        }
        head := form.items[0]
        if head.kind == .Symbol {
            switch head.text {
            case "quote":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "quote expects one form", span = form.span}, false
                }
                return macro_form_value(form.items[1]), Compile_Error{}, true
            case "quasiquote":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "quasiquote expects one form", span = form.span}, false
                }
                quoted, err_quoted, ok_quoted := macro_quasiquote_form(form.items[1], macros, bindings)
                if !ok_quoted {
                    return Macro_Value{}, err_quoted, false
                }
                return macro_owned_form_value(quoted), Compile_Error{}, true
            case "do":
                return macro_eval_sequence(form.items[1:], macros, bindings)
            case "not", "core.not":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "not expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                truthy := macro_truthy(value)
                macro_value_delete_backing(&value)
                return macro_bool_value(!truthy), Compile_Error{}, true
            case "and":
                for arg in form.items[1:] {
                    value, err_value, ok_value := macro_eval_expr(arg, macros, bindings)
                    if !ok_value {
                        return Macro_Value{}, err_value, false
                    }
                    truthy := macro_truthy(value)
                    macro_value_delete_backing(&value)
                    if !truthy {
                        return macro_bool_value(false), Compile_Error{}, true
                    }
                }
                return macro_bool_value(true), Compile_Error{}, true
            case "or":
                for arg in form.items[1:] {
                    value, err_value, ok_value := macro_eval_expr(arg, macros, bindings)
                    if !ok_value {
                        return Macro_Value{}, err_value, false
                    }
                    truthy := macro_truthy(value)
                    macro_value_delete_backing(&value)
                    if truthy {
                        return macro_bool_value(true), Compile_Error{}, true
                    }
                }
                return macro_bool_value(false), Compile_Error{}, true
            case "if":
                if len(form.items) != 4 {
                    return Macro_Value{}, Compile_Error{message = "if expects condition, then, and else", span = form.span}, false
                }
                cond_value, err_cond, ok_cond := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_cond {
                    return Macro_Value{}, err_cond, false
                }
                cond_truthy := macro_truthy(cond_value)
                macro_value_delete_backing(&cond_value)
                if cond_truthy {
                    return macro_eval_expr(form.items[2], macros, bindings)
                }
                return macro_eval_expr(form.items[3], macros, bindings)
            case "cond":
                if len(form.items) < 3 {
                    return Macro_Value{}, Compile_Error{message = "cond expects at least one clause", span = form.span}, false
                }
                if (len(form.items)-1)%2 != 0 {
                    return Macro_Value{}, Compile_Error{message = "cond expects test/body pairs", span = form.span}, false
                }
                i := 1
                for i < len(form.items) {
                    test_form := form.items[i]
                    if test_form.kind == .Keyword && test_form.text == ":else" {
                        if i+2 < len(form.items) {
                            return Macro_Value{}, Compile_Error{message = "cond :else must be the final clause", span = test_form.span}, false
                        }
                        return macro_eval_expr(form.items[i+1], macros, bindings)
                    }
                    test_value, err_test, ok_test := macro_eval_expr(test_form, macros, bindings)
                    if !ok_test {
                        return Macro_Value{}, err_test, false
                    }
                    truthy := macro_truthy(test_value)
                    macro_value_delete_backing(&test_value)
                    if truthy {
                        return macro_eval_expr(form.items[i+1], macros, bindings)
                    }
                    i += 2
                }
                return macro_nil_value(), Compile_Error{}, true
            case "case":
                if len(form.items) < 4 {
                    return Macro_Value{}, Compile_Error{message = "case expects subject and clauses", span = form.span}, false
                }
                if (len(form.items)-2)%2 != 0 {
                    return Macro_Value{}, Compile_Error{message = "case expects clause/body pairs", span = form.span}, false
                }
                subject, err_subject, ok_subject := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_subject {
                    return Macro_Value{}, err_subject, false
                }
                defer macro_value_delete_backing(&subject)
                i := 2
                for i < len(form.items) {
                    clause := form.items[i]
                    if clause.kind == .Keyword && clause.text == ":else" {
                        if i+2 < len(form.items) {
                            return Macro_Value{}, Compile_Error{message = "case :else must be the final clause", span = clause.span}, false
                        }
                        return macro_eval_expr(form.items[i+1], macros, bindings)
                    }
                    matched := false
                    if clause.kind == .Set {
                        for item in clause.items {
                            value, err_value, ok_value := macro_eval_expr(item, macros, bindings)
                            if !ok_value {
                                return Macro_Value{}, err_value, false
                            }
                            if macro_value_equal(subject, value) {
                                matched = true
                            }
                            macro_value_delete_backing(&value)
                            if matched {
                                break
                            }
                        }
                    } else {
                        value, err_value, ok_value := macro_eval_expr(clause, macros, bindings)
                        if !ok_value {
                            return Macro_Value{}, err_value, false
                        }
                        matched = macro_value_equal(subject, value)
                        macro_value_delete_backing(&value)
                    }
                    if matched {
                        return macro_eval_expr(form.items[i+1], macros, bindings)
                    }
                    i += 2
                }
                return macro_nil_value(), Compile_Error{}, true
            case "let":
                if len(form.items) < 3 || form.items[1].kind != .Vector {
                    return Macro_Value{}, Compile_Error{message = "macro let expects binding vector and body", span = form.span}, false
                }
                local: [dynamic]Macro_Binding
                defer delete(local)
                for binding in bindings {
                    append(&local, binding)
                }
                local_owned_start := len(local)
                binding_form := form.items[1]
                if len(binding_form.items)%2 != 0 {
                    return Macro_Value{}, Compile_Error{message = "macro let expects [name value ...] bindings", span = binding_form.span}, false
                }
                i := 0
                for i < len(binding_form.items) {
                    name_form := binding_form.items[i]
                    if name_form.kind != .Symbol {
                        return Macro_Value{}, Compile_Error{message = "macro let binding name must be a symbol", span = name_form.span}, false
                    }
                    value, err_value, ok_value := macro_eval_expr(binding_form.items[i+1], macros, local[:])
                    if !ok_value {
                        return Macro_Value{}, err_value, false
                    }
                    append(&local, Macro_Binding{name = name_form.text, value = value})
                    i += 2
                }
                value, err_value, ok_value := macro_eval_sequence(form.items[2:], macros, local[:])
                for idx in local_owned_start ..< len(local) {
                    macro_value_delete_backing(&local[idx].value)
                }
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                return value, Compile_Error{}, true
            case "list":
                return macro_eval_list_builder(.List, form, macros, bindings)
            case "vector":
                return macro_eval_list_builder(.Vector, form, macros, bindings)
            case "brace":
                return macro_eval_list_builder(.Brace, form, macros, bindings)
            case "first", "arr.first", "kvist.first":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "first expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                forms, err_forms, ok_forms := macro_list_from_value(value, form.items[1].span)
                if !ok_forms {
                    macro_value_delete_backing(&value)
                    return Macro_Value{}, err_forms, false
                }
                if len(forms) == 0 {
                    macro_value_delete_backing(&value)
                    return macro_nil_value(), Compile_Error{}, true
                }
                result := macro_owned_form_value(clone_cst_form(forms[0]))
                macro_value_delete_backing(&value)
                return result, Compile_Error{}, true
            case "rest", "arr.rest", "kvist.rest":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "rest expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                forms, err_forms, ok_forms := macro_list_from_value(value, form.items[1].span)
                if !ok_forms {
                    macro_value_delete_backing(&value)
                    return Macro_Value{}, err_forms, false
                }
                if len(forms) <= 1 {
                    macro_value_delete_backing(&value)
                    return macro_forms_value(nil), Compile_Error{}, true
                }
                cloned := clone_cst_form_slice(forms[1:])
                result := macro_owned_forms_value(cloned[:])
                delete(cloned)
                macro_value_delete_backing(&value)
                return result, Compile_Error{}, true
            case "nth", "arr.nth", "kvist.nth":
                if len(form.items) != 3 {
                    return Macro_Value{}, Compile_Error{message = "nth expects sequence and index", span = form.span}, false
                }
                seq_value, err_seq, ok_seq := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_seq {
                    return Macro_Value{}, err_seq, false
                }
                forms, err_forms, ok_forms := macro_list_from_value(seq_value, form.items[1].span)
                if !ok_forms {
                    macro_value_delete_backing(&seq_value)
                    return Macro_Value{}, err_forms, false
                }
                index_value, err_index, ok_index := macro_eval_expr(form.items[2], macros, bindings)
                if !ok_index {
                    macro_value_delete_backing(&seq_value)
                    return Macro_Value{}, err_index, false
                }
                if index_value.kind != .Int {
                    macro_value_delete_backing(&seq_value)
                    return Macro_Value{}, Compile_Error{message = "nth index must be an integer", span = form.items[2].span}, false
                }
                if index_value.int_value < 0 || index_value.int_value >= len(forms) {
                    macro_value_delete_backing(&seq_value)
                    return macro_nil_value(), Compile_Error{}, true
                }
                result := macro_owned_form_value(clone_cst_form(forms[index_value.int_value]))
                macro_value_delete_backing(&seq_value)
                return result, Compile_Error{}, true
            case "core.count", "count", "kvist.count", "str.count":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "count expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                #partial switch value.kind {
                case .Forms:
                    return macro_int_value(len(value.forms)), Compile_Error{}, true
                case .Form:
                    if value.form.kind == .List || value.form.kind == .Vector || value.form.kind == .Brace {
                        return macro_int_value(len(value.form.items)), Compile_Error{}, true
                    }
                    return macro_int_value(1), Compile_Error{}, true
                case .String:
                    return macro_int_value(len(value.string_value)), Compile_Error{}, true
                case .Nil:
                    return macro_int_value(0), Compile_Error{}, true
                case:
                    return macro_int_value(1), Compile_Error{}, true
                }
            case "core.slice", "slice", "str.slice":
                if len(form.items) != 3 && len(form.items) != 4 {
                    return Macro_Value{}, Compile_Error{message = "slice expects sequence, start, and optional end", span = form.span}, false
                }
                seq_value, err_seq, ok_seq := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_seq {
                    return Macro_Value{}, err_seq, false
                }
                start_value, err_start, ok_start := macro_eval_expr(form.items[2], macros, bindings)
                if !ok_start {
                    macro_value_delete_backing(&seq_value)
                    return Macro_Value{}, err_start, false
                }
                if start_value.kind != .Int {
                    macro_value_delete_backing(&seq_value)
                    return Macro_Value{}, Compile_Error{message = "slice start must be an integer", span = form.items[2].span}, false
                }
                end := -1
                if len(form.items) == 4 {
                    end_value, err_end, ok_end := macro_eval_expr(form.items[3], macros, bindings)
                    if !ok_end {
                        macro_value_delete_backing(&seq_value)
                        return Macro_Value{}, err_end, false
                    }
                    if end_value.kind != .Int {
                        macro_value_delete_backing(&seq_value)
                        return Macro_Value{}, Compile_Error{message = "slice end must be an integer", span = form.items[3].span}, false
                    }
                    end = end_value.int_value
                }
                if seq_value.kind == .String {
                    result := macro_owned_string_value(macro_slice_string(seq_value.string_value, start_value.int_value, end))
                    macro_value_delete_backing(&seq_value)
                    return result, Compile_Error{}, true
                }
                forms, err_forms, ok_forms := macro_list_from_value(seq_value, form.items[1].span)
                if !ok_forms {
                    macro_value_delete_backing(&seq_value)
                    return Macro_Value{}, err_forms, false
                }
                sliced := macro_slice_forms(forms, start_value.int_value, end)
                cloned := clone_cst_form_slice(sliced)
                result := macro_owned_forms_value(cloned[:])
                delete(cloned)
                delete(sliced)
                macro_value_delete_backing(&seq_value)
                return result, Compile_Error{}, true
            case "concat":
                out: [dynamic]CST_Form
                for arg in form.items[1:] {
                    value, err_value, ok_value := macro_eval_expr(arg, macros, bindings)
                    if !ok_value {
                        return Macro_Value{}, err_value, false
                    }
                    forms, err_forms, ok_forms := macro_value_to_owned_forms(value, arg.span)
                    if !ok_forms {
                        macro_value_delete_backing(&value)
                        return Macro_Value{}, err_forms, false
                    }
                    for item in forms {
                        append(&out, item)
                    }
                    delete(forms)
                    macro_value_delete_backing(&value)
                }
                result := macro_owned_forms_value(out[:])
                delete(out)
                return result, Compile_Error{}, true
            case "forms":
                out: [dynamic]CST_Form
                for arg in form.items[1:] {
                    value, err_value, ok_value := macro_eval_expr(arg, macros, bindings)
                    if !ok_value {
                        return Macro_Value{}, err_value, false
                    }
                    forms, err_forms, ok_forms := macro_value_to_owned_forms(value, arg.span)
                    if !ok_forms {
                        macro_value_delete_backing(&value)
                        return Macro_Value{}, err_forms, false
                    }
                    for item in forms {
                        append(&out, item)
                    }
                    delete(forms)
                    macro_value_delete_backing(&value)
                }
                result := macro_owned_forms_value(out[:])
                delete(out)
                return result, Compile_Error{}, true
            case "subst":
                if len(form.items) != 4 {
                    return Macro_Value{}, Compile_Error{message = "subst expects template, names, and values", span = form.span}, false
                }
                template_value, err_template, ok_template := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_template {
                    return Macro_Value{}, err_template, false
                }
                template_form, err_template_form, ok_template_form := macro_value_to_form(template_value, form.items[1].span)
                if !ok_template_form {
                    return Macro_Value{}, err_template_form, false
                }
                names_value, err_names, ok_names := macro_eval_expr(form.items[2], macros, bindings)
                if !ok_names {
                    return Macro_Value{}, err_names, false
                }
                name_forms, err_name_forms, ok_name_forms := macro_list_from_value(names_value, form.items[2].span)
                if !ok_name_forms {
                    return Macro_Value{}, err_name_forms, false
                }
                values_value, err_values, ok_values := macro_eval_expr(form.items[3], macros, bindings)
                if !ok_values {
                    return Macro_Value{}, err_values, false
                }
                value_forms, err_value_forms, ok_value_forms := macro_list_from_value(values_value, form.items[3].span)
                if !ok_value_forms {
                    return Macro_Value{}, err_value_forms, false
                }
                if len(name_forms) != len(value_forms) {
                    return Macro_Value{}, Compile_Error{message = "subst expects the same number of names and values", span = form.span}, false
                }
                names: [dynamic]string
                defer delete(names)
                for name_form in name_forms {
                    if name_form.kind != .Symbol {
                        return Macro_Value{}, Compile_Error{message = "subst names must be symbols", span = name_form.span}, false
                    }
                    append(&names, name_form.text)
                }
                subst_result := macro_owned_form_value(macro_subst_form(template_form, names[:], value_forms[:]))
                macro_value_delete_backing(&values_value)
                macro_value_delete_backing(&names_value)
                macro_value_delete_backing(&template_value)
                return subst_result, Compile_Error{}, true
            case "str":
                builder := strings.builder_make()
                defer strings.builder_destroy(&builder)
                for arg in form.items[1:] {
                    value, err_value, ok_value := macro_eval_expr(arg, macros, bindings)
                    if !ok_value {
                        return Macro_Value{}, err_value, false
                    }
                    text, err_text, ok_text := macro_value_to_string(value, arg.span)
                    if !ok_text {
                        macro_value_delete_backing(&value)
                        return Macro_Value{}, err_text, false
                    }
                    strings.write_string(&builder, text)
                    delete(text)
                    macro_value_delete_backing(&value)
                }
                return macro_owned_string_value(strings.clone(strings.to_string(builder))), Compile_Error{}, true
            case "io.read", "io__read":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "io.read expects one path argument", span = form.span}, false
                }
                path_value, err_path_value, ok_path_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_path_value {
                    return Macro_Value{}, err_path_value, false
                }
                raw_path, err_raw_path, ok_raw_path := macro_value_to_string(path_value, form.items[1].span)
                if !ok_raw_path {
                    macro_value_delete_backing(&path_value)
                    return Macro_Value{}, err_raw_path, false
                }
                defer delete(raw_path)
                defer macro_value_delete_backing(&path_value)
                path, err_path, ok_path := macro_eval_read_path(raw_path, form.items[1].span)
                if !ok_path {
                    return Macro_Value{}, err_path, false
                }
                defer delete(path)
                data, read_err := os.read_entire_file_from_path(path, context.allocator)
                if read_err != nil {
                    return Macro_Value{}, Compile_Error{message = fmt.tprintf("compile-time io.read could not read file: %s", path), span = form.items[1].span}, false
                }
                text := strings.clone(string(data))
                delete(data)
                return macro_owned_string_value(text), Compile_Error{}, true
            case "symbol":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "symbol expects one string argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                if value.kind != .String {
                    macro_value_delete_backing(&value)
                    return Macro_Value{}, Compile_Error{message = "symbol expects one string argument", span = form.items[1].span}, false
                }
                symbol_text := strings.clone(value.string_value)
                macro_value_delete_backing(&value)
                return macro_owned_form_value(CST_Form{kind = .Symbol, text = symbol_text, span = form.span}), Compile_Error{}, true
            case "gensym":
                prefix := "__kvist_gensym"
                if len(form.items) > 2 {
                    return Macro_Value{}, Compile_Error{message = "gensym expects zero or one string argument", span = form.span}, false
                }
                gensym_value := Macro_Value{}
                gensym_has_value := false
                if len(form.items) == 2 {
                    value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                    if !ok_value {
                        return Macro_Value{}, err_value, false
                    }
                    if value.kind != .String {
                        macro_value_delete_backing(&value)
                        return Macro_Value{}, Compile_Error{message = "gensym expects zero or one string argument", span = form.items[1].span}, false
                    }
                    gensym_value = value
                    gensym_has_value = true
                    prefix = value.string_value
                }
                macro_gensym_counter += 1
                gensym_text := strings.clone(fmt.tprintf("%s_%d", prefix, macro_gensym_counter))
                if gensym_has_value {
                    macro_value_delete_backing(&gensym_value)
                }
                return macro_owned_form_value(CST_Form{
                    kind = .Symbol,
                    text = gensym_text,
                    span = form.span,
                }), Compile_Error{}, true
            case "keyword":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "keyword expects one string argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                if value.kind != .String {
                    macro_value_delete_backing(&value)
                    return Macro_Value{}, Compile_Error{message = "keyword expects one string argument", span = form.items[1].span}, false
                }
                keyword_text := strings.clone(fmt.tprintf(":%s", value.string_value))
                macro_value_delete_backing(&value)
                return macro_owned_form_value(CST_Form{kind = .Keyword, text = keyword_text, span = form.span}), Compile_Error{}, true
            case "name":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "name expects one symbol or keyword", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                single, err_single, ok_single := macro_value_to_form(value, form.items[1].span)
                if !ok_single {
                    macro_value_delete_backing(&value)
                    return Macro_Value{}, err_single, false
                }
                #partial switch single.kind {
                case .Symbol:
                    if len(single.text) > 1 && single.text[0] == '.' {
                        result := macro_owned_string_value(strings.clone(single.text[1:]))
                        macro_value_delete_backing(&value)
                        return result, Compile_Error{}, true
                    }
                    if len(single.text) > 1 && single.text[len(single.text)-1] == ':' {
                        result := macro_owned_string_value(strings.clone(single.text[:len(single.text)-1]))
                        macro_value_delete_backing(&value)
                        return result, Compile_Error{}, true
                    }
                    result := macro_owned_string_value(strings.clone(single.text))
                    macro_value_delete_backing(&value)
                    return result, Compile_Error{}, true
                case .Keyword:
                    if len(single.text) > 0 && single.text[0] == ':' {
                        result := macro_owned_string_value(strings.clone(single.text[1:]))
                        macro_value_delete_backing(&value)
                        return result, Compile_Error{}, true
                    }
                    result := macro_owned_string_value(strings.clone(single.text))
                    macro_value_delete_backing(&value)
                    return result, Compile_Error{}, true
                case:
                    macro_value_delete_backing(&value)
                    return Macro_Value{}, Compile_Error{message = "name expects one symbol or keyword", span = form.items[1].span}, false
                }
            case "+":
                int_sum := 0
                float_sum := 0.0
                all_int := true
                for item in form.items[1:] {
                    value, err_value, ok_value := macro_eval_expr(item, macros, bindings)
                    if !ok_value {
                        return Macro_Value{}, err_value, false
                    }
                    if value.kind == .Int {
                        int_sum += value.int_value
                        float_sum += f64(value.int_value)
                        macro_value_delete_backing(&value)
                        continue
                    }
                    if value.kind == .Form && value.form.kind == .Number {
                        parsed_int, ok_int := strconv.parse_int(value.form.text)
                        if ok_int {
                            int_sum += parsed_int
                            float_sum += f64(parsed_int)
                            macro_value_delete_backing(&value)
                            continue
                        }
                    }
                    number, ok_number := macro_value_number(value)
                    macro_value_delete_backing(&value)
                    if !ok_number {
                        return Macro_Value{}, Compile_Error{message = "+ expects numeric arguments", span = item.span}, false
                    }
                    all_int = false
                    float_sum += number
                }
                if all_int {
                    return macro_int_value(int_sum), Compile_Error{}, true
                }
                return macro_float_value(float_sum), Compile_Error{}, true
            case "=":
                if len(form.items) < 3 {
                    return Macro_Value{}, Compile_Error{message = "= expects at least two arguments", span = form.span}, false
                }
                previous, err_previous, ok_previous := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_previous {
                    return Macro_Value{}, err_previous, false
                }
                for item in form.items[2:] {
                    current, err_current, ok_current := macro_eval_expr(item, macros, bindings)
                    if !ok_current {
                        macro_value_delete_backing(&previous)
                        return Macro_Value{}, err_current, false
                    }
                    if !macro_value_equal(previous, current) {
                        macro_value_delete_backing(&previous)
                        macro_value_delete_backing(&current)
                        return macro_bool_value(false), Compile_Error{}, true
                    }
                    macro_value_delete_backing(&previous)
                    previous = current
                }
                macro_value_delete_backing(&previous)
                return macro_bool_value(true), Compile_Error{}, true
            case "<", "<=", ">", ">=":
                if len(form.items) < 3 {
                    return Macro_Value{}, Compile_Error{message = fmt.tprintf("%s expects at least two arguments", head.text), span = form.span}, false
                }
                previous, err_previous, ok_previous := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_previous {
                    return Macro_Value{}, err_previous, false
                }
                previous_number, ok_previous_number := macro_value_number(previous)
                if !ok_previous_number {
                    macro_value_delete_backing(&previous)
                    return Macro_Value{}, Compile_Error{message = fmt.tprintf("%s expects numeric arguments", head.text), span = form.items[1].span}, false
                }
                macro_value_delete_backing(&previous)
                for item in form.items[2:] {
                    current, err_current, ok_current := macro_eval_expr(item, macros, bindings)
                    if !ok_current {
                        return Macro_Value{}, err_current, false
                    }
                    current_number, ok_current_number := macro_value_number(current)
                    if !ok_current_number {
                        macro_value_delete_backing(&current)
                        return Macro_Value{}, Compile_Error{message = fmt.tprintf("%s expects numeric arguments", head.text), span = item.span}, false
                    }
                    macro_value_delete_backing(&current)
                    matched := false
                    switch head.text {
                    case "<":
                        matched = previous_number < current_number
                    case "<=":
                        matched = previous_number <= current_number
                    case ">":
                        matched = previous_number > current_number
                    case ">=":
                        matched = previous_number >= current_number
                    }
                    if !matched {
                        return macro_bool_value(false), Compile_Error{}, true
                    }
                    previous_number = current_number
                }
                return macro_bool_value(true), Compile_Error{}, true
            case "contains?", "core.contains?", "core-contains?":
                return macro_eval_contains_expr(form, macros, bindings)
            case "str.contains?":
                return macro_eval_string_contains_expr(form, macros, bindings)
            case "starts-with?", "str.starts-with?":
                return macro_eval_string_affix_expr(form, macros, bindings, true)
            case "ends-with?", "str.ends-with?":
                return macro_eval_string_affix_expr(form, macros, bindings, false)
            case "parse-int", "str.parse-int":
                return macro_eval_parse_int_expr(form, macros, bindings)
            case "digit?", "str.digit?":
                return macro_eval_digit_expr(form, macros, bindings)
            case "some?", "every?":
                return macro_eval_some_every_expr(form, macros, bindings, head.text == "every?")
            case "map":
                return macro_eval_map_expr(form, macros, bindings)
            case "filter":
                return macro_eval_filter_expr(form, macros, bindings)
            case "reduce":
                return macro_eval_reduce_expr(form, macros, bindings)
            case "form?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "form? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                return macro_bool_value(value.kind == .Form), Compile_Error{}, true
            case "vector?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "vector? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .Vector), Compile_Error{}, true
            case "brace?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "brace? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .Brace), Compile_Error{}, true
            case "list?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "list? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .List), Compile_Error{}, true
            case "symbol?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "symbol? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .Symbol), Compile_Error{}, true
            case "keyword?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "keyword? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .Keyword), Compile_Error{}, true
            case "field-selector?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "field-selector? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .Symbol &&
                                        len(value.form.text) > 1 &&
                                        value.form.text[0] == '.'), Compile_Error{}, true
            case "string?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "string? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind == .String {
                    return macro_bool_value(true), Compile_Error{}, true
                }
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .String), Compile_Error{}, true
            case "number?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "number? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind == .Int {
                    return macro_bool_value(true), Compile_Error{}, true
                }
                if value.kind == .Float {
                    return macro_bool_value(true), Compile_Error{}, true
                }
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .Number), Compile_Error{}, true
            case "int?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "int? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind == .Int {
                    return macro_bool_value(true), Compile_Error{}, true
                }
                if value.kind != .Form || value.form.kind != .Number {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                _, ok_parsed := strconv.parse_int(value.form.text)
                return macro_bool_value(ok_parsed), Compile_Error{}, true
            case "float?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "float? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind == .Float {
                    return macro_bool_value(true), Compile_Error{}, true
                }
                if value.kind != .Form || value.form.kind != .Number {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                _, ok_parsed := strconv.parse_int(value.form.text)
                if ok_parsed {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                _, ok_float := strconv.parse_f64(value.form.text)
                return macro_bool_value(ok_float), Compile_Error{}, true
            case "bool?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "bool? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind == .Bool {
                    return macro_bool_value(true), Compile_Error{}, true
                }
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .Bool), Compile_Error{}, true
            case "nil?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "nil? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                defer macro_value_delete_backing(&value)
                if value.kind == .Nil {
                    return macro_bool_value(true), Compile_Error{}, true
                }
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .Nil), Compile_Error{}, true
            case "source":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "source expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                single, err_single, ok_single := macro_value_to_form(value, form.items[1].span)
                if !ok_single {
                    macro_value_delete_backing(&value)
                    return Macro_Value{}, err_single, false
                }
                result := macro_owned_string_value(macro_form_text(single))
                macro_value_delete_backing(&value)
                return result, Compile_Error{}, true
            case "text":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "text expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                if value.kind == .String {
                    result := macro_owned_string_value(strings.clone(value.string_value))
                    macro_value_delete_backing(&value)
                    return result, Compile_Error{}, true
                }
                if value.kind == .Int {
                    result := macro_owned_string_value(strings.clone(macro_int_text(value.int_value)))
                    macro_value_delete_backing(&value)
                    return result, Compile_Error{}, true
                }
                if value.kind == .Float {
                    result := macro_owned_string_value(strings.clone(macro_float_text(value.float_value)))
                    macro_value_delete_backing(&value)
                    return result, Compile_Error{}, true
                }
                if value.kind == .Bool {
                    if value.bool_value {
                        return macro_owned_string_value(strings.clone("true")), Compile_Error{}, true
                    }
                    return macro_owned_string_value(strings.clone("false")), Compile_Error{}, true
                }
                if value.kind == .Nil {
                    return macro_owned_string_value(strings.clone("nil")), Compile_Error{}, true
                }
                if value.kind == .Form {
                    #partial switch value.form.kind {
                    case .String:
                        result := macro_owned_string_value(unquote_string(value.form.text))
                        macro_value_delete_backing(&value)
                        return result, Compile_Error{}, true
                    case .Symbol:
                        result := macro_owned_string_value(strings.clone(value.form.text))
                        macro_value_delete_backing(&value)
                        return result, Compile_Error{}, true
                    case .Keyword:
                        if len(value.form.text) > 0 && value.form.text[0] == ':' {
                            result := macro_owned_string_value(strings.clone(value.form.text[1:]))
                            macro_value_delete_backing(&value)
                            return result, Compile_Error{}, true
                        }
                        result := macro_owned_string_value(strings.clone(value.form.text))
                        macro_value_delete_backing(&value)
                        return result, Compile_Error{}, true
                    case .Number, .Bool, .Nil:
                        result := macro_owned_string_value(strings.clone(value.form.text))
                        macro_value_delete_backing(&value)
                        return result, Compile_Error{}, true
                    case:
                    }
                }
                macro_value_delete_backing(&value)
                return Macro_Value{}, Compile_Error{message = "text expects a scalar literal, symbol, or keyword", span = form.items[1].span}, false
            case "error":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "error expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                message, err_message, ok_message := macro_value_to_string(value, form.items[1].span)
                if !ok_message {
                    macro_value_delete_backing(&value)
                    return Macro_Value{}, err_message, false
                }
                macro_value_delete_backing(&value)
                return Macro_Value{}, Compile_Error{message = message, span = form.items[1].span}, false
            }
        }
        if head.kind == .Symbol {
            if user_macro, ok_user := find_user_macro(macros, head.text); ok_user {
                local_bindings, err_bindings, ok_bindings := macro_collect_eval_call_bindings(user_macro, form, macros, bindings)
                if !ok_bindings {
                    return Macro_Value{}, err_bindings, false
                }
                value, err, ok := macro_eval_sequence(user_macro.body[:], macros, local_bindings[:])
                if !ok {
                    macro_binding_slice_delete_backing(&local_bindings)
                    return Macro_Value{}, macro_error_with_expansion_context(user_macro, err), false
                }
                result := macro_value_clone_backing(value)
                macro_value_delete_backing(&value)
                macro_binding_slice_delete_backing(&local_bindings)
                return result, Compile_Error{}, true
            }
        }
        return macro_form_value(form), Compile_Error{}, true
    }
    return Macro_Value{}, Compile_Error{message = "unsupported macro form", span = form.span}, false
}

expand_user_macro_call :: proc(macro_decl: User_Macro, call: CST_Form, macros: []User_Macro) -> (CST_Form, Compile_Error, bool) {
    value, err_value, ok_value := invoke_user_macro_value(macro_decl, call, macros)
    if !ok_value {
        return CST_Form{}, err_value, false
    }
    expanded, err_form, ok_form := macro_value_to_owned_form(value, call.span)
    if !ok_form {
        macro_value_delete_backing(&value)
        return CST_Form{}, err_form, false
    }
    macro_value_delete_backing(&value)
    if expanded.span.start == 0 && expanded.span.end == 0 {
        expanded.span = call.span
    }
    return expanded, Compile_Error{}, true
}

expand_user_macro_call_to_forms :: proc(macro_decl: User_Macro, call: CST_Form, macros: []User_Macro) -> ([]CST_Form, Compile_Error, bool) {
    value, err_value, ok_value := invoke_user_macro_value(macro_decl, call, macros)
    if !ok_value {
        return nil, err_value, false
    }
    forms, err_forms, ok_forms := macro_value_to_owned_forms(value, call.span)
    macro_value_delete_backing(&value)
    return forms, err_forms, ok_forms
}

macro_emit_expanded_form :: proc(e: ^Macro_Expander, indent: string, form: CST_Form, macros: []User_Macro, suffix: string = "") -> (Compile_Error, bool) {
    expanded, err_expand, ok_expand := macroexpand_form_with_macros(form, macros)
    if !ok_expand {
        return err_expand, false
    }
    defer delete(expanded.output)
    defer delete(expanded.source_map)

    start_line := e.line
    text_end := len(expanded.output)
    if text_end > 0 && expanded.output[text_end-1] == '\n' {
        text_end -= 1
    }

    start := 0
    i := 0
    for i < text_end {
        if expanded.output[i] == '\n' {
            strings.write_string(&e.builder, indent)
            strings.write_string(&e.builder, expanded.output[start:i])
            strings.write_byte(&e.builder, '\n')
            e.line += 1
            start = i + 1
        }
        i += 1
    }
    strings.write_string(&e.builder, indent)
    strings.write_string(&e.builder, expanded.output[start:text_end])
    strings.write_string(&e.builder, suffix)
    strings.write_byte(&e.builder, '\n')
    e.line += 1

    if len(expanded.source_map) == 0 {
        macro_record_source_map(e, start_line, e.line-1, form.span)
        return {}, true
    }

    for entry in expanded.source_map {
        adjusted := entry
        adjusted.generated_start_line = start_line + entry.generated_start_line - 1
        adjusted.generated_end_line = start_line + entry.generated_end_line - 1
        append(e.source_map, adjusted)
    }
    return {}, true
}

macro_emit_body_form :: proc(e: ^Macro_Expander, item: CST_Form, macros: []User_Macro, suffix: string) -> (Compile_Error, bool) {
    return macro_emit_expanded_form(e, "    ", item, macros, suffix)
}

write_macro_form :: proc(builder: ^strings.Builder, form: CST_Form) {
    #partial switch form.kind {
    case .List:
        if len(form.items) == 3 &&
           form.items[0].kind == .Symbol &&
           form.items[0].text == "__kvist_field" &&
           form.items[2].kind == .Symbol {
            write_macro_form(builder, form.items[1])
            strings.write_byte(builder, '.')
            strings.write_string(builder, form.items[2].text)
            return
        }
        if len(form.items) == 2 &&
           form.items[0].kind == .Symbol &&
           len(form.items[0].text) > 1 &&
           form.items[0].text[0] == '.' {
            write_macro_form(builder, form.items[1])
            strings.write_string(builder, form.items[0].text)
            return
        }
        strings.write_byte(builder, '(')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            write_macro_form(builder, item)
        }
        strings.write_byte(builder, ')')
    case .Vector:
        strings.write_byte(builder, '[')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            write_macro_form(builder, item)
        }
        strings.write_byte(builder, ']')
    case .Brace:
        strings.write_byte(builder, '{')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            write_macro_form(builder, item)
        }
        strings.write_byte(builder, '}')
    case .Symbol, .Keyword, .String, .Number, .Bool, .Nil:
        strings.write_string(builder, form.text)
    }
}

write_macro_expanded_output :: proc(builder: ^strings.Builder, output: string) {
    text_end := len(output)
    if text_end > 0 && output[text_end-1] == '\n' {
        text_end -= 1
    }
    strings.write_string(builder, output[:text_end])
}

macroexpand_cst_form_with_macros :: proc(form: CST_Form, macros: []User_Macro) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    #partial switch form.kind {
    case .List:
        if len(form.items) > 0 && form.items[0].kind == .Symbol {
            switch form.items[0].text {
            case "def", "def-", "defvar", "defvar-":
                return macroexpand_def_binding_form_preserving_types(form, macros)
            case "defstruct", "defstruct-", "defunion", "defunion-":
                return clone_cst_form(form), Compile_Error{}, true
            case "defn", "defn-":
                return macroexpand_defn_form_preserving_types(form, macros)
            }
            builtin_kind := builtin_macro_kind(form.items[0].text)
            if builtin_kind != .When &&
               builtin_kind != .When_Let &&
               builtin_kind != .If_Let &&
               builtin_kind != .When_Ok &&
               builtin_kind != .If_Ok {
                if user_macro, ok_user := find_user_macro(macros, form.items[0].text); ok_user {
                    expanded, err_user, ok_user_expand := expand_user_macro_call(user_macro, form, macros)
                    if !ok_user_expand {
                        return CST_Form{}, err_user, false
                    }
                    defer delete_cst_form(&expanded)
                    return macroexpand_cst_form_with_macros(expanded, macros)
                }
            }
            #partial switch builtin_kind {
            case .Thread_First, .Thread_Last:
                return clone_cst_form(form), Compile_Error{}, true
            case:
            }
        }
        expanded = CST_Form{kind = form.kind, span = form.span}
        if form.text != "" {
            expanded.text = strings.clone(form.text)
        }
        for item, idx in form.items {
            if idx == 0 && item.kind == .List {
                if _, _, ok_type := parse_type_text(item); ok_type {
                    append(&expanded.items, clone_cst_form(item))
                    continue
                }
            }
            child, err_child, ok_child := macroexpand_cst_form_with_macros(item, macros)
            if !ok_child {
                delete_cst_form(&expanded)
                return CST_Form{}, err_child, false
            }
            append(&expanded.items, child)
        }
        return expanded, Compile_Error{}, true
    case .Vector, .Brace, .Set:
        expanded = CST_Form{kind = form.kind, span = form.span}
        if form.text != "" {
            expanded.text = strings.clone(form.text)
        }
        for item in form.items {
            child, err_child, ok_child := macroexpand_cst_form_with_macros(item, macros)
            if !ok_child {
                delete_cst_form(&expanded)
                return CST_Form{}, err_child, false
            }
            append(&expanded.items, child)
        }
        return expanded, Compile_Error{}, true
    case:
        return clone_cst_form(form), Compile_Error{}, true
    }
}

macroexpand_def_binding_form_preserving_types :: proc(form: CST_Form, macros: []User_Macro) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 {
        return clone_cst_form(form), Compile_Error{}, true
    }
    expanded = CST_Form{kind = form.kind, span = form.span}
    if form.text != "" {
        expanded.text = strings.clone(form.text)
    }

    append(&expanded.items, clone_cst_form(form.items[0]))
    append(&expanded.items, clone_cst_form(form.items[1]))

    value_index := 2
    if len(form.items) > 3 && form.items[2].kind == .String {
        append(&expanded.items, clone_cst_form(form.items[2]))
        value_index = 3
    }

    if form.items[1].kind == .Symbol &&
       len(form.items[1].text) > 0 &&
       form.items[1].text[len(form.items[1].text)-1] == ':' {
        _, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], value_index)
        if !ok_type {
            delete_cst_form(&expanded)
            return CST_Form{}, err_type, false
        }
        for type_item in form.items[value_index:next_i] {
            append(&expanded.items, clone_cst_form(type_item))
        }
        value_index = next_i
    }

    for item in form.items[value_index:] {
        child, err_child, ok_child := macroexpand_cst_form_with_macros(item, macros)
        if !ok_child {
            delete_cst_form(&expanded)
            return CST_Form{}, err_child, false
        }
        append(&expanded.items, child)
    }
    return expanded, Compile_Error{}, true
}

macroexpand_param_vector_preserving_types :: proc(form: CST_Form, macros: []User_Macro) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    if form.kind != .Vector {
        return macroexpand_cst_form_with_macros(form, macros)
    }
    expanded = CST_Form{kind = form.kind, span = form.span}
    if form.text != "" {
        expanded.text = strings.clone(form.text)
    }

    i := 0
    for i < len(form.items) {
        target := form.items[i]
        append(&expanded.items, clone_cst_form(target))
        if target.kind != .Symbol || len(target.text) == 0 || target.text[len(target.text)-1] != ':' {
            i += 1
            continue
        }
        if i+1 >= len(form.items) {
            i += 1
            continue
        }
        _, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], i+1)
        if !ok_type {
            delete_cst_form(&expanded)
            return CST_Form{}, err_type, false
        }
        for type_item in form.items[i+1:next_i] {
            append(&expanded.items, clone_cst_form(type_item))
        }
        i = next_i
        if i < len(form.items) && is_symbol(form.items[i], "=") {
            append(&expanded.items, clone_cst_form(form.items[i]))
            if i+1 >= len(form.items) {
                delete_cst_form(&expanded)
                return CST_Form{}, Compile_Error{message = "missing default parameter value", span = form.items[i].span}, false
            }
            value, err_value, ok_value := macroexpand_cst_form_with_macros(form.items[i+1], macros)
            if !ok_value {
                delete_cst_form(&expanded)
                return CST_Form{}, err_value, false
            }
            append(&expanded.items, value)
            i += 2
        }
    }
    return expanded, Compile_Error{}, true
}

macroexpand_defn_form_preserving_types :: proc(form: CST_Form, macros: []User_Macro) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    expanded = CST_Form{kind = form.kind, span = form.span}
    if form.text != "" {
        expanded.text = strings.clone(form.text)
    }

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
        if i == params_index {
            params, err_params, ok_params := macroexpand_param_vector_preserving_types(item, macros)
            if !ok_params {
                delete_cst_form(&expanded)
                return CST_Form{}, err_params, false
            }
            append(&expanded.items, params)
            i += 1
            continue
        }
        if i == params_index+1 && is_symbol(item, "->") {
            append(&expanded.items, clone_cst_form(item))
            if i+1 >= len(form.items) {
                delete_cst_form(&expanded)
                return CST_Form{}, Compile_Error{message = "missing return spec after '->'", span = item.span}, false
            }
            if form.items[i+1].kind == .Vector && vector_is_named_returns(form.items[i+1]) {
                append(&expanded.items, clone_cst_form(form.items[i+1]))
                i += 2
                continue
            }
            _, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], i+1)
            if !ok_type {
                delete_cst_form(&expanded)
                return CST_Form{}, err_type, false
            }
            for type_item in form.items[i+1:next_i] {
                append(&expanded.items, clone_cst_form(type_item))
            }
            i = next_i
            continue
        }
        if i <= params_index {
            append(&expanded.items, clone_cst_form(item))
        } else {
            child, err_child, ok_child := macroexpand_cst_form_with_macros(item, macros)
            if !ok_child {
                delete_cst_form(&expanded)
                return CST_Form{}, err_child, false
            }
            append(&expanded.items, child)
        }
        i += 1
    }
    return expanded, Compile_Error{}, true
}

write_macro_form_expanded :: proc(builder: ^strings.Builder, form: CST_Form, macros: []User_Macro) -> (Compile_Error, bool) {
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if user_macro, ok_user := find_user_macro(macros, form.items[0].text); ok_user {
            expanded, err_user, ok_user_expand := expand_user_macro_call(user_macro, form, macros)
            if !ok_user_expand {
                return err_user, false
            }
            defer delete_cst_form(&expanded)
            return write_macro_form_expanded(builder, expanded, macros)
        }
        switch builtin_macro_kind(form.items[0].text) {
        case .With_Allocator:
            expanded, err_expand, ok_expand := macroexpand_with_allocator(form, macros)
            if !ok_expand {
                return err_expand, false
            }
            defer delete(expanded.output)
            defer delete(expanded.source_map)
            write_macro_expanded_output(builder, expanded.output)
            return Compile_Error{}, true
        case .With_Temp_Allocator:
            expanded, err_expand, ok_expand := macroexpand_with_temp_allocator(form, macros)
            if !ok_expand {
                return err_expand, false
            }
            defer delete(expanded.output)
            defer delete(expanded.source_map)
            write_macro_expanded_output(builder, expanded.output)
            return Compile_Error{}, true
        case .When:
            expanded_when, err_expand, ok_expand := expand_when_form(form)
            if !ok_expand {
                return err_expand, false
            }
            defer delete_borrowed_cst_form(&expanded_when)
            return write_macro_form_expanded(builder, expanded_when, macros)
        case .Thread_First:
            expanded, err_expand, ok_expand := expand_thread_form(form, false)
            if !ok_expand {
                return err_expand, false
            }
            defer delete_borrowed_cst_form(&expanded)
            return write_macro_form_expanded(builder, expanded, macros)
        case .Thread_Last:
            expanded, err_expand, ok_expand := expand_thread_form(form, true)
            if !ok_expand {
                return err_expand, false
            }
            defer delete_borrowed_cst_form(&expanded)
            return write_macro_form_expanded(builder, expanded, macros)
        case .When_Let:
            expanded, err_expand, ok_expand := macroexpand_when_let(form, macros)
            if !ok_expand {
                return err_expand, false
            }
            defer delete(expanded.output)
            defer delete(expanded.source_map)
            write_macro_expanded_output(builder, expanded.output)
            return Compile_Error{}, true
        case .If_Let:
            expanded, err_expand, ok_expand := macroexpand_if_let(form, macros)
            if !ok_expand {
                return err_expand, false
            }
            defer delete(expanded.output)
            defer delete(expanded.source_map)
            write_macro_expanded_output(builder, expanded.output)
            return Compile_Error{}, true
        case .When_Ok:
            expanded, err_expand, ok_expand := macroexpand_when_ok(form, macros)
            if !ok_expand {
                return err_expand, false
            }
            defer delete(expanded.output)
            defer delete(expanded.source_map)
            write_macro_expanded_output(builder, expanded.output)
            return Compile_Error{}, true
        case .If_Ok:
            expanded, err_expand, ok_expand := macroexpand_if_ok(form, macros)
            if !ok_expand {
                return err_expand, false
            }
            defer delete(expanded.output)
            defer delete(expanded.source_map)
            write_macro_expanded_output(builder, expanded.output)
            return Compile_Error{}, true
        case .None:
        }
    }

    #partial switch form.kind {
    case .List:
        if len(form.items) == 3 &&
           form.items[0].kind == .Symbol &&
           form.items[0].text == "__kvist_field" &&
           form.items[2].kind == .Symbol {
            err_receiver, ok_receiver := write_macro_form_expanded(builder, form.items[1], macros)
            if !ok_receiver {
                return err_receiver, false
            }
            strings.write_byte(builder, '.')
            strings.write_string(builder, form.items[2].text)
            return Compile_Error{}, true
        }
        if len(form.items) == 2 &&
           form.items[0].kind == .Symbol &&
           len(form.items[0].text) > 1 &&
           form.items[0].text[0] == '.' {
            err_receiver, ok_receiver := write_macro_form_expanded(builder, form.items[1], macros)
            if !ok_receiver {
                return err_receiver, false
            }
            strings.write_string(builder, form.items[0].text)
            return Compile_Error{}, true
        }
        strings.write_byte(builder, '(')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            err_item, ok_item := write_macro_form_expanded(builder, item, macros)
            if !ok_item {
                return err_item, false
            }
        }
        strings.write_byte(builder, ')')
    case .Vector:
        strings.write_byte(builder, '[')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            err_item, ok_item := write_macro_form_expanded(builder, item, macros)
            if !ok_item {
                return err_item, false
            }
        }
        strings.write_byte(builder, ']')
    case .Brace:
        strings.write_byte(builder, '{')
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            err_item, ok_item := write_macro_form_expanded(builder, item, macros)
            if !ok_item {
                return err_item, false
            }
        }
        strings.write_byte(builder, '}')
    case .Set:
        strings.write_string(builder, "#{")
        for item, idx in form.items {
            if idx > 0 {
                strings.write_byte(builder, ' ')
            }
            err_item, ok_item := write_macro_form_expanded(builder, item, macros)
            if !ok_item {
                return err_item, false
            }
        }
        strings.write_byte(builder, '}')
    case .Symbol, .Keyword, .String, .Number, .Bool, .Nil:
        strings.write_string(builder, form.text)
    }
    return Compile_Error{}, true
}

macro_form_text :: proc(form: CST_Form) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    write_macro_form(&builder, form)
    return strings.clone(strings.to_string(builder))
}

macro_output_line_count :: proc(output: string) -> int {
    if len(output) == 0 {
        return 1
    }
    lines := 1
    for ch in output {
        if ch == '\n' {
            lines += 1
        }
    }
    if output[len(output)-1] == '\n' {
        lines -= 1
    }
    if lines < 1 {
        return 1
    }
    return lines
}

macroexpand_with_allocator :: proc(form: CST_Form, macros: []User_Macro) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 || form.items[1].kind != .Vector {
        return result, Compile_Error{message = "with-allocator expects binding vector and body", span = form.span}, false
    }
    binding := form.items[1]
    if len(binding.items) != 2 || binding.items[0].kind != .Symbol {
        return result, Compile_Error{message = "with-allocator expects [name allocator] binding", span = binding.span}, false
    }

    allocator_name := binding.items[0].text
    expanded_allocator_expr, err_allocator_expr, ok_allocator_expr := macroexpand_cst_form_with_macros(binding.items[1], macros)
    if !ok_allocator_expr {
        return result, err_allocator_expr, false
    }
    defer delete_cst_form(&expanded_allocator_expr)
    allocator_expr := macro_form_text(expanded_allocator_expr)
    defer delete(allocator_expr)

    e := Macro_Expander{builder = strings.builder_make(), line = 1, source_map = &result.source_map}
    defer strings.builder_destroy(&e.builder)

    macro_emit_line(&e, "(do", form.span)
    macro_emit_line(&e, fmt.tprintf("  (let [%s %s", allocator_name, allocator_expr), binding.items[1].span)
    macro_emit_line(&e, "        kvist-old-allocator-1 context.allocator]", form.span)
    macro_emit_line(&e, fmt.tprintf("    (set! context.allocator %s)", allocator_name), form.span)
    macro_emit_line(&e, "    (defer (do", form.span)
    macro_emit_line(&e, "      (set! context.allocator kvist-old-allocator-1)))", form.span)
    body := form.items[2:]
    for item, idx in body {
        suffix := ""
        if idx == len(body)-1 {
            suffix = "))"
        }
        err_body, ok_body := macro_emit_body_form(&e, item, macros, suffix)
        if !ok_body {
            return result, err_body, false
        }
    }

    result.output = strings.clone(strings.to_string(e.builder))
    return result, {}, true
}

macroexpand_with_temp_allocator :: proc(form: CST_Form, macros: []User_Macro) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 || form.items[1].kind != .Vector {
        return result, Compile_Error{message = "with-temp-allocator expects binding vector and body", span = form.span}, false
    }
    binding := form.items[1]
    if len(binding.items) != 1 || binding.items[0].kind != .Symbol {
        return result, Compile_Error{message = "with-temp-allocator expects [name] binding", span = binding.span}, false
    }

    allocator_name := binding.items[0].text

    e := Macro_Expander{builder = strings.builder_make(), line = 1, source_map = &result.source_map}
    defer strings.builder_destroy(&e.builder)

    macro_emit_line(&e, "(do", form.span)
    macro_emit_line(&e, "  (let [kvist-temp-scope-1 (runtime.default-temp-allocator-temp-begin)", form.span)
    macro_emit_line(&e, fmt.tprintf("        %s context.temp-allocator", allocator_name), form.span)
    macro_emit_line(&e, "        kvist-old-allocator-1 context.allocator]", form.span)
    macro_emit_line(&e, fmt.tprintf("    (set! context.allocator %s)", allocator_name), form.span)
    macro_emit_line(&e, "    (defer (do", form.span)
    macro_emit_line(&e, "      (set! context.allocator kvist-old-allocator-1)", form.span)
    macro_emit_line(&e, "      (runtime.default-temp-allocator-temp-end kvist-temp-scope-1)))", form.span)
    body := form.items[2:]
    for item, idx in body {
        suffix := ""
        if idx == len(body)-1 {
            suffix = "))"
        }
        err_body, ok_body := macro_emit_body_form(&e, item, macros, suffix)
        if !ok_body {
            return result, err_body, false
        }
    }

    result.output = strings.clone(strings.to_string(e.builder))
    return result, {}, true
}

macroexpand_when_let :: proc(form: CST_Form, macros: []User_Macro) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    expanded, err_expand, ok_expand := expand_when_let_form(form)
    if !ok_expand {
        return result, err_expand, false
    }
    defer delete_borrowed_cst_form(&expanded)
    return macroexpand_form_with_macros(expanded, macros)
}

macroexpand_if_let :: proc(form: CST_Form, macros: []User_Macro) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    expanded, err_expand, ok_expand := expand_if_let_form(form)
    if !ok_expand {
        return result, err_expand, false
    }
    defer delete_borrowed_cst_form(&expanded)
    return macroexpand_form_with_macros(expanded, macros)
}

macroexpand_when_ok :: proc(form: CST_Form, macros: []User_Macro) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    expanded, err_expand, ok_expand := expand_when_ok_form(form)
    if !ok_expand {
        return result, err_expand, false
    }
    defer delete_borrowed_cst_form(&expanded)
    return macroexpand_form_with_macros(expanded, macros)
}

macroexpand_if_ok :: proc(form: CST_Form, macros: []User_Macro) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    expanded, err_expand, ok_expand := expand_if_ok_form(form)
    if !ok_expand {
        return result, err_expand, false
    }
    defer delete_borrowed_cst_form(&expanded)
    return macroexpand_form_with_macros(expanded, macros)
}

macroexpand_form_with_macros :: proc(form: CST_Form, macros: []User_Macro) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if user_macro, ok_user := find_user_macro(macros, form.items[0].text); ok_user {
            expanded, err_user, ok_user_expand := expand_user_macro_call(user_macro, form, macros)
            if !ok_user_expand {
                return result, err_user, false
            }
            defer delete_cst_form(&expanded)
            return macroexpand_form_with_macros(expanded, macros)
        }
        switch builtin_macro_kind(form.items[0].text) {
        case .With_Allocator:
            return macroexpand_with_allocator(form, macros)
        case .With_Temp_Allocator:
            return macroexpand_with_temp_allocator(form, macros)
        case .When:
            expanded, err_expand, ok_expand := expand_when_form(form)
            if !ok_expand {
                return result, err_expand, false
            }
            defer delete_borrowed_cst_form(&expanded)
            return macroexpand_form_with_macros(expanded, macros)
        case .Thread_First:
            expanded, err_expand, ok_expand := expand_thread_form(form, false)
            if !ok_expand {
                return result, err_expand, false
            }
            defer delete_borrowed_cst_form(&expanded)
            return macroexpand_form_with_macros(expanded, macros)
        case .Thread_Last:
            expanded, err_expand, ok_expand := expand_thread_form(form, true)
            if !ok_expand {
                return result, err_expand, false
            }
            defer delete_borrowed_cst_form(&expanded)
            return macroexpand_form_with_macros(expanded, macros)
        case .When_Let:
            return macroexpand_when_let(form, macros)
        case .If_Let:
            return macroexpand_if_let(form, macros)
        case .When_Ok:
            return macroexpand_when_ok(form, macros)
        case .If_Ok:
            return macroexpand_if_ok(form, macros)
        case .None:
        }
    }
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    err_write, ok_write := write_macro_form_expanded(&builder, form, macros)
    if !ok_write {
        return result, err_write, false
    }
    strings.write_byte(&builder, '\n')
    result.output = strings.clone(strings.to_string(builder))
    append(&result.source_map, Source_Map_Entry{
        generated_start_line = 1,
        generated_end_line = macro_output_line_count(result.output),
        source_span = form.span,
    })
    return result, {}, true
}

macroexpand_form :: proc(form: CST_Form, anchor_path: string = ".") -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    previous_anchor := macro_eval_set_anchor(anchor_path)
    defer macro_eval_restore_anchor(previous_anchor)

    core_macros, err_core, ok_core := core_package_local_macros(anchor_path)
    if !ok_core {
        return result, err_core, false
    }
    defer {
        for i in 0..<len(core_macros) {
            delete_user_macro(&core_macros[i])
        }
        delete(core_macros)
    }
    return macroexpand_form_with_macros(form, core_macros[:])
}

macroexpand_source :: proc(source: string, anchor_path: string = ".") -> (output: string, err: Compile_Error, ok: bool) {
    result, err_result, ok_result := macroexpand_source_with_map(source, anchor_path)
    if !ok_result {
        return "", err_result, false
    }
    defer delete(result.source_map)
    return result.output, {}, true
}

macroexpand_source_with_map :: proc(source: string, anchor_path: string = ".") -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    result_allocator := context.allocator
    old_allocator := context.allocator
    temp_scope := runtime.default_temp_allocator_temp_begin()
    defer runtime.default_temp_allocator_temp_end(temp_scope)
    context.allocator = context.temp_allocator
    defer context.allocator = old_allocator

    form, err_form, ok_form := read_single_eval_form(source)
    if !ok_form {
        return result, clone_compile_error(err_form, result_allocator), false
    }
    temp_result, err_expand, ok_expand := macroexpand_form(form, anchor_path)
    if !ok_expand {
        return result, clone_compile_error(err_expand, result_allocator), false
    }
    result.output = strings.clone(temp_result.output, result_allocator)
    context.allocator = result_allocator
    for entry in temp_result.source_map {
        append(&result.source_map, entry)
    }
    return result, {}, true
}

macroexpand_top_level_form_with_macros :: proc(form: CST_Form, macros: []User_Macro) -> (expanded: [dynamic]CST_Form, err: Compile_Error, ok: bool) {
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if user_macro, ok_user := find_user_macro(macros, form.items[0].text); ok_user {
            forms_out, err_user, ok_user_expand := expand_user_macro_call_to_forms(user_macro, form, macros)
            if !ok_user_expand {
                return expanded, err_user, false
            }
            for form_out in forms_out {
                nested, err_nested, ok_nested := macroexpand_top_level_form_with_macros(form_out, macros)
                if !ok_nested {
                    for i in 0 ..< len(forms_out) {
                        delete_cst_form(&forms_out[i])
                    }
                    delete(forms_out)
                    return expanded, err_nested, false
                }
                for nested_form in nested {
                    append(&expanded, nested_form)
                }
                delete(nested)
            }
            for i in 0 ..< len(forms_out) {
                delete_cst_form(&forms_out[i])
            }
            delete(forms_out)
            return expanded, Compile_Error{}, true
        }
    }

    rewritten, err_expand, ok_expand := macroexpand_cst_form_with_macros(form, macros)
    if !ok_expand {
        return expanded, err_expand, false
    }
    append(&expanded, rewritten)
    return expanded, Compile_Error{}, true
}

macroexpand_builtin_runtime_form :: proc(form: CST_Form) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        switch builtin_macro_kind(form.items[0].text) {
        case .When:
            expanded_when, err_expand, ok_expand := expand_when_form(form)
            if !ok_expand {
                return CST_Form{}, err_expand, false
            }
            defer delete_borrowed_cst_form(&expanded_when)
            return macroexpand_builtin_runtime_form(expanded_when)
        case .Thread_First:
            expanded_thread, err_expand, ok_expand := expand_thread_form(form, false)
            if !ok_expand {
                return CST_Form{}, err_expand, false
            }
            defer delete_borrowed_cst_form(&expanded_thread)
            return macroexpand_builtin_runtime_form(expanded_thread)
        case .Thread_Last:
            expanded_thread, err_expand, ok_expand := expand_thread_form(form, true)
            if !ok_expand {
                return CST_Form{}, err_expand, false
            }
            defer delete_borrowed_cst_form(&expanded_thread)
            return macroexpand_builtin_runtime_form(expanded_thread)
        case .When_Let:
            expanded_when, err_expand, ok_expand := expand_when_let_form(form)
            if !ok_expand {
                return CST_Form{}, err_expand, false
            }
            defer delete_borrowed_cst_form(&expanded_when)
            return macroexpand_builtin_runtime_form(expanded_when)
        case .If_Let:
            expanded_if, err_expand, ok_expand := expand_if_let_form(form)
            if !ok_expand {
                return CST_Form{}, err_expand, false
            }
            defer delete_borrowed_cst_form(&expanded_if)
            return macroexpand_builtin_runtime_form(expanded_if)
        case .When_Ok:
            expanded_when, err_expand, ok_expand := expand_when_ok_form(form)
            if !ok_expand {
                return CST_Form{}, err_expand, false
            }
            defer delete_borrowed_cst_form(&expanded_when)
            return macroexpand_builtin_runtime_form(expanded_when)
        case .If_Ok:
            expanded_if, err_expand, ok_expand := expand_if_ok_form(form)
            if !ok_expand {
                return CST_Form{}, err_expand, false
            }
            defer delete_borrowed_cst_form(&expanded_if)
            return macroexpand_builtin_runtime_form(expanded_if)
        case .With_Allocator, .With_Temp_Allocator, .None:
        }
    }

    #partial switch form.kind {
    case .List, .Vector, .Brace, .Set:
        expanded = form
        expanded.items = nil
        for item in form.items {
            child, err_child, ok_child := macroexpand_builtin_runtime_form(item)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&expanded.items, child)
        }
        return expanded, Compile_Error{}, true
    case:
        return form, Compile_Error{}, true
    }
}

macroexpand_top_forms :: proc(forms: []CST_Top_Form, include_core_macros: bool = false, anchor_path: string = ".") -> (expanded: [dynamic]CST_Top_Form, macros: [dynamic]User_Macro, err: Compile_Error, ok: bool) {
    previous_anchor := macro_eval_set_anchor(anchor_path)
    defer macro_eval_restore_anchor(previous_anchor)

    if include_core_macros {
        initial_macros, err_core, ok_core := core_package_local_macros(anchor_path)
        if !ok_core {
            return expanded, macros, err_core, false
        }
        for macro_decl in initial_macros {
            append(&macros, macro_decl)
        }
        delete(initial_macros)
    }
    for top in forms {
        if is_defmacro_form(top.form) {
            macro_decl, err_macro, ok_macro := parse_user_macro_decl(top)
            if !ok_macro {
                return expanded, macros, err_macro, false
            }
            append(&macros, macro_decl)
        }
    }
    for top in forms {
        if is_defmacro_form(top.form) {
            continue
        }
        expanded_forms, err_expand, ok_expand := macroexpand_top_level_form_with_macros(top.form, macros[:])
        if !ok_expand {
            return expanded, macros, err_expand, false
        }
        for i in 0 ..< len(expanded_forms) {
            rewritten := &expanded_forms[i]
            if is_defmacro_form(rewritten^) {
                macro_decl, err_macro, ok_macro := parse_user_macro_decl(CST_Top_Form{
                    form      = rewritten^,
                    doc_lines = top.doc_lines,
                    source    = top.source,
                })
                if !ok_macro {
                    delete_cst_form_slice(&expanded_forms)
                    return expanded, macros, err_macro, false
                }
                append(&macros, macro_decl)
                delete_cst_form(rewritten)
                continue
            }
            append(&expanded, CST_Top_Form{
                form      = rewritten^,
                doc_lines = clone_string_slice(top.doc_lines[:]),
                source    = strings.clone(top.source),
            })
            rewritten^ = CST_Form{}
        }
        delete(expanded_forms)
    }
    return expanded, macros, Compile_Error{}, true
}

macroexpand_program_source_with_map :: proc(source: string) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
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
    expanded, _, err_expand, ok_expand := macroexpand_top_forms(forms[:], true)
    if !ok_expand {
        return result, clone_compile_error(err_expand, result_allocator), false
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    line := 1
    for top in expanded {
        text := macro_form_text(top.form)
        defer delete(text)
        strings.write_string(&builder, text)
        strings.write_byte(&builder, '\n')
        append(&result.source_map, Source_Map_Entry{
            generated_start_line = line,
            generated_end_line   = line + macro_output_line_count(text) - 1,
            source_span          = top.form.span,
        })
        line += macro_output_line_count(text)
    }
    result.output = strings.clone(strings.to_string(builder), result_allocator)
    context.allocator = result_allocator
    copied: [dynamic]Source_Map_Entry
    for entry in result.source_map {
        append(&copied, entry)
    }
    result.source_map = copied
    return result, Compile_Error{}, true
}

macroexpand_eval_source_with_map :: proc(source, eval_source: string, anchor_path: string = ".") -> (result: Emit_Result, err: Compile_Error, ok: bool) {
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
    _, macros, err_expand, ok_expand := macroexpand_top_forms(forms[:], true, anchor_path)
    if !ok_expand {
        return result, clone_compile_error(err_expand, result_allocator), false
    }
    eval_form, err_eval, ok_eval := read_single_eval_form(eval_source)
    if !ok_eval {
        return result, clone_compile_error(err_eval, result_allocator), false
    }
    previous_anchor := macro_eval_set_anchor(anchor_path)
    temp_result, err_macro, ok_macro := macroexpand_form_with_macros(eval_form, macros[:])
    macro_eval_restore_anchor(previous_anchor)
    if !ok_macro {
        return result, clone_compile_error(err_macro, result_allocator), false
    }
    result.output = strings.clone(temp_result.output, result_allocator)
    context.allocator = result_allocator
    for entry in temp_result.source_map {
        append(&result.source_map, entry)
    }
    return result, Compile_Error{}, true
}
