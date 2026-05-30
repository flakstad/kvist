package main

import "core:fmt"
import kvist_live "../../src/kvist_live"

demo_command :: proc(runtime: ^kvist_live.Runtime, module: ^kvist_live.Live_Module, command: ^kvist_live.Live_Command, args: []kvist_live.Value) -> (kvist_live.Value, kvist_live.Runtime_Error, bool) {
    count := i64(0)
    if entry, ok := kvist_live.module_state_get(module, "count"); ok && entry.value.kind == .Int {
        count = entry.value.int_value
    }
    count += 1

    next_count := kvist_live.value_int(count)
    defer kvist_live.value_delete(&next_count)
    kvist_live.module_state_put(module, "count", next_count)

    message, _ := kvist_live.module_state_get_string(module, "message")
    fmt.println(fmt.tprintf("[%s] %s (count=%d)", module.version, message, count))

    return kvist_live.value_int(count), kvist_live.Runtime_Error{}, true
}

demo_init :: proc(runtime: ^kvist_live.Runtime, module: ^kvist_live.Live_Module) -> (kvist_live.Runtime_Error, bool) {
    err, ok := kvist_live.register_command(runtime, module, "tick", "Print the live message and increment count.", demo_command)
    if !ok {
        return err, false
    }
    return kvist_live.Runtime_Error{}, true
}

demo_migrate :: proc(runtime: ^kvist_live.Runtime, old_module: kvist_live.Live_Module, new_module: ^kvist_live.Live_Module) -> (kvist_live.Runtime_Error, bool) {
    if entry, ok := kvist_live.state_entries_get(old_module.state[:], "count"); ok {
        kvist_live.module_state_put(new_module, "count", entry.value)
    }
    kvist_live.module_state_put_string(new_module, "migrated-from", old_module.version)
    return kvist_live.Runtime_Error{}, true
}

append_state_string :: proc(entries: ^[dynamic]kvist_live.State_Entry, key, value: string) {
    append(entries, kvist_live.State_Entry{
        key = key,
        value = kvist_live.value_string(value),
    })
}

delete_definition :: proc(def: ^kvist_live.Module_Definition) {
    if def.name != "" {
        delete(def.name)
    }
    if def.version != "" {
        delete(def.version)
    }
    kvist_live.state_entry_slice_delete(&def.initial_state)
    kvist_live.delete_behavior_definition_slice(&def.commands)
    kvist_live.delete_behavior_definition_slice(&def.hooks)
    def^ = kvist_live.Module_Definition{}
}

build_definition :: proc(version, message: string) -> kvist_live.Module_Definition {
    state: [dynamic]kvist_live.State_Entry
    append_state_string(&state, "message", message)

    return kvist_live.Module_Definition{
        name = "demo",
        version = version,
        initial_state = state,
        init = demo_init,
        migrate = demo_migrate,
    }
}

main :: proc() {
    runtime := kvist_live.new_runtime(kvist_live.Runtime_Config{
        app_name = "live-reload-demo",
        live_enabled = true,
    })
    defer kvist_live.runtime_delete(&runtime)

    v1 := build_definition("v1", "hello from version one")
    defer delete_definition(&v1)
    load_err, load_ok := kvist_live.load_module(&runtime, v1)
    if !load_ok {
        fmt.eprintln("load failed: ", load_err.message)
        return
    }

    _, _, _ = kvist_live.invoke_command(&runtime, "tick", nil)

    v2 := build_definition("v2", "hello from version two")
    defer delete_definition(&v2)
    reload_err, reload_ok := kvist_live.reload_module(&runtime, v2)
    if !reload_ok {
        fmt.eprintln("reload failed: ", reload_err.message)
        return
    }

    _, _, _ = kvist_live.invoke_command(&runtime, "tick", nil)

    if module, ok := kvist_live.loaded_module(&runtime, "demo"); ok {
        migrated_from, _ := kvist_live.module_state_get_string(module, "migrated-from")
        if entry, count_ok := kvist_live.module_state_get(module, "count"); count_ok {
            fmt.println(fmt.tprintf("state survived reload: count=%d migrated-from=%s", entry.value.int_value, migrated_from))
        }
    }
}
