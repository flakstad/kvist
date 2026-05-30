package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import kvist_live "../../src/kvist_live"

MODULE_PATH :: "examples/live_commands_demo/live/commands.kvist"
TICK_DELAY :: 1 * time.Second

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

read_module_source :: proc(path: string) -> (string, bool) {
    data, read_err := os.read_entire_file_from_path(path, context.allocator)
    if read_err != nil {
        fmt.eprintln("could not read live module: ", path)
        return "", false
    }
    defer delete(data)
    return strings.clone(string(data)), true
}

render_value :: proc(value: kvist_live.Value) -> string {
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

host_log_capability :: proc(runtime: ^kvist_live.Runtime, capability_name: string, args: []kvist_live.Value) -> (kvist_live.Value, kvist_live.Runtime_Error, bool) {
    if len(args) == 0 {
        fmt.println("[host.log]")
        return kvist_live.value_nil(), kvist_live.Runtime_Error{}, true
    }

    for arg in args {
        rendered := render_value(arg)
        fmt.println("[host.log] ", rendered)
        delete(rendered)
    }
    return kvist_live.value_nil(), kvist_live.Runtime_Error{}, true
}

host_render_tick_capability :: proc(runtime: ^kvist_live.Runtime, capability_name: string, args: []kvist_live.Value) -> (kvist_live.Value, kvist_live.Runtime_Error, bool) {
    if len(args) != 3 {
        return kvist_live.value_nil(), kvist_live.Runtime_Error{message = strings.clone("host.render-tick expects version, message, and count")}, false
    }
    if args[0].kind != .String || args[1].kind != .String || args[2].kind != .Int {
        return kvist_live.value_nil(), kvist_live.Runtime_Error{message = strings.clone("host.render-tick received invalid argument types")}, false
    }
    fmt.println(fmt.tprintf("[%s] %s (count=%d)", args[0].text, args[1].text, args[2].int_value))
    return kvist_live.value_nil(), kvist_live.Runtime_Error{}, true
}

live_module_init :: proc(runtime: ^kvist_live.Runtime, module: ^kvist_live.Live_Module) -> (kvist_live.Runtime_Error, bool) {
    command_name, command_ok := kvist_live.module_state_get_string(module, "command-name")
    if !command_ok || command_name == "" {
        kvist_live.module_state_put_string(module, "command-name", "tick")
    }

    counter_key, counter_ok := kvist_live.module_state_get_string(module, "counter-key")
    if !counter_ok || counter_key == "" {
        kvist_live.module_state_put_string(module, "counter-key", "run-count")
        counter_key = "run-count"
    }

    if _, ok := kvist_live.module_state_get(module, counter_key); !ok {
        start_count := kvist_live.value_int(0)
        defer kvist_live.value_delete(&start_count)
        kvist_live.module_state_put(module, counter_key, start_count)
    }

    return kvist_live.Runtime_Error{}, true
}

live_module_migrate :: proc(runtime: ^kvist_live.Runtime, old_module: kvist_live.Live_Module, new_module: ^kvist_live.Live_Module) -> (kvist_live.Runtime_Error, bool) {
    new_counter_key, new_counter_ok := kvist_live.module_state_get_string(new_module, "counter-key")
    if !new_counter_ok || new_counter_key == "" {
        new_counter_key = "run-count"
        kvist_live.module_state_put_string(new_module, "counter-key", new_counter_key)
    }

    old_counter_key, old_counter_ok := kvist_live.state_entries_get_string(old_module.state[:], "counter-key")
    if !old_counter_ok || old_counter_key == "" {
        old_counter_key = new_counter_key
    }

    if entry, ok := kvist_live.state_entries_get(old_module.state[:], old_counter_key); ok {
        kvist_live.module_state_put(new_module, new_counter_key, entry.value)
    }
    kvist_live.module_state_put_string(new_module, "migrated-from", old_module.version)
    return kvist_live.Runtime_Error{}, true
}

live_module_shutdown :: proc(runtime: ^kvist_live.Runtime, module: ^kvist_live.Live_Module) {
    fmt.println(fmt.tprintf("shutting down module %s (%s)", module.name, module.version))
}

print_banner :: proc() {
    fmt.println("kvist live commands demo")
    fmt.println("editing file: ", MODULE_PATH)
    fmt.println("edit the live command or hook bodies while this runs")
    fmt.println("press ctrl-c to stop")
    fmt.println("")
}

main :: proc() {
    runtime := kvist_live.new_runtime(kvist_live.Runtime_Config{
        app_name = "live-commands-demo",
        live_enabled = true,
    })
    defer kvist_live.runtime_delete(&runtime)

    capability_err, capability_ok := kvist_live.register_capability(&runtime, kvist_live.Host_Capability{
        name = "host.log",
        doc = "Print a line from the host side.",
        handler = host_log_capability,
    })
    if !capability_ok {
        fmt.eprintln("failed to register host capability: ", capability_err.message)
        return
    }

    render_err, render_ok := kvist_live.register_capability(&runtime, kvist_live.Host_Capability{
        name = "host.render-tick",
        doc = "Render the current tick message from the host side.",
        handler = host_render_tick_capability,
    })
    if !render_ok {
        fmt.eprintln("failed to register render capability: ", render_err.message)
        return
    }

    source, source_ok := read_module_source(MODULE_PATH)
    if !source_ok {
        return
    }
    defer delete(source)

    initial_def, initial_err, initial_ok := kvist_live.module_definition_from_kvist_source(source)
    if initial_ok {
        initial_def.init = live_module_init
        initial_def.migrate = live_module_migrate
        initial_def.shutdown = live_module_shutdown
    }
    if !initial_ok {
        fmt.eprintln("failed to parse live module: ", initial_err.message)
        return
    }
    load_err, load_ok := kvist_live.load_module(&runtime, initial_def)
    delete_definition(&initial_def)
    if !load_ok {
        fmt.eprintln("failed to load live module: ", load_err.message)
        return
    }

    print_banner()

    for {
        current_source, current_ok := read_module_source(MODULE_PATH)
        if current_ok {
            if current_source != source {
                next_def, next_err, next_ok := kvist_live.module_definition_from_kvist_source(current_source)
                if next_ok {
                    next_def.init = live_module_init
                    next_def.migrate = live_module_migrate
                    next_def.shutdown = live_module_shutdown
                }
                if !next_ok {
                    fmt.eprintln("reload parse failed: ", next_err.message)
                    delete(current_source)
                } else {
                    reload_err, reload_ok := kvist_live.reload_module(&runtime, next_def)
                    delete_definition(&next_def)
                    if !reload_ok {
                        fmt.eprintln("reload failed: ", reload_err.message)
                        delete(current_source)
                    } else {
                        delete(source)
                        source = current_source
                        fmt.println("reloaded live module from disk")
                    }
                }
            } else {
                delete(current_source)
            }
        }

        _, command_err, command_ok := kvist_live.invoke_command(&runtime, "tick", nil)
        if !command_ok {
            fmt.eprintln("command failed: ", command_err.message)
        }
        time.sleep(TICK_DELAY)
    }
}
