package kvist_live_demo_support

import "core:fmt"
import "core:strings"
import kvist_live "../kvist_live"

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

Host_Log_Capability :: proc(runtime: ^kvist_live.Runtime, capability_name: string, args: []kvist_live.Value) -> (kvist_live.Value, kvist_live.Runtime_Error, bool) {
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

Host_Render_Tick_Capability :: proc(runtime: ^kvist_live.Runtime, capability_name: string, args: []kvist_live.Value) -> (kvist_live.Value, kvist_live.Runtime_Error, bool) {
    if len(args) != 3 {
        return kvist_live.value_nil(), kvist_live.Runtime_Error{message = strings.clone("host.render-tick expects version, message, and count")}, false
    }
    if args[0].kind != .String || args[1].kind != .String || args[2].kind != .Int {
        return kvist_live.value_nil(), kvist_live.Runtime_Error{message = strings.clone("host.render-tick received invalid argument types")}, false
    }
    fmt.println(fmt.tprintf("[%s] %s (count=%d)", args[0].text, args[1].text, args[2].int_value))
    return kvist_live.value_nil(), kvist_live.Runtime_Error{}, true
}

Register_Live_Commands_Capabilities :: proc(runtime: ^kvist_live.Runtime) -> (kvist_live.Runtime_Error, bool) {
    capability_err, capability_ok := kvist_live.register_capability(runtime, kvist_live.Host_Capability{
        name = "host.log",
        doc = "Print a line from the host side.",
        handler = Host_Log_Capability,
    })
    if !capability_ok {
        return capability_err, false
    }

    return kvist_live.register_capability(runtime, kvist_live.Host_Capability{
        name = "host.render-tick",
        doc = "Render the current tick message from the host side.",
        handler = Host_Render_Tick_Capability,
    })
}

Live_Module_Init :: proc(runtime: ^kvist_live.Runtime, module: ^kvist_live.Live_Module) -> (kvist_live.Runtime_Error, bool) {
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

Live_Module_Shutdown :: proc(runtime: ^kvist_live.Runtime, module: ^kvist_live.Live_Module) {
    fmt.println(fmt.tprintf("shutting down module %s (%s)", module.name, module.version))
}

Print_Live_Commands_Banner :: proc(module_path, live_dir: string) {
    fmt.println("kvist live commands demo")
    fmt.println("editing file: ", module_path)
    fmt.println("edit files under: ", live_dir)
    fmt.println("edit the root module or imported helper file while this runs")
    fmt.println("press ctrl-c to stop")
    fmt.println("")
}
