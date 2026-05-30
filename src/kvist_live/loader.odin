package kvist_live

import "core:fmt"
import "core:strconv"
import "core:strings"
import kvist "../kvist"

kvist_literal_value :: proc(form: kvist.CST_Form) -> (Value, Runtime_Error, bool) {
    #partial switch form.kind {
    case .String:
        return value_string(kvist.unquote_string(form.text)), Runtime_Error{}, true
    case .Number:
        parsed, ok := strconv.parse_i64(form.text)
        if !ok {
            return Value{}, Runtime_Error{message = strings.clone("expected integer literal in live module")}, false
        }
        return value_int(parsed), Runtime_Error{}, true
    case .Bool:
        return value_bool(form.text == "true"), Runtime_Error{}, true
    case .Nil:
        return value_nil(), Runtime_Error{}, true
    case .Keyword:
        return value_string(form.text), Runtime_Error{}, true
    case:
        return Value{}, Runtime_Error{message = strings.clone("unsupported literal in live module; expected string, int, bool, nil, or keyword")}, false
    }
}

append_state_value :: proc(state: ^[dynamic]State_Entry, key: string, value: Value) {
    append(state, State_Entry{
        key = strings.clone(key),
        value = value,
    })
}

option_state_key :: proc(form: kvist.CST_Form) -> (string, bool) {
    if form.kind != .Keyword || len(form.text) < 2 {
        return "", false
    }
    return form.text[1:], true
}

find_state_entry_index :: proc(state: []State_Entry, key: string) -> int {
    for entry, idx in state {
        if entry.key == key {
            return idx
        }
    }
    return -1
}

put_state_value :: proc(state: ^[dynamic]State_Entry, key: string, value: Value) {
    idx := find_state_entry_index(state^[:], key)
    if idx >= 0 {
        value_delete(&state^[idx].value)
        state^[idx].value = value
        return
    }
    append_state_value(state, key, value)
}

put_state_string :: proc(state: ^[dynamic]State_Entry, key, value: string) {
    put_state_value(state, key, value_string(value))
}

apply_literal_options :: proc(state: ^[dynamic]State_Entry, form: kvist.CST_Form) -> (Runtime_Error, bool) {
    if form.kind != .Brace {
        return Runtime_Error{message = strings.clone("expected brace options map in live module")}, false
    }
    i := 0
    for i < len(form.items) {
        if i+1 >= len(form.items) {
            return Runtime_Error{message = strings.clone("live module options map has a missing value")}, false
        }
        key, ok := option_state_key(form.items[i])
        if !ok {
            return Runtime_Error{message = strings.clone("live module options map expects keyword keys")}, false
        }
        value, value_err, value_ok := kvist_literal_value(form.items[i+1])
        if !value_ok {
            return value_err, false
        }
        put_state_value(state, key, value)
        i += 2
    }
    return Runtime_Error{}, true
}

extract_behavior_doc :: proc(form: kvist.CST_Form) -> string {
    if form.kind != .Brace {
        return ""
    }
    i := 0
    for i+1 < len(form.items) {
        key, ok := option_state_key(form.items[i])
        if ok && key == "doc" && form.items[i+1].kind == .String {
            return kvist.unquote_string(form.items[i+1].text)
        }
        i += 2
    }
    return ""
}

find_behavior_definition :: proc(defs: []Behavior_Definition, name: string) -> (Behavior_Definition, bool) {
    for def in defs {
        if def.name == name {
            return def, true
        }
    }
    return Behavior_Definition{}, false
}

command_or_hook_parts :: proc(form: kvist.CST_Form, head: string) -> (name_form, options_form: kvist.CST_Form, body_start: int, err: Runtime_Error, ok: bool) {
    if len(form.items) < 2 {
        return kvist.CST_Form{}, kvist.CST_Form{}, 0, Runtime_Error{message = strings.clone(fmt.tprintf("%s expects at least a symbol name", head))}, false
    }
    if form.items[1].kind != .Symbol {
        return kvist.CST_Form{}, kvist.CST_Form{}, 0, Runtime_Error{message = strings.clone(fmt.tprintf("%s expects a symbol name", head))}, false
    }

    if len(form.items) >= 3 && form.items[2].kind == .Brace {
        return form.items[1], form.items[2], 3, Runtime_Error{}, true
    }

    return form.items[1], kvist.CST_Form{}, 2, Runtime_Error{}, true
}

extract_params :: proc(form: kvist.CST_Form, label: string) -> ([dynamic]string, Runtime_Error, bool) {
    if form.kind != .Vector {
        return nil, Runtime_Error{message = strings.clone(fmt.tprintf("%s expects a parameter vector", label))}, false
    }

    params: [dynamic]string
    for item in form.items {
        if item.kind != .Symbol {
            delete_string_slice(&params)
            return nil, Runtime_Error{message = strings.clone(fmt.tprintf("%s parameters must be symbols", label))}, false
        }
        append(&params, strings.clone(item.text))
    }
    return params, Runtime_Error{}, true
}

module_definition_from_kvist_source :: proc(source: string) -> (Module_Definition, Runtime_Error, bool) {
    forms, read_err, read_ok := kvist.read_top_forms(source)
    if !read_ok {
        return Module_Definition{}, Runtime_Error{message = strings.clone(read_err.message)}, false
    }

    name := strings.clone("commands")
    version := strings.clone("dev")
    state: [dynamic]State_Entry
    functions: [dynamic]Behavior_Definition
    commands: [dynamic]Behavior_Definition
    hooks: [dynamic]Behavior_Definition

    for top in forms {
        form := top.form
        if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
            continue
        }

        if kvist.is_symbol(form.items[0], "live/module") {
            if len(form.items) != 2 {
                delete(name)
                delete(version)
                state_entry_slice_delete(&state)
                delete_behavior_definition_slice(&functions)
                delete_behavior_definition_slice(&commands)
                delete_behavior_definition_slice(&hooks)
                return Module_Definition{}, Runtime_Error{message = strings.clone("live/module expects one options map")}, false
            }
            if form.items[1].kind != .Brace {
                delete(name)
                delete(version)
                state_entry_slice_delete(&state)
                delete_behavior_definition_slice(&functions)
                delete_behavior_definition_slice(&commands)
                delete_behavior_definition_slice(&hooks)
                return Module_Definition{}, Runtime_Error{message = strings.clone("live/module expects a brace options map")}, false
            }

            i := 0
            for i < len(form.items[1].items) {
                if i+1 >= len(form.items[1].items) {
                    delete(name)
                    delete(version)
                    state_entry_slice_delete(&state)
                    delete_behavior_definition_slice(&functions)
                    delete_behavior_definition_slice(&commands)
                    delete_behavior_definition_slice(&hooks)
                    return Module_Definition{}, Runtime_Error{message = strings.clone("live/module options map has a missing value")}, false
                }
                key_form := form.items[1].items[i]
                value_form := form.items[1].items[i+1]
                key, ok := option_state_key(key_form)
                if !ok {
                    delete(name)
                    delete(version)
                    state_entry_slice_delete(&state)
                    delete_behavior_definition_slice(&functions)
                    delete_behavior_definition_slice(&commands)
                    delete_behavior_definition_slice(&hooks)
                    return Module_Definition{}, Runtime_Error{message = strings.clone("live/module expects keyword keys")}, false
                }
                value, value_err, value_ok := kvist_literal_value(value_form)
                if !value_ok {
                    delete(name)
                    delete(version)
                    state_entry_slice_delete(&state)
                    delete_behavior_definition_slice(&functions)
                    delete_behavior_definition_slice(&commands)
                    delete_behavior_definition_slice(&hooks)
                    return Module_Definition{}, value_err, false
                }
                switch key {
                case "name":
                    if value.kind != .String {
                        value_delete(&value)
                        delete(name)
                        delete(version)
                        state_entry_slice_delete(&state)
                        delete_behavior_definition_slice(&functions)
                        delete_behavior_definition_slice(&commands)
                        delete_behavior_definition_slice(&hooks)
                        return Module_Definition{}, Runtime_Error{message = strings.clone("live/module :name must be a string")}, false
                    }
                    delete(name)
                    name = strings.clone(value.text)
                    value_delete(&value)
                case "version":
                    if value.kind != .String {
                        value_delete(&value)
                        delete(name)
                        delete(version)
                        state_entry_slice_delete(&state)
                        delete_behavior_definition_slice(&functions)
                        delete_behavior_definition_slice(&commands)
                        delete_behavior_definition_slice(&hooks)
                        return Module_Definition{}, Runtime_Error{message = strings.clone("live/module :version must be a string")}, false
                    }
                    delete(version)
                    version = strings.clone(value.text)
                    value_delete(&value)
                case:
                    put_state_value(&state, key, value)
                }
                i += 2
            }
            continue
        }

        if kvist.is_symbol(form.items[0], "live/defn") || kvist.is_symbol(form.items[0], "defn") {
            form_name := form.items[0].text
            if len(form.items) < 4 {
                delete(name)
                delete(version)
                state_entry_slice_delete(&state)
                delete_behavior_definition_slice(&functions)
                delete_behavior_definition_slice(&commands)
                delete_behavior_definition_slice(&hooks)
                return Module_Definition{}, Runtime_Error{message = strings.clone(fmt.tprintf("%s expects a name, parameter vector, and a body", form_name))}, false
            }
            if form.items[1].kind != .Symbol {
                delete(name)
                delete(version)
                state_entry_slice_delete(&state)
                delete_behavior_definition_slice(&functions)
                delete_behavior_definition_slice(&commands)
                delete_behavior_definition_slice(&hooks)
                return Module_Definition{}, Runtime_Error{message = strings.clone(fmt.tprintf("%s expects a symbol name", form_name))}, false
            }
            params, params_err, params_ok := extract_params(form.items[2], form_name)
            if !params_ok {
                delete(name)
                delete(version)
                state_entry_slice_delete(&state)
                delete_behavior_definition_slice(&functions)
                delete_behavior_definition_slice(&commands)
                delete_behavior_definition_slice(&hooks)
                return Module_Definition{}, params_err, false
            }
            append(&functions, Behavior_Definition{
                name = strings.clone(form.items[1].text),
                params = params,
                body = clone_cst_form_slice(form.items[3:]),
            })
            continue
        }

        if kvist.is_symbol(form.items[0], "live/command") {
            name_form, options_form, body_start, part_err, part_ok := command_or_hook_parts(form, "live/command")
            if !part_ok {
                delete(name)
                delete(version)
                state_entry_slice_delete(&state)
                delete_behavior_definition_slice(&functions)
                delete_behavior_definition_slice(&commands)
                delete_behavior_definition_slice(&hooks)
                return Module_Definition{}, part_err, false
            }
            put_state_string(&state, "command-name", name_form.text)
            doc := ""
            if options_form.kind == .Brace {
                options_err, options_ok := apply_literal_options(&state, options_form)
                if !options_ok {
                    delete(name)
                    delete(version)
                    state_entry_slice_delete(&state)
                    delete_behavior_definition_slice(&functions)
                    delete_behavior_definition_slice(&commands)
                    delete_behavior_definition_slice(&hooks)
                    return Module_Definition{}, options_err, false
                }
                doc = extract_behavior_doc(options_form)
            }
            append(&commands, Behavior_Definition{
                name = strings.clone(name_form.text),
                doc = strings.clone(doc),
                body = clone_cst_form_slice(form.items[body_start:]),
            })
            continue
        }

        if kvist.is_symbol(form.items[0], "live/hook") {
            name_form, options_form, body_start, part_err, part_ok := command_or_hook_parts(form, "live/hook")
            if !part_ok {
                delete(name)
                delete(version)
                state_entry_slice_delete(&state)
                delete_behavior_definition_slice(&functions)
                delete_behavior_definition_slice(&commands)
                delete_behavior_definition_slice(&hooks)
                return Module_Definition{}, part_err, false
            }
            put_state_string(&state, "hook-name", name_form.text)
            doc := ""
            if options_form.kind == .Brace {
                options_err, options_ok := apply_literal_options(&state, options_form)
                if !options_ok {
                    delete(name)
                    delete(version)
                    state_entry_slice_delete(&state)
                    delete_behavior_definition_slice(&functions)
                    delete_behavior_definition_slice(&commands)
                    delete_behavior_definition_slice(&hooks)
                    return Module_Definition{}, options_err, false
                }
                doc = extract_behavior_doc(options_form)
            }
            append(&hooks, Behavior_Definition{
                name = strings.clone(name_form.text),
                doc = strings.clone(doc),
                body = clone_cst_form_slice(form.items[body_start:]),
            })
            continue
        }

        if !kvist.is_symbol(form.items[0], "defconst") && !kvist.is_symbol(form.items[0], "defvar") && !kvist.is_symbol(form.items[0], "def") {
            continue
        }

        if form.items[1].kind != .Symbol {
            delete(name)
            delete(version)
            state_entry_slice_delete(&state)
            delete_behavior_definition_slice(&functions)
            delete_behavior_definition_slice(&commands)
            delete_behavior_definition_slice(&hooks)
            return Module_Definition{}, Runtime_Error{message = strings.clone("live module bindings require symbol names")}, false
        }

        binding_name := form.items[1].text
        value_form := form.items[len(form.items)-1]
        value, value_err, value_ok := kvist_literal_value(value_form)
        if !value_ok {
            delete(name)
            delete(version)
            state_entry_slice_delete(&state)
            delete_behavior_definition_slice(&functions)
            delete_behavior_definition_slice(&commands)
            delete_behavior_definition_slice(&hooks)
            return Module_Definition{}, value_err, false
        }

        switch binding_name {
        case "module-name":
            if value.kind != .String {
                value_delete(&value)
                delete(name)
                delete(version)
                state_entry_slice_delete(&state)
                delete_behavior_definition_slice(&functions)
                delete_behavior_definition_slice(&commands)
                delete_behavior_definition_slice(&hooks)
                return Module_Definition{}, Runtime_Error{message = strings.clone("module-name must be a string")}, false
            }
            delete(name)
            name = strings.clone(value.text)
            value_delete(&value)
        case "module-version":
            if value.kind != .String {
                value_delete(&value)
                delete(name)
                delete(version)
                state_entry_slice_delete(&state)
                delete_behavior_definition_slice(&functions)
                delete_behavior_definition_slice(&commands)
                delete_behavior_definition_slice(&hooks)
                return Module_Definition{}, Runtime_Error{message = strings.clone("module-version must be a string")}, false
            }
            delete(version)
            version = strings.clone(value.text)
            value_delete(&value)
        case:
            append(&state, State_Entry{
                key = strings.clone(binding_name),
                value = value,
            })
        }
    }

    if name == "" {
        delete(version)
        state_entry_slice_delete(&state)
        delete_behavior_definition_slice(&functions)
        delete_behavior_definition_slice(&commands)
        delete_behavior_definition_slice(&hooks)
        return Module_Definition{}, Runtime_Error{message = strings.clone("module-name must not be empty")}, false
    }

    for i in 0 ..< len(commands) {
        if len(commands[i].body) > 0 {
            continue
        }
        fn_def, found := find_behavior_definition(functions[:], commands[i].name)
        if !found {
            delete(name)
            delete(version)
            state_entry_slice_delete(&state)
            delete_behavior_definition_slice(&functions)
            delete_behavior_definition_slice(&commands)
            delete_behavior_definition_slice(&hooks)
            return Module_Definition{}, Runtime_Error{message = strings.clone(fmt.tprintf("live/command %s needs a body or a same-named defn", commands[i].name))}, false
        }
        if len(fn_def.params) != 0 {
            delete(name)
            delete(version)
            state_entry_slice_delete(&state)
            delete_behavior_definition_slice(&functions)
            delete_behavior_definition_slice(&commands)
            delete_behavior_definition_slice(&hooks)
            return Module_Definition{}, Runtime_Error{message = strings.clone(fmt.tprintf("live/command %s currently requires a zero-arg defn", commands[i].name))}, false
        }
        commands[i].body = clone_cst_form_slice(fn_def.body[:])
    }

    for i in 0 ..< len(hooks) {
        if len(hooks[i].body) > 0 {
            continue
        }
        fn_def, found := find_behavior_definition(functions[:], hooks[i].name)
        if !found {
            delete(name)
            delete(version)
            state_entry_slice_delete(&state)
            delete_behavior_definition_slice(&functions)
            delete_behavior_definition_slice(&commands)
            delete_behavior_definition_slice(&hooks)
            return Module_Definition{}, Runtime_Error{message = strings.clone(fmt.tprintf("live/hook %s needs a body or a same-named defn", hooks[i].name))}, false
        }
        if len(fn_def.params) != 0 {
            delete(name)
            delete(version)
            state_entry_slice_delete(&state)
            delete_behavior_definition_slice(&functions)
            delete_behavior_definition_slice(&commands)
            delete_behavior_definition_slice(&hooks)
            return Module_Definition{}, Runtime_Error{message = strings.clone(fmt.tprintf("live/hook %s currently requires a zero-arg defn", hooks[i].name))}, false
        }
        hooks[i].body = clone_cst_form_slice(fn_def.body[:])
    }

    return Module_Definition{
        name = name,
        version = version,
        initial_state = state,
        functions = functions,
        commands = commands,
        hooks = hooks,
    }, Runtime_Error{}, true
}
