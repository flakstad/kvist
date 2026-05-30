package kvist_live

import "core:strconv"
import "core:fmt"
import "core:strings"
import kvist "../kvist"

Eval_Binding :: struct {
    name:  string,
    value: Value,
}

delete_eval_binding_slice :: proc(bindings: ^[dynamic]Eval_Binding) {
    for i in 0 ..< len(bindings^) {
        if bindings^[i].name != "" {
            delete(bindings^[i].name)
        }
        value_delete(&bindings^[i].value)
    }
    delete(bindings^)
    bindings^ = nil
}

clone_eval_binding_slice :: proc(bindings: []Eval_Binding) -> (out: [dynamic]Eval_Binding) {
    for binding in bindings {
        append(&out, Eval_Binding{
            name = strings.clone(binding.name),
            value = value_clone(binding.value),
        })
    }
    return out
}

find_binding :: proc(bindings: []Eval_Binding, name: string) -> (Value, bool) {
    for i := len(bindings) - 1; i >= 0; i -= 1 {
        if bindings[i].name == name {
            return bindings[i].value, true
        }
    }
    return Value{}, false
}

find_live_function :: proc(module: ^Live_Module, name: string) -> (^Behavior_Definition, bool) {
    for i in 0 ..< len(module.functions) {
        if module.functions[i].name == name {
            return &module.functions[i], true
        }
    }
    return nil, false
}

find_module_binding :: proc(module: ^Live_Module, name: string) -> (Value, bool) {
    if entry, ok := module_state_get(module, name); ok {
        return value_clone(entry.value), true
    }
    return Value{}, false
}

value_truthy :: proc(value: Value) -> bool {
    #partial switch value.kind {
    case .Nil:
        return false
    case .Bool:
        return value.bool_value
    case:
        return true
    }
}

value_text :: proc(value: Value) -> string {
    #partial switch value.kind {
    case .Nil:
        return strings.clone("nil")
    case .Bool:
        if value.bool_value {
            return strings.clone("true")
        }
        return strings.clone("false")
    case .Int:
        return strings.clone(fmt.tprintf("%d", value.int_value))
    case .String, .Handle:
        return strings.clone(value.text)
    }
    return strings.clone("")
}

values_equal :: proc(a, b: Value) -> bool {
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
    case .String, .Handle:
        return a.text == b.text
    }
    return false
}

state_key_text :: proc(module: ^Live_Module, form: kvist.CST_Form, bindings: []Eval_Binding) -> (string, Runtime_Error, bool) {
    value, err, ok := eval_form(module, form, bindings)
    if !ok {
        return "", err, false
    }
    defer value_delete(&value)
    #partial switch value.kind {
    case .String, .Handle:
        return strings.clone(value.text), Runtime_Error{}, true
    case:
        return "", Runtime_Error{message = strings.clone("state key must evaluate to a string")}, false
    }
}

eval_list :: proc(module: ^Live_Module, form: kvist.CST_Form, bindings: []Eval_Binding) -> (Value, Runtime_Error, bool) {
    if len(form.items) == 0 || form.items[0].kind != .Symbol {
        return Value{}, Runtime_Error{message = strings.clone("live evaluator expects list forms with symbolic heads")}, false
    }

    head := form.items[0].text
    switch head {
    case "do":
        result := value_nil()
        for item in form.items[1:] {
            value_delete(&result)
            next, err, ok := eval_form(module, item, bindings)
            if !ok {
                return Value{}, err, false
            }
            result = next
        }
        return result, Runtime_Error{}, true
    case "if":
        if len(form.items) < 3 || len(form.items) > 4 {
            return Value{}, Runtime_Error{message = strings.clone("if expects test, then, and optional else")}, false
        }
        test, err, ok := eval_form(module, form.items[1], bindings)
        if !ok {
            return Value{}, err, false
        }
        defer value_delete(&test)
        if value_truthy(test) {
            return eval_form(module, form.items[2], bindings)
        }
        if len(form.items) == 4 {
            return eval_form(module, form.items[3], bindings)
        }
        return value_nil(), Runtime_Error{}, true
    case "when":
        if len(form.items) < 2 {
            return Value{}, Runtime_Error{message = strings.clone("when expects a test")}, false
        }
        test, err, ok := eval_form(module, form.items[1], bindings)
        if !ok {
            return Value{}, err, false
        }
        defer value_delete(&test)
        if !value_truthy(test) {
            return value_nil(), Runtime_Error{}, true
        }
        result := value_nil()
        for body_form in form.items[2:] {
            value_delete(&result)
            next, next_err, next_ok := eval_form(module, body_form, bindings)
            if !next_ok {
                return Value{}, next_err, false
            }
            result = next
        }
        return result, Runtime_Error{}, true
    case "let":
        if len(form.items) < 3 || form.items[1].kind != .Vector {
            return Value{}, Runtime_Error{message = strings.clone("let expects a binding vector and a body")}, false
        }
        local := clone_eval_binding_slice(bindings)
        defer delete_eval_binding_slice(&local)
        i := 0
        for i < len(form.items[1].items) {
            if i+1 >= len(form.items[1].items) {
                return Value{}, Runtime_Error{message = strings.clone("let binding vector has a missing value")}, false
            }
            name_form := form.items[1].items[i]
            if name_form.kind != .Symbol {
                return Value{}, Runtime_Error{message = strings.clone("let binding names must be symbols")}, false
            }
            value, err, ok := eval_form(module, form.items[1].items[i+1], local[:])
            if !ok {
                return Value{}, err, false
            }
            append(&local, Eval_Binding{
                name = strings.clone(name_form.text),
                value = value,
            })
            i += 2
        }
        result := value_nil()
        for body_form in form.items[2:] {
            value_delete(&result)
            next, err, ok := eval_form(module, body_form, local[:])
            if !ok {
                return Value{}, err, false
            }
            result = next
        }
        return result, Runtime_Error{}, true
    case "state/get":
        if len(form.items) != 2 {
            return Value{}, Runtime_Error{message = strings.clone("state/get expects one key argument")}, false
        }
        key, err, ok := state_key_text(module, form.items[1], bindings)
        if !ok {
            return Value{}, err, false
        }
        defer delete(key)
        entry, found := module_state_get(module, key)
        if !found {
            return value_nil(), Runtime_Error{}, true
        }
        return value_clone(entry.value), Runtime_Error{}, true
    case "state/set!":
        if len(form.items) != 3 {
            return Value{}, Runtime_Error{message = strings.clone("state/set! expects a key and a value")}, false
        }
        key, err, ok := state_key_text(module, form.items[1], bindings)
        if !ok {
            return Value{}, err, false
        }
        defer delete(key)
        value, value_err, value_ok := eval_form(module, form.items[2], bindings)
        if !value_ok {
            return Value{}, value_err, false
        }
        module_state_put(module, key, value)
        return value, Runtime_Error{}, true
    case "state/inc!":
        if len(form.items) != 2 && len(form.items) != 3 {
            return Value{}, Runtime_Error{message = strings.clone("state/inc! expects a key and optional delta")}, false
        }
        key, err, ok := state_key_text(module, form.items[1], bindings)
        if !ok {
            return Value{}, err, false
        }
        defer delete(key)
        delta := i64(1)
        if len(form.items) == 3 {
            delta_value, delta_err, delta_ok := eval_form(module, form.items[2], bindings)
            if !delta_ok {
                return Value{}, delta_err, false
            }
            defer value_delete(&delta_value)
            if delta_value.kind != .Int {
                return Value{}, Runtime_Error{message = strings.clone("state/inc! delta must evaluate to an int")}, false
            }
            delta = delta_value.int_value
        }
        current := i64(0)
        if entry, found := module_state_get(module, key); found {
            if entry.value.kind != .Int {
                return Value{}, Runtime_Error{message = strings.clone("state/inc! requires an int state slot")}, false
            }
            current = entry.value.int_value
        }
        updated := value_int(current + delta)
        module_state_put(module, key, updated)
        return updated, Runtime_Error{}, true
    case "module/name":
        return value_string(module.name), Runtime_Error{}, true
    case "module/version":
        return value_string(module.version), Runtime_Error{}, true
    case "host/call":
        if len(form.items) < 2 {
            return Value{}, Runtime_Error{message = strings.clone("host/call expects a capability name")}, false
        }
        cap_value, err, ok := eval_form(module, form.items[1], bindings)
        if !ok {
            return Value{}, err, false
        }
        defer value_delete(&cap_value)
        if cap_value.kind != .String && cap_value.kind != .Handle {
            return Value{}, Runtime_Error{message = strings.clone("host/call capability name must evaluate to a string")}, false
        }
        args: [dynamic]Value
        defer {
            for i in 0 ..< len(args) {
                value_delete(&args[i])
            }
            delete(args)
        }
        for arg_form in form.items[2:] {
            value, value_err, value_ok := eval_form(module, arg_form, bindings)
            if !value_ok {
                return Value{}, value_err, false
            }
            append(&args, value)
        }
        return call_capability(module.runtime, cap_value.text, args[:])
    case "hook/emit":
        if len(form.items) != 2 {
            return Value{}, Runtime_Error{message = strings.clone("hook/emit expects one hook name")}, false
        }
        hook_value, err, ok := eval_form(module, form.items[1], bindings)
        if !ok {
            return Value{}, err, false
        }
        defer value_delete(&hook_value)
        if hook_value.kind != .String && hook_value.kind != .Handle {
            return Value{}, Runtime_Error{message = strings.clone("hook/emit expects a hook name string")}, false
        }
        hook_err, hook_ok := emit_hook(module.runtime, hook_value.text, nil)
        if !hook_ok {
            return Value{}, hook_err, false
        }
        return value_nil(), Runtime_Error{}, true
    case "+":
        total := i64(0)
        for arg_form in form.items[1:] {
            value, err, ok := eval_form(module, arg_form, bindings)
            if !ok {
                return Value{}, err, false
            }
            defer value_delete(&value)
            if value.kind != .Int {
                return Value{}, Runtime_Error{message = strings.clone("+ expects int arguments")}, false
            }
            total += value.int_value
        }
        return value_int(total), Runtime_Error{}, true
    case "=":
        if len(form.items) != 3 {
            return Value{}, Runtime_Error{message = strings.clone("= expects exactly two arguments")}, false
        }
        lhs, lhs_err, lhs_ok := eval_form(module, form.items[1], bindings)
        if !lhs_ok {
            return Value{}, lhs_err, false
        }
        defer value_delete(&lhs)
        rhs, rhs_err, rhs_ok := eval_form(module, form.items[2], bindings)
        if !rhs_ok {
            return Value{}, rhs_err, false
        }
        defer value_delete(&rhs)
        return value_bool(values_equal(lhs, rhs)), Runtime_Error{}, true
    case "str":
        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)
        for arg_form in form.items[1:] {
            value, err, ok := eval_form(module, arg_form, bindings)
            if !ok {
                return Value{}, err, false
            }
            rendered := value_text(value)
            strings.write_string(&builder, rendered)
            delete(rendered)
            value_delete(&value)
        }
        return value_string(strings.to_string(builder)), Runtime_Error{}, true
    case:
        live_fn, found := find_live_function(module, head)
        if !found {
            return Value{}, Runtime_Error{message = strings.clone(fmt.tprintf("unsupported live form: %s", head))}, false
        }
        if len(form.items)-1 != len(live_fn.params) {
            return Value{}, Runtime_Error{message = strings.clone(fmt.tprintf("live function %s expects %d args", head, len(live_fn.params)))}, false
        }

        local := clone_eval_binding_slice(bindings)
        defer delete_eval_binding_slice(&local)

        for arg_form, idx in form.items[1:] {
            value, value_err, value_ok := eval_form(module, arg_form, bindings)
            if !value_ok {
                return Value{}, value_err, false
            }
            append(&local, Eval_Binding{
                name = strings.clone(live_fn.params[idx]),
                value = value,
            })
        }

        result := value_nil()
        for body_form in live_fn.body {
            value_delete(&result)
            next, err, ok := eval_form(module, body_form, local[:])
            if !ok {
                return Value{}, err, false
            }
            result = next
        }
        return result, Runtime_Error{}, true
    }
}

eval_form :: proc(module: ^Live_Module, form: kvist.CST_Form, bindings: []Eval_Binding) -> (Value, Runtime_Error, bool) {
    #partial switch form.kind {
    case .String:
        return value_string(kvist.unquote_string(form.text)), Runtime_Error{}, true
    case .Number:
        parsed, ok := strconv.parse_i64(form.text)
        if !ok {
            return Value{}, Runtime_Error{message = strings.clone("expected integer literal")}, false
        }
        return value_int(parsed), Runtime_Error{}, true
    case .Bool:
        return value_bool(form.text == "true"), Runtime_Error{}, true
    case .Nil:
        return value_nil(), Runtime_Error{}, true
    case .Keyword:
        return value_string(form.text[1:]), Runtime_Error{}, true
    case .Symbol:
        if value, ok := find_binding(bindings, form.text); ok {
            return value_clone(value), Runtime_Error{}, true
        }
        if value, ok := find_module_binding(module, form.text); ok {
            return value, Runtime_Error{}, true
        }
        return Value{}, Runtime_Error{message = strings.clone(fmt.tprintf("unknown live symbol: %s", form.text))}, false
    case .List:
        return eval_list(module, form, bindings)
    case .Vector, .Brace:
        return Value{}, Runtime_Error{message = strings.clone("live evaluator does not support vector or map literals in behavior bodies yet")}, false
    case:
        return Value{}, Runtime_Error{message = strings.clone("unsupported live form kind")}, false
    }
}

execute_command_body :: proc(runtime: ^Runtime, module: ^Live_Module, command: ^Live_Command, args: []Value) -> (Value, Runtime_Error, bool) {
    bindings: [dynamic]Eval_Binding
    defer delete_eval_binding_slice(&bindings)
    append(&bindings, Eval_Binding{name = strings.clone("args"), value = value_int(i64(len(args)))})

    result := value_nil()
    for form in command.body {
        value_delete(&result)
        next, err, ok := eval_form(module, form, bindings[:])
        if !ok {
            return Value{}, err, false
        }
        result = next
    }
    return result, Runtime_Error{}, true
}

execute_hook_body :: proc(runtime: ^Runtime, module: ^Live_Module, hook: ^Live_Hook, payload: []Value) -> (Runtime_Error, bool) {
    bindings: [dynamic]Eval_Binding
    defer delete_eval_binding_slice(&bindings)
    append(&bindings, Eval_Binding{name = strings.clone("payload-count"), value = value_int(i64(len(payload)))})

    result := value_nil()
    for form in hook.body {
        value_delete(&result)
        next, err, ok := eval_form(module, form, bindings[:])
        if !ok {
            return err, false
        }
        result = next
    }
    value_delete(&result)
    return Runtime_Error{}, true
}
