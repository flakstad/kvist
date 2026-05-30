package kvist_live

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import kvist "../kvist"

Loader_Accum :: struct {
    name:      string,
    version:   string,
    state:     [dynamic]State_Entry,
    functions: [dynamic]Behavior_Definition,
    commands:  [dynamic]Behavior_Definition,
    hooks:     [dynamic]Behavior_Definition,
}

loader_accum_delete :: proc(accum: ^Loader_Accum) {
    if accum.name != "" {
        delete(accum.name)
    }
    if accum.version != "" {
        delete(accum.version)
    }
    state_entry_slice_delete(&accum.state)
    delete_behavior_definition_slice(&accum.functions)
    delete_behavior_definition_slice(&accum.commands)
    delete_behavior_definition_slice(&accum.hooks)
    accum^ = Loader_Accum{}
}

new_loader_accum :: proc() -> Loader_Accum {
    return Loader_Accum{
        name = strings.clone("commands"),
        version = strings.clone("dev"),
    }
}

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

put_behavior_definition :: proc(defs: ^[dynamic]Behavior_Definition, def: Behavior_Definition) {
    for i in 0 ..< len(defs^) {
        if defs^[i].name == def.name {
            delete_behavior_definition(&defs^[i])
            defs^[i] = def
            return
        }
    }
    append(defs, def)
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

loader_error :: proc(message: string, accum: ^Loader_Accum) -> (Module_Definition, Runtime_Error, bool) {
    loader_accum_delete(accum)
    return Module_Definition{}, Runtime_Error{message = strings.clone(message)}, false
}

loader_errorf :: proc(accum: ^Loader_Accum, format: string, args: ..any) -> (Module_Definition, Runtime_Error, bool) {
    return loader_error(fmt.tprintf(format, ..args), accum)
}

path_in_stack :: proc(stack: []string, path: string) -> bool {
    for entry in stack {
        if entry == path {
            return true
        }
    }
    return false
}

delete_string_stack :: proc(values: ^[dynamic]string) {
    delete_string_slice(values)
}

merge_imported_accum :: proc(target: ^Loader_Accum, imported: Loader_Accum) {
    for entry in imported.state {
        put_state_value(&target.state, entry.key, value_clone(entry.value))
    }
    for fn_def in imported.functions {
        put_behavior_definition(&target.functions, clone_behavior_definition(fn_def))
    }
}

resolve_import_path_from_form :: proc(form: kvist.CST_Form, current_path: string) -> (string, Runtime_Error, bool) {
    if current_path == "" {
        return "", Runtime_Error{message = strings.clone("live imports require path-based loading")}, false
    }
    if len(form.items) != 2 || form.items[1].kind != .String {
        return "", Runtime_Error{message = strings.clone("live imports currently support only (import \"path\")")}, false
    }
    import_path := kvist.unquote_string(form.items[1].text)
    defer delete(import_path)
    resolved, resolve_err, resolve_ok := kvist.resolve_source_import_path(current_path, import_path)
    if !resolve_ok {
        return "", Runtime_Error{message = strings.clone(resolve_err.message)}, false
    }
    return resolved, Runtime_Error{}, true
}

load_imported_live_file :: proc(path: string, import_stack: []string) -> (Loader_Accum, Runtime_Error, bool) {
    if path_in_stack(import_stack, path) {
        return Loader_Accum{}, Runtime_Error{message = strings.clone(fmt.tprintf("circular live import detected: %s", path))}, false
    }

    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        return Loader_Accum{}, Runtime_Error{message = strings.clone(fmt.tprintf("could not read live import: %s", path))}, false
    }
    defer delete(data)

    forms, forms_err, forms_ok := kvist.read_top_forms(string(data))
    if !forms_ok {
        return Loader_Accum{}, Runtime_Error{message = strings.clone(forms_err.message)}, false
    }

    next_stack := clone_string_slice(import_stack)
    defer delete_string_stack(&next_stack)
    append(&next_stack, strings.clone(path))

    accum := new_loader_accum()
    _, err, ok := module_definition_from_forms(&accum, forms[:], path, next_stack[:], false)
    if !ok {
        return Loader_Accum{}, err, false
    }
    return accum, Runtime_Error{}, true
}

module_definition_from_forms :: proc(accum: ^Loader_Accum, forms: []kvist.CST_Top_Form, current_path: string, import_stack: []string, allow_live_decls: bool) -> (Module_Definition, Runtime_Error, bool) {
    for top in forms {
        form := top.form
        if form.kind != .List || len(form.items) == 0 || form.items[0].kind != .Symbol {
            continue
        }

        if kvist.is_symbol(form.items[0], "import") {
            resolved, import_err, import_ok := resolve_import_path_from_form(form, current_path)
            if !import_ok {
                return loader_error(import_err.message, accum)
            }

            imported, imported_err, imported_ok := load_imported_live_file(resolved, import_stack)
            if !imported_ok {
                return loader_error(imported_err.message, accum)
            }
            merge_imported_accum(accum, imported)
            loader_accum_delete(&imported)
            continue
        }

        if kvist.is_symbol(form.items[0], "live/module") {
            if !allow_live_decls {
                return loader_error("live/module is only allowed in the root live module file", accum)
            }
            if len(form.items) != 2 {
                return loader_error("live/module expects one options map", accum)
            }
            if form.items[1].kind != .Brace {
                return loader_error("live/module expects a brace options map", accum)
            }

            i := 0
            for i < len(form.items[1].items) {
                if i+1 >= len(form.items[1].items) {
                    return loader_error("live/module options map has a missing value", accum)
                }
                key_form := form.items[1].items[i]
                value_form := form.items[1].items[i+1]
                key, key_ok := option_state_key(key_form)
                if !key_ok {
                    return loader_error("live/module expects keyword keys", accum)
                }
                value, value_err, value_ok := kvist_literal_value(value_form)
                if !value_ok {
                    return loader_error(value_err.message, accum)
                }
                switch key {
                case "name":
                    if value.kind != .String {
                        value_delete(&value)
                        return loader_error("live/module :name must be a string", accum)
                    }
                    delete(accum.name)
                    accum.name = strings.clone(value.text)
                    value_delete(&value)
                case "version":
                    if value.kind != .String {
                        value_delete(&value)
                        return loader_error("live/module :version must be a string", accum)
                    }
                    delete(accum.version)
                    accum.version = strings.clone(value.text)
                    value_delete(&value)
                case:
                    put_state_value(&accum.state, key, value)
                }
                i += 2
            }
            continue
        }

        if kvist.is_symbol(form.items[0], "live/defn") || kvist.is_symbol(form.items[0], "defn") {
            form_name := form.items[0].text
            if len(form.items) < 4 {
                return loader_errorf(accum, "%s expects a name, parameter vector, and a body", form_name)
            }
            if form.items[1].kind != .Symbol {
                return loader_errorf(accum, "%s expects a symbol name", form_name)
            }
            if !allow_live_decls && (form.items[1].text == "init" || form.items[1].text == "shutdown" || form.items[1].text == "migrate") {
                return loader_error("imported live helper files may not define init, shutdown, or migrate", accum)
            }
            params, params_err, params_ok := extract_params(form.items[2], form_name)
            if !params_ok {
                return loader_error(params_err.message, accum)
            }
            put_behavior_definition(&accum.functions, Behavior_Definition{
                name = strings.clone(form.items[1].text),
                params = params,
                body = clone_cst_form_slice(form.items[3:]),
            })
            continue
        }

        if kvist.is_symbol(form.items[0], "live/command") {
            if !allow_live_decls {
                return loader_error("live/command is only allowed in the root live module file", accum)
            }
            name_form, options_form, body_start, part_err, part_ok := command_or_hook_parts(form, "live/command")
            if !part_ok {
                return loader_error(part_err.message, accum)
            }
            put_state_string(&accum.state, "command-name", name_form.text)
            doc := ""
            if options_form.kind == .Brace {
                options_err, options_ok := apply_literal_options(&accum.state, options_form)
                if !options_ok {
                    return loader_error(options_err.message, accum)
                }
                doc = extract_behavior_doc(options_form)
            }
            put_behavior_definition(&accum.commands, Behavior_Definition{
                name = strings.clone(name_form.text),
                doc = strings.clone(doc),
                body = clone_cst_form_slice(form.items[body_start:]),
            })
            continue
        }

        if kvist.is_symbol(form.items[0], "live/hook") {
            if !allow_live_decls {
                return loader_error("live/hook is only allowed in the root live module file", accum)
            }
            name_form, options_form, body_start, part_err, part_ok := command_or_hook_parts(form, "live/hook")
            if !part_ok {
                return loader_error(part_err.message, accum)
            }
            put_state_string(&accum.state, "hook-name", name_form.text)
            doc := ""
            if options_form.kind == .Brace {
                options_err, options_ok := apply_literal_options(&accum.state, options_form)
                if !options_ok {
                    return loader_error(options_err.message, accum)
                }
                doc = extract_behavior_doc(options_form)
            }
            put_behavior_definition(&accum.hooks, Behavior_Definition{
                name = strings.clone(name_form.text),
                doc = strings.clone(doc),
                body = clone_cst_form_slice(form.items[body_start:]),
            })
            continue
        }

        if !kvist.is_symbol(form.items[0], "defconst") && !kvist.is_symbol(form.items[0], "defvar") && !kvist.is_symbol(form.items[0], "def") {
            continue
        }

        if len(form.items) < 3 || form.items[1].kind != .Symbol {
            return loader_error("live module bindings require symbol names", accum)
        }

        binding_name := form.items[1].text
        value_form := form.items[len(form.items)-1]
        value, value_err, value_ok := kvist_literal_value(value_form)
        if !value_ok {
            return loader_error(value_err.message, accum)
        }

        switch binding_name {
        case "module-name":
            if value.kind != .String {
                value_delete(&value)
                return loader_error("module-name must be a string", accum)
            }
            delete(accum.name)
            accum.name = strings.clone(value.text)
            value_delete(&value)
        case "module-version":
            if value.kind != .String {
                value_delete(&value)
                return loader_error("module-version must be a string", accum)
            }
            delete(accum.version)
            accum.version = strings.clone(value.text)
            value_delete(&value)
        case:
            put_state_value(&accum.state, binding_name, value)
        }
    }

    return Module_Definition{}, Runtime_Error{}, true
}

finalize_module_definition :: proc(accum: ^Loader_Accum) -> (Module_Definition, Runtime_Error, bool) {
    if accum.name == "" {
        return loader_error("module-name must not be empty", accum)
    }

    for i in 0 ..< len(accum.commands) {
        if len(accum.commands[i].body) > 0 {
            continue
        }
        fn_def, found := find_behavior_definition(accum.functions[:], accum.commands[i].name)
        if !found {
            return loader_errorf(accum, "live/command %s needs a body or a same-named defn", accum.commands[i].name)
        }
        if len(fn_def.params) != 0 {
            return loader_errorf(accum, "live/command %s currently requires a zero-arg defn", accum.commands[i].name)
        }
        accum.commands[i].body = clone_cst_form_slice(fn_def.body[:])
    }

    for i in 0 ..< len(accum.hooks) {
        if len(accum.hooks[i].body) > 0 {
            continue
        }
        fn_def, found := find_behavior_definition(accum.functions[:], accum.hooks[i].name)
        if !found {
            return loader_errorf(accum, "live/hook %s needs a body or a same-named defn", accum.hooks[i].name)
        }
        if len(fn_def.params) != 0 {
            return loader_errorf(accum, "live/hook %s currently requires a zero-arg defn", accum.hooks[i].name)
        }
        accum.hooks[i].body = clone_cst_form_slice(fn_def.body[:])
    }

    return Module_Definition{
        name = accum.name,
        version = accum.version,
        initial_state = accum.state,
        functions = accum.functions,
        commands = accum.commands,
        hooks = accum.hooks,
    }, Runtime_Error{}, true
}

module_definition_from_kvist_source :: proc(source: string) -> (Module_Definition, Runtime_Error, bool) {
    forms, read_err, read_ok := kvist.read_top_forms(source)
    if !read_ok {
        return Module_Definition{}, Runtime_Error{message = strings.clone(read_err.message)}, false
    }

    accum := new_loader_accum()
    _, err, ok := module_definition_from_forms(&accum, forms[:], "", nil, true)
    if !ok {
        return Module_Definition{}, err, false
    }
    return finalize_module_definition(&accum)
}

module_definition_from_kvist_path :: proc(path: string) -> (Module_Definition, Runtime_Error, bool) {
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        return Module_Definition{}, Runtime_Error{message = strings.clone(fmt.tprintf("could not read live module: %s", path))}, false
    }
    defer delete(data)

    forms, forms_err, forms_ok := kvist.read_top_forms(string(data))
    if !forms_ok {
        return Module_Definition{}, Runtime_Error{message = strings.clone(forms_err.message)}, false
    }

    stack: [dynamic]string
    defer delete_string_stack(&stack)
    append(&stack, strings.clone(path))

    accum := new_loader_accum()
    _, err, ok := module_definition_from_forms(&accum, forms[:], path, stack[:], true)
    if !ok {
        return Module_Definition{}, err, false
    }
    return finalize_module_definition(&accum)
}
