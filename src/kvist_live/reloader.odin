package kvist_live

import "core:fmt"
import "core:os"
import "core:strings"

module_definition_delete :: proc(def: ^Module_Definition) {
    if def.name != "" {
        delete(def.name)
    }
    if def.version != "" {
        delete(def.version)
    }
    state_entry_slice_delete(&def.initial_state)
    delete_behavior_definition_slice(&def.functions)
    delete_behavior_definition_slice(&def.commands)
    delete_behavior_definition_slice(&def.hooks)
    def^ = Module_Definition{}
}

module_reloader_delete :: proc(reloader: ^Module_Reloader) {
    if reloader.module_path != "" {
        delete(reloader.module_path)
    }
    if reloader.watch_dir != "" {
        delete(reloader.watch_dir)
    }
    if reloader.last_signature != "" {
        delete(reloader.last_signature)
    }
    reloader^ = Module_Reloader{}
}

apply_module_load_config :: proc(def: ^Module_Definition, config: Module_Load_Config) {
    if config.init != nil {
        def.init = config.init
    }
    if config.shutdown != nil {
        def.shutdown = config.shutdown
    }
    if config.migrate != nil {
        def.migrate = config.migrate
    }
}

sort_strings_in_place :: proc(values: []string) {
    for i in 0 ..< len(values) {
        for j in i + 1 ..< len(values) {
            if values[j] < values[i] {
                values[i], values[j] = values[j], values[i]
            }
        }
    }
}

live_dir_signature :: proc(dir: string) -> (string, Runtime_Error, bool) {
    entries, read_err := os.read_directory_by_path(dir, -1, context.allocator)
    if read_err != nil {
        return "", Runtime_Error{message = strings.clone(fmt.tprintf("could not read live module directory: %s", dir))}, false
    }
    defer os.file_info_slice_delete(entries, context.allocator)

    file_names: [dynamic]string
    defer {
        for name in file_names {
            delete(name)
        }
        delete(file_names)
    }

    for entry in entries {
        if entry.type != .Regular || !strings.has_suffix(entry.name, ".kvist") {
            continue
        }
        append(&file_names, strings.clone(entry.name))
    }
    sort_strings_in_place(file_names[:])

    builder, builder_err := strings.builder_make()
    if builder_err != nil {
        return "", Runtime_Error{message = strings.clone("could not allocate live module signature builder")}, false
    }
    defer strings.builder_destroy(&builder)

    for name in file_names {
        path, join_err := os.join_path({dir, name}, context.allocator)
        if join_err != nil {
            return "", Runtime_Error{message = strings.clone(fmt.tprintf("could not join live module path for: %s", name))}, false
        }
        defer delete(path)

        stamp, stamp_err := os.modification_time_by_path(path)
        if stamp_err != nil {
            return "", Runtime_Error{message = strings.clone(fmt.tprintf("could not stat live module path: %s", path))}, false
        }
        fmt.sbprintf(&builder, "%s|%v\n", name, stamp)
    }

    return strings.clone(strings.to_string(builder)), Runtime_Error{}, true
}

new_module_reloader :: proc(module_path: string, watch_dir := "") -> (Module_Reloader, Runtime_Error, bool) {
    resolved_watch_dir := watch_dir
    if resolved_watch_dir == "" {
        dir, _ := os.split_path(module_path)
        if dir == "" {
            resolved_watch_dir = "."
        } else {
            resolved_watch_dir = dir
        }
    }

    signature, err, ok := live_dir_signature(resolved_watch_dir)
    if !ok {
        return Module_Reloader{}, err, false
    }
    defer delete(signature)

    return Module_Reloader{
        module_path = strings.clone(module_path),
        watch_dir = strings.clone(resolved_watch_dir),
        last_signature = strings.clone(signature),
        has_loaded = false,
    }, Runtime_Error{}, true
}

load_initial_definition :: proc(reloader: ^Module_Reloader) -> (Module_Definition, Runtime_Error, bool) {
    def, err, ok := module_definition_from_kvist_path(reloader.module_path)
    if !ok {
        return Module_Definition{}, err, false
    }
    reloader.has_loaded = true
    return def, Runtime_Error{}, true
}

load_initial_module :: proc(runtime: ^Runtime,
                            reloader: ^Module_Reloader,
                            config := Module_Load_Config{}) -> (Runtime_Error, bool) {
    def, err, ok := load_initial_definition(reloader)
    if !ok {
        return err, false
    }
    defer module_definition_delete(&def)

    apply_module_load_config(&def, config)
    return load_module(runtime, def)
}

reload_if_source_changed :: proc(reloader: ^Module_Reloader) -> (bool, Module_Definition, Runtime_Error, bool) {
    current_signature, current_err, current_ok := live_dir_signature(reloader.watch_dir)
    if !current_ok {
        return false, Module_Definition{}, current_err, false
    }

    if !reloader.has_loaded {
        delete(current_signature)
        def, err, ok := load_initial_definition(reloader)
        return true, def, err, ok
    }

    if current_signature == reloader.last_signature {
        delete(current_signature)
        return false, Module_Definition{}, Runtime_Error{}, true
    }

    def, err, ok := module_definition_from_kvist_path(reloader.module_path)
    if !ok {
        delete(current_signature)
        return true, Module_Definition{}, err, false
    }

    if reloader.last_signature != "" {
        delete(reloader.last_signature)
    }
    reloader.last_signature = current_signature
    return true, def, Runtime_Error{}, true
}

reload_module_if_source_changed :: proc(runtime: ^Runtime,
                                        reloader: ^Module_Reloader,
                                        config := Module_Load_Config{}) -> (bool, Runtime_Error, bool) {
    changed, def, err, ok := reload_if_source_changed(reloader)
    if !ok || !changed {
        return changed, err, ok
    }
    defer module_definition_delete(&def)

    apply_module_load_config(&def, config)
    reload_err, reload_ok := reload_module(runtime, def)
    return true, reload_err, reload_ok
}
