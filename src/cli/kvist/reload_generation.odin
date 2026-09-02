package main

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import kvist "../../odin/kvist"

compile_path_to_output_or_exit :: proc(input, output_path: string) {
    data := read_source_or_exit(input)
    defer delete(transmute([]byte)data)

    result, err, ok := kvist.compile_path_with_map(input)
    if !ok {
        formatted := kvist.format_compile_error(input, data, err)
        fmt.eprint(formatted)
        delete(formatted)
        os.exit(1)
    }
    defer delete(result.output)
    defer kvist.source_map_slice_delete(result.source_map)
    defer kvist.compile_warning_slice_delete(result.warnings)

    print_compile_warnings(input, data, "", result.warnings[:])
    output, err_rebase, ok_rebase := kvist.rebase_emitted_odin_imports_for_output_path(result.output, output_path)
    if !ok_rebase {
        fmt.eprintln(err_rebase.message)
        os.exit(1)
    }
    defer delete(output)
    write_output_or_exit(output_path, output)
}

reload_app_module_source :: proc(config: Reload_App_Config, app_import_path, olive_reload_import_path: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    strings.write_string(&builder, "package hot_app_module\n\n")
    strings.write_string(&builder, "import \"base:runtime\"\n")
    fmt.sbprintf(&builder, "import app %q\n", app_import_path)
    fmt.sbprintf(&builder, "import olive_reload %q\n\n", olive_reload_import_path)
    strings.write_string(&builder, "@(export)\n")
    strings.write_string(&builder, "olive_reload_api_version: u32 = olive_reload.MANIFEST_API_VERSION\n\n")
    strings.write_string(&builder, "@(export)\n")
    strings.write_string(&builder, "olive_reload_state_size :: proc \"c\" () -> int {\n    return size_of(app.")
    strings.write_string(&builder, config.state_type)
    strings.write_string(&builder, ")\n}\n\n")
    strings.write_string(&builder, "@(export)\n")
    strings.write_string(&builder, "olive_reload_state_align :: proc \"c\" () -> int {\n    return align_of(app.")
    strings.write_string(&builder, config.state_type)
    strings.write_string(&builder, ")\n}\n\n")
    strings.write_string(&builder, "@(export)\n")
    strings.write_string(&builder, "olive_reload_on_load :: proc \"c\" (state: rawptr, is_reload: bool) {\n    context = runtime.default_context()\n    app_state := (^app.")
    strings.write_string(&builder, config.state_type)
    strings.write_string(&builder, ")(state)\n")
    if config.init_name != "" {
        strings.write_string(&builder, "    if !is_reload {\n        app.")
        strings.write_string(&builder, config.init_name)
        strings.write_string(&builder, "(app_state)\n    }\n")
    }
    if config.on_load_name != "" {
        strings.write_string(&builder, "    app.")
        strings.write_string(&builder, config.on_load_name)
        strings.write_string(&builder, "(app_state, is_reload)\n")
    }
    strings.write_string(&builder, "}\n\n")
    strings.write_string(&builder, "@(export)\n")
    strings.write_string(&builder, "olive_reload_on_unload :: proc \"c\" (state: rawptr) {\n    context = runtime.default_context()\n    app_state := (^app.")
    strings.write_string(&builder, config.state_type)
    strings.write_string(&builder, ")(state)\n")
    if config.on_unload_name != "" {
        strings.write_string(&builder, "    app.")
        strings.write_string(&builder, config.on_unload_name)
        strings.write_string(&builder, "(app_state)\n")
    }
    strings.write_string(&builder, "}\n\n")
    strings.write_string(&builder, "@(export)\n")
    strings.write_string(&builder, "kvist_reload_app_version :: proc \"c\" () -> cstring {\n    return cstring(")
    fmt.sbprintf(&builder, "%q", config.version)
    strings.write_string(&builder, ")\n}\n\n")
    strings.write_string(&builder, "@(export)\n")
    strings.write_string(&builder, "olive_reload_app_run :: proc \"c\" (state: rawptr, host: rawptr) {\n    context = runtime.default_context()\n    app_state := (^app.")
    strings.write_string(&builder, config.state_type)
    strings.write_string(&builder, ")(state)\n    app_host := (^app.")
    strings.write_string(&builder, config.reload_prefix)
    strings.write_string(&builder, "__Run_Host")
    strings.write_string(&builder, ")(host)\n    app.")
    strings.write_string(&builder, config.run_name)
    strings.write_string(&builder, "(app_state, app_host)\n}\n")

    return strings.clone(strings.to_string(builder))
}

reload_app_host_source :: proc(config: Reload_App_Config, input_path, app_import_path, olive_reload_import_path, module_binary_path: string, json_output := false) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    strings.write_string(&builder, "package hot_app_host\n\n")
    strings.write_string(&builder, "import \"core:dynlib\"\n")
    strings.write_string(&builder, "import \"core:fmt\"\n")
    strings.write_string(&builder, "import \"core:os\"\n")
    if json_output {
        strings.write_string(&builder, "import \"core:strings\"\n")
    }
    fmt.sbprintf(&builder, "import app %q\n", app_import_path)
    fmt.sbprintf(&builder, "import olive_reload %q\n\n", olive_reload_import_path)

    strings.write_string(&builder, "App_Symbols :: struct {\n")
    strings.write_string(&builder, "    :version  proc \"c\" () -> cstring `dynlib:\"kvist_reload_app_version\"`,\n")
    strings.write_string(&builder, "    :run      proc \"c\" (state: rawptr, :host rawptr) `dynlib:\"olive_reload_app_run\"`,\n")
    strings.write_string(&builder, "    __handle:    dynlib.Library,\n")
    strings.write_string(&builder, "}\n\n")
    strings.write_string(&builder, "run :: proc(symbols: ^App_Symbols, state: ^app.")
    strings.write_string(&builder, config.state_type)
    strings.write_string(&builder, ", host: ^olive_reload.Run_Host) {\n")
    strings.write_string(&builder, "    symbols.run(rawptr(state), rawptr(host))\n")
    strings.write_string(&builder, "}\n\n")
    if json_output {
        strings.write_string(&builder, "reload_event_prefix :: \"KVIST_RELOAD_EVENT\\t\"\n\n")
        strings.write_string(&builder, "reload_json_write_escaped_string :: proc(builder: ^strings.Builder, value: string) {\n")
        strings.write_string(&builder, "    strings.write_byte(builder, '\"')\n")
        strings.write_string(&builder, "    for ch in value {\n")
        strings.write_string(&builder, "        switch ch {\n")
        strings.write_string(&builder, "        case '\\\\':\n            strings.write_string(builder, \"\\\\\\\\\")\n")
        strings.write_string(&builder, "        case '\"':\n            strings.write_string(builder, \"\\\\\\\"\")\n")
        strings.write_string(&builder, "        case '\\n':\n            strings.write_string(builder, \"\\\\n\")\n")
        strings.write_string(&builder, "        case '\\r':\n            strings.write_string(builder, \"\\\\r\")\n")
        strings.write_string(&builder, "        case '\\t':\n            strings.write_string(builder, \"\\\\t\")\n")
        strings.write_string(&builder, "        case:\n            strings.write_rune(builder, ch)\n")
        strings.write_string(&builder, "        }\n")
        strings.write_string(&builder, "    }\n")
        strings.write_string(&builder, "    strings.write_byte(builder, '\"')\n")
        strings.write_string(&builder, "}\n\n")
        strings.write_string(&builder, "reload_emit_event :: proc(event, input_path, package_name, module_binary_path, rebuild_command, message: string, generation: int) {\n")
        strings.write_string(&builder, "    payload := strings.builder_make()\n")
        strings.write_string(&builder, "    defer strings.builder_destroy(&payload)\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \"{\")\n")
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, \"mode\")\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \": \")\n")
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, \"reload\")\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \", \")\n")
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, \"event\")\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \": \")\n")
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, event)\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \", \")\n")
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, \"input\")\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \": \")\n")
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, input_path)\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \", \")\n")
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, \"package\")\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \": \")\n")
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, package_name)\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \", \")\n")
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, \"module_binary\")\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \": \")\n")
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, module_binary_path)\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \", \")\n")
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, \"rebuild_command\")\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \": \")\n")
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, rebuild_command)\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \", \")\n")
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, \"generation\")\n")
        strings.write_string(&builder, "    fmt.sbprintf(&payload, \": %d, \", generation)\n")
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, \"message\")\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \": \")\n")
        strings.write_string(&builder, "    reload_json_write_escaped_string(&payload, message)\n")
        strings.write_string(&builder, "    strings.write_string(&payload, \"}\\n\")\n")
        strings.write_string(&builder, "    fmt.print(reload_event_prefix, strings.to_string(payload))\n")
        strings.write_string(&builder, "}\n\n")
    }
    strings.write_string(&builder, "reload_event_name :: proc(kind: olive_reload.Reload_Event_Kind) -> string {\n")
    strings.write_string(&builder, "    switch kind {\n")
    strings.write_string(&builder, "    case .Started:\n        return \"started\"\n")
    strings.write_string(&builder, "    case .Reloaded:\n        return \"reloaded\"\n")
    strings.write_string(&builder, "    case .Restarted:\n        return \"restarted\"\n")
    strings.write_string(&builder, "    case .Resource_Changed:\n        return \"resource_changed\"\n")
    strings.write_string(&builder, "    case .Reload_Failed:\n        return \"reload_failed\"\n")
    strings.write_string(&builder, "    }\n")
    strings.write_string(&builder, "    return \"unknown\"\n")
    strings.write_string(&builder, "}\n\n")
    strings.write_string(&builder, "reload_handle_event :: proc(event: olive_reload.Reload_Event) {\n")
    if json_output {
        strings.write_string(&builder, "    reload_emit_event(reload_event_name(event.kind), ")
        fmt.sbprintf(&builder, "%q, %q, %q, %q", input_path, config.package_name, module_binary_path, fmt.tprintf("kvist dev --reload %q --rebuild", input_path))
        strings.write_string(&builder, ", event.message, event.generation)\n")
    } else {
        strings.write_string(&builder, "    switch event.kind {\n")
        strings.write_string(&builder, "    case .Started:\n        fmt.printf(\"[reload] started generation=%d\\n\", event.generation)\n")
        strings.write_string(&builder, "    case .Reloaded:\n        fmt.printf(\"[reload] reloaded generation=%d\\n\", event.generation)\n")
        strings.write_string(&builder, "    case .Restarted:\n        fmt.printf(\"[reload] restarted generation=%d: %s\\n\", event.generation, event.message)\n")
        strings.write_string(&builder, "    case .Resource_Changed:\n        fmt.printf(\"[reload] resource :changed %s\\n\", event.message)\n")
        strings.write_string(&builder, "    case .Reload_Failed:\n        fmt.eprintf(\"[reload] reload :failed %s\\n\", event.message)\n")
        strings.write_string(&builder, "    }\n")
    }
    strings.write_string(&builder, "}\n\n")
    strings.write_string(&builder, "main :: proc() {\n")
    fmt.sbprintf(&builder, "    module_path := %q\n", module_binary_path)
    strings.write_string(&builder, "    state := app.")
    strings.write_string(&builder, config.state_type)
    strings.write_string(&builder, "{}\n")
    strings.write_string(&builder, "    symbols := App_Symbols{}\n\n")
    if !json_output {
        fmt.sbprintf(&builder, "    fmt.println(\"[reload] running %s\")\n", config.package_name)
        fmt.sbprintf(&builder, "    fmt.println(%q)\n", fmt.tprintf("[reload] rebuild with: kvist dev --reload %q --rebuild", input_path))
    }
    strings.write_string(&builder, "    status := olive_reload.run_host(module_path, &symbols, &state, run, reload_handle_event)\n")
    strings.write_string(&builder, "    os.exit(status)\n")
    strings.write_string(&builder, "}\n")

    return strings.clone(strings.to_string(builder))
}

reload_app_main_source :: proc(config: Reload_App_Config, app_import_path, reload_runtime_import_path: string) -> string {
    builder := strings.builder_make()
    defer strings.builder_destroy(&builder)

    strings.write_string(&builder, "package reload_app_main\n\n")
    fmt.sbprintf(&builder, "import app %q\n", app_import_path)
    fmt.sbprintf(&builder, "import reload_runtime %q\n", reload_runtime_import_path)
    strings.write_string(&builder, "\nmain :: proc() {\n")
    strings.write_string(&builder, "    state := app.")
    strings.write_string(&builder, config.state_type)
    strings.write_string(&builder, "{}\n")
    if config.init_name != "" {
        strings.write_string(&builder, "    app.")
        strings.write_string(&builder, config.init_name)
        strings.write_string(&builder, "(&state)\n")
    }
    if config.on_load_name != "" {
        strings.write_string(&builder, "    app.")
        strings.write_string(&builder, config.on_load_name)
        strings.write_string(&builder, "(&state, false)\n")
    }
    if config.on_unload_name != "" {
        strings.write_string(&builder, "    defer app.")
        strings.write_string(&builder, config.on_unload_name)
        strings.write_string(&builder, "(&state)\n")
    }
    strings.write_string(&builder, "    host := reload_runtime.Run_Host{}\n")
    strings.write_string(&builder, "    app.")
    strings.write_string(&builder, config.run_name)
    strings.write_string(&builder, "(&state, &host)\n")
    strings.write_string(&builder, "}\n")

    return strings.clone(strings.to_string(builder))
}

reload_runtime_path_from_source_root :: proc(anchor_path: string) -> (string, bool) {
    roots := kvist.kvist_source_package_roots(anchor_path)
    defer kvist.delete_string_slice(&roots)

    for root in roots {
        runtime_path, join_err := os.join_path({root, "odin", "olive_reload"}, context.allocator)
        if join_err == nil {
            if os.exists(runtime_path) && os.is_dir(runtime_path) {
                return runtime_path, true
            }
            delete(runtime_path)
        }

        parent, _ := os.split_path(root)
        if parent == "" || parent == root {
            continue
        }
        runtime_path, join_err = os.join_path({parent, "odin", "olive_reload"}, context.allocator)
        if join_err != nil {
            continue
        }
        if os.exists(runtime_path) && os.is_dir(runtime_path) {
            return runtime_path, true
        }
        delete(runtime_path)
    }
    return "", false
}

write_reload_app_generated_sources_or_exit :: proc(input: string, config: Reload_App_Config, paths: Reload_App_Paths, json_output := false) {
    input_abs, abs_err := os.get_absolute_path(input, context.allocator)
    if abs_err != nil {
        fmt.eprintln("failed to resolve input path")
        os.exit(1)
    }
    defer delete(input_abs)

    olive_reload_path, ok_reload_runtime := reload_runtime_path_from_source_root(input_abs)
    if !ok_reload_runtime {
        fmt.eprintln("failed to locate olive_reload runtime source")
        os.exit(1)
    }
    defer delete(olive_reload_path)

    module_app_import := reload_app_relative_path_or_exit(paths.module_dir, paths.app_dir)
    defer delete(module_app_import)
    module_olive_reload_import := reload_app_relative_path_or_exit(paths.module_dir, olive_reload_path)
    defer delete(module_olive_reload_import)
    host_app_import := reload_app_relative_path_or_exit(paths.host_dir, paths.app_dir)
    defer delete(host_app_import)
    host_olive_reload_import := reload_app_relative_path_or_exit(paths.host_dir, olive_reload_path)
    defer delete(host_olive_reload_import)
    module_source := reload_app_module_source(config, module_app_import, module_olive_reload_import)
    defer delete(module_source)
    host_source := reload_app_host_source(config, input_abs, host_app_import, host_olive_reload_import, paths.module_binary, json_output)
    defer delete(host_source)

    write_output_or_exit(paths.module_odin, module_source)
    write_output_or_exit(paths.host_odin, host_source)
}
