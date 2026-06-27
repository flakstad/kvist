// Copyright (c) Andreas Flakstad and Kvist contributors
// SPDX-License-Identifier: MIT

package kvist_live

import "core:strings"
import kvist "../kvist"

value_nil :: proc() -> Value {
    return Value{kind = .Nil}
}

value_bool :: proc(v: bool) -> Value {
    return Value{kind = .Bool, bool_value = v}
}

value_int :: proc(v: i64) -> Value {
    return Value{kind = .Int, int_value = v}
}

value_string :: proc(v: string) -> Value {
    return Value{kind = .String, text = strings.clone(v)}
}

value_keyword :: proc(v: string) -> Value {
    return Value{kind = .Keyword, text = strings.clone(v)}
}

value_handle :: proc(v: string) -> Value {
    return Value{kind = .Handle, text = strings.clone(v)}
}

value_delete :: proc(value: ^Value) {
    #partial switch value.kind {
    case .String, .Keyword, .Handle:
        if value.text != "" {
            delete(value.text)
        }
    case:
    }
    value^ = Value{}
}

value_clone :: proc(value: Value) -> Value {
    cloned := value
    #partial switch value.kind {
    case .String, .Keyword, .Handle:
        cloned.text = strings.clone(value.text)
    case:
    }
    return cloned
}

state_entry_delete :: proc(entry: ^State_Entry) {
    if entry.key != "" {
        delete(entry.key)
    }
    value_delete(&entry.value)
    entry^ = State_Entry{}
}

state_entry_clone :: proc(entry: State_Entry) -> State_Entry {
    return State_Entry{
        key = strings.clone(entry.key),
        value = value_clone(entry.value),
    }
}

module_state_delete :: proc(state: ^[dynamic]State_Entry) {
    for i in 0 ..< len(state^) {
        state_entry_delete(&state^[i])
    }
    delete(state^)
    state^ = nil
}

state_entry_slice_delete :: proc(state: ^[dynamic]State_Entry) {
    module_state_delete(state)
}

module_state_clone :: proc(state: []State_Entry) -> (out: [dynamic]State_Entry) {
    for entry in state {
        append(&out, state_entry_clone(entry))
    }
    return out
}

runtime_event_delete :: proc(event: ^Runtime_Event) {
    if event.module_name != "" {
        delete(event.module_name)
    }
    if event.detail != "" {
        delete(event.detail)
    }
    event^ = Runtime_Event{}
}

runtime_delete :: proc(runtime: ^Runtime) {
    if runtime.config.app_name != "" {
        delete(runtime.config.app_name)
    }

    for i in 0 ..< len(runtime.capabilities) {
        if runtime.capabilities[i].name != "" {
            delete(runtime.capabilities[i].name)
        }
        if runtime.capabilities[i].doc != "" {
            delete(runtime.capabilities[i].doc)
        }
    }
    delete(runtime.capabilities)

    for i in 0 ..< len(runtime.commands) {
        if runtime.commands[i].name != "" {
            delete(runtime.commands[i].name)
        }
        if runtime.commands[i].module_name != "" {
            delete(runtime.commands[i].module_name)
        }
        if runtime.commands[i].doc != "" {
            delete(runtime.commands[i].doc)
        }
        delete_cst_form_slice(&runtime.commands[i].body)
    }
    delete(runtime.commands)

    for i in 0 ..< len(runtime.hooks) {
        if runtime.hooks[i].name != "" {
            delete(runtime.hooks[i].name)
        }
        if runtime.hooks[i].module_name != "" {
            delete(runtime.hooks[i].module_name)
        }
        if runtime.hooks[i].doc != "" {
            delete(runtime.hooks[i].doc)
        }
        delete_cst_form_slice(&runtime.hooks[i].body)
    }
    delete(runtime.hooks)

    for i in 0 ..< len(runtime.modules) {
        module_delete(&runtime.modules[i])
    }
    delete(runtime.modules)

    for i in 0 ..< len(runtime.events) {
        runtime_event_delete(&runtime.events[i])
    }
    delete(runtime.events)

    runtime^ = Runtime{}
}

module_delete :: proc(module: ^Live_Module) {
    if module.name != "" {
        delete(module.name)
    }
    if module.version != "" {
        delete(module.version)
    }
    if module.reload_from_version != "" {
        delete(module.reload_from_version)
    }
    if module.last_error != "" {
        delete(module.last_error)
    }
    module_state_delete(&module.state)
    module_state_delete(&module.reload_state)
    delete_behavior_definition_slice(&module.functions)
    delete_behavior_definition_slice(&module.commands)
    delete_behavior_definition_slice(&module.hooks)
    module^ = Live_Module{}
}

module_clone :: proc(module: Live_Module) -> Live_Module {
    cloned := module
    cloned.runtime = nil
    cloned.name = strings.clone(module.name)
    cloned.version = strings.clone(module.version)
    cloned.reload_from_version = strings.clone(module.reload_from_version)
    cloned.last_error = strings.clone(module.last_error)
    cloned.state = module_state_clone(module.state[:])
    cloned.reload_state = module_state_clone(module.reload_state[:])
    cloned.functions = clone_behavior_definition_slice(module.functions[:])
    cloned.commands = clone_behavior_definition_slice(module.commands[:])
    cloned.hooks = clone_behavior_definition_slice(module.hooks[:])
    return cloned
}

new_runtime :: proc(config: Runtime_Config) -> Runtime {
    return Runtime{
        config = Runtime_Config{
            app_name = strings.clone(config.app_name),
            live_enabled = config.live_enabled,
        },
        next_generation = 1,
    }
}

record_event :: proc(runtime: ^Runtime, kind: Runtime_Event_Kind, module_name, detail: string) {
    append(&runtime.events, Runtime_Event{
        kind = kind,
        module_name = strings.clone(module_name),
        detail = strings.clone(detail),
    })
}

find_capability_index :: proc(runtime: ^Runtime, name: string) -> int {
    for capability, idx in runtime.capabilities {
        if capability.name == name {
            return idx
        }
    }
    return -1
}

find_module_index :: proc(runtime: ^Runtime, name: string) -> int {
    for module, idx in runtime.modules {
        if module.name == name {
            return idx
        }
    }
    return -1
}

register_capability :: proc(runtime: ^Runtime, capability: Host_Capability) -> (Runtime_Error, bool) {
    if capability.name == "" {
        err := Runtime_Error{message = strings.clone("capability name must not be empty")}
        record_event(runtime, .Error, "", err.message)
        return err, false
    }
    if capability.handler == nil {
        err := Runtime_Error{message = strings.clone("capability handler must not be nil")}
        record_event(runtime, .Error, capability.name, err.message)
        return err, false
    }
    if find_capability_index(runtime, capability.name) >= 0 {
        err := Runtime_Error{message = strings.clone("capability already registered")}
        record_event(runtime, .Error, capability.name, err.message)
        return err, false
    }

    append(&runtime.capabilities, Host_Capability{
        name = strings.clone(capability.name),
        doc = strings.clone(capability.doc),
        handler = capability.handler,
    })
    record_event(runtime, .Capability_Registered, capability.name, capability.doc)
    return Runtime_Error{}, true
}

call_capability :: proc(runtime: ^Runtime, name: string, args: []Value) -> (Value, Runtime_Error, bool) {
    idx := find_capability_index(runtime, name)
    if idx < 0 {
        err := Runtime_Error{message = strings.clone("unknown capability")}
        record_event(runtime, .Error, name, err.message)
        return value_nil(), err, false
    }

    record_event(runtime, .Capability_Called, name, "")
    return runtime.capabilities[idx].handler(runtime, name, args)
}

module_state_put :: proc(module: ^Live_Module, key: string, value: Value) {
    for i in 0 ..< len(module.state) {
        if module.state[i].key == key {
            value_delete(&module.state[i].value)
            module.state[i].value = value_clone(value)
            return
        }
    }
    append(&module.state, State_Entry{
        key = strings.clone(key),
        value = value_clone(value),
    })
}

module_state_put_string :: proc(module: ^Live_Module, key, value: string) {
    temp := value_string(value)
    defer value_delete(&temp)
    module_state_put(module, key, temp)
}

module_state_get :: proc(module: ^Live_Module, key: string) -> (^State_Entry, bool) {
    for i in 0 ..< len(module.state) {
        if module.state[i].key == key {
            return &module.state[i], true
        }
    }
    return nil, false
}

state_entries_get :: proc(state: []State_Entry, key: string) -> (State_Entry, bool) {
    for entry in state {
        if entry.key == key {
            return entry, true
        }
    }
    return State_Entry{}, false
}

state_entries_get_dynamic :: proc(state: [dynamic]State_Entry, key: string) -> (State_Entry, bool) {
    return state_entries_get(state[:], key)
}

state_entries_get_string :: proc(state: []State_Entry, key: string) -> (string, bool) {
    for entry in state {
        if entry.key == key && entry.value.kind == .String {
            return entry.value.text, true
        }
    }
    return "", false
}

module_state_get_string :: proc(module: ^Live_Module, key: string) -> (string, bool) {
    return state_entries_get_string(module.state[:], key)
}

merge_missing_state_entries :: proc(dst: ^Live_Module, src: []State_Entry) {
    for entry in src {
        if _, exists := module_state_get(dst, entry.key); exists {
            continue
        }
        module_state_put(dst, entry.key, entry.value)
    }
}

module_definition_to_module :: proc(runtime: ^Runtime, def: Module_Definition) -> Live_Module {
    module := Live_Module{
        runtime = runtime,
        name = strings.clone(def.name),
        version = strings.clone(def.version),
        state = module_state_clone(def.initial_state[:]),
        functions = clone_behavior_definition_slice(def.functions[:]),
        commands = clone_behavior_definition_slice(def.commands[:]),
        hooks = clone_behavior_definition_slice(def.hooks[:]),
        init = def.init,
        shutdown = def.shutdown,
        migrate = def.migrate,
        generation = runtime.next_generation,
    }
    runtime.next_generation += 1
    return module
}

run_source_init :: proc(runtime: ^Runtime, module: ^Live_Module) -> (Runtime_Error, bool) {
    if _, found := find_live_function(module, "init"); !found {
        return Runtime_Error{}, true
    }

    result, err, ok := execute_named_live_function(module, "init", nil)
    value_delete(&result)
    if !ok && err.message != "" {
        record_event(runtime, .Error, module.name, err.message)
    }
    return err, ok
}

run_source_migrate :: proc(runtime: ^Runtime, module: ^Live_Module) -> (Runtime_Error, bool) {
    if _, found := find_live_function(module, "migrate"); !found {
        return Runtime_Error{}, true
    }

    result, err, ok := execute_named_live_function(module, "migrate", nil)
    value_delete(&result)
    if !ok && err.message != "" {
        record_event(runtime, .Error, module.name, err.message)
    }
    return err, ok
}

run_source_shutdown :: proc(runtime: ^Runtime, module: ^Live_Module) {
    if _, found := find_live_function(module, "shutdown"); !found {
        return
    }

    result, err, ok := execute_named_live_function(module, "shutdown", nil)
    value_delete(&result)
    if !ok && err.message != "" {
        record_event(runtime, .Error, module.name, err.message)
    }
}

find_command_index :: proc(runtime: ^Runtime, name: string) -> int {
    for i := len(runtime.commands) - 1; i >= 0; i -= 1 {
        if runtime.commands[i].name == name {
            return i
        }
    }
    return -1
}

find_module_generation :: proc(runtime: ^Runtime, generation: int) -> (^Live_Module, bool) {
    for i in 0 ..< len(runtime.modules) {
        if runtime.modules[i].generation == generation {
            return &runtime.modules[i], true
        }
    }
    return nil, false
}

register_command :: proc(runtime: ^Runtime, module: ^Live_Module, name, doc: string, handler: Command_Handler, body: []kvist.CST_Form = nil) -> (Runtime_Error, bool) {
    if name == "" {
        err := Runtime_Error{message = strings.clone("command name must not be empty")}
        record_event(runtime, .Error, module.name, err.message)
        return err, false
    }
    if handler == nil {
        err := Runtime_Error{message = strings.clone("command handler must not be nil")}
        record_event(runtime, .Error, module.name, err.message)
        return err, false
    }

    append(&runtime.commands, Live_Command{
        name = strings.clone(name),
        module_name = strings.clone(module.name),
        module_generation = module.generation,
        doc = strings.clone(doc),
        body = clone_cst_form_slice(body),
        handler = handler,
    })
    record_event(runtime, .Command_Registered, module.name, name)
    return Runtime_Error{}, true
}

invoke_command :: proc(runtime: ^Runtime, name: string, args: []Value) -> (Value, Runtime_Error, bool) {
    idx := find_command_index(runtime, name)
    if idx < 0 {
        err := Runtime_Error{message = strings.clone("unknown command")}
        record_event(runtime, .Error, name, err.message)
        return value_nil(), err, false
    }
    module, ok := find_module_generation(runtime, runtime.commands[idx].module_generation)
    if !ok {
        err := Runtime_Error{message = strings.clone("command refers to unloaded module")}
        record_event(runtime, .Error, name, err.message)
        return value_nil(), err, false
    }
    record_event(runtime, .Command_Called, module.name, name)
    return runtime.commands[idx].handler(runtime, module, &runtime.commands[idx], args)
}

register_hook :: proc(runtime: ^Runtime, module: ^Live_Module, name, doc: string, handler: Hook_Handler, body: []kvist.CST_Form = nil) -> (Runtime_Error, bool) {
    if name == "" {
        err := Runtime_Error{message = strings.clone("hook name must not be empty")}
        record_event(runtime, .Error, module.name, err.message)
        return err, false
    }
    if handler == nil {
        err := Runtime_Error{message = strings.clone("hook handler must not be nil")}
        record_event(runtime, .Error, module.name, err.message)
        return err, false
    }

    append(&runtime.hooks, Live_Hook{
        name = strings.clone(name),
        module_name = strings.clone(module.name),
        module_generation = module.generation,
        doc = strings.clone(doc),
        body = clone_cst_form_slice(body),
        handler = handler,
    })
    record_event(runtime, .Hook_Registered, module.name, name)
    return Runtime_Error{}, true
}

emit_hook :: proc(runtime: ^Runtime, name: string, payload: []Value) -> (Runtime_Error, bool) {
    fired := false
    for i in 0 ..< len(runtime.hooks) {
        if runtime.hooks[i].name != name {
            continue
        }
        module, ok := find_module_generation(runtime, runtime.hooks[i].module_generation)
        if !ok {
            continue
        }
        hook_err, hook_ok := runtime.hooks[i].handler(runtime, module, &runtime.hooks[i], payload)
        if !hook_ok {
            if hook_err.message != "" {
                record_event(runtime, .Error, module.name, hook_err.message)
            }
            return hook_err, false
        }
        fired = true
    }
    if fired {
        record_event(runtime, .Hook_Emitted, "", name)
        return Runtime_Error{}, true
    }
    err := Runtime_Error{message = strings.clone("no handlers registered for hook")}
    record_event(runtime, .Error, "", err.message)
    return err, false
}

clear_generation_commands :: proc(runtime: ^Runtime, generation: int) {
    out: [dynamic]Live_Command
    for i in 0 ..< len(runtime.commands) {
        command := runtime.commands[i]
        if command.module_generation == generation {
            if runtime.commands[i].name != "" {
                delete(runtime.commands[i].name)
            }
            if runtime.commands[i].module_name != "" {
                delete(runtime.commands[i].module_name)
            }
            if runtime.commands[i].doc != "" {
                delete(runtime.commands[i].doc)
            }
            delete_cst_form_slice(&runtime.commands[i].body)
            continue
        }
        append(&out, command)
    }
    delete(runtime.commands)
    runtime.commands = out
}

clear_generation_hooks :: proc(runtime: ^Runtime, generation: int) {
    out: [dynamic]Live_Hook
    for i in 0 ..< len(runtime.hooks) {
        hook := runtime.hooks[i]
        if hook.module_generation == generation {
            if runtime.hooks[i].name != "" {
                delete(runtime.hooks[i].name)
            }
            if runtime.hooks[i].module_name != "" {
                delete(runtime.hooks[i].module_name)
            }
            if runtime.hooks[i].doc != "" {
                delete(runtime.hooks[i].doc)
            }
            delete_cst_form_slice(&runtime.hooks[i].body)
            continue
        }
        append(&out, hook)
    }
    delete(runtime.hooks)
    runtime.hooks = out
}

load_module :: proc(runtime: ^Runtime, def: Module_Definition) -> (Runtime_Error, bool) {
    if def.name == "" {
        err := Runtime_Error{message = strings.clone("module name must not be empty")}
        record_event(runtime, .Error, "", err.message)
        return err, false
    }
    if find_module_index(runtime, def.name) >= 0 {
        err := Runtime_Error{message = strings.clone("module already loaded")}
        record_event(runtime, .Error, def.name, err.message)
        return err, false
    }

    module := module_definition_to_module(runtime, def)
    if module.init != nil {
        init_err, ok := module.init(runtime, &module)
        if !ok {
            if init_err.message != "" {
                module.last_error = strings.clone(init_err.message)
                record_event(runtime, .Error, def.name, init_err.message)
            }
            clear_generation_commands(runtime, module.generation)
            clear_generation_hooks(runtime, module.generation)
            module_delete(&module)
            return init_err, false
        }
        module.init_count += 1
    }

    for command_def in module.commands {
        command_err, command_ok := register_command(runtime, &module, command_def.name, command_def.doc, execute_command_body, command_def.body[:])
        if !command_ok {
            clear_generation_commands(runtime, module.generation)
            clear_generation_hooks(runtime, module.generation)
            module_delete(&module)
            return command_err, false
        }
    }
    for hook_def in module.hooks {
        hook_err, hook_ok := register_hook(runtime, &module, hook_def.name, hook_def.doc, execute_hook_body, hook_def.body[:])
        if !hook_ok {
            clear_generation_commands(runtime, module.generation)
            clear_generation_hooks(runtime, module.generation)
            module_delete(&module)
            return hook_err, false
        }
    }

    source_init_err, source_init_ok := run_source_init(runtime, &module)
    if !source_init_ok {
        clear_generation_commands(runtime, module.generation)
        clear_generation_hooks(runtime, module.generation)
        module_delete(&module)
        return source_init_err, false
    }

    append(&runtime.modules, module)
    record_event(runtime, .Module_Loaded, def.name, def.version)
    return Runtime_Error{}, true
}

reload_module :: proc(runtime: ^Runtime, def: Module_Definition) -> (Runtime_Error, bool) {
    idx := find_module_index(runtime, def.name)
    if idx < 0 {
        return load_module(runtime, def)
    }

    old_module := module_clone(runtime.modules[idx])
    defer module_delete(&old_module)

    new_module := module_definition_to_module(runtime, def)
    new_module.reload_count = runtime.modules[idx].reload_count + 1
    new_module.reload_from_version = strings.clone(old_module.version)
    new_module.reload_state = module_state_clone(old_module.state[:])

    if def.migrate != nil {
        migrate_err, ok := def.migrate(runtime, old_module, &new_module)
        if !ok {
            if migrate_err.message != "" {
                record_event(runtime, .Error, def.name, migrate_err.message)
            }
            module_delete(&new_module)
            return migrate_err, false
        }
    } else {
        // Keep new source-defined bindings from the replacement module, and
        // only carry forward runtime-added state slots that are missing.
        merge_missing_state_entries(&new_module, old_module.state[:])
    }

    source_migrate_err, source_migrate_ok := run_source_migrate(runtime, &new_module)
    if !source_migrate_ok {
        clear_generation_commands(runtime, new_module.generation)
        clear_generation_hooks(runtime, new_module.generation)
        module_delete(&new_module)
        return source_migrate_err, false
    }

    if new_module.init != nil {
        init_err, ok := new_module.init(runtime, &new_module)
        if !ok {
            if init_err.message != "" {
                record_event(runtime, .Error, def.name, init_err.message)
            }
            clear_generation_commands(runtime, new_module.generation)
            clear_generation_hooks(runtime, new_module.generation)
            module_delete(&new_module)
            return init_err, false
        }
        new_module.init_count = old_module.init_count + 1
    } else {
        new_module.init_count = old_module.init_count
    }

    for command_def in new_module.commands {
        command_err, command_ok := register_command(runtime, &new_module, command_def.name, command_def.doc, execute_command_body, command_def.body[:])
        if !command_ok {
            clear_generation_commands(runtime, new_module.generation)
            clear_generation_hooks(runtime, new_module.generation)
            module_delete(&new_module)
            return command_err, false
        }
    }
    for hook_def in new_module.hooks {
        hook_err, hook_ok := register_hook(runtime, &new_module, hook_def.name, hook_def.doc, execute_hook_body, hook_def.body[:])
        if !hook_ok {
            clear_generation_commands(runtime, new_module.generation)
            clear_generation_hooks(runtime, new_module.generation)
            module_delete(&new_module)
            return hook_err, false
        }
    }

    source_init_err, source_init_ok := run_source_init(runtime, &new_module)
    if !source_init_ok {
        clear_generation_commands(runtime, new_module.generation)
        clear_generation_hooks(runtime, new_module.generation)
        module_delete(&new_module)
        return source_init_err, false
    }

    if runtime.modules[idx].shutdown != nil {
        runtime.modules[idx].shutdown(runtime, &runtime.modules[idx])
        record_event(runtime, .Module_Shutdown, def.name, runtime.modules[idx].version)
    }
    run_source_shutdown(runtime, &runtime.modules[idx])

    clear_generation_commands(runtime, runtime.modules[idx].generation)
    clear_generation_hooks(runtime, runtime.modules[idx].generation)
    module_delete(&runtime.modules[idx])
    runtime.modules[idx] = new_module
    record_event(runtime, .Module_Reloaded, def.name, def.version)
    return Runtime_Error{}, true
}

loaded_module :: proc(runtime: ^Runtime, name: string) -> (^Live_Module, bool) {
    idx := find_module_index(runtime, name)
    if idx < 0 {
        return nil, false
    }
    return &runtime.modules[idx], true
}
