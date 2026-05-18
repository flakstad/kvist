package odinl

import "core:fmt"
import "core:strings"

Emitter_Features :: struct {
    dynamic_literals: bool,
    core_map:         bool,
    core_filter:      bool,
    core_reduce:      bool,
}

Emitter :: struct {
    builder:                   strings.Builder,
    indent:                    int,
    unions:                    [dynamic]Union_Decl,
    features:                  ^Emitter_Features,
    line:                      int,
    attach_next_decl:          bool,
    pending_prefix_directives: [dynamic]string,
    pending_suffix_directives: [dynamic]string,
}

mark_dynamic_literals :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.dynamic_literals = true
    }
}

mark_core_map :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_map = true
    }
}

mark_core_filter :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_filter = true
    }
}

mark_core_reduce :: proc(e: ^Emitter) {
    if e.features != nil {
        e.features.core_reduce = true
    }
}

raw_attaches_to_next_decl :: proc(text: string) -> bool {
    return len(text) >= 2 && text[0] == '@' && text[1] == '('
}

raw_is_proc_directive :: proc(text: string) -> bool {
    return len(text) > 1 && text[0] == '#' && !contains_newline(text)
}

emit_indent :: proc(e: ^Emitter) {
    i := 0
    for i < e.indent {
        strings.write_string(&e.builder, "    ")
        i += 1
    }
}

emit_line :: proc(e: ^Emitter, text: string = "") {
    emit_indent(e)
    strings.write_string(&e.builder, text)
    strings.write_byte(&e.builder, '\n')
    e.line += 1
}

emit_raw_newline :: proc(e: ^Emitter) {
    strings.write_byte(&e.builder, '\n')
    e.line += 1
}

contains_newline :: proc(text: string) -> bool {
    for ch in text {
        if ch == '\n' {
            return true
        }
    }
    return false
}

append_indented_multiline :: proc(builder: ^strings.Builder, text: string, indent: string, final_suffix: string = "") {
    start := 0
    i := 0
    for i < len(text) {
        if text[i] == '\n' {
            strings.write_string(builder, indent)
            strings.write_string(builder, text[start:i])
            strings.write_byte(builder, '\n')
            start = i + 1
        }
        i += 1
    }
    strings.write_string(builder, indent)
    strings.write_string(builder, text[start:])
    strings.write_string(builder, final_suffix)
}

emit_prefixed_expr :: proc(e: ^Emitter, prefix, expr: string) {
    if !contains_newline(expr) {
        emit_indent(e)
        strings.write_string(&e.builder, prefix)
        strings.write_string(&e.builder, expr)
        strings.write_byte(&e.builder, '\n')
        e.line += 1
        return
    }

    start := 0
    i := 0
    emit_indent(e)
    strings.write_string(&e.builder, prefix)
    for i < len(expr) {
        if expr[i] == '\n' {
            strings.write_string(&e.builder, expr[start:i])
            strings.write_byte(&e.builder, '\n')
            e.line += 1
            start = i + 1
            if start < len(expr) {
                emit_indent(e)
            }
        }
        i += 1
    }
    strings.write_string(&e.builder, expr[start:])
    strings.write_byte(&e.builder, '\n')
    e.line += 1
}

surround_with_braces :: proc(prefix, inner: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, prefix)
    strings.write_byte(&builder, '{')
    strings.write_string(&builder, inner)
    strings.write_byte(&builder, '}')
    return strings.clone(strings.to_string(builder))
}

Brace_Pair :: struct {
    key:   string,
    value: string,
}

emit_brace_pair_texts :: proc(e: ^Emitter, form: CST_Form) -> (pairs: [dynamic]Brace_Pair, err: Compile_Error, ok: bool) {
    i := 0
    for i < len(form.items) {
        if i+1 >= len(form.items) {
            return pairs, Compile_Error{message = "missing brace-form value", span = form.span}, false
        }

        key := form.items[i]
        val := form.items[i+1]
        value_text, err_value, ok_value := emit_expr(e, val)
        if !ok_value {
            return pairs, err_value, false
        }

        #partial switch key.kind {
        case .Keyword:
            append(&pairs, Brace_Pair{key = map_name(key.text[1:]), value = value_text})
        case .String:
            append(&pairs, Brace_Pair{key = key.text, value = value_text})
        case:
            key_text, err_key, ok_key := emit_expr(e, key)
            if !ok_key {
                return pairs, err_key, false
            }
            append(&pairs, Brace_Pair{key = key_text, value = value_text})
        }
        i += 2
    }
    return pairs, {}, true
}

emit_brace_pairs :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    pairs, err_pairs, ok_pairs := emit_brace_pair_texts(e, form)
    if !ok_pairs {
        return "", err_pairs, false
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for pair, idx in pairs {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        fmt.sbprintf(&builder, "%s = %s", pair.key, pair.value)
    }
    return strings.clone(strings.to_string(builder)), {}, true
}

emit_vector_item_texts :: proc(e: ^Emitter, form: CST_Form) -> (items: [dynamic]string, err: Compile_Error, ok: bool) {
    for item in form.items {
        text, err_item, ok_item := emit_expr(e, item)
        if !ok_item {
            return items, err_item, false
        }
        append(&items, text)
    }
    return items, {}, true
}

emit_vector_items :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    items, err_items, ok_items := emit_vector_item_texts(e, form)
    if !ok_items {
        return "", err_items, false
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    for text, idx in items {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        strings.write_string(&builder, text)
    }
    return strings.clone(strings.to_string(builder)), {}, true
}

has_multiline_items :: proc(items: []string) -> bool {
    for item in items {
        if contains_newline(item) {
            return true
        }
    }
    return false
}

type_form_needs_dynamic_literals :: proc(form: CST_Form) -> bool {
    if form.kind == .Symbol {
        return len(form.text) >= 4 && form.text[:4] == "map[" ||
               len(form.text) >= 9 && form.text[:9] == "[dynamic]"
    }
    if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
        return false
    }
    return form.items[0].text == "map" || form.items[0].text == "dynamic"
}

emit_vector_literal :: proc(e: ^Emitter, prefix: string, form: CST_Form) -> (string, Compile_Error, bool) {
    items, err_items, ok_items := emit_vector_item_texts(e, form)
    if !ok_items {
        return "", err_items, false
    }
    if !has_multiline_items(items[:]) {
        inner, err_inner, ok_inner := emit_vector_items(e, form)
        if !ok_inner {
            return "", err_inner, false
        }
        return surround_with_braces(prefix, inner), {}, true
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, prefix)
    strings.write_string(&builder, "{\n")
    for item in items {
        append_indented_multiline(&builder, item, "    ", ",")
        strings.write_byte(&builder, '\n')
    }
    strings.write_byte(&builder, '}')
    return strings.clone(strings.to_string(builder)), {}, true
}

emit_brace_literal :: proc(e: ^Emitter, prefix: string, form: CST_Form) -> (string, Compile_Error, bool) {
    pairs, err_pairs, ok_pairs := emit_brace_pair_texts(e, form)
    if !ok_pairs {
        return "", err_pairs, false
    }

    multiline := false
    for pair in pairs {
        if contains_newline(pair.value) {
            multiline = true
            break
        }
    }
    if !multiline {
        inner, err_inner, ok_inner := emit_brace_pairs(e, form)
        if !ok_inner {
            return "", err_inner, false
        }
        return surround_with_braces(prefix, inner), {}, true
    }

    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)
    strings.write_string(&builder, prefix)
    strings.write_string(&builder, "{\n")
    for pair in pairs {
        item := fmt.tprintf("%s = %s", pair.key, pair.value)
        append_indented_multiline(&builder, item, "    ", ",")
        strings.write_byte(&builder, '\n')
    }
    strings.write_byte(&builder, '}')
    return strings.clone(strings.to_string(builder)), {}, true
}

emit_call_text :: proc(name: string, arg_texts: []string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    multiline := false
    for arg_text in arg_texts {
        if contains_newline(arg_text) {
            multiline = true
            break
        }
    }

    if multiline {
        strings.write_string(&builder, name)
        strings.write_string(&builder, "(\n")
        for arg_text, idx in arg_texts {
            suffix := ","
            if idx == len(arg_texts)-1 {
                suffix = ""
            }
            append_indented_multiline(&builder, arg_text, "    ", suffix)
            strings.write_byte(&builder, '\n')
        }
        strings.write_byte(&builder, ')')
        return strings.clone(strings.to_string(builder))
    }

    fmt.sbprintf(&builder, "%s(", name)
    for arg_text, idx in arg_texts {
        if idx > 0 {
            strings.write_string(&builder, ", ")
        }
        strings.write_string(&builder, arg_text)
    }
    strings.write_byte(&builder, ')')
    return strings.clone(strings.to_string(builder))
}

emit_thread_step :: proc(e: ^Emitter, current: string, step: CST_Form, thread_last: bool) -> (string, Compile_Error, bool) {
    #partial switch step.kind {
    case .Keyword:
        return fmt.tprintf("%s.%s", current, map_name(step.text[1:])), {}, true
    case .Symbol:
        if thread_last && step.text == "slice" {
            return slice_all_expr_text(current), {}, true
        }
        args: [dynamic]string
        append(&args, current)
        return emit_call_text(map_name(step.text), args[:]), {}, true
    case .List:
        if len(step.items) == 0 {
            return "", Compile_Error{message = "thread step cannot be an empty list", span = step.span}, false
        }
        head := step.items[0]
        if head.kind == .Keyword {
            if len(step.items) != 1 {
                return "", Compile_Error{message = "keyword thread step does not take arguments", span = step.span}, false
            }
            return fmt.tprintf("%s.%s", current, map_name(head.text[1:])), {}, true
        }
        if head.kind != .Symbol {
            return "", Compile_Error{message = "thread list step expects symbol or keyword head", span = head.span}, false
        }
        if thread_last && (head.text == "map" || head.text == "filter") {
            if len(step.items) != 2 {
                return "", Compile_Error{message = fmt.tprintf("%s thread step expects one function argument", head.text), span = step.span}, false
            }
            f, err_f, ok_f := emit_expr(e, step.items[1])
            if !ok_f {
                return "", err_f, false
            }
            collection := slice_all_expr_text(current)
            if head.text == "map" {
                mark_core_map(e)
                return emit_call_text("odinl_map", []string{f, collection}), {}, true
            } else {
                mark_core_filter(e)
                return emit_call_text("odinl_filter", []string{f, collection}), {}, true
            }
        }
        if thread_last && head.text == "reduce" {
            if len(step.items) != 3 {
                return "", Compile_Error{message = "reduce thread step expects function and initial value", span = step.span}, false
            }
            f, err_f, ok_f := emit_expr(e, step.items[1])
            if !ok_f {
                return "", err_f, false
            }
            init, err_init, ok_init := emit_expr(e, step.items[2])
            if !ok_init {
                return "", err_init, false
            }
            mark_core_reduce(e)
            return emit_call_text("odinl_reduce", []string{f, init, slice_all_expr_text(current)}), {}, true
        }
        if thread_last && head.text == "slice" {
            if len(step.items) > 3 {
                return "", Compile_Error{message = "slice thread step expects optional start and end", span = step.span}, false
            }
            if len(step.items) == 1 {
                return slice_all_expr_text(current), {}, true
            }
            start, err_start, ok_start := emit_expr(e, step.items[1])
            if !ok_start {
                return "", err_start, false
            }
            if len(step.items) == 2 {
                return fmt.tprintf("(%s)[%s:]", current, start), {}, true
            }
            end, err_end, ok_end := emit_expr(e, step.items[2])
            if !ok_end {
                return "", err_end, false
            }
            return fmt.tprintf("(%s)[%s:%s]", current, start, end), {}, true
        }
        args: [dynamic]string
        if !thread_last {
            append(&args, current)
        }
        for arg in step.items[1:] {
            arg_text, err_arg, ok_arg := emit_expr(e, arg)
            if !ok_arg {
                return "", err_arg, false
            }
            append(&args, arg_text)
        }
        if thread_last {
            append(&args, current)
        }
        return emit_call_text(map_name(head.text), args[:]), {}, true
    case:
        return "", Compile_Error{message = "unsupported thread step", span = step.span}, false
    }
    return "", Compile_Error{message = "unsupported thread step", span = step.span}, false
}

emit_thread_expr :: proc(e: ^Emitter, form: CST_Form, thread_last: bool = false) -> (string, Compile_Error, bool) {
    if len(form.items) < 3 {
        return "", Compile_Error{message = "-> expects an initial expression and at least one step", span = form.span}, false
    }

    current, err_current, ok_current := emit_expr(e, form.items[1])
    if !ok_current {
        return "", err_current, false
    }

    for step in form.items[2:] {
        next, err_step, ok_step := emit_thread_step(e, current, step, thread_last)
        if !ok_step {
            return "", err_step, false
        }
        current = next
    }
    return current, {}, true
}

slice_all_expr_text :: proc(text: string) -> string {
    if len(text) >= 2 && text[0] == '[' && text[1] == ']' {
        return text
    }
    return fmt.tprintf("(%s)[:]", text)
}

emit_proc_literal_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) < 2 || !is_symbol(form.items[0], "proc") || form.items[1].kind != .Vector {
        return "", Compile_Error{message = "invalid proc literal", span = form.span}, false
    }

    params, err_params, ok_params := parse_param_vector(form.items[1])
    if !ok_params {
        return "", err_params, false
    }

    body_index := 2
    returns := Return_Spec{kind = .None}
    if body_index < len(form.items) && is_symbol(form.items[body_index], "->") {
        if body_index+1 >= len(form.items) {
            return "", Compile_Error{message = "missing proc literal return spec", span = form.items[body_index].span}, false
        }
        return_form := form.items[body_index+1]
        #partial switch return_form.kind {
        case .Vector:
            named, err_named, ok_named := parse_named_returns(return_form)
            if !ok_named {
                return "", err_named, false
            }
            returns.kind = .Named
            returns.named = named
            body_index += 2
        case .Symbol, .List:
            return_text, next_index, err_return, ok_return := parse_type_text_from_forms(form.items[:], body_index+1)
            if !ok_return {
                return "", err_return, false
            }
            returns.kind = .Single
            returns.single_ty = return_text
            body_index = next_index
        case:
            return "", Compile_Error{message = "unsupported proc literal return spec", span = return_form.span}, false
        }
    }
    if body_index >= len(form.items) {
        return "", Compile_Error{message = "proc literal body is empty", span = form.span}, false
    }

    sub := Emitter{
        builder  = strings.builder_make(),
        indent   = 1,
        unions   = e.unions,
        features = e.features,
    }
    defer strings.builder_destroy(&sub.builder)

    strings.write_string(&sub.builder, "proc(")
    for param, idx in params {
        if idx > 0 {
            strings.write_string(&sub.builder, ", ")
        }
        fmt.sbprintf(&sub.builder, "%s: %s", param.name, param.ty)
    }
    strings.write_byte(&sub.builder, ')')
    emit_return_spec(&sub, returns)
    strings.write_string(&sub.builder, " {\n")

    body: [dynamic]CST_Form
    for item in form.items[body_index:] {
        append(&body, item)
    }
    err_body, ok_body := emit_body_forms(&sub, body[:], returns)
    if !ok_body {
        return "", err_body, false
    }

    strings.write_string(&sub.builder, "}")
    return strings.clone(strings.to_string(sub.builder)), {}, true
}

emit_operator_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    head := form.items[0]
    if head.kind != .Symbol {
        return "", {}, false
    }

    op := head.text
    if op == "not" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "not expects one argument", span = form.span}, false
        }
        value, err_value, ok_value := emit_expr(e, form.items[1])
        if !ok_value {
            return "", err_value, false
        }
        return fmt.tprintf("!(%s)", value), {}, true
    }

    if op == "and" || op == "or" {
        if len(form.items) < 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects at least two arguments", op), span = form.span}, false
        }
        joiner := " && "
        if op == "or" {
            joiner = " || "
        }
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        for arg, idx in form.items[1:] {
            if idx > 0 {
                strings.write_string(&builder, joiner)
            }
            value, err_value, ok_value := emit_expr(e, arg)
            if !ok_value {
                return "", err_value, false
            }
            fmt.sbprintf(&builder, "(%s)", value)
        }
        return strings.clone(strings.to_string(builder)), {}, true
    }

    if op == "+" || op == "*" || op == "/" || op == "%" {
        if len(form.items) < 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects at least two arguments", op), span = form.span}, false
        }
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        for arg, idx in form.items[1:] {
            if idx > 0 {
                fmt.sbprintf(&builder, " %s ", op)
            }
            value, err_value, ok_value := emit_expr(e, arg)
            if !ok_value {
                return "", err_value, false
            }
            fmt.sbprintf(&builder, "(%s)", value)
        }
        return strings.clone(strings.to_string(builder)), {}, true
    }

    if op == "-" {
        if len(form.items) == 2 {
            value, err_value, ok_value := emit_expr(e, form.items[1])
            if !ok_value {
                return "", err_value, false
            }
            return fmt.tprintf("-(%s)", value), {}, true
        }
        if len(form.items) >= 3 {
            builder := strings.builder_make()
            defer strings.builder_destroy(&builder)
            for arg, idx in form.items[1:] {
                if idx > 0 {
                    strings.write_string(&builder, " - ")
                }
                value, err_value, ok_value := emit_expr(e, arg)
                if !ok_value {
                    return "", err_value, false
                }
                fmt.sbprintf(&builder, "(%s)", value)
            }
            return strings.clone(strings.to_string(builder)), {}, true
        }
        return "", Compile_Error{message = "- expects at least one argument", span = form.span}, false
    }

    if op == "==" || op == "!=" || op == "<" || op == "<=" || op == ">" || op == ">=" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects exactly two arguments", op), span = form.span}, false
        }
        lhs, err_lhs, ok_lhs := emit_expr(e, form.items[1])
        if !ok_lhs {
            return "", err_lhs, false
        }
        rhs, err_rhs, ok_rhs := emit_expr(e, form.items[2])
        if !ok_rhs {
            return "", err_rhs, false
        }
        return fmt.tprintf("(%s) %s (%s)", lhs, op, rhs), {}, true
    }

    if op == "in?" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "in? expects exactly two arguments", span = form.span}, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[1])
        if !ok_collection {
            return "", err_collection, false
        }
        key, err_key, ok_key := emit_expr(e, form.items[2])
        if !ok_key {
            return "", err_key, false
        }
        return fmt.tprintf("(%s) in (%s)", key, collection), {}, true
    }

    if op == "in" || op == "not-in" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects exactly two arguments", op), span = form.span}, false
        }
        lhs, err_lhs, ok_lhs := emit_expr(e, form.items[1])
        if !ok_lhs {
            return "", err_lhs, false
        }
        rhs, err_rhs, ok_rhs := emit_expr(e, form.items[2])
        if !ok_rhs {
            return "", err_rhs, false
        }
        if op == "not-in" {
            return fmt.tprintf("!((%s) in (%s))", lhs, rhs), {}, true
        }
        return fmt.tprintf("(%s) in (%s)", lhs, rhs), {}, true
    }

    return "", {}, false
}

find_union_decl :: proc(e: ^Emitter, name: string) -> (^Union_Decl, bool) {
    for i in 0..<len(e.unions) {
        if e.unions[i].name == name {
            return &e.unions[i], true
        }
    }
    return nil, false
}

emit_union_constructor :: proc(e: ^Emitter, union_decl: ^Union_Decl, arg: CST_Form) -> (string, Compile_Error, bool) {
    if arg.kind != .Brace {
        return "", Compile_Error{message = "union construction expects a brace form", span = arg.span}, false
    }
    if len(arg.items) != 2 {
        return "", Compile_Error{message = "union construction expects exactly one variant", span = arg.span}, false
    }

    key := arg.items[0]
    value := arg.items[1]
    if key.kind != .Keyword {
        return "", Compile_Error{message = "union construction expects a keyword variant", span = key.span}, false
    }

    variant_name := map_name(key.text[1:])
    found := false
    for variant in union_decl.variants {
        if variant.name == variant_name {
            found = true
            break
        }
    }
    if !found {
        return "", Compile_Error{message = "unknown union variant", span = key.span}, false
    }

    value_text, err_value, ok_value := emit_expr(e, value)
    if !ok_value {
        return "", err_value, false
    }
    return fmt.tprintf("%s(%s)", union_decl.name, value_text), {}, true
}

emit_directive_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    if len(form.items) < 2 || form.items[0].kind != .Symbol || len(form.items[0].text) == 0 || form.items[0].text[0] != '#' {
        return "", Compile_Error{message = "invalid directive expression", span = form.span}, false
    }

    target := form.items[1]
    if len(form.items) > 2 {
        call_items: [dynamic]CST_Form
        for item in form.items[1:] {
            append(&call_items, item)
        }
        target = CST_Form{
            kind  = .List,
            items = call_items,
            span  = form.span,
        }
    }

    target_text, err_target, ok_target := emit_expr(e, target)
    if !ok_target {
        return "", err_target, false
    }
    return fmt.tprintf("%s %s", form.items[0].text, target_text), {}, true
}

emit_call_like :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    head := form.items[0]
    if head.kind != .Symbol {
        return "", Compile_Error{message = "unsupported call head", span = head.span}, false
    }

    if operator_text, err_op, ok_op := emit_operator_expr(e, form); ok_op {
        return operator_text, {}, true
    } else if err_op.message != "" {
        return "", err_op, false
    }

    if head.text == "get" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "get expects collection and key", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        key, err_key, ok_key := emit_expr(e, form.items[2])
        if !ok_key {
            return "", err_key, false
        }
        return fmt.tprintf("%s[%s]", target, key), {}, true
    }

    if head.text == "nil?" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "nil? expects one expression", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        return fmt.tprintf("(%s) == nil", target), {}, true
    }

    if head.text == "map" || head.text == "filter" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = fmt.tprintf("%s expects function and collection", head.text), span = form.span}, false
        }
        f, err_f, ok_f := emit_expr(e, form.items[1])
        if !ok_f {
            return "", err_f, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[2])
        if !ok_collection {
            return "", err_collection, false
        }
        collection = slice_all_expr_text(collection)
        if head.text == "map" {
            mark_core_map(e)
            return emit_call_text("odinl_map", []string{f, collection}), {}, true
        } else {
            mark_core_filter(e)
            return emit_call_text("odinl_filter", []string{f, collection}), {}, true
        }
    }

    if head.text == "reduce" {
        if len(form.items) != 4 {
            return "", Compile_Error{message = "reduce expects function, initial value, and collection", span = form.span}, false
        }
        f, err_f, ok_f := emit_expr(e, form.items[1])
        if !ok_f {
            return "", err_f, false
        }
        init, err_init, ok_init := emit_expr(e, form.items[2])
        if !ok_init {
            return "", err_init, false
        }
        collection, err_collection, ok_collection := emit_expr(e, form.items[3])
        if !ok_collection {
            return "", err_collection, false
        }
        collection = slice_all_expr_text(collection)
        mark_core_reduce(e)
        return emit_call_text("odinl_reduce", []string{f, init, collection}), {}, true
    }

    if head.text == "slice" {
        if len(form.items) < 2 || len(form.items) > 4 {
            return "", Compile_Error{message = "slice expects collection, optional start, and optional end", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        if len(form.items) == 2 {
            return fmt.tprintf("(%s)[:]", target), {}, true
        }
        start, err_start, ok_start := emit_expr(e, form.items[2])
        if !ok_start {
            return "", err_start, false
        }
        if len(form.items) == 3 {
            return fmt.tprintf("(%s)[%s:]", target, start), {}, true
        }
        end, err_end, ok_end := emit_expr(e, form.items[3])
        if !ok_end {
            return "", err_end, false
        }
        return fmt.tprintf("(%s)[%s:%s]", target, start, end), {}, true
    }

    if head.text == "^" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "^ expects one pointer expression", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        return fmt.tprintf("(%s)^", target), {}, true
    }

    if head.text == "&" {
        if len(form.items) != 2 {
            return "", Compile_Error{message = "& expects one addressable expression", span = form.span}, false
        }
        target, err_target, ok_target := emit_expr(e, form.items[1])
        if !ok_target {
            return "", err_target, false
        }
        return fmt.tprintf("&(%s)", target), {}, true
    }

    if head.text == "->" {
        return emit_thread_expr(e, form)
    }

    if head.text == "->>" {
        return emit_thread_expr(e, form, true)
    }

    if head.text == "new" {
        if len(form.items) != 3 {
            return "", Compile_Error{message = "new expects type and literal", span = form.span}, false
        }
        type_form := form.items[1]
        type_text, err_type, ok_type := parse_type_text(type_form)
        if !ok_type {
            return "", err_type, false
        }
        if type_form_needs_dynamic_literals(type_form) {
            mark_dynamic_literals(e)
        }
        #partial switch form.items[2].kind {
        case .Vector:
            return emit_vector_literal(e, type_text, form.items[2])
        case .Brace:
            return emit_brace_literal(e, type_text, form.items[2])
        case:
            return "", Compile_Error{message = "new expects vector or brace literal", span = form.items[2].span}, false
        }
    }

    if head.text == "make" {
        if len(form.items) < 2 {
            return "", Compile_Error{message = "make expects a type and optional arguments", span = form.span}, false
        }
        type_text, err_type, ok_type := parse_type_text(form.items[1])
        if !ok_type {
            return "", err_type, false
        }
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        fmt.sbprintf(&builder, "make(%s", type_text)
        for arg in form.items[2:] {
            arg_text, err_arg, ok_arg := emit_expr(e, arg)
            if !ok_arg {
                return "", err_arg, false
            }
            strings.write_string(&builder, ", ")
            strings.write_string(&builder, arg_text)
        }
        strings.write_byte(&builder, ')')
        return strings.clone(strings.to_string(builder)), {}, true
    }

    if len(form.items) == 2 && form.items[1].kind == .Brace {
        union_decl, ok_union := find_union_decl(e, map_name(head.text))
        if ok_union {
            return emit_union_constructor(e, union_decl, form.items[1])
        }
        return emit_brace_literal(e, map_name(head.text), form.items[1])
    }

    arg_texts: [dynamic]string
    for arg in form.items[1:] {
        arg_text, err_arg, ok_arg := emit_expr(e, arg)
        if !ok_arg {
            return "", err_arg, false
        }
        append(&arg_texts, arg_text)
    }
    return emit_call_text(map_name(head.text), arg_texts[:]), {}, true
}

emit_expr :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    #partial switch form.kind {
    case .String:
        return form.text, {}, true
    case .Number:
        return form.text, {}, true
    case .Bool:
        return form.text, {}, true
    case .Nil:
        return form.text, {}, true
    case .Symbol:
        return map_name(form.text), {}, true
    case .Keyword:
        return map_name(form.text[1:]), {}, true
    case .List:
        if len(form.items) == 0 {
            return "", Compile_Error{message = "empty list expression", span = form.span}, false
        }
        if form.items[0].kind == .Symbol && len(form.items[0].text) > 0 && form.items[0].text[0] == '#' {
            return emit_directive_expr(e, form)
        }
        if is_symbol(form.items[0], "proc") {
            return emit_proc_literal_expr(e, form)
        }
        if form.items[0].kind == .Keyword {
            if len(form.items) != 2 {
                return "", Compile_Error{message = "field access expects one receiver", span = form.span}, false
            }
            receiver, err_receiver, ok_receiver := emit_expr(e, form.items[1])
            if !ok_receiver {
                return "", err_receiver, false
            }
            return fmt.tprintf("%s.%s", receiver, map_name(form.items[0].text[1:])), {}, true
        }
        if is_symbol(form.items[0], "odin") {
            if len(form.items) != 2 || form.items[1].kind != .String {
                return "", Compile_Error{message = "odin expects one string literal", span = form.span}, false
            }
            return unquote_string(form.items[1].text), {}, true
        }
        return emit_call_like(e, form)
    case .Vector:
        return emit_vector_literal(e, "", form)
    case .Brace:
        return emit_brace_literal(e, "", form)
    }
    return "", Compile_Error{message = "unsupported expression", span = form.span}, false
}

Binding :: struct {
    is_destructure: bool,
    name:           string,
    pattern:        [dynamic]string,
    is_typed:       bool,
    ty:             string,
    value:          CST_Form,
}

parse_let_bindings :: proc(form: CST_Form) -> (bindings: [dynamic]Binding, err: Compile_Error, ok: bool) {
    if form.kind != .Vector {
        return bindings, Compile_Error{message = "let expects a binding vector", span = form.span}, false
    }
    i := 0
    for i < len(form.items) {
        target := form.items[i]
        #partial switch target.kind {
        case .Vector:
            if i+1 >= len(form.items) {
                return bindings, Compile_Error{message = "destructuring binding missing value", span = target.span}, false
            }
            names: [dynamic]string
            for part in target.items {
                if part.kind != .Symbol {
                    return bindings, Compile_Error{message = "destructuring expects symbols", span = part.span}, false
                }
                append(&names, map_name(part.text))
            }
            append(&bindings, Binding{
                is_destructure = true,
                pattern = names,
                value = form.items[i+1],
            })
            i += 2
        case .Symbol:
            if len(target.text) > 0 && target.text[len(target.text)-1] == ':' {
                if i+2 >= len(form.items) {
                    return bindings, Compile_Error{message = "typed binding missing type or value", span = target.span}, false
                }
                type_text, next_i, err_type, ok_type := parse_type_text_from_forms(form.items[:], i+1)
                if !ok_type {
                    return bindings, err_type, false
                }
                if next_i >= len(form.items) {
                    return bindings, Compile_Error{message = "typed binding missing value", span = target.span}, false
                }
                append(&bindings, Binding{
                    name = map_name(target.text[:len(target.text)-1]),
                    is_typed = true,
                    ty = type_text,
                    value = form.items[next_i],
                })
                i = next_i + 1
            } else {
                if i+1 >= len(form.items) {
                    return bindings, Compile_Error{message = "binding missing value", span = target.span}, false
                }
                append(&bindings, Binding{
                    name = map_name(target.text),
                    value = form.items[i+1],
                })
                i += 2
            }
        case:
            return bindings, Compile_Error{message = "unsupported binding target", span = target.span}, false
        }
    }
    return bindings, {}, true
}

emit_body_forms :: proc(e: ^Emitter, body: []CST_Form, returns: Return_Spec) -> (Compile_Error, bool) {
    for form, idx in body {
        last := idx == len(body)-1
        err_stmt, ok_stmt := emit_stmt(e, form, last, returns)
        if !ok_stmt {
            return err_stmt, false
        }
    }
    return {}, true
}

returns_when_final :: proc(last_in_proc: bool, returns: Return_Spec) -> Return_Spec {
    if last_in_proc {
        return returns
    }
    return Return_Spec{kind = .None}
}

emit_if_like :: proc(e: ^Emitter, head: string, form: CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    if len(form.items) < 3 || len(form.items) > 4 {
        return Compile_Error{message = fmt.tprintf("%s expects test, then, and optional else", head), span = form.span}, false
    }
    test, err_test, ok_test := emit_expr(e, form.items[1])
    if !ok_test {
        return err_test, false
    }
    emit_indent(e)
    strings.write_string(&e.builder, "if ")
    strings.write_string(&e.builder, test)
    strings.write_string(&e.builder, " {")
    emit_raw_newline(e)
    e.indent += 1
    branch_returns := returns_when_final(last_in_proc, returns)
    err_then, ok_then := emit_stmt(e, form.items[2], last_in_proc, branch_returns)
    if !ok_then {
        return err_then, false
    }
    e.indent -= 1
    emit_line(e, "}")
    if len(form.items) == 4 {
        emit_indent(e)
        strings.write_string(&e.builder, "else {")
        emit_raw_newline(e)
        e.indent += 1
        err_else, ok_else := emit_stmt(e, form.items[3], last_in_proc, branch_returns)
        if !ok_else {
            return err_else, false
        }
        e.indent -= 1
        emit_line(e, "}")
    }
    return {}, true
}

is_else_keyword :: proc(form: CST_Form) -> bool {
    return form.kind == .Keyword && form.text == ":else"
}

emit_cond_stmt :: proc(e: ^Emitter, form: CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    if len(form.items) < 3 {
        return Compile_Error{message = "cond expects at least one clause", span = form.span}, false
    }
    if (len(form.items)-1)%2 != 0 {
        return Compile_Error{message = "cond expects test/body pairs", span = form.span}, false
    }

    branch_returns := returns_when_final(last_in_proc, returns)
    i := 1
    for i < len(form.items) {
        test_form := form.items[i]
        body_form := form.items[i+1]
        is_else := is_else_keyword(test_form)

        if is_else && i+2 < len(form.items) {
            return Compile_Error{message = "cond :else must be the final clause", span = test_form.span}, false
        }

        if is_else {
            emit_indent(e)
            strings.write_string(&e.builder, "else {")
            emit_raw_newline(e)
        } else {
            test, err_test, ok_test := emit_expr(e, test_form)
            if !ok_test {
                return err_test, false
            }
            emit_indent(e)
            if i == 1 {
                strings.write_string(&e.builder, "if ")
            } else {
                strings.write_string(&e.builder, "else if ")
            }
            strings.write_string(&e.builder, test)
            strings.write_string(&e.builder, " {")
            emit_raw_newline(e)
        }

        e.indent += 1
        err_body, ok_body := emit_stmt(e, body_form, last_in_proc, branch_returns)
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")

        i += 2
    }

    return {}, true
}

is_type_switch_subject :: proc(form: CST_Form) -> bool {
    return form.kind == .Vector && len(form.items) == 2 && form.items[0].kind == .Symbol
}

switch_has_else_clause :: proc(form: CST_Form) -> bool {
    i := 2
    for i < len(form.items) {
        if is_else_keyword(form.items[i]) {
            return true
        }
        i += 2
    }
    return false
}

emit_switch_case_label :: proc(e: ^Emitter, clause: CST_Form, type_switch: bool) -> (string, Compile_Error, bool) {
    if is_else_keyword(clause) {
        return "case:", {}, true
    }

    if type_switch {
        if clause.kind == .Symbol {
            return fmt.tprintf("case %s:", map_name(clause.text)), {}, true
        }
        if clause.kind == .Vector {
            builder := strings.builder_make()
            defer strings.builder_destroy(&builder)
            strings.write_string(&builder, "case ")
            for item, idx in clause.items {
                if item.kind != .Symbol {
                    return "", Compile_Error{message = "type-switch case vector expects symbols", span = item.span}, false
                }
                if idx > 0 {
                    strings.write_string(&builder, ", ")
                }
                strings.write_string(&builder, map_name(item.text))
            }
            strings.write_string(&builder, ":")
            return strings.clone(strings.to_string(builder)), {}, true
        }
        return "", Compile_Error{message = "type-switch case expects a type symbol or vector of types", span = clause.span}, false
    }

    if clause.kind == .Vector {
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        strings.write_string(&builder, "case ")
        for item, idx in clause.items {
            item_text, err_item, ok_item := emit_expr(e, item)
            if !ok_item {
                return "", err_item, false
            }
            if idx > 0 {
                strings.write_string(&builder, ", ")
            }
            strings.write_string(&builder, item_text)
        }
        strings.write_string(&builder, ":")
        return strings.clone(strings.to_string(builder)), {}, true
    }

    clause_text, err_clause, ok_clause := emit_expr(e, clause)
    if !ok_clause {
        return "", err_clause, false
    }
    return fmt.tprintf("case %s:", clause_text), {}, true
}

emit_switch_stmt :: proc(e: ^Emitter, form: CST_Form, last_in_proc: bool, returns: Return_Spec, force_partial: bool = false) -> (Compile_Error, bool) {
    if len(form.items) < 4 {
        return Compile_Error{message = "switch expects subject and at least one clause", span = form.span}, false
    }

    type_switch := is_type_switch_subject(form.items[1])
    emit_indent(e)
    if !type_switch && (force_partial || switch_has_else_clause(form)) {
        strings.write_string(&e.builder, "#partial ")
    }
    strings.write_string(&e.builder, "switch ")
    if type_switch {
        binding_name := map_name(form.items[1].items[0].text)
        subject, err_subject, ok_subject := emit_expr(e, form.items[1].items[1])
        if !ok_subject {
            return err_subject, false
        }
        strings.write_string(&e.builder, binding_name)
        strings.write_string(&e.builder, " in ")
        strings.write_string(&e.builder, subject)
    } else {
        subject, err_subject, ok_subject := emit_expr(e, form.items[1])
        if !ok_subject {
            return err_subject, false
        }
        strings.write_string(&e.builder, subject)
    }
    strings.write_string(&e.builder, " {")
    emit_raw_newline(e)

    branch_returns := returns_when_final(last_in_proc, returns)
    i := 2
    saw_else := false
    for i < len(form.items) {
        if i+1 >= len(form.items) {
            return Compile_Error{message = "switch clause missing body", span = form.span}, false
        }

        clause := form.items[i]
        body := form.items[i+1]

        if is_else_keyword(clause) {
            if i+2 < len(form.items) {
                return Compile_Error{message = "switch :else must be the final clause", span = clause.span}, false
            }
            saw_else = true
        } else if saw_else {
            return Compile_Error{message = "switch cannot have clauses after :else", span = clause.span}, false
        }

        label, err_label, ok_label := emit_switch_case_label(e, clause, type_switch)
        if !ok_label {
            return err_label, false
        } else {
            emit_line(e, label)
        }

        e.indent += 1
        err_body, ok_body := emit_stmt(e, body, last_in_proc, branch_returns)
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1

        i += 2
    }

    emit_line(e, "}")
    return {}, true
}

emit_stmt :: proc(e: ^Emitter, form: CST_Form, last_in_proc: bool, returns: Return_Spec) -> (Compile_Error, bool) {
    if form.kind != .List {
        expr, err_expr, ok_expr := emit_expr(e, form)
        if !ok_expr {
            return err_expr, false
        }
        if last_in_proc && returns.kind == .Single {
            emit_prefixed_expr(e, "return ", expr)
        } else {
            emit_prefixed_expr(e, "", expr)
        }
        return {}, true
    }

    if len(form.items) == 0 {
        return Compile_Error{message = "empty list statement", span = form.span}, false
    }

    if form.items[0].kind == .Keyword {
        expr, err_expr, ok_expr := emit_expr(e, form)
        if !ok_expr {
            return err_expr, false
        }
        if last_in_proc && returns.kind == .Single {
            emit_prefixed_expr(e, "return ", expr)
        } else {
            emit_prefixed_expr(e, "", expr)
        }
        return {}, true
    }

    head := form.items[0]
    if head.kind != .Symbol {
        return Compile_Error{message = "unsupported statement head", span = head.span}, false
    }

    switch head.text {
    case "comment":
        return {}, true
    case "#partial":
        if len(form.items) < 2 || !is_symbol(form.items[1], "switch") {
            return Compile_Error{message = "#partial currently expects a switch form", span = form.span}, false
        }
        switch_items: [dynamic]CST_Form
        for item in form.items[1:] {
            append(&switch_items, item)
        }
        switch_form := CST_Form{
            kind  = .List,
            items = switch_items,
            span  = form.span,
        }
        return emit_switch_stmt(e, switch_form, last_in_proc, returns, true)
    case "let":
        if len(form.items) < 3 {
            return Compile_Error{message = "let expects bindings and body", span = form.span}, false
        }
        bindings, err_bind, ok_bind := parse_let_bindings(form.items[1])
        if !ok_bind {
            return err_bind, false
        }
        scoped := !last_in_proc
        if scoped {
            emit_line(e, "{")
            e.indent += 1
        }
        for binding in bindings {
            value, err_value, ok_value := emit_expr(e, binding.value)
            if !ok_value {
                return err_value, false
            }
            if binding.is_destructure {
                line_builder := strings.builder_make()
                defer strings.builder_destroy(&line_builder)
                for name, idx in binding.pattern {
                    if idx > 0 {
                        strings.write_string(&line_builder, ", ")
                    }
                    strings.write_string(&line_builder, name)
                }
                fmt.sbprintf(&line_builder, " := %s", value)
                emit_prefixed_expr(e, "", strings.clone(strings.to_string(line_builder)))
            } else if binding.is_typed {
                emit_prefixed_expr(e, fmt.tprintf("%s: %s = ", binding.name, binding.ty), value)
            } else {
                emit_prefixed_expr(e, fmt.tprintf("%s := ", binding.name), value)
            }
        }
        body: [dynamic]CST_Form
        for item in form.items[2:] {
            append(&body, item)
        }
        err_body, ok_body := emit_body_forms(e, body[:], returns_when_final(last_in_proc, returns))
        if !ok_body {
            return err_body, false
        }
        if scoped {
            e.indent -= 1
            emit_line(e, "}")
        }
        return {}, true
    case "do":
        emit_line(e, "{")
        e.indent += 1
        body: [dynamic]CST_Form
        for item in form.items[1:] {
            append(&body, item)
        }
        err_body, ok_body := emit_body_forms(e, body[:], returns_when_final(last_in_proc, returns))
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "when":
        if len(form.items) < 3 {
            return Compile_Error{message = "when expects test and body", span = form.span}, false
        }
        test, err_test, ok_test := emit_expr(e, form.items[1])
        if !ok_test {
            return err_test, false
        }
        emit_indent(e)
        strings.write_string(&e.builder, "if ")
        strings.write_string(&e.builder, test)
        strings.write_string(&e.builder, " {")
        emit_raw_newline(e)
        e.indent += 1
        body: [dynamic]CST_Form
        for item in form.items[2:] {
            append(&body, item)
        }
        err_body, ok_body := emit_body_forms(e, body[:], returns_when_final(last_in_proc, returns))
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "if":
        return emit_if_like(e, "if", form, last_in_proc, returns)
    case "cond":
        return emit_cond_stmt(e, form, last_in_proc, returns)
    case "switch":
        return emit_switch_stmt(e, form, last_in_proc, returns)
    case "return":
        if len(form.items) == 1 {
            emit_line(e, "return")
            return {}, true
        }
        if len(form.items) == 2 {
            value, err_value, ok_value := emit_expr(e, form.items[1])
            if !ok_value {
                return err_value, false
            }
            emit_prefixed_expr(e, "return ", value)
            return {}, true
        }
        line_builder := strings.builder_make()
        defer strings.builder_destroy(&line_builder)
        strings.write_string(&line_builder, "return ")
        for item, idx in form.items[1:] {
            if idx > 0 {
                strings.write_string(&line_builder, ", ")
            }
            value, err_value, ok_value := emit_expr(e, item)
            if !ok_value {
                return err_value, false
            }
            strings.write_string(&line_builder, value)
        }
        emit_line(e, strings.clone(strings.to_string(line_builder)))
        return {}, true
    case "break":
        if len(form.items) != 1 {
            return Compile_Error{message = "break does not take arguments", span = form.span}, false
        }
        emit_line(e, "break")
        return {}, true
    case "continue":
        if len(form.items) != 1 {
            return Compile_Error{message = "continue does not take arguments", span = form.span}, false
        }
        emit_line(e, "continue")
        return {}, true
    case "defer":
        if len(form.items) < 2 {
            return Compile_Error{message = "defer expects a body", span = form.span}, false
        }
        if len(form.items) == 2 {
            deferred := form.items[1]
            if deferred.kind == .List && len(deferred.items) > 0 && deferred.items[0].kind == .Symbol {
                switch deferred.items[0].text {
                case "if", "when", "cond", "switch", "let", "do":
                case:
                    expr, err_expr, ok_expr := emit_expr(e, deferred)
                    if !ok_expr {
                        return err_expr, false
                    }
                    emit_line(e, fmt.tprintf("defer %s", expr))
                    return {}, true
                }
            } else {
                expr, err_expr, ok_expr := emit_expr(e, deferred)
                if !ok_expr {
                    return err_expr, false
                }
                emit_line(e, fmt.tprintf("defer %s", expr))
                return {}, true
            }
        }
        emit_line(e, "defer {")
        e.indent += 1
        body: [dynamic]CST_Form
        for item in form.items[1:] {
            append(&body, item)
        }
        err_body, ok_body := emit_body_forms(e, body[:], Return_Spec{kind = .None})
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "set!":
        if len(form.items) != 3 {
            return Compile_Error{message = "set! expects place and value", span = form.span}, false
        }
        lhs, err_lhs, ok_lhs := emit_expr(e, form.items[1])
        if !ok_lhs {
            return err_lhs, false
        }
        rhs, err_rhs, ok_rhs := emit_expr(e, form.items[2])
        if !ok_rhs {
            return err_rhs, false
        }
        emit_line(e, fmt.tprintf("%s = %s", lhs, rhs))
        return {}, true
    case "each":
        body_start := 3
        name_form: CST_Form
        coll_form: CST_Form
        if len(form.items) >= 4 && form.items[1].kind == .Symbol {
            name_form = form.items[1]
            coll_form = form.items[2]
        } else if len(form.items) >= 3 && form.items[1].kind == .Vector && len(form.items[1].items) == 2 && form.items[1].items[0].kind == .Symbol {
            name_form = form.items[1].items[0]
            coll_form = form.items[1].items[1]
            body_start = 2
        } else {
            return Compile_Error{message = "each expects [name collection] and body", span = form.span}, false
        }
        name := map_name(name_form.text)
        coll, err_coll, ok_coll := emit_expr(e, coll_form)
        if !ok_coll {
            return err_coll, false
        }
        emit_indent(e)
        strings.write_string(&e.builder, "for ")
        strings.write_string(&e.builder, name)
        strings.write_string(&e.builder, " in ")
        strings.write_string(&e.builder, coll)
        strings.write_string(&e.builder, " {")
        emit_raw_newline(e)
        e.indent += 1
        body: [dynamic]CST_Form
        for item in form.items[body_start:] {
            append(&body, item)
        }
        err_body, ok_body := emit_body_forms(e, body[:], Return_Spec{kind = .None})
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "for":
        if len(form.items) < 3 {
            return Compile_Error{message = "for expects condition and body", span = form.span}, false
        }
        cond, err_cond, ok_cond := emit_expr(e, form.items[1])
        if !ok_cond {
            return err_cond, false
        }
        emit_indent(e)
        strings.write_string(&e.builder, "for ")
        strings.write_string(&e.builder, cond)
        strings.write_string(&e.builder, " {")
        emit_raw_newline(e)
        e.indent += 1
        body: [dynamic]CST_Form
        for item in form.items[2:] {
            append(&body, item)
        }
        err_body, ok_body := emit_body_forms(e, body[:], Return_Spec{kind = .None})
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
        return {}, true
    case "odin":
        raw, err_raw, ok_raw := emit_expr(e, form)
        if !ok_raw {
            return err_raw, false
        }
        emit_prefixed_expr(e, "", raw)
        return {}, true
    case:
        expr, err_expr, ok_expr := emit_expr(e, form)
        if !ok_expr {
            return err_expr, false
        }
        if last_in_proc && returns.kind == .Single {
            emit_prefixed_expr(e, "return ", expr)
        } else {
            emit_prefixed_expr(e, "", expr)
        }
        return {}, true
    }
}

emit_return_spec :: proc(e: ^Emitter, returns: Return_Spec) {
    #partial switch returns.kind {
    case .None:
        return
    case .Single:
        fmt.sbprintf(&e.builder, " -> %s", returns.single_ty)
    case .Named:
        strings.write_string(&e.builder, " -> (")
        for field, idx in returns.named {
            if idx > 0 {
                strings.write_string(&e.builder, ", ")
            }
            fmt.sbprintf(&e.builder, "%s: %s", field.name, field.ty)
        }
        strings.write_byte(&e.builder, ')')
    }
}

emit_proc_directives :: proc(e: ^Emitter, directives: []string) {
    for directive in directives {
        strings.write_string(&e.builder, directive)
        strings.write_byte(&e.builder, ' ')
    }
}

emit_proc_suffix_directives :: proc(e: ^Emitter, directives: []string) {
    for directive in directives {
        strings.write_byte(&e.builder, ' ')
        strings.write_string(&e.builder, directive)
    }
}

emit_decl :: proc(e: ^Emitter, decl: IR_Decl) -> (Compile_Error, bool) {
    for line in decl.doc_lines {
        emit_line(e, line)
    }
    has_pending_proc_directives := len(e.pending_prefix_directives) > 0 || len(e.pending_suffix_directives) > 0
    if has_pending_proc_directives && decl.kind != .Proc && decl.kind != .Raw {
        return Compile_Error{message = "procedure directive must be followed by a proc declaration", span = decl.span}, false
    }
    #partial switch decl.kind {
    case .Package:
        emit_line(e, fmt.tprintf("package %s", decl.package_name))
    case .Import:
        if decl.import_decl.has_alias {
            emit_line(e, fmt.tprintf("import %s %s", decl.import_decl.alias, decl.import_decl.path))
        } else {
            emit_line(e, fmt.tprintf("import %s", decl.import_decl.path))
        }
    case .Const:
        value, err_value, ok_value := emit_expr(e, decl.const_decl.value)
        if !ok_value {
            return err_value, false
        }
        if decl.const_decl.has_ty {
            emit_line(e, fmt.tprintf("%s: %s : %s", decl.const_decl.name, decl.const_decl.ty, value))
        } else {
            emit_line(e, fmt.tprintf("%s :: %s", decl.const_decl.name, value))
        }
    case .Struct:
        emit_indent(e)
        strings.write_string(&e.builder, decl.struct_decl.name)
        strings.write_string(&e.builder, " :: struct {")
        emit_raw_newline(e)
        e.indent += 1
        for field in decl.struct_decl.fields {
            emit_line(e, fmt.tprintf("%s: %s,", field.name, field.ty))
        }
        e.indent -= 1
        emit_line(e, "}")
    case .Enum:
        emit_indent(e)
        strings.write_string(&e.builder, decl.enum_decl.name)
        strings.write_string(&e.builder, " :: enum {")
        emit_raw_newline(e)
        e.indent += 1
        for variant in decl.enum_decl.variants {
            if variant.has_value {
                value, err_value, ok_value := emit_expr(e, variant.value)
                if !ok_value {
                    return err_value, false
                }
                emit_line(e, fmt.tprintf("%s = %s,", variant.name, value))
            } else {
                emit_line(e, fmt.tprintf("%s,", variant.name))
            }
        }
        e.indent -= 1
        emit_line(e, "}")
    case .Union:
        emit_indent(e)
        strings.write_string(&e.builder, decl.union_decl.name)
        strings.write_string(&e.builder, " :: union {")
        emit_raw_newline(e)
        e.indent += 1
        for variant in decl.union_decl.variants {
            emit_line(e, fmt.tprintf("%s,", variant.ty))
        }
        e.indent -= 1
        emit_line(e, "}")
    case .Proc:
        emit_indent(e)
        fmt.sbprintf(&e.builder, "%s :: ", decl.proc_decl.name)
        emit_proc_directives(e, e.pending_prefix_directives[:])
        emit_proc_directives(e, decl.proc_decl.prefix_directives[:])
        strings.write_string(&e.builder, "proc(")
        for param, idx in decl.proc_decl.params {
            if idx > 0 {
                strings.write_string(&e.builder, ", ")
            }
            fmt.sbprintf(&e.builder, "%s: %s", param.name, param.ty)
        }
        strings.write_byte(&e.builder, ')')
        emit_return_spec(e, decl.proc_decl.returns)
        emit_proc_suffix_directives(e, e.pending_suffix_directives[:])
        emit_proc_suffix_directives(e, decl.proc_decl.suffix_directives[:])
        clear(&e.pending_prefix_directives)
        clear(&e.pending_suffix_directives)
        strings.write_string(&e.builder, " {")
        emit_raw_newline(e)
        e.indent += 1
        err_body, ok_body := emit_body_forms(e, decl.proc_decl.body[:], decl.proc_decl.returns)
        if !ok_body {
            return err_body, false
        }
        e.indent -= 1
        emit_line(e, "}")
    case .Raw:
        if raw_is_proc_directive(decl.raw_text) {
            if is_proc_prefix_directive(decl.raw_text) {
                append(&e.pending_prefix_directives, decl.raw_text)
            } else {
                append(&e.pending_suffix_directives, decl.raw_text)
            }
            return {}, true
        }
        if has_pending_proc_directives && !raw_attaches_to_next_decl(decl.raw_text) {
            return Compile_Error{message = "procedure directive must be followed by a proc declaration", span = decl.span}, false
        }
        if raw_attaches_to_next_decl(decl.raw_text) {
            e.attach_next_decl = true
        }
        emit_prefixed_expr(e, "", decl.raw_text)
    case:
        return Compile_Error{message = "unsupported declaration kind", span = decl.span}, false
    }
    return {}, true
}

emit_core_map_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_map :: proc(f: proc(x: $T) -> $U, xs: []T) -> [dynamic]U {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]U)")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "append(&out, f(x))")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_filter_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_filter :: proc(pred: proc(x: $T) -> bool, xs: []T) -> [dynamic]T {")
    e.indent += 1
    emit_line(e, "out := make([dynamic]T)")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "if pred(x) {")
    e.indent += 1
    emit_line(e, "append(&out, x)")
    e.indent -= 1
    emit_line(e, "}")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return out")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_reduce_helper :: proc(e: ^Emitter) {
    emit_line(e, "odinl_reduce :: proc(f: proc(acc: $U, x: $T) -> U, init: U, xs: []T) -> U {")
    e.indent += 1
    emit_line(e, "acc := init")
    emit_line(e, "for x in xs {")
    e.indent += 1
    emit_line(e, "acc = f(acc, x)")
    e.indent -= 1
    emit_line(e, "}")
    emit_line(e, "return acc")
    e.indent -= 1
    emit_line(e, "}")
}

emit_core_helpers :: proc(e: ^Emitter, features: Emitter_Features) {
    if !(features.core_map || features.core_filter || features.core_reduce) {
        return
    }

    emit_raw_newline(e)
    if features.core_map {
        emit_core_map_helper(e)
    }
    if features.core_filter {
        if features.core_map {
            emit_raw_newline(e)
        }
        emit_core_filter_helper(e)
    }
    if features.core_reduce {
        if features.core_map || features.core_filter {
            emit_raw_newline(e)
        }
        emit_core_reduce_helper(e)
    }
}

emit_decls :: proc(decls: []IR_Decl) -> (string, Compile_Error, bool) {
    result, err, ok := emit_decls_with_source_map(decls)
    return result.output, err, ok
}

emit_decls_with_source_map :: proc(decls: []IR_Decl) -> (Emit_Result, Compile_Error, bool) {
    result := Emit_Result{}
    features := Emitter_Features{}
    e := Emitter{
        builder  = strings.builder_make(),
        features = &features,
        line     = 1,
    }
    defer strings.builder_destroy(&e.builder)
    for decl in decls {
        if decl.kind == .Union {
            append(&e.unions, decl.union_decl)
        }
    }
    for decl, idx in decls {
        start_line := e.line
        err_decl, ok_decl := emit_decl(&e, decl)
        if !ok_decl {
            return result, err_decl, false
        }
        emitted_lines := e.line > start_line
        end_line := e.line - 1
        if !emitted_lines {
            end_line = start_line
        }
        append(&result.source_map, Source_Map_Entry{
            generated_start_line = start_line,
            generated_end_line   = end_line,
            source_span          = decl.span,
        })
        if idx+1 < len(decls) && emitted_lines {
            if e.attach_next_decl {
                e.attach_next_decl = false
                continue
            }
            strings.write_byte(&e.builder, '\n')
            e.line += 1
        }
    }
    emit_core_helpers(&e, features)
    if features.dynamic_literals {
        output_builder := strings.builder_make()
        defer strings.builder_destroy(&output_builder)
        strings.write_string(&output_builder, "#+feature dynamic-literals\n")
        strings.write_string(&output_builder, strings.to_string(e.builder))
        for &entry in result.source_map {
            entry.generated_start_line += 1
            entry.generated_end_line += 1
        }
        result.output = strings.clone(strings.to_string(output_builder))
        return result, {}, true
    }
    result.output = strings.clone(strings.to_string(e.builder))
    return result, {}, true
}

emit_ir_program :: proc(program: IR_Program) -> (string, Compile_Error, bool) {
    return emit_decls(program.decls[:])
}

emit_ir_program_with_source_map :: proc(program: IR_Program) -> (Emit_Result, Compile_Error, bool) {
    return emit_decls_with_source_map(program.decls[:])
}

program_imports_fmt :: proc(program: IR_Program) -> bool {
    for decl in program.decls {
        if decl.kind == .Import && decl.import_decl.path == "\"core:fmt\"" {
            if !decl.import_decl.has_alias || decl.import_decl.alias == "fmt" {
                return true
            }
        }
    }
    return false
}

proc_decl_is_main :: proc(decl: IR_Decl) -> bool {
    return decl.kind == .Proc && decl.proc_decl.name == "main"
}

make_symbol_form :: proc(text: string, span: Span) -> CST_Form {
    return CST_Form{
        kind = .Symbol,
        text = text,
        span = span,
    }
}

make_println_form :: proc(value: CST_Form) -> CST_Form {
    items: [dynamic]CST_Form
    append(&items, make_symbol_form("fmt.println", value.span))
    append(&items, value)
    return CST_Form{
        kind = .List,
        items = items,
        span = value.span,
    }
}

emit_eval_program_with_source_map :: proc(program: IR_Program, eval_form: CST_Form, no_print: bool) -> (Emit_Result, Compile_Error, bool) {
    decls: [dynamic]IR_Decl
    append(&decls, IR_Decl{
        kind = .Package,
        span = eval_form.span,
        package_name = "main",
    })

    if !no_print && !program_imports_fmt(program) {
        append(&decls, IR_Decl{
            kind = .Import,
            span = eval_form.span,
            import_decl = Import_Decl{
                alias = "fmt",
                path = "\"core:fmt\"",
                has_alias = true,
            },
        })
    }

    for decl, idx in program.decls {
        if decl.kind == .Package {
            continue
        }
        if proc_decl_is_main(decl) {
            continue
        }
        if decl.kind == .Raw && idx+1 < len(program.decls) && proc_decl_is_main(program.decls[idx+1]) {
            if raw_is_proc_directive(decl.raw_text) || raw_attaches_to_next_decl(decl.raw_text) {
                continue
            }
        }
        append(&decls, decl)
    }

    body: [dynamic]CST_Form
    if no_print {
        append(&body, eval_form)
    } else {
        append(&body, make_println_form(eval_form))
    }

    append(&decls, IR_Decl{
        kind = .Proc,
        span = eval_form.span,
        proc_decl = Proc_Decl{
            name = "main",
            body = body,
        },
    })

    return emit_decls_with_source_map(decls[:])
}

decl_name :: proc(decl: IR_Decl) -> string {
    #partial switch decl.kind {
    case .Const:
        return decl.const_decl.name
    case .Struct:
        return decl.struct_decl.name
    case .Enum:
        return decl.enum_decl.name
    case .Union:
        return decl.union_decl.name
    case .Proc:
        return decl.proc_decl.name
    }
    return ""
}

decl_matches :: proc(a, b: IR_Decl) -> bool {
    if a.kind != b.kind {
        return false
    }
    if a.kind == .Import {
        return a.import_decl.path == b.import_decl.path &&
               a.import_decl.alias == b.import_decl.alias &&
               a.import_decl.has_alias == b.import_decl.has_alias
    }
    a_name := decl_name(a)
    if a_name == "" {
        return false
    }
    return a_name == decl_name(b)
}

emit_eval_decl_program_with_source_map :: proc(program: IR_Program, eval_decl: IR_Decl) -> (Emit_Result, Compile_Error, bool) {
    decls: [dynamic]IR_Decl
    append(&decls, IR_Decl{
        kind = .Package,
        span = eval_decl.span,
        package_name = "main",
    })

    found_eval_decl := eval_decl.kind == .Ignored ||
                       eval_decl.kind == .Package
    if eval_decl.kind == .Import {
        for decl in program.decls {
            if decl_matches(decl, eval_decl) {
                found_eval_decl = true
                break
            }
        }
        if !found_eval_decl {
            append(&decls, eval_decl)
        }
    }

    for decl, idx in program.decls {
        if decl.kind == .Package {
            continue
        }
        if proc_decl_is_main(decl) && !proc_decl_is_main(eval_decl) {
            continue
        }
        if decl.kind == .Raw && idx+1 < len(program.decls) && proc_decl_is_main(program.decls[idx+1]) {
            if !proc_decl_is_main(eval_decl) &&
               (raw_is_proc_directive(decl.raw_text) || raw_attaches_to_next_decl(decl.raw_text)) {
                continue
            }
        }
        if decl_matches(decl, eval_decl) {
            found_eval_decl = true
        }
        append(&decls, decl)
    }

    if !found_eval_decl && eval_decl.kind != .Import {
        append(&decls, eval_decl)
    }

    if !proc_decl_is_main(eval_decl) {
        append(&decls, IR_Decl{
            kind = .Proc,
            span = eval_decl.span,
            proc_decl = Proc_Decl{
                name = "main",
            },
        })
    }

    return emit_decls_with_source_map(decls[:])
}

emit_eval_program :: proc(program: IR_Program, eval_form: CST_Form, no_print: bool) -> (string, Compile_Error, bool) {
    result, err, ok := emit_eval_program_with_source_map(program, eval_form, no_print)
    if !ok {
        return "", err, false
    }
    defer delete(result.source_map)
    return result.output, {}, true
}
