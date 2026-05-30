package kvist

import "core:fmt"
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

Macro_Value_Kind :: enum {
    Nil,
    Bool,
    Int,
    String,
    Form,
    Forms,
}

Macro_Value :: struct {
    kind:         Macro_Value_Kind,
    bool_value:   bool,
    int_value:    int,
    string_value: string,
    form:         CST_Form,
    forms:        [dynamic]CST_Form,
}

Macro_Binding :: struct {
    name:  string,
    value: Macro_Value,
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

macro_nil_value :: proc() -> Macro_Value {
    return Macro_Value{kind = .Nil}
}

macro_bool_value :: proc(value: bool) -> Macro_Value {
    return Macro_Value{kind = .Bool, bool_value = value}
}

macro_int_value :: proc(value: int) -> Macro_Value {
    return Macro_Value{kind = .Int, int_value = value}
}

macro_string_value :: proc(value: string) -> Macro_Value {
    return Macro_Value{kind = .String, string_value = value}
}

macro_form_value :: proc(form: CST_Form) -> Macro_Value {
    return Macro_Value{kind = .Form, form = form}
}

macro_forms_value :: proc(forms: []CST_Form) -> Macro_Value {
    out: [dynamic]CST_Form
    for form in forms {
        append(&out, form)
    }
    return Macro_Value{kind = .Forms, forms = out}
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
        return false
    }
    switch a.kind {
    case .Nil:
        return true
    case .Bool:
        return a.bool_value == b.bool_value
    case .Int:
        return a.int_value == b.int_value
    case .String:
        return a.string_value == b.string_value
    case .Form:
        return macro_form_text(a.form) == macro_form_text(b.form)
    case .Forms:
        if len(a.forms) != len(b.forms) {
            return false
        }
        for form, idx in a.forms {
            if macro_form_text(form) != macro_form_text(b.forms[idx]) {
                return false
            }
        }
        return true
    }
    return false
}

macro_value_to_form :: proc(value: Macro_Value, span: Span) -> (CST_Form, Compile_Error, bool) {
    switch value.kind {
    case .Form:
        return value.form, Compile_Error{}, true
    case .Nil:
        return CST_Form{kind = .Nil, text = "nil", span = span}, Compile_Error{}, true
    case .Bool:
        if value.bool_value {
            return CST_Form{kind = .Bool, text = "true", span = span}, Compile_Error{}, true
        }
        return CST_Form{kind = .Bool, text = "false", span = span}, Compile_Error{}, true
    case .Int:
        return CST_Form{kind = .Number, text = macro_int_text(value.int_value), span = span}, Compile_Error{}, true
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
            append(&out, form)
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

macro_value_to_string :: proc(value: Macro_Value, span: Span) -> (string, Compile_Error, bool) {
    switch value.kind {
    case .String:
        return value.string_value, Compile_Error{}, true
    case .Form:
        #partial switch value.form.kind {
        case .Symbol:
            return value.form.text, Compile_Error{}, true
        case .Keyword:
            if len(value.form.text) > 0 && value.form.text[0] == ':' {
                return value.form.text[1:], Compile_Error{}, true
            }
            return value.form.text, Compile_Error{}, true
        case .String:
            return unquote_string(value.form.text), Compile_Error{}, true
        case:
            return "", Compile_Error{message = "expected string-like macro value", span = span}, false
        }
    case .Nil:
        return "", Compile_Error{}, true
    case .Int:
        return macro_int_text(value.int_value), Compile_Error{}, true
    case .Bool:
        if value.bool_value {
            return "true", Compile_Error{}, true
        }
        return "false", Compile_Error{}, true
    case .Forms:
        return "", Compile_Error{message = "expected string-like macro value", span = span}, false
    }
    return "", Compile_Error{message = "expected string-like macro value", span = span}, false
}

macro_lookup_binding :: proc(bindings: []Macro_Binding, name: string) -> (Macro_Value, bool) {
    for i := len(bindings) - 1; i >= 0; i -= 1 {
        if bindings[i].name == name {
            return bindings[i].value, true
        }
    }
    return Macro_Value{}, false
}

is_defmacro_form :: proc(form: CST_Form) -> bool {
    return form.kind == .List && len(form.items) > 0 &&
        form.items[0].kind == .Symbol &&
        (form.items[0].text == "defmacro" || form.items[0].text == "defmacro-")
}

core_macro_decl_from_source :: proc(source: string) -> (User_Macro, Compile_Error, bool) {
    forms, err_forms, ok_forms := read_top_forms(source)
    if !ok_forms {
        return User_Macro{}, err_forms, false
    }
    if len(forms) != 1 {
        return User_Macro{}, Compile_Error{message = "internal core macro definition must contain exactly one form"}, false
    }
    return parse_user_macro_decl(forms[0])
}

core_package_local_macros :: proc() -> ([]User_Macro, Compile_Error, bool) {
    sources := []string{
        `(defmacro when-let [binding & body]
  (list (quote let)
        (vector (vector (first binding) (nth binding 1))
                (nth binding 2))
        (list (quote when)
              (nth binding 1)
              (list (quote do) body))))`,
        `(defmacro if-let [binding then else]
  (list (quote let)
        (vector (vector (first binding) (nth binding 1))
                (nth binding 2))
        (list (quote if)
              (nth binding 1)
              then
              else)))`,
        `(defmacro when-ok [binding & body]
  (list (quote let)
        (vector (vector (first binding) (nth binding 1))
                (nth binding 2))
        (list (quote when)
              (list (quote ==) (nth binding 1) (brace))
              (list (quote do) body))))`,
        `(defmacro if-ok [binding then else]
  (list (quote let)
        (vector (vector (first binding) (nth binding 1))
                (nth binding 2))
        (list (quote if)
              (list (quote ==) (nth binding 1) (brace))
              then
              else)))`,
    }

    macros: [dynamic]User_Macro
    for source in sources {
        macro_decl, err_macro, ok_macro := core_macro_decl_from_source(source)
        if !ok_macro {
            return nil, err_macro, false
        }
        append(&macros, macro_decl)
    }
    return macros[:], Compile_Error{}, true
}

builtin_macro_kind :: proc(head: string) -> Builtin_Macro_Kind {
    switch head {
    case "with-allocator":
        return .With_Allocator
    case "with-temp-allocator":
        return .With_Temp_Allocator
    case "with-delete":
        return .With_Delete
    case "->":
        return .Thread_First
    case "->>":
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
    if len(binding.items) != 3 || binding.items[0].kind != .Symbol || binding.items[1].kind != .Symbol {
        return bindings, condition, Compile_Error{message = fmt.tprintf("%s expects %s binding", name, binding_label), span = binding.span}, false
    }

    destructure := CST_Form{kind = .Vector, span = binding.span}
    append(&destructure.items, binding.items[0])
    append(&destructure.items, binding.items[1])

    bindings = CST_Form{kind = .Vector, span = binding.span}
    append(&bindings.items, destructure)
    append(&bindings.items, binding.items[2])
    condition = binding.items[1]
    return bindings, condition, {}, true
}

expand_when_let_form :: proc(form: CST_Form) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    bindings, condition, err_bind, ok_bind := parse_binding_condition_macro(form, "when-let", "[value bool expr]")
    if !ok_bind {
        return expanded, err_bind, false
    }
    when_form := CST_Form{kind = .List, span = form.span}
    append(&when_form.items, macro_symbol("when", form.items[0].span))
    append(&when_form.items, condition)
    for item in form.items[2:] {
        append(&when_form.items, item)
    }

    expanded = CST_Form{kind = .List, span = form.span}
    append(&expanded.items, macro_symbol("let", form.items[0].span))
    append(&expanded.items, bindings)
    append(&expanded.items, when_form)
    return expanded, {}, true
}

expand_if_let_form :: proc(form: CST_Form) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) != 4 {
        return expanded, Compile_Error{message = "if-let expects [value bool expr], then, and else", span = form.span}, false
    }
    bindings, condition, err_bind, ok_bind := parse_binding_condition_macro(form, "if-let", "[value bool expr]")
    if !ok_bind {
        return expanded, err_bind, false
    }

    if_form := CST_Form{kind = .List, span = form.span}
    append(&if_form.items, macro_symbol("if", form.items[0].span))
    append(&if_form.items, condition)
    append(&if_form.items, form.items[2])
    append(&if_form.items, form.items[3])

    expanded = CST_Form{kind = .List, span = form.span}
    append(&expanded.items, macro_symbol("let", form.items[0].span))
    append(&expanded.items, bindings)
    append(&expanded.items, if_form)
    return expanded, {}, true
}

expand_when_ok_form :: proc(form: CST_Form) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    bindings, condition, err_bind, ok_bind := parse_binding_condition_macro(form, "when-ok", "[value err expr]")
    if !ok_bind {
        return expanded, err_bind, false
    }

    when_form := CST_Form{kind = .List, span = form.span}
    append(&when_form.items, macro_symbol("when", form.items[0].span))
    append(&when_form.items, macro_error_success_condition(condition))
    for item in form.items[2:] {
        append(&when_form.items, item)
    }

    expanded = CST_Form{kind = .List, span = form.span}
    append(&expanded.items, macro_symbol("let", form.items[0].span))
    append(&expanded.items, bindings)
    append(&expanded.items, when_form)
    return expanded, {}, true
}

expand_if_ok_form :: proc(form: CST_Form) -> (expanded: CST_Form, err: Compile_Error, ok: bool) {
    if len(form.items) != 4 {
        return expanded, Compile_Error{message = "if-ok expects [value err expr], then, and else", span = form.span}, false
    }
    bindings, condition, err_bind, ok_bind := parse_binding_condition_macro(form, "if-ok", "[value err expr]")
    if !ok_bind {
        return expanded, err_bind, false
    }

    if_form := CST_Form{kind = .List, span = form.span}
    append(&if_form.items, macro_symbol("if", form.items[0].span))
    append(&if_form.items, macro_error_success_condition(condition))
    append(&if_form.items, form.items[2])
    append(&if_form.items, form.items[3])

    expanded = CST_Form{kind = .List, span = form.span}
    append(&expanded.items, macro_symbol("let", form.items[0].span))
    append(&expanded.items, bindings)
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
    if len(form.items) > 4 && form.items[2].kind == .String {
        doc_lines = append_doc_lines(doc_lines[:], doc_lines_from_string(unquote_string(form.items[2].text))[:])
        params_index = 3
    }
    if params_index >= len(form.items) || form.items[params_index].kind != .Vector {
        return macro_decl, Compile_Error{message = "defmacro expects a parameter vector", span = form.span}, false
    }
    params, err_params, ok_params := parse_macro_param_vector(form.items[params_index])
    if !ok_params {
        return macro_decl, err_params, false
    }
    if params_index+1 >= len(form.items) {
        return macro_decl, Compile_Error{message = "defmacro body is empty", span = form.span}, false
    }
    body: [dynamic]CST_Form
    for item in form.items[params_index+1:] {
        append(&body, item)
    }
    return User_Macro{
        name      = form.items[1].text,
        doc_lines = doc_lines,
        params    = params,
        body      = body,
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

invoke_user_macro_value :: proc(macro_decl: User_Macro, call: CST_Form, macros: []User_Macro) -> (Macro_Value, Compile_Error, bool) {
    bindings, err_bindings, ok_bindings := macro_collect_call_bindings(macro_decl, call)
    if !ok_bindings {
        return Macro_Value{}, err_bindings, false
    }
    return macro_eval_sequence(macro_decl.body[:], macros, bindings[:])
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
            forms, err_forms, ok_forms := macro_value_to_forms(value, arg.span)
            if !ok_forms {
                return nil, err_forms, false
            }
            for item in forms {
                append(&rest_out, item)
            }
        }
        append(&out, Macro_Binding{name = macro_decl.params.rest_name, value = macro_forms_value(rest_out[:])})
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
            return Macro_Value{}, err_next, false
        }
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
        forms, err_forms, ok_forms := macro_value_to_forms(value, arg.span)
        if !ok_forms {
            return Macro_Value{}, err_forms, false
        }
        for item in forms {
            append(&out.items, item)
        }
    }
    return macro_form_value(out), Compile_Error{}, true
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
            return macro_value_to_form(value, form.items[1].span)
        }
        inner, err_inner, ok_inner := macro_quasiquote_form(form.items[1], macros, bindings, depth-1)
        if !ok_inner {
            return CST_Form{}, err_inner, false
        }
        out := CST_Form{kind = .List, span = form.span}
        append(&out.items, form.items[0])
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
        append(&out.items, form.items[0])
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
            append(&out.items, form.items[0])
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
                forms, err_forms, ok_forms := macro_value_to_forms(value, item.items[1].span)
                if !ok_forms {
                    return CST_Form{}, err_forms, false
                }
                for expanded in forms {
                    append(&out.items, expanded)
                }
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
                forms, err_forms, ok_forms := macro_value_to_forms(value, item.items[1].span)
                if !ok_forms {
                    return CST_Form{}, err_forms, false
                }
                for expanded in forms {
                    append(&out.items, expanded)
                }
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
                forms, err_forms, ok_forms := macro_value_to_forms(value, item.items[1].span)
                if !ok_forms {
                    return CST_Form{}, err_forms, false
                }
                for expanded in forms {
                    append(&out.items, expanded)
                }
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
                forms, err_forms, ok_forms := macro_value_to_forms(value, item.items[1].span)
                if !ok_forms {
                    return CST_Form{}, err_forms, false
                }
                for expanded in forms {
                    append(&out.items, expanded)
                }
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
        return form, Compile_Error{}, true
    }
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
        if !ok_parsed {
            return Macro_Value{}, Compile_Error{message = "macro evaluator only supports integer numeric literals", span = form.span}, false
        }
        value = parsed
        return macro_int_value(value), Compile_Error{}, true
    case .String:
        return macro_string_value(unquote_string(form.text)), Compile_Error{}, true
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
                return macro_form_value(quoted), Compile_Error{}, true
            case "do":
                return macro_eval_sequence(form.items[1:], macros, bindings)
            case "if":
                if len(form.items) != 4 {
                    return Macro_Value{}, Compile_Error{message = "if expects condition, then, and else", span = form.span}, false
                }
                cond_value, err_cond, ok_cond := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_cond {
                    return Macro_Value{}, err_cond, false
                }
                if macro_truthy(cond_value) {
                    return macro_eval_expr(form.items[2], macros, bindings)
                }
                return macro_eval_expr(form.items[3], macros, bindings)
            case "let":
                if len(form.items) < 3 || form.items[1].kind != .Vector {
                    return Macro_Value{}, Compile_Error{message = "macro let expects binding vector and body", span = form.span}, false
                }
                local: [dynamic]Macro_Binding
                for binding in bindings {
                    append(&local, binding)
                }
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
                return macro_eval_sequence(form.items[2:], macros, local[:])
            case "list":
                return macro_eval_list_builder(.List, form, macros, bindings)
            case "vector":
                return macro_eval_list_builder(.Vector, form, macros, bindings)
            case "brace":
                return macro_eval_list_builder(.Brace, form, macros, bindings)
            case "first":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "first expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                forms, err_forms, ok_forms := macro_list_from_value(value, form.items[1].span)
                if !ok_forms {
                    return Macro_Value{}, err_forms, false
                }
                if len(forms) == 0 {
                    return macro_nil_value(), Compile_Error{}, true
                }
                return macro_form_value(forms[0]), Compile_Error{}, true
            case "rest":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "rest expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                forms, err_forms, ok_forms := macro_list_from_value(value, form.items[1].span)
                if !ok_forms {
                    return Macro_Value{}, err_forms, false
                }
                if len(forms) <= 1 {
                    return macro_forms_value(nil), Compile_Error{}, true
                }
                return macro_forms_value(forms[1:]), Compile_Error{}, true
            case "nth":
                if len(form.items) != 3 {
                    return Macro_Value{}, Compile_Error{message = "nth expects sequence and index", span = form.span}, false
                }
                seq_value, err_seq, ok_seq := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_seq {
                    return Macro_Value{}, err_seq, false
                }
                forms, err_forms, ok_forms := macro_list_from_value(seq_value, form.items[1].span)
                if !ok_forms {
                    return Macro_Value{}, err_forms, false
                }
                index_value, err_index, ok_index := macro_eval_expr(form.items[2], macros, bindings)
                if !ok_index {
                    return Macro_Value{}, err_index, false
                }
                if index_value.kind != .Int {
                    return Macro_Value{}, Compile_Error{message = "nth index must be an integer", span = form.items[2].span}, false
                }
                if index_value.int_value < 0 || index_value.int_value >= len(forms) {
                    return macro_nil_value(), Compile_Error{}, true
                }
                return macro_form_value(forms[index_value.int_value]), Compile_Error{}, true
            case "count":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "count expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
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
            case "concat":
                out: [dynamic]CST_Form
                for arg in form.items[1:] {
                    value, err_value, ok_value := macro_eval_expr(arg, macros, bindings)
                    if !ok_value {
                        return Macro_Value{}, err_value, false
                    }
                    forms, err_forms, ok_forms := macro_value_to_forms(value, arg.span)
                    if !ok_forms {
                        return Macro_Value{}, err_forms, false
                    }
                    for item in forms {
                        append(&out, item)
                    }
                }
                return macro_forms_value(out[:]), Compile_Error{}, true
            case "forms":
                out: [dynamic]CST_Form
                for arg in form.items[1:] {
                    value, err_value, ok_value := macro_eval_expr(arg, macros, bindings)
                    if !ok_value {
                        return Macro_Value{}, err_value, false
                    }
                    forms, err_forms, ok_forms := macro_value_to_forms(value, arg.span)
                    if !ok_forms {
                        return Macro_Value{}, err_forms, false
                    }
                    for item in forms {
                        append(&out, item)
                    }
                }
                return macro_forms_value(out[:]), Compile_Error{}, true
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
                        return Macro_Value{}, err_text, false
                    }
                    strings.write_string(&builder, text)
                }
                return macro_string_value(strings.clone(strings.to_string(builder))), Compile_Error{}, true
            case "symbol":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "symbol expects one string argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                if value.kind != .String {
                    return Macro_Value{}, Compile_Error{message = "symbol expects one string argument", span = form.items[1].span}, false
                }
                return macro_form_value(CST_Form{kind = .Symbol, text = value.string_value, span = form.span}), Compile_Error{}, true
            case "keyword":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "keyword expects one string argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                if value.kind != .String {
                    return Macro_Value{}, Compile_Error{message = "keyword expects one string argument", span = form.items[1].span}, false
                }
                return macro_form_value(CST_Form{kind = .Keyword, text = fmt.tprintf(":%s", value.string_value), span = form.span}), Compile_Error{}, true
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
                    return Macro_Value{}, err_single, false
                }
                #partial switch single.kind {
                case .Symbol:
                    return macro_string_value(single.text), Compile_Error{}, true
                case .Keyword:
                    if len(single.text) > 0 && single.text[0] == ':' {
                        return macro_string_value(single.text[1:]), Compile_Error{}, true
                    }
                    return macro_string_value(single.text), Compile_Error{}, true
                case:
                    return Macro_Value{}, Compile_Error{message = "name expects one symbol or keyword", span = form.items[1].span}, false
                }
            case "=":
                if len(form.items) != 3 {
                    return Macro_Value{}, Compile_Error{message = "= expects two arguments", span = form.span}, false
                }
                left, err_left, ok_left := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_left {
                    return Macro_Value{}, err_left, false
                }
                right, err_right, ok_right := macro_eval_expr(form.items[2], macros, bindings)
                if !ok_right {
                    return Macro_Value{}, err_right, false
                }
                return macro_bool_value(macro_value_equal(left, right)), Compile_Error{}, true
            case "form?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "form? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                return macro_bool_value(value.kind == .Form), Compile_Error{}, true
            case "vector?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "vector? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
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
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .Keyword), Compile_Error{}, true
            case "string?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "string? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
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
                if value.kind == .Int {
                    return macro_bool_value(true), Compile_Error{}, true
                }
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .Number), Compile_Error{}, true
            case "bool?":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "bool? expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                if value.kind == .Bool {
                    return macro_bool_value(true), Compile_Error{}, true
                }
                if value.kind != .Form {
                    return macro_bool_value(false), Compile_Error{}, true
                }
                return macro_bool_value(value.form.kind == .Bool), Compile_Error{}, true
            case "text":
                if len(form.items) != 2 {
                    return Macro_Value{}, Compile_Error{message = "text expects one argument", span = form.span}, false
                }
                value, err_value, ok_value := macro_eval_expr(form.items[1], macros, bindings)
                if !ok_value {
                    return Macro_Value{}, err_value, false
                }
                if value.kind == .String {
                    return macro_string_value(value.string_value), Compile_Error{}, true
                }
                if value.kind == .Int {
                    return macro_string_value(macro_int_text(value.int_value)), Compile_Error{}, true
                }
                if value.kind == .Bool {
                    if value.bool_value {
                        return macro_string_value("true"), Compile_Error{}, true
                    }
                    return macro_string_value("false"), Compile_Error{}, true
                }
                if value.kind == .Nil {
                    return macro_string_value("nil"), Compile_Error{}, true
                }
                if value.kind == .Form {
                    #partial switch value.form.kind {
                    case .String:
                        return macro_string_value(unquote_string(value.form.text)), Compile_Error{}, true
                    case .Symbol:
                        return macro_string_value(value.form.text), Compile_Error{}, true
                    case .Keyword:
                        if len(value.form.text) > 0 && value.form.text[0] == ':' {
                            return macro_string_value(value.form.text[1:]), Compile_Error{}, true
                        }
                        return macro_string_value(value.form.text), Compile_Error{}, true
                    case .Number, .Bool, .Nil:
                        return macro_string_value(value.form.text), Compile_Error{}, true
                    case:
                    }
                }
                return Macro_Value{}, Compile_Error{message = "text expects a scalar literal, symbol, or keyword", span = form.items[1].span}, false
            }
        }
        if head.kind == .Symbol {
            if user_macro, ok_user := find_user_macro(macros, head.text); ok_user {
                local_bindings, err_bindings, ok_bindings := macro_collect_eval_call_bindings(user_macro, form, macros, bindings)
                if !ok_bindings {
                    return Macro_Value{}, err_bindings, false
                }
                return macro_eval_sequence(user_macro.body[:], macros, local_bindings[:])
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
    expanded, err_form, ok_form := macro_value_to_form(value, call.span)
    if !ok_form {
        return CST_Form{}, err_form, false
    }
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
    return macro_value_to_forms(value, call.span)
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
            if user_macro, ok_user := find_user_macro(macros, form.items[0].text); ok_user {
                expanded, err_user, ok_user_expand := expand_user_macro_call(user_macro, form, macros)
                if !ok_user_expand {
                    return CST_Form{}, err_user, false
                }
                return macroexpand_cst_form_with_macros(expanded, macros)
            }
        }
        expanded = form
        expanded.items = nil
        for item in form.items {
            child, err_child, ok_child := macroexpand_cst_form_with_macros(item, macros)
            if !ok_child {
                return CST_Form{}, err_child, false
            }
            append(&expanded.items, child)
        }
        return expanded, Compile_Error{}, true
    case .Vector, .Brace, .Set:
        expanded = form
        expanded.items = nil
        for item in form.items {
            child, err_child, ok_child := macroexpand_cst_form_with_macros(item, macros)
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

write_macro_form_expanded :: proc(builder: ^strings.Builder, form: CST_Form, macros: []User_Macro) -> (Compile_Error, bool) {
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if user_macro, ok_user := find_user_macro(macros, form.items[0].text); ok_user {
            expanded, err_user, ok_user_expand := expand_user_macro_call(user_macro, form, macros)
            if !ok_user_expand {
                return err_user, false
            }
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
        case .With_Delete:
            expanded, err_expand, ok_expand := macroexpand_with_delete(form, macros)
            if !ok_expand {
                return err_expand, false
            }
            defer delete(expanded.output)
            defer delete(expanded.source_map)
            write_macro_expanded_output(builder, expanded.output)
            return Compile_Error{}, true
        case .Thread_First:
            expanded, err_expand, ok_expand := expand_thread_form(form, false)
            if !ok_expand {
                return err_expand, false
            }
            return write_macro_form_expanded(builder, expanded, macros)
        case .Thread_Last:
            expanded, err_expand, ok_expand := expand_thread_form(form, true)
            if !ok_expand {
                return err_expand, false
            }
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

macroexpand_with_delete :: proc(form: CST_Form, macros: []User_Macro) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    if len(form.items) < 3 || form.items[1].kind != .Vector {
        return result, Compile_Error{message = "with-delete expects binding vector and body", span = form.span}, false
    }
    binding := form.items[1]
    if len(binding.items) < 2 || len(binding.items)%2 != 0 {
        return result, Compile_Error{message = "with-delete expects [name value ...] bindings", span = binding.span}, false
    }

    e := Macro_Expander{builder = strings.builder_make(), line = 1, source_map = &result.source_map}
    defer strings.builder_destroy(&e.builder)

    macro_emit_line(&e, "(do", form.span)
    i := 0
    for i < len(binding.items) {
        if binding.items[i].kind != .Symbol {
            return result, Compile_Error{message = "with-delete binding name must be a symbol", span = binding.items[i].span}, false
        }
        binding_name := binding.items[i].text
        expanded_value_expr, err_value_expr, ok_value_expr := macroexpand_cst_form_with_macros(binding.items[i+1], macros)
        if !ok_value_expr {
            return result, err_value_expr, false
        }
        value_expr := macro_form_text(expanded_value_expr)
        defer delete(value_expr)
        suffix := ""
        if i+2 >= len(binding.items) {
            suffix = "]"
        }
        if i == 0 {
            macro_emit_line(&e, fmt.tprintf("  (let [%s %s%s", binding_name, value_expr, suffix), binding.items[i+1].span)
        } else {
            macro_emit_line(&e, fmt.tprintf("        %s %s%s", binding_name, value_expr, suffix), binding.items[i+1].span)
        }
        i += 2
    }
    i = 0
    for i < len(binding.items) {
        binding_name := binding.items[i].text
        macro_emit_line(&e, fmt.tprintf("    (defer (delete %s))", binding_name), binding.items[i].span)
        i += 2
    }
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
    return macroexpand_form_with_macros(expanded, macros)
}

macroexpand_if_let :: proc(form: CST_Form, macros: []User_Macro) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    expanded, err_expand, ok_expand := expand_if_let_form(form)
    if !ok_expand {
        return result, err_expand, false
    }
    return macroexpand_form_with_macros(expanded, macros)
}

macroexpand_when_ok :: proc(form: CST_Form, macros: []User_Macro) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    expanded, err_expand, ok_expand := expand_when_ok_form(form)
    if !ok_expand {
        return result, err_expand, false
    }
    return macroexpand_form_with_macros(expanded, macros)
}

macroexpand_if_ok :: proc(form: CST_Form, macros: []User_Macro) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    expanded, err_expand, ok_expand := expand_if_ok_form(form)
    if !ok_expand {
        return result, err_expand, false
    }
    return macroexpand_form_with_macros(expanded, macros)
}

macroexpand_form_with_macros :: proc(form: CST_Form, macros: []User_Macro) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol {
        if user_macro, ok_user := find_user_macro(macros, form.items[0].text); ok_user {
            expanded, err_user, ok_user_expand := expand_user_macro_call(user_macro, form, macros)
            if !ok_user_expand {
                return result, err_user, false
            }
            return macroexpand_form_with_macros(expanded, macros)
        }
        switch builtin_macro_kind(form.items[0].text) {
        case .With_Allocator:
            return macroexpand_with_allocator(form, macros)
        case .With_Temp_Allocator:
            return macroexpand_with_temp_allocator(form, macros)
        case .With_Delete:
            return macroexpand_with_delete(form, macros)
        case .Thread_First:
            expanded, err_expand, ok_expand := expand_thread_form(form, false)
            if !ok_expand {
                return result, err_expand, false
            }
            return macroexpand_form_with_macros(expanded, macros)
        case .Thread_Last:
            expanded, err_expand, ok_expand := expand_thread_form(form, true)
            if !ok_expand {
                return result, err_expand, false
            }
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

macroexpand_form :: proc(form: CST_Form) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
    return macroexpand_form_with_macros(form, nil)
}

macroexpand_source :: proc(source: string) -> (output: string, err: Compile_Error, ok: bool) {
    result, err_result, ok_result := macroexpand_source_with_map(source)
    if !ok_result {
        return "", err_result, false
    }
    defer delete(result.source_map)
    return result.output, {}, true
}

macroexpand_source_with_map :: proc(source: string) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
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
    temp_result, err_expand, ok_expand := macroexpand_form(form)
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

macroexpand_top_forms :: proc(forms: []CST_Top_Form, include_core_macros: bool = false) -> (expanded: [dynamic]CST_Top_Form, macros: [dynamic]User_Macro, err: Compile_Error, ok: bool) {
    if include_core_macros {
        initial_macros, err_core, ok_core := core_package_local_macros()
        if !ok_core {
            return expanded, macros, err_core, false
        }
        for macro_decl in initial_macros {
            append(&macros, macro_decl)
        }
    }
    for top in forms {
        if is_defmacro_form(top.form) {
            macro_decl, err_macro, ok_macro := parse_user_macro_decl(top)
            if !ok_macro {
                return expanded, macros, err_macro, false
            }
            append(&macros, macro_decl)
            continue
        }
        if top.form.kind == .List && len(top.form.items) > 0 && top.form.items[0].kind == .Symbol {
            if user_macro, ok_user := find_user_macro(macros[:], top.form.items[0].text); ok_user {
                forms_out, err_user, ok_user_expand := expand_user_macro_call_to_forms(user_macro, top.form, macros[:])
                if !ok_user_expand {
                    return expanded, macros, err_user, false
                }
                for form_out in forms_out {
                    rewritten, err_expand, ok_expand := macroexpand_cst_form_with_macros(form_out, macros[:])
                    if !ok_expand {
                        return expanded, macros, err_expand, false
                    }
                    append(&expanded, CST_Top_Form{
                        form      = rewritten,
                        doc_lines = top.doc_lines,
                        source    = top.source,
                    })
                }
                continue
            }
        }
        rewritten, err_expand, ok_expand := macroexpand_cst_form_with_macros(top.form, macros[:])
        if !ok_expand {
            return expanded, macros, err_expand, false
        }
        append(&expanded, CST_Top_Form{
            form      = rewritten,
            doc_lines = top.doc_lines,
            source    = top.source,
        })
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
    expanded, _, err_expand, ok_expand := macroexpand_top_forms(forms[:])
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

macroexpand_eval_source_with_map :: proc(source, eval_source: string) -> (result: Emit_Result, err: Compile_Error, ok: bool) {
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
    _, macros, err_expand, ok_expand := macroexpand_top_forms(forms[:])
    if !ok_expand {
        return result, clone_compile_error(err_expand, result_allocator), false
    }
    eval_form, err_eval, ok_eval := read_single_eval_form(eval_source)
    if !ok_eval {
        return result, clone_compile_error(err_eval, result_allocator), false
    }
    temp_result, err_macro, ok_macro := macroexpand_form_with_macros(eval_form, macros[:])
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
