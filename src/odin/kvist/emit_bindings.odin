package kvist

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

Binding :: struct {
    is_destructure:      bool,
    is_result_binding:   bool,
    is_data_destructure: bool,
    name:                string,
    pattern:             [dynamic]string,
    target:              CST_Form,
    is_typed:            bool,
    ty:                  string,
    deferred_delete:     bool,
    err_deferred_delete: bool,
    defer_with_cleanup:  bool,
    cleanup:             CST_Form,
    or_modifier:         string,
    target_span:         Span,
    value:               CST_Form,
}

data_binding_rhs_is_data :: proc(e: ^Emitter, form: CST_Form) -> bool {
    if form.kind == .Vector || form.kind == .Brace || form.kind == .Set {
        return true
    }
    if form.kind == .List && len(form.items) > 0 && form.items[0].kind == .Symbol &&
       (form.items[0].text == "quote" || form.items[0].text == "quasiquote") {
        return true
    }
    ty, ok_ty := obvious_form_type(e, form)
    return ok_ty && ty == "Data"
}

binding_is_data_destructure :: proc(e: ^Emitter, binding: Binding) -> bool {
    if binding.is_data_destructure || binding.target.kind == .Brace {
        return true
    }
    return binding.target.kind == .Vector && data_binding_rhs_is_data(e, binding.value)
}

binding_native_sequence_type :: proc(e: ^Emitter, binding: Binding) -> (collection_ty, element_ty: string, ok: bool) {
    if !binding.is_destructure || binding.is_result_binding || binding.target.kind != .Vector {
        return "", "", false
    }
    if binding.value.kind == .List &&
       len(binding.value.items) > 0 &&
       binding.value.items[0].kind == .Symbol {
        head_name := map_name(binding.value.items[0].text)
        if proc_decl, ok_proc := find_proc_decl(e, head_name); ok_proc && proc_decl.returns.kind != .Single {
            return "", "", false
        }
    }
    ok_collection_ty: bool
    collection_ty, ok_collection_ty = obvious_form_type(e, binding.value)
    if !ok_collection_ty {
        probe := Binding{name = "kvist_sequence", value = binding.value}
        collection_ty, ok_collection_ty = obvious_binding_type(e, probe)
    }
    if !ok_collection_ty ||
       (!type_text_is_fixed_array(collection_ty) &&
        !type_text_is_slice(collection_ty) &&
        !type_text_is_dynamic_array(collection_ty)) {
        return "", "", false
    }
    ok_element_ty: bool
    element_ty, ok_element_ty = collection_element_type(collection_ty)
    if !ok_element_ty {
        return "", "", false
    }
    return collection_ty, element_ty, true
}

binding_is_native_sequence_destructure :: proc(e: ^Emitter, binding: Binding) -> bool {
    _, _, ok := binding_native_sequence_type(e, binding)
    return ok
}

validate_native_sequence_binding_pattern :: proc(binding: Binding) -> (Compile_Error, bool) {
    if len(binding.target.items) == 0 {
        return Compile_Error{
            message = "native sequence destructuring expects at least one binding",
            span = binding.target.span,
        }, false
    }
    for item in binding.target.items {
        if item.kind == .Symbol && item.text == "&" {
            return Compile_Error{
                message = "native sequence destructuring does not yet support rest bindings (`&`)",
                span = item.span,
            }, false
        }
        if item.kind == .Keyword && item.text == ":as" {
            return Compile_Error{
                message = "native sequence destructuring does not yet support `:as` bindings",
                span = item.span,
            }, false
        }
        if item.kind == .Vector || item.kind == .Brace {
            return Compile_Error{
                message = "native sequence destructuring does not yet support nested patterns",
                span = item.span,
            }, false
        }
        if item.kind != .Symbol {
            return Compile_Error{
                message = "native sequence destructuring expects symbols or _",
                span = item.span,
            }, false
        }
    }
    return {}, true
}

fixed_array_type_length :: proc(type_text: string) -> (int, bool) {
    if !type_text_is_fixed_array(type_text) {
        return 0, false
    }
    close := strings.index(type_text, "]")
    if close <= 1 {
        return 0, false
    }
    length, ok := strconv.parse_int(type_text[1:close])
    if !ok || length < 0 {
        return 0, false
    }
    return length, true
}

validate_native_sequence_binding_bounds :: proc(binding: Binding, collection_ty: string) -> (Compile_Error, bool) {
    length, known_length := fixed_array_type_length(collection_ty)
    if !known_length || len(binding.target.items) <= length {
        return {}, true
    }
    return Compile_Error{
        message = fmt.tprintf(
            "native sequence pattern requires %d elements, but %s contains %d",
            len(binding.target.items),
            collection_ty,
            length,
        ),
        span = binding.target.items[length].span,
    }, false
}

emit_native_sequence_let_binding :: proc(e: ^Emitter, binding: Binding) -> (Compile_Error, bool) {
    collection_ty, element_ty, ok_type := binding_native_sequence_type(e, binding)
    if !ok_type {
        return Compile_Error{message = "expected a statically known native sequence", span = binding.value.span}, false
    }
    err_pattern, ok_pattern := validate_native_sequence_binding_pattern(binding)
    if !ok_pattern {
        return err_pattern, false
    }
    err_bounds, ok_bounds := validate_native_sequence_binding_bounds(binding, collection_ty)
    if !ok_bounds {
        return err_bounds, false
    }
    err_owned, bad_owned := owned_result_usage_error(binding.value, true, e)
    if bad_owned {
        return err_owned, false
    }
    value, err_value, ok_value := emit_expr_for_expected_type(e, binding.value, collection_ty)
    if !ok_value {
        return err_value, false
    }
    source := thread_temp_name(e)
    emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", source), value, binding.value.span)
    if form_produces_owned_value(binding.value, e) {
        emit_line(e, fmt.tprintf("defer delete(%s)", source))
    }
    if type_text_is_slice(collection_ty) || type_text_is_dynamic_array(collection_ty) {
        emit_line_mapped(
            e,
            fmt.tprintf(
                "assert(len(%s) >= %d, \"native sequence pattern requires at least %d elements\")",
                source,
                len(binding.target.items),
                len(binding.target.items),
            ),
            binding.target.span,
        )
    }
    for item, idx in binding.target.items {
        indexed := fmt.tprintf("%s[%d]", source, idx)
        if item.text == "_" {
            emit_line_mapped(e, fmt.tprintf("_ = %s", indexed), item.span)
            continue
        }
        name := map_name(item.text)
        if type_text_has_managed_lifecycle(e, element_ty) {
            cloned := managed_clone_value_text(e, element_ty, indexed)
            emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", name), cloned, item.span)
            emit_line(e, fmt.tprintf("defer %s", managed_destroy_value_text(e, element_ty, name)))
        } else {
            emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", name), indexed, item.span)
        }
    }
    return {}, true
}

data_pattern_append_name :: proc(names: ^[dynamic]string, form: CST_Form) -> (Compile_Error, bool) {
    if form.kind != .Symbol || form.text == "_" || form.text == "&" {
        return {}, true
    }
    name := map_name(form.text)
    for existing in names^ {
        if existing == name {
            return Compile_Error{message = fmt.tprintf("duplicate Data pattern binding `%s`", form.text), span = form.span}, false
        }
    }
    append(names, name)
    return {}, true
}

validate_data_pattern_names :: proc(form: CST_Form, names: ^[dynamic]string, let_pattern: bool) -> (Compile_Error, bool) {
    #partial switch form.kind {
    case .Symbol:
        return data_pattern_append_name(names, form)
    case .Vector:
        saw_rest := false
        saw_as := false
        i := 0
        for i < len(form.items) {
            item := form.items[i]
            if item.kind == .Symbol && item.text == "&" {
                if saw_rest || saw_as || i+1 >= len(form.items) {
                    return Compile_Error{message = "sequential Data pattern expects one binding after &", span = item.span}, false
                }
                saw_rest = true
                err_rest, ok_rest := validate_data_pattern_names(form.items[i+1], names, let_pattern)
                if !ok_rest {
                    return err_rest, false
                }
                i += 2
                continue
            }
            if item.kind == .Keyword && item.text == ":as" {
                if !let_pattern || saw_as || i+1 >= len(form.items) || i+2 != len(form.items) {
                    return Compile_Error{message = "sequential let destructuring expects :as followed by one final binding", span = item.span}, false
                }
                if form.items[i+1].kind != .Symbol {
                    return Compile_Error{message = "sequential :as expects a symbol binding", span = form.items[i+1].span}, false
                }
                saw_as = true
                err_as, ok_as := validate_data_pattern_names(form.items[i+1], names, let_pattern)
                if !ok_as {
                    return err_as, false
                }
                i += 2
                continue
            }
            if saw_rest {
                return Compile_Error{message = "only :as may follow a sequential & binding", span = item.span}, false
            }
            err_item, ok_item := validate_data_pattern_names(item, names, let_pattern)
            if !ok_item {
                return err_item, false
            }
            i += 1
        }
    case .Brace:
        if len(form.items)%2 != 0 {
            return Compile_Error{message = "map Data pattern expects key/value pairs", span = form.span}, false
        }
        i := 0
        for i < len(form.items) {
            key := form.items[i]
            value := form.items[i+1]
            if key.kind == .Keyword {
                if key.text == ":as" {
                    if !let_pattern {
                        return Compile_Error{message = "map :as is only valid in let destructuring; use (as name pattern) in match", span = key.span}, false
                    }
                    if value.kind != .Symbol {
                        return Compile_Error{message = "map :as expects a symbol binding", span = value.span}, false
                    }
                    err_as, ok_as := validate_data_pattern_names(value, names, let_pattern)
                    if !ok_as {
                        return err_as, false
                    }
                    i += 2
                    continue
                }
                if key.text == ":or" {
                    if !let_pattern || value.kind != .Brace {
                        return Compile_Error{message = "map :or expects a defaults map in let destructuring", span = value.span}, false
                    }
                    i += 2
                    continue
                }
                shorthand := key.text == ":keys" || key.text == ":strs" || key.text == ":syms" || strings.has_suffix(key.text, "/keys")
                if shorthand {
                    if value.kind != .Vector {
                        return Compile_Error{message = fmt.tprintf("%s destructuring expects a vector of symbols", key.text), span = value.span}, false
                    }
                    for name_form in value.items {
                        if name_form.kind != .Symbol {
                            return Compile_Error{message = fmt.tprintf("%s destructuring expects symbols", key.text), span = name_form.span}, false
                        }
                        err_name, ok_name := data_pattern_append_name(names, name_form)
                        if !ok_name {
                            return err_name, false
                        }
                    }
                    i += 2
                    continue
                }
            }
            err_target, ok_target := validate_data_pattern_names(key, names, let_pattern)
            if !ok_target {
                return err_target, false
            }
            i += 2
        }
    case:
        if let_pattern {
            return Compile_Error{message = "let Data destructuring expects symbol, vector, or map binding forms", span = form.span}, false
        }
    }
    return {}, true
}

data_pattern_default_for_name :: proc(map_pattern: CST_Form, name: string) -> (CST_Form, bool) {
    if map_pattern.kind != .Brace {
        return {}, false
    }
    i := 0
    for i+1 < len(map_pattern.items) {
        if map_pattern.items[i].kind == .Keyword && map_pattern.items[i].text == ":or" {
            defaults := map_pattern.items[i+1]
            if defaults.kind == .Brace {
                j := 0
                for j+1 < len(defaults.items) {
                    if defaults.items[j].kind == .Symbol && map_name(defaults.items[j].text) == name {
                        return defaults.items[j+1], true
                    }
                    j += 2
                }
            }
        }
        i += 2
    }
    return {}, false
}

emit_owned_data_local :: proc(e: ^Emitter, name, value: string, span: Span, already_owned: bool) {
    text := value
    if !already_owned {
        text = emit_call_text("kvist_data_retain", []string{value})
    }
    emit_prefixed_expr_mapped(e, fmt.tprintf("%s := ", name), text, span)
    emit_line(e, fmt.tprintf("defer kvist_data_release(%s)", name))
    bind_local_type(e, name, "Data")
}

emit_data_pattern_literal_temp :: proc(e: ^Emitter, form: CST_Form) -> (string, Compile_Error, bool) {
    mark_data_type(e)
    value, _, err_value, ok_value := emit_contextual_data_value(e, form)
    if !ok_value {
        return "", err_value, false
    }
    temp := thread_temp_name(e)
    emit_owned_data_local(e, temp, value, form.span, true)
    return temp, {}, true
}

data_shorthand_key :: proc(kind_text, local_text: string, span: Span) -> CST_Form {
    if kind_text == ":strs" {
        return CST_Form{kind = .String, text = local_text, span = span}
    }
    if kind_text == ":syms" {
        quoted := CST_Form{kind = .Symbol, text = local_text, span = span}
        return make_list_form({make_symbol_form("quote", span), quoted}, span)
    }
    namespace := ""
    if strings.has_suffix(kind_text, "/keys") && kind_text != ":keys" {
        namespace = kind_text[1:len(kind_text)-len("/keys")]
    }
    text := fmt.tprintf(":%s", local_text)
    if namespace != "" {
        text = fmt.tprintf(":%s/%s", namespace, local_text)
    }
    return CST_Form{kind = .Keyword, text = text, span = span}
}

emit_data_pattern_bindings :: proc(e: ^Emitter, pattern: CST_Form, source: string, defaults_owner: CST_Form = {}) -> (Compile_Error, bool) {
    #partial switch pattern.kind {
    case .Symbol:
        if pattern.text == "_" {
            return {}, true
        }
        name := map_name(pattern.text)
        emit_owned_data_local(e, name, source, pattern.span, false)
        return {}, true
    case .Vector:
        item_index := 0
        i := 0
        for i < len(pattern.items) {
            item := pattern.items[i]
            if item.kind == .Symbol && item.text == "&" {
                rest_temp := thread_temp_name(e)
                rest_value := fmt.tprintf("kvist_data_rest_from(%s, %d)", source, item_index)
                emit_owned_data_local(e, rest_temp, rest_value, item.span, true)
                err_rest, ok_rest := emit_data_pattern_bindings(e, pattern.items[i+1], rest_temp)
                if !ok_rest {
                    return err_rest, false
                }
                i += 2
                continue
            }
            if item.kind == .Keyword && item.text == ":as" {
                return emit_data_pattern_bindings(e, pattern.items[i+1], source)
            }
            child := thread_temp_name(e)
            emit_line_mapped(e, fmt.tprintf("%s := kvist_data_nth_or_nil(%s, %d)", child, source, item_index), item.span)
            err_child, ok_child := emit_data_pattern_bindings(e, item, child)
            if !ok_child {
                return err_child, false
            }
            item_index += 1
            i += 1
        }
        return {}, true
    case .Brace:
        i := 0
        for i < len(pattern.items) {
            key_form := pattern.items[i]
            target := pattern.items[i+1]
            if key_form.kind == .Keyword && (key_form.text == ":or") {
                i += 2
                continue
            }
            if key_form.kind == .Keyword && key_form.text == ":as" {
                err_as, ok_as := emit_data_pattern_bindings(e, target, source)
                if !ok_as {
                    return err_as, false
                }
                i += 2
                continue
            }
            if key_form.kind == .Keyword &&
               (key_form.text == ":keys" || key_form.text == ":strs" || key_form.text == ":syms" || strings.has_suffix(key_form.text, "/keys")) {
                for local_form in target.items {
                    lookup_key := data_shorthand_key(key_form.text, local_form.text, key_form.span)
                    key_temp, err_key, ok_key := emit_data_pattern_literal_temp(e, lookup_key)
                    if !ok_key {
                        return err_key, false
                    }
                    child := thread_temp_name(e)
                    present := thread_temp_name(e)
                    emit_line(e, fmt.tprintf("%s, %s := kvist_data_get_present(%s, %s)", child, present, source, key_temp))
                    local_name := map_name(local_form.text)
                    if default_form, has_default := data_pattern_default_for_name(pattern, local_name); has_default {
                        owned_child := thread_temp_name(e)
                        emit_line(e, fmt.tprintf("%s := Data{{}}", owned_child))
                        emit_line(e, fmt.tprintf("if %s {{", present))
                        e.indent += 1
                        emit_line(e, fmt.tprintf("%s = kvist_data_retain(%s)", owned_child, child))
                        e.indent -= 1
                        emit_line(e, "} else {")
                        e.indent += 1
                        fallback, err_fallback, ok_fallback := emit_expr_for_expected_type(e, default_form, "Data")
                        if !ok_fallback {
                            return err_fallback, false
                        }
                        if !form_produces_owned_managed_type(e, default_form, "Data") {
                            fallback = emit_call_text("kvist_data_retain", []string{fallback})
                        }
                        emit_prefixed_expr_mapped(e, fmt.tprintf("%s = ", owned_child), fallback, default_form.span)
                        e.indent -= 1
                        emit_line(e, "}")
                        emit_line(e, fmt.tprintf("defer kvist_data_release(%s)", owned_child))
                        child = owned_child
                    }
                    err_local, ok_local := emit_data_pattern_bindings(e, local_form, child)
                    if !ok_local {
                        return err_local, false
                    }
                }
                i += 2
                continue
            }
            key_temp, err_key, ok_key := emit_data_pattern_literal_temp(e, target)
            if !ok_key {
                return err_key, false
            }
            child := thread_temp_name(e)
            present := thread_temp_name(e)
            emit_line(e, fmt.tprintf("%s, %s := kvist_data_get_present(%s, %s)", child, present, source, key_temp))
            if key_form.kind == .Symbol {
                local_name := map_name(key_form.text)
                if default_form, has_default := data_pattern_default_for_name(pattern, local_name); has_default {
                    owned_child := thread_temp_name(e)
                    emit_line(e, fmt.tprintf("%s := Data{{}}", owned_child))
                    emit_line(e, fmt.tprintf("if %s {{", present))
                    e.indent += 1
                    emit_line(e, fmt.tprintf("%s = kvist_data_retain(%s)", owned_child, child))
                    e.indent -= 1
                    emit_line(e, "} else {")
                    e.indent += 1
                    fallback, err_fallback, ok_fallback := emit_expr_for_expected_type(e, default_form, "Data")
                    if !ok_fallback {
                        return err_fallback, false
                    }
                    if !form_produces_owned_managed_type(e, default_form, "Data") {
                        fallback = emit_call_text("kvist_data_retain", []string{fallback})
                    }
                    emit_prefixed_expr_mapped(e, fmt.tprintf("%s = ", owned_child), fallback, default_form.span)
                    e.indent -= 1
                    emit_line(e, "}")
                    emit_line(e, fmt.tprintf("defer kvist_data_release(%s)", owned_child))
                    child = owned_child
                }
            }
            err_target, ok_target := emit_data_pattern_bindings(e, key_form, child, pattern)
            if !ok_target {
                return err_target, false
            }
            i += 2
        }
        return {}, true
    case:
        return Compile_Error{message = "unsupported Data destructuring pattern", span = pattern.span}, false
    }
}

emit_data_let_binding :: proc(e: ^Emitter, binding: Binding) -> (Compile_Error, bool) {
    if !data_binding_rhs_is_data(e, binding.value) {
        return Compile_Error{
            message = "Data destructuring requires a statically known Data value; bind or annotate an opaque imported result as Data first",
            span = binding.value.span,
        }, false
    }
    names: [dynamic]string
    defer delete(names)
    err_pattern, ok_pattern := validate_data_pattern_names(binding.target, &names, true)
    if !ok_pattern {
        return err_pattern, false
    }
    mark_data_type(e)
    value, err_value, ok_value := emit_expr_for_expected_type(e, binding.value, "Data")
    if !ok_value {
        return err_value, false
    }
    source := thread_temp_name(e)
    emit_owned_data_local(e, source, value, binding.value.span, form_produces_owned_managed_type(e, binding.value, "Data"))
    return emit_data_pattern_bindings(e, binding.target, source)
}

match_pattern_is_catchall :: proc(form: CST_Form) -> bool {
    return (form.kind == .Keyword && form.text == ":else") ||
           (form.kind == .Symbol && form.text == "_")
}

match_kind_name :: proc(form: CST_Form) -> (string, bool) {
    if form.kind != .Keyword {
        return "", false
    }
    switch form.text {
    case ":nil": return "Nil", true
    case ":bool": return "Bool", true
    case ":int": return "Int", true
    case ":float": return "Float", true
    case ":string": return "String", true
    case ":symbol": return "Symbol", true
    case ":keyword": return "Keyword", true
    case ":list": return "List", true
    case ":vector": return "Vector", true
    case ":map": return "Map", true
    case ":set": return "Set", true
    case ":tagged": return "Tagged", true
    }
    return "", false
}

match_pattern_is_literal :: proc(form: CST_Form) -> bool {
    #partial switch form.kind {
    case .Nil, .Bool, .Number, .String, .Keyword:
        return true
    case .List:
        return len(form.items) == 2 &&
               form.items[0].kind == .Symbol &&
               form.items[0].text == "quote" &&
               form.items[1].kind == .Symbol
    case:
        return false
    }
}

match_literals_equal :: proc(a, b: CST_Form) -> bool {
    if !match_pattern_is_literal(a) || !match_pattern_is_literal(b) || a.kind != b.kind {
        return false
    }
    if a.kind == .Nil {
        return true
    }
    if a.kind == .List {
        return a.items[1].text == b.items[1].text
    }
    return a.text == b.text
}

validate_match_pattern :: proc(form: CST_Form, names: ^[dynamic]string) -> (Compile_Error, bool) {
    if match_pattern_is_catchall(form) || match_pattern_is_literal(form) {
        return {}, true
    }
    #partial switch form.kind {
    case .Symbol:
        return data_pattern_append_name(names, form)
    case .Vector:
        saw_rest := false
        i := 0
        for i < len(form.items) {
            if form.items[i].kind == .Symbol && form.items[i].text == "&" {
                if saw_rest || i+2 != len(form.items) {
                    return Compile_Error{message = "match sequence pattern expects one final binding after &", span = form.items[i].span}, false
                }
                saw_rest = true
                err_rest, ok_rest := validate_match_pattern(form.items[i+1], names)
                if !ok_rest {
                    return err_rest, false
                }
                i += 2
                continue
            }
            err_item, ok_item := validate_match_pattern(form.items[i], names)
            if !ok_item {
                return err_item, false
            }
            i += 1
        }
    case .Brace:
        if len(form.items)%2 != 0 {
            return Compile_Error{message = "match map pattern expects literal-key/pattern pairs", span = form.span}, false
        }
        i := 0
        for i < len(form.items) {
            if !match_pattern_is_literal(form.items[i]) {
                return Compile_Error{message = "match map keys must be compile-time Data literals", span = form.items[i].span}, false
            }
            err_value, ok_value := validate_match_pattern(form.items[i+1], names)
            if !ok_value {
                return err_value, false
            }
            i += 2
        }
    case .Set:
        for item in form.items {
            if !match_pattern_is_literal(item) {
                return Compile_Error{message = "match set patterns are exact and may contain only literals", span = item.span}, false
            }
        }
    case .List:
        if len(form.items) != 3 || form.items[0].kind != .Symbol {
            return Compile_Error{message = "match list pattern expects (as name pattern) or (kind :kind pattern)", span = form.span}, false
        }
        if form.items[0].text == "as" {
            if form.items[1].kind != .Symbol || form.items[1].text == "_" {
                return Compile_Error{message = "match as pattern expects a binding name", span = form.items[1].span}, false
            }
            err_name, ok_name := data_pattern_append_name(names, form.items[1])
            if !ok_name {
                return err_name, false
            }
            return validate_match_pattern(form.items[2], names)
        }
        if form.items[0].text == "kind" {
            if _, ok_kind := match_kind_name(form.items[1]); !ok_kind {
                return Compile_Error{message = "unknown Data kind in match pattern", span = form.items[1].span}, false
            }
            return validate_match_pattern(form.items[2], names)
        }
        return Compile_Error{message = "match list pattern expects (as name pattern) or (kind :kind pattern)", span = form.span}, false
    case:
        return Compile_Error{message = "unsupported Data match pattern", span = form.span}, false
    }
    return {}, true
}

emit_match_pattern_condition :: proc(e: ^Emitter, pattern: CST_Form, source: string) -> (string, Compile_Error, bool) {
    if match_pattern_is_catchall(pattern) || pattern.kind == .Symbol {
        return "true", {}, true
    }
    if match_pattern_is_literal(pattern) {
        literal, err_literal, ok_literal := emit_data_pattern_literal_temp(e, pattern)
        if !ok_literal {
            return "", err_literal, false
        }
        return fmt.tprintf("kvist_data_equal(%s, %s)", source, literal), {}, true
    }
    conditions: [dynamic]string
    defer delete(conditions)
    #partial switch pattern.kind {
    case .Vector:
        rest_index := -1
        for item, idx in pattern.items {
            if item.kind == .Symbol && item.text == "&" {
                rest_index = idx
                break
            }
        }
        fixed_count := len(pattern.items)
        if rest_index >= 0 {
            fixed_count = rest_index
        }
        append(&conditions, fmt.tprintf("(%s.kind == .List || %s.kind == .Vector)", source, source))
        if rest_index >= 0 {
            append(&conditions, fmt.tprintf("len(%s.payload.items) >= %d", source, fixed_count))
        } else {
            append(&conditions, fmt.tprintf("len(%s.payload.items) == %d", source, fixed_count))
        }
        for item, idx in pattern.items[:fixed_count] {
            child := fmt.tprintf("kvist_data_nth_or_nil(%s, %d)", source, idx)
            condition, err_condition, ok_condition := emit_match_pattern_condition(e, item, child)
            if !ok_condition {
                return "", err_condition, false
            }
            append(&conditions, condition)
        }
    case .Brace:
        append(&conditions, fmt.tprintf("%s.kind == .Map", source))
        i := 0
        for i < len(pattern.items) {
            key, err_key, ok_key := emit_data_pattern_literal_temp(e, pattern.items[i])
            if !ok_key {
                return "", err_key, false
            }
            append(&conditions, fmt.tprintf("kvist_data_contains(%s, %s)", source, key))
            child := fmt.tprintf("kvist_data_get(%s, %s)", source, key)
            condition, err_condition, ok_condition := emit_match_pattern_condition(e, pattern.items[i+1], child)
            if !ok_condition {
                return "", err_condition, false
            }
            append(&conditions, condition)
            i += 2
        }
    case .Set:
        append(&conditions, fmt.tprintf("%s.kind == .Set", source))
        append(&conditions, fmt.tprintf("len(%s.payload.items) == %d", source, len(pattern.items)))
        for item in pattern.items {
            literal, err_literal, ok_literal := emit_data_pattern_literal_temp(e, item)
            if !ok_literal {
                return "", err_literal, false
            }
            append(&conditions, fmt.tprintf("kvist_data_contains(%s, %s)", source, literal))
        }
    case .List:
        if pattern.items[0].text == "as" {
            return emit_match_pattern_condition(e, pattern.items[2], source)
        }
        kind_name, _ := match_kind_name(pattern.items[1])
        append(&conditions, fmt.tprintf("%s.kind == .%s", source, kind_name))
        inner, err_inner, ok_inner := emit_match_pattern_condition(e, pattern.items[2], source)
        if !ok_inner {
            return "", err_inner, false
        }
        append(&conditions, inner)
    case:
        return "", Compile_Error{message = "unsupported Data match pattern", span = pattern.span}, false
    }
    return strings.join(conditions[:], " && ", context.allocator), {}, true
}

emit_match_capture_bindings :: proc(e: ^Emitter, pattern: CST_Form, source: string) -> (Compile_Error, bool) {
    if match_pattern_is_catchall(pattern) || match_pattern_is_literal(pattern) {
        return {}, true
    }
    #partial switch pattern.kind {
    case .Symbol:
        return emit_data_pattern_bindings(e, pattern, source)
    case .Vector:
        item_index := 0
        i := 0
        for i < len(pattern.items) {
            item := pattern.items[i]
            if item.kind == .Symbol && item.text == "&" {
                rest_temp := thread_temp_name(e)
                emit_owned_data_local(e, rest_temp, fmt.tprintf("kvist_data_rest_from(%s, %d)", source, item_index), item.span, true)
                return emit_match_capture_bindings(e, pattern.items[i+1], rest_temp)
            }
            child := fmt.tprintf("kvist_data_nth_or_nil(%s, %d)", source, item_index)
            err_child, ok_child := emit_match_capture_bindings(e, item, child)
            if !ok_child {
                return err_child, false
            }
            item_index += 1
            i += 1
        }
    case .Brace:
        i := 0
        for i < len(pattern.items) {
            key, err_key, ok_key := emit_data_pattern_literal_temp(e, pattern.items[i])
            if !ok_key {
                return err_key, false
            }
            child := fmt.tprintf("kvist_data_get(%s, %s)", source, key)
            err_child, ok_child := emit_match_capture_bindings(e, pattern.items[i+1], child)
            if !ok_child {
                return err_child, false
            }
            i += 2
        }
    case .Set:
        return {}, true
    case .List:
        if pattern.items[0].text == "as" {
            err_alias, ok_alias := emit_data_pattern_bindings(e, pattern.items[1], source)
            if !ok_alias {
                return err_alias, false
            }
        }
        return emit_match_capture_bindings(e, pattern.items[2], source)
    }
    return {}, true
}

validate_match_form :: proc(e: ^Emitter, form: CST_Form) -> (Compile_Error, bool) {
    if len(form.items) < 6 || (len(form.items)-2)%2 != 0 {
        return Compile_Error{message = "match expects a Data subject followed by pattern/result pairs and a final :else or _ arm", span = form.span}, false
    }
    subject := form.items[1]
    literal_subject := match_pattern_is_literal(subject) ||
                       subject.kind == .Vector ||
                       subject.kind == .Brace ||
                       subject.kind == .Set
    if !literal_subject {
        if ty, ok_ty := obvious_form_type(e, subject); !ok_ty || ty != "Data" {
            return Compile_Error{message = "match subject must be statically known as Data", span = subject.span}, false
        }
    }
    previous_literals: [dynamic]CST_Form
    defer delete(previous_literals)
    for i := 2; i < len(form.items); i += 2 {
        pattern := form.items[i]
        names: [dynamic]string
        err_pattern, ok_pattern := validate_match_pattern(pattern, &names)
        delete(names)
        if !ok_pattern {
            return err_pattern, false
        }
        if match_pattern_is_catchall(pattern) && i != len(form.items)-2 {
            return Compile_Error{message = "match catch-all must be the final arm", span = pattern.span}, false
        }
        if match_pattern_is_literal(pattern) {
            for previous in previous_literals {
                if match_literals_equal(previous, pattern) {
                    return Compile_Error{message = "duplicate exact literal match arm", span = pattern.span}, false
                }
            }
            append(&previous_literals, pattern)
        }
    }
    if !match_pattern_is_catchall(form.items[len(form.items)-2]) {
        return Compile_Error{message = "match requires a final :else or _ catch-all arm", span = form.items[len(form.items)-2].span}, false
    }
    return {}, true
}

emit_match_stmt :: proc(
    e: ^Emitter,
    form: CST_Form,
    last_in_proc: bool,
    returns: Return_Spec,
    discard_result := false,
) -> (Compile_Error, bool) {
    err_form, ok_form := validate_match_form(e, form)
    if !ok_form {
        return err_form, false
    }
    mark_data_type(e)
    subject_value, err_subject, ok_subject := emit_expr_for_expected_type(e, form.items[1], "Data")
    if !ok_subject {
        return err_subject, false
    }
    emit_line(e, "{")
    e.indent += 1
    push_local_type_scope(e)
    subject := thread_temp_name(e)
    subject_form := form.items[1]
    contextual_literal := match_pattern_is_literal(subject_form) ||
                          subject_form.kind == .Vector ||
                          subject_form.kind == .Brace ||
                          subject_form.kind == .Set
    emit_owned_data_local(
        e,
        subject,
        subject_value,
        subject_form.span,
        contextual_literal || form_produces_owned_managed_type(e, subject_form, "Data"),
    )
    conditions: [dynamic]string
    defer delete(conditions)
    for i := 2; i < len(form.items); i += 2 {
        pattern := form.items[i]
        catchall := match_pattern_is_catchall(pattern)
        condition := "true"
        if !catchall {
            err_condition: Compile_Error
            ok_condition: bool
            condition, err_condition, ok_condition = emit_match_pattern_condition(e, pattern, subject)
            if !ok_condition {
                pop_local_type_scope(e)
                return err_condition, false
            }
        }
        append(&conditions, condition)
    }
    arm_index := 0
    for i := 2; i < len(form.items); i += 2 {
        pattern := form.items[i]
        result := form.items[i+1]
        catchall := match_pattern_is_catchall(pattern)
        condition := conditions[arm_index]
        if i == 2 {
            emit_line(e, fmt.tprintf("if %s {{", condition))
        } else if catchall {
            emit_line(e, "} else {")
        } else {
            emit_line(e, fmt.tprintf("}} else if %s {{", condition))
        }
        e.indent += 1
        push_local_type_scope(e)
        err_captures, ok_captures := emit_match_capture_bindings(e, pattern, subject)
        if !ok_captures {
            pop_local_type_scope(e)
            pop_local_type_scope(e)
            return err_captures, false
        }
        err_result, ok_result := emit_if_branch_stmt(
            e,
            result,
            last_in_proc,
            returns_when_final(last_in_proc, returns),
            discard_result,
        )
        pop_local_type_scope(e)
        if !ok_result {
            pop_local_type_scope(e)
            return err_result, false
        }
        e.indent -= 1
        arm_index += 1
    }
    emit_line(e, "}")
    pop_local_type_scope(e)
    e.indent -= 1
    emit_line(e, "}")
    return {}, true
}

discard_mapped_name :: proc(text: string) -> string {
    name := map_name(text)
    if name == "_" {
        delete(name)
        return ""
    }
    return name
}

binding_output_name :: proc(name: string) -> string {
    if name == "" {
        return "_"
    }
    return name
}

is_discard_binding_name :: proc(name: string) -> bool {
    return name == "" || name == "_"
}

emit_loop_binding_assignment :: proc(e: ^Emitter, name, value: string) {
    if is_discard_binding_name(name) {
        emit_line(e, fmt.tprintf("_ = %s", value))
    } else {
        emit_line(e, fmt.tprintf("%s := %s", name, value))
    }
}

let_binding_has_defer_marker :: proc(items: []CST_Form, idx: int) -> bool {
    return idx < len(items) &&
           items[idx].kind == .Keyword &&
           items[idx].text == ":defer"
}

let_binding_has_errdefer_marker :: proc(items: []CST_Form, idx: int) -> bool {
    return idx < len(items) &&
           items[idx].kind == .Keyword &&
           items[idx].text == ":errdefer"
}

let_binding_has_defer_with_marker :: proc(items: []CST_Form, idx: int) -> bool {
    return idx < len(items) &&
           items[idx].kind == .Keyword &&
           items[idx].text == ":defer-with"
}

let_binding_or_modifier :: proc(items: []CST_Form, idx: int) -> (string, bool) {
    if idx >= len(items) || items[idx].kind != .Keyword {
        return "", false
    }
    switch items[idx].text {
    case ":or-return", ":or-break", ":or-continue":
        return items[idx].text[1:], true
    case:
        return "", false
    }
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
                return bindings, Compile_Error{message = "multi-return binding missing value", span = target.span}, false
            }
            names: [dynamic]string
            simple_symbols := true
            for part in target.items {
                if part.kind == .Symbol {
                    append(&names, discard_mapped_name(part.text))
                } else {
                    simple_symbols = false
                }
            }
            or_modifier, has_or_modifier := let_binding_or_modifier(form.items[:], i+2)
            if has_or_modifier && !simple_symbols {
                return bindings, Compile_Error{message = "or-* multi-return binding expects symbols", span = target.span}, false
            }
            deferred_delete := false
            err_deferred_delete := false
            defer_with_cleanup := false
            cleanup := CST_Form{}
            next_i := i + 2
            if has_or_modifier {
                if len(names) != 2 {
                    return bindings, Compile_Error{message = "or-* let binding expects exactly two names", span = target.span}, false
                }
                if names[1] != "ok" && names[1] != "err" {
                    return bindings, Compile_Error{message = "or-* let binding requires [value ok] or [value err]", span = target.span}, false
                }
                next_i += 1
                for next_i < len(form.items) {
                    if let_binding_has_defer_marker(form.items[:], next_i) {
                        if deferred_delete {
                            return bindings, Compile_Error{message = "duplicate :defer binding marker", span = form.items[next_i].span}, false
                        }
                        deferred_delete = true
                        next_i += 1
                    } else if let_binding_has_errdefer_marker(form.items[:], next_i) {
                        if err_deferred_delete {
                            return bindings, Compile_Error{message = "duplicate :errdefer binding marker", span = form.items[next_i].span}, false
                        }
                        err_deferred_delete = true
                        next_i += 1
                    } else if let_binding_has_defer_with_marker(form.items[:], next_i) {
                        if defer_with_cleanup {
                            return bindings, Compile_Error{message = "duplicate :defer-with binding marker", span = form.items[next_i].span}, false
                        }
                        if next_i+1 >= len(form.items) {
                            return bindings, Compile_Error{message = ":defer-with expects a cleanup function", span = form.items[next_i].span}, false
                        }
                        defer_with_cleanup = true
                        cleanup = form.items[next_i+1]
                        next_i += 2
                    } else {
                        break
                    }
                }
                cleanup_count := 0
                if deferred_delete {
                    cleanup_count += 1
                }
                if err_deferred_delete {
                    cleanup_count += 1
                }
                if defer_with_cleanup {
                    cleanup_count += 1
                }
                if cleanup_count > 1 {
                    return bindings, Compile_Error{message = "use only one cleanup marker: :defer, :errdefer, or :defer-with", span = target.span}, false
                }
                if err_deferred_delete && (or_modifier != "or-return" || names[1] != "err") {
                    return bindings, Compile_Error{message = ":errdefer is only supported on [value err] :or-return bindings", span = target.span}, false
                }
            } else if let_binding_has_defer_marker(form.items[:], i+2) {
                return bindings, Compile_Error{message = ":defer binding marker is only supported on named local bindings or [value ok/err] :or-* bindings", span = form.items[i+2].span}, false
            } else if let_binding_has_errdefer_marker(form.items[:], i+2) {
                return bindings, Compile_Error{message = ":errdefer is only supported on [value err] :or-return bindings", span = form.items[i+2].span}, false
            } else if let_binding_has_defer_with_marker(form.items[:], i+2) {
                return bindings, Compile_Error{message = ":defer-with binding marker is only supported on named local bindings or [value ok/err] :or-* bindings", span = form.items[i+2].span}, false
            }
            append(&bindings, Binding{
                is_destructure      = !has_or_modifier,
                is_result_binding   = has_or_modifier,
                is_data_destructure = !simple_symbols,
                pattern             = names,
                target              = target,
                deferred_delete     = deferred_delete,
                err_deferred_delete = err_deferred_delete,
                defer_with_cleanup  = defer_with_cleanup,
                cleanup             = cleanup,
                or_modifier         = or_modifier,
                target_span         = target.span,
                value               = form.items[i+1],
            })
            i = next_i
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
                deferred_delete := false
                defer_with_cleanup := false
                cleanup := CST_Form{}
                marker_i := next_i + 1
                if let_binding_has_defer_marker(form.items[:], marker_i) {
                    deferred_delete = true
                    marker_i += 1
                } else if let_binding_has_defer_with_marker(form.items[:], marker_i) {
                    if marker_i+1 >= len(form.items) {
                        return bindings, Compile_Error{message = ":defer-with expects a cleanup function", span = form.items[marker_i].span}, false
                    }
                    defer_with_cleanup = true
                    cleanup = form.items[marker_i+1]
                    marker_i += 2
                } else if let_binding_has_errdefer_marker(form.items[:], marker_i) {
                    return bindings, Compile_Error{message = ":errdefer is only supported on [value err] :or-return bindings", span = form.items[marker_i].span}, false
                }
                name := discard_mapped_name(target.text[:len(target.text)-1])
                append(&bindings, Binding{
                    name               = name,
                    is_typed           = true,
                    ty                 = type_text,
                    deferred_delete    = deferred_delete,
                    defer_with_cleanup = defer_with_cleanup,
                    cleanup            = cleanup,
                    target_span        = target.span,
                    value              = form.items[next_i],
                })
                i = next_i + 1
                if deferred_delete || defer_with_cleanup {
                    i = marker_i
                }
            } else {
                if i+1 >= len(form.items) {
                    return bindings, Compile_Error{message = "binding missing value", span = target.span}, false
                }
                deferred_delete := false
                defer_with_cleanup := false
                cleanup := CST_Form{}
                next_i := i + 2
                if let_binding_has_defer_marker(form.items[:], next_i) {
                    deferred_delete = true
                    next_i += 1
                } else if let_binding_has_defer_with_marker(form.items[:], next_i) {
                    if next_i+1 >= len(form.items) {
                        return bindings, Compile_Error{message = ":defer-with expects a cleanup function", span = form.items[next_i].span}, false
                    }
                    defer_with_cleanup = true
                    cleanup = form.items[next_i+1]
                    next_i += 2
                } else if let_binding_has_errdefer_marker(form.items[:], next_i) {
                    return bindings, Compile_Error{message = ":errdefer is only supported on [value err] :or-return bindings", span = form.items[next_i].span}, false
                }
                name := discard_mapped_name(target.text)
                append(&bindings, Binding{
                    name               = name,
                    deferred_delete    = deferred_delete,
                    defer_with_cleanup = defer_with_cleanup,
                    cleanup            = cleanup,
                    target_span        = target.span,
                    value              = form.items[i+1],
                })
                i = next_i
            }
        case .Brace:
            if i+1 >= len(form.items) {
                return bindings, Compile_Error{message = "Data map destructuring binding missing value", span = target.span}, false
            }
            if let_binding_has_defer_marker(form.items[:], i+2) ||
               let_binding_has_errdefer_marker(form.items[:], i+2) ||
               let_binding_has_defer_with_marker(form.items[:], i+2) {
                return bindings, Compile_Error{message = "Data destructuring is automatically managed and does not accept ownership modifiers", span = form.items[i+2].span}, false
            }
            append(&bindings, Binding{
                is_destructure      = true,
                is_data_destructure = true,
                target              = target,
                target_span         = target.span,
                value               = form.items[i+1],
            })
            i += 2
        case:
            return bindings, Compile_Error{message = "unsupported binding target", span = target.span}, false
        }
    }
    return bindings, {}, true
}
